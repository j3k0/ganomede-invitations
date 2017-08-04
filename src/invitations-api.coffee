log = require "./log"
authdb = require "authdb"
redis = require "redis"
restify = require "restify"
vasync = require 'vasync'
crypto = require 'crypto'
SendNotification = require './send-notification'
pkg = require '../package.json'
ServiceEnv = require './service-env'
helpers = require 'ganomede-helpers'

redisClient = null
authdbClient = null
sendNotification = null

REDIS_TTL_SECONDS = 15 * 24 * 3600 # 15 days

sendError = (err, next) ->
  log.error err
  next err

# Sets EXPIRE of Redis-stored invitations to REDIS_TTL_SECONDS
expire = (key) ->
  redisClient.expire key, REDIS_TTL_SECONDS, (err, retval) ->
    if err
      log.error("failed to EXPIRE redis key `#{key}`", err)

    # if user has received or sent no invitations,
    # this isn't an error (no need to log... that's pretty heavy)
    #if retval == 0
    #  log.warn("failed to EXPIRE redis key: `#{key}` does not exist or
    #            the timeout could not be set")

updateExpireMiddleware = (req, res, next) ->
  if req.params.user?.username
    expire(req.params.user.username)

  if req.params.invitation instanceof Invitation
    expire(req.params.invitation.id)

  next()

# Populates req.params.invitation with redisClient.get(req.params.invitationId)
findInvitationMiddleware = (req, res, next) ->
  id = req.params.invitationId
  if !id
    return sendError(new restify.InvalidContentError('invalid content'), next)

  Invitation.loadFromRedis id, (err, invitation) ->
    if err
      log.error err
      return sendError(new restify.InternalError('failed to query db'), next)

    if !invitation
      return sendError(new restify.NotFoundError('not found'), next)

    req.params.invitation = invitation
    next()

#
# Helpers
#

class Invitation
  constructor: (from, data) ->
    @id = Invitation.getId(data.type, from, data.to)
    @from = from
    @to = data.to
    @gameId = data.gameId
    @type = data.type

  valid: ->
    @id && @from && @to && @gameId && @type

  saveToRedis: (callback) ->
    json = JSON.stringify(this)
    #multi = redisClient.multi()
    vasync.parallel funcs: [
      redisClient.sadd.bind(redisClient, @from, @id)
      redisClient.sadd.bind(redisClient, @to, @id)
      redisClient.set.bind(redisClient, @id, json)
    ], callback
    #multi.exec(callback)

  deleteFromRedis: (callback) ->
    #multi = redisClient.multi()
    vasync.parallel funcs: [
      redisClient.srem.bind(redisClient, @from, @id)
      redisClient.srem.bind(redisClient, @to, @id)
      redisClient.del.bind(redisClient, @id)
    ], callback
    #multi.exec(callback)

  @loadFromRedis: (id, callback) ->
    redisClient.get id, (err, json) ->
      if err
        return callback(err)

      if !json
        return callback(null, null)

      callback(null, Invitation.fromJSON(json))

  @fromJSON: (json) ->
    obj = JSON.parse(json)
    invitation = new Invitation(obj.from, obj)
    invitation.id = obj.id
    return invitation

  @forUsername: (username, callback) ->
    ids = null
    expiredIds = []

    vasync.waterfall [
      redisClient.smembers.bind(redisClient, username)
      (ids_, cb) ->
        ids = ids_
        if ids.length
          redisClient.mget(ids, cb)
        else
          process.nextTick(cb.bind(null, null, []))
    ]
    ,
    (err, jsons) ->
      if err
        return callback(err)

      if !ids || ids.length == 0
        return callback(null, [])

      result = jsons.filter (json, idx) ->
        if json == null
          expiredIds.push(ids[idx])
        return !!json

      if expiredIds.length
        redisClient.srem(username, expiredIds)

      try
        list = result.map(Invitation.fromJSON)
      catch error
        return callback(error, null)

      callback(null, list)

  @getId: (type, from, to) ->
    str = JSON.stringify({
      type: type
      users: [from, to].sort()
    })

    crypto.createHash('md5').update(str, 'utf8').digest('hex')

#
# Methods
#

createInvitation = (req, res, next) ->
  invitation = new Invitation(req.params.user.username, req.body)
  req.params.invitation = invitation

  if !invitation.valid()
    err = new restify.InvalidContentError "invalid content"
    return sendError err, next

  invitation.saveToRedis (err, replies) ->
    if err
      log.error err
      err = new restify.InternalError "failed add to database"
      return sendError err, next

    # send notification
    sendNotification
      from: pkg.api
      to: invitation.to
      type: 'invitation-created'
      data:
        invitation: invitation
      push:
        app: invitation.type
        title: [ "invitation_received_title" ]
        message: [ "invitation_received_message", invitation.from ]
        # Tell notifier to fetch "name" from "userId"
        messageArgsTypes: [ 'username' ]

    # reply to request
    res.send invitation
    next()

listInvitations = (req, res, next) ->
  Invitation.forUsername req.params.user.username, (err, list) ->
    if err
      log.error err
      return sendError(new restify.InternalError('failed to query db'), next)

    res.send(list)
    next()

deleteInvitation = (req, res, next) ->
  username = req.params.user.username
  invitation = req.params.invitation
  reason = req.body.reason

  badReason = (allowed) ->
    sendError(new restify.InvalidContentError('invalid reason'), next)

  del = () ->
    invitation.deleteFromRedis (err, replies) ->
      if err
        log.error(err)
        return sendError(new restify.InternalError('failed to query db'), next)

      # send notification
      sendNotification
        from: pkg.api
        to: if (reason == 'cancel') then invitation.to else invitation.from
        type: 'invitation-deleted'
        data:
          reason: reason
          invitation: invitation

      # Reply to request
      delete req.params.invitation # don't refresh expire
      res.send(204)
      next()

  # TODO:
  # this looks like a mess...

  if !reason
    return sendError(new restify.InvalidContentError('reason required'), next)

  if username == invitation.from
    if reason != 'cancel'
      return badReason()

    return del()

  if username == invitation.to
    if (reason != 'accept') && (reason != 'refuse')
      return badReason()

    return del()

  # Request is only deletable by sender or receiver.
  return sendError(new restify.ForbiddenError('forbidden'), next)

#
# Init
#

initialize = (options={}) ->
  if options.authdbClient
    authdbClient = options.authdbClient
  else
    authdbClient = authdb.createClient
      host: ServiceEnv.host('REDIS_AUTH', 6379)
      port: ServiceEnv.port('REDIS_AUTH', 6379)

  if options.redisClient
    redisClient = options.redisClient
  else
    redisClient = redis.createClient(
      ServiceEnv.port('REDIS_INVITATIONS', 6379),
      ServiceEnv.host('REDIS_INVITATIONS', 6379),
        no_ready_check: true
    )

  # If we have sendNotification option, then use that.
  # Otherwise if ENV variables are set, use those.
  # Otherwise don't send notifications.
  if options.sendNotification instanceof Function
    sendNotification = options.sendNotification
  else if ServiceEnv.exists 'NOTIFICATIONS', 8080
    url = ServiceEnv.url('NOTIFICATIONS', 8080)
    sendNotification = SendNotification.create url
  else
    sendNotification = () -> # no-op

addRoutesAs = (server, routes, middlewares...) ->
  for own method, endpoint of routes
    server[method].apply server, [ endpoint ].concat middlewares

addDel = (server, endpoint, middlewares...) ->
  addRoutesAs.apply @, [server, {
    del:  "#{endpoint}"
    post: "#{endpoint}/delete"
  }].concat middlewares

addRoutes = (prefix, server) ->
  endpoint = "/#{prefix}/auth/:authToken/invitations"

  # All requests must be authorized.
  authMiddleware = helpers.restify.middlewares.authdb.create({
    authdbClient,
    secret: process.env.API_SECRET
  })
  server.use (req, res, next) ->
    authorize = req.route.path.startsWith(endpoint)
    if (authorize)
      authMiddleware req, res, next
    else
      next()

  server.get endpoint, listInvitations, updateExpireMiddleware
  server.post endpoint, createInvitation, updateExpireMiddleware
  addDel server, "#{endpoint}/:invitationId",
    findInvitationMiddleware, deleteInvitation, updateExpireMiddleware
  #server.del "#{endpoint}/:invitationId", authMiddleware,
  #  findInvitationMiddleware, deleteInvitation, updateExpireMiddleware

# Export the module
module.exports =
  initialize: initialize
  addRoutes: addRoutes
  Invitation: Invitation

# vim: ts=2:sw=2:et:

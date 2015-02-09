log = require "./log"
authdb = require "authdb"
redis = require "redis"
restify = require "restify"
vasync = require 'vasync'

redisClient = null
authdbClient = null

REDIS_TTL_SECONDS = 15 * 24 * 3600 # 15 days

sendError = (err, next) ->
  log.error err
  next err

# Populates req.params.user with value returned from authDb.getAccount()
authMiddleware = (req, res, next) ->
  authToken = req.params.authToken
  if !authToken
    return sendError(new restify.InvalidContentError('invalid content'), next)

  authdbClient.getAccount authToken, (err, account) ->
    if err || !account
      return sendError(new restify.UnauthorizedError('not authorized'), next)

    req.params.user = account
    next()

# Sets EXPIRE of Redis-stored invitations to REDIS_TTL_SECONDS
expire = (key) ->
  redisClient.expire key, REDIS_TTL_SECONDS, (err, retval) ->
    if err
      log.error("failed to EXPIRE redis key `#{key}`", err)

    if retval == 0
      log.warn("failed to EXPIRE redis key: `#{key}` does not exist or
                the timeout could not be set")

updateExpireMiddleware = (req, res, next) ->
  if req.params.user?.username
    expire(req.params.user.username)

  if req.params.invitation instanceof Invitation
    expire(req.params.invitation.id)

  next()

#
# Helpers
#

class Invitation
  constructor: (from, data) ->
    @id = Invitation._rand() + Invitation._rand()
    @from = from
    @to = data.to
    @gameId = data.gameId
    @type = data.type

  valid: ->
    @id && @from && @to && @gameId && @type

  saveToRedis: (callback) ->
    json = JSON.stringify(this)
    multi = redisClient.multi()

    multi.sadd(@from, @id)
    multi.sadd(@to, @id)
    multi.set(@id, json)
    multi.exec(callback)

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

  @_rand: () ->
    Math.random().toString(36).substr(2)

#
# Create a new invitation
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

    res.send invitation
    next()

listInvitations = (req, res, next) ->
  Invitation.forUsername req.params.user.username, (err, list) ->
    if err
      log.error err
      return sendError(new restify.InternalError('failed to query db'))

    res.send(list)
    next()

initialize = (options={}) ->
  if options.authdbClient
    authdbClient = options.authdbClient
  else
    authdbClient = authdb.createClient
      host: process.env.REDIS_AUTH_PORT_6379_TCP_ADDR || 6379
      port: process.env.REDIS_AUTH_PORT_6379_TCP_PORT || 'localhost'

  if options.redisClient
    redisClient = options.redisClient
  else
    redisClient = redis.createClient(
      process.env.REDIS_INVITATIONS_PORT_6379_TCP_PORT || 6379,
      process.env.REDIS_INVITATIONS_PORT_6379_TCP_ADDR || "localhost")

addRoutes = (prefix, server) ->
  endpoint = "/#{prefix}/auth/:authToken/invitations"
  server.get endpoint, authMiddleware, listInvitations, updateExpireMiddleware
  server.post endpoint, authMiddleware, createInvitation, updateExpireMiddleware

# Export the module
module.exports =
  initialize: initialize
  addRoutes: addRoutes

# vim: ts=2:sw=2:et:

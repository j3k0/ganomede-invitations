log = require "./log"
authdb = require "authdb"
redis = require "redis"
restify = require "restify"

redisClient = null
authdbClient = null

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

# TODO:
# temp stuff, will figure it out later
#
# Invitations that @username have sent or received
# /invitations/v1/auth/:authToken/invitations
# class Invitations
#   constructor: (username) ->
#     @username = username
#     @invitations = []

#   query: () ->
#     redi

#   sent: () ->
#     username = @username
#     return @invitations.filter (i) ->
#       return i.from == username

#   received: () ->
#     username = @username
#     return @invitations.filter (i) ->
#       return i.to == username

#
# Helpers
#


#
# Create a new invitation
#

# Generate a random token
rand = ->
  Math.random().toString(36).substr(2)
genToken = -> rand() + rand()

createInvitation = (req, res, next) ->
  obj =
    id: genToken()
    from: req.params.user.username
    to: req.body.to
    gameId: req.body.gameId
    type: req.body.type

  if !obj.from or !obj.to or !obj.gameId or !obj.type
    err = new restify.InvalidContentError "invalid content"
    return sendError err, next

  val = JSON.stringify(obj)
  multi = redisClient.multi()
  multi.lpush obj.from, val
  multi.lpush obj.to, val
  multi.set obj.id, val
  multi.exec (err, replies) ->
    if err
      log.error err
      err = new restify.InternalError "failed add to database"
      return sendError err, next
    res.send obj
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

listInvitations = (req, res, next) ->
  next(new restify.InternalError('not implemented'))

addRoutes = (prefix, server) ->
  endpoint = "/#{prefix}/auth/:authToken/invitations"
  server.get endpoint, authMiddleware, listInvitations
  server.post endpoint, authMiddleware, createInvitation

# Export the module
module.exports =
  initialize: initialize
  addRoutes: addRoutes

# vim: ts=2:sw=2:et:

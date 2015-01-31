log = require "./log"
authdb = require "authdb"
redis = require "redis"
restify = require "restify"

redisClient = null
authdbClient = null

initialize = (options) ->

  options = options || {}

  if options.authdbClient
    authdbClient = options.authdbClient
  else
    authdbClient = authdb.createClient
      host: process.env.REDIS_AUTH_PORT_6379_TCP_ADDR
      port: process.env.REDIS_AUTH_PORT_6379_TCP_PORT

  if options.redisClient
    redisClient = options.redisClient
  else
    redisClient = redis.createClient(
      process.env.REDIS_INVITATIONS_PORT_6379_TCP_PORT || 6379,
      process.env.REDIS_INVITATIONS_PORT_6379_TCP_ADDR || "localhost")

addRoutes = (prefix, server) ->
  server.post "/#{prefix}/auth/:authToken/invitations", createInvitation

#
# Helpers
#
sendError = (err, next) ->
  log.error err
  next err

# Wrap HTTP errors with authentication token validation code
needAuth = (method) ->
  (req, res, next) ->
    authToken = req.params.authToken
    if !authToken
      err = new restify.InvalidContentError "invalid content"
      return sendError err, next
    authdbClient.getAccount authToken, (err, account) ->
      if err
        log.error err
        err = new restify.UnauthorizedError "not authorized"
        return sendError err, next
      if !account
        err = new restify.UnauthorizedError "not authorized"
        return sendError err, next
      req.params.user = account
      method req, res, next

#
# Create a new invitation
#

# Generate a random token
rand = ->
  Math.random().toString(36).substr(2)
genToken = -> rand() + rand()

createInvitation = needAuth (req, res, next) ->
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

# Export the module
module.exports =
  initialize: initialize
  addRoutes: addRoutes

# vim: ts=2:sw=2:et:

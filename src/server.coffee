restify = require 'restify'
log = require('./log')
pkg = require('../package.json')

createServer = (options={}) ->
  server = restify.createServer
    handleUncaughtExceptions: true
    log: log

  server.use restify.queryParser()
  server.use restify.bodyParser()
  server.use restify.gzipResponse()

  shouldLogRequest = (req) ->
    req.url.indexOf("/#{pkg.api}/ping/_health_check") < 0

  shouldLogResponse = (res) ->
    (res && res.statusCode >= 500)

  filteredLogger = (errorsOnly, logger) ->
    logger_mw = (req, res, next) ->
      logError = errorsOnly && shouldLogResponse(res)
      logInfo = !errorsOnly && (
        shouldLogRequest(req) || shouldLogResponse(res))
      if logError || logInfo
        logger(req, res)
      if next && typeof next == 'function'
        next()

  # Log incoming requests
  requestLogger = filteredLogger(false, (req) ->
    req.log.info({req_id: req.id()}, "#{req.method} #{req.url}"))
  server.use(requestLogger)

  # Audit requests at completion
  server.on('after', filteredLogger(process.env.NODE_ENV == 'production',
    restify.auditLogger({log: log, body: true})))

  # Automatically add a request-id to the response
  setRequestId = (req, res, next) ->
    res.setHeader('x-request-id', req.id())
    req.log = req.log.child({req_id: req.id()})
    next()
  server.use(setRequestId)

  # Send audit statistics
  sendAuditStats = require './send-audit-stats'
  server.on 'after', sendAuditStats

  return server

module.exports = { createServer }

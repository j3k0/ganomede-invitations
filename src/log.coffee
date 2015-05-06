bunyan = require "bunyan"
log = bunyan.createLogger name: "invitations"

# class used by elasticsearch for logging
log.ElasticLogger = class
  constructor: (config) ->
    log = log
    @error = log.error.bind log
    @warning = log.warn.bind log
    @info = log.info.bind log
    @debug = log.debug.bind log
    @trace = (method, requestUrl, body, responseBody, responseStatus) ->
      log.trace
        method: method
        requestUrl: requestUrl
        body: body
        responseBody: responseBody
        responseStatus: responseStatus
    # bunyan's loggers do not need to be closed
    @close = ->
      undefined

module.exports = log
# vim: ts=2:sw=2:et:

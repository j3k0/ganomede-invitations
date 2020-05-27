/*
 * decaffeinate suggestions:
 * DS102: Remove unnecessary code created because of implicit returns
 * DS207: Consider shorter variations of null checks
 * Full docs: https://github.com/decaffeinate/decaffeinate/blob/master/docs/suggestions.md
 */
import * as restify from 'restify';
import log from './log';
import pkg = require('../package.json');
import sendAuditStats from './send-audit-stats';

const createServer = function(options?): restify.Server {
  if (!options) { options = {}; }
  const server = restify.createServer({
    handleUncaughtExceptions: true,
    log
  });

  server.use(restify.plugins.queryParser());
  server.use(restify.plugins.bodyParser());
  server.use(restify.plugins.gzipResponse());

  const shouldLogRequest = req => req.url.indexOf(`/${pkg.api}/ping/_health_check`) < 0;

  const shouldLogResponse = res => res && (res.statusCode >= 500);

  const filteredLogger = function(errorsOnly, logger) {
    return function logger_mw(req, res, next) {
      const logError = errorsOnly && shouldLogResponse(res);
      const logInfo = !errorsOnly && (
        shouldLogRequest(req) || shouldLogResponse(res));
      if (logError || logInfo) {
        logger(req, res);
      }
      if (next && (typeof next === 'function')) {
        return next();
      }
    };
  };

  // Log incoming requests
  const requestLogger = filteredLogger(false, req => req.log.info({req_id: req.id()}, `${req.method} ${req.url}`));
  server.use(requestLogger);

  // Audit requests at completion
  server.on('after', filteredLogger(process.env.NODE_ENV === 'production',
    restify.plugins.auditLogger({
      log,
      body: true,
      event: 'after'
    })));

  // Automatically add a request-id to the response
  const setRequestId = function(req, res, next) {
    res.setHeader('x-request-id', req.id());
    req.log = req.log.child({req_id: req.id()});
    return next();
  };
  server.use(setRequestId);

  // Send audit statistics
  server.on('after', sendAuditStats);

  return server;
};

export default { createServer };
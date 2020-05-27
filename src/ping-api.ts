/*
 * decaffeinate suggestions:
 * DS102: Remove unnecessary code created because of implicit returns
 * Full docs: https://github.com/decaffeinate/decaffeinate/blob/master/docs/suggestions.md
 */
const ping = function(req, res, next) {
  res.send("pong/" + req.params.token);
  return next();
};

const addRoutes = function(prefix, server) {
  server.get(`/${prefix}/ping/:token`, ping);
  return server.head(`/${prefix}/ping/:token`, ping);
};

export default {addRoutes};

// vim: ts=2:sw=2:et:

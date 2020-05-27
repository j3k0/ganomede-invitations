/*
 * decaffeinate suggestions:
 * DS102: Remove unnecessary code created because of implicit returns
 * Full docs: https://github.com/decaffeinate/decaffeinate/blob/master/docs/suggestions.md
 */
// About

import * as os from "os";
import pk = require("../package.json");

const about = {
  hostname: os.hostname(),
  type: pk.name,
  version: pk.version,
  description: pk.description,
  startDate: (new Date).toISOString()
};

const sendAbout = function(req, res, next) {
  res.send(about);
  return next();
};

const addRoutes = function(prefix, server) {
  server.get("/about", sendAbout);
  return server.get(`/${prefix}/about`, sendAbout);
};

export default {addRoutes};

// vim: ts=2:sw=2:et:


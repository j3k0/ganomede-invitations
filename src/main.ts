/*
 * decaffeinate suggestions:
 * DS102: Remove unnecessary code created because of implicit returns
 * Full docs: https://github.com/decaffeinate/decaffeinate/blob/master/docs/suggestions.md
 */
import log from "./log";
import aboutApi from "./about-api";
import pingApi from "./ping-api";
import invitationsApi from "./invitations-api";
import * as restify from "restify";

const addRoutes = function(prefix, server: restify.Server) {
  log.info("adding routes");

  // Platform Availability
  pingApi.addRoutes(prefix, server);

  // About
  aboutApi.addRoutes(prefix, server);

  // Invitations
  invitationsApi.initialize();
  return invitationsApi.addRoutes(prefix, server);
};

const initialize = function(callback?: () => void) {
  log.info("initializing backend");
  if (typeof callback === 'function')
    callback();
};

const destroy = () => log.info("destroying backend");

export default {
  initialize,
  destroy,
  addRoutes,
  log
};

// vim: ts=2:sw=2:et:

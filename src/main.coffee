log = require "./log"
aboutApi = require "./about-api"
pingApi = require "./ping-api"
invitationsApi = require "./invitations-api"

addRoutes = (prefix, server) ->
  log.info "adding routes"

  # Platform Availability
  pingApi.addRoutes prefix, server

  # About
  aboutApi.addRoutes prefix, server

  # Invitations
  invitationsApi.initialize()
  invitationsApi.addRoutes prefix, server

initialize = (callback) ->
  log.info "initializing backend"
  callback?()

destroy = ->
  log.info "destroying backend"

module.exports =
  initialize: initialize
  destroy: destroy
  addRoutes: addRoutes
  log: log

# vim: ts=2:sw=2:et:

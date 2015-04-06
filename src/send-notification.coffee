superagent = require 'superagent'
log = require './log'

sendNotification = (uri, notification, callback) ->
  if !notification.hasOwnProperty('secret')
    notification.secret = process.env.API_SECRET

  log.info "sending notification",
    uri: uri
    notification: notification

  superagent
    .post(uri)
    .send(notification)
    .end (err, res) ->
      if (err)
        log.error 'sendNotification() failed',
          err: err
          uri: uri
          notification: notification

      callback?(err, res.body)

module.exports =
    create: (uri) ->
      (notification, callback) -> sendNotification(uri, notification, callback)

# vim: ts=2:sw=2:et:

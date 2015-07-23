superagent = require 'superagent'
log = require './log'

sendNotification = (url, notification, callback) ->
  if !notification.hasOwnProperty('secret')
    notification.secret = process.env.API_SECRET

  url = "#{url}/notifications/v1/messages"
  log.info "sending notification",
    url: url
    notification: notification

  superagent
    .post(url)
    .send(notification)
    .end (err, res) ->
      if (err)
        log.error 'sendNotification() failed',
          err: err
          url: url
          notification: notification

      callback?(err, res.body)

module.exports =
    create: (url) ->
      (notification, callback) -> sendNotification(url, notification, callback)

# vim: ts=2:sw=2:et:

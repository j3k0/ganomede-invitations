superagent = require 'superagent'
log = require './log'

sendNotification = (uri, notification, callback) ->
  if !notification.hasOwnProperty('secret')
    notification.secret = process.env.API_SECRET

  superagent
    .post(uri)
    .send(notification)
    .end (err, res) ->
      if (err)
        logger.error 'sendNotification() failed',
          err: err
          uri: uri
          notification: notification

      callback?(err, res.body)

module.exports = sendNotification

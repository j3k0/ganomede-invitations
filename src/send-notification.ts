import * as superagent from 'superagent';
import log from './log';

export interface Notification {
  secret?: string;
  from?: string;
  to: string;
  type: 'invitation-created'|'invitation-deleted';
  data: any,
  push?: {
    app: string;
    title: string[];
    message: string[];
    messageArgsTypes: string[];
  }
}

export type SendNotificationCallback = (err?: Error, body?: any) => void;

const sendNotification = function(url: string, notification: Notification, callback?: SendNotificationCallback) {
  if (!notification.hasOwnProperty('secret')) {
    notification.secret = process.env.API_SECRET;
  }

  url = `${url}/notifications/v1/messages`;
  log.info("sending notification", {
    url,
    notification
  }
  );

  return superagent
    .post(url)
    .send(notification)
    .end(function(err, res) {
      if (err) {
        log.error('sendNotification() failed', {
          err,
          url,
          notification
        }
        );
      }

      if (typeof callback === 'function')
        callback(err, res.body);
  });
};

export type SendNotificationFunction = (notification: Notification, callback?: SendNotificationCallback) => void;

export default {
  create (url): SendNotificationFunction {
    return (notification, callback) => sendNotification(url, notification, callback);
  }
};

// vim: ts=2:sw=2:et:

import log from "./log";
import * as authdb from "authdb";
import * as redis from "redis";
import * as restifyErrors from "restify-errors";
import * as restify from "restify";
import * as vasync from 'vasync';
import * as crypto from 'crypto';
import authdbHelper from './authdb-helper';
import SendNotification from './send-notification';
import {SendNotificationFunction} from './send-notification';
import ServiceEnv from './service-env';
import pkg = require('../package.json');

let redisClient:redis.RedisClient|null = null;
let usermetadbClient:redis.RedisClient|null = null;
let authdbClient:any = null;
let sendNotification:SendNotificationFunction|null = null;

const REDIS_TTL_SECONDS = 15 * 24 * 3600; // 15 days

const sendError = function(err, next) {
  log.warn({err}, 'request failed');
  if (['NotFound', 'Unauthorized', 'Forbidden'].indexOf(err?.body?.code) >= 0)
    err.body.code += 'Error';
  log.warn({err}, 'request failed');
  return next(err) ;
};

// Sets EXPIRE of Redis-stored invitations to REDIS_TTL_SECONDS
const expire = key => redisClient!.expire(key, REDIS_TTL_SECONDS, function(err, retval) {
  if (err) {
    return log.error(`failed to EXPIRE redis key \`${key}\``, err);
  }
});

// if user has received or sent no invitations,
// this isn't an error (no need to log... that's pretty heavy)
//if retval == 0
//  log.warn("failed to EXPIRE redis key: `#{key}` does not exist or
//            the timeout could not be set")

const updateExpireMiddleware = function(req, res, next) {
  if (req.params.user != null ? req.params.user.username : undefined) {
    expire(req.params.user.username);
  }

  if (req.params.invitation instanceof Invitation) {
    expire(req.params.invitation.id);
  }

  return next();
};

// Populates req.params.invitation with redisClient.get(req.params.invitationId)
const findInvitationMiddleware = function(req, res, next) {
  const id = req.params.invitationId;
  if (!id) {
    return sendError(new restifyErrors.InvalidContentError('invalid content'), next);
  }

  return Invitation.loadFromRedis(id, function(err, invitation) {
    if (err) {
      log.error(err);
      return sendError(new restifyErrors.InternalError('failed to query db'), next);
    }

    if (!invitation) {
      return sendError(new restifyErrors.NotFoundError('not found'), next);
    }

    req.params.invitation = invitation;
    return next();
  });
};

//
// Helpers
//

class Invitation {
  id: string;
  from: string;
  to: string;
  gameId: string;
  type: string;

  constructor(from, data) {
    this.id = Invitation.getId(data.type, from, data.to);
    this.from = from;
    this.to = data.to;
    this.gameId = data.gameId;
    this.type = data.type;
  }

  valid() {
    return this.id && this.from && this.to && this.gameId && this.type;
  }

  saveToRedis(callback) {
    const json = JSON.stringify(this);
    //multi = redisClient.multi()
    return vasync.parallel({funcs: [
      redisClient!.sadd.bind(redisClient, this.from, this.id),
      redisClient!.sadd.bind(redisClient, this.to, this.id),
      redisClient!.set.bind(redisClient, this.id, json)
    ]
  }, callback);
  }

  deleteFromRedis(callback: (err?: Error) => void) {
    //multi = redisClient.multi()
    return vasync.parallel({funcs: [
      redisClient!.srem.bind(redisClient, this.from, this.id),
      redisClient!.srem.bind(redisClient, this.to, this.id),
      redisClient!.del.bind(redisClient, this.id)
    ]
  }, callback);
  }

  saveTemporaryBan(_req: restify.Request, _seconds: number) {
    // const temporaryBanKey = `${this.id}:ban`;
    // redisClient!.set(temporaryBanKey, '1');
    // redisClient!.expire(temporaryBanKey, seconds);
  }

  hasBan(callback: (hasBan: boolean) => void) {
    callback(false);
    // const temporaryBanKey = `${this.id}:ban`;
    // redisClient!.get(temporaryBanKey, (err: Error|null, data: string|false|null) => {
    //   callback(!err && !!data);
    // });
  }

  static loadFromRedis(id: string, callback: (err?: Error, invitation?:Invitation) => void) {
    return redisClient!.get(id, function(err, json) {
      if (err)
        return callback(err);
      if (!json)
        return callback(undefined, undefined);
      return callback(undefined, Invitation.fromJSON(json));
    });
  }

  static fromJSON(json) {
    const obj = JSON.parse(json);
    const invitation = new Invitation(obj.from, obj);
    invitation.id = obj.id;
    return invitation;
  }

  static forUsername(username: string, callback) {
    let ids: string[]|undefined;
    const expiredIds: string[] = [];

    return vasync.waterfall([
      redisClient!.smembers.bind(redisClient, username),
      function(ids_: string[], cb: redis.Callback<string[]>) {
        ids = ids_;
        if (ids?.length) {
          return redisClient!.mget(ids, cb);
        } else {
          return process.nextTick(cb.bind(null, null, []));
        }
      }
    ],
    function(err?: Error, jsons?: any[]) {
      let list;
      if (err) {
        return callback(err);
      }

      if (!jsons || !ids || (ids.length === 0)) {
        return callback(null, []);
      }

      const result = jsons.filter(function(json, idx) {
        if (json === null) {
          expiredIds.push(ids![idx]);
        }
        return !!json;
      });

      if (expiredIds.length) {
        redisClient!.srem(username, expiredIds);
      }

      try {
        list = result.map(Invitation.fromJSON);
      } catch (error) {
        return callback(error, null);
      }

      return callback(null, list);
    });
  }

  static getId(type, from, to) {
    const str = JSON.stringify({
      type,
      users: [from, to].sort()
    });

    return crypto.createHash('md5').update(str, 'utf8').digest('hex');
  }
}

//
// Methods
//

const checkBlocked = function (usermetadbClient: redis.RedisClient | null) {
  return function (req: restify.Request, res: restify.Response, next: restify.Next) {
    const from: string | undefined = req.params.user.username;
    const to: string | undefined = req.body?.to;
    if (!from || !to || !usermetadbClient) // cannot check for blocked users
      return next();
    usermetadbClient?.GET(`${to}:$blocked`, function (err: Error | null, value?: string | null) {
      // Is the sending user is blocked by the receiver.
      if (value && value.split(',').indexOf(from) >= 0) {
        // Yes, return an error.
        next(new restifyErrors.ForbiddenError({
          statusCode: 423,
          message: 'You are not allowed to invite this player.',
          code: 'InvitationBlocked'
        }));
      }
      else {
        next();
      }
    })
  };
}

const createInvitation = function(req, res, next) {
  const invitation = new Invitation(req.params.user.username, req.body);
  req.params.invitation = invitation;

  if (!invitation.valid()) {
    const err = new restifyErrors.InvalidContentError("invalid content");
    return sendError(err, next);
  }

  invitation.hasBan(hasBan => {
    if (hasBan) {
      res.send(Object.assign({
        code: 'TooManyInvitations'
      }, invitation));
      delete req.params.invitation;
      return next();
      // const err = new restifyErrors.TooManyRequestsError("too many invitations");
      // return sendError(err, next);
    }
    invitation.saveToRedis(function(err, replies) {
      if (err) {
        log.error(err);
        err = new restifyErrors.InternalError("failed add to database");
        return sendError(err, next);
      }

      // send notification
      if (sendNotification) sendNotification({
        from: pkg.api,
        to: invitation.to,
        type: 'invitation-created',
        data: {
          invitation
        },
        push: {
          app: invitation.type,
          title: [ "invitation_received_title" ],
          message: [ "invitation_received_message", invitation.from ],
          messageArgsTypes: [ 'directory:name' ]
        }});

      // reply to request
      res.send(invitation);
      next();
    });
  });
};

const listInvitations = (req, res, next) => Invitation.forUsername(req.params.user.username, function(err, list) {
  if (err) {
    log.error(err);
    return sendError(new restifyErrors.InternalError('failed to query db'), next);
  }

  res.send(list);
  return next();
});

const deleteInvitation = function(req: restify.Request, res: restify.Response, next: restify.Next) {
  const username:string = req.params.user.username;
  const invitation:Invitation = req.params.invitation;
  const reason:string = req.body.reason;

  const badReason = () => sendError(new restifyErrors.InvalidContentError('invalid reason'), next);

  const del = () => invitation.deleteFromRedis(function(err) {
    if (err) {
      log.error(err);
      return sendError(new restifyErrors.InternalError('failed to query db'), next);
    }
    if (reason === 'cancel' || reason === 'refuse') {
      req.log.info({
        from: invitation.from,
        to: invitation.to
      }, 'invitation canceled');
      invitation.saveTemporaryBan(req, 6 * 3600);
    }

    // send notification
    sendNotification!({
      from: pkg.api,
      to: (reason === 'cancel') ? invitation.to : invitation.from,
      type: 'invitation-deleted',
      data: {
        reason,
        invitation
      }
    });

    // Reply to request
    delete req.params.invitation; // don't refresh expire
    res.send(204);
    return next();
  });

  // TODO:
  // this looks like a mess...

  if (!reason) {
    return sendError(new restifyErrors.InvalidContentError('reason required'), next);
  }

  if (username === invitation.from) {
    if (reason !== 'cancel') {
      return badReason();
    }

    return del();
  }

  if (username === invitation.to) {
    if ((reason !== 'accept') && (reason !== 'refuse')) {
      return badReason();
    }

    return del();
  }

  // Request is only deletable by sender or receiver.
  return sendError(new restifyErrors.ForbiddenError('forbidden'), next);
};

//
// Init
//

export interface InvitationsApiOptions {
  authdbClient?: any;
  redisClient?: redis.RedisClient;
  usermetadbClient?: redis.RedisClient;
  sendNotification?: SendNotificationFunction;
}

const initialize = function(options?: InvitationsApiOptions) {
  if (options == null) { options = {}; }
  if (options.authdbClient) {
    authdbClient = options.authdbClient;
  } else {
    authdbClient = authdb.createClient({
      host: ServiceEnv.host('REDIS_AUTH', 6379),
      port: ServiceEnv.port('REDIS_AUTH', 6379)
    });
  }

  usermetadbClient = options.usermetadbClient
    ?? redis.createClient(
      ServiceEnv.port('REDIS_USERMETA', 6379),
      ServiceEnv.host('REDIS_USERMETA', 6379),
        {no_ready_check: true}
    );

  if (options.redisClient) {
    redisClient = options.redisClient;
  } else {
    redisClient = redis.createClient(
      ServiceEnv.port('REDIS_INVITATIONS', 6379),
      ServiceEnv.host('REDIS_INVITATIONS', 6379),
        {no_ready_check: true}
    );
  }

  // If we have sendNotification option, then use that.
  // Otherwise if ENV variables are set, use those.
  // Otherwise don't send notifications.
  if (options.sendNotification instanceof Function) {
    return sendNotification = options.sendNotification;
  } else if (ServiceEnv.exists('NOTIFICATIONS', 8080)) {
    const url = ServiceEnv.url('NOTIFICATIONS', 8080);
    return sendNotification = SendNotification.create(url);
  } else {
    return sendNotification = function() {}; // no-op
  }
};

const addRoutesAs = function (server: restify.Server, routes: {[type: string]: string}, middlewares: restify.RequestHandler[]) {
  for (let method of Object.keys(routes || {})) {
    const endpoint: string = routes[method];
    server[method].apply(server, ([ endpoint ] as (string|restify.RequestHandler)[]).concat(middlewares));
  }
};

const addDel = function(server: restify.Server, endpoint: string, ...middlewares: restify.RequestHandler[]) {
  addRoutesAs(server, {
    del:  `${endpoint}`,
    post: `${endpoint}/delete`
  }, middlewares);
};

const addRoutes = function(prefix: string, server: restify.Server) {
  const endpoint = `/${prefix}/auth/:authToken/invitations`;

  // All requests must be authorized.
  const authMiddleware = authdbHelper.create({
    authdbClient,
    secret: process.env.API_SECRET || ''
  });
  server.use(function(req, res, next) {
    const authorize = req.getRoute().path.toString().startsWith(endpoint);
    if (authorize) {
      return authMiddleware(req, res, next);
    } else {
      return next();
    }
  });

  server.get(endpoint, listInvitations, updateExpireMiddleware);
  server.post(endpoint, checkBlocked(usermetadbClient), createInvitation, updateExpireMiddleware);
  return addDel(server, `${endpoint}/:invitationId`,
    findInvitationMiddleware, deleteInvitation, updateExpireMiddleware);
};
  //server.del "#{endpoint}/:invitationId", authMiddleware,
  //  findInvitationMiddleware, deleteInvitation, updateExpireMiddleware

// Export the module
export default {
  initialize,
  addRoutes,
  Invitation
};

// vim: ts=2:sw=2:et:

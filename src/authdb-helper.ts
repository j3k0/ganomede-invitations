import * as restifyErrors from 'restify-errors';
import { RequestHandler, Request, Response, Next } from 'restify';
import { HttpError } from 'restify-errors';
import Logger from 'bunyan';
const SECRET_SEPARATOR = '.';

export interface AuthdbUser {
  username: string;
  email?: string;
}

export interface AuthdbClient {
  addAccount: (token: string, user: AuthdbUser, callback?: (err?: HttpError | null) => void) => void;
  getAccount: (token: string, callback: (err: HttpError | null, user?: AuthdbUser) => void) => void;
}

export interface AuthenticatorAccount {
  req_id?: string;
  username: string;
  email: string;
  token?: string;
}

export interface AuthdbOptions {
  authdbClient: AuthdbClient;
  log?: Logger;
  secret: string;
}

export default {

  create: function (options: AuthdbOptions): RequestHandler {

    const authdbClient: AuthdbClient = options.authdbClient;
    if (!authdbClient) {
      throw new Error("options.authdbClient is missing");
    }

    const secret: string = options.secret ? options.secret + SECRET_SEPARATOR : '';
    if (options.hasOwnProperty('secret')) {
      if (!(typeof options.secret === 'string' && options.secret.length > 0)) {
        throw new Error("options.secret must be non-empty string");
      }
    }

    function parseUsernameFromSecretToken(token: string): string | null {
      const valid = (0 === token.indexOf(secret)) && (token.length > secret.length);
      const username = valid ? token.slice(secret.length) : null;
      return username;
    };

    const log: Logger = options.log || {
      error: function () { }
    } as Logger;

    return function (req: Request, res: Response, next: Next): void {
      if (!req.params) req.params = {};
      const authToken: string | undefined = req.params.authToken;
      if (!authToken) {
        return next(new restifyErrors.InvalidContentError('invalid content'));
      }
      if (secret) {
        const spoofUsername = parseUsernameFromSecretToken(authToken);
        if (spoofUsername) {
          req.params.user = {
            _secret: true,
            username: spoofUsername
          };
          return next();
        }
      }
      return authdbClient.getAccount(authToken, function (err, account) {
        if (err || !account) {
          if (err) {
            log.error('authdbClient.getAccount() failed', {
              err: err,
              token: authToken
            });
          }
          const authErr = new restifyErrors.UnauthorizedError('not authorized');
          authErr.body.code = 'UnauthorizedError'; // legacy error code, we want to keep compatibility
          return next(authErr);
        }
        req.params.user = account;
        return next();
      });
    };
  }
}
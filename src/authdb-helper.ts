import * as restifyErrors from 'restify-errors';
const SECRET_SEPARATOR = '.';

export default {
  
  create: function(options) {
    var authdbClient, log, parseUsernameFromSecretToken, secret;
    authdbClient = options.authdbClient;
    if (!authdbClient) {
      throw new Error("options.authdbClient is missing");
    }
    secret = options.secret ? options.secret + SECRET_SEPARATOR : false;
    if (options.hasOwnProperty('secret')) {
      if (!(typeof options.secret === 'string' && options.secret.length > 0)) {
        throw new Error("options.secret must be non-empty string");
      }
    }
    parseUsernameFromSecretToken = function(token) {
      var username, valid;
      valid = (0 === token.indexOf(secret)) && (token.length > secret.length);
      username = valid ? token.slice(secret.length) : null;
      return username;
    };
    log = options.log || {
      error: function() {}
    };
    return function(req, res, next) {
      var authToken, spoofUsername;
      authToken = req.params.authToken;
      if (!authToken) {
        return next(new restifyErrors.InvalidContentError('invalid content'));
      }
      if (secret) {
        spoofUsername = parseUsernameFromSecretToken(authToken);
        if (spoofUsername) {
          req.params.user = {
            _secret: true,
            username: spoofUsername
          };
          return next();
        }
      }
      return authdbClient.getAccount(authToken, function(err, account) {
        if (err || !account) {
          if (err) {
            log.error('authdbClient.getAccount() failed', {
              err: err,
              token: authToken
            });
          }
          return next(new restifyErrors.UnauthorizedError('not authorized'));
        }
        req.params.user = account;
        return next();
      });
    };
  }
}
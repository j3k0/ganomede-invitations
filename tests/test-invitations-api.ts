/*
 * decaffeinate suggestions:
 * DS102: Remove unnecessary code created because of implicit returns
 * DS207: Consider shorter variations of null checks
 * Full docs: https://github.com/decaffeinate/decaffeinate/blob/master/docs/suggestions.md
 */
import * as lodash from 'lodash';
import * as assert from "assert";
import * as restify from 'restify';
import * as vasync from 'vasync';
import * as superagent from 'superagent';
import api from "../src/invitations-api";
import * as fakeRedis from "fakeredis";
import expect from 'expect.js';
import * as authdb from 'authdb';
import * as td from 'testdouble';

const PREFIX = 'invitations/v1';

describe("invitations-api", function() {

  let server: restify.Server = restify.createServer();
  let redis = fakeRedis.createClient(`test-invitations-init`);

  let i = 0;

  // some sample data
  let data = createData();

  function createData() {
    const RND_STR = String(Math.random()).split('.')[1].slice(0,8);
    return {
      rnd: RND_STR,

      authTokens: {
        valid: 'valid-token-12345689-' + RND_STR,
        invalid: 'invalid-token-12345689-' + RND_STR,
        random1: 'token-random-user-1-' + RND_STR,
        to: 'valid-token-userto-' + RND_STR
      },

      usernames: {
        from: 'some-username-' + RND_STR,
        to: 'valid-username-' + RND_STR,
        random1: 'random-user-' + RND_STR
      },

      invitation: {
        gameId: "0123456789abcdef012345" + RND_STR,
        type: "triominos/v1",
        to: "valid-username-" + RND_STR
      }
    };
  };

  const fakeSendNotificationUrl = 'http://notifications.ganomede/add';
  const fakeSendNotification = td.function('.fakeSendNotification()');

  const endpoint = function(token) {
    const host = `http://localhost:${server!.address().port}`;
    return `${host}/${PREFIX}/auth/${token}/invitations`;
  };

  const expect401 = done => (function(err, res) {
    /*if (err)
      console.log(err);
    assert.ok(!err)*/;
    assert.equal(401, res.status);
    assert.equal('UnauthorizedError', res.body.code);
    return done();
  });

  beforeEach(function(done) {

    data = createData();
    i += 1;

    // Setup mock implementation of other modules
    server = restify.createServer();
    redis = fakeRedis.createClient(`test-invitations-${i}`);
    const redisAuth = fakeRedis.createClient(`test-authdb-${i}`);
    const authdbClient = authdb.createClient({redisClient: redisAuth});
    api.initialize({
      authdbClient,
      redisClient: redis,
      sendNotification: fakeSendNotification.bind(null, fakeSendNotificationUrl)
    });

    server.use(restify.plugins.bodyParser());
    api.addRoutes(PREFIX, server);

    const addAuthdbAccount = (token, username) => (cb) => {
      authdbClient.addAccount(token, {username}, cb);
    }

    return vasync.parallel({
      funcs: [
        addAuthdbAccount(data.authTokens.valid, data.usernames.from),
        addAuthdbAccount(data.authTokens.random1, data.usernames.random1),
        addAuthdbAccount(data.authTokens.to, data.usernames.to),
        cb => server.listen(1337, cb)
      ]
    }
      ,
      done);
  });

  afterEach(function(done) {
    td.reset();
    server.close();
    return server.once('close', redis.flushdb.bind(redis, done));
  });

  describe('POST: Add new invitations', function() {
    it("should allow authenticated users to create new invitations", done => superagent
      .post(endpoint(data.authTokens.valid))
      .send(data.invitation)
      .end(function(err, res) {
        assert.ok(!err);
        assert.equal(200, res.status);
        assert.ok(res.body.id);

        return redis.get(res.body.id, function(err, reply) {
          assert.ok(!err);
          assert.equal(data.usernames.from, JSON.parse(reply).from);
          return done();
        });
    }));

    it("should reject unauthenticated users with HTTP 401", done => superagent
      .post(endpoint(data.authTokens.invalid))
      .send(data.invitation)
      .end(expect401(done)));

    it("should allow only valid requests", function(done) {
      const badInvites = [{
        gameId: data.invitation.gameId,
        type: data.invitation.type
      }
      , {
        gameId: data.invitation.gameId,
        to: data.invitation.to
      }
      , {
        type: data.invitation.type,
        to: data.invitation.to
      }
      ];

      const test = (body, cb) => superagent.agent()
        .post(endpoint(data.authTokens.valid))
        .send(body)
        .end(function(err, res) {
          assert.equal(400, res.status);
          assert.equal('InvalidContent', res.body.code);
          return cb();
      });

      return vasync.forEachParallel({
        func: test,
        inputs: badInvites
      }
        ,
        done);
    });

    return it('Sends notification to ganomede-notificaions', done => superagent
      .post(endpoint(data.authTokens.valid))
      .send(data.invitation)
      .end(function(err, res) {
        expect(err).to.be(null);

        const matchPush = td.matchers.argThat(function(arg) {
          // Good basics
          expect(lodash.pick(arg, 'from', 'to', 'type')).to.eql({
            from: 'invitations/v1',
            to: data.usernames.to,
            type: 'invitation-created'
          });

          // data.invitation is correct
          expect(arg).to.have.property('data');
          expect(arg.data).to.have.property('invitation');
          expect(arg.data.invitation).to.have.property('id');
          // For some reason, coffee `class` makes methods show up
          // when comparing with `.to.eql()`, so Object.assign() that out
          // and only account for enumerables.
          const enumerablesOfInitvation = Object.assign({}, arg.data.invitation);
          expect(lodash.omit(enumerablesOfInitvation, 'id')).to.eql({
            from: data.usernames.from,
            to: data.usernames.to,
            gameId: data.invitation.gameId,
            type: 'triominos/v1'
          });

          // has push with nice *ArgsTypes
          expect(arg).to.have.property('push');
          expect(arg.push).to.eql({
            app: 'triominos/v1',
            title: ['invitation_received_title'],
            message: ['invitation_received_message', data.usernames.from],
            messageArgsTypes: ['directory:name']
          });

          return true;
        });

        td.verify(fakeSendNotification(fakeSendNotificationUrl, matchPush));
        return done();
    }));
  });

  //
  // List user invitations
  //

  describe('GET: List user invitations', function() {
    it("should allow authenticated users list their invitations", function(done) {
      const listInvites = function(authToken, cb) {
        if (authToken == null) { authToken = data.authTokens.valid; }
        return superagent
          .get(endpoint(authToken))
          .end(function(err, res) {
            assert.ok(!err);
            assert.equal(200, res.status);
            assert.ok(Array.isArray(res.body));
            return cb(res.body);
        });
      };

      const testInvites = test => (_, cb) => listInvites(null, function(invites) {
        test(invites);
        return cb();
      });

      // empty at first
      const t1 = invites => assert.equal(0, invites.length);

      // add invitation
      let invitationId = null;
      const t2 = (_, cb) => superagent
        .post(endpoint(data.authTokens.valid))
        .send(data.invitation)
        .end(function(err, res) {
          assert.ok(!err);
          assert.equal(200, res.status);
          assert.ok(res.body.id);
          invitationId = res.body.id;
          return cb();
      });

      // shoud have one invite
      const t3 = function(invites) {
        const invite = invites[0];
        assert.equal(1, invites.length);
        assert.equal(data.usernames.from, invite.from);
        assert.equal(data.invitation.to, invite.to);
        assert.equal(data.invitation.type, invite.type);
        assert.equal(data.invitation.gameId, invite.gameId);
        return assert.equal(invitationId, invite.id);
      };

      return vasync.pipeline(
        {funcs: [testInvites(t1), t2, testInvites(t3)]}
        ,
        done);
    });

    it('should reject unauthenitacted users with HTTP 401', done => superagent
      .get(endpoint(data.authTokens.invalid))
      .end(expect401(done)));

    return it('should allow auth via API_SECRET.username', function(done) {
      const token = `${process.env.API_SECRET}.${data.usernames.from}`;
      return superagent
        .get(endpoint(token))
        .end(function(err, res) {
          expect(err).to.be(null);
          expect(res.status).to.be(200);
          return done(err);
      });
    });
  });

  describe('DEL: Delete invitation', function() {

    const withoutError = cb => (function(err, res) {
      //assert.ok(!err);
      return cb(res);
    });

    const add = (token, invitation, cb) => superagent.agent()
      .post(endpoint(token))
      .send(invitation)
      .end(withoutError(cb));

    const delWithDel = (id, token, reason, cb) => superagent.agent()
      .del(`${endpoint(token)}/${id}`)
      .send({reason})
      .end(withoutError(cb));

    const delWithPost = (id, token, reason, cb) => superagent.agent()
      .post(`${endpoint(token)}/${id}/delete`)
      .send({reason})
      .end(withoutError(cb));

    const testUsing = function(desc, del) {

      it(desc + 'results in HTTP 404 for non-existent invitation ID', done => del('nonexistentid', data.authTokens.valid, '', function(res) {
        assert.equal(res.status, 404);
        assert.equal(res.body.code, 'NotFoundError');
        return done();
      }));

      it(desc + 'should reject unauthenitacted users with HTTP 401', done => del('nonexistentid', data.authTokens.invalid, '', function(res) {
        assert.equal(401, res.status);
        assert.equal(res.body.code, 'UnauthorizedError');
        return done();
      }));

      it(desc + 'should refuse requests with bad reason field', function(done) {
        let invitationId = null;

        const go = () => add(data.authTokens.valid, data.invitation, function(res) {
          assert.equal(200, res.status);
          assert.ok(res?.body?.id);
          invitationId = res.body.id;

          return vasync.parallel({
            funcs: [
              delAs.bind(null, data.authTokens.valid, 'accept'), // from user
              delAs.bind(null, data.authTokens.to, 'cancel'), // to user
              delAs.bind(null, data.authTokens.valid, '') // no reason specified
            ]
          }
            ,
            done);
        });

        const badRequest = cb => (function(res) {
          assert.equal(400, res.status);
          assert.equal('InvalidContent', res.body.code);
          return cb();
        });

        var delAs = (token, reason, cb) => del(invitationId, token, reason, badRequest(cb));

        return go();
      });

      it(desc + 'should delete invitations only for participants', done => // add invite from first user to second
      // try to delete as third user
      add(data.authTokens.valid, data.invitation, function(res) {
        assert.equal(200, res.status);
        assert.ok(res.body.id);

        return del(res.body.id, data.authTokens.random1, 'reason', function(res) {
          assert.equal(403, res.status);
          assert.equal('ForbiddenError', res.body.code);
          return done();
        });
      }));

      function testDelete(tokenKey, reason) {
        it(desc + "should let users delete their invitations (" + reason + ")", function(done) {
          const deleteToken = data.authTokens[tokenKey];
          const deleteNewInvite = (next) => add(data.authTokens.valid, data.invitation, function(res) {
            assert.equal(undefined, res.body?.code);
            assert.equal(200, res.status);
            assert.ok(res.body.id);

            del(res.body.id, deleteToken, reason, function(res) {
              assert.equal(undefined, res.body?.message);
              assert.equal(undefined, res.body?.code);
              assert.equal(204, res.status);
              ensureDeleted(next);
            });
          });

          var ensureDeleted = (next) => superagent
            .get(endpoint(data.authTokens.valid))
            .end(function(err, res) {
              assert.ok(!err);
              assert.equal(200, res.status);
              assert.ok(Array.isArray(res.body));
              assert.equal(0, res.body.length);
              next();
          });

          deleteNewInvite(done);
        });
      };
      testDelete('valid', 'cancel');
      testDelete('to', 'accept');
      testDelete('to', 'refuse');
    };

    testUsing("[del] ", delWithDel);
    testUsing("[post] ", delWithPost);
  });

  //
  // ANTI-SPAM
  //

  describe('ANTI-SPAM: Cannot add new invitations until 24h elapsed', function() {
    it("prevent users to create a new invitation just after refusal", done => {
      superagent
      .post(endpoint(data.authTokens.valid))
      .send(data.invitation)
      .end(function(err, res) {
        assert.equal(200, res.status);
        superagent
        .del(`${endpoint(data.authTokens.to)}/${res.body.id}`)
        .send({reason: 'refuse'})
        .end(function(err, res) {
          assert.equal(204, res.status);
          superagent
          .post(endpoint(data.authTokens.valid))
          .send(data.invitation)
          .end(function(err, res) {
            assert.equal(200, res.status);
            assert.equal('TooManyInvitations', res.body.code);
            done();
          });
        });
      });
    });
  });

  //
  // TTL
  //

  return describe('TTL: Redis-stored invitations should be EXPIREable', function() {
    it('should add TTL to newly created invitations', done => superagent
      .post(endpoint(data.authTokens.valid))
      .send(data.invitation)
      .end(function(err, res) {
        assert.ok(!err);
        assert.equal(200, res.status);

        return redis.keys('*', function(err, keys) {
          assert.ok(!err);
          assert.ok(Array.isArray(keys));
          assert.equal(3, keys.length);

          const ttlOk = (key, cb) => redis.ttl(key, function(err, ttl) {
            assert.ok(!err);
            if (key === data.invitation.to) {
              assert.equal(-1, ttl); // key exists with no ttl
            } else {
              assert.ok(ttl > 0);
            }
            return cb();
          });

          return vasync.forEachParallel({
            func: ttlOk,
            inputs: keys
          }
            ,
            done);
        });
    }));

    return it('should not include expired invitations in the listing', function(done) {
      let expiredId = null;

      const add = next => superagent
        .post(endpoint(data.authTokens.valid))
        .send(data.invitation)
        .end(function(err, res) {
          assert.ok(!err);
          assert.equal(200, res.status);
          assert.ok(res.body.id);
          expiredId = res.body.id;
          return next();
      });

      const expire = function(next) {
        const WAIT_MS = 1;
        return redis.pexpire(expiredId, WAIT_MS, function(err, retval) {
          assert.ok(!err);
          assert.equal(1, retval);
          return setTimeout(next, 2 + WAIT_MS);
        });
      };

      return add(expire.bind(null, () => superagent
        .get(endpoint(data.authTokens.valid))
        .end(function(err, res) {
          assert.ok(!err);
          assert.equal(200, res.status);
          assert.ok(Array.isArray(res.body));
          assert.equal(0, res.body.length);

          // Since we expired only invitation in user's list
          // we expect it to be emptied by Invitation.forUsername
          return redis.smembers(data.usernames.from, function(err, ids) {
            assert.ok(!err);
            assert.ok(Array.isArray(ids));
            assert.equal(0, ids.length);
            return done();
          });
      }))
      );
    });
  });
});

// vim: ts=2:sw=2:et:

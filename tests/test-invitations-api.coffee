lodash = require 'lodash'
assert = require "assert"
restify = require 'restify'
vasync = require 'vasync'
superagent = require 'superagent'
authdb = require 'authdb'
api = require "../src/invitations-api"
fakeRedis = require "fakeredis"
expect = require 'expect.js'
authdb = require 'authdb'
td = require 'testdouble'

PREFIX = 'invitations/v1'

describe "invitations-api", ->

  server = null
  redis = null
  i = 0

  # some sample data
  data =
    authTokens:
      valid: 'valid-token-12345689'
      invalid: 'invalid-token-12345689'
      random1: 'token-random-user-1'
      to: 'valid-token-userto'

    usernames:
      from: 'some-username'
      to: 'valid-username'
      random1: 'random-user-1'

    invitation:
      gameId: "0123456789abcdef012345",
      type: "triominos/v1",
      to: "valid-username"

  fakeSendNotificationUrl = 'http://notifications.ganomede/add'
  fakeSendNotification = td.function('.fakeSendNotification()')

  endpoint = (token) ->
    host = "http://localhost:#{server.address().port}"
    return "#{host}/#{PREFIX}/auth/#{token}/invitations"

  expect401 = (done) ->
    return (err, res) ->
      assert.ok !err
      assert.equal 401, res.status
      assert.equal 'UnauthorizedError', res.body.code
      done()

  beforeEach (done) ->

    i += 1

    # Setup mock implementation of other modules
    server = restify.createServer()
    redis = fakeRedis.createClient("test-invitations-#{i}")
    redisAuth = fakeRedis.createClient("test-authdb-#{i}")
    authdbClient = authdb.createClient({redisClient: redisAuth})
    api.initialize({
      authdbClient,
      redisClient: redis
      sendNotification: fakeSendNotification.bind(null, fakeSendNotificationUrl)
    })

    server.use(restify.bodyParser())
    api.addRoutes(PREFIX, server)

    addAuthdbAccount = (token, username) ->
      authdbClient.addAccount.bind(
        authdbClient,
        token,
        {username}
      )

    vasync.parallel
      funcs: [
        addAuthdbAccount data.authTokens.valid, data.usernames.from
        addAuthdbAccount data.authTokens.random1, data.usernames.random1
        addAuthdbAccount data.authTokens.to, data.usernames.to
        (cb) -> server.listen(1337, cb)
      ]
      ,
      done

  afterEach (done) ->
    td.reset()
    server.close()
    server.once('close', redis.flushdb.bind(redis, done))

  describe 'POST: Add new invitations', () ->
    it "should allow authenticated users to create new invitations", (done) ->
      superagent
        .post endpoint(data.authTokens.valid)
        .send data.invitation
        .end (err, res) ->
          assert.ok !err
          assert.equal 200, res.status
          assert.ok res.body.id

          redis.get res.body.id, (err, reply) ->
            assert.ok !err
            assert.equal data.usernames.from, JSON.parse(reply).from
            done()

    it "should reject unauthenticated users with HTTP 401", (done) ->
      superagent
        .post endpoint(data.authTokens.invalid)
        .send data.invitation
        .end expect401(done)

    it "should allow only valid requests", (done) ->
      badInvites = [
        gameId: data.invitation.gameId
        type: data.invitation.type
      ,
        gameId: data.invitation.gameId
        to: data.invitation.to
      ,
        type: data.invitation.type
        to: data.invitation.to
      ]

      test = (body, cb) ->
        superagent.agent()
          .post endpoint(data.authTokens.valid)
          .send body
          .end (err, res) ->
            assert.equal 400, res.status
            assert.equal 'InvalidContent', res.body.code
            cb()

      vasync.forEachParallel
        func: test
        inputs: badInvites
        ,
        done

    it 'Sends notification to ganomede-notificaions', (done) ->
      superagent
        .post endpoint(data.authTokens.valid)
        .send data.invitation
        .end (err, res) ->
          expect(err).to.be(null)

          matchPush = td.matchers.argThat (arg) ->
            # Good basics
            expect(lodash.pick(arg, 'from', 'to', 'type')).to.eql({
              from: 'invitations/v1',
              to: 'valid-username',
              type: 'invitation-created'
            })

            # data.invitation is correct
            expect(arg).to.have.property('data')
            expect(arg.data).to.have.property('invitation')
            expect(arg.data.invitation).to.have.property('id')
            # For some reason, coffee `class` makes methods show up
            # when comparing with `.to.eql()`, so Object.assign() that out
            # and only account for enumerables.
            enumerablesOfInitvation = Object.assign({}, arg.data.invitation)
            expect(lodash.omit(enumerablesOfInitvation, 'id')).to.eql({
              from: 'some-username',
              to: 'valid-username',
              gameId: '0123456789abcdef012345',
              type: 'triominos/v1'
            })

            # has push with nice *ArgsTypes
            expect(arg).to.have.property('push')
            expect(arg.push).to.eql({
              app: 'triominos/v1',
              title: ['invitation_received_title'],
              message: ['invitation_received_message', 'some-username'],
              messageArgsTypes: ['directory:name']
            })

            return true

          td.verify(fakeSendNotification(fakeSendNotificationUrl, matchPush))
          done()

  #
  # List user invitations
  #

  describe 'GET: List user invitations', () ->
    it "should allow authenticated users list their invitations", (done) ->
      listInvites = (authToken=data.authTokens.valid, cb) ->
        superagent
          .get endpoint(authToken)
          .end (err, res) ->
            assert.ok !err
            assert.equal 200, res.status
            assert.ok Array.isArray(res.body)
            cb(res.body)

      testInvites = (test) ->
        return (_, cb) ->
          listInvites null, (invites) ->
            test(invites)
            cb()

      # empty at first
      t1 = (invites) ->
        assert.equal 0, invites.length

      # add invitation
      invitationId = null
      t2 = (_, cb) ->
        superagent
          .post endpoint(data.authTokens.valid)
          .send data.invitation
          .end (err, res) ->
            assert.ok !err
            assert.equal 200, res.status
            assert.ok res.body.id
            invitationId = res.body.id
            cb()

      # shoud have one invite
      t3 = (invites) ->
        invite = invites[0]
        assert.equal 1, invites.length
        assert.equal data.usernames.from, invite.from
        assert.equal data.invitation.to, invite.to
        assert.equal data.invitation.type, invite.type
        assert.equal data.invitation.gameId, invite.gameId
        assert.equal invitationId, invite.id

      vasync.pipeline
        funcs: [testInvites(t1), t2, testInvites(t3)]
        ,
        done

    it 'should reject unauthenitacted users with HTTP 401', (done) ->
      superagent
        .get endpoint(data.authTokens.invalid)
        .end expect401(done)

    it 'should allow auth via API_SECRET.username', (done) ->
      token = "#{process.env.API_SECRET}.#{data.usernames.from}"
      superagent
        .get endpoint(token)
        .end (err, res) ->
          expect(err).to.be(null)
          expect(res.status).to.be(200)
          done(err)

  describe 'DEL: Delete invitation', () ->

    withoutError = (cb) ->
      (err, res) ->
        assert.ok !err
        cb(res)

    add = (token, invitation, cb) ->
      superagent.agent()
        .post endpoint(token)
        .send invitation
        .end withoutError cb

    delWithDel = (id, token, reason, cb) ->
      superagent.agent()
        .del "#{endpoint(token)}/#{id}"
        .send reason: reason
        .end withoutError cb

    delWithPost = (id, token, reason, cb) ->
      superagent.agent()
        .post "#{endpoint(token)}/#{id}/delete"
        .send reason: reason
        .end withoutError cb

    testUsing = (desc, del) ->

      it desc + 'results in HTTP 404 for non-existent invitation ID', (done) ->
        del 'nonexistentid', data.authTokens.valid, '', (res) ->
          assert.equal 404, res.status
          assert.equal 'NotFoundError', res.body.code
          done()

      it desc + 'should reject unauthenitacted users with HTTP 401', (done) ->
        del 'nonexistentid', data.authTokens.invalid, '', (res) ->
          assert.equal 401, res.status
          assert.equal 'UnauthorizedError', res.body.code
          done()

      it desc + 'should refuse requests with bad reason field', (done) ->
        invitationId = null

        go = () ->
          add data.authTokens.valid, data.invitation, (res) ->
            assert.equal 200, res.status,
            assert.ok res.body.id
            invitationId = res.body.id

            vasync.parallel
              funcs: [
                delAs.bind null, data.authTokens.valid, 'accept' # from user
                delAs.bind null, data.authTokens.to, 'cancel' # to user
                delAs.bind null, data.authTokens.valid, '' # no reason specified
              ]
              ,
              done

        badRequest = (cb) ->
          (res) ->
            assert.equal 400, res.status
            assert.equal 'InvalidContent', res.body.code
            cb()

        delAs = (token, reason, cb) ->
          del invitationId, token, reason, badRequest(cb)

        go()

      it desc + 'should delete invitations only for participants', (done) ->
        # add invite from first user to second
        # try to delete as third user
        add data.authTokens.valid, data.invitation, (res) ->
          assert.equal 200, res.status
          assert.ok res.body.id

          del res.body.id, data.authTokens.random1, 'reason', (res) ->
            assert.equal 403, res.status
            assert.equal 'ForbiddenError', res.body.code
            done()

      it desc + "should let users delete their invitations", (done) ->
        deleteNewInvite = (deleteToken, reason, _, next) ->
          add data.authTokens.valid, data.invitation, (res) ->
            assert.equal 200, res.status
            assert.ok res.body.id

            del res.body.id, deleteToken, reason, (res) ->
              assert.equal 204, res.status
              ensureDeleted(deleteToken, next)

        ensureDeleted = (deleteToken, next) ->
          superagent
            .get endpoint(data.authTokens.valid)
            .end (err, res) ->
              assert.ok !err
              assert.equal 200, res.status
              assert.ok Array.isArray(res.body)
              assert.equal 0, res.body.length
              next()

        vasync.pipeline
          funcs: [
            deleteNewInvite.bind(null, data.authTokens.valid, 'cancel')
            deleteNewInvite.bind(null, data.authTokens.to, 'accept')
            deleteNewInvite.bind(null, data.authTokens.to, 'refuse')
          ]
          ,
          done

    testUsing "[del] ", delWithDel
    testUsing "[post] ", delWithPost

  #
  # TTL
  #

  describe 'TTL: Redis-stored invitations should be EXPIREable', () ->
    it 'should add TTL to newly created invitations', (done) ->
      superagent
        .post endpoint(data.authTokens.valid)
        .send data.invitation
        .end (err, res) ->
          assert.ok !err
          assert.equal 200, res.status

          redis.keys '*', (err, keys) ->
            assert.ok !err
            assert.ok Array.isArray(keys)
            assert.equal 3, keys.length

            ttlOk = (key, cb) ->
              redis.ttl key, (err, ttl) ->
                assert.ok !err
                if key == data.invitation.to
                  assert.equal -1, ttl # key exists with no ttl
                else
                  assert.ok ttl > 0
                cb()

            vasync.forEachParallel
              func: ttlOk
              inputs: keys
              ,
              done

    it 'should not include expired invitations in the listing', (done) ->
      expiredId = null

      add = (next) ->
        superagent
          .post endpoint(data.authTokens.valid)
          .send data.invitation
          .end (err, res) ->
            assert.ok !err
            assert.equal 200, res.status
            assert.ok res.body.id
            expiredId = res.body.id
            next()

      expire = (next) ->
        WAIT_MS = 1
        redis.pexpire expiredId, WAIT_MS, (err, retval) ->
          assert.ok !err
          assert.equal 1, retval
          setTimeout next, 2 + WAIT_MS

      add expire.bind null, () ->
        superagent
          .get endpoint(data.authTokens.valid)
          .end (err, res) ->
            assert.ok !err
            assert.equal 200, res.status
            assert.ok Array.isArray(res.body)
            assert.equal 0, res.body.length

            # Since we expired only invitation in user's list
            # we expect it to be emptied by Invitation.forUsername
            redis.smembers data.usernames.from, (err, ids) ->
              assert.ok !err
              assert.ok Array.isArray(ids)
              assert.equal 0, ids.length
              done()

# vim: ts=2:sw=2:et:

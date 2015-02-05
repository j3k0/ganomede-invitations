assert = require "assert"
restify = require 'restify'
vasync = require 'vasync'
superagent = require 'superagent'
api = require "../src/invitations-api"
fakeRedis = require "fakeredis"
fakeAuthdb = require "./fake-authdb"

describe "invitations-api", ->

  server = null
  redis = null
  authdb = null
  i = 0

  # some sample data
  data =
    authTokens:
      valid: 'valid-token-12345689'
      invalid: 'invalid-token-12345689'

    usernames:
      from: 'some-username'
      to: 'valid-username'

    invitation:
      gameId: "0123456789abcdef012345",
      type: "triominos/v1",
      to: "valid-username"

  endpoint = (token) ->
    return server.url + "/test/v0/auth/#{token}/invitations"

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
    authdb = fakeAuthdb.createClient()
    api.initialize
      authdbClient: authdb
      redisClient: redis
    authdb.addAccount data.authTokens.valid, username: data.usernames.from

    server.use(restify.bodyParser())
    api.addRoutes "test/v0", server
    server.listen(1337, done)

  afterEach (done) ->
    server.close()
    server.once('close', done)

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
            assert.equal 'some-username', JSON.parse(reply).from
            done()

    it "should reject unauthenitacted users with HTTP 401", (done) ->
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

# vim: ts=2:sw=2:et:

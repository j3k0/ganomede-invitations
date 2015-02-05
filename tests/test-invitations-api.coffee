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

  endpoint = (path) ->
    return server.url + path

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

  #
  # POST new invitations
  #

  it "should allow authenticated users to post new invitations", (done) ->
    # we can't access routes bound this way (we can, but we don't know id),
    # but we making requests to them anyway so we shouldn't really bother
    # checking them manually
    #assert.ok server.routes.post["/test/v0/auth/:authToken/invitations"]

    superagent
      .post endpoint("/test/v0/auth/#{data.authTokens.valid}/invitations")
      .send data.invitation
      .end (err, res) ->
        assert.ok !err
        assert.equal 200, res.status
        assert.ok res.body.id

        redis.get res.body.id, (err, reply) ->
          assert.ok !err
          assert.equal 'some-username', JSON.parse(reply).from
          done()

  it "should allow only authenticated users to post new invitations", (done) ->
    # assert.ok server.routes.post["/test/v0/auth/:authToken/invitations"]

    superagent
      .post endpoint("/test/v0/auth/#{data.authTokens.invalid}/invitations")
      .send data.invitation
      .end (err, res) ->
        assert.equal 401, res.status
        done()

  it "should allow only valid requests", (done) ->
    # assert.ok server.routes.post["/test/v0/auth/:authToken/invitations"]

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
        .post endpoint("/test/v0/auth/#{data.authTokens.valid}/invitations")
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

  it "should let authenticated users list their invitations", (done) ->
    # assert.ok server.routes.get["/test/v0/auth/:authToken/invitations"]

    listInvites = (authToken=data.authTokens.valid, cb) ->
      superagent
        .get endpoint(authToken)
        .end (err, res) ->
          assert.ok !err # are you sure?
          assert.equal 200, res.status
          assert.ok Array.isArray(res.body)
          cb(res.body)

    testInvites = (test) ->
      return (cb) ->
        listInvites null, (invites) ->
          test(invites)
          cb()

    # empty at first
    t1 = (invites) ->
      assert.equal 0, invites.length

    # add invitation
    invitationId = null
    t2 = (cb) ->
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

# vim: ts=2:sw=2:et:

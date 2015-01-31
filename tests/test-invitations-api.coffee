assert = require "assert"
api = require "../src/invitations-api"

fakeRestify = require "./fake-restify"
server = fakeRestify.createServer()

fakeRedis = require "fakeredis"
redis = fakeRedis.createClient("test-invitations-api")

fakeAuthdb = require "./fake-authdb"
authdb = fakeAuthdb.createClient()

describe "invitations-api", ->

  before ->
    # Setup mock implementation of other modules
    api.initialize
      authdbClient: authdb
      redisClient: redis
    api.addRoutes "test/v0", server
    authdb.addAccount "valid-token-12345689", username: "some-username"

  #
  # POST new invitations
  #

  it "should allow authenticated users to post new invitations", (done) ->

    assert.ok server.routes.post["/test/v0/auth/:authToken/invitations"]
    server.request(
      "post", "/test/v0/auth/:authToken/invitations",
        params:
          authToken: "valid-token-12345689"
        body:
          gameId: "0123456789abcdef012345",
          type: "triominos/v1",
          to: "valid-username"
      , (res) ->
        assert.equal 200, res.status
        assert.ok res.body.id
        redis.get res.body.id, (err, reply) ->
          obj = JSON.parse(reply)
          assert.ok !err
          assert.equal "some-username", obj.from
          done()
    )

  it "should allow only authenticated users to post new invitations", ->

    assert.ok server.routes.post["/test/v0/auth/:authToken/invitations"]
    server.request "post", "/test/v0/auth/:authToken/invitations",
      params: authToken: "invalid-token-12345689"
      body:
        gameId: "0123456789abcdef012345",
        type: "triominos/v1",
        to: "valid-username"
    assert.equal 401, server.res.status

  it "should allow only valid requests", ->

    assert.ok server.routes.post["/test/v0/auth/:authToken/invitations"]

    server.request "post", "/test/v0/auth/:authToken/invitations",
      params: authToken: "valid-token-12345689"
      body:
        gameId: "0123456789abcdef012345",
        type: "triominos/v1"
    assert.equal 400, server.res.status
    assert.equal "InvalidContent", server.res.body.code

    server.request "post", "/test/v0/auth/:authToken/invitations",
      params: authToken: "valid-token-12345689"
      body:
        gameId: "0123456789abcdef012345",
        to: "valid-username"
    assert.equal 400, server.res.status
    assert.equal "InvalidContent", server.res.body.code

    server.request "post", "/test/v0/auth/:authToken/invitations",
      params: authToken: "valid-token-12345689"
      body:
        type: "triominos/v1"
        to: "valid-username"
    assert.equal 400, server.res.status
    assert.equal "InvalidContent", server.res.body.code

# vim: ts=2:sw=2:et:

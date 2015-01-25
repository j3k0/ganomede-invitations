assert = require "assert"
pingApi = require "../src/ping-api"

fakeRestify = require "./fake-restify"
server = fakeRestify.createServer()

describe "ping-api", ->

  before ->
    pingApi.addRoutes "users", server

  it "should have get and head routes", ->
    assert.ok server.routes.get["/users/ping/:token"]
    assert.ok server.routes.head["/users/ping/:token"]

  it "should reply to a ping with a pong", ->
    server.request "get", "/users/ping/:token", params: token: "pop"
    assert.equal server.res.body, "pong/pop"
    server.request "head", "/users/ping/:token", params: token: "beep"
    assert.equal server.res.body, "pong/beep"

# vim: ts=2:sw=2:et:

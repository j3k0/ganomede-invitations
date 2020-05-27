/*
 * decaffeinate suggestions:
 * DS102: Remove unnecessary code created because of implicit returns
 * Full docs: https://github.com/decaffeinate/decaffeinate/blob/master/docs/suggestions.md
 */
import * as assert from "assert";
import pingApi from "../src/ping-api";

import {Server} from "./fake-restify";
const server = new Server();

describe("ping-api", function() {

  before(() => pingApi.addRoutes("users", server));

  it("should have get and head routes", function() {
    assert.ok(server.routes.get["/users/ping/:token"]);
    return assert.ok(server.routes.head["/users/ping/:token"]);
});

  return it("should reply to a ping with a pong", function() {
    server.request("get", "/users/ping/:token", {params: {token: "pop"}});
    assert.equal(server.res!.body, "pong/pop");
    server.request("head", "/users/ping/:token", {params: {token: "beep"}});
    return assert.equal(server.res!.body, "pong/beep");
  });
});

// vim: ts=2:sw=2:et:

class RedisMulti
  constructor: (@client) ->
    @calls = []
  lpush: (key, value) -> @calls.push => @client.lpush key, value
  set: (key, value) -> @calls.push => @client.set key, value
  exec: (cb) ->
    cb null, (c() for c in @calls)

class RedisClient
  constructor: ->
    @store = {}
  multi: -> new RedisMulti this
  lpush: (key, value) ->
    if @store[key]
      @store[key].push "#{value}"
    else
      @store[key] = [ "#{value}" ]
  set: (key, value) ->
    @store[key] = "#{value}"
  get: (key, cb) ->
    if @store[key] == undefined
      cb "key not found"
    else
      cb null, @store[key]

module.exports =
  createClient: -> new RedisClient
# vim: ts=2:sw=2:et:

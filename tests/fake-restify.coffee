# vim: ts=2:sw=2:et:

class Res
  constructor: ->
    @status = 200
  send: (data) ->
    @body = data

class Server
  constructor: ->
    @routes =
      get: {}
      head: {}
      put: {}
      post: {}
      del: {}
  get: (url, callback) ->
    @routes.get[url] = callback
  head: (url, callback) ->
    @routes.head[url] = callback
  put: (url, callback) ->
    @routes.put[url] = callback
  post: (url, callback) ->
    @routes.post[url] = callback
  del: (url, callback) ->
    @routes.del[url] = callback

  request: (type, url, req, callback) ->
    res = @res = new Res
    next = (data) =>
      if data
        res.status = data.statusCode || 500
        res.send data.body
      callback? res
    @routes[type][url] req, res, next

module.exports =
  createServer: -> new Server

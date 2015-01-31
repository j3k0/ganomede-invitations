class AuthdbClient
  constructor: ->
    @store = {}
  addAccount: (token, user) ->
    @store[token] = user
  getAccount: (token, cb) ->
    if !@store[token]
      return cb "invalid authentication token"
    cb null, @store[token]

module.exports =
  createClient: -> new AuthdbClient
# vim: ts=2:sw=2:et:


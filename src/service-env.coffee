class ServiceEnv
  @addrEnv: (name, port) -> "#{name}_PORT_#{port}_TCP_ADDR"
  @portEnv: (name, port) -> "#{name}_PORT_#{port}_TCP_PORT"
  @exists: (name, port) ->
    return process.env.hasOwnProperty(@addrEnv name,port) &&
      process.env.hasOwnProperty(@portEnv name,port)
  @url: (name, port) ->
    if !@exists name, port
      return undefined
    else
      addr = @addrEnv name,port
      port = @portEnv name,port
      url = "http://#{process.env[addr]}"
      if port != "80"
        url += ":#{process.env[port]}"
      return url
  @host: (name, port) ->
    return process.env[@addrEnv name, port] || '127.0.0.1'
  @port: (name, port, defaultValue) ->
    return +(process.env[@portEnv name, port] || port)

module.exports = ServiceEnv
# vim: ts=2:sw=2:et:

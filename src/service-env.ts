const ServiceEnv = function() {}

ServiceEnv.config = function(name, port) {
  return {
    exists: ServiceEnv.exists(name, port),
    host: ServiceEnv.host(name, port),
    port: ServiceEnv.port(name, port),
    protocol: ServiceEnv.protocol(name, port),
    url: ServiceEnv.url(name, port)
  };
};

ServiceEnv.addrEnv = function(name, port) {
  return "" + name + "_PORT_" + port + "_TCP_ADDR";
};

ServiceEnv.portEnv = function(name, port) {
  return "" + name + "_PORT_" + port + "_TCP_PORT";
};

ServiceEnv.protocolEnv = function(name, port) {
  return "" + name + "_PORT_" + port + "_TCP_PROTOCOL";
};

ServiceEnv.exists = function(name, port) {
  return process.env.hasOwnProperty(this.addrEnv(name, port));
};

ServiceEnv.url = function(name, port) {
  var host, protocol, url;
  if (!this.exists(name, port)) {
    return void 0;
  } else {
    protocol = this.protocol(name, port);
    host = this.host(name, port);
    port = this.port(name, port);
    url = "" + protocol + "://" + host;
    if (port !== "80" || port !== "443") {
      url += ":" + port;
    }
    return url;
  }
};

ServiceEnv.host = function(name, port) {
  return process.env[this.addrEnv(name, port)] || '127.0.0.1';
};

ServiceEnv.port = function(name, port) {
  return +(process.env[this.portEnv(name, port)] || port);
};

ServiceEnv.protocol = function(name, port) {
  return process.env[this.protocolEnv(name, port)] || 'http';
};

export default ServiceEnv;
'use strict';

const logMod = require('./log');
const StatsD = require('node-statsd');
const dummyClient = () => {
  return {
    increment: function () {},
    timing: function () {},
    decrement: function () {},
    histogram: function () {},
    gauge: function () {},
    set: function () {},
    unique: function () {}
  };
};

const requiredEnv = ['STATSD_HOST', 'STATSD_PORT', 'STATSD_PREFIX'];
const missingEnv = () => {
  const len = requiredEnv.length;
  for (let i = 0; i < len; i++) {
    const e = requiredEnv[i];
    if (!process.env[e])
      return e;
  }
};

const createClient = function (arg) {
  const log = arg ? arg.log : logMod.child({
    module: 'statsd'
  });
  if (missingEnv()) {
    log.warn("Can't initialize statsd, missing env: " + missingEnv());
    return dummyClient();
  }
  const client = new StatsD({
    host: process.env.STATSD_HOST,
    port: process.env.STATSD_PORT,
    prefix: process.env.STATSD_PREFIX
  });
  client.socket.on('error', function (error) {
    return log.error('error in socket', error);
  });
  return client;
};

module.exports = {
  createClient: createClient,
  dummyClient: dummyClient
};

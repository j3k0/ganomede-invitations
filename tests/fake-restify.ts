/*
 * decaffeinate suggestions:
 * DS102: Remove unnecessary code created because of implicit returns
 * Full docs: https://github.com/decaffeinate/decaffeinate/blob/master/docs/suggestions.md
 */
// vim: ts=2:sw=2:et:

class Res {
  status: number;
  body: any;

  constructor() {
    this.status = 200;
  }
  send(data) {
    return this.body = data;
  }
}

class Server {
  routes: {
    get: {[url:string]: Function};
    head: {[url:string]: Function};
    put: {[url:string]: Function};
    post: {[url:string]: Function};
    del: {[url:string]: Function};
  }
  res?: Res;
  
  constructor() {
    this.routes = {
      get: {},
      head: {},
      put: {},
      post: {},
      del: {}
    };
  }
  get(url, callback) {
    return this.routes.get[url] = callback;
  }
  head(url, callback) {
    return this.routes.head[url] = callback;
  }
  put(url, callback) {
    return this.routes.put[url] = callback;
  }
  post(url, callback) {
    return this.routes.post[url] = callback;
  }
  del(url, callback) {
    return this.routes.del[url] = callback;
  }

  request(type, url, req, callback) {
    const res = (this.res = new Res);
    const next = data => {
      if (data) {
        res.status = data.statusCode || 500;
        res.send(data.body);
      }
      return (typeof callback === 'function' ? callback(res) : undefined);
    };
    return this.routes[type][url](req, res, next);
  }
}

export default {createServer() { return new Server; }};

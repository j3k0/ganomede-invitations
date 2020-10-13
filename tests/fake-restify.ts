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

export class Server {
  public routes: {
    get: {[url:string]: Function};
    head: {[url:string]: Function};
    put: {[url:string]: Function};
    post: {[url:string]: Function};
    del: {[url:string]: Function};
  }
  public res?: Res;
  
  public constructor() {
    this.routes = {
      get: {},
      head: {},
      put: {},
      post: {},
      del: {}
    };
  }
  public get(url, callback) {
    return this.routes.get[url] = callback;
  }
  public head(url, callback) {
    return this.routes.head[url] = callback;
  }
  public put(url, callback) {
    return this.routes.put[url] = callback;
  }
  public post(url, callback) {
    return this.routes.post[url] = callback;
  }
  public del(url, callback) {
    return this.routes.del[url] = callback;
  }

  public request(type: string, url: string, req, callback?: (res: Res) => void) {
    const res = (this.res = new Res);
    const next = data => {
      if (data) {
        res.status = data.statusCode || 500;
        res.send(data.body);
      }
      if (typeof callback === 'function') callback(res);
    };
    return this.routes[type][url](req, res, next);
  }
}

export default {createServer() { return new Server; }};

import { Request, Response, Next, Server } from "restify";

const ping = function(req: Request, res: Response, next: Next) {
  res.send("pong/" + req.params.token);
  next();
};

const addRoutes = function(prefix: string, server: Server) {
  server.get(`/${prefix}/ping/:token`, ping);
  server.head(`/${prefix}/ping/:token`, ping);
};

export default {addRoutes};

// vim: ts=2:sw=2:et:
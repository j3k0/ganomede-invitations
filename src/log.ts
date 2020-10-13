import * as bunyan from "bunyan";
const log = bunyan.createLogger({
    name: "invitations",
    level: (process.env.LOG_LEVEL || 'info') as any
});
export default log;
// vim: ts=2:sw=2:et:
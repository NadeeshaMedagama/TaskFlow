// Vercel serverless entrypoint.
//
// Vercel does not run containers: it imports a module, expects a request
// handler back, and calls it once per request. An Express app IS such a
// handler -- `app(req, res)` is exactly the signature Node's http server uses
// -- so there is no adapter to write and no second copy of the routes to keep
// in step. server.js only calls app.listen() when it is run directly, so
// requiring it here starts no listener.
//
// vercel.json points every /api/* and /health request at this file.
module.exports = require('./server');

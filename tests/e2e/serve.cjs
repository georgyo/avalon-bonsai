// Static server for the build dir. The client calls https://avalon.onl/api directly
// (src/api.ml), so no /api reverse proxy is needed here anymore — but that also means the
// API is cross-origin from localhost and avalon.onl sends no CORS headers, so the e2e
// driver (play.cjs) launches its browser with web security disabled.
const http = require('http');
const fs = require('fs');
const path = require('path');

const ROOT = path.join(__dirname, '../../_build/default/bin');
const PORT = process.env.PORT || 8123;
const MIME = { '.html': 'text/html', '.js': 'application/javascript', '.css': 'text/css', '.map': 'application/json' };

const server = http.createServer((req, res) => {
  let file = req.url === '/' ? '/index.html' : req.url.split('?')[0];
  const full = path.join(ROOT, file);
  fs.readFile(full, (err, data) => {
    if (err) { res.writeHead(404); res.end('not found'); return; }
    res.writeHead(200, { 'content-type': MIME[path.extname(full)] || 'application/octet-stream' });
    res.end(data);
  });
});
server.listen(PORT, () => console.log('serving ' + ROOT + ' on http://localhost:' + PORT));

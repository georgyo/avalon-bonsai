// Static server for the build dir. The client calls https://api.avalon.onl/api directly
// (src/api.ml), so no /api reverse proxy is needed here — that host serves CORS headers
// for localhost origins, so a stock browser works.
const http = require('http');
const fs = require('fs');
const path = require('path');

const ROOT = path.join(__dirname, '../../_build/default/bin');
const PORT = process.env.PORT || 8123;
const MIME = { '.html': 'text/html', '.js': 'application/javascript', '.css': 'text/css', '.map': 'application/json' };

const server = http.createServer((req, res) => {
  let file = req.url === '/' ? '/index.html' : req.url.split('?')[0];
  try { file = decodeURIComponent(file); } catch { res.writeHead(400); res.end('bad request'); return; }
  // A NUL byte makes fs.readFile throw synchronously (uncaught -> server death).
  if (file.includes('\0')) { res.writeHead(400); res.end('bad request'); return; }
  const full = path.join(ROOT, file);
  if (full !== ROOT && !full.startsWith(ROOT + path.sep)) { res.writeHead(403); res.end('forbidden'); return; }
  fs.readFile(full, (err, data) => {
    if (err) { res.writeHead(404); res.end('not found'); return; }
    res.writeHead(200, { 'content-type': MIME[path.extname(full)] || 'application/octet-stream' });
    res.end(data);
  });
});
server.listen(PORT, process.env.HOST || '127.0.0.1', () => console.log('serving ' + ROOT + ' on http://localhost:' + PORT));

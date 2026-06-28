// Static server for the build dir + reverse proxy of /api -> https://avalon.onl/api
const http = require('http');
const https = require('https');
const fs = require('fs');
const path = require('path');

const ROOT = path.join(__dirname, '../../_build/default/bin');
const PORT = process.env.PORT || 8123;
const MIME = { '.html': 'text/html', '.js': 'application/javascript', '.css': 'text/css', '.map': 'application/json' };

const server = http.createServer((req, res) => {
  if (req.url.startsWith('/api/')) {
    const chunks = [];
    req.on('data', c => chunks.push(c));
    req.on('end', () => {
      const body = Buffer.concat(chunks);
      const upstreamPath = req.url; // /api/<endpoint>
      const headers = { ...req.headers, host: 'avalon.onl' };
      delete headers['content-length'];
      const preq = https.request({ hostname: 'avalon.onl', port: 443, path: upstreamPath, method: req.method, headers }, pres => {
        res.writeHead(pres.statusCode, pres.headers);
        pres.pipe(res);
      });
      preq.on('error', e => { res.writeHead(502); res.end(JSON.stringify({ message: 'proxy error: ' + e.message })); });
      if (body.length) preq.write(body);
      preq.end();
    });
    return;
  }
  let file = req.url === '/' ? '/index.html' : req.url.split('?')[0];
  const full = path.join(ROOT, file);
  fs.readFile(full, (err, data) => {
    if (err) { res.writeHead(404); res.end('not found'); return; }
    res.writeHead(200, { 'content-type': MIME[path.extname(full)] || 'application/octet-stream' });
    res.end(data);
  });
});
server.listen(PORT, () => console.log('serving ' + ROOT + ' on http://localhost:' + PORT + ' (/api -> https://avalon.onl/api)'));

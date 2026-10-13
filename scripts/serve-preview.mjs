import { createServer } from 'node:http';
import { readFile, stat } from 'node:fs/promises';
import { resolve, extname, sep } from 'node:path';
const root = resolve('build/web');
const port = Number(process.argv[2] ?? 5173);
if (!Number.isInteger(port) || port < 1024 || port > 65535) {
  throw new Error('Preview port must be an integer between 1024 and 65535.');
}
const types = {'.html':'text/html; charset=utf-8','.js':'application/javascript','.json':'application/json','.wasm':'application/wasm','.png':'image/png','.jpg':'image/jpeg','.ttf':'font/ttf','.otf':'font/otf','.svg':'image/svg+xml'};
createServer(async (req,res) => {
  // Keep one callback origin for old local bookmarks and browser OAuth state.
  if (req.headers.host === `127.0.0.1:${port}`) {
    res.writeHead(307, {'Location': `http://localhost:${port}${req.url}`, 'Cache-Control':'no-store'});
    res.end();
    return;
  }
  try {
    let path = resolve(root, '.' + decodeURIComponent(new URL(req.url, 'http://localhost').pathname));
    if (path !== root && !path.startsWith(root + sep)) { res.writeHead(403); res.end(); return; }
    if (path === root || (await stat(path)).isDirectory()) path = resolve(path, 'index.html');
    res.writeHead(200, {'Content-Type': types[extname(path)] ?? 'application/octet-stream','Cache-Control':'no-store'});
    res.end(await readFile(path));
  } catch {
    // Browser OAuth returns to an application route handled by Flutter.
    if (new URL(req.url, 'http://localhost').pathname === '/auth/callback') {
      res.writeHead(200, {'Content-Type':'text/html; charset=utf-8','Cache-Control':'no-store'});
      res.end(await readFile(resolve(root, 'index.html')));
      return;
    }
    res.writeHead(404); res.end('Not found');
  }
}).listen(port,'127.0.0.1', () => console.log(`MSU Food preview: http://localhost:${port}`));

import { createServer } from 'node:http';
import { readFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const directory = fileURLToPath(new URL('../apps/godot/dist/', import.meta.url));
const port = Number(process.env.PORT || 4175);
const types = { '.html': 'text/html', '.js': 'application/javascript', '.wasm': 'application/wasm', '.pck': 'application/octet-stream', '.png': 'image/png' };
const server = createServer(async (request,response) => {
  try {
    const name = decodeURIComponent(new URL(request.url,'http://localhost').pathname);
    if (name === '/favicon.ico') { response.writeHead(204); response.end(); return; }
    const filename = path.resolve(directory, `.${name === '/' ? '/index.html' : name}`);
    if (!filename.startsWith(directory)) { response.writeHead(403); response.end(); return; }
    let bytes = await readFile(filename);
    // Local test override only; exported artifacts are never modified.
    if (filename.endsWith('index.html')) {
      const url = new URL(process.env.RALLY_PREVIEW_REALTIME_URL || 'ws://127.0.0.1:8787');
      if (!['ws:','wss:'].includes(url.protocol) || url.username || url.password) throw new Error('Invalid preview server URL');
      bytes = Buffer.from(bytes.toString().replace('const engine = new Engine(GODOT_CONFIG);',
        `GODOT_CONFIG.args = ${JSON.stringify(['--',`--server=${url.href}`])};\nconst engine = new Engine(GODOT_CONFIG);`));
    }
    response.writeHead(200, { 'Content-Type': types[path.extname(filename)] || 'application/octet-stream', 'Cache-Control':'no-store' });
    response.end(bytes);
  } catch { response.writeHead(404); response.end('Build the Godot web client first.'); }
});
server.listen(port,'127.0.0.1', () => console.log(`Godot web preview: http://127.0.0.1:${port}`));

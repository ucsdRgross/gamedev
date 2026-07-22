// Dependency-free dev server (PLAN §7). Static hosting for the app plus a small
// save/load API backed by palette/saved/*.json, so palettes survive browser clears
// and stay inspectable from tests and git.
//
//   GET    /api/saves          -> ["name", ...]        (sorted list of saved names)
//   GET    /api/saves/<name>   -> the saved JSON        (404 if absent)
//   PUT    /api/saves/<name>   <- JSON body, writes saved/<name>.json
//   DELETE /api/saves/<name>   -> removes saved/<name>.json
//
// Everything else is served as a static file from the repo root. Path traversal is
// refused: a resolved request path that escapes the root is a 403.

import { createServer } from 'node:http';
import { readFile, readdir, writeFile, unlink, stat } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { dirname, join, resolve, extname, normalize, sep } from 'node:path';

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const SAVES_DIR = join(ROOT, 'saved');

const MIME = {
  '.html': 'text/html; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.mjs': 'text/javascript; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.png': 'image/png',
  '.svg': 'image/svg+xml',
  '.ico': 'image/x-icon',
  '.txt': 'text/plain; charset=utf-8',
  '.map': 'application/json; charset=utf-8',
};

/** Restrict a save name to a safe basename — no extension, no separators, no traversal. */
export function safeSaveName(raw) {
  const name = String(raw || '').trim().replace(/\.json$/i, '');
  if (!/^[A-Za-z0-9 _-]{1,64}$/.test(name)) return null;
  return name;
}

/** Send a JSON response with the given status. */
function sendJson(res, status, data) {
  const body = JSON.stringify(data);
  res.writeHead(status, {
    'Content-Type': 'application/json; charset=utf-8',
    'Content-Length': Buffer.byteLength(body),
    'Cache-Control': 'no-store',
  });
  res.end(body);
}

/** Read a full request body as a string, capped so a runaway upload can't exhaust memory. */
function readBody(req, limit = 1 << 20) {
  return new Promise((resolvePromise, reject) => {
    let size = 0;
    const chunks = [];
    req.on('data', (c) => {
      size += c.length;
      if (size > limit) {
        reject(new Error('body too large'));
        req.destroy();
        return;
      }
      chunks.push(c);
    });
    req.on('end', () => resolvePromise(Buffer.concat(chunks).toString('utf8')));
    req.on('error', reject);
  });
}

/** List the names of every saved palette, without the .json extension, sorted. */
async function listSaves() {
  let files;
  try {
    files = await readdir(SAVES_DIR);
  } catch {
    return [];
  }
  return files
    .filter((f) => f.toLowerCase().endsWith('.json'))
    .map((f) => f.slice(0, -5))
    .sort((a, b) => a.localeCompare(b));
}

/** Handle every /api/saves request; returns true if the request was an API call. */
async function handleApi(req, res, pathname) {
  if (pathname === '/api/saves' || pathname === '/api/saves/') {
    if (req.method !== 'GET') {
      sendJson(res, 405, { error: 'method not allowed' });
      return true;
    }
    sendJson(res, 200, await listSaves());
    return true;
  }

  const rest = pathname.slice('/api/saves/'.length);
  const name = safeSaveName(decodeURIComponent(rest));
  if (!name) {
    sendJson(res, 400, { error: 'invalid save name' });
    return true;
  }
  const file = join(SAVES_DIR, `${name}.json`);

  if (req.method === 'GET') {
    try {
      const text = await readFile(file, 'utf8');
      res.writeHead(200, { 'Content-Type': 'application/json; charset=utf-8', 'Cache-Control': 'no-store' });
      res.end(text);
    } catch {
      sendJson(res, 404, { error: 'not found' });
    }
    return true;
  }

  if (req.method === 'PUT') {
    let body;
    try {
      body = await readBody(req);
      JSON.parse(body); // reject anything that is not valid JSON before it hits disk
    } catch {
      sendJson(res, 400, { error: 'body must be valid JSON' });
      return true;
    }
    await writeFile(file, body.endsWith('\n') ? body : `${body}\n`, 'utf8');
    sendJson(res, 200, { ok: true, name });
    return true;
  }

  if (req.method === 'DELETE') {
    try {
      await unlink(file);
      sendJson(res, 200, { ok: true, name });
    } catch {
      sendJson(res, 404, { error: 'not found' });
    }
    return true;
  }

  sendJson(res, 405, { error: 'method not allowed' });
  return true;
}

/** Resolve a URL path to a file inside ROOT, or null if it escapes the root. */
function resolveStatic(pathname) {
  const clean = decodeURIComponent(pathname.split('?')[0]);
  const rel = normalize(clean).replace(/^(\.\.[/\\])+/, '').replace(/^[/\\]+/, '');
  const abs = resolve(ROOT, rel === '' ? 'index.html' : rel);
  if (abs !== ROOT && !abs.startsWith(ROOT + sep)) return null;
  return abs;
}

/** Serve a static file, falling back to index.html for a bare directory request. */
async function handleStatic(req, res, pathname) {
  let file = resolveStatic(pathname);
  if (!file) {
    sendJson(res, 403, { error: 'forbidden' });
    return;
  }
  try {
    const info = await stat(file);
    if (info.isDirectory()) file = join(file, 'index.html');
    const data = await readFile(file);
    res.writeHead(200, {
      'Content-Type': MIME[extname(file).toLowerCase()] || 'application/octet-stream',
      'Content-Length': data.length,
      'Cache-Control': 'no-store',
    });
    res.end(req.method === 'HEAD' ? undefined : data);
  } catch {
    res.writeHead(404, { 'Content-Type': 'text/plain; charset=utf-8' });
    res.end('404 Not Found');
  }
}

/** Build the HTTP server without binding it — the test harness listens on port 0. */
export function createDevServer() {
  return createServer(async (req, res) => {
    try {
      const pathname = (req.url || '/').split('?')[0];
      if (pathname === '/api/saves' || pathname.startsWith('/api/saves/')) {
        await handleApi(req, res, pathname);
        return;
      }
      if (req.method !== 'GET' && req.method !== 'HEAD') {
        sendJson(res, 405, { error: 'method not allowed' });
        return;
      }
      await handleStatic(req, res, pathname);
    } catch (err) {
      sendJson(res, 500, { error: String(err && err.message ? err.message : err) });
    }
  });
}

/** Start listening. Only runs when invoked directly, not when imported by a test. */
function main() {
  const port = Number(process.env.PORT) || 5173;
  const server = createDevServer();
  server.listen(port, () => {
    const addr = server.address();
    const shown = typeof addr === 'object' && addr ? addr.port : port;
    process.stdout.write(`palette dev server → http://localhost:${shown}\n`);
  });
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  main();
}

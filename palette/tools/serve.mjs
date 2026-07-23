// Dependency-free dev server (PLAN §7). Static hosting for the app plus a small
// save/load API backed by palette/saved/*.json, so palettes survive browser clears
// and stay inspectable from tests and git.
//
//   GET    /api/saves          -> ["name", ...]        (sorted list of saved names)
//   GET    /api/saves/<name>   -> the saved JSON        (404 if absent)
//   PUT    /api/saves/<name>   <- JSON body, writes saved/<name>.json
//   DELETE /api/saves/<name>   -> removes saved/<name>.json
//
//   GET    /api/reference          -> ["file.png", ...]  (sorted list of image files)
//   PUT    /api/reference/<file>   <- raw image bytes, writes reference/<file>
//   GET    /api/palettes           -> ["file.png", ...]  (sorted list of palette images)
//   PUT    /api/palettes/<file>    <- raw image bytes, writes palettes/<file>
//
//   GET    /api/ping           -> { app: 'palette-creator', pid, port }
//   POST   /api/shutdown       -> stops this server (loopback callers only)
//
// ping/shutdown exist so `start.cmd` can be double-clicked repeatedly: a second run finds
// the first, asks it to stand down, and takes the port back. See `main()`.
//
// `reference/` is the user's art library for the recolour gallery; `palettes/` is their
// library of palette images to recolour *into* (PLAN §19.5). Both are read back through
// ordinary static hosting — `/reference/<file>`, `/palettes/<file>` — so only listing and
// writing need an endpoint, and one handler serves both folders.
//
// Everything else is served as a static file from the repo root. Path traversal is
// refused: a resolved request path that escapes the root is a 403.

import { createServer } from 'node:http';
import { readFile, readdir, writeFile, unlink, stat, mkdir } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { dirname, join, resolve, extname, normalize, sep } from 'node:path';
import { spawn } from 'node:child_process';

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const SAVES_DIR = join(ROOT, 'saved');
const REFERENCE_DIR = join(ROOT, 'reference');
const PALETTES_DIR = join(ROOT, 'palettes');

/** Image types the reference and palette folders accept. Anything else is refused. */
const IMAGE_EXTS = ['.png', '.jpg', '.jpeg', '.gif'];
const MAX_IMAGE_BYTES = 16 << 20;

/**
 * The two image-asset folders behind their APIs. `reference/` holds images to recolour;
 * `palettes/` holds palette images to recolour *into*. One handler serves both — they differ
 * only in which folder they touch — so the path-traversal guard cannot drift between them.
 */
const ASSETS = {
  '/api/reference': REFERENCE_DIR,
  '/api/palettes': PALETTES_DIR,
};

const MIME = {
  '.html': 'text/html; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.mjs': 'text/javascript; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.jpeg': 'image/jpeg',
  '.gif': 'image/gif',
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

/**
 * Restrict an image-asset filename to a safe basename plus an allowed image extension.
 * Deliberately built on `safeSaveName` rather than beside it — one traversal guard in the
 * codebase, not two that can drift apart.
 */
export function safeReferenceName(raw) {
  const file = String(raw || '').trim();
  const ext = extname(file).toLowerCase();
  if (!IMAGE_EXTS.includes(ext)) return null;
  const base = safeSaveName(file.slice(0, -ext.length));
  return base ? `${base}${ext}` : null;
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

/** Read a full request body as a Buffer, capped so a runaway upload can't exhaust memory. */
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
    req.on('end', () => resolvePromise(Buffer.concat(chunks)));
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
      body = (await readBody(req)).toString('utf8');
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

/**
 * Handle an image-asset request against one folder (reference images or palette images).
 * `prefix` is the route base (`/api/reference`), `dir` the folder it maps to.
 */
async function handleAssetApi(req, res, pathname, prefix, dir) {
  if (pathname === prefix || pathname === `${prefix}/`) {
    if (req.method !== 'GET') {
      sendJson(res, 405, { error: 'method not allowed' });
      return;
    }
    let files = [];
    try {
      files = (await readdir(dir)).filter((f) => IMAGE_EXTS.includes(extname(f).toLowerCase()));
    } catch {
      files = []; // the folder simply does not exist yet
    }
    sendJson(res, 200, files.sort((a, b) => a.localeCompare(b)));
    return;
  }

  const name = safeReferenceName(decodeURIComponent(pathname.slice(`${prefix}/`.length)));
  if (!name) {
    sendJson(res, 400, { error: 'invalid image name' });
    return;
  }

  if (req.method === 'PUT') {
    let body;
    try {
      body = await readBody(req, MAX_IMAGE_BYTES);
    } catch {
      sendJson(res, 413, { error: 'image too large' });
      return;
    }
    if (!body.length) {
      sendJson(res, 400, { error: 'empty body' });
      return;
    }
    await mkdir(dir, { recursive: true });
    await writeFile(join(dir, name), body);
    sendJson(res, 200, { ok: true, name });
    return;
  }

  if (req.method === 'DELETE') {
    try {
      await unlink(join(dir, name));
      sendJson(res, 200, { ok: true, name });
    } catch {
      sendJson(res, 404, { error: 'not found' });
    }
    return;
  }

  sendJson(res, 405, { error: 'method not allowed' });
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

/** Only a caller on this machine may ask the server to stop. */
function isLoopback(req) {
  const addr = req.socket.remoteAddress || '';
  return addr === '127.0.0.1' || addr === '::1' || addr === '::ffff:127.0.0.1';
}

/**
 * Build the HTTP server without binding it — the test harness listens on port 0.
 * `onShutdown` is what `POST /api/shutdown` calls; without it the route does not exist,
 * so a server embedded in a test cannot be told to stop.
 */
export function createDevServer({ onShutdown = null } = {}) {
  return createServer(async (req, res) => {
    try {
      const pathname = (req.url || '/').split('?')[0];
      if (pathname === '/api/ping') {
        sendJson(res, 200, { app: 'palette-creator', pid: process.pid, port: req.socket.localPort });
        return;
      }
      if (pathname === '/api/shutdown') {
        if (!onShutdown) {
          sendJson(res, 404, { error: 'not found' });
        } else if (req.method !== 'POST') {
          sendJson(res, 405, { error: 'method not allowed' });
        } else if (!isLoopback(req)) {
          sendJson(res, 403, { error: 'forbidden' });
        } else {
          sendJson(res, 200, { ok: true, stopping: true });
          // Reply first, then stand down, so the caller knows it was heard.
          setTimeout(onShutdown, 20);
        }
        return;
      }
      if (pathname === '/api/saves' || pathname.startsWith('/api/saves/')) {
        await handleApi(req, res, pathname);
        return;
      }
      for (const [prefix, dir] of Object.entries(ASSETS)) {
        if (pathname === prefix || pathname.startsWith(`${prefix}/`)) {
          await handleAssetApi(req, res, pathname, prefix, dir);
          return;
        }
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

/**
 * Open a URL in the user's browser. Needed by `--open`, which is what lets `start.cmd` be a
 * double-click rather than a command line (PLAN §19.5) — the server has to be listening
 * before the browser asks for the page, so it opens from here rather than from the script.
 */
function openBrowser(url) {
  const [cmd, args] = process.platform === 'win32'
    ? ['cmd', ['/c', 'start', '', url]]
    : process.platform === 'darwin' ? ['open', [url]] : ['xdg-open', [url]];
  try {
    spawn(cmd, args, { detached: true, stdio: 'ignore' }).unref();
  } catch {
    process.stdout.write('could not open a browser automatically\n');
  }
}

/** Ask whoever holds a port to identify itself. `null` means nothing answered. */
async function probe(port) {
  try {
    const res = await fetch(`http://127.0.0.1:${port}/api/ping`, { signal: AbortSignal.timeout(600) });
    return res.ok ? await res.json() : {};
  } catch {
    return null;
  }
}

/** Ask a previous instance to stand down, and wait for it to actually let go of the port. */
async function replaceExisting(port) {
  const existing = await probe(port);
  if (existing?.app !== 'palette-creator') {
    // Either the port is free, or something that is not us has it. Never kill a stranger's
    // server just because it picked the same port — 5173 is a popular number. The listen
    // retry below moves us out of the way instead.
    return existing === null;
  }
  process.stdout.write(`replacing the palette server already on port ${port} (pid ${existing.pid})\n`);
  try {
    await fetch(`http://127.0.0.1:${port}/api/shutdown`, { method: 'POST', signal: AbortSignal.timeout(1000) });
  } catch {
    // An older build with no shutdown route. Fall through: the retry finds another port.
  }
  for (let i = 0; i < 20; i++) {
    if (await probe(port) === null) return true;
    await new Promise((r) => setTimeout(r, 100));
  }
  return false;
}

/** Listen on `port`, stepping to the next one if something else already has it. */
function listenFrom(server, port, attempts = 20) {
  return new Promise((resolvePromise, reject) => {
    let current = port;
    let left = attempts;
    const onError = (err) => {
      if (err.code !== 'EADDRINUSE' || left-- <= 0) {
        reject(err);
        return;
      }
      current += 1;
      server.listen(current);
    };
    server.on('error', onError);
    server.once('listening', () => {
      server.off('error', onError);
      resolvePromise(current);
    });
    server.listen(current);
  });
}

/** Start listening. Only runs when invoked directly, not when imported by a test. */
async function main() {
  const port = Number(process.env.PORT) || 5173;

  // `start.cmd` passes --replace, because being double-clicked again is how the app gets
  // restarted. Without it a second run would just die on EADDRINUSE.
  if (process.argv.includes('--replace')) await replaceExisting(port);

  let server;
  const stop = () => {
    // `close` releases the listening socket at once — that is what the replacement waits
    // for — but its callback only fires once every open connection has finished, and a
    // keep-alive socket (the browser's, or the replacement's own probe, which `fetch`
    // pools) would otherwise hold it open. `closeAllConnections` drops those; the timer is
    // a backstop, because a process being replaced must not outlive the handover.
    server.close(() => process.exit(0));
    server.closeAllConnections?.();
    setTimeout(() => process.exit(0), 500);
  };
  server = createDevServer({ onShutdown: stop });

  const bound = await listenFrom(server, port);
  const url = `http://localhost:${bound}`;
  if (bound !== port) process.stdout.write(`port ${port} is taken by something else\n`);
  process.stdout.write(`palette dev server → ${url}\n`);
  if (process.argv.includes('--open')) openBrowser(url);
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  main();
}

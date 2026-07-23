// Dev-server API tests. The server is booted on an ephemeral port and driven over
// real HTTP, so this exercises routing, the saves CRUD cycle, and path-traversal
// refusal exactly as the browser would hit them.

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFile, unlink, readdir } from 'node:fs/promises';
import { spawn } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { dirname, join, resolve } from 'node:path';
import { createDevServer, safeReferenceName, safeSaveName } from '../tools/serve.mjs';

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const SAVES_DIR = join(ROOT, 'saved');
const REFERENCE_DIR = join(ROOT, 'reference');
const TEST_NAME = '__servetest_tmp';

/** Boot the server on port 0 and return its base URL plus a close function. */
async function boot() {
  const server = createDevServer();
  await new Promise((res) => server.listen(0, '127.0.0.1', res));
  const { port } = server.address();
  return { base: `http://127.0.0.1:${port}`, close: () => new Promise((r) => server.close(r)) };
}

test('safeSaveName accepts clean names and rejects traversal', () => {
  assert.equal(safeSaveName('My Palette-1'), 'My Palette-1');
  assert.equal(safeSaveName('foo.json'), 'foo');
  assert.equal(safeSaveName('../secret'), null);
  assert.equal(safeSaveName('a/b'), null);
  assert.equal(safeSaveName(''), null);
  assert.equal(safeSaveName('x'.repeat(65)), null);
});

test('static hosting serves index.html at the root', async () => {
  const { base, close } = await boot();
  try {
    const res = await fetch(`${base}/`);
    assert.equal(res.status, 200);
    assert.match(res.headers.get('content-type') || '', /text\/html/);
    const body = await res.text();
    assert.match(body, /<html/i);
  } finally {
    await close();
  }
});

test('path traversal outside the root is refused', async () => {
  const { base, close } = await boot();
  try {
    const res = await fetch(`${base}/../../package.json`);
    // Either normalised back into the root (404/served index) or refused, never the
    // parent's package.json.
    if (res.status === 200) {
      const body = await res.text();
      assert.doesNotMatch(body, /"name"\s*:\s*"palette-creator"[\s\S]*node_modules/);
    } else {
      assert.ok(res.status === 403 || res.status === 404);
    }
  } finally {
    await close();
  }
});

test('saves API round-trips PUT -> list -> GET -> DELETE', async () => {
  const { base, close } = await boot();
  const file = join(SAVES_DIR, `${TEST_NAME}.json`);
  try {
    const payload = { format: 'pixel-palette/1', seed: 'PAL1-TEST', note: 'hi' };

    const put = await fetch(`${base}/api/saves/${TEST_NAME}`, {
      method: 'PUT',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(payload),
    });
    assert.equal(put.status, 200);

    // It really landed on disk as a .json file.
    const onDisk = JSON.parse(await readFile(file, 'utf8'));
    assert.equal(onDisk.seed, 'PAL1-TEST');

    const list = await (await fetch(`${base}/api/saves`)).json();
    assert.ok(list.includes(TEST_NAME));

    const got = await (await fetch(`${base}/api/saves/${TEST_NAME}`)).json();
    assert.deepEqual(got, payload);

    const del = await fetch(`${base}/api/saves/${TEST_NAME}`, { method: 'DELETE' });
    assert.equal(del.status, 200);

    const listAfter = await (await fetch(`${base}/api/saves`)).json();
    assert.ok(!listAfter.includes(TEST_NAME));
  } finally {
    try { await unlink(file); } catch { /* already gone */ }
    await close();
  }
});

test('a non-JSON PUT body is rejected and nothing is written', async () => {
  const { base, close } = await boot();
  const file = join(SAVES_DIR, `${TEST_NAME}_bad.json`);
  try {
    const res = await fetch(`${base}/api/saves/${TEST_NAME}_bad`, {
      method: 'PUT',
      body: 'not json {',
    });
    assert.equal(res.status, 400);
    const names = await readdir(SAVES_DIR);
    assert.ok(!names.includes(`${TEST_NAME}_bad.json`));
  } finally {
    try { await unlink(file); } catch { /* expected */ }
    await close();
  }
});

test('an invalid save name is a 400', async () => {
  const { base, close } = await boot();
  try {
    const res = await fetch(`${base}/api/saves/${encodeURIComponent('../evil')}`, {
      method: 'PUT',
      body: '{}',
    });
    assert.equal(res.status, 400);
  } finally {
    await close();
  }
});

test('GET of a missing save is a 404', async () => {
  const { base, close } = await boot();
  try {
    const res = await fetch(`${base}/api/saves/__definitely_absent__`);
    assert.equal(res.status, 404);
  } finally {
    await close();
  }
});

test('safeReferenceName keeps the extension and still refuses traversal', () => {
  assert.equal(safeReferenceName('sprite sheet.png'), 'sprite sheet.png');
  assert.equal(safeReferenceName('walk.GIF'), 'walk.gif');
  assert.equal(safeReferenceName('photo.JPEG'), 'photo.jpeg');
  assert.equal(safeReferenceName('../../etc/passwd.png'), null);
  assert.equal(safeReferenceName('a/b.png'), null);
  assert.equal(safeReferenceName('script.js'), null, 'only image extensions are accepted');
  assert.equal(safeReferenceName('noext'), null);
  assert.equal(safeReferenceName('x'.repeat(65) + '.png'), null);
});

test('reference API round-trips an image and serves it back statically', async () => {
  const { base, close } = await boot();
  const name = `${TEST_NAME}.png`;
  const bytes = Uint8Array.from([137, 80, 78, 71, 13, 10, 26, 10, 1, 2, 3, 4]);
  try {
    const put = await fetch(`${base}/api/reference/${name}`, { method: 'PUT', body: bytes });
    assert.equal(put.status, 200);

    const list = await (await fetch(`${base}/api/reference`)).json();
    assert.ok(list.includes(name), `expected ${name} in ${JSON.stringify(list)}`);

    // Read back through ordinary static hosting, which is how the gallery loads it.
    const got = await fetch(`${base}/reference/${name}`);
    assert.equal(got.status, 200);
    assert.equal(got.headers.get('content-type'), 'image/png');
    assert.deepEqual([...new Uint8Array(await got.arrayBuffer())], [...bytes]);

    const del = await fetch(`${base}/api/reference/${name}`, { method: 'DELETE' });
    assert.equal(del.status, 200);
    assert.ok(!(await readdir(REFERENCE_DIR)).includes(name));
  } finally {
    try { await unlink(join(REFERENCE_DIR, name)); } catch { /* already removed */ }
    await close();
  }
});

test('the palettes API is a second folder behind the same handler', async () => {
  const { base, close } = await boot();
  const name = `${TEST_NAME}.png`;
  const PALETTES_DIR = join(ROOT, 'palettes');
  const bytes = Uint8Array.from([137, 80, 78, 71, 13, 10, 26, 10, 9, 9, 9]);
  try {
    const put = await fetch(`${base}/api/palettes/${name}`, { method: 'PUT', body: bytes });
    assert.equal(put.status, 200);
    assert.ok((await (await fetch(`${base}/api/palettes`)).json()).includes(name));

    // Served statically from /palettes, exactly like /reference.
    const got = await fetch(`${base}/palettes/${name}`);
    assert.equal(got.status, 200);
    assert.deepEqual([...new Uint8Array(await got.arrayBuffer())], [...bytes]);

    // It is a distinct folder — a palette upload does not appear in the reference list.
    assert.ok(!(await (await fetch(`${base}/api/reference`)).json()).includes(name));

    assert.equal((await fetch(`${base}/api/palettes/${name}`, { method: 'DELETE' })).status, 200);
  } finally {
    try { await unlink(join(PALETTES_DIR, name)); } catch { /* already removed */ }
    await close();
  }
});

test('the reference API refuses a bad name and an empty body', async () => {
  const { base, close } = await boot();
  try {
    const bad = await fetch(`${base}/api/reference/${encodeURIComponent('../evil.png')}`, {
      method: 'PUT',
      body: Uint8Array.from([1]),
    });
    assert.equal(bad.status, 400);

    const empty = await fetch(`${base}/api/reference/${TEST_NAME}.png`, { method: 'PUT', body: new Uint8Array(0) });
    assert.equal(empty.status, 400);

    const notImage = await fetch(`${base}/api/reference/evil.js`, { method: 'PUT', body: Uint8Array.from([1]) });
    assert.equal(notImage.status, 400);
  } finally {
    await close();
  }
});

test('a server identifies itself on /api/ping', async () => {
  const { base, close } = await boot();
  try {
    const res = await fetch(`${base}/api/ping`);
    assert.equal(res.status, 200);
    const body = await res.json();
    assert.equal(body.app, 'palette-creator');
    assert.equal(body.pid, process.pid);
    assert.ok(body.port > 0);
  } finally {
    await close();
  }
});

test('/api/shutdown does not exist unless the server was given a way to stop', async () => {
  // The test harness embeds the server, so a stray shutdown request must not be able to
  // stop it. Only the standalone `main()` wires the route up.
  const { base, close } = await boot();
  try {
    assert.equal((await fetch(`${base}/api/shutdown`, { method: 'POST' })).status, 404);
    assert.equal((await fetch(`${base}/api/ping`)).status, 200, 'still alive');
  } finally {
    await close();
  }
});

test('/api/shutdown stops a server that has one, and refuses a GET', async () => {
  let stopped = false;
  const server = createDevServer({ onShutdown: () => { stopped = true; } });
  await new Promise((res) => server.listen(0, '127.0.0.1', res));
  const base = `http://127.0.0.1:${server.address().port}`;
  try {
    assert.equal((await fetch(`${base}/api/shutdown`)).status, 405, 'GET must not stop the server');
    assert.equal(stopped, false);

    const res = await fetch(`${base}/api/shutdown`, { method: 'POST' });
    assert.equal(res.status, 200);
    assert.deepEqual(await res.json(), { ok: true, stopping: true });
    // The reply is sent before the shutdown runs, so give the timer a tick.
    await new Promise((r) => setTimeout(r, 60));
    assert.equal(stopped, true);
  } finally {
    await new Promise((r) => server.close(r));
  }
});

test('a second server started with --replace takes the port from the first', async () => {
  // The double-click-again path, exercised end to end against two real processes.
  const script = join(ROOT, 'tools', 'serve.mjs');
  const port = 5100 + Math.floor(Math.random() * 700);
  const env = { ...process.env, PORT: String(port) };

  const started = (child) => new Promise((res, rej) => {
    let out = '';
    child.stdout.on('data', (d) => {
      out += d.toString();
      if (out.includes('palette dev server')) res(out);
    });
    child.on('error', rej);
    setTimeout(() => rej(new Error(`server did not start: ${out}`)), 10000);
  });

  const first = spawn(process.execPath, [script], { env, stdio: ['ignore', 'pipe', 'pipe'] });
  // Captured immediately: the handover is fast enough that `exit` can fire before the
  // replacement has finished starting, and a listener attached afterwards never sees it.
  const firstExited = new Promise((res) => first.once('exit', res));
  let second;
  try {
    await started(first);
    const before = await (await fetch(`http://127.0.0.1:${port}/api/ping`)).json();
    assert.equal(before.pid, first.pid);

    second = spawn(process.execPath, [script, '--replace'], { env, stdio: ['ignore', 'pipe', 'pipe'] });
    const log = await started(second);
    assert.match(log, new RegExp(`replacing the palette server already on port ${port}`));
    assert.match(log, new RegExp(`http://localhost:${port}`), 'the replacement must reuse the port');

    const after = await (await fetch(`http://127.0.0.1:${port}/api/ping`)).json();
    assert.equal(after.pid, second.pid, 'the new process should now own the port');
    assert.notEqual(after.pid, before.pid);

    // …and the one it replaced is gone, not left running in the background.
    const code = await Promise.race([
      firstExited,
      new Promise((_, rej) => setTimeout(() => rej(new Error('the replaced server did not exit')), 5000)),
    ]);
    assert.equal(code, 0, 'the replaced server should exit cleanly');
  } finally {
    first.kill();
    second?.kill();
  }
});

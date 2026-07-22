// Dev-server API tests. The server is booted on an ephemeral port and driven over
// real HTTP, so this exercises routing, the saves CRUD cycle, and path-traversal
// refusal exactly as the browser would hit them.

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFile, unlink, readdir } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { dirname, join, resolve } from 'node:path';
import { createDevServer, safeSaveName } from '../tools/serve.mjs';

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const SAVES_DIR = join(ROOT, 'saved');
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

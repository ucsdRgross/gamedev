// PLAN S1 — the server serves, answers /api/ping, and hands its port over on /api/shutdown.

import test from 'node:test';
import assert from 'node:assert/strict';
import { createDevServer, listenFrom } from '../src/server.mjs';

/** Start a server on an ephemeral port and return `{ url, close }`. */
async function serve({ onShutdown = null } = {}) {
  const server = createDevServer({ onShutdown });
  const port = await listenFrom(server, 0);
  return {
    url: `http://127.0.0.1:${port}`,
    port,
    close: () => new Promise((r) => { server.closeAllConnections?.(); server.close(r); }),
  };
}

test('ping identifies the app so a second launch can reclaim the port', async () => {
  const s = await serve();
  try {
    const res = await fetch(`${s.url}/api/ping`);
    assert.equal(res.status, 200);
    const body = await res.json();
    assert.equal(body.app, 'designloop');
    assert.equal(body.pid, process.pid);
  } finally {
    await s.close();
  }
});

test('/ redirects to the index, and the index is served', async () => {
  const s = await serve();
  try {
    const res = await fetch(`${s.url}/`, { redirect: 'manual' });
    assert.equal(res.status, 302);
    assert.equal(res.headers.get('location'), '/web/index.html');
    const page = await fetch(`${s.url}/web/index.html`);
    assert.equal(page.status, 200);
    assert.match(await page.text(), /Design Loop/);
  } finally {
    await s.close();
  }
});

test('the browser can import the shared parser straight from src/', async () => {
  const s = await serve();
  try {
    const res = await fetch(`${s.url}/src/grammar.mjs`);
    assert.equal(res.status, 200);
    assert.match(res.headers.get('content-type'), /javascript/);
  } finally {
    await s.close();
  }
});

test('nothing outside web/ and src/ is reachable, traversal included', async () => {
  const s = await serve();
  try {
    for (const path of ['/package.json', '/test/server.test.mjs', '/../package.json', '/src/../package.json']) {
      const res = await fetch(`${s.url}${path}`);
      assert.equal(res.status, 404, `${path} should not be served`);
    }
  } finally {
    await s.close();
  }
});

test('shutdown only exists when a stop hook was given, and only for POST', async () => {
  const bare = await serve();
  try {
    assert.equal((await fetch(`${bare.url}/api/shutdown`, { method: 'POST' })).status, 404);
  } finally {
    await bare.close();
  }

  let stopped = false;
  const s = await serve({ onShutdown: () => { stopped = true; } });
  try {
    assert.equal((await fetch(`${s.url}/api/shutdown`)).status, 405);
    const res = await fetch(`${s.url}/api/shutdown`, { method: 'POST' });
    assert.equal(res.status, 200);
    assert.equal((await res.json()).stopping, true);
    await new Promise((r) => setTimeout(r, 60));
    assert.equal(stopped, true, 'the stop hook runs after the reply');
  } finally {
    await s.close();
  }
});

test('an unknown API path is a JSON 404, not an HTML one', async () => {
  const s = await serve();
  try {
    const res = await fetch(`${s.url}/api/nope`);
    assert.equal(res.status, 404);
    assert.equal((await res.json()).error, 'no such endpoint');
  } finally {
    await s.close();
  }
});

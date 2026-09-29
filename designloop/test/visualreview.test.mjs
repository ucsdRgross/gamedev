// The visual review: the page and images served from `<project>/visual-review/`, a verdict is on
// disk (log, then review.json) before the 200, and Done wakes a watch parked on the folder.

import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, mkdir, writeFile, readFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const ROOT = await mkdtemp(join(tmpdir(), 'designloop-review-'));
process.env.DESIGNLOOP_ROOT = ROOT;
const { createDevServer, listenFrom } = await import('../src/server.mjs');
const { readJson, writeJsonAtomic } = await import('../src/store.mjs');
const { watchOwner, reviewReport, resolveTarget } = await import('../src/watch.mjs');

const DIR = join(ROOT, 'demoproject', 'visual-review');
const PNG = Buffer.from('89504e470d0a1a0a', 'hex');

async function fixture() {
  await rm(DIR, { recursive: true, force: true });
  await mkdir(join(DIR, 'after'), { recursive: true });
  await writeFile(join(DIR, 'index.html'), '<!doctype html><title>review</title>', 'utf8');
  await writeFile(join(DIR, 'after', 'one.png'), PNG);
  await writeJsonAtomic(join(DIR, 'manifest.json'), {
    shots: [
      { id: 'one', title: 'The first', row: 'P1', scene: 'res://a.tscn', env: {}, png: 'user://a.png', seen: 'a board',
        crops: [{ label: 'the rim', x: 1, y: 2, w: 3, h: 4 }] },
      { id: 'two', title: 'The second', row: 'P2', scene: 'res://b.tscn', env: {}, png: 'user://b.png', seen: 'a sidebar' },
    ],
  });
}

async function serve() {
  const server = createDevServer();
  const port = await listenFrom(server, 0);
  const url = `http://127.0.0.1:${port}`;
  return {
    url,
    post: (p, body) => fetch(`${url}/api/visual-review/demoproject${p}`, {
      method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body || {}),
    }).then(async (r) => ({ status: r.status, body: await r.json() })),
    close: () => new Promise((r) => { server.closeAllConnections?.(); server.close(r); }),
  };
}

test('the page and the images are served from the project folder, and nothing outside it', async () => {
  await fixture();
  const s = await serve();
  try {
    const page = await fetch(`${s.url}/visual-review/demoproject/`);
    assert.equal(page.status, 200);
    assert.match(await page.text(), /<title>review/);
    const img = await fetch(`${s.url}/visual-review/demoproject/after/one.png`);
    assert.equal(img.headers.get('content-type'), 'image/png');
    assert.deepEqual(Buffer.from(await img.arrayBuffer()), PNG);
    assert.equal((await fetch(`${s.url}/visual-review/demoproject/before/one.png`)).status, 404);
    await writeFile(join(ROOT, 'secret.txt'), 'outside', 'utf8');
    assert.equal((await fetch(`${s.url}/visual-review/demoproject/..%2f..%2fsecret.txt`)).status, 404);
  } finally {
    await s.close();
  }
});

test('the API reports the manifest, the verdicts and which side of each pair exists', async () => {
  await fixture();
  const s = await serve();
  try {
    const got = await fetch(`${s.url}/api/visual-review/demoproject`).then((r) => r.json());
    assert.deepEqual(got.manifest.shots.map((shot) => shot.id), ['one', 'two']);
    assert.deepEqual(got.review, { shots: {} });
    assert.deepEqual(got.manifest.shots[0].crops, [{ label: 'the rim', x: 1, y: 2, w: 3, h: 4 }]);
    assert.ok(got.files.one.after, 'after/one.png exists');
    assert.equal(got.files.one.before, null, 'no before/one.png: the page shows "no before"');
    assert.equal(got.files.two.after, null);
    assert.equal((await fetch(`${s.url}/api/visual-review/nosuch`)).status, 404);
  } finally {
    await s.close();
  }
});

test('a verdict is appended to review.log and materialised in review.json before the 200', async () => {
  await fixture();
  const s = await serve();
  try {
    assert.equal((await s.post('/verdict', { id: 'one', verdict: 'approve', comment: '' })).status, 200);
    const reject = await s.post('/verdict', { id: 'two', verdict: 'reject', comment: 'the rim is too thin' });
    assert.equal(reject.status, 200);
    const review = await readJson(join(DIR, 'review.json'));
    assert.equal(review.shots.one.verdict, 'approve');
    assert.equal(review.shots.two.verdict, 'reject');
    assert.equal(review.shots.two.comment, 'the rim is too thin');
    const log = (await readFile(join(DIR, 'review.log'), 'utf8')).trim().split('\n').map((l) => JSON.parse(l));
    assert.deepEqual(log.map((e) => [e.id, e.verdict]), [['one', 'approve'], ['two', 'reject']]);

    assert.equal((await s.post('/verdict', { id: 'one', verdict: 'maybe' })).status, 400);
    assert.equal((await s.post('/verdict', { id: 'nine', verdict: 'approve' })).status, 400);
    assert.equal((await readFile(join(DIR, 'review.log'), 'utf8')).trim().split('\n').length, 2,
      'a refused verdict writes nothing');
  } finally {
    await s.close();
  }
});

test('Done wakes a watch parked on the folder, and a refresh after it parks the next one again', async () => {
  await fixture();
  const s = await serve();
  try {
    const target = await resolveTarget(ROOT, 'visual-review/demoproject');
    assert.equal(target.dir, DIR);
    await writeJsonAtomic(join(DIR, 'status.agent.json'), { state: 'ready', mode: 'visual-review', at: '2000-01-01T00:00:00Z' });
    const parked = watchOwner(DIR);
    await s.post('/verdict', { id: 'two', verdict: 'comment', comment: 'darker' });
    setTimeout(() => s.post('/done'), 80);
    const status = await parked;
    assert.equal(status.state, 'done');
    assert.equal(status.reason, 'reviewed');
    const report = await reviewReport(DIR, 'visual-review/demoproject');
    assert.match(report, /comment\s+two — "darker"/);
    assert.match(report, /unreviewed\s+one/);

    await writeJsonAtomic(join(DIR, 'status.agent.json'), { state: 'ready', mode: 'visual-review', at: '2999-01-01T00:00:00Z' });
    const again = await watchOwner(DIR, { timeoutMs: 400 });
    assert.equal(again, null, 'a Done the worker has already refreshed after does not wake it again');
  } finally {
    await s.close();
  }
});

test('the index lists each review with its current-shoot verdicts and whether it waits on the owner', async () => {
  await fixture();
  const s = await serve();
  try {
    await writeJsonAtomic(join(DIR, 'status.agent.json'), { state: 'ready', mode: 'visual-review', at: '2026-01-01T00:00:00Z' });
    await writeJsonAtomic(join(DIR, 'review.json'), { shots: {
      one: { verdict: 'approve', comment: '', at: '2000-01-01T00:00:00Z' },
      two: { verdict: 'reject', comment: 'thin', at: '2000-01-01T00:00:00Z' },
    } });
    const list = () => fetch(`${s.url}/api/visual-reviews`).then((r) => r.json());
    const [row] = (await list()).filter((r) => r.project === 'demoproject');
    assert.equal(row.shots, 2);
    assert.deepEqual(row.counts, { approve: 0, reject: 1, comment: 0 }, 'the approve was given on an older after');
    assert.equal(row.shot_at, '2026-01-01T00:00:00Z');
    assert.equal(row.done, false);
    assert.equal(row.waiting, true);

    await s.post('/verdict', { id: 'one', verdict: 'comment', comment: 'darker' });
    await s.post('/done');
    const [after] = (await list()).filter((r) => r.project === 'demoproject');
    assert.deepEqual(after.counts, { approve: 0, reject: 1, comment: 1 });
    assert.equal(after.done, true);
    assert.equal(after.waiting, false);
  } finally {
    await s.close();
  }
});

/** Run the real review page's script against a stub DOM and the given API payload. */
async function openPage(data) {
  const html = await readFile(join(import.meta.dirname, '..', '..', 'solatro', 'visual-review', 'index.html'), 'utf8');
  const script = html.match(/<script>([\s\S]*)<\/script>/)[1];
  const elements = {};
  const element = () => ({ value: '', textContent: '', className: '', innerHTML: '', replaceChildren() {}, append() {}, blur() {}, focus() {} });
  const document = {
    getElementById: (id) => (elements[id] ||= element()),
    addEventListener() {},
  };
  const fetch = async () => ({ ok: true, json: async () => data });
  new Function('document', 'fetch', 'location', script)(document, fetch, { pathname: '/visual-review/demoproject/' });
  await new Promise((r) => setTimeout(r, 0));
  return elements;
}

test('the page pre-fills a current verdict\'s comment and leaves the box empty for one given on an older after', async () => {
  const manifest = { shots: [{ id: 'one', title: 'The first', row: 'P1', seen: 'a board' }] };
  const review = { shots: { one: { verdict: 'comment', comment: 'darker', at: '2026-01-02T00:00:00Z' } } };
  const current = await openPage({ manifest, review, files: { one: { after: '2026-01-01T00:00:00Z' } } });
  assert.equal(current.comment.value, 'darker');
  const stale = await openPage({ manifest, review, files: { one: { after: '2026-01-03T00:00:00Z' } } });
  assert.equal(stale.comment.value, '', 'a new after starts with an empty comment');
  assert.match(stale.verdict.textContent, /older after.*darker/, 'the old comment is still shown, read-only');
});

test.after(() => rm(ROOT, { recursive: true, force: true }));

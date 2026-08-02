// PLAN S3 + S5–S8 — the JSON API of §4.8, driven end to end over HTTP against a throwaway design.

import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, mkdir, writeFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const ROOT = await mkdtemp(join(tmpdir(), 'designloop-repo-'));
process.env.DESIGNLOOP_ROOT = ROOT;
const { createDevServer, listenFrom } = await import('../src/server.mjs');
const { readJson } = await import('../src/store.mjs');

const DIR = join(ROOT, 'demoproject', 'design', 'demo');

/** A four-question design: one ⚑gate, one section gated on it, one plain question. */
const DOC = `# Demo

## 1 roots

- **QR1** \`[root]\` ⚑gate — Which path? · **(a)** wide — opens the detail — **→ next:** the detail questions · **(b)** narrow — skips them — **→ next:** nothing more · *default* (a)
- **Q1** \`[root]\` — A plain one · **(a)** yes · **(b)** no · *default* (a)

## 2 detail \`[QR1=a]\`

- **Q2** \`[root]\` — Detail one · **(a)** yes · **(b)** no · *default* (a)
- **Q3** \`[root]\` — Detail two · **(a)** yes · **(b)** no · *default* (a)
`;

async function fixture() {
  await rm(DIR, { recursive: true, force: true });
  await mkdir(DIR, { recursive: true });
  await writeFile(join(DIR, 'DESIGN.md'), DOC, 'utf8');
  await writeFile(join(DIR, 'meta.json'), JSON.stringify({
    slug: 'demo', title: 'A demo design', projects: ['demoproject'], doc: 'DESIGN.md',
    created: '2026-08-01T00:00:00Z', rounds: 1, confirmed_version: null,
  }, null, 2), 'utf8');
}

async function serve() {
  const server = createDevServer();
  const port = await listenFrom(server, 0);
  const url = `http://127.0.0.1:${port}`;
  return {
    url,
    get: (p) => fetch(`${url}/api/designs/demoproject/demo${p}`).then((r) => r.json()),
    post: (p, body) => fetch(`${url}/api/designs/demoproject/demo${p}`, {
      method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body || {}),
    }).then(async (r) => ({ status: r.status, body: await r.json() })),
    close: () => new Promise((r) => { server.closeAllConnections?.(); server.close(r); }),
  };
}

test('the index lists a design under every project it touches', async () => {
  await fixture();
  const s = await serve();
  try {
    const list = await fetch(`${s.url}/api/designs`).then((r) => r.json());
    const demo = list.find((d) => d.key === 'demoproject/demo');
    assert.ok(demo, 'the scan finds <project>/design/<slug>/meta.json');
    assert.equal(demo.title, 'A demo design');
    assert.equal(demo.owner.state, 'answering');
    assert.equal(demo.agent.state, 'idle');
    assert.equal(demo.answered, 0);
    assert.ok(demo.touched, 'last touched is reported');
  } finally {
    await s.close();
  }
});

test('a round runs to the end and hands the turn to the agent', async () => {
  await fixture();
  const s = await serve();
  try {
    assert.equal((await s.get('/next')).question.id, 'QR1', 'roots come first');

    let r = await s.post('/answer', { id: 'QR1', state: 'chosen', option: 'a' });
    assert.equal(r.status, 200);
    assert.equal(r.body.owner.state, 'answering');
    assert.equal(r.body.next.id, 'Q2', 'the gated section is heavier than the ungated one (§5.5)');

    await s.post('/answer', { id: 'Q2', state: 'defaulted', option: 'a' });
    await s.post('/answer', { id: 'Q3', state: 'not_relevant', option: 'a' });
    r = await s.post('/answer', { id: 'Q1', state: 'chosen', option: 'b' });
    assert.equal(r.body.done, true);
    assert.equal(r.body.owner.state, 'done');
    assert.equal(r.body.owner.reason, 'complete');

    const next = await s.get('/next');
    assert.equal(next.done, true);
    assert.deepEqual((await readJson(join(DIR, 'status.owner.json'))).reason, 'complete');
  } finally {
    await s.close();
  }
});

test('answering the gate the other way prunes the section entirely', async () => {
  await fixture();
  const s = await serve();
  try {
    const r = await s.post('/answer', { id: 'QR1', state: 'chosen', option: 'b' });
    assert.equal(r.body.next.id, 'Q1', 'Q2 and Q3 are gone, not merely later');
    await s.post('/answer', { id: 'Q1', state: 'chosen', option: 'a' });
    assert.equal((await s.get('/next')).done, true);
  } finally {
    await s.close();
  }
});

test('re-answering previews its blast radius before applying, then strands and restores', async () => {
  await fixture();
  const s = await serve();
  try {
    await s.post('/answer', { id: 'QR1', state: 'chosen', option: 'a' });
    await s.post('/answer', { id: 'Q2', state: 'chosen', option: 'a', note: 'typed by hand' });
    await s.post('/answer', { id: 'Q3', state: 'chosen', option: 'b' });

    const preview = await s.post('/reanswer?preview=1', { id: 'QR1', state: 'chosen', option: 'b' });
    assert.deepEqual(preview.body.strand.map((x) => x.id), ['Q2', 'Q3']);
    assert.equal(preview.body.preview, true);
    assert.equal((await readJson(join(DIR, 'answers.json'))).answers.Q2.active, true, 'a preview writes nothing');

    const applied = await s.post('/reanswer', { id: 'QR1', state: 'chosen', option: 'b' });
    assert.deepEqual(applied.body.strand, ['Q2', 'Q3']);
    let saved = (await readJson(join(DIR, 'answers.json'))).answers;
    assert.equal(saved.Q2.active, false);
    assert.equal(saved.Q2.note, 'typed by hand', 'kept, not deleted (Q35)');

    const back = await s.post('/reanswer', { id: 'QR1', state: 'chosen', option: 'a' });
    assert.deepEqual(back.body.restore, ['Q2', 'Q3']);
    saved = (await readJson(join(DIR, 'answers.json'))).answers;
    assert.equal(saved.Q2.active, true);
    assert.equal(saved.Q2.note, 'typed by hand');
    assert.equal(saved.Q3.option, 'b', 'and it comes back as the answer it was');
  } finally {
    await s.close();
  }
});

test('free text at a ⚑gate ends the round immediately (chart B2)', async () => {
  await fixture();
  const s = await serve();
  try {
    const r = await s.post('/answer', {
      id: 'QR1', state: 'chosen', override: true, note: 'neither — I want a third thing',
    });
    assert.equal(r.body.owner.state, 'done');
    assert.equal(r.body.owner.reason, 'new_branch_needed');
    // The asymmetry that matters: reachable questions remain, and the round has ended anyway.
    assert.equal((await s.get('/next')).done, false, 'questions remain — the UI stops on the status');
    const saved = (await readJson(join(DIR, 'answers.json'))).answers.QR1;
    assert.equal(saved.override, true);
    assert.equal(saved.option, null);
    assert.equal(saved.note, 'neither — I want a third thing');
  } finally {
    await s.close();
  }
});

test('free text on an ORDINARY question is an override that keeps the round going', async () => {
  await fixture();
  const s = await serve();
  try {
    await s.post('/answer', { id: 'QR1', state: 'chosen', option: 'a' });
    const r = await s.post('/answer', { id: 'Q2', state: 'chosen', override: true, note: 'something else' });
    assert.equal(r.body.owner.state, 'answering');
    assert.equal(r.body.next.id, 'Q3');
  } finally {
    await s.close();
  }
});

test('the round-2 handshake: agent ready, then the UI takes the turn back', async () => {
  await fixture();
  const s = await serve();
  try {
    await s.post('/answer', { id: 'QR1', state: 'chosen', option: 'b' });
    await s.post('/answer', { id: 'Q1', state: 'chosen', option: 'a' });
    assert.equal((await s.get('')).owner.state, 'done');

    // The agent half — written by the agent, never by the UI.
    await writeFile(join(DIR, 'status.agent.json'), JSON.stringify({
      state: 'ready', mode: 'questions', round: 2, at: '2026-08-01T00:00:00Z',
      summary: 'Your answer to QR1 opened these',
    }, null, 2), 'utf8');

    const seen = await s.get('');
    assert.equal(seen.agent.state, 'ready');
    assert.equal(seen.agent.summary, 'Your answer to QR1 opened these');

    const resumed = await s.post('/resume');
    assert.equal(resumed.body.owner.state, 'answering');
    assert.equal(resumed.body.owner.round, 2);
    assert.equal(resumed.body.owner.reason, null);
  } finally {
    await s.close();
  }
});

test('history is in answer order and says what each answer was', async () => {
  await fixture();
  const s = await serve();
  try {
    await s.post('/answer', { id: 'QR1', state: 'chosen', option: 'a' });
    await s.post('/answer', { id: 'Q2', state: 'defaulted', option: 'a' });
    const history = await s.get('/history');
    assert.deepEqual(history.map((h) => h.id), ['QR1', 'Q2']);
    assert.equal(history[0].isGate, true);
    assert.equal(history[0].label, 'wide');
    assert.equal(history[1].state, 'defaulted');
  } finally {
    await s.close();
  }
});

test('a bad answer is refused, and nothing is written', async () => {
  await fixture();
  const s = await serve();
  try {
    assert.equal((await s.post('/answer', { id: 'Q99', option: 'a' })).status, 400);
    assert.equal((await s.post('/answer', { id: 'QR1', option: 'z' })).status, 400);
    assert.equal(await readJson(join(DIR, 'answers.json')), null, 'nothing on disk');
  } finally {
    await s.close();
  }
});

test('the browser can fetch the document it parses with the shared module', async () => {
  await fixture();
  const s = await serve();
  try {
    const text = await fetch(`${s.url}/api/designs/demoproject/demo/doc`).then((r) => r.text());
    assert.equal(text, DOC);
  } finally {
    await s.close();
  }
});

test.after(async () => {
  await rm(ROOT, { recursive: true, force: true });
});

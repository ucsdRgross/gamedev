// PLAN S4 — durability. The gate for this step is the crash test at the bottom: a process that
// dies between the log append and the materialise must be recovered by replay.

import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, rm, readFile, writeFile, appendFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import {
  load, answer, commit, append, materialise, materialiseShape, writeJsonAtomic, annotate, hashDoc, readJson,
} from '../src/store.mjs';

/** A throwaway design directory. */
async function dir() {
  return mkdtemp(join(tmpdir(), 'designloop-'));
}

test('an answer is on disk in both files before it is acknowledged', async () => {
  const d = await dir();
  try {
    await answer(d, { id: 'QR1', state: 'chosen', option: 'a', round: 1 }, { slug: 'spotlight' });

    const log = (await readFile(join(d, 'answers.log'), 'utf8')).trim().split('\n');
    assert.equal(log.length, 1);
    assert.deepEqual(JSON.parse(log[0]).id, 'QR1');

    const json = await readJson(join(d, 'answers.json'));
    assert.equal(json.slug, 'spotlight');
    assert.deepEqual(Object.keys(json.answers), ['QR1']);
    assert.deepEqual(json.answers.QR1, {
      state: 'chosen', option: 'a', note: '', override: false, active: true, round: 1, at: json.answers.QR1.at,
    });
  } finally {
    await rm(d, { recursive: true, force: true });
  }
});

test('the three answer states are distinguishable on disk (Q108)', async () => {
  const d = await dir();
  try {
    await answer(d, { id: 'Q1', state: 'chosen', option: 'a' });
    await answer(d, { id: 'Q2', state: 'defaulted', option: 'b' });
    await answer(d, { id: 'Q3', state: 'not_relevant', option: 'a' });
    await answer(d, { id: 'Q4', state: 'chosen', option: null, override: true, note: 'what I actually want' });
    const s = await load(d);
    assert.deepEqual(
      ['Q1', 'Q2', 'Q3', 'Q4'].map((id) => s.answers[id].state),
      ['chosen', 'defaulted', 'not_relevant', 'chosen'],
    );
    assert.equal(s.answers.Q4.override, true);
    assert.equal(s.answers.Q4.option, null);
    assert.equal(s.answers.Q4.note, 'what I actually want');
  } finally {
    await rm(d, { recursive: true, force: true });
  }
});

test('seq is strictly increasing across every event', async () => {
  const d = await dir();
  try {
    await answer(d, { id: 'Q1', state: 'chosen', option: 'a' }, { strand: ['Q2', 'Q3'] });
    await answer(d, { id: 'Q4', state: 'chosen', option: 'b' }, { restore: ['Q2'] });
    const seqs = (await readFile(join(d, 'answers.log'), 'utf8')).trim().split('\n').map((l) => JSON.parse(l).seq);
    assert.deepEqual(seqs, [1, 2, 3, 4]);
  } finally {
    await rm(d, { recursive: true, force: true });
  }
});

test('stranded answers go inactive and come back intact (Q35)', async () => {
  const d = await dir();
  try {
    await answer(d, { id: 'Q73', state: 'chosen', option: 'a', note: 'typed by hand' });
    await answer(d, { id: 'QR2', state: 'chosen', option: 'b' }, { strand: ['Q73'] });
    let s = await load(d);
    assert.equal(s.answers.Q73.active, false);
    assert.equal(s.answers.Q73.note, 'typed by hand', 'nothing typed is ever lost');

    await answer(d, { id: 'QR2', state: 'chosen', option: 'a' }, { restore: ['Q73'] });
    s = await load(d);
    assert.equal(s.answers.Q73.active, true);
    assert.equal(s.answers.Q73.note, 'typed by hand');
  } finally {
    await rm(d, { recursive: true, force: true });
  }
});

test('answers.json is fully rebuildable from the log alone (§4.4)', async () => {
  const d = await dir();
  try {
    await answer(d, { id: 'QR1', state: 'chosen', option: 'a' }, { slug: 'spotlight' });
    await answer(d, { id: 'QR3', state: 'defaulted', option: 'c' }, { strand: ['QR1'] });
    const before = await readJson(join(d, 'answers.json'));

    await rm(join(d, 'answers.json'));
    const replayed = materialiseShape(await load(d, { slug: 'spotlight' }));
    assert.deepEqual(replayed.answers, before.answers);
  } finally {
    await rm(d, { recursive: true, force: true });
  }
});

test('a hand-edited answers.json with no log is read as-is (chart I5)', async () => {
  const d = await dir();
  try {
    await writeJsonAtomic(join(d, 'answers.json'), {
      slug: 'x', doc_hash: null, updated: '2026-08-01T00:00:00Z',
      answers: { Q1: { state: 'chosen', option: 'b', note: '', override: false, active: true, round: 1, at: '2026-08-01T00:00:00Z' } },
    });
    const s = await load(d);
    assert.equal(s.answers.Q1.option, 'b');
  } finally {
    await rm(d, { recursive: true, force: true });
  }
});

test('a torn final log line is dropped, not fatal', async () => {
  const d = await dir();
  try {
    await answer(d, { id: 'Q1', state: 'chosen', option: 'a' });
    await appendFile(join(d, 'answers.log'), '{"seq":2,"event":"answer","id":"Q2","sta');
    const s = await load(d);
    assert.deepEqual(Object.keys(s.answers), ['Q1'], 'the half-written answer was never acknowledged');
  } finally {
    await rm(d, { recursive: true, force: true });
  }
});

test('an annotation survives a restart (F7)', async () => {
  const d = await dir();
  try {
    await annotate(d, 'node', 'D6', 'split this into two');
    await annotate(d, 'edge', 'D6->D7', 'should be conditional');
    const a = await readJson(join(d, 'annotations.json'));
    assert.equal(a.nodes.D6[0].text, 'split this into two');
    assert.equal(a.edges['D6->D7'][0].text, 'should be conditional');
  } finally {
    await rm(d, { recursive: true, force: true });
  }
});

test('doc_hash changes when the document changes under the answers', () => {
  assert.notEqual(hashDoc('a'), hashDoc('b'));
  assert.match(hashDoc('a'), /^sha256:[0-9a-f]{64}$/);
});

// --- THE S4 GATE ------------------------------------------------------------------------------

test('a crash between the log append and the materialise is recovered by replay', async () => {
  const d = await dir();
  try {
    // Two answers land normally.
    await answer(d, { id: 'QR1', state: 'chosen', option: 'a' }, { slug: 'spotlight' });
    await answer(d, { id: 'QR2', state: 'chosen', option: 'b' }, { slug: 'spotlight' });
    const survived = await readJson(join(d, 'answers.json'));
    assert.deepEqual(Object.keys(survived.answers), ['QR1', 'QR2']);

    // The third one is simulated exactly as the crash window of §4.4 leaves it: the append and its
    // fsync completed, and the process died before `materialise` ran. Nothing else is touched —
    // answers.json is byte-for-byte what it was one answer ago.
    await append(d, [{
      seq: 3, at: '2026-08-01T12:00:00Z', event: 'answer',
      id: 'QR3', state: 'chosen', option: 'a', note: 'the one that must not be lost', override: false, round: 1,
    }]);
    assert.deepEqual(
      await readJson(join(d, 'answers.json')),
      survived,
      'precondition: the materialised file is stale, exactly as a crash would leave it',
    );

    // Restart. The loader replays the log and finds the answer the materialised file never got.
    const recovered = await load(d, { slug: 'spotlight' });
    assert.equal(recovered.recovered, true, 'the loader must NOTICE that it recovered');
    assert.deepEqual(Object.keys(recovered.answers), ['QR1', 'QR2', 'QR3']);
    assert.equal(recovered.answers.QR3.note, 'the one that must not be lost');
    assert.equal(recovered.seq, 3, 'and the next answer does not reuse a sequence number');

    // Writing again heals the materialised file, and a second load is clean.
    await materialise(d, recovered);
    const healed = await load(d, { slug: 'spotlight' });
    assert.equal(healed.recovered, false);
    assert.deepEqual(Object.keys((await readJson(join(d, 'answers.json'))).answers), ['QR1', 'QR2', 'QR3']);

    // And the recovered state is the one the next answer builds on, not the stale file.
    await commit(d, [{ event: 'answer', id: 'QR4', state: 'chosen', option: 'a' }], { slug: 'spotlight' });
    const after = await load(d);
    assert.equal(after.seq, 4);
    assert.deepEqual(Object.keys(after.answers), ['QR1', 'QR2', 'QR3', 'QR4']);
  } finally {
    await rm(d, { recursive: true, force: true });
  }
});

test('a crash between the two fsyncs cannot lose an answer the owner was shown as saved', async () => {
  const d = await dir();
  try {
    // Answers acknowledged to the owner are the ones whose POST returned; each of those has both
    // a log line and a materialise. Simulate a truncated answers.json (a partial write that the
    // temp+rename is designed to prevent, forced here to prove the log is the authority anyway).
    await answer(d, { id: 'Q1', state: 'chosen', option: 'a' });
    await answer(d, { id: 'Q2', state: 'chosen', option: 'b' });
    await writeFile(join(d, 'answers.json'), '{"slug":"x","answers":{"Q1"', 'utf8');

    const s = await load(d);
    assert.deepEqual(Object.keys(s.answers), ['Q1', 'Q2'], 'the log rebuilds what the corrupt file lost');
    assert.equal(s.recovered, true);
  } finally {
    await rm(d, { recursive: true, force: true });
  }
});

// PLAN S9 — the agent parked on the watch wakes within a second of the last answer.

import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, rm, mkdir, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { watchOwner, claim, heartbeat } from '../src/watch.mjs';
import { writeJsonAtomic, readJson } from '../src/store.mjs';
import { readSession } from '../src/registry.mjs';

async function design() {
  const dir = join(await mkdtemp(join(tmpdir(), 'designloop-watch-')), 'demo');
  await mkdir(dir, { recursive: true });
  await writeJsonAtomic(join(dir, 'status.owner.json'), {
    state: 'answering', reason: null, round: 1, at: '2026-08-01T00:00:00Z',
  });
  return dir;
}

test('the watch wakes within a second of the owner finishing', async () => {
  const dir = await design();
  try {
    const started = Date.now();
    const parked = watchOwner(dir);
    // The owner answers the last reachable question a moment later.
    setTimeout(() => {
      writeJsonAtomic(join(dir, 'status.owner.json'), {
        state: 'done', reason: 'complete', round: 1, at: '2026-08-01T00:01:00Z',
      });
    }, 120);
    const status = await parked;
    const elapsed = Date.now() - started;
    assert.equal(status.state, 'done');
    assert.equal(status.reason, 'complete');
    assert.ok(elapsed < 1000, `woke in ${elapsed}ms, must be under a second`);
  } finally {
    await rm(dir, { recursive: true, force: true });
  }
});

test('the free-text-at-a-gate ending wakes it just the same', async () => {
  const dir = await design();
  try {
    const parked = watchOwner(dir);
    setTimeout(() => {
      writeJsonAtomic(join(dir, 'status.owner.json'), {
        state: 'done', reason: 'new_branch_needed', round: 1, at: '2026-08-01T00:01:00Z',
      });
    }, 80);
    assert.equal((await parked).reason, 'new_branch_needed');
  } finally {
    await rm(dir, { recursive: true, force: true });
  }
});

test('a round that ended before the agent parked returns at once', async () => {
  const dir = await design();
  try {
    await writeJsonAtomic(join(dir, 'status.owner.json'), {
      state: 'done', reason: 'complete', round: 1, at: '2026-08-01T00:00:00Z',
    });
    const status = await watchOwner(dir, { timeoutMs: 2000 });
    assert.equal(status.state, 'done', 'the owner finishing first must not strand the agent');
  } finally {
    await rm(dir, { recursive: true, force: true });
  }
});

test('an owner who stops halfway is not a timeout — the watch just waits (Q23=a)', async () => {
  const dir = await design();
  try {
    const status = await watchOwner(dir, { timeoutMs: 400 });
    assert.equal(status, null, 'nothing changed, so nothing is reported');
  } finally {
    await rm(dir, { recursive: true, force: true });
  }
});

test('waking claims the agent half, and never touches the owner half', async () => {
  const dir = await design();
  try {
    const before = await readJson(join(dir, 'status.owner.json'));
    await claim(dir, { state: 'working', round: 2 });
    const agent = await readJson(join(dir, 'status.agent.json'));
    assert.equal(agent.state, 'working');
    assert.equal(agent.round, 2);
    assert.deepEqual(await readJson(join(dir, 'status.owner.json')), before, 'one writer per file');
  } finally {
    await rm(dir, { recursive: true, force: true });
  }
});

test('a design directory that does not exist yet fails loudly, not silently', async () => {
  await assert.rejects(watchOwner(join(tmpdir(), 'designloop-nope-' + Date.now()), { pollMs: 50 }));
});

// --- is anyone listening? (S19.7, §4.9) ---------------------------------------------------------
//
// The owner could answer a whole round into a directory nobody was watching and have no way to
// tell. `session.json` is the watch's heartbeat, and the case that matters is the one where NOBODY
// got to clean up: a killed process, a crashed one, a chat session that simply ended.

test('a parked watch says so, and a session that ended goes stale on its own', async () => {
  const dir = await design();
  try {
    const stop = heartbeat(dir, { intervalMs: 40, key: 'demo/demo' });
    await new Promise((r) => setTimeout(r, 60));

    const beating = await readSession(dir);
    assert.equal(beating.watching, true, 'a live watch reads as watching');
    assert.equal(beating.stale, false);
    assert.ok(beating.since, 'and says how long it has been parked');

    // The heartbeat stops WITHOUT the process getting to tidy up — the whole point.
    await stop();
    const raw = await readJson(join(dir, 'session.json'));
    await writeJsonAtomic(join(dir, 'session.json'), {
      ...raw, watching: true, at: new Date(Date.now() - 60_000).toISOString(), every_ms: 5000,
    });

    const abandoned = await readSession(dir);
    assert.equal(abandoned.watching, false, 'an old heartbeat is not a live session');
    assert.equal(abandoned.stale, true, 'and it is reported as one that STOPPED, not one that never was');
  } finally {
    await rm(dir, { recursive: true, force: true });
  }
});

test('a design nobody has ever watched is not reported as a session that died', async () => {
  const dir = await design();
  try {
    const never = await readSession(dir);
    assert.deepEqual(
      { watching: never.watching, stale: never.stale, ever: never.ever },
      { watching: false, stale: false, ever: false },
      'no file at all means "no agent is watching", never "the session stopped"',
    );
  } finally {
    await rm(dir, { recursive: true, force: true });
  }
});

test('a clean shutdown is immediate, not a 20-second wait for staleness', async () => {
  const dir = await design();
  try {
    const stop = heartbeat(dir, { intervalMs: 40, key: 'demo/demo' });
    await new Promise((r) => setTimeout(r, 60));
    await stop();
    const after = await readSession(dir);
    assert.equal(after.watching, false);
    assert.equal(after.stale, false, 'it said goodbye, so there is nothing to report as broken');
  } finally {
    await rm(dir, { recursive: true, force: true });
  }
});

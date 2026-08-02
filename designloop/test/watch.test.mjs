// PLAN S9 — the agent parked on the watch wakes within a second of the last answer.

import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, rm, mkdir, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { watchOwner, claim } from '../src/watch.mjs';
import { writeJsonAtomic, readJson } from '../src/store.mjs';

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

// How the agent finds out you are done (PLAN S9; DESIGN chart E, QR1=c, Q20–Q23).
//
//   npm --prefix designloop run watch -- solatro/spotlight
//
// The agent session parks on this. It blocks — no polling loop in the transcript, no "check back
// in five minutes" — and returns the moment `status.owner.json` changes, printing what happened
// and setting the agent half to `working` so the UI can see it was picked up.
//
// ⚠ This is the one mechanism with no precedent in this repo (DESIGN §2, chart E). It is therefore
// built so that its failure is harmless: **telling the agent in chat always works** (Q22=a). If
// the watch dies, hangs, or is never started, nothing is lost — every answer is already on disk
// and a fresh session reads it with `load()`. Never make this the only route.
//
// It waits forever by default (Q23=a: an owner who stops halfway is not a timeout). `--timeout`
// exists for scripts, not for the owner.

import { watch as fsWatch } from 'node:fs';
import { stat } from 'node:fs/promises';
import { join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { readJson, writeJsonAtomic, load, now } from './store.mjs';
import { find, DEFAULT_OWNER_STATUS } from './registry.mjs';

const TOOL_ROOT = resolve(fileURLToPath(new URL('..', import.meta.url)));
const REPO_ROOT = resolve(process.env.DESIGNLOOP_ROOT || resolve(TOOL_ROOT, '..'));

/** Read the owner half, with the defaults filled in. */
async function ownerStatus(dir) {
  return { ...DEFAULT_OWNER_STATUS, ...(await readJson(join(dir, 'status.owner.json'))) };
}

/** True when two owner statuses describe a different situation. */
function changed(a, b) {
  return a.state !== b.state || a.reason !== b.reason || a.round !== b.round;
}

/**
 * Block until the owner's half of the status changes, and return the new one.
 *
 * `fs.watch` is the fast path and a 250 ms poll is the backstop — file watching is the least
 * portable thing in Node, and a watch that silently stops firing would strand an agent for as long
 * as the owner is willing to wait. Both paths lead to the same check.
 */
export function watchOwner(dir, { pollMs = 250, timeoutMs = 0, signal = null } = {}) {
  return new Promise((resolvePromise, reject) => {
    let baseline = null;
    let done = false;
    let watcher = null;
    let timer = null;
    let deadline = null;

    const finish = (value, err) => {
      if (done) return;
      done = true;
      watcher?.close();
      clearInterval(timer);
      clearTimeout(deadline);
      if (err) reject(err);
      else resolvePromise(value);
    };

    const check = async () => {
      if (done) return;
      try {
        // A missing directory is a typo in the design key, not an owner who is slow. Waiting
        // forever on one is the worst failure this tool could have, so it is the loud one.
        if (!(await stat(dir)).isDirectory()) throw new Error(`${dir} is not a directory`);
        const current = await ownerStatus(dir);
        if (baseline === null) {
          baseline = current;
          // Already done when the watch started: the owner finished before the agent parked.
          if (current.state === 'done') finish(current);
          return;
        }
        if (changed(baseline, current)) finish(current);
      } catch (err) {
        finish(null, err);
      }
    };

    signal?.addEventListener('abort', () => finish(null, new Error('watch aborted')), { once: true });
    if (timeoutMs > 0) deadline = setTimeout(() => finish(null), timeoutMs);

    check().then(() => {
      if (done) return;
      try {
        watcher = fsWatch(dir, { persistent: true }, (_event, name) => {
          if (!name || String(name).startsWith('status.owner')) check();
        });
        watcher.on('error', () => { watcher = null; });  // the poll carries on alone
      } catch {
        watcher = null;
      }
      timer = setInterval(check, pollMs);
    });
  });
}

/** What the agent needs to read next, printed rather than made it go looking. */
async function report(design, status) {
  const state = await load(design.dir, { slug: design.slug });
  const answers = Object.entries(state.answers).filter(([, a]) => a.active !== false);
  const flagged = answers.filter(([, a]) => a.state !== 'chosen');
  const overrides = answers.filter(([, a]) => a.override);

  const lines = [
    '',
    `${design.key} — the owner's turn ended`,
    `  state       ${status.state}${status.reason ? ` (${status.reason})` : ''}`,
    `  round       ${status.round}`,
    `  answered    ${answers.length} active`,
  ];
  if (flagged.length) {
    lines.push(`  unreviewed  ${flagged.length} — ${flagged.map(([id, a]) => `${id}:${a.state}`).join(', ')}`);
  }
  if (overrides.length) {
    lines.push(`  own answers ${overrides.length} — ${overrides.map(([id]) => id).join(', ')}`);
  }
  if (status.reason === 'new_branch_needed') {
    lines.push('', '  The round ended at a ⚑gate the owner answered in their own words. Author the new',
      '  branch: add their answer as a real option on that question, plus whatever it opens, then',
      '  set status.agent.json to ready. They resume at that same question (chart B2, P7).');
  }
  lines.push('', `  answers     ${join(design.dir, 'answers.json')}`, '');
  process.stdout.write(`${lines.join('\n')}\n`);
}

/**
 * The heartbeat that tells the OWNER whether anyone is listening (§4.9).
 *
 * Everything else in this file answers "has the owner finished?". This answers the question from
 * the other side, which until now the tool could not answer at all: the owner sat on a question
 * screen with no way to know whether an agent was parked, whether its session had ended, or what
 * to do about it. A watch that is running says so every few seconds; a watch that was killed,
 * crashed, or whose chat session simply ended stops saying it, and the file goes stale on its own.
 *
 * Staleness, not a clean shutdown flag, is the signal on purpose: the failure this exists to
 * report is a process that did NOT get to run its exit handler.
 */
const HEARTBEAT_MS = 5000;

export function heartbeat(dir, { intervalMs = HEARTBEAT_MS, key = null } = {}) {
  const path = join(dir, 'session.json');
  const since = now();
  const beat = () => writeJsonAtomic(path, {
    watching: true, key, pid: process.pid, since, at: now(), every_ms: intervalMs,
  }).catch(() => {});
  beat();
  const timer = setInterval(beat, intervalMs);
  timer.unref?.();
  const stop = async () => {
    clearInterval(timer);
    // Best effort, and never load-bearing: if this never runs, the file goes stale and the UI says
    // the same thing a beat later.
    await writeJsonAtomic(path, { watching: false, key, pid: process.pid, since, at: now(), every_ms: intervalMs }).catch(() => {});
  };
  for (const signal of ['SIGINT', 'SIGTERM']) {
    process.once(signal, () => { stop().then(() => process.exit(0)); });
  }
  return stop;
}

/** Tell the UI the agent picked it up. `status.agent.json` is agent-owned, so this is ours (§4.2). */
export async function claim(dir, patch) {
  const current = (await readJson(join(dir, 'status.agent.json'))) || {};
  const next = { state: 'working', mode: 'questions', round: 1, ...current, ...patch, at: now() };
  await writeJsonAtomic(join(dir, 'status.agent.json'), next);
  return next;
}

async function main() {
  const args = process.argv.slice(2).filter((a) => a !== '--');
  const target = args.find((a) => !a.startsWith('-'));
  if (!target) {
    process.stdout.write('usage: npm --prefix designloop run watch -- <project>/<slug> [--timeout <seconds>]\n');
    process.exit(2);
  }
  const design = await find(REPO_ROOT, target);
  if (!design) {
    process.stdout.write(`no design at "${target}" — expected <project>/design/<slug>/meta.json\n`);
    process.exit(1);
  }
  const timeoutArg = args.indexOf('--timeout');
  const timeoutMs = timeoutArg >= 0 ? Number(args[timeoutArg + 1]) * 1000 : 0;

  process.stdout.write(`watching ${design.key} — waiting for the owner. Ctrl-C, or just tell me in chat.\n`);
  // The owner's screen shows this as "an agent is parked on this design" (§4.9). It is the only
  // way they can tell a live session from one that ended while they were mid-question.
  const stopHeartbeat = heartbeat(design.dir, { key: design.key });
  const status = await watchOwner(design.dir, { timeoutMs });
  if (!status) {
    await stopHeartbeat();
    process.stdout.write('timed out; nothing has changed\n');
    process.exit(3);
  }
  await report(design, status);
  await claim(design.dir, { state: 'working', round: status.round });
  // The watch returning means the agent is now WORKING, not watching. `status.agent.json` carries
  // that; this file is only ever about whether someone is parked.
  await stopHeartbeat();
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  main();
}

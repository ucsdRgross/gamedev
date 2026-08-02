// The durable answer store (PLAN S4, §4.3, §4.4, §7; DESIGN chart B12, Q80–Q82).
//
// The rule, and it is the whole point of this module:
//
//     append to answers.log → fsync → rewrite answers.json → fsync → THEN respond 200
//
// A crash anywhere in that sequence leaves the log ahead of the materialised file, never behind,
// so `load()` replaying the log always reproduces at least as much as the owner was told was saved.
// The UI never advances on a failed write (chart I7), which is only true if this module throws
// rather than swallowing.
//
// `answers.log` and `answers.json` are UI-owned. Nothing agent-side writes them, so there is no
// lock, no merge, and no read-modify-write of a shared file (PLAN §2).

import { open, readFile, writeFile, rename, mkdir, readdir, stat } from 'node:fs/promises';
import { createHash } from 'node:crypto';
import { join } from 'node:path';

const LOG = 'answers.log';
const ANSWERS = 'answers.json';
const ANNOTATIONS = 'annotations.json';

/** ISO-8601 UTC, the timestamp format every file in §4 uses. */
export function now() {
  return new Date().toISOString().replace(/\.\d+Z$/, 'Z');
}

/** `sha256:…` of a string — the `doc_hash` that says which DESIGN.md the answers were given to. */
export function hashDoc(text) {
  return `sha256:${createHash('sha256').update(text, 'utf8').digest('hex')}`;
}

/** Read a JSON file, or `null` if it is absent or unreadable. */
export async function readJson(path) {
  try {
    return JSON.parse(await readFile(path, 'utf8'));
  } catch {
    return null;
  }
}

/**
 * Write JSON durably: temp file → fsync → rename (§4). The rename is atomic, so a reader either
 * sees the whole old file or the whole new one, and the fsync is what makes that true after a
 * power cut rather than only after a process crash.
 */
export async function writeJsonAtomic(path, obj) {
  const body = `${JSON.stringify(obj, null, 2)}\n`;
  const tmp = `${path}.tmp`;
  const fh = await open(tmp, 'w');
  try {
    await fh.writeFile(body, 'utf8');
    await fh.sync();
  } finally {
    await fh.close();
  }
  await renameWithRetry(tmp, path);
}

/**
 * `rename` over an existing file, retried.
 *
 * On Windows a replacing rename fails with EPERM/EACCES whenever anything else holds the
 * destination or its directory open for a moment — and this tool guarantees exactly that: the
 * agent's watch (S9) has the design directory open while the UI writes into it. Measured, not
 * theorised: it fired on the first run of the watch test. The rename is still atomic; only the
 * moment it happens moves.
 */
async function renameWithRetry(from, to, attempts = 20) {
  for (let i = 0; ; i++) {
    try {
      await rename(from, to);
      return;
    } catch (err) {
      const transient = err.code === 'EPERM' || err.code === 'EACCES' || err.code === 'EBUSY';
      if (!transient || i >= attempts) throw err;
      await new Promise((r) => setTimeout(r, 10 + i * 5));
    }
  }
}

/**
 * Append events to `answers.log` and fsync (§4.4). One JSON object per line, `seq` strictly
 * increasing. This returns only once the bytes are on the platter — everything after it in the
 * sequence is recoverable, everything before it never happened.
 */
export async function append(dir, events) {
  const list = Array.isArray(events) ? events : [events];
  if (!list.length) return;
  const body = `${list.map((e) => JSON.stringify(e)).join('\n')}\n`;
  await mkdir(dir, { recursive: true });
  const fh = await open(join(dir, LOG), 'a');
  try {
    await fh.writeFile(body, 'utf8');
    await fh.sync();
  } finally {
    await fh.close();
  }
}

/**
 * An empty state, so a design with no answers loads the same shape as one with them.
 * `order` is the sequence the questions were first answered in — the history list (Q33) is that
 * path, so re-answering a question keeps its original place rather than jumping to the end.
 * It is derived, not stored: `answers.json` is exactly §4.3 and nothing more.
 */
function emptyState(slug = '') {
  return { slug, doc_hash: null, updated: null, answers: {}, order: [], seq: 0 };
}

/** Apply one log event to a state. This function IS the recovery contract of §4.4. */
export function applyEvent(state, event) {
  switch (event.event) {
    case 'answer':
      state.answers[event.id] = {
        state: event.state,
        option: event.option ?? null,
        note: event.note ?? '',
        override: event.override ?? false,
        active: true,
        round: event.round ?? 1,
        at: event.at,
      };
      if (!state.order.includes(event.id)) state.order.push(event.id);
      break;
    case 'strand':
    case 'restore':
      for (const id of event.ids || []) {
        if (state.answers[id]) state.answers[id].active = event.active !== false;
      }
      break;
    case 'meta':
      if (event.doc_hash) state.doc_hash = event.doc_hash;
      if (event.slug) state.slug = event.slug;
      break;
    default:
      // An event kind from a newer build. Skipping it is safer than guessing what it meant.
      break;
  }
  if (typeof event.seq === 'number' && event.seq > state.seq) state.seq = event.seq;
  if (event.at) state.updated = event.at;
  return state;
}

/**
 * Load a design's answers. The log is authoritative: it is written first, so after a crash between
 * the append and the materialise it is the only place the last answer exists. `answers.json` is
 * used only when there is no log at all — the hand-edited case (chart I5).
 *
 * Returns `{ ...state, recovered }`; `recovered` is true when the replay disagreed with the
 * materialised file, which is exactly the crash this step exists to survive.
 */
export async function load(dir, { slug = '' } = {}) {
  const materialised = await readJson(join(dir, ANSWERS));
  let log = null;
  try {
    log = await readFile(join(dir, LOG), 'utf8');
  } catch {
    log = null;
  }

  if (log === null) {
    if (!materialised) return { ...emptyState(slug), recovered: false };
    return {
      ...emptyState(slug), ...materialised, order: Object.keys(materialised.answers || {}),
      seq: 0, recovered: false,
    };
  }

  const state = emptyState(materialised?.slug || slug);
  const events = [];
  for (const line of log.split('\n')) {
    const text = line.trim();
    if (!text) continue;
    try {
      events.push(JSON.parse(text));
    } catch {
      // A torn final line: the process died mid-append. The answer it described was never
      // acknowledged to the owner, so dropping it is correct — and it can only ever be the last.
    }
  }
  events.sort((a, b) => (a.seq ?? 0) - (b.seq ?? 0));
  for (const event of events) applyEvent(state, event);
  if (materialised?.doc_hash && !state.doc_hash) state.doc_hash = materialised.doc_hash;

  const rebuilt = materialiseShape(state);
  const recovered = JSON.stringify(rebuilt.answers) !== JSON.stringify(materialised?.answers ?? {});
  return { ...state, recovered };
}

/** The exact on-disk shape of `answers.json` (§4.3), keys in the order the contract gives. */
export function materialiseShape(state) {
  const answers = {};
  for (const id of Object.keys(state.answers)) {
    const a = state.answers[id];
    answers[id] = {
      state: a.state,
      option: a.option ?? null,
      note: a.note ?? '',
      override: a.override ?? false,
      active: a.active !== false,
      round: a.round ?? 1,
      at: a.at,
    };
  }
  return { slug: state.slug, doc_hash: state.doc_hash ?? null, updated: state.updated ?? now(), answers };
}

/** Rewrite `answers.json` from the state, atomically. Always follows an `append`, never precedes. */
export async function materialise(dir, state) {
  await mkdir(dir, { recursive: true });
  const shape = materialiseShape(state);
  await writeJsonAtomic(join(dir, ANSWERS), shape);
  return shape;
}

/**
 * The whole §4.4 sequence for one or more events, in order, with nothing returned until both
 * fsyncs are done. `events` may carry strand/restore beside the answer; they belong to the same
 * decision and must not be able to land separately.
 */
export async function commit(dir, events, { slug = '', docHash = null } = {}) {
  const state = await load(dir, { slug });
  const stamped = (Array.isArray(events) ? events : [events]).map((e, i) => ({
    seq: state.seq + 1 + i,
    at: e.at || now(),
    ...e,
  }));
  await append(dir, stamped);
  for (const e of stamped) applyEvent(state, e);
  if (docHash) state.doc_hash = docHash;
  if (slug) state.slug = slug;
  await materialise(dir, state);
  return state;
}

/** Record one answer (§4.3 fields), plus whatever it stranded or restored. */
export async function answer(dir, record, { strand = [], restore = [], slug = '', docHash = null } = {}) {
  const events = [{
    event: 'answer',
    id: record.id,
    state: record.state,
    option: record.option ?? null,
    note: record.note ?? '',
    override: record.override ?? false,
    round: record.round ?? 1,
  }];
  if (strand.length) events.push({ event: 'strand', ids: strand, cause: record.id, active: false });
  if (restore.length) events.push({ event: 'restore', ids: restore, cause: record.id, active: true });
  return commit(dir, events, { slug, docHash });
}

/** Node and edge annotations (§4.5), under the same durability rule as answers (Q57/F7). */
export async function annotate(dir, target, key, text) {
  const bucket = target === 'edge' ? 'edges' : 'nodes';
  const file = join(dir, ANNOTATIONS);
  const current = (await readJson(file)) || { nodes: {}, edges: {}, approved: {} };
  current[bucket] = current[bucket] || {};
  current[bucket][key] = [...(current[bucket][key] || []), { at: now(), text }];
  await mkdir(dir, { recursive: true });
  await writeJsonAtomic(file, current);
  return current;
}

/** The most recent write to any file in a design directory — the index's "last touched". */
export async function lastTouched(dir) {
  let latest = null;
  try {
    for (const name of await readdir(dir)) {
      const info = await stat(join(dir, name)).catch(() => null);
      if (info?.isFile() && (!latest || info.mtime > latest)) latest = info.mtime;
    }
  } catch {
    return null;
  }
  return latest ? latest.toISOString() : null;
}

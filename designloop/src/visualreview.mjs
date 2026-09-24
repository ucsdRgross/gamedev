// The post-work visual review: `<project>/visual-review/`, one BEFORE/AFTER pair per shot.
//
// Every file has one writer, as everywhere in this tool. The worker writes `manifest.json`, the
// images and `status.agent.json` (through `review.py`); the owner writes `review.log`,
// `review.json` and `status.owner.json` through the routes below and nothing else.

import { stat } from 'node:fs/promises';
import { join, resolve, sep } from 'node:path';
import { readJson, writeJsonAtomic, append, now } from './store.mjs';
import { writeOwnerStatus, readStatus } from './registry.mjs';

export const VERDICTS = ['approve', 'reject', 'comment'];

/** `<repo>/<project>/visual-review`, or null for a project name that is not one plain directory. */
export function reviewDir(repoRoot, project) {
  if (!/^[\w-]+$/.test(project)) return null;
  return join(repoRoot, project, 'visual-review');
}

/** A file inside the review folder, or null if the path escapes it. */
export function reviewFile(dir, rel) {
  const abs = resolve(dir, rel.replace(/^[/\\]+/, ''));
  return abs === dir || abs.startsWith(dir + sep) ? abs : null;
}

/** When `<side>/<id>.png` was written, or null when it is absent — the page's "no before". */
async function shotTime(dir, side, id) {
  const info = await stat(join(dir, side, `${id}.png`)).catch(() => null);
  return info ? info.mtime.toISOString() : null;
}

/** Everything the page shows, in one payload. */
export async function readReview(dir) {
  const manifest = await readJson(join(dir, 'manifest.json'));
  const review = (await readJson(join(dir, 'review.json'))) || { shots: {} };
  const files = {};
  for (const shot of manifest.shots) {
    files[shot.id] = { before: await shotTime(dir, 'before', shot.id), after: await shotTime(dir, 'after', shot.id) };
  }
  const { owner, agent } = await readStatus(dir);
  return { manifest, review, files, owner, agent };
}

/** Log first, then the materialised file — the same order `answers.log` keeps, for the same reason. */
export async function recordVerdict(dir, { id, verdict, comment }) {
  const record = { verdict, comment, at: now() };
  await append(dir, { event: 'verdict', id, ...record }, 'review.log');
  const review = (await readJson(join(dir, 'review.json'))) || { shots: {} };
  review.shots[id] = record;
  review.updated = record.at;
  await writeJsonAtomic(join(dir, 'review.json'), review);
  return review;
}

/** Done hands the turn back; `run watch -- visual-review/<project>` is parked on exactly this. */
export function markDone(dir) {
  return writeOwnerStatus(dir, { state: 'done', reason: 'reviewed' });
}

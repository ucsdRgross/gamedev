// Finding the designs (PLAN S3, §4.1, §4.2, §7; DESIGN chart H1–H4, Q101–Q107).
//
// Designs live BESIDE the code they describe — `<project>/design/<slug>/` — and `designloop/`
// holds only the tool (Q101=b). So there is no central list to keep in step with reality: the
// index is a scan, and a design that is moved, renamed on disk, or deleted by hand is simply what
// the next scan finds.
//
// A design's key everywhere in the API is `<first project>/<slug>` (§4.1).

import { readdir, readFile } from 'node:fs/promises';
import { join, resolve } from 'node:path';
import { readJson, writeJsonAtomic, load, lastTouched, now } from './store.mjs';

/** Directories that are never projects. */
const SKIP = new Set(['node_modules', 'design', '.git', '.claude', '.godot', 'dist', 'build']);

/** Whose turn it is, owner half (§4.2). The default is "your turn" — nothing has happened yet. */
export const DEFAULT_OWNER_STATUS = { state: 'answering', reason: null, round: 1, at: null };
/** Whose turn it is, agent half (§4.2). */
export const DEFAULT_AGENT_STATUS = { state: 'idle', mode: 'questions', round: 1, at: null };

/** The design's key: `<first project>/<slug>`. */
export function key(design) {
  return `${design.projects?.[0] ?? 'unknown'}/${design.slug}`;
}

/** Split a key back into its parts. Returns null for anything that is not `project/slug`. */
export function parseKey(raw) {
  const parts = String(raw || '').split('/').filter(Boolean);
  if (parts.length !== 2) return null;
  if (parts.some((p) => p === '.' || p === '..' || /[\\:]/.test(p))) return null;
  return { project: parts[0], slug: parts[1] };
}

/** Read both status halves, filling in the defaults for a design nobody has touched yet. */
export async function readStatus(dir) {
  return {
    owner: { ...DEFAULT_OWNER_STATUS, ...(await readJson(join(dir, 'status.owner.json'))) },
    agent: { ...DEFAULT_AGENT_STATUS, ...(await readJson(join(dir, 'status.agent.json'))) },
  };
}

/** Write the owner half. UI-owned: the agent half is never touched from here (§4.2). */
export async function writeOwnerStatus(dir, patch) {
  const current = { ...DEFAULT_OWNER_STATUS, ...(await readJson(join(dir, 'status.owner.json'))) };
  const next = { state: current.state, reason: current.reason, round: current.round, ...patch, at: now() };
  await writeJsonAtomic(join(dir, 'status.owner.json'), next);
  return next;
}

/** Count the open gaps in a design's own `gaps/` directory (Q105=a, Q89b=c). */
export async function countGaps(dir) {
  let files;
  try {
    files = await readdir(join(dir, 'gaps'));
  } catch {
    return { open: 0, total: 0 };
  }
  let open = 0;
  let total = 0;
  for (const name of files) {
    if (!name.toLowerCase().endsWith('.md')) continue;
    total += 1;
    const text = await readFile(join(dir, 'gaps', name), 'utf8').catch(() => '');
    if (/^status:\s*(open|questioned)\s*$/mi.test(text)) open += 1;
  }
  return { open, total };
}

/** Everything the index needs about one design directory, or null if it is not one. */
export async function readDesign(repoRoot, project, slug) {
  const dir = join(repoRoot, project, 'design', slug);
  const meta = await readJson(join(dir, 'meta.json'));
  if (!meta || !meta.slug) return null;
  const ui = (await readJson(join(dir, 'ui_meta.json'))) || {};
  const status = await readStatus(dir);
  const answers = await load(dir, { slug: meta.slug });
  const gaps = await countGaps(dir);
  const design = {
    slug: meta.slug,
    // `title` is UI-owned so that renaming from the index (Q107=a) never writes meta.json, which
    // is the agent's file. meta.json's title is what a design is called until the owner says so.
    title: ui.title || meta.title || meta.slug,
    projects: Array.isArray(meta.projects) && meta.projects.length ? meta.projects : [project],
    doc: meta.doc || 'DESIGN.md',
    created: meta.created || null,
    rounds: meta.rounds ?? 1,
    confirmed_version: meta.confirmed_version ?? null,
    archived: ui.archived === true,
    opened: ui.opened || null,
    dir,
    owner: status.owner,
    agent: status.agent,
    answered: Object.values(answers.answers).filter((a) => a.active !== false).length,
    gaps: gaps.open,
    touched: await lastTouched(dir),
  };
  design.key = key(design);
  design.docPath = resolve(dir, design.doc);
  return design;
}

/** Scan the repo for `<project>/design/<slug>/meta.json`. */
export async function discover(repoRoot) {
  const designs = [];
  let projects;
  try {
    projects = await readdir(repoRoot, { withFileTypes: true });
  } catch {
    return designs;
  }
  for (const entry of projects) {
    if (!entry.isDirectory() || entry.name.startsWith('.') || SKIP.has(entry.name)) continue;
    let slugs;
    try {
      slugs = await readdir(join(repoRoot, entry.name, 'design'), { withFileTypes: true });
    } catch {
      continue;
    }
    for (const slug of slugs) {
      if (!slug.isDirectory()) continue;
      const design = await readDesign(repoRoot, entry.name, slug.name);
      if (design) designs.push(design);
    }
  }
  designs.sort((a, b) => a.key.localeCompare(b.key));
  return designs;
}

/** Find one design by its `<project>/<slug>` key. */
export async function find(repoRoot, rawKey) {
  const parts = parseKey(rawKey);
  if (!parts) return null;
  const direct = await readDesign(repoRoot, parts.project, parts.slug);
  if (direct) return direct;
  // A design may list several projects and appears under each (Q103=a), but its key names the
  // first — so a key built from a secondary project has to be resolved by scanning.
  const all = await discover(repoRoot);
  return all.find((d) => d.slug === parts.slug && d.projects.includes(parts.project)) || null;
}

/** Rename or archive a design. Never delete — a frozen version's path must stay valid (Q107=a). */
export async function rename(dir, title) {
  const ui = (await readJson(join(dir, 'ui_meta.json'))) || {};
  await writeJsonAtomic(join(dir, 'ui_meta.json'), { ...ui, title, updated: now() });
}

/** Archive or unarchive. Archived designs stay listed, greyed — this is not a delete (Q85=a). */
export async function archive(dir, archived) {
  const ui = (await readJson(join(dir, 'ui_meta.json'))) || {};
  await writeJsonAtomic(join(dir, 'ui_meta.json'), { ...ui, archived: !!archived, updated: now() });
}

/** Record that the owner opened this design, which is what "last opened" in the index means. */
export async function touch(dir) {
  const ui = (await readJson(join(dir, 'ui_meta.json'))) || {};
  await writeJsonAtomic(join(dir, 'ui_meta.json'), { ...ui, opened: now() });
}

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
import { parseDocument } from './grammar.mjs';
import { parseCharts } from './graph.mjs';
import { readGaps as readGapFiles, countGaps as countGapList } from './gaps.mjs';

/** Directories that are never projects. */
const SKIP = new Set(['node_modules', 'design', '.git', '.claude', '.godot', 'dist', 'build']);

/** Whose turn it is, owner half (§4.2). The default is "your turn" — nothing has happened yet. */
export const DEFAULT_OWNER_STATUS = { state: 'answering', reason: null, round: 1, at: null };
/** Whose turn it is, agent half (§4.2). */
export const DEFAULT_AGENT_STATUS = { state: 'idle', mode: 'questions', round: 1, at: null };

/**
 * Is an agent parked on this design right now (§4.9)?
 *
 * `session.json` is a heartbeat written by `watch.mjs` every few seconds. Read here, it answers the
 * one question the owner could not previously ask the tool: *is anyone listening?* A session that
 * ended — Ctrl-C, a crashed process, a chat that simply stopped — leaves the last beat behind, so
 * **staleness is the signal**, not a flag someone remembered to clear.
 *
 * The grace factor is deliberately generous. A false "nobody is listening" sends the owner off to
 * start a session they already have; a few extra seconds of "still watching" costs nothing, because
 * the fallback the screen offers — tell the agent in chat — was always the honest route (Q22=a).
 */
const SESSION_STALE_AFTER = 4;
/**
 * …and never a window under this, whatever the beat interval, because `now()` writes timestamps to
 * the SECOND. A window of a few hundred milliseconds would be measuring rounding, and would report
 * a watch that is beating perfectly as one that has died.
 */
const SESSION_MIN_WINDOW_MS = 3000;

export async function readSession(dir) {
  const raw = await readJson(join(dir, 'session.json'));
  if (!raw || !raw.at) return { watching: false, since: null, at: null, stale: false, ever: !!raw };
  const age = Date.now() - Date.parse(raw.at);
  const window = Math.max((raw.every_ms || 5000) * SESSION_STALE_AFTER, SESSION_MIN_WINDOW_MS);
  const stale = !Number.isFinite(age) || age > window;
  return {
    watching: raw.watching === true && !stale,
    since: raw.since || null,
    at: raw.at,
    stale: raw.watching === true && stale,
    ever: true,
  };
}

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

// Gaps are read by `src/gaps.mjs` (S15): a gap is a draft question, so the module that knows the
// questionnaire grammar owns the file format, and the registry only counts what it finds.

/**
 * Read the agent's own assumptions (Q58=c, Q94b=a). `ASSUMPTIONS.md` is a table in this repo's
 * house style; a bullet list is accepted too, because the file is written by hand and the panel
 * showing it must not be the reason someone reformats their notes.
 */
export async function readAssumptions(dir) {
  const text = await readFile(join(dir, 'ASSUMPTIONS.md'), 'utf8').catch(() => '');
  const out = [];
  let header = true;
  for (const line of text.split(/\r?\n/)) {
    const trimmed = line.trim();
    if (trimmed.startsWith('|')) {
      const cells = trimmed.slice(1, trimmed.endsWith('|') ? -1 : undefined).split('|').map((c) => c.trim());
      if (cells.every((c) => /^:?-{2,}:?$/.test(c))) continue;
      if (header) {
        header = false;                       // the first row of a table is its heading, not data
        continue;
      }
      if (cells.length >= 3) out.push({ source: 'agent', when: cells[0], step: cells[1], text: cells[2], why: cells[3] || '' });
      continue;
    }
    if (/^-\s+\S/.test(trimmed)) out.push({ source: 'agent', text: trimmed.slice(2).trim(), why: '' });
  }
  return out;
}

/**
 * Parse a design's document far enough to say whether it is well-formed.
 *
 * The index carries these as badges, which is half of GAP-001's resolution (b, 2026-08-01): a
 * ⚑gate option with no `→ next:` no longer refuses the document, so the defect has to be visible
 * somewhere the authoring agent will meet it. The other half is `run check`.
 */
async function docHealth(docPath) {
  const text = await readFile(docPath, 'utf8').catch(() => null);
  if (text === null) return { errors: 0, warnings: 0, doc_missing: true };
  const parsed = parseDocument(text);
  // Link warnings (§6.1) join the authoring-warning badge GAP-001 created. Same reasoning: a label
  // naming a chart that does not exist is the author's defect, it reaches the author here, and it
  // never blocks the owner. A chart the parser cannot read at all is a separate, louder failure and
  // is not counted here — the canvas reports it when it tries to draw.
  let links = 0;
  try {
    links = parseCharts(text, { file: docPath }).warnings.length;
  } catch { /* unreadable charts are the canvas's error to report, not a warning to badge */ }
  return { errors: parsed.errors.length, warnings: parsed.warnings.length + links, doc_missing: false };
}

/** Everything the index needs about one design directory, or null if it is not one. */
export async function readDesign(repoRoot, project, slug) {
  const dir = join(repoRoot, project, 'design', slug);
  const meta = await readJson(join(dir, 'meta.json'));
  if (!meta || !meta.slug) return null;
  const ui = (await readJson(join(dir, 'ui_meta.json'))) || {};
  const status = await readStatus(dir);
  const answers = await load(dir, { slug: meta.slug });
  const gaps = countGapList(await readGapFiles(dir));
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
    session: await readSession(dir),
    answered: Object.values(answers.answers).filter((a) => a.active !== false).length,
    // Open and closed both reach the index card: Q89b=c wants the open ones visible without being
    // asked, and Q96b=a keeps the closed ones, which are only kept if somebody can see them.
    gaps: gaps.open,
    gaps_closed: gaps.closed,
    gaps_total: gaps.total,
    touched: await lastTouched(dir),
  };
  design.key = key(design);
  design.docPath = resolve(dir, design.doc);
  Object.assign(design, await docHealth(design.docPath));
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

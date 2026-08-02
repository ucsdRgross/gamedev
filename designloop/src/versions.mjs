// Confirm, the frozen versions, and the diff between them (PLAN S14, §4.7; DESIGN chart G,
// Q59–Q62, Q71, Q72, Q115).
//
// Confirm freezes `versions/NNN/`: the graph, the answers, the annotations, AND the layout with the
// collapse state and the viewport (Q115=b), so reopening a version puts back exactly what was on
// screen — not an equivalent picture, the same one. `engine` is recorded beside the positions so a
// later layout change cannot silently re-flow a frozen version.
//
// A frozen version is never mutated. Confirm again and you get the next one; the working copy stays
// editable (Q61=a).
//
// `DESIGN.md` inside a version is GENERATED from the graph and never hand-edited (Q71=a) — a JSON
// graph nobody can read will rot, and a hand-edited render drifts from what it renders. It
// round-trips: re-ingesting it reproduces the same graph, which the test asserts.

import { readdir, mkdir, writeFile, stat } from 'node:fs/promises';
import { join } from 'node:path';
import { readJson, writeJsonAtomic, now } from './store.mjs';

/** `versions/003` — three digits, so a directory listing sorts the way a human reads it. */
export const pad = (n) => String(n).padStart(3, '0');

/** Every frozen version, oldest first. Derived from the directory: a version has no index file. */
export async function listVersions(dir) {
  let entries;
  try {
    entries = await readdir(join(dir, 'versions'), { withFileTypes: true });
  } catch {
    return [];
  }
  const out = [];
  for (const entry of entries) {
    if (!entry.isDirectory() || !/^\d+$/.test(entry.name)) continue;
    const path = join(dir, 'versions', entry.name);
    const graph = await readJson(join(path, 'graph.json'));
    if (!graph) continue;
    const info = await stat(join(path, 'graph.json')).catch(() => null);
    const layout = await readJson(join(path, 'layout.json'));
    const answers = await readJson(join(path, 'answers.json'));
    out.push({
      n: Number(entry.name),
      at: info ? info.mtime.toISOString() : null,
      charts: graph.charts.length,
      nodes: Object.keys(graph.nodes).length,
      answers: Object.keys(answers?.answers || {}).length,
      collapsed: layout?.collapsed || [],
      engine: layout?.engine || null,
    });
  }
  return out.sort((a, b) => a.n - b.n);
}

/**
 * The highest version NUMBER on disk, readable or not.
 *
 * `listVersions` skips a version whose `graph.json` cannot be read — a freeze that died between
 * the two writes, say — and numbering the next one off that list would hand it a directory that
 * already exists and overwrite what is in it. A version is citable only if its number is never
 * reused, so the numbering counts directories and the listing reads them.
 */
async function highestVersion(dir) {
  try {
    const entries = await readdir(join(dir, 'versions'), { withFileTypes: true });
    return entries.reduce(
      (max, e) => (e.isDirectory() && /^\d+$/.test(e.name) ? Math.max(max, Number(e.name)) : max),
      0,
    );
  } catch {
    return 0;
  }
}

/** Everything a frozen version holds, for reopening it read-only (Q90=a, H6). */
export async function readVersion(dir, n) {
  const path = join(dir, 'versions', pad(n));
  const graph = await readJson(join(path, 'graph.json'));
  if (!graph) return null;
  return {
    n,
    graph,
    layout: await readJson(join(path, 'layout.json')),
    answers: await readJson(join(path, 'answers.json')),
    annotations: await readJson(join(path, 'annotations.json')),
  };
}

/**
 * Node-level diff between two graphs (Q62=a): what was added, removed, and changed.
 * "Changed" is the label, the shape or the edges into and out of the node — the three things that
 * alter what the node means. Position is not a change; it is a consequence of one.
 */
export function diffGraphs(before, after) {
  const edgesOf = (graph, id) => graph.edges
    .filter((e) => e.from === id || e.to === id)
    .map((e) => `${e.from}-${e.label}->${e.to}`)
    .sort();

  const added = [];
  const removed = [];
  const changed = [];
  for (const id of Object.keys(after.nodes)) {
    if (!before.nodes[id]) {
      added.push({ id, label: after.nodes[id].label, chart: after.nodes[id].chart });
      continue;
    }
    const a = before.nodes[id];
    const b = after.nodes[id];
    const was = edgesOf(before, id).join('|');
    const is = edgesOf(after, id).join('|');
    const fields = [];
    if (a.label !== b.label) fields.push('label');
    if (a.shape !== b.shape) fields.push('shape');
    if (was !== is) fields.push('edges');
    if (fields.length) changed.push({ id, chart: b.chart, fields, before: a.label, after: b.label });
  }
  for (const id of Object.keys(before.nodes)) {
    if (!after.nodes[id]) removed.push({ id, label: before.nodes[id].label, chart: before.nodes[id].chart });
  }
  return { added, removed, changed };
}

/** Render one chart back to the §6 mermaid subset. Re-ingesting this reproduces the same chart. */
export function renderChart(graph, chart) {
  const lines = ['```mermaid', 'flowchart TD'];
  for (const id of chart.nodes) {
    const node = graph.nodes[id];
    lines.push(node.shape === 'decision' ? `  ${id}{"${node.label}"}` : `  ${id}["${node.label}"]`);
  }
  for (const edge of graph.edges.filter((e) => e.chart === chart.id)) {
    lines.push(edge.label ? `  ${edge.from} -- "${edge.label}" --> ${edge.to}` : `  ${edge.from} --> ${edge.to}`);
  }
  lines.push('```');
  return lines.join('\n');
}

/**
 * The human-readable render frozen beside the JSON (Q71=a, chart G3): the charts as mermaid, the
 * decisions as prose, the assumptions and the out-of-scope list. Q72=a keeps the raw transcript in
 * `transcript.md` rather than inline, so this file stays readable.
 */
export function renderDesignMarkdown({ design, version, graph, questions, answers, annotations, assumptions, outOfScope }) {
  const md = [];
  const answerOf = (id) => answers.answers?.[id];
  md.push(`# ${design.title} — confirmed design, version ${version}`);
  md.push('');
  md.push('**Generated by the Design Loop at Confirm. Never hand-edit it** — it is rendered from');
  md.push('`graph.json` and `answers.json` beside it, and an edit here would be lost and would make');
  md.push('the two disagree. To change the design, reopen it and Confirm again.');
  md.push('');
  md.push(`Frozen ${now()} · ${graph.charts.length} charts · ${Object.keys(graph.nodes).length} nodes `
    + `· ${Object.keys(answers.answers || {}).length} answers`);
  md.push('');

  md.push('## The design');
  md.push('');
  for (const chart of graph.charts) {
    md.push(`### Chart ${chart.id} — ${chart.title}`);
    md.push('');
    md.push(renderChart(graph, chart));
    md.push('');
    const notes = chart.nodes.flatMap((id) => (annotations.nodes?.[id] || []).map((a) => ({ id, ...a })));
    const flagged = chart.nodes.filter((id) => annotations.flagged?.[id]);
    if (flagged.length) {
      md.push(`**Flagged for another look:** ${flagged.join(', ')}`);
      md.push('');
    }
    for (const note of notes) {
      md.push(`- **${note.id}** — ${note.text}`);
    }
    if (notes.length) md.push('');
  }

  md.push('## The decisions');
  md.push('');
  md.push('| Question | Answer | What it settles |');
  md.push('|---|---|---|');
  for (const q of questions) {
    const a = answerOf(q.id);
    if (!a || a.active === false) continue;
    const option = q.options.find((o) => o.letter === a.option);
    const label = a.override ? `*(own answer)* ${a.note}` : `(${a.option}) ${option ? option.label : ''}`;
    const mark = a.state === 'chosen' ? '' : ` — *${a.state.replace('_', ' ')}*`;
    md.push(`| ${q.id} | ${label.replace(/\|/g, '\\|')}${mark} | ${(option?.consequence || '').replace(/\|/g, '\\|')} |`);
  }
  md.push('');

  md.push('## Assumptions');
  md.push('');
  md.push('Everywhere structure was filled in rather than asked about, plus every answer that was');
  md.push('waved through (Q58=c, Q116=a). All three sources are listed and labelled.');
  md.push('');
  for (const item of assumptions) {
    md.push(`- **${item.source}** — ${item.text}${item.why ? ` *(${item.why})*` : ''}`);
  }
  if (!assumptions.length) md.push('- none');
  md.push('');

  md.push('## Out of scope');
  md.push('');
  for (const item of outOfScope) md.push(`- **${item.id}** — ${item.text}`);
  if (!outOfScope.length) md.push('- nothing was confirmed out of scope');
  md.push('');
  return `${md.join('\n')}\n`;
}

/** The raw Q&A transcript, kept beside the render rather than inside it (Q72=a, Q84=a). */
export function renderTranscript({ design, version, questions, answers }) {
  const md = [`# ${design.title} — answers of record, version ${version}`, ''];
  md.push('The full transcript. `DESIGN.md` beside this file carries the decisions and their');
  md.push('rationale; this is everything that was asked and everything that came back.');
  md.push('');
  for (const q of questions) {
    const a = answers.answers?.[q.id];
    if (!a) continue;
    md.push(`### ${q.id} — ${q.text}`);
    md.push('');
    for (const option of q.options) {
      const picked = option.letter === a.option && !a.override;
      md.push(`- ${picked ? '**' : ''}(${option.letter}) ${option.label}${picked ? '**' : ''}`
        + `${option.consequence ? ` — ${option.consequence}` : ''}`);
    }
    md.push('');
    md.push(`**Answer:** ${a.override ? 'their own words' : `(${a.option})`} · recorded as \`${a.state}\``
      + `${a.active === false ? ' · **inactive** — set aside by a later change' : ''} · round ${a.round}`);
    if (a.note) {
      md.push('');
      md.push(`> ${a.note.split('\n').join('\n> ')}`);
    }
    md.push('');
  }
  return `${md.join('\n')}\n`;
}

/** What changed since the previous version (§4.7): nodes, questions, and gaps closed. */
export function renderChangelog({ version, previous, graph, answers, questions, gaps }) {
  const md = [`# Version ${version} — what changed`, ''];
  if (!previous) {
    md.push(`First frozen version: ${graph.charts.length} charts, ${Object.keys(graph.nodes).length} nodes, `
      + `${Object.keys(answers.answers || {}).length} answers.`);
    md.push('');
    return `${md.join('\n')}\n`;
  }
  const diff = diffGraphs(previous.graph, graph);
  md.push(`Against version ${previous.n}.`);
  md.push('');
  for (const [title, list, render] of [
    ['Nodes added', diff.added, (n) => `- **${n.id}** (${n.chart}) — ${n.label}`],
    ['Nodes changed', diff.changed, (n) => `- **${n.id}** (${n.chart}) — ${n.fields.join(', ')}`],
    ['Nodes removed', diff.removed, (n) => `- **${n.id}** (${n.chart}) — ${n.label}`],
  ]) {
    md.push(`## ${title}`);
    md.push('');
    if (!list.length) md.push('- none');
    for (const item of list) md.push(render(item));
    md.push('');
  }

  const before = previous.answers?.answers || {};
  const after = answers.answers || {};
  const newAnswers = Object.keys(after).filter((id) => !before[id]);
  const rewritten = Object.keys(after).filter((id) => before[id] && (
    before[id].option !== after[id].option || before[id].state !== after[id].state));
  md.push('## Questions answered since');
  md.push('');
  if (!newAnswers.length) md.push('- none');
  for (const id of newAnswers) {
    const q = questions.find((x) => x.id === id);
    md.push(`- **${id}** (${after[id].option ?? 'own answer'}) — ${q ? q.text : ''}`);
  }
  md.push('');
  if (rewritten.length) {
    md.push('## Answers changed');
    md.push('');
    for (const id of rewritten) md.push(`- **${id}** ${before[id].option} → ${after[id].option ?? 'own answer'}`);
    md.push('');
  }
  md.push('## Gaps closed');
  md.push('');
  const closed = gaps.filter((g) => g.status !== 'open');
  if (!closed.length) md.push('- none');
  for (const g of closed) md.push(`- **${g.id}** — ${g.title} *(${g.status})*`);
  md.push('');
  return `${md.join('\n')}\n`;
}

/**
 * Freeze the next version (chart G2). Everything is written into a fresh directory and nothing
 * already frozen is touched — that is what makes a version citable.
 */
export async function freeze(dir, payload) {
  const existing = await listVersions(dir);
  const version = (await highestVersion(dir)) + 1;
  const previous = existing.length ? await readVersion(dir, existing[existing.length - 1].n) : null;
  const path = join(dir, 'versions', pad(version));
  await mkdir(path, { recursive: true });

  const { graph, answers, annotations, layout } = payload;
  await writeJsonAtomic(join(path, 'graph.json'), graph);
  await writeJsonAtomic(join(path, 'answers.json'), answers);
  await writeJsonAtomic(join(path, 'annotations.json'), annotations);
  await writeJsonAtomic(join(path, 'layout.json'), layout);
  await writeFile(join(path, 'DESIGN.md'), renderDesignMarkdown({ ...payload, version }), 'utf8');
  await writeFile(join(path, 'transcript.md'), renderTranscript({ ...payload, version }), 'utf8');
  await writeFile(join(path, 'changelog.md'), renderChangelog({ ...payload, version, previous }), 'utf8');
  return { version, path };
}

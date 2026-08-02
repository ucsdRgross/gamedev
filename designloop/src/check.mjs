// Does this document parse? (PLAN S10.) The authoring agent's check before it hands over a URL:
// a question the parser cannot read is a question the owner never sees.
//
//   npm --prefix designloop run check -- solatro/spotlight
//   npm --prefix designloop run check -- path/to/DESIGN.md
//   npm --prefix designloop run check -- solatro/spotlight charts     one line per mermaid chart

import { readFile } from 'node:fs/promises';
import { resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { parseDocument, reachability, nextQuestion, longestPath } from './grammar.mjs';
import { parseCharts, validate as validateGraph, describeGraph } from './graph.mjs';
import { find } from './registry.mjs';

const TOOL_ROOT = resolve(fileURLToPath(new URL('..', import.meta.url)));
const REPO_ROOT = resolve(process.env.DESIGNLOOP_ROOT || resolve(TOOL_ROOT, '..'));

/** Parse a document and describe it the way the authoring agent needs to hear it. */
export function describe(markdown, file = 'DESIGN.md') {
  const parsed = parseDocument(markdown);
  const live = parsed.questions.filter((q) => !q.retired);
  const { reachable, pending } = reachability(live, {});

  // The charts are half the document (S11). A chart the canvas cannot ingest is a chart the owner
  // never reviews, so it is reported here, before a URL is handed over, not after.
  let graph = null;
  let graphError = null;
  try {
    graph = parseCharts(markdown, { file });
  } catch (err) {
    graphError = err;
  }

  return {
    parsed,
    graph,
    graphError,
    lines: [
      `questions   ${live.length} live, ${parsed.questions.length - live.length} retired`,
      `gates       ${live.filter((q) => q.isGate).length} ⚑gate, ${live.filter((q) => q.notes).length} marked notes`,
      `at the top  ${reachable.length} askable now, ${pending.length} waiting on a gate`,
      `opens at    ${nextQuestion(live, {}, parsed.sections)?.id ?? '(nothing)'}`,
      `longest     ${longestPath(live)} questions on one path`,
      `charts      ${graph ? `${graph.charts.length} ingested, ${Object.keys(graph.nodes).length} nodes, ${graph.edges.length} edges` : 'FAILED — see below'}`,
      `errors      ${parsed.errors.length}`,
      `warnings    ${parsed.warnings.length}`,
      `skipped     ${parsed.ignored.length} bullet(s) that name a question ID but are not questions`,
    ],
  };
}

async function main() {
  const target = process.argv.slice(2).filter((a) => a !== '--' && a !== 'charts')[0];
  if (!target) {
    process.stdout.write('usage: npm --prefix designloop run check -- <project>/<slug> | <path to DESIGN.md>\n');
    process.exit(2);
  }
  let path = resolve(REPO_ROOT, target);
  if (!target.endsWith('.md')) {
    const design = await find(REPO_ROOT, target);
    if (!design) {
      process.stdout.write(`no design at "${target}"\n`);
      process.exit(1);
    }
    path = design.docPath;
  }
  const { parsed, graph, graphError, lines } = describe(await readFile(path, 'utf8'), target);
  process.stdout.write(`\n${path}\n${lines.map((l) => `  ${l}`).join('\n')}\n`);
  for (const e of parsed.errors) process.stdout.write(`  ERROR   line ${e.line ?? '?'}: ${e.message}\n`);
  for (const w of parsed.warnings) process.stdout.write(`  warning line ${w.line ?? '?'}: ${w.message}\n`);
  if (graphError) process.stdout.write(`  CHART   ${graphError.message}\n`);
  const graphErrors = graph ? validateGraph(graph) : [];
  for (const e of graphErrors) process.stdout.write(`  CHART   ${e.message}\n`);
  // A bare word, not a flag: `npm run check -- <design> charts`. npm eats unknown `--flags` before
  // the script ever sees them and then exits non-zero, which looks like a failure that never was.
  if (graph && process.argv.slice(2).includes('charts')) {
    process.stdout.write(`${describeGraph(graph).map((l) => `  ${l}`).join('\n')}\n`);
  }
  process.stdout.write('\n');
  process.exit(parsed.errors.length || graphError || graphErrors.length ? 1 : 0);
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  main();
}

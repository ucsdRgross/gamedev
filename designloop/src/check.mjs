// Does this document parse? (PLAN S10.) The authoring agent's check before it hands over a URL:
// a question the parser cannot read is a question the owner never sees.
//
//   npm --prefix designloop run check -- solatro/spotlight
//   npm --prefix designloop run check -- path/to/DESIGN.md

import { readFile } from 'node:fs/promises';
import { resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { parseDocument, reachability, nextQuestion, longestPath } from './grammar.mjs';
import { find } from './registry.mjs';

const TOOL_ROOT = resolve(fileURLToPath(new URL('..', import.meta.url)));
const REPO_ROOT = resolve(process.env.DESIGNLOOP_ROOT || resolve(TOOL_ROOT, '..'));

/** Parse a document and describe it the way the authoring agent needs to hear it. */
export function describe(markdown) {
  const parsed = parseDocument(markdown);
  const live = parsed.questions.filter((q) => !q.retired);
  const { reachable, pending } = reachability(live, {});
  return {
    parsed,
    lines: [
      `questions   ${live.length} live, ${parsed.questions.length - live.length} retired`,
      `gates       ${live.filter((q) => q.isGate).length} ⚑gate, ${live.filter((q) => q.notes).length} marked notes`,
      `at the top  ${reachable.length} askable now, ${pending.length} waiting on a gate`,
      `opens at    ${nextQuestion(live, {}, parsed.sections)?.id ?? '(nothing)'}`,
      `longest     ${longestPath(live)} questions on one path`,
      `errors      ${parsed.errors.length}`,
      `warnings    ${parsed.warnings.length}`,
      `skipped     ${parsed.ignored.length} bullet(s) that name a question ID but are not questions`,
    ],
  };
}

async function main() {
  const target = process.argv.slice(2).filter((a) => a !== '--')[0];
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
  const { parsed, lines } = describe(await readFile(path, 'utf8'));
  process.stdout.write(`\n${path}\n${lines.map((l) => `  ${l}`).join('\n')}\n`);
  for (const e of parsed.errors) process.stdout.write(`  ERROR   line ${e.line ?? '?'}: ${e.message}\n`);
  for (const w of parsed.warnings) process.stdout.write(`  warning line ${w.line ?? '?'}: ${w.message}\n`);
  process.stdout.write('\n');
  process.exit(parsed.errors.length ? 1 : 0);
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  main();
}

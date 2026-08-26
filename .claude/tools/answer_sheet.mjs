// Render a design's answers as RESOLVED TEXT, so charts are written from what the owner chose
// rather than from the option letter — which is opaque — or from the author's memory of the
// question, which defaults to whatever the author recommended.
//
// THE FAILURE THIS EXISTS TO PREVENT, measured on solatro/poker-patience: nine chart nodes stated
// the option the author had recommended instead of the option the owner picked. Every one of them
// was a question where the two differed; not one node was wrong where they agreed. The correlation
// is perfect and it is diagnostic — this is authoring bias, not random error.
//
// `run check`'s `stale` line cannot catch it: that flags a node posing an ANSWERED question as an
// open fork, and a node confidently stating the WRONG answer is, to a parser, ordinary prose.
//
// Usage, from the repo root:
//   node .claude/tools/answer_sheet.mjs <project>/<slug>            every answered question
//   node .claude/tools/answer_sheet.mjs <project>/<slug> --diverged only where the owner
//                                                                   overrode the recommendation
//   node .claude/tools/answer_sheet.mjs <project>/<slug> --prose    only free-text answers, which
//                                                                   the plan must quote verbatim

import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { parseDocument } from '../../designloop/src/grammar.mjs';

const key = process.argv[2];
if (!key) {
  console.error('usage: node .claude/tools/answer_sheet.mjs <project>/<slug> [--diverged|--prose]');
  process.exit(2);
}
const mode = process.argv[3] || '';
const [project, slug] = key.split('/');
const dir = join(project, 'design', slug);

const doc = parseDocument(readFileSync(join(dir, 'DESIGN.md'), 'utf8'));
const answers = JSON.parse(readFileSync(join(dir, 'answers.json'), 'utf8')).answers || {};

const wrap = (s, indent) => {
  const words = String(s).replace(/\s+/g, ' ').trim().split(' ');
  const lines = [];
  let line = '';
  for (const w of words) {
    if ((line + ' ' + w).length > 96) { lines.push(line); line = w; }
    else line = line ? line + ' ' + w : w;
  }
  if (line) lines.push(line);
  return lines.map((l) => indent + l).join('\n');
};

let shown = 0;
let diverged = 0;
let prose = 0;

for (const q of doc.questions) {
  if (q.retired) continue;
  const a = answers[q.id];
  if (!a || a.active === false) continue;

  const isProse = !a.option;
  const isDiverged = a.option && q.default && a.option !== q.default;
  if (isProse) prose++;
  if (isDiverged) diverged++;

  if (mode === '--diverged' && !isDiverged) continue;
  if (mode === '--prose' && !isProse) continue;
  shown++;

  const flag = isDiverged ? '  ⚠ OVERRODE the recommendation (' + q.default + ')' : '';
  console.log('\n' + q.id + (a.option ? ' = (' + a.option + ')' : ' = FREE TEXT, no letter') + flag);

  if (a.option) {
    const opt = q.options.find((o) => o.letter === a.option);
    // THE POINT OF THIS TOOL: the chosen option's own words, resolved from the document.
    const text = opt
      ? [opt.label, opt.consequence].filter(Boolean).join(' — ')
      : '(no such option in the document — the answer is stranded)';
    console.log(wrap(text, '    '));
  }
  if (a.note && String(a.note).trim()) {
    console.log('    note (quote this verbatim in the plan; never summarise it):');
    console.log(wrap(a.note, '      '));
  }
}

console.error('\n' + shown + ' shown | ' + diverged + ' overrode the recommendation | '
  + prose + ' free text');
if (mode !== '--diverged' && mode !== '--prose') {
  console.error('⚠ Write every chart node from THIS output, and start with --diverged: those are '
    + 'the nodes that go wrong.');
}

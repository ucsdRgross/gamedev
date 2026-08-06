// PLAN S2 / §5.6 — the question grammar, one case per construct, plus THE acceptance test:
// `solatro/design/spotlight/DESIGN.md` parsing unchanged.

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';
import {
  parseDocument, parseQuestionLine, parseGate, evaluateGate, reachability,
  nextQuestion, blastRadius, validate, longestPath, describeGate, GrammarError, auditGates } from '../src/grammar.mjs';

const REPO = resolve(dirname(fileURLToPath(import.meta.url)), '..', '..');

/** Wrap question lines in the minimum document that gives them a section. */
function doc(...lines) {
  return ['## S', '', ...lines, ''].join('\n');
}

const A = (letter) => ({ state: 'chosen', option: letter, active: true });

test('[root] is always askable', () => {
  const g = parseGate('root');
  assert.equal(g.root, true);
  assert.equal(evaluateGate(g, {}), 'true');
});

test('[Q4=b] — true, false and pending', () => {
  const g = parseGate('Q4=b');
  assert.equal(evaluateGate(g, {}), 'pending');
  assert.equal(evaluateGate(g, { Q4: A('b') }), 'true');
  assert.equal(evaluateGate(g, { Q4: A('a') }), 'false');
});

test('[Q4=b|c] — the letter list is an OR inside one atom', () => {
  const g = parseGate('Q4=b|c');
  assert.deepEqual(g.atoms[0].letters, ['b', 'c']);
  assert.equal(evaluateGate(g, { Q4: A('c') }), 'true');
  assert.equal(evaluateGate(g, { Q4: A('a') }), 'false');
});

test('[Q4=b & Q9=a] — a conjunction is false as soon as one atom is', () => {
  const g = parseGate('Q4=b & Q9=a');
  assert.equal(g.atoms.length, 2);
  assert.equal(evaluateGate(g, { Q4: A('a') }), 'false');
  assert.equal(evaluateGate(g, { Q4: A('b') }), 'pending');
  assert.equal(evaluateGate(g, { Q4: A('b'), Q9: A('a') }), 'true');
});

test('[Q7≠c] — negation', () => {
  const g = parseGate('Q7≠c');
  assert.equal(evaluateGate(g, { Q7: A('c') }), 'false');
  assert.equal(evaluateGate(g, { Q7: A('a') }), 'true');
});

test('a ⚑gate with → next: on every option parses its previews', () => {
  const q = parseQuestionLine(
    '- **Q1** `[root]` ⚑gate — Pick a path · **(a)** left — goes west — **→ next:** western questions'
    + ' · **(b)** right — goes east — **→ next:** eastern questions · *default* (a)',
    { strict: true },
  );
  assert.equal(q.isGate, true);
  assert.deepEqual(q.options.map((o) => o.next), ['western questions', 'eastern questions']);
  assert.equal(q.options[0].consequence, 'goes west');
});

test('a ⚑gate missing a → next: throws in strict mode, and warns otherwise', () => {
  const line = '- **Q1** `[root]` ⚑gate — Pick · **(a)** left — **→ next:** west · **(b)** right · *default* (a)';
  assert.throws(() => parseQuestionLine(line, { strict: true }), GrammarError);
  const q = parseQuestionLine(line);
  assert.equal(q.warnings.length, 1);
  assert.match(q.warnings[0], /→ next/);
});

test('a gate naming a letter the referenced question does not offer is an error', () => {
  const { errors } = parseDocument(doc(
    '- **Q4** `[root]` — Pick · **(a)** one · **(b)** two · *default* (a)',
    '- **Q5** `[Q4=z]` — Follow-up · **(a)** yes · **(b)** no · *default* (a)',
  ));
  assert.equal(errors.length, 1);
  assert.match(errors[0].message, /Q4=z/);
});

test('a gate naming a question that does not exist is an error', () => {
  const { errors } = parseDocument(doc('- **Q5** `[Q99=a]` — Follow-up · **(a)** yes · **(b)** no · *default* (a)'));
  assert.equal(errors.length, 1);
  assert.match(errors[0].message, /Q99, which does not exist/);
});

test('both retired forms parse as retired, with no options', () => {
  const superseded = parseQuestionLine('- **Q140** — *superseded by QR5. Not asked.*');
  const settled = parseQuestionLine('- **Q15** — *settled: a free-text box is on every question, always. Not asked.*');
  for (const q of [superseded, settled]) {
    assert.equal(q.retired, true);
    assert.equal(q.options.length, 0);
  }
  assert.match(superseded.reason, /superseded by QR5/);
});

test('a section gate ANDs with each question gate', () => {
  const { questions } = parseDocument([
    '### 17.4 The reveal `[QR4=a]`',
    '',
    '- **QR4** `[root]` — Expand? · **(a)** yes · **(b)** no · *default* (a)',
    '- **Q43** `[Q44=a]` — How far? · **(a)** full · **(b)** part · *default* (a)',
    '- **Q44** `[root]` — Before? · **(a)** yes · **(b)** no · *default* (a)',
  ].join('\n'));
  const q43 = questions.find((q) => q.id === 'Q43');
  assert.equal(q43.effectiveGate.atoms.length, 2);
  assert.equal(evaluateGate(q43.effectiveGate, { Q44: A('a'), QR4: A('b') }), 'false');
  assert.equal(evaluateGate(q43.effectiveGate, { Q44: A('a'), QR4: A('a') }), 'true');
});

test('a question repeating its own section gate is not asked about it twice', () => {
  // Measured on the real Spotlight document: §17.2 is gated `[QR1=a]` and its questions carry
  // `[QR1=a]` too, so the question screen said "asked because QR1 = …" twice on one screen. The
  // conjunction of an atom with itself is that atom.
  const { questions } = parseDocument([
    '### 17.2 The mechanical rule `[QR1=a]`',
    '',
    '- **QR1** `[root]` — Mechanical? · **(a)** yes · **(b)** no · *default* (a)',
    '- **Q9** `[QR1=a]` — Ship the seam? · **(a)** now · **(b)** later · *default* (a)',
  ].join('\n'));
  const q9 = questions.find((q) => q.id === 'Q9');
  assert.equal(q9.effectiveGate.atoms.length, 1, 'one reason, not the same reason twice');
  assert.equal(q9.effectiveGate.text, 'QR1=a');
  assert.equal(describeGate(q9.effectiveGate, questions, { QR1: A('a') }).length, 1);
  assert.equal(evaluateGate(q9.effectiveGate, { QR1: A('b') }), 'false', 'and it still gates');
});

test('an option whose consequence contains a " — " of its own keeps it whole', () => {
  const q = parseQuestionLine(
    '- **Q1** `[root]` — Pick · **(a)** one — first — and then some · **(b)** two · *default* (a)',
  );
  assert.equal(q.options[0].label, 'one');
  assert.equal(q.options[0].consequence, 'first — and then some');
});

test('an option list of four, with the default marked among them', () => {
  const q = parseQuestionLine(
    '- **Q1** `[root]` — Pick · **(a)** one · **(b)** two · **(c)** three · **(d)** four · *default* (c) · notes',
  );
  assert.deepEqual(q.options.map((o) => o.letter), ['a', 'b', 'c', 'd']);
  assert.equal(q.default, 'c');
  assert.equal(q.notes, true);
});

test('a *default* naming a letter that is not an option is an error', () => {
  assert.throws(
    () => parseQuestionLine('- **Q1** `[root]` — Pick · **(a)** one · **(b)** two · *default* (z)'),
    /not one of its options/,
  );
});

test('a ⇒ hint is stripped and never parsed for meaning', () => {
  const q = parseQuestionLine(
    '- **Q49** `[root]` — Collapse? · **(a)** yes · **(b)** no · *default* (a) — (b) grows the board ⇒ (b) skips Q50',
  );
  assert.equal(q.default, 'a');
  assert.equal(q.defaultNote, '(b) grows the board');
  assert.equal(q.hint, '(b) skips Q50');
});

test('prose that merely mentions a question ID is not a question', () => {
  assert.equal(parseQuestionLine('- **Q61** — is E3 right, or should the whole set re-shuffle?'), null);
  const { questions, ignored, errors } = parseDocument(doc('- **Q61** — is E3 right, or should the set re-shuffle?'));
  assert.equal(questions.length, 0);
  assert.equal(errors.length, 0);
  assert.equal(ignored.length, 1);
});

test('fenced blocks are skipped, so a grammar example is not a question', () => {
  const { questions } = parseDocument([
    '## S', '', '```', '- **Q57** `[Q31=a]` — example · **(a)** x · **(b)** y · *default* (b)', '```', '',
  ].join('\n'));
  assert.equal(questions.length, 0);
});

test('a duplicate ID is an error', () => {
  const { errors } = parseDocument(doc(
    '- **Q1** `[root]` — a · **(a)** x · **(b)** y · *default* (a)',
    '- **Q1** `[root]` — b · **(a)** x · **(b)** y · *default* (a)',
  ));
  assert.match(errors[0].message, /duplicate ID/);
});

test('a gate cycle is an error', () => {
  const { errors } = parseDocument(doc(
    '- **Q1** `[Q2=a]` — a · **(a)** x · **(b)** y · *default* (a)',
    '- **Q2** `[Q1=a]` — b · **(a)** x · **(b)** y · *default* (a)',
  ));
  assert.ok(errors.some((e) => /gate cycle/.test(e.message)), 'a cycle must be reported');
});

test('a gate no answer can ever satisfy is an error', () => {
  const { errors } = parseDocument(doc(
    '- **Q1** `[root]` — a · **(a)** x · **(b)** y · *default* (a)',
    '- **Q2** `[Q1=a & Q1=b]` — b · **(a)** x · **(b)** y · *default* (a)',
  ));
  assert.ok(errors.some((e) => /never be satisfied/.test(e.message)));
});

test('reachability separates PENDING from PRUNED (chart C7 vs C10)', () => {
  const { questions } = parseDocument(doc(
    '- **Q4** `[root]` — a · **(a)** x · **(b)** y · *default* (a)',
    '- **Q9** `[root]` — b · **(a)** x · **(b)** y · *default* (a)',
    '- **Q20** `[Q4=b & Q9=a]` — c · **(a)** x · **(b)** y · *default* (a)',
  ));
  let r = reachability(questions, {});
  assert.deepEqual(r.pending.map((q) => q.id), ['Q20']);
  r = reachability(questions, { Q4: A('b') });
  assert.deepEqual(r.pending.map((q) => q.id), ['Q20'], 'still pending while Q9 is unanswered');
  r = reachability(questions, { Q4: A('a') });
  assert.deepEqual(r.pruned.map((q) => q.id), ['Q20'], 'one false atom prunes without waiting');
});

test('blastRadius strands transitively and restores on the way back', () => {
  const { questions } = parseDocument(doc(
    '- **Q1** `[root]` — a · **(a)** x · **(b)** y · *default* (a)',
    '- **Q2** `[Q1=a]` — b · **(a)** x · **(b)** y · *default* (a)',
    '- **Q3** `[Q2=a]` — c · **(a)** x · **(b)** y · *default* (a)',
  ));
  const answers = { Q1: A('a'), Q2: A('a'), Q3: A('a') };
  const away = blastRadius(questions, answers, 'Q1', { option: 'b' });
  assert.deepEqual(away.strand, ['Q2', 'Q3'], 'stranding cascades down the chain');
  const stranded = { Q1: A('b'), Q2: { ...A('a'), active: false }, Q3: { ...A('a'), active: false } };
  const back = blastRadius(questions, stranded, 'Q1', { option: 'a' });
  assert.deepEqual(back.restore, ['Q2', 'Q3'], 'and nothing typed is lost');
});

test('ordering is document order within a section, sections by gate weight (§5.5)', () => {
  const { questions, sections } = parseDocument([
    '### 0 roots', '',
    '- **QR1** `[root]` — root · **(a)** x · **(b)** y · *default* (a)',
    '- **Q1** `[root]` — first · **(a)** x · **(b)** y · *default* (a)',
    '', '### 1 detail `[QR1=a]`', '',
    '- **Q2** `[root]` — gated · **(a)** x · **(b)** y · *default* (a)',
  ].join('\n'));
  assert.equal(nextQuestion(questions, {}, sections).id, 'QR1', 'roots come first');
  assert.equal(nextQuestion(questions, { QR1: A('a') }, sections).id, 'Q2', 'the heavier section unlocks ahead');
  assert.equal(nextQuestion(questions, { QR1: A('b') }, sections).id, 'Q1', 'and is gone entirely when pruned');
});


// --- THE DAG AUDITS (grammar.auditGates) -------------------------------------------------------
// Three defects that leave a document parsing, validating and answering perfectly while silently
// withholding questions from the owner. All three cost real rounds on solatro/spotlight before the
// audit existed; these pin the exact shapes so they cannot come back unreported.

const AUDIT_DOC = (extra) => `# Audit

## 1 roots

- **QR1** \`[root]\` ⚑gate — Root? · **(a)** yes — **→ next:** more · **(b)** no — **→ next:** nothing · *default* (a)
${extra}
`;

test('audit: a question that gates another but is not marked ⚑gate', () => {
  const md = AUDIT_DOC(`- **Q1** \`[root]\` — Plain, but it gates Q2 · **(a)** yes · **(b)** no · *default* (a)
- **Q2** \`[Q1=a]\` — Downstream · **(a)** yes · **(b)** no · *default* (a)`);
  const { questions, sections } = parseDocument(md);
  const hits = auditGates(questions, sections).map((w) => w.message);
  assert.ok(hits.some((m) => /^Q1 gates 1 question\(s\) but is not marked/.test(m)),
    'an unmarked gating question amputates its subtree on any free-text answer');

  // Marking it clears the audit — the fix must actually be the fix.
  const fixed = md.replace('- **Q1** `[root]` —', '- **Q1** `[root]` ⚑gate —');
  const p2 = parseDocument(fixed);
  assert.deepEqual(auditGates(p2.questions, p2.sections).filter((w) => /not marked/.test(w.message)), []);
});

test('audit: a new option orphaned from a multi-letter gate its default should be in', () => {
  // `[Q1=a|b]` enumerates who reaches Q2. Adding (c) as the DEFAULT without widening that set is
  // exactly how Q113=(d) came to orphan Q114 — origin_rise, the number that sets every beam length.
  const md = AUDIT_DOC(`- **Q1** \`[root]\` ⚑gate — Which? · **(a)** a — **→ next:** more · **(b)** b — **→ next:** more · **(c)** c — **→ next:** more · *default* (c)
- **Q2** \`[Q1=a|b]\` — Downstream · **(a)** yes · **(b)** no · *default* (a)`);
  const { questions, sections } = parseDocument(md);
  assert.ok(auditGates(questions, sections).some((w) => /DEFAULT \(c\) is not among them/.test(w.message)));

  // ⚠ AND IT MUST STAY QUIET ON A LEGITIMATE DECLINE, or it gets muted and catches nothing.
  // Here (b) reaches nothing on purpose and is NOT the default: that is a sub-feature being turned
  // down, not an omission. Reporting every orphan produced 24 such warnings on Spotlight.
  const decline = AUDIT_DOC(`- **Q1** \`[root]\` ⚑gate — Which? · **(a)** yes — **→ next:** more · **(b)** decline — **→ next:** nothing · *default* (a)
- **Q2** \`[Q1=a]\` — Downstream · **(a)** yes · **(b)** no · *default* (a)`);
  const p2 = parseDocument(decline);
  assert.deepEqual(auditGates(p2.questions, p2.sections).filter((w) => /DEFAULT/.test(w.message)), []);
});

test('audit: a section heading narrower than its own question lines', () => {
  // reachability() evaluates effectiveGate, so the HEADING wins. Widening the lines to `a|c` and
  // leaving the heading at `a` keeps the whole section pruned — which is what stranded 20 answers
  // the moment the owner clicked the option they had been told to click.
  const md = `# Audit

## 1 roots

- **QR1** \`[root]\` ⚑gate — Root? · **(a)** a — **→ next:** more · **(b)** b — **→ next:** more · **(c)** c — **→ next:** more · *default* (a)

## 2 detail \`[QR1=a]\`

- **Q1** \`[QR1=a|c]\` — Widened on the line but not the heading · **(a)** yes · **(b)** no · *default* (a)
`;
  const { questions, sections } = parseDocument(md);
  const hits = auditGates(questions, sections).map((w) => w.message);
  assert.ok(hits.some((m) => /Q1: gate admits QR1=c but its section/.test(m)),
    'the heading silently overrides the line');
});

// --- THE ACCEPTANCE TEST (PLAN S2, §5.6) ------------------------------------------------------
// The document is not edited to make it parse. If it does not parse, the grammar is wrong.

// ⚠ THESE ASSERT PROPERTIES, NOT COUNTS, AND THAT IS THE POINT (2026-08-03).
// They used to pin `188 questions + 8 QR gates`, `195 live` and `longestPath === 194`. Spotlight is
// a LIVING document: it went 195 -> 275 questions across four ordinary design revisions and broke
// five tests in this suite every time, none of which had found a defect. A tool's suite that fails
// whenever a document it reads is edited is measuring the wrong thing — the invariant is "the
// acceptance document still parses clean and its DAG is still sound", not "it still has 188
// questions". Counts are REPORTED (`npm run check` prints them) rather than asserted.
test('the Spotlight DESIGN.md parses clean and keeps its structural invariants', () => {
  const md = readFileSync(resolve(REPO, 'solatro/design/spotlight/DESIGN.md'), 'utf8');
  const { questions, errors, warnings } = parseDocument(md);

  assert.deepEqual(errors.map((e) => e.message), [], 'the acceptance document must parse clean');
  assert.deepEqual(warnings.map((w) => w.id), [], 'and warning-free: every ⚑gate option previews');

  const qr = questions.filter((q) => q.id.startsWith('QR'));
  assert.ok(qr.length >= 8, 'the root forks are still roots');
  assert.equal(qr.every((q) => q.isGate), true, 'every root fork is a ⚑gate');
  assert.ok(questions.length > qr.length, 'and there are numbered questions below them');

  // Q140 is retired IN PLACE. IDs are never renumbered, so a retired one may never come back to
  // life or be reused. ⚠ deepEqual, not `.every()` — `every` on an empty array is vacuously true,
  // so reviving Q140 would have passed silently. Retirements do not grow with the living document
  // (unlike the counts above), so pinning the exact set is safe; a NEW deliberate retirement
  // updates this line.
  assert.deepEqual(questions.filter((q) => q.retired).map((q) => q.id), ['Q140']);
});

test('the Spotlight DAG validates: no cycle, no undefined ID or letter, nothing unreachable', () => {
  const md = readFileSync(resolve(REPO, 'solatro/design/spotlight/DESIGN.md'), 'utf8');
  const { questions, sections } = parseDocument(md);
  assert.deepEqual(validate(questions, sections).map((e) => e.message), []);
  assert.ok(questions.filter((q) => !q.retired).length > 0, 'and it is not empty');
});

// ⚠ THE REAL INVARIANT ABOUT GATING, and it is the one that has actually caught bugs.
// Every question named in another question's gate must itself be marked ⚑gate. Without the mark, a
// free-text answer — which has no letter, so no gate naming it can ever be true — amputates the
// whole subtree in SILENCE: no warning, no round ending, nothing on screen. Measured on Spotlight
// 2026-08-03: six unmarked gating questions, 20 questions never asked, and the round still reported
// `done (complete)`. `run check` counts gates but has never verified this.
test('every question that gates another is marked ⚑gate', () => {
  const md = readFileSync(resolve(REPO, 'solatro/design/spotlight/DESIGN.md'), 'utf8');
  const { questions } = parseDocument(md);
  const marked = new Set(questions.filter((q) => q.isGate).map((q) => q.id));
  const named = new Set();
  for (const q of questions) {
    for (const atom of (q.effectiveGate || q.gate)?.atoms || []) named.add(atom.id);
  }
  assert.deepEqual([...named].filter((id) => !marked.has(id)), [],
    'an unmarked gating question amputates its subtree without saying so');
});

// ⚠ AND THE OTHER HALF: an option that appears in NO downstream gate prunes everything below it.
// A newly added option is by construction absent from every gate written earlier, so it orphans its
// subtree by DEFAULT. Caught `Q113=(d)` orphaning `Q114` — `origin_rise`, the number that sets every
// beam's length. A legitimate "decline this sub-feature" option looks identical, so this asserts the
// known-good set rather than emptiness.
test('no option silently orphans its subtree except the known declines', () => {
  const md = readFileSync(resolve(REPO, 'solatro/design/spotlight/DESIGN.md'), 'utf8');
  const { questions } = parseDocument(md);
  const covered = new Map();
  for (const q of questions) {
    for (const atom of (q.effectiveGate || q.gate)?.atoms || []) {
      if (!covered.has(atom.id)) covered.set(atom.id, new Set());
      if (atom.op === '=') atom.letters.forEach((l) => covered.get(atom.id).add(l));
      else covered.get(atom.id).add('*');
    }
  }
  const orphans = [];
  for (const q of questions) {
    const seen = covered.get(q.id);
    if (!seen || seen.has('*')) continue;
    for (const o of q.options) if (!seen.has(o.letter)) orphans.push(`${q.id}=${o.letter}`);
  }
  // Each of these is a deliberate "decline the whole sub-feature" branch — pruning IS its job.
  const DECLINES = new Set([
    'QR1=b', 'QR2=b', 'QR4=b', 'QR6=b', 'QR7=b', 'QR9=a', 'Q3=a', 'Q22=a', 'Q31=b', 'Q35=b',
    'Q49=b', 'Q66=b', 'Q98=a', 'Q100=b', 'Q122=b', 'Q131=a', 'Q136=b', 'Q149=a', 'Q213=b',
    'Q251=a', 'Q260=c',
  ]);
  assert.deepEqual(orphans.filter((o) => !DECLINES.has(o)), [],
    'an option reaching nothing is usually a new option whose subtree was never widened');
});

test('the Spotlight questionnaire opens at QR1 and QR1=(b) prunes §17.2', () => {
  const md = readFileSync(resolve(REPO, 'solatro/design/spotlight/DESIGN.md'), 'utf8');
  const { questions, sections } = parseDocument(md);

  assert.equal(nextQuestion(questions, {}, sections).id, 'QR1');

  const before = reachability(questions, {}).pruned.length;
  const after = reachability(questions, { QR1: A('b') }).pruned;
  assert.ok(after.length > before, 'answering the root gate prunes');
  // §17.2 "The mechanical rule" is gated [QR1=a] as a whole section.
  assert.ok(after.some((q) => q.id === 'Q9'), 'Q9 (§17.2) is pruned by QR1=(b)');
  assert.ok(after.filter((q) => q.sectionTitle.includes('mechanical rule')).length >= 20);
});

// The document's §0 estimates "the longest possible path is ~150". The DAG does not bear that out:
// only ONE pair of questions in the whole set is mutually exclusive (Q118 `[Q113=a]` against
// Q114 `[Q113=b|c]`), so a single set of answers reaches 194 of the 195 live questions. The ~150 is
// a hand estimate, not a property of the gates — recorded in ASSUMPTIONS.md and reported to the
// owner rather than papered over. This test pins the measured number so it cannot drift silently.
test('the longest path through Spotlight is nearly every live question', () => {
  const md = readFileSync(resolve(REPO, 'solatro/design/spotlight/DESIGN.md'), 'utf8');
  const { questions } = parseDocument(md);
  const live = questions.filter((q) => !q.retired).length;
  const longest = longestPath(questions);
  // The DAG barely prunes on the DEFAULT path: almost every root default is the "include this"
  // branch, so one set of answers reaches nearly the whole document. That is a real property worth
  // pinning — and it is the one the document's own §0 must keep telling the owner honestly — but it
  // is a RATIO, not a number that has to be re-typed whenever a question is added.
  assert.ok(longest > live * 0.9, `longest path ${longest} of ${live} live: the DAG saves little`);
  assert.ok(longest <= live);
});

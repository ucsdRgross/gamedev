// PLAN S2 / §5.6 — the question grammar, one case per construct, plus THE acceptance test:
// `solatro/SPOTLIGHT_DESIGN.md` parsing unchanged.

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';
import {
  parseDocument, parseQuestionLine, parseGate, evaluateGate, reachability,
  nextQuestion, blastRadius, validate, longestPath, GrammarError,
} from '../src/grammar.mjs';

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

// --- THE ACCEPTANCE TEST (PLAN S2, §5.6) ------------------------------------------------------
// The document is not edited to make it parse. If it does not parse, the grammar is wrong.

test('SPOTLIGHT_DESIGN.md parses unchanged: 188 questions + 8 QR gates, zero errors', () => {
  const md = readFileSync(resolve(REPO, 'solatro', 'SPOTLIGHT_DESIGN.md'), 'utf8');
  const { questions, errors, warnings } = parseDocument(md);

  assert.deepEqual(errors.map((e) => e.message), [], 'the acceptance document must parse clean');

  const qr = questions.filter((q) => q.id.startsWith('QR'));
  const numbered = questions.filter((q) => !q.id.startsWith('QR'));
  assert.equal(qr.length, 8, 'eight root gates');
  assert.equal(numbered.length, 188, '188 numbered questions');
  assert.equal(qr.every((q) => q.isGate), true, 'every root fork is a ⚑gate');

  // The one documented shortfall, tracked as gaps/GAP-001.md: QR8's option (a) has no → next:.
  assert.deepEqual(warnings.map((w) => w.id), ['QR8'], 'exactly one known warning');

  const retired = questions.filter((q) => q.retired);
  assert.deepEqual(retired.map((q) => q.id), ['Q140'], 'Q140 is retired in place, never renumbered');
});

test('the Spotlight DAG validates: no cycle, no undefined ID or letter, nothing unreachable', () => {
  const md = readFileSync(resolve(REPO, 'solatro', 'SPOTLIGHT_DESIGN.md'), 'utf8');
  const { questions, sections } = parseDocument(md);
  assert.deepEqual(validate(questions, sections).map((e) => e.message), []);

  // Every question is reachable under SOME assignment, which is what "no unreachable question"
  // means for a DAG whose leaves depend on choices nobody has made yet.
  const reachableSomewhere = questions.filter((q) => !q.retired).length;
  assert.equal(reachableSomewhere, 195);
});

test('the Spotlight questionnaire opens at QR1 and QR1=(b) prunes §17.2', () => {
  const md = readFileSync(resolve(REPO, 'solatro', 'SPOTLIGHT_DESIGN.md'), 'utf8');
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
test('the longest path through Spotlight is 194 of 195 live questions', () => {
  const md = readFileSync(resolve(REPO, 'solatro', 'SPOTLIGHT_DESIGN.md'), 'utf8');
  const { questions } = parseDocument(md);
  assert.equal(longestPath(questions), 194);
});

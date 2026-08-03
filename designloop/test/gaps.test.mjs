// PLAN S15 — the gap surface: gaps read as draft questions, stale plan steps, promotion.
//
// The acceptance gate S15 states: "a hand-written gap file appears as a badge and generates a
// one-question scoped round." The badge half is the registry's counts; the round half is
// `scopedQuestions` / `nextGapQuestion`, driven over HTTP in `api.test.mjs`.

import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, mkdir, writeFile, readFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { readFile as read } from 'node:fs/promises';

import {
  parseGap, readGaps, countGaps, scopedQuestions, nextGapQuestion, planSteps, staleSteps, staleFor,
  nextGapId, promoteAssumption, nodesIn, isGapId, readPlanSteps,
} from '../src/gaps.mjs';

/** A gap written exactly as the SKILL.md template says, by hand, as an executing agent would. */
const OPEN_GAP = `# GAP-002 — the empty deck case is not covered
status: open
raised: 2026-08-02, during execution plan step S7
design: \`DESIGN.md\` nodes D4, D6
severity: GAP

**What the design says** — D4 draws the next card and D6 scores it.

**What it does not say** — what happens when the deck is empty at D4. Two readings of chart D are
equally defensible and they differ in what the player sees.

**Why it blocks** — GAP: two defensible choices differ in observable behaviour.

**Options I can see** — **(a)** reshuffle the discard — the run never ends on an empty deck ·
**(b)** end the round — an empty deck is a real ending, and the player can plan for it ·
*my recommendation* (b) — an infinite deck removes the only resource pressure in the mode

**Blast radius** — plan steps S7, S9; design nodes D4, D6

**Meanwhile** — parked the deck thread; continued on scoring.
`;

const CLOSED_GAP = `# GAP-001 — a settled one
status: resolved
raised: 2026-08-01, during execution plan step S2
severity: CONTRADICTION
resolution: |
  the owner chose (b): a warning, not an error, and the document was never edited.

**What the design says** — two incompatible things.

**Options I can see** — **(a)** error · **(b)** warning · *my recommendation* (b)

**Blast radius** — plan steps S2; design nodes B7a
`;

test('a hand-written gap parses into a question in the questionnaire grammar (J8)', () => {
  const gap = parseGap('GAP-002.md', OPEN_GAP);
  assert.equal(gap.id, 'GAP-002');
  assert.equal(gap.status, 'open');
  assert.equal(gap.open, true);
  assert.equal(gap.severity, 'GAP');
  assert.equal(gap.title, 'the empty deck case is not covered');

  const q = gap.question;
  assert.ok(q, 'the gap IS a draft question');
  assert.equal(q.id, 'GAP-002');
  assert.equal(q.options.length, 2);
  assert.equal(q.options[0].letter, 'a');
  assert.equal(q.options[0].label, 'reshuffle the discard');
  assert.equal(q.options[0].consequence, 'the run never ends on an empty deck');
  // `*my recommendation*` is the gap template's word for `*default*`; the grammar module never
  // learns a second spelling, so the normalisation has to happen here and has to work.
  assert.equal(q.default, 'b');
  // Q110=a — a gap is the case `notes` exists for: the agent could not decide it.
  assert.equal(q.notes, true);
  assert.equal(q.gate.root, true, 'a gap question is asked unconditionally in its scoped round');
});

test('the report travels with the question, so the screen stays self-contained (rule 4)', () => {
  const gap = parseGap('GAP-002.md', OPEN_GAP);
  const labels = gap.context.map((c) => c.label);
  assert.deepEqual(labels, ['What the design says', 'What it does not say', 'Why it blocks', 'Meanwhile']);
  const notSaid = gap.context.find((c) => c.label === 'What it does not say').value;
  assert.match(notSaid, /empty at D4/, 'a paragraph that wraps over source lines is joined');
  assert.match(notSaid, /differ in what the player sees\.$/, 'and it stops at the next field');
});

test('bold at the start of a wrapped line is not mistaken for the next field', () => {
  // Measured against the real GAP-001, whose "what it does not say" wraps onto a line beginning
  // `**zero errors**`. A field is a capitalised bold phrase followed by a dash; emphasis is not.
  const gap = parseGap('GAP-003.md', `# GAP-003 — wrapping
status: open

**What it does not say** — the document must parse unchanged, with
**zero errors**, and nothing else.

**Options I can see** — **(a)** one ·
**(b)** two · *my recommendation* (a)

**Blast radius** — plan steps S1
`);
  assert.equal(gap.context[0].value, 'the document must parse unchanged, with **zero errors**, and nothing else.');
  assert.deepEqual(gap.question.options.map((o) => o.label), ['one', 'two'], 'and a wrapped option is still an option');
  assert.deepEqual(gap.blast.steps, ['S1'], 'the field after it is still found');
});

test('the blast radius separates plan steps from design nodes', () => {
  const gap = parseGap('GAP-002.md', OPEN_GAP);
  assert.deepEqual(gap.blast.steps, ['S7', 'S9']);
  assert.deepEqual(gap.blast.nodes, ['D4', 'D6']);
});

test('a closed gap keeps its resolution and is not asked again (Q96b=a, Q91b=a)', () => {
  const closed = parseGap('GAP-001.md', CLOSED_GAP);
  assert.equal(closed.open, false);
  assert.match(closed.resolution, /the owner chose \(b\)/);
  assert.equal(scopedQuestions([closed]).length, 0, 'a closed gap is kept, not re-asked');
  const counts = countGaps([closed, parseGap('GAP-002.md', OPEN_GAP)]);
  assert.deepEqual(counts, { open: 1, closed: 1, total: 2 });
});

test('the scoped round asks the open gaps and stops (chart J12)', () => {
  const gaps = [parseGap('GAP-001.md', CLOSED_GAP), parseGap('GAP-002.md', OPEN_GAP)];
  assert.deepEqual(scopedQuestions(gaps).map((q) => q.id), ['GAP-002']);
  assert.equal(nextGapQuestion(gaps, {})?.id, 'GAP-002');
  assert.equal(nextGapQuestion(gaps, { 'GAP-002': { option: 'b', active: true } }), null);
  // A stranded answer is not an answer: the gap comes back, like any other question (Q35=a).
  assert.equal(nextGapQuestion(gaps, { 'GAP-002': { option: 'b', active: false } })?.id, 'GAP-002');
});

test('plan steps are read with their citations, ranges expanded (Q93b=a)', async () => {
  const steps = planSteps(await read(new URL('../design/designloop/PLAN.md', import.meta.url), 'utf8'));
  assert.equal(steps.length, 19, 'S1–S19, exactly the steps in the plan');
  // The two review steps cite nodes that did not exist until the review that produced them, which
  // is what keeps a finding traceable back to the screen it came from.
  assert.ok(steps.find((s) => s.id === 'S19').cites.includes('B19'), 'S19 cites what it implements');
  assert.ok(steps.find((s) => s.id === 'S19').cites.includes('D14'));
  const s7 = steps.find((s) => s.id === 'S7');
  assert.ok(s7.cites.includes('D4') && s7.cites.includes('D9'), 'D1–D9 is a range, and it expands');
  assert.ok(s7.cites.includes('Q36b'), 'a lettered ID is its own question, not its number');
  assert.equal(steps.find((s) => s.id === 'S11').cites.join(','), 'G2,F12,F14,Q64');
});

test('only steps citing a changed node are stale — the rest keep their work (J16, J17)', async () => {
  const steps = planSteps(await read(new URL('../design/designloop/PLAN.md', import.meta.url), 'utf8'));
  const stale = staleSteps(steps, { nodes: ['D4', 'D6'], steps: [] });
  assert.deepEqual(stale.map((s) => s.id), ['S7'], 'D4/D6 live in chart D, which only S7 implements');
  assert.deepEqual(stale[0].because, ['D4', 'D6'], 'and it says which node did it');
  assert.equal(staleSteps(steps, { nodes: [], steps: ['S9'] })[0].named, true, 'a step named outright');
  assert.equal(staleSteps(steps, { nodes: ['ZZ99'] }).length, 0, 'a node nothing cites strands nothing');
});

test('an OPEN gap makes steps stale; a closed one already became a design version', () => {
  const steps = [
    { id: 'S7', line: 1, title: 'back and history', cites: ['D4', 'D9'] },
    { id: 'S12', line: 2, title: 'canvas', cites: ['F2'] },
  ];
  const gaps = [parseGap('GAP-001.md', CLOSED_GAP), parseGap('GAP-002.md', OPEN_GAP)];
  const stale = staleFor(gaps, steps);
  assert.deepEqual(stale.map((s) => s.id), ['S7']);
  assert.equal(stale[0].gap, 'GAP-002');
  assert.equal(staleFor([gaps[0]], steps).length, 0, 'a resolved gap is not still blocking anything');
});

test('the real GAP-001 in this repo reads as closed, with its options and its resolution', async () => {
  const dir = new URL('../design/designloop/', import.meta.url);
  const gaps = await readGaps(dir.pathname.replace(/^\/([A-Za-z]:)/, '$1'));
  const one = gaps.find((g) => g.id === 'GAP-001');
  assert.ok(one, 'the tool finds its own gap');
  assert.equal(one.open, false);
  assert.equal(one.question.options.length, 3);
  assert.equal(one.question.default, 'b', 'the resolution the owner actually chose');
  assert.match(one.resolution, /warns by default/);
});

test('promoting an assumption files an open gap with no options (Q95b=a, Q94=a)', async () => {
  const dir = await mkdtemp(join(tmpdir(), 'designloop-gaps-'));
  try {
    await mkdir(join(dir, 'gaps'), { recursive: true });
    await writeFile(join(dir, 'gaps', 'GAP-001.md'), CLOSED_GAP, 'utf8');
    assert.equal(nextGapId(await readGaps(dir)), 'GAP-002');

    const filed = await promoteAssumption(dir, {
      assumption: 'the chart title is the nearest preceding heading',
      step: 'S11 / §4.6',
      nodes: ['Q64'],
    });
    assert.equal(filed.id, 'GAP-002');

    const gaps = await readGaps(dir);
    const promoted = gaps.find((g) => g.id === 'GAP-002');
    assert.equal(promoted.open, true, 'it is open the moment it is filed');
    assert.equal(promoted.question, null, 'the tool does not author the options — the agent does');
    assert.deepEqual(promoted.blast.steps, ['S11']);
    assert.deepEqual(promoted.blast.nodes, ['Q64']);
    assert.match(promoted.context.find((c) => c.label === 'What it does not say').value,
      /nearest preceding heading/, 'the assumption itself is what the gap is about');

    // The whole point of promotion: the step that relied on it is stale from this moment.
    const steps = [{ id: 'S11', line: 1, title: 'graph ingestion', cites: ['G2', 'Q64'] }];
    assert.deepEqual(staleFor(gaps, steps).map((s) => s.id), ['S11']);

    // "Do not delete or edit a gap" — the closed one is untouched by any of this.
    assert.equal(await readFile(join(dir, 'gaps', 'GAP-001.md'), 'utf8'), CLOSED_GAP);
    assert.deepEqual(await readPlanSteps(dir), [], 'a design with no plan simply has no steps');
  } finally {
    await rm(dir, { recursive: true, force: true });
  }
});

test('a gap ID is told apart from a question ID, because both key one answers file', () => {
  assert.equal(isGapId('GAP-002'), true);
  assert.equal(isGapId('Q88b'), false);
  assert.equal(isGapId('QR1'), false);
  assert.deepEqual(nodesIn('J8–J10, Q86'), ['J8', 'J9', 'J10', 'Q86']);
});

// src/provenance.mjs — the distance between an ANSWER and what the documents say it was.
//
// Every case here is the solatro/spotlight 2026-08-04 incident reduced to its smallest form: one
// free-text answer, two documents paraphrasing it, and an executor filing a gap on the difference
// between the paraphrases. The acceptance document is exercised at the bottom, the same way the
// grammar tests use it — never asserting counts, only that the reports are computable and that the
// one defect the incident turned on is visible.

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { parseDocument } from '../src/grammar.mjs';
import { readJson } from '../src/store.mjs';
import {
  normalise, sharesPhrase, citationLines, restatementsOf,
  softAnswers, quoteAudit, normativeBlocks, contractAudit,
} from '../src/provenance.mjs';

const REPO = resolve(fileURLToPath(new URL('../..', import.meta.url)));
const SPOTLIGHT = resolve(REPO, 'solatro/design/spotlight');

// The real Q16 note, verbatim — the string the whole incident is about.
const Q16_NOTE = 'whole act? increases or decreases based on cards being scored. dims after '
  + 'initially showing, but gets revealed again at start of next scoring section';

test('normalise folds emphasis, smart punctuation and whitespace', () => {
  assert.equal(normalise('**Whole   act** — “yes”'), 'whole act - "yes"');
});

test('sharesPhrase finds a carried-over run of words, not a paraphrase', () => {
  assert.ok(sharesPhrase('the set increases or decreases based on cards being scored, so', Q16_NOTE));
  // This is the actual failure: a summary that means the right thing and carries none of the words.
  assert.ok(!sharesPhrase('forced_spotlight stays set for the whole act', Q16_NOTE));
});

test('sharesPhrase needs a real run, not one shared word', () => {
  assert.ok(!sharesPhrase('whole', Q16_NOTE));
  assert.ok(!sharesPhrase('the act is whole and the cards are scored', Q16_NOTE));
});

test('citationLines skips fenced blocks', () => {
  const text = ['prose about Q12', '```', 'Q99 inside a fence', '```', 'more about Q12 and Q13'].join('\n');
  const hits = citationLines(text);
  assert.deepEqual(hits.map((h) => h.line), [1, 5]);
  assert.deepEqual(hits[1].ids, ['Q12', 'Q13']);
});

test("restatementsOf can exclude a question's own bullet", () => {
  const docs = [{ name: 'D.md', text: ['- **Q16** `[root]` — the question · **(a)** x · *default* (a)', 'D20 restates Q16 badly'].join('\n') }];
  assert.equal(restatementsOf('Q16', docs).length, 2);
  const others = restatementsOf('Q16', docs, { includeSelf: false });
  assert.equal(others.length, 1);
  assert.equal(others[0].line, 2);
});

test('softAnswers lists answers with a note and no option, and flags the hedged ones', () => {
  const questions = parseDocument(
    '- **Q16** `[root]` — persists how long? · **(a)** its line · **(b)** the act · *default* (a)\n'
    + '- **Q17** `[root]` — bump revision? · **(a)** no · **(b)** yes · *default* (a)\n',
  ).questions;
  const soft = softAnswers({
    Q16: { option: null, note: Q16_NOTE },
    Q17: { option: 'a', note: '' },
    Q18: { option: null, note: '' },
  }, questions);
  assert.deepEqual(soft.map((s) => s.id), ['Q16']);
  // Q16's note literally opens "whole act?" — a question mark inside an ANSWER, which is the
  // strongest provisional signal there is and which survived four rounds unnoticed.
  assert.equal(soft[0].provisional, true);
  assert.equal(soft[0].promoted, false);
});

test('softAnswers marks an answer PROMOTED once an option carries the owner\'s words', () => {
  const questions = parseDocument(
    '- **Q16** `[root]` — persists how long? · **(a)** its line · '
    + '**(b)** the whole act, and it increases or decreases based on cards being scored · '
    + '*default* (b)\n',
  ).questions;
  const soft = softAnswers({ Q16: { option: null, note: Q16_NOTE } }, questions);
  assert.equal(soft[0].promoted, true);
});

test('quoteAudit catches the document that paraphrases and clears the one that quotes', () => {
  const questions = parseDocument(
    '- **Q16** `[root]` — persists how long? · **(a)** its line · **(b)** the act · *default* (a)\n',
  ).questions;
  const answers = { Q16: { option: null, note: Q16_NOTE } };
  const bad = { name: 'PLAN.md', text: 'The forced set is per-act state (`Q16` whole act).' };
  const good = {
    name: 'DESIGN.md',
    text: 'D20 (`Q16`): it "increases or decreases based on cards being scored", so it travels.',
  };
  const hits = quoteAudit(answers, questions, [bad, good]);
  assert.deepEqual(hits.map((h) => h.doc), ['PLAN.md']);
  assert.deepEqual(hits[0].lines, [1]);
});

test('quoteAudit says nothing about a document that never cites the answer', () => {
  const questions = parseDocument(
    '- **Q16** `[root]` — persists? · **(a)** yes · **(b)** no · *default* (a)\n',
  ).questions;
  const hits = quoteAudit({ Q16: { option: null, note: Q16_NOTE } }, questions,
    [{ name: 'OTHER.md', text: 'nothing to do with any of this' }]);
  assert.deepEqual(hits, []);
});

test('normativeBlocks reads §1 through GDScript doc comments', () => {
  // ⚠ The regression this pins: `##` opens a GDScript doc comment AND a markdown heading, so a
  // parser that tests headings before fences walks out of §1 on the first contract's first line.
  // The first draft reported "0 normative blocks" for a document with seven.
  const plan = [
    '## 0. Preamble', 'not a contract', '',
    '## 1. NORMATIVE CONTRACTS', '', '### 1.4 The block seam (`Q9`=a)', '',
    '```gdscript', '## Does this card hide what is under it?', 'func blocks_spotlight() -> bool:',
    '    return true', '```', '',
    '## 2. Phase 1', '```gdscript', 'not normative', '```',
  ].join('\n');
  const blocks = normativeBlocks(plan);
  assert.equal(blocks.length, 1);
  assert.equal(blocks[0].lang, 'gdscript');
  assert.match(blocks[0].code, /return true/);
  // The heading is provenance too — most sections say which answers they implement there.
  assert.deepEqual(blocks[0].cites, ['Q9']);
});

test('contractAudit reports a contract no ⚑contract question authorises', () => {
  const questions = parseDocument(
    '- **Q9** `[root]` — ship the seam now? · **(a)** now · **(b)** later · *default* (a)\n',
  ).questions;
  const plan = ['## 1. NORMATIVE CONTRACTS', '### 1.4 The seam (`Q9`=a)', '```gdscript',
    'func blocks_spotlight() -> bool: return false', '```'].join('\n');
  const audit = contractAudit(questions, plan);
  // Q9 decided WHETHER to ship, never what the default was — so the default was invented, and
  // inverted. That is the whole reason the tag exists.
  assert.equal(audit.unauthorised.length, 1);
  assert.deepEqual(audit.contracts, []);
});

test('contractAudit clears the block once the question is ⚑contract, and reports the reverse', () => {
  const questions = parseDocument(
    '- **Q9** `[root]` ⚑contract — ship the seam, and with what default? · **(a)** blocks · '
    + '**(b)** passes · *default* (a)\n'
    + '- **Q31** `[root]` ⚑contract — what is in the set? · **(a)** the line · **(b)** the meld · '
    + '*default* (a)\n',
  ).questions;
  const plan = ['## 1. NORMATIVE CONTRACTS', '### 1.4 The seam (`Q9`=a)', '```gdscript',
    'func blocks_spotlight() -> bool: return true', '```'].join('\n');
  const audit = contractAudit(questions, plan);
  assert.deepEqual(audit.unauthorised, []);
  // Q31 is ⚑contract and nothing wrote it down — an answer that was meant to become a contract.
  assert.deepEqual(audit.uncontracted, ['Q31']);
});

test('⚑contract and ⚑gate are independent and parse in either order', () => {
  const both = parseDocument(
    '- **Q1** `[root]` ⚑gate ⚑contract — a · **(a)** x — **→ next:** y · *default* (a)\n'
    + '- **Q2** `[root]` ⚑contract ⚑gate — b · **(a)** x — **→ next:** y · *default* (a)\n'
    + '- **Q3** `[root]` — c · **(a)** x · *default* (a)\n',
  ).questions;
  assert.deepEqual(both.map((q) => [q.isGate, q.isContract]),
    [[true, true], [true, true], [false, false]]);
});

// --- the acceptance document -------------------------------------------------------------------
// Never asserts counts (it is a LIVING document, §grammar tests) — only that every report is
// computable against the real thing, and that the answer the incident turned on is now quoted.

test('spotlight: the provenance reports run against the real design', async (t) => {
  const doc = await readFile(resolve(SPOTLIGHT, 'DESIGN.md'), 'utf8').catch(() => null);
  if (doc === null) return t.skip('acceptance document not present');
  const plan = await readFile(resolve(SPOTLIGHT, 'PLAN.md'), 'utf8').catch(() => '');
  const answers = (await readJson(resolve(SPOTLIGHT, 'answers.json')))?.answers || {};
  const parsed = parseDocument(doc);
  const docs = [{ name: 'DESIGN.md', text: doc }, { name: 'PLAN.md', text: plan }];

  assert.ok(softAnswers(answers, parsed.questions).length > 0, 'spotlight has free-text answers');
  assert.ok(Array.isArray(quoteAudit(answers, parsed.questions, docs)));

  const audit = contractAudit(parsed.questions, plan);
  assert.ok(audit.blocks.length > 0, 'PLAN §1 has normative blocks');
  assert.deepEqual(audit.unauthorised, [], 'every §1 contract cites a ⚑contract question');
  assert.deepEqual(audit.uncontracted, [], 'every ⚑contract question is written down in §1');

  // THE regression. Q16's answer was paraphrased into two documents and the operative clause was
  // dropped from both; v7 quotes it. If this fails, someone has summarised it away again.
  const unquoted = quoteAudit(answers, parsed.questions, docs).map((u) => `${u.id}@${u.doc}`);
  assert.ok(!unquoted.includes('Q16@DESIGN.md'), 'Q16 is quoted in the design, not summarised');
  assert.ok(restatementsOf('Q16', docs).length > 1, 'Q16 is spoken for in more than one place');
});

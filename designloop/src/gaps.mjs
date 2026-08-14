// The gap surface (PLAN S15, §4.8; DESIGN chart J8–J17, Q86–Q97b).
//
// A gap is what an executing agent files when it meets a decision the design does not cover and
// cannot take on its own. Chart J8 is the load-bearing sentence: **a gap is a draft question**,
// written in the questionnaire grammar, so its options drop into the next round unchanged. That is
// only true if the same parser reads them, so this module hands the gap's own "Options I can see"
// line to `grammar.parseQuestionBody` — the code that reads every other question in the tool.
//
// The file format is the template in `.claude/skills/flowchart-design/SKILL.md`:
//
//     # GAP-007 — <one-line title>
//     status: open | questioned | resolved | withdrawn
//     outcome: answered | withdrawn | superseded   (when it closes; withdrawn = it was never a gap)
//     raised: <date>, during <execution plan step>
//     design: <doc>, nodes <D6, I10>
//     severity: GAP | CONTRADICTION
//     resolution: |            (added when it is closed — Q96b=a keeps closed gaps with them)
//       …
//
//     **What the design says** — …
//     **What the ANSWER says** — … (verbatim from answers.json, and why it does not settle this)
//     **What it does not say** — …
//     **Why it blocks** — …
//     **Options I can see** — **(a)** … · **(b)** … · *my recommendation* (a)
//     **Blast radius** — plan steps <S4, S9>; design nodes <D6, D7>
//     **Meanwhile** — …
//
// Everything read out of the prose is best-effort — the same standing §4.6 gives `decidedBy` — and
// a gap that carries no parsable options is still listed, marked as awaiting its options. It is
// never rewritten: "do not delete or edit a gap" is absolute, and this module only ever reads.

import { readdir, readFile, writeFile, mkdir } from 'node:fs/promises';
import { join } from 'node:path';
import { parseQuestionBody, GrammarError } from './grammar.mjs';

/** A gap ID, and the prefix of every answer a scoped round records. */
const RE_GAP_ID = /^([A-Z]+-\d+)/;
/** A design node ID, as PLAN §6 defines it. */
const RE_NODE = /\b([A-Z]{1,2}\d+[a-z]?)\b/g;
/** An execution-plan step ID (`S4`, `S15`). */
const RE_STEP = /\bS(\d+)\b/g;

/** Statuses that still want an answer. `resolved` and `withdrawn` are kept, not asked (Q96b=a). */
const OPEN_STATES = new Set(['open', 'questioned', 'unstated']);

/**
 * A gap file with no `status:` line. Still treated as OPEN — an unreadable status is not evidence
 * of closure — but NAMED, so the fallback cannot pass for a real `status: open`.
 *
 * ⚠ It defaulted to `open` silently until 2026-08-14. solatro/spotlight's eleven gap files write
 * their status in prose instead of the key, so the page said "11 open" for a stream with two, and
 * `staleFor` marked plan steps stale on nine answered gaps.
 */
const UNSTATED = 'unstated';

/** Is this ID a gap's, rather than a question's? Answers of both kinds share one file (§4.3). */
export function isGapId(id) {
  return RE_GAP_ID.test(String(id || ''));
}

/** Pull one `**Label** — …` paragraph out of a gap file, joined into a single line. */
function paragraph(text, label) {
  const lines = text.split(/\r?\n/);
  const start = lines.findIndex((l) => l.trim().startsWith(`**${label}**`));
  if (start === -1) return null;
  const out = [lines[start].trim()];
  for (let i = start + 1; i < lines.length; i++) {
    const line = lines[i].trim();
    // The paragraph ends at a blank line, a heading, or the next `**Field** —`. Bold at the start
    // of a line is not enough to end it: an option (`**(b)** …`) is bold and is routinely wrapped
    // onto its own line, and so is emphasis that happens to land there (`**zero errors**, and…`).
    // A field is a capitalised bold phrase followed by a dash, which is what the template writes.
    if (!line || line.startsWith('#')) break;
    if (/^\*\*[A-Z][A-Za-z' ]*\*\*\s*[—-]\s/.test(line)) break;
    out.push(line);
  }
  return out.join(' ').replace(new RegExp(`^\\*\\*${label}\\*\\*\\s*[—-]?\\s*`), '').trim();
}

/** A `key: value` line from the gap's head. `|` alone means the value is a block, not a line. */
function field(text, name) {
  const value = (new RegExp(`^${name}:\\s*(.*)$`, 'mi').exec(text)?.[1] || '').trim();
  return value && value !== '|' ? value : null;
}

/**
 * A `key: |` block — YAML's literal scalar, which is how a resolution is written so it can run to
 * several lines. Everything indented under the key belongs to it.
 */
function block(text, name) {
  const lines = text.split(/\r?\n/);
  const start = lines.findIndex((l) => new RegExp(`^${name}:\\s*\\|\\s*$`, 'i').test(l));
  if (start === -1) return null;
  const out = [];
  for (let i = start + 1; i < lines.length; i++) {
    if (!/^\s+\S/.test(lines[i])) break;
    out.push(lines[i].trim());
  }
  return out.join(' ').trim() || null;
}

/** Expand `J8–J17` into every ID between, so a blast radius written as a range still resolves. */
function expandRange(from, to) {
  const a = /^([A-Z]{1,2})(\d+)([a-z]?)$/.exec(from);
  const b = /^([A-Z]{1,2})(\d+)([a-z]?)$/.exec(to);
  if (!a || !b || a[1] !== b[1]) return [from, to];
  const out = [];
  for (let n = Number(a[2]); n <= Number(b[2]); n++) out.push(`${a[1]}${n}`);
  // A lettered endpoint (`Q97b`) names a different question from its number (`Q97`); both are in.
  if (a[3]) out.push(from);
  if (b[3]) out.push(to);
  return out;
}

/** Every design node ID named in a fragment, ranges expanded. */
export function nodesIn(text) {
  const source = String(text || '');
  const out = new Set();
  for (const m of source.matchAll(/\b([A-Z]{1,2}\d+[a-z]?)\s*[–—-]\s*([A-Z]{1,2}\d+[a-z]?)\b/g)) {
    for (const id of expandRange(m[1], m[2])) out.add(id);
  }
  for (const m of source.matchAll(RE_NODE)) out.add(m[1]);
  return [...out];
}

/**
 * The gap's blast radius (chart J16): the plan steps and design nodes it puts in question.
 * The line names both, and the steps half is written first, so it is split on "design node".
 */
function blastRadius(line) {
  if (!line) return { steps: [], nodes: [] };
  const cut = /design nodes?/i.exec(line);
  const stepsHalf = cut ? line.slice(0, cut.index) : line;
  const nodesHalf = cut ? line.slice(cut.index) : '';
  const steps = [...new Set([...stepsHalf.matchAll(RE_STEP)].map((m) => `S${m[1]}`))];
  const nodes = nodesIn(nodesHalf).filter((id) => !steps.includes(id));
  return { steps, nodes };
}

/**
 * Turn the gap's "Options I can see" line into a Question the answering screen can render.
 *
 * The template writes `*my recommendation* (a)` where a question writes `*default* (a)` — same
 * meaning, different word, because a gap is the agent recommending rather than the design
 * defaulting. Normalising it here keeps PLAN §5.1 exactly as specified: the grammar module never
 * learns a second spelling.
 */
export function gapQuestion(gap) {
  if (!gap.optionsLine) return null;
  // A gap may say in prose that it has no options yet — the promoted-assumption case (Q95b=a)
  // writes exactly that. That is a gap awaiting its options, not a malformed one, and it must not
  // be reported as a parse error: the owner would be told the agent wrote a broken file.
  if (!/\*\*\([a-z]\)\*\*/.test(gap.optionsLine)) return null;
  const body = gap.optionsLine.replace(/\*my recommendation\*/i, '*default*');
  try {
    const question = parseQuestionBody(gap.id, `${gap.title} · ${body}`, { gate: { root: true, atoms: [], text: 'root' } });
    question.effectiveGate = question.gate;
    // A gap is exactly the case the `notes` marker exists for: the agent could not decide it, so
    // its own option list is the most likely place to be insufficient (Q110=a stops Enter here).
    question.notes = true;
    question.gap = gap.id;
    question.context = gap.context;
    question.section = 0;
    question.order = 0;
    return question;
  } catch (err) {
    gap.error = err instanceof GrammarError ? err.message : String(err.message || err);
    return null;
  }
}

/** Parse one gap file. Never throws: a malformed gap must still be visible, it is the report. */
export function parseGap(name, text) {
  const heading = (/^#\s+(.*)$/m.exec(text)?.[1] || name).trim();
  const id = RE_GAP_ID.exec(heading)?.[1] || name.replace(/\.md$/i, '');
  const stated = field(text, 'status');
  const status = (stated || UNSTATED).split(/\s/)[0].toLowerCase();
  const gap = {
    id,
    file: name,
    title: heading.replace(/^[A-Z]+-\d+\s*[—-]\s*/, ''),
    status,
    // Did the FILE say this, or is it the UNSTATED fallback?
    statusStated: !!stated,
    open: OPEN_STATES.has(status),
    // How it ENDED, once it has (`answered` | `withdrawn` | `superseded`). Distinct from `status`,
    // which is where it sits in the round: a gap withdrawn because the design answered it and a gap
    // withdrawn because it was never a gap at all are different lessons for the next
    // questionnaire. `withdrawn` in particular means STOP LOOKING FOR A DECISION —
    // solatro/spotlight GAP-002 was an executor escalating two paraphrases of one answer, and the
    // fix was to go read the answer.
    outcome: (field(text, 'outcome') || '').split(/\s/)[0].toLowerCase() || null,
    severity: field(text, 'severity'),
    raised: field(text, 'raised'),
    design: field(text, 'design'),
    // Q96b=a — a closed gap is kept WITH its resolution; it is the record of where the design was
    // thin and the best input into making the next questionnaire better.
    resolution: block(text, 'resolution') || field(text, 'resolution'),
    context: [
      ['What the design says', paragraph(text, 'What the design says')],
      // MANDATORY in the template, and the one that stops a wasted round: the verbatim note from
      // answers.json for every question involved, and why it does not settle this. An executor who
      // cannot fill this in does not have a gap.
      ['What the ANSWER says', paragraph(text, 'What the ANSWER says')],
      ['What it does not say', paragraph(text, 'What it does not say')],
      ['Why it blocks', paragraph(text, 'Why it blocks')],
      ['Meanwhile', paragraph(text, 'Meanwhile')],
    ].filter(([, v]) => v).map(([label, value]) => ({ label, value })),
    optionsLine: paragraph(text, 'Options I can see'),
    blast: blastRadius(paragraph(text, 'Blast radius')),
    error: null,
    text,
  };
  gap.question = gapQuestion(gap);
  return gap;
}

/** Read every gap in a design's own `gaps/` directory (Q105=a: inside the design, not shared). */
export async function readGaps(dir) {
  let files;
  try {
    files = await readdir(join(dir, 'gaps'));
  } catch {
    return [];
  }
  const gaps = [];
  for (const name of files.sort()) {
    if (!name.toLowerCase().endsWith('.md')) continue;
    gaps.push(parseGap(name, await readFile(join(dir, 'gaps', name), 'utf8').catch(() => '')));
  }
  return gaps;
}

/** Open / closed / total, which is what the index badge says (Q89b=c, Q96b=a). */
export function countGaps(gaps) {
  const open = gaps.filter((g) => g.open).length;
  // Inside `open`, and reported beside it — a bare "11 open" hides which kind they are.
  const unstated = gaps.filter((g) => !g.statusStated).length;
  return { open, closed: gaps.length - open, total: gaps.length, unstated };
}

/**
 * The scoped round (Q90b=b, chart J12): only the open gaps' own questions, and only the ones the
 * owner has not answered yet. Never the whole questionnaire again (Q91b=a) — that is the point.
 */
export function scopedQuestions(gaps) {
  return gaps.filter((g) => g.open && g.question).map((g) => g.question);
}

/** The next unanswered gap question, in file order. */
export function nextGapQuestion(gaps, answers = {}) {
  return scopedQuestions(gaps).find((q) => {
    const a = answers[q.id];
    return !a || a.active === false;
  }) || null;
}

/**
 * The execution plan's steps and what each cites (chart J16, Q93b=a).
 *
 * Every step must cite the design node IDs it implements, or nothing can compute a blast radius —
 * that is the hard requirement Q93b accepted. Two shapes are read, because both are in this repo:
 * the plan's `**S15 — title.** *(implements J8–J17, Q86–Q97b)*` and the handoff's
 * `- id: S15` / `description: … (implements A4, I2, I3)`.
 */
export function planSteps(markdown) {
  const lines = String(markdown ?? '').split(/\r?\n/);
  const steps = new Map();
  const add = (id, line, title, cites) => {
    const step = steps.get(id) || { id, line, title, cites: [] };
    step.cites = [...new Set([...step.cites, ...cites])];
    if (!step.title && title) step.title = title;
    steps.set(id, step);
  };
  lines.forEach((raw, i) => {
 // ⚠ THE LEADING LIST / CHECKBOX MARKER IS TOLERATED ON PURPOSE.
    // It used to be rejected, and rejection here is not benign: an unmatched step line falls
    // through to the `citations(raw)` branch below, which attributes whatever it finds to the
    // PREVIOUS step. Measured — `**S1**`, `- [ ] **S2**`, `- [x] **S3**` parsed as ONE step citing
    // all three steps' nodes, so the stale-step report would have named the wrong steps with no
    // error anywhere. A plan author writing a checklist should get a checklist, not corruption.
    //
    // (Whether a plan SHOULD carry checkboxes is a separate, documented judgement — a plan is a
    // specification and status belongs in the handoff — but that is guidance, and guidance must not
    // be enforced by silent data loss.)
    const heading = /^(?:[-*+]\s*(?:\[[ xX]\]\s*)?)?\*\*(S\d+)\s*[—-]\s*([^*]*)\*\*\s*(.*)$/.exec(raw.trim());
    if (heading) {
      add(heading[1], i + 1, heading[2].trim().replace(/\.$/, ''), citations(heading[3]));
      return;
    }
    const yaml = /^-?\s*id:\s*(S\d+)\s*$/.exec(raw.trim());
    if (yaml) {
      add(yaml[1], i + 1, '', []);
      return;
    }
    const cites = citations(raw);
    if (!cites.length) return;
    // A citation on a continuation line belongs to the most recent step — the handoff writes the
    // `(implements …)` clause inside a folded YAML description, lines below its `id:`.
    const last = [...steps.values()].pop();
    if (last) add(last.id, last.line, last.title, cites);
  });
  return [...steps.values()];
}

/**
 * The execution plan beside the design, if there is one. `PLAN.md` in the design's own directory
 * is where this repo puts it (PLAN §2), and a design with no plan yet simply has no stale steps —
 * the gap surface still works, it just has nothing to mark.
 */
export async function readPlanSteps(dir, file = 'PLAN.md') {
  const text = await readFile(join(dir, file), 'utf8').catch(() => null);
  return text === null ? [] : planSteps(text);
}

/**
 * **THE INVERSE CITATION CHECK: which ANSWERED questions does no plan step claim to implement?**
 *
 * ⚠ **THIS IS THE CHECK THAT WAS MISSING, AND ITS ABSENCE COST A FEATURE.** Everything else here
 * validates STEPS → NODES: every citation resolves, no step cites nothing. Nothing validated
 * NODES → STEPS, so an answered question that no step implements was invisible to every tool in the
 * repo — and therefore invisible to the agent executing the plan.
 *
 * Measured on Spotlight, 2026-08-04: **255 answered questions, 65 cited by a step, 190 cited by
 * none.** `Q85` (*"Radius 16 art units, centred on the card's ART-SQUARE centre"*) was one of the
 * 190. It was read, not implemented, and shipped wrong through three phases and two by-eye reviews,
 * because no step claimed it and so nothing could report it missing.
 *
 * ⚠ **NOT AN ERROR, AND DELIBERATELY SO.** Many answers are scope, context or rationale with nothing
 * to build ("is this in this plan at all", "why we chose X"). The honest output is a REVIEWABLE LIST
 * the owner triages once; what matters is that the residue is deliberate rather than unnoticed.
 * `ignore` carries the ones already triaged, so the list converges on zero instead of being ignored
 * wholesale — a list nobody can clear is a list nobody reads.
 *
 * @param {Array} questions parsed design questions
 * @param {object} answers  the `answers` block of answers.json
 * @param {Array} steps     from `planSteps()`
 * @param {Set<string>} ignore ids already triaged as "nothing to implement"
 */
export function uncitedAnswers(questions, answers = {}, steps = [], ignore = new Set()) {
  const cited = new Set();
  for (const step of steps) for (const c of step.cites) cited.add(c);
  const out = [];
  for (const q of questions) {
    if (q.retired) continue;
    const a = answers[q.id];
    if (!a || a.state !== 'chosen') continue;
    // An INACTIVE answer is a different defect and `answers.log`'s strand report owns it — flagging
    // it here too would bury the live ones.
    if (a.active === false) continue;
    if (cited.has(q.id) || ignore.has(q.id)) continue;
    out.push({ id: q.id, title: (q.text || '').replace(/\s+/g, ' ').slice(0, 88), override: !!a.override });
  }
  return out;
}

/** The design node IDs an `(implements …)` clause names. Nothing else on the line counts. */
function citations(text) {
  const m = /\(implements\s+([^)]*)\)/i.exec(String(text ?? ''));
  return m ? nodesIn(m[1]) : [];
}

/**
 * Which plan steps a set of changed design nodes makes stale (chart J16, Q92b=a, Q95b=a).
 * Untouched steps were never blocked and are not thrown away (J17) — so this returns only the
 * intersection, never "re-check everything", which is the honest fallback nobody does.
 */
export function staleSteps(steps, { nodes = [], steps: named = [] } = {}) {
  const wanted = new Set(nodes);
  const namedSet = new Set(named);
  return steps
    .map((step) => {
      const cited = step.cites.filter((id) => wanted.has(id));
      const byName = namedSet.has(step.id);
      if (!cited.length && !byName) return null;
      return { ...step, because: cited, named: byName };
    })
    .filter(Boolean);
}

/**
 * Every stale step of a design, and the gap that made it so.
 *
 * A gap is stale-making while it is OPEN: the decision under it has not been taken, so a step that
 * cites what it puts in question cannot be worked to a settled answer. A closed gap has already
 * become design version N+1 and its steps were re-derived then (J15 → J17).
 */
export function staleFor(gaps, steps) {
  const out = [];
  for (const gap of gaps) {
    if (!gap.open) continue;
    for (const step of staleSteps(steps, gap.blast)) {
      out.push({ ...step, gap: gap.id, gapTitle: gap.title });
    }
  }
  return out;
}

/** The next free `GAP-NNN` in a directory that already holds some. */
export function nextGapId(gaps) {
  const highest = gaps.reduce((max, g) => Math.max(max, Number(/(\d+)$/.exec(g.id)?.[1] || 0)), 0);
  return `GAP-${String(highest + 1).padStart(3, '0')}`;
}

/**
 * File a gap for an assumption the owner wants a say in after the fact (Q95b=a).
 *
 * It is deliberately filed with NO options: the owner is saying "I want to decide this", not
 * deciding it, and inventing the options here would be the tool authoring questions, which Q94=(a)
 * puts out of scope. It lists as an open gap awaiting its options, every step that relied on the
 * assumption is stale from this moment, and the agent writes the real question next round.
 */
export async function promoteAssumption(dir, { assumption, step = '', nodes = [], why = '' }) {
  const gaps = await readGaps(dir);
  const id = nextGapId(gaps);
  const blastSteps = step ? [...new Set([...String(step).matchAll(RE_STEP)].map((m) => `S${m[1]}`))] : [];
  const body = `# ${id} — the owner wants a say in an assumption that was already made
status: open
raised: ${new Date().toISOString().slice(0, 10)}, promoted from an assumption by the owner
design: ${step || '(the assumption gives no step)'}
severity: GAP

**What the design says** — nothing: this was taken as an assumption, not asked. The line it was
recorded under is quoted below.

**What it does not say** — ${assumption}

**Why it blocks** — the owner has withdrawn the licence to assume it (Q95b=a). It is now an owner
call, which is the GAP row of the triage table.${why ? `\n\n${why}` : ''}

**Options I can see** — none yet. This gap was filed from the review canvas, and the tool does not
author questions (Q94=a). Write the options in the questionnaire grammar and they become the next
scoped round unchanged.

**Blast radius** — plan steps ${blastSteps.join(', ') || '(none named)'}; design nodes ${nodes.join(', ') || '(none named)'}

**Meanwhile** — every step above is stale until this is answered (J16). Steps that cite none of it
were never blocked and keep going (J17).
`;
  await mkdir(join(dir, 'gaps'), { recursive: true });
  await writeFile(join(dir, 'gaps', `${id}.md`), body, 'utf8');
  return { id, file: `${id}.md` };
}

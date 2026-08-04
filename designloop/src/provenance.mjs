// PROVENANCE — does what the documents SAY about an answer still match the answer?
//
// Every defect this module reports was found the same way, on solatro/spotlight 2026-08-04, and it
// is worth stating once because it is the whole design rationale:
//
//   Q16 was answered in free text with no lettered option. Two normative documents then restated
//   it — DESIGN.md D20 as "stays set for the whole act", PLAN.md §1.3 as "Q16 whole act" — and BOTH
//   dropped the clause that settles it ("increases or decreases based on cards being scored"). An
//   executing agent read two lossy summaries of one answer, saw a contradiction that does not exist
//   in answers.json, and spent a round of the owner's time filing a gap on it.
//
//   The conflict was manufactured by restatement. The source was never ambiguous.
//
// So: three reports, all of them about the distance between an answer and what a document says it
// was. None of them blocks — `check`'s standing rule is that the author judges and the tool tells.
//
//   1. softAnswers()  — answered in prose, with no option to point at. The workflow's own fix is to
//                       promote the owner's words to a new lettered option (spotlight did it for
//                       QR2=d and Q24=c, and missed it for Q16). This is the list that makes the
//                       omission visible instead of relying on the author remembering.
//   2. quoteAudit()   — a document that RELIES on a free-text answer must quote it, not summarise
//                       it. This finds the ones that summarise.
//   3. contractAudit()— a code-level contract in PLAN §1 that no ⚑contract question covers. That is
//                       an invented contract, which is what §1.4's `return false` was.
//
// Pure except for the caller handing in document text; no I/O here.

/** A question ID as it appears in prose. */
const RE_ID = /\b(QR\d+|Q\d+[a-z]?)\b/g;

/**
 * Hedges that mark an answer as thinking-aloud rather than settled. `Q16`'s note opens with the
 * literal word "whole act?" — a question mark inside an ANSWER is the strongest signal there is,
 * and it survived four rounds without anyone noticing.
 */
const HEDGES = [/\?/, /\bnot sure\b/i, /\bmaybe\b/i, /\bi think\b/i, /\bprobably\b/i, /\bor something\b/i];

/** Normalise for comparison: collapse whitespace, drop markdown emphasis and smart punctuation. */
export function normalise(text) {
  return String(text ?? '')
    .replace(/[*_`]/g, '')
    .replace(/[‘’]/g, "'")
    .replace(/[“”]/g, '"')
    .replace(/[–—]/g, '-')
    .replace(/\s+/g, ' ')
    .trim()
    .toLowerCase();
}

/**
 * Every line of `text` that names a question ID, with its 1-based line number.
 * Fenced blocks are skipped for the same reason `parseDocument` skips them: the grammar example in
 * every document's §0 names IDs that are not citations of anything.
 */
export function citationLines(text) {
  const out = [];
  let fenced = false;
  const lines = String(text ?? '').split(/\r?\n/);
  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];
    if (/^\s*```/.test(line)) { fenced = !fenced; continue; }
    if (fenced) continue;
    const ids = [...new Set([...line.matchAll(RE_ID)].map((m) => m[1]))];
    if (ids.length) out.push({ line: i + 1, ids, text: line.trim() });
  }
  return out;
}

/**
 * Every place `id` is named across a set of `{name, text}` documents.
 *
 * ⚠ A question's OWN bullet is not a restatement of its answer — it is the question. Counting it
 * makes every answered question look like it is being paraphrased in the questionnaire, which
 * buries the real hits. `includeSelf` is there for the restatement index, which wants it shown.
 */
export function restatementsOf(id, docs, { includeSelf = true } = {}) {
  const own = new RegExp(`^-\\s+\\*\\*${id}\\*\\*`);
  const out = [];
  for (const doc of docs) {
    for (const hit of citationLines(doc.text)) {
      if (!hit.ids.includes(id)) continue;
      if (!includeSelf && own.test(hit.text)) continue;
      out.push({ doc: doc.name, line: hit.line, text: hit.text, own: own.test(hit.text) });
    }
  }
  return out;
}

/**
 * REPORT 1 — answers that carry no lettered option.
 *
 * `state: 'chosen'` with `option: null` is an answer written as prose because none of the options
 * contained it. That is not a defect in itself — it is how the owner corrects a premise, and it is
 * where the best answers come from. The defect is LEAVING it there: the note is now the answer of
 * record, it is not on the DAG, no gate can read it, and every downstream document has to
 * paraphrase it. The fix the workflow already knows is to add the owner's words as a new option.
 *
 * `provisional` marks a note that reads as thinking aloud rather than as a decision.
 */
export function softAnswers(answers = {}, questions = []) {
  const known = new Map(questions.map((q) => [q.id, q]));
  const out = [];
  for (const [id, a] of Object.entries(answers || {})) {
    if (!a || a.active === false) continue;
    const note = String(a.note ?? '').trim();
    if (a.option || !note) continue;
    const q = known.get(id);
    out.push({
      id,
      note,
      // Has the workflow's fix been applied? An option whose label contains a decent run of the
      // note's words is the owner's answer promoted to a letter, which is what closes this.
      promoted: !!q && q.options.some((o) => sharesPhrase(o.label + ' ' + o.consequence, note)),
      provisional: HEDGES.some((re) => re.test(note)),
      line: q?.line ?? null,
    });
  }
  return out.sort((a, b) => a.id.localeCompare(b.id, undefined, { numeric: true }));
}

/**
 * Do these two strings share a run of at least `words` consecutive words? Deliberately crude: it
 * answers "did someone carry the owner's actual wording across", not "do these mean the same".
 */
export function sharesPhrase(a, b, words = 5) {
  const left = normalise(a).split(' ').filter(Boolean);
  const right = normalise(b).split(' ').filter(Boolean);
  if (left.length < words || right.length < words) return false;
  const grams = new Set();
  for (let i = 0; i + words <= right.length; i++) grams.add(right.slice(i, i + words).join(' '));
  for (let i = 0; i + words <= left.length; i++) {
    if (grams.has(left.slice(i, i + words).join(' '))) return true;
  }
  return false;
}

/**
 * REPORT 2 — a document relies on a free-text answer without quoting it.
 *
 * "Relies on" is "names the ID at all", which over-reports by design: a document that mentions a
 * free-text answer in passing and does not quote it is exactly as unreadable to an executor as one
 * that restates it wrongly, and the fix is the same — paste the note.
 *
 * ⚠ The check is a SHARED PHRASE, not equality. A note runs to several sentences and a document
 * legitimately quotes the operative clause rather than all of it; what must never happen is a
 * restatement that carries none of the owner's words. Five consecutive words is the bar.
 */
export function quoteAudit(answers = {}, questions = [], docs = []) {
  const soft = softAnswers(answers, questions);
  const out = [];
  for (const entry of soft) {
    for (const doc of docs) {
      const cites = restatementsOf(entry.id, [doc], { includeSelf: false });
      if (!cites.length) continue;
      if (sharesPhrase(doc.text, entry.note)) continue;
      out.push({
        id: entry.id,
        doc: doc.name,
        lines: cites.map((c) => c.line),
        note: entry.note,
      });
    }
  }
  return out;
}

/**
 * A fenced code block in PLAN §1, with the questions the surrounding section cites.
 *
 * ⚠ FENCES ARE HANDLED BEFORE HEADINGS, and that is not a detail: a GDScript doc comment starts
 * with `##`, so a heading test applied first walks straight out of §1 on the first line of the
 * first contract it is trying to read. The first draft reported "0 normative blocks" for a
 * document with eight of them.
 */
export function normativeBlocks(planText, { sectionPattern = /^##\s*1\.\s/ } = {}) {
  const lines = String(planText ?? '').split(/\r?\n/);
  const blocks = [];
  let inSection = false;
  let heading = '';
  let fence = null;
  let start = 0;
  let body = [];
  let context = [];
  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];
    const fenceMatch = /^\s*```(\w*)/.exec(line);
    if (fence === null && !fenceMatch && /^#{2,3}\s/.test(line)) {
      if (/^##\s/.test(line)) inSection = sectionPattern.test(line);
      heading = line.replace(/^#+\s*/, '').trim();
      // The heading itself is provenance: `### 1.7 Hand re-evaluation (Q22=b, Q23=a…)` is where
      // most of these sections say which answers they implement, so it seeds the context rather
      // than resetting it away.
      context = [heading];
      continue;
    }
    if (!inSection) continue;
    if (fenceMatch && fence === null) {
      fence = fenceMatch[1] || '';
      start = i + 1;
      body = [];
      continue;
    }
    if (fence !== null && /^\s*```\s*$/.test(line)) {
      blocks.push({
        heading,
        lang: fence,
        line: start,
        code: body.join('\n'),
        // Questions named in the block itself OR in the prose since the last heading. A contract's
        // provenance is routinely written in the sentence above it, not inside the code.
        cites: [...new Set([...[...body.join('\n').matchAll(RE_ID)].map((m) => m[1]),
          ...[...context.join('\n').matchAll(RE_ID)].map((m) => m[1])])],
      });
      fence = null;
      continue;
    }
    if (fence !== null) body.push(line);
    else context.push(line);
  }
  return blocks;
}

/**
 * REPORT 3 — contracts and the questions that authorise them.
 *
 * Two directions, and the first is the one that cost a round:
 *   - a normative block citing NO ⚑contract question is a contract nobody asked for. `PLAN.md`
 *     §1.4 cited `Q9`, which asked whether to ship a seam and never what its default was, so the
 *     default was invented — and inverted.
 *   - a ⚑contract question no block cites is an answer that was supposed to become a contract and
 *     did not.
 */
export function contractAudit(questions = [], planText = '') {
  const contracts = questions.filter((q) => q.isContract && !q.retired);
  const byId = new Map(contracts.map((q) => [q.id, q]));
  const blocks = normativeBlocks(planText);
  const unauthorised = [];
  const seen = new Set();
  for (const block of blocks) {
    const covering = block.cites.filter((id) => byId.has(id));
    covering.forEach((id) => seen.add(id));
    if (!covering.length) {
      unauthorised.push({
        heading: block.heading,
        line: block.line,
        cites: block.cites,
        lang: block.lang,
      });
    }
  }
  return {
    blocks,
    contracts: contracts.map((q) => q.id),
    unauthorised,
    uncontracted: contracts.filter((q) => !seen.has(q.id)).map((q) => q.id),
  };
}

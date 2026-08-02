// The question grammar (PLAN §5, §7). Pure: no I/O, no DOM, no Node built-ins — so the browser
// imports this exact file and there is only ever ONE parser. That is the whole reason the runtime
// is Node (DESIGN §11, the QR2 evidence).
//
// The normative grammar is PLAN §5; the prose version is in
// `.claude/skills/flowchart-design/SKILL.md` and the two must agree.
//
//   - **<ID>** `<gate>` [⚑gate] — <text> · <option> [· <option>…] · *default* (<letter>) [· notes] [⇒ <hint>]
//
// The acceptance test is `solatro/SPOTLIGHT_DESIGN.md` parsing UNCHANGED: 188 Q-numbered questions
// plus 8 QR root gates, zero errors. If that document does not parse, the grammar is wrong.

/** An ID is `QR<n>` or `Q<n>` with an optional letter suffix (`Q88` and `Q88b` are different). */
export const ID_PATTERN = /^(?:QR\d+|Q\d+[a-z]?)$/;

/** The separator between a question's parts: space, U+00B7, space. */
const SEP = ' · ';

/** Hint markers. Never parsed for meaning — `⇒ skips …` is a convenience, the gates are the truth. */
const HINT = /\s[⇒⇐]\s/;

const RE_QUESTION_HEAD = /^-\s+\*\*(QR\d+|Q\d+[a-z]?)\*\*\s*(.*)$/;
const RE_GATE = /^`\[([^\]]*)\]`\s*/;
const RE_RETIRED = /^—\s*\*(.+)\*\s*$/;
const RE_OPTION = /^\*\*\(([a-z])\)\*\*\s*([\s\S]*)$/;
const RE_DEFAULT = /^\*default\*\s*\(([a-z])\)\s*([\s\S]*)$/;
const RE_NEXT = /\s—\s\*\*→\s*next:\*\*\s*/;
const RE_HEADING = /^(#{2,6})\s+(.*)$/;
const RE_HEADING_GATE = /\s*`\[([^\]]*)\]`\s*$/;

/** A parse or validation failure, with the source line so the document can be fixed. */
export class GrammarError extends Error {
  constructor(message, { id = null, line = null } = {}) {
    super(message);
    this.name = 'GrammarError';
    this.id = id;
    this.line = line;
  }
}

/**
 * Parse a gate expression (PLAN §5.2).
 *   gate := "root" | conj ;  conj := atom (" & " atom)* ;  atom := ID ("="|"≠") letters
 * `|` binds inside ONE atom's letter list only — there is no cross-question `or`.
 */
export function parseGate(str) {
  const text = String(str ?? '').trim();
  if (text === 'root') return { root: true, atoms: [], text };
  if (!text) throw new GrammarError('empty gate');
  const atoms = text.split('&').map((raw) => {
    const part = raw.trim();
    const m = /^(QR\d+|Q\d+[a-z]?)\s*(=|≠)\s*(.+)$/.exec(part);
    if (!m) throw new GrammarError(`cannot parse gate atom "${part}" in "[${text}]"`);
    const letters = m[3].split('|').map((l) => l.trim());
    if (!letters.length || letters.some((l) => !/^[a-z]$/.test(l))) {
      throw new GrammarError(`gate atom "${part}" must name single option letters`);
    }
    return { id: m[1], op: m[2] === '=' ? '=' : '≠', letters };
  });
  return { root: false, atoms, text };
}

/** Conjoin two gates. A `root` gate contributes nothing, which is what makes it the identity. */
export function andGates(a, b) {
  if (!a || a.root) return b || { root: true, atoms: [], text: 'root' };
  if (!b || b.root) return a;
  return { root: false, atoms: [...a.atoms, ...b.atoms], text: `${a.text} & ${b.text}` };
}

/** Split a trailing `⇒ …` / `⇐ …` hint off a segment. */
function splitHint(segment) {
  const m = HINT.exec(segment);
  if (!m) return { body: segment.trim(), hint: null };
  return { body: segment.slice(0, m.index).trim(), hint: segment.slice(m.index + m[0].length).trim() };
}

/**
 * Parse one option: `**(a)** label — consequence — **→ next:** preview`.
 * The consequence may contain a ` — ` of its own, so only the FIRST one splits label from
 * consequence, and the `→ next:` clause is taken off before either.
 */
function parseOption(segment) {
  const m = RE_OPTION.exec(segment);
  if (!m) return null;
  let rest = m[2].trim();
  let next = null;
  const nx = RE_NEXT.exec(rest);
  if (nx) {
    next = rest.slice(nx.index + nx[0].length).trim();
    rest = rest.slice(0, nx.index).trim();
  }
  let label = rest;
  let consequence = '';
  const dash = rest.indexOf(' — ');
  if (dash !== -1) {
    label = rest.slice(0, dash).trim();
    consequence = rest.slice(dash + 3).trim();
  }
  return { letter: m[1], label, consequence, next };
}

/**
 * Parse one question line. Returns a Question, `{retired:true}` for a retired question, or `null`
 * when the line is not a question line at all.
 *
 * `null` matters: both design documents carry prose bullets that mention a question by ID
 * (`- **Q61** — is E3 right, or …`) outside the questionnaire. A question line is distinguished by
 * carrying a backticked gate; a retired one, by being entirely italic. Anything else is prose and
 * is skipped rather than treated as a broken question — the alternative is a parser that reports
 * errors in documents that are perfectly correct.
 *
 * `strict` (PLAN §5.1) makes a ⚑gate question whose options do not all carry `→ next:` throw.
 * See `gaps/GAP-001.md`: `SPOTLIGHT_DESIGN.md` contains one such question and the acceptance gate
 * forbids editing it, so the default is non-strict and the shortfall is reported as a warning.
 */
export function parseQuestionLine(line, { strict = false, lineNumber = null } = {}) {
  const head = RE_QUESTION_HEAD.exec(line.trim());
  if (!head) return null;
  const id = head[1];
  let rest = head[2].trim();

  const gm = RE_GATE.exec(rest);
  if (!gm) {
    const retired = RE_RETIRED.exec(rest);
    if (retired) {
      return {
        id, retired: true, reason: retired[1].trim(), gate: null, text: retired[1].trim(),
        options: [], default: null, notes: false, isGate: false, hint: null, line: lineNumber,
      };
    }
    return null;
  }
  const gate = parseGate(gm[1]);
  rest = rest.slice(gm[0].length).trim();

  let isGate = false;
  if (rest.startsWith('⚑gate')) {
    isGate = true;
    rest = rest.slice('⚑gate'.length).trim();
  }
  if (!rest.startsWith('—')) {
    throw new GrammarError(`${id}: expected "—" after the gate`, { id, line: lineNumber });
  }
  rest = rest.slice(1).trim();

  const segments = rest.split(SEP);
  const question = {
    id,
    retired: false,
    gate,
    isGate,
    text: '',
    options: [],
    default: null,
    defaultNote: '',
    notes: false,
    hint: null,
    line: lineNumber,
    warnings: [],
  };

  const first = splitHint(segments[0]);
  question.text = first.body;
  if (first.hint) question.hint = first.hint;

  for (const raw of segments.slice(1)) {
    const { body, hint } = splitHint(raw);
    if (hint) question.hint = hint;
    if (!body) continue;
    const option = parseOption(body);
    if (option) {
      question.options.push(option);
      continue;
    }
    const def = RE_DEFAULT.exec(body);
    if (def) {
      question.default = def[1];
      question.defaultNote = def[2].trim().replace(/^—\s*/, '');
      continue;
    }
    if (/^notes\b/i.test(body)) {
      question.notes = true;
      continue;
    }
    throw new GrammarError(`${id}: unrecognised segment "${body}"`, { id, line: lineNumber });
  }

  if (!question.options.length) {
    throw new GrammarError(`${id}: no options`, { id, line: lineNumber });
  }
  const letters = question.options.map((o) => o.letter);
  if (new Set(letters).size !== letters.length) {
    throw new GrammarError(`${id}: duplicate option letters`, { id, line: lineNumber });
  }
  if (!question.default) {
    throw new GrammarError(`${id}: no *default*`, { id, line: lineNumber });
  }
  if (!letters.includes(question.default)) {
    throw new GrammarError(`${id}: *default* (${question.default}) is not one of its options`, { id, line: lineNumber });
  }
  if (isGate) {
    const missing = question.options.filter((o) => !o.next).map((o) => o.letter);
    if (missing.length) {
      const message = `${id}: ⚑gate option(s) (${missing.join(', ')}) carry no "→ next:" preview`;
      if (strict) throw new GrammarError(message, { id, line: lineNumber });
      question.warnings.push(message);
    }
  }
  return question;
}

/**
 * Parse a whole design document.
 * Returns `{questions, sections, errors, warnings, ignored}`. Fenced blocks are skipped whole, so
 * the grammar example in every document's §0 and the mermaid charts are never mistaken for content.
 */
export function parseDocument(markdown, { strict = false } = {}) {
  const lines = String(markdown ?? '').split(/\r?\n/);
  const questions = [];
  const sections = [];
  const errors = [];
  const warnings = [];
  const ignored = [];
  const seen = new Map();

  let fence = null;
  let section = { title: '(document)', gate: { root: true, atoms: [], text: 'root' }, level: 0, index: 0, line: 0, count: 0 };
  sections.push(section);

  lines.forEach((line, i) => {
    const lineNumber = i + 1;
    const fenceMatch = /^\s*(```+|~~~+)/.exec(line);
    if (fenceMatch) {
      if (fence === null) fence = fenceMatch[1][0];
      else if (fenceMatch[1][0] === fence) fence = null;
      return;
    }
    if (fence !== null) return;

    const heading = RE_HEADING.exec(line);
    if (heading) {
      let title = heading[2].trim();
      let gate = { root: true, atoms: [], text: 'root' };
      const gm = RE_HEADING_GATE.exec(title);
      if (gm) {
        title = title.slice(0, gm.index).trim();
        try {
          gate = parseGate(gm[1]);
        } catch (err) {
          errors.push(new GrammarError(`section "${title}": ${err.message}`, { line: lineNumber }));
        }
      }
      section = { title, gate, level: heading[1].length, index: sections.length, line: lineNumber, count: 0 };
      sections.push(section);
      return;
    }

    let q;
    try {
      q = parseQuestionLine(line, { strict, lineNumber });
    } catch (err) {
      errors.push(err instanceof GrammarError ? err : new GrammarError(err.message, { line: lineNumber }));
      return;
    }
    if (!q) {
      if (/^-\s+\*\*(QR\d+|Q\d+[a-z]?)\*\*/.test(line.trim())) ignored.push({ line: lineNumber, text: line.trim() });
      return;
    }
    if (seen.has(q.id)) {
      errors.push(new GrammarError(`${q.id}: duplicate ID (also on line ${seen.get(q.id)})`, { id: q.id, line: lineNumber }));
      return;
    }
    seen.set(q.id, lineNumber);
    q.section = section.index;
    q.sectionTitle = section.title;
    q.order = questions.length;
    q.effectiveGate = q.retired ? null : andGates(q.gate, section.gate);
    for (const w of q.warnings || []) warnings.push(new GrammarError(w, { id: q.id, line: lineNumber }));
    section.count += 1;
    questions.push(q);
  });

  errors.push(...validate(questions, sections));
  return { questions, sections, errors, warnings, ignored };
}

/**
 * Explain a gate in the owner's terms: "asked because QR3 = both — circle on the card, beam from
 * above" (Q17=a). Used by the browser, which imports this module directly — the point of the
 * shared parser is that the screen and the server cannot disagree about what a gate means.
 */
export function describeGate(gate, questions, answers = {}) {
  if (!gate || gate.root) return [];
  const map = byId(questions);
  return gate.atoms.map((atom) => {
    const ref = map.get(atom.id);
    const given = answerFor(answers, atom.id);
    const labelOf = (letter) => ref?.options.find((o) => o.letter === letter)?.label || `(${letter})`;
    return {
      id: atom.id,
      op: atom.op,
      letters: atom.letters,
      question: ref?.text || '',
      wanted: atom.letters.map(labelOf),
      chosen: given?.option ?? null,
      chosenLabel: given?.option ? labelOf(given.option) : null,
    };
  });
}

/** Index questions by ID. */
export function byId(questions) {
  const map = new Map();
  for (const q of questions) map.set(q.id, q);
  return map;
}

/**
 * Evaluate a gate against the current answers: `"true"`, `"false"` or `"pending"` (PLAN §5.4).
 * `answers` maps ID → `{option, active}`. An inactive answer, or one that is free text instead of
 * an option (`option: null`), counts as not yet answered — there is nothing for a gate to test.
 */
export function evaluateGate(gate, answers) {
  if (!gate || gate.root) return 'true';
  let pending = false;
  for (const atom of gate.atoms) {
    const a = answers instanceof Map ? answers.get(atom.id) : answers?.[atom.id];
    if (!a || a.active === false || !a.option) {
      pending = true;
      continue;
    }
    const hit = atom.letters.includes(a.option);
    const ok = atom.op === '=' ? hit : !hit;
    if (!ok) return 'false';
  }
  return pending ? 'pending' : 'true';
}

/** Read an answer out of a Map or a plain object, so callers can pass either. */
function answerFor(answers, id) {
  return answers instanceof Map ? answers.get(id) : answers?.[id];
}

/**
 * Classify every question (PLAN §5.4). REACHABLE = askable now; PENDING = its gate depends on
 * something unanswered; PRUNED = its gate is decidably false. `answered` is everything with a live
 * answer, which is what feeds other gates.
 */
export function reachability(questions, answers = {}) {
  const reachable = [];
  const pending = [];
  const pruned = [];
  const answered = [];
  for (const q of questions) {
    if (q.retired) continue;
    const state = evaluateGate(q.effectiveGate || q.gate, answers);
    const a = answerFor(answers, q.id);
    if (state === 'false') {
      pruned.push(q);
      continue;
    }
    if (a && a.active !== false) {
      answered.push(q);
      continue;
    }
    (state === 'true' ? reachable : pending).push(q);
  }
  return { reachable, pending, pruned, answered };
}

/**
 * How many questions a given question transitively prunes: every question whose gate names it,
 * plus everything those in turn reach. This is the weight §5.5 orders sections by.
 */
export function pruneClosure(questions) {
  const dependents = new Map();
  for (const q of questions) {
    if (q.retired) continue;
    for (const atom of (q.effectiveGate || q.gate || { atoms: [] }).atoms) {
      if (!dependents.has(atom.id)) dependents.set(atom.id, new Set());
      dependents.get(atom.id).add(q.id);
    }
  }
  const closure = new Map();
  for (const q of questions) {
    if (q.retired) continue;
    const seenIds = new Set();
    const stack = [...(dependents.get(q.id) || [])];
    while (stack.length) {
      const id = stack.pop();
      if (seenIds.has(id)) continue;
      seenIds.add(id);
      for (const nxt of dependents.get(id) || []) stack.push(nxt);
    }
    closure.set(q.id, seenIds);
  }
  return closure;
}

/**
 * Section weight (PLAN §5.5): the number of questions a section's gate-referenced questions
 * transitively prune. Sections sort by that, descending, ties keeping document order.
 */
export function sectionWeights(questions, sections) {
  const closure = pruneClosure(questions);
  const weights = new Map();
  for (const s of sections) {
    const union = new Set();
    for (const atom of s.gate?.atoms || []) {
      for (const id of closure.get(atom.id) || []) union.add(id);
    }
    weights.set(s.index, union.size);
  }
  return weights;
}

/** The next question to ask: document order within a section, sections by gate weight (§5.5). */
export function nextQuestion(questions, answers = {}, sections = null) {
  const { reachable } = reachability(questions, answers);
  if (!reachable.length) return null;
  const weights = sections ? sectionWeights(questions, sections) : new Map();
  let best = null;
  for (const q of reachable) {
    if (!best) { best = q; continue; }
    const wq = weights.get(q.section) ?? 0;
    const wb = weights.get(best.section) ?? 0;
    if (q.section !== best.section && wq !== wb) {
      if (wq > wb) best = q;
      continue;
    }
    if (q.order < best.order) best = q;
  }
  return best;
}

/**
 * What changing one answer would strand or bring back (PLAN §7, Q34).
 * An answer is active exactly when its gate evaluates true, so this is a fixpoint: stranding one
 * answer can make a gate that named it pending, which strands the next one down.
 */
export function blastRadius(questions, answers, id, next) {
  const current = new Map();
  for (const q of questions) {
    const a = answerFor(answers, q.id);
    if (a) current.set(q.id, { ...a });
  }
  const target = current.get(id) || { state: 'chosen', active: true };
  current.set(id, { ...target, ...next, active: true });

  for (let pass = 0; pass < questions.length + 2; pass++) {
    let changed = false;
    for (const q of questions) {
      const a = current.get(q.id);
      if (!a || q.id === id) continue;
      const live = evaluateGate(q.effectiveGate || q.gate, current) === 'true';
      if ((a.active !== false) !== live) {
        a.active = live;
        changed = true;
      }
    }
    if (!changed) break;
  }

  const strand = [];
  const restore = [];
  for (const q of questions) {
    const before = answerFor(answers, q.id);
    const after = current.get(q.id);
    if (!before || q.id === id) continue;
    const wasActive = before.active !== false;
    const isActive = after.active !== false;
    if (wasActive && !isActive) strand.push(q.id);
    if (!wasActive && isActive) restore.push(q.id);
  }
  return { strand, restore, answers: current };
}

/**
 * Static checks over a parsed document (PLAN §5.6): a gate naming an ID or a letter that does not
 * exist is a hard error, as is a cycle, as is a question no assignment of answers can ever reach.
 */
export function validate(questions, sections = []) {
  const errors = [];
  const map = byId(questions);

  for (const q of questions) {
    if (q.retired) continue;
    const gates = [{ gate: q.gate, where: 'gate' }];
    const section = sections.find((s) => s.index === q.section);
    if (section && !section.gate.root) gates.push({ gate: section.gate, where: `section "${section.title}"` });
    for (const { gate, where } of gates) {
      for (const atom of gate.atoms) {
        const ref = map.get(atom.id);
        if (!ref) {
          errors.push(new GrammarError(`${q.id}: ${where} names ${atom.id}, which does not exist`, { id: q.id, line: q.line }));
          continue;
        }
        if (ref.retired) {
          errors.push(new GrammarError(`${q.id}: ${where} names ${atom.id}, which is retired`, { id: q.id, line: q.line }));
          continue;
        }
        const offered = ref.options.map((o) => o.letter);
        for (const letter of atom.letters) {
          if (!offered.includes(letter)) {
            errors.push(new GrammarError(
              `${q.id}: ${where} names ${atom.id}=${letter}, but ${atom.id} offers only (${offered.join(', ')})`,
              { id: q.id, line: q.line },
            ));
          }
        }
      }
    }

    // Unsatisfiable: two atoms over the same question that no single answer can satisfy. Atoms
    // that name a letter the question does not offer are skipped — already reported above, and
    // reporting the same defect twice makes the error list harder to act on, not easier.
    const perId = new Map();
    for (const atom of (q.effectiveGate || q.gate).atoms) {
      const ref = map.get(atom.id);
      if (!ref || ref.retired) continue;
      const offered = ref.options.map((o) => o.letter);
      if (atom.letters.some((l) => !offered.includes(l))) continue;
      const allowed = atom.op === '=' ? offered.filter((l) => atom.letters.includes(l))
                                      : offered.filter((l) => !atom.letters.includes(l));
      const prev = perId.get(atom.id) || offered;
      perId.set(atom.id, prev.filter((l) => allowed.includes(l)));
    }
    for (const [refId, allowed] of perId) {
      if (!allowed.length) {
        errors.push(new GrammarError(`${q.id}: gate can never be satisfied — no answer to ${refId} passes it`, { id: q.id, line: q.line }));
      }
    }
  }

  // Cycles: a gate graph that loops can never be answered in any order.
  const colour = new Map();
  const stack = [];
  const visit = (id) => {
    const state = colour.get(id);
    if (state === 'done') return;
    if (state === 'open') {
      const cycle = [...stack.slice(stack.indexOf(id)), id].join(' → ');
      errors.push(new GrammarError(`gate cycle: ${cycle}`, { id }));
      return;
    }
    colour.set(id, 'open');
    stack.push(id);
    const q = map.get(id);
    for (const atom of (q?.effectiveGate || q?.gate || { atoms: [] }).atoms) {
      if (map.has(atom.id)) visit(atom.id);
    }
    stack.pop();
    colour.set(id, 'done');
  };
  for (const q of questions) if (!q.retired) visit(q.id);

  return errors;
}

/**
 * The longest possible path: the most questions a single set of answers can leave reachable.
 * Branch and bound over the questions any gate actually names — everything else is decided by
 * those. Reported by the acceptance test against the document's own "~150" estimate.
 */
export function longestPath(questions) {
  const live = questions.filter((q) => !q.retired);
  const map = byId(live);
  const vars = [...new Set(live.flatMap((q) => (q.effectiveGate || q.gate).atoms.map((a) => a.id)))]
    .filter((id) => map.has(id));
  const options = new Map(vars.map((id) => [id, map.get(id).options.map((o) => o.letter)]));

  const ungated = live.filter((q) => !(q.effectiveGate || q.gate).atoms.length).length;
  const gated = live.filter((q) => (q.effectiveGate || q.gate).atoms.length);

  let best = 0;
  const assignment = new Map();

  const countAndBound = () => {
    const answers = new Map([...assignment].map(([k, v]) => [k, { option: v, active: true }]));
    let sure = ungated;
    let maybe = 0;
    for (const q of gated) {
      const state = evaluateGate(q.effectiveGate || q.gate, answers);
      if (state === 'true') sure += 1;
      else if (state === 'pending') maybe += 1;
    }
    return { sure, bound: sure + maybe };
  };

  const step = (i) => {
    const { sure, bound } = countAndBound();
    if (bound <= best) return;
    if (i >= vars.length) {
      if (sure > best) best = sure;
      return;
    }
    for (const letter of options.get(vars[i])) {
      assignment.set(vars[i], letter);
      step(i + 1);
    }
    assignment.delete(vars[i]);
  };
  step(0);
  return best;
}

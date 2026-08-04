// The answering session (PLAN S5–S8, S19; DESIGN charts B, B2, D).
//
// One question on the screen and NOTHING that indicates progress (Q10=a, Q26=a, Q114=a) — no
// count, no bar, no "question 4 of". The end of a round arrives without warning, and the DONE
// screen is the signal.
//
// This module imports `../src/grammar.mjs` — the same file the server parses with. That is the
// point of the Node runtime (DESIGN §11): the screen and the server cannot disagree about what a
// gate means, because there is one parser.
//
// S19 (the owner's review of 2026-08-03) changed four things about how it is driven, and each one
// is a rule this file now keeps:
//
//   1. History is a scrollable SIDEBAR carrying the question AND the answer, not a screen you have
//      to leave the question for.
//   2. BACK is a real visit stack, like a browser's. It is never a no-op that looks like a click
//      that failed, and it never dead-ends at the index.
//   3. EVERY control says which key presses it, and Enter's target is VISIBLE before you press it.
//   4. Nothing you typed is ever thrown away by a keystroke.

import { parseDocument, describeGate } from '../src/grammar.mjs';
import { md } from './md.mjs';

const params = new URLSearchParams(location.search);
const key = params.get('key') || '';
/**
 * `?scope=gaps` is the SCOPED round (Q90b=b, chart J12): the open gaps' own questions and nothing
 * else. It is the same screen, the same keyboard, the same durability — only the source of the
 * questions differs, which is the whole point of a gap being written in the question grammar.
 */
const scope = params.get('scope') === 'gaps' ? 'gaps' : null;
const screen = document.getElementById('screen');
const titleEl = document.getElementById('design-title');
const historyPanel = document.getElementById('history-panel');
const historyList = document.getElementById('history-list');
const historyCount = document.getElementById('history-count');
const historyHandle = document.getElementById('history-handle');
const sessionChip = document.getElementById('session-chip');
const sessionDetail = document.getElementById('session-detail');
const keyhelp = document.getElementById('keyhelp');

/** The design's meta + both status halves + whether an agent is parked (§4.9). */
let design = null;
/** The parsed document, for gate explanations and history labels. */
let parsed = { questions: [], sections: [] };
/** The question on screen, its recorded answer if it has one, and whether this is a re-answer. */
let view = null;
/** A run of Enter-accepted defaults, shown back to the owner when the run ends (Q111=a). */
let hammered = [];
/** Where the visible focus ring is. -1 means the owner has not moved it. */
let focusIndex = -1;
let focusables = [];
/** A message to show above the next question — stranding notices, hammer summaries, round openers. */
let banner = null;
let history = [];
/** The open gaps' questions, when this screen is a scoped round. Empty otherwise. */
let gapQuestions = [];
/** The scoped round says what it is, once, at the top. */
let announcedScope = false;

const api = (path, init) => fetch(`/api/designs/${key}${path}`, init).then(async (r) => {
  const body = await r.json().catch(() => ({}));
  if (!r.ok) throw new Error(body.error || `${r.status}`);
  return body;
});

/** Build an element with inline markdown content. */
function el(tag, className, html) {
  const node = document.createElement(tag);
  if (className) node.className = className;
  if (html !== undefined) node.innerHTML = html;
  return node;
}

/** The answers map, as the grammar module wants it. */
function answersFromHistory(list) {
  const map = {};
  for (const h of list) map[h.id] = { option: h.option, active: h.active, state: h.state };
  return map;
}

// --- what a key does, and saying so (S19.3) -------------------------------------------------------
//
// Every control on this screen has a key, and every control SHOWS it. The option letters own their
// own keys — `(b)` is pressed by `b`, always — so an action whose mnemonic collides with an option
// on the question currently displayed simply has no key on that question rather than stealing one.
// Both real documents top out at three options, so this is a guard, not a common case.

const ACTION_KEYS = { write: 'w', notRelevant: 'n', history: 'h', canvas: 'g', session: 'i' };

function keyFor(action) {
  const wanted = ACTION_KEYS[action];
  const taken = (view?.question.options || []).some((o) => o.letter === wanted);
  return taken ? null : wanted;
}

/** The `⌨` chip that goes on a control. */
function kbd(label) {
  return label ? el('span', 'kbd', label) : null;
}

function withKey(button, label) {
  const chip = kbd(label);
  if (chip) button.append(chip);
  return button;
}

// --- the visit stack (S19.2) ---------------------------------------------------------------------
//
// BACK used to mean "the last answer in the file", which is not what a back button means: standing
// on that same last answer, it pointed at itself and the click did nothing, which is why the owner
// had to use the history list instead.
//
// This is a browser's back stack. It records the questions this screen has SHOWN, in the order it
// showed them, and BACK steps one entry down it. It lives in `sessionStorage` so that walking off
// to the canvas and coming back does not reset it — the owner's own words: "in case user checks
// another page then comes back". Arriving fresh with no stack at all, BACK falls back to the last
// question actually answered, never to the index: leaving the questionnaire is what the link in
// the corner is for.

const NAV_KEY = `designloop.nav.${key}${scope ? '.gaps' : ''}`;

function loadNav() {
  try {
    const raw = JSON.parse(sessionStorage.getItem(NAV_KEY) || '[]');
    return Array.isArray(raw) ? raw.filter((x) => typeof x === 'string') : [];
  } catch {
    return [];
  }
}
let nav = loadNav();

function saveNav() {
  // Long rounds are long; the tail is the only part BACK can reach anyway.
  if (nav.length > 500) nav = nav.slice(-500);
  try { sessionStorage.setItem(NAV_KEY, JSON.stringify(nav)); } catch { /* private mode */ }
}

/** Record that this question is now on screen. Repeats of the top are not a new visit. */
function pushNav(id) {
  if (!id || nav[nav.length - 1] === id) return;
  nav.push(id);
  saveNav();
}

/** What BACK would open, or null when there is nowhere to go. */
function backTarget() {
  const current = view?.question.id;
  for (let i = nav.length - 2; i >= 0; i--) {
    if (nav[i] !== current) return { id: nav[i], depth: nav.length - i };
  }
  // No stack above this question: opened straight from the index, from a canvas link, or in a new
  // tab. "Where was I before this?" then means the question answered immediately BEFORE this one —
  // which for a question nobody has answered yet is simply the latest answer.
  //
  // Not "the newest answer" unconditionally: standing on the first question of the round, that
  // would send BACK *forward*, to the end of the history. There is genuinely nothing before the
  // first question, and the button says so instead.
  const live = history.filter((h) => h.active);
  const at = live.findIndex((h) => h.id === current);
  const previous = at === -1 ? live[live.length - 1] : live[at - 1];
  return previous ? { id: previous.id, depth: 0 } : null;
}

function goBack() {
  hammered = [];
  const target = backTarget();
  if (!target) return;
  // Pop back to the target INCLUSIVE, so it becomes the new top and the entry below it is where
  // the next BACK goes. Truncating one too far is what turns a back stack into a one-shot.
  if (target.depth) nav = nav.slice(0, nav.length - target.depth + 1);
  saveNav();
  revisit(target.id, { record: false });
}

// --- drafts (S19.4) -------------------------------------------------------------------------------
//
// What the owner typed belongs to them. It used to live only in the textarea, so anything that
// re-rendered the screen — including the Enter that took the recommendation instead — destroyed it,
// and the browser's own undo had nothing left to undo because the element itself was gone. Every
// keystroke is now saved against its question and restored when that question comes back.

const draftKey = (id) => `designloop.draft.${key}.${id}`;

function readDraft(id) {
  try { return sessionStorage.getItem(draftKey(id)) || ''; } catch { return ''; }
}

function writeDraft(id, text) {
  try {
    if (text) sessionStorage.setItem(draftKey(id), text);
    else sessionStorage.removeItem(draftKey(id));
  } catch { /* private mode */ }
}

const noteValue = () => document.getElementById('note')?.value ?? '';

// --- loading -------------------------------------------------------------------------------------

async function refresh() {
  design = await api('');
  titleEl.textContent = scope === 'gaps' ? `${design.title} — the open gaps` : design.title;
  document.title = `${design.title} — Design Loop`;
  document.getElementById('canvas-link').href = `canvas.html?key=${encodeURIComponent(key)}`;
  renderSession();
  // Re-parsed on every refresh, never cached: the agent rewrites the document between rounds
  // (chart B2), and `refresh()` is exactly what runs when it does. A parse held over from round 1
  // makes BACK, the history list and the canvas' `#Qn` links silently miss every question round 2
  // added, and leaves `describeGate` unable to name the options it is explaining.
  parsed = parseDocument(await fetch(`/api/designs/${key}/doc`).then((r) => r.text()));
  history = await api('/history');
  renderHistoryPanel();
  if (scope === 'gaps') return refreshGaps();
  // The round can end with reachable questions still on the table: free text at a ⚑gate ends it on
  // the spot, because every question after it sits on a branch just declined (chart B2, §4.2).
  //
  // `gaps_answered` is the one ending that does NOT mean the questionnaire is over: a scoped round
  // is an interruption, and Q88b=a is explicit that only the affected thread parks. It hands the
  // turn back so the agent writes the next design version, and this screen carries on asking.
  if (design.owner.state === 'done' && design.owner.reason !== 'gaps_answered' && design.agent.state !== 'ready') {
    return renderDone({ owner: design.owner, agent: design.agent });
  }
  if (design.agent.state === 'ready' && design.owner.state === 'done') {
    // The agent finished a round while this screen was away. Take the turn back (§4.2).
    design = await api('/resume', { method: 'POST' });
  }
  // `question.html?key=…#Q26` opens that question directly — the canvas links here from a node's
  // "decided by" list (Q18's other direction: node → the question that created it).
  const wanted = decodeURIComponent(location.hash.slice(1));
  if (wanted && parsed.questions.some((q) => q.id === wanted)) {
    location.hash = '';
    return revisit(wanted);
  }
  const next = await api('/next');
  if (next.done) return renderDone(next);
  view = { question: next.question, answer: next.answer, revisit: false };
  pushNav(next.question.id);
  return render();
}

/**
 * The scoped round. Its questions come from `gaps/*.md` rather than from the design document, and
 * it ignores the questionnaire's own state entirely: a gap can be answered while the main round is
 * finished, half-finished, or waiting on the agent (Q88b=a — only the affected thread parks).
 */
async function refreshGaps() {
  const data = await api('/gaps');
  gapQuestions = data.gaps.map((g) => g.question).filter(Boolean);
  const next = await api('/next?scope=gaps');
  if (next.done) return renderGapsDone(data);
  view = { question: next.question, answer: next.answer, revisit: false };
  pushNav(next.question.id);
  if (!announcedScope) {
    announcedScope = true;
    banner = el('div', 'banner', `<strong>A scoped round.</strong> Only what the open gaps ask — `
      + `never the whole questionnaire again. Each one is a decision an agent hit during `
      + `implementation and would not take on your behalf; the thread it belongs to is parked and `
      + `everything else has kept going.`);
  }
  return render();
}

// --- is anyone listening? (S19.7, §4.9) -----------------------------------------------------------

/**
 * Whether an agent is parked on this design, and what to do when it is not.
 *
 * The owner could previously answer a whole round into a directory nobody was watching and have no
 * way to tell. `session.json` is the watch process' heartbeat; a session that ended leaves it
 * stale. The fallback has always been true and is said here rather than assumed: telling the agent
 * in chat works whether or not anything is watching (Q22=a), because every answer is already on
 * disk before the next question appears.
 */
function renderSession() {
  const s = design?.session || { watching: false, stale: false, ever: false };
  const state = s.watching ? 'live' : (s.stale ? 'stale' : 'none');
  sessionChip.className = `badge session ${state}`;
  sessionChip.textContent = {
    live: '● an agent is watching',
    stale: '◍ the session stopped',
    none: '○ no agent is watching',
  }[state];

  const prompt = scope === 'gaps'
    ? `The gaps at ${key} are answered — read designloop/design/${key.split('/')[1]}/gaps/ against the answers, write the next design version with its changelog, close them in place with their resolutions, and re-derive the plan steps they made stale.`
    : `I am answering ${key} in the Design Loop. Park on it:\nnpm --prefix designloop run watch -- ${key}\nWhen it wakes, read the answers, revise the design, and hand the turn back with status.agent.json.`;

  sessionDetail.replaceChildren();
  sessionDetail.append(el('div', null, {
    live: `<strong>An agent is parked on this design.</strong> It is blocked on `
      + `<code>run watch</code> and returns the moment you finish this round — you do not have to `
      + `tell it anything. Watching since ${s.since ? new Date(s.since).toLocaleTimeString() : 'a moment ago'}.`,
    stale: `<strong>The session that was watching this design has stopped.</strong> Its last `
      + `heartbeat was ${s.at ? new Date(s.at).toLocaleTimeString() : 'a while ago'}. `
      + `<strong>Nothing is lost</strong> — every answer was on disk before the next question `
      + `appeared, and a fresh session reads them all. Keep answering; start a new one when you like.`,
    none: `<strong>No agent is watching this design.</strong> That is not a problem: every answer `
      + `is on disk before the next question appears, and any session can read them. It only means `
      + `nobody is woken automatically when you finish. Start one by pasting this into a Claude `
      + `Code session in the repo:`,
  }[state]));
  if (state !== 'live') {
    const pre = document.createElement('pre');
    pre.textContent = prompt;
    sessionDetail.append(pre);
    const copy = el('button', null, 'Copy that prompt');
    copy.addEventListener('click', async () => {
      await navigator.clipboard.writeText(prompt).catch(() => {});
      copy.textContent = 'Copied';
    });
    sessionDetail.append(el('div', 'row', ''));
    sessionDetail.lastChild.append(copy);
  }
}

function toggleSession() {
  sessionDetail.hidden = !sessionDetail.hidden;
}

sessionChip.addEventListener('click', toggleSession);

/** The chip goes stale on its own if nothing refreshes it, so it is polled while answering. */
setInterval(async () => {
  if (!key) return;
  const latest = await api('?poll=1').catch(() => null);
  if (!latest) return;
  const was = design?.session?.watching;
  design = { ...design, session: latest.session, owner: latest.owner, agent: latest.agent };
  if (was !== latest.session?.watching || sessionChip.textContent === '') renderSession();
}, 7000);

// --- the history sidebar (S19.1) ------------------------------------------------------------------

/**
 * Q33=a asked for a BACK button and a clickable history. The history was a button that replaced
 * the question with a list of IDs and option letters — you had to leave the question to read it,
 * and what it showed was not enough to recognise an answer by. It is now a sidebar that is always
 * there, scrolls, and carries **both halves**: what was asked, and what you said.
 */
function renderHistoryPanel() {
  historyList.replaceChildren();
  const live = history.filter((h) => h.active).length;
  historyCount.textContent = history.length
    ? `${live}${history.length > live ? ` of ${history.length}` : ''}`
    : '';
  if (!history.length) {
    historyList.append(el('p', 'faint', 'Nothing yet. Answers appear here as you give them.'));
    return;
  }
  for (const h of history) {
    const answer = h.override
      ? `<em>your own answer</em>${h.note ? ` — ${md(h.note.slice(0, 140))}` : ''}`
      : `<span class="state-${h.state}">(${h.option})</span> ${md(h.label || '')}`;
    const button = el('button', `history-entry${h.active ? '' : ' inactive'}`
      + `${view && h.id === view.question.id ? ' current' : ''}`,
      `<span class="hq"><span class="hid">${h.id}</span>${md(h.text || '')}</span>`
      + `<span class="ha">${answer}</span>`
      + (h.active ? '' : '<span class="hq faint">— set aside by a later change, kept</span>'));
    button.dataset.id = h.id;
    button.addEventListener('click', () => revisit(h.id));
    historyList.append(button);
  }
  const current = historyList.querySelector('.history-entry.current');
  current?.scrollIntoView({ block: 'nearest' });
}

function toggleHistory() {
  document.body.classList.toggle('no-history');
  historyHandle.textContent = document.body.classList.contains('no-history') ? '›' : '‹';
}

historyHandle.addEventListener('click', toggleHistory);

// --- the question screen ---------------------------------------------------------------------------

function render() {
  const q = view.question;
  focusables = [];
  focusIndex = -1;
  screen.replaceChildren();

  if (banner) {
    screen.append(banner);
    banner = null;
  }

  if (view.revisit) {
    const back = el('div', 'banner', 'You are looking at an answer you already gave. '
      + 'Changing it may make later answers irrelevant — you will be told before that happens.');
    screen.append(back);
  }

  if (q.gap) screen.append(el('div', 'phase', `${q.gap} · a gap found during implementation`));
  screen.append(el('div', 'qtext', md(q.text)));

  // Rule 4 — a question is answerable with nothing else on screen. A gap's question is its title,
  // so the report it came out of comes with it: what the design says, what it does not, why the
  // agent would not decide it. Without this the owner would have to go and read the file.
  if (q.context?.length) {
    const box = el('div', 'gap');
    const dl = document.createElement('dl');
    for (const { label, value } of q.context) {
      dl.append(el('dt', null, label), el('dd', null, md(value)));
    }
    box.append(dl);
    screen.append(box);
  }

  // Q17=a — the gate, collapsed by default, expandable to "asked because …".
  const why = describeGate(q.effectiveGate, parsed.questions, answersFromHistory(history));
  if (why.length) {
    const details = el('details', 'why');
    details.append(el('summary', null, 'asked because…'));
    for (const w of why) {
      const line = w.op === '='
        ? `<strong>${w.id}</strong> = ${md(w.chosenLabel || w.wanted.join(' or '))}`
        : `<strong>${w.id}</strong> is anything but ${md(w.wanted.join(' or '))}`;
      details.append(el('div', 'muted', `${line} <span class="faint">— ${md(w.question)}</span>`));
    }
    screen.append(details);
  }

  const list = el('div', 'options');
  for (const option of q.options) {
    const button = el('button', 'option');
    button.type = 'button';
    button.dataset.letter = option.letter;
    // The option's own letter IS its key — `(b)` is pressed by `b` — so it needs no second chip
    // saying the same character twice. The key legend below says as much once.
    button.innerHTML = `<span class="letter">(${option.letter})</span><span class="label">${md(option.label)}</span>`;
    // Q12=b — the recommendation is MARKED but never pre-selected; every answer is a real click.
    if (option.letter === q.default) button.querySelector('.label').after(el('span', 'rec', 'recommended'));
    if (option.consequence) button.append(el('span', 'consequence', md(option.consequence)));
    // B7b / Q17d — only a ⚑gate previews what follows. On an ordinary question it is noise.
    // GAP-001=b: an option whose preview the author never wrote says so, rather than rendering
    // nothing. Silence here is indistinguishable from "nothing follows this branch", and rule 5
    // exists so that a path is never chosen blind — an honest gap is the least bad way to say it.
    if (q.isGate) {
      button.append(option.next
        ? el('span', 'next', `→ next: ${md(option.next)}`)
        : el('span', 'next missing', '→ next: not described'));
    }
    if (view.answer && view.answer.option === option.letter && !view.answer.override) button.classList.add('selected');
    button.addEventListener('click', () => choose(option.letter));
    list.append(button);
    focusables.push(button);
  }
  screen.append(list);

  // Free text is on every question, always (Q15, settled). On a ⚑gate it ends the round (chart B2).
  screen.append(el('label', 'note-label', q.isGate
    ? 'Or write your own answer — on a question like this one that ends the round, and I go author the branch you actually want.'
    : 'Add a note, or write your own answer instead of choosing.'));
  const note = document.createElement('textarea');
  note.id = 'note';
  // The draft outranks the recorded note: it is what the owner typed most recently and has not
  // committed. Restoring it is what makes a stray keystroke survivable (S19.4).
  note.value = readDraft(q.id) || view.answer?.note || '';
  note.addEventListener('input', () => {
    hammered = [];
    writeDraft(q.id, note.value);
    // Typing changes what Enter does — it now means "use what I wrote" — so the marker moves as
    // the first character lands, not as a surprise afterwards.
    paintEnterTarget();
  });
  screen.append(note);
  focusables.push(note);

  const row = el('div', 'row');
  row.style.marginTop = '1rem';
  const write = withKey(el('button', null, 'Use what I wrote'), keyFor('write'));
  write.dataset.action = 'write';
  write.addEventListener('click', () => submitWritten());
  // Q17b=a / Q14 — NOT RELEVANT records the recommended default and flags it unreviewed. It is one
  // button, not two: "skip" and "not relevant" would be the same act under two names.
  const nr = withKey(el('button', null, 'Not relevant'), keyFor('notRelevant'));
  nr.title = 'Records the recommended answer and flags it as unreviewed';
  nr.addEventListener('click', () => submit({ state: 'not_relevant', option: q.default, note: noteValue() }));
  const target = backTarget();
  const back = withKey(el('button', null, '← Back'), '⌫');
  back.disabled = !target;
  // A disabled button that says why beats a live one that does nothing, which is what sent the
  // owner to the history list in the first place.
  back.title = target
    ? `Back to ${target.id}`
    : 'Nothing to go back to yet — this is the first question you have seen';
  back.addEventListener('click', goBack);
  const hist = withKey(el('button', null, 'History'), keyFor('history'));
  hist.title = 'Show or hide the list of what you have answered';
  hist.addEventListener('click', toggleHistory);
  row.append(write, nr, el('span', 'spacer'), back, hist);
  for (const b of [write, nr, back, hist]) focusables.push(b);
  screen.append(row);

  screen.append(el('p', 'faint', q.notes
    ? 'The options here may not cover it — writing your own answer is expected.'
    : '&nbsp;'));

  renderKeyHelp();
  renderHistoryPanel();
  paintEnterTarget();
}

/** The key legend, from the same map the handler reads — it cannot drift from what the keys do. */
function renderKeyHelp() {
  const q = view.question;
  const parts = [
    `<span class="kbd">↑</span><span class="kbd">↓</span> move`,
    `<span class="kbd">⏎</span> the highlighted one`,
    `${q.options.map((o) => `<span class="kbd">${o.letter}</span>`).join('')} the options`,
    keyFor('write') ? `<span class="kbd">${keyFor('write')}</span> use what I wrote` : '',
    keyFor('notRelevant') ? `<span class="kbd">${keyFor('notRelevant')}</span> not relevant` : '',
    `<span class="kbd">⌫</span> back`,
    keyFor('history') ? `<span class="kbd">${keyFor('history')}</span> history` : '',
    keyFor('canvas') ? `<span class="kbd">${keyFor('canvas')}</span> review canvas` : '',
    keyFor('session') ? `<span class="kbd">${keyFor('session')}</span> is anyone watching` : '',
  ].filter(Boolean);
  keyhelp.innerHTML = parts.join(' · ');
}

// --- what Enter does, said out loud (S19.3) ---------------------------------------------------------
//
// Enter used to silently take the recommendation. Nothing on the screen said so, so the owner
// learned it by having it happen — and it happened while there was typed text in the note box,
// which it discarded. Now: exactly one control is marked as Enter's target at all times, the mark
// moves as the situation changes, and the target is whatever the mark is on.

/** The index in `focusables` that Enter will press, and whether that is the owner's choice. */
function enterTarget() {
  if (focusIndex >= 0) return { index: focusIndex, deliberate: true };
  const q = view?.question;
  if (!q) return { index: -1, deliberate: false };
  // Typed something? Then Enter means what you wrote. It can never mean "throw that away and take
  // the recommendation" — that was the bug.
  if (noteValue().trim()) {
    const index = focusables.findIndex((n) => n.dataset?.action === 'write');
    return { index, deliberate: false, written: true };
  }
  const index = focusables.findIndex((n) => n.dataset?.letter === q.default);
  return { index, deliberate: false, defaulted: index >= 0 };
}

function paintEnterTarget() {
  for (const node of focusables) {
    node.classList.remove('enter-target');
    node.querySelector?.('.enter-chip')?.remove();
  }
  const { index } = enterTarget();
  const node = focusables[index];
  if (!node || node.tagName === 'TEXTAREA') return;
  node.classList.add('enter-target');
  node.append(el('span', 'enter-chip', '⏎ Enter'));
}

function paintFocus() {
  focusables.forEach((node, i) => node.classList.toggle('focused', i === focusIndex));
  if (focusIndex >= 0) focusables[focusIndex].focus();
  paintEnterTarget();
}

/** Enter, in one place: press whatever is marked, in the mode the mark means. */
function pressEnter() {
  const target = enterTarget();
  const node = focusables[target.index];
  if (!node) return;
  if (target.deliberate) {
    // The owner moved the mark there themselves, so this is a considered answer (Q108: `chosen`),
    // not a default that was walked past.
    node.click();
    return;
  }
  if (target.written) return submitWritten();
  return acceptDefault();
}

/** Write-in answers, from the button and from Enter alike, so they cannot behave differently. */
function submitWritten() {
  const text = noteValue();
  if (!text.trim()) {
    banner = el('div', 'banner warn', 'There is nothing written yet — type your answer first, or pick an option.');
    render();
    return Promise.resolve();
  }
  return submit({ override: true, note: text, state: 'chosen' });
}

/** Pick an option deliberately (Q108: `chosen`). */
function choose(letter) {
  hammered = [];
  submit({ state: 'chosen', option: letter, note: noteValue() });
}

/**
 * Send an answer. A question that already has an answer goes through `reanswer`, which previews
 * its blast radius first (Q34=a) — nothing is stranded before the owner has seen the number.
 */
async function submit(payload) {
  const q = view.question;
  const body = { id: q.id, state: 'chosen', option: null, note: '', override: false, ...payload };
  const already = history.some((h) => h.id === q.id);

  if (already) {
    const preview = await api('/reanswer?preview=1', {
      method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body),
    });
    // Q34=a — said clearly BEFORE it applies, in the page rather than in a browser dialog, so it
    // is reachable by keyboard like everything else (Q113=a).
    if (preview.strand.length) {
      renderBlastRadius(preview, () => apply(body, already));
      return;
    }
  }
  return apply(body, already);
}

/** The Q34 warning screen: what a re-answer is about to set aside, and a way out. */
function renderBlastRadius(preview, onContinue) {
  screen.replaceChildren();
  screen.append(el('h2', null, `This makes ${preview.strand.length} of your answers irrelevant`));
  screen.append(el('p', 'muted', 'They are kept, marked inactive, and come back intact if you change '
    + 'your mind again. Nothing you typed is lost.'));
  const ul = el('ul', 'history');
  for (const s of preview.strand) {
    const li = document.createElement('li');
    li.append(el('div', 'history-item inactive', `<strong>${s.id}</strong> ${md(s.text.slice(0, 110))}`));
    ul.append(li);
  }
  screen.append(ul);
  if (preview.restore.length) {
    screen.append(el('p', 'muted', `${preview.restore.length} earlier answer`
      + `${preview.restore.length === 1 ? '' : 's'} would come back: `
      + preview.restore.map((r) => r.id).join(', ')));
  }
  const row = el('div', 'row');
  const go = el('button', null, 'Continue');
  go.addEventListener('click', onContinue);
  const cancel = el('button', null, 'Leave it as it was');
  cancel.addEventListener('click', () => render());
  row.append(go, cancel);
  screen.append(row);
  focusables = [go, cancel];
  focusIndex = 0;
  paintFocus();
}

/** Send the answer and move on. Everything before this point is preview; this is the write. */
async function apply(body, already) {
  const q = view.question;
  const result = await api(already ? '/reanswer' : '/answer', {
    method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body),
  });

  // It is recorded, so the draft has served its purpose. Only now — never before the 200.
  writeDraft(q.id, '');
  history = await api('/history');
  if (result.strand.length || result.restore.length) {
    const parts = [];
    if (result.strand.length) parts.push(`${result.strand.length} answer${result.strand.length === 1 ? '' : 's'} became irrelevant and were kept, marked inactive`);
    if (result.restore.length) parts.push(`${result.restore.length} earlier answer${result.restore.length === 1 ? '' : 's'} came back`);
    banner = el('div', 'banner warn', parts.join(', and '));
  }

  if (body.override && q.isGate) return refresh();     // chart B2 — the round ends on the spot
  if (result.done || !result.next) return refresh();
  view = { question: result.next, answer: null, revisit: false };
  pushNav(result.next.id);
  return render();
}

/** Enter on a question the owner has not touched accepts the recommendation (Q12, Q109–Q111). */
async function acceptDefault() {
  const q = view.question;
  // Q109=a / Q110=a — a gate picks a whole path and a `notes` question is flagged because the
  // options may not be enough. Neither may be walked past without a deliberate choice.
  if (q.isGate || q.notes) {
    endHammerRun(q);
    return;
  }
  const label = q.options.find((o) => o.letter === q.default)?.label || '';
  hammered.push({ id: q.id, letter: q.default, label });
  // The note rides along. Enter cannot be a way to lose it (S19.4).
  await submit({ state: 'defaulted', option: q.default, note: noteValue() });
}

/** Show what a run of Enter just accepted, and stop (Q111=a). */
function endHammerRun(q) {
  const box = el('div', 'banner warn');
  const why = q.isGate
    ? 'This one decides a whole branch, so it needs a deliberate answer — defaulting past it would '
      + 'commit you to a path you never saw.'
    : 'This one is flagged as likely to need more than its options offer, so it needs a deliberate answer.';
  box.append(el('div', null, hammered.length
    ? `<strong>You accepted ${hammered.length} recommended answer${hammered.length === 1 ? '' : 's'}</strong> `
      + `without reading ${hammered.length === 1 ? 'it' : 'them'}. ${why}`
    : why));
  if (hammered.length) {
    const ul = el('ul', 'history');
    for (const h of hammered) {
      const li = document.createElement('li');
      const b = el('button', 'history-item', `<strong>${h.id}</strong> <span class="state-defaulted">(${h.letter})</span> ${md(h.label)}`);
      b.addEventListener('click', () => revisit(h.id));
      li.append(b);
      ul.append(li);
    }
    box.append(ul);
  }
  banner = box;
  hammered = [];
  render();
  focusIndex = 0;
  paintFocus();
}

// --- revisiting (chart D) --------------------------------------------------------------------------

/** Open an earlier question with its recorded answer selected (D2). */
async function revisit(id, { record = true } = {}) {
  hammered = [];
  const q = parsed.questions.find((x) => x.id === id) || gapQuestions.find((x) => x.id === id);
  const answer = history.find((h) => h.id === id);
  if (!q) return;
  // The "you already answered this" banner belongs to an answer that exists. Arriving from the
  // canvas at a question nobody has reached yet is just being asked it early.
  view = { question: q, answer, revisit: !!answer };
  if (record) pushNav(id);
  render();
}

// --- the DONE screen (Q28=a, chart E10) ----------------------------------------------------------

let poll = null;

/**
 * The end of a scoped round (chart J15). It does not wait for the agent the way the main round
 * does: the agent's next act is a new design version and a changelog, not more questions, and the
 * owner's own next act is usually to look at what the answers just made stale.
 */
function renderGapsDone(data) {
  screen.replaceChildren();
  const answered = data.gaps.filter((g) => g.open && g.answer);
  screen.append(el('h2', null, answered.length
    ? 'That is every open gap answered'
    : 'Nothing here is waiting on you'));
  screen.append(el('p', 'muted', answered.length
    ? 'The agent has been handed the turn back. It writes the next design version — a changelog of '
      + 'what changed and which gaps closed — and re-derives the plan steps your answers made stale. '
      + 'Steps that cite none of it were never blocked and keep their work.'
    : 'Every gap on this design is either closed or still waiting for the agent to draft its '
      + 'options. Nothing here needs an answer from you.'));
  if (answered.length && !design?.session?.watching) {
    screen.append(el('p', 'muted', 'Nothing is watching this design right now, so tell the agent in '
      + 'chat — the answers are on disk either way. The chip at the top has a prompt to paste.'));
  }
  const row = el('div', 'row');
  const gaps = el('button', null, 'See the gaps and what is stale');
  gaps.addEventListener('click', () => { location.href = `gaps.html?key=${encodeURIComponent(key)}`; });
  row.append(gaps);
  screen.append(row);
  // No question is on screen, so no key may act as though one were: `view` going null is what
  // stops `w`, `n` and Enter from operating on the question that was here a moment ago.
  view = null;
  focusables = [gaps];
  focusIndex = -1;
  keyhelp.innerHTML = '';
  renderHistoryPanel();
}

function renderDone(state) {
  screen.replaceChildren();
  const reason = state.owner?.reason || state.reason;
  screen.append(el('h2', null, reason === 'new_branch_needed'
    ? 'Your answer needs a branch that does not exist yet'
    : 'That is everything for now'));
  screen.append(el('p', 'muted', reason === 'new_branch_needed'
    ? 'Every question after that one sits on a path you just declined to take, so the round has ended '
      + 'here. The agent is reading what you wrote and will author the branch you actually want — you '
      + 'will come back to that same question with your answer on it as a real option.'
    : 'The agent is reading your answers. This screen switches itself over when the next round is ready — '
      + 'and telling it in chat always works too.'));
  // The one place where "is anyone listening?" decides what the owner should do next, so it is
  // said here in full rather than left to the chip.
  if (!design?.session?.watching) {
    screen.append(el('div', 'banner warn',
      '<strong>Nothing is watching this design.</strong> Your answers are safely on disk — every one '
      + 'of them was written before the next question appeared — but no session will wake up on its '
      + 'own. Open the chip at the top of the screen for a prompt to paste into a Claude Code '
      + 'session, or just say so in chat.'));
  }
  screen.append(el('p', 'faint', 'Everything you answered is in the sidebar, and clicking any of it goes back to that question.'));
  view = null;
  focusables = [];
  focusIndex = -1;
  keyhelp.innerHTML = '';
  renderHistoryPanel();

  // E10 — the UI watches `status.agent.json` and switches ITSELF over. The owner never has to
  // reload, and never has to be told to.
  clearInterval(poll);
  poll = setInterval(async () => {
    const latest = await api('?poll=1').catch(() => null);
    if (!latest) return;
    design = { ...design, ...latest };
    renderSession();
    if (latest.agent.state !== 'ready') return;
    clearInterval(poll);
    // Q29=a — round 2 opens by saying what opened it, not just with more questions.
    if (latest.agent.summary) banner = el('div', 'banner', md(latest.agent.summary));
    await refresh();
  }, 1500);
}

// --- input parity (Q112, Q113) --------------------------------------------------------------------

document.addEventListener('keydown', (event) => {
  const typing = ['TEXTAREA', 'INPUT'].includes(document.activeElement?.tagName);
  // Ctrl/Alt/Meta belong to the browser — Ctrl+Z in the note box has to keep working, which is the
  // whole point of not destroying what was typed in the first place.
  if (event.ctrlKey || event.metaKey) {
    // …except the browser-ish back chord, which people try.
    if (event.key === 'ArrowLeft' && event.altKey) { event.preventDefault(); goBack(); }
    return;
  }
  if (event.altKey) {
    if (event.key === 'ArrowLeft') { event.preventDefault(); goBack(); }
    return;
  }

  if (event.key === 'Escape' && !sessionDetail.hidden) {
    sessionDetail.hidden = true;
    return;
  }
  if (event.key === 'ArrowDown' || event.key === 'ArrowUp') {
    if (typing) return;
    event.preventDefault();
    hammered = [];
    // The ring has one slot MORE than there are controls: slot 0 is "the owner has not chosen",
    // which is the state that leaves Enter on its automatic target. Arrowing past the end returns
    // to it, and the ⏎ mark visibly springs back to the recommendation.
    const slots = focusables.length + 1;
    const slot = (focusIndex + 1 + (event.key === 'ArrowDown' ? 1 : -1) + slots) % slots;
    focusIndex = slot - 1;
    if (focusIndex < 0) document.activeElement?.blur();
    paintFocus();
    return;
  }
  if (event.key === 'Enter' && !typing) {
    event.preventDefault();
    if (view) pressEnter();
    else if (focusIndex >= 0) focusables[focusIndex].click();
    return;
  }
  if (event.key === 'Backspace' && !typing) {
    event.preventDefault();
    goBack();
    return;
  }
  if (typing) return;

  if (event.key === '?') {
    keyhelp.classList.toggle('faint');
    return;
  }
  if (!view) return;

  // An option's letter moves the mark to it. It does not answer on its own: a single stray key
  // must never commit an answer, and the ⏎ mark now makes the second step obvious.
  const option = focusables.findIndex((n) => n.dataset?.letter === event.key);
  if (option >= 0) {
    event.preventDefault();
    hammered = [];
    focusIndex = option;
    paintFocus();
    return;
  }
  // Every other control has a key, and presses on the spot — none of them records an answer
  // without another confirmation, so there is nothing to protect against.
  const actions = new Map();
  const bind = (name, fn) => {
    const k = keyFor(name);
    // An action whose key an option has claimed simply has no key on this question. Silently
    // rebinding it to something else would put a key on screen that does something else tomorrow.
    if (k) actions.set(k, fn);
  };
  bind('write', () => submitWritten());
  bind('notRelevant', () => submit({ state: 'not_relevant', option: view.question.default, note: noteValue() }));
  bind('history', toggleHistory);
  bind('canvas', () => { location.href = `canvas.html?key=${encodeURIComponent(key)}`; });
  bind('session', toggleSession);
  const action = actions.get(event.key);
  if (action) {
    event.preventDefault();
    action();
  }
});

refresh().catch((err) => {
  screen.replaceChildren(el('div', 'banner bad', `Could not open this design: ${md(err.message)}`));
});

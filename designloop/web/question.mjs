// The answering session (PLAN S5–S8; DESIGN charts B, B2, D).
//
// One question on the screen and NOTHING that indicates progress (Q10=a, Q26=a, Q114=a) — no
// count, no bar, no "question 4 of". The end of a round arrives without warning, and the DONE
// screen is the signal.
//
// This module imports `../src/grammar.mjs` — the same file the server parses with. That is the
// point of the Node runtime (DESIGN §11): the screen and the server cannot disagree about what a
// gate means, because there is one parser.

import { parseDocument, describeGate } from '../src/grammar.mjs';

const key = new URLSearchParams(location.search).get('key') || '';
const screen = document.getElementById('screen');
const titleEl = document.getElementById('design-title');

/** The design's meta + both status halves. */
let design = null;
/** The parsed document, for gate explanations and history labels. */
let parsed = { questions: [], sections: [] };
/** The question on screen, its recorded answer if it has one, and whether this is a re-answer. */
let view = null;
/** A run of Enter-accepted defaults, shown back to the owner when the run ends (Q111=a). */
let hammered = [];
/** Where the visible focus ring is. -1 means nothing is focused, and Enter takes the default. */
let focusIndex = -1;
let focusables = [];
/** A message to show above the next question — stranding notices, hammer summaries, round openers. */
let banner = null;

const api = (path, init) => fetch(`/api/designs/${key}${path}`, init).then(async (r) => {
  const body = await r.json().catch(() => ({}));
  if (!r.ok) throw new Error(body.error || `${r.status}`);
  return body;
});

/** Escape, then render the inline markdown a question may contain (Q19=a). */
function md(text) {
  const safe = String(text ?? '')
    .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
  return safe
    .replace(/`([^`]+)`/g, '<code>$1</code>')
    .replace(/\*\*([^*]+)\*\*/g, '<strong>$1</strong>')
    .replace(/(^|[^*])\*([^*]+)\*/g, '$1<em>$2</em>');
}

/** Build an element with inline markdown content. */
function el(tag, className, html) {
  const node = document.createElement(tag);
  if (className) node.className = className;
  if (html !== undefined) node.innerHTML = html;
  return node;
}

/** The answers map, as the grammar module wants it. */
function answersFromHistory(history) {
  const map = {};
  for (const h of history) map[h.id] = { option: h.option, active: h.active, state: h.state };
  return map;
}

let history = [];

// --- loading -----------------------------------------------------------------------------------

async function refresh() {
  design = await api('');
  titleEl.textContent = design.title;
  document.title = `${design.title} — Design Loop`;
  if (!parsed.questions.length) {
    parsed = parseDocument(await fetch(`/api/designs/${key}/doc`).then((r) => r.text()));
  }
  history = await api('/history');
  // The round can end with reachable questions still on the table: free text at a ⚑gate ends it on
  // the spot, because every question after it sits on a branch just declined (chart B2, §4.2).
  if (design.owner.state === 'done' && design.agent.state !== 'ready') {
    return renderDone({ owner: design.owner, agent: design.agent });
  }
  if (design.agent.state === 'ready' && design.owner.state === 'done') {
    // The agent finished a round while this screen was away. Take the turn back (§4.2).
    design = await api('/resume', { method: 'POST' });
  }
  const next = await api('/next');
  if (next.done) return renderDone(next);
  view = { question: next.question, answer: next.answer, revisit: false };
  return render();
}

// --- the question screen -------------------------------------------------------------------------

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

  screen.append(el('div', 'qtext', md(q.text)));

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
    button.innerHTML = `<span class="letter">(${option.letter})</span><span class="label">${md(option.label)}</span>`;
    // Q12=b — the recommendation is MARKED but never pre-selected; every answer is a real click.
    if (option.letter === q.default) button.querySelector('.label').after(el('span', 'rec', 'recommended'));
    if (option.consequence) button.append(el('span', 'consequence', md(option.consequence)));
    // B7b / Q17d — only a ⚑gate previews what follows. On an ordinary question it is noise.
    if (q.isGate && option.next) button.append(el('span', 'next', `→ next: ${md(option.next)}`));
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
  note.value = view.answer?.note || '';
  note.addEventListener('input', () => { hammered = []; });
  screen.append(note);
  focusables.push(note);

  const row = el('div', 'row');
  row.style.marginTop = '1rem';
  const write = el('button', null, 'Use what I wrote');
  write.addEventListener('click', () => submit({ override: true, note: note.value, state: 'chosen' }));
  // Q17b=a / Q14 — NOT RELEVANT records the recommended default and flags it unreviewed. It is one
  // button, not two: "skip" and "not relevant" would be the same act under two names.
  const nr = el('button', null, 'Not relevant');
  nr.title = 'Records the recommended answer and flags it as unreviewed';
  nr.addEventListener('click', () => submit({ state: 'not_relevant', option: q.default, note: note.value }));
  const back = el('button', null, '← Back');
  back.addEventListener('click', goBack);
  const hist = el('button', null, 'History');
  hist.addEventListener('click', renderHistory);
  row.append(write, nr, el('span', 'spacer'), back, hist);
  for (const b of [write, nr, back, hist]) focusables.push(b);
  screen.append(row);

  screen.append(el('p', 'faint', q.notes
    ? 'The options here may not cover it — writing your own answer is expected.'
    : '&nbsp;'));
}

/** Pick an option deliberately (Q108: `chosen`). */
function choose(letter) {
  hammered = [];
  submit({ state: 'chosen', option: letter, note: document.getElementById('note')?.value || '' });
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
  return render();
}

/** Enter on a question nobody has focused accepts the recommendation (Q12, Q109–Q111). */
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
  await submit({ state: 'defaulted', option: q.default, note: '' });
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

// --- back, history, revisiting (chart D) --------------------------------------------------------

function goBack() {
  hammered = [];
  const live = history.filter((h) => h.active);
  const last = live[live.length - 1];
  if (!last) return;
  revisit(last.id);
}

/** Open an earlier question with its recorded answer selected (D2). */
async function revisit(id) {
  hammered = [];
  const q = parsed.questions.find((x) => x.id === id);
  const answer = history.find((h) => h.id === id);
  if (!q) return;
  view = { question: q, answer, revisit: true };
  render();
}

/** Q33=a — a BACK button AND a clickable history list. */
function renderHistory() {
  screen.replaceChildren();
  screen.append(el('h2', null, 'What you have answered'));
  const ul = el('ul', 'history');
  for (const h of history) {
    const li = document.createElement('li');
    const state = h.override ? 'your own answer' : `(${h.option})`;
    const b = el('button', `history-item${h.active ? '' : ' inactive'}`,
      `<strong>${h.id}</strong> <span class="state-${h.state}">${state}</span> ${md(h.label || h.note || '')}`
      + (h.active ? '' : ' <span class="faint">— set aside by a later change, kept</span>'));
    b.addEventListener('click', () => revisit(h.id));
    li.append(b);
    ul.append(li);
  }
  screen.append(ul);
  const back = el('button', null, 'Back to the question');
  back.addEventListener('click', () => render());
  const row = el('div', 'row');
  row.append(back);
  screen.append(row);
  focusables = [...ul.querySelectorAll('button'), back];
  focusIndex = -1;
}

// --- the DONE screen (Q28=a, chart E10) ----------------------------------------------------------

let poll = null;

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
  const hist = el('button', null, 'Look back over your answers');
  hist.addEventListener('click', renderHistory);
  screen.append(hist);

  // E10 — the UI watches `status.agent.json` and switches ITSELF over. The owner never has to
  // reload, and never has to be told to.
  clearInterval(poll);
  poll = setInterval(async () => {
    const latest = await api('').catch(() => null);
    if (!latest || latest.agent.state !== 'ready') return;
    clearInterval(poll);
    // Q29=a — round 2 opens by saying what opened it, not just with more questions.
    if (latest.agent.summary) banner = el('div', 'banner', md(latest.agent.summary));
    await refresh();
  }, 1500);
}

// --- input parity (Q112, Q113) --------------------------------------------------------------------

function paintFocus() {
  focusables.forEach((node, i) => node.classList.toggle('focused', i === focusIndex));
  if (focusIndex >= 0) focusables[focusIndex].focus();
}

document.addEventListener('keydown', (event) => {
  const typing = document.activeElement?.tagName === 'TEXTAREA';
  if (event.key === 'ArrowDown' || event.key === 'ArrowUp') {
    if (typing) return;
    event.preventDefault();
    hammered = [];
    // The ring has one slot MORE than there are controls: slot 0 is "nothing focused", which is
    // the state Enter reads as "accept the recommendation". Arrowing past the end returns to it.
    const slots = focusables.length + 1;
    const slot = (focusIndex + 1 + (event.key === 'ArrowDown' ? 1 : -1) + slots) % slots;
    focusIndex = slot - 1;
    if (focusIndex < 0) document.activeElement?.blur();
    paintFocus();
    return;
  }
  if (event.key === 'Enter' && !typing) {
    event.preventDefault();
    if (focusIndex >= 0) focusables[focusIndex].click();
    else if (view) acceptDefault();
    return;
  }
  if (event.key === 'Backspace' && !typing) {
    event.preventDefault();
    goBack();
    return;
  }
  if (!typing && /^[a-z]$/.test(event.key) && view) {
    const index = focusables.findIndex((n) => n.dataset?.letter === event.key);
    if (index >= 0) {
      event.preventDefault();
      hammered = [];
      focusIndex = index;
      paintFocus();
    }
  }
});

refresh().catch((err) => {
  screen.replaceChildren(el('div', 'banner bad', `Could not open this design: ${md(err.message)}`));
});

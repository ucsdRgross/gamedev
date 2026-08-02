// The gap surface (PLAN S15; DESIGN chart J8–J17, Q89b, Q90b, Q92b, Q95b, Q96b).
//
// One page answering the three questions an owner has when an agent says "I filed a gap":
// what is open, what does it block, and what did the closed ones turn into.
//
//   - open gaps, each with the options the agent drafted, and one button that starts the SCOPED
//     round (Q90b=b — in the website, never the whole questionnaire again)
//   - the plan steps those open gaps make STALE (Q92b=a, J16), each naming the node that did it
//   - closed gaps, kept with their resolutions (Q96b=a)

import { md } from './md.mjs';

const key = new URLSearchParams(location.search).get('key') || '';
const body = document.getElementById('body');

document.getElementById('question-link').href = `question.html?key=${encodeURIComponent(key)}`;
document.getElementById('canvas-link').href = `canvas.html?key=${encodeURIComponent(key)}`;

function el(tag, className, html) {
  const node = document.createElement(tag);
  if (className) node.className = className;
  if (html !== undefined) node.innerHTML = html;
  return node;
}

/** One gap, open or closed. */
function renderGap(gap) {
  const card = el('div', `gap ${gap.open ? 'open' : 'closed'}`);
  card.append(el('h3', null, `${gap.id} — ${md(gap.title)}`));
  const meta = el('div', 'gap-meta');
  meta.append(el('span', `badge ${gap.open ? 'gaps' : 'ok'}`, gap.status));
  if (gap.severity) meta.append(' ', el('span', 'badge', gap.severity));
  meta.append(` ${gap.raised || ''}`);
  card.append(meta);

  const dl = document.createElement('dl');
  for (const { label, value } of gap.context || []) {
    dl.append(el('dt', null, label), el('dd', null, md(value)));
  }

  // Q96b=a — a closed gap is the record of where the design was thin, and it is only a record if
  // what it became is on the page beside it.
  if (gap.resolution) {
    dl.append(el('dt', null, 'Resolution'), el('dd', null, md(gap.resolution)));
  }

  if (gap.question) {
    dl.append(el('dt', null, gap.open ? 'Options — this is what the scoped round asks' : 'Options it offered'));
    const dd = document.createElement('dd');
    for (const option of gap.question.options) {
      const line = el('span', 'opt');
      line.append(el('span', 'letter', `(${option.letter})`));
      line.append(el('span', null, md(option.label)
        + (option.consequence ? ` <span class="faint">— ${md(option.consequence)}</span>` : '')
        + (option.letter === gap.question.default ? ' <span class="rec">recommended</span>' : '')));
      dd.append(line);
    }
    dl.append(dd);
  } else if (gap.open) {
    dl.append(el('dt', null, 'Options'), el('dd', 'faint', gap.error
      ? `this gap's options do not parse — ${md(gap.error)}`
      : 'none drafted yet. The agent writes them in the questionnaire grammar; '
        + 'the tool does not author questions (Q94=a).'));
  }

  if (gap.answer) {
    dl.append(el('dt', null, 'Your answer'), el('dd', null, gap.answer.override
      ? md(gap.answer.note || 'your own answer')
      : `(${gap.answer.option})${gap.answer.note ? ` — ${md(gap.answer.note)}` : ''}`));
  }

  const blast = [
    gap.blast?.steps?.length ? `plan steps ${gap.blast.steps.join(', ')}` : '',
    gap.blast?.nodes?.length ? `design nodes ${gap.blast.nodes.join(', ')}` : '',
  ].filter(Boolean).join(' · ');
  if (blast) dl.append(el('dt', null, 'Blast radius'), el('dd', 'faint', blast));

  card.append(dl);
  return card;
}

const data = await (await fetch(`/api/designs/${key}/gaps`)).json();
const design = await (await fetch(`/api/designs/${key}`)).json();
document.getElementById('design-title').textContent = `${design.title} — gaps`;
document.title = `Gaps — ${design.title}`;

const open = data.gaps.filter((g) => g.open);
const closed = data.gaps.filter((g) => !g.open);
const answerable = open.filter((g) => g.question && !g.answer);

body.replaceChildren();

if (!data.gaps.length) {
  body.append(el('p', 'muted', 'No gaps have been filed against this design. '
    + 'An executing agent files one when it meets a decision the design does not cover and cannot '
    + 'take on its own — it parks that thread only, and keeps working everything else.'));
}

if (open.length) {
  body.append(el('h2', null, `${open.length} open`));
  // Q90b=b / J12 — the scoped round, in the website. Only these questions and whatever they open.
  if (answerable.length) {
    const row = el('div', 'row');
    const go = el('a', 'design-card', `<strong>Answer ${answerable.length} `
      + `gap${answerable.length === 1 ? '' : 's'} now</strong><div class="meta">A scoped round: `
      + `only these questions, never the whole questionnaire again.</div>`);
    go.href = `question.html?key=${encodeURIComponent(key)}&scope=gaps`;
    go.style.cssText = 'text-decoration:none;display:block;width:100%';
    row.append(go);
    body.append(row);
  }
  for (const gap of open) body.append(renderGap(gap));
}

// J16 — every plan step citing a node an open gap puts in question is STALE and is re-derived
// before it is worked again. Steps that cite none of it were never blocked (J17).
if (data.stale.length) {
  const box = el('div', 'banner stale');
  box.append(el('div', null, `<strong>${data.stale.length} plan step`
    + `${data.stale.length === 1 ? ' is' : 's are'} stale.</strong> `
    + 'Re-derive them against the answer before working them again. Every other step was never '
    + 'blocked and is not thrown away.'));
  for (const step of data.stale) {
    const why = [step.because.length ? `nodes ${step.because.join(', ')}` : '', step.named ? 'named in the blast radius' : '']
      .filter(Boolean).join(' · ');
    box.append(el('span', 'step', `<span class="mono">${step.id}</span> ${md(step.title || '')} `
      + `<span class="faint">— ${step.gap}, ${why}</span>`));
  }
  body.append(box);
} else if (data.steps) {
  body.append(el('p', 'faint', `No plan step is stale — ${data.steps} steps read, none of them `
    + 'citing anything an open gap puts in question.'));
}

if (closed.length) {
  body.append(el('h2', null, `${closed.length} closed, kept`));
  body.append(el('p', 'muted', 'Closed gaps are never deleted. They are the record of where the '
    + 'design was thin, and the best input into making the next questionnaire better (Q96b=a).'));
  for (const gap of closed) body.append(renderGap(gap));
}

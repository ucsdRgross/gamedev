// The review canvas (PLAN S12–S14; DESIGN chart F, Q52, Q53, Q54, Q63, Q66, Q113, Q115).
//
// The whole design graph at once, pan and zoom, with each chart collapsible (Q52=c) AND a chart
// picker that shows one chart on its own (Q52's written answer asked for both: the picker "to focus
// on specific subcharts without needing to see the entire graph", the whole graph "if I want to see
// all connections").
//
// It renders `graph.json` itself — the same file an implementation agent consumes (Q64=a, the
// no-mocks rule) — and it imports `../src/layout.mjs`, the same module the server would, so a
// version frozen at Confirm reproduces exactly (Q53=b, Q115=b).
//
// Desktop only (Q63=a). Everything reachable by mouse AND by keyboard (Q113=a): the key legend at
// the bottom of the canvas is the contract.

import { parseDocument, reachability } from '../src/grammar.mjs';
import { layout, edgeGeometry } from '../src/layout.mjs';
import { md, esc } from './md.mjs';

const key = new URLSearchParams(location.search).get('key') || '';
const svg = document.getElementById('canvas');
const stage = document.getElementById('stage');
const picker = document.getElementById('chart-picker');
const panel = document.getElementById('side-panel');
const statusLine = document.getElementById('canvas-status');

const api = (path, init) => fetch(`/api/designs/${key}${path}`, init).then(async (r) => {
  const body = await r.json().catch(() => ({}));
  if (!r.ok) throw new Error(body.error || `${r.status}`);
  return body;
});

/** Everything loaded from disk, and everything derived from it. Redrawn whole on any change. */
const state = {
  design: null,
  graph: null,
  questions: [],
  sections: [],
  answers: {},
  history: [],
  prunedQuestions: new Set(),
  annotations: { nodes: {}, edges: {}, approved: {}, flagged: {} },
  assumptions: [],
  outOfScope: [],
  versions: [],
  frozen: null,
  collapsed: new Set(),
  only: null,
  colourBy: 'chart',
  showRuledOut: false,
  selected: null,
  laid: null,
  view: { x: 0, y: 0, k: 1 },
};

/** Colour by chart (Q66): a fixed palette, indexed by the chart's place in the document. */
const CHART_COLOURS = [
  '#7ab6ff', '#ffb454', '#8fd694', '#e58ee0', '#f2748c', '#63d3d3',
  '#c3a6ff', '#d9c46a', '#8ea9ff', '#7fd1a8', '#ff9e7a', '#b7c26a',
];

const SVGNS = 'http://www.w3.org/2000/svg';

/** Build an SVG element with attributes, because doing it by hand 40 times is how typos hide. */
function svgEl(tag, attrs = {}, className = null) {
  const node = document.createElementNS(SVGNS, tag);
  for (const [k, v] of Object.entries(attrs)) node.setAttribute(k, v);
  if (className) node.setAttribute('class', className);
  return node;
}

// --- loading -------------------------------------------------------------------------------------

async function load() {
  state.design = await api('');
  document.getElementById('design-title').textContent = state.design.title;
  document.title = `${state.design.title} — review`;
  document.getElementById('questions-link').href = `question.html?key=${encodeURIComponent(key)}`;

  const [graph, doc, history, review, versions] = await Promise.all([
    api('/graph'),
    fetch(`/api/designs/${key}/doc`).then((r) => r.text()),
    api('/history'),
    api('/review'),
    api('/versions'),
  ]);

  state.graph = graph;
  const parsed = parseDocument(doc);
  state.questions = parsed.questions;
  state.sections = parsed.sections;
  state.history = history;
  state.answers = {};
  for (const h of history) state.answers[h.id] = { option: h.option, active: h.active, state: h.state, note: h.note, override: h.override };
  state.prunedQuestions = new Set(reachability(parsed.questions, state.answers).pruned.map((q) => q.id));
  state.annotations = { nodes: {}, edges: {}, approved: {}, flagged: {}, ...review.annotations };
  state.assumptions = review.assumptions || [];
  state.outOfScope = review.out_of_scope || [];
  state.versions = versions.versions || [];
  state.frozen = null;

  // Q115=b — a frozen version reopens exactly as it was left, collapse state included.
  const wanted = new URLSearchParams(location.search).get('version');
  if (wanted) {
    await openVersion(Number(wanted));
    return;
  }
  redraw();
  fit();
}

/**
 * A node the owner's answers ruled out (Q54=a): every question that decides it is pruned.
 * Hidden by default and revealable — "here is what you ruled out" — rather than deleted, because
 * a branch nobody took is still part of the record of why.
 */
function isRuledOut(id) {
  const decided = state.graph.nodes[id].decidedBy || [];
  return decided.length > 0 && decided.every((q) => state.prunedQuestions.has(q));
}

/** Every status a node can carry (Q66=c). The first one that applies wins the colour. */
function statusOf(id) {
  if (state.annotations.flagged?.[id]) return 'flagged';
  if (isRuledOut(id)) return 'ruled';
  if ((state.annotations.nodes[id] || []).length) return 'annotated';
  if (state.graph.nodes[id].new) return 'new';
  return 'plain';
}

// --- the chart picker ----------------------------------------------------------------------------

function renderPicker() {
  picker.replaceChildren();
  const all = document.createElement('button');
  all.className = `picker-row${state.only === null ? ' current' : ''}`;
  all.innerHTML = '<span class="picker-name">All charts</span>'
    + `<span class="picker-count">${state.graph.charts.length}</span>`;
  all.addEventListener('click', () => {
    state.only = null;
    redraw();
    fit();
  });
  picker.append(all);

  for (const chart of state.graph.charts) {
    const row = document.createElement('div');
    row.className = `picker-row-wrap${state.only === chart.id ? ' current' : ''}`;
    const open = document.createElement('button');
    open.className = 'picker-row';
    // The name wraps rather than being cut off, and the tooltip carries it whole either way — a
    // chart called "C reachability (what m…" is a chart you cannot identify from the list.
    open.title = `${chart.id} · ${chart.title}\n${chart.nodes.length} nodes — click to show it on its own`;
    open.innerHTML = `<span class="picker-swatch" style="background:${colourOf(chart.id)}"></span>`
      + `<span class="picker-name"><strong>${esc(chart.id)}</strong> ${esc(chart.title)}</span>`
      + `<span class="picker-count">${chart.nodes.length}</span>`;
    open.addEventListener('click', () => {
      state.only = state.only === chart.id ? null : chart.id;
      redraw();
      fit();
    });
    const fold = document.createElement('button');
    fold.className = 'picker-fold';
    fold.textContent = state.collapsed.has(chart.id) ? '+' : '–';
    fold.title = state.collapsed.has(chart.id) ? 'Expand this chart' : 'Collapse this chart to one box';
    fold.addEventListener('click', (e) => {
      e.stopPropagation();
      toggleCollapse(chart.id);
    });
    row.append(open, fold);
    picker.append(row);
  }
}

function colourOf(chartId) {
  const index = state.graph.charts.findIndex((c) => c.id === chartId);
  return CHART_COLOURS[(index < 0 ? 0 : index) % CHART_COLOURS.length];
}

function toggleCollapse(chartId) {
  if (state.collapsed.has(chartId)) state.collapsed.delete(chartId);
  else state.collapsed.add(chartId);
  redraw();
}

// --- drawing -------------------------------------------------------------------------------------

/** Recompute the layout and rebuild the SVG. At Spotlight's size this is a couple of milliseconds. */
function redraw() {
  const laid = state.frozen
    ? state.frozen.layout
    : layout(state.graph, { collapsed: [...state.collapsed], only: state.only });
  state.laid = laid;

  svg.replaceChildren();
  const defs = svgEl('defs');
  for (const [id, colour] of [['arrow', 'var(--edge)'], ['arrow-hi', 'var(--accent)']]) {
    const marker = svgEl('marker', {
      id, viewBox: '0 0 10 10', refX: 9, refY: 5, markerWidth: 7, markerHeight: 7, orient: 'auto-start-reverse',
    });
    marker.append(svgEl('path', { d: 'M 0 0 L 10 5 L 0 10 z', fill: colour }));
    defs.append(marker);
  }
  svg.append(defs);

  const scene = svgEl('g', {}, 'scene');
  scene.setAttribute('id', 'scene');
  const frames = svgEl('g', {}, 'frames');
  const edges = svgEl('g', {}, 'edges');
  // The colour mode lives on the group, so the stylesheet paints by status ONLY in status mode —
  // otherwise its rules would beat the per-chart colours below, which are presentation attributes.
  const nodes = svgEl('g', {}, `nodes by-${state.colourBy}`);
  scene.append(frames, edges, nodes);
  svg.append(scene);

  for (const chart of state.graph.charts) {
    const frame = laid.charts[chart.id];
    if (!frame) continue;
    frames.append(drawFrame(chart, frame));
  }

  const visible = (id) => laid.positions[id] && (state.showRuledOut || !isRuledOut(id));
  const labelBoxes = [];
  for (const edge of state.graph.edges) {
    if (!visible(edge.from) || !visible(edge.to)) continue;
    const drawn = drawEdge(edge, laid, labelBoxes);
    if (drawn) edges.append(drawn);
  }
  for (const [id, node] of Object.entries(state.graph.nodes)) {
    if (!visible(id)) continue;
    nodes.append(drawNode(id, node, laid));
  }

  renderPicker();
  applyView();
  renderStatus();
  renderPanel();
}

/** A chart's frame: its title bar is the click target that collapses it (Q52=c). */
function drawFrame(chart, frame) {
  const g = svgEl('g', { transform: `translate(${frame.x},${frame.y})` }, `frame${frame.collapsed ? ' collapsed' : ''}`);
  g.append(svgEl('rect', { x: 0, y: 0, width: frame.w, height: frame.h, rx: 12 }, 'frame-box'));
  const title = svgEl('text', { x: 14, y: 24 }, 'frame-title');
  title.setAttribute('fill', colourOf(chart.id));
  title.textContent = `${chart.id} · ${chart.title}`;
  g.append(title);

  const hint = svgEl('text', { x: frame.w - 14, y: 24, 'text-anchor': 'end' }, 'frame-hint');
  hint.textContent = frame.collapsed ? `${chart.nodes.length} nodes — click to expand` : 'click the title to collapse';
  g.append(hint);

  const hit = svgEl('rect', { x: 0, y: 0, width: frame.w, height: frame.collapsed ? frame.h : 34 }, 'frame-hit');
  hit.addEventListener('click', () => toggleCollapse(chart.id));
  g.append(hit);
  return g;
}

/** One node: a rounded box, or a chamfered slab for a decision. */
function drawNode(id, node, laid) {
  const p = laid.positions[id];
  const size = laid.sizes[id];
  const lines = laid.lines[id];
  const status = statusOf(id);
  const g = svgEl('g', { transform: `translate(${p.x},${p.y})`, 'data-id': id },
    `node ${status}${state.selected === id ? ' selected' : ''}`);

  const shell = node.shape === 'decision'
    ? svgEl('path', { d: chamfer(size.w, size.h) }, 'shell')
    : svgEl('rect', { x: 0, y: 0, width: size.w, height: size.h, rx: 7 }, 'shell');
  if (state.colourBy === 'chart') {
    shell.setAttribute('stroke', colourOf(node.chart));
    shell.setAttribute('fill', `${colourOf(node.chart)}1a`);
  }
  g.append(shell);

  const text = svgEl('text', { x: size.w / 2, y: 0, 'text-anchor': 'middle' }, 'node-label');
  lines.forEach((line, i) => {
    const tspan = svgEl('tspan', { x: size.w / 2, y: 9 + 15 * (i + 1) - 4 });
    tspan.textContent = line;
    text.append(tspan);
  });
  g.append(text);

  const tag = svgEl('text', { x: 6, y: size.h - 5 }, 'node-id');
  tag.textContent = id;
  g.append(tag);

  // Q55/Q18 — which nodes trace back to a question, on the canvas rather than only in the panel.
  // The chip names the questions and says whether they are answered yet, so "what is still open"
  // is readable without clicking every box.
  const decided = node.decidedBy || [];
  if (decided.length) {
    const open = decided.filter((q) => !state.answers[q] && !state.prunedQuestions.has(q)).length;
    const chip = svgEl('text', { x: size.w / 2, y: size.h - 5, 'text-anchor': 'middle' },
      `node-decided${open ? ' open' : ''}`);
    chip.textContent = decided.length === 1 ? decided[0] : `${decided[0]}+${decided.length - 1}`;
    const title = svgEl('title');
    title.textContent = decided.map((qid) => {
      const a = state.answers[qid];
      if (a) return `${qid} — answered ${a.override ? 'in your own words' : `(${a.option})`}`;
      if (state.prunedQuestions.has(qid)) return `${qid} — ruled out by an earlier answer`;
      const q = state.questions.find((x) => x.id === qid);
      return `${qid} — not answered yet, recommended (${q?.default ?? '?'})`;
    }).join('\n');
    chip.append(title);
    g.append(chip);
  }

  if (node.new) {
    const badge = svgEl('text', { x: size.w - 6, y: size.h - 5, 'text-anchor': 'end' }, 'node-new');
    badge.textContent = 'NEW';
    g.append(badge);
  }
  if ((state.annotations.nodes[id] || []).length) {
    const note = svgEl('circle', { cx: size.w - 10, cy: 10, r: 5 }, 'node-note');
    g.append(note);
  }
  g.addEventListener('click', () => select(id));
  return g;
}

/** The decision shape: a slab with its left and right ends cut, legible with a long label. */
function chamfer(w, h) {
  const c = Math.min(16, h / 2);
  return `M ${c} 0 L ${w - c} 0 L ${w} ${h / 2} L ${w - c} ${h} L ${c} ${h} L 0 ${h / 2} Z`;
}

/**
 * Where an edge's label goes, given every label already placed.
 *
 * The midpoint is the honest place for it, and at a fan-out — chart B8's five branches leave one
 * node — every midpoint is nearly the same point, so the chips stack on top of each other and none
 * of them can be read. Nudging along the edge (up the line, towards its own source) keeps a label
 * on the edge it belongs to while separating it from its neighbours. Deterministic: the edges are
 * walked in document order, so the same graph always resolves the same way and a frozen version
 * reproduces (Q53=b).
 */
function placeLabel(box, taken) {
  const overlaps = (candidate) => taken.some((other) => (
    candidate.x < other.x + other.w && candidate.x + candidate.w > other.x
      && candidate.y < other.y + other.h && candidate.y + candidate.h > other.y
  ));
  const step = box.h + 3;
  // Alternate above and below the midpoint, widening — the label stays near where its edge is.
  for (const offset of [0, -step, step, -2 * step, 2 * step, -3 * step, 3 * step, -4 * step, 4 * step]) {
    const candidate = { ...box, y: box.y + offset };
    if (!overlaps(candidate)) {
      taken.push(candidate);
      return candidate;
    }
  }
  taken.push(box);
  return box;
}

/** One edge: straight down the layers, or bowed out to the right when it is a loop back up. */
function drawEdge(edge, laid, labelBoxes = []) {
  const geo = edgeGeometry(edge, laid);
  if (!geo) return null;
  const g = svgEl('g', { 'data-key': edge.key },
    `edge${geo.back ? ' back' : ''}${state.annotations.edges[edge.key]?.length ? ' annotated' : ''}`
    + `${state.annotations.flagged?.[edge.key] ? ' flagged' : ''}`
    + `${state.selected === edge.key ? ' selected' : ''}`);

  const d = geo.back
    ? `M ${geo.x1} ${geo.y1} C ${geo.x1 + 70} ${geo.y1}, ${geo.x2 + 70} ${geo.y2}, ${geo.x2} ${geo.y2}`
    : `M ${geo.x1} ${geo.y1} C ${geo.x1} ${geo.y1 + 22}, ${geo.x2} ${geo.y2 - 22}, ${geo.x2} ${geo.y2}`;
  g.append(svgEl('path', { d, 'marker-end': 'url(#arrow)' }, 'edge-line'));
  g.append(svgEl('path', { d }, 'edge-hit'));

  if (edge.label) {
    const mx = (geo.x1 + geo.x2) / 2 + (geo.back ? 52 : 0);
    const my = (geo.y1 + geo.y2) / 2;
    const width = 7 + edge.label.length * 5.6;
    const box = placeLabel({ x: mx - width / 2, y: my - 9, w: width, h: 17 }, labelBoxes);
    g.append(svgEl('rect', { x: box.x, y: box.y, width: box.w, height: box.h, rx: 4 }, 'edge-label-box'));
    const text = svgEl('text', { x: box.x + box.w / 2, y: box.y + 13, 'text-anchor': 'middle' }, 'edge-label');
    text.textContent = edge.label;
    g.append(text);
    // When a label has been moved off its own midpoint, a hairline ties it back to the edge, so a
    // chip between two lines is never ambiguous about which one it labels.
    if (Math.abs(box.y + 9 - my) > 1) {
      g.append(svgEl('line', { x1: mx, y1: my, x2: box.x + box.w / 2, y2: box.y + box.h / 2 }, 'edge-label-tie'));
    }
  }
  g.addEventListener('click', () => select(edge.key));
  return g;
}

// --- pan, zoom and fitting -----------------------------------------------------------------------

function applyView() {
  const scene = svg.querySelector('#scene');
  if (scene) scene.setAttribute('transform', `translate(${state.view.x},${state.view.y}) scale(${state.view.k})`);
}

/** Fit the drawn graph in the stage, with a margin. `0` on the keyboard, `fit` on the toolbar. */
function fit() {
  const box = state.laid.bounds;
  const rect = stage.getBoundingClientRect();
  const k = Math.min((rect.width - 40) / Math.max(box.w, 1), (rect.height - 40) / Math.max(box.h, 1));
  state.view.k = Math.max(0.02, Math.min(k, 1.6));
  state.view.x = (rect.width - box.w * state.view.k) / 2;
  state.view.y = (rect.height - box.h * state.view.k) / 2;
  applyView();
  renderStatus();
}

/** Zoom about a point in stage coordinates, so the wheel keeps what is under the pointer put. */
function zoomAt(factor, cx, cy) {
  const k = Math.max(0.03, Math.min(4, state.view.k * factor));
  const scale = k / state.view.k;
  state.view.x = cx - (cx - state.view.x) * scale;
  state.view.y = cy - (cy - state.view.y) * scale;
  state.view.k = k;
  applyView();
  renderStatus();
}

/** Put a node in the middle of the stage — what search and the arrow keys do. */
function centreOn(id) {
  const p = state.laid.positions[id];
  if (!p) return;
  const size = state.laid.sizes[id];
  const rect = stage.getBoundingClientRect();
  state.view.x = rect.width / 2 - (p.x + size.w / 2) * state.view.k;
  state.view.y = rect.height / 2 - (p.y + size.h / 2) * state.view.k;
  applyView();
}

let dragging = null;
stage.addEventListener('pointerdown', (e) => {
  if (e.target.closest('.node') || e.target.closest('.frame-hit') || e.target.closest('.edge')) return;
  dragging = { x: e.clientX, y: e.clientY, vx: state.view.x, vy: state.view.y };
  stage.setPointerCapture(e.pointerId);
  stage.classList.add('grabbing');
});
stage.addEventListener('pointermove', (e) => {
  if (!dragging) return;
  state.view.x = dragging.vx + (e.clientX - dragging.x);
  state.view.y = dragging.vy + (e.clientY - dragging.y);
  applyView();
});
stage.addEventListener('pointerup', (e) => {
  dragging = null;
  stage.releasePointerCapture(e.pointerId);
  stage.classList.remove('grabbing');
});
stage.addEventListener('wheel', (e) => {
  e.preventDefault();
  const rect = stage.getBoundingClientRect();
  zoomAt(e.deltaY < 0 ? 1.12 : 1 / 1.12, e.clientX - rect.left, e.clientY - rect.top);
}, { passive: false });

// --- selection, search and the keyboard ----------------------------------------------------------

function select(id) {
  state.selected = id;
  redraw();
  if (state.laid.positions[id]) centreOn(id);
}

/** Arrow keys move the selection to the nearest visible node in that direction (Q113=a). */
function step(dx, dy) {
  const ids = Object.keys(state.laid.positions).filter((id) => state.showRuledOut || !isRuledOut(id));
  if (!ids.length) return;
  if (!state.selected || !state.laid.positions[state.selected]) {
    select(ids[0]);
    return;
  }
  const from = state.laid.positions[state.selected];
  let best = null;
  for (const id of ids) {
    if (id === state.selected) continue;
    const p = state.laid.positions[id];
    const ox = p.x - from.x;
    const oy = p.y - from.y;
    if (dx && Math.sign(ox) !== Math.sign(dx)) continue;
    if (dy && Math.sign(oy) !== Math.sign(dy)) continue;
    // Along the axis of travel, distance counts; across it, it counts four times as much, so
    // "down" means the node below rather than the nearest node that happens to be lower.
    const cost = dx ? Math.abs(ox) + 4 * Math.abs(oy) : Math.abs(oy) + 4 * Math.abs(ox);
    if (!best || cost < best.cost) best = { id, cost };
  }
  if (best) select(best.id);
}

const search = document.getElementById('search');
search.addEventListener('keydown', (e) => {
  if (e.key !== 'Enter') return;
  const text = search.value.trim().toLowerCase();
  if (!text) return;
  const ids = Object.keys(state.graph.nodes);
  const hit = ids.find((id) => id.toLowerCase() === text)
    || ids.find((id) => id.toLowerCase().startsWith(text))
    || ids.find((id) => state.graph.nodes[id].label.toLowerCase().includes(text));
  if (!hit) {
    statusLine.textContent = `nothing matches "${search.value.trim()}"`;
    return;
  }
  // A hit inside a collapsed or hidden chart is useless unless the chart opens (F9).
  const chart = state.graph.nodes[hit].chart;
  if (state.only && state.only !== chart) state.only = chart;
  state.collapsed.delete(chart);
  if (isRuledOut(hit)) state.showRuledOut = true;
  redraw();
  select(hit);
});

document.addEventListener('keydown', (e) => {
  // Ctrl/Alt/Meta combinations belong to the browser and to the operating system — a canvas that
  // swallows Ctrl+− or Ctrl+F is a canvas that has broken the window it lives in.
  if (e.ctrlKey || e.metaKey || e.altKey) return;
  const typing = ['INPUT', 'TEXTAREA'].includes(document.activeElement?.tagName);
  if (e.key === '/' && !typing) {
    e.preventDefault();
    search.focus();
    return;
  }
  if (typing) return;
  const rect = stage.getBoundingClientRect();
  switch (e.key) {
    case 'ArrowDown': e.preventDefault(); step(0, 1); break;
    case 'ArrowUp': e.preventDefault(); step(0, -1); break;
    case 'ArrowLeft': e.preventDefault(); step(-1, 0); break;
    case 'ArrowRight': e.preventDefault(); step(1, 0); break;
    case '+': case '=': zoomAt(1.15, rect.width / 2, rect.height / 2); break;
    case '-': zoomAt(1 / 1.15, rect.width / 2, rect.height / 2); break;
    case '0': fit(); break;
    case 's': toggleColour(); break;
    case 'r': toggleRuledOut(); break;
    case 'f': toggleAllChrome(); break;
    case '1': toggleChrome('picker'); break;
    case '2': toggleChrome('panel'); break;
    case '3': toggleChrome('bar'); break;
    case 'c':
      if (state.selected && state.graph.nodes[state.selected]) toggleCollapse(state.graph.nodes[state.selected].chart);
      break;
    case 'Escape':
      state.selected = null;
      redraw();
      break;
    default: break;
  }
});

// --- the toolbar ---------------------------------------------------------------------------------

function toggleColour() {
  state.colourBy = state.colourBy === 'chart' ? 'status' : 'chart';
  document.getElementById('colour-mode').textContent = `colour: by ${state.colourBy}`;
  redraw();
}

function toggleRuledOut() {
  state.showRuledOut = !state.showRuledOut;
  document.getElementById('ruled-out').textContent = `ruled out: ${state.showRuledOut ? 'shown' : 'hidden'}`;
  redraw();
}

document.getElementById('colour-mode').addEventListener('click', toggleColour);
document.getElementById('ruled-out').addEventListener('click', toggleRuledOut);
document.getElementById('collapse-all').addEventListener('click', () => {
  for (const c of state.graph.charts) state.collapsed.add(c.id);
  redraw();
  fit();
});
document.getElementById('expand-all').addEventListener('click', () => {
  state.collapsed.clear();
  redraw();
  fit();
});
document.getElementById('zoom-in').addEventListener('click', () => {
  const r = stage.getBoundingClientRect();
  zoomAt(1.15, r.width / 2, r.height / 2);
});
document.getElementById('zoom-out').addEventListener('click', () => {
  const r = stage.getBoundingClientRect();
  zoomAt(1 / 1.15, r.width / 2, r.height / 2);
});
document.getElementById('zoom-fit').addEventListener('click', fit);

// --- chrome: the graph can have the whole window -------------------------------------------------

/**
 * Two fixed sidebars and a toolbar cost roughly a third of the window, and at 17 % zoom on a
 * 14-chart graph that third is the difference between reading a node and not. Each folds
 * independently and `f` folds them all; the toggle handles stay on the stage so nothing is ever
 * hidden with no way back.
 */
const CHROME = {
  picker: { cls: 'no-picker', button: 'toggle-picker', shown: '‹', hidden: '›' },
  panel: { cls: 'no-panel', button: 'toggle-panel', shown: '›', hidden: '‹' },
  bar: { cls: 'no-bar', button: 'toggle-bar', shown: '⌃', hidden: '⌄' },
};

function toggleChrome(which, force = null) {
  const spec = CHROME[which];
  const hide = force === null ? !document.body.classList.contains(spec.cls) : force;
  document.body.classList.toggle(spec.cls, hide);
  document.getElementById(spec.button).textContent = hide ? spec.hidden : spec.shown;
  document.getElementById('full-screen').textContent = Object.values(CHROME)
    .every((s) => document.body.classList.contains(s.cls)) ? '⤡ show the panels' : '⤢ full width';
  // The stage changed size, so a fitted view is no longer fitted.
  fit();
}

function toggleAllChrome() {
  const anyShown = Object.values(CHROME).some((s) => !document.body.classList.contains(s.cls));
  for (const which of Object.keys(CHROME)) toggleChrome(which, anyShown);
}

for (const [which, spec] of Object.entries(CHROME)) {
  document.getElementById(spec.button).addEventListener('click', () => toggleChrome(which));
}
document.getElementById('full-screen').addEventListener('click', toggleAllChrome);

/** The line under the canvas: what is on screen, and every key that does something. */
function renderStatus() {
  const shown = Object.keys(state.laid.positions).filter((id) => state.showRuledOut || !isRuledOut(id)).length;
  const ruled = Object.keys(state.graph.nodes).filter(isRuledOut).length;
  statusLine.innerHTML = `<span>${shown} nodes${state.only ? ` · chart ${esc(state.only)} only` : ''}`
    + `${state.collapsed.size ? ` · ${state.collapsed.size} collapsed` : ''}`
    + `${ruled ? ` · ${ruled} ruled out${state.showRuledOut ? '' : ' (hidden)'}` : ''}`
    + ` · ${Math.round(state.view.k * 100)}%</span>`
    + '<span class="keys">arrows move · enter opens · / find · +/− zoom · 0 fit · c collapse · '
    + 's colour · r ruled out · f full width</span>';
}

// --- the side panel (PLAN S13; DESIGN F3, F5, F6, Q55–Q58, Q116) ----------------------------------

/** A `<details>` section with a count, so the three panel sections stay scannable when long. */
function section(title, count, open = false) {
  const el = document.createElement('details');
  el.className = 'panel-section';
  el.open = open;
  const summary = document.createElement('summary');
  summary.innerHTML = `${esc(title)} <span class="panel-count">${count}</span>`;
  el.append(summary);
  return el;
}

/**
 * Promote an assumption to a gap (Q95b=a). The gap is filed open with no options — the owner is
 * saying they want the decision, not making it — and every plan step that cited the assumption's
 * step or its question is stale from now on, which the gap page reports.
 */
async function promoteAssumption(item, button) {
  button.disabled = true;
  button.textContent = 'filing…';
  try {
    const filed = await api('/promote', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        assumption: item.text,
        step: item.step || '',
        // A defaulted or not-relevant answer names its question; a plan step citing that question
        // is what becomes stale. An agent assumption names its step instead.
        nodes: item.id ? [item.id] : [],
        why: item.why ? `**The assumption's own note** — ${item.why}` : '',
      }),
    });
    button.textContent = `filed as ${filed.id}`;
    button.title = 'Open gaps.html to answer it, once the agent has written its options.';
  } catch (err) {
    button.disabled = false;
    button.textContent = `could not file it: ${err.message}`;
  }
}

/** Every note the owner has written and not resolved: on nodes, on edges, and on answers. */
function openNotes() {
  const notes = [];
  for (const [id, list] of Object.entries(state.annotations.nodes || {})) {
    for (const note of list) notes.push({ target: id, kind: 'node', ...note });
  }
  for (const [key, list] of Object.entries(state.annotations.edges || {})) {
    for (const note of list) notes.push({ target: key, kind: 'edge', ...note });
  }
  for (const h of state.history) {
    if (h.note) notes.push({ target: h.id, kind: h.override ? 'own answer' : 'answer note', text: h.note, at: '' });
  }
  return notes;
}

function renderPanel() {
  panel.replaceChildren();

  if (state.frozen) {
    const banner = document.createElement('div');
    banner.className = 'banner';
    banner.innerHTML = `<strong>Version ${state.frozen.n}, frozen.</strong> This is exactly what was on `
      + 'screen when it was confirmed — its layout and its collapse state came out of the version, not '
      + 'from re-running the engine. Nothing here can be edited.';
    const back = document.createElement('button');
    back.textContent = 'Back to the working copy';
    back.addEventListener('click', () => {
      state.frozen = null;
      history.replaceState(null, '', `canvas.html?key=${encodeURIComponent(key)}`);
      load();
    });
    panel.append(banner, back);
  }

  if (state.selected) panel.append(renderDetail(state.selected));

  const assumptions = section('Assumptions', state.assumptions.length);
  const list = document.createElement('ul');
  list.className = 'panel-list';
  for (const item of state.assumptions) {
    const li = document.createElement('li');
    // The assumptions come out of ASSUMPTIONS.md and out of question text — both are markdown, and
    // reading `**no backticked gate**` with its asterisks is reading the source, not the sentence.
    li.innerHTML = `<span class="tag ${esc(item.source)}">${esc(item.source.replace('_', ' '))}</span> `
      + `${item.id ? `<strong>${esc(item.id)}</strong> ` : ''}${md(item.text)}`
      + `${item.why ? ` <span class="faint">— ${md(item.why)}</span>` : ''}`;
    // Q95b=a — an assumption can be promoted to a gap after the fact, and every step that relied
    // on it is stale from that moment. This is the button that says "actually I do want a say in
    // that"; it files the gap and leaves the options to the agent (the tool never authors a
    // question, Q94=a).
    if (!state.frozen) {
      const promote = document.createElement('button');
      promote.className = 'link';
      promote.textContent = 'I want a say in this';
      promote.title = 'File this as an open gap. Plan steps that relied on it become stale.';
      promote.addEventListener('click', () => promoteAssumption(item, promote));
      li.append(' ', promote);
    }
    list.append(li);
  }
  if (!state.assumptions.length) list.innerHTML = '<li class="faint">none yet</li>';
  assumptions.append(list);
  panel.append(assumptions);

  const scope = section('Out of scope', state.outOfScope.length);
  const scopeList = document.createElement('ul');
  scopeList.className = 'panel-list';
  for (const item of state.outOfScope) {
    const li = document.createElement('li');
    li.innerHTML = `<strong>${esc(item.id)}</strong> ${md(item.text)} <span class="faint">— ${md(item.answer)}</span>`;
    scopeList.append(li);
  }
  if (!state.outOfScope.length) scopeList.innerHTML = '<li class="faint">nothing confirmed out of scope</li>';
  scope.append(scopeList);
  panel.append(scope);

  const notes = openNotes();
  const notesSection = section('Open notes', notes.length);
  const notesList = document.createElement('ul');
  notesList.className = 'panel-list';
  for (const note of notes) {
    const li = document.createElement('li');
    const jump = document.createElement('button');
    jump.className = 'link';
    jump.textContent = note.target;
    jump.addEventListener('click', () => select(note.target));
    li.append(jump);
    li.insertAdjacentHTML('beforeend', ` ${esc(note.kind)}: ${md(note.text)}`);
    notesList.append(li);
  }
  if (!notes.length) notesList.innerHTML = '<li class="faint">nothing annotated yet</li>';
  notesSection.append(notesList);
  panel.append(notesSection);

  panel.append(renderVersions());
}

/** F5 / F6 — a node or an edge, what decided it, and the box you annotate it in. */
function renderDetail(id) {
  const box = document.createElement('div');
  box.className = 'detail';
  const isEdge = !state.graph.nodes[id];
  const edge = isEdge ? state.graph.edges.find((e) => e.key === id) : null;
  if (isEdge && !edge) return box;

  const node = isEdge ? null : state.graph.nodes[id];
  box.innerHTML = `<div class="detail-head"><span class="detail-id">${esc(id)}</span>`
    + `<span class="faint">${isEdge ? 'edge' : `${node.shape} in chart ${esc(node.chart)}`}</span></div>`
    + `<div class="detail-label">${md(isEdge
      ? `${edge.from} → ${edge.to}${edge.label ? ` · “${edge.label}”` : ''}` : node.label)}</div>`;

  // Q55=a — which question decided this node, WITH the answer that was given.
  const decided = isEdge ? [] : (node.decidedBy || []);
  if (decided.length) {
    const why = document.createElement('div');
    why.className = 'detail-why';
    why.innerHTML = '<div class="faint">decided by</div>';
    for (const qid of decided) {
      const q = state.questions.find((x) => x.id === qid);
      const a = state.answers[qid];
      const option = q?.options.find((o) => o.letter === a?.option);
      // An unanswered question still HAS an answer waiting: its recommended default is what the
      // design proceeds on if the owner never gets to it (Q17b/Q12), so a node whose question is
      // unanswered is not undecided — it is provisionally decided, and the panel says which way.
      const fallback = q?.options.find((o) => o.letter === q.default);
      const row = document.createElement('div');
      row.className = 'detail-q';
      row.innerHTML = `<strong>${esc(qid)}</strong> ${md(q ? q.text : '(not in this document)')}<br>`
        + (a
          ? `<span class="answered">answered ${a.override ? 'in your own words' : `(${esc(a.option)}) ${md(option?.label || '')}`}</span>`
            + `${a.active === false ? ' <span class="faint">— set aside</span>' : ''}`
          : `<span class="faint">${state.prunedQuestions.has(qid) ? 'ruled out by an earlier answer' : 'not answered yet'}</span>`
            + (fallback && !state.prunedQuestions.has(qid)
              ? ` <span class="recommends">— recommended (${esc(fallback.letter)}) ${md(fallback.label)}</span>` : ''));
      // Q18's other direction, in the owner's words: clicking a node reaches the question that
      // created it. The canvas can only link; the question screen is where it is answered.
      if (q) {
        const jump = document.createElement('a');
        jump.className = 'link';
        jump.href = `question.html?key=${encodeURIComponent(key)}#${encodeURIComponent(qid)}`;
        jump.textContent = a ? 'change this answer' : 'answer it';
        row.append(document.createTextNode(' '), jump);
      }
      why.append(row);
    }
    box.append(why);
  } else if (!isEdge) {
    // Saying nothing here is what made it impossible to tell a node nobody asked about from a node
    // whose question the panel simply failed to find. `decidedBy` is best-effort (§4.6), so the
    // honest words are "no question names it", not "it was not decided".
    const none = document.createElement('div');
    none.className = 'detail-why';
    none.innerHTML = '<div class="faint">decided by</div>'
      + '<div class="detail-q faint">no question names this node — it is structure the agent filled '
      + 'in. If it should have been your call, flag it and say so.</div>';
    box.append(none);
  }

  for (const note of (isEdge ? state.annotations.edges[id] : state.annotations.nodes[id]) || []) {
    const item = document.createElement('div');
    item.className = 'detail-note';
    item.textContent = note.text;
    box.append(item);
  }

  const area = document.createElement('textarea');
  area.placeholder = isEdge
    ? 'What is wrong with this edge? "this should be rewired to D7" is exactly the note to write.'
    : 'A note on this node — split it, rename it, or say what it is missing.';
  const row = document.createElement('div');
  row.className = 'row';
  const save = document.createElement('button');
  save.textContent = 'Save note';
  save.addEventListener('click', async () => {
    if (!area.value.trim()) return;
    const written = await api('/annotate', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ target: isEdge ? 'edge' : 'node', key: id, text: area.value.trim() }),
    });
    state.annotations = { flagged: {}, ...written.annotations };
    area.value = '';
    redraw();
  });

  // Q59, in the owner's words: flag what you do not like. Everything unflagged is "not objected
  // to", which is deliberately weaker than approved — it may simply not have been read yet.
  const flagged = !!state.annotations.flagged?.[id];
  const flag = document.createElement('button');
  flag.className = flagged ? 'flagged' : '';
  flag.textContent = flagged ? '⚑ flagged — clear it' : '⚑ Flag this for another look';
  flag.addEventListener('click', async () => {
    const written = await api('/approve', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ target: isEdge ? 'edge' : 'node', key: id, state: flagged ? null : 'flagged' }),
    });
    state.annotations = { flagged: {}, ...written.annotations };
    redraw();
  });
  row.append(save, flag);
  box.append(area, row);
  return box;
}

// --- versions, Confirm and export (PLAN S14; DESIGN F10, F11, G1–G3, Q61, Q62, Q65, Q115) ---------

function renderVersions() {
  const wrap = section('Versions', state.versions.length, state.versions.length > 0);
  const list = document.createElement('ul');
  list.className = 'panel-list';
  for (const v of state.versions) {
    const li = document.createElement('li');
    const open = document.createElement('button');
    open.className = 'link';
    open.textContent = `version ${v.n}`;
    open.addEventListener('click', () => openVersion(v.n));
    li.append(open);
    li.append(` · ${v.nodes} nodes · ${v.answers} answers`
      + `${v.collapsed.length ? ` · ${v.collapsed.length} collapsed` : ''}`
      + `${v.at ? ` · ${new Date(v.at).toLocaleString()}` : ''}`);
    list.append(li);
  }
  if (!state.versions.length) list.innerHTML = '<li class="faint">nothing confirmed yet</li>';
  wrap.append(list);

  if (state.versions.length > 1) {
    const row = document.createElement('div');
    row.className = 'row';
    const a = document.createElement('select');
    const b = document.createElement('select');
    for (const select of [a, b]) {
      for (const v of state.versions) {
        const option = document.createElement('option');
        option.value = v.n;
        option.textContent = `v${v.n}`;
        select.append(option);
      }
    }
    a.value = state.versions[state.versions.length - 2].n;
    b.value = state.versions[state.versions.length - 1].n;
    const go = document.createElement('button');
    go.textContent = 'Diff';
    const out = document.createElement('div');
    out.className = 'diff-out';
    go.addEventListener('click', async () => {
      const diff = await api(`/diff?a=${a.value}&b=${b.value}`);
      out.innerHTML = `<div><strong>${diff.added.length}</strong> added · `
        + `<strong>${diff.changed.length}</strong> changed · <strong>${diff.removed.length}</strong> removed</div>`
        + [...diff.added.map((n) => `+ ${n.id} ${n.label}`),
          ...diff.changed.map((n) => `~ ${n.id} (${n.fields.join(', ')})`),
          ...diff.removed.map((n) => `− ${n.id} ${n.label}`)]
          .map((line) => `<div class="diff-line">${esc(line)}</div>`).join('');
    });
    row.append(a, b, go);
    wrap.append(row, out);
  }

  const actions = document.createElement('div');
  actions.className = 'row panel-actions';
  const confirm = document.createElement('button');
  confirm.className = 'primary';
  confirm.textContent = 'Confirm this design';
  confirm.title = 'Freeze a version — the working copy stays editable (Q61=a)';
  confirm.addEventListener('click', doConfirm);
  const again = document.createElement('button');
  again.textContent = 'Review again';
  again.title = 'Hand it back with your annotations on it (F10)';
  again.addEventListener('click', async () => {
    await api('/review', { method: 'POST' });
    statusLine.textContent = 'handed back — your annotations are on it, and the agent has the turn';
  });
  const svgOut = document.createElement('button');
  svgOut.textContent = 'Export SVG';
  svgOut.addEventListener('click', () => exportImage('svg'));
  const pngOut = document.createElement('button');
  pngOut.textContent = 'Export PNG';
  pngOut.addEventListener('click', () => exportImage('png'));
  actions.append(confirm, again, svgOut, pngOut);
  // A frozen version is read-only (Q61=a) — but a picture of one is exactly what Q65 is for.
  if (state.frozen) for (const b of [confirm, again]) b.disabled = true;
  wrap.append(actions);
  return wrap;
}

/** Q115=b — freeze the positions, the collapse state AND the viewport, so a version reopens as left. */
async function doConfirm() {
  const layoutJson = {
    engine: state.laid.engine,
    positions: state.laid.positions,
    collapsed: [...state.collapsed].sort(),
    viewport: { x: Math.round(state.view.x), y: Math.round(state.view.y), zoom: Number(state.view.k.toFixed(4)) },
  };
  const result = await api('/confirm', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ layout: layoutJson }),
  });
  state.versions = result.versions;
  statusLine.textContent = `version ${result.version} frozen — versions/${String(result.version).padStart(3, '0')}/`;
  renderPanel();
}

/** Reopen a frozen version exactly as it was left (Q115=b, H6 read-only). */
async function openVersion(n) {
  const version = await api(`/versions/${n}`);
  state.frozen = { n, ...version };
  state.graph = version.graph;
  state.annotations = { nodes: {}, edges: {}, approved: {}, flagged: {}, ...version.annotations };
  state.collapsed = new Set(version.layout?.collapsed || []);
  state.only = null;
  // Recompute the frames and the label wrapping, then let the FROZEN positions win — that is what
  // `engine` in layout.json is for: a later engine may lay it out differently, and the version does
  // not care, because its own positions are on disk.
  const fresh = layout(version.graph, { collapsed: [...state.collapsed] });
  state.frozen.layout = { ...fresh, ...version.layout, positions: { ...fresh.positions, ...version.layout.positions } };
  redraw();
  if (version.layout?.viewport) {
    state.view = { x: version.layout.viewport.x, y: version.layout.viewport.y, k: version.layout.viewport.zoom };
    applyView();
    renderStatus();
  } else {
    fit();
  }
}

/**
 * Q65=a — SVG and PNG, for pasting elsewhere. The stylesheet is embedded rather than duplicated in
 * this file, so an exported chart looks like the canvas it came from and cannot drift from it.
 */
async function exportImage(kind) {
  const css = await fetch('app.css').then((r) => r.text());
  const box = state.laid.bounds;
  const clone = svg.cloneNode(true);
  clone.setAttribute('xmlns', SVGNS);
  clone.setAttribute('width', box.w + 40);
  clone.setAttribute('height', box.h + 40);
  clone.setAttribute('viewBox', `-20 -20 ${box.w + 40} ${box.h + 40}`);
  clone.querySelector('#scene')?.setAttribute('transform', 'translate(0,0) scale(1)');
  const style = document.createElementNS(SVGNS, 'style');
  style.textContent = `${css}\n svg { background: var(--bg); }`;
  clone.insertBefore(style, clone.firstChild);
  const source = new XMLSerializer().serializeToString(clone);
  const name = `${state.design.slug}-${state.only || 'all'}`;

  if (kind === 'svg') {
    download(`${name}.svg`, URL.createObjectURL(new Blob([source], { type: 'image/svg+xml' })));
    return;
  }
  const image = new Image();
  image.src = `data:image/svg+xml;base64,${btoa(unescape(encodeURIComponent(source)))}`;
  await image.decode();
  const target = document.createElement('canvas');
  target.width = (box.w + 40) * 2;
  target.height = (box.h + 40) * 2;
  const ctx = target.getContext('2d');
  ctx.scale(2, 2);
  ctx.drawImage(image, 0, 0);
  download(`${name}.png`, target.toDataURL('image/png'));
}

function download(name, href) {
  const a = document.createElement('a');
  a.href = href;
  a.download = name;
  a.click();
}

load().catch((err) => {
  statusLine.textContent = '';
  panel.innerHTML = `<div class="banner bad">Could not open the graph: ${esc(err.message)}</div>`;
});

// The layout engine (PLAN S12, §4.7; DESIGN F2, Q52, Q53, Q115).
//
// Hand-rolled layered layout — the plan's instruction was to try one first and measure it, because
// adding an npm dependency to a zero-dependency project is a gap to file, not a choice to make.
// The measurement is in `HANDOFF_designloop.md`; at Spotlight's 176 nodes it is a few milliseconds.
//
// It must be DETERMINISTIC for a given input (Q53=b): a version frozen at Confirm records these
// positions and its `engine` name, and reopening it has to reproduce the same picture. So: no
// randomness, no Date, no Math.random, no dependence on measured text — labels are wrapped by
// character count, which is why `wrapLabel` lives here rather than in the renderer.
//
// The pipeline is the classic layered one, cut down to what these charts need:
//
//   1. break cycles      DFS; an edge to a node on the stack is a back edge and does not rank
//   2. rank              longest path from the sources, so every edge points down a layer
//   3. order             initial DFS order, then barycentre sweeps to untangle crossings
//   4. place             median placement with left-to-right packing, then centre each chart
//   5. pack charts       shelf-pack the per-chart blocks into a page
//
// Pure: no I/O, no DOM, no Node built-ins. The browser imports this exact file.

/** The engine's name, recorded in `layout.json` so a later change cannot re-flow a frozen version. */
export const ENGINE = 'layered-v1';

export const METRICS = {
  nodeWidth: 232,
  charWidth: 6.35,     // 12px "Segoe UI" average — an estimate on purpose: it must not vary by host
  lineHeight: 15,
  padX: 10,
  padY: 9,
  maxLines: 10,
  layerGap: 46,        // vertical space between layers
  nodeGap: 22,         // horizontal space between nodes in a layer
  chartGapX: 90,
  chartGapY: 110,
  chartPad: 34,        // room inside a chart's frame for its title
  collapsedWidth: 268,
  collapsedHeight: 74,
  pageWidth: 5200,     // the shelf width charts are packed into
};

/**
 * Wrap a label to the node width, by character count.
 * Long words (a Godot method name, say) are broken rather than allowed to overflow, and the label
 * is capped at `maxLines` because one 20-line node makes its whole layer unreadable.
 */
export function wrapLabel(text, maxChars = Math.floor((METRICS.nodeWidth - 2 * METRICS.padX) / METRICS.charWidth)) {
  const words = String(text ?? '').trim().split(/\s+/).filter(Boolean);
  const lines = [];
  let current = '';
  const push = () => {
    if (current) lines.push(current);
    current = '';
  };
  for (let word of words) {
    while (word.length > maxChars) {
      push();
      lines.push(word.slice(0, maxChars - 1) + '-');
      word = word.slice(maxChars - 1);
    }
    if (!current) current = word;
    else if (current.length + 1 + word.length <= maxChars) current += ` ${word}`;
    else {
      push();
      current = word;
    }
  }
  push();
  if (!lines.length) lines.push('');
  if (lines.length > METRICS.maxLines) {
    return [...lines.slice(0, METRICS.maxLines - 1), `${lines[METRICS.maxLines - 1].slice(0, maxChars - 1)}…`];
  }
  return lines;
}

/** The median of a sorted-able list, taking the lower of two middles so the result is stable. */
function median(values) {
  if (!values.length) return null;
  const sorted = [...values].sort((a, b) => a - b);
  return sorted.length % 2 ? sorted[(sorted.length - 1) / 2]
    : (sorted[sorted.length / 2 - 1] + sorted[sorted.length / 2]) / 2;
}

/**
 * Depth-first sweep marking back edges. A chart is a DAG plus its loops (`C10 --> C8` is the row
 * loop, `I10 --> I5` is the allocator's), and a loop has no layering — so the back edges are found
 * once, here, and every later stage works on what is left.
 */
function breakCycles(ids, edges) {
  const out = new Map(ids.map((id) => [id, []]));
  for (const e of edges) if (out.has(e.from)) out.get(e.from).push(e);

  const state = new Map(ids.map((id) => [id, 'new']));
  const back = new Set();
  const visit = (id) => {
    state.set(id, 'open');
    for (const e of out.get(id) || []) {
      const s = state.get(e.to);
      if (s === 'open') back.add(e);
      else if (s === 'new') visit(e.to);
    }
    state.set(id, 'done');
  };
  // Sources first, then anything a source never reached — declaration order throughout, so the
  // same chart always produces the same set of back edges.
  const indegree = new Map(ids.map((id) => [id, 0]));
  for (const e of edges) if (indegree.has(e.to) && e.from !== e.to) indegree.set(e.to, indegree.get(e.to) + 1);
  for (const id of ids) if (indegree.get(id) === 0 && state.get(id) === 'new') visit(id);
  for (const id of ids) if (state.get(id) === 'new') visit(id);
  return back;
}

/** Longest-path ranking over the forward edges: every edge drops at least one layer. */
function rankNodes(ids, forward) {
  const incoming = new Map(ids.map((id) => [id, []]));
  const outgoing = new Map(ids.map((id) => [id, []]));
  for (const e of forward) {
    outgoing.get(e.from).push(e.to);
    incoming.get(e.to).push(e.from);
  }
  const rank = new Map(ids.map((id) => [id, 0]));
  // Kahn order, so a node is ranked only once every predecessor is.
  const pending = new Map(ids.map((id) => [id, incoming.get(id).length]));
  const queue = ids.filter((id) => pending.get(id) === 0);
  for (let i = 0; i < queue.length; i++) {
    const id = queue[i];
    for (const next of outgoing.get(id)) {
      rank.set(next, Math.max(rank.get(next), rank.get(id) + 1));
      pending.set(next, pending.get(next) - 1);
      if (pending.get(next) === 0) queue.push(next);
    }
  }
  return rank;
}

/**
 * Order the nodes inside each layer to reduce edge crossings: repeated barycentre sweeps, down then
 * up, keeping the previous order as the tie-break. Four passes is where the charts here stop
 * improving; more is free but changes nothing, and it must terminate identically every time.
 */
function orderLayers(layers, forward) {
  const up = new Map();
  const down = new Map();
  for (const e of forward) {
    if (!down.has(e.from)) down.set(e.from, []);
    if (!up.has(e.to)) up.set(e.to, []);
    down.get(e.from).push(e.to);
    up.get(e.to).push(e.from);
  }

  const indexOf = new Map();
  const reindex = () => layers.forEach((layer) => layer.forEach((id, i) => indexOf.set(id, i)));
  reindex();

  for (let pass = 0; pass < 4; pass++) {
    const order = pass % 2 === 0
      ? layers.map((_, i) => i).slice(1)                       // downward: fix on the layer above
      : layers.map((_, i) => layers.length - 1 - i).slice(1);  // upward
    for (const li of order) {
      const neighbours = pass % 2 === 0 ? up : down;
      const scored = layers[li].map((id, i) => {
        const bar = median((neighbours.get(id) || []).map((n) => indexOf.get(n)).filter((v) => v !== undefined));
        return { id, key: bar === null ? i : bar, i };
      });
      scored.sort((a, b) => (a.key - b.key) || (a.i - b.i));
      layers[li] = scored.map((s) => s.id);
      reindex();
    }
  }
  return layers;
}

/**
 * Give every node an x: aim it at the median of its neighbours, then pack the layer left to right
 * without overlapping and without reordering. Two passes each way is enough to straighten the long
 * spines these charts are mostly made of.
 */
function placeX(layers, forward, sizes) {
  const up = new Map();
  const down = new Map();
  for (const e of forward) {
    if (!down.has(e.from)) down.set(e.from, []);
    if (!up.has(e.to)) up.set(e.to, []);
    down.get(e.from).push(e.to);
    up.get(e.to).push(e.from);
  }

  const x = new Map();
  for (const layer of layers) {
    let cursor = 0;
    for (const id of layer) {
      x.set(id, cursor);
      cursor += sizes.get(id).w + METRICS.nodeGap;
    }
  }

  const centre = (id) => x.get(id) + sizes.get(id).w / 2;
  const pack = (layer, wanted) => {
    // Left to right: never move a node before its predecessor's right edge.
    let limit = -Infinity;
    for (const id of layer) {
      const w = sizes.get(id).w;
      const target = Math.max(wanted.get(id) - w / 2, limit);
      x.set(id, target);
      limit = target + w + METRICS.nodeGap;
    }
    // Right to left: pull the tail back towards where it wanted to be, without re-crossing.
    limit = Infinity;
    for (let i = layer.length - 1; i >= 0; i--) {
      const id = layer[i];
      const w = sizes.get(id).w;
      const target = Math.min(Math.max(wanted.get(id) - w / 2, x.get(id)), limit - w - METRICS.nodeGap);
      if (target > x.get(id)) x.set(id, target);
      limit = x.get(id);
    }
  };

  for (let pass = 0; pass < 4; pass++) {
    const neighbours = pass % 2 === 0 ? up : down;
    const order = pass % 2 === 0 ? layers.slice(1) : layers.slice(0, -1).reverse();
    for (const layer of order) {
      const wanted = new Map();
      for (const id of layer) {
        const bar = median((neighbours.get(id) || []).map(centre));
        wanted.set(id, bar === null ? centre(id) : bar);
      }
      pack(layer, wanted);
    }
  }
  return x;
}

/** Lay out one chart on its own, with (0,0) at the top-left of its content. */
function layoutChart(chart, graph) {
  const ids = chart.nodes;
  const edges = graph.edges.filter((e) => e.chart === chart.id && e.from !== e.to);

  const sizes = new Map();
  const lines = new Map();
  for (const id of ids) {
    const wrapped = wrapLabel(graph.nodes[id].label);
    lines.set(id, wrapped);
    sizes.set(id, {
      w: METRICS.nodeWidth,
      h: Math.max(38, wrapped.length * METRICS.lineHeight + 2 * METRICS.padY),
    });
  }

  const back = breakCycles(ids, edges);
  const forward = edges.filter((e) => !back.has(e));
  const rank = rankNodes(ids, forward);

  const depth = Math.max(0, ...ids.map((id) => rank.get(id)));
  const layers = Array.from({ length: depth + 1 }, () => []);
  for (const id of ids) layers[rank.get(id)].push(id);   // declaration order inside a layer

  orderLayers(layers, forward);
  const x = placeX(layers, forward, sizes);

  const positions = new Map();
  let y = 0;
  for (const layer of layers) {
    const tallest = Math.max(...layer.map((id) => sizes.get(id).h));
    for (const id of layer) positions.set(id, { x: x.get(id), y: y + (tallest - sizes.get(id).h) / 2 });
    y += tallest + METRICS.layerGap;
  }

  // Normalise to (0,0) — every chart is placed as a block afterwards.
  const minX = Math.min(...ids.map((id) => positions.get(id).x));
  for (const id of ids) positions.get(id).x -= minX;

  const width = Math.max(...ids.map((id) => positions.get(id).x + sizes.get(id).w));
  const height = Math.max(...ids.map((id) => positions.get(id).y + sizes.get(id).h));
  return { positions, sizes, lines, width, height, back };
}

/**
 * Lay out the whole graph (PLAN §7).
 *
 * `collapsed` is the set of chart IDs folded to a single box (Q52=c) — it changes the layout, which
 * is exactly why Q115=b freezes it beside the positions.
 *
 * Returns the `layout.json` shape of §4.7 plus what the renderer needs: per-node sizes, the wrapped
 * label lines, each chart's frame, and which edges were treated as back edges.
 */
export function layout(graph, { collapsed = [], only = null } = {}) {
  const folded = new Set(collapsed);
  const charts = only ? graph.charts.filter((c) => c.id === only) : graph.charts;

  const blocks = charts.map((chart) => {
    if (folded.has(chart.id)) {
      return {
        chart, collapsed: true,
        width: METRICS.collapsedWidth, height: METRICS.collapsedHeight,
        positions: new Map(), sizes: new Map(), lines: new Map(), back: new Set(),
      };
    }
    return { chart, collapsed: false, ...layoutChart(chart, graph) };
  });

  // Shelf-pack the blocks in chart order: fill a row until it would exceed the page width, then
  // start the next. Deterministic, and it keeps charts in document order, which is how the owner
  // read them.
  const positions = {};
  const sizes = {};
  const lines = {};
  const frames = {};
  const back = new Set();
  let shelfX = 0;
  let shelfY = 0;
  let shelfH = 0;
  let pageW = 0;

  for (const block of blocks) {
    const w = block.width + 2 * METRICS.chartPad;
    const h = block.height + METRICS.chartPad + 2 * METRICS.chartPad;
    if (shelfX > 0 && shelfX + w > METRICS.pageWidth) {
      shelfX = 0;
      shelfY += shelfH + METRICS.chartGapY;
      shelfH = 0;
    }
    const originX = shelfX + METRICS.chartPad;
    const originY = shelfY + 2 * METRICS.chartPad;
    frames[block.chart.id] = {
      x: shelfX, y: shelfY, w, h, collapsed: block.collapsed, title: block.chart.title,
    };
    for (const [id, p] of block.positions) {
      positions[id] = { x: Math.round(originX + p.x), y: Math.round(originY + p.y) };
      sizes[id] = block.sizes.get(id);
      lines[id] = block.lines.get(id);
    }
    for (const e of block.back) back.add(e.key);
    shelfX += w + METRICS.chartGapX;
    shelfH = Math.max(shelfH, h);
    pageW = Math.max(pageW, shelfX - METRICS.chartGapX);
  }

  return {
    engine: ENGINE,
    positions,
    sizes,
    lines,
    charts: frames,
    backEdges: [...back],
    bounds: { w: Math.round(pageW), h: Math.round(shelfY + shelfH) },
    collapsed: [...folded].sort(),
  };
}

/**
 * Where one edge starts and ends, in absolute coordinates. Null when either end is hidden.
 *
 * A forward edge leaves the bottom of its source and arrives at the top of its target. A back edge
 * — a loop the ranking had to cut — leaves and arrives on the RIGHT side, so the renderer can bow
 * it out to the side instead of drawing it straight back up through the nodes it skips.
 */
/** Where a straight line from a rectangle's centre towards (tx,ty) crosses its border. */
function borderPoint(rect, tx, ty) {
  const cx = rect.x + rect.w / 2;
  const cy = rect.y + rect.h / 2;
  const dx = tx - cx;
  const dy = ty - cy;
  if (!dx && !dy) return { x: cx, y: cy };
  const t = Math.min(
    dx ? (rect.w / 2) / Math.abs(dx) : Infinity,
    dy ? (rect.h / 2) / Math.abs(dy) : Infinity,
  );
  return { x: cx + dx * t, y: cy + dy * t };
}

/**
 * Where a derived cross-chart link starts and ends (PLAN §6.1, S12; DESIGN F13).
 *
 * It runs from the node that named the other chart to that CHART — the target is the chart's frame,
 * never a node inside it, because the label named a chart and picking an endpoint would be
 * inventing structure. When the source's own chart is collapsed the link starts at the collapsed
 * box instead, which is F8: the fold is where these links matter most.
 *
 * Both ends land on a border rather than a centre, so the line never runs underneath a box, and
 * the layout is not consulted for ranking — links are drawn over a layout computed from `edges`
 * alone, so they can never move a node or re-flow a frozen version.
 */
export function linkGeometry(link, laid) {
  const toFrame = laid.charts[link.toChart];
  const fromFrame = laid.charts[link.fromChart];
  if (!toFrame || !fromFrame) return null;

  const p = laid.positions[link.from];
  const s = laid.sizes[link.from];
  const source = p && s ? { x: p.x, y: p.y, w: s.w, h: s.h } : fromFrame;
  if (source === fromFrame && fromFrame === toFrame) return null;

  const sc = { x: source.x + source.w / 2, y: source.y + source.h / 2 };
  const tc = { x: toFrame.x + toFrame.w / 2, y: toFrame.y + toFrame.h / 2 };
  const a = borderPoint(source, tc.x, tc.y);
  const b = borderPoint(toFrame, sc.x, sc.y);

  // The control point of a bow, always PERPENDICULAR to the line and never zero.
  //
  // With every chart collapsed — the view these links are most useful in — the charts shelf-pack
  // into a single row, so both ends sit at the same y and a bow proportional to the vertical drop
  // would be flat: ten straight lines lying along the row, through the boxes between them. The bow
  // is what keeps a link off the boxes it passes and keeps two links between the same pair apart.
  const dx = b.x - a.x;
  const dy = b.y - a.y;
  const len = Math.hypot(dx, dy) || 1;
  // A quadratic Bézier only reaches HALF its control offset, so the offset has to be twice the
  // clearance wanted. Measured against the collapsed row, where the links pass over other charts:
  // at 120 the curve peaked at 60 and grazed the 74-high boxes it crossed. 260 peaks at 130 and
  // passes cleanly above them.
  const lift = Math.max(30, Math.min(len * 0.14, 260));
  return {
    x1: a.x, y1: a.y, x2: b.x, y2: b.y,
    // Left-hand normal, so a link and its reverse bow to opposite sides rather than overlapping.
    cx: (a.x + b.x) / 2 + (-dy / len) * lift,
    cy: (a.y + b.y) / 2 + (dx / len) * lift,
    folded: source === fromFrame,
  };
}

export function edgeGeometry(edge, laid) {
  const a = laid.positions[edge.from];
  const b = laid.positions[edge.to];
  if (!a || !b) return null;
  const sa = laid.sizes[edge.from];
  const sb = laid.sizes[edge.to];
  if (b.y > a.y) {
    return { x1: a.x + sa.w / 2, y1: a.y + sa.h, x2: b.x + sb.w / 2, y2: b.y, back: false };
  }
  return { x1: a.x + sa.w, y1: a.y + sa.h / 2, x2: b.x + sb.w, y2: b.y + sb.h / 2, back: true };
}

// Mermaid ingestion (PLAN S11, §4.6, §6, §7; DESIGN G2, Q64).
//
// The design document's ```mermaid blocks ARE the design graph. There is no second copy and no
// hand-authored JSON — the canvas renders what an implementation agent consumes (Q64=a, the
// no-mocks rule).
//
// Mermaid is a large, loose language. This module accepts the small subset PLAN §6 documents and
// **throws on everything else, naming the file and the line**:
//
//   flowchart TD
//     A1["label text"]                box node
//     A2{"label text"}                decision node
//     A1 --> A2                       plain edge
//     A1 -- "edge label" --> A2       labelled edge, quoted
//     A1 -- edge label --> A2         labelled edge, bare
//     A1["label"] --> A2["label"]     inline declaration on an edge line
//
// Guessing at anything else is what turns a diagram change into a silently wrong graph — the
// failure this module exists to make impossible. If a chart needs a construct that is not here,
// that is a plan change, not a parser change.
//
// Pure: no I/O, no DOM, no Node built-ins, so the browser imports this exact file (PLAN §2).

/** A node ID: one or two capitals, digits, an optional letter suffix. `A1`, `QR3`, `D10`, `B7a`. */
export const NODE_ID = /^[A-Z]{1,2}\d+[a-z]?$/;
const NODE_ID_HEAD = /^([A-Z]{1,2})(\d+)([a-z]?)/;
/** A question ID, for `decidedBy` (§4.6). Same shape as the grammar's, and deliberately separate. */
const QUESTION_ID = /\b(QR\d+|Q\d+[a-z]?)\b/g;
/** The `NEW:` marker a label carries when the node is new work rather than existing behaviour. */
const NEW_MARKER = /(^|[\s("])NEW:/;

const FENCE = /^\s*```+\s*(\w*)\s*$/;
const HEADING = /^(#{1,6})\s+(.*)$/;

/** A construct outside the §6 subset, or a chart that contradicts itself. */
export class GraphError extends Error {
  constructor(message, { file = null, line = null, text = null } = {}) {
    super(`${file ?? '?'}:${line ?? '?'} ${message}`);
    this.name = 'GraphError';
    this.file = file;
    this.line = line;
    this.text = text;
    this.reason = message;
  }
}

/**
 * Find the ```mermaid blocks, with the line each one starts on.
 * A fence of any other language is skipped whole — a code sample is not a chart.
 */
function mermaidBlocks(lines) {
  const blocks = [];
  let open = null;
  lines.forEach((raw, i) => {
    const fence = FENCE.exec(raw);
    if (!fence) return;
    if (open === null) {
      open = { lang: fence[1], start: i };
      return;
    }
    if (open.lang === 'mermaid') {
      // `start` is the index of the first body line, which is also the 1-based line number of the
      // opening fence — the line an error about the chart as a whole should name.
      const start = open.start + 1;
      blocks.push({
        start,
        end: i,
        body: lines.slice(start, i).map((text, k) => ({ text, line: start + k + 1 })),
      });
    }
    open = null;
  });
  return blocks;
}

/**
 * Join a block's source lines into statements. A statement is one line, EXCEPT that a quoted label
 * may run across lines — §6 says join those with a single space, which is exactly how both design
 * documents wrap their long labels.
 */
function statements(body, file) {
  const out = [];
  let buffer = null;
  for (const { text, line } of body) {
    const trimmed = text.trim();
    if (buffer === null) {
      if (!trimmed) continue;
      buffer = { text: trimmed, line };
    } else {
      buffer.text += ` ${trimmed}`;
    }
    // An odd number of quotes means the label is still open and the next line belongs to it.
    if ((buffer.text.match(/"/g) || []).length % 2 === 0) {
      out.push(buffer);
      buffer = null;
    }
  }
  if (buffer) {
    throw new GraphError('a quoted label is never closed', { file, line: buffer.line, text: buffer.text });
  }
  return out;
}

/** A cursor over one statement, so every "what is here?" failure can name the file and line. */
class Cursor {
  constructor(statement, file) {
    this.text = statement.text;
    this.line = statement.line;
    this.file = file;
    this.pos = 0;
  }

  fail(message) {
    return new GraphError(message, { file: this.file, line: this.line, text: this.text });
  }

  skipSpace() {
    while (this.pos < this.text.length && this.text[this.pos] === ' ') this.pos += 1;
  }

  get rest() {
    return this.text.slice(this.pos);
  }

  get done() {
    this.skipSpace();
    return this.pos >= this.text.length;
  }

  /** Read `"…"` whole, so a label containing `-->`, `--` or `·` can never be mistaken for syntax. */
  readQuoted() {
    if (this.text[this.pos] !== '"') throw this.fail(`expected a quoted label at "${this.rest.slice(0, 24)}"`);
    const end = this.text.indexOf('"', this.pos + 1);
    if (end === -1) throw this.fail('a quoted label is never closed');
    const value = this.text.slice(this.pos + 1, end);
    this.pos = end + 1;
    return value;
  }
}

/**
 * Read one node reference: a bare ID, or an ID declaring its label.
 * Only `["…"]` and `{"…"}` exist in the subset. Every other mermaid shape — `(round)`, `([stadium])`,
 * `[[subroutine]]`, `>flag]`, and unquoted labels of any kind — is refused by name.
 */
function readNodeRef(cursor) {
  cursor.skipSpace();
  const head = NODE_ID_HEAD.exec(cursor.rest);
  if (!head) throw cursor.fail(`expected a node ID at "${cursor.rest.slice(0, 24)}"`);
  const id = head[0];
  cursor.pos += id.length;
  const open = cursor.text[cursor.pos];

  if (open !== '[' && open !== '{') return { id, label: null, shape: null };

  const close = open === '[' ? ']' : '}';
  const shape = open === '[' ? 'box' : 'decision';
  cursor.pos += 1;
  if (cursor.text[cursor.pos] !== '"') {
    throw cursor.fail(`${id}: a node label must be quoted — "${id}${open}${cursor.text.slice(cursor.pos, cursor.pos + 16)}…"`);
  }
  const label = cursor.readQuoted();
  if (cursor.text[cursor.pos] !== close) {
    throw cursor.fail(`${id}: expected "${close}" after the label, found "${cursor.rest.slice(0, 12)}"`);
  }
  cursor.pos += 1;
  return { id, label: label.trim().replace(/\s+/g, ' '), shape };
}

/**
 * Read one edge: `-->`, `-- label -->`, or `-- "label" -->`.
 * Other arrow kinds (`-.->`, `==>`, `---`, `<-->`) are outside the subset and say so.
 */
function readEdge(cursor) {
  cursor.skipSpace();
  if (cursor.rest.startsWith('-->')) {
    cursor.pos += 3;
    return '';
  }
  const exotic = /^(-\.-+>|=+>|<-+>|-{3,}(?!>)|-{2}[ox])/.exec(cursor.rest);
  if (exotic) throw cursor.fail(`arrow "${exotic[0]}" is outside the subset — only "-->" and "-- label -->" exist`);
  if (!cursor.rest.startsWith('--')) {
    throw cursor.fail(`expected an edge at "${cursor.rest.slice(0, 24)}"`);
  }
  cursor.pos += 2;
  cursor.skipSpace();

  let label;
  if (cursor.text[cursor.pos] === '"') {
    label = cursor.readQuoted();
  } else {
    const end = cursor.text.indexOf('-->', cursor.pos);
    if (end === -1) throw cursor.fail('an edge label opened with "--" but no "-->" closes it');
    label = cursor.text.slice(cursor.pos, end).trim();
    cursor.pos = end;
    // §6: a bare label may not contain `·` or a quote. Those are the two characters that would make
    // the statement ambiguous, so a document using them has to quote the label.
    if (!label) throw cursor.fail('an edge label is empty — write "-->" for an unlabelled edge');
    if (/["·]/.test(label)) throw cursor.fail(`edge label "${label}" contains " or · — quote it`);
  }
  cursor.skipSpace();
  if (!cursor.rest.startsWith('-->')) {
    throw cursor.fail(`expected "-->" after the edge label, found "${cursor.rest.slice(0, 16)}"`);
  }
  cursor.pos += 3;
  return label.trim().replace(/\s+/g, ' ');
}

/** Question IDs named in a piece of text — the raw material of `decidedBy` (§4.6). */
function questionsIn(text) {
  return [...String(text ?? '').matchAll(QUESTION_ID)].map((m) => m[1]);
}

/** Parse one ```mermaid block into a chart. */
function parseChart(block, file) {
  const lines = statements(block.body, file);
  if (!lines.length) throw new GraphError('an empty mermaid block', { file, line: block.start });

  const header = lines[0];
  if (header.text !== 'flowchart TD') {
    throw new GraphError(`"${header.text}" is not a chart header — "flowchart TD" is the only one accepted`,
      { file, line: header.line, text: header.text });
  }

  const nodes = new Map();
  const edges = [];

  /** First declaration of an ID wins; a bare reference reuses it; a conflict is an error. */
  const declare = (ref, cursor) => {
    const existing = nodes.get(ref.id);
    if (!existing) {
      nodes.set(ref.id, { id: ref.id, label: ref.label ?? '', shape: ref.shape ?? 'box', line: cursor.line });
      return;
    }
    if (ref.label === null) return;
    if (existing.label && existing.label !== ref.label) {
      throw cursor.fail(`${ref.id} is declared twice with different labels (first on line ${existing.line})`);
    }
    if (existing.label && existing.shape !== ref.shape) {
      throw cursor.fail(`${ref.id} is declared twice with different shapes (first on line ${existing.line})`);
    }
    // It was a bare reference until now, so this is where the node is really declared.
    if (!existing.label) existing.line = cursor.line;
    existing.label = ref.label;
    existing.shape = ref.shape;
  };

  for (const statement of lines.slice(1)) {
    const cursor = new Cursor(statement, file);
    const from = readNodeRef(cursor);
    declare(from, cursor);
    if (cursor.done) continue;

    const label = readEdge(cursor);
    const to = readNodeRef(cursor);
    declare(to, cursor);
    edges.push({ from: from.id, to: to.id, label, line: cursor.line });

    if (!cursor.done) {
      // A --> B --> C chain, a trailing `;`, a `style` clause: all real mermaid, none of it §6.
      throw cursor.fail(`unexpected "${cursor.rest.trim()}" after the edge — one edge per line`);
    }
  }

  // §6: every chart's node IDs share a prefix letter, which becomes the chart ID.
  const prefixes = new Map();
  for (const id of nodes.keys()) {
    const prefix = NODE_ID_HEAD.exec(id)[1];
    if (!prefixes.has(prefix)) prefixes.set(prefix, []);
    prefixes.get(prefix).push(id);
  }
  if (prefixes.size !== 1) {
    const shown = [...prefixes.entries()].map(([p, ids]) => `${p} (${ids.slice(0, 3).join(', ')})`).join(' and ');
    throw new GraphError(`this chart mixes node prefixes: ${shown} — one chart, one prefix`,
      { file, line: block.start });
  }

  return {
    id: [...prefixes.keys()][0],
    line: block.start,
    nodes: [...nodes.values()],
    edges,
  };
}

/** The `Flowchart X — ` lead of a heading: its name and its title, separated. */
const HEADING_LEAD = /^Flowchart\s+([A-Z]{1,2}\d*)\s*[—-]\s*/i;

/** Strip a leading section number and a `Flowchart X — ` prefix off a heading. */
function cleanTitle(heading) {
  return String(heading)
    .replace(/^[\d][\w.-]*\.\s+/, '')
    .replace(HEADING_LEAD, '')
    .trim();
}

/**
 * What the document CALLS this chart, which is not always its ID (§4.6).
 * `### Flowchart B2 — free text at a gating question` heads a chart whose nodes are prefixed `P`,
 * and a label saying "chart B2" means that one. Null when the heading names nothing.
 */
function chartName(heading) {
  const lead = HEADING_LEAD.exec(String(heading).replace(/^[\d][\w.-]*\.\s+/, ''));
  return lead ? lead[1] : null;
}

/**
 * The prose after a chart, in chunks, up to the next fenced block.
 * §4.6 makes it the second source of `decidedBy`: a bullet naming a node and a question is the
 * document saying which question decides that node, and both design docs are written that way
 * ("**D5 — the skip tunable.** … What counts as 'can react' is **Q47**").
 *
 * It runs past headings deliberately. Spotlight puts chart D's forks under a `### The forks inside
 * D` heading and its questionnaire refers back to node IDs by name from §17 — stopping at the first
 * heading threw away most of the mapping. A chunk only counts when it names a node of THIS chart,
 * and node IDs are chart-scoped, so reading further costs little and recovers a lot.
 */
function proseAfter(lines, endIndex) {
  const chunks = [];
  let current = [];
  const flush = () => {
    if (current.length) chunks.push(current.join(' '));
    current = [];
  };
  for (let i = endIndex + 1; i < lines.length; i++) {
    const line = lines[i];
    if (FENCE.test(line)) break;
    if (!line.trim()) {
      flush();
      continue;
    }
    // A new list item, heading or table row starts a new chunk: one is one claim about one node.
    // `[-*] ` needs the space: a continuation line starting `**Q31, Q32…**` is the same bullet.
    if (/^\s*([-*]\s|\||#{1,6}\s)/.test(line)) flush();
    current.push(line.trim());
  }
  flush();
  return chunks;
}

/**
 * A reference to another chart, written in prose inside a node label (PLAN §6.1; DESIGN F12–F14).
 *
 * `\b` before `chart` is load-bearing: it is what keeps `flowchart TD` from matching. Case is
 * significant — chart names are capitals.
 */
const CHART_REF = /\bchart\s+([A-Z]{1,2}\d*)\b/g;

/**
 * Derive the cross-chart links (PLAN §6.1, GAP-002 = b).
 *
 * The subset has no cross-chart arrow, so charts never point at each other — and yet both real
 * design documents refer to each other constantly, in prose, inside labels:
 * `A6["owner answers one question at a time — chart B"]`. The link is already authored; this reads
 * it rather than inventing it. It NEVER guesses: a reference that resolves to nothing is a warning
 * naming the line, not a link to somewhere plausible.
 *
 * Returns `{ links, warnings }`. Warnings, not errors — an unresolved reference is an authoring
 * defect in a document that is otherwise perfectly readable, and GAP-001 already settled that that
 * class of thing must not block the owner (who cannot fix it) mid-review.
 */
function deriveLinks({ charts, nodes }) {
  // The name the DOCUMENT uses comes first, and it has to: Spotlight's §7 holds two charts, so
  // every chart ID after it is one letter ahead of the heading that names it. `K14 "see chart H"`
  // means the chart headed *Flowchart H*, which is the chart with ID `I`. Resolving by ID first
  // would silently link it to the wrong chart — a wrong link, drawn confidently, which is worse
  // than no link at all.
  const byName = new Map();
  for (const chart of charts) {
    if (chart.name && !byName.has(chart.name)) byName.set(chart.name, chart.id);
  }
  const byId = new Map(charts.map((c) => [c.id, c.id]));

  const links = [];
  const warnings = [];
  const seen = new Set();

  for (const chart of charts) {
    for (const id of chart.nodes) {
      const node = nodes[id];
      for (const match of String(node.label ?? '').matchAll(CHART_REF)) {
        const ref = match[1];
        // Resolution order, first hit wins (§6.1): the name the document uses, then the chart ID,
        // then a node ID the graph declares — `chart E3` is chart E, said by one of its nodes.
        const toChart = byName.get(ref) ?? byId.get(ref) ?? nodes[ref]?.chart ?? null;
        if (!toChart) {
          warnings.push(new GraphError(
            `${id}: "chart ${ref}" names no chart and no node — it is not linked to anything`,
            { line: node.line, text: node.label },
          ));
          continue;
        }
        // A reference to the node's OWN chart is not a link. Spotlight's chart E says "chart E2",
        // "chart E3", "chart E4" about its own nodes; drawing those is noise, and it is correct
        // authoring, so it is dropped silently rather than warned about.
        if (toChart === chart.id) continue;
        const key = `${id}~>${toChart}`;
        // §4.6: one link per (from, toChart). D8's label says "chart E" twice; repetition in prose
        // is not a second connection.
        if (seen.has(key)) continue;
        seen.add(key);
        links.push({ key, from: id, fromChart: chart.id, toChart, ref, line: node.line });
      }
    }
  }
  return { links, warnings };
}

/**
 * Parse every chart in a design document (PLAN §7).
 * Returns the §4.6 shape. `doc_hash` is left null — this module is pure, and the caller that read
 * the file is the one that can hash it.
 */
export function parseCharts(markdown, { file = 'DESIGN.md' } = {}) {
  const lines = String(markdown ?? '').split(/\r?\n/);
  const blocks = mermaidBlocks(lines);

  const charts = [];
  const nodes = {};
  const edges = [];
  const seenChart = new Map();
  const namedHeading = new Set();

  for (const block of blocks) {
    const chart = parseChart(block, file);
    if (seenChart.has(chart.id)) {
      throw new GraphError(
        `a second chart uses the "${chart.id}" prefix (the first is on line ${seenChart.get(chart.id)}) — `
        + 'two charts cannot share an ID, and merging them would invent structure',
        { file, line: chart.line },
      );
    }
    seenChart.set(chart.id, chart.line);

    // Best-effort title: the nearest heading above the block, with its numbering and its
    // "Flowchart X —" lead stripped. Charts sharing a heading share a title, which is true.
    // The lead itself becomes `name` (§4.6) — the chart's ID is `P`, but the document calls it B2.
    let title = '';
    let name = null;
    for (let i = block.start - 2; i >= 0; i--) {
      const heading = HEADING.exec(lines[i]);
      if (heading) {
        title = cleanTitle(heading[2]);
        // One heading names ONE chart: the first under it. Spotlight's §7 holds chart E and chart
        // F, and "chart E" in a label means the first one. The second is nameless and is reached
        // by its ID.
        if (!namedHeading.has(i)) {
          name = chartName(heading[2]);
          if (name) namedHeading.add(i);
        }
        break;
      }
    }

    const decided = new Map(chart.nodes.map((n) => [n.id, new Set(questionsIn(n.label))]));
    for (const chunk of proseAfter(lines, block.end)) {
      const named = chart.nodes.filter((n) => new RegExp(`\\b${n.id}\\b`).test(chunk));
      if (!named.length) continue;
      const asked = questionsIn(chunk);
      if (!asked.length) continue;
      for (const node of named) for (const q of asked) decided.get(node.id).add(q);
    }

    for (const node of chart.nodes) {
      nodes[node.id] = {
        chart: chart.id,
        label: node.label,
        shape: node.shape,
        new: NEW_MARKER.test(node.label),
        decidedBy: [...decided.get(node.id)],
        line: node.line,
      };
    }

    // §4.5: the edge key is FROM->TO, and every edge of a pair that has several is suffixed #1, #2…
    // in source order, so an annotation can name exactly one of them.
    const counts = new Map();
    for (const edge of chart.edges) {
      const pair = `${edge.from}->${edge.to}`;
      counts.set(pair, (counts.get(pair) || 0) + 1);
    }
    const seenPair = new Map();
    for (const edge of chart.edges) {
      const pair = `${edge.from}->${edge.to}`;
      let key = pair;
      if (counts.get(pair) > 1) {
        const n = (seenPair.get(pair) || 0) + 1;
        seenPair.set(pair, n);
        key = `${pair}#${n}`;
      }
      edges.push({ key, from: edge.from, to: edge.to, label: edge.label, chart: chart.id, line: edge.line });
    }

    // `name` stays null rather than falling back to the ID, and that is deliberate: in Spotlight
    // the heading "Flowchart F" names the chart whose IDs are `G`, so an ID-shaped fallback would
    // put a WRONG name in the table and §6.1 resolves names first.
    charts.push({ id: chart.id, name, title, line: chart.line, nodes: chart.nodes.map((n) => n.id) });
  }

  const { links, warnings } = deriveLinks({ charts, nodes });
  return { doc_hash: null, charts, nodes, edges, links, warnings };
}

/**
 * Static checks over an ingested graph (PLAN §7). Ingestion throws on anything it cannot read;
 * these are the things that parse but are still wrong, and they are returned rather than thrown so
 * a caller can report all of them at once.
 */
export function validate(graph) {
  const errors = [];
  for (const [id, node] of Object.entries(graph.nodes)) {
    if (!node.label) {
      errors.push(new GraphError(`${id} is referenced but never given a label`, { line: node.line }));
    }
  }
  for (const edge of graph.edges) {
    for (const end of [edge.from, edge.to]) {
      if (!graph.nodes[end]) errors.push(new GraphError(`edge ${edge.key} names ${end}, which no chart declares`, { line: edge.line }));
    }
    if (graph.nodes[edge.from] && graph.nodes[edge.to]
        && graph.nodes[edge.from].chart !== graph.nodes[edge.to].chart) {
      errors.push(new GraphError(`edge ${edge.key} crosses charts (${graph.nodes[edge.from].chart} → ${graph.nodes[edge.to].chart})`, { line: edge.line }));
    }
    if (edge.from === edge.to) {
      errors.push(new GraphError(`edge ${edge.key} points at itself`, { line: edge.line }));
    }
  }
  return errors;
}

/** A one-line summary per chart, for `run check` and the handoff (PLAN §8). */
export function describeGraph(graph) {
  return graph.charts.map((c) => {
    const within = graph.edges.filter((e) => e.chart === c.id).length;
    // The document's own name for the chart, shown only when it differs from the ID — which it
    // does whenever a section holds two charts (§6.1), and that is exactly when the reader needs
    // to be told.
    const called = c.name && c.name !== c.id ? ` (called ${c.name})` : '';
    const out = (graph.links ?? []).filter((l) => l.fromChart === c.id).map((l) => l.toChart);
    const links = out.length ? `  → ${[...new Set(out)].join(' ')}` : '';
    return `${c.id.padEnd(3)} ${String(c.nodes.length).padStart(3)} nodes ${String(within).padStart(3)} edges  ${c.title}${called}${links}`;
  });
}

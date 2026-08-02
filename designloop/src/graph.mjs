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

/** Strip a leading section number and a `Flowchart X — ` prefix off a heading. */
function cleanTitle(heading) {
  return String(heading)
    .replace(/^[\d][\w.-]*\.\s+/, '')
    .replace(/^Flowchart\s+[A-Z]{1,2}\d*\s*[—-]\s*/i, '')
    .trim();
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
    let title = '';
    for (let i = block.start - 2; i >= 0; i--) {
      const heading = HEADING.exec(lines[i]);
      if (heading) {
        title = cleanTitle(heading[2]);
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

    charts.push({ id: chart.id, title, line: chart.line, nodes: chart.nodes.map((n) => n.id) });
  }

  return { doc_hash: null, charts, nodes, edges };
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
    return `${c.id.padEnd(3)} ${String(c.nodes.length).padStart(3)} nodes ${String(within).padStart(3)} edges  ${c.title}`;
  });
}

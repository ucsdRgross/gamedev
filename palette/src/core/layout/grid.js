// The cell grid every picker layout is built on (PLAN §9).
//
// A layout is an assignment of palette entries to grid cells. Everything about *where*
// cells are and *which cells touch* lives here, so the fifteen variants only have to
// decide the assignment. Four topologies are supported because four of the variants are
// defined by their topology rather than by their algorithm.
//
// Adjacency and cell positions are precomputed once per grid: the scorer walks every
// edge on every call and the annealer walks one cell's edges per proposal, so both want
// flat typed arrays rather than repeated bounds arithmetic.

const HEX_ROW_SPACING = Math.sqrt(3) / 2;
const MAX_NEIGHBORS = 6;

/** The grid topologies layouts can be built on. */
export const TOPOLOGIES = ['rect', 'torus', 'hex', 'disc'];

/** A width×height cell grid with a topology, an active-cell mask, and precomputed edges. */
export class Grid {
  constructor(w, h, topology = 'rect') {
    if (!TOPOLOGIES.includes(topology)) throw new Error(`unknown topology: ${topology}`);
    this.w = w | 0;
    this.h = h | 0;
    this.topology = topology;
    this.mask = buildMask(this.w, this.h, topology);

    this.active = [];
    for (let i = 0; i < this.mask.length; i++) if (this.mask[i]) this.active.push(i);
    this.active = Int32Array.from(this.active);
    this.count = this.active.length;
    // Reverse index: cell -> position in `active`, so algorithms holding one value per
    // active cell can look up by cell id without searching. -1 for masked-out cells.
    this.slot = new Int32Array(this.w * this.h).fill(-1);
    this.active.forEach((cell, a) => { this.slot[cell] = a; });

    // Continuous positions, precomputed: the SOM reads them millions of times per run.
    this.px = new Float64Array(this.w * this.h);
    this.py = new Float64Array(this.w * this.h);
    for (let i = 0; i < this.px.length; i++) {
      const x = i % this.w;
      const y = (i / this.w) | 0;
      this.px[i] = topology === 'hex' ? x + (y & 1 ? 0.5 : 0) : x;
      this.py[i] = topology === 'hex' ? y * HEX_ROW_SPACING : y;
    }
    this.spanX = this.w;
    this.spanY = topology === 'hex' ? this.h * HEX_ROW_SPACING : this.h;
    this.wraps = topology === 'torus';

    this.nbr = new Int32Array(this.w * this.h * MAX_NEIGHBORS).fill(-1);
    this.nbrCount = new Uint8Array(this.w * this.h);
    this.#buildNeighbors();
    this.edges = this.#buildEdges();
  }

  /** Squared distance between two cells, wrapped on a torus. */
  dist2(i, j) {
    let dx = this.px[i] - this.px[j];
    let dy = this.py[i] - this.py[j];
    if (this.wraps) {
      dx = wrapDelta(dx, this.spanX);
      dy = wrapDelta(dy, this.spanY);
    }
    return dx * dx + dy * dy;
  }

  /** The neighbours of cell `i` as a plain array of cell indices. */
  neighbors(i) {
    const out = [];
    const base = i * MAX_NEIGHBORS;
    for (let k = 0; k < this.nbrCount[i]; k++) out.push(this.nbr[base + k]);
    return out;
  }

  #buildNeighbors() {
    for (const i of this.active) {
      const x = i % this.w;
      const y = (i / this.w) | 0;
      let n = 0;
      for (const [dx, dy] of neighborOffsets(this.topology, y)) {
        let nx = x + dx;
        let ny = y + dy;
        if (this.topology === 'torus') {
          nx = ((nx % this.w) + this.w) % this.w;
          ny = ((ny % this.h) + this.h) % this.h;
        } else if (nx < 0 || ny < 0 || nx >= this.w || ny >= this.h) {
          continue;
        }
        const j = ny * this.w + nx;
        if (!this.mask[j] || j === i) continue;
        let dup = false; // a 2-wide torus wraps onto the same cell from both sides
        for (let q = 0; q < n; q++) if (this.nbr[i * MAX_NEIGHBORS + q] === j) dup = true;
        if (dup) continue;
        this.nbr[i * MAX_NEIGHBORS + n++] = j;
      }
      this.nbrCount[i] = n;
    }
  }

  #buildEdges() {
    const pairs = [];
    for (const i of this.active) {
      const base = i * MAX_NEIGHBORS;
      for (let k = 0; k < this.nbrCount[i]; k++) {
        const j = this.nbr[base + k];
        if (j > i) pairs.push(i, j);
      }
    }
    return Int32Array.from(pairs);
  }
}

/**
 * Mean position of a set of cells. On a torus the coordinates are averaged as angles —
 * arithmetic means put the centroid of a blob straddling the seam in the wrong half.
 */
export function centroidOf(grid, cells, fallback) {
  if (cells.length === 0) return fallback;
  if (!grid.wraps) {
    let x = 0;
    let y = 0;
    for (const i of cells) { x += grid.px[i]; y += grid.py[i]; }
    return [x / cells.length, y / cells.length];
  }
  const axis = (coords, span) => {
    let sx = 0;
    let sy = 0;
    for (const i of cells) {
      const a = (coords[i] / span) * 2 * Math.PI;
      sx += Math.cos(a);
      sy += Math.sin(a);
    }
    return ((Math.atan2(sy, sx) / (2 * Math.PI)) * span + span) % span;
  };
  return [axis(grid.px, grid.spanX), axis(grid.py, grid.spanY)];
}

/** Signed delta on a wrapped axis of the given length, taking the shorter way round. */
function wrapDelta(d, len) {
  const m = ((d % len) + len) % len;
  return m > len / 2 ? m - len : m;
}

/** Neighbour offsets for a topology; hex depends on the row's parity (odd-r offset). */
function neighborOffsets(topology, y) {
  if (topology !== 'hex') return [[1, 0], [-1, 0], [0, 1], [0, -1]];
  const s = y & 1 ? 1 : -1; // odd rows lean right, even rows lean left
  return [[1, 0], [-1, 0], [0, -1], [s, -1], [0, 1], [s, 1]];
}

/** Active-cell mask: everything except `disc`, which keeps an inscribed circle. */
function buildMask(w, h, topology) {
  const mask = new Uint8Array(w * h).fill(1);
  if (topology !== 'disc') return mask;
  const cx = (w - 1) / 2;
  const cy = (h - 1) / 2;
  const r = Math.min(w, h) / 2;
  for (let y = 0; y < h; y++) {
    for (let x = 0; x < w; x++) {
      const dx = x - cx;
      const dy = y - cy;
      mask[y * w + x] = dx * dx + dy * dy <= r * r ? 1 : 0;
    }
  }
  return mask;
}

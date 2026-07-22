// PAL1 seed string codec (PLAN §6).
//
// The payload carries the FULL parameter set, not an RNG seed. A bare RNG seed stops
// reproducing its palette the moment the algorithm changes, which defeats the entire
// point of being able to re-tune months later.
//
//   [ver:u8][paramCount:u8][params: u16 x paramCount]
//   [lockCount:u8][ (slotIndex:u8, rgb:u24) x n ]
//   [overrideCount:u8][ (slotIndex:u8, rgb:u24) x n ]
//
// Old decoders are kept when PAL2 arrives, so a seed pasted a year from now still
// resolves. Within PAL1, appending parameters is safe: a short payload is filled out
// with defaults.

import { PARAMS, normalizeParams, defaultParams, paramToU16, u16ToParam } from './params.js';
import { allocate, buildSlots } from './allocate.js';
import { hexToRgb8, rgb8ToHex } from './oklch.js';

export const SEED_VERSION = 1;
const PREFIX = 'PAL1-';
const ALPHABET = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_';

/** Encode bytes as unpadded base64url. */
function toBase64Url(bytes) {
  let out = '';
  for (let i = 0; i < bytes.length; i += 3) {
    const b0 = bytes[i];
    const b1 = i + 1 < bytes.length ? bytes[i + 1] : 0;
    const b2 = i + 2 < bytes.length ? bytes[i + 2] : 0;
    const n = (b0 << 16) | (b1 << 8) | b2;
    const chars = bytes.length - i;
    out += ALPHABET[(n >> 18) & 63] + ALPHABET[(n >> 12) & 63];
    if (chars > 1) out += ALPHABET[(n >> 6) & 63];
    if (chars > 2) out += ALPHABET[n & 63];
  }
  return out;
}

/** Decode unpadded base64url back to bytes. */
function fromBase64Url(str) {
  const clean = str.replace(/[^A-Za-z0-9\-_]/g, '');
  const out = [];
  for (let i = 0; i < clean.length; i += 4) {
    const chunk = clean.slice(i, i + 4);
    let n = 0;
    for (let k = 0; k < 4; k++) {
      const idx = k < chunk.length ? ALPHABET.indexOf(chunk[k]) : 0;
      if (k < chunk.length && idx < 0) throw new Error(`bad seed character "${chunk[k]}"`);
      n = (n << 6) | Math.max(0, idx);
    }
    out.push((n >> 16) & 255);
    if (chunk.length > 2) out.push((n >> 8) & 255);
    if (chunk.length > 3) out.push(n & 255);
  }
  return Uint8Array.from(out);
}

/** Slot ids in stable order for a parameter set — the index space seeds refer to. */
export function slotIdsFor(params) {
  return buildSlots(allocate(params)).map((s) => s.id);
}

/**
 * Encode parameters plus locked and overridden colours into a `PAL1-…` seed string.
 * Locks and overrides are keyed by slot id and stored as slot indices.
 */
export function encodeSeed(params, locks = {}, overrides = {}) {
  const p = normalizeParams(params);
  const ids = slotIdsFor(p);
  const bytes = [SEED_VERSION, PARAMS.length];
  for (const spec of PARAMS) {
    const u = paramToU16(spec, p[spec.name]);
    bytes.push((u >> 8) & 255, u & 255);
  }
  for (const table of [locks, overrides]) {
    const entries = Object.entries(table)
      .map(([id, hex]) => [ids.indexOf(id), hex])
      .filter(([idx]) => idx >= 0)
      .sort((a, b) => a[0] - b[0]);
    bytes.push(Math.min(255, entries.length));
    for (const [idx, hex] of entries.slice(0, 255)) {
      const rgb = hexToRgb8(hex);
      bytes.push(idx, rgb[0], rgb[1], rgb[2]);
    }
  }
  return PREFIX + toBase64Url(Uint8Array.from(bytes));
}

/** Decode a `PAL1-…` seed string back to `{ params, locks, overrides }`. */
export function decodeSeed(seed) {
  const text = String(seed).trim();
  if (!text.toUpperCase().startsWith(PREFIX)) throw new Error('seed must start with PAL1-');
  const bytes = fromBase64Url(text.slice(PREFIX.length));
  if (bytes.length < 2) throw new Error('seed payload is truncated');
  const version = bytes[0];
  if (version !== SEED_VERSION) throw new Error(`unsupported seed version ${version}`);

  const count = bytes[1];
  let pos = 2;
  const params = defaultParams();
  for (let i = 0; i < count; i++) {
    if (pos + 1 >= bytes.length) throw new Error('seed payload is truncated');
    const u = (bytes[pos] << 8) | bytes[pos + 1];
    pos += 2;
    // Fields beyond the current schema come from a newer build; skip them rather than
    // fail, so a forward seed still yields a usable palette.
    if (i < PARAMS.length) params[PARAMS[i].name] = u16ToParam(PARAMS[i], u);
  }

  const ids = slotIdsFor(params);
  const readTable = () => {
    const table = {};
    if (pos >= bytes.length) return table;
    const n = bytes[pos++];
    for (let i = 0; i < n && pos + 3 < bytes.length + 1; i++) {
      const idx = bytes[pos];
      const hex = rgb8ToHex([bytes[pos + 1], bytes[pos + 2], bytes[pos + 3]]);
      pos += 4;
      if (ids[idx]) table[ids[idx]] = hex;
    }
    return table;
  };
  return { params: normalizeParams(params), locks: readTable(), overrides: readTable() };
}

import test from 'node:test';
import assert from 'node:assert/strict';
import { encodeSeed, decodeSeed, slotIdsFor, SEED_VERSION } from '../src/core/seed.js';
import { PARAMS, defaultParams, normalizeParams, paramToU16 } from '../src/core/params.js';
import { generatePalette, paletteHexes } from '../src/core/generate.js';
import { makeRng } from '../src/core/rng.js';

/** A deterministic random parameter set covering every field. */
function randomParams(rng) {
  const p = {};
  for (const spec of PARAMS) {
    if (spec.type === 'bool') p[spec.name] = rng() < 0.5;
    else if (spec.type === 'enum') p[spec.name] = spec.options[Math.floor(rng() * spec.options.length)];
    else {
      const v = spec.min + rng() * (spec.max - spec.min);
      p[spec.name] = spec.type === 'int' ? Math.round(v) : v;
    }
  }
  return normalizeParams(p);
}

test('seed strings are prefixed, compact and base64url-safe', () => {
  const seed = encodeSeed(defaultParams());
  assert.match(seed, /^PAL1-[A-Za-z0-9_-]+$/);
  assert.ok(seed.length < 240, `seed is ${seed.length} characters`);
});

test('round-trips over randomised parameter sets', () => {
  const rng = makeRng(31337);
  for (let i = 0; i < 300; i++) {
    const params = randomParams(rng);
    const decoded = decodeSeed(encodeSeed(params));
    for (const spec of PARAMS) {
      if (spec.type === 'float') {
        assert.ok(
          Math.abs(decoded.params[spec.name] - params[spec.name]) <= (spec.max - spec.min) / 65535,
          `${spec.name}: ${decoded.params[spec.name]} vs ${params[spec.name]}`,
        );
      } else {
        assert.equal(decoded.params[spec.name], params[spec.name], spec.name);
      }
    }
  }
});

test('re-encoding a decoded seed is a fixed point', () => {
  const rng = makeRng(4);
  for (let i = 0; i < 100; i++) {
    const first = encodeSeed(randomParams(rng));
    const second = encodeSeed(decodeSeed(first).params);
    assert.equal(second, first);
  }
});

test('locks and overrides survive the round trip', () => {
  const params = { ...defaultParams(), color_count: 24 };
  const ids = slotIdsFor(params);
  const locks = { [ids[3]]: '#123456', [ids[11]]: '#ABCDEF' };
  const overrides = { [ids[0]]: '#FF0000', [ids[23]]: '#00FF80' };
  const decoded = decodeSeed(encodeSeed(params, locks, overrides));
  assert.deepEqual(decoded.locks, locks);
  assert.deepEqual(decoded.overrides, overrides);
});

test('locks pointing at slots that no longer exist are dropped', () => {
  const big = { ...defaultParams(), color_count: 40 };
  const ids = slotIdsFor(big);
  const seed = encodeSeed(big, { [ids[38]]: '#112233' });
  const decoded = decodeSeed(seed);
  assert.equal(decoded.locks[ids[38]], '#112233');
  // Encoding the same lock against a smaller palette simply omits it.
  const small = encodeSeed({ ...defaultParams(), color_count: 6 }, { [ids[38]]: '#112233' });
  assert.deepEqual(decodeSeed(small).locks, {});
});

test('a seed reproduces its palette exactly', () => {
  const rng = makeRng(808);
  for (let i = 0; i < 40; i++) {
    const params = randomParams(rng);
    const ids = slotIdsFor(params);
    const overrides = ids.length > 2 ? { [ids[1]]: '#4488CC' } : {};
    const original = generatePalette(params, { overrides });
    const decoded = decodeSeed(original.seed);
    const rebuilt = generatePalette(decoded.params, {
      locks: decoded.locks, overrides: decoded.overrides,
    });
    assert.deepEqual(paletteHexes(rebuilt), paletteHexes(original), `seed ${original.seed}`);
    assert.equal(rebuilt.seed, original.seed);
  }
});

test('a short PAL1 payload still decodes, filling the tail with defaults', () => {
  // Simulates a seed written before the last few parameters were appended.
  const params = { ...defaultParams(), color_count: 20, root_hue: 200 };
  const keep = PARAMS.length - 3;
  const bytes = [SEED_VERSION, keep];
  for (let i = 0; i < keep; i++) {
    const u = paramToU16(PARAMS[i], params[PARAMS[i].name]);
    bytes.push((u >> 8) & 255, u & 255);
  }
  const ALPHABET = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_';
  let payload = '';
  for (let i = 0; i < bytes.length; i += 3) {
    const n = (bytes[i] << 16) | ((bytes[i + 1] ?? 0) << 8) | (bytes[i + 2] ?? 0);
    const chars = bytes.length - i;
    payload += ALPHABET[(n >> 18) & 63] + ALPHABET[(n >> 12) & 63];
    if (chars > 1) payload += ALPHABET[(n >> 6) & 63];
    if (chars > 2) payload += ALPHABET[n & 63];
  }
  const decoded = decodeSeed(`PAL1-${payload}`);
  assert.equal(decoded.params.color_count, 20);
  assert.ok(Math.abs(decoded.params.root_hue - 200) < 0.02);
  for (const spec of PARAMS.slice(keep)) {
    assert.equal(decoded.params[spec.name], spec.default, `${spec.name} should fall back to its default`);
  }
  assert.deepEqual(decoded.locks, {});
});

test('malformed seeds are rejected with a useful message', () => {
  assert.throws(() => decodeSeed('nonsense'), /must start with PAL1-/);
  assert.throws(() => decodeSeed('PAL1-'), /truncated/);
  assert.throws(() => decodeSeed('PAL1-AwAA'), /unsupported seed version/);
});

test('whitespace and case in the prefix are tolerated', () => {
  const seed = encodeSeed(defaultParams());
  assert.deepEqual(decodeSeed(`  ${seed}  `).params, decodeSeed(seed).params);
  assert.deepEqual(decodeSeed(seed.replace('PAL1', 'pal1')).params, decodeSeed(seed).params);
});

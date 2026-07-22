// Seeded xorshift128 PRNG. Determinism is a tested requirement, so nothing in this
// codebase may call Math.random — every stochastic choice runs through here.

/** SplitMix32, used only to expand a small integer seed into a full xorshift state. */
function splitmix32(seed) {
  let a = seed | 0;
  return function next() {
    a = (a + 0x9e3779b9) | 0;
    let t = a ^ (a >>> 16);
    t = Math.imul(t, 0x21f0aaad);
    t = t ^ (t >>> 15);
    t = Math.imul(t, 0x735a2d97);
    return (t ^ (t >>> 15)) >>> 0;
  };
}

/** Create a deterministic PRNG returning floats in [0, 1). */
export function makeRng(seed) {
  const mix = splitmix32(Math.floor(seed) >>> 0);
  let x = mix() || 1;
  let y = mix() || 2;
  let z = mix() || 3;
  let w = mix() || 4;
  const next = () => {
    const t = x ^ (x << 11);
    x = y;
    y = z;
    z = w;
    w = (w ^ (w >>> 19)) ^ (t ^ (t >>> 8));
    return (w >>> 0) / 4294967296;
  };
  for (let i = 0; i < 8; i++) next(); // discard the seeding transient
  return next;
}

/** Draw a float in [lo, hi). */
export function rngRange(rng, lo, hi) {
  return lo + rng() * (hi - lo);
}

/** Draw an integer in [lo, hi] inclusive. */
export function rngInt(rng, lo, hi) {
  return lo + Math.floor(rng() * (hi - lo + 1));
}

/** Pick one element of an array. */
export function rngPick(rng, arr) {
  return arr[Math.min(arr.length - 1, Math.floor(rng() * arr.length))];
}

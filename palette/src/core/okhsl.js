// OKHSL — a perceptual replacement for HSL (Björn Ottosson, bottosson.github.io/posts/colorpicker).
//
// The colour-space maps and the dither reference lay colour out on a hue×lightness rectangle and
// paint the colour each position represents. Doing that in plain **HSL** bands: HSL lightness is
// not perceptually uniform and its saturation peaks in a hard ridge at l=0.5, so an even sweep of
// pixels is an uneven sweep of colour, which the eye reads as contouring. Doing it in raw **OKLCH**
// would be perceptually smooth but leaves large out-of-gamut holes at any fixed chroma, because the
// sRGB gamut is a lumpy shape in OKLCH.
//
// OKHSL is the fix an artist means by "why not do it the way OKLab does": it keeps HSL's guarantee
// that **every (h,s,l) triple is a real sRGB colour** (s and l are normalised against the gamut
// boundary, so there are no holes) while making lightness and hue **perceptually uniform** (l runs
// through OKLab lightness with Ottosson's `toe` correction, hue is the OKLab hue angle). The result
// is a smooth, band-free colormap with full coverage — exactly what a reference image needs.
//
// This is a faithful transcription of Ottosson's public-domain reference. The magic constants are
// the standard OKLab LMS→linear-sRGB matrix (the same one `oklch.js` uses, reused here) and the
// polynomial fits Ottosson published for the gamut cusp; they are not free parameters to tune.

import { oklabToLinearRgb, linearToSrgb } from './oklch.js';

const TAU = Math.PI * 2;

// Ottosson's "toe" — the correction that turns OKLab L into a perceptually even lightness axis
// (Lr), matching CIE L* near the ends. k3 chosen so toe(1)=1 and toe(0)=0.
const K1 = 0.206;
const K2 = 0.03;
const K3 = (1 + K1) / (1 + K2);

/** OKLab L → reference lightness Lr. */
export function toe(x) {
  return 0.5 * (K3 * x - K1 + Math.sqrt((K3 * x - K1) * (K3 * x - K1) + 4 * K2 * K3 * x));
}

/** Reference lightness Lr → OKLab L (the inverse of `toe`). */
export function toeInv(x) {
  return (x * x + K1 * x) / (K3 * (x + K2));
}

/** OKLab (L=1, a, b) → linear-sRGB. Used to locate the gamut cusp for a hue. */
function oklabToLinearSrgb(L, a, b) {
  return oklabToLinearRgb(L, a, b);
}

/**
 * The maximum saturation S = C/L on the `(a, b)` hue line that still fits in sRGB — the chroma at
 * which the first of R, G, B reaches the gamut edge. A cubic fit picks the branch (which channel
 * clips first), refined by one Halley step. Ottosson's coefficients.
 */
function computeMaxSaturation(a, b) {
  let k0; let k1; let k2; let k3; let k4; let wl; let wm; let ws;
  if (-1.88170328 * a - 0.80936493 * b > 1) {
    // Red clips first.
    k0 = 1.19086277; k1 = 1.76576728; k2 = 0.59662641; k3 = 0.75515197; k4 = 0.56771245;
    wl = 4.0767416621; wm = -3.3077115913; ws = 0.2309699292;
  } else if (1.81444104 * a - 1.19445276 * b > 1) {
    // Green clips first.
    k0 = 0.73956515; k1 = -0.45954404; k2 = 0.08285427; k3 = 0.1254107; k4 = 0.14503204;
    wl = -1.2684380046; wm = 2.6097574011; ws = -0.3413193965;
  } else {
    // Blue clips first.
    k0 = 1.35733652; k1 = -0.00915799; k2 = -1.1513021; k3 = -0.50559606; k4 = 0.00692167;
    wl = -0.0041960863; wm = -0.7034186147; ws = 1.707614701;
  }
  let S = k0 + k1 * a + k2 * b + k3 * a * a + k4 * a * b;

  const kl = 0.3963377774 * a + 0.2158037573 * b;
  const km = -0.1055613458 * a - 0.0638541728 * b;
  const ks = -0.0894841775 * a - 1.291485548 * b;

  const l_ = 1 + S * kl;
  const m_ = 1 + S * km;
  const s_ = 1 + S * ks;
  const l = l_ * l_ * l_;
  const m = m_ * m_ * m_;
  const s = s_ * s_ * s_;
  const ldS = 3 * kl * l_ * l_;
  const mdS = 3 * km * m_ * m_;
  const sdS = 3 * ks * s_ * s_;
  const ldS2 = 6 * kl * kl * l_;
  const mdS2 = 6 * km * km * m_;
  const sdS2 = 6 * ks * ks * s_;
  const f = wl * l + wm * m + ws * s;
  const f1 = wl * ldS + wm * mdS + ws * sdS;
  const f2 = wl * ldS2 + wm * mdS2 + ws * sdS2;
  S -= (f * f1) / (f1 * f1 - 0.5 * f * f2);
  return S;
}

/** The gamut cusp `{ L, C }` for a hue given as a unit `(a, b)` — its most saturated colour. */
export function findCusp(a, b) {
  const S = computeMaxSaturation(a, b);
  const rgb = oklabToLinearSrgb(1, S * a, S * b);
  const Lcusp = Math.cbrt(1 / Math.max(rgb[0], rgb[1], rgb[2]));
  return { L: Lcusp, C: Lcusp * S };
}

/**
 * The chroma at which the segment from `(L0, 0)` toward `(L1, C1)` crosses the sRGB gamut boundary,
 * as a fraction `t`. Uses the cusp to pick the half-plane, then one Halley step per channel on the
 * upper half. Ottosson's reference, verbatim.
 */
function findGamutIntersection(a, b, L1, C1, L0, cusp) {
  let t;
  if ((L1 - L0) * cusp.C - (cusp.L - L0) * C1 <= 0) {
    t = (cusp.C * L0) / (C1 * cusp.L + cusp.C * (L0 - L1));
  } else {
    t = (cusp.C * (L0 - 1)) / (C1 * (cusp.L - 1) + cusp.C * (L0 - L1));
    const dL = L1 - L0;
    const dC = C1;
    const kl = 0.3963377774 * a + 0.2158037573 * b;
    const km = -0.1055613458 * a - 0.0638541728 * b;
    const ks = -0.0894841775 * a - 1.291485548 * b;
    const lDt = dL + dC * kl;
    const mDt = dL + dC * km;
    const sDt = dL + dC * ks;

    const L = L0 * (1 - t) + t * L1;
    const C = t * C1;
    const l_ = L + C * kl;
    const m_ = L + C * km;
    const s_ = L + C * ks;
    const l = l_ * l_ * l_;
    const m = m_ * m_ * m_;
    const s = s_ * s_ * s_;
    const ldt = 3 * lDt * l_ * l_;
    const mdt = 3 * mDt * m_ * m_;
    const sdt = 3 * sDt * s_ * s_;
    const ldt2 = 6 * lDt * lDt * l_;
    const mdt2 = 6 * mDt * mDt * m_;
    const sdt2 = 6 * sDt * sDt * s_;

    const r = 4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s - 1;
    const r1 = 4.0767416621 * ldt - 3.3077115913 * mdt + 0.2309699292 * sdt;
    const r2 = 4.0767416621 * ldt2 - 3.3077115913 * mdt2 + 0.2309699292 * sdt2;
    const ur = r1 / (r1 * r1 - 0.5 * r * r2);
    let tr = -r * ur;

    const g = -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s - 1;
    const g1 = -1.2684380046 * ldt + 2.6097574011 * mdt - 0.3413193965 * sdt;
    const g2 = -1.2684380046 * ldt2 + 2.6097574011 * mdt2 - 0.3413193965 * sdt2;
    const ug = g1 / (g1 * g1 - 0.5 * g * g2);
    let tg = -g * ug;

    const bb = -0.0041960863 * l - 0.7034186147 * m + 1.707614701 * s - 1;
    const b1 = -0.0041960863 * ldt - 0.7034186147 * mdt + 1.707614701 * sdt;
    const b2 = -0.0041960863 * ldt2 - 0.7034186147 * mdt2 + 1.707614701 * sdt2;
    const ub = b1 / (b1 * b1 - 0.5 * bb * b2);
    let tb = -bb * ub;

    tr = ur >= 0 ? tr : Infinity;
    tg = ug >= 0 ? tg : Infinity;
    tb = ub >= 0 ? tb : Infinity;
    t += Math.min(tr, tg, tb);
  }
  return t;
}

/** Cusp `{ L, C }` → saturation/temperature form `{ S, T }`. */
function toST(cusp) {
  return { S: cusp.C / cusp.L, T: cusp.C / (1 - cusp.L) };
}

/** Ottosson's polynomial fit for the mid-saturation `{ S, T }` of a hue. */
function getSTMid(a, b) {
  const S = 0.11516993 + 1 / (
    7.4477897 + 4.1590124 * b
    + a * (-2.19557347 + 1.75198401 * b
      + a * (-2.13704948 - 10.02301043 * b
        + a * (-4.24894561 + 5.38770819 * b + 4.69891013 * a)))
  );
  const T = 0.11239642 + 1 / (
    1.6132032 - 0.68124379 * b
    + a * (0.40370612 + 0.90148123 * b
      + a * (-0.27087943 + 0.6122399 * b
        + a * (0.00299215 - 0.45399568 * b - 0.14661872 * a)))
  );
  return { S, T };
}

/** The three chroma control points `[C0, Cmid, Cmax]` OKHSL interpolates saturation across. */
function getCs(L, a, b, cusp, stMid) {
  const Cmax = findGamutIntersection(a, b, L, 1, L, cusp);
  const stMax = toST(cusp);
  const k = Cmax / Math.min(L * stMax.S, (1 - L) * stMax.T);

  let Ca = L * stMid.S;
  let Cb = (1 - L) * stMid.T;
  const Cmid = 0.9 * k * Math.sqrt(Math.sqrt(1 / (1 / (Ca ** 4) + 1 / (Cb ** 4))));

  Ca = L * 0.4;
  Cb = (1 - L) * 0.8;
  const C0 = Math.sqrt(1 / (1 / (Ca * Ca) + 1 / (Cb * Cb)));
  return [C0, Cmid, Cmax];
}

/**
 * A hue's cusp and mid-ST, which depend only on the hue and are the expensive part of an OKHSL
 * conversion (a cubic fit plus a Halley step). On a hue×lightness rectangle every pixel of a column
 * shares a hue, so computing this once per column and passing it into `okhslToSrgb` turns ~hundreds
 * of thousands of conversions back into a few hundred cusp solves.
 */
export function hueContext(hueDeg) {
  const h = hueDeg / 360;
  const a = Math.cos(TAU * h);
  const b = Math.sin(TAU * h);
  return { a, b, cusp: findCusp(a, b), stMid: getSTMid(a, b) };
}

/**
 * OKHSL (hue in degrees, s and l in 0..1) → gamma-encoded sRGB floats in 0..1.
 *
 * Always in gamut: `s` and `l` are normalised against the gamut boundary, so every triple is a real
 * colour. Pass a `hueContext(hue)` as `ctx` to reuse a column's cusp solve.
 */
export function okhslToSrgb(hueDeg, s, l, ctx = null) {
  if (l >= 1) return [1, 1, 1];
  if (l <= 0) return [0, 0, 0];
  const { a, b, cusp, stMid } = ctx ?? hueContext(hueDeg);
  const L = toeInv(l);
  const [C0, Cmid, Cmax] = getCs(L, a, b, cusp, stMid);

  const mid = 0.8;
  const midInv = 1.25;
  let C;
  if (s < mid) {
    const t = midInv * s;
    const k1 = mid * C0;
    const k2 = 1 - k1 / Cmid;
    C = (t * k1) / (1 - k2 * t);
  } else {
    const t = 5 * (s - mid);
    const k0 = Cmid;
    const k1 = (0.2 * Cmid * Cmid * midInv * midInv) / C0;
    const k2 = 1 - k1 / (Cmax - Cmid);
    C = k0 + (t * k1) / (1 - k2 * t);
  }

  const rgb = oklabToLinearSrgb(L, C * a, C * b);
  return [linearToSrgb(rgb[0]), linearToSrgb(rgb[1]), linearToSrgb(rgb[2])];
}

/**
 * `okhslToSrgb` with the per-hue cusp solve memoised — the form the map builders use.
 *
 * The cusp/mid solve is the whole cost of a conversion and depends only on the hue, so on a
 * hue×lightness rectangle (at most a few hundred distinct hues however many pixels it has) this
 * turns hundreds of thousands of conversions back into a few hundred solves. The cache is keyed by
 * the exact hue value and is bounded by the handful of map widths ever used, so it does not grow
 * without limit over a session.
 */
const HUE_CTX = new Map();
export function okhslCached(hueDeg, s, l) {
  let ctx = HUE_CTX.get(hueDeg);
  if (!ctx) { ctx = hueContext(hueDeg); HUE_CTX.set(hueDeg, ctx); }
  return okhslToSrgb(hueDeg, s, l, ctx);
}

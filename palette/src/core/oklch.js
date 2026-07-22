// OKLCH / OKLab / sRGB conversions, perceptual distance, and WCAG contrast.
// DOM-free: importable from both Node and the browser.
//
// Conventions used throughout the codebase:
//   OKLCH   { L, C, h }   L 0..1, C 0..~0.37, h degrees 0..360
//   OKLab   [L, a, b]
//   linear  [r, g, b]     0..1, may fall outside when out of gamut
//   sRGB    [r, g, b]     0..1 gamma-encoded, may fall outside when out of gamut
//   rgb8    [r, g, b]     integers 0..255

const DEG = 180 / Math.PI;
const RAD = Math.PI / 180;

/** Convert cylindrical OKLCH to cartesian OKLab. */
export function oklchToOklab(L, C, h) {
  const t = h * RAD;
  return [L, C * Math.cos(t), C * Math.sin(t)];
}

/** Convert cartesian OKLab to cylindrical OKLCH (hue normalised to 0..360). */
export function oklabToOklch(L, a, b) {
  const C = Math.sqrt(a * a + b * b);
  let h = C < 1e-9 ? 0 : Math.atan2(b, a) * DEG;
  if (h < 0) h += 360;
  return { L, C, h };
}

/** Convert OKLab to linear-light sRGB (Ottosson matrices); output may be out of [0,1]. */
export function oklabToLinearRgb(L, a, b) {
  const l_ = L + 0.3963377774 * a + 0.2158037573 * b;
  const m_ = L - 0.1055613458 * a - 0.0638541728 * b;
  const s_ = L - 0.0894841775 * a - 1.291485548 * b;
  const l = l_ * l_ * l_;
  const m = m_ * m_ * m_;
  const s = s_ * s_ * s_;
  return [
    4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
    -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
    -0.0041960863 * l - 0.7034186147 * m + 1.707614701 * s,
  ];
}

/** Convert linear-light sRGB to OKLab. */
export function linearRgbToOklab(r, g, b) {
  const l = 0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b;
  const m = 0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b;
  const s = 0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b;
  const l_ = Math.cbrt(l);
  const m_ = Math.cbrt(m);
  const s_ = Math.cbrt(s);
  return [
    0.2104542553 * l_ + 0.793617785 * m_ - 0.0040720468 * s_,
    1.9779984951 * l_ - 2.428592205 * m_ + 0.4505937099 * s_,
    0.0259040371 * l_ + 0.7827717662 * m_ - 0.808675766 * s_,
  ];
}

/** Apply the sRGB transfer function to one linear-light channel. */
export function linearToSrgb(c) {
  const s = c < 0 ? -1 : 1;
  const a = Math.abs(c);
  return s * (a <= 0.0031308 ? a * 12.92 : 1.055 * Math.pow(a, 1 / 2.4) - 0.055);
}

/** Invert the sRGB transfer function for one gamma-encoded channel. */
export function srgbToLinear(c) {
  const s = c < 0 ? -1 : 1;
  const a = Math.abs(c);
  return s * (a <= 0.04045 ? a / 12.92 : Math.pow((a + 0.055) / 1.055, 2.4));
}

/** Convert OKLCH to gamma-encoded sRGB floats; result may be out of [0,1] (see gamut.js). */
export function oklchToSrgb(L, C, h) {
  const [ll, aa, bb] = oklchToOklab(L, C, h);
  const lin = oklabToLinearRgb(ll, aa, bb);
  return [linearToSrgb(lin[0]), linearToSrgb(lin[1]), linearToSrgb(lin[2])];
}

/** Convert gamma-encoded sRGB floats to OKLCH. */
export function srgbToOklch(rgb) {
  const lab = linearRgbToOklab(srgbToLinear(rgb[0]), srgbToLinear(rgb[1]), srgbToLinear(rgb[2]));
  return oklabToOklch(lab[0], lab[1], lab[2]);
}

/** Convert gamma-encoded sRGB floats to OKLab. */
export function srgbToOklab(rgb) {
  return linearRgbToOklab(srgbToLinear(rgb[0]), srgbToLinear(rgb[1]), srgbToLinear(rgb[2]));
}

/** Clamp a value into [lo, hi]. */
export function clamp(v, lo, hi) {
  return v < lo ? lo : v > hi ? hi : v;
}

/**
 * Round in-range sRGB floats to 8-bit integers.
 * Only a final safety net: colours must already be in gamut (see gamut.js) — this
 * function must never be relied on to *bring* a colour into gamut.
 */
export function srgbToRgb8(rgb) {
  return [
    Math.round(clamp(rgb[0], 0, 1) * 255),
    Math.round(clamp(rgb[1], 0, 1) * 255),
    Math.round(clamp(rgb[2], 0, 1) * 255),
  ];
}

/** Convert 8-bit channels to gamma-encoded sRGB floats. */
export function rgb8ToSrgb(rgb8) {
  return [rgb8[0] / 255, rgb8[1] / 255, rgb8[2] / 255];
}

/** Convert 8-bit channels to OKLab. */
export function rgb8ToOklab(rgb8) {
  return srgbToOklab(rgb8ToSrgb(rgb8));
}

/** Convert 8-bit channels to OKLCH. */
export function rgb8ToOklch(rgb8) {
  return srgbToOklch(rgb8ToSrgb(rgb8));
}

/** Format 8-bit channels as an uppercase `#RRGGBB` string. */
export function rgb8ToHex(rgb8) {
  return `#${rgb8.map((v) => clamp(Math.round(v), 0, 255).toString(16).padStart(2, '0')).join('').toUpperCase()}`;
}

/** Parse `#RGB`, `#RRGGBB` or bare hex into 8-bit channels; throws on malformed input. */
export function hexToRgb8(hex) {
  let s = String(hex).trim().replace(/^#/, '');
  if (s.length === 3) s = s[0] + s[0] + s[1] + s[1] + s[2] + s[2];
  if (!/^[0-9a-fA-F]{6}$/.test(s)) throw new Error(`hexToRgb8: bad hex "${hex}"`);
  return [parseInt(s.slice(0, 2), 16), parseInt(s.slice(2, 4), 16), parseInt(s.slice(4, 6), 16)];
}

/** Perceptual difference between two OKLab colours, reported x100. */
export function deltaEOK(lab1, lab2) {
  const dL = lab1[0] - lab2[0];
  const da = lab1[1] - lab2[1];
  const db = lab1[2] - lab2[2];
  return 100 * Math.sqrt(dL * dL + da * da + db * db);
}

/** Perceptual difference between two 8-bit colours, reported x100. */
export function deltaERgb8(a, b) {
  return deltaEOK(rgb8ToOklab(a), rgb8ToOklab(b));
}

/** WCAG relative luminance of an 8-bit colour. */
export function relativeLuminance(rgb8) {
  const r = srgbToLinear(rgb8[0] / 255);
  const g = srgbToLinear(rgb8[1] / 255);
  const b = srgbToLinear(rgb8[2] / 255);
  return 0.2126 * r + 0.7152 * g + 0.0722 * b;
}

/** WCAG contrast ratio between two 8-bit colours, in [1, 21]. */
export function contrastRatio(a, b) {
  const la = relativeLuminance(a);
  const lb = relativeLuminance(b);
  const hi = Math.max(la, lb);
  const lo = Math.min(la, lb);
  return (hi + 0.05) / (lo + 0.05);
}

/** Signed shortest-path angular difference from `from` to `to`, in [-180, 180). */
export function hueDelta(from, to) {
  return ((((to - from + 540) % 360) + 360) % 360) - 180;
}

/** Normalise an angle into [0, 360). */
export function normHue(h) {
  return ((h % 360) + 360) % 360;
}

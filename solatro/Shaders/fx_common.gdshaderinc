// fx_common.gdshaderinc — the pieces every Solatro visual effect shares: the pixel grid, the
// noise, the dither, and the ONE definition of the juggling path.
//
// UNIVERSAL RULE (owner, 2026-07-27): no VFX pixel grid ever rotates. The mechanical form of it
// is QUANTIZE FIRST, ROTATE AFTER — snap the sample point to the grid in the quad's own
// world-aligned space, and let every rotation act on the ALREADY-QUANTIZED coordinate. Rotating a
// frame before quantizing rotates the grid and yields diagonal pixels; rotating after moves
// CONTENT through a fixed grid, which is what keeps the pixels square while the thing they depict
// turns. Never rotate UV before fx_quantize.

// --- pixel grid -------------------------------------------------------------------------------
// `grid` = extent / pixel, where pixel is ART UNITS PER FX PIXEL — a free per-material knob, since
// mixed densities across hosts are wanted. Quantize in LOCAL space, never SCREEN_UV: that would
// lock the chunkiness to the window rather than to the art.
vec2 fx_quantize(vec2 uv, vec2 grid) {
	return (floor(uv * grid) + 0.5) / grid;
}

// UV -> local ART COORDINATES, snapped to the effect's pixel grid. Every effect starts here.
//
// ⚠ The Y FLIP is not cosmetic. QuadMesh is a 3-D primitive: its +Y points UP and its UVs run
// downward from that, so a raw (UV - 0.5) * extent hands back a y that is INVERTED against
// Godot's 2-D convention (+y down, up is negative). Without the flip every effect renders
// mirrored — fire hangs off the BOTTOM edge and its tips point down, which is exactly what the
// first snapshot run caught. Doing it once, here, is what lets the effects above reason in plain
// 2-D terms and share contour maths with GDScript.
//
// The flip happens AFTER quantization, so the grid is only mirrored — never rotated, never
// resampled — and the universal quantize-first-rotate-after rule still holds.
vec2 fx_local(vec2 uv, vec2 extent, float pixel) {
	vec2 grid = max(extent / max(pixel, 0.01), vec2(1.0));
	vec2 p = (fx_quantize(uv, grid) - 0.5) * extent;
	return vec2(p.x, -p.y);
}

// --- noise ------------------------------------------------------------------------------------
float fx_hash11(float n) { return fract(sin(n * 127.1) * 43758.5453); }
float fx_hash21(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

// Bilinear value noise over the integer lattice, smoothstepped so the interpolation has no
// creases. Four hashes; this is the unit fx_fbm is built from and the shader's main cost.
float fx_value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 w = f * f * (3.0 - 2.0 * f);
	float a = fx_hash21(i);
	float b = fx_hash21(i + vec2(1.0, 0.0));
	float c = fx_hash21(i + vec2(0.0, 1.0));
	float d = fx_hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, w.x), mix(c, d, w.x), w.y);
}

// Three octaves. Deliberately shallow: this runs per fragment, and callers must gate it behind an
// "is this fragment even lit" test — running it on the empty majority of a quad triples the cost
// of the whole effect for pixels that draw nothing.
float fx_fbm(vec2 p) {
	return fx_value_noise(p) * 0.6
		+ fx_value_noise(p * 2.03) * 0.3
		+ fx_value_noise(p * 4.01) * 0.1;
}

// --- dither -----------------------------------------------------------------------------------
// Bayer 4x4, the same matrix necromii's retro.gdshader uses, so the repo dithers ONE way. Breaks
// band EDGES without softening them, which is what keeps the banding reading as pixel art.
float fx_bayer(vec2 frag) {
	const float pattern[16] = float[16](
		 0.0,  8.0,  2.0, 10.0,
		12.0,  4.0, 14.0,  6.0,
		 3.0, 11.0,  1.0,  9.0,
		15.0,  7.0, 13.0,  5.0);
	int x = int(mod(frag.x, 4.0));
	int y = int(mod(frag.y, 4.0));
	return pattern[y * 4 + x] / 16.0;
}

// --- the juggling path ------------------------------------------------------------------------
// A real cascade is a CLOSED LOOP, not a ball bouncing along one line: a TALL arc carries balls one
// way across the top, and a SHALLOWER return arc carries them back the other way along the bottom.
// Balls are spread evenly around the whole loop, so at any moment roughly half travel each way.
//   f      = share of the cycle spent on the tall arc. 0.5 is even; > 0.5 gives longer hang time,
//            which is what real juggling looks like (the throw takes longer than the carry).
//   h_bot  = the "flat" return — a small upward arc, not a straight line.
// Both halves are MONOTONIC in x, which is what makes fx_nearest_ball's closed-form lookup
// invertible; do not add a timing ease inside a half without checking it stays invertible.
// ONE definition, included by juggle.gdshader AND fire.gdshader, so burning balls physically
// cannot drift off their balls — two copies of this maths is the bug the include exists to
// prevent.
vec2 fx_ball_at(float s, float span, float h_top, float h_bot, float f) {
	float u = fract(s);
	if (u < f) {                                     // tall arc, +x -> -x
		float a = u / f;
		return vec2(span * 0.5 * (1.0 - 2.0 * a), -h_top * sin(a * PI));
	}
	float a = (u - f) / (1.0 - f);                   // shallow return, -x -> +x
	return vec2(span * 0.5 * (2.0 * a - 1.0), -h_bot * sin(a * PI));
}

// Squared distance from `p` to the NEAREST ball, with that ball's index in `id`.
//
// Ball counts are uncapped (owner ruling 5), and a shader loop always needs a constant bound — so
// there is no loop over the count. Both arcs are monotonic in x, so from a fragment's x you can
// RECOVER the cycle position that would put a ball there (one per arc), convert it to a
// real-valued index, and the only balls that can possibly cover this fragment are the two
// bracketing integers. Two arcs x two candidates = FOUR evaluations, O(1) at any count including
// 500 — which is also what lets fire mark INDIVIDUAL balls: the index falls out of the lookup.
//
// `n` may be fractional (a stack count mid-transition), so indices are wrapped into
// [0, ceil(n)) — without that the newest ball ghosts at the seam.
float fx_nearest_ball(vec2 p, float n, float phase, float span, float h_top, float h_bot,
		float f, out float id) {
	float count = max(ceil(n), 1.0);
	float best = 1e9;
	id = 0.0;
	for (int arc = 0; arc < 2; arc++) {
		// Clamp rather than reject: a fragment just past the end of the span is still inside the
		// endpoint ball's radius, and clamping is what keeps the caps of the pattern drawn.
		float ax = clamp((arc == 0) ? (0.5 - p.x / max(span, 1e-4))
									: (0.5 + p.x / max(span, 1e-4)), 0.0, 1.0);
		float s = (arc == 0) ? ax * f : f + ax * (1.0 - f);
		float m = (s - phase) * n;
		for (int j = 0; j < 2; j++) {                // floor and ceil — a fixed 2, not a cap
			float i = mod(floor(m) + float(j), count);
			vec2 d = p - fx_ball_at(phase + i / n, span, h_top, h_bot, f);
			float dd = dot(d, d);
			if (dd < best) { best = dd; id = i; }
		}
	}
	return best;
}

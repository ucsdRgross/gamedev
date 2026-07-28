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
// GRAVITY, as a time warp along the THROW only. `a` is how far through the tall arc in TIME; this
// returns how far along it in SPACE. At g = 1 they are the same (constant speed, the original
// motion). Above 1 the ball covers the ends fast and crawls through the apex — decelerating into
// the top of the throw and accelerating out of it, which is what a thrown ball does.
//
// The curve is |2a-1|^g mirrored about the apex, chosen because it is EXACTLY INVERTIBLE
// (fx_arc_ease_inv, exponent 1/g). That matters more than the exact curve: fx_nearest_ball recovers
// a ball index from a fragment's x in closed form, which needs this mapping inverted analytically.
// The carry (return arc) is deliberately NOT warped — nothing is falling there, it is a hand
// moving a ball back, and warping it made the loop pause twice per cycle.
float fx_arc_ease(float a, float g) {
	if (g <= 1.0) return a;
	float d = 2.0 * a - 1.0;                         // -1 .. 1, zero at the apex
	return 0.5 + 0.5 * sign(d) * pow(abs(d), g);
}

float fx_arc_ease_inv(float e, float g) {
	if (g <= 1.0) return e;
	float d = 2.0 * e - 1.0;
	return 0.5 + 0.5 * sign(d) * pow(abs(d), 1.0 / g);
}

// --- the arc ladder ---------------------------------------------------------------------------
// The loop is no longer one throw and one carry: as the ball count rises, LANES are added between
// them — arcs at evenly spaced heights that the balls also travel (owner 2026-07-28). Two arcs is
// the original pattern exactly.
//
// Every arc starts and ends at (±span/2, 0), because sin() is zero at both ends — which is what
// lets any number of them chain into ONE closed loop with no jump in position. Arcs alternate
// direction (even ones run +x -> -x), so the count must be EVEN or the loop would not close in x.
// Heights descend from the throw to the carry, so a ball sweeps high, then progressively lower, then
// throws again.
const int FX_MAX_ARCS = 8;

// Height of arc `j` of `arcs`: the tall throw at j = 0 down to the flat carry at the last one.
float fx_arc_height(float j, float arcs, float h_top, float h_bot) {
	return mix(h_top, h_bot, j / max(arcs - 1.0, 1.0));
}

// Share of the cycle the TALL arc takes. `f` is that share in the two-arc pattern; it thins as lanes
// are added (x 2/A) so the balls spread over the ladder instead of crowding the top arc — at eight
// arcs the top one still runs slowest, but only slightly. At A = 2 this is exactly `f`.
float fx_arc_top_share(float f, float arcs) {
	return f * 2.0 / max(arcs, 2.0);
}

// Where arc `j` starts in the cycle, and how much of the cycle it spans.
vec2 fx_arc_span(float j, float arcs, float f) {
	float ftop = fx_arc_top_share(f, arcs);
	float rest = (1.0 - ftop) / max(arcs - 1.0, 1.0);
	return (j < 0.5) ? vec2(0.0, ftop) : vec2(ftop + (j - 1.0) * rest, rest);
}

vec2 fx_ball_at(float s, float span, float h_top, float h_bot, float f, float g, float arcs) {
	float A = max(arcs, 2.0);
	float u = fract(s);
	float ftop = fx_arc_top_share(f, A);
	float rest = (1.0 - ftop) / (A - 1.0);
	// Which arc, and how far along it in TIME.
	float j = 0.0;
	float a = u / max(ftop, 1e-5);
	if (u >= ftop) {
		float k = min(floor((u - ftop) / max(rest, 1e-5)), A - 2.0);
		j = k + 1.0;
		a = ((u - ftop) - k * rest) / max(rest, 1e-5);
	}
	// Gravity eases every arc except the CARRY (the lowest): nothing is falling on that one, it is a
	// hand moving a ball back. The eased value drives BOTH axes, so the PATH is untouched and only
	// the speed along it changes — feeding x the ease and y the raw time would bend the arc itself.
	if (j < A - 1.5) a = fx_arc_ease(a, g);
	// Even arcs run +x -> -x, odd ones the reverse, so consecutive arcs chain end to end.
	float sweep = (mod(j, 2.0) < 1.0) ? 1.0 : -1.0;
	return vec2(span * 0.5 * (1.0 - 2.0 * a) * sweep,
			-fx_arc_height(j, A, h_top, h_bot) * sin(a * PI));
}

// Which way ball `i` travels. ALTERNATING (owner 2026-07-28): even indices ride the loop in the
// host's own direction, odd ones mirror it, so neighbouring balls cross rather than trooping round
// together. `dir` is that host's own ±1 — randomised per host, so the FIRST ball goes left on one
// card and right on the next, and two cards juggling the same count never run the same pattern.
float fx_ball_dir(float i, float dir) {
	return (mod(i, 2.0) < 1.0) ? dir : -dir;
}

// THE ball position: index in, ART-UNIT offset from the host's centre out, mirroring included. Call
// sites pass an INDEX rather than a cycle position so the mirror cannot be forgotten at one of them
// — a ball drawn on one side with its flame on the other is exactly the drift this include exists
// to prevent.
vec2 fx_ball_pos(float i, float n, float phase, float span, float h_top, float h_bot, float f,
		float g, float dir, float arcs) {
	vec2 q = fx_ball_at(phase + i / n, span, h_top, h_bot, f, g, arcs);
	q.x *= fx_ball_dir(i, dir);
	return q;
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
		float f, float g, float dir, float arcs, out float id) {
	float count = max(ceil(n), 1.0);
	float A = max(arcs, 2.0);
	float best = 1e9;
	id = 0.0;
	// Still NO loop over the ball count — the work is set by the ARC LADDER, which is bounded by
	// FX_MAX_ARCS: arcs x 2 directions x 2 bracketing integers. Two arcs is 8 evaluations, the
	// eight-arc ceiling is 32, and 5 balls cost exactly what 500 do either way.
	for (int arc = 0; arc < FX_MAX_ARCS; arc++) {
		if (float(arc) >= A) break;
		float j = float(arc);
		vec2 sp = fx_arc_span(j, A, f);              // (start of this arc in the cycle, its share)
		float sweep = (mod(j, 2.0) < 1.0) ? 1.0 : -1.0;
		// Balls run in TWO directions, so the recovery runs once per direction group: un-mirror the
		// fragment into that group's frame first. A ball is always found by the branch matching its
		// OWN direction, so the wrap below cannot lose one however the parity falls.
		for (int m2 = 0; m2 < 2; m2++) {
			float px = p.x * ((m2 == 0) ? dir : -dir) * sweep;
			// Clamp rather than reject: a fragment just past the end of the span is still inside the
			// endpoint ball's radius, and clamping is what keeps the caps of the pattern drawn.
			float ax = clamp(0.5 - px / max(span, 1e-4), 0.0, 1.0);
			// x gives the position along the arc; the gravity ease turns that back into a TIME, which
			// is what the index is spaced in — and the carry is not eased, so it does not invert.
			// Still monotonic, so the two bracketing integers are still the two nearest on this arc.
			float at = (j < A - 1.5) ? fx_arc_ease_inv(ax, g) : ax;
			float m = (sp.x + at * sp.y - phase) * n;
			for (int k = 0; k < 2; k++) {            // floor and ceil — a fixed 2, not a cap
				float i = mod(floor(m) + float(k), count);
				vec2 d = p - fx_ball_pos(i, n, phase, span, h_top, h_bot, f, g, dir, A);
				float dd = dot(d, d);
				if (dd < best) { best = dd; id = i; }
			}
		}
	}
	return best;
}

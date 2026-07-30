// fx_common.gdshaderinc — the pieces every Solatro visual effect shares: the pixel grid, the
// noise, the dither, and the ONE definition of the juggling path.
//
// UNIVERSAL RULE (owner, 2026-07-27): no VFX pixel grid ever rotates. The mechanical form of it
// is QUANTIZE FIRST, ROTATE AFTER — snap the sample point to the grid in the quad's own
// world-aligned space, and let every rotation act on the ALREADY-QUANTIZED coordinate. Rotating a
// frame before quantizing rotates the grid and yields diagonal pixels; rotating after moves
// CONTENT through a fixed grid, which is what keeps the pixels square while the thing they depict
// turns. Never rotate UV before fx_local's quantization.

// --- pixel grid -------------------------------------------------------------------------------
// THE FX PIXEL GRID IS ANCHORED ON THE HOST'S ORIGIN, and that is the whole contract. `pixel` is
// ART UNITS PER FX PIXEL — a free per-material knob, since mixed densities across hosts are wanted.
// Quantize in LOCAL space, never SCREEN_UV: that would lock the chunkiness to the window rather
// than to the art.
//
// ⚠ IT USED TO BE ANCHORED ON THE QUAD'S EDGE, AND THAT WAS A BUG WITH TWO FACES (owner report
// 2026-07-29: *"changing height of fire effect causes effect to jitter left and right, becoming
// misaligned with art and causing subpixel gaps where fire effect and art connects"*).
//
// The old form was `(fx_quantize(uv, extent / pixel) - 0.5) * extent`, whose cell centres land at
// `(k + 0.5) * pixel - extent/2`. The grid's PHASE is therefore `-extent/2 mod pixel` — so:
//  * **any change to the quad's size slides the whole grid sideways.** `FxRequest.reach` is
//    `height + sink`, so dragging `height` in the FX editor swept the lattice left and right under
//    the art. That is the jitter, exactly.
//  * **the grid was never aligned to the ART's pixels in the first place**, except by luck. A card's
//    own texels sit on integers about its origin; the FX grid sat on an offset of half a quad. Hence
//    the sub-pixel seam where flame met host.
// Anchoring on the origin fixes both at once: cell boundaries fall on multiples of `pixel` measured
// from the host's centre, which is exactly where the art's own texels are, and NOTHING about the
// quad can move them. It is also the reason FX_HANDOFF §6a's lever B was rejected ("resizing a live
// quad moves the FX pixel lattice") — that objection is now void.
//
// ⚠ The two forms agree wherever `extent / (2 * pixel)` happens to be a whole number, which is why
// this survived so long: every snapshot panel that used a round extent looked identical.

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
	float cell = max(pixel, 0.01);
	vec2 s = (uv - 0.5) * extent;              // continuous, origin-centred, still pre-flip
	vec2 q = (floor(s / cell) + 0.5) * cell;   // the ONE lattice, anchored on the origin
	return vec2(q.x, -q.y);
}

// THE SAME POINT, NOT QUANTIZED — the fragment's true position in the host's art space.
//
// ⚠ THIS IS NOT FOR DRAWING, and using it to draw would break the universal rule above. It exists
// for one job: an OCCLUSION TEST against art that is NOT on the FX grid. A card's face is a
// Polygon2D, so its edge is a line at SCREEN resolution; testing "am I over the art" at the
// quantized point makes that boundary a staircase with a one-FX-pixel tread, which is the jaggedness
// the owner reported at every rotation (FX_HANDOFF §0c). Testing it here instead lets the art's own
// edge slice the chunky flame pixels diagonally — which is exactly what real occlusion does.
//
// ⚠ It is the WRONG point for a host whose art IS pixel art (a sprite prop, a juggling ball): there
// the drawing lands on the FX grid too, so the quantized test is the one that agrees with it. The
// caller picks, on u_shape.
vec2 fx_local_raw(vec2 uv, vec2 extent) {
	vec2 s = (uv - 0.5) * extent;
	return vec2(s.x, -s.y);                    // the same y flip fx_local applies, for the same reason
}

// Snap an ART-SPACE point onto the SAME pixel lattice fx_local() hands fragments back on.
//
// Why balls need this: a ball's centre moves continuously along its arc, so without this the disc
// test is rasterized at an arbitrary sub-pixel phase — measured on 05c_ball_sphere, the same ball's
// row widths ran 31/44/…/87 down one half and 87/…/34/9 down the other — and the phase changes as it
// travels, so the silhouette wobbles frame to frame. Snapping the CENTRE (owner 2026-07-28: the
// centre only, not the radius) makes every ball rasterize at phase zero: a stable, symmetric circle
// that translates in whole pixels, which is what pixel art does.
//
// ⚠ IT TAKES NO EXTENT ANY MORE, and that is the point. The lattice is anchored on the host's origin,
// so two quads of DIFFERENT sizes centred on the same host share it exactly — which is what lets a
// plume snap to the centre its ball was drawn at. It used to need the partner quad's extent for
// precisely the reason the grid was broken, and `u_partner_extent` went with it. The partner's
// `pixel` still matters, because that is a real per-material choice.
//
// ⚠ The Y FLIP MUST BE UNDONE, and this is not pedantry — it was measured. `fx_local` quantizes and
// THEN negates y, so a point handed back in that frame has to be flipped into the pre-flip frame,
// snapped there, and flipped again. Snapping y with the x formula lands BETWEEN lattice rows: the
// first attempt at this left the ball's row widths running 28/41/…/84 down the top and 84/…/34/15 up
// the bottom, i.e. still not symmetric.
vec2 fx_pixel_snap(vec2 p, float pixel) {
	float cell = max(pixel, 0.01);
	float x = (floor(p.x / cell) + 0.5) * cell;
	float y = -(floor(-p.y / cell) + 0.5) * cell;
	return vec2(x, y);
}

// THE NEAREST CELL *BOUNDARY* CORNER — a whole number of cells from the host's origin on both axes.
//
// This is what lets an INSTANCED effect keep the host's own lattice. An instance quad is placed by
// vertex() at its subject's position, and the fragment then recovers its host-space point as
// `fx_pixel_snap(fx_local_raw(UV, extent) + origin)`. That is exactly `fx_local` of the true
// host-space position — the identity `fx_pixel_snap(fx_local_raw(uv, e), c) == fx_local(uv, e, c)`,
// which holds because fx_local quantizes BEFORE its y flip and this snap undoes the flip to match —
// but ONLY while `origin` is a whole number of cells. Add a half-cell offset instead and every
// instance draws on a lattice shifted half a pixel from its host's, which is the seam this whole
// file exists to prevent.
//
// ⚠ IT IS ALSO WHAT MAKES THE INSTANCE QUAD SAFE TO CLIP AGAINST. Cell centres sit at
// `(k + 0.5) * cell`, so cell BOUNDARIES sit at whole multiples — and a quad centred on one of those
// with a whole number of cells of half-extent has its edges on boundaries too. Every cell it touches
// is therefore covered in FULL. A quad centred on a cell CENTRE would cut its edge cells in half and
// draw a partial chunky pixel, which reads as a torn edge rather than as pixel art.
vec2 fx_cell_round(vec2 p, float pixel) {
	float cell = max(pixel, 0.01);
	return round(p / cell) * cell;
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
// ✅ THE PATH NO LONGER HAS TO BE INVERTIBLE, AND THAT CONSTRAINT IS WORTH KNOWING IS GONE. Both
// halves used to have to be MONOTONIC in x so `fx_nearest_ball` could recover a ball index from a
// fragment's x in closed form, and "do not add a timing ease inside a half without checking it stays
// invertible" was a real rule on anyone tuning this. Instancing answers "which ball" from
// INSTANCE_CUSTOM instead (FX_HANDOFF §0d.6), so the path is now free to be any function of time at
// all — an ease inside a half, a non-monotonic flourish, a hold at the apex.
// ONE definition, included by juggle.gdshader AND fire.gdshader, so burning balls physically
// cannot drift off their balls — two copies of this maths is the bug the include exists to
// prevent.
// GRAVITY, as a time warp along the THROW only. `a` is how far through the tall arc in TIME; this
// returns how far along it in SPACE. At g = 1 they are the same (constant speed, the original
// motion). Above 1 the ball covers the ends fast and crawls through the apex — decelerating into
// the top of the throw and accelerating out of it, which is what a thrown ball does.
//
// The curve is |2a-1|^g mirrored about the apex. ⚠ It was chosen because it is EXACTLY INVERTIBLE —
// there was a matching `fx_arc_ease_inv` at exponent 1/g, and the nearest-ball search needed this
// mapping inverted analytically to turn a fragment's x back into a ball index. **That inverse is
// deleted and the requirement with it** (FX_HANDOFF §0d.6), so this curve is now a free look choice
// rather than the only shape that fit. It is kept because it reads correctly, not because it must be.
// The carry (return arc) is deliberately NOT warped — nothing is falling there, it is a hand
// moving a ball back, and warping it made the loop pause twice per cycle.
float fx_arc_ease(float a, float g) {
	if (g <= 1.0) return a;
	float d = 2.0 * a - 1.0;                         // -1 .. 1, zero at the apex
	return 0.5 + 0.5 * sign(d) * pow(abs(d), g);
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

// ONE GRAVITY FOR THE WHOLE LADDER (owner report 2026-07-29: *"balls have inconsistent speeds
// between different arcs such that it looks like they are all under different gravity"*).
//
// A ball thrown to height h is in the air for a time proportional to sqrt(h). The arcs used to take
// NEARLY EQUAL shares of the cycle — the top arc `f*2/A` and every other one an equal slice of the
// rest — so a ball crossed the tall throw and the flat carry in about the same time, which is only
// possible under two different gravities. Weighting each arc by sqrt of its own height is what makes
// one gravity carry the whole ladder.
//
// `f` survives as the HANG-TIME BIAS on the throw: 0.5 is the purely physical share, above it the
// throw is given more of the cycle than physics alone would (which is what real juggling looks
// like, and what the knob promised before).
float fx_arc_weight(float j, float arcs, float h_top, float h_bot, float f) {
	float w = sqrt(max(fx_arc_height(j, arcs, h_top, h_bot), 1e-4));
	return (j < 0.5) ? w * (max(f, 0.05) / 0.5) : w;
}

// THE LADDER, RESOLVED ONCE PER FRAGMENT — where every arc starts in the cycle and how much of the
// cycle it owns. `start[k]` and `share[k]` are zero past the live arc count.
//
// ⚠ THIS EXISTS FOR ONE REASON: EVERY NUMBER IN IT DEPENDS ONLY ON UNIFORMS. Nothing about the
// ladder varies across a quad, yet the shape of the old code re-derived it constantly —
// `fx_arc_span` summed the whole ladder and then walked it, `fx_ball_at` did the same, and
// `fx_nearest_ball` called the first once per arc and the second twice per arc. At the 8-arc ceiling
// that was ~384 `fx_arc_weight` evaluations per fragment, each carrying a `sqrt`, plus the `pow` in
// the ease — pure overhead with no visual contribution (FX_HANDOFF §1b.1, measured 2026-07-30).
// Filling this table costs 8 of them, and every lookup below reads it instead.
//
// The shares are NORMALIZED here, so callers never divide by the total again.
void fx_arc_ladder(float arcs, float h_top, float h_bot, float f,
		out float start[FX_MAX_ARCS], out float share[FX_MAX_ARCS]) {
	float total = 0.0;
	for (int k = 0; k < FX_MAX_ARCS; k++) {
		share[k] = (float(k) < arcs) ? fx_arc_weight(float(k), arcs, h_top, h_bot, f) : 0.0;
		total += share[k];
	}
	total = max(total, 1e-5);
	float acc = 0.0;
	for (int k = 0; k < FX_MAX_ARCS; k++) {
		share[k] /= total;
		start[k] = acc;
		acc += share[k];
	}
}

// Where a ball sitting at cycle position `s` is, given an already-resolved ladder. The walk that
// finds which arc `s` falls on is now pure comparisons against `start`/`share` — no weights, no
// sqrt — which is the whole of the saving.
vec2 fx_ball_at_ladder(float s, float span, float h_top, float h_bot, float g, float arcs,
		float start[FX_MAX_ARCS], float share[FX_MAX_ARCS]) {
	float A = max(arcs, 2.0);
	float u = fract(s);
	float j = A - 1.0;
	float a = 0.0;
	for (int k = 0; k < FX_MAX_ARCS; k++) {
		if (float(k) >= A) break;
		if (u < start[k] + share[k] || float(k) >= A - 1.0) {
			j = float(k);
			a = (u - start[k]) / max(share[k], 1e-5);
			break;
		}
	}
	a = clamp(a, 0.0, 1.0);
	// The gravity ease is applied to EVERY arc, the carry included (2026-07-29). Exempting the
	// lowest one gave it a visibly different character from its neighbours — the thing that read as
	// "each arc has its own gravity". The eased value drives BOTH axes, so the PATH is untouched and
	// only the speed along it changes; feeding x the ease and y the raw time would bend the arc.
	a = fx_arc_ease(a, g);
	// Even arcs run +x -> -x, odd ones the reverse, so consecutive arcs chain end to end.
	float sweep = (mod(j, 2.0) < 1.0) ? 1.0 : -1.0;
	return vec2(span * 0.5 * (1.0 - 2.0 * a) * sweep,
			-fx_arc_height(j, A, h_top, h_bot) * sin(a * PI));
}

// Which way ball `i` travels: the HOST's own ±1, the same for every ball on that host. `dir` is
// randomised per host, so the pattern runs one way on one card and the other way on the next, and
// two cards juggling the same count never look like one pattern.
//
// THE ball position: index in, ART-UNIT offset from the host's centre out, mirroring included. Call
// sites pass an INDEX rather than a cycle position so the mirror cannot be forgotten at one of them
// — a ball drawn on one side with its flame on the other is exactly the drift this include exists
// to prevent.
//
// ⚠ DO NOT REINTRODUCE A PER-BALL MIRROR (`i` even -> dir, odd -> -dir). It was here for the
// two-arc pattern, where every ball rode ONE loop and would otherwise troop round in a conga line.
// The ARC LADDER already alternates sweep direction per arc — and consecutive balls sit in
// consecutive arcs whenever the count is near the arc count — so the two alternations CANCEL and
// every ball ends up moving the same way, leaving half the pattern empty. Measured 2026-07-28 at
// the counts where n == arcs (2, 4, 6 — the owner's "below 10"): 2/2, 4/4 and 6/6 balls travelling
// in one direction with the mirror, an even split without it. Crossing now comes from the ladder,
// which is where it belongs, so the whole host turns ONE way and `i` does not enter the direction
// at all — `FxJuggle.ball_pos` multiplies by the same bare `dir`, and this used to be wrapped in an
// identity `fx_ball_dir(i, dir)` that made the two sides look asymmetric for no reason.
vec2 fx_ball_pos_ladder(float i, float n, float phase, float span, float h_top, float h_bot,
		float g, float dir, float arcs, float start[FX_MAX_ARCS], float share[FX_MAX_ARCS]) {
	vec2 q = fx_ball_at_ladder(phase + i / n, span, h_top, h_bot, g, arcs, start, share);
	q.x *= dir;
	return q;
}

// ONE BALL'S POSITION, LADDER AND ALL — the VERTEX-stage entry point of the instanced juggling
// layer, and the only place either shader asks where a ball is.
//
// ⚠ A LADDER-FREE WRAPPER LIKE THIS WAS DELETED ON 2026-07-29 AND THIS IS NOT A REGRESSION — read
// this before "fixing" it back. That one was called once per FRAGMENT by both shaders, to re-derive a
// centre `fx_nearest_ball` had already computed: a second full `fx_arc_ladder` (8 `sqrt` plus a
// normalizing pass) and a second walk, per fragment, for a number the caller already held. It was
// deleted so it could not come back to the FRAGMENT stage, and it has not.
//
// This is the vertex stage, where the arithmetic is the opposite shape. One instance is one ball, so
// the index arrives in INSTANCE_CUSTOM and the position is wanted exactly ONCE per vertex — four
// evaluations per ball per frame, against the hundreds of thousands of fragments the closed-form
// nearest-ball search used to run over. There is no lookup left to piggyback on, because there is no
// lookup: knowing WHICH ball a fragment belongs to is what instancing answers for free, and that was
// the entire cost of this layer (FX_HANDOFF §0d.5).
vec2 fx_ball_of(float i, float n, float phase, float span, float h_top, float h_bot,
		float f, float g, float dir, float arcs) {
	float A = max(arcs, 2.0);
	float start[FX_MAX_ARCS];
	float share[FX_MAX_ARCS];
	fx_arc_ladder(A, h_top, h_bot, f, start, share);
	return fx_ball_pos_ladder(i, n, phase, span, h_top, h_bot, g, dir, A, start, share);
}

// ⚠ `fx_balls_near` AND `fx_nearest_ball` ARE GONE, AND THE WHOLE POINT IS THAT NOTHING REPLACED
// THEM (2026-07-29 — FX_HANDOFF §0d.6). They were the fragment stage answering "which ball, if any,
// am I part of": one box test to reject the empty majority of a pattern-sized quad, then a
// closed-form inversion of the arc ladder — 8 `sqrt`, then per arc a `pow` and two candidate
// positions each carrying another `pow` and a `sin` — for every fragment that survived the box.
//
// **That question is what INSTANCING answers for nothing.** One instance per ball means the index
// arrives in INSTANCE_CUSTOM, the position is computed once per vertex (`fx_ball_of`), and a
// fragment's ball is simply the instance it belongs to. Fitting the published measurements
// (FX_HANDOFF §0d.5) put the cost of this layer at guard-box area x cost of one of these calls, to
// within 4 % on both quads — so removing the call and shrinking the area from the pattern's box to
// each ball's own box attacks both factors of the only product that mattered.
//
// What went with them, and none of it is a loss:
//  * `lit_only` and the `u_ball_fire` LEVELS TEXTURE. A plume instance exists only for a ball that is
//    actually alight and carries its own level in INSTANCE_CUSTOM.y, so the bug the flag fixed
//    ("a lit ball's plume disappears and comes back", §2) cannot be expressed any more: no fragment
//    ever resolves a ball other than its own, lit or not.
//  * The nearest-ball TIE-BREAK. Overlapping balls used to be resolved by distance; they are resolved
//    by DRAW ORDER now, and FxJuggle sorts the instances so the highest-level ball draws last
//    (owner, 2026-07-29: *"if overlapping, ball with highest stacks win"*).

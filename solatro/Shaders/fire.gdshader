shader_type canvas_item;
render_mode blend_mix, unshaded;
// Pixelated fire as a decorator over a SHAPE — RAISE THE MASK (owner design, 2026-07-30).
//
// THE MODEL: the fire region is the art's MASK RAISED by an arch-shaped amount, minus the mask.
//
//     floor(x) = the surface this column stands on, eroded by `sink`   — ONE down-march
//     top(x)   = floor(x) - h * dome(u(x))                             — the ogee, art y up = minus
//     fire(p)  = top(p.x) <= p.y <= floor(p.x)
//
// What that buys, and each line is a bug the per-column CONTOUR model it replaces actually had:
//  * EVERY upward-facing surface burns, anywhere in the art. The test is local and vertical, so the
//    hoop's inner-bottom arc — the inside of the hole, which faces up — lights from the same code
//    that lights the outer top arc. A contour can only ever return the topmost surface in a column,
//    which is why "the top half of the image" was never a definition of where fire sits.
//  * ONE TENDRIL PER SURFACE, and it falls out rather than being arranged: a cell spanning the ring
//    holds the outer arc high up and the inner arc far below, and each column simply grows a flame
//    on the surface it has (owner: *"1 tendril on top and 1 on bottom"*).
//  * NO ENORMOUS FLAME, structurally: a flame is exactly `h` long in every column on every shape, so
//    one can never leap the hole in a ring.
//  * TIPS POINT UP BY CONSTRUCTION — because the march is WORLD-down, not because of any per-shape
//    branch (owner ruling 1). A spinning knife rotates only the mask LOOKUP.
//  * Shape following is IN the shader, so nothing is baked at _ready and nothing can go stale when a
//    host turns.
//
// ⚠ THE ANCHOR AND THE DRAPE ARE DELIBERATELY ABSENT, and this is the owner's pre-ruled fallback
// rather than an omission (FX_HANDOFF §1.4a: *"If not possible without performance drop, then dont
// do engulf trick with height checking and just stick with mask shifting to find bases"*). The
// design called for the arch to be anchored ONCE per cell, at the highest surface in it, which needs
// three more down-marches — and those marches have to start above the whole shape, because an anchor
// that depended on the fragment's own height would differ down a column and tear the flame.
//
// MEASURED, 20 burning hosts, Intel UHD, Tests/Visual/fx_cost.tscn (2026-07-30):
//     hoop   0.67 ms shipped contour ->  1.21 ms mask shift -> 22.52 ms with the anchor
//     card   1.13 ms                 ->  1.53 ms            ->  1.81 ms
//     knife  0.64 ms                 ->  0.36 ms            ->  0.62 ms
// The anchor costs 21 ms on the one shape it exists for — more than a whole 60 fps frame, for 20
// props and nothing else on screen. So it is dropped WHOLE, not approximated at reduced sample
// counts, which is what produced the two builds the owner rejected. What goes with it is ENGULF: a
// flame no longer drapes down to a lower surface in its own cell. Every other §1 property survives,
// because every one of them comes from the mask and not from the anchor.
//
// There is no ball special case (owner 2026-07-30: *"fire effect should be unified and identical in
// how it treats everything"*). A ball is a SHAPE whose mask is the union of the discs; the march,
// the comb, the ogee, the onion shells and the ramp above it are literally the same code for a card,
// a knife, a hoop and a ball.
//
// This shader is NEVER a material on the host. A ShaderMaterial on a CardVisual polygon is clipped
// to that polygon's UV rect (fire could not rise above the card) and inherits the card's rotation,
// offset spin and basis3d squash (flames would tumble and flatten). It is its own quad.

#include "res://Shaders/fx_common.gdshaderinc"

// Shape kinds. Mirrored by FxAttachment.Shape — the mapping is asserted by the FX ATTACHMENT suite,
// since GDScript and GLSL cannot share an enum. A card and a blade are NOT both boxes any more: a
// blade is a SPRITE and answers with its own alpha, which is what lets fire find the real drawing.
const int SHAPE_BOX = 0;
const int SHAPE_RADII = 1;
const int SHAPE_SPRITE = 2;
const int SHAPE_BALLS = 3;

// Number of entries in the deformable-card radius table. 32, NOT 16: the star rig goes up to 16
// arms, and 16 samples cannot represent 16 alternating features (Nyquist) — at 16 the arms either
// smooth into a blob or beat against the grid depending on phase.
const int RADII = 32;

// What mask_level answers. A value >= 0 is a SOLID surface and the value itself is the fire level it
// emits; MASK_EMPTY is no art at all.
//
// ⚠ THERE IS NO LONGER A "SOLID BUT DARK" ANSWER (2026-07-30). An unlit ball used to return one, so
// that it occluded without lighting (owner ruling 3) — and that is exactly what made a LIT ball's
// plume disappear and come back (FX_HANDOFF §2): the unlit ball won the one-per-fragment lookup, the
// march reported "solid, emits nothing", and the fragment was forced dark. Fire now resolves the
// nearest LIT ball (`lit_only` in fx_nearest_ball), so an unlit ball is never the answer here at
// all. Ruling 3 still holds where it matters — an unlit ball emits nothing, and is dark because of
// it — and what was given up is only its occlusion of a plume passing behind it, which the owner
// pre-ruled as the cheaper of the two.
const float MASK_EMPTY = -1.0;

bool mask_solid(float m) { return m >= 0.0; }
// A march that found nothing. Larger than any quad, so every comparison against it fails.
const float NO_SURFACE = 1e9;
// The loop bound the march needs (GLSL cannot loop to a runtime count). The march is bounded in ART
// UNITS by the flame's own height and breaks out long before this — at the shipped numbers that is
// ~21 steps on a card and ~41 on a prop at 200 stacks — so this is only the compiler's constant.
const int MARCH_MAX = 64;

// ===== LIVE — pushed every frame by FxAttachment ==============================================
uniform int u_shape = 0;
uniform int u_half = 0;              // split props: 0 whole, 1 back arc only, 2 front arc only
uniform vec2 u_extent = vec2(64.0);  // the quad's size in art units; UV maps across exactly this
// The BALL quad's lattice (SHAPE_BALLS only), so a plume snaps to the centre its ball was drawn at
// rather than to this quad's own grid. Pushed from FxRequest.partner_id / partner_pixel.
uniform vec2 u_partner_extent = vec2(64.0);
uniform float u_partner_pixel = 1.0;
uniform vec2 u_body = vec2(38.0, 50.0);
uniform float u_shape_rot = 0.0;
uniform float u_time = 0.0;          // pacing-aware, script-driven — NEVER the built-in TIME
uniform float u_seed = 0.0;
uniform float u_count = 0.0;         // tendrils. A FLOAT, and uncapped: see u_count's use below
uniform float u_level = 0.0;         // normalized stack level -> the ramp's v axis
uniform float u_intensity = 1.0;     // surplus stacks push heat UP the ramp instead of adding
                                     // tendrils (owner ruling 4)
uniform vec2 u_lag = vec2(0.0);      // the host's motion, normalized — the cape
uniform float u_radii[RADII];        // deformable card silhouette
// SHAPE_BALLS only: the width of ONE ball's flame, in art units — a ball's DIAMETER, so a plume is
// exactly as wide as the ball it stands on.
//
// ⚠ It is NOT a comb pitch any more (2026-07-30). It used to make the comb TILE the quad at ball
// pitch, on the reasoning that each ball would then catch roughly one cell — but a comb is anchored
// to the QUAD and a ball MOVES, so which cell a ball caught changed as it flew, and cells past the
// first zeroed the flame outright (see `tendril`). A ball's flame is anchored to the ball now, and
// this is only how wide it is. Every other shape combs its own silhouette and leaves this at 0.
uniform float u_emit_width = 0.0;
// SPRITE kinds: the art's own sheet, and the frame to read out of it. This is what retires the
// baked per-column profile — a mask sampled live cannot go stale when its host turns, and it is the
// only representation that knows a ring has a HOLE in it.
uniform sampler2D u_art : filter_nearest, repeat_disable, hint_default_transparent;
uniform vec4 u_art_rect = vec4(0.0, 0.0, 1.0, 1.0);   // the frame, in normalized sheet UV
uniform vec2 u_art_size = vec2(32.0);                 // the size that frame is DRAWN at, centred
// -1 while the host's art is MIRRORED (PropVisual.face_travel). The mask is the art, so it mirrors
// with it — a blade heading right would otherwise emit off the outline it no longer has.
uniform float u_art_flip = 1.0;
// SHAPE_BALLS only. Shared with juggle.gdshader from ONE computation in FxJuggle, so a plume can
// never trail its ball by a frame.
uniform float u_ball_count = 1.0;
uniform float u_phase = 0.0;
uniform float u_span = 30.0;
uniform float u_arc_height = 37.5;
uniform float u_return_height = 6.0;
uniform float u_ball_radius = 3.0;
// One texel per ball, r = that ball's OWN normalized fire level (owner ruling 21: a ball's flame
// is the ball's effect at the level it was spawned with, never the card's Burning). Uploaded on
// status change, never per frame.
uniform sampler2D u_ball_fire : filter_nearest, repeat_disable, hint_default_black;

// ===== STATIC — written once from FxStyle ======================================================
uniform float u_pixel = 1.0;
uniform float u_skew : hint_range(0.0, 1.0) = 0.15;
uniform float u_inner_alpha : hint_range(0.0, 1.0) = 0.5;
uniform float u_height = 14.0;
uniform float u_height_var : hint_range(0.0, 1.0) = 0.45;
uniform float u_base_width : hint_range(0.1, 2.0) = 1.0;
// The ogee arch profile (see tendril()). point: lower = sharper tip. flare: lower = the
// shoulders bulge further out before the curve turns in toward the point.
uniform float u_ogee_point : hint_range(0.2, 3.0) = 1.0;
uniform float u_ogee_flare : hint_range(0.2, 3.0) = 0.35;
// The ONION shells (see tendril()): power shapes them (< 1 fattens the core, > 1 thins it to a
// filament), rise is the WEAK height term that cools the tip. Height must never be the main term —
// that is what stacked the colours in rows instead of wrapping them.
uniform float u_onion_power : hint_range(0.25, 4.0) = 1.0;
uniform float u_onion_rise : hint_range(0.0, 1.0) = 0.35;
// How far INTO the art the fire is allowed, in art units — an EROSION of the mask, not an offset
// added to a contour: the base is the surface plus this, and a fragment already inside the art is
// lit only while it is within this of the surface above it.
uniform float u_sink = 2.0;
uniform int u_merge = 0;
uniform float u_sway_amp = 0.35;
uniform float u_sway_speed = 4.0;
uniform float u_flicker_speed = 1.7;
uniform float u_wave_amp = 0.0;
uniform float u_wave_freq = 0.35;
uniform float u_wave_speed = 6.0;
uniform float u_desync : hint_range(0.0, 1.0) = 1.0;
uniform float u_pulse_amp = 0.0;
uniform float u_pulse_speed = 2.0;
uniform float u_lag_amount : hint_range(0.0, 2.0) = 1.0;
uniform vec2 u_wind = vec2(0.0);
uniform float u_noise_amp = 0.5;
uniform float u_noise_scale = 0.35;
uniform float u_noise_scroll = 18.0;
uniform float u_top_fraction : hint_range(0.2, 0.8) = 0.6;
// The ball path's gravity ease. Read here as well as in juggle.gdshader — the plume quad and the
// ball quad MUST agree on the timing or a flame slides off its ball; FxStyle pushes one value to
// both, exactly as it does for the span and the arc heights.
uniform float u_ball_gravity : hint_range(1.0, 3.0) = 1.0;
// The host's ±1 base direction — same source, same reason: the plume has to be mirrored exactly as
// its ball is (see fx_ball_pos).
uniform float u_ball_dir = 1.0;
// How many arcs the ball loop is made of. Same source again: the plume has to be on the same ladder
// as its ball, or a lit ball's flame ends up hanging on a lane the ball is not on.
uniform float u_ball_arcs = 2.0;
// The WHOLE palette: u = heat, v = stack level. Colour-per-stack is one texture coordinate
// (owner ruling 14), the band count is however many hard columns the image has rather than a
// fixed 4, and frost or poison is a different .tres rather than a code path.
uniform sampler2D u_ramp : source_color, filter_nearest, repeat_disable;
uniform float u_brightness = 1.0;
uniform float u_opacity = 1.0;
uniform float u_dither = 0.0;

// ===== THE MASK =================================================================================

// Deformable-card reach along the ray at angle `a` from straight up, in the ART's own frame (the
// caller has already rotated the lookup, so this never touches u_shape_rot).
float radii_reach(float a) {
	float t = (a / TAU + 1.0) * float(RADII);
	int i0 = int(floor(t)) % RADII;
	return mix(u_radii[i0], u_radii[(i0 + 1) % RADII], fract(t));
}

// THE MASK: the LEVEL of the surface at `p`, or MASK_EMPTY where there is no art.
//
// One function, a branch per shape, so adding a prop kind is one branch and touches nothing else.
// Analytic for the kinds that have it; an ALPHA SAMPLE of the sheet for sprite kinds, which is what
// lets a mask know about the hoop's hole and retires the baked per-column profile.
//
// ⚠ ROTATION ROTATES THE LOOKUP, NEVER THE PIXEL GRID (universal rule): `p` arrives already
// quantized in the quad's world-aligned space and only the lookup turns into the art's frame.
//
// `ball` / `ball_level` are the fragment's own nearest ball, resolved ONCE per fragment by the
// caller and passed down. The closed-form ball lookup is by far the most expensive thing in this
// file, and a march never leaves its column, so re-running it at every step of a march would cost
// more than the whole rest of the shader. Ignored by every other kind.
float mask_level(vec2 p, vec2 ball, float ball_level) {
	if (u_shape == SHAPE_BALLS) {
		vec2 d = p - ball;
		if (dot(d, d) > u_ball_radius * u_ball_radius) return MASK_EMPTY;
		return ball_level;
	}
	float c = cos(u_shape_rot);
	float s = sin(u_shape_rot);
	vec2 q = vec2(p.x * c + p.y * s, -p.x * s + p.y * c);
	if (u_shape == SHAPE_BOX) {
		vec2 h = u_body * 0.5;
		return (abs(q.x) <= h.x && abs(q.y) <= h.y) ? u_level : MASK_EMPTY;
	}
	if (u_shape == SHAPE_RADII) {
		return (length(q) <= radii_reach(atan(q.x, -q.y))) ? u_level : MASK_EMPTY;
	}
	// SPRITE: the drawing's own alpha, read at the point the art is actually drawn at. `u_art_size`
	// is the WHOLE frame centred on the host's origin — deliberately not the tight body box, which
	// is not centred on it and would slide the mask sideways.
	vec2 t = vec2(q.x * u_art_flip, q.y) / max(u_art_size, vec2(1e-4)) + 0.5;
	if (t.x < 0.0 || t.x > 1.0 || t.y < 0.0 || t.y > 1.0) return MASK_EMPTY;
	float a = texture(u_art, u_art_rect.xy + t * u_art_rect.zw).a;
	return (a > 0.5) ? u_level : MASK_EMPTY;
}

// Half the art's WORLD-ALIGNED width at the live rotation — the span the comb divides.
//
// Not `u_body.x * 0.5`: that is the UNROTATED width, so a card turned 90 degrees (which
// anim_spin_start does every revolution) had its 50-unit-wide silhouette combed across only 38
// units, leaving a third of the top edge bare and the flames off-centre. Caught by the rotation
// snapshot. This is the one thing about the comb that a uniform cannot carry, which is why
// `u_emit_width` is an override rather than the only source.
float body_half_width() {
	vec2 h = u_body * 0.5;
	return h.x * abs(cos(u_shape_rot)) + h.y * abs(sin(u_shape_rot));
}

// The body's WORLD-ALIGNED half-extent at the live rotation — `body_half_width` on both axes.
vec2 body_bound() {
	vec2 h = u_body * 0.5;
	float c = abs(cos(u_shape_rot));
	float s = abs(sin(u_shape_rot));
	return vec2(h.x * c + h.y * s, h.x * s + h.y * c);
}

// THE EMPTY MAJORITY, REJECTED FIRST — `fx_balls_near`'s lever (FX_HANDOFF §1b.2), now for every
// other shape, and it is the largest single saving in this file.
//
// ⚠ THE QUAD IS SIZED FOR THE WORST CASE AND THE FRAGMENT IS NOT. A quad is the host's CIRCUMSCRIBED
// bound plus reach on all four sides — 84.8 x 84.8 for a 38x50 card, because a card CAN spin — so a
// card that is not currently turned leaves most of its quad empty, and every one of those empty
// fragments still walked the whole ~20-lookup march to find nothing. Below the body nothing can burn
// at all, because the march only ever walks DOWN.
//
// It CANNOT change a pixel: every fragment it rejects is one where `surface_below` could not have
// found a surface within reach anyway. That is the whole reason to prefer this to shrinking the quad
// — shrinking moves the pixel lattice, and this does not touch it.
//
// ⚠ CONSERVATIVE ON EVERY AXIS, deliberately. `tall` is the tallest a flame can be — `height` at full
// `height_var`, plus the erosion its base sinks by — and it is the SIDEWAYS margin too, because sway,
// fan and the cape all push a tip out of its own cell and none of them can push it further sideways
// than the flame is long. Tightening this is how you clip a flame off the edge of a card.
bool body_near(vec2 p) {
	vec2 b = body_bound();
	float tall = u_height * (1.0 + u_height_var) + max(u_sink, 0.0);
	return abs(p.x) <= b.x + tall && p.y <= b.y && p.y >= -b.y - tall;
}

// THE DOWN-MARCH. Walk DOWN from `p` in FX-pixel steps until the mask is hit, and return the top of
// that surface run (art y is positive DOWN), or NO_SURFACE within `reach`. `level` comes back as
// what that surface emits.
//
// ⚠ DOWN IS WORLD-DOWN, ALWAYS, independent of the host's rotation. That is the whole of why a
// spinning knife's flames stay upright (owner ruling 1), and it is free: `p` is already in the
// world-aligned quad space, so only the mask LOOKUP rotates.
//
// A fragment already INSIDE the art walks UP instead, at most `u_sink` far: that is what `sink`
// means now — an EROSION of the mask — so fire reaches exactly `sink` into the art and no further,
// rather than filling every solid pixel below the surface.
float surface_below(vec2 p, float reach, vec2 ball, float ball_level, out float level) {
	level = MASK_EMPTY;
	float step = max(u_pixel, 0.05);
	float here = mask_level(p, ball, ball_level);
	if (mask_solid(here)) {
		int up = int(ceil(max(u_sink, 0.0) / step));
		for (int i = 1; i <= MARCH_MAX; i++) {
			if (i > up) break;
			if (!mask_solid(mask_level(vec2(p.x, p.y - float(i) * step), ball, ball_level))) {
				level = here;
				return p.y - float(i - 1) * step;
			}
		}
		return NO_SURFACE;
	}
	int n = int(ceil(max(reach, 0.0) / step));
	for (int i = 1; i <= MARCH_MAX; i++) {
		if (i > n) break;
		float y = p.y + float(i) * step;
		float l = mask_level(vec2(p.x, y), ball, ball_level);
		if (mask_solid(l)) {
			level = l;
			return y;
		}
	}
	return NO_SURFACE;
}

// ===== THE CROWN ================================================================================

// Heat contributed by one tendril at (x, rise). `id` places it in the comb and desyncs it; `pitch`
// is the cell width and `xc` its centre; `grow` is how much of its full height it has grown to; and
// `fan` is how far OUT it stands, normalized to [-1, 1], which is the only thing the outward skew
// reads. All four are resolved by the caller, so the comb has exactly one definition and a ball —
// whose flame is anchored to the ball rather than to a cell of a comb — goes through the same code.
//
// ⚠ `grow` AND `fan` USED TO BE DERIVED HERE, FROM `cells` AND `w`, AND BOTH WERE WRONG FOR A BALL.
// A ball's comb is TILED — `cells` is 1 because a cell is one ball wide, not because there is one
// tendril — so `(id >= floor(cells)) ? fract(cells) : 1.0` returned fract(1.0) = 0 for every cell
// past the first, and every ball right of the quad's centre had its flame's height multiplied by
// ZERO. That is the whole of the owner's *"fire on balls sometimes disappears, then reappears
// later"* (FX_HANDOFF §2): a ball's plume died the moment it travelled right of centre and came back
// when it crossed to the left. `fan` was `xc / (w * 0.5)` with `w` the emit width, which for a ball
// is one DIAMETER — so a ball 15 units out was fanned as if it stood 11 cell-widths off centre and
// its tip was flung clean outside its own arch.
float tendril(float id, float grow, float pitch, float xc, float fan, float x, float rise) {
	float half_w = pitch * 0.5 * u_base_width;
	// TWO independent randoms per tendril, both folded through the HOST's seed so no two hosts run
	// the same crown even on identical parameters (owner 2026-07-28). `ph` offsets its phase; `rate`
	// varies its sway SPEED — a shared speed makes a row of tendrils read as one sheet sliding side
	// to side however their phases are scattered, which is not "swaying in different directions".
	float ph = fx_hash11(id + u_seed) * TAU * u_desync;
	float rate = mix(1.0, 0.55 + 0.9 * fx_hash11(id * 7.31 + u_seed + 41.0), u_desync);

	float h = u_height
		* mix(1.0, 0.55 + 0.45 * fx_value_noise(vec2(id * 3.7 + u_seed,
				u_time * u_flicker_speed)), u_height_var)
		// The whole-effect breath carries the HOST's phase too, or every burning card on the board
		// breathes in unison.
		* (1.0 + u_pulse_amp * sin(u_time * u_pulse_speed + fx_hash11(u_seed) * TAU))
		* grow;
	if (rise >= h) return 0.0;
	float k = clamp(rise / h, 0.0, 1.0);              // 0 at the base, 1 at the tip

	// Everything that displaces the spine grows with height, so the base stays planted on the body
	// and only the TIP moves: skew (systematic outward fan — ruling 1's "angle skew as spread"),
	// sway (oscillating drift), wave (snaking), wind, and the motion lag.
	float drift = u_skew * fan * k
		+ sin(u_time * u_sway_speed * rate + ph) * u_sway_amp * k * k
		+ sin(rise * u_wave_freq - u_time * u_wave_speed + ph) * u_wave_amp * k
		+ (u_wind.x + u_lag.x * u_lag_amount) * k * k;

	// NOT clamped to [-1, 1]: the dome below already falls to zero outside the cell, and clamping
	// here made u_merge a silent NO-OP — a neighbour tendril is by definition sampled at |u| > 1,
	// so clamping pinned every neighbour to the cell edge where the dome is exactly 0 and the
	// 3-tap max could never contribute anything. Caught by the fire-ladder snapshot: merge was on
	// at 40 stacks and changed nothing.
	float u = (x - xc - drift * half_w) / half_w;

	// OGEE — the flame's TOP falls to 0 at its cell edges, so its BASE spans the full cell and the
	// outline rises into ONE pointed tip. This is what keeps a single stack a flame rather than a
	// pole, AND what makes a 300-stack card degrade into a sheet of flame instead of noise.
	//
	// The profile is an OGEE ARCH (owner, 2026-07-27): near-vertical where it springs off the
	// body, bulging out through an inflection, then curving back in to a point — NOT a dome. It is
	// derived by inverting the arch's own half-width, w(k) = (1 - k^a)^b at normalized height k:
	// solving for k gives k = (1 - |u|^(1/b))^(1/a), which is the height of the outline above any
	// horizontal position. So the two exponents ARE the arch: u_ogee_point (= 1/b) sharpens or
	// blunts the tip, u_ogee_flare (= 1/a) controls how far the shoulders bulge before turning in.
	// A parabola (the old dome) is the degenerate case with no inflection at all.
	float dome = pow(max(1.0 - pow(abs(u), u_ogee_point), 0.0), u_ogee_flare);
	if (rise >= h * dome) return 0.0;

	// ONION SHELLS, not stacked rows (owner 2026-07-27: "each layer wraps around the other, like
	// actual candle lights"). Heat is how far ACROSS the flame this fragment is, measured against
	// the flame's own half-width AT THIS HEIGHT — so every iso-heat contour is a scaled copy of the
	// outline, hottest along the core and coolest at the rim, exactly like a candle. Height is only
	// a weak secondary term (u_onion_rise); making heat a function of height ALONE is what produced
	// horizontal stripes stacked up the flame.
	//
	// The half-width comes from inverting the same ogee the outline uses: the outline is
	// dome(u) = (1 - |u|^p)^f, so its half-width at normalized height k is (1 - k^(1/f))^(1/p).
	// One arch, read two ways — the shape cannot drift from its own shells.
	float half_at_k = pow(max(1.0 - pow(k, 1.0 / max(u_ogee_flare, 1e-3)), 0.0),
			1.0 / max(u_ogee_point, 1e-3));
	float across = clamp(abs(u) / max(half_at_k, 1e-3), 0.0, 1.0);
	// u_onion_power shapes the shells: below 1 fattens the core, above 1 thins it to a filament.
	return pow(1.0 - across, u_onion_power) * (1.0 - u_onion_rise * k);
}

// One tendril of the comb, standing on whatever its column is over.
//
// `floor_y` is this COLUMN's base, already found and eroded by the caller — it depends on the
// fragment alone, never on the cell, so it is computed ONCE per fragment rather than once per
// tendril (which would otherwise triple with `merge` on).
//
// So the arch RIDES the surface it stands on: on a slope its outline slopes with it. That is the
// trade the fallback makes (see the header) — the alternative was the per-cell anchor, which keeps
// every arch identical and costs 21 ms on a board of hoops. Nothing here is ever tilted or sheared:
// `rise` is a WORLD-vertical distance and the ogee is evaluated in world x, so a flame on a steep
// flank is still a flame pointing straight up, only a shorter one where its base is higher.
//
// The NEWEST tendril occupies a partial cell, so its height is ramped by the fraction: it grows out
// of the surface instead of sliding in from the edge. Cell boundaries move continuously as `cells`
// changes, so the established flames only shuffle rather than teleport — which is what makes a stack
// change smooth (owner ruling 16). Tweening the stack count alone is NOT enough; the count itself
// has to be continuous. ⚠ This is a SPANNING comb's rule and only a spanning comb's: it is meaningful
// exactly because the last cell is the newest one.
float tendril_at(float id, float cells, float pitch, float w, vec2 p, float floor_y) {
	float xc = (id + 0.5) * pitch - w * 0.5;
	float grow = (id >= floor(cells)) ? fract(cells) : 1.0;
	return tendril(id, grow, pitch, xc, xc / max(w * 0.5, 1e-4), p.x, floor_y - p.y);
}

void fragment() {
	// The host's MODULATE, which the renderer folds into COLOR before this function runs. Every
	// path below OVERWRITES COLOR, which silently threw it away: the focus highlight (owner ruling
	// 10) and a prop's fade never reached the flames, so a selected card lit up while its fire did
	// not, and an exiting prop's fire stayed at full alpha (owner report 2026-07-28). Captured
	// here, multiplied back in at the end.
	vec4 tint = COLOR;
	vec2 p = fx_local(UV, u_extent, u_pixel);
	float heat = 0.0;
	float level = u_level;
	float alpha_mul = 1.0;

	// The fragment's own nearest ball, resolved ONCE and handed to every mask lookup below (see
	// mask_level). A no-op for every other shape.
	vec2 ball = vec2(1e9);
	float ball_level = 0.0;
	float ball_id = 0.0;
	// Whether this fragment can draw anything at all. Only the ball shape can answer no — and when it
	// does, the march below is skipped entirely, which is the whole point (`return` is not allowed in
	// a Godot fragment processor, so it is a flag).
	bool alive = true;
	if (u_shape == SHAPE_BALLS) {
		// THE EMPTY MAJORITY, REJECTED FIRST (FX_HANDOFF §1b.2), with a margin for what this quad
		// draws BEYOND a ball: one flame's height, plus the erosion the base sinks by. Below the
		// pattern is rejected too — the march only ever walks DOWN, away from every ball.
		alive = fx_balls_near(p, u_height + max(u_sink, 0.0), u_span, u_arc_height, u_ball_radius);
	} else {
		// The same rejection for every other shape — see body_near.
		alive = body_near(p);
	}
	if (alive && u_shape == SHAPE_BALLS) {
		// THE NEAREST LIT BALL (the second half of FX_HANDOFF §2). Resolving the nearest ball of
		// any kind cost plumes too: high above ball A the nearest ball is often a different ball B,
		// and if B was unlit the march reported "solid, emits nothing" and forced the fragment dark —
		// an unlit ball actively suppressing a lit one's plume wherever it won the lookup. An unlit
		// ball is not on fire and has nothing this quad can draw, so it is not a candidate at all.
		fx_nearest_ball(p, u_ball_count, u_phase, u_span, u_arc_height, u_return_height,
				u_top_fraction, u_ball_gravity, u_ball_dir, u_ball_arcs, u_ball_fire, 1, ball_id,
				ball_level);
		// No lit ball anywhere near this column: there is nothing for the march to find.
		alive = ball_level > 0.0;
		// SNAPPED on the BALL quad's lattice, not this quad's: the two have different reaches and
		// different `pixel`, so snapping here with u_extent/u_pixel would anchor the plume up to half
		// a pixel off its ball and jitter as the ball travelled.
		if (alive) ball = fx_pixel_snap(fx_ball_pos(ball_id, u_ball_count, u_phase, u_span,
				u_arc_height, u_return_height, u_top_fraction, u_ball_gravity, u_ball_dir,
				u_ball_arcs), u_partner_extent, u_partner_pixel);
	}

	// THE COMB: `u_count` cells across the host's own width, one tendril standing in each. The width
	// is the host's bounding box AT THE LIVE ROTATION, which no uniform can carry — a card turned 90
	// degrees is 50 units wide, not 38.
	float w = 2.0 * body_half_width();
	float cells = max(u_count, 1.0);
	float pitch = max(w / cells, 1e-4);
	// The comb owns exactly `cells` cells and no more, so the outermost flames are not duplicated
	// past the host's edge.
	float id = clamp(floor((p.x + w * 0.5) / pitch), 0.0, ceil(cells) - 1.0);

	// THIS COLUMN'S FLOOR — one down-march, shared by every tendril that reaches this fragment. Not
	// walked at all on a fragment the ball guard already rejected: that march is ~20 mask lookups,
	// and it is the cost §1b.2 exists to skip.
	float floor_level = MASK_EMPTY;
	float floor_y = NO_SURFACE;
	if (alive) floor_y = surface_below(p, u_height, ball, ball_level, floor_level) + u_sink;
	if (floor_y < NO_SURFACE && mask_solid(floor_level) && p.y <= floor_y) {
		level = floor_level;
		if (u_shape == SHAPE_BALLS) {
			// ONE FLAME PER BALL, ANCHORED TO THAT BALL — not a cell of a comb the ball happens to be
			// standing in (FX_HANDOFF §2, root cause). A ball travels; a comb anchored to the QUAD does
			// not, so a ball drifted through cells as it flew: its flame changed identity (and with it
			// its desync phase and its flicker), it thinned to nothing whenever the ball crossed a cell
			// boundary — where the arch's own outline is zero — and every cell past the first zeroed
			// the flame outright through `grow`. Anchoring the arch to the ball's OWN snapped centre
			// makes the plume a property of the ball, which is what ruling 21 says it is.
			//
			// `u_emit_width` is one ball DIAMETER, so a ball's flame is exactly as wide as its ball.
			// The fan is measured across the PATTERN, so the outermost balls lean outward like the
			// outermost tendrils of a crown do — one diameter would have fanned a ball 15 units out as
			// if it stood 11 cell-widths off centre and flung its tip outside its own arch.
			// No merge: balls do not have neighbours in a comb to fuse with.
			heat = tendril(ball_id, 1.0, max(u_emit_width, 1e-4), ball.x,
					clamp(ball.x / max(u_span * 0.5, 1e-4), -1.0, 1.0), p.x, floor_y - p.y);
		} else {
			heat = tendril_at(id, cells, pitch, w, p, floor_y);
			if (u_merge == 1) {                       // neighbours fuse, no V-notch between them
				heat = max(heat, tendril_at(id - 1.0, cells, pitch, w, p, floor_y));
				heat = max(heat, tendril_at(id + 1.0, cells, pitch, w, p, floor_y));
			}
		}
	}
	// Where the flame overlays the body it is drawn at u_inner_alpha. Every shipped style now sets
	// that to 1.0 — fire BLOCKS what it covers (owner 2026-07-29: seeing the art through the flame
	// "looks very bad"). How far the flames come down over the art is u_sink's job, not the alpha's.
	// Guarded by `alive` too: a rejected fragment cannot reach a non-zero `heat`, and `alpha_mul` is
	// only ever read where heat is non-zero — so this is one more mask lookup the empty majority skips.
	if (alive && mask_solid(mask_level(p, ball, ball_level))) alpha_mul = u_inner_alpha;
	// Split props: keep only the emitters belonging to this half, so a hoop's back-arc flames sit
	// behind the occupied card exactly as its back arc does.
	if (u_half == 1 && p.x > 0.0) heat = 0.0;
	if (u_half == 2 && p.x <= 0.0) heat = 0.0;

	// GUARD THE NOISE. Most fragments in the quad are empty, and fx_fbm is seven hash+lerp taps —
	// running it unconditionally triples the shader's cost for pixels that draw nothing. This one
	// branch is the single biggest saving in the shader and the easiest thing to drop in a
	// refactor; do not.
	if (heat <= 0.0) {
		COLOR = vec4(0.0);
	} else {
		// The turbulence scrolls UP, with the flame. Art y is NEGATIVE upward, so a feature held at a
		// fixed noise coordinate sits at `p.y = y_noise - t * scroll` — MINUS made the grain drift
		// DOWNWARD, which read as the fire falling (owner report 2026-07-28). PLUS carries it up.
		heat *= mix(1.0, 0.7 + 0.6 * fx_fbm(vec2(p.x, p.y + u_time * u_noise_scroll)
				* u_noise_scale + u_seed), u_noise_amp);
		heat *= u_intensity;
		heat += (fx_bayer(FRAGCOORD.xy) - 0.5) * u_dither * 0.15;

		vec4 col = texture(u_ramp, vec2(clamp(heat, 0.0, 1.0), clamp(level, 0.0, 1.0)));
		col.rgb *= u_brightness;
		col.a *= u_opacity * alpha_mul;
		COLOR = col * tint;
	}
}

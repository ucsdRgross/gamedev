shader_type canvas_item;
render_mode blend_mix, unshaded;
// Pixelated fire as a decorator over a SHAPE — GENERIC NOISE FIRE OVER A COVER FIELD
// (owner design, 2026-07-29, replacing the tendril/comb/ogee/onion build).
//
// Owner: *"Fire effect no longer has tendrils at all, just average fire shader effects like moving
// noise instead... just increasing shader params as intensity/stacks increase, no more individual
// tendrils, make sure all params have scaling ratios as stacks increase"* — and *"should still be
// form fitting to any shape and rotation. Do this for all current fire effects card prop ball."*
//
// THE MODEL, IN FOUR LINES:
//
//     cover(p) = how far above the FIRST of u_taps fixed taps below p to land inside the mask
//     n        = two scrolling noise layers, sampled in the SAME world-aligned quantized p
//     shape    = cover * (((cover + aperture) * n - aperture) * gain)     // the Kinomoto form
//     heat     = clamp(shape, 0, 1)  ->  COLOR = texture(u_ramp, vec2(heat, u_level))
//
// `cover` is 1 at the surface and falls to 0 at full reach, which is exactly the role `UV.y` plays
// in the reference this is ported from (Fire Shader by Yui Kinomoto @arlez80, MIT). Substituting
// the MASK-derived cover for the QUAD's `UV.y` is the whole port: the same arithmetic that burns a
// rectangle in the original burns the HOST'S OWN SHAPE here.
//
// ⚠ `cover` REPLACES THE DOWN-MARCH AND THE TENDRIL IN ONE MOVE, and the two are worthless apart.
// Measured on the retired build (FX_HANDOFF §9, 78 burning cards, GPU timer): deleting every
// tendril computation on its own was worth 4 %, and replacing the march with 4 shifted mask taps
// was worth 1.7x. The march could not be cut while a tendril needed a surface located to 0.4 art
// units (~11 effective taps); noise does not need that, so it can. THE COST OF THIS SHADER IS
// `mask_level` CALL COUNT x COST PER CALL AND NOTHING ELSE — every design decision below is about
// keeping the call count down.
//
// What that model buys, and each line is a property the retired build had to argue for:
//  * FORM-FITTING IS FREE. `cover` is sampled from the mask itself, so fire hugs whatever
//    `mask_level` answers — card, deformed card, blade, ring, ball — with no per-shape code.
//  * EVERY UPWARD-FACING SURFACE BURNS, anywhere in the art. The taps are local and vertical, so a
//    hoop's inner-bottom arc (the inside of the hole, which faces up) lights from the same code
//    that lights the outer top arc. Multiple surfaces in one column stop being a special case:
//    they are simply more body below a fragment.
//  * NO FLAME CAN LEAP A HOLE, structurally: no tap reaches further than `u_height`.
//  * NO CORNER CHAMFER — but ⚠ THAT TOOK A MASK CHANGE, NOT A FLAME ONE, and two earlier drafts of
//    this header got it wrong. "Fire licks DOWN the side of a card from each top corner" was never
//    the flame model: `u_radii` used to hold a RADIUS, and interpolating a function with a vertex in
//    it cut a real 2.32-unit chamfer that is a genuine upward-facing slope, so every correct model
//    stood fire on it. It holds a radial SCALE now (see radii_scale) and the RADII branch reduces to
//    the exact box at rest. FX_HANDOFF §0i.1.
//  * TIPS POINT UP BY CONSTRUCTION — the taps step WORLD-down and only the mask LOOKUP rotates
//    (owner ruling 1). A spinning knife needs no per-shape branch.
//
// There is no ball special case (owner 2026-07-30: *"fire effect should be unified and identical in
// how it treats everything"*). A ball is a SHAPE whose mask is the union of the discs; the cover
// field, the noise and the ramp above it are literally the same code for a card, a knife, a hoop
// and a ball. ⚠ The ball-fire quad USED to carry a comb tiled at ball pitch, and that was the cause
// of "fire on balls sometimes disappears, then reappears later" (FX_HANDOFF §2). With no comb the
// entire bug class is deleted by construction rather than fixed: one flame per ball is just noise
// over the ball mask.
//
// This shader is NEVER a material on the host. A ShaderMaterial on a CardVisual polygon is clipped
// to that polygon's UV rect (fire could not rise above the card) and inherits the card's rotation,
// offset spin and basis3d squash (flames would tumble and flatten). It is its own quad.

#include "res://Shaders/fx_common.gdshaderinc"

// Shape kinds. Mirrored by FxAttachment.Shape — the mapping is asserted by the FX ATTACHMENT suite,
// since GDScript and GLSL cannot share an enum. A card and a blade are NOT both boxes: a blade is a
// SPRITE and answers with its own alpha, which is what lets fire find the real drawing.
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
// ⚠ THERE IS NO "SOLID BUT DARK" ANSWER. An unlit ball used to return one, so that it occluded
// without lighting (owner ruling 3) — and that is exactly what made a LIT ball's plume disappear and
// come back (FX_HANDOFF §2). Fire resolves the nearest LIT ball (`lit_only` in fx_nearest_ball), so
// an unlit ball is never the answer here at all. What was given up is only its occlusion of a plume
// passing behind it, which the owner pre-ruled as the cheaper of the two.
const float MASK_EMPTY = -1.0;

bool mask_solid(float m) { return m >= 0.0; }

// The compiler's bound on the cover ladder. `u_taps` is the LIVE count and is what actually costs —
// this only has to be at least as large. ⚠ Keep it small: a GPU warp runs until every lane exits,
// so an unrolled ceiling nobody uses still bloats the instruction cache.
const int COVER_TAPS_MAX = 8;

// ===== LIVE — pushed every frame by FxAttachment ==============================================
uniform int u_shape = 0;
uniform int u_half = 0;              // split props: 0 whole, 1 back arc only, 2 front arc only
uniform vec2 u_extent = vec2(64.0);  // the quad's size in art units; UV maps across exactly this
// The BALL quad's PIXEL (SHAPE_BALLS only), so a plume snaps on the lattice its ball was drawn on
// rather than on this quad's own. Pushed from FxRequest.partner_id / partner_pixel.
//
// ⚠ There is no `u_partner_extent` any more: the lattice is anchored on the HOST'S ORIGIN, so two
// quads of different sizes centred on the same host share it exactly and only `pixel` can differ.
// It existed solely because the grid used to be anchored on the quad's edge (fx_common §pixel grid).
uniform float u_partner_pixel = 1.0;
uniform vec2 u_body = vec2(38.0, 50.0);
uniform float u_shape_rot = 0.0;
uniform float u_time = 0.0;          // pacing-aware, script-driven — NEVER the built-in TIME
uniform float u_seed = 0.0;
// ⚠ THERE IS NO `u_count` UNIFORM. It was the comb's cell count, and the comb is gone. It survives
// in `FxRequest.live` — where `FxAttachment._emit_embers` reads it as the ember RATE — but nothing in
// this shader reads it, and Godot ignores a `set_shader_parameter` for a name the shader does not
// declare, so carrying a dead uniform bought only the illusion that something used it.
uniform float u_level = 0.0;         // normalized stack level -> the ramp's v axis
uniform float u_intensity = 1.0;     // surplus stacks push heat UP the ramp (owner ruling 4)
uniform vec2 u_lag = vec2(0.0);      // the host's motion, normalized — the cape
uniform float u_radii[RADII];        // deformable card silhouette
// SPRITE kinds: the art's own sheet, and the frame to read out of it. A mask sampled live cannot go
// stale when its host turns, and it is the only representation that knows a ring has a HOLE in it.
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
// The ball path's shape and timing. Read here as well as in juggle.gdshader — the plume quad and
// the ball quad MUST agree or a flame slides off its ball, so FxJuggle.geometry() pushes ONE set of
// numbers to both. `u_top_fraction` is the throw's hang-time bias, `u_ball_gravity` the ease along
// an arc, `u_ball_dir` the host's ±1 base direction and `u_ball_arcs` how many arcs the loop has.
uniform float u_top_fraction : hint_range(0.2, 0.8) = 0.6;
uniform float u_ball_gravity : hint_range(1.0, 3.0) = 1.0;
uniform float u_ball_dir = 1.0;
uniform float u_ball_arcs = 2.0;
// One texel per ball, r = that ball's OWN normalized fire level (owner ruling 21: a ball's flame
// is the ball's effect at the level it was spawned with, never the card's Burning). Uploaded on
// status change, never per frame.
uniform sampler2D u_ball_fire : filter_nearest, repeat_disable, hint_default_black;

// ===== STATIC — written once from FxStyle ======================================================
uniform float u_pixel = 1.0;
uniform float u_inner_alpha : hint_range(0.0, 1.0) = 1.0;
// THE REACH: how far above a surface the fire can possibly be, in art units. It is a HARD bound now
// rather than a ceiling on a varying tendril — no tap goes further — so `FxRequest.reach` is exact
// and the quad is no longer padded for a variation that no longer exists.
uniform float u_height = 7.0;
// HOW MANY COVER TAPS. The single most important cost knob in the file: the shader is linear in
// this at ~0.48 ms per tap per full screen of burning cards (FX_HANDOFF §9), so 4 -> 6 is +50 % on
// the dominant term. 4 taps over a 7-unit reach is 1.75-unit resolution, and the noise hides the
// banding that leaves; do not raise it without looking at 01_fire_ladder side by side.
uniform int u_taps : hint_range(2, 8) = 4;
// How much of one tap step the ladder's phase is dithered by, per FX pixel. 1 is a full step and is
// what dissolves the tap ladder's staircase into a gradient; 0 shows the raw bands, which is what
// `00_cover_field` wants and nothing else does. See cover_below().
uniform float u_cover_dither : hint_range(0.0, 1.0) = 1.0;
// THE APERTURE, from the reference — and ⚠ IT IS A CUT, NOT AN OPENING. Read the shaped value at
// average noise: `heat = 0.5 * gain * cover * (cover - aperture)`, which is zero at `cover =
// aperture`. So the aperture is literally **the cover threshold below which nothing burns**: LOW
// leaves a solid body of fire filling its whole reach, HIGH eats the flame back toward its base and
// leaves only what the brightest noise pushes through. `00b_aperture` shows the three regimes.
uniform float u_aperture : hint_range(0.0, 1.0) = 0.35;
// Contrast on the shaped value before it is clamped into the ramp. Low leaves a soft gradient over
// the whole flame; high slams most of it to the hot end and leaves only a thin cool rim.
uniform float u_fire_gain : hint_range(0.25, 8.0) = 2.2;
// How far INTO the art the fire is allowed, in art units — an EROSION of the mask, not an offset
// added to a contour. Positive sinks the base below the surface (no seam where flame meets host);
// NEGATIVE lifts it clear so the flames cover no art at all.
uniform float u_sink = 2.0;
// Outward lean of the crown: the noise is sheared away from centre in proportion to how far out a
// fragment sits (owner ruling 1's "some angle skew as spread"). Grows with height above the
// surface, so the base stays planted and only the top of the flame moves.
uniform float u_skew = 0.15;
// Whole-effect breathing on the aperture. Kept separate from the noise so photosensitivity can be
// reduced independently of overall brightness.
uniform float u_pulse_amp = 0.0;
uniform float u_pulse_speed = 2.0;
// How hard the flames trail the host's motion (the cape), and a constant bias on top of it.
uniform float u_lag_amount : hint_range(0.0, 2.0) = 1.0;
uniform vec2 u_wind = vec2(0.0);
// THE NOISE. `amp` is how far it swings either side of flat — 0 gives a smooth, noiseless flame,
// which is what the geometry snapshots use to see the cover field on its own. `scale` is grain
// size, `scroll` how fast the grain RISES, `ratio` the second layer's grain relative to the first
// and `flicker_speed` that layer's speed relative to the first. Two layers at different speeds is
// what stops noise reading as static (FX_HANDOFF §0e); it is the one idea kept from the tri-colour
// reference, and it is cheap.
uniform float u_noise_amp : hint_range(0.0, 1.0) = 0.5;
uniform float u_noise_scale = 0.35;
uniform float u_noise_scroll = 18.0;
uniform float u_noise_ratio = 2.1;
uniform float u_flicker_speed = 1.7;
// WHICH NOISE SOURCE, and this exists to be MEASURED rather than to be a feature (FX_HANDOFF
// §0e.1). 1 = `fx_fbm`, three octaves of hash+lerp per fragment; 0 = one fetch from a baked
// seamless tile. It trades seven ALU taps for one memory fetch on an Intel UHD with shared memory
// bandwidth, and which wins is genuinely not obvious — `fx_cost.tscn` prices both rows.
// ⚠ It is a UNIFORM branch, so every lane of every warp takes the same side and it costs nothing.
// This is NOT a noise-TYPE system: the texture is swappable data (`FxFireStyle.noise_tex`), and
// there is exactly one alternative to it, not an enum.
uniform int u_noise_procedural : hint_range(0, 1) = 1;
uniform sampler2D u_noise_tex : filter_nearest, repeat_enable, hint_default_white;
// The art units one full tile of `u_noise_tex` covers at scale 1. Only the texture path reads it.
uniform float u_noise_tile = 32.0;
// The WHOLE palette: u = heat, v = stack level. Colour-per-stack is one texture coordinate
// (owner ruling 14), the band count is however many hard columns the image has rather than a
// fixed 4, and frost or poison is a different .tres rather than a code path.
uniform sampler2D u_ramp : source_color, filter_nearest, repeat_disable;
uniform float u_brightness = 1.0;
uniform float u_opacity = 1.0;
uniform float u_dither = 0.0;

// ===== THE MASK =================================================================================

// THE DEFORMABLE CARD'S RADIAL SCALE at angle `a` from straight up, in the ART's own frame (the
// caller has already rotated the lookup, so this never touches u_shape_rot).
//
// ⚠ THE TABLE IS A SCALE AGAINST THE REST RECTANGLE, NOT A RADIUS, AND THAT IS WHAT KILLED THE
// CORNER CHAMFER (owner report, twice: *"card fire has weird overlapping curvature at corners"*,
// then *"still chamfered"*). FX_HANDOFF §10 E, taken.
//
// Storing `r(a)` asked the shader to interpolate a function with a CORNER in it, and no scheme that
// blends two rays can reproduce a vertex — at 32 rays a 38x50 card's corner (37.23 deg, sampled at
// multiples of 11.25) came out cut by 2.32 art units. That chamfer is a genuine upward-facing slope,
// so the cover field stood fire on it, CORRECTLY; the fault was never the fire. Two dead ends worth
// recording, because both look like fixes and neither is:
//  * MORE RAYS only shrinks it — 32 -> -2.32, 64 -> -1.41, 128 -> -0.56 art units, at 128 floats per
//    material per quad per host.
//  * INTERPOLATING `1/r` (exact along a straight edge, since `1/r` is linear in `cos`/`sin` there)
//    fixes the scalloped bulge BETWEEN samples, and does nothing at all for the vertex.
//
// Dividing the measured radius by the REST rectangle's radius at the same angle makes the table
// `1.0` everywhere on an undeformed card. The mask test below then divides it back out and lands on
// the EXACT box branch — same two comparisons, same answer, no vertex to miss. A real deformation
// becomes a smooth field near 1, which is the one thing that interpolates cleanly.
//
// ⚠ `FxAttachment` OWNS THE OTHER HALF OF THIS CONTRACT. Both paths that fill the table
// (`_fill_radii_from_outline` and `measure_silhouette`) divide by `_rect_radius`, which is this
// branch's own closed form. Change one and you must change all three.
float radii_scale(float a) {
	float t = (a / TAU + 1.0) * float(RADII);
	int i0 = int(floor(t)) % RADII;
	return max(mix(u_radii[i0], u_radii[(i0 + 1) % RADII], fract(t)), 1e-3);
}

// THE MASK: the LEVEL of the surface at `p`, or MASK_EMPTY where there is no art.
//
// One function, a branch per shape, so adding a prop kind is one branch and touches nothing else.
// Analytic for the kinds that have it; an ALPHA SAMPLE of the sheet for sprite kinds, which is what
// lets a mask know about the hoop's hole.
//
// ⚠ ROTATION ROTATES THE LOOKUP, NEVER THE PIXEL GRID (universal rule): `p` arrives already
// quantized in the quad's world-aligned space and only the lookup turns into the art's frame.
//
// ⚠ THIS IS THE WHOLE COST OF THE SHADER — it is called `u_taps + 1` times per live fragment and
// nothing else in the file is within an order of magnitude. The RADII branch's `atan` is why a
// card's mask is 1.9x a box's (FX_HANDOFF §6c).
//
// `ball` / `ball_level` are the fragment's own nearest ball, resolved ONCE per fragment by the
// caller and passed down. The closed-form ball lookup is by far the most expensive thing in this
// file, and the cover ladder never leaves its column, so re-running it per tap would cost more than
// the whole rest of the shader. Ignored by every other kind.
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
		// The SAME test the box branch runs, on a coordinate divided by the deformation's radial
		// scale. At rest every scale is 1.0 and this IS the box branch — corners included, which is
		// the whole point (see radii_scale). It is also cheaper than the radius form it replaces:
		// two comparisons and a divide, against a `length()`.
		vec2 hr = u_body * 0.5;
		vec2 t = q / radii_scale(atan(q.x, -q.y));
		return (abs(t.x) <= hr.x && abs(t.y) <= hr.y) ? u_level : MASK_EMPTY;
	}
	// SPRITE: the drawing's own alpha, read at the point the art is actually drawn at. `u_art_size`
	// is the WHOLE frame centred on the host's origin — deliberately not the tight body box, which
	// is not centred on it and would slide the mask sideways.
	vec2 t = vec2(q.x * u_art_flip, q.y) / max(u_art_size, vec2(1e-4)) + 0.5;
	if (t.x < 0.0 || t.x > 1.0 || t.y < 0.0 || t.y > 1.0) return MASK_EMPTY;
	float a = texture(u_art, u_art_rect.xy + t * u_art_rect.zw).a;
	return (a > 0.5) ? u_level : MASK_EMPTY;
}

// Half the art's WORLD-ALIGNED width at the live rotation. Not `u_body.x * 0.5`: that is the
// UNROTATED width, so a card turned 90 degrees (which anim_spin_start does every revolution) is 50
// units wide, not 38. Read by the outward fan, which is measured across the silhouette.
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
// other shape, and it is worth 2.1x on a burning screen (§6a). ⚠ IT IS EASY TO LOSE IN A REWRITE
// AND IT MUST SURVIVE ONE (§0g.9).
//
// ⚠ THE QUAD IS SIZED FOR THE WORST CASE AND THE FRAGMENT IS NOT. A quad is the host's CIRCUMSCRIBED
// bound plus reach on all four sides — 84.8 x 84.8 for a 38x50 card, because a card CAN spin — so a
// card that is not currently turned leaves most of its quad empty, and every one of those empty
// fragments would otherwise pay the whole cover ladder to find nothing.
//
// It CANNOT change a pixel: every fragment it rejects is one where no tap could have found a
// surface anyway. That is the whole reason to prefer this to shrinking the quad — shrinking moves
// the pixel lattice, and this does not touch it.
//
// ⚠ `tall` IS RE-DERIVED FROM THE NEW REACH. It used to carry `height_var`, which no longer exists;
// a tap ladder is bounded at exactly `u_height`, so the margin is that plus the erosion the base
// sinks by. It is the SIDEWAYS margin too, because the skew and the cape push the noise out of its
// own column and neither can push it further sideways than the flame is long.
bool body_near(vec2 p) {
	vec2 b = body_bound();
	float tall = u_height + max(u_sink, 0.0);
	return abs(p.x) <= b.x + tall && p.y <= b.y && p.y >= -b.y - tall;
}

// ===== THE COVER FIELD ==========================================================================

// HOW FAR ABOVE THE NEAREST SURFACE BELOW ME AM I — the whole of the geometry, in `u_taps` mask
// lookups with NO early-out and NO divergence.
//
// `u_taps` taps step WORLD-DOWN from `base` at even spacing across `u_height`, and cover is read off
// the FIRST of them that lands inside the mask: 1 when the very first tap hits, falling a step at a
// time to 0 when none of them do. That is exactly the role `UV.y` plays in the reference — so the
// aperture term, the gain and the feel of the original all carry over unchanged.
//
// ⚠ IT IS THE FIRST HIT, NOT THE COUNT OF HITS, AND THE DIFFERENCE IS NOT COSMETIC. Counting hits
// measures how much SOLID MASS is below, which collapses on anything thin: a knife 4 art units
// thick under a 10-unit reach can never put more than one of four taps inside itself, so it would
// burn at a quarter strength at its own surface, and a juggled ball of radius 1.3 would barely
// light at all. Distance-to-surface is the quantity the model actually wants, it costs the same
// `min` per tap, and it makes a thin blade and a fat card burn identically at their surfaces —
// which is the "unified and identical in how it treats everything" the owner asked for.
//
// ⚠ WHY A FIXED COUNT AND NOT A SEARCH. The retired build marched down until it hit something,
// which reads as cheap and is not: a GPU warp runs until EVERY lane exits, and in the empty band
// above the flames no lane ever hits, so a 35-step march behaved like ~11 unconditional taps
// (FX_HANDOFF §9). A fixed ladder of 4 is 4.
//
// ⚠ WHY THE LADDER STARTS AT `p.y - u_sink` RATHER THAN AT `p`. `sink` is an EROSION of the mask:
// fire reaches exactly `sink` into the art and no further. Shifting the whole ladder up by `sink`
// puts cover = 1 exactly `sink` deep, and `deep` below cuts everything under that — so a card is
// not lit all the way to its bottom edge. A NEGATIVE sink shifts the ladder DOWN, which lifts the
// flames clear of the art entirely; that is what the negative half of the knob means.
//
// Art y is positive DOWN, so "below" is +y and "up" is -y. That never depends on the host's
// rotation — only the mask LOOKUP turns (owner ruling 1), which is the whole of why a spinning
// knife's flames stay upright, and it is free.
float cover_below(vec2 p, vec2 ball, float ball_level, out bool deep) {
	float n = float(clamp(u_taps, 2, COVER_TAPS_MAX));
	float step_y = max(u_height, 1e-4) / n;
	// ⚠ THE LADDER'S PHASE IS DITHERED PER FX PIXEL, AND THAT IS WHAT STOPS `u_taps` FROM BEING
	// VISIBLE AS HARD CONCENTRIC SHELLS (owner report 2026-07-29: *"multiple stacked masks whose
	// edges are hard defined and with large spaces in between"*).
	//
	// `cover` can only take `taps + 1` values, and `u_ramp` is `filter_nearest`, so without this
	// every one of those values is a flat band with a hard edge — a ring of flat colour per tap,
	// ringing the whole silhouette. It was invisible while `pixel` was finer than a screen pixel
	// (the bands were sub-pixel) and unmissable the moment the styles went onto the game's real
	// pixel size.
	//
	// Offsetting the whole ladder by up to half a step, per FX pixel, turns that staircase into a
	// dithered gradient — the same trick `u_dither` plays on the ramp's own bands, one step earlier.
	// It costs ONE hash and no extra taps, which matters because taps are the entire cost of this
	// shader. Keyed on the quantized position and NOT on `u_time`, so the dither is stable: a
	// time-varying one crawls, and reads as the fire boiling rather than rising.
	// ⚠ THE JITTER MOVES THE TAPS AND NOT THE EROSION TEST, and keeping those apart is a contract, not
	// a detail. `sink` promises fire reaches EXACTLY that far into the art — and a NEGATIVE sink
	// promises the flames cover no art at all. A jittered erosion test bites half a tap step into the
	// host regardless of the sign, which quietly breaks the negative half of the knob. So `erode` is
	// exact and only `base` is dithered.
	float jitter = (fx_hash21(floor(p / max(u_pixel, 0.01))) - 0.5) * u_cover_dither;
	float erode = p.y - u_sink;
	float base = erode + jitter * step_y;
	// `n + 1` is "no tap hit at all", which the arithmetic below turns into cover 0 — so the
	// no-surface case needs no branch of its own.
	float first = n + 1.0;

	// ⚠ A BALL'S COLUMN IS SOLVED, NOT SAMPLED, AND THIS IS THE JUGGLING LAYER'S BIGGEST LEVER.
	// A disc has a closed form for "where is my surface in this column" — one `sqrt` — so the ball
	// quad pays ZERO mask lookups where every other shape pays `u_taps + 1`.
	//
	// It was not optional. The tap ladder is a WIN wherever the retired march was long and a LOSS
	// wherever it was short, and on balls it was short: `fx_balls_near` already rejected the empty
	// band (FX_HANDOFF §1b.2), so a fragment that survived to the march usually hit a ball on its
	// first or second step. Trading 1-2 conditional lookups for 5 unconditional ones made the
	// juggling layer measurably WORSE — which is exactly what the first run of this build showed,
	// and it is the same reason §6a's `body_near` bought the card layer 2.1x and the ball layer
	// nothing.
	//
	// ⚠ IT IS NOT AN APPROXIMATION AND IT IS NOT A SECOND MODEL. It answers the identical question —
	// which is the first tap of the SAME ladder to land inside the mask — by SOLVING for that index
	// instead of testing each one, and it quantizes to the same `n + 1` levels. A ball and a card
	// burn identically at their surfaces, which is the owner's *"fire should be unified and
	// identical in how it treats everything"*. Only the arithmetic differs, and only where the mask
	// has a closed form worth having.
	if (u_shape == SHAPE_BALLS) {
		float dx = p.x - ball.x;
		float r2 = u_ball_radius * u_ball_radius - dx * dx;
		deep = false;
		// No ball anywhere in this column, so no tap of the ladder could have hit one either.
		if (r2 <= 0.0) return 0.0;
		float half_h = sqrt(r2);
		float top = ball.y - half_h;              // the disc's UPPER surface in this column
		float bot = ball.y + half_h;
		deep = erode >= top && erode <= bot;      // the EXACT erosion test — never the jittered base
		// The first tap at or below that surface. A disc's segment in a column is contiguous, so the
		// index is the whole answer — but it still has to LAND in the segment: a ball smaller than
		// one tap spacing can sit entirely between two taps, and then nothing burns, exactly as it
		// would not with the ladder.
		float i = max(ceil((top - base) / step_y), 1.0);
		if (i <= n && base + i * step_y <= bot) first = i;
		return clamp(1.0 - (first - 1.0) / n, 0.0, 1.0);
	}

	// TAP ZERO IS THE EROSION TEST, not part of the ladder: `base` solid means this fragment is
	// more than `sink` inside the art, where fire is not allowed. One lookup, and it replaces the
	// retired build's separate walk-up loop.
	deep = mask_solid(mask_level(vec2(p.x, erode), ball, ball_level));
	for (int i = 1; i <= COVER_TAPS_MAX; i++) {
		if (float(i) > n) break;
		if (mask_solid(mask_level(vec2(p.x, base + float(i) * step_y), ball, ball_level))) {
			first = min(first, float(i));
		}
	}
	return clamp(1.0 - (first - 1.0) / n, 0.0, 1.0);
}

// THE NOISE, sampled in the SAME world-aligned, already quantized `p` the cover field used.
//
// ⚠ NEVER ROTATE A COORDINATE BEFORE QUANTIZING IT (fx_common §0b). The noise is world-aligned for
// the same reason the pixel grid is: rotating the sample point rotates the grain with the host, and
// the pixels go diagonal.
//
// The turbulence scrolls UP, with the flame. Art y is NEGATIVE upward, so a feature held at a fixed
// noise coordinate sits at `p.y = y_noise - t * scroll` — MINUS made the grain drift DOWNWARD,
// which read as the fire FALLING (owner report 2026-07-28). PLUS carries it up.
//
// Two layers at different scales AND different speeds. One layer scrolling rigidly reads as a
// texture sliding past, not as fire; the beat between two is what makes it churn.
//
// ⚠ THE SECOND LAYER IS A PERFORMANCE KNOB AS WELL AS A LOOK ONE. It is a third of the noise cost,
// and the noise is the second most expensive thing in this shader after the cover field — so
// `noise_ratio <= 0` drops it whole, on a uniform branch that costs nothing to carry. That is the
// compromise to reach for if a machine cannot afford the layer; it is a visible change, so show the
// owner `01_fire_ladder` before and after rather than taking it silently.
float fire_noise(vec2 p) {
	vec2 a = p * u_noise_scale + vec2(0.0, u_time * u_noise_scroll) + u_seed;
	bool two = u_noise_ratio > 0.0;
	vec2 b = p * (u_noise_scale * u_noise_ratio)
			+ vec2(0.0, u_time * u_noise_scroll * u_flicker_speed) + u_seed * 1.7;
	float n;
	if (u_noise_procedural == 1) {
		n = two ? 0.5 * (fx_fbm(a) + fx_value_noise(b)) : fx_fbm(a);
	} else {
		// The baked tile is in ART UNITS per tile, so dividing by `u_noise_tile` is what makes the
		// grain the same size as the procedural path's at the same `noise_scale`.
		n = two ? 0.5 * (texture(u_noise_tex, a / u_noise_tile).r
					+ texture(u_noise_tex, b / u_noise_tile).r)
				: texture(u_noise_tex, a / u_noise_tile).r;
	}
	// `amp` swings the noise either side of flat rather than scaling it toward zero: at amp = 0 the
	// flame is a clean cover field with no grain at all, which is the state the geometry snapshots
	// need to see the shape on its own.
	//
	// ⚠ IT NEEDS A CONTRAST GAIN, AND WITHOUT ONE THE NOISE CANNOT REACH ITS OWN ENDS. Measured over
	// 400k samples of exactly this expression: `fx_fbm` alone spans 0.185..0.815 (1st..99th pct) and
	// AVERAGING the two layers narrows it further to 0.215..0.786 — the central limit theorem, not a
	// bug, but the two-layer trick pays for its churn in range. A plain `mix(0.5, n, amp)` can only
	// ever shrink that, so at the shipped `amp = 0.5` the noise swung a mere **0.358..0.643**.
	//
	// That is the whole of "the fire bottoms look off" and most of "stacked masks with hard edges":
	// with a swing that small, `heat` at the base (`n * gain`) lands inside ONE ramp band, so the
	// flame's foot was a FLAT BAR of a single colour, and every ragged edge in the picture was the
	// cover ladder showing through rather than the noise doing its job. Verified by dumping the
	// rendered rows: the bottom two rows of a burning card held exactly one colour.
	//
	// `NOISE_CONTRAST` is set so `amp = 1` reaches the full 0..1 with ~5 % clipping at the ends —
	// and clipping is WANTED here, because it is what gives fire solid cores and clean cutoffs.
	const float NOISE_CONTRAST = 2.0;
	return clamp(0.5 + (n - 0.5) * u_noise_amp * NOISE_CONTRAST, 0.0, 1.0);
}

void fragment() {
	// The host's MODULATE, which the renderer folds into COLOR before this function runs. Every
	// path below OVERWRITES COLOR, which silently threw it away: the focus highlight (owner ruling
	// 10) and a prop's fade never reached the flames, so a selected card lit up while its fire did
	// not. Captured here, multiplied back in at the end.
	vec4 tint = COLOR;
	vec2 p = fx_local(UV, u_extent, u_pixel);
	float heat = 0.0;
	float level = u_level;
	float alpha_mul = 1.0;

	// The fragment's own nearest ball, resolved ONCE and handed to every mask lookup below (see
	// mask_level). A no-op for every other shape.
	vec2 ball = vec2(1e9);
	float ball_level = 0.0;
	// Whether this fragment can draw anything at all. (`return` is not allowed in a Godot fragment
	// processor, so it is a flag.)
	bool alive = true;
	if (u_shape == SHAPE_BALLS) {
		// THE EMPTY MAJORITY, REJECTED FIRST (FX_HANDOFF §1b.2), with a margin for what this quad
		// draws BEYOND a ball: one flame's reach, plus the erosion the base sinks by. Below the
		// pattern is rejected too — the taps only ever step DOWN, away from every ball.
		alive = fx_balls_near(p, u_height + max(u_sink, 0.0), u_span, u_arc_height, u_ball_radius);
	} else {
		// The same rejection for every other shape — see body_near.
		alive = body_near(p);
	}
	if (alive && u_shape == SHAPE_BALLS) {
		// THE NEAREST LIT BALL (the second half of FX_HANDOFF §2). High above ball A the nearest
		// ball is often a different ball B, and an unlit B used to report "solid, emits nothing" and
		// force the fragment dark — an unlit ball actively suppressing a lit one's plume.
		//
		// ⚠ THE CENTRE COMES BACK FROM THE LOOKUP. It used to be re-derived with `fx_ball_pos`,
		// which rebuilds the whole arc ladder (8 sqrt plus a normalize) and walks it again — per
		// fragment, for a ball the lookup had ALREADY positioned. Same arithmetic, same result, one
		// evaluation (FX_HANDOFF §1b.1's hoist, finished 2026-07-29).
		float ball_id = 0.0;
		vec2 raw = vec2(0.0);
		fx_nearest_ball(p, u_ball_count, u_phase, u_span, u_arc_height, u_return_height,
				u_top_fraction, u_ball_gravity, u_ball_dir, u_ball_arcs, u_ball_fire, 1, ball_id,
				ball_level, raw);
		// No lit ball anywhere near this column: there is nothing for the cover field to find.
		alive = ball_level > 0.0;
		// A BALL'S FLAME IS THE BALL'S OWN LEVEL, never the card's Burning (owner ruling 21): each
		// ball burns at the level it was lit with, and `u_level` on this quad is not that.
		level = ball_level;
		// SNAPPED on the BALL quad's lattice, not this quad's: the two have different reaches and
		// different `pixel`, so snapping here with u_extent/u_pixel would anchor the plume up to half
		// a pixel off its ball and jitter as the ball travelled.
		if (alive) ball = fx_pixel_snap(raw, u_partner_pixel);
	}

	// THE COVER FIELD — `u_taps` lookups plus the erosion test, and that is the entire geometry.
	float cover = 0.0;
	bool deep = false;
	if (alive) cover = cover_below(p, ball, ball_level, deep);
	// Split props: keep only the half this quad owns, so a hoop's back-arc flames sit behind the
	// occupied card exactly as its back arc does. Done BEFORE the noise, so the discarded half costs
	// nothing at all.
	if (u_half == 1 && p.x > 0.0) cover = 0.0;
	if (u_half == 2 && p.x <= 0.0) cover = 0.0;

	// GUARD THE NOISE. Most fragments in the quad have no body below them at all, and the noise is
	// the second most expensive thing in the file — running it unconditionally is what tripled the
	// retired shader's cost for pixels that draw nothing. This one branch survives the rewrite for
	// exactly the same reason it existed before; it is the easiest thing to lose in a refactor.
	//
	// ⚠ IT REJECTS ON GEOMETRY ALONE, which is what makes it sound. The shaped value below is
	// `cover * (((cover + ap) * n - ap) * gain)` and `n` is at most 1, so its ceiling is
	// `cover * cover * gain` — zero exactly when cover is zero, whatever the noise says.
	if (!alive || deep || cover <= 0.0) {
		COLOR = vec4(0.0);
	} else {
		// Where the fire overlays the body it is drawn at u_inner_alpha. ⚠ THE LOOKUP IS SKIPPED
		// WHOLE when the style is opaque, and every shipped style is (owner 2026-07-29: seeing the
		// art through the flame "looks very bad") — a uniform branch, so it costs nothing and saves
		// a full mask call on every lit fragment. How far the flames come down over the art is
		// u_sink's job, not the alpha's.
		if (u_inner_alpha < 1.0 && mask_solid(mask_level(p, ball, ball_level))) {
			alpha_mul = u_inner_alpha;
		}
		// EVERYTHING THAT DISPLACES THE FLAME GROWS WITH HEIGHT, so the base stays planted on the
		// body and only the top moves: skew (systematic outward fan — ruling 1's "angle skew as
		// spread"), the wind, and the host's motion lag (the cape). `k` is height above the surface,
		// normalized — the complement of cover, which is the only thing `rise` was ever needed for.
		float k = 1.0 - cover;
		float fan = clamp(p.x / max(body_half_width(), 1e-4), -1.0, 1.0);
		float drift = (u_skew * fan + u_wind.x + u_lag.x * u_lag_amount) * k * k;
		float n = fire_noise(vec2(p.x - drift * u_height, p.y));

		// THE PORT, and it is one line. The reference is `UV.y * (((UV.y + aperture) * noise -
		// aperture) * 75.0)`, which burns a RECTANGLE because UV is the quad; substituting the
		// mask-derived `cover` for `UV.y` burns the HOST. Nothing else about the maths changes.
		//
		// ⚠ THE APERTURE IS WEIGHTED BY `k`, SO IT EATS THE TIP AND NEVER THE BASE — and that is a bug
		// fix, not a flourish (owner report 2026-07-29: *"transparency when it should be opaque"*).
		//
		// With a constant aperture the shaped value at the surface is `((1 + ap) * n - ap) * gain`,
		// which goes NEGATIVE whenever `n < ap / (1 + ap)` — about a quarter of the time at the
		// shipped tuning. So the flame was guaranteed to be punched through with transparent holes
		// right down to the body it stands on, at every setting, and the host's art showed through
		// them. Fading the aperture out as `cover -> 1` makes the base `n * gain`, which is solid for
		// any noise the two layers can actually produce, while the tip keeps the full cut that gives
		// the flame its ragged outline. It is also what fire looks like: a fire is opaque where it
		// meets its fuel and wispy at the top.
		//
		// The whole-effect breath rides the APERTURE rather than the brightness, so a breathing
		// flame grows and shrinks instead of flashing. It carries the HOST's phase, or every burning
		// card on the board would breathe in unison.
		float ap = u_aperture * k
				* (1.0 + u_pulse_amp * sin(u_time * u_pulse_speed + fx_hash11(u_seed) * TAU));
		heat = cover * (((cover + ap) * n - ap) * u_fire_gain);
		heat *= u_intensity;
		// ⚠ THE DITHER IS INDEXED ON THE FX PIXEL GRID, NOT ON SCREEN PIXELS. It used to take
		// `FRAGCOORD.xy`, which is one Bayer cell per SCREEN pixel — so at any `pixel` coarser than a
		// screen pixel each chunky FX block came out with a 4x4 checkerboard printed inside it, which
		// is the exact opposite of what a pixel-art dither is for. Invisible while `pixel` was finer
		// than a screen pixel (which is the bug that hid it), and glaring the moment the styles were
		// put on the game's real pixel size. `p` is already quantized, so dividing by `u_pixel` gives
		// one index per FX pixel and the pattern scales with the art.
		heat += (fx_bayer(p / max(u_pixel, 0.01)) - 0.5) * u_dither * 0.15;

		vec4 col = texture(u_ramp, vec2(clamp(heat, 0.0, 1.0), clamp(level, 0.0, 1.0)));
		col.rgb *= u_brightness;
		col.a *= u_opacity * alpha_mul;
		COLOR = col * tint;
	}
}

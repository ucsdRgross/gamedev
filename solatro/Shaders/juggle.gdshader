shader_type canvas_item;
render_mode blend_mix, unshaded;
// Juggled balls, with NO STACK LIMIT (owner ruling 5) — ONE INSTANCE PER BALL.
//
// ⚠ THIS USED TO BE ONE QUAD OVER THE WHOLE PATTERN, AND THAT WAS THE COST OF THE LAYER. A quad
// sized to the pattern is ~33 x 64 art units for ~28 art units of actual ball, so 39 fragments out of
// 40 ran a closed-form inversion of the arc ladder to discover they were empty (fx_common's note
// where `fx_nearest_ball` used to be). One instance per ball inverts the problem: the ball's INDEX
// arrives in INSTANCE_CUSTOM, `vertex()` places that one ball, and a fragment's only remaining
// question is whether it is inside a disc it already knows the centre of.
//
// Counts stay genuinely uncapped — 500 balls is 500 instances, and the per-frame CPU cost is ZERO
// because the instance data holds only the index and the level, which change when the STACK count
// does and not when the balls move. The motion is entirely `u_phase` and the vertex stage.
//
// All balls pass IN FRONT of the card (owner ruling 11): no depth split, no second bracket node.
// When two overlap the LAST instance drawn wins, and FxJuggle orders them so that is the ball with
// the highest level (owner: *"if overlapping, ball with highest stacks win"*).

#include "res://Shaders/fx_common.gdshaderinc"

// ===== LIVE — pushed per frame by FxAttachment ================================================
uniform vec2 u_extent = vec2(64.0);
uniform float u_time = 0.0;      // pacing-aware, script-driven — never the built-in TIME
uniform float u_count = 0.0;     // == StatusJuggling.stacks, UNCAPPED, and a FLOAT so that a
                                 // stack change eases instead of teleporting every ball
uniform float u_phase = 0.0;     // one clock shared with the ball-fire quad, so a plume can
                                 // never drift off its ball
uniform float u_span = 30.0;
uniform float u_arc_height = 37.5;   // the tall throw arc; GDScript grows it with the count
uniform float u_return_height = 6.0; // the shallow "flat" return
uniform float u_ball_radius = 3.0;   // GDScript already shrank this for the count
uniform float u_ball_spin = 2.0;     // GDScript already raised this for the count (ruling 25)

// ===== STATIC — written once from FxStyle =====================================================
uniform float u_pixel = 1.0;
// The HOST's own random, identical on every quad this host owns (FxAttachment._seed) and different
// on every other host — what keeps two cards with the same stack count from moving as one.
uniform float u_seed = 0.0;
// This host's ±1 base direction. Randomised per host, so ball 0 sets off left on one card and right
// on the next; the ball-fire quad is handed the SAME value, or a plume would sit on the mirror image
// of its ball.
uniform float u_ball_dir = 1.0;
uniform float u_top_fraction : hint_range(0.2, 0.8) = 0.6;
// GRAVITY along the throw: 1 = constant speed around the loop, higher makes the ball cover the ends
// of an arc fast and LINGER at its apex, which is what deceleration into the top of a throw and
// acceleration out of it look like. See fx_arc_ease in fx_common.gdshaderinc.
uniform float u_ball_gravity : hint_range(1.0, 3.0) = 1.0;
// How many ARCS the loop is made of — 2 is the original throw-and-carry, and GDScript adds lanes
// between them as the ball count rises (owner). Always EVEN, or the loop would not close
// in x. Both quads read it, for the same reason they share the gravity.
uniform float u_ball_arcs = 2.0;
// SPHERE shading (owner: "balls need to be spherical"). bands = how many hard tones the
// terminator is quantized into; light is the direction it comes from in ART space (so -y is UP,
// like everywhere else in 2-D), light_z is how head-on it is, and spec is the threshold that sets
// how big the highlight is (higher = tighter). All four are FxStyle levers — nothing baked.
uniform int u_ball_bands : hint_range(2, 8) = 3;
uniform vec2 u_ball_light = vec2(-0.45, -0.6);
uniform float u_ball_light_z : hint_range(0.05, 2.0) = 0.65;
uniform float u_ball_spec : hint_range(0.5, 0.999) = 0.965;
// FLAT colours: balls do NOT ride the stack ramp (owner ruling 20). Their count already reads
// through size and speed, so a third channel would be redundant.
//
// The body TONES are an N x 1 strip of EXACT palette entries, darkest first (FxStyle.ball_tones, a
// PaletteRamp), sampled with filter_nearest — one texel per band. They used to be mix(shade, lit),
// and the in-between colours that produced were off-palette by up to 49/255 even though both
// endpoints were hand-picked (owner: "blending can create unpredictable and bad looking
// colors"). A texture rather than a vec4 array because a dynamically indexed array returned garbage
// on GLES3 once already (ARCHITECTURE_REVIEW §4g).
uniform sampler2D u_ball_tones : source_color, filter_nearest, repeat_disable;
uniform vec4 u_gloss : source_color = vec4(1.0, 0.98, 0.85, 1.0);
uniform float u_opacity = 1.0;

// THIS INSTANCE'S BALL, resolved once per vertex instead of searched for per fragment.
//   v_origin — the ball's position rounded to a whole number of FX cells. The quad is placed there,
//              and the fragment adds it back to recover its host-space point on the host's OWN
//              lattice (fx_cell_round explains why whole cells and nothing else will do).
//   v_centre — the same position snapped to a cell CENTRE, which is what the disc is measured from,
//              so every ball rasterizes at phase zero and translates in whole pixels.
//   v_id     — the ball index, for the spin phase and the newest ball's grow-in.
varying vec2 v_origin;
varying vec2 v_centre;
varying float v_id;

void vertex() {
	float n = max(u_count, 1.0);
	v_id = INSTANCE_CUSTOM.x;
	vec2 raw = fx_ball_of(v_id, n, u_phase, u_span, u_arc_height, u_return_height,
			u_top_fraction, u_ball_gravity, u_ball_dir, u_ball_arcs);
	v_origin = fx_cell_round(raw, u_pixel);
	v_centre = fx_pixel_snap(raw, u_pixel);
	// ⚠ NO Y FLIP HERE, AND THE FIRST DRAFT GOT THIS WRONG — it negated y and drew the whole pattern
	// mirrored below the card (caught by `05_balls`: the oracle crosses above centre, the rendered
	// balls below). `fx_local`'s flip is between UV and MESH space, not between mesh space and ART
	// space: the 2-D renderer uses a canvas mesh's vertex x/y directly, and canvas +y is DOWN, which is
	// the direction art +y already points. So a vertex offset IS an art-space offset.
	VERTEX += v_origin;
}

void fragment() {
	// The host's MODULATE, which the renderer folds into COLOR before this function runs. Both
	// branches below OVERWRITE COLOR, which silently threw it away — so the focus highlight (owner
	// ruling 10) never reached the balls (owner report). Multiplied back in at the end.
	vec4 tint = COLOR;
	float n = max(u_count, 1.0);
	float id = v_id;
	// THE FRAGMENT'S HOST-SPACE POINT, on the host's own origin-anchored lattice. `v_origin` is a
	// whole number of cells, so adding it before the snap lands on exactly the grid `fx_local` would
	// have returned for this point off a host-sized quad — the identity fx_cell_round documents. The
	// flame's chunky pixels therefore did not move when this quad became one quad per ball.
	vec2 p = fx_pixel_snap(fx_local_raw(UV, u_extent) + v_origin, u_pixel);
	// Both points are on the lattice, so `d` is a whole number of cells and the disc rasterizes
	// symmetrically — the same reason the centre was snapped when this was a single quad.
	vec2 d = p - v_centre;
	float d2 = dot(d, d);
	// The newest ball occupies a partial slot, so ramp its RADIUS by the fraction: it grows in
	// place rather than popping into the pattern, and the loop's spacing absorbs the rest.
	float r = u_ball_radius * ((id >= floor(n)) ? fract(n) : 1.0);

	if (d2 > r * r || r <= 0.0) {
		COLOR = vec4(0.0);
	} else {
		// A SPHERE, not a disc. Lift the fragment onto the hemisphere it would sit on — z from the
		// unit disc, so the normal carries the curvature — and shade by that normal. The Lambert
		// term's iso-lines on a sphere are closed curves AROUND the light, so quantizing it gives
		// bands that follow the curvature and a terminator that bends; a straight two-tone split
		// reads flat however it is coloured.
		vec2 nd = d / max(r, 1e-4);
		vec3 nrm = vec3(nd, sqrt(max(1.0 - dot(nd, nd), 0.0)));
		// SPIN (owner ruling 25): the ball's SHADING FRAME turns — the light direction rotates,
		// AFTER the fragment was snapped to the grid, so the pixel grid itself never rotates
		// (§0b universal rule). A per-ball phase keeps them from turning in unison. No trails —
		// ruled too noisy.
		// The per-ball spin phase folds in the HOST's seed as well as the ball index: keyed on the
		// index alone, every card's ball 0 turned in lockstep with every other card's.
		float sp = u_ball_spin * u_time + fx_hash11(id + u_seed) * TAU;
		vec2 lit_dir = vec2(cos(sp) * u_ball_light.x - sin(sp) * u_ball_light.y,
				sin(sp) * u_ball_light.x + cos(sp) * u_ball_light.y);
		vec3 lgt = normalize(vec3(lit_dir, u_ball_light_z));
		// Hard bands, no antialiasing: floor to a band index, then SAMPLE that band's palette entry —
		// never a mix between two, which is what put off-palette colours on the balls.
		float bands = float(max(u_ball_bands, 2));
		float step_i = min(floor(clamp(dot(nrm, lgt), 0.0, 1.0) * bands), bands - 1.0);
		vec4 col = texture(u_ball_tones, vec2((step_i + 0.5) / bands, 0.5));
		// The highlight sits ON the surface: a half-vector threshold puts it where the sphere would
		// actually catch the light, off-centre and tightening toward the pole as u_ball_spec rises.
		if (dot(nrm, normalize(lgt + vec3(0.0, 0.0, 1.0))) > u_ball_spec) col = u_gloss;
		col.a *= u_opacity;
		COLOR = col * tint;
	}
}

shader_type canvas_item;
render_mode blend_mix, unshaded;
// Juggled balls, with NO STACK LIMIT (owner ruling 5) and no loop over the count.
//
// A shader loop always needs a constant bound, so there is no loop over the COUNT: balls are evenly
// spaced on one closed loop of arcs, each monotonic in x, which makes the nearest-ball test
// invertible in closed form (fx_nearest_ball). The work is set by the number of ARCS — bounded by
// FX_MAX_ARCS — never by the ball count, so 5 balls and 500 cost the same frame time.
//
// All balls pass IN FRONT of the card, on one quad (owner ruling 11): no depth split, no second
// bracket node. When two overlap, the lookup keeps the nearest, which is stable and cheap.

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
// between them as the ball count rises (owner 2026-07-28). Always EVEN, or the loop would not close
// in x. Both quads read it, for the same reason they share the gravity.
uniform float u_ball_arcs = 2.0;
// SPHERE shading (owner 2026-07-27: "balls need to be spherical"). bands = how many hard tones the
// terminator is quantized into; light is the direction it comes from in ART space (so -y is UP,
// like everywhere else in 2-D), light_z is how head-on it is, and spec is the threshold that sets
// how big the highlight is (higher = tighter). All four are FxStyle levers — nothing baked.
uniform int u_ball_bands : hint_range(2, 8) = 3;
uniform vec2 u_ball_light = vec2(-0.45, -0.6);
uniform float u_ball_light_z : hint_range(0.05, 2.0) = 0.65;
uniform float u_ball_spec : hint_range(0.5, 0.999) = 0.965;
// FLAT colours: balls do NOT ride the stack ramp (owner ruling 20). Their count already reads
// through size and speed, so a third channel would be redundant.
uniform vec4 u_lit : source_color = vec4(1.0, 0.82, 0.35, 1.0);
uniform vec4 u_shade : source_color = vec4(0.72, 0.45, 0.12, 1.0);
uniform vec4 u_gloss : source_color = vec4(1.0, 0.98, 0.85, 1.0);
uniform float u_opacity = 1.0;

void fragment() {
	// The host's MODULATE, which the renderer folds into COLOR before this function runs. Both
	// branches below OVERWRITE COLOR, which silently threw it away — so the focus highlight (owner
	// ruling 10) never reached the balls (owner report 2026-07-28). Multiplied back in at the end.
	vec4 tint = COLOR;
	vec2 p = fx_local(UV, u_extent, u_pixel);
	float n = max(u_count, 1.0);
	float id;
	float d2 = fx_nearest_ball(p, n, u_phase, u_span, u_arc_height, u_return_height,
			u_top_fraction, u_ball_gravity, u_ball_dir, u_ball_arcs, id);

	// The newest ball occupies a partial slot, so ramp its RADIUS by the fraction: it grows in
	// place rather than popping into the pattern, and the loop's spacing absorbs the rest.
	float r = u_ball_radius * ((id >= floor(n)) ? fract(n) : 1.0);

	if (d2 > r * r || r <= 0.0) {
		COLOR = vec4(0.0);
	} else {
		vec2 d = p - fx_ball_pos(id, n, u_phase, u_span, u_arc_height, u_return_height,
				u_top_fraction, u_ball_gravity, u_ball_dir, u_ball_arcs);
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
		// Hard bands, no antialiasing: floor to a band index, then span shade -> lit across them so
		// the brightest band IS u_lit and the dark side IS u_shade, at any band count.
		float bands = float(max(u_ball_bands, 2));
		float step_i = min(floor(clamp(dot(nrm, lgt), 0.0, 1.0) * bands), bands - 1.0);
		vec4 col = mix(u_shade, u_lit, step_i / (bands - 1.0));
		// The highlight sits ON the surface: a half-vector threshold puts it where the sphere would
		// actually catch the light, off-centre and tightening toward the pole as u_ball_spec rises.
		if (dot(nrm, normalize(lgt + vec3(0.0, 0.0, 1.0))) > u_ball_spec) col = u_gloss;
		col.a *= u_opacity;
		COLOR = col * tint;
	}
}

shader_type canvas_item;
render_mode blend_mix, unshaded;
// Juggled balls, with NO STACK LIMIT (owner ruling 5) and no loop over the count.
//
// A shader loop always needs a constant bound, so there is none: balls are evenly spaced on one
// closed loop whose two halves are each monotonic in x, which makes the nearest-ball test
// invertible in closed form (fx_nearest_ball). Four evaluations at any count — 5 balls and 500
// cost the same frame time.
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
uniform float u_top_fraction : hint_range(0.2, 0.8) = 0.6;
// FLAT colours: balls do NOT ride the stack ramp (owner ruling 20). Their count already reads
// through size and speed, so a third channel would be redundant.
uniform vec4 u_lit : source_color = vec4(1.0, 0.82, 0.35, 1.0);
uniform vec4 u_shade : source_color = vec4(0.72, 0.45, 0.12, 1.0);
uniform vec4 u_gloss : source_color = vec4(1.0, 0.98, 0.85, 1.0);
uniform float u_opacity = 1.0;

void fragment() {
	vec2 p = fx_local(UV, u_extent, u_pixel);
	float n = max(u_count, 1.0);
	float id;
	float d2 = fx_nearest_ball(p, n, u_phase, u_span, u_arc_height, u_return_height,
			u_top_fraction, id);

	// The newest ball occupies a partial slot, so ramp its RADIUS by the fraction: it grows in
	// place rather than popping into the pattern, and the loop's spacing absorbs the rest.
	float r = u_ball_radius * ((id >= floor(n)) ? fract(n) : 1.0);

	if (d2 > r * r || r <= 0.0) {
		COLOR = vec4(0.0);
	} else {
		vec2 d = p - fx_ball_at(u_phase + id / n, u_span, u_arc_height, u_return_height,
				u_top_fraction);
		// SPIN (owner ruling 25): rotate the ball's own SHADING frame — after quantizing, never
		// before, so the pixel grid stays square. A per-ball phase keeps them from turning in
		// unison, and the off-centre gloss dot is what actually reads as rolling: a symmetric
		// two-tone split looks identical every half turn. No trails — ruled too noisy.
		float sp = u_ball_spin * u_time + fx_hash11(id) * TAU;
		vec2 q = vec2(cos(sp) * d.x - sin(sp) * d.y, sin(sp) * d.x + cos(sp) * d.y);
		bool rim = (sqrt(d2) > r - 1.0) || (q.y > r * 0.35);
		bool gloss = length(q + vec2(0.3, 0.3) * r) < r * 0.3;
		vec4 col = gloss ? u_gloss : (rim ? u_shade : u_lit);   // hard steps, no antialiasing
		col.a *= u_opacity;
		COLOR = col;
	}
}

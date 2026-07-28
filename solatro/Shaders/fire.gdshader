shader_type canvas_item;
render_mode blend_mix, unshaded;
// Pixelated fire as a decorator over a SHAPE. The quad is world-aligned and the silhouette turns
// inside it (u_shape_rot), so flames rise in world space however the host is rotated — a knife
// spinning to face travel must not spin its flames (owner ruling 1).
//
// Tips point up BY CONSTRUCTION: the emitting width is combed into exactly u_count cells and each
// tendril rises straight up from the contour beneath it. Nothing ever has to bend a flame back
// toward vertical, because none ever leaves it — and the comb is O(1), so 3 tendrils and 300 cost
// the same (owner ruling 4: no small cap).
//
// This shader is NEVER a material on the host. A ShaderMaterial on a CardVisual polygon is clipped
// to that polygon's UV rect (fire could not rise above the card) and inherits the card's rotation,
// offset spin and basis3d squash (flames would tumble and flatten). It is its own quad.

#include "res://Shaders/fx_common.gdshaderinc"

// Emitter modes. Mirrored by FxAttachment.Mode — the mapping is asserted by the FX ATTACHMENT
// suite, since GDScript and GLSL cannot share an enum.
const int MODE_SILHOUETTE = 0;
const int MODE_BALLS = 1;

// Silhouette kinds. Mirrored by FxAttachment.Shape, asserted by the same test. A card and a blade
// are BOTH boxes; only a deformed card needs the radius table, so it is its own kind rather than
// every card paying for a 32-tap silhouette it does not use.
const int SHAPE_BOX = 0;
const int SHAPE_RING = 1;
const int SHAPE_RADII = 2;

// Number of entries in the deformable-card radius table. 32, NOT 16: the star rig goes up to 16
// arms, and 16 samples cannot represent 16 alternating features (Nyquist) — at 16 the arms either
// smooth into a blob or beat against the grid depending on phase.
const int RADII = 32;

// ===== LIVE — pushed every frame by FxAttachment ==============================================
uniform int u_mode = 0;
uniform int u_shape = 0;
uniform int u_half = 0;              // split props: 0 whole, 1 back arc only, 2 front arc only
uniform vec2 u_extent = vec2(64.0);  // the quad's size in art units; UV maps across exactly this
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
// Balls mode only. Shared with juggle.gdshader from ONE computation in FxAttachment, so a plume
// can never trail its ball by a frame.
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
uniform float u_wrap : hint_range(0.0, 1.0) = 0.0;
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
// The WHOLE palette: u = heat, v = stack level. Colour-per-stack is one texture coordinate
// (owner ruling 14), the band count is however many hard columns the image has rather than a
// fixed 4, and frost or poison is a different .tres rather than a code path.
uniform sampler2D u_ramp : source_color, filter_nearest, repeat_disable;
uniform float u_brightness = 1.0;
uniform float u_opacity = 1.0;
uniform float u_dither = 0.0;

// Silhouette reach along the ray at angle `a` measured from straight up. One branch per kind:
// adding a prop shape is one branch here and touches nothing else.
float shape_radius(float a) {
	float th = a - u_shape_rot;                       // rotate the LOOKUP, never the pixel grid
	if (u_shape == SHAPE_RING) {
		// An ELLIPSE, not a circle: the hoop's art is a foreshortened ring (32x72 texels), so a
		// circle of its half-WIDTH would sit the flames deep inside the real arc. r = ab / |(b·dx,
		// a·dy)|, which collapses back to the radius when the body is square.
		vec2 h = max(u_body * 0.5, vec2(1e-4));
		vec2 d = vec2(sin(th), -cos(th));
		return (h.x * h.y) / max(length(vec2(h.y * d.x, h.x * d.y)), 1e-4);
	}
	if (u_shape == SHAPE_RADII) {
		float t = (th / TAU + 1.0) * float(RADII);
		int i0 = int(floor(t)) % RADII;
		return mix(u_radii[i0], u_radii[(i0 + 1) % RADII], fract(t));
	}
	vec2 h = u_body * 0.5;                            // box: ray/rect exit
	vec2 d = vec2(sin(th), -cos(th));
	return min(h.x / max(abs(d.x), 1e-4), h.y / max(abs(d.y), 1e-4));
}

// Exact top (sgn -1) or bottom (sgn +1) contour of the ROTATED BOX at horizontal position x.
//
// A box is convex with four corners, so its contour is the upper (or lower) hull: walk the four
// edges and keep the extreme y among those that span x. Exact at EVERY angle — the fixed-point
// iteration below converges in one step only for an UNROTATED rectangle, and at 90 degrees it
// returned a visibly slanted base for what should be a flat edge (caught by the rotation
// snapshot). Cards and blades are both boxes, so this is the common path, and it is cheaper than
// the two shape_radius taps it replaces.
// One edge of the hull: if edge a->b spans x, fold its y at x into `best`.
float box_edge(float x, vec2 a, vec2 b, float sgn, float best) {
	float dx = b.x - a.x;
	if (abs(dx) < 1e-5) return best;           // a vertical edge spans no x range
	float t = (x - a.x) / dx;
	if (t < 0.0 || t > 1.0) return best;       // this edge does not cover x
	float y = a.y + (b.y - a.y) * t;
	return (sgn < 0.0) ? min(best, y) : max(best, y);
}

float box_contour(float x, float sgn) {
	vec2 h = u_body * 0.5;
	float c = cos(u_shape_rot);
	float s = sin(u_shape_rot);
	// Corners in the same frame shape_radius works in: local (lx, ly) maps to
	// (lx*c - ly*s, lx*s + ly*c), and "up" is negative y.
	vec2 p0 = vec2( h.x * c - h.y * s,  h.x * s + h.y * c);
	vec2 p1 = vec2(-h.x * c - h.y * s, -h.x * s + h.y * c);
	// Unrolled, with no local array: a dynamically indexed local array is not reliable across
	// GLES3 drivers, and this one compiled without complaint and then returned garbage (the fire
	// vanished entirely — again caught by the snapshot, not by any headless check).
	// Sentinel is OPPOSITE the search direction: the top contour is a MIN over edges, so it must
	// start at +1e9. Starting it at sgn * 1e9 made min() keep the sentinel forever and the fire
	// disappeared completely. If no edge covers x the sentinel survives, which parks the base far
	// enough away that no tendril reaches — the correct answer for "off the end of the shape".
	float best = -sgn * 1e9;
	best = box_edge(x, p0, p1, sgn, best);
	best = box_edge(x, p1, -p0, sgn, best);
	best = box_edge(x, -p0, -p1, sgn, best);
	best = box_edge(x, -p1, p0, sgn, best);
	return best;
}

// Contour y at horizontal position x, top side (sgn -1) or bottom (sgn +1).
//
// A polar radius table is not directly invertible for a vertical line, so this is a fixed-point
// iteration. Exact for the ring, and it converges in ONE step for a rectangle (the top edge is
// flat, so the first angle is already the answer). A DEEPLY star-deformed card is not near-convex
// and a vertical line can cross its outline three times; there the iteration settles on the
// convex-hull contour, so flames bridge across a notch instead of dipping into it. Fine for mild
// deformation; if deep stars must be hugged, raise the iteration count.
float contour_y(float x, float sgn) {
	if (u_shape == SHAPE_RING) {
		// Exact for the ellipse of shape_radius. Rotation is ignored here (the ring kinds never
		// turn — a hoop's directional art mirrors, it does not rotate), which is the same
		// assumption the circle this replaced already made.
		vec2 h = max(u_body * 0.5, vec2(1e-4));
		float d = 1.0 - (x * x) / (h.x * h.x);
		return d <= 0.0 ? sgn * 1e9 : sgn * h.y * sqrt(d);
	}
	if (u_shape == SHAPE_BOX) return box_contour(x, sgn);
	float y = sgn * u_body.y * 0.5;
	for (int it = 0; it < 2; it++) {
		float a = atan(x, -y);
		y = -shape_radius(a) * cos(a);
	}
	return y;
}

// Half the silhouette's HORIZONTAL reach at the current rotation — the width the comb spans.
//
// Not u_body.x * 0.5: that is the UNROTATED width, so a card turned 90 degrees (which
// anim_spin_start does every revolution) had its 50-unit-wide silhouette combed across only 38
// units, leaving a third of the top edge bare and the flames off-centre. Caught by the rotation
// snapshot. The deformable table keeps the nominal width — it is already an approximation, and
// the alternative is a 32-tap max per fragment.
float emit_half_width() {
	if (u_shape == SHAPE_RING) return u_body.x * 0.5;
	if (u_shape == SHAPE_RADII) return u_body.x * 0.5;
	vec2 h = u_body * 0.5;
	return h.x * abs(cos(u_shape_rot)) + h.y * abs(sin(u_shape_rot));
}

// Heat contributed by one tendril at (x, rise). `cell`/`cells` place it in the comb; `seed`
// desyncs it (for balls the cell is always 0 but each ball needs its own phase, so the two are
// separate arguments).
float tendril(float cell, float cells, float seed, float x, float rise, float w) {
	float half_w = (w / cells) * 0.5 * u_base_width;
	float xc = ((cell + 0.5) / cells - 0.5) * w;
	float ph = fx_hash11(seed + u_seed) * TAU * u_desync;

	// The NEWEST tendril occupies a partial cell, so ramp its height by the fraction: it grows out
	// of the surface instead of sliding in from the edge. Cell boundaries move continuously as
	// `cells` changes, so the established flames only shuffle rather than teleport — which is what
	// makes a stack change smooth (owner ruling 16). Tweening the stack count alone is NOT enough;
	// the count itself has to be continuous.
	float grow = (cell >= floor(cells)) ? fract(cells) : 1.0;

	float h = u_height
		* mix(1.0, 0.55 + 0.45 * fx_value_noise(vec2(seed * 3.7 + u_seed,
				u_time * u_flicker_speed)), u_height_var)
		* (1.0 + u_pulse_amp * sin(u_time * u_pulse_speed))
		* grow;
	if (rise >= h) return 0.0;
	float k = clamp(rise / h, 0.0, 1.0);              // 0 at the base, 1 at the tip

	// Everything that displaces the spine grows with height, so the base stays planted on the body
	// and only the TIP moves: skew (systematic outward fan — ruling 1's "angle skew as spread"),
	// sway (oscillating drift), wave (snaking), wind, and the motion lag.
	float drift = u_skew * (xc / max(w * 0.5, 1e-4)) * k
		+ sin(u_time * u_sway_speed + ph) * u_sway_amp * k * k
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
	float top = h * dome;
	if (rise >= top) return 0.0;

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

void fragment() {
	vec2 p = fx_local(UV, u_extent, u_pixel);
	float heat = 0.0;
	float alpha_mul = 1.0;
	float level = u_level;

	if (u_mode == MODE_SILHOUETTE) {
		float w = emit_half_width() * 2.0;
		float n = max(u_count, 1.0);
		// WRAP slides the base from the TOP contour down to the BOTTOM one, so the same comb gives
		// both "flames on top" and "engulfed" without ever tilting a flame.
		float top_y = contour_y(p.x, -1.0);
		float base = mix(top_y, contour_y(p.x, 1.0), u_wrap) + u_sink;
		float rise = base - p.y;                      // > 0 means above the base line
		if (rise > 0.0 && abs(p.x) <= w * 0.5) {
			float id = min(floor((p.x / w + 0.5) * n), ceil(n) - 1.0);
			heat = tendril(id, n, id, p.x, rise, w);
			if (u_merge == 1) {                       // neighbours fuse, no V-notch between them
				heat = max(heat, tendril(id - 1.0, n, id - 1.0, p.x, rise, w));
				heat = max(heat, tendril(id + 1.0, n, id + 1.0, p.x, rise, w));
			}
			// Where the flame overlays the body, draw it at its own alpha so a burning card keeps
			// its rank and suit readable. Fire is overlay ONLY (ruling 15) — it never tints or
			// chars its host, so nothing here writes to the card's own art.
			if (p.y > top_y) alpha_mul = u_inner_alpha;
		}
		// Split props: keep only the emitters belonging to this half, so a hoop's back-arc flames
		// sit behind the occupied card exactly as its back arc does.
		if (u_half == 1 && p.x > 0.0) heat = 0.0;
		if (u_half == 2 && p.x <= 0.0) heat = 0.0;
	} else {
		// BALLS: the SAME closed-form lookup juggle.gdshader uses, from the same include, so the
		// plume is welded to the ball rather than following it a frame later.
		float n = max(u_count, 1.0);
		float id;
		fx_nearest_ball(p, n, u_phase, u_span, u_arc_height, u_return_height, u_top_fraction, id);
		float lvl = texelFetch(u_ball_fire, ivec2(int(id), 0), 0).r;
		if (lvl > 0.0) {
			vec2 c = fx_ball_at(u_phase + id / n, u_span, u_arc_height, u_return_height,
					u_top_fraction);
			float rise = (c.y - p.y) + u_ball_radius; // from just under the ball, so no seam
			if (rise > 0.0) heat = tendril(0.0, 1.0, id, p.x - c.x, rise, u_ball_radius * 3.0);
			level = lvl;                              // the BALL's level, not the card's
		}
	}

	// GUARD THE NOISE. Most fragments in the quad are empty, and fx_fbm is seven hash+lerp taps —
	// running it unconditionally triples the shader's cost for pixels that draw nothing. This one
	// branch is the single biggest saving in the shader and the easiest thing to drop in a
	// refactor; do not.
	if (heat <= 0.0) {
		COLOR = vec4(0.0);
	} else {
		heat *= mix(1.0, 0.7 + 0.6 * fx_fbm(vec2(p.x, p.y - u_time * u_noise_scroll)
				* u_noise_scale + u_seed), u_noise_amp);
		heat *= u_intensity;
		heat += (fx_bayer(FRAGCOORD.xy) - 0.5) * u_dither * 0.15;

		vec4 col = texture(u_ramp, vec2(clamp(heat, 0.0, 1.0), clamp(level, 0.0, 1.0)));
		col.rgb *= u_brightness;
		col.a *= u_opacity * alpha_mul;
		COLOR = col;
	}
}

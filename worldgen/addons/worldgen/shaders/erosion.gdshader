shader_type canvas_item;
render_mode unshaded;

// Single-pass "directional gabor" erosion noise: produces branching gullies and
// ridges by steering anisotropic gabor stripes along the terrain's own slope
// (aspect) and folding them at branch_angle each octave. Ported from a Shadertoy
// technique; the simplex BASE-noise generator was removed -- instead we sample the
// pipeline's existing heightmap and compute its value / gradient / laplacian by
// finite differences (our_field), so erosion shapes OUR terrain. The colored
// analytic-derivative debug output, time scroll and mouse were cut.
//
// Every vec3 here is an "analytic" triple (value, d/dx, d/dy): the helpers
// propagate derivatives so slope masks / fades stay smooth. Final height =
// base + (erosion / max_erosion) * amplitude.

uniform sampler2D height_tex : filter_nearest;
uniform vec2 tex_size = vec2(512.0, 512.0);
uniform int output_mode = 0;     // 0 = final eroded height, 1 = erosion field only (debug)

// --- main tunables (mirror the original) ---
uniform int octaves = 4;
uniform float amplitude = 0.08;   // height the erosion field adds (our 0..1 scale)
uniform float frequency = 24.0;   // higher -> finer gabor cells (voronoi shift = 28 - floor(freq))
uniform float gain = 0.5;
uniform float lacunarity = 1.2;
uniform float branch_angle = 0.6283185;  // radians (~36 deg); set from GDScript
uniform float ridge_rounding = 0.1;
uniform float gully_rounding = 0.1;
uniform float detail = 1.2;
uniform float steepness_scale = 100.0;   // folds the old MAX_HEIGHT * steepness_scale; TUNE FIRST
// Elevation gate: erosion only carves at/above min_elevation, ramping in over
// elevation_falloff, so low ground (coasts/plains) stays flat.
uniform float min_elevation = 0.42;
uniform float elevation_falloff = 0.12;

#define ROOT_TWO 1.4142135624
#define TAU 6.28318530717959
#define M_PI 3.14159265358979323846
#define VORONOI_MAX_FREQUENCY_SHIFT 28
#define VORONOI_SALT 938443
#define HASH_LEN 8u
#define GET_R16_BITS(x) ((x) & 0xFFFFu)
#define GET_L16_BITS(x) ((x) >> 16u)
const ivec2 WORLD_DIMENSIONS = ivec2(1 << 29, 1 << 28);

// ============================ voronoi cell hashing ==========================
uint hash_ivec2(ivec2 data) {
	uint hash = HASH_LEN;
	uint tmp;
	hash += GET_R16_BITS(uint(data.x));
	tmp = (GET_L16_BITS(uint(data.x)) << 11u) ^ hash;
	hash = (hash << 16u) ^ tmp;
	hash += hash >> 11u;
	hash += GET_R16_BITS(uint(data.y));
	tmp = (GET_L16_BITS(uint(data.y)) << 11u) ^ hash;
	hash = (hash << 16u) ^ tmp;
	hash += hash >> 11u;
	hash ^= hash << 3u;
	hash += hash >> 5u;
	hash ^= hash << 4u;
	hash += hash >> 17u;
	hash ^= hash << 25u;
	hash += hash >> 6u;
	return hash;
}

ivec2 rand_2d_to_2d(ivec2 value, int frequency_mask) {
	uint a = hash_ivec2(value) & uint(frequency_mask);
	uint b = hash_ivec2(value + VORONOI_SALT) & uint(frequency_mask);
	return ivec2(int(a), int(b));
}

ivec2 wrap(ivec2 cell, int frequency_shift) {
	ivec2 wrap_at = ivec2(WORLD_DIMENSIONS.x >> frequency_shift, WORLD_DIMENSIONS.y >> frequency_shift);
	ivec2 r;
	r.x = cell.x < 0 ? (wrap_at.x + cell.x) : (cell.x & (wrap_at.x - 1));
	r.y = cell.y < 0 ? (wrap_at.y + cell.y) : (cell.y & (wrap_at.y - 1));
	return r;
}

ivec2 get_cell_position(ivec2 cell, int frequency_shift) {
	ivec2 wrapped_cell = wrap(cell, frequency_shift);
	ivec2 shifted = ivec2(cell.x << frequency_shift, cell.y << frequency_shift);
	return shifted + rand_2d_to_2d(wrapped_cell, (1 << frequency_shift) - 1);
}

// ============================ graded easing / mixing ========================
vec3 ease_out_quad(vec3 t) {
	float v = 1.0 - clamp(t.x, 0.0, 1.0);
	float mask = (t.x >= 0.0 && t.x <= 1.0) ? 1.0 : 0.0;
	return vec3(1.0 - v * v, (2.0 * v * mask) * t.yz);
}

vec3 ease_in_quad_linear(vec3 t, vec3 smoothing) {
	float s = max(smoothing.x, 0.0001);
	bool is_quad = t.x < s;
	float val_out = is_quad ? (0.5 * t.x * t.x / s) : (t.x - 0.5 * s);
	float df_dt = is_quad ? (t.x / s) : 1.0;
	float df_ds = is_quad ? (-0.5 * t.x * t.x / (s * s)) : -0.5;
	vec2 grad_out = df_dt * t.yz + df_ds * smoothing.yz;
	return vec3(val_out, grad_out);
}

vec3 ease_out_pow(vec3 t, float power) {
	float base = 1.0 - clamp(t.x, 0.0, 1.0);
	float new_h = 1.0 - pow(base, power);
	float deriv = power * pow(max(base, 0.0001), power - 1.0);
	return vec3(new_h, t.yz * deriv);
}

vec3 abs3(vec3 t) {
	float s = sign(t.x);
	return vec3(abs(t.x), t.yz * s);
}

vec3 mix_graded(vec3 a, vec3 b, vec3 t) {
	if (t.x > 1.0) t = vec3(1.0, 0.0, 0.0);
	return mix(a, b, t.x) + vec3(0.0, (b.x - a.x) * t.yz);
}

vec3 multiply_graded(vec3 a, vec3 b) {
	return vec3(a.x * b.x, (a.x * b.yz) + (b.x * a.yz));
}

vec3 get_rounding(vec3 fade_target, float rr, float gr) {
	float u = fade_target.x + 0.5;
	float c = clamp(u, 0.0, 1.0);
	float grad_scalar = (u >= 0.0 && u <= 1.0) ? (rr - gr) : 0.0;
	return vec3(mix(gr, rr, c), grad_scalar * fade_target.yz);
}

// ============================ directional gabor noise =======================
vec3 directional_gabor2(ivec2 p, float in_frequency, vec3 aspect, out vec3 sloping) {
	int frequency_shift = max(VORONOI_MAX_FREQUENCY_SHIFT - int(floor(in_frequency)), 0);
	float freq = float(1 << frequency_shift) * ROOT_TWO;
	ivec2 base_cell = ivec2(p.x >> frequency_shift, p.y >> frequency_shift);
	float inv_frequency = 1.0 / freq;
	float stripe_freq = TAU * ROOT_TWO * (1.0 + fract(in_frequency));
	const float dis_fall_off = 4.0;

	vec2 dir = vec2(cos(aspect.x), sin(aspect.x));
	vec2 perp_dir = vec2(-dir.y, dir.x);

	vec3 as = vec3(0.0);
	vec3 ac = vec3(0.0);
	vec3 at = vec3(0.0);
	for (int j = -2; j <= 2; j++) {
		for (int i = -2; i <= 2; i++) {
			ivec2 cell = base_cell + ivec2(i, j);
			ivec2 cell_position = get_cell_position(cell, frequency_shift);
			vec2 cell_delta = vec2(p - cell_position) * inv_frequency;
			float sqr_dis = dot(cell_delta, cell_delta);
			float alignment = dot(cell_delta, dir * stripe_freq);
			float weight = exp(-dis_fall_off * sqr_dis);
			vec2 cs = vec2(cos(alignment), sin(alignment));
			float delta_proj = dot(cell_delta, perp_dir);
			vec2 grad_dir = (dir + aspect.yz * delta_proj * freq) * stripe_freq;
			as += weight * vec3(cs.y, -2.0 * dis_fall_off * cell_delta * cs.y + cs.x * grad_dir);
			ac += weight * vec3(cs.x, -2.0 * dis_fall_off * cell_delta * cs.x - cs.y * grad_dir);
			at += weight * vec3(1.0, -2.0 * dis_fall_off * cell_delta);
		}
	}
	vec3 oc0 = vec3(ac.x, (ac.yz - ac.x * at.yz / at.x) * inv_frequency) / at.x;
	vec3 os0 = vec3(as.x, (as.yz - as.x * at.yz / at.x) * inv_frequency) / at.x;

	float mag = 0.5 * dot(vec2(oc0.x, os0.x), vec2(oc0.x, os0.x)) + 0.5;
	vec2 grad_mag = oc0.x * oc0.yz + os0.x * os0.yz;

	vec3 out_cos = vec3(oc0.x / mag, (mag * oc0.yz - oc0.x * grad_mag) / (mag * mag));
	vec3 out_sin = vec3(os0.x / mag, (mag * os0.yz - os0.x * grad_mag) / (mag * mag));

	sloping = out_sin;
	return out_cos;
}

// ====================== base field from OUR heightmap =======================
float h_at(ivec2 c) {
	c = clamp(c, ivec2(0), ivec2(tex_size) - 1);
	return texelFetch(height_tex, c, 0).r;
}

// Returns (height, d/dx, d/dy, laplacian) via finite differences. Replaces the
// original's analytic simplex sample.
vec4 our_field(ivec2 p) {
	float c = h_at(p);
	float xp = h_at(p + ivec2(1, 0));
	float xm = h_at(p - ivec2(1, 0));
	float yp = h_at(p + ivec2(0, 1));
	float ym = h_at(p - ivec2(0, 1));
	float gx = (xp - xm) * 0.5;
	float gy = (yp - ym) * 0.5;
	float lap = xp + xm + yp + ym - 4.0 * c;
	return vec4(c, gx, gy, lap);
}

void get_derivatives(ivec2 xz, out vec3 steepness, out vec3 aspect, out vec3 laplacian) {
	vec4 c = our_field(xz);
	vec4 dcdx = our_field(xz + ivec2(1, 0));
	vec4 dcdy = our_field(xz + ivec2(0, 1));

	float cl = length(c.yz);
	float dcldx = length(dcdx.yz) - cl;
	float dcldy = length(dcdy.yz) - cl;
	steepness = vec3(cl, dcldx, dcldy);

	float theta = atan(c.z, c.y);
	aspect = vec3(theta, atan(dcdx.z, dcdx.y) - theta, atan(dcdy.z, dcdy.y) - theta);
	aspect.yz = (fract((aspect.yz / TAU) + 0.5) - 0.5) * TAU;

	laplacian = vec3(c.w, dcdx.w - c.w, dcdy.w - c.w);
}

// ================================ fragment ==================================
void fragment() {
	ivec2 xz = ivec2(UV * tex_size);

	vec4 base = our_field(xz);

	vec3 steepness, laplacian, aspect;
	get_derivatives(xz, steepness, aspect, laplacian);
	steepness *= steepness_scale;
	laplacian *= steepness_scale;

	// FADE_TARGET_1 path from the original.
	laplacian /= 25.0;
	vec3 fade_target = abs(laplacian.x) >= 1.0 ? vec3(sign(laplacian.x), 0.0, 0.0) : laplacian;

	vec3 rounding = get_rounding(fade_target, ridge_rounding, gully_rounding);
	vec3 slope_mask = ease_out_quad(ease_in_quad_linear(steepness, rounding));

	vec3 ridge_gully_slope_mask = vec3(1.0, 0.0, 0.0);
	vec3 ridge_gully_fade_target = vec3(0.0);

	float freq = frequency;
	float amp = 1.0;

	// First octave of stripes runs perpendicular to the terrain aspect.
	aspect.x += M_PI / 2.0;

	vec3 gabor = directional_gabor2(xz, freq, aspect, steepness);
	vec3 octave = mix_graded(fade_target, gabor, slope_mask);
	ridge_gully_fade_target = mix_graded(ridge_gully_fade_target, gabor, ridge_gully_slope_mask);

	vec3 erosion = octave * amp;
	float max_erosion = amp;

	for (int i = 1; i < octaves; i++) {
		amp *= gain;
		freq += lacunarity;
		aspect.x += sign(steepness.x) * -branch_angle;

		rounding = get_rounding(gabor, ridge_rounding, gully_rounding) * float(1 << int(freq - frequency));
		vec3 octave_slope_mask = ease_out_quad(ease_in_quad_linear(abs3(steepness), rounding));
		slope_mask = multiply_graded(ease_out_pow(slope_mask, detail), octave_slope_mask);

		vec3 octave_rg = ease_out_quad(ease_in_quad_linear(abs3(steepness) * 2.0, rounding));
		ridge_gully_slope_mask = multiply_graded(ridge_gully_slope_mask, octave_rg);

		fade_target = octave;
		ridge_gully_fade_target = mix_graded(ridge_gully_fade_target, gabor, ridge_gully_slope_mask);

		gabor = directional_gabor2(xz, freq, aspect, steepness);
		octave = mix_graded(fade_target, gabor, slope_mask);

		erosion += octave * amp;
		max_erosion += amp;
	}

	float ero = erosion.x / max_erosion;          // ~ -1..1
	// Suppress erosion on low ground so coasts/plains stay flat.
	float gate = smoothstep(min_elevation, min_elevation + max(elevation_falloff, 1e-4), base.x);
	ero *= gate;
	float out_h = base.x + ero * amplitude;       // eroded terrain
	float value = (output_mode == 1) ? (0.5 + 0.5 * ero) : out_h;
	COLOR = vec4(vec3(value), 1.0);
}

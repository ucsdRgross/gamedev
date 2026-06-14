shader_type canvas_item;

// Tectonic blueprint: domain-warped Voronoi over the plate seed points.
// Outputs per pixel:
//   R,G = winning plate's drift vector (encoded 0..1)
//   B   = plate id / 15
//   A   = distance to nearest plate centre (normalized)
uniform int seed = 57;
uniform int plate_count = 5;
uniform sampler2D plate_tex; // texel i = (centre.x, centre.y, drift.x, drift.y)
uniform float warp_strength = 90.0; // pixels of organic edge distortion
uniform float warp_frequency = 5.0;

vec2 grad_hash(vec2 p) {
	p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
	return -1.0 + 2.0 * fract(sin(p) * 43758.5453123);
}

float gnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = dot(grad_hash(i + vec2(0.0, 0.0)), f - vec2(0.0, 0.0));
	float b = dot(grad_hash(i + vec2(1.0, 0.0)), f - vec2(1.0, 0.0));
	float c = dot(grad_hash(i + vec2(0.0, 1.0)), f - vec2(0.0, 1.0));
	float d = dot(grad_hash(i + vec2(1.0, 1.0)), f - vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

void fragment() {
	vec2 off = vec2(mod(float(seed), 256.0), mod(float(seed) * 1.37, 256.0));
	// Three-octave warp so plate edges are jagged/noisy, not smooth bisectors.
	vec2 wc = UV * warp_frequency + off;
	vec2 warp = vec2(gnoise(wc), gnoise(wc + vec2(31.7))) * warp_strength;
	warp += vec2(gnoise(wc * 2.3), gnoise(wc * 2.3 + vec2(11.5))) * (warp_strength * 0.5);
	warp += vec2(gnoise(wc * 5.7), gnoise(wc * 5.7 + vec2(7.3))) * (warp_strength * 0.28);
	// Clamp so the warp organically distorts edges but never folds coordinate
	// space (which would let central plates win the whole map).
	warp = clamp(warp, vec2(-warp_strength), vec2(warp_strength));
	vec2 px = UV * 768.0 + warp;

	int best = 0;
	float min_dist = 1.0e9;
	for (int i = 0; i < plate_count; i++) {
		vec2 centre = texelFetch(plate_tex, ivec2(i, 0), 0).xy;
		float dd = distance(px, centre);
		if (dd < min_dist) {
			min_dist = dd;
			best = i;
		}
	}

	vec2 drift = texelFetch(plate_tex, ivec2(best, 0), 0).zw;
	// Alpha MUST be 1.0: a fractional alpha makes the viewport alpha-blend the
	// output over the cleared background, scaling .b by alpha and corrupting the
	// plate-id readback. (Distance isn't needed downstream — deform recomputes.)
	COLOR = vec4((drift + 1.0) * 0.5, float(best) / 15.0, 1.0);
}

shader_type canvas_item;

// Base landmass: fractal gradient (Perlin) noise + central island mask.
// Gradient noise (vs. the old value noise) avoids axis-aligned square blocks
// and matches the smooth Simplex the CPU build used.
uniform int seed = 42;
uniform float frequency = 0.004;
uniform float island_radius = 0.72; // smaller = land confined nearer the centre
uniform float land_contrast = 1.7;  // >1 pushes values away from sea level (more land + peaks)

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
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y); // ~ -0.7 .. 0.7
}

float fbm(vec2 p) {
	float v = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 4; i++) {
		v += amp * gnoise(p);
		p *= 2.0;
		amp *= 0.5;
	}
	return v; // ~ -1 .. 1
}

void fragment() {
	// Bounded seed offset: large raw seeds wreck sin() precision.
	vec2 off = vec2(mod(float(seed), 256.0), mod(float(seed) * 1.37, 256.0));
	vec2 coord = UV * frequency * 768.0 + off;
	float n = fbm(coord) * 0.5 + 0.5; // 0 .. 1, clustered near 0.5
	// Contrast around 0.5 so the smooth gradient noise yields real lowlands,
	// highlands, and peaks instead of a narrow mid band.
	n = clamp((n - 0.5) * land_contrast + 0.5, 0.0, 1.0);

	// Central island mask forces high landmass density in the middle.
	float d = distance(UV, vec2(0.5));
	float mask = clamp(1.0 - (d / island_radius), 0.0, 1.0);
	mask = pow(mask, 0.5);

	COLOR = vec4(vec3(clamp(n * mask, 0.0, 1.0)), 1.0);
}

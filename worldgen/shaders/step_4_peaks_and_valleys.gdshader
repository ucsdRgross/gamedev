shader_type canvas_item;

// Peaks & valleys: ridged gradient noise + fine detail layered onto land.
// Ridged noise (1 - |gnoise|) gives natural mountain ridge lines instead of
// the concentric "donut" rings the old cellular formula produced.
uniform sampler2D deformed_tex;
uniform float ocean_threshold = 0.38;
uniform float ridge_frequency = 0.012;
uniform float detail_frequency = 0.04;
uniform float boundary_radius = 0.46; // hard edge clamp so land never reaches screen edges
uniform int seed = 44;

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

float ridged_fbm(vec2 p) {
	float v = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 4; i++) {
		float r = 1.0 - abs(gnoise(p));
		r = r * r;
		v += amp * r;
		p *= 2.0;
		amp *= 0.5;
	}
	return v; // ~ 0 .. 1
}

void fragment() {
	float height = texture(deformed_tex, UV).r;

	if (height > ocean_threshold) {
		vec2 off = vec2(mod(float(seed), 256.0), mod(float(seed) * 1.37, 256.0));
		float ridge = ridged_fbm(UV * ridge_frequency * 768.0 + off);
		float detail = gnoise(UV * detail_frequency * 768.0 + off + vec2(13.0)) * 0.12;
		// Concentrate the ridge uplift in already-high terrain so plains stay
		// plains and only highlands grow into mountains.
		float highland = smoothstep(ocean_threshold, ocean_threshold + 0.25, height);
		height = clamp(height + ridge * 0.25 * highland + detail, 0.0, 1.2);
	}

	// Edge clamp: tectonics/peaks can push land outward, so force a hard fade to
	// ocean past boundary_radius, guaranteeing land never touches the edges.
	float edge = distance(UV, vec2(0.5));
	float edge_mask = 1.0 - smoothstep(boundary_radius, boundary_radius + 0.04, edge);
	height *= edge_mask;

	COLOR = vec4(vec3(height), 1.0);
}

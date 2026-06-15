shader_type canvas_item;

// Base landmass: samples a CPU-baked fractal noise map (no shader noise) and
// applies a contrast remap + central island mask.
uniform sampler2D noise_tex;        // CPU-baked fbm, 0..1
uniform float island_radius = 0.72; // smaller = land confined nearer the centre
uniform float land_contrast = 1.7;  // >1 pushes values away from sea level (more land + peaks)

void fragment() {
	float n = texture(noise_tex, UV).r;  // 0 .. 1
	// Contrast around 0.5 so the smooth noise yields real lowlands, highlands and
	// peaks instead of a narrow mid band.
	n = clamp((n - 0.5) * land_contrast + 0.5, 0.0, 1.0);

	// Central island mask forces high landmass density in the middle.
	float d = distance(UV, vec2(0.5));
	float mask = clamp(1.0 - (d / island_radius), 0.0, 1.0);
	mask = pow(mask, 0.5);

	COLOR = vec4(vec3(clamp(n * mask, 0.0, 1.0)), 1.0);
}

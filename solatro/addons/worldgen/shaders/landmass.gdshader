shader_type canvas_item;

// Base landmass: samples a CPU-baked fractal noise map (no shader noise) and
// applies a contrast remap + central island mask.
uniform sampler2D noise_tex;        // CPU-baked fbm, 0..1
uniform sampler2D warp_x_tex;       // shared tectonic warp (x), 0..1 -> jagged coastline
uniform sampler2D warp_y_tex;       // shared tectonic warp (y), 0..1
uniform float island_radius = 0.72; // smaller = land confined nearer the centre
uniform float land_contrast = 1.7;  // >1 pushes values away from sea level (more land + peaks)
uniform float edge_jag = 0.06;      // UV displacement of the island cutoff
uniform float island_falloff = 0.5; // island-mask edge exponent (>1 = gentler coastal slope)

void fragment() {
	float n = texture(noise_tex, UV).r;  // 0 .. 1
	// Contrast around 0.5 so the smooth noise yields real lowlands, highlands and
	// peaks instead of a narrow mid band.
	n = clamp((n - 0.5) * land_contrast + 0.5, 0.0, 1.0);

	// Central island mask forces high landmass density in the middle. Warp the
	// sample position with the tectonic noise so the cutoff is jagged, not a circle.
	vec2 jag = (vec2(texture(warp_x_tex, UV).r, texture(warp_y_tex, UV).r) - 0.5) * 2.0 * edge_jag;
	float d = distance(UV + jag, vec2(0.5));
	float mask = clamp(1.0 - (d / island_radius), 0.0, 1.0);
	mask = pow(mask, island_falloff);

	COLOR = vec4(vec3(clamp(n * mask, 0.0, 1.0)), 1.0);
}

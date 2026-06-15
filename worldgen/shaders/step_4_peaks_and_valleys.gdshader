shader_type canvas_item;

// Peaks & valleys: ridged gradient noise + fine detail layered onto land.
// Ridged noise (1 - |gnoise|) gives natural mountain ridge lines instead of
// the concentric "donut" rings the old cellular formula produced.
uniform sampler2D deformed_tex;
uniform sampler2D ridge_tex;   // CPU-baked ridged noise, 0..1
uniform sampler2D detail_tex;  // CPU-baked fbm detail noise, 0..1
uniform float ocean_threshold = 0.38;
uniform float boundary_radius = 0.46; // hard edge clamp so land never reaches screen edges
uniform float peak_uplift = 0.25;       // ridge uplift amount in highlands
uniform float highland_range = 0.25;    // height band above sea over which uplift ramps in
uniform float peak_detail_strength = 0.12; // fine detail-noise amplitude

void fragment() {
	float height = texture(deformed_tex, UV).r;

	if (height > ocean_threshold) {
		float ridge = texture(ridge_tex, UV).r;                                 // 0 .. 1
		float detail = (texture(detail_tex, UV).r - 0.5) * 2.0 * peak_detail_strength;
		// Concentrate the ridge uplift in already-high terrain so plains stay
		// plains and only highlands grow into mountains.
		float highland = smoothstep(ocean_threshold, ocean_threshold + highland_range, height);
		height = clamp(height + ridge * peak_uplift * highland + detail, 0.0, 1.2);
	}

	// Edge clamp: tectonics/peaks can push land outward, so force a hard fade to
	// ocean past boundary_radius, guaranteeing land never touches the edges.
	float edge = distance(UV, vec2(0.5));
	float edge_mask = 1.0 - smoothstep(boundary_radius, boundary_radius + 0.04, edge);
	height *= edge_mask;

	COLOR = vec4(vec3(height), 1.0);
}

shader_type canvas_item;

// Peaks & valleys: altitude-blended multifractal noise layered onto land.
// Lowlands stay smooth (fbm detail only), mid elevations get rounded billow
// foothills, and highlands grow sharp ridged-multifractal crests -- so one
// terrain transitions plains -> hills -> mountains instead of wearing the same
// ridged texture everywhere. Both ridge and billow are domain-warped at bake.
uniform sampler2D deformed_tex;
uniform sampler2D ridge_tex;   // CPU-baked ridged-multifractal noise, 0..1 (highlands)
uniform sampler2D billow_tex;  // CPU-baked billow-multifractal noise, 0..1 (foothills)
uniform sampler2D detail_tex;  // CPU-baked fbm detail noise, 0..1
uniform sampler2D warp_x_tex;  // shared tectonic warp (x), 0..1 -> jagged edge clamp
uniform sampler2D warp_y_tex;  // shared tectonic warp (y), 0..1
uniform float ocean_threshold = 0.38;
uniform float boundary_radius = 0.46; // hard edge clamp so land never reaches screen edges
uniform float edge_jag = 0.06;        // UV displacement of the edge clamp (matches landmass)
uniform float peak_uplift = 0.25;       // ridge uplift amount in highlands
uniform float highland_range = 0.25;    // height band above sea over which uplift ramps in
uniform float peak_detail_strength = 0.12; // fine detail-noise amplitude
uniform float peak_billow_strength = 0.12; // foothill (billow) amplitude, peaks at mid elevation
uniform float peak_height_cap = 4.0;       // ceiling so peaks aren't plateaued (high = no flattening)

void fragment() {
	float height = texture(deformed_tex, UV).r;

	if (height > ocean_threshold) {
		float ridge = texture(ridge_tex, UV).r;                                 // 0 .. 1
		float billow = texture(billow_tex, UV).r;                               // 0 .. 1
		float detail = (texture(detail_tex, UV).r - 0.5) * 2.0 * peak_detail_strength;
		// t: 0 just above sea -> 1 in the highlands. Ridges dominate high ground;
		// billow foothills peak at mid elevation (t*(1-t) is max at t=0.5).
		float t = smoothstep(ocean_threshold, ocean_threshold + highland_range, height);
		float ridge_w = t;
		float billow_w = t * (1.0 - t) * 4.0;
		// Soft ceiling instead of a hard 0..1.2 clamp: peaks keep their dynamic
		// range (no flat tops) but can't run away past peak_height_cap.
		height = min(max(height
			+ ridge * peak_uplift * ridge_w
			+ billow * peak_billow_strength * billow_w
			+ detail, 0.0), peak_height_cap);
	}

	// Edge clamp: tectonics/peaks can push land outward, so force a hard fade to
	// ocean past boundary_radius. Warp the cutoff with the same tectonic noise as
	// the landmass mask so the outer coastline is jagged, not a clean circle.
	vec2 jag = (vec2(texture(warp_x_tex, UV).r, texture(warp_y_tex, UV).r) - 0.5) * 2.0 * edge_jag;
	float edge = distance(UV + jag, vec2(0.5));
	float edge_mask = 1.0 - smoothstep(boundary_radius, boundary_radius + 0.04, edge);
	height *= edge_mask;

	COLOR = vec4(vec3(height), 1.0);
}

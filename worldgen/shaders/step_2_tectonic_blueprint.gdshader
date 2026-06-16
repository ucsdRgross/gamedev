shader_type canvas_item;

// Tectonic blueprint: domain-warped Voronoi over the plate seed points.
// Outputs per pixel:
//   R,G = winning plate's drift vector (encoded 0..1)
//   B   = plate id / 15
//   A   = distance to nearest plate centre (normalized)
uniform int plate_count = 5;
uniform sampler2D plate_tex; // texel i = (centre.x, centre.y, drift.x, drift.y)
uniform sampler2D warp_x_tex; // CPU-baked domain-warp noise (x), 0..1
uniform sampler2D warp_y_tex; // CPU-baked domain-warp noise (y), 0..1
uniform float warp_strength = 90.0; // pixels of organic edge distortion
uniform float map_px = 768.0;  // map size in px (plate centres live in this space)

void fragment() {
	// Jagged plate edges from the baked warp map (signed), clamped so coordinate
	// space never folds (which would let central plates win the whole map).
	vec2 warp = (vec2(texture(warp_x_tex, UV).r, texture(warp_y_tex, UV).r) - 0.5) * 2.0 * warp_strength;
	warp = clamp(warp, vec2(-warp_strength), vec2(warp_strength));
	vec2 px = UV * map_px + warp;

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

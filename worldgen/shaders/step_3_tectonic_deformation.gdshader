shader_type canvas_item;

// Tectonic deformation:
//   1. PHYSICAL MOVEMENT — each plate's terrain is sample-shifted along its
//      drift vector (plates genuinely slide).
//   2. BOUNDARY COLLISION — using the two nearest plates, height is raised where
//      they converge (mountain ranges) and lowered where they diverge (rifts /
//      crevasses), concentrated in a band along the cell boundary. This puts the
//      relief AT the plate edges (not at centres like the raw CPU model, which
//      just lifted whole plate interiors).
uniform sampler2D landmass_tex;
uniform int plate_count = 5;
uniform sampler2D plate_tex;       // texel i = (centre.x, centre.y, drift.x, drift.y)
uniform sampler2D plate_land_tex;  // texel i.r = 1.0 continental, 0.0 oceanic
uniform sampler2D warp_x_tex;      // same baked warp the blueprint used
uniform sampler2D warp_y_tex;
uniform float warp_strength = 90.0;
uniform float map_px = 768.0;      // map size in px (plate centres live in this space)
uniform float drift_intensity = 0.25;
uniform float plate_move = 0.03;   // UV distance plates slide
uniform float tectonic_band = 55.0; // px width of the boundary relief band
uniform float land_rift_damping = 0.5; // land-land divergence drops only this fraction of ocean's

void fragment() {
	// Replicate the blueprint's warped coordinate exactly (same baked textures).
	vec2 warp = (vec2(texture(warp_x_tex, UV).r, texture(warp_y_tex, UV).r) - 0.5) * 2.0 * warp_strength;
	warp = clamp(warp, vec2(-warp_strength), vec2(warp_strength));
	vec2 px = UV * map_px + warp;

	// Two nearest plates.
	int best = 0;
	int second = 0;
	float d1 = 1.0e9;
	float d2 = 1.0e9;
	for (int i = 0; i < plate_count; i++) {
		vec2 centre = texelFetch(plate_tex, ivec2(i, 0), 0).xy;
		float dd = distance(px, centre);
		if (dd < d1) { d2 = d1; second = best; d1 = dd; best = i; }
		else if (dd < d2) { d2 = dd; second = i; }
	}

	vec4 p1d = texelFetch(plate_tex, ivec2(best, 0), 0);
	vec4 p2d = texelFetch(plate_tex, ivec2(second, 0), 0);
	vec2 c1 = p1d.xy;
	vec2 c2 = p2d.xy;
	vec2 drift1 = p1d.zw;
	vec2 drift2 = p2d.zw;

	// 1. Physically slide this plate's terrain along its drift vector.
	float h = texture(landmass_tex, UV - drift1 * plate_move).r;

	// 2. Relief in a band along the boundary between the two nearest plates.
	float boundary = 1.0 - smoothstep(0.0, tectonic_band, d2 - d1);
	vec2 dir = normalize(c2 - c1);
	// >0 = plates approach each other (uplift), <0 = pull apart (rift).
	float convergence = dot(drift1, dir) - dot(drift2, dir);
	float relief = convergence * drift_intensity * boundary;

	// Bias land over water: when two continental plates pull apart, keep most of
	// the land instead of dropping it to ocean (oceanic spreading drops normally).
	float land1 = texelFetch(plate_land_tex, ivec2(best, 0), 0).r;
	float land2 = texelFetch(plate_land_tex, ivec2(second, 0), 0).r;
	float both_land = step(1.5, land1 + land2);
	if (relief < 0.0) {
		relief *= mix(1.0, land_rift_damping, both_land);
	}
	h += relief;

	COLOR = vec4(vec3(clamp(h, 0.0, 1.5)), 1.0);
}

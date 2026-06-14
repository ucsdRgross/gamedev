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
uniform int seed = 57;
uniform int plate_count = 5;
uniform sampler2D plate_tex;       // texel i = (centre.x, centre.y, drift.x, drift.y)
uniform sampler2D plate_land_tex;  // texel i.r = 1.0 continental, 0.0 oceanic
uniform float warp_strength = 90.0;
uniform float warp_frequency = 5.0;
uniform float drift_intensity = 0.25;
uniform float plate_move = 0.03;   // UV distance plates slide
uniform float tectonic_band = 55.0; // px width of the boundary relief band
uniform float land_rift_damping = 0.5; // land-land divergence drops only this fraction of ocean's

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
	// Replicate the blueprint's warped coordinate exactly.
	vec2 off = vec2(mod(float(seed), 256.0), mod(float(seed) * 1.37, 256.0));
	vec2 wc = UV * warp_frequency + off;
	vec2 warp = vec2(gnoise(wc), gnoise(wc + vec2(31.7))) * warp_strength;
	warp += vec2(gnoise(wc * 2.3), gnoise(wc * 2.3 + vec2(11.5))) * (warp_strength * 0.5);
	warp += vec2(gnoise(wc * 5.7), gnoise(wc * 5.7 + vec2(7.3))) * (warp_strength * 0.28);
	warp = clamp(warp, vec2(-warp_strength), vec2(warp_strength)); // never fold space
	vec2 px = UV * 768.0 + warp;

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

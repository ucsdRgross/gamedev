shader_type spatial;

// Heightmap vertex displacement for the 3D map viewer. A flat (subdivided) plane
// is pushed up in Y by the terrain height sampled per-vertex, and shaded with the
// colormap via TRIPLANAR projection so near-vertical faces (cliffs/coasts) sample
// the map from the side instead of smearing a single top-down texel down the wall.
// Normals are reconstructed from the height gradient so the relief is lit.

uniform sampler2D height_map : filter_linear;            // R = terrain height (data)
uniform sampler2D color_map : source_color, filter_nearest;
uniform float height_scale = 0.6;                        // world height per unit of map height
uniform float sea_level = 0.0;                           // subtracted before scaling (drops ocean)
uniform float relief_gain = 1.0;                         // extra exaggeration of land relief
uniform vec2 uv_texel = vec2(0.00390625);                // 1 vertex step in UV (for normals)
uniform float xz_step = 0.004;                           // world distance between adjacent verts
// Triplanar: tri_scale maps world units -> color_map UV (= 1/plane_size so the top
// projection lines up 1:1 with the map). tri_sharpness biases the blend toward the
// dominant axis so flat ground stays the true top-down map.
uniform float tri_scale = 1.0;
uniform float tri_sharpness = 6.0;

varying vec2 v_uv;
varying vec3 v_world;
varying vec3 v_wnormal;

float lift(float h) {
	return max(h - sea_level, 0.0) * relief_gain * height_scale;
}

void vertex() {
	v_uv = UV;
	VERTEX.y += lift(texture(height_map, UV).r);
	float hl = lift(texture(height_map, UV - vec2(uv_texel.x, 0.0)).r);
	float hr = lift(texture(height_map, UV + vec2(uv_texel.x, 0.0)).r);
	float hd = lift(texture(height_map, UV - vec2(0.0, uv_texel.y)).r);
	float hu = lift(texture(height_map, UV + vec2(0.0, uv_texel.y)).r);
	NORMAL = normalize(vec3(hl - hr, 2.0 * xz_step, hd - hu));
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_wnormal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	// Blend weights from the (world) normal: flat ground -> top (y) projection,
	// which is the true top-down map (== v_uv); steep faces -> x/z side projections.
	vec3 bn = pow(abs(v_wnormal), vec3(tri_sharpness));
	bn /= (bn.x + bn.y + bn.z);
	vec2 uv_x = fract(vec2(v_world.z, v_world.y) * tri_scale);
	vec2 uv_z = fract(vec2(v_world.x, v_world.y) * tri_scale);
	vec3 c = texture(color_map, v_uv).rgb * bn.y
		+ texture(color_map, uv_x).rgb * bn.x
		+ texture(color_map, uv_z).rgb * bn.z;
	ALBEDO = c;
}

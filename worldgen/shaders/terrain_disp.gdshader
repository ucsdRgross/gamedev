shader_type spatial;

// Heightmap vertex displacement for the 3D map viewer. A flat (subdivided) plane
// is pushed up in Y by the terrain height sampled per-vertex, and shaded with the
// colormap. Normals are reconstructed from the height gradient so the relief is
// lit. Replaces the old extruded-slice stack.

uniform sampler2D height_map : filter_linear;            // R = terrain height (data)
uniform sampler2D color_map : source_color, filter_nearest;
uniform float height_scale = 0.6;                        // world height per unit of map height
uniform float sea_level = 0.0;                           // subtracted before scaling (drops ocean)
uniform float relief_gain = 1.0;                         // extra exaggeration of land relief
uniform vec2 uv_texel = vec2(0.00390625);               // 1 vertex step in UV (for normals)
uniform float xz_step = 0.004;                           // world distance between adjacent verts

varying vec2 v_uv;

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
}

void fragment() {
	ALBEDO = texture(color_map, v_uv).rgb;
}

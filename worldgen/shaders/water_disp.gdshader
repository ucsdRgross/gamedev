shader_type spatial;
render_mode cull_disabled;

// Separate heightmap vertex displacement for the water surface (rivers + lakes).
// Uses its OWN height (the water-surface elevation) and its own colormap, which is
// transparent everywhere there is no inland water -- those fragments are discarded,
// so only river/lake ribbons render, floating at their true surface elevation.

uniform sampler2D height_map : filter_linear;            // R = water-surface elevation (data)
uniform sampler2D color_map : source_color, filter_nearest;  // transparent where no water
uniform float height_scale = 0.6;                        // must match the terrain shader
uniform float sea_level = 0.0;
uniform float relief_gain = 1.0;
uniform float water_alpha = 0.7;

varying vec2 v_uv;

void vertex() {
	v_uv = UV;
	VERTEX.y += max(texture(height_map, UV).r - sea_level, 0.0) * relief_gain * height_scale;
}

void fragment() {
	vec4 c = texture(color_map, v_uv);
	if (c.a < 0.5) discard;            // no water here
	ALBEDO = c.rgb;
	ALPHA = water_alpha;
	METALLIC = 0.2;
	ROUGHNESS = 0.1;
}

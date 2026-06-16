shader_type canvas_item;

// Climate classification. Reads a packed state texture (R=height, G=river flag)
// and outputs a biome *id* (not a color) so the CPU/viewer own palette + legend:
//   R = biome_id / 255.0
//   G = near_river flag (0/1)
//   B = height (passthrough)
uniform sampler2D state_tex;
uniform sampler2D temp_tex;   // CPU-baked temperature noise, 0..1
uniform sampler2D humid_tex;  // CPU-baked humidity noise, 0..1 (shared with rivers)
uniform float ocean_threshold = 0.38;
uniform float mountain_threshold = 0.65;
// Biome variety lever: number of bands per axis. Max land biomes = product.
uniform int height_bands = 3;
uniform int temp_bands = 3;
uniform int humid_bands = 3;

void fragment() {
	vec4 state = texture(state_tex, UV);
	float h = state.r;
	bool near_river = state.g > 0.5;

	int biome = 0; // Ocean

	if (h >= ocean_threshold) {
		float raw_t = texture(temp_tex, UV).r;
		float raw_h = texture(humid_tex, UV).r;

		float elevation = h - ocean_threshold;
		float t = clamp(raw_t - (elevation * 0.5), 0.0, 1.0);
		float humid = clamp(raw_h + (near_river ? 0.35 : 0.0), 0.0, 1.0);

		// Modular classification: height_bands x temp_bands x humid_bands land
		// biomes (ids 1..product). Ocean stays id 0. Height is banded over the
		// above-sea range; temp/humid over their full 0..1 range.
		float hb = clamp((h - ocean_threshold) / max(0.001, 1.0 - ocean_threshold), 0.0, 0.99999);
		int h_band = int(hb * float(height_bands));
		int t_band = int(clamp(t, 0.0, 0.99999) * float(temp_bands));
		int hu_band = int(clamp(humid, 0.0, 0.99999) * float(humid_bands));

		biome = 1 + h_band * (temp_bands * humid_bands) + t_band * humid_bands + hu_band;
	}

	COLOR = vec4(float(biome) / 255.0, near_river ? 1.0 : 0.0, h, 1.0);
}

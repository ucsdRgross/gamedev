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

		// Modular 3x3x3 classification: 3 bands each of height, temperature,
		// humidity -> 27 land biomes (ids 1..27). Ocean stays id 0.
		int h_band;
		if (h >= mountain_threshold) h_band = 2;
		else if (h >= mix(ocean_threshold, mountain_threshold, 0.5)) h_band = 1;
		else h_band = 0;
		int t_band = (t < 0.34) ? 0 : (t < 0.67 ? 1 : 2);
		int hu_band = (humid < 0.34) ? 0 : (humid < 0.67 ? 1 : 2);

		biome = 1 + h_band * 9 + t_band * 3 + hu_band;
	}

	COLOR = vec4(float(biome) / 255.0, near_river ? 1.0 : 0.0, h, 1.0);
}

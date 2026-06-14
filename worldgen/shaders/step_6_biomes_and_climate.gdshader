shader_type canvas_item;

// Climate classification. Reads a packed state texture (R=height, G=river flag)
// and outputs a biome *id* (not a color) so the CPU/viewer own palette + legend:
//   R = biome_id / 255.0
//   G = near_river flag (0/1)
//   B = height (passthrough)
uniform sampler2D state_tex;
uniform int seed_t = 3;
uniform int seed_h = 4;
uniform float ocean_threshold = 0.38;
uniform float mountain_threshold = 0.65;
uniform float temp_frequency = 0.006;
uniform float humid_frequency = 0.007;

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

// Two-octave climate field in 0..1 with contrast so values span the full range
// (more biome variety) instead of clustering at mid (one dominant biome).
float climate_field(vec2 p) {
	// gnoise has low RMS (~0.2); amplify hard so values span the full 0..1 range
	// and split evenly across the 3 bands (otherwise everything sits mid-band).
	float v = gnoise(p) * 0.65 + gnoise(p * 2.4 + vec2(19.3)) * 0.35;
	v = clamp(v * 3.2 * 0.5 + 0.5, 0.0, 1.0);
	return v;
}

void fragment() {
	vec4 state = texture(state_tex, UV);
	float h = state.r;
	bool near_river = state.g > 0.5;

	int biome = 0; // Ocean

	if (h >= ocean_threshold) {
		vec2 off_t = vec2(mod(float(seed_t), 256.0), mod(float(seed_t) * 1.37, 256.0));
		vec2 off_h = vec2(mod(float(seed_h), 256.0), mod(float(seed_h) * 1.37, 256.0));
		float raw_t = climate_field(UV * temp_frequency * 768.0 + off_t);
		float raw_h = climate_field(UV * humid_frequency * 768.0 + off_h);

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

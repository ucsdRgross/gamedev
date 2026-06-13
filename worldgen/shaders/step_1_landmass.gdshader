shader_type canvas_item;

uniform int seed = 42;
uniform float frequency = 0.004;

float hash2d(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

float noise2d(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash2d(i);
	float b = hash2d(i + vec2(1.0, 0.0));
	float c = hash2d(i + vec2(0.0, 1.0));
	float d = hash2d(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void fragment() {
	vec2 coord = UV * frequency * 768.0 + vec2(float(seed));
	float n = noise2d(coord) * 0.5 + noise2d(coord * 2.0) * 0.25 + noise2d(coord * 4.0) * 0.125;
	
	// Just the raw topographical noise template
	float final_height = clamp((n - 0.1) * 1.5, 0.0, 1.0);
	COLOR = vec4(vec3(final_height), 1.0);
}

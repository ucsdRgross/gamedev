shader_type canvas_item;

uniform sampler2D biome_tex;
uniform int seed = 99;

float hash2d(vec2 p) {
    return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
    // Canvas split into 32x32 node cells
    float grid_size = 32.0;
    vec2 cell = floor(UV * grid_size);
    vec2 local_uv = fract(UV * grid_size);
    
    // Roll random node pos inside cell
    vec2 random_pos = vec2(hash2d(cell + float(seed)), hash2d(cell + float(seed + 1)));
    
    // Check underlying biome suitability (e.g., not ocean)
    // We sample the biome texture at the candidate position
    vec2 candidate_uv = (cell + random_pos) / grid_size;
    vec4 biome = texture(biome_tex, candidate_uv);
    
    float node_val = 0.0;
    // Simple filter: Check if candidate is land (not deep blue ocean color)
    if (length(biome.rgb - vec3(0.1, 0.2, 0.36)) > 0.1) {
        // Draw a small dot if the current UV is near the random candidate
        float dist = distance(UV, candidate_uv);
        if (dist < 0.005) {
            node_val = 1.0;
        }
    }
    
    COLOR = vec4(vec3(node_val), 1.0);
}

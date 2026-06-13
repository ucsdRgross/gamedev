shader_type canvas_item;

uniform sampler2D height_tex;
uniform sampler2D flow_tex;
uniform int seed_t = 3;
uniform int seed_h = 4;
uniform float ocean_threshold = 0.2;
uniform float mountain_threshold = 0.7;

float hash2d(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

float noise2d(vec2 p) {
    vec2 i = floor(p); vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash2d(i), hash2d(i+vec2(1.0,0.0)), f.x), mix(hash2d(i+vec2(0.0,1.0)), hash2d(i+vec2(1.0,1.0)), f.x), f.y);
}

void fragment() {
    float h = texture(height_tex, UV).r;
    float flow = texture(flow_tex, UV).g;
    
    vec3 color;
    
    if (h < ocean_threshold) {
        color = vec3(0.1, 0.2, 0.36); // Ocean
    } else {
        float raw_t = noise2d(UV * 0.006 * 768.0 + vec2(float(seed_t)));
        float raw_h = noise2d(UV * 0.007 * 768.0 + vec2(float(seed_h)));
        
        float elevation = h - ocean_threshold;
        float t = clamp(raw_t - (elevation * 0.5), 0.0, 1.0);
        bool near_river = flow > 220.0;
        float humid = clamp(raw_h + (near_river ? 0.35 : 0.0), 0.0, 1.0);
        
        if (h >= mountain_threshold) {
            if (t < 0.35) color = vec3(0.88, 0.91, 0.94); // Glacial Peak
            else if (t > 0.65) color = vec3(0.6, 0.1, 0.1); // Volcanic Crag
            else color = vec3(0.29, 0.33, 0.39); // Barren Ridges
        } else if (t < 0.25) {
            color = vec3(0.22, 0.74, 0.97); // Cryo Frostwastes
        } else if (t < 0.38) {
            if (humid < 0.4) color = vec3(0.48, 0.17, 0.07); // Tectonic Fissures
            else color = vec3(0.61, 0.64, 0.68); // Ashen Tundra
        } else if (t > 0.65) {
            if (humid < 0.3) color = vec3(0.97, 0.98, 0.98); // Salt Flats
            else if (humid < 0.55) color = vec3(0.39, 0.64, 0.05); // Tornado Prairie
            else color = vec3(0.01, 0.47, 0.34); // Toxic Swamps
        } else {
            if (humid < 0.35) color = vec3(0.7, 0.32, 0.03); // Shattered Savannah
            else if (humid < 0.6) color = vec3(0.08, 0.5, 0.23); // Seismic Plains
            else color = vec3(0.02, 0.37, 0.27); // Acidic Jungle
        }
        
        if (near_river) color = mix(color, vec3(0.14, 0.39, 0.92), 0.8);
    }
    
    COLOR = vec4(color, 1.0);
}

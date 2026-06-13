shader_type canvas_item;

uniform sampler2D deformed_tex;
uniform float ocean_threshold = 0.2;
uniform int seed = 44;

float hash2d(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

float noise2d(vec2 p) {
    vec2 i = floor(p); vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash2d(i), hash2d(i+vec2(1.0,0.0)), f.x), mix(hash2d(i+vec2(0.0,1.0)), hash2d(i+vec2(1.0,1.0)), f.x), f.y);
}

// Simplified cellular noise for ridges
float cellular(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    float minDist = 1.0;
    for (int y = -1; y <= 1; y++) {
        for (int x = -1; x <= 1; x++) {
            vec2 neighbor = vec2(float(x), float(y));
            vec2 point = vec2(hash2d(i + neighbor), hash2d(i + neighbor + vec2(13.4, 7.1)));
            float d = distance(f, neighbor + point);
            minDist = min(minDist, d);
        }
    }
    return minDist;
}

void fragment() {
    float height = texture(deformed_tex, UV).r;
    
    if (height > ocean_threshold) {
        vec2 coord = UV * 0.015 * 768.0 + vec2(float(seed));
        float ridge = 1.0 - abs(cellular(coord) * 2.0 - 1.0);
        float detail = (noise2d(UV * 0.08 * 768.0 + vec2(float(seed + 5))) * 2.0 - 1.0) * 0.12;
        
        height = clamp(height + (pow(ridge, 3.0) * 0.45) + detail, 0.0, 1.2);
    }
    
    COLOR = vec4(vec3(height), 1.0);
}

shader_type canvas_item;

uniform sampler2D height_tex;
uniform sampler2D flow_tex;

void fragment() {
    float h = texture(height_tex, UV).r;
    vec4 flow_data = texture(flow_tex, UV);
    float flow = flow_data.g;
    
    // Calculate local slope (gradient)
    vec2 texel = 1.0 / vec2(textureSize(height_tex, 0));
    float h_up = texture(height_tex, UV + vec2(0.0, texel.y)).r;
    float h_down = texture(height_tex, UV - vec2(0.0, texel.y)).r;
    float h_right = texture(height_tex, UV + vec2(texel.x, 0.0)).r;
    float h_left = texture(height_tex, UV - vec2(texel.x, 0.0)).r;
    float slope = length(vec2(h_right - h_left, h_up - h_down));
    
    // Hydraulic Erosion: Carve where water is high and moving fast (steep)
    if (flow > 30.0) {
        float carve = flow * slope * 0.005;
        h = max(h - carve, 0.1); 
    }
    
    COLOR = vec4(vec3(h), 1.0);
}

shader_type canvas_item;

uniform sampler2D height_tex;
uniform int pass_index = 0;

void fragment() {
    vec2 texel = 1.0 / vec2(textureSize(height_tex, 0));
    vec4 current = texture(height_tex, UV);
    float h = current.r;
    float flow = (pass_index == 0) ? 1.0 : current.g;
    float downhill_idx = -1.0;
    
    if (pass_index == 0) {
        float min_h = h;
        int best_idx = -1;
        int count = 0;
        for (int y = -1; y <= 1; y++) {
            for (int x = -1; x <= 1; x++) {
                if (x == 0 && y == 0) { count++; continue; }
                float nh = texture(height_tex, UV + vec2(float(x), float(y)) * texel).r;
                if (nh < min_h) {
                    min_h = nh;
                    best_idx = count;
                }
                count++;
            }
        }
        downhill_idx = float(best_idx);
        COLOR = vec4(h, flow, downhill_idx, 1.0);
    } else {
        float accumulated_flow = flow;
        float my_downhill = current.b;
        
        int count = 0;
        for (int y = -1; y <= 1; y++) {
            for (int x = -1; x <= 1; x++) {
                if (x == 0 && y == 0) { count++; continue; }
                vec2 n_uv = UV + vec2(float(x), float(y)) * texel;
                vec4 n_data = texture(height_tex, n_uv);
                
                int opposite_idx = 8 - count;
                if (int(n_data.b) == opposite_idx) {
                    accumulated_flow += n_data.g;
                }
                count++;
            }
        }
        COLOR = vec4(h, accumulated_flow, my_downhill, 1.0);
    }
}

shader_type canvas_item;

uniform sampler2D landmass_tex;
uniform sampler2D blueprint_tex;
uniform float drift_intensity = 0.22;

void fragment() {
    vec4 blue = texture(blueprint_tex, UV);
    vec2 drift_dir = blue.rg * 2.0 - 1.0;
    
    // 1. Shift landmass coordinates
    vec2 drift_uv = UV - (drift_dir * drift_intensity);
    float h = texture(landmass_tex, drift_uv).r;
    
    // 2. Divergence logic (Mountains/Rifts)
    vec2 texel = 1.0 / vec2(textureSize(blueprint_tex, 0));
    vec2 d_up = texture(blueprint_tex, UV + vec2(0.0, texel.y)).rg * 2.0 - 1.0;
    vec2 d_down = texture(blueprint_tex, UV - vec2(0.0, texel.y)).rg * 2.0 - 1.0;
    vec2 d_right = texture(blueprint_tex, UV + vec2(texel.x, 0.0)).rg * 2.0 - 1.0;
    vec2 d_left = texture(blueprint_tex, UV - vec2(texel.x, 0.0)).rg * 2.0 - 1.0;
    
    float div_x = d_right.x - d_left.x;
    float div_y = d_up.y - d_down.y;
    float divergence = div_x + div_y;
    
    if (divergence < -0.1) {
        h += abs(divergence) * 0.5;
    } else if (divergence > 0.1) {
        h -= divergence * 0.3;
    }
    
    // 3. APPLY ISLAND MASK
    float dist_from_center = length(UV - vec2(0.5));
    float mask = clamp(1.0 - (dist_from_center / 0.44), 0.0, 1.0);
    mask = pow(mask, 0.5);
    
    COLOR = vec4(vec3(h * mask), 1.0);
}

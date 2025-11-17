shader_type canvas_item;

// This uniform will store the mouse position (absolute pixel coordinates)
uniform vec2 mouse_pos = vec2(0.0, 0.0);

// Set a radius for the spotlight effect
uniform float radius = 300.0;

void fragment() {
    // --- CHANGE IS HERE ---
    // Get the viewport size (in pixels) by taking the reciprocal of SCREEN_PIXEL_SIZE
    vec2 viewport_size = 1.0 / SCREEN_PIXEL_SIZE;

    // Get the fragment's normalized coordinate (0.0 to 1.0) on the screen
    vec2 screen_uv = SCREEN_UV;

    // 1. Get the screen position of the current fragment (pixel)
    vec2 pos_on_screen = screen_uv * viewport_size;

    // 2. Calculate the distance between the current pixel and the stored mouse position
    float dist = distance(pos_on_screen, mouse_pos);

    // 3. Create a smooth value for the effect falloff
    float normalized_dist = smoothstep(radius, radius + 100.0, dist);

    // 4. Invert the distance (brightness is 1.0 inside, 0.0 outside)
    float brightness = 1.0 - normalized_dist;

    // 5. Sample the node's texture
    vec4 current_color = texture(TEXTURE, UV);
    
    // 6. Apply the brightness effect
    COLOR.rgb = current_color.rgb * brightness;
    COLOR.a = current_color.a;
}
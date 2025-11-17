shader_type canvas_item;

// This uniform will be set in the script to the texture of the *other* viewport
uniform sampler2D previous_frame_texture : filter_linear;

// Array uniforms for circle data
uniform int num_circles = 0;
uniform vec4 circle_data_pos_time[32]; // (center_x, center_y, start_time, unused)
uniform vec4 circle_data_color[32];    // (r, g, b, blend_mode_float)

// Scalar uniforms
uniform float time = 0.0;
uniform float speed_scale = 400.0;
uniform float ring_width = 3.0;

void fragment() {
    // Get the ColorRect's actual pixel dimensions.
    vec2 rect_size = 1.0 / TEXTURE_PIXEL_SIZE;
    // Get the fragment's local pixel coordinate inside the ColorRect.
    vec2 pos_on_rect = UV * rect_size;

    vec4 total_ripple_color = vec4(0.0);

    // 1. Calculate new ripples
    for (int i = 0; i < num_circles; i++) {
        vec2 center = circle_data_pos_time[i].xy;
        float start_time = circle_data_pos_time[i].z;

        vec4 color_data = circle_data_color[i];
        vec3 color = color_data.rgb;
        float blend_mode = color_data.a; // 1.0 (ADD) or -1.0 (SUBTRACT)

        float delta_time = time - start_time;
        float ripple_radius = delta_time * speed_scale;

        float dist = distance(pos_on_rect, center);

        // Check if the pixel is inside the ripple
        if (dist < ripple_radius + ring_width) {

            // Calculate ring intensity (fades out at the edges)
            float dist_to_ring_edge = abs(dist - ripple_radius);
            float intensity = 1.0 - smoothstep(0.0, ring_width, dist_to_ring_edge);

            // Add/Subtract the ripple color to the total
            total_ripple_color.rgb += color * intensity * blend_mode;
            total_ripple_color.a = 1.0;
        }
    }

    // --- DOUBLE BUFFERING: Accumulation ---
    // 2. Read the previous frame's output from the *other* viewport texture
    vec4 existing_color = texture(previous_frame_texture, UV);

    // 3. Add the new ripples to the accumulated history
    vec4 final_color = existing_color + total_ripple_color;

    // 4. Set the final color and clamp
    COLOR.rgb = clamp(final_color.rgb, 0.0, 1.0);
    COLOR.a = 1.0;
}
shader_type canvas_item;

uniform int seed = 57;
uniform int plate_count = 5;
uniform vec4 plates[15]; // Array storage packing pos.xy and normalized drift dir.zw vectors

float hash2d(vec2 p) {
    return fract(sin(dot(p, vec2(15.3, 94.2))) * 43758.5453);
}

float noise2d(vec2 p) {
    vec2 i = floor(p); vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash2d(i), hash2d(i+vec2(1.0,0.0)), f.x), mix(hash2d(i+vec2(0.0,1.0)), hash2d(i+vec2(1.0,1.0)), f.x), f.y);
}

void fragment() {
    // Inject continuous domain warping noise to organically distort and jag fault line cell margins
    vec2 warp_coord = UV * 15.0 + vec2(float(seed));
    vec2 warp = vec2(noise2d(warp_coord), noise2d(warp_coord + vec2(5.2))) * 0.04;
    vec2 warped_pixel_pos = (UV + warp) * 768.0;
    
    int closest_plate_idx = 0;
	float min_dist = 99999.0;
	
	// Scan plate seed allocations simultaneously via GPU pipeline cores
	for (int i = 0; i < plate_count; i++) {
	    float d = distance(warped_pixel_pos, plates[i].xy);
	    if (d < min_dist) {
	        min_dist = d;
	        closest_plate_idx = i;
	    }
	}
	
	// Extract the kinematically packed direction velocity vectors for the winning plate zone
	vec2 drift_dir = plates[closest_plate_idx].zw;
	
	// Pack parameters cleanly into color tracking arrays:
	// R, G channels store drift velocity vectors; B stores plate ID; A stores boundary distance metrics
	COLOR = vec4((drift_dir + 1.0) * 0.5, float(closest_plate_idx) / 15.0, min_dist / 768.0);
}

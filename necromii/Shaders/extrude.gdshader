shader_type spatial;
render_mode unshaded;

render_mode world_vertex_coords;

//skew model torwards camera
const float skew_factor = 0.5;
void vertex() {
	VERTEX.z -= VERTEX.y * skew_factor;
	VERTEX.z += NODE_POSITION_WORLD.y * skew_factor;
}

// Will ignore pixels with alpha below this value for extrusion
uniform float extruded_alpha_cull : hint_range(0.0, 1.0) = 1.0;
// If pixels with alpha are extruded, this sets the alpha to 1
uniform bool opaque_extrude = true;
// Keeps original image on front and back of cube unaffected by other parameters
uniform bool keep_image = true;
// Same as above but for original image
uniform float image_alpha_cull : hint_range(0.0, 1.0) = 1.0;
// When searching for texture edges, how big should steps be
// If 5, extrusion is precise to 1/5 pixel increments
uniform float precision : hint_range(0, 1) = 1.0;
// Offset extruded portion
uniform vec2 offset = vec2(0.0);
// Change color of extruded portion
uniform vec4 color_mix : source_color;
// 0 is no mix, 1 is solid color
uniform float mix_strength : hint_range(0.0, 1.0);
// 2D image where opaque pixels are extruded
uniform sampler2D Texture : source_color, filter_nearest_mipmap;

varying float pixel_size;
struct imgPoint {
	vec4 color;
	vec2 uv;
};

bool isInImg(vec2 uv){
	return uv.x >= 0.0 && uv.y >= 0.0 && uv.x <= 1.0 && uv.y <= 1.0;
}

// Return colored pixel found starting from UV with given slope
imgPoint imgExtrude(vec2 pos_on_img, vec2 slope, bool flipped){
	vec4 color;
	slope = normalize(slope);
	// Flip y as UV has inverted y axis
	slope.y *= -1.0;
	// While not yet hit edge of image texture
	while (isInImg(pos_on_img)) {
		// Flip image for back face
		if (flipped) color = texture(Texture, vec2(-pos_on_img.x, pos_on_img.y) + offset);
		else color = texture(Texture, pos_on_img + offset);
		// Colored pixel found
		if (color.w >= extruded_alpha_cull) {
			if (opaque_extrude) color.w = 1.0;
			color = mix(color, color_mix, mix_strength);
			return imgPoint(color, pos_on_img);
		}
		float pixel_step = 1.0 / pixel_size / precision;
		pos_on_img += slope * pixel_step;
	}
	return imgPoint(vec4(0.0), pos_on_img);
}

vec2 UVtoXY(vec2 uv){
	vec2 xy = uv * 2.0 - vec2(1.0);
	xy.y *= -1.0;
	return xy;
}
vec2 XYtoUV(vec2 xy){
	vec2 uv = (xy + vec2(1.0)) / 2.0;
	uv.y *= -1.0;
	return uv;
}

vec3 PlaneLineIntersection(vec3 plane_point, vec3 plane_normal, vec3 line_point, vec3 line_dir){
	float t = (dot(plane_normal, plane_point) - dot(plane_normal, line_point)) / (dot(plane_normal, normalize(line_dir)));
	return line_point + normalize(line_dir) * t;
}

void fragment() {
	pixel_size = max(VIEWPORT_SIZE.x, VIEWPORT_SIZE.y);
	// Get fragment position in world space coordinates
	vec3 frag_pos = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	// Get the camera direction by sustracting the camera position from the fragment position
	vec3 camera_ray = normalize(frag_pos - CAMERA_POSITION_WORLD);
	// Get transformed camera ray to handle rotation and scaling
	vec3 model_ray = normalize((inverse(MODEL_MATRIX) * vec4(camera_ray, 0.0)).xyz);
	
	// Determine which face of the cube we are looking at
	ivec2 face = ivec2(UV / vec2(1.0/3.0, 1.0/2.0));
	// Make each face have similar UV
	vec2 adjusted_UV = mod(UV,vec2(1.0/3.0, 1.0/2.0)) * vec2(3.0, 2.0);
	
	// Z
	if (face.x == 0 && face.y == 0) {
		// No need to extrude if already on colored pixel
		vec4 color = texture(Texture, adjusted_UV);
		if (color.w >= image_alpha_cull && keep_image) {
			ALBEDO = color.rgb;
			ALPHA = color.w;
		// Extrude
		} else {
			// From pixel cast ray from focal point to see if it collides with opaque pixel
			// If it collides, color the pixel with collided color
			imgPoint first_pixel = imgExtrude(adjusted_UV, model_ray.xy, false);
			ALBEDO = first_pixel.color.rgb;
			ALPHA = first_pixel.color.w;
			// Cap extruded end so it doesn't extrude infinitely
			// Does so by casting ray in opposite direction in order to find position of second collision
			vec3 point = vec3(UVtoXY(adjusted_UV),2.0);
			vec3 ray_intersection = PlaneLineIntersection(vec3(0.0), vec3(0.0,0.0,1.0), point, model_ray);
			vec2 uv_point = XYtoUV(ray_intersection.xy) + vec2(0.0,1.0);
			if (isInImg(uv_point)) {
				imgPoint second_pixel = imgExtrude(uv_point, -model_ray.xy, false);
				// If second raycast does not hit same texture on backface, then that pixel is clear
				if (model_ray.y <= 0.0 && second_pixel.uv.y < first_pixel.uv.y ) ALPHA = 0.0;
				else if (model_ray.y > 0.0 && second_pixel.uv.y > first_pixel.uv.y ) ALPHA = 0.0;	
			}
		}
	} 
	// -Z
	else if (face.x == 2 && face.y == 0) {
		// Back face has to be flipped in order to line up with front face
		vec2 correct_UV = vec2(-adjusted_UV.x, adjusted_UV.y);
		vec4 color = texture(Texture, correct_UV);
		if (color.w >= image_alpha_cull && keep_image) {
			ALBEDO = color.rgb;
			ALPHA = color.w;
		} else {
			imgPoint first_pixel = imgExtrude(adjusted_UV, vec2(-model_ray.x, model_ray.y), true);
			ALBEDO = first_pixel.color.rgb;
			ALPHA = first_pixel.color.w;
			
			vec3 point = vec3(UVtoXY(vec2(-adjusted_UV.x, adjusted_UV.y)),-2.0);
			vec3 ray_intersection = PlaneLineIntersection(vec3(0.0), vec3(0.0,0.0,1.0), point, model_ray);
			vec2 uv_point = XYtoUV(ray_intersection.xy) + vec2(1.0,1.0);
			if (isInImg(uv_point)) {
				imgPoint second_pixel = imgExtrude(uv_point, -model_ray.xy, false);
				if (model_ray.y <= 0.0 && second_pixel.uv.y < first_pixel.uv.y ) ALPHA = 0.0;
				else if (model_ray.y > 0.0 && second_pixel.uv.y > first_pixel.uv.y ) ALPHA = 0.0;
			}
		}
	}
	// X
	else if (face.x == 1 && face.y == 0) {
		// Convert pixel position on side of cube as if it is actually on same plane as texture on front of cube
		vec3 point = vec3(0.0, UVtoXY(adjusted_UV).yx);
		vec3 ray_intersection = PlaneLineIntersection(vec3(0.0), vec3(0.0,0.0,1.0), point, -model_ray);
		vec3 image_intersection = PlaneLineIntersection(vec3(0.0), vec3(1.0,0.0,0.0), ray_intersection, vec3(model_ray.xy, 0.0));
		vec2 new_uv = XYtoUV(image_intersection.xy) + vec2(0.5, 1.0);
		vec4 img_color = imgExtrude(new_uv, model_ray.xy, false).color;
		ALBEDO = img_color.rgb;
		ALPHA = img_color.w;
		// Find pixel position as if it is on front or back face and cast ray in opposite direction
		vec2 xy = UVtoXY(adjusted_UV);
		if (model_ray.z > 0.0) point = vec3(1.0, xy.y, -1.0 - xy.x);
		else point = vec3(1.0, xy.y, 1.0 - xy.x);
		ray_intersection = PlaneLineIntersection(vec3(0.0), vec3(0.0,0.0,1.0), point, model_ray);
		vec2 uv_point = XYtoUV(ray_intersection.xy) + vec2(0,1.0);
		if (isInImg(uv_point)) {
			// If ray collides with nothing then there can't be extrusion there
			vec4 img_color = imgExtrude(uv_point, -model_ray.xy, false).color;
			if (img_color.w == 0.0) ALPHA = 0.0;
		}
	}
	// -X
	else if (face.x == 0 && face.y == 1) {
		vec3 point = vec3(0.0, UVtoXY(adjusted_UV).yx);
		vec3 ray_intersection = PlaneLineIntersection(vec3(0.0), vec3(0.0,0.0,1.0), point, -model_ray);
		vec3 image_intersection = PlaneLineIntersection(vec3(0.0), vec3(-1.0,0.0,0.0), ray_intersection, vec3(model_ray.xy, 0.0));
		vec2 new_uv = XYtoUV(image_intersection.xy) + vec2(-0.5, 1.0);
		vec4 img_color = imgExtrude(new_uv, model_ray.xy, false).color;
		ALBEDO = img_color.rgb;
		ALPHA = img_color.w;
		
		vec2 xy = UVtoXY(adjusted_UV);
		if (model_ray.z > 0.0) point = vec3(-1.0, xy.y, -1.0 + xy.x);
		else point = vec3(-1.0, xy.y, 1.0 + xy.x);
		ray_intersection = PlaneLineIntersection(vec3(0.0), vec3(0.0,0.0,1.0), point, model_ray);
		vec2 uv_point = XYtoUV(ray_intersection.xy) + vec2(0.0,1.0);
		if (isInImg(uv_point)) {
			vec4 img_color = imgExtrude(uv_point, -model_ray.xy, false).color;
			if (img_color.w == 0.0) ALPHA = 0.0;
		}
	}
	// Y
	else if (face.x == 1 && face.y == 1) {
		vec2 rotated_UV = -UVtoXY(adjusted_UV);
		vec3 point = vec3(rotated_UV.x, 0.0, rotated_UV.y);
		vec3 ray_intersection = PlaneLineIntersection(vec3(0.0), vec3(0.0,0.0,1.0), point, -model_ray);
		vec3 image_intersection = PlaneLineIntersection(vec3(0.0), vec3(0.0,1.0,0.0), ray_intersection, vec3(model_ray.xy, 0.0));
		vec2 new_uv = XYtoUV(image_intersection.xy) + vec2(0.0,0.5);
		vec4 img_color = imgExtrude(new_uv, model_ray.xy, false).color;
		ALBEDO = img_color.rgb;
		ALPHA = img_color.w;
		
		vec2 xy = UVtoXY(vec2(-adjusted_UV.x, adjusted_UV.y));
		if (model_ray.z > 0.0) point = vec3(xy.x, 1.0, xy.y - 1.0);
		else point = vec3(xy.x, 1.0, xy.y + 1.0);
		ray_intersection = PlaneLineIntersection(vec3(0.0), vec3(0.0,0.0,1.0), point, model_ray);
		vec2 uv_point = XYtoUV(ray_intersection.xy) + vec2(1.0,1.0);
		if (isInImg(uv_point)) {
			vec4 img_color = imgExtrude(uv_point, -model_ray.xy, false).color;
			if (img_color.w == 0.0) ALPHA = 0.0;
		}
	}
	// -Y
	else if (face.x == 2 && face.y == 1) {
		vec2 XY = UVtoXY(adjusted_UV);
		vec3 point = vec3(XY.x, 0.0, XY.y);
		vec3 ray_intersection = PlaneLineIntersection(vec3(0.0), vec3(0.0,0.0,1.0), point, -model_ray);
		vec3 image_intersection = PlaneLineIntersection(vec3(0.0), vec3(0.0,-1.0,0.0), ray_intersection, vec3(model_ray.xy, 0.0));
		vec2 new_uv = XYtoUV(image_intersection.xy);
		new_uv += vec2(0.0, 1.5);
		vec4 img_color = imgExtrude(new_uv, model_ray.xy, false).color;
		ALBEDO = img_color.rgb;
		ALPHA = img_color.w;
		
		vec2 xy = UVtoXY(adjusted_UV);
		if (model_ray.z > 0.0) point = vec3(xy.x, -1.0, xy.y - 1.0);
		else point = vec3(xy.x, -1.0, xy.y + 1.0);
		ray_intersection = PlaneLineIntersection(vec3(0.0), vec3(0.0,0.0,1.0), point, model_ray);
		vec2 uv_point = XYtoUV(ray_intersection.xy) + vec2(0.0,1.0);
		if (isInImg(uv_point)) {
			vec4 img_color = imgExtrude(uv_point, -model_ray.xy, false).color;
			if (img_color.w == 0.0) ALPHA = 0.0;
		}
	}
}

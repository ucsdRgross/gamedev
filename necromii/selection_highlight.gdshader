shader_type canvas_item;

const int max_length = 4092;
uniform int size;
uniform vec2 points[max_length];
uniform vec2 texture_size;
uniform vec2 bounds[2];

void fragment() {
	int limit = clamp(size, 0, max_length);
	vec4 c = vec4(0.0, 0.0, 0.0, 0.0);
	vec2 pixel = texture_size * UV;
//
//	bool inside = false;
//	if (limit > 3){
//		//check if outside bounded rectangle first
//		if (pixel.x < bounds[0].x || pixel.x > bounds[1].x || pixel.y < bounds[0].y || pixel.y > bounds[1].y) {
//			inside = false;
//		} else{
//			//if inside polygon, total raycast intersections will be odd
//			for (int i = 0, j = limit-1; i < limit; j = i++) {
//				if ( ((points[i].y > pixel.y) != (points[j].y > pixel.y)) &&
//					(pixel.x < (points[j].x - points[i].x) * (pixel.y - points[i].y) / (points[j].y - points[i].y) + points[i].x) )
//					inside = !inside;
//				}
//			//inside = true;
////			for (int i = 0; i < limit-1; i++) {
////				vec2 dvec = normalize(points[i+1] - points[i]);
////				vec2 N = vec2(dvec.y, -dvec.x);
////				float D = dot(N, points[i]);
////				float dist = dot(N, pixel) - D;
////				if (dist > 0.0) {
////					inside = false;
////					break;
////				}
////			}
//		}
//	}
//	if (inside && limit > 3) {
//		c = vec4(UV.x, 1.0 - abs(UV.x - UV.y) , UV.y, 1.0);
//	}
	
	if (limit > 3) {
		for (int i = 0; i < limit; i++) {
		if (distance(pixel, points[i]) < 10.0) {
			c = vec4(UV.x, 1.0 - abs(UV.x - UV.y) , UV.y, 1.0);
			//break;
		}
	}
	}
	
	COLOR = c;
//	if (line_points[10].x > 0.0){
//		c = vec4(UV.x, UV.y, 0.0, 1.0);
//	}
	
}

shader_type canvas_item;

const int max_length = 4090;
uniform int size;
uniform vec2 points[max_length];
uniform vec2 bounds[2];

void fragment() {
	int limit = clamp(size, 0, max_length);
	vec4 c = vec4(0.0, 0.0, 0.0, 0.0);

	bool inside = false;
	if (limit > 3){
		//check if outside bounded rectangle first
		if (FRAGCOORD.x < bounds[0].x || FRAGCOORD.x > bounds[1].x || FRAGCOORD.y < bounds[0].y || FRAGCOORD.y > bounds[1].y) {
			inside = false;
		} else{
			//if inside polygon, total raycast intersections will be odd
			for (int i = 0, j = limit-1; i < limit; j = i++) {
				if ( ((points[i].y > FRAGCOORD.y) != (points[j].y > FRAGCOORD.y)) &&
					(FRAGCOORD.x < (points[j].x - points[i].x) * (FRAGCOORD.y - points[i].y) / (points[j].y - points[i].y) + points[i].x) )
					inside = !inside;
				}
			//inside = true;
//			for (int i = 0; i < limit-1; i++) {
//				vec2 dvec = normalize(points[i+1] - points[i]);
//				vec2 N = vec2(dvec.y, -dvec.x);
//				float D = dot(N, points[i]);
//				float dist = dot(N, pixel) - D;
//				if (dist > 0.0) {
//					inside = false;
//					break;
//				}
//			}
		}
	}
	if (inside && limit > 3) {
		c = vec4(UV.x, 1.0 - abs(UV.x - UV.y) , UV.y, 1.0);
	}
	
//	if (limit > 3) {
//		for (int i = 0; i < limit; i++) {
//			if (distance(FRAGCOORD.xy, points[i]) < 10.0) {
//				c = vec4(UV.x, 1.0 - abs(UV.x - UV.y) , UV.y, 1.0);
//				break;
//			}
//		}
//	}
	
	COLOR = c;
}
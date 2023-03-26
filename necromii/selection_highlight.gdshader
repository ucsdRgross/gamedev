shader_type canvas_item;

const int max_length = 4090;
uniform int size;
uniform vec2 points[max_length];
uniform vec2 bounds[2];

void fragment() {
	int limit = clamp(size, 0, max_length);
	vec4 c = vec4(0.0);

	bool inside = false;
	if (limit > 2){
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
		}
	}
	if (inside ) {
		c = vec4(UV.x + sin(TIME) / 5.0, 1.0 - abs(UV.x + sin(TIME * 1.5)/5.0 - UV.y + cos(TIME * 2.0)/5.0), UV.y + cos(TIME * 2.5)/5.0, 1.4 - (mod(UV.x, 0.1) - mod(UV.y, 0.1)) - abs(sin(TIME * 0.75)));
	}
	COLOR = c;
}
shader_type canvas_item;

const int max_length = 2048;
uniform int size;
uniform vec2 points[max_length];
uniform vec2 bounds[2];
uniform vec2 world_pos;

void fragment() {
	vec2 WORLDCOORD = FRAGCOORD.xy + world_pos;
	int limit = clamp(size, 0, max_length);
	vec4 c = vec4(0.0);

	bool inside = false;
	if (limit > 2){
		//check if outside bounded rectangle first
		if (WORLDCOORD.x < bounds[0].x || WORLDCOORD.x > bounds[1].x || WORLDCOORD.y < bounds[0].y || WORLDCOORD.y > bounds[1].y) {
			inside = false;
		} else{
			//if inside polygon, total raycast intersections will be odd
			for (int i = 0, j = limit-1; i < limit; j = i++) {
				if ( ((points[i].y > WORLDCOORD.y) != (points[j].y > WORLDCOORD.y)) &&
					(WORLDCOORD.x < (points[j].x - points[i].x) * (WORLDCOORD.y - points[i].y) / (points[j].y - points[i].y) + points[i].x) )
					inside = !inside;
				}
		}
	}
	if (inside ) {
		c = vec4(UV.x + sin(TIME) / 5.0, 1.0 - abs(UV.x + sin(TIME * 1.5)/5.0 - UV.y + cos(TIME * 2.0)/5.0), UV.y + cos(TIME * 2.5)/5.0, 1.45 - (mod(UV.x, 0.1) - mod(UV.y, 0.1)) - abs(sin(TIME * 0.75)));
	}
	COLOR = c;
}
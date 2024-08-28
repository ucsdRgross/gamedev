shader_type canvas_item;

uniform float squeeze;

//void vertex() {
	//if (VERTEX.y < 0.0){
		//VERTEX.x *= squeeze;
	//} else {
		//VERTEX.x /= squeeze;
	//}
	////COLOR.rgb = vec3(1.0, 0.0, 0.0);
//}

void fragment() {
	float uvy = UV.y;
	if (squeeze > 0.0) {
		uvy = 1.0 - uvy;
	}
	float ysqz = sign(squeeze) * squeeze * uvy;
	float x = (UV.x - (ysqz / 2.0)) / (1.0 - ysqz);
	if (x < 0.0 || x > 1.0) {
		COLOR.a = 0.0;
	} else {
		COLOR = texture(TEXTURE, vec2(x, UV.y));
	}
}

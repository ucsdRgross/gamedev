shader_type spatial;

//skew model torwards camera
void vertex() {
	vec3 _Skew = vec3(0, 0.2, 0.2);
	VERTEX.y += _Skew.y * VERTEX.z * VERTEX.y;
	VERTEX.z -= _Skew.z * VERTEX.y;
}

void fragment() {
	ALBEDO = vec3(0.1, 0.0, 1.0);
}
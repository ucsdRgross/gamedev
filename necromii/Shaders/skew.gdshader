shader_type spatial;

const vec3 skew = vec3(0.0, 0.25, -0.40);
//skew model torwards camera
void vertex() {
	vec3 s = (vec4(skew, 0.0) * MODELVIEW_MATRIX).xyz;
	VERTEX += s * VERTEX.y;
}
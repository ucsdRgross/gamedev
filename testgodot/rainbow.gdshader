shader_type spatial;
render_mode unshaded;

void fragment() {
	ALBEDO = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

shader_type spatial;

render_mode world_vertex_coords;

//skew model torwards camera
uniform float skew_factor = 0.5;
void vertex() {
	VERTEX.z -= VERTEX.y * skew_factor;
	VERTEX.z += NODE_POSITION_WORLD.y * skew_factor;
}
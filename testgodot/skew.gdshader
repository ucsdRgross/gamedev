shader_type spatial;

render_mode world_vertex_coords;
uniform float skew_factor = 1.0;
void vertex() {
	VERTEX.z -= VERTEX.y * skew_factor;
	VERTEX.z += NODE_POSITION_WORLD.y * skew_factor;
}
shader_type spatial;
render_mode unshaded;
uniform sampler2D depth_texture : source_color, hint_depth_texture;
uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;
varying mat4 CAMERA;
// focal point of camera in world space
// change this in code to follow where camera is looking at, or follow player position
uniform vec3 focal_point = vec3(0.0);
// depth of field / width of focal plane in meters
uniform float DoF = 5.0;
// maximum amount of blur based off of distance from focal plane
uniform float blur_cap: hint_range(0.0,8.0) = 2.0;
// how quickly blur occurs away from focal plane
// bigger number is slower, smaller number is faster
uniform float blur_rate = 2.0;
// multiples y vector of focal plane to make it less or more vertical
// value of 1.0 is no change, 0.0 will make focal plane vertical regardless of camera angle
// focal plane is typically perpendicular to camera view, 
// but a more vertical focal plane may sometimes look better
// if we want background to blur consistently regardless of distance to plane
// ex: tall buildings show up focused in background because they are technically equally close
uniform float vertical_bias = 1.0;

void vertex() {
	POSITION = vec4(VERTEX, 1.0);
	CAMERA = INV_VIEW_MATRIX;
}

float PlanePointDist(vec3 pn, vec3 pp, vec3 p){
	float d = -(pn.x * pp.x + pn.y * pp.y + pn.z * pp.z);
	float a = abs((pn.x * p.x + pn.y * p.y + pn.z * p.z + d));
    float b = sqrt(pn.x * pn.x + pn.y * pn.y + pn.z * pn.z);
	return a/b;
}

void fragment() {
	float depth = texture(depth_texture, SCREEN_UV).x;
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, depth);
	vec4 view = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	view.xyz /= view.w;
	float linear_depth = -view.z;
	vec4 world = CAMERA * INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	vec3 world_position = world.xyz / world.w;
	vec3 focal_plane_normal = focal_point - CAMERA_POSITION_WORLD;
	focal_plane_normal.y *= vertical_bias;
	float dist_to_plane = PlanePointDist(focal_plane_normal, focal_point, world_position);
	float blur_amount = clamp((dist_to_plane-DoF)/blur_rate, 0.0, blur_cap);
	vec4 color = textureLod(screen_texture, SCREEN_UV, blur_amount);
	ALBEDO = color.xyz;
}
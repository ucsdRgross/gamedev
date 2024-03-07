shader_type spatial;
render_mode unshaded;

float sphIntersect( vec3 ro, vec3 rd, vec4 sph )
{
    vec3 oc = ro - sph.xyz;
    float b = dot( oc, rd );
    float c = dot( oc, oc ) - sph.w*sph.w;
    float h = b*b - c;
    if( h<0.0 ) return -1.0;
    h = sqrt( h );
    return -b - h;
}


void fragment() {
	// Get fragment position in world space coordinates
	vec3 frag_pos = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	// Get the camera direction by sustracting the camera position from the fragment position
	vec3 camera_ray = normalize(frag_pos - CAMERA_POSITION_WORLD);
	// Get transformed ray direction
	vec3 model_ray = normalize((inverse(MODEL_MATRIX) * vec4(camera_ray, 0.0)).xyz);
	// Get transformed origin
	vec3 ray_origin = (inverse(MODEL_MATRIX) * vec4(CAMERA_POSITION_WORLD, 1.0)).xyz;
	// Calculate sphere hit
	float ray_hit = sphIntersect(ray_origin,model_ray,vec4(vec3(0.0),0.5));
	
	if (ray_hit != -1.0){
		ALBEDO = vec3(mod(UV,vec2(1.0/3.0, 1.0/2.0)) * vec2(3.0, 2.0), 0.0); 
	} else {
		ALPHA = 0.0;
	}
}

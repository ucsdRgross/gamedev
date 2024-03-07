/*
	Toon Shader by Firerabbit
	
	MIT License
*/

shader_type spatial;
render_mode ambient_light_disabled;

uniform vec4 color : source_color = vec4(1.0);
uniform sampler2D tex : source_color, hint_default_white;

uniform float shadow : hint_range(0.0, 1.0) = 0.5;
uniform float shadow_width : hint_range(0.001, 0.5) = 0.0;
uniform vec4 shadow_color: source_color = vec4(0.705);

uniform float _specular_smoothness : hint_range(0.0,0.5) = 0.01;
uniform float _specular_strength : hint_range(0.0,0.25) = 0.075;
uniform float _glossiness : hint_range(0.0,0.5) = 0.1;

uniform float _rim_size : hint_range(0,1) = 0.5;
uniform float _rim_smoothness : hint_range(0.0,0.5) = 0.01;

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
	// With a chosen face of cube as front, find ray intersection with image
	
	
	float ray_hit = sphIntersect(CAMERA_POSITION_WORLD,camera_ray,vec4(NODE_POSITION_WORLD,1.0));
	if (ray_hit != -1.0){
		vec3 world_pos = camera_ray * ray_hit + CAMERA_POSITION_WORLD;
		vec3 world_normal = normalize(frag_pos - NODE_POSITION_WORLD);
		ALBEDO = vec3(1.0, 1.0, 1.0);
		//ALBEDO = vec3(mod(UV,vec2(1.0/3.0, 1.0/2.0)) * vec2(3.0, 2.0), 0.0); 
	} else {
		ALPHA = 0.0;
	}
	ALBEDO = pow(texture(tex, UV).rgb, vec3(2.2)) * color.rgb;
}


void light() {
	float NdotL = dot(NORMAL, LIGHT) * ATTENUATION;
	NdotL = smoothstep(shadow - shadow_width, shadow + shadow_width, NdotL);
	
	// specular
	vec3 H = normalize(VIEW + LIGHT);
	float NdotH = max(0, dot(NORMAL, H));
	float specular_intensity = pow(NdotH, 1.0 / _glossiness);
	vec3 specular = vec3(smoothstep(0.5 - _specular_smoothness, 0.5 + _specular_smoothness, specular_intensity));
	
	// rim
	float rimDot = 1.0 - dot(VIEW, NORMAL);
	float rim_intensity = rimDot * NdotL;
	vec3 rim = vec3(smoothstep(1.0 -_rim_size - _rim_smoothness, 1.0 -_rim_size + _rim_smoothness, rim_intensity));
	
	DIFFUSE_LIGHT = mix(ALBEDO * shadow_color.rgb, (ALBEDO + (rim + specular) * _specular_strength) * LIGHT_COLOR.rgb * 0.33, NdotL + 0.33 * (smoothstep(1.0 -_rim_size - _rim_smoothness, 1.0 -_rim_size + _rim_smoothness, rimDot)));
}
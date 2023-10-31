shader_type canvas_item;

uniform sampler2D turbulent_texture;
uniform sampler2D pigment_texture;
uniform sampler2D paper_texture;
uniform float turbulent_scale = 0.5;
uniform float pigment_scale = 1.0;
uniform float paper_scale = 1.5;
uniform float edge_detection = 0.3;

//https://www.w3.org/TR/WCAG21/#dfn-relative-luminance
vec3 adjustSaturation(vec3 color, float value) {
  const vec3 luminosityFactor = vec3(0.2126, 0.7152, 0.0722);
  vec3 grayscale = vec3(dot(color, luminosityFactor));

  return mix(grayscale, color, 1.0 + value);
}

float applyTextureHelper(float c, float noise, float scale) {
	float density = 1.0 + (scale * (noise - 0.5));
	float new_c = c * (1.0 - (1.0 - c) * (density - 1.0));
	return new_c;
}

vec3 applyTexture(vec3 color, vec2 uv, sampler2D noise, float scale) {
	vec3 new_color;
	vec4 noise_color = texture(noise, uv);
	new_color.r = applyTextureHelper(color.r, noise_color.r, scale);
	new_color.g = applyTextureHelper(color.g, noise_color.g, scale);
	new_color.b = applyTextureHelper(color.b, noise_color.b, scale);
	return new_color;
}

vec3 outliner(vec3 color, float edge_strength) {
	float luminance = dot(color,vec3(0.2126, 0.7152, 0.0722));
	float gradient = fwidth(luminance);
	bool isEdge = gradient > edge_strength;
	vec3 edge;
	if (isEdge){
		edge = vec3(1.0,1.0,1.0);
	}else{
		edge = vec3(0.0,0.0,0.0);
	}
	return edge;
}

uniform float wobbly_strength = 0.15;
//https://godotshaders.com/shader/wobbly-effect-hand-painted-animation/
vec4 wobbly_effect(vec2 uv, sampler2D txt, float wob){
	vec4 offset = texture(paper_texture, uv) * wobbly_strength;
	return texture(txt, uv + offset.xy - vec2(0.5,0.5)*wob*1.85);
}

vec3 alpha_paint(vec3 color){
	//perceived color for emphasis on lighter colors
	float pc = 1.0 - (color.r*0.241 + color.g*0.691 + color.b*0.068);
	vec4 canvas = vec4(1.0,1.0,1.0,1.0);
	vec4 paint = vec4(color, 0.2 + (0.3 * pc));
	return mix(canvas,paint,0.9).rgb;
}           
                                                                 
uniform sampler2D sTextureSamples;                  
uniform float scaleX = 1.0;
uniform float scaleY = 1.0; 
uniform float scaleY2 = 1.0; 
uniform float sigma_r2 = 1.0;

vec3 liquidize(vec3 colorRef, sampler2D txt, vec2 vTexcoord){
	float pc = 1.0 - (colorRef.r*0.241 + colorRef.g*0.691 + colorRef.b*0.068);
	vec3 color = vec3(0.0, 0.0, 0.0);
	float yFetch = vTexcoord.y * scaleY2;
	float weight = 0.0;
	for(int i=0; i<25; i++){
		vec2 coords = texture(sTextureSamples, vec2(float(i) / 30.0, yFetch)).xy;
		coords = (coords - 0.5) * vec2(scaleX, scaleY);
		vec3 colorFetch = texture(txt, coords + vTexcoord).xyz;
		vec3 colorDist = colorFetch - colorRef;
		float tmpWeight = exp(-dot(colorDist, colorDist) / (sigma_r2 * (1.0 - pc)));
		color += colorFetch * tmpWeight;
		weight += tmpWeight;
	}
	if(weight <= 0.0) {
		color = colorRef;
	} else {
		color = color / weight;
	}

	return color.xyz;
}

float colorDistance(vec3 a, vec3 b){
	float rmean = (a.r + b.r) / 2.0;
	float red = a.r - b.r;
	float green = a.g - b.g;
	float blue = a.b - b.b;
	return sqrt(((2.0+rmean/256.0)*red*red) + (4.0 * green * green) + ((2.0+(255.0-rmean)/256.0)*blue*blue));
}

uniform float dark_edges_range;
uniform float dark_edges_darkeness;

vec3 darken_edges(vec3 og, vec3 paint, vec3 edge){
	float edge_luman = dot(edge,vec3(0.2126, 0.7152, 0.0722));
	if (colorDistance(og, paint) > dark_edges_range && edge_luman > 0.0){
		return mix(paint,1.0-edge,dark_edges_darkeness).rgb;
	}
	return paint;
}

void fragment() {
	vec3 og = texture(TEXTURE,UV).rgb;
	//saturate image
	vec3 color = adjustSaturation(og, 3.0);
	color = liquidize(og, TEXTURE, UV);
	//apply textures
	vec3 txt;
	txt = applyTexture(color, UV, turbulent_texture, turbulent_scale);
	txt = applyTexture(txt, UV, pigment_texture, pigment_scale);
	txt = applyTexture(txt, UV, paper_texture, paper_scale);
	//image abstraction (simplifies color pallete)
	//unnecessary for pixel art since it has a small color pallete
	
	//wobble edges and outline 
	vec3 edge = outliner(wobbly_effect(UV, TEXTURE, wobbly_strength).rgb, edge_detection);
	//control image (bleed edges into each other, so wobble multiple images and stack them together?)
	
	//render phase
	//apply color with transparency
	vec3 paint = alpha_paint(color);

	//darken edges
	paint = darken_edges(og, paint, edge);
	
	paint = adjustSaturation(paint, 0.5);
	
	vec4 color_with_alpha = vec4(paint,texture(TEXTURE,UV).a);
	COLOR = color_with_alpha;
}

void vertex() {
  // Animate Sprite moving in big circle around its location
  //VERTEX += vec2(cos(TIME)*0.5, sin(TIME)*0.3);
}
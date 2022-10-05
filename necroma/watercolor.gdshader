shader_type canvas_item;

uniform sampler2D turbulent_texture;
uniform sampler2D pigment_texture;
uniform sampler2D paper_texture;
uniform float turbulent_scale = 1.0;
uniform float pigment_scale = 1.0;
uniform float paper_scale = 1.0;

vec3 adjustSaturation(vec3 color, float value) {
  // https://www.w3.org/TR/WCAG21/#dfn-relative-luminance
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


void fragment() {
	//saturate image
	vec3 color = adjustSaturation(texture(TEXTURE,UV).rgb, 2.0);
	//apply textures
	color = applyTexture(color, UV, turbulent_texture, turbulent_scale);
	color = applyTexture(color, UV, pigment_texture, pigment_scale);
	color = applyTexture(color, UV, paper_texture, paper_scale);
	
	vec4 color_with_alpha = vec4(color,texture(TEXTURE,UV).a);
	COLOR = color_with_alpha;
}

void vertex() {
  // Animate Sprite moving in big circle around its location
  VERTEX += vec2(cos(TIME)*0.5, sin(TIME)*0.3);
}
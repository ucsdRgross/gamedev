shader_type canvas_item;

vec3 adjustSaturation(vec3 color, float value) {
  // https://www.w3.org/TR/WCAG21/#dfn-relative-luminance
  const vec3 luminosityFactor = vec3(0.2126, 0.7152, 0.0722);
  vec3 grayscale = vec3(dot(color, luminosityFactor));

  return mix(grayscale, color, 1.0 + value);
}

void fragment() {
	vec4 color = vec4(adjustSaturation(texture(TEXTURE,UV).rgb, 1.0),texture(TEXTURE,UV).a);
	COLOR = color;
}
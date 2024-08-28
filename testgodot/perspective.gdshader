shader_type canvas_item;

uniform vec2 topleft = vec2(0.01, 0.0);
uniform vec2 topright;
uniform vec2 bottomleft;
uniform vec2 bottomright;

uniform sampler2D SCREEN_TEXTURE : hint_screen_texture;///, filter_linear_mipmap;

float _cross( in vec2 a, in vec2 b ) { return a.x*b.y - a.y*b.x; }

vec2 invBilinear( in vec2 p, in vec2 a, in vec2 b, in vec2 c, in vec2 d ) {
	vec2 res = vec2(-1.0);

	vec2 e = b-a;
	vec2 f = d-a;
	vec2 g = a-b+c-d;
	vec2 h = p-a;

	float k2 = _cross( g, f );
	float k1 = _cross( e, f ) + _cross( h, g );
	float k0 = _cross( h, e );
	
	float w = k1*k1 - 4.0*k0*k2;
	if( w<=0.001 ) return vec2(-1.0);
	w = sqrt( w );
	
	// will fail for k0=0, which is only on the ba edge 
    if(k0<=0.001&&k0>=-0.001) return vec2(-1.0);
    float v = 2.0*k0/(-k1 - w); 
    if( v<0.0 || v>1.0 ) v = 2.0*k0/(-k1 + w);

    float ta = (e.x + g.x*v);
    ta+=0.001*(1.-abs(sign(ta)));
    float u = (h.x - f.x*v)/ta;
    if( u<0.0 || u>1.0 || v<0.0 || v>1.0 ) return vec2(-1.0);
    return vec2( u, v );
}


void fragment(){
	vec2 topleftUV = topleft / vec2(textureSize(TEXTURE,0));  // compensates for screensize ratio
	vec2 toprightUV = vec2(1.0,0.0)+topright / vec2(textureSize(TEXTURE,0));
	vec2 bottomrightUV = vec2(1.0,1.0)+bottomright / vec2(textureSize(TEXTURE,0));
	vec2 bottomleftUV =vec2(0.0,1.0)+ bottomleft / vec2(textureSize(TEXTURE,0));

	vec2 newUV = invBilinear(UV, topleftUV, toprightUV, bottomrightUV, bottomleftUV);
	
	if (topleft.x == 0.0 || topright.x == 0.0) {
		COLOR = texture(SCREEN_TEXTURE, UV);
	}
	else {
		if (newUV == vec2(-1.0)){
			COLOR = vec4(0.0);
		}else {
			COLOR = texture(SCREEN_TEXTURE, newUV);
		}
	}
}
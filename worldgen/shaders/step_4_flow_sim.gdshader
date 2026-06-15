shader_type canvas_item;
// blend_disabled: this is a DATA pass, not a visual one. Without it the viewport
// alpha-blends our fragment over the background, scaling RGB by alpha and
// corrupting the data channels (momentum lives in alpha here).
render_mode blend_disabled;

// Phase 1 hydraulic flow simulation (Step 4).
//
// Droplet heads live IN the map: each pixel of `prev_state` stores
//   R = carved height, G = head weight (0 = no head), B,A = momentum vector.
// Each tick every pixel gathers its 8 neighbours and "receives" any head whose
// movement vector points into it. Converging heads sum their weights (so large
// rivers only form where many droplets meet). Each pixel writes only itself, so
// no scatter is needed. Heads carve the height they pass through; they vanish
// only on reaching an ACTUAL ocean pixel (base height < ocean_threshold).
uniform sampler2D prev_state; // r=height, g=weight, b=mom.x, a=mom.y
uniform sampler2D base_tex;   // r=H0 (un-eroded height, for the real sea test)
uniform float ocean_threshold = 0.38;
uniform float inertia = 1.2;       // how strongly accumulated weight keeps a river straight
uniform float carve_rate = 0.02;   // height removed per unit weight per tick
uniform float carve_depth = 0.25;  // max groove depth below base height

// Snap a direction to the nearest of the 8 grid neighbours (integer offset).
vec2 dir8(vec2 d) {
	if (length(d) < 1e-5) return vec2(0.0);
	float ang = round(atan(d.y, d.x) / (PI / 4.0)) * (PI / 4.0);
	return vec2(round(cos(ang)), round(sin(ang)));
}

void fragment() {
	vec2 texel = 1.0 / vec2(textureSize(prev_state, 0));
	vec4 self = texture(prev_state, UV);
	float self_h = self.r;
	float base_h = texture(base_tex, UV).r;

	// Gather heads flowing INTO this pixel from the 8 neighbours.
	float in_weight = 0.0;
	vec2 in_mom = vec2(0.0);
	for (int oy = -1; oy <= 1; oy++) {
		for (int ox = -1; ox <= 1; ox++) {
			if (ox == 0 && oy == 0) continue;
			vec2 noff = vec2(float(ox), float(oy));
			vec2 nuv = UV + noff * texel;
			vec4 nst = texture(prev_state, nuv);
			float nw = nst.g;
			if (nw <= 0.0) continue;

			// Neighbour's flow direction = downhill (of carved height) + momentum.
			float hL = texture(prev_state, nuv - vec2(texel.x, 0.0)).r;
			float hR = texture(prev_state, nuv + vec2(texel.x, 0.0)).r;
			float hD = texture(prev_state, nuv - vec2(0.0, texel.y)).r;
			float hU = texture(prev_state, nuv + vec2(0.0, texel.y)).r;
			// Heights live in 0..1 so raw gradients are tiny; use the DIRECTION of
			// downhill (normalized) so terrain — not magnitude — steers the head.
			// On flat ground (no slope) keep the head's previous heading.
			vec2 downhill = -vec2(hR - hL, hU - hD);
			float dhlen = length(downhill);
			vec2 dh_dir = (dhlen > 1e-7) ? downhill / dhlen : nst.ba;
			// Momentum (already stored normalized) only smooths the path; inertia
			// stays < 1 so downhill dominates and rivers follow valleys / converge
			// instead of shooting in straight grid lines.
			vec2 d = dh_dir + nst.ba * inertia;
			// It flows into us iff its chosen neighbour offset equals -noff.
			if (dir8(d) == -noff) {
				in_weight += nw;
				in_mom += normalize(d + vec2(1e-6)) * nw;
			}
		}
	}

	float new_weight = in_weight;
	vec2 new_mom = (in_weight > 0.0) ? in_mom / in_weight : vec2(0.0);

	// Real sea termination (revision 5): heads vanish only on a genuine ocean
	// pixel, never merely because they carved below sea level mid-path.
	if (base_h < ocean_threshold) {
		new_weight = 0.0;
		new_mom = vec2(0.0);
	}

	// Carve the height this water passes through (deeper for heavier rivers).
	float new_h = self_h;
	if (new_weight > 0.0) {
		new_h = max(self_h - carve_rate * new_weight, base_h - carve_depth);
	}

	COLOR = vec4(new_h, new_weight, new_mom.x, new_mom.y);
}

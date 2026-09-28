shader_type canvas_item;
// THE CARD OUTLINE SHADER, for the card's face (`Type`), its rank / suit / stamp pips and its art:
// a solid 8-directional rim in a palette colour around whatever its frame draws, plus the recolour,
// because a Polygon2D has one material and the rank pip and card art need both.

// THE POLYGON IS BIGGER THAN THE ART: a fragment can only write inside its polygon, so every client
// holds `u_outline_width` units of margin past its frame. `CardOutline.frame_polygon` UVs them.

// ⚠ TAP IN UV SPACE VIA `TEXTURE_PIXEL_SIZE`, never `SCREEN_UV`/`FRAGCOORD`: the rig skins vertices
// and leaves UVs, so only a texture-space rim rides the deformation. A screen-space one detaches
// from stretched art and passes every rest-pose check.

// ⚠ `vertex()` ONLY COPIES `COLOR` INTO A VARYING, NEVER TOUCHES `VERTEX`: Godot's 2D skinning is
// applied before it (measured: a posed card's drawn extents are identical with and without it).

// ⚠ NEAREST FILTERING, NO MIPMAPS, or the taps blur and the clamp leaks neighbouring texels.
// ⚠ NEVER PASS `TEXTURE` TO A FUNCTION: GLES3 compiles it and the EDITOR's compiler rejects it, so
// the suite goes green on a shader every `@tool` host fails to load. Tap inline.

// "The rim is exactly one unit" is a REST-POSE claim: deformed, it thickens with its cell, which is
// wanted. Any test asserting thickness must PIN THE POSE.

// ⚠ THE FRAME CLAMP IS NOT OPTIONAL: the sheets have no gutter, so every tap is tested against
// `u_frame_uv`. Measured: 13/13 rank, 18/19 suit-pip and 3/3 stamp frames touch their edge, where a
// missing clamp is loud; the 32x32 sheets (2/52) are where it hides.

// The palette image and its width arrive as uniforms from PaletteDB, never as shader defaults, so
// swapping the palette recolours everything.
uniform sampler2D u_palette : source_color, filter_nearest, repeat_disable;
uniform int u_num_colors = 32;

// This element's frame in NORMALIZED sheet UV: (min.x, min.y, max.x, max.y). Everything outside is
// another frame's art and is read as alpha 0.
uniform vec4 u_frame_uv = vec4(0.0, 0.0, 1.0, 1.0);
// Rim thickness in SOURCE TEXELS, which on a card is also art units. `CardOutline` derives the
// polygon's padding from the same constant, so the two cannot disagree.
uniform int u_outline_width : hint_range(0, 4) = 1;
// The rim's palette entry: ONE ink per card, authored on the card's TYPE.
uniform int u_outline_index : hint_range(0, 255) = 28;

// 0 = the texture's own colours; 1 = flatten to `u_fill_index`. Not a style choice: the pip and
// type sheets are authored IN the palette and shaded, while the rank pip and card art are
// suit-agnostic silhouettes that must take the suit's role.
uniform int u_fill_mode : hint_range(0, 1) = 0;
uniform int u_fill_index : hint_range(0, 255) = 0;

// An EQUAL-CHANNEL multiplier on this element's BODY, so a lit element goes toward white with no
// colour cast; 1.0 is unlit. ⚠ THE RIM IS EXCLUDED: focus is drawn there at its own ink, so a card
// that is legal AND focused is outlined once and not brightened twice.
uniform float u_brighten = 1.0;

// This polygon's centre in CARD coordinates, and the card's extent, so all five polygons evaluate
// the alert against ONE coordinate and show one band. 1 texel = 1 art unit makes local -> card a
// pure translation, pushed per polygon by `CardOutline`, so the band rides the art's texels.
uniform vec2 u_card_offset = vec2(0.0);
uniform vec2 u_card_extent;

// The alert kind, in `CardOutline.Alert`'s order: 0 none, 1 GLARE, 2 THROB, 3 SHIMMER. ⚠ NO `TIME`:
// `u_alert_clock` is a PHASE in turns that `CardVisual._process` advances over a fraction of
// `get_delay()`, so the cue scales with the cascade it announces.
uniform int u_alert_kind : hint_range(0, 3) = 0;
uniform float u_alert_clock = 0.0;
uniform int u_alert_color : hint_range(0, 255) = 31;
// GLARE band thickness, in CARD-SPACE art units.
uniform float u_alert_thickness = 8.0;
// GLARE DEAD ZONE at each SIDE of the card: clamps the band's travel AND suppresses the glare
// beyond it, so the band tapers instead of clipping. Why side rims blink without it:
// `OutlineStyle.glare_buffer`.
uniform float u_alert_buffer = 0.0;
// SHIMMER's colours: an N x 1 strip built from a `PaletteRamp` by `OutlineStyle.shimmer_texture()`.
uniform sampler2D u_shimmer_ramp : source_color, filter_nearest, repeat_disable;

// The host's `modulate` reaches `fragment()` only through this varying: the built-in COLOR there is
// already multiplied by the texel under UV, and on the rim that texel is empty.
varying vec4 v_modulate;

void vertex() {
	v_modulate = COLOR;
}

const int ALERT_NONE  = 0;
const int ALERT_GLARE = 1;
const int ALERT_THROB = 2;
const int ALERT_SHIMMER = 3;

/// One entry of the live palette, sampled at the entry's CENTRE.
vec3 palette_rgb(int idx) {
	return texture(u_palette, vec2((float(idx) + 0.5) / float(u_num_colors), 0.5)).rgb;
}

/// Is `uv` inside THIS element's frame? The rest of the sheet is neighbouring frames.
bool in_frame(vec2 uv) {
	return uv.x >= u_frame_uv.x && uv.y >= u_frame_uv.y
		&& uv.x <  u_frame_uv.z && uv.y <  u_frame_uv.w;
}

// ⚠ THERE IS DELIBERATELY NO `frame_alpha(...)` HELPER: `TEXTURE` is a `fragment()`-local built-in,
// unknown inside a user function, and passing it in as a `sampler2D` breaks the editor's compiler.
// The taps are inline in `fragment()`, and `in_frame` carries the clamp on its own.

/// A linear ping-pong on `phase`, HARD at each end: a sine reads as a gentle shine, not an alert.
float bounce(float phase) {
	return abs(fract(phase) * 2.0 - 1.0);
}

// GLARE and THROB are hard-stepped so the ink stays on the palette. SHIMMER is the ONLY lerped ramp
// in this project (owner: sampled steps jump on a rim meant to glow), bounced in reverse so phase 0
// rests on its FIRST entry.

/// The rim's colour at `card_pos`: the card's resting ink, with the live alert applied over it.
vec3 alert_ink(vec2 card_pos) {
	vec3 ink = palette_rgb(u_outline_index);
	if (u_alert_kind == ALERT_GLARE) {
		float limit = max(u_card_extent.x * 0.5 - u_alert_buffer, 0.0);
		float centre = mix(-limit, limit, bounce(u_alert_clock));
		float band = 1.0 - step(u_alert_thickness * 0.5, abs(card_pos.x - centre));
		band *= 1.0 - step(limit, abs(card_pos.x));
		ink = mix(ink, palette_rgb(u_alert_color), band);
	} else if (u_alert_kind == ALERT_THROB) {
		ink = mix(ink, palette_rgb(u_alert_color), step(0.5, bounce(u_alert_clock)));
	} else if (u_alert_kind == ALERT_SHIMMER) {
		int last = textureSize(u_shimmer_ramp, 0).x - 1;
		float t = (1.0 - bounce(u_alert_clock)) * float(last);
		float lo = floor(t);
		float hi = min(lo + 1.0, float(last));
		float span = float(last + 1);
		vec3 from = texture(u_shimmer_ramp, vec2((lo + 0.5) / span, 0.5)).rgb;
		vec3 to = texture(u_shimmer_ramp, vec2((hi + 0.5) / span, 0.5)).rgb;
		ink = mix(from, to, t - lo);
	}
	return ink;
}

// BODY is any texel with alpha > 0, drawn at its OWN alpha, so a translucent face shows what is
// under the card. RIM is an EMPTY texel within `u_outline_width` of body in all eight directions,
// so it never lines a translucent texel. No early return: Godot rejects `return` in `fragment()`.
void fragment() {
	vec2 texel = TEXTURE_PIXEL_SIZE;
	float w = float(u_outline_width);

	vec2 pad_min = u_frame_uv.xy - w * texel;
	vec2 pad_max = u_frame_uv.zw + w * texel;
	vec2 card_pos = (UV - 0.5 * (pad_min + pad_max)) / texel + u_card_offset;

	vec4 src = vec4(0.0);
	if (in_frame(UV)) src = texture(TEXTURE, UV);

	vec4 out_col = vec4(0.0);

	if (src.a > 0.0) {
		vec3 body = (u_fill_mode == 1) ? palette_rgb(u_fill_index) : src.rgb;
		out_col = vec4(body * u_brighten, src.a);
	} else {
		float hit = 0.0;
		for (int dy = -u_outline_width; dy <= u_outline_width; dy++) {
			for (int dx = -u_outline_width; dx <= u_outline_width; dx++) {
				if (dx == 0 && dy == 0) continue;
				vec2 tap = UV + vec2(float(dx), float(dy)) * texel;
				if (in_frame(tap)) hit = max(hit, texture(TEXTURE, tap).a);
			}
		}
		if (hit > 0.0) out_col = vec4(alert_ink(card_pos), 1.0);
	}
	COLOR = out_col * v_modulate;
}

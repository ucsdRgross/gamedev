shader_type canvas_item;
// THE CARD OUTLINE SHADER - one shader, five clients: the card's FACE (`Type`), the rank / suit / stamp
// pips, and the card art. It draws a solid 8-directional rim in a palette colour around whatever its
// frame draws, and ABSORBED `Assets/color_picker.gdshader`'s recolour, because a Polygon2D has one
// material and the rank pip and card art need both.
//
// Rules, landmines and the design record: ARCHITECTURE_REVIEW §4j. What must hold IN HERE:
//
//  1. THE POLYGON IS BIGGER THAN THE ART. A canvas fragment shader can only write inside its own
//     polygon, so every client holds `u_outline_width` units of margin past its frame -
//     `CardOutline.frame_polygon` is the only supported way to UV one.
//  2. ⚠ TAP IN UV SPACE VIA `TEXTURE_PIXEL_SIZE`, never `SCREEN_UV`/`FRAGCOORD`. All five polygons are
//     skinned to the card's autoplaying star rig; bone weights move VERTEX POSITIONS and leave UVs
//     alone, so a texture-space rim rides the deformation. A screen-space one holds constant SCREEN
//     thickness while the art stretches and DETACHES - and passes every rest-pose check.
//     (This is the OPPOSITE of `fire`/`glow`, which quantize on a WORLD grid so their pixels do not
//     crawl under a moving card. Different job: those are not attached to the art's texels.)
//  3. ⚠ WRITE NO `vertex()`. Godot applies 2D skinning there and this needs none.
//  4. ⚠ NEAREST FILTERING, NO MIPMAPS, or the taps blur and the frame clamp leaks fractional texels
//     from neighbouring frames. Already correct project-wide - a DON'T-REGRESS item, not a task.
//  5. ⚠ NEVER PASS `TEXTURE` TO A FUNCTION. It compiles on GLES3 and the EDITOR's compiler rejects it,
//     so the whole suite can go green on a shader every `@tool` host fails to load. Tap inline.
//
// "The rim is exactly one unit" is a REST-POSE claim: deformed, it thickens with its cell, which is the
// behaviour to want. Any test asserting thickness must PIN THE POSE.
//
// ⚠ THE FRAME CLAMP IS NOT OPTIONAL. The sheets are packed edge to edge with no gutter, so the padded
// window overlaps four neighbouring frames and every tap must be tested against `u_frame_uv`. Measured:
// 13/13 rank, 18/19 suit-pip and 3/3 stamp frames have art touching their frame edge, so a missing
// clamp is LOUD there - and the 32x32 sheets are sparse (2/52), which is where a subtly wrong one hides.

// ── THE PALETTE ───────────────────────────────────────────────────────────────────────────────────
// Both the image and its width arrive as uniforms from PaletteDB, never as shader defaults. The
// VisualShader this pattern replaced had the palette baked into itself and a hand-kept `num_colors`,
// so swapping the palette recoloured nothing (ARCHITECTURE_REVIEW §4h).
uniform sampler2D u_palette : source_color, filter_nearest, repeat_disable;
uniform int u_num_colors = 32;

// ── THE FRAME ─────────────────────────────────────────────────────────────────────────────────────
// This element's frame in NORMALIZED sheet UV: (min.x, min.y, max.x, max.y). Everything outside is
// another frame's art and is read as alpha 0.
uniform vec4 u_frame_uv = vec4(0.0, 0.0, 1.0, 1.0);
// Rim thickness in SOURCE TEXELS, which on a card is also art units. The polygon's padding must match
// it — `CardOutline` derives both from the one constant so they cannot disagree.
uniform int u_outline_width : hint_range(0, 4) = 1;
// The rim's palette entry. ONE ink per card (design D7), authored on the card's TYPE.
uniform int u_outline_index : hint_range(0, 255) = 28;

// ── THE BODY ──────────────────────────────────────────────────────────────────────────────────────
// 0 = the texture's own colours; 1 = flatten to `u_fill_index`. Which an element uses is not a style
// choice - the pip and type sheets are authored IN the palette and already shaded, while the rank pip
// and card art are suit-agnostic silhouettes that must take the suit's role (§4h).
uniform int u_fill_mode : hint_range(0, 1) = 0;
uniform int u_fill_index : hint_range(0, 255) = 0;

// ── CARD SPACE ────────────────────────────────────────────────────────────────────────────────────
// This polygon's centre in CARD coordinates, and the card's extent. Together they let all five polygons
// evaluate the alert against ONE coordinate, so a card shows a single band rather than five local
// sweeps (design D9). One vec2 per polygon, because 1 texel = 1 art unit makes local -> card a pure
// TRANSLATION - and it is the node's own position, pushed by `CardOutline`, so there is no second copy.
// ⚠ REST card space, not deformed: reading true deformed position needs a varying from the vertex
// stage, which rule 3 forbids. The two constraints agree.
uniform vec2 u_card_offset = vec2(0.0);
uniform vec2 u_card_extent = vec2(40.0, 54.0);

// ── THE ALERT ─────────────────────────────────────────────────────────────────────────────────────
// A status announcing that its card is about to act - a MODE, not a colour (design D6). Tuning lives in
// `OutlineStyle`.
// ⚠ NO `TIME`. The built-in is banned project-wide for ignoring the game's pacing; every shader here
// takes a script-driven clock (`fire`, `juggle`). `u_alert_clock` is a PHASE in turns, advanced by
// `CardVisual._process` over a fraction of `get_delay()`, so the cue scales with the cascade it
// announces.
uniform int u_alert_kind : hint_range(0, 2) = 0;   // 0 = none, 1 = GLARE, 2 = THROB
uniform float u_alert_clock = 0.0;
uniform int u_alert_color : hint_range(0, 255) = 31;
// GLARE band thickness, in CARD-SPACE art units — a card-wide quantity now, not a per-element one.
uniform float u_alert_thickness = 8.0;
// GLARE DEAD ZONE at each SIDE of the card. It does two things with one number - clamps the band's
// travel AND suppresses the glare beyond that limit, so the band tapers instead of clipping. Why a
// card's side rims blink without it: `OutlineStyle.glare_buffer`.
uniform float u_alert_buffer = 0.0;

const int ALERT_NONE  = 0;
const int ALERT_GLARE = 1;
const int ALERT_THROB = 2;

/// One entry of the live palette. `+ 0.5` lands on the entry's CENTRE rather than its left edge.
vec3 palette_rgb(int idx) {
	return texture(u_palette, vec2((float(idx) + 0.5) / float(u_num_colors), 0.5)).rgb;
}

/// Is `uv` inside THIS element's frame? Everything else in the sheet belongs to a neighbouring frame.
bool in_frame(vec2 uv) {
	return uv.x >= u_frame_uv.x && uv.y >= u_frame_uv.y
		&& uv.x <  u_frame_uv.z && uv.y <  u_frame_uv.w;
}

// ⚠ **THERE IS DELIBERATELY NO `frame_alpha(...)` HELPER, AND IT TOOK TWO ATTEMPTS TO LEARN WHY.**
// `TEXTURE` is a `fragment()`-local BUILT-IN in Godot's shading language, not a global:
//
//   * reading it inside a user function fails outright — *"Unknown identifier in expression:
//     'TEXTURE'"*;
//   * and passing it IN as a `sampler2D` argument compiles fine on the GLES3 runtime path but trips
//     the EDITOR's shader compiler — *"Condition
//     `!actions.custom_samplers.has(function->arguments[j].tex_builtin)` is true"*. The game ran, the
//     whole test suite went green, and every `@tool` host that previews this shader threw errors.
//     ⚠ That asymmetry is the thing to remember: **a shader can be correct everywhere the tests look
//     and still be broken in the editor**, and the editor is where the art is judged.
//
// The tap is therefore INLINE in `fragment()` below, and `in_frame` carries the clamp on its own —
// which was the only thing the helper was buying.

/// A sharp ping-pong on `phase`: 0 -> 1 -> 0 with a HARD reversal at each end. Deliberately a linear
/// triangle rather than a sine — the owner chose bouncing over a repeating sweep because it "gives
/// more an alert feel", and a sine eases into each end and reads as a gentle shine instead.
float bounce(float phase) {
	return abs(fract(phase) * 2.0 - 1.0);
}

/// The rim's colour at `card_pos`: the card's resting ink, with the live alert applied over it.
vec3 alert_ink(vec2 card_pos) {
	vec3 ink = palette_rgb(u_outline_index);
	if (u_alert_kind == ALERT_GLARE) {
		// A thick band sweeping the CARD and bouncing L<->R. Because the coordinate is card space, a
		// 10-unit pip shows only the slice of the card-wide band that crosses its own rim — which is
		// what makes five polygons read as one glare instead of five.
		//
		// ⚠ A pip is 10 units of a ~40-unit sweep, so a pip FLASHES for roughly a quarter of the pass
		// rather than glowing steadily. That IS "one single glare", but it is a different read from a
		// per-element one, and it is the first thing to look at on the outline atlas tool.
		// The sweep's endpoints are pulled IN by the buffer, so the band's centre never reaches the
		// card's vertical sides — see `u_alert_buffer` for why that is a blink and not a taste call.
		float limit = max(u_card_extent.x * 0.5 - u_alert_buffer, 0.0);
		float centre = mix(-limit, limit, bounce(u_alert_clock));
		// Hard-edged, not smoothstepped: this is a pixel-art game and a feathered band would put
		// off-palette intermediates on a one-texel rim.
		float band = 1.0 - step(u_alert_thickness * 0.5, abs(card_pos.x - centre));
		// And suppressed outright inside the dead zone, so the band's trailing half TAPERS as it nears
		// a side rather than clipping against it. Clamping the travel alone would still let a thick
		// band's tail cover the whole rim at the turn.
		band *= 1.0 - step(limit, abs(card_pos.x));
		ink = mix(ink, palette_rgb(u_alert_color), band);
	} else if (u_alert_kind == ALERT_THROB) {
		// The whole rim toggles between its resting ink and the alert's own entry. QUANTIZED rather
		// than blended for the same reason the band is hard-edged: a continuous mix between two
		// palette entries spends most of its time on colours that are in no palette at all.
		ink = mix(ink, palette_rgb(u_alert_color), step(0.5, bounce(u_alert_clock)));
	}
	return ink;
}

void fragment() {
	vec2 texel = TEXTURE_PIXEL_SIZE;
	float w = float(u_outline_width);

	// The padded window this polygon's bounding box maps onto: the frame grown by the rim on all four
	// sides. Derived from the frame and the width rather than taken as a uniform, because
	// `CardOutline.frame_polygon` built the UVs from exactly these two facts — deriving it here means
	// there is no third copy that can disagree with them.
	vec2 pad_min = u_frame_uv.xy - w * texel;
	vec2 pad_max = u_frame_uv.zw + w * texel;
	// This fragment in the CARD's coordinates. One coordinate, five polygons, one band (D9).
	// Distance from the window's centre in TEXELS is distance in art units, by the 1:1 rule above, so
	// this is a divide and a translation — no per-element scale term to get wrong.
	vec2 card_pos = (UV - 0.5 * (pad_min + pad_max)) / texel + u_card_offset;

	vec4 src = vec4(0.0);
	if (in_frame(UV)) src = texture(TEXTURE, UV);

	// ⚠ Structured as one assignment rather than early returns: Godot's shading language rejects
	// `return` inside `fragment()` outright ("Using 'return' in the 'fragment' processor function is
	// incorrect"), so the guard-clause shape this wants to be written in is not available.
	// Everything not art and not rim stays fully transparent — that is the padding ring the polygon
	// holds for a rim it did not need on this side.
	vec4 out_col = vec4(0.0);

	if (src.a > 0.5) {
		// BODY. The source alpha is authored 1-bit on every sheet here, so a hard cut is exact and
		// keeps the rim from having to blend against a fringe that does not exist.
		out_col = vec4((u_fill_mode == 1) ? palette_rgb(u_fill_index) : src.rgb, 1.0);
	} else {
		// RIM. Eight-directional and exactly `u_outline_width` texels: a diagonal-only contact must
		// still produce its corner pixel, which is what separates this from a 4-tap version that
		// passes a naive "is there an outline" check and leaves every diagonal notched.
		//
		// The bounds are UNIFORM, so the loop costs 8 taps at the shipped width rather than a fixed
		// worst-case neighbourhood — and there is no divergence, since every fragment on the quad
		// iterates identically.
		float hit = 0.0;
		for (int dy = -u_outline_width; dy <= u_outline_width; dy++) {
			for (int dx = -u_outline_width; dx <= u_outline_width; dx++) {
				if (dx == 0 && dy == 0) continue;
				vec2 tap = UV + vec2(float(dx), float(dy)) * texel;
				// THE CLAMP: everything outside this element's own frame is another frame's art and
				// reads as empty. Tested BEFORE the sample, so a tap over a neighbour costs nothing.
				if (in_frame(tap)) hit = max(hit, texture(TEXTURE, tap).a);
			}
		}
		if (hit > 0.5) out_col = vec4(alert_ink(card_pos), 1.0);
	}
	COLOR = out_col;
}

shader_type canvas_item;
render_mode blend_premul_alpha, unshaded;
// THE SPOTLIGHT GLOW — a distance field around a host, coloured by a ramp and drawn at two
// different blends depending on whether it is over the host's own art.
// Design: solatro/design/spotlight/DESIGN.md §14b, chart O (O1-O21). Plan: PLAN.md §1.9.
//
// THE MODEL, IN FOUR LINES:
//
//     d         = signed distance from p to the mask, negative inside      (O5, O6)
//     e         = d + sink                        // the field starts INSIDE the silhouette (Q209=a)
//     intensity = sum over layers of falloff(e / (reach * radius_i)) * gain_i        (O7-O10)
//     COLOR     = texture(u_ramp, intensity) ... premultiplied, see THE BLEND below  (O11-O21)
//
// ⚠ **IT IS NOT A SECOND COPY OF `fire.gdshader`**, and the difference is one question. Fire asks
// *"how far above the nearest surface BELOW me am I"* — directional, answered by `u_taps` downward
// mask lookups, and that call count is the entire cost of that shader. A glow asks *"how far from
// the mask am I, in ANY direction"*, which is one polygon distance (or, for the disc, one
// subtraction). The mask machinery is shared — the same 24-vertex silhouette, the same wedge
// table, the same `fx_common.gdshaderinc` — and the field over it is not.
//
// ===== THE BLEND, WHICH IS THE ONE NON-OBVIOUS DECISION IN THIS FILE ============================
//
// `Q218` asks for **additive OUTSIDE the silhouette, tinted OVER the art**, with the owner's
// condition: *"(c) is fine if it doesnt lead to visible seam between additive and tinted parts,
// otherwise just tint, dont want blowout to white"*. A canvas quad has ONE blend mode for the whole
// material and there is no screen read (DESIGN.md §1.6 fact 1), so "two blends in one pass" looks
// impossible — and with `blend_mix` or `blend_add` it is.
//
// **`blend_premul_alpha` IS EXACTLY BOTH OF THEM, ON A KNOB.** Its equation is
//
//     result = src.rgb + dst * (1 - src.a)
//
// so at `src.a = 0` it is PURE ADDITION, at `src.a = 1` it is an opaque draw, and in between it is
// a true lerp toward `src.rgb / src.a`. The fragment therefore chooses its own blend by choosing
// its alpha: **0 outside the silhouette (additive, correct for a lamp, and harmless because there
// is no art under it) and `u_inner_alpha` over the art (a tint that cannot blow out, which is what
// keeps the rank glyph legible).** The RGB is premultiplied by that alpha on the way out.
//
// ⚠ THE SEAM THE OWNER WARNED ABOUT IS THEREFORE A CONTINUOUS KNOB, NOT A CLIFF — but it is still
// visible if `inner_alpha` is far from 0, because the two sides of the silhouette then genuinely do
// different arithmetic. **This is gate G2.2 and it is an eye call**: render the circle over a busy
// card face, look at the boundary, and if it reads as a seam, raise nothing — set `u_inner_alpha`
// toward 0 or tint both sides. Do not resolve it from a description.
//
// ===== WHAT IS DELIBERATELY ABSENT ==============================================================
//
//  * **No fade.** `Q264`=(a): the glow snaps on and snaps off. There is no `u_fade`, and the style
//    has no fade knob to push into one.
//  * **No animation.** `Q126`=(a): steady. No `u_time` is read here at all — which also means this
//    shader has no pacing hazard, unlike every other effect in the layer.
//  * **No `TIME`.** For the same reason it is banned everywhere else: the built-in ignores the
//    game's own pacing. There is nothing here that needs a clock.
//  * **No prop client.** `Q221` / `Q257`: card, circle and beam only.

#include "res://Shaders/fx_common.gdshaderinc"

// ===== MASK KINDS ===============================================================================
//
// ⚠ **THESE ARE NOT `FxAttachment.Shape`, AND THE NAME `u_mask_kind` IS THE GUARD AGAINST READING
// THEM AS IF THEY WERE.** `fire.gdshader` mirrors that enum exactly (BOX 0, RADII 1, SPRITE 2,
// BALLS 3) because fire's branches ARE the host kinds. A glow's branches are not: a card at rest
// and a deformed card are both "the exact silhouette" here, so `Shape.BOX` and `Shape.RADII`
// collapse into one kind, and the disc — which is not a host kind at all — needs one of its own.
// PLAN.md §1.9 specifies these three values literally, and its neighbouring sentence about
// mirroring `Shape` is prose that the value list contradicts; the values win, and the uniform is
// named differently from fire's `u_shape` so no caller can push one into the other by habit.
const int MASK_OUTLINE = 0;   // the host's exact 24-vertex silhouette — Q124=b
const int MASK_SPRITE  = 1;   // reserved: no client, because props do not glow (Q221, Q257)
const int MASK_DISC    = 2;   // the spotlight circle — QR9=c, and the CHEAP client

// Host art space (0) or the light layer's screen space (1) — Q229=a. It selects ONE thing: whether
// there is host art under this quad at all. On the light layer there is not, so the over-art test
// has nothing to ask and the disc's own radius stands in for the silhouette (see `fragment`).
uniform int u_space = 0;
uniform int u_mask_kind = 0;

// Must match FxAttachment.POLY / WEDGES / WEDGE_CANDIDATES — the same three constants fire
// declares, and `test_fx_attachment` asserts the mirror on both shaders.
const int POLY = 24;
const int WEDGES = 32;
const int WEDGE_CANDIDATES = 4;

uniform vec2 u_extent = vec2(64.0);   // the quad's size in art units; UV maps across exactly this
uniform vec2 u_body = vec2(38.0, 50.0);
uniform vec2 u_inner = vec2(0.0);     // the largest box that fits INSIDE the silhouette
uniform float u_shape_rot = 0.0;
uniform vec2 u_poly[POLY];
uniform float u_wedge[WEDGES];
uniform int u_poly_count = 0;

// ===== THE STYLE'S KNOBS — FxGlowStyle.apply() writes every one of these ========================

const int MAX_LAYERS = 4;             // must match FxGlowStyle.MAX_LAYERS

uniform float u_pixel = 0.5;          // FxGlowStyle.grid, NOT FxStyle.pixel — see that script
uniform float u_dither : hint_range(0.0, 1.0) = 1.0;
uniform float u_reach = 4.0;
uniform float u_sink = 4.0;
uniform int u_layers : hint_range(1, 4) = 2;
uniform float u_layer_radius[MAX_LAYERS];
uniform float u_layer_gain[MAX_LAYERS];
uniform float u_inverse_square : hint_range(0.0, 1.0) = 0.6;
uniform float u_inner_alpha : hint_range(0.0, 1.0) = 0.35;
uniform float u_circle_radius = 16.0;
uniform float u_circle_inner_alpha : hint_range(0.0, 1.0) = 0.5;

// ⚠ **DECLARED, AND THAT IS THE WHOLE POINT** (VFX.md §7.11). `FxAttachment._apply_static` writes
// `u_brightness` with the player's `fx_intensity` already folded in — it is the photosensitivity
// floor, and the ONE way a "reduce effects" setting reaches every effect without editing a `.tres`.
// `juggle.gdshader` does not declare it, so the setting silently misses the balls. Do not repeat it.
uniform float u_brightness = 1.0;
uniform float u_opacity : hint_range(0.0, 1.0) = 1.0;

// The off-palette colour ramp — u = intensity, 0 at the halo's faint outer limit, 1 at the core.
// ⚠ **`filter_linear`, UNLIKE EVERY OTHER RAMP IN THIS PROJECT.** The palette ramps are
// `filter_nearest` because hard columns read as pixel art; light is the granted off-palette
// exception (GAP-003, Q134=b, Q135=b), so it is allowed to be smooth. The chunkiness still arrives,
// from `u_pixel` quantizing the POSITION this is sampled at.
uniform sampler2D u_ramp : source_color, filter_linear, repeat_disable, hint_default_transparent;
uniform float u_ramp_width = 64.0;

// ===== THE MASK =================================================================================
// Shared verbatim with fire.gdshader — same wedge table, same union-of-wedges argument, same
// candidate bound. See that file's header for why it is a union rather than a half-plane per slot
// and why more rays were not the cheap fix.

int wrap_i(int i) { return i >= u_poly_count ? i - u_poly_count : i; }

bool wedge_has(vec2 p, int i) {
	int i0 = wrap_i(i);
	vec2 a = u_poly[i0];
	vec2 b = u_poly[wrap_i(i0 + 1)];
	return a.x * p.y - a.y * p.x >= 0.0
			&& p.x * b.y - p.y * b.x >= 0.0
			&& (b.x - a.x) * (p.y - a.y) - (b.y - a.y) * (p.x - a.x) >= 0.0;
}

bool poly_solid(vec2 p) {
	if (u_poly_count < 3) return false;
	float t = (atan(p.x, -p.y) / TAU + 1.0) * float(WEDGES);
	int slot = int(floor(t)) % WEDGES;
	int w = int(u_wedge[slot]);
	for (int k = 0; k < WEDGE_CANDIDATES; k++) {
		if (wedge_has(p, w + k)) return true;
	}
	return false;
}

// Distance from `p` to the segment a->b. The standard clamped projection; no branches.
float seg_dist(vec2 p, vec2 a, vec2 b) {
	vec2 ab = b - a;
	vec2 ap = p - a;
	float t = clamp(dot(ap, ab) / max(dot(ab, ab), 1e-6), 0.0, 1.0);
	return length(ap - ab * t);
}

// ===== THE FIELD ================================================================================

// SIGNED DISTANCE FROM `p` TO THE MASK — negative inside, positive outside, in ART UNITS.
// `p` arrives quantized in the quad's world-aligned frame; only the LOOKUP is rotated into the
// art's frame, never the grid (the universal rule, fx_common's header).
//
// ⚠ **THE OUTLINE BRANCH IS THIS SHADER'S WHOLE COST**: `u_poly_count` segment distances, up to 24,
// every one of them unconditional because a distance is a MINIMUM and no early-out can be taken
// without knowing the rest. That is a fixed price per lit fragment, unlike fire's, which is why
// `body_near` below matters more here than it does there. The DISC branch is one subtraction, and
// that is why the spotlight circle — the effect that runs over the most pixels — is the cheap one.
float mask_dist(vec2 p) {
	if (u_mask_kind == MASK_DISC) return length(p) - u_circle_radius;
	float c = cos(u_shape_rot);
	float s = sin(u_shape_rot);
	vec2 q = vec2(p.x * c + p.y * s, -p.x * s + p.y * c);
	if (u_mask_kind == MASK_SPRITE || u_poly_count < 3) {
		// No client (props do not glow) and no distance field for an alpha mask. A box stands in, so
		// a mis-wired host draws something recognisable rather than nothing at all.
		vec2 d = abs(q) - u_body * 0.5;
		return length(max(d, vec2(0.0))) + min(max(d.x, d.y), 0.0);
	}
	float best = 1e6;
	for (int i = 0; i < POLY; i++) {
		if (i >= u_poly_count) break;
		best = min(best, seg_dist(q, u_poly[i], u_poly[wrap_i(i + 1)]));
	}
	return poly_solid(q) ? -best : best;
}

// IS `p` INSIDE the mask — the test that picks the blend. Uses the SAME predicate the distance's
// sign comes from, so the two can never disagree along the silhouette.
bool mask_inside(vec2 p) {
	if (u_mask_kind == MASK_DISC) return dot(p, p) <= u_circle_radius * u_circle_radius;
	float c = cos(u_shape_rot);
	float s = sin(u_shape_rot);
	vec2 q = vec2(p.x * c + p.y * s, -p.x * s + p.y * c);
	if (u_mask_kind == MASK_SPRITE || u_poly_count < 3) {
		vec2 h = u_body * 0.5;
		return abs(q.x) <= h.x && abs(q.y) <= h.y;
	}
	if (abs(q.x) <= u_inner.x && abs(q.y) <= u_inner.y) return true;
	return poly_solid(q);
}

// THE EMPTY MAJORITY, REJECTED FIRST (O2) — the same lever fire's `body_near` is, and worth 2.1x
// there. It matters MORE here: what it rejects is an unconditional 24-segment loop.
//
// ⚠ It cannot change a pixel. The field is exactly zero beyond `reach` past the mask, and this
// rejects only fragments further out than that — a quad is the host's circumscribed bound plus
// reach on all four sides, because a card CAN spin, so a card at rest leaves most of its quad empty.
bool field_near(vec2 p) {
	if (u_mask_kind == MASK_DISC) {
		float r = u_circle_radius + u_reach;
		return dot(p, p) <= r * r;
	}
	vec2 h = u_body * 0.5;
	float c = abs(cos(u_shape_rot));
	float s = abs(sin(u_shape_rot));
	vec2 b = vec2(h.x * c + h.y * s, h.x * s + h.y * c) + vec2(u_reach);
	return abs(p.x) <= b.x && abs(p.y) <= b.y;
}

// ONE LAYER'S FALLOFF, as a blend of a smooth curve and a true inverse-square (O7, `Q208`=a).
// `x` is 0 where the layer is at full strength and 1 at its outer limit.
//
// ⚠ **THE INVERSE-SQUARE TERM IS NORMALIZED TO REACH ZERO AT x = 1, and it has to be.** Physical
// `1/(1+kx)^2` is still ~4 % at the limit, and 4 % of a lamp with a hard edge at the quad's border
// is a visible RECTANGLE around every glowing card. Subtracting its own value at the limit and
// rescaling costs two constants and removes the box.
//
// ⚠ This knob is what decides whether the glow reads as A LAMP or as A SMUDGE (`Q208`'s own
// wording): the inverse-square end drops hard and leaves a hot core, the smooth end fades evenly.
float falloff(float x) {
	float t = clamp(x, 0.0, 1.0);
	float smooth_term = (1.0 - t) * (1.0 - t);
	const float K = 4.0;
	const float FLOOR = 1.0 / ((1.0 + K) * (1.0 + K));
	float inv = 1.0 / ((1.0 + K * t) * (1.0 + K * t));
	float inv_term = (inv - FLOOR) / (1.0 - FLOOR);
	return mix(smooth_term, inv_term, clamp(u_inverse_square, 0.0, 1.0));
}

void fragment() {
	vec2 p = fx_local(UV, u_extent, u_pixel);
	if (!field_near(p)) discard;

	float d = mask_dist(p);
	if (d >= u_reach || d <= -max(u_sink, 0.0)) discard;

	// ⚠ **THE FIELD PEAKS ON THE SILHOUETTE AND FALLS AWAY IN BOTH DIRECTIONS**, and getting this
	// wrong is what the first build did. `sink` is *"how far INSIDE the silhouette the field
	// starts"* (`Q209`=a) — its job is that the light is **already at full strength where it crosses
	// the host's edge, so there is no seam there.** An erosion of the distance (`d + sink`, which is
	// what fire's sink is) does the opposite: it spends part of the reach before the edge is even
	// reached, so at the outline the light is a third decayed and the halo outside is invisible.
	// **Measured, 2026-08-04, `09_glow_falloff`: no halo at all outside any of the five panels.**
	//
	// So the two sides use two spans. Outside, the layer's own radius (`Q207`'s multi-exposure).
	// Inside, `sink` — which is also `Q122`=(c)'s INNER LIFT, a rim of light hugging the art's own
	// edge rather than a wash filling the whole card. A card is 38x50 art units and sink ships at 4,
	// so the lift is a border, not a fill.
	float inner_span = max(u_sink, 1e-4);

	// THE MULTI-EXPOSURE SUM (O10): each layer is the same field at its own radius and gain, which
	// is what backlit animation got by exposing one frame through several diffusions.
	float intensity = 0.0;
	for (int i = 0; i < MAX_LAYERS; i++) {
		if (i >= u_layers) break;
		float r = max(u_reach * u_layer_radius[i], 1e-4);
		intensity += falloff(d >= 0.0 ? d / r : -d / inner_span) * u_layer_gain[i];
	}
	intensity = clamp(intensity, 0.0, 1.0);
	if (intensity <= 0.0) discard;

	// DITHER ON THE FX PIXEL GRID, never on FRAGCOORD (O16) — a screen-space dither crawls under a
	// moving card instead of sitting on its pixels. Scaled by ONE ramp texel, so it breaks the step
	// between adjacent samples and cannot smear a whole band.
	if (u_dither > 0.0) {
		float step_u = 1.0 / max(u_ramp_width, 1.0);
		intensity = clamp(intensity + (fx_bayer(p / max(u_pixel, 0.01)) - 0.5) * u_dither * step_u,
				0.0, 1.0);
	}

	vec4 ramp = texture(u_ramp, vec2(intensity, 0.5));

	// ⚠ **THE OVER-ART TEST USES THE UNQUANTIZED POSITION** (O15, `Q215`=a). A card's face is drawn
	// at screen resolution, so testing this at the chunky point makes the boundary a staircase with
	// a one-FX-pixel tread. Fire paid for this lesson twice — once for cards and again for props.
	// Testing it here lets the art's own edge slice the chunky glow pixels diagonally, which is what
	// real occlusion does.
	//
	// ⚠ ON THE LIGHT LAYER THERE IS NO HOST ART TO BE OVER (`u_space` = 1). The disc's own radius
	// stands in: inside it, the circle is over the card's picture by construction — it is 16 art
	// units centred on a 32x32 art square, so it covers the whole picture and nothing else — and
	// `circle_inner_alpha` is the knob for exactly that (`Q217`=a, its own knob, not the glow's).
	vec2 raw = fx_local_raw(UV, u_extent);
	bool over_art = mask_inside(raw);
	float over_alpha = (u_mask_kind == MASK_DISC || u_space == 1)
			? u_circle_inner_alpha : u_inner_alpha;

	// THE BLEND, per the header. `cover` is how PRESENT the light is at this fragment — the ramp's
	// own alpha is part of it, which is what lets the gradient fade the halo out at its outer limit
	// rather than the shader hard-cutting it.
	//
	// ⚠ **THE OVER-ART ALPHA IS SCALED BY `cover`, AND THAT IS NOT A REFINEMENT — A CONSTANT ALPHA
	// THERE DARKENS THE CARD.** `blend_premul_alpha` keeps `dst * (1 - a)`, so an alpha that stays
	// at `inner_alpha` where the light has faded to nothing dims the art by `1 - inner_alpha` for no
	// reason: a 35 % grey wash over every card in reach, brightest nowhere. Scaling it means the
	// tint arrives exactly in proportion to the light, and a fragment the glow does not reach is
	// untouched.
	//
	// ⚠ And the RGB is PREMULTIPLIED BY THAT ALPHA over the art (`tint * a`), which is what makes
	// the result a true lerp `tint*a + dst*(1-a)` — a tint that cannot exceed the ramp's own colour,
	// so it cannot blow out to white. Outside the silhouette it is NOT premultiplied and the alpha
	// is 0, which is pure addition. Both halves, one pass.
	float cover = intensity * ramp.a * u_opacity;
	vec3 tint = ramp.rgb * u_brightness;
	// ⚠ **THE ALPHA RIDES `u_brightness` TOO (clamped — brightness may exceed 1 as an art choice,
	// alpha may not), AND THE HOST'S OWN ALPHA.** Without the first, `fx_intensity = 0` zeroed the
	// RGB but left `a` standing, and `dst * (1 - a)` drew a DARK DISC over every spotlit card — the
	// exact inverse of G2.4's "scales the lights toward nothing". Without the second, a host fading
	// out via modulate kept a full-strength tint over its vanishing art.
	float a = over_art ? over_alpha * cover * clamp(u_brightness, 0.0, 1.0) * COLOR.a : 0.0;
	vec3 lit = over_art ? tint * a : tint * cover;

	// ⚠ THE HOST'S MODULATE IS MULTIPLIED BACK IN (O18), or the focus highlight never reaches the
	// glow — which is precisely Q121's complaint. ⚠ Q121=(b) also changes the highlight itself so
	// the two read distinctly on one card; that half is not a glow-side fix and is not done here.
	COLOR = vec4(lit * COLOR.rgb, a);
}

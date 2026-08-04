shader_type canvas_item;
render_mode blend_premul_alpha, unshaded;
// THE LIGHT LAYER — one full-screen surface that produces the dim, the spotlight circles and the
// beams in ONE pass (design §9, chart H; `Q240`=b).
// Design: solatro/design/spotlight/DESIGN.md §9 (H1-H9) and §14b. Plan: PLAN.md §1.10.
//
// THE MODEL IS CHART H, LINE FOR LINE:
//
//     coverage = 0
//     for each live light: coverage += its BEAM contribution        (H4)
//     for each live light: coverage += its CIRCLE contribution      (H5, brighter than the beam)
//     coverage ACCUMULATES — two beams crossing are brighter than one (H6, Q100=a)
//     dim alpha = u_dim * (1 - clamp(coverage))                     (H7, Q101=a clamps at 1)
//     additive light = clamp(coverage) * the light colour           (H8)
//
// ⚠ **THE DIM IS DRIVEN BY BEAM COUNT, NOT BY ACT STATE** (`QR2`=d). `u_dim` is non-zero exactly
// while a light is live, wherever that happens — including outside scoring entirely, where
// `u_dim_scale` makes it shallower (`Q245`=c). Nothing here knows what a submit is.
//
// ⚠ **THIS SURFACE SITS ABOVE EVERYTHING, WITH NO EXEMPTIONS** — `DESIGN.md` v9, GAP-004, owner:
// *"dim doesnt last long enough to matter for readability, dim everything without worrying about
// certain visuals being exempt"*. `Q74`–`Q76` exempted the props, the score popups and the focus
// panel and are WITHDRAWN; the props dim, the popups dim, the focus panel dims, the HUD dims
// (`Q73`=a) and the card glow dims (`Q77`=a, which is what makes the glow read only inside the
// circle and beam — chart G13). **Do not re-derive an exemption for anything.** The dim is a
// fraction of `Game.get_delay()`, which is the whole reason none is needed.
//
// ===== THE BLEND ================================================================================
//
// `blend_premul_alpha`: `result = src.rgb + dst * (1 - src.a)`. Both halves of chart H are that one
// equation — **the dim IS the alpha and the light IS the rgb**, in a single output:
//
//   * a fully dimmed pixel: `a = u_dim`, `rgb = 0` — the board is multiplied down by `1 - u_dim`;
//   * a fully lit pixel: `a = 0`, `rgb = colour * coverage` — pure addition, the dim punched
//     through by the same `1 - coverage` term that lifts the light;
//   * everything between is H7 and H8 simultaneously, with no second pass and no screen read.
//
// This is why the layer can be one surface at all. A `blend_mix` version needs the destination to
// dim it, which a canvas quad cannot read (DESIGN.md §1.6 fact 1).

#include "res://Shaders/fx_common.gdshaderinc"

// ⚠ **NO CAP — `Q107`, and the owner's words are the specification**: *"No cap. soft cap at how
// many cards can fit on screen."* This array is sized to the widest board the game can actually put
// on screen at once, and **the design may not lean on a smaller number** — it is a bound, not a
// policy. A light past the end is dropped by the CPU, which is a visible bug rather than a designed
// limit, so `LightLayer` is what has to keep this honest.
const int MAX_LIGHTS = 64;

// Per light, in SCREEN pixels:
//   xy = the circle's centre · z = the circle's radius · w = per-light intensity
uniform vec4 u_lights[MAX_LIGHTS];
//   xy = the beam's origin · z = width at the origin · w = width at the target
uniform vec4 u_beams[MAX_LIGHTS];
uniform int u_light_count = 0;

// 0..1, and **non-zero only while a BEAM is live** (`QR2`=d). The travel of this value is the whole
// of the dim's timing; there is no act state anywhere in this file.
uniform float u_dim : hint_range(0.0, 1.0) = 0.0;
// A shallower dim outside scoring than inside it (`Q245`=c). The owner's scrutiny note on that
// question is the reason it is a separate multiplier rather than folded into `u_dim`: *"(a) means
// the screen pulses dark on every single card you place"*, so the shallow case has to be tunable
// without touching the deep one.
uniform float u_dim_scale : hint_range(0.0, 1.0) = 1.0;
// ⚠ **A PALETTE ENTRY, NOT BLACK** (`Q79`=a), and UNIFORM, not a vignette (`Q80`=c chose subtle
// noise — see `u_dim_noise`). Pushed by the CPU from the palette, because a shader may not resolve
// a palette index.
uniform vec4 u_dim_color : source_color = vec4(0.05, 0.04, 0.09, 1.0);
// `Q80`=(c): a subtle noise on the dim rather than a flat field. Held very low on purpose — this is
// the largest surface in the game, and anything visible here reads as film grain over the whole
// screen rather than as texture on a light.
uniform float u_dim_noise : hint_range(0.0, 0.25) = 0.03;

uniform vec4 u_light_color : source_color = vec4(1.0, 0.85, 0.55, 1.0);
uniform float u_beam_intensity : hint_range(0.0, 2.0) = 0.45;
// ⚠ **THE CIRCLE'S OWN LIGHT, AND IT IS DELIBERATELY WELL BELOW §16's SUGGESTED 1.0.** The circle
// has to READ as a pool inside the beam (chart H5 — *"the circle is brighter than the beam"*, and
// the owner: *"we can move on to next phase once circle shows up inside beam"*), so a coverage-only
// circle is not enough: with the beam's coverage now converging on the circle's, an invisible
// circle is exactly what you get. But 1.0 is what washed the rank glyph off the card. This is the
// value that shows the pool and keeps the art, judged by eye on `10_light_layer` — and it is a
// FLOOR, not the whole answer: once the glow draws the disc (`QR9`=c, `MASK_DISC`) most of the
// circle's brightness comes from there, where `circle_inner_alpha` holds it off the art.
uniform float u_circle_intensity : hint_range(0.0, 2.0) = 0.3;
uniform float u_beam_softness : hint_range(0.0, 1.0) = 0.35;
// THE POOL'S PENUMBRA. ⚠ **0.75 WAS AN OVER-CORRECTION AND IS NOT THE FIX IT LOOKED LIKE.** It was
// raised to hide the arc where beam and circle met (owner: *"there is clear semicircle where beam
// and circle overlap"*), but that arc was a step between two VALUES, and it is now gone
// structurally — the beam's coverage converges on the circle's, so they are equal where they meet
// whatever this is set to. Blurring the edge was treating the symptom, and it cost the pool its
// shape (owner, 2026-08-04: *"circle edges are way too soft now, earlier it was better"*).
// 0.4 is between the two: a real penumbra, still a circle. Judged by eye, and fully tunable.
uniform float u_circle_softness : hint_range(0.0, 1.0) = 0.4;

// ⚠ **VOLUMETRIC NOISE FROM THE START, NOT ADDED LATER** (`Q98`=b), and it SCROLLS (`Q99`=a). The
// scroll is on `u_time`, which the CPU pushes with the game's own pacing — **never GLSL `TIME`**,
// which ignores it.
// ⚠ **THE GRAIN'S SIZE, AND THE FIRST DEFAULTS WERE MISTUNED — OWNER-REPORTED, 2026-08-04:**
// *"pixelated hard edge noise inside the light ... some sort of mistuned noise map or something at
// wrong resolution."* Isolated by rendering with `u_beam_noise = 0` (the patches vanished, so it
// was this and not the dim's dither): `scale` was **0.02**, which puts `fx_fbm`'s base cell at 50
// SCREEN PIXELS and its finest octave at ~12 — features the size of a card's art square, so the
// haze read as flat blocks with visible joins rather than as grain. Tripled to 0.06, the base cell
// is ~17 px and the finest ~4, which is grain.
//
// ⚠ The amplitude term was crude too: `n * 1.6` is not centred on 1, so the noise darkened the beam
// more than it brightened it and pushed the low end toward a hard cutoff. It is centred now.
uniform float u_beam_noise : hint_range(0.0, 1.0) = 0.25;
uniform float u_beam_noise_scale = 0.06;
uniform float u_beam_noise_scroll = 12.0;
uniform float u_time = 0.0;

// The photosensitivity floor, and `Q83` is explicit about what it may NOT remove: *"keeps beams
// glow and dim"*. So `fx_intensity` scales the LIGHTS toward nothing and leaves a REDUCED DIM
// standing — gate G2.4. It is one multiplier because the setting has to reach every effect without
// editing a resource.
uniform float u_brightness = 1.0;
uniform float u_pixel = 1.0;

// HOW MUCH OF THE BEAM COVERS `p` — a cone from `origin`, `w0` wide there, opening out to **exactly
// the circle it serves** and STOPPING THERE. Distance is measured across the cone's axis and the
// width is interpolated along it, so the edges are straight lines rather than a widening capsule.
//
// ⚠ **THE CONE ENDS AT THE CIRCLE AND ITS MOUTH IS THE CIRCLE'S WIDTH** (owner, 2026-08-04:
// *"shouldnt beams cut off at the circle? They reach max width at the circle then keep going for
// some reason. beam edges should match circle"*). Two consequences, and the second is why this is
// not just a clamp:
//
//  * **THE CONE ENDS ON THE CIRCLE'S FAR ARC, NOT ON ITS CENTRE.** ⚠ The target point IS the
//    circle's centre, so cutting the cone at `t = 1` ends it on a CHORD THROUGH THE MIDDLE OF THE
//    POOL — a straight line halfway across the circle, which is exactly what the owner saw twice
//    (2026-08-04: *"Beam hard cuts into a straight line when it reaches halfway into circle instead
//    of covering entire circle"*). Past the centre plane the cross-section is therefore measured
//    from the CENTRE rather than across the axis, which continues the cone as the circle's own far
//    half. The two agree exactly at `t = 1` — there the across-axis distance and the distance from
//    the centre are the same number — so the join is seamless by construction rather than by
//    tuning. Beyond the circle the beam still draws nothing: the first build let it run to the edge
//    of the screen at constant width, which read as the beam sailing past the card.
//  * **THE TARGET WIDTH IS DERIVED FROM `radius`, NOT PASSED IN.** §16 specified
//    `beam_width_at_target` as a knob whose stated requirement was *"must cover the circle"* — a
//    number whose only correct value is another number is not a knob, it is a derived quantity, and
//    making it one is what "beam edges should match circle" means mechanically. `flare` is what is
//    left of it: extra half-width beyond the circle, in screen pixels, and **0 is the owner's
//    answer**. The junction needs no blending: the circle is drawn at the same place and is
//    brighter, so it covers the cone's mouth.
//
// ⚠ **A BEAM NEVER POINTS UPWARD** (`Q117`) and its origin sits ~600 px above its target
// (`Q114`) — but neither is enforced here. Both are properties of where the CPU puts the origin
// (S14), and a shader that also clamped them would be a second, disagreeing copy of that rule.
float beam_cover(vec2 p, vec2 origin, vec2 target, float w0, float radius, float flare,
		out float along) {
	vec2 axis = target - origin;
	float len2 = max(dot(axis, axis), 1e-4);
	float t = dot(p - origin, axis) / len2;
	along = clamp(t, 0.0, 1.0);
	if (t < 0.0) return 0.0;                       // the lamp has no back
	float mouth = max(radius + flare, 1e-4);
	float across;
	if (t <= 1.0) {
		// The cone proper: distance ACROSS the axis, against a width opening from `w0` to the
		// circle's own.
		vec2 on_axis = origin + axis * t;
		across = length(p - on_axis) / max(mix(w0 * 0.5, mouth, t), 1e-4);
	} else {
		// Past the centre plane: the circle's far half finishes the shape. Measured from the
		// CENTRE, which equals the across-axis distance exactly at t = 1, so the two meet with no
		// seam and no straight edge anywhere.
		across = length(p - target) / mouth;
		if (across > 1.0) return 0.0;
	}
	return 1.0 - smoothstep(1.0 - u_beam_softness, 1.0, across);
}

float circle_cover(vec2 p, vec2 centre, float radius) {
	float d = length(p - centre) / max(radius, 1e-4);
	return 1.0 - smoothstep(1.0 - u_circle_softness, 1.0, d);
}

void fragment() {
	// SCREEN space: the layer does not scroll with the board (§9 consequence 4). The positions it is
	// fed are converted from board space by the CPU every frame, which is what makes chart H work.
	vec2 p = SCREEN_UV / max(SCREEN_PIXEL_SIZE, vec2(1e-6));

	// TWO SUMS, NOT ONE — and the split is the answer to a card under a circle being unreadable.
	//
	// ⚠ **THE CIRCLE PUNCHES THE DIM BUT DOES NOT ADD LIGHT HERE.** Chart H8 has the layer adding
	// `coverage * light colour`, and `QR9`=(c) has the GLOW shader drawing the same circle as
	// `MASK_DISC`, held down over art by `circle_inner_alpha`. Both lighting one circle is twice the
	// light for the one client that has no room for it — measured on `10_light_layer` over a real
	// board, 2026-08-04: **a card under a beam kept its rank and pips, a card under a circle lost
	// them entirely**, washed to near-white. `Q218`'s note is explicit: *"dont want blowout to
	// white."*
	//
	// So the circle contributes COVERAGE — it removes the dim over its card, which is what makes the
	// card read at full brightness — and the light INSIDE it is the glow's job, where the
	// readability knob lives. The beam still adds, because a beam is light in the air with no art
	// under it to wash out.
	//
	// ⚠ REVERSIBLE, and it is one line: put `circle` back into `add_cover` to restore chart H8
	// literally. Logged in `design/spotlight/ASSUMPTIONS.md`.
	float coverage = 0.0;
	float add_cover = 0.0;
	for (int i = 0; i < MAX_LIGHTS; i++) {
		if (i >= u_light_count) break;
		vec4 L = u_lights[i];
		vec4 B = u_beams[i];
		float along = 0.0;
		float beam = beam_cover(p, B.xy, L.xy, B.z, L.z, B.w, along);
		// ⚠ **THE BEAM'S DIM-PUNCH CONVERGES ON THE CIRCLE'S; ITS ADDED LIGHT DOES NOT.** Owner,
		// 2026-08-04: *"there is clear semicircle where beam and circle overlap"* — and that arc was
		// the whole of this. Two coverage sources met at one edge with different magnitudes: inside
		// the disc the dim was punched to ZERO, and one pixel outside it, still inside the beam,
		// only to `u_beam_intensity` (0.45). A step that size along a circular boundary reads as a
		// drawn arc, and softening the circle's edge only blurs the arc rather than removing it —
		// the step is between the two VALUES, not at the geometry.
		//
		// So the beam's contribution to COVERAGE ramps to 1 along its length: at the origin it is
		// `u_beam_intensity`, at the target it matches the circle exactly and the boundary has
		// nothing left to show. Physically it is the cone converging on the pool it makes.
		//
		// ⚠ The ADDITIVE term deliberately does NOT ramp — it stays at `u_beam_intensity`. Adding
		// full light at the target is what washed the card out in the first place; the whole point
		// of the coverage/additive split is that the dim can open completely somewhere the light
		// does not also pile up.
		if (u_beam_noise > 0.0 && beam > 0.0) {
			// Volumetric grain along the beam, scrolling toward the target. Quantized on the FX
			// pixel grid like everything else, so it does not read as screen-space static.
			// ⚠ ONE factor for BOTH terms: the grain is in the light itself, so a beam that adds
			// grainy light while punching a smooth hole in the dim would show its own noise as a
			// second, contradictory texture.
			vec2 q = fx_pixel_snap(p, max(u_pixel, 0.01)) * u_beam_noise_scale;
			float n = fx_fbm(q + vec2(0.0, -u_time * u_beam_noise_scroll * u_beam_noise_scale));
			beam *= mix(1.0, 0.55 + n * 0.9, u_beam_noise);
		}
		float beam_add = beam * u_beam_intensity;
		beam *= mix(u_beam_intensity, 1.0, along);
		// THE CIRCLE IS BRIGHTER THAN THE BEAM (chart H5, owner) — it opens the dim completely where
		// the beam only thins it, which is what "brighter" means once the light itself comes from
		// the glow.
		float circle = circle_cover(p, L.xy, L.z);
		coverage += (beam + circle) * L.w;
		add_cover += (beam_add + circle * u_circle_intensity) * L.w;
	}
	// ACCUMULATE, THEN CLAMP (`Q100`=a, `Q101`=a). The sum is what makes two crossing beams brighter
	// than one; the clamp is what stops it blowing out to white.
	float lit = clamp(coverage, 0.0, 1.0);
	float add_lit = clamp(add_cover, 0.0, 1.0);

	// ⚠ **`fx_intensity` SCALES THE LIGHTS AND LEAVES A REDUCED DIM** — `Q83`, gate G2.4: *"keeps
	// beams glow and dim"*. At `u_brightness = 0` there is no circle and no beam, and the dim is
	// still there at a reduced depth, so the effect degrades rather than disappearing.
	float lights = add_lit * u_brightness;

	// H7 and H8, as one premultiplied output: the alpha IS the dim and the rgb IS the light. The
	// same `1 - lit` term darkens less where the light is, which is the hole the beam punches.
	float dim = u_dim * u_dim_scale * (1.0 - lit);
	if (u_dim_noise > 0.0 && dim > 0.0) {
		dim *= 1.0 + (fx_bayer(p) - 0.5) * u_dim_noise;
	}
	vec3 add = u_light_color.rgb * lights * u_light_color.a;

	COLOR = vec4(add + u_dim_color.rgb * dim, clamp(dim, 0.0, 1.0));
}

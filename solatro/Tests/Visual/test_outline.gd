extends TestSuite
# res://Tests/Visual/test_outline.gd
# ==============================================================================
# THE CARD OUTLINE — the 1-unit, 8-directional rim `Shaders/outline.gdshader` draws around every
# element on a card, and the geometry that had to change to make room for it.
#
# WHY A SEPARATE SUITE. The outline is the first thing in this project where the SHAPE THE PLAYER SEES
# is produced by a shader rather than by geometry, and the card's FX mask is still geometry-derived.
# That is two representations of one fact — "how big is this card" — with the engine comparing them
# nowhere. Every check below is a comparison between the two, or between the shader and the padded UV
# mapping that feeds it.
#
# ⚠ **THE ORACLE IS THE POINT.** The neighbour-bleed / 8-direction / rim-thickness claims are NOT
# asserted as three separate spot checks; they are asserted as ONE exact image comparison against a
# CPU oracle built from the sheet's own alpha. A spot check ("is there an outline?") passes on a 4-tap
# implementation, on a rim that has eaten a source pixel, and on a rim made of the neighbouring
# frame's art. The oracle disagrees with all three.
#
# WHAT IS COVERED ELSEWHERE, deliberately not duplicated here:
#   * that the mask the fire stands on IS the drawn silhouette, at rest and at four deformed poses —
#     `test_pixels.test_the_card_mask_is_the_card_the_player_sees` (it stands up a REAL CardVisual,
#     which needs autoloads and a pinned animation; this suite is renderer-light on purpose).
#   * that a prop texel is a card texel and the rim is exactly one unit —
#     `test_pixels.test_one_pixel_size_for_all_art`.
#
# CATEGORY MAP: BEHAVIOR — what the player sees (the rim exists, is one unit, is 8-directional, is
# this card's art and not its neighbour's, and the alert stops when its status does). IMPLEMENTATION
# pins: the texel-to-art-unit identity, and the two source-level rules that keep the rim riding the
# rig through deformation.
# ==============================================================================

const VP_SIZE := 64

var _vp : SubViewport
var _stage : Node2D

func suite_name() -> String:
	return "OUTLINE"

func _ready() -> void:
	TestLog.line("============ OUTLINE TEST PASS ============")
	behavior_section("A REAL RENDERER IS REQUIRED (never skipped)")
	if not _check_renderer():
		finish()
		return
	_build_stage()
	implementation_section("ONE SOURCE TEXEL IS ONE ART UNIT")
	test_per_texel_is_one()
	behavior_section("THE RIM IS THIS FRAME'S ART, DILATED BY EXACTLY ONE UNIT")
	await test_rim_matches_its_oracle()
	behavior_section("THE DRAWN CARD IS THE CARD THE MASK DESCRIBES")
	test_corner_bite_survives_the_dilation()
	behavior_section("THE ALERT IS DECLARED, NOT TOGGLED")
	test_alert_is_off_until_a_status_declares_it()
	implementation_section("THE RULES THAT KEEP THE RIM ON THE ART")
	test_shader_taps_in_texture_space()
	finish()

## The guard, copied in shape from `test_pixels`: a dummy renderer compiles no shader and rasterizes
## no triangle, so an outline check under `--headless` would be reported green having looked at
## nothing. It FAILS with the fix in the message; it never skips (owner).
func _check_renderer() -> bool:
	var display := DisplayServer.get_name()
	var live := display != "headless"
	check(live, "the run has a real renderer, so the rim can be checked at all",
			"DisplayServer is '%s' — re-run all_tests.tscn WITHOUT --headless" % display)
	return live

func _build_stage() -> void:
	_vp = SubViewport.new()
	_vp.size = Vector2i(VP_SIZE, VP_SIZE)
	_vp.disable_3d = true
	# Transparent, so "was this pixel drawn" is answerable at all — an opaque clear colour answers yes
	# for every pixel in the target.
	_vp.transparent_bg = true
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	# ⚠ A SubViewport carries its OWN filter and it defaults to LINEAR — it does not inherit the
	# project's `default_texture_filter = 0`. The rim is a one-texel feature and a bilinear read would
	# smear it across two, so an exact comparison would be meaningless. Same trap `test_pixels` and
	# `Tools/spotlight_tool.gd` both had to handle.
	_vp.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	add_child(_vp)
	_stage = Node2D.new()
	# INTEGER centre at 1 art unit per pixel, so the polygon's corners land on pixel boundaries and the
	# comparison below is texel-for-pixel rather than half-covered everywhere.
	_stage.position = Vector2(VP_SIZE, VP_SIZE) * 0.5
	_vp.add_child(_stage)

func _shoot() -> Image:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := _vp.get_texture().get_image()
	for child : Node in _stage.get_children():
		_stage.remove_child(child)
		child.queue_free()
	return img

# ------------------------------------------------------------------ the texel identity

## `per_texel` is 1.0 art unit per source texel for the card's TYPE frame under the INNER-rect mapping.
##
## ⚠ **ONE LINE, AND IT GUARDS THE THING MOST LIKELY TO HAVE BEEN MISSED IN THIS WHOLE CHANGE.**
## `CardVisual._bind_rig` divides `CARD_SIZE` by the type frame's pixel size to turn the measured
## corner bite into art units, and that was exactly 1.0 only while the type frame WAS the card. It is
## not any more — the frame is 38x52 inside a 40x54 polygon — so dividing by `CARD_SIZE` gives
## (1.0526, 1.0385) and inflates every corner notch by 4-5 %, quietly, under a comment still claiming
## the value is 1.0. Nothing about that line looks size-dependent, which is what made it dangerous.
func test_per_texel_is_one() -> void:
	var frame_px := CardModifier.frame_size(CardModifierType.TYPE_TEXTURE,
			CardModifierType.H_FRAMES, CardModifierType.V_FRAMES)
	var inner := CardVisual.CARD_SIZE - Vector2.ONE * CardVisual.ART_OUTLINE * 2.0
	check_impl(inner == frame_px,
			"the card's inner rect IS the type frame, so one source texel is one art unit",
			"inner %s vs frame %s (CARD_SIZE %s, outline %.1f)"
			% [inner, frame_px, CardVisual.CARD_SIZE, CardVisual.ART_OUTLINE])
	check_impl(CardVisual.CARD_ART_SIZE == frame_px,
			"CARD_ART_SIZE agrees with what the sheet actually holds",
			"%s vs %s" % [CardVisual.CARD_ART_SIZE, frame_px])

# ------------------------------------------------------------------ the rim, against an oracle

## THE RIM, PIXEL FOR PIXEL, against a CPU oracle built from the sheet's own alpha.
##
## The oracle is written from the RULE, not from the shader: a texel is BODY if this frame's alpha is
## opaque there, RIM if any of its eight neighbours INSIDE THIS FRAME is opaque, and transparent
## otherwise. Three separate defects fail it and only it:
##
##  * **NEIGHBOUR BLEED.** The sheets carry no transparent gutter, so the padded window overlaps four
##    neighbouring frames and only `u_frame_uv` stops them being sampled. ⚠ Measured 2026-08-04:
##    13/13 rank, 18/19 suit-pip and 3/3 stamp frames have art touching their frame edge, so a missing
##    clamp is LOUD on the pip sheets — but the 32x32 sheets are sparse (2/52 `suit_art` frames touch
##    an edge), which is where a subtly wrong clamp would hide. **Both are tested below.**
##  * **A 4-TAP RIM.** Diagonal-only contact must still produce its corner pixel. A 4-tap
##    implementation passes any "is there an outline" check and leaves every diagonal notched.
##  * **A RIM THAT ATE A SOURCE PIXEL.** Body wins over rim everywhere, so an off-by-one that draws the
##    ink over the art's own outermost texel shows up as a body/rim mismatch rather than as nothing.
func test_rim_matches_its_oracle() -> void:
	# One DENSE frame (art running to every edge, where bleed is loud) and one SPARSE 32x32 frame
	# (where a wrong clamp is quiet) — the two failure modes have opposite signatures.
	await _check_frame_against_oracle("rank pip 'A' (dense sheet, art on the frame edge)",
			PipRankNumeral.RANK_TEXTURE, PipRankNumeral.H_FRAMES, PipRankNumeral.V_FRAMES, 0)
	await _check_frame_against_oracle("suit pip (dense sheet)",
			PipSuit.SUIT_TEXTURE, PipSuit.SUIT_TEXTURE_H_FRAMES, PipSuit.SUIT_TEXTURE_V_FRAMES, 0)
	await _check_frame_against_oracle("card art (sparse 32x32 sheet — the quiet case)",
			PipSuit.ART_TEXTURE, PipSuit.ART_TEXTURE_H_FRAMES, PipSuit.ART_TEXTURE_V_FRAMES, 1)

func _check_frame_against_oracle(label : String, sheet : Texture2D, h_frames : int, v_frames : int,
		frame_index : int) -> void:
	var frame := CardModifier.frame_rect(sheet, h_frames, v_frames, frame_index)
	var w := int(CardOutline.WIDTH)

	# The element exactly as a card builds it: a polygon one rim wider than its frame on every side,
	# UV'd by the real padded mapping, wearing the real material. No stand-in — a stand-in cannot
	# disagree with the game (CLAUDE.md rule 5).
	var poly := Polygon2D.new()
	var h := frame.size * 0.5 + Vector2.ONE * CardOutline.WIDTH
	poly.polygon = PackedVector2Array([Vector2(-h.x, -h.y), Vector2(h.x, -h.y),
			Vector2(h.x, h.y), Vector2(-h.x, h.y)])
	CardOutline.frame_polygon(poly, sheet, h_frames, v_frames, frame_index)
	CardOutline.fill_texture(poly)
	CardOutline.set_rim(poly, CardOutline.STYLE, CardVisual.CARD_SIZE)
	_stage.add_child(poly)
	var img := await _shoot()

	var src := sheet.get_image()
	var ink := PaletteDB.color(CardOutline.STYLE.outline_index)
	var origin := Vector2i(_stage.position) - Vector2i(h)
	var body_wrong := 0
	var rim_missing := 0
	var rim_spurious := 0
	var first_bad := ""
	# Walk the PADDED window: frame size plus a rim on each side, which is exactly the polygon.
	for py : int in int(frame.size.y) + 2 * w:
		for px : int in int(frame.size.x) + 2 * w:
			# This padded-window texel in the frame's own coordinates (the rim ring is negative / past
			# the far edge, and `_frame_alpha` reads both as empty — which IS the clamp).
			var fx := px - w
			var fy := py - w
			var got := img.get_pixel(origin.x + px, origin.y + py)
			var want : Color
			if _frame_alpha(src, frame, fx, fy):
				want = src.get_pixel(int(frame.position.x) + fx, int(frame.position.y) + fy)
				want.a = 1.0
			elif _any_neighbour(src, frame, fx, fy, w):
				want = ink
			else:
				want = Color(0, 0, 0, 0)
			if _same(got, want): continue
			if want.a == 0.0: rim_spurious += 1
			elif _same(want, ink): rim_missing += 1
			else: body_wrong += 1
			if first_bad.is_empty():
				first_bad = "first at frame texel (%d, %d): drew %s, oracle says %s" \
						% [fx, fy, got, want]
	check(body_wrong == 0 and rim_missing == 0 and rim_spurious == 0,
			"%s: every texel is its own frame's art or an 8-directional 1-unit rim of it" % label,
			("%d body wrong, %d rim missing (a 4-tap rim or a clamp eating its own frame), "
			+ "%d rim spurious (NEIGHBOUR BLEED — the padded window is sampling the frame next "
			+ "door). %s") % [body_wrong, rim_missing, rim_spurious, first_bad])

## This frame's alpha at `(fx, fy)` in FRAME coordinates, with everything outside the frame read as
## empty. The oracle's copy of the shader's clamp — written from the rule rather than transcribed, so
## the two can genuinely disagree.
func _frame_alpha(src : Image, frame : Rect2, fx : int, fy : int) -> bool:
	if fx < 0 or fy < 0 or fx >= int(frame.size.x) or fy >= int(frame.size.y): return false
	return src.get_pixel(int(frame.position.x) + fx, int(frame.position.y) + fy).a > 0.5

## Is any texel within Chebyshev distance `w` opaque? EIGHT directions at w = 1, corners included —
## which is the half a 4-tap implementation gets wrong.
func _any_neighbour(src : Image, frame : Rect2, fx : int, fy : int, w : int) -> bool:
	for dy : int in range(-w, w + 1):
		for dx : int in range(-w, w + 1):
			if dx == 0 and dy == 0: continue
			if _frame_alpha(src, frame, fx + dx, fy + dy): return true
	return false

## Colour equality at 8-bit precision. The render target is 8-bit per channel, so comparing floats
## exactly would fail on rounding that no eye and no later pass can see.
func _same(a : Color, b : Color) -> bool:
	if absf(a.a - b.a) > 0.02: return false
	if a.a < 0.5: return true             # both transparent: RGB is undefined, do not compare it
	return absf(a.r - b.r) < 0.02 and absf(a.g - b.g) < 0.02 and absf(a.b - b.b) < 0.02

# ------------------------------------------------------------------ the mask seam

## **A 1-UNIT DILATION PRESERVES A CORNER BITE EXACTLY**, so the FX mask — which is built from the type
## frame's alpha via `CardModifierType.corner_notch()` and applied to the RIG's 40x54 rectangle — still
## describes the drawn silhouette after the shader has rimmed it.
##
## The identity: put the art at offset (1,1) in the 40x54 card and let it bite an N x M rectangle out
## of a corner. A card texel is covered iff some opaque art texel lies within Chebyshev distance 1, so
## the corner texel stays clear exactly when `cx <= N-1` AND `cy <= M-1` — an N x M clear rectangle in
## CARD space, the same N x M the art bit. Exact, therefore asserted exactly.
##
## ⚠ **AND IT ALSO CATCHES THE OTHER HALF, WHICH IS THE HALF THAT WILL BITE SOMEONE LATER.** The mask
## agrees with the drawn edge only because the art reaches its frame boundary everywhere else — dilate
## it by one and the silhouette lands exactly on the polygon. A future type frame drawn pulling IN from
## its frame edge would leave the mask oversized there and root every flame off the art, silently.
## Frames 12 and 13 of the shipped sheet already do this (96 and 92 perimeter texels against 172);
## nothing uses them yet. **This check is what will fail the day something does.**
func test_corner_bite_survives_the_dilation() -> void:
	var src := CardModifierType.TYPE_TEXTURE.get_image()
	var w := int(CardVisual.ART_OUTLINE)
	var checked := 0
	for type_script : GDScript in [TypePaper, TypeInput, TypeHeavy, TypeBoosterBasic]:
		var type_mod : CardModifierType = type_script.new()
		var frame := CardModifier.frame_rect(CardModifierType.TYPE_TEXTURE,
				CardModifierType.H_FRAMES, CardModifierType.V_FRAMES, type_mod.get_frame())
		var notch := type_mod.corner_notch()
		var card := CardVisual.CARD_SIZE
		# The DRAWN silhouette: this frame's alpha dilated by the rim, in card coordinates.
		var drawn_clear_w := 0
		while drawn_clear_w < int(card.x) and not _dilated(src, frame, drawn_clear_w, 0, w):
			drawn_clear_w += 1
		var drawn_clear_h := 0
		while drawn_clear_h < int(card.y) and not _dilated(src, frame, 0, drawn_clear_h, w):
			drawn_clear_h += 1
		# ⚠ CONTAINMENT, NOT EQUALITY, and the difference is `corner_notch`'s own documented behaviour:
		# it returns the largest clear rectangle BY AREA, which for a one-texel bite is exact and for a
		# STAIRCASE corner deliberately under-cuts ("it under-cuts by a texel rather than eating art the
		# frame actually draws"). So the mask's bite must FIT INSIDE the drawing's, never exceed it —
		# under-cutting leaves a texel of flame on art, over-cutting leaves it on nothing.
		check(notch.x <= drawn_clear_w and notch.y <= drawn_clear_h,
				"frame %d: the corner the mask bites fits inside the corner the drawing bites"
				% type_mod.get_frame(),
				"drawn bites %d x %d, corner_notch() says %s — the mask is cutting MORE than the "
				% [drawn_clear_w, drawn_clear_h, notch]
				+ "drawing does, which puts flames on nothing at that corner")
		# THE EXTENT SEAM: the drawn silhouette must REACH the card box on all four sides, because the
		# mask (the rig at ±20/±27) says it does. Interior holes are fine — a type may be drawn hollow —
		# but art that pulls IN from its frame edge makes the mask oversized there, and every effect on
		# that card roots that far off the drawing with nothing in the engine to notice.
		var short := Vector4i(_inset(src, frame, w, card, 0), _inset(src, frame, w, card, 1),
				_inset(src, frame, w, card, 2), _inset(src, frame, w, card, 3))
		check(short == Vector4i.ZERO,
				"frame %d: the drawn card reaches its 40x54 box on all four sides"
				% type_mod.get_frame(),
				("art pulls in by (left %d, top %d, right %d, bottom %d) art units past the corner "
				+ "bites — the RIG claims that much more card than the DRAWING has, so effects on "
				+ "this type root that far proud of the art on those sides")
				% [short.x, short.y, short.z, short.w])
		checked += 1
	check_impl(checked == 4, "every shipped card type was checked", str(checked))

## How far one SIDE of the drawn silhouette falls short of the card box, in art units, measured at that
## side's MIDPOINT so the four corner bites do not count as shortfall. `side`: 0 left, 1 top, 2 right,
## 3 bottom. Zero when the drawing reaches the box, which is what the mask assumes.
func _inset(src : Image, frame : Rect2, w : int, card : Vector2, side : int) -> int:
	var span := 0
	var mid := 0
	match side:
		0, 2: span = int(card.x); mid = int(card.y) * 0.5
		_:    span = int(card.y); mid = int(card.x) * 0.5
	for d : int in span:
		var step : int = d if side == 0 or side == 1 else span - 1 - d
		var hit := false
		match side:
			0, 2: hit = _dilated(src, frame, step, mid, w)
			_:    hit = _dilated(src, frame, mid, step, w)
		if hit: return d
	return span

## Is card texel `(cx, cy)` covered by the art dilated by `w`? The art sits at offset `(w, w)` inside
## the card, so a card texel maps to art texel `(cx - w, cy - w)` and the dilation reaches `w` around it.
func _dilated(src : Image, frame : Rect2, cx : int, cy : int, w : int) -> bool:
	for dy : int in range(-w, w + 1):
		for dx : int in range(-w, w + 1):
			var ax := cx - w + dx
			var ay := cy - w + dy
			if ax < 0 or ay < 0 or ax >= int(frame.size.x) or ay >= int(frame.size.y): continue
			if src.get_pixel(int(frame.position.x) + ax, int(frame.position.y) + ay).a > 0.5:
				return true
	return false

# ------------------------------------------------------------------ the alert

## THE ALERT IS RE-DERIVED FROM THE LIVE STATUS LIST, so it cannot leak and two of them cannot switch
## each other off.
##
## ⚠ **ASSERTED BY REMOVING THE STATUS, NEVER BY CALLING AN "OFF" METHOD** — there deliberately is no
## off method. An imperative `alert_on()` / `alert_off()` pair leaks the moment a status is freed,
## merged away or rewound mid-alert, because nothing is left to call the off. That is the failure this
## design exists to make impossible, so the test has to exercise the path that would have leaked.
func test_alert_is_off_until_a_status_declares_it() -> void:
	var data := TestFactories.m_card(3.0, 1)
	var vis : CardVisual = CardVisual.CARD_VISUAL.instantiate()
	vis.current_context = CardVisual.DisplayContext.PREVIEW
	vis.data = data
	add_child(vis)
	vis.show_front = true

	# ⚠ **THE TUNING RESOURCE MUST ACTUALLY REACH THE ALERT**, or `tools/outline_atlas.tscn` is tuning a
	# preview and the game keeps whatever was hardcoded — which is the exact failure the style resource
	# was introduced to end. Two representations of one number with nothing comparing them is how this
	# project's recurring bugs are shaped, so the comparison is written here rather than assumed.
	var st := CardOutline.STYLE
	var default_glare := CardAlert.glare()
	check(default_glare.resolved_period(st) == st.glare_period_fraction
			and default_glare.resolved_thickness(st) == st.glare_thickness
			and default_glare.resolved_buffer(st) == st.glare_buffer
			and default_glare.resolved_color(st) == st.glare_color,
			"an unqualified GLARE takes its tempo, thickness, side buffer and ink from the style",
			"alert(%.2f, %.2f, %.2f, %d) vs style(%.2f, %.2f, %.2f, %d)"
			% [default_glare.resolved_period(st), default_glare.resolved_thickness(st),
			default_glare.resolved_buffer(st), default_glare.resolved_color(st),
			st.glare_period_fraction, st.glare_thickness, st.glare_buffer, st.glare_color])
	# THROB keeps its OWN tempo and its OWN ink — the two are different cues and share neither (owner
	# 2026-08-06). A single shared period would pass every other check in this file.
	var default_throb := CardAlert.throb()
	check(default_throb.resolved_period(st) == st.throb_period_fraction
			and default_throb.resolved_color(st) == st.throb_color,
			"and a THROB takes its own period and its own ink, not the glare's",
			"throb(%.2f, %d) vs glare(%.2f, %d)"
			% [default_throb.resolved_period(st), default_throb.resolved_color(st),
			st.glare_period_fraction, st.glare_color])
	# ⚠ **LATE RESOLUTION IS THE POINT, so assert it directly.** A status builds its request without
	# knowing which card will read it, so the fields must still be UNSET afterwards — resolving them at
	# construction would bake the shipped defaults in and make a TYPE's own style unreachable for every
	# field the status did not name. That failure would be near-invisible: the card would look right for
	# the default type and wrong for every type that overrode anything.
	check_impl(default_glare.period_fraction < 0.0 and default_glare.thickness < 0.0
			and default_glare.buffer < 0.0 and default_glare.color < 0,
			"an unqualified alert stores SENTINELS, so a per-type style can still override it")
	# And a type's override is what those sentinels resolve against — the third layer, exercised.
	var custom := st.duplicate() as OutlineStyle
	custom.glare_thickness = st.glare_thickness + 7.0
	check(default_glare.resolved_thickness(custom) == st.glare_thickness + 7.0,
			"the SAME alert resolves differently against a type's own style",
			"%.2f" % default_glare.resolved_thickness(custom))

	check(vis._alert == null, "a card with no statuses runs no alert")

	var one := StatusTestAlert.new()
	data.add_status(one)
	vis.update_visual()
	check(vis._alert != null and vis._alert.kind == CardOutline.Alert.GLARE,
			"a status that DECLARES an alert turns the card's outline into one")

	# TWO at once: the second clearing must not switch off the first, which a bool or a pushed flag
	# would get wrong. `CardVisual` has the precedent for that hazard in `_spin_holding`.
	var two := StatusTestAlertThrob.new()
	data.add_status(two)
	vis.update_visual()
	check(vis._alert != null and vis._alert.kind == CardOutline.Alert.THROB,
			"with two alerts declared the LAST one wins (status order, like the FX requests)")
	data.remove_status(two)
	vis.update_visual()
	check(vis._alert != null and vis._alert.kind == CardOutline.Alert.GLARE,
			"clearing one of two alerts leaves the other still alerting")

	data.remove_status(one)
	vis.update_visual()
	var mat := vis.type.material as ShaderMaterial
	var pushed_kind : int = mat.get_shader_parameter(&"u_alert_kind")
	var pushed_clock : float = mat.get_shader_parameter(&"u_alert_clock")
	check(vis._alert == null and pushed_kind == int(CardOutline.Alert.NONE),
			"removing the last alerting status returns the outline to rest — with no off method called",
			"still pushing kind %d" % pushed_kind)
	check_impl(vis._alert_clock == 0.0 and pushed_clock == 0.0,
			"and parks the phase, so the next alert starts at the beginning rather than mid-bounce",
			"%f / %f" % [vis._alert_clock, pushed_clock])
	vis.queue_free()

# ------------------------------------------------------------------ the source-level rules

## TWO RULES THAT ARE INVISIBLE IN A REST-POSE IMAGE AND DECIDE WHETHER AN ANIMATED CARD LOOKS RIGHT.
##
## All five polygons are skinned to the card's star rig, which autoplays, so a card is never the
## rectangle it measures. The rim survives that because Polygon2D bone weights move VERTEX POSITIONS
## and leave each vertex's UV alone — the fragment stage sees the same UV-to-texel correspondence at
## rest and fully deformed. Two things have to hold, and BOTH pass every rest-pose pixel check:
##
##  1. the neighbourhood is tapped in UV space via `TEXTURE_PIXEL_SIZE`. A `SCREEN_UV` or `FRAGCOORD`
##     neighbourhood holds a constant SCREEN thickness while the art stretches, so the rim DETACHES
##     from the drawing — worst at the corners, where `Arm_TopLeft` swings out ~26 %.
##  2. there is no `vertex()` function. Godot applies 2D skinning in the vertex stage, and a custom
##     `vertex()` is the one way to interfere with it; not having one removes the question.
##
## ⚠ **THIS IS A SOURCE-TEXT CHECK, AND THAT IS THE PROPORTIONATE FORM.** Catching (1) by rendering
## needs a pinned deformed pose and a thickness measurement along a stretched edge — which
## `test_pixels.test_the_card_mask_is_the_card_the_player_sees` already does for the silhouette as a
## whole. What is left is the rule itself, and a rule is cheapest to assert where it is written.
func test_shader_taps_in_texture_space() -> void:
	var raw := FileAccess.get_file_as_string(CardOutline.SHADER.resource_path)
	check_impl(not raw.is_empty(), "the outline shader source is readable",
			CardOutline.SHADER.resource_path)
	# ⚠ COMMENTS STRIPPED FIRST. The shader's own header EXPLAINS the rule by naming `SCREEN_UV` and
	# `FRAGCOORD` as the things not to use, so a scan of the raw text finds them and fails on the
	# documentation rather than on the code. A check that cannot tell a prohibition from its violation
	# is worse than no check — it trains the next person to delete the comment.
	var text := ""
	for line : String in raw.split("\n"):
		var slash := line.find("//")
		text += (line if slash < 0 else line.substr(0, slash)) + "\n"
	check_impl(text.contains("TEXTURE_PIXEL_SIZE"),
			"the rim's neighbourhood is a TEXTURE-space step, so it rides the art through deformation")
	check_impl(not text.contains("SCREEN_UV") and not text.contains("FRAGCOORD"),
			"and never a SCREEN-space one, which would hold a constant screen thickness while the "
			+ "art stretched and detach the rim from the drawing")
	check_impl(not text.contains("void vertex()"),
			"the shader writes no vertex() — Godot's 2D skinning lives there and must not be touched")
	# ⚠ **NO USER FUNCTION MAY TAKE A `sampler2D`, AND THIS CHECK EXISTS BECAUSE THE SUITE MISSED IT
	# ONCE.** `TEXTURE` is a `fragment()`-local built-in. Passing it into a helper compiles on the GLES3
	# runtime path — so the game ran and every check in this file passed — while the EDITOR's shader
	# compiler rejected it outright (*"Condition `!actions.custom_samplers.has(...)` is true"*), which
	# broke every `@tool` host that previews the shader. The editor is where the art is judged, so a
	# shader that is only correct where the tests look is not correct. Tap inline in `fragment()`.
	check_impl(not text.contains("sampler2D") or text.count("sampler2D") == text.count("uniform sampler2D"),
			"no user function takes a sampler2D — a built-in sampler passed as an argument compiles at "
			+ "runtime and fails in the EDITOR, so the whole suite can go green on a broken shader",
			"%d sampler2D mentions, %d of them uniforms"
			% [text.count("sampler2D"), text.count("uniform sampler2D")])

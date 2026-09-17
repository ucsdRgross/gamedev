extends TestSuite
# THE CARD OUTLINE: the one-unit, 8-directional rim `Shaders/outline.gdshader` draws around every
# element on a card. The rim is shader-drawn and the FX mask is geometry-derived, two representations
# of "how big is this card" that the engine compares nowhere, so every check here is that comparison.

# The mask-versus-drawing seam at DEFORMED poses lives in `test_pixels`
# (`test_the_card_mask_is_the_card_the_player_sees`, `test_one_pixel_size_for_all_art`): those stand
# up a real `CardVisual` with a pinned animation, and this suite stays renderer-light on purpose.

const VP_SIZE := 64

## Read as TEXT, never loaded: the claim is about what is SAVED, and loading runs the `@tool` script that writes the material.
const CARD_SCENE_PATH := "res://Cards/card_visual.tscn"

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
	test_the_card_scene_ships_no_baked_material()
	test_card_separation_derives_from_the_pip_row()
	finish()

# A dummy renderer compiles no shader and rasterizes no triangle, so a headless run would report
# every rim check green having looked at nothing. It FAILS with the fix in the message, never skips.
func _check_renderer() -> bool:
	var display := DisplayServer.get_name()
	var live := display != "headless"
	check(live, "the run has a real renderer, so the rim can be checked at all",
			"DisplayServer is '%s' — re-run all_tests.tscn WITHOUT --headless" % display)
	return live

# Transparent, so "was this pixel drawn" is answerable; NEAREST, because a SubViewport's own filter
# defaults to LINEAR and would smear the one-texel rim across two; an INTEGER centre at one art unit
# per pixel, so the polygon's corners land on pixel boundaries and the comparison is texel-for-pixel.
func _build_stage() -> void:
	_vp = SubViewport.new()
	_vp.size = Vector2i(VP_SIZE, VP_SIZE)
	_vp.disable_3d = true
	_vp.transparent_bg = true
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_vp.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	add_child(_vp)
	_stage = Node2D.new()
	_stage.position = Vector2(VP_SIZE, VP_SIZE) * 0.5
	_vp.add_child(_stage)

func _shoot() -> Image:
	await await_drawn_frames(2)
	var img := _vp.get_texture().get_image()
	for child : Node in _stage.get_children():
		_stage.remove_child(child)
		child.queue_free()
	return img

# `CardVisual._bind_rig` divides `CARD_SIZE` by the type frame's pixel size to turn the measured
# corner bite into art units, which is 1.0 only while the inner rect IS the frame: a 38x52 frame in a
# 40x54 polygon divided by `CARD_SIZE` inflates every corner notch by 4-5 %, quietly.
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

# ⚠ ONE EXACT IMAGE COMPARISON against a CPU oracle written from the RULE, not from the shader: a spot
# check ("is there an outline?") passes on a 4-tap rim, on a rim that ate a source texel and on a rim
# made of the neighbouring frame's art. The oracle disagrees with all three.
func test_rim_matches_its_oracle() -> void:
	await _check_frame_against_oracle("rank pip 'A' (dense sheet, art on the frame edge)",
			PipRankNumeral.RANK_TEXTURE, PipRankNumeral.H_FRAMES, PipRankNumeral.V_FRAMES, 0)
	await _check_frame_against_oracle("suit pip (dense sheet)",
			PipSuit.SUIT_TEXTURE, PipSuit.SUIT_TEXTURE_H_FRAMES, PipSuit.SUIT_TEXTURE_V_FRAMES, 0)
	await _check_frame_against_oracle("card art (sparse 32x32 sheet — the quiet case)",
			PipSuit.ART_TEXTURE, PipSuit.ART_TEXTURE_H_FRAMES, PipSuit.ART_TEXTURE_V_FRAMES, 1)

# A DENSE frame (art on every edge, where neighbour bleed is loud: 13/13 rank, 18/19 suit-pip and 3/3
# stamp frames touch an edge) and a SPARSE 32x32 frame (2/52 touch one, where a wrong clamp hides).
# The element is built exactly as a card builds it; a stand-in cannot disagree with the game.
func _check_frame_against_oracle(label : String, sheet : Texture2D, h_frames : int, v_frames : int,
		frame_index : int) -> void:
	var frame := CardModifier.frame_rect(sheet, h_frames, v_frames, frame_index)
	var w := int(CardOutline.WIDTH)
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
	for py : int in int(frame.size.y) + 2 * w:
		for px : int in int(frame.size.x) + 2 * w:
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

# This frame's alpha at `(fx, fy)` in FRAME coordinates, everything outside read as empty: the
# oracle's copy of the shader's clamp, written from the rule rather than transcribed.
func _frame_alpha(src : Image, frame : Rect2, fx : int, fy : int) -> bool:
	if fx < 0 or fy < 0 or fx >= int(frame.size.x) or fy >= int(frame.size.y): return false
	return src.get_pixel(int(frame.position.x) + fx, int(frame.position.y) + fy).a > 0.5

## Any opaque texel within Chebyshev distance `w`: eight directions, corners included, which is the half a 4-tap rim gets wrong.
func _any_neighbour(src : Image, frame : Rect2, fx : int, fy : int, w : int) -> bool:
	for dy : int in range(-w, w + 1):
		for dx : int in range(-w, w + 1):
			if dx == 0 and dy == 0: continue
			if _frame_alpha(src, frame, fx + dx, fy + dy): return true
	return false

# Colour equality at 8-bit precision, because the render target is 8-bit per channel. Two
# transparent colours are the same colour: their RGB is undefined and is never compared.
func _same(a : Color, b : Color) -> bool:
	if absf(a.a - b.a) > 0.02: return false
	if a.a < 0.5: return true
	return absf(a.r - b.r) < 0.02 and absf(a.g - b.g) < 0.02 and absf(a.b - b.b) < 0.02

# A ONE-UNIT DILATION PRESERVES A CORNER BITE EXACTLY: a card texel is covered iff an opaque art texel
# lies within Chebyshev distance 1, so an N x M bite in the art is an N x M clear rectangle in card
# space, and `corner_notch()`'s mask still describes the drawn silhouette after the rim.
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
		var drawn_clear_w := 0
		while drawn_clear_w < int(card.x) and not _dilated(src, frame, drawn_clear_w, 0, w):
			drawn_clear_w += 1
		var drawn_clear_h := 0
		while drawn_clear_h < int(card.y) and not _dilated(src, frame, 0, drawn_clear_h, w):
			drawn_clear_h += 1
		_check_the_mask_bite_fits_the_drawn_bite(type_mod, notch, drawn_clear_w, drawn_clear_h)
		_check_the_drawing_reaches_the_card_box(type_mod, src, frame, w, card)
		checked += 1
	check_impl(checked == 4, "every shipped card type was checked", str(checked))

# ⚠ CONTAINMENT, NOT EQUALITY: `corner_notch()` returns the largest clear rectangle BY AREA, exact for
# a one-texel bite and deliberately under-cut for a staircase corner. Under-cutting leaves a texel of
# flame on art; over-cutting leaves it on nothing, so the mask's bite must fit inside the drawing's.
func _check_the_mask_bite_fits_the_drawn_bite(type_mod: CardModifierType, notch: Vector2,
		drawn_clear_w: int, drawn_clear_h: int) -> void:
	check(notch.x <= drawn_clear_w and notch.y <= drawn_clear_h,
			"frame %d: the corner the mask bites fits inside the corner the drawing bites"
			% type_mod.get_frame(),
			"drawn bites %d x %d, corner_notch() says %s — the mask is cutting MORE than the "
			% [drawn_clear_w, drawn_clear_h, notch]
			+ "drawing does, which puts flames on nothing at that corner")

# THE EXTENT SEAM: the mask (the rig at ±20/±27) says the drawing reaches the card box on all four
# sides. Art that pulls IN from its frame edge leaves the mask oversized there and roots every
# effect that far off the drawing; frames 12 and 13 of the shipped sheet already do, unused so far.
func _check_the_drawing_reaches_the_card_box(type_mod: CardModifierType, src: Image, frame: Rect2,
		w: int, card: Vector2) -> void:
	var short := Vector4i(_inset(src, frame, w, card, 0), _inset(src, frame, w, card, 1),
			_inset(src, frame, w, card, 2), _inset(src, frame, w, card, 3))
	check(short == Vector4i.ZERO,
			"frame %d: the drawn card reaches its 40x54 box on all four sides"
			% type_mod.get_frame(),
			("art pulls in by (left %d, top %d, right %d, bottom %d) art units past the corner "
			+ "bites — the RIG claims that much more card than the DRAWING has, so effects on "
			+ "this type root that far proud of the art on those sides")
			% [short.x, short.y, short.z, short.w])

# How far one SIDE of the drawn silhouette falls short of the card box, in art units, measured at
# that side's MIDPOINT so the corner bites do not count. `side`: 0 left, 1 top, 2 right, 3 bottom.
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

## Whether card texel `(cx, cy)` is covered by the art dilated by `w`; the art sits at offset `(w, w)` inside the card.
func _dilated(src : Image, frame : Rect2, cx : int, cy : int, w : int) -> bool:
	for dy : int in range(-w, w + 1):
		for dx : int in range(-w, w + 1):
			var ax := cx - w + dx
			var ay := cy - w + dy
			if ax < 0 or ay < 0 or ax >= int(frame.size.x) or ay >= int(frame.size.y): continue
			if src.get_pixel(int(frame.position.x) + ax, int(frame.position.y) + ay).a > 0.5:
				return true
	return false

# ⚠ THE ALERT IS RE-DERIVED FROM THE LIVE STATUS LIST and there is deliberately no off method: an
# on/off pair leaks the moment a status is freed, merged away or rewound mid-alert. So the alert is
# switched off here by REMOVING the status, the path that would have leaked.
func test_alert_is_off_until_a_status_declares_it() -> void:
	var data := TestFactories.m_card(3.0, 1)
	var vis : CardVisual = CardVisual.CARD_VISUAL.instantiate()
	vis.current_context = CardVisual.DisplayContext.PREVIEW
	vis.data = data
	add_child(vis)
	vis.show_front = true
	_check_the_style_resource_reaches_the_alert()
	check(vis._alert == null, "a card with no statuses runs no alert")

	var one := StatusTestAlert.new()
	data.add_status(one)
	vis.update_visual()
	check(vis._alert != null and vis._alert.kind == CardOutline.Alert.GLARE,
			"a status that DECLARES an alert turns the card's outline into one")
	_check_two_alerts_clear_independently(vis, data)

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

# ⚠ THE TUNING RESOURCE MUST REACH THE ALERT, or `Tools/outline_atlas.tscn` tunes a preview while the
# game keeps a hardcoded number. THROB keeps its OWN tempo and ink (owner ruling), and a request
# stores SENTINELS so a TYPE's own style can still override every field the status did not name.
func _check_the_style_resource_reaches_the_alert() -> void:
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
	var default_throb := CardAlert.throb()
	check(default_throb.resolved_period(st) == st.throb_period_fraction
			and default_throb.resolved_color(st) == st.throb_color,
			"and a THROB takes its own period and its own ink, not the glare's",
			"throb(%.2f, %d) vs glare(%.2f, %d)"
			% [default_throb.resolved_period(st), default_throb.resolved_color(st),
			st.glare_period_fraction, st.glare_color])
	check_impl(default_glare.period_fraction < 0.0 and default_glare.thickness < 0.0
			and default_glare.buffer < 0.0 and default_glare.color < 0,
			"an unqualified alert stores SENTINELS, so a per-type style can still override it")
	var custom := st.duplicate() as OutlineStyle
	custom.glare_thickness = st.glare_thickness + 7.0
	check(default_glare.resolved_thickness(custom) == st.glare_thickness + 7.0,
			"the SAME alert resolves differently against a type's own style",
			"%.2f" % default_glare.resolved_thickness(custom))

# TWO at once: clearing the second must not switch off the first, which a bool or a pushed flag
# would get wrong (`CardVisual._spin_holding` is the precedent for that hazard).
func _check_two_alerts_clear_independently(vis: CardVisual, data: CardData) -> void:
	var two := StatusTestAlertThrob.new()
	data.add_status(two)
	vis.update_visual()
	check(vis._alert != null and vis._alert.kind == CardOutline.Alert.THROB,
			"with two alerts declared the LAST one wins (status order, like the FX requests)")
	data.remove_status(two)
	vis.update_visual()
	check(vis._alert != null and vis._alert.kind == CardOutline.Alert.GLARE,
			"clearing one of two alerts leaves the other still alerting")

# TWO RULES INVISIBLE IN A REST-POSE IMAGE: the rim is tapped in UV space (a SCREEN-space rim holds a
# constant thickness while the skinned art stretches and DETACHES, worst at the corners where
# `Arm_TopLeft` swings out ~26 %), and `vertex()` never writes `VERTEX`, which skinning moves first.
func test_shader_taps_in_texture_space() -> void:
	var raw := FileAccess.get_file_as_string(CardOutline.SHADER.resource_path)
	check_impl(not raw.is_empty(), "the outline shader source is readable",
			CardOutline.SHADER.resource_path)
	var text := _strip_shader_comments(raw)
	check_impl(text.contains("TEXTURE_PIXEL_SIZE"),
			"the rim's neighbourhood is a TEXTURE-space step, so it rides the art through deformation")
	check_impl(not text.contains("SCREEN_UV") and not text.contains("FRAGCOORD"),
			"and never a SCREEN-space one, which would hold a constant screen thickness while the "
			+ "art stretched and detach the rim from the drawing")
	var writes_vertex := RegEx.create_from_string("\\bVERTEX(\\.[xyzw]+)?\\s*[-+*/]?=[^=]")
	check_impl(writes_vertex.search(text) == null,
			"vertex() never writes VERTEX — skinning moves VERTEX before the shader sees it, and a "
			+ "vertex() that writes it detaches the rim from the rig")
	var defines_vertex := RegEx.create_from_string("(?m)^\\s*#define\\b.*\\bVERTEX\\b")
	check_impl(defines_vertex.search(text) == null,
			"no #define mentions VERTEX — an alias would write it under another name")
	_check_no_user_function_takes_a_sampler(text)

# ⚠ COMMENTS STRIPPED FIRST, both `//` and `/* */`: the shader's own header names `SCREEN_UV` and
# `FRAGCOORD` as the things not to use, and a check that cannot tell a prohibition from its
# violation trains the next person to delete the comment.
func _strip_shader_comments(raw: String) -> String:
	var block := RegEx.create_from_string("(?s)/\\*.*?\\*/")
	var line := RegEx.create_from_string("//[^\\n]*")
	return line.sub(block.sub(raw, "", true), "", true)

# ⚠ `TEXTURE` is a `fragment()`-local built-in. Passing it into a helper compiles on the GLES3
# runtime path and the EDITOR's shader compiler rejects it, so every `@tool` host that previews the
# shader breaks while the whole suite stays green. The suite missed it once; tap inline.
func _check_no_user_function_takes_a_sampler(text: String) -> void:
	check_impl(not text.contains("sampler2D") or text.count("sampler2D") == text.count("uniform sampler2D"),
			"no user function takes a sampler2D — a built-in sampler passed as an argument compiles at "
			+ "runtime and fails in the EDITOR, so the whole suite can go green on a broken shader",
			"%d sampler2D mentions, %d of them uniforms"
			% [text.count("sampler2D"), text.count("uniform sampler2D")])

# ⚠ `CardOutline.material_of()` assigns `poly.material`, a SCENE MUTATION that `@tool` runs in the
# editor too, so an editor re-bake persists the suitless PREVIEW card's uniforms: its `u_frame_uv`
# stays at the whole-sheet default, no clamp, and the edge-packed sheets bleed. Assert the scene.
func test_the_card_scene_ships_no_baked_material() -> void:
	var text := FileAccess.get_file_as_string(CARD_SCENE_PATH)
	check(not text.is_empty(), "the card scene is readable at %s" % CARD_SCENE_PATH)
	check(not text.contains("SubResource(\"ShaderMaterial"),
			"card_visual.tscn assigns no saved ShaderMaterial (an editor re-bake freezes the "
			+ "suitless preview's uniforms, including an unclamped u_frame_uv)")
	check(not text.contains("[sub_resource type=\"ShaderMaterial\""),
			"card_visual.tscn defines no ShaderMaterial sub-resource")

# THE ART CAN MOVE: a covered card's visible strip is its BOTTOM band (stacks grow upward), which must
# show the pip row plus the owner's 2-unit clearance for the idle rig. The row's position lives in
# `card_visual.tscn`, so CARD_SEPARATION is derived from it here rather than asserted to be 16.
func test_card_separation_derives_from_the_pip_row() -> void:
	var text := FileAccess.get_file_as_string(CARD_SCENE_PATH)
	check(not text.is_empty(), "the card scene is readable at %s" % CARD_SCENE_PATH)
	var rank_y := _scene_node_position_y(text, "Rank")
	var pip_half := _scene_node_polygon_half_height(text, "Rank")
	check(rank_y > 0.0 and pip_half > 0.0,
			"the pip row's position and extent are readable from the scene",
			"y %.1f, half-height %.1f" % [rank_y, pip_half])

	var card_bottom : float = CardVisual.CARD_SIZE.y / 2.0
	var pip_bottom := rank_y + pip_half
	var margin_below := card_bottom - pip_bottom
	var pip_height := pip_half * 2.0
	var rig_clearance := 2.0
	var derived := margin_below + pip_height + rig_clearance

	check(margin_below > 0.0,
			"the pip row sits INSIDE the card's bottom edge, with a margin below it",
			"card bottom %.1f, pip bottom %.1f" % [card_bottom, pip_bottom])
	check(is_equal_approx(derived, float(CardVisual.CARD_SEPARATION)),
			"CARD_SEPARATION is exactly the strip that shows a covered card's pips, "
			+ "derived from where they actually are",
			"%.1f margin + %.1f pip + %.1f clearance = %.1f, but CARD_SEPARATION is %d"
			% [margin_below, pip_height, rig_clearance, derived, CardVisual.CARD_SEPARATION])

## `position = Vector2(x, y)` of a named node in a saved scene, or 0.0.
func _scene_node_position_y(text: String, node_name: String) -> float:
	var block_text := _scene_node_block(text, node_name)
	var re := RegEx.create_from_string("position = Vector2\\(\\s*-?[0-9.]+\\s*,\\s*(-?[0-9.]+)")
	var m := re.search(block_text)
	return float(m.get_string(1)) if m else 0.0

## Half the vertical extent of a named node's `polygon`, or 0.0.
func _scene_node_polygon_half_height(text: String, node_name: String) -> float:
	var block_text := _scene_node_block(text, node_name)
	var re := RegEx.create_from_string("polygon = PackedVector2Array\\(([^)]*)\\)")
	var m := re.search(block_text)
	if not m: return 0.0
	var nums : Array[float] = []
	for piece : String in m.get_string(1).split(","):
		nums.append(float(piece.strip_edges()))
	var top := 0.0
	var bottom := 0.0
	for i : int in range(1, nums.size(), 2):
		top = minf(top, nums[i])
		bottom = maxf(bottom, nums[i])
	return (bottom - top) / 2.0

## The text of one `[node name="..."]` block, up to the next node.
func _scene_node_block(text: String, node_name: String) -> String:
	var start := text.find("[node name=\"%s\"" % node_name)
	if start == -1: return ""
	var end := text.find("[node ", start + 1)
	return text.substr(start, (end - start) if end > start else -1)

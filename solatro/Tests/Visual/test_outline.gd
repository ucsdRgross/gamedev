extends TestSuite
# THE CARD OUTLINE: the 1-unit, 8-directional rim Shaders/outline.gdshader draws around every
# element on a card, and the geometry that had to change to make room for it.

# WHY A SEPARATE SUITE. The shape the player sees is produced by a shader while the card's FX mask is
# still geometry-derived, and the engine compares the two nowhere. Every check below compares them,
# or compares the shader against the padded UV mapping that feeds it.

# ⚠ THE ORACLE IS THE POINT. The neighbour-bleed, 8-direction and rim-thickness claims are asserted
# as ONE exact image comparison against a CPU oracle. A spot check passes on a 4-tap rim, on a rim
# that has eaten a source pixel, and on a rim made of the neighbouring frame's art.

# COVERED ELSEWHERE, deliberately not duplicated: that the mask the fire stands on IS the drawn
# silhouette at rest and deformed, and that a prop texel is a card texel, both in test_pixels. That
# suite stands up a REAL CardVisual with autoloads; this one is renderer-light on purpose.

# CATEGORY MAP. BEHAVIOR is what the player sees: the rim exists, is one unit, is 8-directional, is
# this card's art and not its neighbour's, and the alert stops when its status does. IMPLEMENTATION
# pins the texel-to-art-unit identity and the two source rules that keep the rim riding the rig.

const VP_SIZE := 64

## Read as TEXT: the claim is about what is SAVED on disk, and loading it would run the @tool script.
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
	test_the_rig_outline_is_the_drawn_card()
	behavior_section("THE ALERT IS DECLARED, NOT TOGGLED")
	test_alert_is_off_until_a_status_declares_it()
	test_an_activated_rim_still_parks_the_status_phase()
	behavior_section("THE SHIMMER BLENDS ALONG ITS RAMP, AND MOVES")
	await test_shimmer_blends_between_ramp_entries()
	implementation_section("THE RULES THAT KEEP THE RIM ON THE ART")
	test_shader_taps_in_texture_space()
	test_the_card_scene_ships_no_baked_material()
	test_card_separation_derives_from_the_pip_row()
	test_leaf_bones_do_not_auto_calculate()
	test_the_glare_slider_limits_are_the_card_width()
	check_all_tests_registered()
	finish()

# The guard, copied in shape from test_pixels: a dummy renderer compiles no shader and rasterizes no
# triangle, so an outline check under --headless would be reported green having looked at nothing.
# It FAILS with the fix in the message and never skips (owner).
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
# Transparent, so "was this pixel drawn" is answerable at all: an opaque clear colour answers yes for
# every pixel in the target.
	_vp.transparent_bg = true
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
# ⚠ A SubViewport carries its OWN filter and defaults to LINEAR, not inheriting the project's
# default_texture_filter of 0. The rim is a one-texel feature and a bilinear read smears it across
# two, making an exact comparison meaningless. Same trap in test_pixels and spotlight_tool.gd.
	_vp.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	add_child(_vp)
	_stage = Node2D.new()
# INTEGER centre at 1 art unit per pixel, so the polygon's corners land on pixel boundaries and the
# comparison below is texel-for-pixel rather than half-covered everywhere.
	_stage.position = Vector2(VP_SIZE, VP_SIZE) * 0.5
	_vp.add_child(_stage)

func _shoot() -> Image:
	await await_drawn_frames(2)
	var img := _vp.get_texture().get_image()
	for child : Node in _stage.get_children():
		_stage.remove_child(child)
		child.queue_free()
	return img

# ------------------------------------------------------------------ the texel identity

# per_texel is 1.0 art unit per source texel for the card's TYPE frame under the INNER-rect mapping.

# ⚠ CardModifierType.drawn_rect and drawn_corners measure in SOURCE TEXELS and CardVisual._bind_rig
# reads them as art units against CARD_SIZE, which holds only while the type frame IS the card's
# inner rect. Nothing about that read looks size-dependent, which is what makes it dangerous.
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

# THE RIM, PIXEL FOR PIXEL, against a CPU oracle built from the sheet's own alpha. The oracle is
# written from the RULE, not from the shader: a texel is BODY at its own alpha where this frame's
# alpha is above 0, RIM where any of its eight neighbours INSIDE THIS FRAME is, else transparent.

# Three defects fail it and only it. NEIGHBOUR BLEED: the sheets carry no transparent gutter, so the
# padded window overlaps four neighbouring frames and only u_frame_uv stops them being sampled -
# outline.gdshader's frame-clamp rule records which sheets make that loud and which hide it.

# A 4-TAP RIM: diagonal-only contact must still produce its corner pixel, and a 4-tap rim passes any
# "is there an outline" check while leaving every diagonal notched. A RIM THAT ATE A SOURCE PIXEL:
# body wins over rim, so an off-by-one shows as a body/rim mismatch rather than as nothing.
func test_rim_matches_its_oracle() -> void:
# One DENSE frame, art running to every edge where bleed is loud, and one SPARSE 32x32 frame where a
# wrong clamp is quiet: the two failure modes have opposite signatures.
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

# The element exactly as a card builds it: a polygon one rim wider than its frame on every side, UV'd
# by the real padded mapping, wearing the real material. No stand-in, because a stand-in cannot
# disagree with the game.
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
# This padded-window texel in the frame's own coordinates. The rim ring is negative or past the far
# edge and _frame_alpha reads both as empty, which IS the clamp.
			var fx := px - w
			var fy := py - w
			var got := img.get_pixel(origin.x + px, origin.y + py)
			var want : Color
			if _frame_alpha(src, frame, fx, fy):
				want = src.get_pixel(int(frame.position.x) + fx, int(frame.position.y) + fy)
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

# This frame's alpha at (fx, fy) in FRAME coordinates, with everything outside the frame read as
# empty. The oracle's copy of the shader's clamp, written from the rule rather than transcribed, so
# the two can genuinely disagree.
func _frame_alpha(src : Image, frame : Rect2, fx : int, fy : int) -> bool:
	if fx < 0 or fy < 0 or fx >= int(frame.size.x) or fy >= int(frame.size.y): return false
	return src.get_pixel(int(frame.position.x) + fx, int(frame.position.y) + fy).a > 0.0

# Is any texel within Chebyshev distance w opaque? EIGHT directions at w = 1, corners included,
# which is the half a 4-tap implementation gets wrong.
func _any_neighbour(src : Image, frame : Rect2, fx : int, fy : int, w : int) -> bool:
	for dy : int in range(-w, w + 1):
		for dx : int in range(-w, w + 1):
			if dx == 0 and dy == 0: continue
			if _frame_alpha(src, frame, fx + dx, fy + dy): return true
	return false

# Colour equality at 8-bit precision. The render target is 8-bit per channel, so comparing floats
# exactly would fail on rounding that no eye and no later pass can see. Where both are transparent
# RGB is undefined, so it is not compared.
func _same(a : Color, b : Color) -> bool:
	if absf(a.a - b.a) > 0.02: return false
	if a.a < 0.5: return true
	return absf(a.r - b.r) < 0.02 and absf(a.g - b.g) < 0.02 and absf(a.b - b.b) < 0.02

# ------------------------------------------------------------------ the mask seam

# THE RIG'S OUTLINE IS THE DRAWN CARD: the silhouette the FX mask is built from, read off a REAL
# CardVisual of every type script under the types folder, is that type's art dilated by the rim - its
# extent (TypeInput draws one texel inside its frame box) and every step of each corner's staircase.
func test_the_rig_outline_is_the_drawn_card() -> void:
	var src := CardModifierType.TYPE_TEXTURE.get_image()
	var w := int(CardVisual.ART_OUTLINE)
	var shipped := _shipped_type_scripts()
	var shipped_frames : Dictionary[int, bool] = {}
	for type_script : GDScript in shipped:
		shipped_frames[(type_script.new() as CardModifierType).get_frame()] = true
	check_impl(TypePaper in shipped, "the card types are discovered from their folder",
			"%d scripts under %s" % [shipped.size(), TYPES_DIR])
	var covered : Dictionary[int, bool] = {}
	for type_script : GDScript in shipped:
		var type_mod : CardModifierType = type_script.new()
		var frame := CardModifier.frame_rect(CardModifierType.TYPE_TEXTURE,
				CardModifierType.H_FRAMES, CardModifierType.V_FRAMES, type_mod.get_frame())
		var vis : CardVisual = CardVisual.CARD_VISUAL.instantiate()
		vis.current_context = CardVisual.DisplayContext.PREVIEW
		vis.data = CardData.new().with_type(type_mod)
		add_child(vis)
		var outline := (vis._rig_outline() as PackedVector2Array).duplicate()
		check(outline.size() <= FxAttachment.POLY,
				"type frame %d's outline fits the FX mask unresampled" % type_mod.get_frame(),
				"%d points, POLY %d" % [outline.size(), FxAttachment.POLY])
		_check_the_rig_spans_the_drawn_box(type_mod.get_frame(), src, frame, w, outline)
		_check_every_texel_agrees(type_mod.get_frame(), src, frame, w, outline)
		if type_script == TypePaper: _check_the_hand_model_is_the_resting_card(outline)
		_check_posed_rigs_fit_the_wedge_candidates(vis, type_script, outline)
		vis.queue_free()
		covered[type_mod.get_frame()] = true
	var want := shipped_frames.keys()
	var got := covered.keys()
	want.sort()
	got.sort()
	check_impl(got == want, "every frame a shipped card type draws was checked",
			"checked %s, the types use %s" % [got, want])

## The folder whose scripts are the shipped card types.
const TYPES_DIR := "res://Cards/Types"

# Every CardModifierType a script under TYPES_DIR declares, so a new type is checked with no edit here.
func _shipped_type_scripts() -> Array[GDScript]:
	var out : Array[GDScript] = []
	for file : String in DirAccess.get_files_at(TYPES_DIR):
		if file.get_extension() != "gd": continue
		var script := load(TYPES_DIR.path_join(file)) as GDScript
		if script.new() is CardModifierType: out.append(script)
	return out

# Every harness and the formation editor stand a card up from star_outline instead of a rig, so the
# hand model at rest must be the stand-in type's real resting rig, point for point.
func _check_the_hand_model_is_the_resting_card(rig: PackedVector2Array) -> void:
	var model := CardVisual.star_outline(CardVisual.CARD_SIZE, 0.0)
	var first_bad := -1
	for i : int in mini(model.size(), rig.size()):
		if not model[i].is_equal_approx(rig[i]):
			first_bad = i
			break
	check(model.size() == rig.size() and first_bad == -1,
			"star_outline at rest is a real resting TypePaper card's rig, point for point",
			"%d model points, %d rig points, first differing index %d (%s vs %s)" % [model.size(),
			rig.size(), first_bad, model[maxi(first_bad, 0)], rig[maxi(first_bad, 0)]])

## The idle animation's poses whose deformation test_pixels documents.
const POSED_SECONDS : Array[float] = [0.15, 0.30]

# The shader covers a wedge slot by testing WEDGE_CANDIDATES consecutive wedges, so a slot holding
# that many vertices leaves its last sliver untested and the mask shows a hole there. A sheared
# corner crowds its staircase into fewer slots, so the bound is asserted on the posed rig.
func _check_posed_rigs_fit_the_wedge_candidates(vis: CardVisual, type_script: GDScript,
		rest: PackedVector2Array) -> void:
	var ap := vis.get_node("AnimationPlayer") as AnimationPlayer
	check_impl(ap.has_animation(CardVisual.RIG_ANIM), "the card carries its idle animation",
			str(CardVisual.RIG_ANIM))
	var type_name := String(type_script.get_global_name())
	for t : float in POSED_SECONDS:
		ap.play(CardVisual.RIG_ANIM)
		ap.seek(t, true)
		ap.pause()
		var posed := (vis._rig_outline() as PackedVector2Array).duplicate()
		var busiest := _busiest_wedge_slot(posed)
		TestLog.line("    [posed wedge slots] %s t=%.2f  busiest slot holds %d of %d vertices"
				% [type_name, t, busiest, posed.size()])
		check_impl(posed != rest, "%s t=%.2f: the rig is posed, not at rest" % [type_name, t])
		check(busiest + 1 <= FxAttachment.WEDGE_CANDIDATES,
				"%s t=%.2f: the posed rig's busiest wedge slot holds %d vertices, so %d candidates cover it"
				% [type_name, t, busiest, busiest + 1],
				"%d candidates are tested - the slot's last sliver reads as a HOLE in the mask"
				% FxAttachment.WEDGE_CANDIDATES)

func _busiest_wedge_slot(outline: PackedVector2Array) -> int:
	var slots := PackedInt32Array()
	slots.resize(FxAttachment.WEDGES)
	for p : Vector2 in outline:
		slots[int(floorf(fposmod(atan2(p.x, -p.y), TAU) / TAU * float(FxAttachment.WEDGES)))
				% FxAttachment.WEDGES] += 1
	var busiest := 0
	for n : int in slots: busiest = maxi(busiest, n)
	return busiest

# Art that pulls IN from its frame edge draws a smaller card; a rig left on the frame box claims the
# difference and roots every effect that far proud of the drawing on those sides.
func _check_the_rig_spans_the_drawn_box(frame_index: int, src: Image, frame: Rect2, w: int,
		outline: PackedVector2Array) -> void:
	var card := Vector2i(CardVisual.CARD_SIZE)
	var drawn := Rect2i()
	for cy : int in card.y:
		for cx : int in card.x:
			if not _dilated(src, frame, cx, cy, w): continue
			var texel := Rect2i(cx, cy, 1, 1)
			drawn = drawn.merge(texel) if drawn.has_area() else texel
	var rig := Rect2(outline[0], Vector2.ZERO)
	for p : Vector2 in outline:
		rig = rig.expand(p)
	rig.position += CardVisual.CARD_SIZE * 0.5
	check(rig.is_equal_approx(Rect2(drawn)),
			"frame %d: the rig spans the %dx%d card this type draws"
			% [frame_index, drawn.size.x, drawn.size.y],
			"the rig spans %s of the card box and the drawing %s - effects root off the art by the "
			% [rig, drawn] + "difference on those sides")

# Compared at every texel centre of the card box, which never lies on a staircase edge, so a corner
# cut one texel short or an extent one texel proud each fail by their own count.
func _check_every_texel_agrees(frame_index: int, src: Image, frame: Rect2, w: int,
		outline: PackedVector2Array) -> void:
	var card := Vector2i(CardVisual.CARD_SIZE)
	var wrong := 0
	var first_bad := ""
	for cy : int in card.y:
		for cx : int in card.x:
			var p := Vector2(cx, cy) + Vector2(0.5, 0.5) - CardVisual.CARD_SIZE * 0.5
			var drawn := _dilated(src, frame, cx, cy, w)
			if Geometry2D.is_point_in_polygon(p, outline) == drawn: continue
			wrong += 1
			if first_bad.is_empty():
				first_bad = "first at card texel (%d, %d), drawn %s" % [cx, cy, drawn]
	check(wrong == 0,
			"frame %d: every texel of the card box is inside the rig's outline exactly where it is drawn"
			% frame_index,
			"%d texels disagree, %s - flames stand on nothing or skip drawn art there"
			% [wrong, first_bad])

# Is card texel (cx, cy) covered by the art dilated by w? The art sits at offset (w, w) inside the
# card. Alpha > 0 is drawn: a translucent face is still face, so it bounds the silhouette.
func _dilated(src : Image, frame : Rect2, cx : int, cy : int, w : int) -> bool:
	for dy : int in range(-w, w + 1):
		for dx : int in range(-w, w + 1):
			var ax := cx - w + dx
			var ay := cy - w + dy
			if ax < 0 or ay < 0 or ax >= int(frame.size.x) or ay >= int(frame.size.y): continue
			if src.get_pixel(int(frame.position.x) + ax, int(frame.position.y) + ay).a > 0.0:
				return true
	return false

# ------------------------------------------------------------------ the alert

# THE ALERT IS RE-DERIVED FROM THE LIVE STATUS LIST, so it cannot leak and two of them cannot switch
# each other off.

# ⚠ ASSERTED BY REMOVING THE STATUS, NEVER BY CALLING AN "OFF" METHOD - there deliberately is no off
# method. An imperative pair leaks the moment a status is freed, merged away or rewound mid-alert,
# so the test has to exercise the path that would leak.
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

# ⚠ THE SHIMMER IS NOT A STATUS ALERT, and a card wearing the activated rim runs it whenever no
# status alerts -- so the GLARE/THROB phase has to park on that card too. The shimmer reads a
# board-wide clock, so a phase left mid-bounce stays invisible until the next status alert opens on it.
func test_an_activated_rim_still_parks_the_status_phase() -> void:
	var data := TestFactories.m_card(3.0, 1)
	var vis : CardVisual = CardVisual.CARD_VISUAL.instantiate()
	vis.current_context = CardVisual.DisplayContext.PREVIEW
	vis.data = data
	add_child(vis)
	vis.show_front = true
	vis.set_match_rim(MarkMatch.Property.RANK, PaletteDB.ROLES.match_rim_active)

	var throb := StatusTestAlertThrob.new()
	data.add_status(throb)
	vis.update_visual()
	for _frame : int in 3:
		vis._advance_alert(0.1)
	check_impl(vis._alert_clock > 0.0,
			"TP-99: a THROB on a card wearing the activated rim advances that card's own phase",
			"%f" % vis._alert_clock)

	data.remove_status(throb)
	vis.update_visual()
	var mat := vis.type.material as ShaderMaterial
	var pushed_clock : float = mat.get_shader_parameter(&"u_alert_clock")
	check(vis._alert_clock == 0.0 and pushed_clock == 0.0,
			"TP-99: removing it parks that phase even though the rim goes on shimmering",
			"%f / %f" % [vis._alert_clock, pushed_clock])
	vis.queue_free()

# ------------------------------------------------------------------ the shimmer

# ⚠ THE MIDPOINTS ARE THE WHOLE TEST. This is the one ramp in the project that BLENDS rather than
# samples (an owner ruling), and a sampled implementation agrees with a blended one at every ramp
# ENTRY — so a check taken there passes on the behaviour the ruling replaced.

# ⚠ And phase 0 is INDISTINGUISHABLE from the flat activated ink, because the ramp opens on that
# entry: a still of a working shimmer and a still of a dead one are the same picture. The movement
# claim is therefore asserted at a midpoint and nowhere else.
func test_shimmer_blends_between_ramp_entries() -> void:
	var cols := PaletteDB.RAMP_MATCH.colors()
	var last := cols.size() - 1
	var at_rest := await _shimmer_pixel(0.0)
	check(_same(at_rest, PaletteDB.color(PaletteDB.ROLES.match_rim_active)),
			"TP-91: at phase 0 the shimmering rim draws the activated ink exactly",
			"drew %s, the role is %s" % [at_rest,
			PaletteDB.color(PaletteDB.ROLES.match_rim_active)])

	var wrong := ""
	var still := 0
	for i : int in last:
# Halfway between entry i and entry i+1: the bounce covers the whole ramp in half a loop, so band i's
# midpoint sits at (i + 0.5) / (2 * last) turns. Derived from the ramp, never typed in.
		var phase := (float(i) + 0.5) / (2.0 * float(last))
		var drawn := await _shimmer_pixel(phase)
		var want := _shimmer_oracle(phase)
		if not _same(drawn, want) and wrong.is_empty():
			wrong = "phase %.3f drew %s, the blend of entries %d and %d is %s" \
					% [phase, drawn, i, i + 1, want]
		if _same(drawn, at_rest): still += 1
	check(wrong.is_empty(),
			"TP-91: every midpoint is the BLEND of its two ramp neighbours, not either of them",
			wrong)
	check(still == 0,
			"TP-91: and every midpoint differs from the resting ink, so the rim is actually moving",
			"%d of %d midpoints drew the resting colour" % [still, last])

# The rim colour a shimmering element draws at `phase`, taken off the render target. The element is
# built as `_check_frame_against_oracle` builds one; no match ink is set on it because the shimmer
# ignores `u_outline_index` entirely — what it draws comes from the ramp alone.
func _shimmer_pixel(phase : float) -> Color:
	var sheet : Texture2D = PipRankNumeral.RANK_TEXTURE
	var frame := CardModifier.frame_rect(sheet, PipRankNumeral.H_FRAMES, PipRankNumeral.V_FRAMES, 0)
	var w := int(CardOutline.WIDTH)
	var poly := Polygon2D.new()
	var h := frame.size * 0.5 + Vector2.ONE * CardOutline.WIDTH
	poly.polygon = PackedVector2Array([Vector2(-h.x, -h.y), Vector2(h.x, -h.y),
			Vector2(h.x, h.y), Vector2(-h.x, h.y)])
	CardOutline.frame_polygon(poly, sheet, PipRankNumeral.H_FRAMES, PipRankNumeral.V_FRAMES, 0)
	CardOutline.fill_texture(poly)
	CardOutline.set_rim(poly, CardOutline.STYLE, CardVisual.CARD_SIZE)
	CardOutline.set_alert(poly, CardAlert.shimmer(), CardOutline.STYLE)
	CardOutline.set_clock(poly, phase)
	_stage.add_child(poly)
	var img := await _shoot()
	var at := _first_rim_texel(sheet.get_image(), frame, w)
	var origin := Vector2i(_stage.position) - Vector2i(h)
	return img.get_pixel(origin.x + at.x + w, origin.y + at.y + w)

# The first texel of the padded window the rim rule puts a rim on — empty here, opaque within one
# unit. Found from the sheet rather than named, so the probe cannot drift off the rim.
func _first_rim_texel(src : Image, frame : Rect2, w : int) -> Vector2i:
	for fy : int in range(-w, int(frame.size.y) + w):
		for fx : int in range(-w, int(frame.size.x) + w):
			if _frame_alpha(src, frame, fx, fy): continue
			if _any_neighbour(src, frame, fx, fy, w): return Vector2i(fx, fy)
	return Vector2i(0, 0)

# The colour the shimmer OUGHT to draw at `phase`, written from the rule: a triangle over the ramp,
# reversed so phase 0 rests on the first entry, blended between the two it falls between.
func _shimmer_oracle(phase : float) -> Color:
	var cols := PaletteDB.RAMP_MATCH.colors()
	var last := cols.size() - 1
	var bounce := absf((phase - floorf(phase)) * 2.0 - 1.0)
	var t := (1.0 - bounce) * float(last)
	var lo := floori(t)
	return cols[lo].lerp(cols[mini(lo + 1, last)], t - float(lo))

# ------------------------------------------------------------------ the source-level rules

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

# ⚠ THE CARD SCENE MUST SHIP NO SAVED MATERIAL, AND THAT IS NOT A STYLE RULE.
# CardOutline.material_of() assigns poly.material, which is a SCENE MUTATION, and CardVisual is
# @tool, so it happens in the editor too.

# Any edit that dirties the scene persists whatever uniform state the scene's PREVIEW card produced,
# and that card has no suit: card_visual.gd's art branch never runs for it, so frame_polygon() never
# fires on Suit or Art and u_frame_uv stays at the shader default of the whole sheet, i.e. NO CLAMP.

# The sheets are packed edge to edge with no gutter, so an unclamped padded window samples the four
# neighbouring frames and the art visibly bleeds. This asserts the scene, not the symptom, so it
# catches ANY future editor re-bake rather than the one uniform that happened to be wrong.
func test_the_card_scene_ships_no_baked_material() -> void:
	var text := FileAccess.get_file_as_string(CARD_SCENE_PATH)
	check(not text.is_empty(), "the card scene is readable at %s" % CARD_SCENE_PATH)
	check(not text.contains("SubResource(\"ShaderMaterial"),
			"card_visual.tscn assigns no saved ShaderMaterial (an editor re-bake freezes the "
			+ "suitless preview's uniforms, including an unclamped u_frame_uv)")
	check(not text.contains("[sub_resource type=\"ShaderMaterial\""),
			"card_visual.tscn defines no ShaderMaterial sub-resource")

# CARD_SEPARATION is DERIVED from where the pips actually sit, not asserted to be 16.

# ⚠ THE WHOLE POINT IS THAT THE ART CAN MOVE. The visible strip of a covered card has to show that
# card's pip row plus clearance for the idle rig, and the pip row's position lives in
# card_visual.tscn where an art pass can change it.

# A check reading CARD_SEPARATION == 16 would pass with the pips moved anywhere at all, and the
# board's row pitch would silently stop matching the art it exists to reveal.

# Stacks grow UPWARD, so the strip that stays visible is the card's BOTTOM band and the margin that
# matters is the one below the pips.
func test_card_separation_derives_from_the_pip_row() -> void:
	var text := FileAccess.get_file_as_string(CARD_SCENE_PATH)
	check(not text.is_empty(), "the card scene is readable at %s" % CARD_SCENE_PATH)

# The Rank pip is positioned in the scene; its polygon gives the pip's own extent.
	var rank_y := _scene_node_position_y(text, "Rank")
	var pip_half := _scene_node_polygon_half_height(text, "Rank")
	check(rank_y > 0.0 and pip_half > 0.0,
			"the pip row's position and extent are readable from the scene",
			"y %.1f, half-height %.1f" % [rank_y, pip_half])

	var card_bottom : float = CardVisual.CARD_SIZE.y / 2.0
	var pip_bottom := rank_y + pip_half
	var margin_below := card_bottom - pip_bottom
	var pip_height := pip_half * 2.0
# The one number that is a CHOICE rather than a measurement, the owner's clearance for the idle rig:
# "pip added 2 pixels, need 2 unit clearance to account for animations".
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

# OutlineStyle types its glare slider limits out, naming CardVisual there being a cyclic reference,
# so a card-size change reaches them only through this row going red.
func test_the_glare_slider_limits_are_the_card_width() -> void:
	var limits : Dictionary[String, float] = {}
	for property : Dictionary in OutlineStyle.new().get_property_list():
		var knob : String = property["name"]
		if knob in ["glare_thickness", "glare_buffer"]:
			limits[knob] = float((property["hint_string"] as String).split(",")[1])
	var thickness : float = limits.get("glare_thickness", -1.0)
	var buffer : float = limits.get("glare_buffer", -1.0)
	check(thickness == CardVisual.CARD_SIZE.x,
			"the glare thickness slider tops out at the card's width", str(limits))
	check(buffer == CardVisual.CARD_SIZE.x / 2.0,
			"the glare buffer slider tops out at half the card's width", str(limits))

# An editor re-save drops `auto_calculate_length_and_angle = false` from the childless Arm_* bones.
# With the default a leaf bone warns on every transform change: 86k log lines, ms/frame 25 -> 50.
func test_leaf_bones_do_not_auto_calculate() -> void:
	var vis : CardVisual = CardVisual.CARD_VISUAL.instantiate()
	var offenders : Array[String] = []
	for node : Node in vis.find_children("*", "Bone2D"):
		var bone := node as Bone2D
		if bone.find_children("*", "Bone2D", false).is_empty() and bone.get_autocalculate_length_and_angle():
			offenders.append(String(bone.name))
	check(offenders.is_empty(), "every childless Bone2D in card_visual.tscn has auto length/angle off",
			"auto-calculating: %s" % [offenders])
	vis.free()

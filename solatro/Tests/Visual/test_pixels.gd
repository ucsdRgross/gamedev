extends TestSuite
# res://Tests/Visual/test_pixels.gd
# ==============================================================================
# PIXELS — the suite that actually looks at what was drawn.
#
# Every other suite in all_tests.tscn is renderer-INDEPENDENT: they assert node order, uniform
# values, data invariants. None of them can see a pixel, and under `--headless` (the dummy renderer)
# a shader is never even compiled — so a GLSL error, an inverted sign, a flame hanging off the
# BOTTOM edge or an effect that draws nothing at all used to pass the whole suite silently. Four such
# bugs shipped past a green run before the snapshot harness caught them by eye.
#
# So this suite renders the real effects into a SubViewport and ASSERTS on the resulting image. It is
# the reason all_tests.tscn now needs a real renderer.
#
# ⚠ IT FAILS, LOUDLY, UNDER A DUMMY RENDERER — it does not skip (owner 2026-07-27: "prioritize
# running all tests properly over skipping them, even if that means all tests never run headless
# anymore"). A skipped pixel check is indistinguishable from a passing one in a log, which is exactly
# how the four bugs above survived. Run the suite WINDOWED:
#     Godot --path solatro res://Tests/all_tests.tscn        (no --headless)
#
# Its reviewable twin is Tests/Visual/fx_snapshot.tscn, which writes PNGs a human judges. This suite
# is for the claims that can be stated as a number; that one is for "does it look right".
#
# CATEGORY MAP: every check here is BEHAVIOR — they are the owner's own visual rulings (flames point
# up, balls are spherical, fire is onion-layered, one pixel size for all art), not internal pins.
# ==============================================================================

## The offscreen stage. Small and zoomed: the checks are about geometry, and a 320px viewport at 4
## pixels per art unit renders an 80-art-unit-wide field, which covers a card plus its flames.
const VP_SIZE := 320
const ZOOM := 4.0

## Pixels per art unit for the CURRENT shot. Not the constant: an 8-ball pattern throws its arc 65 art
## units up and a 50-ball one 89, so a fixed zoom pushed most of the pattern off the stage and the
## first run of this suite reported 20 "missing" balls that were simply outside the viewport. Each
## shot fits itself with _zoom_to_fit.
var _zoom := ZOOM

## Ball agreement tolerance in ART UNITS. `nearest` finds a ball's EDGE pixel, so anything under the
## ball's own radius is agreement; 2.0 is comfortably inside that at every count and still catches
## the ~5-unit-and-up disagreements a real path bug produces.
const BALL_TOLERANCE := 2.0

var _vp : SubViewport
var _stage : Node2D

func suite_name() -> String:
	return "PIXELS"

func _ready() -> void:
	TestLog.line("============ PIXELS TEST PASS ============")
	behavior_section("A REAL RENDERER IS REQUIRED (never skipped)")
	if not _check_renderer():
		finish()
		return
	_build_stage()
	await test_fire_draws_upright()
	await test_fire_bands_are_onion_shells()
	await test_balls_sit_on_their_oracle()
	await test_ball_reads_as_a_sphere()
	await test_hoop_halves_reassemble()
	await test_one_pixel_size_for_all_art()
	finish()

## The guard. A dummy renderer cannot compile a shader or rasterize a triangle, so every check below
## would be meaningless — it is reported as a FAILURE with the fix in the message, never as a skip.
func _check_renderer() -> bool:
	var display := DisplayServer.get_name()
	var live := display != "headless"
	check(live, "the run has a real renderer, so pixels can be checked at all",
			"DisplayServer is '%s' — re-run all_tests.tscn WITHOUT --headless (this suite cannot be "
			% display + "verified by a dummy renderer, and skipping it would hide exactly the bugs "
			+ "it exists to catch)")
	return live

func _build_stage() -> void:
	_vp = SubViewport.new()
	_vp.size = Vector2i(VP_SIZE, VP_SIZE)
	_vp.disable_3d = true
	# TRANSPARENT, not the project clear colour: every check below asks "was this pixel DRAWN", and an
	# opaque backdrop answers yes for all 102400 of them — which made the first run of this suite
	# report 19200 phantom pixels under the card and pass its "something was drawn" check trivially.
	_vp.transparent_bg = true
	# ALWAYS, not UPDATE_ONCE: each shot re-populates the stage and waits for a fresh frame, and an
	# update mode that fires once would hand every later shot the FIRST shot's image.
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_vp)
	_stage = Node2D.new()
	_stage.position = Vector2(VP_SIZE, VP_SIZE) * 0.5
	_vp.add_child(_stage)
	_zoom_to_fit(0.0)

## Blow the stage up as far as `half_extent` art units still fitting inside it allows, capped at ZOOM.
## Everything a shot measures must be ON the stage: a clipped effect reads as a missing one.
func _zoom_to_fit(half_extent: float) -> void:
	_zoom = ZOOM if half_extent <= 0.0 else minf(ZOOM, float(VP_SIZE) * 0.47 / half_extent)
	_stage.scale = Vector2.ONE * _zoom

# ------------------------------------------------------------------ the checks

## The bug class this suite exists for: an effect that compiles to nothing, or renders MIRRORED.
## QuadMesh's +Y is up, so a raw (UV - 0.5) * extent puts the flames under the card — which is what
## the very first GPU run actually showed. Assert both ends: fire above the top edge, nothing at all
## below the bottom one (at wrap 0 the flame is on top by construction).
func test_fire_draws_upright() -> void:
	behavior_section("FIRE RENDERS, AND IT RENDERS UPWARD")
	var body := CardVisual.CARD_SIZE
	_host_fire(body, 4, _plain_fire_style())
	var img := await _shoot()
	var lit := PixelProbe.count(img, Rect2i(Vector2i.ZERO, img.get_size()), PixelProbe.is_opaque)
	check(lit > 0, "the fire shader compiles and draws something at 4 stacks",
			"0 opaque pixels — a dummy renderer, a GLSL error, or an effect that culled itself")
	var half := body * 0.5 * _zoom
	var centre := Vector2(VP_SIZE, VP_SIZE) * 0.5
	var above := Rect2i(Vector2i(0, 0), Vector2i(VP_SIZE, int(centre.y - half.y)))
	var below := Rect2i(Vector2i(0, int(centre.y + half.y)), Vector2i(VP_SIZE, VP_SIZE))
	check(PixelProbe.count(img, above, PixelProbe.is_opaque) > 0,
			"flames reach ABOVE the host's top edge")
	check(PixelProbe.count(img, below, PixelProbe.is_opaque) == 0,
			"nothing is drawn below the host's bottom edge (the QuadMesh y-flip)",
			"%d pixels under the card" % PixelProbe.count(img, below, PixelProbe.is_opaque))

## ONION SHELLS, not rows (owner 2026-07-27) — and the check has to DISCRIMINATE, which took two
## tries. "The core is hotter than the rim at one height" does NOT: the old height-based heat divided
## by `top`, which already varies across x, so it satisfied that too (verified by mutation — the
## check passed with the old formula restored, i.e. it was worthless).
##
## What actually separates them is the SHAPE of the hottest band:
##   * row-layered (heat from height): iso-heat contours are the outline scaled VERTICALLY, all
##     anchored on the base — so the hottest band is a WIDE, SHORT slab lying along the base.
##   * onion-layered (heat from distance across, over the local half-width): the contours are scaled
##     copies about the core — so the hottest band is a TALL, NARROW spine up the middle.
## Assert the spine. Noise off, one tendril, so the hot region is the shell structure and nothing else.
func test_fire_bands_are_onion_shells() -> void:
	behavior_section("FIRE IS ONION-LAYERED, NOT ROW-LAYERED")
	_host_fire(CardVisual.CARD_SIZE, 1, _plain_fire_style())   # ONE tendril, full width
	var img := await _shoot()
	var area := Rect2i(Vector2i.ZERO, img.get_size())
	var hottest := _peak_luminance(img, area)
	check(hottest > 0.0, "the flame rendered, so it has a hottest band at all",
			"peak luminance %.3f" % hottest)
	if hottest <= 0.0: return
	# The hottest band: everything within a hair of the peak. `filter_nearest` on the ramp makes the
	# bands flat, so this picks out exactly one band rather than a gradient's crest.
	var core := PixelProbe.bounds(img, area, func(c: Color) -> bool:
			return PixelProbe.is_opaque(c) and c.get_luminance() >= hottest - 0.02)
	check(core.size.y > core.size.x,
			"the hottest band is a TALL SPINE up the flame's core, not a wide slab on its base",
			"hottest band is %d x %d px (w x h) — wider than tall means the colours are stacked in "
			% [core.size.x, core.size.y] + "rows")

## Every ball, at every count, sits where the INDEPENDENT oracle says. This is the check that would
## have caught a real path bug — and the one whose earlier disagreement turned out to be the harness
## re-enabling the clock it had parked, so the tolerance is in art units and stated.
func test_balls_sit_on_their_oracle() -> void:
	behavior_section("BALLS SIT ON THEIR SPEC POSITIONS")
	var style := StatusJuggling.JUGGLE_STYLE
	for n : int in [1, 3, 8, 50]:
		var geo := FxJuggle.geometry(n, style)
		var phase := 0.13
		_host_balls(n, style, phase)
		var img := await _shoot()
		var expected := PixelProbe.ball_positions(float(n), phase, geo[&"u_span"],
				geo[&"u_arc_height"], geo[&"u_return_height"], style.ball_top_fraction)
		var worst := 0.0
		var missing := 0
		for p : Vector2 in expected:
			var want := Vector2(VP_SIZE, VP_SIZE) * 0.5 + p * _zoom
			var hit := PixelProbe.nearest(img, want, int(ceilf(BALL_TOLERANCE * _zoom)) + 2,
					PixelProbe.is_warm)
			if not hit[&"found"]:
				missing += 1
				continue
			worst = maxf(worst, (hit[&"offset"] as Vector2).length() / _zoom)
		check(missing == 0 and worst <= BALL_TOLERANCE,
				"%d balls all render within %.1f art units of the spec" % [n, BALL_TOLERANCE],
				"%d missing, worst offset %.2f art units" % [missing, worst])

## A ball must read as a SPHERE, not a disc (owner 2026-07-27): banded curvature plus a highlight
## sitting ON the surface. Measurable form: at least three distinct tones inside one ball (a flat
## two-tone split has two), and the brightest tone is OFF CENTRE — a centred dot is a disc's gloss.
func test_ball_reads_as_a_sphere() -> void:
	behavior_section("BALLS ARE SPHERICAL")
	var style := StatusJuggling.JUGGLE_STYLE.duplicate() as FxStyle
	style.ball_radius = 12.0
	style.ball_radius_min = 12.0
	style.ball_span = 1.0
	style.ball_arc_height = 1.0
	style.ball_return_height = 1.0
	_host_balls(1, style, 0.3)
	var img := await _shoot()
	var area := Rect2i(Vector2i.ZERO, img.get_size())
	var tones := PixelProbe.palette_of(img, area)
	check(tones.size() >= 3, "one ball shades into 3+ hard tones (a disc has 2)",
			"%d distinct tones" % tones.size())
	var box := PixelProbe.bounds(img, area, PixelProbe.is_opaque)
	check(box.size.x > 4 and box.size.y > 4, "the big ball actually rendered",
			"bounds %s" % box)
	if box.size.x <= 4: return
	var brightest := _brightest_pixel(img, box)
	var off := (Vector2(brightest) - (Vector2(box.position) + Vector2(box.size) * 0.5)).length()
	check(off > float(box.size.x) * 0.08,
			"the highlight sits OFF-CENTRE, on the surface (a centred dot reads flat)",
			"brightest pixel %.1f px from the centre of a %d px ball" % [off, box.size.x])

## The hoop's two halves are the FULL frame cut down its middle, so drawing them side by side must
## reproduce the whole ring EXACTLY — no seam, no doubled column, nothing missing. Pixel-for-pixel:
## this is the one claim about the art that a human eye cannot actually confirm.
func test_hoop_halves_reassemble() -> void:
	behavior_section("THE HOOP'S HALVES ARE THE WHOLE RING")
	var whole := HoopVisual.new()
	_zoom_to_fit(whole.art_size.y * 0.5 + 2.0)
	_place(whole, 1.0)
	var img_whole := await _shoot()
	var split := HoopVisual.new()
	_place(split, 1.0)
	split.set_split_active(true)
	_place(split.ensure_back(), 1.0)
	_place(split.ensure_front(), 1.0)
	var img_split := await _shoot()
	var diff := 0
	for y : int in img_whole.get_height():
		for x : int in img_whole.get_width():
			if img_whole.get_pixel(x, y) != img_split.get_pixel(x, y): diff += 1
	check(diff == 0, "back half + front half == the whole ring, pixel for pixel",
			"%d pixels differ" % diff)

## ONE PIXEL SIZE FOR ALL ART (owner 2026-07-27). The ball prop and the card's Ball pip are the SAME
## source frame, so at any card_scale their drawn footprints must be identical — that is the whole
## claim behind PropVisual.ART_PIXEL_SCALE, and it is only true if the prop scales WITH the cards.
func test_one_pixel_size_for_all_art() -> void:
	behavior_section("A PROP TEXEL IS A CARD TEXEL, AT EVERY CARD SCALE")
	var pip_frames := Vector2i(PipSuit.SUIT_TEXTURE_H_FRAMES, PipSuit.SUIT_TEXTURE_V_FRAMES)
	var frame := CardModifier.frame_rect(PipSuit.SUIT_TEXTURE, pip_frames.x, pip_frames.y,
			BallVisual.FRAME)
	for card_scale : float in [1.5, 2.5, 4.0]:
		# The card's pip: one frame across an UNSCALED frame-sized quad, the card then scaled.
		var pip := _Sprite.new()
		pip.sheet = PipSuit.SUIT_TEXTURE
		pip.src = frame
		pip.dest = Rect2(-frame.size * 0.5, frame.size)
		_place(pip, card_scale)
		var img_pip := await _shoot()
		var box_pip := PixelProbe.bounds(img_pip, Rect2i(Vector2i.ZERO, img_pip.get_size()),
				PixelProbe.is_opaque)
		# The prop, scaled the way PropLayer scales it every frame.
		var prop := BallVisual.new()
		_place(prop, card_scale / PropVisual.AUTHORED_CARD_SCALE)
		var img_prop := await _shoot()
		var box_prop := PixelProbe.bounds(img_prop, Rect2i(Vector2i.ZERO, img_prop.get_size()),
				PixelProbe.is_opaque)
		check(box_pip.size == box_prop.size and box_pip.size.x > 0,
				"card_scale %.1f: the prop's footprint matches the card pip's" % card_scale,
				"pip %s vs prop %s" % [box_pip.size, box_prop.size])

# ----------------------------------------------------------------- the stage

## Fire off `style` at `stacks`, on a host of `body` art units — the same FxAttachment a card builds.
func _host_fire(body: Vector2, stacks: int, style: FxStyle) -> void:
	_zoom_to_fit(body.y * 0.5 + style.height * (1.0 + style.height_var) + 4.0)
	var att := FxAttachment.new()
	att.configure(body, false, FxAttachment.Shape.BOX, FxAttachment.Half.WHOLE, false)
	_place(att, 1.0)
	att.sync([FxFire.request(&"fire", stacks, style)] as Array[FxRequest])
	_park(att, 0.0)

## The juggling pattern at a fixed phase, with no ball on fire (this suite is about the balls).
func _host_balls(n: int, style: FxStyle, phase: float) -> void:
	var geo := FxJuggle.geometry(n, style)
	_zoom_to_fit(geo[&"u_arc_height"] + geo[&"u_ball_radius"] + 4.0)
	var att := FxAttachment.new()
	att.configure(CardVisual.CARD_SIZE, false, FxAttachment.Shape.BOX, FxAttachment.Half.WHOLE,
			false)
	_place(att, 1.0)
	att.sync(FxJuggle.requests(n, PackedInt32Array(), style, StatusJuggling.BALL_FIRE_STYLE))
	_park(att, phase)

## Park an attachment's clock at a FIXED time and phase so the image is reproducible.
## ⚠ ORDER: `_push_live` ends with `set_process(not _fx.is_empty())`, so disabling the process before
## pushing silently re-enables it and the awaited frames then advance the phase — which is exactly
## the false "ball positions are wrong" this suite would otherwise report. Disable it LAST.
func _park(att: FxAttachment, phase: float) -> void:
	att._time = 3.7
	att._phase = phase
	att._push_live(0.0)
	att.set_process(false)

## Fire with every source of raggedness off: this suite measures geometry and band structure, and
## noise/flicker/dither only make both harder to state.
func _plain_fire_style() -> FxStyle:
	var style := StatusBurning.CARD_FIRE_STYLE.duplicate() as FxStyle
	style.height_var = 0.0
	style.noise_amp = 0.0
	style.dither = 0.0
	style.sway_amp = 0.0
	style.desync = 0.0
	return style

func _place(node: Node2D, node_scale: float) -> void:
	node.scale = Vector2.ONE * node_scale
	_stage.add_child(node)

## Draw the current stage and hand back its image, then clear the stage for the next shot.
## Two frames: one to apply what was just written, one to be sure it reached the render target.
func _shoot() -> Image:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := _vp.get_texture().get_image()
	for child in _stage.get_children():
		_stage.remove_child(child)
		child.queue_free()
	return img

# ----------------------------------------------------------------- pixel readers

## The highest luminance among the drawn pixels — "how far up the heat ramp did this effect get",
## since the ramp runs deep red to white.
func _peak_luminance(img: Image, area: Rect2i) -> float:
	var best := 0.0
	for y : int in range(area.position.y, area.end.y):
		for x : int in range(area.position.x, area.end.x):
			var c := img.get_pixel(x, y)
			if PixelProbe.is_opaque(c): best = maxf(best, c.get_luminance())
	return best

func _brightest_pixel(img: Image, area: Rect2i) -> Vector2i:
	var best := Vector2i.ZERO
	var best_l := -1.0
	for y : int in range(area.position.y, area.end.y):
		for x : int in range(area.position.x, area.end.x):
			var c := img.get_pixel(x, y)
			if not PixelProbe.is_opaque(c): continue
			if c.get_luminance() > best_l:
				best_l = c.get_luminance()
				best = Vector2i(x, y)
	return best

## A bare textured quad, for drawing a card's pip the way CardVisual does — one frame across a
## frame-sized shape, with card_scale applied by the node's own scale.
class _Sprite extends Node2D:
	var sheet : Texture2D
	var src : Rect2
	var dest : Rect2
	func _draw() -> void:
		draw_texture_rect_region(sheet, dest, src)

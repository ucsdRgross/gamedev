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
# up, balls are spherical, fire is a bounded cover field, one pixel size for all art), not
# internal pins.
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

## The per-host random seed every shot pins, so the images are REPRODUCIBLE. `_seed` drives flame
## flicker, the whole-effect pulse and the ball spin — and the spin rotates the shading frame the
## highlight sits in, so an unpinned seed makes "the highlight is off-centre" a coin flip. Any value
## works; this one is simply a value that is the same every run.
const SEED := 12.5

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
	await test_fire_is_a_bounded_falling_cover_field()
	await test_every_upward_surface_burns()
	await test_balls_sit_on_their_oracle()
	await test_balls_ignore_their_hosts_rotation()
	await test_ball_reads_as_a_sphere()
	await test_hoop_halves_reassemble()
	await test_one_pixel_size_for_all_art()
	await test_effects_take_their_host_modulate()
	await test_balls_alternate_directions()
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

## THE COVER FIELD IS THE MODEL, AND THIS IS WHAT MAKES IT A MODEL RATHER THAN A GRADIENT (owner
## 2026-07-29, replacing the onion shells with generic noise fire). Heat is
## `cover * (((cover + aperture) * n - aperture) * gain)` where `cover` is how far above the nearest
## surface BELOW this fragment it sits — 1 at the surface, falling one tap at a time to 0 at exactly
## `height` above it.
##
## ⚠ THE ONION SECTION THIS REPLACES DIED WHOLE, and deliberately so: "the hottest band is a narrow
## core" and "the base row crosses several shells" were claims about a per-flame arch with shells
## wrapped around its spine, and there is no arch. Porting them would have been asserting the old
## model against the new one. What is asserted instead are the three properties of the NEW model that
## a bug can actually break, none of which depend on a single art knob:
##
##  1. **THE FLAME IS BOUNDED AT `height`.** No tap reaches further, so nothing may be drawn above it.
##     This is the invariant that makes "no flame leaps the hole" and "the quad cannot clip its own
##     flames" both free, and it is the one an off-by-one in the tap ladder breaks.
##  2. **HEAT FALLS OFF WITH HEIGHT.** The band against the body must be hotter than the band near the
##     top of the reach. A `cover` that came back constant — the failure mode of a broken mask lookup,
##     which still draws a perfectly plausible-looking slab — passes every "did it render" check and
##     fails this one.
##  3. **IT IS FORM-FITTING**: with `skew = 0` the flame is exactly as wide as the body under it and no
##     wider. Fire that spread past the silhouette would mean the taps are not stepping straight down.
##
## Noise is held flat (`_plain_fire_style`), because the noise exists precisely to hide 1 and 2.
func test_fire_is_a_bounded_falling_cover_field() -> void:
	behavior_section("FIRE IS A COVER FIELD: BOUNDED AT `height`, COOLING UPWARD, FORM-FITTING")
	var body := CardVisual.CARD_SIZE
	var style := _plain_fire_style()
	# ⚠ EIGHT STACKS, NOT ONE, AND THE RAMP IS WHY. At one stack `u_level` is 0, which is the ramp's
	# darkest row — entry 0 makes a 1-stack flame near-black, a known art item — so the WHOLE flame
	# lands inside ~0.01 of luminance and "the base is hotter than the tip" is unmeasurable however
	# correct the shader is. It failed exactly that way once. Eight is where the game lives and where
	# the ramp has range to read.
	var stacks := 8
	_host_fire(body, stacks, style)
	var img := await _shoot()
	var area := Rect2i(Vector2i.ZERO, img.get_size())
	var flame := PixelProbe.bounds(img, area, PixelProbe.is_opaque)
	check(flame.size.y > 0, "the flame rendered at all", "no opaque pixels")
	if flame.size.y <= 0: return
	var centre := Vector2(VP_SIZE, VP_SIZE) * 0.5
	var top_edge := centre.y - body.y * 0.5 * _zoom
	# 1. THE HARD BOUND: `height + sink`, because the cover ladder is measured from `p.y - sink` — so
	# the topmost fragment that can light sits that far above the surface and none can sit higher.
	# One pixel of slack for the quantization of the FX grid.
	var live : Dictionary[StringName, float] = FxFire.stacks_live(stacks, style)
	var reach_px := (live[&"u_height"] + maxf(style.sink, 0.0)) * _zoom
	var overshoot := top_edge - float(flame.position.y)
	check(overshoot <= reach_px + 1.0,
			"nothing is drawn higher than `height` above the surface — the tap ladder is a hard bound",
			"flame reaches %.1f px above the top edge, but %d taps over %.1f art units plus %.1f of "
			% [overshoot, style.cover_taps, live[&"u_height"], style.sink]
			+ "sink bound it at %.1f px" % reach_px)
	# 2. COOLING UPWARD. Two rows near the two ends OF WHAT WAS DRAWN, compared on mean luminance over
	# the lit pixels of each. Rows rather than single pixels because the ramp is `filter_nearest` and a
	# single pixel can sit on a band edge.
	#
	# ⚠ MEASURED AGAINST THE FLAME'S OWN EXTENT, NOT AGAINST `height`, and that is not laziness — it
	# is the aperture. `heat = cover * (((cover + ap) * n - ap) * gain)` goes NEGATIVE at low cover:
	# at the shipped card tuning with the noise held flat, cover 0.5 lands under `ramp_cut` and cover
	# 0.25 is already below zero, so the flame legitimately fills only the lower half of its reach and
	# the noise is what pushes it higher. A row pinned at 60 % of `height` reads EMPTY and fails a
	# correct shader — which it did, on the first run of this check.
	var low := _row_luminance(img, flame, flame.end.y - 2)
	var high := _row_luminance(img, flame, flame.position.y + maxi(flame.size.y / 6, 1))
	check(low > 0.0 and high > 0.0 and low > high + 0.02,
			"heat FALLS OFF with height above the surface, rather than sitting in one flat slab",
			"mean luminance %.3f at the flame's base vs %.3f near its top — a constant `cover` "
			% [low, high] + "(a broken mask lookup) still draws a plausible slab and fails only here")
	# 3. FORM-FITTING. With skew off, the flame may not reach past the body it stands on.
	var body_left := centre.x - body.x * 0.5 * _zoom
	var body_right := centre.x + body.x * 0.5 * _zoom
	check(float(flame.position.x) >= body_left - 1.0 and float(flame.end.x) <= body_right + 1.0,
			"and the flame is exactly as wide as the body under it — the taps step straight DOWN",
			"flame spans x %d..%d against a body of %.0f..%.0f"
			% [flame.position.x, flame.end.x, body_left, body_right])

## Mean luminance of the lit pixels of one row, inside `box`. -1 when the row is empty, so a caller
## can tell "cold" from "not drawn".
func _row_luminance(img: Image, box: Rect2i, y: int) -> float:
	if y < 0 or y >= img.get_height(): return -1.0
	var total := 0.0
	var n := 0
	for x : int in range(maxi(box.position.x, 0), mini(box.end.x, img.get_width())):
		var c := img.get_pixel(x, y)
		if not PixelProbe.is_opaque(c): continue
		total += c.get_luminance()
		n += 1
	return total / float(n) if n > 0 else -1.0

## THE CLAIM §1 EXISTS FOR: fire finds EVERY upward-facing surface in the art, not just the topmost
## one in each column (FX_HANDOFF §1.1). The hoop is the counterexample the owner named — its ring
## has TWO upward-facing surfaces in the same column, the outer top arc and the inner arc at the
## BOTTOM of the hole, and a per-column contour can only ever return the first.
##
## Stated as pixels: inside the ring's HOLE, sitting on its lower inner arc, there must be flame. The
## old model could not put a single lit pixel there, by construction — its skirt's `a < PI/2` cut
## discarded that surface and `contour_y` never saw it. So this check is the discriminator, and it is
## a real one: it fails against everything that shipped before 2026-07-30.
##
## AND THE INVARIANT THAT BOUNDS IT: no flame may LEAP the hole. A flame reaching from the outer arc
## down to the inner one would fill the ring solid — the "enormous flame" the owner
## forbade — so the hole's MIDDLE, a flame-length clear of both surfaces, must stay empty.
func test_every_upward_surface_burns() -> void:
	behavior_section("EVERY UPWARD-FACING SURFACE BURNS, AND NO FLAME LEAPS THE HOLE")
	var body := PropVisual.art_size_for(HoopVisual.SHEET, HoopVisual.FRAMES)
	var style : FxFireStyle = PropVisual.PROP_FIRE_STYLE
	_zoom_to_fit(body.y * 0.5 + style.height + 4.0)
	var att := FxAttachment.new()
	att.configure(body, false, FxAttachment.Shape.SPRITE, FxAttachment.Half.WHOLE, false)
	_place(att, 1.0)
	att.measure_sprite_silhouette(HoopVisual.SHEET,
			CardModifier.frame_rect(HoopVisual.SHEET, HoopVisual.FRAMES, 1, 0), body)
	att._seed = SEED
	att.sync([FxFire.request(&"fire", 4, style)] as Array[FxRequest])
	_park(att, 0.0)
	var img := await _shoot()
	var mid := Vector2(VP_SIZE, VP_SIZE) * 0.5
	# The hole is the ring minus its wall. Measured off the art itself rather than typed in: the wall
	# is a uniform inset of the outer ellipse (see the sheet), so the hole's half-height is the body's
	# minus that inset, and the band just above the hole's floor is where the inner flames live.
	var wall := body.x * 0.5 - _hole_half_width(body)
	var hole_bottom := body.y * 0.5 - wall
	var inner := Rect2i(
			Vector2i(int(mid.x - body.x * 0.15), int(mid.y + (hole_bottom - style.height) * _zoom)),
			Vector2i(int(body.x * 0.3 * _zoom), int(style.height * _zoom)))
	check(PixelProbe.count(img, inner, PixelProbe.is_opaque) > 0,
			"the ring's INNER-BOTTOM arc — an upward surface no contour can reach — is alight",
			"0 lit pixels in the hole's floor band %s; this is the exact bug §1 replaced the contour "
			% inner + "model to fix, so a zero here means the mask is not being marched")
	# The hole's middle: further than a flame is long from either surface, so nothing may reach it.
	var clear := Rect2i(Vector2i(int(mid.x - body.x * 0.1), int(mid.y - body.y * 0.1)),
			Vector2i(int(body.x * 0.2 * _zoom), int(body.y * 0.2 * _zoom)))
	check(PixelProbe.count(img, clear, PixelProbe.is_opaque) == 0,
			"and the middle of the hole is EMPTY — no flame leaps from one arc to the other",
			"%d lit pixels in the ring's hollow: a flame has bridged two separate surfaces, which "
			% PixelProbe.count(img, clear, PixelProbe.is_opaque)
			+ "is the ENORMOUS FLAME a bounded flame length makes impossible")

## Half the width of the hoop's HOLE, in art units, read off the sheet's alpha — never typed in, so
## this cannot drift from the drawing the mask is sampled out of.
func _hole_half_width(body: Vector2) -> float:
	var img := HoopVisual.SHEET.get_image()
	var src := CardModifier.frame_rect(HoopVisual.SHEET, HoopVisual.FRAMES, 1, 0)
	var y := int(src.position.y + src.size.y * 0.5)
	var first := -1
	var last := -1
	for x : int in int(src.size.x):
		if img.get_pixel(int(src.position.x) + x, y).a > 0.0: continue
		if first < 0: first = x
		last = x
	if first < 0: return 0.0
	return float(last - first + 1) * 0.5 * (body.x / src.size.x)

## Every ball, at every count, sits where the INDEPENDENT oracle says. This is the check that would
## have caught a real path bug — and the one whose earlier disagreement turned out to be the harness
## re-enabling the clock it had parked, so the tolerance is in art units and stated.
func test_balls_sit_on_their_oracle() -> void:
	behavior_section("BALLS SIT ON THEIR SPEC POSITIONS")
	var style := StatusJuggling.JUGGLE_STYLE
	# BOTH directions: a host's base direction is a coin flip, and the whole pattern mirrors with it,
	# so checking only +1 would leave half the possible boards unverified.
	for dir : float in [1.0, -1.0] as Array[float]:
		for n : int in [1, 3, 8, 50]:
			var geo := FxJuggle.geometry(n, style)
			var phase := 0.13
			_host_balls(n, style, phase, dir)
			var img := await _shoot()
			var expected := PixelProbe.ball_positions(float(n), phase, geo[&"u_span"],
					geo[&"u_arc_height"], geo[&"u_return_height"], style.ball_top_fraction,
					style.ball_gravity, dir, geo[&"u_ball_arcs"])
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
					"%d balls all render within %.1f art units of the spec (direction %+.0f)"
					% [n, BALL_TOLERANCE, dir],
					"%d missing, worst offset %.2f art units" % [missing, worst])

## THE SAME CLAIM ON A TURNING HOST, AND IT IS HERE BECAUSE THE SNAPSHOT THAT USED TO CARRY IT IS
## FLAKY. The juggling pattern does not rotate with its card (owner 2026-07-30, §4): `juggle.gdshader`
## never reads `u_shape_rot` and `FxAttachment._push_live` counter-rotates the quad, so the balls must
## sit on the WORLD-UPRIGHT oracle no matter how far the host is turned.
##
## ⚠ THIS IS THE INSTRUMENT THAT DECIDES A PERFORMANCE LEVER, and that is why it is an assertion
## rather than a picture. `fx_snapshot`'s `05f_ball_rotation` reported exactly this displacement —
## growing with the angle, along +x, up to ~6 art units at 90 degrees — and it is what got
## FX_HANDOFF §1b's quad-extent lever (worth ~25 % of the juggling layer) implemented, measured and
## then REVERTED with no mechanism ever found. Measured 2026-07-29: **that displacement appears on an
## UNCHANGED build**, once in five consecutive runs of the shot, while `att.rotation` and
## `host.global_rotation` printed correct in every run. So the snapshot's standing "rotated panels are
## not reproducible" warning is real, the revert's evidence was one flaky run, and a claim about
## rotated balls needs a check that runs every suite instead.
func test_balls_ignore_their_hosts_rotation() -> void:
	behavior_section("A TURNING HOST DOES NOT TURN THE PATTERN")
	var style := StatusJuggling.JUGGLE_STYLE
	var geo := FxJuggle.geometry(5, style)
	var phase := 0.13
	for deg : float in [30.0, 45.0, 90.0] as Array[float]:
		_host_balls(5, style, phase, 1.0, deg)
		var img := await _shoot()
		var expected := PixelProbe.ball_positions(5.0, phase, geo[&"u_span"], geo[&"u_arc_height"],
				geo[&"u_return_height"], style.ball_top_fraction, style.ball_gravity, 1.0,
				geo[&"u_ball_arcs"])
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
				"host at %.0f deg: every ball still sits within %.1f art units of the UPRIGHT spec"
				% [deg, BALL_TOLERANCE],
				"%d missing, worst offset %.2f art units" % [missing, worst])

## A ball must read as a SPHERE, not a disc (owner 2026-07-27): banded curvature plus a highlight
## sitting ON the surface. Measurable form: at least three distinct tones inside one ball (a flat
## two-tone split has two), and the brightest tone is OFF CENTRE — a centred dot is a disc's gloss.
func test_ball_reads_as_a_sphere() -> void:
	behavior_section("BALLS ARE SPHERICAL")
	var style := StatusJuggling.JUGGLE_STYLE.duplicate() as FxJuggleStyle
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
func _host_fire(body: Vector2, stacks: int, style: FxFireStyle) -> void:
	_zoom_to_fit(body.y * 0.5 + style.height + 4.0)
	var att := FxAttachment.new()
	att.configure(body, false, FxAttachment.Shape.BOX, FxAttachment.Half.WHOLE, false)
	_place(att, 1.0)
	att._seed = SEED
	att.sync([FxFire.request(&"fire", stacks, style)] as Array[FxRequest])
	_park(att, 0.0)

## The juggling pattern at a fixed phase, with no ball on fire (this suite is about the balls).
##
## `deg` turns the HOST the attachment hangs under, which is the only way to exercise the
## counter-rotation: `_push_live` reads `get_parent().global_rotation`, so a rotation put on the
## attachment itself would be overwritten on the first push. A turned host also declares
## `rotates`, exactly as a spinning card does, so the quad takes the diagonal bound it would
## really get.
func _host_balls(n: int, style: FxJuggleStyle, phase: float, dir: float = 1.0,
		deg: float = 0.0) -> void:
	var geo := FxJuggle.geometry(n, style)
	_zoom_to_fit(geo[&"u_arc_height"] + geo[&"u_ball_radius"] + 4.0)
	var turned := not is_zero_approx(deg)
	var att := FxAttachment.new()
	att.configure(CardVisual.CARD_SIZE, turned, FxAttachment.Shape.BOX, FxAttachment.Half.WHOLE,
			false)
	if turned:
		var host := Node2D.new()
		host.rotation = deg_to_rad(deg)
		_place(host, 1.0)
		att.scale = Vector2.ONE
		host.add_child(att)
	else:
		_place(att, 1.0)
	# Pin the host's randomness BEFORE sync: the quads read `_seed` and `_ball_dir` as they are BUILT,
	# unlike the clock, which is pushed afterwards (VFX.md §4.4).
	#
	# ⚠ THE SEED MATTERS AS MUCH AS THE DIRECTION, and leaving it random is what made
	# `test_ball_reads_as_a_sphere` fail intermittently. The seed drives the ball's SPIN, the spin
	# rotates the shading frame, and that frame decides where the highlight sits — so a seed that
	# happened to roll the highlight near the ball's centre failed the "highlight is off-centre"
	# assertion through no fault of the shader (measured 4.5 px against an 8 px bound, 2026-07-30).
	# A rendering test with a random input is not a test.
	att._seed = SEED
	att._ball_dir = dir
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

## Fire with every source of raggedness off: this suite measures GEOMETRY, and the noise exists
## precisely to hide geometry.
##
## ⚠ `noise_amp = 0` IS NOT "NOISE DISABLED", IT IS NOISE HELD FLAT AT 0.5 (see `fire_noise` in
## `fire.gdshader`). That matters for reading the numbers below: the shaped value is
## `cover * (((cover + aperture) * 0.5 - aperture) * gain)`, a clean monotone function of cover
## alone, which is exactly what makes the cover field measurable at all.
func _plain_fire_style() -> FxFireStyle:
	var style := StatusBurning.CARD_FIRE_STYLE.duplicate() as FxFireStyle
	style.noise_amp = 0.0
	style.dither = 0.0
	style.skew = 0.0
	return style

## Crossing comes from the ARC LADDER, not from a per-ball mirror (fixed 2026-07-28). Three
## statements, because the oracle check above cannot prove this on its own — an oracle that mirrored
## the same balls as the shader would agree with it:
##
## 1. Ball 1 sits where the LADDER puts it, and NOT at the reflection of that spot. Before the fix
##    the odd balls were mirrored, so this is exactly the assertion that flipped.
## 2. Flipping the host's coin reflects the WHOLE pattern, not one ball.
## 3. THE REGRESSION GUARD: at a count where the ball count equals the arc count, the balls must not
##    all travel the same way. That is the bug the mirror caused — the arc ladder alternates sweep
##    per arc, consecutive balls sit in consecutive arcs, and the per-ball mirror cancelled it, so
##    at 2, 4 and 6 balls every one of them ran in one direction and half the pattern sat empty
##    (owner report). Checked on the oracle, which is what the render is pinned to above.
func test_balls_alternate_directions() -> void:
	behavior_section("BALLS CROSS VIA THE ARC LADDER, AND THE HOST PICKS A SIDE")
	var style : FxJuggleStyle = StatusJuggling.JUGGLE_STYLE
	var geo := FxJuggle.geometry(2, style)
	var phase := 0.15
	var mid := Vector2(VP_SIZE, VP_SIZE) * 0.5
	var reach := int(ceilf(BALL_TOLERANCE * _zoom)) + 2
	_host_balls(2, style, phase, 1.0)
	var img := await _shoot()
	var expected := PixelProbe.ball_positions(2.0, phase, geo[&"u_span"], geo[&"u_arc_height"],
			geo[&"u_return_height"], style.ball_top_fraction, style.ball_gravity, 1.0,
			geo[&"u_ball_arcs"])
	var here := PixelProbe.nearest(img, mid + expected[1] * _zoom, reach, PixelProbe.is_warm)
	var reflection := Vector2(-expected[1].x, expected[1].y)
	var there := PixelProbe.nearest(img, mid + reflection * _zoom, reach, PixelProbe.is_warm)
	# Through typed locals: a Dictionary lookup is a Variant, and `check()` takes a bool.
	var found_here : bool = here[&"found"]
	var found_there : bool = there[&"found"]
	check(found_here and not found_there,
			"ball 1 sits where the ARC LADDER puts it, not at the mirror of it",
			"at its ladder spot: %s; at the mirrored spot: %s" % [found_here, found_there])
	_check_directions_split()
	# Reflect the whole pattern by flipping the host's coin. Compared as a MIDPOINT (position + end),
	# whose reflection about the stage centre is 2*VP_SIZE - it.
	var plus := PixelProbe.bounds(img, Rect2i(Vector2i.ZERO, img.get_size()), PixelProbe.is_warm)
	_host_balls(2, style, phase, -1.0)
	var flipped_img := await _shoot()
	var minus := PixelProbe.bounds(flipped_img, Rect2i(Vector2i.ZERO, flipped_img.get_size()),
			PixelProbe.is_warm)
	var want_sum := 2 * VP_SIZE - (plus.position.x + plus.end.x)
	check(absf(float(minus.position.x + minus.end.x) - float(want_sum)) <= 2.0 * _zoom,
			"the host's direction flips the WHOLE pattern, not just one ball",
			"dir +1 spans x %d..%d, dir -1 spans %d..%d (expected midpoint sum %d, got %d)"
			% [plus.position.x, plus.end.x, minus.position.x, minus.end.x, want_sum,
			minus.position.x + minus.end.x])

## THE REGRESSION GUARD (see the docstring above). Sample every ball's x a hair apart in the cycle at
## the counts where the ball count EQUALS the arc count — 2, 4 and 6, which is where the cancellation
## was total — and require both directions to be present. A per-ball mirror makes every one of these
## unanimous, which is what left half the pattern empty.
func _check_directions_split() -> void:
	var style : FxJuggleStyle = StatusJuggling.JUGGLE_STYLE
	for count : int in [2, 4, 6]:
		var geo := FxJuggle.geometry(count, style)
		if not is_equal_approx(geo[&"u_ball_arcs"], float(count)): continue
		var right := 0
		for i : int in count:
			var a := PixelProbe.ball_positions(float(count), 0.30, geo[&"u_span"],
					geo[&"u_arc_height"], geo[&"u_return_height"], style.ball_top_fraction,
					style.ball_gravity, 1.0, geo[&"u_ball_arcs"])
			var b := PixelProbe.ball_positions(float(count), 0.305, geo[&"u_span"],
					geo[&"u_arc_height"], geo[&"u_return_height"], style.ball_top_fraction,
					style.ball_gravity, 1.0, geo[&"u_ball_arcs"])
			if b[i].x > a[i].x: right += 1
		check(right > 0 and right < count,
				"%d balls on %d arcs travel BOTH ways (no per-ball mirror)"
				% [count, int(geo[&"u_ball_arcs"])],
				"%d of %d moving +x" % [right, count])

## Ruling 10 — the focus highlight reaches the EFFECTS, not just the card art. A card is highlighted
## by its `modulate`, which the renderer folds into COLOR before the fragment function; both FX
## shaders used to OVERWRITE COLOR, so a selected card lit up while its fire and balls did not
## (owner report 2026-07-28). The same multiply is what makes a prop's exit fade carry its flames.
##
## Stated as pixels: render each effect twice, once plain and once under the card's own highlight
## modulate, and require the highlighted one to come out BRIGHTER. Alpha is checked the same way
## (halved modulate → less coverage), which is the fade half of the same mechanism.
func test_effects_take_their_host_modulate() -> void:
	behavior_section("EFFECTS FOLLOW THEIR HOST'S MODULATE (focus highlight, fade)")
	# The literal CardVisual.focused writes; if that changes, this check should move with it.
	var highlight := Color(1.825, 1.825, 1.825)
	for kind : String in ["fire", "balls"] as Array[String]:
		var plain := await _shoot_modulated(kind, Color.WHITE)
		var lit := await _shoot_modulated(kind, highlight)
		var area := Rect2i(Vector2i.ZERO, plain.get_size())
		# MEAN, not peak: both effects already reach near-white at their hottest, and an 8-bit target
		# clamps there — so the peak barely moves under a highlight even when everything else does.
		var plain_lum := _mean_luminance(plain, area)
		var lit_lum := _mean_luminance(lit, area)
		check(plain_lum > 0.0 and lit_lum > plain_lum * 1.05,
				"%s brightens when its host is highlighted" % kind,
				"mean luminance %.3f plain vs %.3f highlighted" % [plain_lum, lit_lum])
		var faded := await _shoot_modulated(kind, Color(1.0, 1.0, 1.0, 0.35))
		var solid_px := PixelProbe.count(plain, area, PixelProbe.is_opaque)
		var faded_px := PixelProbe.count(faded, area, PixelProbe.is_opaque)
		check(faded_px < solid_px,
				"%s fades with its host's alpha (a leaving prop takes its effects with it)" % kind,
				"%d opaque pixels at alpha 1.0 vs %d at 0.35" % [solid_px, faded_px])

## One effect on a host carrying `tint`, for the modulate check. The modulate goes on a PARENT of the
## attachment, exactly as a card's does (CardVisual sets it on the root, FX hangs off Offset).
func _shoot_modulated(kind: String, tint: Color) -> Image:
	var host := Node2D.new()
	host.modulate = tint
	_place(host, 1.0)
	var att := FxAttachment.new()
	att.configure(CardVisual.CARD_SIZE, false, FxAttachment.Shape.BOX, FxAttachment.Half.WHOLE,
			false)
	host.add_child(att)
	att._seed = SEED
	if kind == "fire":
		_zoom_to_fit(CardVisual.CARD_SIZE.length() * 0.5 + StatusBurning.CARD_FIRE_STYLE.height)
		att.sync([FxFire.request(&"fire", 6, _plain_fire_style())] as Array[FxRequest])
	else:
		var style := StatusJuggling.JUGGLE_STYLE
		var geo := FxJuggle.geometry(3, style)
		_zoom_to_fit(geo[&"u_arc_height"] + geo[&"u_ball_radius"] + 4.0)
		att.sync(FxJuggle.requests(3, PackedInt32Array(), style, StatusJuggling.BALL_FIRE_STYLE))
	_park(att, 0.13)
	return await _shoot()

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
## Mean luminance over the DRAWN pixels only — how bright the effect is overall, which is what a
## highlight moves. (The peak barely moves: both effects already hit the ramp's white end, and the
## render target clamps there.) Zero when nothing was drawn.
func _mean_luminance(img: Image, area: Rect2i) -> float:
	var total := 0.0
	var lit := 0
	for y : int in range(area.position.y, area.end.y):
		for x : int in range(area.position.x, area.end.x):
			var c := img.get_pixel(x, y)
			if not PixelProbe.is_opaque(c): continue
			total += c.get_luminance()
			lit += 1
	return total / float(lit) if lit > 0 else 0.0


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

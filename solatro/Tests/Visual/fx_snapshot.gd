extends SnapshotScene
# res://Tests/Visual/fx_snapshot.gd
# ==============================================================================
# FX SNAPSHOTS — the visual half of the FX test plan.
#
# The headless suite cannot see a single pixel: --headless uses the dummy renderer, which never
# compiles a shader program, so a GLSL syntax error, an inverted sign, a flame growing DOWNWARD or
# an effect that draws nothing at all all pass it silently. This scene is the same code path run
# WINDOWED, where the GPU compiles and rasterizes for real: it lays out a grid of cases, captures
# the viewport, writes PNGs, and quits. A human (or an agent) reviews the images.
#
# Run it after ANY shader edit:
#     Godot --path solatro res://Tests/Visual/fx_snapshot.tscn
# Output: user://fx_snapshots/*.png — on Windows,
#     %APPDATA%\Godot\app_userdata\Solatro\fx_snapshots\
#
# Deliberately NOT in all_tests.tscn: it needs a window and a GPU, so it stays a separate,
# explicit run rather than something that breaks CI-style headless invocations.
#
# Determinism: the RNG is seeded and each attachment's clock is DRIVEN BY HAND to a fixed time
# rather than left to accumulate from real frame deltas, so two runs of an unchanged shader produce
# identical images and a diff means a real change.
#
# ⚠ ONE EXCEPTION, measured 2026-07-27: `02_fire_rotation` is NOT reproducible — two consecutive runs
# of identical code differ by ~11k pixels, all of them inside the ROTATED panels (the 0-degree panel
# is stable). Every other shot is byte-identical across runs. So that shot is for EYE review ("are
# the flames upright, are the pixels square"), and a pixel diff of it means nothing. If it ever needs
# to be diffable, start at what varies per run for a rotated host only — `fx_bayer(FRAGCOORD.xy)` is
# screen-space, so a sub-pixel placement difference moves every band edge.
# ==============================================================================

const OUT_DIR := "user://fx_snapshots"

## Where each shot's clock is parked. Not zero: at t = 0 every noise term is at its starting
## value and the flames look artificially uniform.
const SHOT_TIME := 3.7

## Largest art-unit-to-pixel blow-up. Cards are 38x50 art units; at 1:1 a tendril is a few pixels
## and nothing is reviewable. Each shot may use LESS than this — see _zoom_for.
const ZOOM_MAX := 5.0

func _ready() -> void:
	if not begin(OUT_DIR, Vector2i(1280, 760)): return
	await _run()
	get_tree().quit()

## Every shot, in order. Each returns the cases it wants laid out across one screen.
func _run() -> void:
	await _shot("00_tendril_count", "GEOMETRY ONLY (no noise/flicker/dither): 1 / 2 / 4 / 8 / 12 "
			+ "tendrils — count them", _tendril_count())
	await _shot("00b_ogee_profile", "the arch profile: (ogee_point, ogee_flare) pairs",
			_ogee_profile())
	await _shot("01_fire_ladder", "Burning 1 / 3 / 12 / 40 / 200 stacks", _fire_ladder())
	await _shot("02_fire_rotation", "host rotated 0 / 30 / 45 / 90 deg — flames stay vertical",
			_fire_rotation())
	await _shot("03_fire_wrap", "u_wrap 0 / 0.35 / 0.7 / 1.0 — tips vertical at every value",
			_fire_wrap())
	await _shot("04_shapes", "ring / blade / split-prop halves", _shapes())
	await _shot("05_balls", "juggling 1 / 3 / 8 / 50 balls", _balls())
	await _shot("05b_ball_path", "ONE ball traced around the cycle: phase 0 .. 0.875",
			_ball_path())
	await _shot("05c_ball_sphere", "ONE ball, big to small: banded curvature + on-surface highlight",
			_ball_sphere())
	await _shot("05d_ball_gravity", "the throw's easing: ball_gravity 1.0 / 1.6 / 2.4, evenly spaced "
			+ "in TIME — higher bunches them at the apex", _ball_gravity())
	await _shot("05e_ball_arcs", "the ARC LADDER: 2 / 4 / 6 / 8 arcs at one ball count — lanes fill "
			+ "in evenly between the carry and the throw", _ball_arcs())
	await _shot("06_ball_fire", "per-ball fire: 5 balls, 2 lit at different levels", _ball_fire())
	await _shot("07_transition", "a stack change mid-ease: fractional counts 1.0 -> 4.0",
			_transition())
	await _shot("08_focus_highlight", "host modulate 1.0 vs the card's focus highlight — the "
			+ "effects must brighten WITH their host (ruling 10)", _focus_highlight())

# ------------------------------------------------------------------ the shots

## Pure geometry: every source of raggedness turned off, so the tendrils are identical and can
## simply be COUNTED. Noise, flicker and dither all make the crown look busier than it is, and an
## off-by-one (or an off-by-two) in the comb is invisible underneath them.
func _tendril_count() -> Array[Case]:
	var out : Array[Case] = []
	var style := StatusBurning.CARD_FIRE_STYLE.duplicate() as FxStyle
	style.height_var = 0.0
	style.noise_amp = 0.0
	style.dither = 0.0
	style.sway_amp = 0.0
	style.desync = 0.0
	for n : int in [1, 2, 4, 8, 12]:
		var live : Dictionary[StringName, float] = FxFire.stacks_live(n, style)
		var req := FxRequest.make(&"fire", FxFire.FIRE_SHADER, style, live[&"u_height"])
		req.live = live
		out.append(_card_case("n = %d" % n, [req]))
	return out

## The tendril's ARCH, isolated. Two big tendrils, no noise or flicker, so the OUTLINE is the only
## thing on screen: an ogee has near-vertical sides where it springs off the body, a bulge, an
## inflection, then a sharp point — a dome or a plain triangle is a failure, not a variation.
func _ogee_profile() -> Array[Case]:
	var out : Array[Case] = []
	# Three, not five: the quad is sized to the flame HEIGHT, so more panels means a smaller zoom
	# and the outline — the only thing this shot is about — stops being legible.
	var pairs : Array[Vector2] = [Vector2(2.0, 1.0), Vector2(1.0, 0.35), Vector2(0.5, 0.35)]
	for pair : Vector2 in pairs:
		var style := StatusBurning.CARD_FIRE_STYLE.duplicate() as FxStyle
		style.ogee_point = pair.x
		style.ogee_flare = pair.y
		style.height_var = 0.0
		style.noise_amp = 0.0
		style.dither = 0.0
		style.sway_amp = 0.0
		style.desync = 0.0
		style.height = 26.0
		var live : Dictionary[StringName, float] = FxFire.stacks_live(2, style)
		var req := FxRequest.make(&"fire", FxFire.FIRE_SHADER, style, live[&"u_height"])
		req.live = live
		out.append(_card_case("point %.2f / flare %.2f" % [pair.x, pair.y], [req]))
	return out

## The headline check: one stack is ONE full-width triangle flush with the card's top edge, three
## are three, and a huge count fuses into a fiercer sheet instead of sprouting slivers.
func _fire_ladder() -> Array[Case]:
	var out : Array[Case] = []
	for stacks : int in [1, 3, 12, 40, 200]:
		out.append(_card_case("%d" % stacks,
				[FxFire.request(&"fire", stacks, StatusBurning.CARD_FIRE_STYLE)]))
	return out

## Flames are gravity-aligned: the SILHOUETTE turns inside a still quad. Every one of these must
## show upright flames on a tilted card, with square (never diagonal) pixels.
func _fire_rotation() -> Array[Case]:
	var out : Array[Case] = []
	for deg : int in [0, 30, 45, 90]:
		var case := _card_case("%d deg" % deg,
				[FxFire.request(&"fire", 5, StatusBurning.CARD_FIRE_STYLE)])
		case.rotation = deg_to_rad(float(deg))
		out.append(case)
	return out

## wrap slides the flame base from the top contour to the bottom one. At 1.0 the card is engulfed
## and EVERY tip is still vertical — that is the claim this shot exists to falsify.
func _fire_wrap() -> Array[Case]:
	var out : Array[Case] = []
	for wrap : float in [0.0, 0.35, 0.7, 1.0]:
		var style := StatusBurning.CARD_FIRE_STYLE.duplicate() as FxStyle
		style.wrap = wrap
		out.append(_card_case("wrap %.2f" % wrap, [FxFire.request(&"fire", 6, style)]))
	return out

## A ring's flames sit on the arc, a blade's on its box, and a split prop's halves each emit from
## one side only (that is how a hoop's back-arc flames stay behind the card it is threading).
func _shapes() -> Array[Case]:
	var out : Array[Case] = []
	# The REAL prop bodies, derived from the same art the kinds derive theirs from rather than
	# retyped: the hoop's art is a foreshortened OVAL (much taller than wide), so a hardcoded square
	# here would have hidden that SHAPE_RING was a circle of the body's half-WIDTH, sitting the
	# flames deep inside the arc.
	var ring_body := PropVisual.art_size_for(HoopVisual.SHEET, HoopVisual.FRAMES)
	var blade_body := PropVisual.art_size_for(KnifeVisual.SHEET)
	out.append(_case("ring", ring_body, FxAttachment.Shape.RING, FxAttachment.Half.WHOLE,
			[FxFire.request(&"fire", 4, PropVisual.PROP_FIRE_STYLE)]))
	out.append(_case("blade", blade_body, FxAttachment.Shape.BOX, FxAttachment.Half.WHOLE,
			[FxFire.request(&"fire", 4, PropVisual.PROP_FIRE_STYLE)]))
	out.append(_case("ring BACK half", ring_body, FxAttachment.Shape.RING,
			FxAttachment.Half.BACK,
			[FxFire.request(&"fire", 4, PropVisual.PROP_FIRE_STYLE)]))
	out.append(_case("ring FRONT half", ring_body, FxAttachment.Shape.RING,
			FxAttachment.Half.FRONT,
			[FxFire.request(&"fire", 4, PropVisual.PROP_FIRE_STYLE)]))
	return out

## The pattern must read as a CLOSED LOOP: a tall arc peaking above the card's top edge and a
## shallow return across the card's centre, roughly half the balls travelling each way.
func _balls() -> Array[Case]:
	var out : Array[Case] = []
	for n : int in [1, 3, 8, 50]:
		out.append(_card_case("%d balls" % n, FxJuggle.requests(n, PackedInt32Array(),
				StatusJuggling.JUGGLE_STYLE, StatusJuggling.BALL_FIRE_STYLE)))
	# The same count with the host's coin landing the other way: every ball mirrors, so this is the
	# other half of what a board actually shows.
	var flipped := _card_case("8 balls, host flipped", FxJuggle.requests(8, PackedInt32Array(),
			StatusJuggling.JUGGLE_STYLE, StatusJuggling.BALL_FIRE_STYLE))
	flipped.ball_dir = -1.0
	out.append(flipped)
	return out

## One ball, stepped around the whole cycle. Laying the loop out phase by phase is the only way to
## see what path the shader ACTUALLY draws: a single frame shows where the balls are, never
## whether the tall arc and the shallow return are the ones the spec asks for.
func _ball_path() -> Array[Case]:
	var out : Array[Case] = []
	for step : int in 8:
		var ph := float(step) / 8.0
		var case := _card_case("phase %.3f" % ph, FxJuggle.requests(1, PackedInt32Array(),
				StatusJuggling.JUGGLE_STYLE, StatusJuggling.BALL_FIRE_STYLE))
		case.phase = ph
		out.append(case)
	return out

## Is a ball a SPHERE? Only a BIG one can answer: at the shipped radius a ball is 6 art units across
## and any shading reads as "a warm blob". So the pattern is collapsed to almost nothing (the quad is
## sized by the arc height, which is what holds the zoom down) and the radius swept from huge to the
## 1-pixel floor. What to look for: bands that CURVE around the light with a bent terminator, a
## highlight sitting on the surface rather than centred, and a ball that is still legible at r = 1.
func _ball_sphere() -> Array[Case]:
	var out : Array[Case] = []
	for radius : float in [14.0, 7.0, 3.0, 1.0]:
		var style := StatusJuggling.JUGGLE_STYLE.duplicate() as FxStyle
		style.ball_radius = radius
		style.ball_radius_min = radius
		# Park the ball at the top of the throw and flatten the loop, so the quad is small and the
		# zoom can be large. Geometry only — none of it touches the shading under test.
		style.ball_span = 1.0
		style.ball_arc_height = 1.0
		style.ball_return_height = 1.0
		var case := _card_case("r = %.0f" % radius, FxJuggle.requests(1, PackedInt32Array(),
				style, StatusJuggling.BALL_FIRE_STYLE))
		case.phase = 0.3
		out.append(case)
	return out

## GRAVITY on the throw. Eight balls are spaced evenly in TIME around the loop, so where they end up
## in SPACE is a direct read of the easing: at 1.0 they are evenly spread along the arc, and as it
## rises they bunch toward the apex (slow there) and thin out at the ends (fast there). The oracle
## crosses come from the same spec, so the balls must stay on them at every value.
func _ball_gravity() -> Array[Case]:
	var out : Array[Case] = []
	for g : float in [1.0, 1.6, 2.4]:
		var style := StatusJuggling.JUGGLE_STYLE.duplicate() as FxStyle
		style.ball_gravity = g
		var case := _card_case("gravity %.1f" % g, FxJuggle.requests(8, PackedInt32Array(),
				style, StatusJuggling.BALL_FIRE_STYLE))
		case.style_gravity = g
		out.append(case)
	return out

## THE ARC LADDER. The ball count is held FIXED and the arc count forced, so the only variable is the
## ladder itself: at 2 it is the original throw-and-carry, and each step adds lanes at evenly spaced
## heights between them. Balls are spread around the whole loop, so a taller ladder spreads them over
## more of the space instead of stacking them on one arc. The oracle crosses come from the same spec,
## so they must stay on the balls at every rung.
func _ball_arcs() -> Array[Case]:
	var out : Array[Case] = []
	for arcs : int in [2, 4, 6, 8]:
		var reqs := FxJuggle.requests(12, PackedInt32Array(), StatusJuggling.JUGGLE_STYLE,
				StatusJuggling.BALL_FIRE_STYLE)
		# Forced rather than reached by ball count: the count also changes radius, span and speed,
		# and this shot is about the ladder alone.
		for req : FxRequest in reqs: req.live[&"u_ball_arcs"] = float(arcs)
		out.append(_card_case("%d arcs" % arcs, reqs))
	return out

## Ruling 10 — a highlighted card highlights its effects too. Both shaders overwrite COLOR, so the
## modulate the renderer folds into it has to be captured and multiplied back or the highlight stops
## at the card's own art. The right-hand panels are the same effects under CardVisual's own focus
## modulate; they must be visibly brighter, not identical.
func _focus_highlight() -> Array[Case]:
	var out : Array[Case] = []
	var highlight := Color(1.825, 1.825, 1.825)
	for lit : bool in [false, true]:
		var fire := _card_case("fire, %s" % ("FOCUSED" if lit else "plain"),
				[FxFire.request(&"fire", 6, StatusBurning.CARD_FIRE_STYLE)] as Array[FxRequest])
		fire.modulate = highlight if lit else Color.WHITE
		out.append(fire)
		var balls := _card_case("balls, %s" % ("FOCUSED" if lit else "plain"),
				FxJuggle.requests(5, PackedInt32Array(), StatusJuggling.JUGGLE_STYLE,
						StatusJuggling.BALL_FIRE_STYLE))
		balls.modulate = highlight if lit else Color.WHITE
		out.append(balls)
	return out

## Fire is PER BALL, at the ball's OWN level. Exactly two plumes here, welded to balls 0 and 3,
## and the all-dark case beside them is the negative that matters.
func _ball_fire() -> Array[Case]:
	var out : Array[Case] = []
	out.append(_card_case("none lit", FxJuggle.requests(5, PackedInt32Array([0, 0, 0, 0, 0]),
			StatusJuggling.JUGGLE_STYLE, StatusJuggling.BALL_FIRE_STYLE)))
	out.append(_card_case("balls 0+3 lit", FxJuggle.requests(5,
			PackedInt32Array([2, 0, 0, 30, 0]),
			StatusJuggling.JUGGLE_STYLE, StatusJuggling.BALL_FIRE_STYLE)))
	out.append(_card_case("card fire + lit balls", _stacked_case()))
	return out

## The stacking case from the design: card fire under the balls, ball fire over them.
func _stacked_case() -> Array[FxRequest]:
	var reqs : Array[FxRequest] = []
	reqs.append(FxFire.request(&"fire", 30, StatusBurning.CARD_FIRE_STYLE))
	reqs.append_array(FxJuggle.requests(5, PackedInt32Array([1, 0, 0, 1, 0]),
			StatusJuggling.JUGGLE_STYLE, StatusJuggling.BALL_FIRE_STYLE))
	return reqs

## Mid-ease frames. A fractional count is the whole mechanism behind "no visual jumps": the newest
## tendril must GROW OUT of the surface while the established ones only shuffle.
func _transition() -> Array[Case]:
	var out : Array[Case] = []
	for n : float in [1.0, 1.5, 2.5, 3.4, 4.0]:
		var live : Dictionary[StringName, float] = FxFire.stacks_live(4,
				StatusBurning.CARD_FIRE_STYLE)
		live[&"u_count"] = n
		var req := FxRequest.make(&"fire", FxFire.FIRE_SHADER, StatusBurning.CARD_FIRE_STYLE,
				live[&"u_height"])
		req.live = live
		out.append(_card_case("count %.1f" % n, [req]))
	return out

# ----------------------------------------------------------------- the harness

## One case: a host body drawn for reference with an FxAttachment on top of it. A class, not a
## Dictionary, so every field is typed — warnings are errors in this project.
class Case:
	var label : String = ""
	var body : Vector2 = Vector2.ZERO
	var shape : FxAttachment.Shape = FxAttachment.Shape.BOX
	var half : FxAttachment.Half = FxAttachment.Half.WHOLE
	var requests : Array[FxRequest] = []
	var rotation : float = 0.0
	## Phase override for the path trace, or -1 to use the shot's shared phase.
	var phase : float = -1.0
	## The style's ball_top_fraction and ball_gravity, carried so the oracle reads the same split and
	## the same throw easing the shader was handed.
	var style_top_fraction : float = 0.6
	var style_gravity : float = 1.0
	## The host's base ball direction, PINNED rather than left to its per-host coin flip — a snapshot
	## whose pattern mirrors at random cannot be diffed, and the oracle has to be told the same value.
	var ball_dir : float = 1.0
	## Host modulate, for the focus-highlight case (ruling 10): the effects must brighten with their
	## host, which they cannot do if a shader overwrites the modulate the renderer folded into COLOR.
	var modulate : Color = Color.WHITE

func _case(label: String, body: Vector2, shape: FxAttachment.Shape, half: FxAttachment.Half,
		requests: Array[FxRequest]) -> Case:
	var c := Case.new()
	# Read off the live style, never retyped: the oracle has to be told the same path parameters the
	# shader was handed, and a stale copy here would read as a shader bug.
	c.style_top_fraction = StatusJuggling.JUGGLE_STYLE.ball_top_fraction
	c.style_gravity = StatusJuggling.JUGGLE_STYLE.ball_gravity
	c.label = label
	c.body = body
	c.shape = shape
	c.half = half
	c.requests = requests
	return c

func _card_case(label: String, requests: Array[FxRequest]) -> Case:
	return _case(label, CardVisual.CARD_SIZE, FxAttachment.Shape.BOX, FxAttachment.Half.WHOLE,
			requests)

## Lay the cases out across the viewport, drive every clock to the SAME fixed time, wait for the
## frame to actually reach the screen, then capture it.
func _shot(file_name: String, caption: String, cases: Array[Case]) -> void:
	var holder := Node2D.new()
	add_child(holder)
	var size := canvas()
	var step := size.x / float(cases.size())
	var zoom := _zoom_for(cases, step)
	var probes : Array[_Probe] = []
	for i : int in cases.size():
		var case : Case = cases[i]
		var slot := Node2D.new()
		slot.position = Vector2(step * (i + 0.5), size.y * 0.55)
		slot.scale = Vector2.ONE * zoom
		slot.rotation = case.rotation
		holder.add_child(slot)
		# The host's own silhouette, so "flush with the top edge" and "behind the card" are
		# judgeable rather than guesses about empty space.
		var ghost := _Ghost.new()
		ghost.body = case.body
		ghost.ring = case.shape == FxAttachment.Shape.RING
		ghost.px = 1.0 / maxf(zoom, 0.01)
		slot.add_child(ghost)
		ghost.balls = _oracle(case)
		if not ghost.balls.is_empty():
			var probe := _Probe.new()
			probe.label = case.label
			probe.origin = slot.position
			probe.zoom = zoom
			probe.expected = ghost.balls
			probes.append(probe)
		# The modulate goes on a PARENT of the attachment, so it reaches the effects the way a card's
		# does — down the tree, not through a uniform. Added AFTER the ghost: the reference geometry
		# has to stay UNDER the effects, or the oracle crosses paint over the very balls they are
		# there to be compared against (which is exactly what happened the first time this node was
		# inserted, and it read as the balls having vanished).
		var host := Node2D.new()
		host.modulate = case.modulate
		slot.add_child(host)
		var att := FxAttachment.new()
		att.configure(case.body, true, case.shape, case.half, false)
		host.add_child(att)
		# BEFORE sync: the quads read the host's direction as they are built, unlike the clock, which
		# is pushed afterwards.
		att._ball_dir = case.ball_dir
		att.sync(case.requests)
		# Park the clock by hand: driving it from real frame deltas would make every run differ,
		# and a snapshot that changes on its own cannot be diffed.
		#
		# ⚠ ORDER MATTERS, and getting it wrong is what a whole debugging pass mistook for a shader
		# bug: `_push_live` ENDS with `set_process(not _fx.is_empty())`, so disabling the process
		# BEFORE pushing silently re-enables it, the two frames awaited below then advance `_phase`
		# and `_time` by real deltas, and every ball ends up ~0.15 of a cycle past the phase the
		# oracle (and the print below) were told about. Disable the process LAST.
		att._time = SHOT_TIME
		att._phase = case.phase if case.phase >= 0.0 else 0.13
		att._push_live(0.0)
		att.set_process(false)
		label(holder, case.label, Vector2(step * (i + 0.5), size.y * 0.9))
		for id : StringName in att._fx:
			var m := (att._fx[id].quad as MeshInstance2D).material as ShaderMaterial
			print("  [", file_name, "/", case.label, "] zoom=", zoom, " ", id,
					" u_phase=", m.get_shader_parameter("u_phase"),
					" u_count=", m.get_shader_parameter("u_count"),
					" u_arc_height=", m.get_shader_parameter("u_arc_height"),
					" u_ball_radius=", m.get_shader_parameter("u_ball_radius"),
					" u_span=", m.get_shader_parameter("u_span"),
					" u_top_fraction=", m.get_shader_parameter("u_top_fraction"),
					" u_return_height=", m.get_shader_parameter("u_return_height"),
					" u_extent=", m.get_shader_parameter("u_extent"))
	var img : Image = await capture(file_name, caption)
	for probe : _Probe in probes: _report(img, probe)
	holder.queue_free()
	await get_tree().process_frame

## The blow-up that keeps every case INSIDE its own slot.
##
## Not a constant: a ball quad is ~152 art units across (the pattern's arc height dominates the
## extent) against a card's ~90, so a fixed zoom made neighbouring slots overlap and one case's
## balls drew on top of the next one's. That is a measurement trap as much as an ugly image — it
## sent a whole debugging pass chasing a phase offset that was really the panel next door.
func _zoom_for(cases: Array[Case], step: float) -> float:
	var widest := 1.0
	for case : Case in cases:
		for req : FxRequest in case.requests:
			widest = maxf(widest, case.body.length() + (req.reach + FxAttachment.FX_MARGIN) * 2.0)
	return minf(ZOOM_MAX, step * 0.98 / widest)

# ------------------------------------------------------ measuring the capture, not eyeballing it
# The oracle CROSSES are drawn at 0.5 art units of width, which at the zooms a ball quad forces
# (~1.0) rounds to half a pixel — Godot drops those lines, so half of every cross is missing from
# the PNG and "does the ball sit on its cross" cannot be judged by eye at all. Two sessions of
# ball-position debugging were spent measuring the images by hand instead. So the harness now
# measures ITSELF: it converts each expected position into image pixels, finds the rendered ball
# nearest to it, and prints the disagreement in ART UNITS. That is the number to read.

## One case's expectation, kept until the frame has been captured.
class _Probe:
	var label : String = ""
	## Slot origin in CANVAS units, and the slot's art-unit-to-canvas blow-up.
	var origin : Vector2 = Vector2.ZERO
	var zoom : float = 1.0
	var expected : PackedVector2Array = PackedVector2Array()

## How far out, in ART UNITS, the probe is willing to look for a ball before calling it missing.
const PROBE_REACH := 24.0

## Print, per expected ball, how far the nearest RENDERED ball pixel actually is — in art units, the
## units the spec is written in. Sub-unit offsets are agreement (the search finds the nearest EDGE
## pixel of a ball, not its centre, so it reads a whole radius pessimistically).
func _report(img: Image, probe: _Probe) -> void:
	var to_img := to_image_scale(img)
	var art_to_img := probe.zoom * to_img
	var reach := int(ceilf(PROBE_REACH * art_to_img))
	for i : int in probe.expected.size():
		var want : Vector2 = (probe.origin + probe.expected[i] * probe.zoom) * to_img
		var hit := PixelProbe.nearest(img, want, reach, PixelProbe.is_warm)
		var off : Vector2 = (hit[&"offset"] as Vector2) / art_to_img
		var found := "nearest rendered ball offset by art (%.1f, %.1f)" % [off.x, off.y] \
				if hit[&"found"] else "NO BALL within %.0f art units" % PROBE_REACH
		print("  PROBE [", probe.label, "] ball ", i, " expected art ", probe.expected[i],
				" -> ", found)

## The expected ball positions for every juggling request in this case, from the SHARED spec oracle
## (PixelProbe.ball_positions — one transcription, also used by the asserting PIXELS suite, and
## deliberately NOT derived from the shader).
func _oracle(case: Case) -> PackedVector2Array:
	var out := PackedVector2Array()
	for req : FxRequest in case.requests:
		if req.phase_period <= 0.0 or req.shader != FxJuggle.JUGGLE_SHADER: continue
		out.append_array(PixelProbe.ball_positions(req.live[&"u_count"],
				case.phase if case.phase >= 0.0 else 0.13, req.live[&"u_span"],
				req.live[&"u_arc_height"], req.live[&"u_return_height"], case.style_top_fraction,
				case.style_gravity, case.ball_dir, req.live[&"u_ball_arcs"]))
	return out

## The host's silhouette, drawn as a plain outline so the effect can be judged against the shape
## it is supposed to be decorating.
class _Ghost extends Node2D:
	var body : Vector2 = Vector2.ZERO
	var ring : bool = false
	## Independent expected ball positions, drawn as crosses.
	var balls : PackedVector2Array = PackedVector2Array()
	## ART UNITS PER SCREEN PIXEL for this slot (1 / the shot's zoom). Every line width below is a
	## multiple of it, so the outline and the crosses are always ~2 px thick on screen. Fixed 0.5-unit
	## widths were sub-pixel at the zoom a ball quad forces (~1.0) and Godot DROPPED them: half of
	## every cross and both horizontal edges of the outline were simply missing from the PNG, which
	## is what made "does the ball sit on its cross" unjudgeable and sent the last pass measuring
	## pixels by hand.
	var px : float = 1.0
	func _draw() -> void:
		var col := Color(0.45, 0.5, 0.6)
		if ring:
			# An ELLIPSE inscribed in the body, not a circle of its half-width: the hoop's art is a
			# foreshortened oval, and the reference has to be the shape the shader claims to hug.
			var pts := PackedVector2Array()
			for i : int in 33:
				var a := TAU * float(i) / 32.0
				pts.append(Vector2(cos(a) * body.x * 0.5, sin(a) * body.y * 0.5))
			draw_polyline(pts, col, 2.0 * px)
		else:
			draw_rect(Rect2(-body * 0.5, body), col, false, 2.0 * px)
		# A centre line: the juggling loop's shallow return arc is specified to ride the card's
		# CENTRE, and that is impossible to eyeball without it.
		draw_line(Vector2(-body.x * 0.5, 0.0), Vector2(body.x * 0.5, 0.0),
				Color(0.35, 0.4, 0.5, 0.7), 1.5 * px)
		# The oracle: where the balls are SUPPOSED to be. A cross that does not sit on a ball is a
		# disagreement between the shader and the spec, readable at a glance and with no pixel
		# measuring — which is what this harness could not do before and cost a long debugging
		# detour.
		for b : Vector2 in balls:
			var c := Color(0.4, 1.0, 0.6)
			var arm := maxf(2.5, 4.0 * px)
			draw_line(b - Vector2(arm, 0.0), b + Vector2(arm, 0.0), c, 1.5 * px)
			draw_line(b - Vector2(0.0, arm), b + Vector2(0.0, arm), c, 1.5 * px)

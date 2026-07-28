extends Node2D
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
# rather than left to accumulate from real frame deltas, so two runs of an unchanged shader
# produce identical images and a diff means a real change.
# ==============================================================================

const OUT_DIR := "user://fx_snapshots"
const RNG_SEED := 20260727

## Where each shot's clock is parked. Not zero: at t = 0 every noise term is at its starting
## value and the flames look artificially uniform.
const SHOT_TIME := 3.7

## Largest art-unit-to-pixel blow-up. Cards are 38x50 art units; at 1:1 a tendril is a few pixels
## and nothing is reviewable. Each shot may use LESS than this — see _zoom_for.
const ZOOM_MAX := 5.0

func _ready() -> void:
	seed(RNG_SEED)
	DisplayServer.window_set_size(Vector2i(1280, 760))
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	# A dark backdrop: the effects are transparent overlays, and on the default clear colour the
	# darkest bands of the ramp are invisible.
	var bg := ColorRect.new()
	bg.color = Color(0.09, 0.09, 0.12)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
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
	await _shot("06_ball_fire", "per-ball fire: 5 balls, 2 lit at different levels", _ball_fire())
	await _shot("07_transition", "a stack change mid-ease: fractional counts 1.0 -> 4.0",
			_transition())

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
	var ring := _case("ring", Vector2(18, 18), FxAttachment.Shape.RING, FxAttachment.Half.WHOLE,
			[FxFire.request(&"fire", 4, PropVisual.PROP_FIRE_STYLE)])
	out.append(ring)
	out.append(_case("blade", Vector2(20, 8), FxAttachment.Shape.BOX, FxAttachment.Half.WHOLE,
			[FxFire.request(&"fire", 4, PropVisual.PROP_FIRE_STYLE)]))
	out.append(_case("ring BACK half", Vector2(18, 18), FxAttachment.Shape.RING,
			FxAttachment.Half.BACK,
			[FxFire.request(&"fire", 4, PropVisual.PROP_FIRE_STYLE)]))
	out.append(_case("ring FRONT half", Vector2(18, 18), FxAttachment.Shape.RING,
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
	## The style's ball_top_fraction, carried so the oracle reads the same split the shader does.
	var style_top_fraction : float = 0.6

func _case(label: String, body: Vector2, shape: FxAttachment.Shape, half: FxAttachment.Half,
		requests: Array[FxRequest]) -> Case:
	var c := Case.new()
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
	var size := get_viewport_rect().size
	var step := size.x / float(cases.size())
	var zoom := _zoom_for(cases, step)
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
		slot.add_child(ghost)
		ghost.balls = _oracle(case)
		var att := FxAttachment.new()
		att.configure(case.body, true, case.shape, case.half, false)
		slot.add_child(att)
		att.sync(case.requests)
		# Park the clock by hand: driving it from real frame deltas would make every run differ,
		# and a snapshot that changes on its own cannot be diffed.
		att.set_process(false)
		att._time = SHOT_TIME
		att._phase = case.phase if case.phase >= 0.0 else 0.13
		att._push_live(0.0)
		_label(holder, case.label, Vector2(step * (i + 0.5), size.y * 0.9))
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
	_label(holder, "%s — %s" % [file_name, caption], Vector2(size.x * 0.5, 30.0))
	# Two frames: one to apply the uniforms written above, one to be sure it has been drawn.
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := "%s/%s.png" % [OUT_DIR, file_name]
	img.save_png(path)
	print("wrote ", ProjectSettings.globalize_path(path))
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

## TEST-ONLY ORACLE. A second, independent implementation of the ball path, in GDScript, used
## ONLY to draw the expected positions into the snapshot. Duplicating the motion maths is
## forbidden in production code — that is exactly the bug fx_common.gdshaderinc exists to prevent
## — but an oracle that agrees with the shader by construction would check nothing. It is
## deliberately transcribed from the SPEC, not from the shader.
func _oracle(case: Case) -> PackedVector2Array:
	var out := PackedVector2Array()
	for req : FxRequest in case.requests:
		if req.phase_period <= 0.0 or req.shader != FxJuggle.JUGGLE_SHADER: continue
		var n : float = req.live[&"u_count"]
		var span : float = req.live[&"u_span"]
		var h_top : float = req.live[&"u_arc_height"]
		var h_bot : float = req.live[&"u_return_height"]
		var f : float = case.style_top_fraction
		var phase : float = case.phase if case.phase >= 0.0 else 0.13
		for i : int in int(ceilf(n)):
			var u := fposmod(phase + float(i) / n, 1.0)
			if u < f:
				var a := u / f
				out.append(Vector2(span * 0.5 * (1.0 - 2.0 * a), -h_top * sin(a * PI)))
			else:
				var a := (u - f) / (1.0 - f)
				out.append(Vector2(span * 0.5 * (2.0 * a - 1.0), -h_bot * sin(a * PI)))
	return out

## Centred caption. Plain Label, no theme — this scene is a diagnostic, not UI, so its strings are
## deliberately literal rather than localized.
func _label(parent: Node, text: String, at: Vector2) -> void:
	var lab := Label.new()
	lab.text = text
	lab.add_theme_color_override("font_color", Color(0.75, 0.78, 0.85))
	lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lab.size = Vector2(400, 20)
	lab.position = at - Vector2(200, 10)
	parent.add_child(lab)

## The host's silhouette, drawn as a plain outline so the effect can be judged against the shape
## it is supposed to be decorating.
class _Ghost extends Node2D:
	var body : Vector2 = Vector2.ZERO
	var ring : bool = false
	## Independent expected ball positions, drawn as crosses.
	var balls : PackedVector2Array = PackedVector2Array()
	func _draw() -> void:
		var col := Color(0.45, 0.5, 0.6)
		if ring:
			draw_arc(Vector2.ZERO, body.x * 0.5, 0.0, TAU, 32, col, 0.6, true)
		else:
			draw_rect(Rect2(-body * 0.5, body), col, false, 0.6)
		# A centre line: the juggling loop's shallow return arc is specified to ride the card's
		# CENTRE, and that is impossible to eyeball without it.
		draw_line(Vector2(-body.x * 0.5, 0.0), Vector2(body.x * 0.5, 0.0),
				Color(0.35, 0.4, 0.5, 0.7), 0.4)
		# The oracle: where the balls are SUPPOSED to be. A cross that does not sit on a ball is a
		# disagreement between the shader and the spec, readable at a glance and with no pixel
		# measuring — which is what this harness could not do before and cost a long debugging
		# detour.
		for b : Vector2 in balls:
			var c := Color(0.4, 1.0, 0.6)
			draw_line(b - Vector2(2.0, 0.0), b + Vector2(2.0, 0.0), c, 0.5)
			draw_line(b - Vector2(0.0, 2.0), b + Vector2(0.0, 2.0), c, 0.5)

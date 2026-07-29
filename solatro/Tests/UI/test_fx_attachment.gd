extends TestSuite
# res://Tests/UI/test_fx_attachment.gd
# ==============================================================================
# The shader-FX layer's GDScript contract. Shader PIXELS are not headless-testable (the dummy
# renderer never compiles a program), so everything here tests what actually breaks: the data
# that reaches the uniforms, the placement of the quads, and the ball_fire size invariant.
#
# CATEGORY MAP: the owner rulings are BEHAVIOR (no stack caps, per-ball fire levels, no visual
# jumps, a face-down card leaking nothing). The uniform names, the enum mirror across the
# GDScript/GLSL boundary, and the shared-Shader policy are IMPLEMENTATION pins.
#
# No play area and no game: every FX host builds its own attachment, which is exactly what makes
# the effects identical in the deck viewer and on the board — so the suite exercises them the same
# way, standalone, and never waits on another suite.
# ==============================================================================

func suite_name() -> String:
	return "FX ATTACHMENT"

var _host : Node2D

func _ready() -> void:
	TestLog.line("============ FX ATTACHMENT TEST PASS ============")
	_host = Node2D.new()
	add_child(_host)
	test_ball_fire_invariant()
	test_ball_fire_index_stability()
	test_ball_fire_emits_alone()
	test_no_tendril_growth_past_budget()
	test_balls_uncapped()
	test_quads_share_geometry()
	test_ball_pos_matches_the_oracle()
	test_lit_balls_are_the_ember_sources()
	test_per_ball_levels()
	test_status_declares_own_fx()
	await test_quad_construction()
	await test_rotation_cancelled()
	await test_fade_before_release()
	test_transition_derived_live()
	test_enum_mirror()
	_host.queue_free()
	finish()

# ------------------------------------------------------------------ BEHAVIOR

## The whole §5e bug surface: stacks and ball_fire drifting apart. Every path that can change the
## count has to keep them equal.
func test_ball_fire_invariant() -> void:
	behavior_section("ball_fire.size() == stacks THROUGH EVERY PATH")
	var c := CardData.new()
	c.add_status(CardModifierStatus.stacked(StatusJuggling, 3))
	var j := c.statuses[0] as StatusJuggling
	check(j.fire_levels().size() == 3, "a fresh status has one level per ball",
			str(j.fire_levels()))

	# MERGE: stacks add, so the levels must be CONCATENATED in the same operation.
	var incoming := CardModifierStatus.stacked(StatusJuggling, 2) as StatusJuggling
	incoming.ball_fire = PackedInt32Array([7, 9])
	c.add_status(incoming)
	check(j.stacks == 5, "merged stacks add", str(j.stacks))
	check(j.fire_levels().size() == 5, "merge concatenates the levels",
			str(j.fire_levels()))
	check(j.fire_levels()[3] == 7 and j.fire_levels()[4] == 9,
			"the incoming balls keep their own fire through the merge", str(j.fire_levels()))

	# DECAY: truncate from the END, never the middle.
	j.stacks = 4
	check(j.fire_levels().size() == 4, "decay truncates the levels", str(j.fire_levels()))
	check(j.fire_levels()[3] == 7, "decay removes the LAST ball, not an earlier one",
			str(j.fire_levels()))

	# TRANSFER: card_data duplicates a status bound to another card.
	var other := CardData.new()
	other.add_status(j)
	var moved := other.statuses[0] as StatusJuggling
	check(moved != j, "a bound status is duplicated on transfer")
	check(moved.fire_levels().size() == moved.stacks,
			"the invariant survives the transfer duplicate",
			"%d vs %d" % [moved.fire_levels().size(), moved.stacks])

	# LOAD of a save written before ball_fire existed: stacks restored, levels empty.
	var old := StatusJuggling.new()
	old.stacks = 6
	old.ball_fire = PackedInt32Array()
	check(old.fire_levels().size() == 6,
			"a pre-change save resizes to stacks with zeros", str(old.fire_levels()))
	check(old.fire_levels()[0] == 0, "and nothing loads already alight")

## Ball index IS ball identity — ball i renders at phase + i/n. Removing from the middle would
## re-index every later ball and make flames jump between them.
func test_ball_fire_index_stability() -> void:
	behavior_section("BALL INDEX IS BALL IDENTITY")
	var c := CardData.new()
	c.add_status(CardModifierStatus.stacked(StatusJuggling, 3))
	var j := c.statuses[0] as StatusJuggling
	j.ball_fire = PackedInt32Array([5, 0, 2])
	j.stacks = 2
	check(j.fire_levels()[0] == 5 and j.fire_levels()[1] == 0,
			"removing a ball never re-indexes the survivors", str(j.fire_levels()))

## A ball catching fire without the ball COUNT changing must still refresh the visual — only the
## stacks setter used to emit, so the plume would simply not appear.
func test_ball_fire_emits_alone() -> void:
	behavior_section("ball_fire ALONE REFRESHES THE VISUAL")
	var c := CardData.new()
	c.add_status(CardModifierStatus.stacked(StatusJuggling, 2))
	var j := c.statuses[0] as StatusJuggling
	var changed : Array[int] = [0]
	c.data_changed.connect(func() -> void: changed[0] += 1)
	j.ball_fire = PackedInt32Array([4, 0])       # stacks untouched
	check(changed[0] >= 1, "changing ball_fire alone fires data_changed", str(changed[0]))

## Owner ruling 4: no small tendril cap. Past the budget the fire gets FIERCER instead of
## sprouting more slivers — and nothing anywhere clamps the stack count itself.
func test_no_tendril_growth_past_budget() -> void:
	behavior_section("SURPLUS FIRE STACKS RAISE INTENSITY, NOT TENDRIL COUNT")
	var style := StatusBurning.CARD_FIRE_STYLE
	var few := FxFire.stacks_live(3, style)
	var many := FxFire.stacks_live(200, style)
	check(few[&"u_count"] == 3.0, "below the budget, one tendril per stack",
			str(few[&"u_count"]))
	check(many[&"u_count"] == float(FxFire.FX_MAX_TENDRILS),
			"past it the count STOPS growing", str(many[&"u_count"]))
	check(many[&"u_intensity"] > few[&"u_intensity"], "while intensity rises",
			"%f vs %f" % [many[&"u_intensity"], few[&"u_intensity"]])
	check(many[&"u_level"] > few[&"u_level"] and many[&"u_level"] <= 1.0,
			"and the colour crawls up the ramp without saturating", str(many[&"u_level"]))
	check(FxFire.merged(200, style), "a dense crown fuses into a sheet")
	check(not FxFire.merged(2, style), "a sparse one does not")

## Owner ruling 5: balls have no stack limit. The closed-form lookup has no loop over the count,
## so what scales is size and arc height, never the number of things evaluated.
func test_balls_uncapped() -> void:
	behavior_section("BALL COUNT IS UNCAPPED; BALLS SHRINK TO FIT")
	var style := StatusJuggling.JUGGLE_STYLE
	var prev_radius := 1e9
	for n : int in [1, 50, 500]:
		var geo := FxJuggle.geometry(n, style)
		check(geo[&"u_count"] == float(n), "u_count == stacks at %d, no clamp" % n,
				str(geo[&"u_count"]))
		check(geo[&"u_ball_radius"] <= prev_radius, "radius shrinks as the count rises at %d" % n,
				str(geo[&"u_ball_radius"]))
		check(geo[&"u_ball_radius"] >= style.ball_radius_min, "never below the floor at %d" % n,
				str(geo[&"u_ball_radius"]))
		prev_radius = geo[&"u_ball_radius"]
	var one := FxJuggle.geometry(1, style)
	var lots := FxJuggle.geometry(50, style)
	check(is_equal_approx(one[&"u_ball_radius"],
			maxf(style.ball_radius / sqrt(1.0), style.ball_radius_min)),
			"the shrink is area-preserving (1/sqrt n)")
	# The arc grows with the count (ruling 13) but is CEILINGED at `ball_arc_max`, because the pattern
	# may not reach far enough above the card to cover the card behind it (owner 2026-07-28) — past
	# the ceiling the balls' own 1/sqrt(n) shrink is what makes room. So the contract is now
	# "never shrinks, never exceeds the ceiling, and does grow somewhere below it".
	check(lots[&"u_arc_height"] >= one[&"u_arc_height"]
			and lots[&"u_arc_height"] <= style.ball_arc_max + 0.001,
			"the throw arc grows with the count but never past its ceiling",
			"1 ball %.1f, 50 balls %.1f, ceiling %.1f"
			% [one[&"u_arc_height"], lots[&"u_arc_height"], style.ball_arc_max])
	var tall := StatusJuggling.JUGGLE_STYLE.duplicate() as FxJuggleStyle
	tall.ball_arc_max = 1e9   # ceiling lifted: the growth underneath it must still be there
	check(FxJuggle.geometry(50, tall)[&"u_arc_height"]
			> FxJuggle.geometry(1, tall)[&"u_arc_height"],
			"and it is a real growth curve, not a constant — it is only the ceiling that flattens it")
	check(lots[&"u_ball_spin"] > one[&"u_ball_spin"], "and the balls spin faster")
	# The ARC LADDER (owner 2026-07-28): lanes appear between the throw and the carry as the count
	# rises, rather than one arc growing without limit. Always EVEN — arcs alternate direction, so an
	# odd count would leave the loop open in x — and capped, because the shader's nearest-ball lookup
	# does a fixed amount of work per arc.
	check(FxJuggle.arcs(1, style) == 2, "one ball is the plain throw-and-carry: 2 arcs",
			str(FxJuggle.arcs(1, style)))
	check(FxJuggle.arcs(50, style) > FxJuggle.arcs(1, style),
			"more balls means more arcs to travel through",
			"1 ball %d, 50 balls %d" % [FxJuggle.arcs(1, style), FxJuggle.arcs(50, style)])
	var odd_arcs : Array[int] = []
	for n : int in [1, 2, 3, 5, 8, 13, 21, 50, 200, 500]:
		var a := FxJuggle.arcs(n, style)
		if a % 2 != 0 or a < 2 or a > style.ball_arcs_max: odd_arcs.append(n)
	check(odd_arcs.is_empty(),
			"the arc count is always EVEN and inside [2, ball_arcs_max], at every ball count",
			"broken at counts %s" % str(odd_arcs))
	check(FxJuggle.period(50, style) < FxJuggle.period(1, style),
			"the pattern quickens with the count")

## The one rule that keeps stacked effects correct: the balls quad and the ball-fire quad read the
## SAME geometry, from one computation. Two copies is the bug that makes flames trail their balls.
func test_quads_share_geometry() -> void:
	behavior_section("BALLS AND BALL-FIRE SHARE ONE GEOMETRY")
	var reqs := FxJuggle.requests(4, PackedInt32Array([2, 0, 0, 0]),
			StatusJuggling.JUGGLE_STYLE, StatusJuggling.BALL_FIRE_STYLE)
	check(reqs.size() == 2, "a lit ball adds the ball-fire quad", str(reqs.size()))
	var balls := reqs[0]
	var fire := reqs[1]
	# u_count is deliberately NOT here any more: on the balls quad it is the ball count, on the fire
	# quad it is the TENDRIL count (one per ball width). The ball count agreement is asserted below.
	var shared : Array[StringName] = [&"u_span", &"u_arc_height", &"u_return_height",
			&"u_ball_radius"]
	for key : StringName in shared:
		var a : float = balls.live[key]
		var b : float = fire.live[key]
		check(a == b, "both quads agree on %s" % key, "%f vs %f" % [a, b])
	check(balls.phase_period == fire.phase_period and balls.phase_period > 0.0,
			"and on one shared phase clock", str(balls.phase_period))
	check(fire.shape == FxAttachment.Shape.BALLS,
			"the fire quad's MASK is the balls, not the card it rides on — a shape, never a mode")
	check(fire.live[&"u_ball_count"] == balls.live[&"u_count"],
			"and it is told the ball count separately, now that u_count means TENDRILS",
			"%f vs %f" % [fire.live[&"u_ball_count"], balls.live[&"u_count"]])
	check(is_equal_approx(fire.live[&"u_emit_width"], 2.0 * fire.live[&"u_ball_radius"]),
			"the comb's pitch is one ball DIAMETER, so each ball catches roughly one cell (§1.4b)",
			"%f for radius %f" % [fire.live[&"u_emit_width"], fire.live[&"u_ball_radius"]])

## THE PIN ON THE SECOND COPY OF THE PATH. `FxJuggle.ball_pos` exists only because embers are
## particles — they are spawned by GDScript into world space, so the shader cannot answer "where is
## the burning ball". Two copies of motion maths is the §4g bug class, so this holds it to the
## INDEPENDENT oracle (PixelProbe.ball_positions, transcribed from the spec, not from the include),
## which test_pixels.gd in turn holds to the rendered frame. Agreement is therefore transitive: this
## drifting from juggle.gdshader fails here, headless, in milliseconds.
func test_ball_pos_matches_the_oracle() -> void:
	behavior_section("SCRIPT-SIDE BALL POSITIONS MATCH THE ORACLE")
	var style := StatusJuggling.JUGGLE_STYLE
	var worst := 0.0
	# Every axis the path branches on: the arc ladder steps with the count, the sweep alternates per
	# arc, and the host's direction is a coin flip that mirrors the whole pattern.
	for dir : float in [1.0, -1.0] as Array[float]:
		for n : int in [1, 2, 3, 8, 50]:
			for phase : float in [0.0, 0.13, 0.5, 0.87] as Array[float]:
				var geo := FxJuggle.geometry(n, style)
				var want := PixelProbe.ball_positions(float(n), phase, geo[&"u_span"],
						geo[&"u_arc_height"], geo[&"u_return_height"], style.ball_top_fraction,
						style.ball_gravity, dir, geo[&"u_ball_arcs"])
				for i : int in want.size():
					var got := FxJuggle.ball_pos(float(i), float(n), phase, geo[&"u_span"],
							geo[&"u_arc_height"], geo[&"u_return_height"], style.ball_top_fraction,
							style.ball_gravity, dir, geo[&"u_ball_arcs"])
					worst = maxf(worst, (got - want[i]).length())
	check(worst < 0.01, "every ball position agrees with the oracle to within 0.01 art units",
			"worst disagreement %.4f" % worst)

## Which balls throw embers is the LIT set, never the ball count: an unlit ball is not on fire and
## has nothing to shed (ruling 3). Built beside the fire texture so the emitter and the shader cannot
## disagree about which balls are burning.
func test_lit_balls_are_the_ember_sources() -> void:
	behavior_section("ONLY ALIGHT BALLS THROW EMBERS")
	var reqs := FxJuggle.requests(4, PackedInt32Array([0, 3, 0, 7]),
			StatusJuggling.JUGGLE_STYLE, StatusJuggling.BALL_FIRE_STYLE)
	check(reqs.size() == 2, "a lit ball adds the ball-fire quad", str(reqs.size()))
	check(reqs[1].lit == PackedInt32Array([1, 3]),
			"the ball-fire request carries exactly the alight indices", str(reqs[1].lit))
	# A ball that is merely PRESENT contributes nothing — the negative case is the whole point.
	var dark := FxJuggle.requests(4, PackedInt32Array(), StatusJuggling.JUGGLE_STYLE,
			StatusJuggling.BALL_FIRE_STYLE)
	check(dark.size() == 1, "and no lit ball means no ball-fire quad at all", str(dark.size()))
	check(StatusJuggling.BALL_FIRE_STYLE.ember != null and PropVisual.PROP_FIRE_STYLE.ember != null,
			"ball and prop fire both carry an ember spec (owner 2026-07-29: embers on EVERY fire)")

## Owner rulings 3 and 21: fire is PER BALL, at the BALL's own level, and a burning card with
## unlit balls shows no ball fire at all. The negative case is the point.
func test_per_ball_levels() -> void:
	behavior_section("PER-BALL FIRE LEVELS")
	var style := StatusJuggling.BALL_FIRE_STYLE
	check(FxJuggle.fire_texture(3, PackedInt32Array([0, 0, 0]), style) == null,
			"no lit ball produces NO texture, so a burning card's balls stay dark")
	var tex := FxJuggle.fire_texture(3, PackedInt32Array([1, 0, 20]), style)
	check(tex != null and tex.get_width() == 3, "one texel per ball",
			str(tex.get_width() if tex else -1))
	var img := tex.get_image()
	check(is_equal_approx(img.get_pixel(1, 0).r, 0.0), "an unlit ball reads zero")
	check(img.get_pixel(2, 0).r > img.get_pixel(0, 0).r,
			"and each lit ball carries its OWN level, not a shared one")
	check(is_equal_approx(img.get_pixel(0, 0).r, FxFire.level(1, style)),
			"read against the BALL style's reference, never the card's")

	# The two are genuinely separate effects: the same ball level must not move when the card's
	# Burning does, which is structurally true because no card stacks reach this call at all.
	var card_level := FxFire.level(30, StatusBurning.CARD_FIRE_STYLE)
	check(not is_equal_approx(card_level, FxFire.level(1, style)),
			"a 30-stack card sits far up the ramp while its 1-stack balls do not")

## Statuses declare their own effects, mirroring draw_icon — the FX layer never learns which
## effects exist, so a new visual status is a new class and nothing else.
func test_status_declares_own_fx() -> void:
	behavior_section("STATUSES DECLARE THEIR OWN FX")
	check(StatusTestA.new().fx_request().is_empty(),
			"a status with no visual asks for nothing")
	check(StatusBurning.new().fx_request().size() == 1, "Burning asks for one effect")
	var j := CardModifierStatus.stacked(StatusJuggling, 2) as StatusJuggling
	check(j.fx_request().size() == 1, "unlit Juggling asks for the balls only",
			str(j.fx_request().size()))
	j.ball_fire = PackedInt32Array([3, 0])
	check(j.fx_request().size() == 2, "a lit ball adds its fire, from the same class",
			str(j.fx_request().size()))

## The quads: one per request, in request order, and OWNED by the host.
func test_quad_construction() -> void:
	behavior_section("QUAD CONSTRUCTION AND DRAW ORDER")
	var att := _attach()
	att.sync(_two_requests())
	await get_tree().process_frame
	check(att.get_child_count() == 2, "one quad per request", str(att.get_child_count()))
	check(att.get_child(0).name == "fire" and att.get_child(1).name == "balls",
			"in request order, so later requests draw on top")
	var quad := att.get_child(0) as MeshInstance2D
	check(quad != null, "quads are MeshInstance2D, never a Control that could eat mouse input")
	check(quad.mesh is QuadMesh, "on a QuadMesh")
	var mat := quad.material as ShaderMaterial
	check(mat != null and mat.shader == FxFire.FIRE_SHADER,
			"every fire quad uses the SAME Shader instance, never a duplicate")
	var extent : Vector2 = (quad.mesh as QuadMesh).size
	check(extent.x >= CardVisual.CARD_SIZE.length(),
			"the quad bounds the card's DIAGONAL, so a spinning card never clips", str(extent))
	var told : Vector2 = mat.get_shader_parameter(&"u_extent")
	check(told == extent, "and the shader is told the same extent the mesh has", str(told))
	att.queue_free()

## The quad holds still in world space while the SHAPE turns inside it, which is what keeps the
## FX pixel grid from shearing against the flame it draws.
func test_rotation_cancelled() -> void:
	behavior_section("THE QUAD HOLDS STILL; THE SILHOUETTE TURNS")
	var att := _attach()
	att.sync(_two_requests())
	_host.rotation = 0.6
	await get_tree().process_frame
	await get_tree().process_frame
	check(is_zero_approx(att.global_rotation), "the quad's global rotation is zero",
			str(att.global_rotation))
	var mat := (att.get_child(0) as MeshInstance2D).material as ShaderMaterial
	var shape_rot : float = mat.get_shader_parameter(&"u_shape_rot")
	check(is_equal_approx(shape_rot, 0.6),
			"and the host's rotation reaches the shader as u_shape_rot", str(shape_rot))
	var quad := att.get_child(0) as CanvasItem
	check(quad.z_index == 0 and att.z_index == 0,
			"no FX node touches z_index — ordering stays structural")
	_host.rotation = 0.0
	att.queue_free()

## Owner ruling 16 reaches zero too: the last stack FADES rather than vanishing mid-frame.
func test_fade_before_release() -> void:
	behavior_section("REACHING ZERO FADES BEFORE RELEASING THE QUAD")
	var att := _attach()
	att.sync(_two_requests())
	await get_tree().process_frame
	att.sync([])                                    # every status gone
	check(att.get_child_count() == 2, "the quads survive the frame the effect ended on",
			str(att.get_child_count()))
	var mat := (att.get_child(0) as MeshInstance2D).material as ShaderMaterial
	await get_tree().process_frame
	var opacity : float = mat.get_shader_parameter(&"u_opacity")
	check(opacity < 1.0, "and start fading out", str(opacity))
	att.queue_free()

# ---------------------------------------------------------- IMPLEMENTATION

## Timings are fractions of the live delay, never wall-clock, and never reached through a play
## area — a viewer card has none and must still ease exactly like a board card.
func test_transition_derived_live() -> void:
	implementation_section("TRANSITION LENGTH IS DERIVED LIVE")
	var s := SettingsManager.settings
	var want := s.base_delay * s.prop_tick_fraction * s.fx_transition_fraction
	check(is_equal_approx(FxAttachment.transition_secs(), want),
			"transition == delay * prop_tick_fraction * fx_transition_fraction",
			"%f vs %f" % [FxAttachment.transition_secs(), want])
	check(FxAttachment.pacing() > 0.0, "the pacing ratio never zeroes the clock (ruling 24)",
			str(FxAttachment.pacing()))

## GDScript and GLSL cannot share an enum, so the mapping exists twice. This is the drift guard:
## it reads the constants straight out of the shader source.
func test_enum_mirror() -> void:
	implementation_section("GDSCRIPT/GLSL ENUM MIRROR")
	var src := FileAccess.get_file_as_string("res://Shaders/fire.gdshader")
	var pairs : Dictionary[String, int] = {
		"SHAPE_BOX": FxAttachment.Shape.BOX,
		"SHAPE_RADII": FxAttachment.Shape.RADII,
		"SHAPE_SPRITE": FxAttachment.Shape.SPRITE,
		"SHAPE_BALLS": FxAttachment.Shape.BALLS,
	}
	for key : String in pairs:
		check(src.contains("const int %s = %d;" % [key, pairs[key]]),
				"fire.gdshader's %s matches the GDScript enum" % key)
	check(src.contains("const int RADII = %d;" % FxAttachment.RADII),
			"and the radius table length matches on both sides")
	# The emitter MODES are gone, not renamed: a ball is a Shape whose mask is the discs, and one
	# code path serves every host (owner 2026-07-30). Re-adding a mode is the regression to catch.
	check(not src.contains("u_mode"), "the fire shader has no emitter MODE left at all")

# ------------------------------------------------------------------- helpers

## A standalone attachment on a rotatable host — the same thing a CardVisual builds, minus the
## card, which is exactly the point: the attachment needs no board and no game.
func _attach() -> FxAttachment:
	var att := FxAttachment.new()
	att.configure(CardVisual.CARD_SIZE)
	_host.add_child(att)
	return att

## Card fire plus juggled balls: the stacking case, in draw order.
func _two_requests() -> Array[FxRequest]:
	var reqs : Array[FxRequest] = []
	reqs.append(FxFire.request(&"fire", 3, StatusBurning.CARD_FIRE_STYLE))
	reqs.append_array(FxJuggle.requests(4, PackedInt32Array(),
			StatusJuggling.JUGGLE_STYLE, StatusJuggling.BALL_FIRE_STYLE))
	return reqs

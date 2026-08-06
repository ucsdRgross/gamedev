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
	test_every_fire_knob_ramps_with_stacks()
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
	test_card_preview_chain_is_tool()
	test_the_mask_is_the_outline()
	test_fx_pixel_is_the_games_pixel()
	test_reach_covers_the_sink()
	test_glow_styles_are_the_three_clients()
	test_glow_grid_replaces_pixel()
	test_glow_layer_arrays_are_padded()
	test_glow_has_no_retired_knob()
	test_glow_shader_declares_every_knob()
	test_glow_shader_constants_mirror()
	# The DESIGN ↔ CODE seam. ⚠ Both directions, because each catches what the other cannot: a
	# documented knob with no property, and a written uniform the shader never declared.
	test_the_design_16_knob_table_is_implemented()
	test_light_shader_declares_every_spotlight_knob()
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

## OWNER 2026-07-29: *"make sure all params have scaling ratios as stacks increase"*. This is the
## check that no knob was left behind when the noise model replaced the tendrils — and it is written
## to fail when a NEW knob is added without a ratio, not just when an existing one regresses.
##
## Three separate claims, and the third is the one ruling 16 lives or dies on:
##  1. Every value `stacks_live` emits actually MOVES between a low and a high count. A knob pinned
##     flat is the failure the retired build had by design below 12 stacks.
##  2. Nothing saturates or runs away: the ramp is logarithmic, so 200 stacks is a few times 1 stack
##     rather than 200 times it, and the level never leaves the ramp.
##  3. **EVERY VALUE IS MONOTONE AND CONTINUOUS IN THE COUNT.** `FxAttachment._eased` tweens these,
##     and it can only tween what is continuous — a knob that stepped at an integer count would make
##     the whole effect pop. Walked one stack at a time, so a step shows up as a spike.
func test_every_fire_knob_ramps_with_stacks() -> void:
	behavior_section("EVERY FIRE KNOB RAMPS WITH THE STACK COUNT, CONTINUOUSLY")
	var style := StatusBurning.CARD_FIRE_STYLE
	var one := FxFire.stacks_live(1, style)
	var many := FxFire.stacks_live(200, style)
	# 1. At one stack every ratio is inert by construction (log(1) == 0), so this also pins "the base
	# style IS what a single stack looks like".
	check(is_equal_approx(one[&"u_height"], style.height)
			and is_equal_approx(one[&"u_aperture"], style.aperture),
			"at ONE stack every ratio is inert, so the style's own values are what is pushed",
			"height %f vs %f" % [one[&"u_height"], style.height])
	var moved : Array[String] = []
	var flat : Array[String] = []
	for key : StringName in one:
		if is_equal_approx(one[key], many[key]): flat.append(str(key))
		else: moved.append(str(key))
	check(flat.is_empty(), "every value stacks_live emits moves between 1 and 200 stacks",
			"pinned flat: %s — a knob with no ratio is exactly what the owner asked to be removed"
			% str(flat))
	check(moved.size() >= 8, "and there are as many scaled knobs as the model has",
			"only %d moved: %s" % [moved.size(), str(moved)])
	# 2. Logarithmic, so it crawls rather than saturating.
	check(many[&"u_intensity"] > one[&"u_intensity"] and many[&"u_intensity"] < 10.0,
			"intensity RISES but stays sane at 200 stacks", str(many[&"u_intensity"]))
	check(many[&"u_level"] > one[&"u_level"] and many[&"u_level"] <= 1.0,
			"and the colour crawls up the ramp without leaving it", str(many[&"u_level"]))
	# 3. Monotone and continuous, walked stack by stack. `u_noise_scale` normally ramps DOWNWARD
	# (coarser grain), so the direction is taken from the pair and then held to.
	var breaks : Array[String] = []
	for key : StringName in one:
		var want := signf(many[key] - one[key])
		var prev : float = one[key]
		for n : int in range(2, 201):
			var here : float = FxFire.stacks_live(n, style)[key]
			var step := here - prev
			if signf(step) != want and not is_zero_approx(step):
				breaks.append("%s reverses at %d" % [key, n])
				break
			# A jump larger than a fifth of the whole 1 -> 200 travel in ONE stack is a step, not a ramp.
			if absf(step) > absf(many[key] - one[key]) * 0.2:
				breaks.append("%s JUMPS at %d (%f in one stack)" % [key, n, step])
				break
			prev = here
	check(breaks.is_empty(),
			"every value is monotone and continuous in the count (ruling 16: a stack change eases)",
			str(breaks))

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
	# ⚠ BY ID, NEVER BY INDEX. The ORDER of these two is load-bearing — the plumes are emitted first
	# so the balls draw over them (FxJuggle.requests) — so a positional read both breaks when the
	# order changes and hides what the order is for. It did exactly that when the order flipped.
	var balls := _named(reqs, &"balls")
	var fire := _named(reqs, &"ball_fire")
	check(balls != null and fire != null, "both juggling requests are present",
			"ids: %s" % str(reqs.map(func(r: FxRequest) -> StringName: return r.id)))
	if balls == null or fire == null: return
	# The plumes must come FIRST, which is what puts every ball in front of every plume, lit or not.
	check(reqs.find(fire) < reqs.find(balls),
			"the plumes are declared BEFORE the balls, so the balls occlude them (tree order)",
			"fire at %d, balls at %d" % [reqs.find(fire), reqs.find(balls)])
	var shared : Array[StringName] = [&"u_count", &"u_span", &"u_arc_height", &"u_return_height",
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
			"and it is told the ball count in its own uniform, which is what its MASK reads",
			"%f vs %f" % [fire.live[&"u_ball_count"], balls.live[&"u_count"]])
	# ⚠ THE OLD `u_emit_width` CHECK IS GONE WITH THE COMB, not ported (2026-07-29). It asserted that
	# the comb's pitch was one ball diameter — the workaround for a comb anchored to the QUAD while
	# its balls travelled, which is what made plumes blink in and out (FX_HANDOFF §2). The cover
	# field samples the ball mask and its taps step straight down, so a plume is as wide as its ball
	# and sits on its ball by construction; there is no width to assert.
	check(not fire.live.has(&"u_emit_width"),
			"and carries no comb width — one flame per ball falls out of the mask now, "
			+ "rather than being arranged", str(fire.live.keys()))

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
	var lit_req := _named(reqs, &"ball_fire")
	check(lit_req != null and lit_req.lit == PackedInt32Array([1, 3]),
			"the ball-fire request carries exactly the alight indices",
			str(lit_req.lit) if lit_req else "no ball_fire request")
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
	var juggle := StatusJuggling.JUGGLE_STYLE
	check(FxJuggle.requests(3, PackedInt32Array([0, 0, 0]), juggle, style).size() == 1,
			"no lit ball produces NO ball-fire quad, so a burning card's balls stay dark")
	# ONE INSTANCE PER LIT BALL, carrying its own level — the levels TEXTURE this replaced had a texel
	# per ball whether it was alight or not, and the shader searched for which ball a fragment was on.
	var reqs := FxJuggle.requests(3, PackedInt32Array([1, 0, 20]), juggle, style)
	var fire : FxRequest = reqs[0]
	check(fire.id == &"ball_fire" and fire.instances.size() == 2,
			"one instance per LIT ball, and the unlit one is simply absent",
			str(fire.instances.size()))
	check(fire.instances[1].g > fire.instances[0].g,
			"each lit ball carries its OWN level, not a shared one")
	check(is_equal_approx(fire.instances[0].g, FxFire.level(1, style)),
			"read against the BALL style's reference, never the card's")
	check(int(fire.instances[0].r) == 0 and int(fire.instances[1].r) == 2,
			"and its own INDEX, which is what the vertex stage places it from",
			"%d %d" % [int(fire.instances[0].r), int(fire.instances[1].r)])
	# Owner, 2026-07-29: *"if overlapping, ball with highest stacks win"*. Instances composite in
	# buffer order, so the highest level must be LAST — this is the whole tie-break now that no
	# fragment resolves a nearest ball.
	var mixed : FxRequest = FxJuggle.requests(4, PackedInt32Array([9, 2, 30, 5]), juggle, style)[0]
	var rising := true
	for i : int in mixed.instances.size() - 1:
		if mixed.instances[i].g > mixed.instances[i + 1].g: rising = false
	check(rising and int(mixed.instances[mixed.instances.size() - 1].r) == 2,
			"instances are ordered by level so the HIGHEST draws last and wins an overlap")
	# The lattice contract: a fractional half-extent slices the quad's edge cells and draws PARTIAL
	# chunky pixels (FxRequest.instance_half).
	for req : FxRequest in reqs:
		if req.instances.is_empty(): continue
		var cell : float = req.style.pixel
		var cells := req.instance_half / cell
		check(is_equal_approx(cells.x, roundf(cells.x)) and is_equal_approx(cells.y, roundf(cells.y)),
				"%s's instance box is a WHOLE number of %s-unit cells" % [req.id, cell],
				str(req.instance_half))

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
	check(src.contains("const int POLY = %d;" % FxAttachment.POLY)
			and src.contains("const int WEDGES = %d;" % FxAttachment.WEDGES)
			and src.contains("const int WEDGE_CANDIDATES = %d;" % FxAttachment.WEDGE_CANDIDATES),
			"and the silhouette's vertex count, wedge index length and candidate count match on both sides")
	# The emitter MODES are gone, not renamed: a ball is a Shape whose mask is the discs, and one
	# code path serves every host (owner 2026-07-30). Re-adding a mode is the regression to catch.
	check(not src.contains("u_mode"), "the fire shader has no emitter MODE left at all")

## THE FX EDITOR PREVIEWS A REAL CARD, SO THE CARD'S DATA CHAIN MUST STAY `@tool` — and this is the pin,
## because the failure is invisible everywhere else. A class whose chain is not `@tool` loads in the
## EDITOR as a placeholder: the type name survives and every member does not. Measured in the owner's
## editor, 2026-07-29, before the flags were added: *"Invalid access to property or key 'data_changed' on
## a base object of type 'Resource (CardData)'"* and *"Nonexistent function 'set_texture' in base
## 'Resource'"* on a `PipSuitHoop` that was already `@tool` — a non-tool BASE is enough to do it.
##
## ⚠ IT CANNOT BE CAUGHT BY RUNNING ANYTHING. At runtime every one of these classes works perfectly,
## placeholder or not, so the suite can only check the source. Verified by A/B: reverting the flags
## reproduced all six of the owner's errors on an editor launch, and restoring them gave zero.
func test_card_preview_chain_is_tool() -> void:
	implementation_section("THE FX EDITOR'S REAL CARD NEEDS ITS WHOLE DATA CHAIN @tool")
	# The chain a previewed card actually walks: its data, the modifier base every pip extends, and the
	# four modifier families a card face draws.
	for path : String in ["res://Cards/card_data.gd", "res://Cards/card_modifier.gd",
			"res://Cards/card_modifier_type.gd", "res://Cards/Pips/pip_suit.gd",
			"res://Cards/Pips/pip_rank.gd", "res://Cards/card_modifier_stamp.gd",
			"res://Cards/card_modifier_skill.gd", "res://Cards/card_visual.gd"] as Array[String]:
		var src := FileAccess.get_file_as_string(path)
		check(src.begins_with("@tool"), "%s is @tool" % path.get_file(),
				"without it the FX editor's card is a placeholder: no signals, no set_texture, and the "
				+ "face silently stops drawing halfway through update_visual")

## THE DEFORMABLE MASK IS THE OUTLINE, EXACTLY — the claim the wedge representation was built to make
## (FX_HANDOFF §0c.1) and the one the 32-ray radial-scale table it replaced could not make at all.
##
## `Geometry2D.is_point_in_polygon` is the oracle: an engine implementation of "is this point inside
## this polygon" that knows nothing about wedges, angular slots or fire. Every sample of a grid over the
## card's own bound must get the same answer from both — at rest, and at warps past what the rig can
## reach, since a stretched corner is the vertex the old table cut off.
##
## ⚠ AND THE INVARIANT THE SHADER'S TWO-CANDIDATE TEST DEPENDS ON, checked here rather than in the hot
## path: no two silhouette vertices may share a WEDGES-th of a turn. If one ever did, a sliver of that
## slot would belong to a third wedge and read as empty — a hole in the mask, with no other symptom.
## Points within half an FX pixel of the boundary are skipped: both sides are exact there and disagree
## only on which side of `>=` a point exactly ON an edge falls, which no flame can show.
func test_the_mask_is_the_outline() -> void:
	implementation_section("THE DEFORMABLE MASK IS THE OUTLINE, VERTEX FOR VERTEX")
	var att := _attach()
	for warp : float in [0.0, 0.1, 0.25, 0.45, 0.6] as Array[float]:
		var outline := CardVisual.star_outline(CardVisual.CARD_SIZE, warp)
		att.measure_outline(outline)
		var poly : PackedVector2Array = att._poly
		var wedge : PackedFloat32Array = att._wedge
		var half : Vector2 = att._poly_half
		var inner : Vector2 = att._poly_inner
		# The vertices reach the shader untouched, or the comparison below is against a resample.
		check(poly.size() == outline.size(),
				"warp %.2f: all %d outline vertices reach the mask" % [warp, outline.size()],
				"%d of %d" % [poly.size(), outline.size()])
		# THE BOUND THE SHADER'S CANDIDATE COUNT RESTS ON: however many vertices fall inside one slot,
		# covering that slot takes one more wedge than that. Counted per slot rather than as a minimum
		# spacing, because a corner's bite deliberately puts three vertices ~1.5 degrees apart and the
		# question is never "how close" but "how many in one slot".
		var slots := PackedInt32Array()
		slots.resize(FxAttachment.WEDGES)
		for i : int in poly.size():
			var a := fposmod(atan2(poly[i].x, -poly[i].y), TAU) / TAU * float(FxAttachment.WEDGES)
			var slot := int(floorf(a)) % FxAttachment.WEDGES
			slots[slot] += 1
		var busiest := 0
		for n : int in slots: busiest = maxi(busiest, n)
		check(busiest + 1 <= FxAttachment.WEDGE_CANDIDATES,
				"warp %.2f: the busiest wedge slot holds %d vertices, so %d candidates cover it (%d tested)"
				% [warp, busiest, busiest + 1, FxAttachment.WEDGE_CANDIDATES],
				"%d vertices in one slot needs %d candidates and the shader tests %d — the slot's last "
				% [busiest, busiest + 1, FxAttachment.WEDGE_CANDIDATES]
				+ "sliver belongs to an untested wedge and reads as a HOLE in the mask")
		var wrong := 0
		var worst := Vector2.ZERO
		var reach := CardVisual.CARD_SIZE.length() * 0.5 * (1.0 + warp) + 2.0
		var stride := 0.5
		var y := -reach
		while y <= reach:
			var x := -reach
			while x <= reach:
				var p := Vector2(x, y)
				var want := Geometry2D.is_point_in_polygon(p, outline)
				if PixelProbe.mask_contains(p, poly, wedge, half, inner) != want \
						and _clear_of_edges(p, outline, 0.5):
					wrong += 1
					worst = p
				x += stride
			y += stride
		check(wrong == 0,
				"warp %.2f: the mask agrees with the polygon at every sample" % warp,
				"%d samples disagree, e.g. %s — the mask is not the shape the card is" % [wrong, worst])
	att.queue_free()

## Whether `p` is further than `margin` art units from every edge of `outline` — the band where "inside"
## is a question about a `>=` rather than about the shape.
func _clear_of_edges(p: Vector2, outline: PackedVector2Array, margin: float) -> bool:
	for i : int in outline.size():
		var a := outline[i]
		var b := outline[(i + 1) % outline.size()]
		if Geometry2D.get_closest_point_to_segment(p, a, b).distance_to(p) <= margin: return false
	return true

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

## ⚠ AN EFFECT'S PIXEL MUST BE THE GAME'S PIXEL, and this is the check that would have caught the
## owner's *"fires not pixelated"* report before it shipped.
##
## The project has ONE pixel size for all art (owner 2026-07-27, pinned on the art side by
## `test_pixels.test_one_pixel_size_for_all_art`). A card draws its pixel art one texel per UNSCALED
## unit, so a card-hosted effect's pixel is 1.0; a prop's art is drawn at `frame_px *
## ART_PIXEL_SCALE` in the prop's own local space, so a prop-hosted effect's pixel is that constant.
## `FxStyle.pixel` is in exactly those local units, and nothing was checking it.
##
## What was actually shipped: `fire_card` 0.4 and `fire_prop` 0.45 — both authored by analogy with
## each other rather than derived, leaving the fire 2.5x finer than every other pixel on a card and
## ~5.5x finer on a prop. It never read as wrong while the retired model drew broad smooth bands; the
## noise fire put a fine grain on it and it read as static immediately.
func test_fx_pixel_is_the_games_pixel() -> void:
	behavior_section("EVERY FX PIXEL IS THE GAME'S ONE PIXEL SIZE")
	# CARD-hosted: the card's own art unit.
	for style : FxStyle in [StatusBurning.CARD_FIRE_STYLE, StatusJuggling.JUGGLE_STYLE,
			StatusJuggling.BALL_FIRE_STYLE]:
		check(is_equal_approx(style.pixel, 1.0),
				"%s is card-hosted, so its pixel is one card art unit" % style.resource_path.get_file(),
				str(style.pixel))
	# PROP-hosted: a prop texel is ART_PIXEL_SCALE units in the prop's local space.
	check(is_equal_approx(PropVisual.PROP_FIRE_STYLE.pixel, PropVisual.ART_PIXEL_SCALE),
			"fire_prop is prop-hosted, so its pixel is ART_PIXEL_SCALE local units",
			"%f vs %f" % [PropVisual.PROP_FIRE_STYLE.pixel, PropVisual.ART_PIXEL_SCALE])

## ⚠ THE QUAD MUST BUDGET `height + sink`, NOT `height` — the owner's *"fire is clipped at edges"*.
## The cover ladder is measured from `p.y - sink`, so a positive sink lifts the whole reachable band
## by that much and a quad sized for `height` alone cuts the top of every flame off square. The
## shader's own `body_near` has always carried the `+ sink` margin; the request is what did not.
func test_reach_covers_the_sink() -> void:
	behavior_section("A FIRE QUAD REACHES height + sink, SO NOTHING CLIPS")
	var style := StatusBurning.CARD_FIRE_STYLE.duplicate() as FxFireStyle
	style.sink = 4.0
	var req := FxFire.request(&"fire", 8, style)
	var live := FxFire.stacks_live(8, style)
	check(req.reach >= live[&"u_height"] + style.sink - 0.001,
			"reach covers the erosion the ladder is shifted by",
			"reach %f against height %f + sink %f" % [req.reach, live[&"u_height"], style.sink])
	# NEGATIVE sink lowers the ladder instead, so it must NOT inflate the quad.
	style.sink = -4.0
	check(is_equal_approx(FxFire.request(&"fire", 8, style).reach, live[&"u_height"]),
			"a negative sink lowers the ladder and buys no extra quad",
			str(FxFire.request(&"fire", 8, style).reach))

# ------------------------------------------------------------------ SPOTLIGHT GLOW (S11)

## `Q221` / `Q257`, in the owner's words: *"should be three card circle beam, no prop"*. The count is
## the assertion — a fourth `.tres` appearing here means a prop glow was added back, which round 1
## cut, and the cut is the reason `FxAttachment`'s genericity now has exactly one client.
func test_glow_styles_are_the_three_clients() -> void:
	behavior_section("THREE GLOW STYLES: CARD, CIRCLE, BEAM — AND NO PROP")
	var paths : Array[String] = ["res://Shaders/Styles/glow_card.tres",
			"res://Shaders/Styles/glow_circle.tres", "res://Shaders/Styles/glow_beam.tres"]
	for p : String in paths:
		var style := load(p)
		check(style is FxGlowStyle, "%s loads as an FxGlowStyle" % p.get_file(),
				str(style))
	var dir := DirAccess.open("res://Shaders/Styles")
	var found : Array[String] = []
	for f : String in dir.get_files():
		if f.begins_with("glow_"): found.append(f.trim_suffix(".remap"))
	check(found.size() == 3, "exactly three glow styles ship, no prop style", str(found))

## ⚠ `grid` REPLACES the inherited `pixel`, and this pins the mechanism rather than the number.
## `Q213`=(d) asked for one knob running from the art's own grid down to SCREEN RESOLUTION, which
## `FxStyle.pixel` cannot express — its range stops at 0.25. So the glow declares its own, hides the
## inherited row from the inspector, and writes `u_pixel` from it after `super(mat)` has already
## written the other one.
##
## ⚠ THIS IS THE ONE DELIBERATE EXCEPTION TO `test_fx_pixel_is_the_games_pixel` ABOVE. Every other
## effect draws on the game's single pixel size; a glow is almost entirely gradient, and drawing it
## on the art's grid turns that gradient into contour rings. Do not "fix" the glow to 1.0.
func test_glow_grid_replaces_pixel() -> void:
	behavior_section("THE GLOW'S GRID IS THE KNOB, AND IT WINS OVER THE INHERITED PIXEL")
	var style := load("res://Shaders/Styles/glow_card.tres").duplicate() as FxGlowStyle
	style.pixel = 4.0          # the inherited one, which must NOT be what reaches the shader
	style.grid = 0.125
	var mat := ShaderMaterial.new()
	style.apply(mat)
	var pushed : float = mat.get_shader_parameter(&"u_pixel")
	check(is_equal_approx(pushed, 0.125),
			"u_pixel comes from grid, not from the inherited pixel", str(pushed))
	check(style.grid < 1.0, "and it ships FINER than the card's own art grid (Q213=d)",
			str(style.grid))
	# The inherited row is hidden from the inspector but still stored, so an existing .tres keeps
	# loading. Hiding it is what stops two rows quantizing the same coordinate.
	var usage := -1
	for prop : Dictionary in style.get_property_list():
		if prop.name != &"pixel": continue
		var raw : Variant = prop.get("usage", 0)
		if raw is int: usage = raw
	check(usage >= 0 and (usage & PROPERTY_USAGE_EDITOR) == 0,
			"the inherited pixel is hidden from the inspector but still saved", str(usage))

## Godot matches an array uniform BY DECLARED SIZE. A `PackedFloat32Array` of 2 pushed at a
## `float[4]` is not partially filled — it is rejected whole, with no error, and the shader then runs
## on whatever the uniform held before. Both arrays are therefore padded to `MAX_LAYERS` on the way
## out, and the fallbacks are chosen so an under-filled array is INERT: radius 1.0 (the layer spans
## the whole reach) and gain 0.0 (it contributes nothing).
func test_glow_layer_arrays_are_padded() -> void:
	behavior_section("LAYER ARRAYS REACH THE SHADER AT EXACTLY MAX_LAYERS")
	var style := FxGlowStyle.new()
	style.layer_radius = PackedFloat32Array([0.35, 1.0])
	style.layer_gain = PackedFloat32Array([1.0, 0.4])
	var mat := ShaderMaterial.new()
	style.apply(mat)
	var radius : PackedFloat32Array = mat.get_shader_parameter(&"u_layer_radius")
	var gain : PackedFloat32Array = mat.get_shader_parameter(&"u_layer_gain")
	check(radius.size() == FxGlowStyle.MAX_LAYERS and gain.size() == FxGlowStyle.MAX_LAYERS,
			"both arrays are padded to MAX_LAYERS", "%d / %d" % [radius.size(), gain.size()])
	check(is_equal_approx(radius[0], 0.35) and is_equal_approx(gain[1], 0.4),
			"the authored entries survive the padding", "%s / %s" % [str(radius), str(gain)])
	check(is_equal_approx(gain[2], 0.0) and is_equal_approx(gain[3], 0.0),
			"an untuned layer contributes nothing rather than full strength", str(gain))
	# LONGER than the array is truncated, not spilled.
	style.layer_gain = PackedFloat32Array([1.0, 0.4, 0.2, 0.1, 0.05])
	style.apply(mat)
	check((mat.get_shader_parameter(&"u_layer_gain") as PackedFloat32Array).size()
			== FxGlowStyle.MAX_LAYERS, "and a longer array is truncated to it",
			str(mat.get_shader_parameter(&"u_layer_gain")))

## `Q264`=(a) DELETED the fade knob rather than shipping it at zero, and `Q126`=(a) settled that the
## glow does not animate at all. Both are regressions that would arrive as a well-meaning addition,
## so the absence is what is pinned.
##
## ⚠ **AND THE COLOUR RAMP IS A `Gradient`, NOT A `PaletteRamp`** — GAP-003, answered by the owner
## 2026-08-04. Every other gradient in this project is palette-bound by construction; light is the
## granted exception (`Q134`=b, `Q135`=b, `Q214`). A well-meaning "fix" back to `PaletteRamp` would
## pass every other test in the repo, including the palette suite, so it is pinned here.
func test_glow_has_no_retired_knob() -> void:
	implementation_section("THE GLOW'S DELETED KNOBS STAY ABSENT, AND ITS RAMP IS OFF-PALETTE")
	var names : Array[StringName] = []
	for prop : Dictionary in FxGlowStyle.new().get_property_list():
		names.append(prop.name)
	check(not names.has(&"glow_fade_fraction") and not names.has(&"fade_fraction"),
			"no fade knob: the glow snaps on and off (Q264=a)")
	check(not names.has(&"breathe_amp") and not names.has(&"breathe_speed"),
			"no breathe knobs: the glow is steady (Q126=a)")
	for path : String in ["res://Shaders/Styles/glow_card.tres",
			"res://Shaders/Styles/glow_circle.tres", "res://Shaders/Styles/glow_beam.tres"]:
		var style := load(path) as FxGlowStyle
		# ⚠ The EXPORT'S OWN TYPE is what forbids a `PaletteRamp` here — `Gradient` and `PaletteRamp`
		# are unrelated classes, so the compiler rejects the comparison outright and a retyped
		# export could not load these files at all. What this asserts is the other half: the ramp is
		# actually FILLED IN, since a null one draws nothing and would look like a dead effect.
		check(style.glow_ramp is Gradient,
				"%s carries an OFF-PALETTE Gradient (GAP-003, Q134=b)" % path.get_file(),
				str(style.glow_ramp))
		check(style.ramp_texture() != null and style.ramp_texture().width == FxGlowStyle.RAMP_WIDTH,
				"and it bakes to a %d-wide texture" % FxGlowStyle.RAMP_WIDTH)

## ⚠ **A UNIFORM THE SHADER DOES NOT DECLARE IS SILENTLY DISCARDED** — `set_shader_parameter` never
## complains, and the effect simply runs on the shader's own default forever. That is exactly how
## `juggle.gdshader` came to miss `fx_intensity`: it does not declare `u_brightness`, and nothing
## said so (VFX.md §7.11). Every name `FxGlowStyle.apply()` writes is therefore checked against the
## shader's real uniform list, `u_brightness` loudest of all.
func test_glow_shader_declares_every_knob() -> void:
	implementation_section("EVERY GLOW UNIFORM THE STYLE WRITES EXISTS IN THE SHADER")
	var shader := load("res://Shaders/glow.gdshader") as Shader
	check(shader != null, "glow.gdshader loads")
	if not shader: return
	var declared : Array[String] = []
	for u : Dictionary in shader.get_shader_uniform_list():
		declared.append(str(u.get("name", "")))
	var written : Array[String] = ["u_pixel", "u_opacity", "u_dither", "u_reach", "u_sink",
			"u_layers", "u_layer_radius", "u_layer_gain", "u_inverse_square", "u_inner_alpha",
			"u_circle_radius", "u_circle_inner_alpha", "u_ramp", "u_ramp_width"]
	for name : String in written:
		check(declared.has(name), "the shader declares %s, which FxGlowStyle.apply() writes" % name)
	check(declared.has("u_brightness"),
			"and it declares u_brightness — the one juggle.gdshader forgot, so fx_intensity misses it")
	check(declared.has("u_mask_kind") and declared.has("u_space"),
			"the two host seams are declared: u_mask_kind and u_space (Q229=a)")

## The GLSL-side constants that must agree with GDScript, plus the two absences the design is
## explicit about. ⚠ `u_mask_kind` is deliberately NOT `FxAttachment.Shape`: a card at rest and a
## deformed card are one kind to a glow, and the disc is not a host kind at all. The DIFFERENT NAME
## is the guard — see the shader's header.
func test_glow_shader_constants_mirror() -> void:
	implementation_section("GLOW SHADER CONSTANTS AND ABSENCES")
	var src := FileAccess.get_file_as_string("res://Shaders/glow.gdshader")
	check(src.contains("const int POLY = %d;" % FxAttachment.POLY)
			and src.contains("const int WEDGES = %d;" % FxAttachment.WEDGES)
			and src.contains("const int WEDGE_CANDIDATES = %d;" % FxAttachment.WEDGE_CANDIDATES),
			"the silhouette constants match FxAttachment on both shaders")
	check(src.contains("const int MAX_LAYERS = %d;" % FxGlowStyle.MAX_LAYERS),
			"MAX_LAYERS matches FxGlowStyle, so the array uniforms are the same size on both sides")
	check(src.contains("blend_premul_alpha"),
			"premultiplied alpha — the one blend that is additive at a=0 and a tint above it (Q218)")
	# `TIME` is banned everywhere (it ignores the game's pacing) and this shader has no clock at all:
	# Q126=(a) steady, Q264=(a) no fade. Both would arrive as a well-meaning addition.
	# ⚠ COMMENTS ARE STRIPPED FIRST. The header discusses both bans by name, so a raw `contains`
	# fails on the documentation that exists to prevent the thing it is looking for.
	var code := ""
	for line : String in src.split("\n"):
		if not line.strip_edges().begins_with("//"): code += line + "\n"
	check(not code.contains("TIME"), "no TIME: the glow is steady (Q126=a) and never fades (Q264=a)")
	check(not code.contains("u_fade"), "and no fade uniform to push a fade into")

	# THE LIGHT LAYER's own two pins. ⚠ `MAX_LIGHTS` is not a policy — Q107 is "No cap. soft cap at
	# how many cards can fit on screen" — so it is a bound the CPU must respect, and every consumer
	# has to agree with it: Godot matches an array uniform by DECLARED SIZE and rejects a shorter
	# one whole rather than filling part of it, which draws a black frame with no error.
	var light_src := FileAccess.get_file_as_string("res://Shaders/light.gdshader")
	var light_code := ""
	for line : String in light_src.split("\n"):
		if not line.strip_edges().begins_with("//"): light_code += line + "\n"
	check(light_code.contains("const int MAX_LIGHTS = 64;"),
			"light.gdshader's MAX_LIGHTS is the bound every consumer sizes its arrays to (Q107)")
	# The beam's grain SCROLLS (Q99=a) on the game's own clock — u_time, pushed by the CPU. The
	# built-in ignores the game's pacing, which is why it is banned across the whole FX layer.
	check(light_code.contains("u_time") and not light_code.contains("TIME"),
			"and it scrolls on u_time, never the built-in TIME (Q99=a)")

## **THE DESIGN'S §16 KNOB TABLE IS A CONTRACT, AND UNTIL 2026-08-04 NOTHING CHECKED IT.**
##
## ⚠ **THIS TEST EXISTS BECAUSE THE TABLE WAS ASPIRATIONAL FOR THREE PHASES.** `DESIGN.md` §16 lists
## the light layer's *"Look"* knobs and says outright that they *"belong on a `FxSpotlightStyle`
## resource beside the other FX styles"*. That resource was never built: `light.gdshader` declared
## **13** look uniforms and `LightLayer` pushed **six**, so every other knob sat at its shader default
## with no way to reach it from GDScript, and `circle_radius` / `beam_width_at_origin` had become
## `const`s on `SpotlightDirector`. The owner found it by trying to change the radius in the tuning
## tool and watching nothing happen.
##
## ⚠ **THE POINT IS THE DIRECTION OF THE CHECK.** Reading the design more carefully would not have
## caught this and did not — the table was read. What was missing is a mechanism that fails when a
## documented knob has no implementation. **This reads the DESIGN DOCUMENT ITSELF**, so the table and
## the code cannot drift apart silently: add a row to §16 without a property and this goes red.
## Every §16 knob that is legitimately absent, and WHY. ⚠ **Delete an entry when its step lands** —
## that is what turns this test on for that knob. An entry whose step is already done is a bug in
## this list, not a licence.
const PENDING_16 : Dictionary[String, String] = {
	# --- waiting on a step that has not been built ---
	"spotlight_expand_rows": "S16 / chart D5's skip tunables (phase 3)",
	"spotlight_expand_cols": "S16 / chart D5's skip tunables (phase 3)",
	"spotlight_skip_row_if_no_reactor": "S16 / D5, and Q47 (what 'can react' means) with it",
	"spotlight_skip_col_if_no_reactor": "S16 / D5, same",
	# --- implemented, but not as a settings property ---
	"spotlight_max_lights": "shipped as LightLayer.MAX_LIGHTS — Q107 makes it a BOUND, not a policy, "
			+ "and it must equal the shader's const, which a runtime setting could not guarantee",
	"spotlight_initial_origins": "shipped as SpotlightOrigins' k0 — allocator state, not player tuning",
	"origin_rise": "shipped inside SpotlightOrigins, which owns every origin rule (Q113/Q250/Q251)",
	# --- retired by an answer ---
	"breathe_amp": "Q126=a — the glow is STEADY. Deliberately absent; ASSUMPTIONS.md records it",
	"light_colour": "British spelling in §16; the property is `light_color` on FxSpotlightStyle",
}

func test_the_design_16_knob_table_is_implemented() -> void:
	implementation_section("EVERY §16 KNOB THE DESIGN LISTS EXISTS AS A REAL PROPERTY")
	var pending := 0
	var doc := FileAccess.get_file_as_string("res://design/spotlight/DESIGN.md")
	check(not doc.is_empty(), "DESIGN.md is readable from the project")
	if doc.is_empty(): return
	# The three homes a §16 knob may legitimately have. A knob found on ANY of them is implemented;
	# one found on none is the defect this test is for.
	var style := FxSpotlightStyle.new()
	var glow := FxGlowStyle.new()
	var settings := PlayerSettings.new()
	var homes : Array[Object] = [style, glow, settings]
	# §16 runs from its own heading to the questionnaire. Rows are `| `name` | meaning | default |`.
	var start := doc.find("## 16. Proposed tunables")
	var stop := doc.find("## 17. THE QUESTIONNAIRE")
	check(start > 0 and stop > start, "DESIGN.md §16 is locatable", "%d..%d" % [start, stop])
	if start < 0 or stop <= start: return
	var missing : Array[String] = []
	var found := 0
	for raw : String in doc.substr(start, stop - start).split("
"):
		var line := raw.strip_edges()
		if not line.begins_with("| `"): continue
		var name := line.substr(3, line.find("`", 3) - 3)
		if name.is_empty(): continue
		# Knobs the design names in prose form rather than as one property.
		if name in ["layer_radius[i]", "layer_gain[i]", "light_colour / light_ramp",
				"breathe_amp` / `breathe_speed", "beam_width_at_target"]:
			continue
		# ⚠ **NOT AN ESCAPE HATCH — A LEDGER, AND THE REASON IS THE POINT.** A §16 knob may be absent
		# for exactly two honest reasons: its implementing STEP has not landed, or an ANSWER retired
		# it. Both are named here with the step or the answer, so the entry is falsifiable and gets
		# DELETED when that step lands — at which point this test starts enforcing the knob. A bare
		# skip list would just be the original defect wearing a test's clothes.
		if PENDING_16.has(name):
			pending += 1
			continue
		var here := false
		for home : Object in homes:
			if name in home: here = true
			# PlayerSettings prefixes the spotlight's own timing knobs; §16 lists them both ways.
			if ("spotlight_" + name) in home: here = true
		if here: found += 1
		else: missing.append(name)
	check(found > 15, "§16's table was actually parsed (not an empty scan)", "%d knobs read" % found)
	check(missing.is_empty(),
			"every §16 knob resolves to a property on FxSpotlightStyle, FxGlowStyle or PlayerSettings",
			"UNIMPLEMENTED and unexplained: " + ", ".join(missing)
			+ " — implement it, or add it to PENDING_16 WITH the step or answer that excuses it")
	# ⚠ Reported, not asserted: the pending count is the honest size of the "documented but not built"
	# residue, and it should FALL as phase 3 and chart E land. A silent skip list would hide that.
	TestLog.line("    [§16] %d knob(s) implemented, %d pending with a recorded reason"
			% [found, pending])

## ⚠ **AND THE OTHER DIRECTION: every uniform `FxSpotlightStyle` writes must EXIST in the shader.**
## Godot ignores a write to an undeclared uniform silently, which is how `FxStyle.apply()`'s
## `u_opacity` would have gone into `light.gdshader` unnoticed — the light layer has no opacity, and
## the style deliberately does not call `super()` for that reason.
func test_light_shader_declares_every_spotlight_knob() -> void:
	implementation_section("EVERY SPOTLIGHT UNIFORM THE STYLE WRITES EXISTS IN THE SHADER")
	var shader := load("res://Shaders/light.gdshader") as Shader
	check(shader != null, "light.gdshader loads")
	if not shader: return
	var declared : Array[String] = []
	for u : Dictionary in shader.get_shader_uniform_list():
		declared.append(str(u.get("name", "")))
	var written : Array[String] = ["u_pixel", "u_circle_intensity", "u_circle_softness",
			"u_beam_intensity", "u_beam_softness", "u_beam_noise", "u_beam_noise_scale",
			"u_beam_noise_scroll", "u_dim_color", "u_dim_noise", "u_light_color"]
	for name : String in written:
		check(name in declared, "light.gdshader declares %s" % name,
				"the style writes it and the shader has no such uniform — a silently ignored knob")
	# The layer pushes these itself rather than through the style; they are the seam's other half.
	for name : String in ["u_dim", "u_brightness", "u_lights", "u_beams",
			"u_light_count", "u_time"]:
		check(name in declared, "light.gdshader declares %s (pushed by LightLayer)" % name)

## One request out of a juggling pair, BY ID. The pair's order is meaningful (plumes before balls, so
## the balls occlude them), so nothing here may depend on a position.
func _named(reqs: Array[FxRequest], id: StringName) -> FxRequest:
	for r : FxRequest in reqs:
		if r.id == id: return r
	return null

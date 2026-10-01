extends Node2D
# FX GPU COST BENCH: what the effects cost to draw, in milliseconds per frame. NOT a test, it asserts
# nothing and prints a table. Run: Godot --path solatro res://Tests/Visual/fx_cost.tscn

# ⚠ Read the DELTAS against the empty-scene row, not the absolutes: a row's absolute cost includes
# the window and the GPU it ran on. The reference is the frame budget, 16.7 ms for 60 fps.

# ⚠ vsync is disabled and max_fps unset, or every row would report the refresh interval. The scene
# runs the GPU flat out; it quits on its own, but do not leave it up.

## Frames thrown away first: a case's first frames carry pipeline warm-up and the quads' first upload.
const WARMUP := 25
## Frames averaged per case.
const FRAMES := 90

## Burning hosts per case: 20 is the owner's stated worst realistic board (VFX.md §6.3).
const HOSTS := 20

func _ready() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	await _run()
	get_tree().quit()

# ⚠ THE PLAIN CARD-FIRE ROW IS A BOX, AND A REAL BOARD CARD IS NOT ONE: CardVisual hands its
# attachment the star rig's outline, so its mask takes the RADII branch. Measured on Intel UHD, 20
# hosts, GPU timer: box 2.13, deformed 4.11 at rest, 4.90 with the corners at ~25 %.

# ⚠ The two juggling quads are priced SEPARATELY as well as together: FxJuggle.requests() builds the
# balls quad AND the ball-fire quad, with different reaches, pixel sizes and shaders.

## Every case, in the order the table reads best: the empty floor first, then each host kind.
func _run() -> void:
	print("=== FX GPU COST (ms per frame, whole viewport, %d frames each) ===" % FRAMES)
	var floor_ms := await _measure("empty scene", func(_h: Node2D) -> void: pass)
	await _row("card fire x%d" % HOSTS, floor_ms, StatusBurning.CARD_FIRE_STYLE, _card_case)
	await _row("card fire (DEFORMED) x%d" % HOSTS, floor_ms, StatusBurning.CARD_FIRE_STYLE,
			_warped_card_case)
	await _row("prop fire (hoop) x%d" % HOSTS, floor_ms, PropVisual.PROP_FIRE_STYLE, _hoop_case)
	await _row("prop fire (knife) x%d" % HOSTS, floor_ms, PropVisual.PROP_FIRE_STYLE, _knife_case)
	await _row("juggle balls x%d" % HOSTS, floor_ms, StatusJuggling.BALL_FIRE_STYLE,
			_balls_case.bind(&"balls"))
	await _row("ball fire x%d" % HOSTS, floor_ms, StatusJuggling.BALL_FIRE_STYLE,
			_balls_case.bind(&"ball_fire"))
	await _row("juggle both x%d" % HOSTS, floor_ms, StatusJuggling.BALL_FIRE_STYLE,
			_balls_case.bind(&""))
	await _screen_rows(floor_ms)

## How many screens' worth of extra hosts the control row parks outside the viewport.
const OFF_SCREEN_MULT := 3

# ⚠ HOST COUNT IS THE WRONG AXIS: the fire shader is FRAGMENT-BOUND and Godot culls canvas items
# outside the viewport, so a frame costs the SCREEN AREA the quads cover times how deep they stack.
# These rows price a window packed edge to edge with the worst host the game can make.

# The off-screen row is the CONTROL: OFF_SCREEN_MULT times as many identical hosts parked outside
# the viewport must cost the same, or culling is not doing what every row here assumes.

# The BOX-BOUND row pins the quads to the box bound, which is what a rotation-aware bound would
# give a card that is not turned: it is that lever's ceiling, measured without building it.
func _screen_rows(floor_ms: float) -> void:
	var packed := _screen_hosts()
	print("  --- a WINDOW FULL of hosts: %d cards at board scale, edge to edge ---" % packed)
	await _screen_row("burning, FULL SCREEN", floor_ms, _burning_host, 0)
	await _screen_row("burning + juggling, FULL SCREEN", floor_ms, _worst_host, 0)
	await _screen_row("burning + juggling, +%dx OFF-SCREEN" % OFF_SCREEN_MULT, floor_ms, _worst_host,
			OFF_SCREEN_MULT)
	await _screen_row("burning + juggling, BOX-BOUND quads", floor_ms, _worst_host.bind(false), 0)
	await _cpu_row()
	await _spotlight_rows(floor_ms)
	await _tap_rows(floor_ms)
	await _noise_rows(floor_ms)

# ⚠ THE LIGHT LAYER IS THE ONLY FULL-SCREEN PASS, AND HOST COUNT IS THE WRONG AXIS FOR IT:
# `light.gdshader` shades the WHOLE viewport every frame and each fragment walks the live lights,
# so the sweep is over LIGHT COUNT and the number to read is the slope. It reports; it trims nothing.
func _spotlight_rows(floor_ms: float) -> void:
	print("  --- SPOTLIGHT (G2.3): light.gdshader, FULL SCREEN, swept over LIGHT COUNT ---")
	for n : int in [0, 1, 8, 24, 64] as Array[int]:
		var ms := await _measure("light layer, %2d light(s), FULL SCREEN" % n,
				func(h: Node2D) -> void: _light_layer_case(h, n))
		print("      -> %+.3f ms over the empty-scene floor" % (ms - floor_ms))

# A REAL `LightLayer` with the REAL shader, never a ColorRect with a hand-set material: the layer's
# own `set_lights` decides the uniforms the shader reads. The lamps sit off the top of the window,
# the way `SpotlightOrigins` places a rig lamp.

# ⚠ DRAWN AT card_scale WITH NO BOARD ZOOM: the lights are hand-placed and there is no board, so
# the game's pool is larger than this one by the board's zoom.

# ⚠ THE SHOW GATE MUST BE UP, or every light's intensity is multiplied by zero and the shader's
# cheap path prices the effect being INVISIBLE.
func _light_layer_case(holder: Node2D, count: int) -> void:
	var layer := LightLayer.new()
	holder.add_child(layer)
	layer.ensure_built()
	var vp := get_viewport().get_visible_rect().size
	layer.size = vp
	var lights : Array[LightLayer.Light] = []
	var scale : float = SettingsManager.settings.card_scale
	for i : int in count:
		var l := LightLayer.Light.new()
		l.centre = Vector2(vp.x * (float(i) + 0.5) / float(maxi(count, 1)), vp.y * 0.6)
		l.radius = layer.style.circle_radius * scale
		l.origin_width = layer.style.beam_width_at_origin * scale
		l.origin = Vector2(l.centre.x, -600.0)
		l.intensity = 1.0
		lights.append(l)
	layer.set_lights(lights, true)
	layer.set_revealed(true)

## How many times `_cpu_row` calls every host's `_push_live`, to lift it out of the frame's noise.
const PUSH_ITER := 60

# THE CPU HALF, WHICH THE GPU TIMER CANNOT SEE: `FxAttachment._push_live` is ~15
# `set_shader_parameter` calls per quad per frame. This times the real function on a full board.

# ⚠ Read it as "what one frame's pushes cost", not as a frame time: the game calls `_push_live`
# once per frame. The hosts are built with `ambient = false`, so the EMBER emitter is not in it.
# The first, untimed pass warms the branches.
func _cpu_row() -> void:
	var holder := Node2D.new()
	add_child(holder)
	_fill_screen(holder, _worst_host, 0)
	await get_tree().process_frame
	var atts : Array[FxAttachment] = []
	_collect(holder, atts)
	var quads := 0
	for att : FxAttachment in atts: quads += att._fx.size()
	for att : FxAttachment in atts: att._push_live(0.016)
	var start := Time.get_ticks_usec()
	for _i : int in PUSH_ITER:
		for att : FxAttachment in atts: att._push_live(0.016)
	var ms := float(Time.get_ticks_usec() - start) / (1000.0 * float(PUSH_ITER))
	print("  --- the CPU half: FxAttachment._push_live over a full board ---")
	print("  -> %-34s %6.3f ms per frame for %d hosts / %d quads (%.1f us per quad)"
			% ["_push_live, FULL SCREEN", ms, atts.size(), quads,
			ms * 1000.0 / maxf(float(quads), 1.0)])
	holder.queue_free()
	await get_tree().process_frame

func _collect(node: Node, out: Array[FxAttachment]) -> void:
	for child : Node in node.get_children():
		var att := child as FxAttachment
		if att: out.append(att)
		else: _collect(child, out)

# COVER TAPS: the fire shader is `mask_level` call count times cost per call, so this sweep is its
# cost curve. It must come out close to linear in the tap count with a fixed offset.

# ⚠ THE NUMBER ALONE DOES NOT PICK THE WINNER: judge 4 against 6 taps by EYE first, since the bet
# is that the banding 4 taps leave is invisible under the noise.
func _tap_rows(floor_ms: float) -> void:
	print("  --- COVER TAPS: the cost curve of the only knob that matters (full screen, burning) ---")
	for taps : int in [2, 4, 6, 8]:
		var style := StatusBurning.CARD_FIRE_STYLE.duplicate() as FxFireStyle
		style.cover_taps = taps
		await _screen_row("burning, %d cover taps" % taps, floor_ms,
				_burning_host_styled.bind(style), 0)

# THE NOISE SOURCE A/B: `fx_fbm` is three octaves of hash+lerp per lit fragment; the baked tile is
# one texture fetch. It trades ALU for memory bandwidth, which an Intel UHD shares.

# ⚠ Whichever wins, check the TILING PERIOD by eye at the shipped `noise_scale` before switching: a
# nearest-filtered scrolling tile repeats visibly if its period lands near the flame height.
func _noise_rows(floor_ms: float) -> void:
	print("  --- NOISE SOURCE: procedural fx_fbm vs the baked tile (full screen, burning) ---")
	for proc : bool in [true, false]:
		var style := StatusBurning.CARD_FIRE_STYLE.duplicate() as FxFireStyle
		style.noise_procedural = proc
		await _screen_row("burning, noise %s" % ("fx_fbm" if proc else "TEXTURE"), floor_ms,
				_burning_host_styled.bind(style), 0)

func _screen_row(label: String, floor_ms: float, build_one: Callable, off: int) -> void:
	var ms := await _measure(label, _fill_screen.bind(build_one, off))
	print("  -> %-34s %6.2f ms of a 16.67 ms frame (%.0f%%)"
			% [label, ms - floor_ms, 100.0 * (ms - floor_ms) / 16.67])

## How many board-scale cards fit in the window, touching: the densest a real screen can be.
func _screen_hosts() -> int:
	var view := get_viewport_rect().size
	var step := CardVisual.CARD_SIZE * PropVisual.AUTHORED_CARD_SCALE
	return ceili(view.x / step.x) * ceili(view.y / step.y)

# ⚠ The off-screen hosts are built identically and are still in the tree, still processing: only
# their quads leave the screen, which is exactly the claim the control row tests.

## Tile `build_one` across the viewport at board scale, then park `off` screenfuls more OUTSIDE it.
func _fill_screen(holder: Node2D, build_one: Callable, off: int) -> void:
	var view := get_viewport_rect().size
	var step := CardVisual.CARD_SIZE * PropVisual.AUTHORED_CARD_SCALE
	var cols := ceili(view.x / step.x)
	var rows := ceili(view.y / step.y)
	for r : int in rows:
		for c : int in cols:
			build_one.call(_at(holder, Vector2((float(c) + 0.5) * step.x,
					(float(r) + 0.5) * step.y)))
	for i : int in off * cols * rows:
		build_one.call(_at(holder, Vector2(view.x * 3.0 + float(i % cols) * step.x,
				view.y * 3.0 + float(i / cols) * step.y)))

## One host at a screen position, scaled the way the board scales a card.
func _at(holder: Node2D, at: Vector2) -> Node2D:
	var host := Node2D.new()
	host.position = at
	host.scale = Vector2.ONE * PropVisual.AUTHORED_CARD_SCALE
	holder.add_child(host)
	return host

## A burning card on the DEFORMED silhouette it really carries.
func _burning_host(host: Node2D) -> void:
	_burning_host_styled(host, StatusBurning.CARD_FIRE_STYLE)

# ⚠ Style LAST: the tap and noise sweeps bind the style, and chained `Callable.bind` puts the
# OUTERMOST bind's arguments first.

## The same, with the style handed in, so a sweep varies one knob at a time.
func _burning_host_styled(host: Node2D, style: FxFireStyle) -> void:
	var att := _card_attachment(host)
	att.sync([FxFire.request(&"fire", 8, style)] as Array[FxRequest])

# THE WORST HOST THE GAME CAN MAKE (owner: every card burning and juggling fire balls): three quads
# on one deformed card. `turns` false PINS the quads to the box bound, which is a ceiling and not a
# shipped configuration: a real card can spin and would clip against that bound.

# ⚠ ONE BODY, ONE PARAMETER: two priced rows must differ in EXACTLY the thing being priced.
func _worst_host(host: Node2D, turns := true) -> void:
	var att := _card_attachment(host, turns)
	var reqs : Array[FxRequest] = [FxFire.request(&"fire", 8, StatusBurning.CARD_FIRE_STYLE)]
	reqs.append_array(FxJuggle.requests(5, PackedInt32Array([4, 4, 4, 4, 4]),
			StatusJuggling.JUGGLE_STYLE, StatusJuggling.BALL_FIRE_STYLE))
	att.sync(reqs)

# THE card-host setup, in one place, so two rows can only differ by the arguments they pass.
# `warped` puts the deformed star outline on it (the RADII mask); without it the host keeps its box.
func _card_attachment(host: Node2D, turns := true, warped := true) -> FxAttachment:
	var att := FxAttachment.new()
	att.configure(CardVisual.CARD_SIZE, turns, FxAttachment.Shape.BOX, FxAttachment.Half.WHOLE,
			false)
	host.add_child(att)
	if warped: att.measure_outline(CardVisual.star_outline(CardVisual.CARD_SIZE, 0.25))
	return att

## One host kind, priced against the empty scene.
func _row(label: String, floor_ms: float, style: FxFireStyle, build: Callable) -> void:
	var ms := await _measure(label, build.bind(style))
	print("  -> %-28s %6.2f ms of a 16.67 ms frame (%.0f%%)"
			% [label, ms - floor_ms, 100.0 * (ms - floor_ms) / 16.67])

# Returns WALL-CLOCK frame time and prints the GPU timer beside it. READ THE GPU TIMER WHERE IT IS
# NON-ZERO: the wall clock also carries the CPU cost of pushing uniforms and swings ~50 % run to
# run (card fire x20 read 1.60, 2.00, 2.39 ms on runs whose GPU timer held at 2.06 / 2.13 / 2.16).

# The GPU timer works under gl_compatibility on Intel UHD (driver 31.0.101.2135: 0.003 for the
# empty scene). On a machine where it reads a flat zero the wall-clock delta is all there is.

## Run one case for FRAMES frames and return its mean millisecond cost per frame.
func _measure(label: String, build: Callable) -> float:
	var holder := Node2D.new()
	add_child(holder)
	build.call(holder)
	var rid := get_viewport().get_viewport_rid()
	for _i : int in WARMUP:
		await get_tree().process_frame
	var start := Time.get_ticks_usec()
	var gpu := 0.0
	for _i : int in FRAMES:
		await get_tree().process_frame
		gpu += RenderingServer.viewport_get_measured_render_time_gpu(rid)
	var ms := float(Time.get_ticks_usec() - start) / (1000.0 * float(FRAMES))
	print("  %-44s %8.3f ms/frame (%5.1f fps, gpu timer %.3f)"
			% [label, ms, 1000.0 / maxf(ms, 0.001), gpu / float(FRAMES)])
	holder.queue_free()
	await get_tree().process_frame
	return ms

## Burning cards at the size the board draws them (CardVisual's own scale), tiled across the window.
func _card_case(holder: Node2D, style: FxFireStyle) -> void:
	_card_fire_case(holder, style, false)

## Burning cards on the star rig's 16-point outline, corners stretched the ~25 % the animation peaks at.
func _warped_card_case(holder: Node2D, style: FxFireStyle) -> void:
	_card_fire_case(holder, style, true)

# ⚠ ONE BODY FOR BOTH ROWS: the box row and the deformed row are only comparable if they differ in
# EXACTLY the silhouette.
func _card_fire_case(holder: Node2D, style: FxFireStyle, warped: bool) -> void:
	for i : int in HOSTS:
		var att := _card_attachment(_slot(holder, i, PropVisual.AUTHORED_CARD_SCALE), true, warped)
		att.sync([FxFire.request(&"fire", 8, style)] as Array[FxRequest])

## Burning hoops: the cover field's worst case, the tallest body with a texture-tap mask.
func _hoop_case(holder: Node2D, style: FxFireStyle) -> void:
	_sprite_case(holder, style, HoopVisual.SHEET, HoopVisual.FRAMES)

func _knife_case(holder: Node2D, style: FxFireStyle) -> void:
	_sprite_case(holder, style, KnifeVisual.SHEET, 1)

## A sprite-masked prop, at the scale PropLayer draws props at.
func _sprite_case(holder: Node2D, style: FxFireStyle, sheet: Texture2D, frames: int) -> void:
	var size := PropVisual.art_size_for(sheet, frames)
	for i : int in HOSTS:
		var host := _slot(holder, i, 1.0)
		var att := FxAttachment.new()
		att.configure(size, false, FxAttachment.Shape.SPRITE, FxAttachment.Half.WHOLE, false)
		host.add_child(att)
		att.measure_sprite_silhouette(sheet, CardModifier.frame_rect(sheet, frames, 1, 0), size)
		att.sync([FxFire.request(&"fire", 8, style)] as Array[FxRequest])

# `only` picks ONE of the two quads FxJuggle declares (&"balls" or &"ball_fire"); empty keeps both,
# which is what a real juggling card draws. Pricing them apart shows which one a change moved.

# ⚠ `only` comes LAST because `_row` binds the style on top: chained `Callable.bind` puts the
# OUTERMOST bind's arguments first, so a case's own arguments trail the style.

## Juggling cards with every ball alight: the ball-fire quad is the biggest one the game builds.
func _balls_case(holder: Node2D, style: FxFireStyle, only: StringName) -> void:
	var levels := PackedInt32Array([4, 4, 4, 4, 4])
	for i : int in HOSTS:
		var att := _card_attachment(_slot(holder, i, PropVisual.AUTHORED_CARD_SCALE), true, false)
		var reqs := FxJuggle.requests(5, levels, StatusJuggling.JUGGLE_STYLE, style)
		if only != &"":
			var one : Array[FxRequest] = []
			for req : FxRequest in reqs:
				if req.id == only: one.append(req)
			reqs = one
		att.sync(reqs)

## One host's place in the grid. Hosts may OVERLAP: a real board's quads do, and that is the fill priced.
func _slot(holder: Node2D, i: int, host_scale: float) -> Node2D:
	var size := Vector2(get_viewport_rect().size)
	var cols := 5
	var host := Node2D.new()
	host.position = Vector2(size.x * (float(i % cols) + 0.5) / float(cols),
			size.y * (float(i / cols) + 0.5) / float((HOSTS + cols - 1) / cols))
	host.scale = Vector2.ONE * host_scale
	holder.add_child(host)
	return host

extends Node2D
# res://Tests/Visual/fx_cost.gd
# ==============================================================================
# FX GPU COST BENCH — what the effects actually cost to draw, in milliseconds.
#
# Built to answer FX_HANDOFF §1.4a ("the anchor costs 4 marches per fragment — measure it"), which it
# did: the per-cell anchor cost 21 ms on 20 burning hoops and was dropped for the owner's pre-ruled
# fallback. Kept because VFX.md §6.3 has wanted a fill-rate number for the whole feature and nobody
# had one — and because the run that answered §1.4a also turned up a much bigger number nobody was
# looking for. See VFX.md §7 for the BALL FIRE row.
#
#     Godot --path solatro res://Tests/Visual/fx_cost.tscn
#
# It is NOT a test and it asserts nothing: it prints a table of milliseconds per frame.
#
# ⚠ Read the DELTAS against the empty-scene row, not the absolute numbers: the absolute cost of a
# row includes the window and whatever GPU this ran on. The reference figure is the frame budget —
# 16.7 ms is all of 60 fps, and the effects are one layer of a whole game.
#
# ⚠ vsync is disabled and max_fps unset, or every row would report the refresh interval and nothing
# else. That means this scene runs the GPU flat out — it quits on its own, but do not leave it up.
# ==============================================================================

## Frames averaged per case, and how many are thrown away first. The discard matters: the first
## frames of a case include the shader's pipeline warm-up and the quads' first upload.
const WARMUP := 25
const FRAMES := 90

## How many burning hosts a case puts on screen. 20 is the owner's stated worst realistic board
## (VFX.md §6.3), and the deck viewer's 50 is the row after it.
const HOSTS := 20

func _ready() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	await _run()
	get_tree().quit()

## Every case, in the order the table reads best: the empty floor first, then each host kind.
func _run() -> void:
	print("=== FX GPU COST (ms per frame, whole viewport, %d frames each) ===" % FRAMES)
	var floor_ms := await _measure("empty scene", func(_h: Node2D) -> void: pass)
	await _row("card fire x%d" % HOSTS, floor_ms, StatusBurning.CARD_FIRE_STYLE, _card_case)
	await _row("prop fire (hoop) x%d" % HOSTS, floor_ms, PropVisual.PROP_FIRE_STYLE, _hoop_case)
	await _row("prop fire (knife) x%d" % HOSTS, floor_ms, PropVisual.PROP_FIRE_STYLE, _knife_case)
	# ⚠ The two juggling quads are priced SEPARATELY. One row for both hid which of them was
	# expensive — FxJuggle.requests() builds the balls quad AND the ball-fire quad, and they have
	# different reaches, different pixel sizes and different shaders (FX_HANDOFF §1).
	await _row("juggle balls x%d" % HOSTS, floor_ms, StatusJuggling.BALL_FIRE_STYLE,
			_balls_case.bind(&"balls"))
	await _row("ball fire x%d" % HOSTS, floor_ms, StatusJuggling.BALL_FIRE_STYLE,
			_balls_case.bind(&"ball_fire"))
	await _row("juggle both x%d" % HOSTS, floor_ms, StatusJuggling.BALL_FIRE_STYLE,
			_balls_case.bind(&""))

## One host kind, priced against the empty scene.
func _row(label: String, floor_ms: float, style: FxFireStyle, build: Callable) -> void:
	var ms := await _measure(label, build.bind(style))
	print("  -> %-28s %6.2f ms of a 16.67 ms frame (%.0f%%)"
			% [label, ms - floor_ms, 100.0 * (ms - floor_ms) / 16.67])

## Run one case for FRAMES frames and return its mean millisecond cost per frame.
##
## ⚠ WALL-CLOCK FRAME TIME, not the renderer's GPU timer. `viewport_get_measured_render_time_gpu`
## returns a flat 0.0 under the gl_compatibility backend this project ships on (measured on Intel
## UHD, 2026-07-30) — it is only implemented for the Vulkan renderers, so a bench built on it reports
## every case as free. With vsync off and nothing else in the scene, the frame interval IS the GPU's
## time to draw these quads, and the empty-scene row is what the rest is read against. Both numbers
## are printed so a future run on a Vulkan build can use the better one.
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

# ------------------------------------------------------------------ the cases

## Burning cards at the size the board draws them (CardVisual's own scale), tiled across the window.
func _card_case(holder: Node2D, style: FxFireStyle) -> void:
	for i : int in HOSTS:
		var host := _slot(holder, i, PropVisual.AUTHORED_CARD_SCALE)
		var att := FxAttachment.new()
		att.configure(CardVisual.CARD_SIZE, true, FxAttachment.Shape.BOX, FxAttachment.Half.WHOLE,
				false)
		host.add_child(att)
		att.sync([FxFire.request(&"fire", 8, style)] as Array[FxRequest])

## Burning hoops — the worst case in the game for the march, because the ring is the tallest body
## and its mask is a texture tap rather than an analytic test.
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

## Juggling cards with every ball alight — the ball-fire quad is the biggest one the game builds.
##
## `only` picks ONE of the two quads FxJuggle declares (&"balls" or &"ball_fire"); empty keeps both,
## which is what a real juggling card draws. Pricing them apart is the only way to know which one a
## change moved.
##
## ⚠ `only` comes LAST because `_row` binds the style on top of the bind below: chained
## `Callable.bind` puts the OUTERMOST bind's arguments first, so a case's own arguments trail the
## style rather than leading it.
func _balls_case(holder: Node2D, style: FxFireStyle, only: StringName) -> void:
	var levels := PackedInt32Array([4, 4, 4, 4, 4])
	for i : int in HOSTS:
		var host := _slot(holder, i, PropVisual.AUTHORED_CARD_SCALE)
		var att := FxAttachment.new()
		att.configure(CardVisual.CARD_SIZE, true, FxAttachment.Shape.BOX, FxAttachment.Half.WHOLE,
				false)
		host.add_child(att)
		var reqs := FxJuggle.requests(5, levels, StatusJuggling.JUGGLE_STYLE, style)
		if only != &"":
			var one : Array[FxRequest] = []
			for req : FxRequest in reqs:
				if req.id == only: one.append(req)
			reqs = one
		att.sync(reqs)

## One host's place in the grid. Hosts are allowed to OVERLAP — a real board's quads do, and
## overlap is exactly the fill this bench is trying to price.
func _slot(holder: Node2D, i: int, host_scale: float) -> Node2D:
	var size := Vector2(get_viewport_rect().size)
	var cols := 5
	var host := Node2D.new()
	host.position = Vector2(size.x * (float(i % cols) + 0.5) / float(cols),
			size.y * (float(i / cols) + 0.5) / float((HOSTS + cols - 1) / cols))
	host.scale = Vector2.ONE * host_scale
	holder.add_child(host)
	return host

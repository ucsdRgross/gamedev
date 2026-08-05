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
	# ⚠ THE ROW ABOVE IS A BOX, AND A REAL BOARD CARD IS NOT ONE. CardVisual hands its attachment the
	# star rig's outline, so a burning card's mask takes the RADII branch — an `atan`, a table index
	# and a lerp on EVERY cover tap, where the box is one exact ray/rect exit. Measured
	# 2026-07-29, Intel UHD, 20 hosts, GPU timer: box 2.13, deformed 4.11 at rest and 4.90 with the
	# corners at the ~25 % the shipped animation reaches. So the branch is ~1.9x the box before the
	# warp adds any fill at all. This is the row that decides whether burning cards ship, and until
	# that date nobody had ever measured it.
	await _row("card fire (DEFORMED) x%d" % HOSTS, floor_ms, StatusBurning.CARD_FIRE_STYLE,
			_warped_card_case)
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
	await _screen_rows(floor_ms)

# ================================================================================================
# THE REAL BOUND — A WINDOW FULL OF HOSTS, AND THE PROOF THAT OFF-SCREEN ONES ARE FREE
#
# ⚠ HOST COUNT IS THE WRONG AXIS, and every row above is built on it. The fire shader is
# FRAGMENT-BOUND, and Godot culls canvas items outside the viewport — so what a frame costs is the
# SCREEN AREA the quads cover times how deep they stack, not how many hosts exist. A 200-card deck
# with 60 cards on screen costs what those 60 cost. The rows below measure the only number that can
# decide whether this ships: **a window packed edge to edge with the worst host the game can make.**
#
# The off-screen row is the CONTROL. It adds OFF_SCREEN_MULT times as many identical hosts, parked
# outside the viewport, and must come back at the same cost. If it does not, culling is not doing
# what this section assumes and every conclusion drawn from it is void.
# ================================================================================================

## How many screens' worth of extra hosts the control row parks outside the viewport.
const OFF_SCREEN_MULT := 3

func _screen_rows(floor_ms: float) -> void:
	var packed := _screen_hosts()
	print("  --- a WINDOW FULL of hosts: %d cards at board scale, edge to edge ---" % packed)
	await _screen_row("burning, FULL SCREEN", floor_ms, _burning_host, 0)
	await _screen_row("burning + juggling, FULL SCREEN", floor_ms, _worst_host, 0)
	await _screen_row("burning + juggling, +%dx OFF-SCREEN" % OFF_SCREEN_MULT, floor_ms, _worst_host,
			OFF_SCREEN_MULT)
	# THE CEILING OF FX_HANDOFF §7a's LEVER B, measured without building it: `host_rotates = false`
	# gives the quad the BOX bound instead of the 62.4 diagonal, which is exactly what a live
	# rotation-aware bound would give a card that is not currently turned. If this row is close to the
	# one above, lever B is not worth its lattice risk.
	await _screen_row("burning + juggling, BOX-BOUND quads", floor_ms, _worst_host.bind(false), 0)
	await _cpu_row()
	await _spotlight_rows(floor_ms)
	await _tap_rows(floor_ms)
	await _noise_rows(floor_ms)

## **GATE G2.3 — THE SPOTLIGHT'S LIGHT LAYER, WHICH HAD NEVER BEEN PRICED.**
##
## ⚠ **IT IS THE ONLY FULL-SCREEN PASS THE GAME ADDED, AND HOST COUNT IS THE WRONG AXIS FOR IT.**
## Every other row here scales with hosts because the fire shader is fragment-bound *inside quads*;
## `light.gdshader` shades the WHOLE viewport every frame regardless of how many cards are lit, and
## its per-fragment work grows with the LIGHT COUNT (each fragment walks the live lights). So the
## sweep is over lights, not hosts, and the interesting number is the slope.
##
## ⚠ `Q254`=(a): **measure, then decide what to cut — do not pre-emptively trim.** This function
## reports; it changes nothing.
func _spotlight_rows(floor_ms: float) -> void:
	print("  --- SPOTLIGHT (G2.3): light.gdshader, FULL SCREEN, swept over LIGHT COUNT ---")
	for n : int in [0, 1, 8, 24, 64] as Array[int]:
		var ms := await _measure("light layer, %2d light(s), FULL SCREEN" % n,
				func(h: Node2D) -> void: _light_layer_case(h, n))
		print("      -> %+.3f ms over the empty-scene floor" % (ms - floor_ms))

## A REAL `LightLayer` with the REAL shader, sized to the window, holding `count` live lights spread
## across it. ⚠ Not a stand-in ColorRect with a hand-set material: the layer's own `set_lights` /
## `_push_lights` is what decides the uniforms the shader actually reads, so anything else would be
## pricing a different shader invocation than the game runs.
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
		l.radius = 16.0 * scale
		l.origin_width = 9.0 * scale
		# Off the top of the window, the way `SpotlightOrigins` places a rig lamp.
		l.origin = Vector2(l.centre.x, -600.0)
		l.intensity = 1.0
		lights.append(l)
	layer.set_lights(lights, true)
	# ⚠ The show gate must be UP or every light's intensity is multiplied by zero and the shader takes
	# its cheap path — which would price the effect being INVISIBLE.
	layer.set_revealed(true)

## THE CPU HALF, WHICH THE GPU TIMER STRUCTURALLY CANNOT SEE — and which became the binding constraint
## the moment the juggling layer stopped being fragment-bound (FX_HANDOFF §0d.6).
##
## `FxAttachment._push_live` is ~15 `set_shader_parameter` calls per quad per frame plus an eased
## Dictionary per effect, and §6a's only measurement of it was indirect: 234 OFF-SCREEN hosts costing
## ~7 ms of wall clock, i.e. ~0.03 ms per host, for hosts that skip the upload entirely. This times the
## real function on the real quads of a full board instead.
##
## ⚠ IT DELIBERATELY CALLS `_push_live` MANY TIMES PER FRAME, which is not a thing the game does — it is
## how the per-call cost gets out from under the frame's noise. So read it as "what one frame's pushes
## cost", not as a frame time. ⚠ These hosts are built with `ambient = false`, so the EMBER emitter is
## not in this number; the uniform push is.
const PUSH_ITER := 60

func _cpu_row() -> void:
	var holder := Node2D.new()
	add_child(holder)
	_fill_screen(holder, _worst_host, 0)
	await get_tree().process_frame
	var atts : Array[FxAttachment] = []
	_collect(holder, atts)
	var quads := 0
	for att : FxAttachment in atts: quads += att._fx.size()
	for att : FxAttachment in atts: att._push_live(0.016)     # warm the branches
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

# ================================================================================================
# THE TWO OPEN QUESTIONS THE NOISE FIRE LEFT (FX_HANDOFF §0), BOTH ON THE ONLY ROW THAT DECIDES
# ANYTHING — a window packed edge to edge with burning cards.
# ================================================================================================

## COVER TAPS. This shader is `mask_level` call count times cost per call and NOTHING ELSE, so this
## sweep is the shader's cost curve, drawn directly. It must come out close to linear in the tap
## count with a fixed offset (the fill, the noise and the ramp); if it does not, something else has
## become expensive and the whole cost model in FX_HANDOFF §9 needs re-deriving.
##
## ⚠ THE NUMBER ALONE DOES NOT PICK THE WINNER. Judge 4 against 6 on `00_cover_field` and
## `01_fire_ladder` by EYE first — the bet the noise model makes is that the banding 4 taps leave is
## invisible under the noise, and only a picture can settle that.
func _tap_rows(floor_ms: float) -> void:
	print("  --- COVER TAPS: the cost curve of the only knob that matters (full screen, burning) ---")
	for taps : int in [2, 4, 6, 8]:
		var style := StatusBurning.CARD_FIRE_STYLE.duplicate() as FxFireStyle
		style.cover_taps = taps
		await _screen_row("burning, %d cover taps" % taps, floor_ms,
				_burning_host_styled.bind(style), 0)

## THE NOISE SOURCE A/B (FX_HANDOFF §0e.1). `fx_fbm` is three octaves of hash+lerp — seven taps of
## ALU per lit fragment; the baked tile is one texture fetch whose octaves were paid for at import.
## It trades ALU for memory bandwidth, and on an Intel UHD with SHARED memory bandwidth which of
## those wins is genuinely not obvious, which is the whole reason both paths exist.
##
## ⚠ Whichever wins, check the TILING PERIOD by eye at the shipped `noise_scale` before switching:
## a nearest-filtered scrolling tile repeats visibly if its period lands near the flame height, and
## that is a look bug no number here will catch.
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

## How many board-scale cards fit in the window, touching — the densest a real screen can be.
func _screen_hosts() -> int:
	var view := get_viewport_rect().size
	var step := CardVisual.CARD_SIZE * PropVisual.AUTHORED_CARD_SCALE
	return ceili(view.x / step.x) * ceili(view.y / step.y)

## Tile `build_one` across the whole viewport at board scale, then park `off` screenfuls more of the
## same OUTSIDE it. ⚠ The off-screen hosts are built identically and are still in the tree, still
## processing — only their quads leave the screen. That is exactly the claim being tested.
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

## The same, with the style handed in — how the tap and noise sweeps vary one knob at a time.
## ⚠ Style LAST: `_screen_row` binds nothing on top, but the sweeps above bind the style, and chained
## `Callable.bind` puts the OUTERMOST bind's arguments first (FX_HANDOFF §11).
func _burning_host_styled(host: Node2D, style: FxFireStyle) -> void:
	var att := _card_attachment(host)
	att.sync([FxFire.request(&"fire", 8, style)] as Array[FxRequest])

## THE WORST HOST THE GAME CAN MAKE (owner 2026-07-29: *"assume every card on screen is burning and
## juggling fire balls"*): three quads on one deformed card — the crown, the balls, and the fire
## riding every one of them.
## `turns` false is the same host with its quads PINNED to the box bound — the ceiling of lever B, not a
## shipped configuration (a real card can spin, and would clip against this bound while it did).
##
## ⚠ ONE BODY, ONE PARAMETER. This was two functions identical but for that flag, in the one file whose
## whole purpose is that two priced rows differ in EXACTLY the thing being priced — a stray argument in
## one copy makes the comparison meaningless while still looking like a real regression.
func _worst_host(host: Node2D, turns := true) -> void:
	var att := _card_attachment(host, turns)
	var reqs : Array[FxRequest] = [FxFire.request(&"fire", 8, StatusBurning.CARD_FIRE_STYLE)]
	reqs.append_array(FxJuggle.requests(5, PackedInt32Array([4, 4, 4, 4, 4]),
			StatusJuggling.JUGGLE_STYLE, StatusJuggling.BALL_FIRE_STYLE))
	att.sync(reqs)

## THE card-host setup, in one place — every card row in this file builds its attachment through here, so
## two rows can only differ by the arguments they pass. `warped` is what puts the deformed star outline on
## it (the RADII mask); without it the host keeps its authored box.
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

## Run one case for FRAMES frames and return its mean millisecond cost per frame.
##
## Returns WALL-CLOCK FRAME TIME, and prints the GPU timer beside it. READ THE GPU TIMER WHERE IT IS
## NON-ZERO: it is the honest read of a shader change, where the wall clock also carries the CPU cost
## of pushing per-frame uniforms — and on this box the wall column swings ~50 % run to run (card fire
## x20 read 1.60, 2.00, 2.39 ms on three runs whose GPU timer held at 2.06 / 2.13 / 2.16).
##
## ⚠ An earlier note here said the timer returns a flat 0.0 under gl_compatibility on Intel UHD.
## IT DOES NOT — re-measured 2026-07-29 on Intel UHD Graphics, driver 31.0.101.2135, where it reports
## 0.003 for the empty scene and tracks every row. If a future machine DOES report a flat zero, the
## wall-clock delta is all there is, and it includes CPU no shader change can remove.
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
	_card_fire_case(holder, style, false)

## Burning cards on the DEFORMED silhouette a board card really carries — the star rig's 16-point
## outline, with the corners stretched the ~25 % the shipped animation peaks at.
func _warped_card_case(holder: Node2D, style: FxFireStyle) -> void:
	_card_fire_case(holder, style, true)

## ⚠ ONE BODY FOR BOTH ROWS, on the `_hoop_case`/`_knife_case` -> `_sprite_case` pattern this file
## already uses. The box row and the deformed row are only comparable if they differ in EXACTLY the
## silhouette — they were two pasted copies of the attachment setup, so a stray `configure` argument in
## one would have shown up as a fill regression that no code change caused.
func _card_fire_case(holder: Node2D, style: FxFireStyle, warped: bool) -> void:
	for i : int in HOSTS:
		var att := _card_attachment(_slot(holder, i, PropVisual.AUTHORED_CARD_SCALE), true, warped)
		att.sync([FxFire.request(&"fire", 8, style)] as Array[FxRequest])

## Burning hoops — the worst case in the game for the cover field, because the ring is the tallest
## body and its mask is a texture tap rather than an analytic test.
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
		var att := _card_attachment(_slot(holder, i, PropVisual.AUTHORED_CARD_SCALE), true, false)
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

extends Control
# THE REVEAL'S ONLY EYE (added 2026-08-05) — stands up a REAL `GameView`, drives a REAL reveal
# through the REAL `spotlight_section_changed` signal, and writes a PNG at each phase of the cycle so
# S16/S17 can be LOOKED AT rather than only measured.
#
# ⚠ **NOTHING ELSE IN THE REPO CAN SHOW THIS.** `Tools/spotlight_tool.tscn` draws its own SIMULATION
# of row separation (it has no `PlayArea` at all — GAP-007), and the suite only measures numbers. So
# before this existed, the shipped reveal had never appeared in any image.
# ⚠ No mocks: the real view, the real board, the real signal (see `.claude/memory/no-mocks-in-tools`).
#
# Run:  <godot>_console --path solatro res://Tests/Visual/reveal_shot.tscn
# It self-quits. Delete it if the reveal is ever folded into `fx_snapshot.gd`'s panel set.
#
# ⚠ It exists because the tuning tool draws its OWN simulation of row separation, not `PlayArea`'s —
# so nothing that had ever been rendered showed the shipped code. Project rule 4: green tests are not
# evidence about pixels.
#
# Output: user://reveal_shots/*.png

const OUT_DIR := "user://reveal_shots"
const GAME_VIEW_SCENE := preload("res://Levels/game_view.tscn")
## The player's real run, and where this harness parks it. See `_ready`.
const REAL_SAVE := "user://run_save/run.tres"
const SAVE_BAK := "user://run_save/run.tres.revealbak"

## The owner's own separation mode, put back before quitting — see `_ready`.
var _prev_mode : int = 0

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	# ⚠ **RESTORE THE OWNER'S SEPARATION MODE ON THE WAY OUT — `SettingsManager.settings` SAVES TO
	# DISK ON EVERY CHANGE.** The first version of this harness left `JUMP_ADJUSTED` behind, and the
	# next run silently opened 65 px instead of 90 because it inherited it. A harness that changes the
	# thing it is measuring is worse than no harness.
	_prev_mode = SettingsManager.settings.spotlight_separation_mode
	# ⚠⚠ **PARK THE REAL RUN SAVE FIRST — `RunManager.new_run()` PERSISTS, AND THIS HARNESS DID NOT
	# DO THIS AT FIRST AND OVERWROTE THE OWNER'S `run_save/run.tres`.** Every suite that touches a run
	# goes through `SolatroTest.backup_real_save()` / `restore_real_save()` for exactly this reason;
	# a bare harness is outside that machinery and has to do it by hand. It also explains a confusing
	# symptom: once the real save had been replaced by a half-played harness run, later runs dealt
	# against THAT and reported `row cards = 0`, which looked like a board-build bug and was not.
	if FileAccess.file_exists(REAL_SAVE) and not FileAccess.file_exists(SAVE_BAK):
		DirAccess.copy_absolute(REAL_SAVE, SAVE_BAK)
	# ⚠ **CLEAR IT AFTER PARKING IT, OR THE VIEW RESUMES INSTEAD OF DEALING.** A save left by an
	# earlier run of THIS harness made `GameView` come back to a played-out board, and the symptom was
	# `row cards = 0` — which reads as a board-build bug and is really a stale save.
	if FileAccess.file_exists(REAL_SAVE): DirAccess.remove_absolute(REAL_SAVE)
	var run := RunManager.new_run(TestDecks.seeded_deck(), TestDecks.standard_rules())
	Main.save_info = run
	run.pending_goal = 1
	run.pending_node_id = 2
	var view : GameView = GAME_VIEW_SCENE.instantiate()
	add_child(view)
	# ⚠ **THIS HARNESS IS A FULL-RECT `Control`, AND THAT IS LOAD-BEARING.** A `Control` child of a
	# `Node2D` gets NO layout: `GameView` sat at size (0,0), `SceneRoot` inherited it, and `LightLayer`
	# — a full-rect `ColorRect` — was zero-sized and rasterized NOTHING. Board and HUD still drew (they
	# position themselves), so the window looked normal while the spotlight was silently absent. That
	# cost a false diagnosis of shipped code. Do not make this a `Node2D` again.
	await get_tree().process_frame
	await get_tree().process_frame
	# ⚠ **DEAL UNTIL A COLUMN IS ACTUALLY STACKED.** One `next()` gives a board ONE card deep per
	# column, where nothing is covered and the reveal correctly does nothing — which is precisely why
	# every earlier fixture proved nothing about S16. Each `Next` drops another card onto the columns,
	# so keep going until `_row_covers_anything` is true somewhere.
	for _n : int in 4:
		await view.game.next()
		view.play_area.flush_rebuild()
		await get_tree().process_frame
		var deep := false
		for zx : int in 2:
			for rz : int in 4:
				if view.play_area._row_covers_anything(zx, rz): deep = true
		if deep: break
	await get_tree().process_frame
	var pa := view.play_area

	# ⚠ **TARGET A ROW THAT ACTUALLY COVERS SOMETHING — otherwise the reveal correctly does nothing
	# and the shot proves nothing.** The first version took row 0 of whichever zone and hardcoded zone
	# 0 in its readout, so on a board whose stacks sit in the OTHER zone it reported `extra=0` and
	# looked broken. Pick the zone/row with a card underneath, which is the only case the feature is
	# for.
	var zone_x := -1
	var row_z := -1
	for zx : int in 2:
		for rz : int in 4:
			if pa._row_covers_anything(zx, rz):
				zone_x = zx
				row_z = rz
				break
		if zone_x >= 0: break
	var row : Array[CardData] = []
	for data : CardData in pa.data_card.keys():
		var v := pa.coord_of_data(data)
		if v.x == zone_x and v.z == row_z: row.append(data)
	# ⚠ **THE PAIR MUST BE IN THE SAME COLUMN.** The first version took any card at `row_z + 1` in the
	# zone, so it measured the distance between two cards in DIFFERENT columns — a number that says
	# nothing about covering and never returned to its starting value. The reveal separates a card from
	# the one directly beneath IT.
	var buried : CardData = null
	var coverer : CardData = null
	for data : CardData in pa.data_card.keys():
		var v := pa.coord_of_data(data)
		if v.x != zone_x or v.z != row_z: continue
		for other : CardData in pa.data_card.keys():
			var ov := pa.coord_of_data(other)
			if ov.x == zone_x and ov.y == v.y and ov.z == row_z + 1:
				coverer = data
				buried = other
				break
		if buried: break
	print("[reveal_shot] revealing zone=%d row=%d (%d cards); buried below = %s"
			% [zone_x, row_z, row.size(), str(buried != null)])
	print("[reveal_shot] board cards = %d" % pa.data_card.size())

	_zx = maxi(zone_x, 0)
	_rz = maxi(row_z, 0)
	# How much of the buried card is showing — the claim the whole step exists for.
	_buried = pa.data_card.get(buried) if buried else null
	_coverer = pa.data_card.get(coverer) if coverer else null
	await _shot("00_closed", pa)
	view.game.spotlight_section_changed.emit(row)
	# Mid-open: sampled by the opening's own progress, not by a frame count, so the shot is the same
	# moment of the animation whatever the frame rate.
	var waited := 0.0
	while waited < 3.0 and _progress(pa) < 0.35:
		waited += await _tick()
	await _shot("01_opening_%d" % roundi(_progress(pa) * 100.0), pa)
	while waited < 6.0 and _progress(pa) < 0.999:
		waited += await _tick()
	# ⚠ **MEASURE THE LAMP SPREAD — chart I2/I12 says origins spread EVENLY across the band.** The
	# owner read the evidence shot as *"the lights arent spread evenly"*, and a picture of overlapping
	# cones cannot settle that: print the actual origin x of every live beam next to its target.
	var ll0 := view.light_layer
	var ox : Array[String] = []
	var tx : Array[String] = []
	for l : LightLayer.Light in ll0._lights:
		ox.append("%.0f" % l.origin.x)
		tx.append("%.0f" % l.centre.x)
	print("[reveal_shot] lamps  origin_x = [%s]" % ", ".join(ox))
	print("[reveal_shot] lamps  target_x = [%s]  (viewport width %.0f)"
			% [", ".join(tx), get_viewport().get_visible_rect().size.x])
	await _shot("02_open_full", pa)

	# The other separation mode, on the same board, for a side-by-side.
	SettingsManager.settings.spotlight_separation_mode = PlayerSettings.SeparationMode.JUMP_ADJUSTED
	view.game.spotlight_section_changed.emit([] as Array[CardData])
	while waited < 9.0 and not pa._row_open.is_empty():
		waited += await _tick()
	view.game.spotlight_section_changed.emit(row)
	while waited < 12.0 and _progress(pa) < 0.999:
		waited += await _tick()
	await _shot("03_open_jump_adjusted", pa)

	view.game.spotlight_section_changed.emit([] as Array[CardData])
	while waited < 15.0 and not pa._row_open.is_empty():
		waited += await _tick()
	await _shot("04_closed_again", pa)

	# ---- S15's MOMENTARY CUE, through the REAL sweep -------------------------------------------
	# ⚠ **THE POINT OF THIS HALF: the cue is unreachable in the shipped game** — `spotlight_cued` is
	# `Q246`-filtered to skills implementing `on_spotlight`, and the only one was a RULES card with no
	# `CardVisual`. `SpotlightProbe` is the board-stage skill that filter was meant to select. This
	# drives `skill_spotlight_check()` itself, NOT a hand-built `spotlight_cued.emit`, so a shot here
	# is evidence about the real path rather than about the drawing code in isolation.
	SettingsManager.settings.spotlight_separation_mode = PlayerSettings.SeparationMode.CARD_HEIGHT
	# ⚠ Stamp then ASK — a ZONE-stage column header is skill-free but permanently covered, so
	# `is_spotlit()` is false and it never transitions. See `GameView._on_debug_cue`.
	var probe_card : CardData = null
	for data : CardData in pa.data_card.keys():
		if data.skill != null: continue
		data.with_skill(SpotlightProbe.new())
		if data.skill.is_spotlit():
			probe_card = data
			break
		data.with_skill(null)
	if probe_card:
		print("[reveal_shot] probe on %s stage=%d is_spotlit=%s"
				% [probe_card.log_str(), probe_card.stage, str(probe_card.skill.is_spotlit())])
		var cued_seen : Array[int] = []
		view.game.spotlight_cued.connect(
				func(cards: Array[CardData]) -> void: cued_seen.append(cards.size()))
		await view.game.skill_spotlight_check()
		print("[reveal_shot] spotlight_cued fired %d time(s): %s" % [cued_seen.size(), str(cued_seen)])
		# ⚠ **WAIT FOR THE PEAK, NOT FOR THE LIGHT TO EXIST.** The first version shot two frames after
		# `is_lit()` went true and the image was BLANK — the cue was real but its spawn envelope was
		# still near zero, so the frame showed nothing. `is_lit()` answers "does a light exist", which
		# is not the same question as "is it visible yet". Track the intensity the shader is actually
		# handed and shoot when it tops out.
		var lit := 0.0
		var peak := 0.0
		while lit < 3.0:
			lit += await _tick()
			var now := 0.0
			for l : LightLayer.Light in view.light_layer._lights: now = maxf(now, l.intensity)
			if now < peak - 0.05: break         # past the top and already retiring
			peak = maxf(peak, now)
			if now >= 0.99: break
		var ll := view.light_layer
		print("[reveal_shot] cue: lights=%d peak_intensity=%.2f dim=%.3f"
				% [ll._lights.size(), peak, ll._dim])
		# ⚠ The node's own render state — the backdrop measurement says NOTHING reached a pixel, so the
		# question is no longer about the light set but about whether this ColorRect draws at all.
		var pc := ll.get_parent() as Control
		print("[reveal_shot] parent rect=%s  view_size=%s  viewport=%s  ll_rect=%s anchors=(%.2f,%.2f)"
				% [str(pc.size) if pc else "n/a", str(view.size),
					str(get_viewport().get_visible_rect().size), str(ll.get_rect()),
					ll.anchor_right, ll.anchor_bottom])
		var parent := ll.get_parent() as CanvasItem
		print("[reveal_shot] layer: visible=%s vis_in_tree=%s size=%s idx=%d/%d mat=%s u_dim=%s count=%s parent=%s parent_vis=%s"
				% [str(ll.visible), str(ll.is_visible_in_tree()), str(ll.size), ll.get_index(),
					ll.get_parent().get_child_count() - 1, str(ll.material != null),
					str(ll._mat.get_shader_parameter(&"u_dim") if ll._mat else null),
					str(ll._mat.get_shader_parameter(&"u_light_count") if ll._mat else null),
					ll.get_parent().name, str(parent.visible) if parent else "n/a"])
		await _shot("05_cue_probe", pa)
	else:
		print("[reveal_shot] no skill-free board card to stamp the probe onto")
	SettingsManager.settings.spotlight_separation_mode = _prev_mode
	# Put the player's run back exactly as it was — see the note in `_ready`.
	if FileAccess.file_exists(SAVE_BAK):
		DirAccess.copy_absolute(SAVE_BAK, REAL_SAVE)
		DirAccess.remove_absolute(SAVE_BAK)
		print("[reveal_shot] real run save restored")
	print("[reveal_shot] done (separation mode restored to %d)" % _prev_mode)
	get_tree().quit()

func _progress(pa: PlayArea) -> float:
	var best := 0.0
	for v : float in pa._row_open.values(): best = maxf(best, v)
	return best

func _tick() -> float:
	await get_tree().process_frame
	return get_process_delta_time()

var _zx : int = 0
var _rz : int = 0
## The covered card and the one covering it — the pair whose separation IS the reveal.
var _buried : CardVisual = null
var _coverer : CardVisual = null

func _shot(name: String, pa: PlayArea) -> void:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("%s/%s.png" % [OUT_DIR, name])
	# ⚠ **SAMPLE THE BACKDROP, BECAUSE "I CANNOT SEE A DIM" IS NOT A MEASUREMENT.** A flat empty patch
	# of the window is where the dim is most visible and least confusable with art, so its luminance
	# across shots is what says whether the light layer is drawing at all.
	var bg := img.get_pixel(int(img.get_width() * 0.30), int(img.get_height() * 0.85))
	# ⚠ **HOW MUCH OF THE BURIED CARD IS SHOWING is the claim S16 exists for.** The strip visible above
	# the covering card is the gap the opening creates, so it is the number that says the reveal
	# REVEALED something rather than merely moved the board.
	var gap := 0.0
	if _buried and _coverer:
		var b : CardVisual = _buried
		var c : CardVisual = _coverer
		if is_instance_valid(b) and is_instance_valid(c):
			gap = c.global_position.y - b.global_position.y
	print("[reveal_shot] %-24s open=%.2f extra=%.1fpx gap=%.1fpx backdrop=(%.3f,%.3f,%.3f)"
			% [name, _progress(pa), pa.row_open_extra(_zx, _rz), gap, bg.r, bg.g, bg.b])

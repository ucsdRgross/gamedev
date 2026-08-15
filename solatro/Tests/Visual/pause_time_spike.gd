extends Node2D
# res://Tests/Visual/pause_time_spike.gd
# ==============================================================================
# PHASE 0 SPIKE (picture-wall PLAN.md S1) — "Scene with one card burning, get_tree().paused = true,
# screenshot at t=0 and t=+20 s. Done when: you can state whether the flame advanced." DESIGN.md
# D7/D10/Q222.
#
# THE REAL SHIPPED EFFECT, not a stand-in (repo rule 5, "no mocks in tools"): a real `PlayArea`
# (res://UI/play_area.tscn) holding a real `Game`/`GameData` with one card, a real
# `CardModifierStatus.stacked(StatusBurning, 3)` attached to it exactly as `add_status` is called
# everywhere else, which builds the real `CardVisual` -> real `FxAttachment` -> the real
# `fire.gdshader` quad, on its ordinary, un-touched `process_mode`. Same fixture pattern as
# `Tests/UI/test_visual_layers.gd:test_fx_inside_its_host` (make_board_game / settle / add_status).
#
# ⚠ THIS PROJECT'S SHADERS DELIBERATELY NEVER READ THE BUILT-IN `TIME` — `fire.gdshader:107`'s
# `u_time` is "pacing-aware, script-driven — NEVER the built-in TIME", and `FxAttachment._process`
# (UI/Fx/fx_attachment.gd:961) is the one place that advances it: `_time += delta * pacing()`, then
# `_push_live` uploads it as `u_time`. So the fact this spike actually needs is not "does built-in
# TIME advance under pause" (it does — that is a fact about the engine, not about this game, and is
# NOT what D7 rests on) but "does FxAttachment's OWN clock keep ticking under
# get_tree().paused = true" — which is a question about `_process`'s process_mode, answerable only
# by running the genuine effect.
#
# Not a repeatable regression test — a one-off diagnostic, run windowed by hand:
#     <console exe> --path solatro res://Tests/Visual/pause_time_spike.tscn
# Writes two PNGs to user://pause_time_spike/, prints a pixel-diff count between them, then quits.
# Deliberately NOT in all_tests.tscn: it needs a real renderer and 20+ real seconds of wall time.
# ==============================================================================

const OUT_DIR := "user://pause_time_spike"
const WAIT_SECS := 20.0
const PLAY_AREA_SCENE := preload("res://UI/play_area.tscn")
const WATCHDOG_SECS := 10.0

func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("pause_time_spike needs a REAL renderer: --headless never compiles a shader. "
				+ "Re-run WITHOUT --headless.")
		get_tree().quit(1)
		return
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	DisplayServer.window_set_size(Vector2i(1152, 648))

	# ---- the real burning card, built the way the game itself builds one -------------------------
	var g := Game.new()
	var s := GameData.new()
	var head := TestFactories.m_card(1, TestFactories.uc())
	head.stage = CardData.Stage.ZONE
	var card := TestFactories.m_card(7, TestFactories.uc())
	card.stage = CardData.Stage.PLAY
	s.upper_zone_type = [head] as Array[CardData]
	s.upper_zone = [TestFactories.col([card] as Array[CardData])] as Array[ArrayCardData]
	g.state = s
	g._begin_act()
	CardEnvironment.CURRENT = g

	var pa : PlayArea = PLAY_AREA_SCENE.instantiate()
	add_child(pa)
	pa.size = Vector2(1152, 648)

	# Wait for the board's CardVisuals to actually be in-tree and _ready (mirrors
	# test_visual_layers.gd's `settle`), with a watchdog so a broken fixture fails loudly instead of
	# hanging forever.
	var waited := 0.0
	while not pa.visuals_ready() and waited < WATCHDOG_SECS:
		await get_tree().process_frame
		waited += get_process_delta_time()
	if not pa.visuals_ready():
		push_error("pause_time_spike: PlayArea never settled (visuals_ready() stayed false for "
				+ "%.1f s) — the fixture is broken, not the spike." % WATCHDOG_SECS)
		get_tree().quit(1)
		return

	# The real status, attached the real way. This is what makes CardVisual build its FxAttachment.
	card.add_status(CardModifierStatus.stacked(StatusBurning, 3))
	await get_tree().process_frame

	var vis : CardVisual = pa.data_card.get(card)
	if not vis or not vis.fx or vis.fx.get_child_count() == 0:
		push_error("pause_time_spike: the burning card never built an FX quad — the fixture is "
				+ "broken, not the spike.")
		get_tree().quit(1)
		return

	# Let it actually burn a moment BEFORE pausing, unpaused, so the noise term is already moving
	# rather than sitting at its t=0 starting value.
	await get_tree().create_timer(1.0).timeout

	get_tree().paused = true
	var img0 := await _capture("t0")

	# get_tree().create_timer defaults process_always = true (Scripts/pacing.gd's whole reason to
	# exist is replacing this in game code) — so THIS wait keeps counting through the pause, which is
	# exactly what is needed to reach +20 REAL seconds while the tree stays paused. It is not what is
	# under test; FxAttachment._process is.
	await get_tree().create_timer(WAIT_SECS).timeout
	var img1 := await _capture("t20")

	var diff := _diff_count(img0, img1)
	var total := img0.get_width() * img0.get_height()
	print("PAUSE_TIME_SPIKE diff_pixels=%d total_pixels=%d" % [diff, total])
	print("PAUSE_TIME_SPIKE t0=%s" % ProjectSettings.globalize_path("%s/t0.png" % OUT_DIR))
	print("PAUSE_TIME_SPIKE t20=%s" % ProjectSettings.globalize_path("%s/t20.png" % OUT_DIR))
	get_tree().quit()

## Waits two rendered frames so the just-applied state is actually on screen, then grabs and
## writes the viewport as a PNG.
func _capture(shot_name: String) -> Image:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("%s/%s.png" % [OUT_DIR, shot_name])
	return img

## A plain per-pixel mechanical comparison — no shader-specific knowledge, just "how many pixels
## are not identical".
func _diff_count(a: Image, b: Image) -> int:
	var n := 0
	for y : int in a.get_height():
		for x : int in a.get_width():
			if a.get_pixel(x, y) != b.get_pixel(x, y): n += 1
	return n

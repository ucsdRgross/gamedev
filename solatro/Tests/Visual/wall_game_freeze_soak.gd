extends TestSuite
# res://Tests/Visual/wall_game_freeze_soak.gd
# ==============================================================================
# S31 / PHASE 7 GATE (PLAN.md §3): "a freeze/resume soak mid-act leaves GameData.revision
# unchanged." Builds ONE real GameView (PlayArea, LightLayer, SpotlightDirector, a real headless
# Game underneath -- the SAME fixture recipe Tests/Engine/test_leak_canary.gd's own "a real show
# WITH a GameView" section already uses), gets it into mid-act, attaches it to a real WallPicture
# via `attach_screen()` (S31), then cycles focus()/unfocus() many times -- each cycle asserting
# `GameData.revision` is bit-for-bit unchanged across the frozen window (L4/L5: "the guarantee
# covers everything the board owns... bit-identical").
#
# STANDALONE, deliberately NOT in all_tests.tscn: needs a REAL `get_tree().paused = true`, which
# test_base.gd's own DEADLOCK RULE comment already documents as fatal to a shared test tree
# (measured directly, HANDOFF: "constructing a real Wall inside the shared test tree freezes
# every other suite" -- this scene freezes the tree on purpose, for real, which is the whole point
# here, so it cannot share a tree with 38 other suites that need to keep running).
#
# One-off diagnostic, run windowed by hand, WITH AN EXTERNAL KILLING TIMEOUT (it calls
# get_tree().quit() itself, but a caller should still bound the process):
#     <console exe> --path solatro res://Tests/Visual/wall_game_freeze_soak.tscn
# ==============================================================================

const GAME_VIEW_SCENE := preload("res://Levels/game_view.tscn")
const WALL_PICTURE_SCENE := preload("res://UI/Wall/wall_picture.tscn")

## Overridable via FREEZE_SEED so a reported failure can be replayed exactly.
const DEFAULT_SEED := 20260817
## "many cycles", not one -- the coordinator's own ask, well past T13's 20-transition precedent.
const CYCLES := 50
const MAX_FROZEN_FRAMES := 6

func suite_name() -> String:
	return "WALL GAME FREEZE SOAK"

func _ready() -> void:
	TestLog.line("============ WALL GAME FREEZE SOAK ============")
	await _run_soak()
	finish()
	get_tree().quit()

func _run_soak() -> void:
	var env_seed := OS.get_environment("FREEZE_SEED")
	var seed_val := int(env_seed) if not env_seed.is_empty() else DEFAULT_SEED
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val
	TestLog.line("FREEZE_SOAK seed=%d cycles=%d" % [seed_val, CYCLES])

	# Disk-test isolation (test_base.gd's own established convention) -- RunManager.new_run() /
	# save_run() below write to the SAME path a real run uses.
	backup_real_save()
	var real_save_info : RunState = Main.save_info

	var cards := TestDecks.seeded_deck()
	var rules := TestDecks.standard_rules()
	var run := RunManager.new_run(cards, rules)
	run.pending_goal = 1
	run.pending_node_id = 2
	Main.save_info = run

	var view : GameView = GAME_VIEW_SCENE.instantiate()
	add_child(view)
	await get_tree().process_frame
	await get_tree().process_frame
	var g : Game = view.game
	await g.next()
	await g.next()   # two rounds dealt -- genuinely mid-act, not just the initial deal
	check(g.state.revision > 0, "the game reached a real mid-act board state before the soak starts",
			"revision=%d" % g.state.revision)

	# The wall picture hosting the game, and the REAL global pause the freeze mechanism depends on
	# (Wall._ready()'s own line, reproduced by hand here since this scene builds no real Wall node).
	var wp : WallPicture = WALL_PICTURE_SCENE.instantiate()
	add_child(wp)
	var viewports := Node.new()
	add_child(viewports)
	var rect := PictureRect.new(&"game", Vector2.ZERO, Vector2(1152, 648), Vector4(24, 24, 24, 24))
	var entry := PictureEntry.new()
	entry.id = &"game"
	entry.design_size = Vector2i(1152, 648)
	wp.build(rect, entry, viewports, view)
	get_tree().paused = true
	wp.focus()
	await get_tree().process_frame

	var revision_before_soak := g.state.revision
	var cycles_run := 0
	for i : int in CYCLES:
		wp.unfocus(Vector2(200, 150))   # leave mid-act -- THE FREEZE
		check(wp.screen_root.process_mode == Node.PROCESS_MODE_PAUSABLE,
				"cycle %d/%d: unfocus() actually flipped the screen back to PAUSABLE" % [i, CYCLES])
		var frozen_revision := g.state.revision
		var frozen_frames := rng.randi_range(1, MAX_FROZEN_FRAMES)
		for _f : int in frozen_frames:
			await get_tree().process_frame
		check(g.state.revision == frozen_revision,
				"cycle %d/%d (seed %d): GameData.revision unchanged across %d frozen frame(s)"
				% [i, CYCLES, seed_val, frozen_frames],
				"before=%d after=%d" % [frozen_revision, g.state.revision])
		wp.focus()   # resume -- back to exactly where it was
		check(wp.screen_root.process_mode == Node.PROCESS_MODE_ALWAYS,
				"cycle %d/%d: focus() actually flipped the screen back to ALWAYS" % [i, CYCLES])
		await get_tree().process_frame
		cycles_run += 1

	check(cycles_run == CYCLES,
			"the soak actually ran every cycle (seed %d) before any of the above was asserted"
			% seed_val, "ran=%d" % cycles_run)
	check(g.state.revision == revision_before_soak,
			"the WHOLE soak leaves revision exactly where it started -- nothing leaked through "
			+ "while frozen, across %d cycles" % CYCLES,
			"before=%d after=%d" % [revision_before_soak, g.state.revision])

	get_tree().paused = false
	wp.teardown()   # frees viewport -> cascades to screen_root (the GameView) -> its Game child
	viewports.queue_free()
	RunManager._shutdown_saver()
	Main.save_info = real_save_info
	restore_real_save()

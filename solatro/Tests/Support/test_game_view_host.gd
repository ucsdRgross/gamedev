class_name TestGameViewHost
## Hosts a real GameView the way production does: inside a design-sized SubViewport.

#Production lays the board out at game_picture_design_size inside the wall's own SubViewport, never
#against the OS window. Instantiating GameView directly into a suite's tree lays it out against the
#OS window instead, which drifts from production.

#Shared by every suite that hosts a real GameView, so the hosting logic exists once.

#queue_free() the returned SubViewport to free the view, and its Game child, too.

## Adds a design-sized SubViewport under `parent`, then `view` under that.
static func host(parent: Node, view: GameView) -> SubViewport:
	var vp := SubViewport.new()
	vp.size = PlayArea.game_picture_design_size(SettingsManager.settings)
	parent.add_child(vp)
	vp.add_child(view)
	return vp

const GAME_VIEW_SCENE : PackedScene = preload("res://Levels/game_view.tscn")

#A SHOT NEEDS A REAL RENDERER, somewhere to put the pictures, and the in-screen panels off -- one
#would open over the very cell being photographed. Isolated, so no knob reaches the player's file.
## The directory the PNGs go in, or "" when there is no renderer and the caller must stop.
static func shot_setup(node: Node, fallback_dir: String) -> String:
	if DisplayServer.get_name() == "headless":
		push_error("a by-eye shot needs a REAL renderer: --headless never fires frame_post_draw.")
		node.get_tree().quit(1)
		return ""
	var out_dir := OS.get_environment("OUT_DIR")
	if out_dir.is_empty(): out_dir = fallback_dir
	if out_dir.begins_with("user://"): DirAccess.make_dir_recursive_absolute(out_dir)
	SettingsManager.isolated = true
	SettingsManager.settings.wall_screen_popups = false
	return out_dir

#THE PLAYER'S OWN RUN PUT BACK: a shot boots a real show over the real save slot, so undoing that
#is the last thing it does.
static func shot_teardown(tag: String) -> void:
	CardEnvironment.CURRENT = null
	RunManager._shutdown_saver()
	RunManager.clear_save()
	TestSuite.restore_real_save(tag)

## How long a shot waits for the opening deal before giving up on it, in seconds.
const SHOT_DEAL_WATCHDOG := 40.0

#EVERY BY-EYE SHOT OF THIS BOARD WANTS THE SAME BOARD: one show dealt at a fixed seed, its
#opening deal finished -- the deal has a duration and the board is not the board until it ends --
#and the two extra grids an overview picture needs.
static func boot_shot_board(node: Node, tag: String, rng_seed: int) -> GameView:
	var view := await boot_show(node, tag, TestDecks.deck_standard_52(),
			TestDecks.standard_rules(), 1_000_000_000, 2, rng_seed)
	var pa := view.play_area
	var waited := 0.0
	while waited < SHOT_DEAL_WATCHDOG and not pa._plan_reveal_pending.is_empty():
		await node.get_tree().process_frame
		waited += node.get_process_delta_time()
	print("[shot] the opening deal finished after %.2f s" % waited)
	await view.game.next()
	view.game.effect_api.add_grid(GridData.new())
	view.game.effect_api.add_grid(GridData.new())
	pa.flush_rebuild()
	return view

#A by-eye harness stands a show up OUTSIDE a suite, so parking the player's own save is part of the
#boot rather than something each one has to remember, and the seed is an argument because a picture
#that is not the same picture twice cannot be diffed. `TestSuite.restore_real_save` puts reality back.

## A parked save, a fresh run, a GameView under `parent`, and CURRENT pointed at its game.
static func boot_show(parent: Node, tag: String, cards: Array[CardData], rules: Array[CardData],
		goal: int, node_id: int, rng_seed: int) -> GameView:
	TestSuite.backup_real_save(tag)
	var run := RunManager.new_run(cards, rules)
	Main.save_info = run
	run.pending_goal = goal
	run.pending_node_id = node_id
	seed(rng_seed)
	var view : GameView = GAME_VIEW_SCENE.instantiate()
	parent.add_child(view)
	await parent.get_tree().process_frame
	await parent.get_tree().process_frame
	CardEnvironment.CURRENT = view.game
	return view

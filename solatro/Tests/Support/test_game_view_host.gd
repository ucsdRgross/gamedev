class_name TestGameViewHost
## Hosts a real GameView the way production does: inside a SubViewport sized to
## `game_picture_design_size` (production lays the board out at that size inside the wall's own
## SubViewport, `UI/Wall/wall_picture.gd`), never against the OS window. Instantiating
## GameView directly into a suite's own tree lays it out against the OS window instead, which
## drifted from production once PlayContainer's height stopped matching the window height.
## Shared by every suite that hosts a real GameView, so the hosting logic exists once.

## Adds a design-sized SubViewport under `parent`, then `view` under that. Returns the
## SubViewport -- `queue_free()` it to free the view (and its Game child) too.
static func host(parent: Node, view: GameView) -> SubViewport:
	var vp := SubViewport.new()
	vp.size = PlayArea.game_picture_design_size(SettingsManager.settings)
	parent.add_child(vp)
	vp.add_child(view)
	return vp

const GAME_VIEW_SCENE : PackedScene = preload("res://Levels/game_view.tscn")

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

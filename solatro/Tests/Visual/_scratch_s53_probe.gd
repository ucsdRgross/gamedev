extends Node2D
# THROWAWAY VERIFICATION SCRATCH SCRIPT -- not part of the suite, deleted after use.

const GAME_VIEW_SCENE := preload("res://Levels/game_view.tscn")

func _ready() -> void:
	var src_cards := TestDecks.seeded_deck()
	var src_rules := TestDecks.standard_rules()
	var run := RunManager.new_run(src_cards, src_rules)
	Main.save_info = run
	run.pending_goal = 1
	run.pending_node_id = 2
	var view : GameView = GAME_VIEW_SCENE.instantiate()
	TestGameViewHost.host(self, view)
	await get_tree().process_frame
	await get_tree().process_frame
	var game := view.game
	var pa := view.play_area
	await game.next()
	await game.next()
	pa.flush_rebuild()
	await get_tree().process_frame

	var waited := 0.0
	while waited < 2.0:
		await get_tree().process_frame
		waited += get_process_delta_time()

	var bar := pa.scroll_container.get_v_scroll_bar()
	print("[S53] ON ENTRY scroll_vertical=%s bar.max_value=%s" % [pa.scroll_container.scroll_vertical, bar.max_value])

	pa.scroll_container.scroll_vertical = 0
	await get_tree().process_frame
	print("[S53] AFTER MANUAL SCROLL scroll_vertical=%s" % [pa.scroll_container.scroll_vertical])

	pa.flush_rebuild()
	await get_tree().process_frame
	await get_tree().process_frame
	print("[S53] AFTER REBUILD (should stay where the player left it) scroll_vertical=%s bar.max_value=%s"
			% [pa.scroll_container.scroll_vertical, bar.max_value])

	RunManager._shutdown_saver()
	RunManager.clear_save()
	get_tree().quit()

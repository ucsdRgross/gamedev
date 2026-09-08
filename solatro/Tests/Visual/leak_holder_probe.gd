extends Node2D
# res://Tests/Visual/leak_holder_probe.gd
# ==============================================================================
# WHO HOLDS THE UNREACHABLE CARDS (not part of the suite).
#
# `LeakSentinel` reports cards that are ALIVE but not reachable from any owner it scans. The
# handoff inferred a REFERENCE CYCLE from that, on the grounds that `CardData` is `RefCounted`.
# ⚠ That inference does not follow: a `RefCounted` also stays alive when something holds a plain
# strong reference the scan simply does not FOLLOW. This probe discriminates the two by NAMING a
# holder for every unreachable card.
#
# It reproduces the product's shape, which `test_leak_canary` structurally cannot: the rules deck
# PERSISTS across shows within one run, so it runs a show, leaves it, and ticks the sentinel with
# the run doc still alive -- the canary drops the whole run doc every cycle, so a cross-show holder
# is released before it could ever be counted.
#
# Run windowed, WITH AN EXTERNAL KILLING TIMEOUT:
#     <console exe> --path solatro res://Tests/Visual/leak_holder_probe.tscn
# ==============================================================================

const GAME_VIEW_SCENE := preload("res://Levels/game_view.tscn")
const SAVE_TAG := "leak_holder_probe"

func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("leak_holder_probe hosts a real GameView. Re-run WITHOUT --headless.")
		get_tree().quit(1)
		return
	TestSuite.backup_real_save(SAVE_TAG)
	LeakSentinel.test_mode = true

	var run := RunManager.new_run(TestDecks.deck_standard_52(), TestDecks.standard_rules())
	Main.save_info = run
	run.pending_goal = 1_000_000_000
	run.pending_node_id = 2
	seed(20260903)

	await _report("before any show")

	var view : GameView = GAME_VIEW_SCENE.instantiate()
	add_child(view)
	for _i : int in 6:
		await get_tree().process_frame
	CardEnvironment.CURRENT = view.game
	await view.game.next()
	for _i : int in 4:
		await get_tree().process_frame
	await _report("show 1 live")

	view.game.exit_show()
	for _i : int in 4:
		await get_tree().process_frame
	view.queue_free()
	for _i : int in 6:
		await get_tree().process_frame
	CardEnvironment.CURRENT = null
	for _i : int in 4:
		await get_tree().process_frame
	await _report("show 1 left -- THE MAP-ENTRY MOMENT the sentinel reports at")

	var view2 : GameView = GAME_VIEW_SCENE.instantiate()
	add_child(view2)
	for _i : int in 6:
		await get_tree().process_frame
	CardEnvironment.CURRENT = view2.game
	await view2.game.next()
	for _i : int in 4:
		await get_tree().process_frame
	await _report("show 2 live")

	view2.queue_free()
	for _i : int in 6:
		await get_tree().process_frame
	CardEnvironment.CURRENT = null
	Main.save_info = RunState.new()
	RunManager.run = null
	for _i : int in 6:
		await get_tree().process_frame
	await _report("run dropped -- nothing legitimate holds anything now")

	RunManager._shutdown_saver()
	RunManager.clear_save()
	TestSuite.restore_real_save(SAVE_TAG)
	get_tree().quit()

## Five checks spread over frames, then a holder for every unreachable card of the LAST one.
##
## ⚠ **ONE SAMPLE CANNOT TELL A LEAK FROM A TRANSIENT.** The sentinel only reports a count that
## survives `leak_sentinel_strikes` checks, so a single reading of the same number it prints is not
## the same observation. A count that falls to zero across these samples was a drop in flight.
func _report(tag: String) -> void:
	var counts : Array[int] = []
	for _s : int in 5:
		for _f : int in 10:
			await get_tree().process_frame
		var a := LeakSentinel._alive_cards()
		var r := LeakSentinel._reachable_set()
		var n := 0
		for c : CardData in a:
			if not r.has(c): n += 1
		counts.append(n)
	print("[leak_holder_probe] === %s === unreachable across 5 settled checks: %s" % [tag, counts])
	_attribute(tag)

func _attribute(tag: String) -> void:
	var alive := LeakSentinel._alive_cards()
	var reachable := LeakSentinel._reachable_set()
	var unreachable : Array[CardData] = []
	for card : CardData in alive:
		if not reachable.has(card): unreachable.append(card)
	print("[leak_holder_probe] === %s === alive %d, reachable %d, UNREACHABLE %d"
			% [tag, alive.size(), reachable.size(), unreachable.size()])
	var held := _held_by_rules_cards()
	var attributed : Dictionary[String, int] = {}
	var orphans : Array[CardData] = []
	for card : CardData in unreachable:
		if held.has(card):
			var key : String = held[card]
			attributed[key] = attributed.get(key, 0) + 1
		else:
			orphans.append(card)
	for key : String in attributed:
		print("[leak_holder_probe]   %3dx HELD BY %s" % [attributed[key], key])
	if orphans.is_empty():
		print("[leak_holder_probe]   no unattributed cards -- every unreachable card has a named holder")
	else:
		print("[leak_holder_probe]   %d UNATTRIBUTED:" % orphans.size())
		print(LeakSentinel._histogram(orphans))

## Every card a PERSISTENT RULES CARD holds through one of its modifier fields, mapped to the
## field that holds it. `ZoneAdder.card_data` and `SkillGridCreator.grid_data` are the two the
## design puts there; both are `@export_storage`, both survive a show, and neither is followed by
## `LeakSentinel._reachable_set()`.
##
## ⚠ Read through `Object.get()` rather than a cast to a concrete skill class: a third field of
## this shape added later must show up here without this probe being edited, or the probe quietly
## certifies a smaller leak than the one that exists.
func _held_by_rules_cards() -> Dictionary[CardData, String]:
	var out : Dictionary[CardData, String] = {}
	# The DEBUG-ONLY undo history. `_debug_commit()` appends `state.to_saveable()`, a FRESH
	# duplicate of the whole board, and the array is uncapped -- while `LeakSentinel` scans
	# `save_history` and never these two.
	var game : Game = CardEnvironment.get_current_game()
	if game:
		for snap : GameData in game.debug_snapshots():
			if not snap: continue
			for c : CardData in snap.all_card_datas():
				if c: out[c] = "Game.debug_snapshots()"
	for source : Array in [_rule_cards(Main.save_info), _rule_cards(RunManager.run)]:
		for rc : CardData in source:
			for mod : CardModifier in [rc.skill, rc.type, rc.stamp, rc.suit]:
				if not mod: continue
				var name := (mod.get_script() as Script).resource_path.get_file()
				var one : Variant = mod.get("card_data")
				if one is CardData: out[one as CardData] = "%s.card_data" % name
				var grid : Variant = mod.get("grid_data")
				if grid is GridData:
					var gd : GridData = grid
					for c : CardData in gd.cell_types:
						if c: out[c] = "%s.grid_data.cell_types" % name
					for cell : ArrayCardData in gd.cells:
						if not cell: continue
						for c : CardData in cell.datas:
							if c: out[c] = "%s.grid_data.cells" % name
	return out

func _rule_cards(rs: RunState) -> Array[CardData]:
	return rs.rule_datas if rs else ([] as Array[CardData])

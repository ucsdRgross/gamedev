extends Control

# PHOTOGRAPHS THE MARK AND TIMES THE OPENING REVEAL, in the real game picture. The reveal has a
# DURATION, so its sequence is printed as it happens, and the look is a colour question, so the
# picture is taken at both zooms.

# Run windowed, WITH AN EXTERNAL KILLING TIMEOUT:
#     OUT_DIR=<absolute dir> <console exe> --path solatro res://Tests/Visual/plan_reveal_shot.tscn

# Deliberately NOT in all_tests.tscn: needs a real renderer and is by-eye material.

const OUT_DIR_FALLBACK := "user://reveal_shots"
const SAVE_TAG := "plan_reveal_shot"
# Long enough for 25 cells at the shipped pacing, which is what the print-out measures.
const REVEAL_WATCHDOG := 40.0

var _out_dir : String

func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("plan_reveal_shot needs a REAL renderer: --headless never fires frame_post_draw.")
		get_tree().quit(1)
		return
	_out_dir = OS.get_environment("OUT_DIR")
	if _out_dir.is_empty(): _out_dir = OUT_DIR_FALLBACK
	if _out_dir.begins_with("user://"): DirAccess.make_dir_recursive_absolute(_out_dir)

	var view := await TestGameViewHost.boot_show(self, SAVE_TAG,
			TestDecks.deck_standard_52(), TestDecks.standard_rules(), 1_000_000_000, 2, 20260913)
	var g := view.game
	var pa := view.play_area
	print("[plan_reveal_shot] base_delay %.2f, plan_reveal_fraction %.2f, get_delay %.2f"
			% [SettingsManager.settings.base_delay,
			SettingsManager.settings.plan_reveal_fraction, g.get_delay()])
	await _watch_the_reveal(pa, g)

	_grant_a_mark_with_all_four(g)
	_bare_one_cell(g)
	await _cover_a_mark(g)
	pa.flush_rebuild()
	await _settle(view)
	pa.open_zoomed_out()
	await _settle(view)
	await _shoot(pa, "overview")
	pa.focus_grid(0)
	await _settle(view)
	await _shoot(pa, "focused")

	CardEnvironment.CURRENT = null
	RunManager._shutdown_saver()
	RunManager.clear_save()
	TestSuite.restore_real_save(SAVE_TAG)
	get_tree().quit()

# THE MOVEMENT, which a still cannot show: one line per cell the reveal deals, with the wall clock
# beside it and the coordinate it landed on, so the ORDER can be read against row-major.
func _watch_the_reveal(pa: PlayArea, g: Game) -> void:
	var started := Time.get_ticks_msec()
	var total := pa._plan_reveal_pending.size()
	var last := -1
	var waited := 0.0
	while waited < REVEAL_WATCHDOG:
		var left : int = pa._plan_reveal_pending.size()
		if total == 0 and left > 0:
			total = left
			started = Time.get_ticks_msec()
			print("[plan_reveal_shot] reveal begins with %d cells to deal" % total)
		if left != last and total > 0:
			var next := "none"
			if left > 0:
				var coord := g.state.cell_type_coord(pa._plan_reveal_pending[0])
				next = "grid %d cell (%d,%d)" % [coord.grid, coord.x, coord.y]
			print("[plan_reveal_shot] t=%5d ms  revealed %2d of %2d  next %s"
					% [Time.get_ticks_msec() - started, total - left, total, next])
			last = left
		if total > 0 and left == 0: break
		await get_tree().process_frame
		waited += get_process_delta_time()
	print("[plan_reveal_shot] reveal done after %.2f s of wall clock" % waited)
	var marks := 0
	for type_card : CardData in g.state.grids[0].cell_types:
		if BoardPlan.is_marked(type_card): marks += 1
	print("[plan_reveal_shot] %d of %d cells carry a mark" % [marks, g.state.grids[0].cell_types.size()])

# A mark printing ALL FOUR properties, which the shipped 52-card deck cannot supply on its own --
# without one, the picture says nothing about whether a talent or a hat is legible in a cell.
func _grant_a_mark_with_all_four(g: Game) -> void:
	var source := CardData.new().with_type(TypePaper.new()) \
			.with_suit(PipSuitFire.new()) \
			.with_rank(PipRankNumeral.new().with_value(11)) \
			.with_skill(SkillExtraPoint.new()) \
			.with_stamp(StampRevealing.new())
	g.effect_api.grant_mark(BoardCoord.new(0, 2, 2, 0), source)
	print("[plan_reveal_shot] cell (2,2) granted a mark printing rank, suit, talent and hat")

# ONE CELL LEFT BARE, because "a mark has no outline" is a claim about the difference between a
# marked cell and an unmarked one, and a board where every cell is marked shows only one side of it.
func _bare_one_cell(g: Game) -> void:
	BoardPlan.clear_mark(g.state.cell_type_at(BoardCoord.new(0, 4, 4, 0)))
	g.state.revision += 1
	print("[plan_reveal_shot] cell (4,4) cleared back to a bare cell, for the comparison")

# A real card ON a mark, which is the comparison the whole look has to survive: the card on top must
# read as a played card and the sliver under it as a mark.
func _cover_a_mark(g: Game) -> void:
	for x : int in 3:
		var card := g.draw_card()
		if not card: return
		await g.place_card_in_grid(card, BoardCoord.new(0, x, 0, 0))
	print("[plan_reveal_shot] row 0 covered by three real cards")

# One picture plus the rim widths behind it, so "the mark has no outline" can be checked against
# numbers rather than impression -- the mark's against a played card's on the same board.
func _shoot(pa: PlayArea, tag: String) -> void:
	var game := CardEnvironment.get_current_game()
	var mark : CardData = game.state.cell_type_at(BoardCoord.new(0, 2, 2, 0))
	var played : CardData = game.state.card_at(BoardCoord.new(0, 0, 0, 0))
	var visual : CardVisual = pa.data_card.get(mark)
	var played_visual : CardVisual = pa.data_card.get(played)
	if visual and played_visual:
		var mark_mat := visual.type.material as ShaderMaterial
		var played_mat := played_visual.type.material as ShaderMaterial
		print("[plan_reveal_shot] %s rim width: mark %s, played card %s (shipped %d)"
				% [tag, str(mark_mat.get_shader_parameter(&"u_outline_width")),
				str(played_mat.get_shader_parameter(&"u_outline_width")), CardOutline.STYLE.width])
		print("[plan_reveal_shot] %s mark modulate %s, board zoom %.3f"
				% [tag, str(visual.modulate), pa.board_zoom])
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("%s/plan_rimless_%s.png" % [_out_dir, tag])
	print("[plan_reveal_shot] wrote plan_rimless_%s.png" % tag)

# Waits until the board stops moving, so a shot is never taken mid-transition.
func _settle(view: GameView) -> void:
	var last := Vector2(INF, INF)
	for _frame : int in 180:
		await get_tree().process_frame
		var now := view.play_area.slot_center_global(BoardCoord.new(0, 0, 0, 0))
		if now.is_equal_approx(last): return
		last = now

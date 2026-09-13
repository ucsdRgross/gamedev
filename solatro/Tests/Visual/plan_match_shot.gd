extends Control

# PHOTOGRAPHS THE MATCH HIGHLIGHT AND THE LANDING, in the real game picture: a card held over marks
# it agrees with, the same board at overview zoom, and a card that has landed on one -- with the
# FOCUS highlight on the same cell, because the two have to stay tellable apart.

# Run windowed, WITH AN EXTERNAL KILLING TIMEOUT:
#     OUT_DIR=<absolute dir> <console exe> --path solatro res://Tests/Visual/plan_match_shot.tscn

# Deliberately NOT in all_tests.tscn: needs a real renderer and is by-eye material.

const OUT_DIR_FALLBACK := "user://plan_match_shot"
const SAVE_TAG := "plan_match_shot"
const REVEAL_WATCHDOG := 40.0

var _out_dir : String
var _input : TestInput
var _held : CardData
var _rank_cell := BoardCoord.new(0, 1, 2, 0)
var _both_cell := BoardCoord.new(0, 2, 2, 0)
var _miss_cell := BoardCoord.new(0, 3, 2, 0)

func _ready() -> void:
	_out_dir = TestGameViewHost.shot_setup(self, OUT_DIR_FALLBACK)
	if _out_dir.is_empty(): return

	var view := await TestGameViewHost.boot_shot_board(self, SAVE_TAG, 20260913)
	_input = TestInput.driving(self, get_viewport())
	var g := view.game
	var pa := view.play_area
	await _settle(view)

	_held = _an_entrance_card(g, pa)
	_mark_the_three_cells(g)
	pa.flush_rebuild()
	await _settle(view)
	pa.focus_grid(0)
	await _settle(view)
	await _pick_the_card_up(pa)
	await _shoot(view, "held_focused")

	pa.open_zoomed_out()
	pa.rest_board()
	await _settle(view)
	await _shoot(view, "held_overview")

	pa.focus_grid(0)
	await _settle(view)
	await _land_the_card(g, pa)
	await _shoot(view, "landed")

	TestGameViewHost.shot_teardown(SAVE_TAG)
	get_tree().quit()

# The card this shot picks up: one the board offers as a focus target in the Entrance, which is what
# a pointer or a focus ring can reach.
func _an_entrance_card(g: Game, pa: PlayArea) -> CardData:
	for control : Control in pa.ui_data:
		var data : CardData = pa.ui_data[control]
		if control.focus_mode != Control.FOCUS_ALL or not control.is_visible_in_tree(): continue
		if g.state.grid_position_of(data).is_entrance(): return data
	return null

# THREE MARKS IN ONE ROW, against the card about to be held: rank alone, rank and suit, and nothing.
# The dealt plan stays on every other cell, which is what the picture has to read against.
func _mark_the_three_cells(g: Game) -> void:
	g.effect_api.grant_mark(_rank_cell, _source(_held.rank, _another_suit(_held.suit)))
	g.effect_api.grant_mark(_both_cell, _source(_held.rank, _held.suit))
	g.effect_api.grant_mark(_miss_cell, _source(_another_rank(_held.rank), _another_suit(_held.suit)))
	print("[plan_match_shot] holding %s over marks at (1,2) rank-only, (2,2) rank+suit, (3,2) neither"
			% str(_held))

# A card that exists only to be copied onto a cell. Its pips are DUPLICATES: `with_suit` rebinds the
# suit's backref to the card it is handed to, so a live card's own pip would lose the board.
func _source(rank: PipRank, suit: PipSuit) -> CardData:
	var source := CardData.new()
	source.with_rank(rank.duplicate_deep(Resource.DEEP_DUPLICATE_ALL) as PipRank)
	source.with_suit(suit.duplicate_deep(Resource.DEEP_DUPLICATE_ALL) as PipSuit)
	return source

func _another_suit(suit: PipSuit) -> PipSuit:
	var knife := PipSuitKnife.new()
	if not PipComparator.printed_same(suit, knife): return knife
	return PipSuitHoop.new()

func _another_rank(rank: PipRank) -> PipRank:
	var two : PipRank = PipRankNumeral.new().with_value(2)
	if not PipComparator.printed_same(rank, two): return two
	return PipRankNumeral.new().with_value(7)

# THROUGH THE PLATFORM'S OWN ROUTE, not `grab_cards`: what is photographed is what a player's
# pick-up produces, and the highlight is derived where that route ends.
func _pick_the_card_up(pa: PlayArea) -> void:
	await _input.click(_centre_of(pa, _held))
	print("[plan_match_shot] picked up: %d card(s) held" % pa.selected_cards.size())

# The landing, plus the FOCUS highlight left on the same cell: the activated rim has to stay
# tellable apart from the focus tint, and only one picture can show that.
func _land_the_card(g: Game, pa: PlayArea) -> void:
	await _input.click(_centre_of(pa, g.state.cell_type_at(_both_cell)))
	var waited := 0.0
	while waited < REVEAL_WATCHDOG and g.state.card_at(_both_cell) != _held:
		await get_tree().process_frame
		waited += get_process_delta_time()
	pa.flush_rebuild()
	await get_tree().process_frame
	print("[plan_match_shot] landed on (2,2): %s" % str(g.state.card_at(_both_cell) == _held))
#The FOCUS HIGHLIGHT put there the way a player puts it there -- the pointer resting on the cell is
#what the board reads as focus, and a bare `grab_focus` loses it to the next rebuild.
	await pa.await_card_settled(_held)
	await _settle_view_of(pa)
	await _input.move_to(_centre_of(pa, g.state.cell_type_at(_miss_cell)))
	await _input.move_to(_centre_of(pa, _held))
	await get_tree().process_frame
	await get_tree().process_frame

func _centre_of(pa: PlayArea, card: CardData) -> Vector2:
	return (pa.data_ui[card] as Control).get_global_rect().get_center()

# One picture plus the numbers behind it: how many cells lit and which elements each of the three
# cells is drawing, so a blank frame cannot pass for a capture.
func _shoot(view: GameView, tag: String) -> void:
	var pa := view.play_area
	var g := view.game
	var lit : PackedStringArray = PackedStringArray()
	for gi : int in g.state.grids.size():
		var count := 0
		for type_card : CardData in (g.state.grids[gi] as GridData).cell_types:
			var visual : CardVisual = pa.data_card.get(type_card)
			if visual and visual.matched_properties != 0: count += 1
		lit.append("grid %d: %d" % [gi, count])
	print("[plan_match_shot] %s: cells lit -- %s, board zoom %.3f"
			% [tag, ", ".join(lit), pa.board_zoom])
	for coord : BoardCoord in [_rank_cell, _both_cell, _miss_cell]:
		_report_cell(pa, g, coord, tag)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("%s/%s.png" % [_out_dir, tag])
	print("[plan_match_shot] wrote %s.png" % tag)

# What one cell is ACTUALLY drawing, read off the live materials: the rim ink and width of every
# element of the mark, and of the card standing on it when there is one.
func _report_cell(pa: PlayArea, g: Game, coord: BoardCoord, tag: String) -> void:
	var mark : CardData = g.state.cell_type_at(coord)
	var mark_visual : CardVisual = pa.data_card.get(mark)
	print("[plan_match_shot] %s (%d,%d) at %s mark %s: %s" % [tag, coord.x, coord.y,
			str(pa.slot_center_global(coord)), str(mark), _rims(mark_visual)])
	var played : CardData = g.state.card_at(coord)
	if not played: return
	var played_visual : CardVisual = pa.data_card.get(played)
	print("[plan_match_shot] %s (%d,%d) card %s: %s  modulate %s" % [tag, coord.x, coord.y,
			str(played), _rims(played_visual), str(played_visual.modulate)])

func _rims(visual: CardVisual) -> String:
	if not visual: return "no visual"
	var parts : PackedStringArray = PackedStringArray()
	for named : Array in [["rank", visual.rank], ["suit", visual.suit], ["art", visual.art],
			["stamp", visual.stamp], ["frame", visual.type]]:
		var mat := (named[1] as Polygon2D).material as ShaderMaterial
		parts.append("%s ink %s w %s" % [named[0], str(mat.get_shader_parameter(&"u_outline_index")),
				str(mat.get_shader_parameter(&"u_outline_width"))])
	return ", ".join(parts)

# A placed card FLIES to its cell and eases out of a tilt, so the board settling is not the card
# settling. TEN consecutive still frames, because a single still one is also what the frame before
# the flight starts looks like.
func _settle_view_of(pa: PlayArea) -> void:
	var last := Vector2(INF, INF)
	var stable := 0
	for _frame : int in 300:
		await get_tree().process_frame
		var visual : CardVisual = pa.data_card.get(_held)
		if not visual: return
		var now := visual.global_position
		stable = stable + 1 if now.is_equal_approx(last) else 0
		if stable >= 10: return
		last = now

# Waits until the board stops moving, so a shot is never taken mid-transition.
func _settle(view: GameView) -> void:
	var last := Vector2(INF, INF)
	for _frame : int in 180:
		await get_tree().process_frame
		var now := view.play_area.slot_center_global(BoardCoord.new(0, 0, 0, 0))
		if now.is_equal_approx(last): return
		last = now

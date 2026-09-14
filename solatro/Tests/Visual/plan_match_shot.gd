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
const SHIMMER_SAMPLES := 8

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

	_held = _an_entrance_card(g, pa, null)
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
	_park_the_shimmer(_landed_visual(view))
	await _shoot(view, "landed")
	var second := await _land_a_second_card(g, pa)
	await _input.move_to(_centre_of(pa, g.state.cell_type_at(_miss_cell)))
	await _probe_the_shimmer(view, second)

	TestGameViewHost.shot_teardown(SAVE_TAG)
	get_tree().quit()

# The card this shot picks up: one the board offers as a focus target in the Entrance, which is what
# a pointer or a focus ring can reach.
func _an_entrance_card(g: Game, pa: PlayArea, kept: CardData) -> CardData:
	for control : Control in pa.ui_data:
		var data : CardData = pa.ui_data[control]
		if data == kept: continue
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
	print("[plan_match_shot] landed on (2,2): %s" % str(await _place(g, pa, _held, _both_cell)))
#The FOCUS HIGHLIGHT put there the way a player puts it there -- the pointer resting on the cell is
#what the board reads as focus, and a bare `grab_focus` loses it to the next rebuild.
	await pa.await_card_settled(_held)
	await _settle_view_of(pa)
	await _input.move_to(_centre_of(pa, g.state.cell_type_at(_miss_cell)))
	await _input.move_to(_centre_of(pa, _held))
	await get_tree().process_frame
	await get_tree().process_frame

# A PLACEMENT THROUGH THE PLATFORM'S OWN ROUTE -- the card clicked, then the cell -- and whether the
# board took it. The card is picked up only if it is not already in hand.
func _place(g: Game, pa: PlayArea, card: CardData, coord: BoardCoord) -> bool:
	if not pa.selected_cards.has(card): await _input.click(_centre_of(pa, card))
	await _input.click(_centre_of(pa, g.state.cell_type_at(coord)))
	var waited := 0.0
	while waited < REVEAL_WATCHDOG and g.state.card_at(coord) != card:
		await get_tree().process_frame
		waited += get_process_delta_time()
	pa.flush_rebuild()
	await get_tree().process_frame
	return g.state.card_at(coord) == card

# A SECOND REALIZED CELL, landed MANY frames after the first: the shimmer's phase is board-wide, and
# two cards landed on one frame would agree even if it were not. Null when the board refuses it.
func _land_a_second_card(g: Game, pa: PlayArea) -> CardData:
	var second := _an_entrance_card(g, pa, _held)
	if not second:
		print("[plan_match_shot] shimmer: no second Entrance card to stage a second realized cell")
		return null
	g.effect_api.grant_mark(_rank_cell, _source(second.rank, second.suit))
	pa.flush_rebuild()
	await _settle_view_of(pa)
	var landed := await _place(g, pa, second, _rank_cell)
	print("[plan_match_shot] second card %s landed on (1,2): %s" % [str(second), str(landed)])
	if not landed: return null
	await pa.await_card_settled(second)
	await _settle_view_of(pa)
	return second

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
	var img := await _frame_image()
	img.save_png("%s/%s.png" % [_out_dir, tag])
	print("[plan_match_shot] wrote %s.png" % tag)

# The picture the viewport is actually showing, two frames on, so nothing is caught mid-draw.
func _frame_image() -> Image:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	return get_viewport().get_texture().get_image()

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

# `landed.png` IS PHASE 0, deliberately: the ramp opens on the ink the activated rim wears at rest,
# so the first picture is the one a DEAD shimmer would also produce. The probe below is the evidence.
# The phase parked is the BOARD'S -- every shimmering rim on it reads that one clock.
func _park_the_shimmer(visual: CardVisual) -> void:
	CardVisual._shimmer_clock = 0.0
	visual._push_alert_clock()

func _landed_visual(view: GameView) -> CardVisual:
	return view.play_area.data_card.get(view.game.state.card_at(_both_cell))

# THE MOVEMENT MEASUREMENT, because a still cannot settle a pulse: one rim pixel of the landed card's
# rank pip is read off the RENDER at evenly spaced moments of a single loop, beside a control pixel on
# an unmatched mark's rim, which must not move at all.
func _probe_the_shimmer(view: GameView, second: CardData) -> void:
	var visual := _landed_visual(view)
	var period : float = CardOutline.STYLE.shimmer_period_fraction * view.game.get_delay()
#THE CONTROL IS ANOTHER CARD'S RANK PIP, not another element of this one: the pips that shimmer sit
#inside this card's art box, so a control taken there measures them again and reads as movement.
	var still : CardVisual = view.play_area.data_card[view.game.state.cell_type_at(_miss_cell)]
	var control_box := _element_rect(still.rank)
	var lit := await _a_moving_pixel(visual, period, control_box, "the landed card")
	if lit.x < 0:
		print("[plan_match_shot] shimmer: nothing in the rank pip's box moved -- nothing to measure")
		return
	var plain := control_box.get_center()
	var mate : CardVisual = view.play_area.data_card.get(second)
	var mate_lit := Vector2i(-1, -1)
	if mate: mate_lit = await _a_moving_pixel(mate, period, control_box, "the second landed card")

	_park_the_shimmer(visual)
	var lit_seen : PackedStringArray = PackedStringArray()
	var control_seen : PackedStringArray = PackedStringArray()
	var moments : PackedStringArray = PackedStringArray()
	var together := 0
	for i : int in SHIMMER_SAMPLES:
		var img := await _frame_image()
		var now := img.get_pixel(lit.x, lit.y).to_html(false)
		var control := img.get_pixel(plain.x, plain.y).to_html(false)
		moments.append("%.2f turns #%s%s" % [CardVisual._shimmer_clock, now,
				_mate_moment(img, mate, mate_lit, now)])
		if mate_lit.x >= 0 and img.get_pixel(mate_lit.x, mate_lit.y).to_html(false) == now:
			together += 1
		if not lit_seen.has(now): lit_seen.append(now)
		if not control_seen.has(control): control_seen.append(control)
		if i == SHIMMER_SAMPLES / 2: img.save_png("%s/landed_phase.png" % _out_dir)
		await get_tree().create_timer(period / float(SHIMMER_SAMPLES)).timeout
	print("[plan_match_shot] shimmer: rank-pip rim pixel %s over one %.2fs loop -- %d distinct colours: #%s"
			% [lit, period, lit_seen.size(), ", #".join(lit_seen)])
	print("[plan_match_shot] shimmer: control pixel %s on an unmatched mark's pip -- %d distinct: #%s"
			% [plain, control_seen.size(), ", #".join(control_seen)])
	if mate_lit.x >= 0:
		print("[plan_match_shot] shimmer: TWO realized cells, landed a placement apart -- rim pixels "
				+ "%s and %s agree at %d of %d moments, phases %.4f and %.4f"
				% [lit, mate_lit, together, SHIMMER_SAMPLES, _pushed_phase(visual),
				_pushed_phase(mate)])
	print("[plan_match_shot] shimmer: moments -- %s" % ", ".join(moments))

# The second realized card's pixel at this moment, for the moment list. Empty when the board could
# not stage a second one, so the line still reads as the single-card probe it was.
func _mate_moment(img: Image, mate: CardVisual, at: Vector2i, lit: String) -> String:
	if not mate or at.x < 0: return ""
	var now := img.get_pixel(at.x, at.y).to_html(false)
	return " vs #%s %s" % [now, "same" if now == lit else "DIFFERS"]

# The phase this card's rank pip is actually carrying, which is the number behind the pixels.
func _pushed_phase(visual: CardVisual) -> float:
	var mat := visual.rank.material as ShaderMaterial
	var phase : float = mat.get_shader_parameter(&"u_alert_clock")
	return phase

# A pixel of the rank pip that MOVES between phase 0 and a quarter of a loop later, found by DIFFING
# two captures rather than by naming a colour: the focused card is drawn through a modulate, so what
# reaches the render is not the palette entry the rim was pushed. `control` is measured the same way.
func _a_moving_pixel(visual: CardVisual, period: float, control: Rect2i, who: String) -> Vector2i:
	_park_the_shimmer(visual)
	var at_rest := await _frame_image()
	await get_tree().create_timer(period * 0.25).timeout
	var later := await _frame_image()
	var moved := _pixels_that_moved(at_rest, later, _element_rect(visual.rank))
	print("[plan_match_shot] shimmer: over a quarter loop %d pixels of %s's rank pip box moved, "
			% [moved.size(), who] + "%d of the control box, which must not move at all"
			% _pixels_that_moved(at_rest, later, control).size())
	return moved[0] if not moved.is_empty() else Vector2i(-1, -1)

# One element's box in VIEWPORT pixels, which is the space a captured image is read in.
func _element_rect(poly: Polygon2D) -> Rect2i:
	var xf := poly.get_global_transform_with_canvas()
	var min_p : Vector2 = xf * poly.polygon[0]
	var max_p := min_p
	for i : int in range(1, poly.polygon.size()):
		var p : Vector2 = xf * poly.polygon[i]
		min_p = min_p.min(p)
		max_p = max_p.max(p)
	return Rect2i(Vector2i(min_p.floor()), Vector2i((max_p - min_p).ceil()))

# Every pixel of `rect` whose colour differs between the two captures. THE measurement: a static rim
# contributes none of them and a drifting one contributes its whole outline.
func _pixels_that_moved(before: Image, after: Image, rect: Rect2i) -> Array[Vector2i]:
	var out : Array[Vector2i] = []
	var box := rect.intersection(Rect2i(Vector2i.ZERO, before.get_size()))
	for y : int in range(box.position.y, box.end.y):
		for x : int in range(box.position.x, box.end.x):
			if before.get_pixel(x, y) != after.get_pixel(x, y): out.append(Vector2i(x, y))
	return out

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

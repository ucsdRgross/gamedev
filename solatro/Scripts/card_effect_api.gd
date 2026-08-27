class_name CardEffectApi
extends RefCounted
## THE ONE SEAM BETWEEN CARD EFFECTS AND THE GAME.
##
## Every card modifier implements its effect through this object and NEVER touches `Game` or
## `GameData` directly. One instance per `Game`, created by that game and handed to modifiers
## as `CardModifier.api`.
##
## ⚠ **READS GO THROUGH HERE TOO, not just writes.** The reason is resilience rather than
## purity: when a property moves or disappears from `Game`/`GameData`, this layer still answers
## — a wrapper returns a sensible empty value instead of every card breaking at once. That is
## why the accessors below guard rather than assume.
##
## ⚠ **Effects modify the DATA layer. The visual layer is optional on top of it.** There is
## deliberately no `view` accessor here: an effect that cannot run headless is wrong, and the
## only code that legitimately reaches the view is the card's own visual node, which is not a
## modifier and does not use this class.
##
## The surface is exactly what card effects actually use, and grows when an effect needs more —
## nothing here is speculative.

var _game : Game

func _init(game: Game) -> void:
	_game = game

## Is there a live game behind this layer at all? Preview contexts (deck viewers, boosters)
## have modifiers with no game, and every accessor below must survive that.
func is_live() -> bool:
	return _game != null and _game.state != null

# ==============================================================================
# BOARD READS
# ==============================================================================

## The grid list, left to right. Empty when there is no live game.
func grids() -> Array[GridData]:
	return _game.state.grids if is_live() else ([] as Array[GridData])

## The Entrance zone's columns.
func upper_zone() -> Array[ArrayCardData]:
	return _game.state.upper_zone if is_live() else ([] as Array[ArrayCardData])

## The lower (performed) zone's columns.
func lower_zone() -> Array[ArrayCardData]:
	return _game.state.lower_zone if is_live() else ([] as Array[ArrayCardData])

## The Entrance zone's header cards.
func upper_zone_type() -> Array[CardData]:
	return _game.state.upper_zone_type if is_live() else ([] as Array[CardData])

## The lower zone's header cards.
func lower_zone_type() -> Array[CardData]:
	return _game.state.lower_zone_type if is_live() else ([] as Array[CardData])

## The undealt deck.
func draw_deck() -> Array[CardData]:
	return _game.state.draw_deck if is_live() else ([] as Array[CardData])

## The board revision counter — the key every cache in the engine is invalidated by.
func revision() -> int:
	return _game.state.revision if is_live() else 0

## The show's running total.
func total_score() -> int:
	return _game.state.total_score if is_live() else 0

## The cards the scoring beam is on right now.
func forced_spotlight() -> Dictionary[CardData, bool]:
	return _game.state.forced_spotlight if is_live() else ({} as Dictionary[CardData, bool])

## A card's legacy board position, or `Vector3i.MIN` when it is not on the board.
func position_of(card: CardData) -> Vector3i:
	return _game.state.position_of(card) if is_live() else Vector3i.MIN

## A card's grid-board coordinate, or NOWHERE when it is not on a grid.
func grid_position_of(card: CardData) -> BoardCoord:
	return _game.state.grid_position_of(card) if is_live() else BoardCoord.NOWHERE

## The card at a grid coordinate, or null.
func card_at(coord: BoardCoord) -> CardData:
	return _game.state.card_at(coord) if is_live() else null

## Does this coordinate name a real cell of a real grid?
func has_cell(coord: BoardCoord) -> bool:
	return _game.state.has_cell(coord) if is_live() else false

# ==============================================================================
# BOARD QUERIES — geometry and legality, all pure reads
# ==============================================================================

## A card's board position as the legacy `(zone, col, row)` vector.
func find_data_vec3(data: CardData) -> Vector3i:
	return _game.find_data_vec3(data) if is_live() else Vector3i.MIN

## The zone columns a legacy position vector points into.
func get_zone_from_vec3(vec3: Vector3i) -> Array[ArrayCardData]:
	return _game.get_zone_from_vec3(vec3) if is_live() else ([] as Array[ArrayCardData])

## Is this card the top of its column?
func is_data_topmost(data: CardData) -> bool:
	return _game.is_data_topmost(data) if is_live() else false

## Every slot in a row, in the given direction.
func row_slot_path(v: Vector3i, left_to_right: bool) -> Array[Vector3i]:
	return _game.row_slot_path(v, left_to_right) if is_live() else ([] as Array[Vector3i])

## Every slot in a row starting from a coordinate, in the given direction.
func row_slot_path_from(coord: Vector3i, left_to_right: bool) -> Array[Vector3i]:
	return _game.row_slot_path_from(coord, left_to_right) if is_live() else ([] as Array[Vector3i])

## Every slot rising up a column from this one.
func column_rise_path(v: Vector3i) -> Array[Vector3i]:
	return _game.column_rise_path(v) if is_live() else ([] as Array[Vector3i])

## The slots a mancala-style sow would drop into.
func mancala_targets(v: Vector3i, count: int, eligible: Callable) -> Array[Vector3i]:
	return _game.mancala_targets(v, count, eligible) if is_live() else ([] as Array[Vector3i])

## Replay-stable 50/50 pick for a row's entity side.
func entity_side_for_row(v: Vector3i) -> bool:
	return _game.entity_side_for_row(v) if is_live() else false

# ==============================================================================
# MUTATION — the write paths. Every one of these goes through Game/Board so the
# mutation guidelines (consistent state first, one revision bump after) still hold.
# ==============================================================================

## Move a card to a legacy board coordinate.
func move_data_to_coord(moving: CardData, dest: Vector3i, cards_in_stack: int = 1,
		trigger_mods: bool = true) -> void:
	if not is_live(): return
	await _game.move_data_to_coord(moving, dest, cards_in_stack, trigger_mods)

## Send a card to the discard pile.
func discard_data(data: CardData) -> void:
	if not is_live(): return
	await _game.discard_data(data)

## Draw the next card from the deck, or null when it is empty.
func draw_card() -> CardData:
	return _game.draw_card() if is_live() else null

## Add to the show's running total.
func add_total_score(amount: int) -> void:
	if not is_live(): return
	_game.state.total_score += amount

## Bump the board revision. ⚠ Only after the state is fully consistent again — the mutation
## guidelines are not suspended by going through this layer.
func bump_revision() -> void:
	if not is_live(): return
	_game.state.revision += 1

## Take a card off the board entirely, without discarding it. Bumps revision once, after.
func remove_from_play(card: CardData) -> void:
	if not is_live(): return
	var vec3 := _game.find_data_vec3(card)
	if vec3 == Vector3i.MIN: return
	_game.get_zone_from_vec3(vec3)[vec3.y].datas.erase(card)
	_game.state.revision += 1

## Put a card back on top of the draw deck. Caller bumps when its whole batch is consistent.
func return_to_draw_deck(card: CardData) -> void:
	if not is_live(): return
	_game.state.draw_deck.append(card)

## Place a card that is not on the board into a zone column end.
func place_card(card: CardData, zone_x: int, col: int) -> bool:
	return Board.place_card(_game.state, card, zone_x, col) if is_live() else false

## Append a zone column and its header in lockstep.
func add_column(zone_cols: Array[ArrayCardData], zone_types: Array[CardData],
		header: CardData) -> void:
	if not is_live(): return
	Board.add_column(_game.state, zone_cols, zone_types, header)

## Remove a zone column and its header; returns the orphaned cards for the caller to discard.
func remove_column(zone_cols: Array[ArrayCardData], zone_types: Array[CardData],
		index: int) -> Array[CardData]:
	if not is_live(): return ([] as Array[CardData])
	return Board.remove_column(_game.state, zone_cols, zone_types, index)

## Append one grid to the board.
func add_grid(grid: GridData) -> void:
	if not is_live(): return
	Board.add_grid(_game.state, grid)

## Remove a grid; returns its orphaned cards for the caller to discard.
func remove_grid(index: int) -> Array[CardData]:
	if not is_live(): return ([] as Array[CardData])
	return Board.remove_grid(_game.state, index)

## The scoring section for one enumerated geometric line of a grid.
func section_of_line(grid: int, line: LineGeometry.Line) -> ScoringSection:
	return ScoringSection.of_geometric_line(_game.state, grid, line) if is_live() else null

# ==============================================================================
# SCORING
# ==============================================================================

## Score one line, built by the caller into a ScoringSection.
func score_line(result: Scoring.Result, section: ScoringSection) -> void:
	if not is_live(): return
	await _game.score_line(result, section)

## THE single line-score write path.
func add_line_score(section: ScoringSection, amount: int) -> void:
	if not is_live(): return
	_game.add_line_score(section, amount)

## Register a combo class. Returns true when it was new.
func register_combo(key: String) -> bool:
	return _game.register_combo(key) if is_live() else false

# ==============================================================================
# DISPATCH
# ==============================================================================

## Broadcast a hook to every modifier that implements it.
func run_all_mods(function: StringName, arg1: Variant = null, arg2: Variant = null) -> void:
	if not is_live(): return
	await _game.run_all_mods(function, arg1, arg2)

## Re-run one modifier's handler against a card — the re-trigger path.
func on_mod_triggered(triggered_data: CardData, triggered_mod: Callable) -> void:
	if not is_live(): return
	await _game.on_mod_triggered(triggered_data, triggered_mod)

# ==============================================================================
# THE ACT GUARD — correctness-critical. An effect that loops MUST check these.
# ==============================================================================

## The act tripped the runaway cap. A looping effect must stop when this is true.
func act_overrun() -> bool:
	return _game.act_overrun if is_live() else false

## The act is being unwound. Nothing further should score or mutate.
func act_cancelled() -> bool:
	return _game.act_cancelled if is_live() else false

# ==============================================================================
# PACING
# ==============================================================================

## The per-step pacing delay. Animation lengths are FRACTIONS of this, never wall-clock
## literals — and headless it compresses to nothing, which is what keeps effects runnable
## with no view attached.
func get_delay() -> float:
	return _game.get_delay() if is_live() else 0.0

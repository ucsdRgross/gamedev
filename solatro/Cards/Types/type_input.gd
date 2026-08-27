class_name TypeInput
extends CardModifierType
	
func get_str() -> String: return TRANSLATION.find('INPUT_ZONE_CARD')
func get_description() -> String: return TRANSLATION.find('INPUT_ZONE_CARD_DESCRIPTION')
func get_frame() -> int: return 2

## Engine zone-header machinery (§15a): the input row's on_next fires every act — never a
## combo class (would be a constant U baseline). Not in rules1, but same opt-out reasoning.
func combo_key(_hook: StringName = &"") -> String: return ""

func on_can_place_stack(stack: Array[CardData], target: CardData) -> Array[CardData]:
	if target != data: return []
	if not api or not api.is_live(): return []
	if api.is_data_topmost(target): return stack
	return []

## ⚠ SCAFFOLDING, NOT THE DESIGN. The design retires this handler outright: the Entrance
## refills from board state (below), never from a Next. It survives only because the LEGACY
## tableau deal — drop this header's column into the paired lower column, then draw — is what
## six suites still use to put cards on a board at all, and the tableau is not archived yet.
## Deleting it early leaves those suites with no board to test against.
## It is a no-op once there is no paired lower column, which is what the archive produces.
func on_next() -> void:
	await _legacy_drop_to_lower()
	await _maybe_refill()

## The legacy tableau drop. Goes with the tableau.
func _legacy_drop_to_lower() -> void:
	if not api or not api.is_live(): return
	var upper := api.upper_zone()
	var lower := api.lower_zone()
	var col : int = api.upper_zone_type().find(data)
	if col > -1 and col < upper.size() and col < lower.size() 			and upper[col].datas.size() > 0:
		await api.move_data_to_coord(upper[col].datas[0], Vector3i(1, col, -1), -1)

## Deals the initial hand: the Entrance starts empty, which is exactly the "empty" refill
## trigger, so game start reuses the same refill path as every later placement.
func on_game_start() -> void:
	await _maybe_refill()

## A card landed anywhere on the grid board -- possibly this header's own slot emptying out.
## Re-checks the refill trigger every time so the leftmost header (dispatched first, per the
## Entrance columns' left-to-right order) always draws before the next one.
func on_card_placed(_landed: BoardCoord) -> void:
	await _maybe_refill()

## Fills this header's OWN slot, left to right, when it is empty AND the refill trigger is
## met -- the Entrance is completely empty, or no held card has anywhere legal to go.
func _maybe_refill() -> void:
	if not api or not api.is_live(): return
	var col : int = api.upper_zone_type().find(data)
	if col == -1 or col >= api.upper_zone().size(): return
	if api.upper_zone()[col].datas.size() > 0: return
	if not await _refill_triggered(): return
	var drawn_card := api.draw_card()
	if drawn_card:
		api.place_card(drawn_card, 0, col)

## The Entrance is fully empty, or every held card has no legal placement anywhere on a grid.
func _refill_triggered() -> bool:
	if _entrance_is_empty(): return true
	return await _no_legal_move_remains()

func _entrance_is_empty() -> bool:
	for column : ArrayCardData in api.upper_zone():
		if column.datas.size() > 0: return false
	return true

## Walks every held card against every grid cell's current top card (or its empty-cell zone
## card) through the existing on_can_place_stack dispatch -- the same legality query
## try_place uses, never a second "is this legal" implementation.
func _no_legal_move_remains() -> bool:
	for column : ArrayCardData in api.upper_zone():
		if column.datas.is_empty(): continue
		var held : Array[CardData] = [column.datas.back()]
		for grid : GridData in api.grids():
			for i : int in grid.cells.size():
				var target : CardData = grid.cells[i].datas.back() \
						if grid.cells[i].datas.size() > 0 else grid.cell_types[i]
				if not (await api.can_place_stack(held, target)).is_empty():
					return false
	return true

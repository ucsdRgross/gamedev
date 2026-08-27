class_name SkillGridCreator
extends CardModifierSkill
## ZoneAdder-shaped, but for a whole grid rather than a zone column: `on_spotlight` builds a
## fresh grid, `on_unspotlight` removes it and discards its cards.

func get_str() -> String: return TRANSLATION.find('GRID_CREATOR_CARD')
func get_description() -> String: return TRANSLATION.find('GRID_CREATOR_CARD_DESCRIPTION')
func get_frame() -> int: return 12

## Engine rules machinery: never a combo class, mirroring every other rules-deck card.
func combo_key(_hook: StringName = &"") -> String: return ""

## The grid this card built, so `on_unspotlight` can find and remove exactly that one.
@export_storage var grid_data : GridData

## Builds a fresh grid at its own default size (GridData's own grid_width/grid_height).
func on_spotlight() -> void:
	if not api or not api.is_live(): return
	if not grid_data:
		grid_data = GridData.new()
	api.add_grid(grid_data)

## Removes the grid this card built and discards the cards it held.
func on_unspotlight() -> void:
	if not api or not api.is_live(): return
	var index := api.grids().find(grid_data)
	if index == -1:
		grid_data = null
		return
	for d : CardData in api.remove_grid(index):
		await api.discard_data(d)
	grid_data = null

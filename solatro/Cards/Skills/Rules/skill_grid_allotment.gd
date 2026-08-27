class_name SkillGridAllotment
extends CardModifierSkill

func get_str() -> String: return TRANSLATION.find('GRID_ALLOTMENT_CARD')
func get_description() -> String: return TRANSLATION.find('GRID_ALLOTMENT_CARD_DESCRIPTION')
func get_frame() -> int: return 11

## Engine rules machinery: never a combo class, a constant baseline every act like the other
## rules-deck cards.
func combo_key(_hook: StringName = &"") -> String: return ""

## The deck-size-to-grid-count formula. Evaluated once at game start, against the deck size at
## that moment: ceil(deck_size / grid_cards_per_unlock), floored at 1 grid, capped at
## grid_max_count. Integer ceiling division as (n + d - 1) / d is exact for GDScript's
## truncating `/` and avoids a float round-trip; d >= 1 is enforced by the setting's own setter.
static func target_grid_count(deck_size: int, cards_per_unlock: int, max_count: int) -> int:
	var d := maxi(cards_per_unlock, 1)
	var raw := (maxi(deck_size, 0) + d - 1) / d
	return clampi(maxi(raw, 1), 1, max_count)

## On game start, matches the actual grid count to the target computed from the deck just dealt
## (`Levels/game.gd.add_deck` runs before this hook). ⚠ Placeholder for the grid-creator card:
## no SkillGridCreator exists yet, so this syncs `state.grids` directly via Board.add_grid /
## Board.remove_grid rather than adding/removing a persistent creator card in the rules deck —
## a later step folds the actual building into that card's own on_spotlight/on_unspotlight and
## reduces this method to adding/removing the right number of them.
func on_game_start() -> void:
	if not game: return
	var settings := SettingsManager.settings
	var target := target_grid_count(game.state.draw_deck.size(), settings.grid_cards_per_unlock,
			settings.grid_max_count)
	while game.state.grids.size() < target:
		Board.add_grid(game.state, GridData.new())
	while game.state.grids.size() > target:
		for orphan : CardData in Board.remove_grid(game.state, game.state.grids.size() - 1):
			await game.discard_data(orphan)

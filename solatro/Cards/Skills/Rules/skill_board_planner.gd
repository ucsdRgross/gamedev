#The rules-deck card whose game-start hook deals the board's marks: one deal, across every grid
#that exists by then, from the same stock.
class_name SkillBoardPlanner
extends CardModifierSkill

func get_str() -> String: return TRANSLATION.find('BOARD_PLANNER_CARD')
func get_description() -> String: return TRANSLATION.find('BOARD_PLANNER_CARD_DESCRIPTION')
func get_frame() -> int: return 13

## Engine rules machinery: never a combo class, mirroring every other rules-deck card.
func combo_key(_hook: StringName = &"") -> String: return ""

#THE one deal. This card is last in the rules deck, so every grid the allotment's creators built
#exists by now and the Entrance has not refilled -- the deck is still whole. The SEED is stored,
#not the generator: the dealt marks persist, so no later path rolls these numbers again.
func on_game_start() -> void:
	if not api or not api.is_live(): return
	var state := api.board_state()
	state.plan_seed = api.plan_seed_for_node()
	var rng := RandomNumberGenerator.new()
	rng.seed = state.plan_seed
	BoardPlan.deal(state, rng)

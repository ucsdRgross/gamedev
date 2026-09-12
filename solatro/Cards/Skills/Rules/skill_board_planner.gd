#The rules-deck card whose game-start hook deals the board's marks: one deal, across every grid
#that exists by then, from the same stock.
class_name SkillBoardPlanner
extends CardModifierSkill

func get_str() -> String: return TRANSLATION.find('BOARD_PLANNER_CARD')
func get_description() -> String: return TRANSLATION.find('BOARD_PLANNER_CARD_DESCRIPTION')
func get_frame() -> int: return 13

## Engine rules machinery: never a combo class, mirroring every other rules-deck card.
func combo_key(_hook: StringName = &"") -> String: return ""

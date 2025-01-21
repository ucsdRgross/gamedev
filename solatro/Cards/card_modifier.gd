class_name CardModifier
extends Resource

enum Rarity {COMMON, UNCOMMON, RARE, LEGENDARY}
#class Skill:
@export var name : String
@export var description : String
@export var frame : int
@export var rarity : Rarity
@export var tags : Dictionary
var data : CardData
var game : Game

func with_data(data:CardData) -> CardModifier:
	self.data = data
	return self

func with_game(game:Game) -> CardModifier:
	self.game = game
	return self

func on_round_start() -> void:
	pass
func on_round_end() -> void:
	pass
#func on_card_enter_game(target:Card) -> void:
	#pass
#func on_card_leave_game(target:Card) -> void:
	#pass
func stack_rule(target:Card) -> bool:
	return false
func on_stack(target:Card) -> void:
	pass
func pickup_rule(target:Card) -> bool:
	return true
func on_pickup(target:Card) -> void:
	pass
func on_submit(target:Card) -> void:
	pass
func on_card_click(target:Card) -> void:
	pass
func on_skill_activated(target:Card) -> void:
	pass
func score_rule() -> void:
	pass
func on_score(target:Card) -> void:
	pass
func after_score() -> void:
	pass
func on_game_start() -> void:
	pass
func on_game_win() -> void:
	pass
func on_game_loss() -> void:
	pass
func on_game_end() -> void:
	pass
func on_deck_enter(target:Card) -> void:
	pass
func on_discard(target:Card) -> void:
	pass
func on_delete(target:Card) -> void:
	pass
func on_draw(target:Card) -> void:
	pass
func on_deck_shuffle() -> void:
	pass
	
func on_trigger(data:CardData, mod:Callable) -> void:
	pass	

func on_card_dropped_on(bot_card:CardData, top_card:CardData) -> void:
	pass

func is_active() -> bool:
	if data.card and not data.card.top_card:
		return true
	return false


func card_shake(card_effect:Callable) -> void:
	if data.card:
		await game.shake_card(data.card, card_effect)
		
func card_raise() -> void:
	if data.card:
		await game.card_raise(data.card)

func card_lower() -> void:
	if data.card:
		await game.card_lower(data.card)

func card_shrink() -> void:
	if data.card:
		await game.card_shrink(data.card)

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
	if data.stamp is StampGlobal:
		return true
	elif data.card:
		if not data.card.top_card:
			return true
		if data.stamp is StampRevealing:
			return true
	return false

func card_shake(card_effect:Callable) -> void:
	await card_raise()
	await card_effect.call()
	await card_lower()
		
func card_raise() -> void:
	await _do_popup(&"card_raise")

func card_lower() -> void:
	await _do_popup(&"card_lower")

func card_shrink() -> void:
	await _do_popup(&"card_shrink")

func _do_popup(method:StringName) -> void:
	var popup_card : Card
	var temp_card := false
	if data.card:
		popup_card = data.card
	elif method == &"card_raise":
		match data.stage:
			data.Stage.DRAW:
				popup_card = game.deck_popup
			data.Stage.DISCARD:
				popup_card = game.discard_popup
		if not popup_card:
			return
		var new_popup_card := popup_card.duplicate(8)
		popup_card.get_parent().add_child(new_popup_card)
		popup_card = new_popup_card
		popup_card.data = data
		temp_card = true
		popup_card.flipped = !popup_card.flipped
		popup_card.show()
	else:
		return
	await Callable(game, method).call(popup_card)
	if temp_card:
		await Callable(game, &"card_lower").call(popup_card)
		popup_card.queue_free()
			

class_name SkillHungryHippo
extends CardModifier

func _init() -> void:
	name = "Hungry Hippo"
	description = "Will consume cards clicked over it and add its rank to itself, up until total value would be higher than 13"
	frame = 54

@export_storage var consumed_cards : Array[CardData]
func on_card_dropped_on(bot_card:CardData, top_card:CardData) -> void:
	if self.data.card:
		if self.data == bot_card and bot_card.card and bot_card.card.top_card \
				and bot_card.card.top_card.data == top_card:
			if bot_card.rank + top_card.rank <= 13:
				await card_shake(eat_card.bind(top_card))

func eat_card(ate_data:CardData) -> void:
	consumed_cards.append(ate_data)
	await game.card_shrink(ate_data.card)
	self.data.card.top_card = null
	ate_data.card.queue_free()
	self.data.rank += ate_data.rank
	game.total_score += ate_data.rank

func on_game_end() -> void:
	for card in consumed_cards:
		self.data.rank -= card.rank
		game.draw_deck.append(card)
	consumed_cards.clear()

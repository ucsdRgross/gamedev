class_name SkillHungryHippo
extends CardModifier

func _init() -> void:
	name = "Hungry Hippo"
	description = "Will consume cards clicked over it and add its rank to itself, up until total value would be higher than 13"
	frame = 54

var consumed_cards : Array[CardData]
func on_card_dropped_on(bot_card:CardData, top_card:CardData) -> void:
	if self.data.card:
		if self.data == bot_card and bot_card.card and bot_card.card.top_card \
				and bot_card.card.top_card.data == top_card:
			if bot_card.rank is PipRank.Numeral and top_card.rank is PipRank.Numeral:
				if bot_card.rank.value + top_card.rank.value <= 13:
					await card_shake(eat_card.bind(top_card))

func eat_card(ate_data:CardData) -> void:
	consumed_cards.append(ate_data)
	if Game.CURRENT: await Game.CURRENT.card_shrink(ate_data.card)
	self.data.card.top_card = null
	ate_data.card.queue_free()
	self.data.rank.value += ate_data.rank.value
	if Game.CURRENT: Game.CURRENT.total_score += ate_data.rank.value

# Oh boy this needs to handle all PipRank Types
func on_game_end() -> void:
	for card in consumed_cards:
		self.data.rank.value -= card.rank.value
		if Game.CURRENT: Game.CURRENT.draw_deck.append(card)
	consumed_cards.clear()

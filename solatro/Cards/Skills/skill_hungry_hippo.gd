class_name SkillHungryHippo
extends CardModifierSkill

func get_str() -> String: return "Hungry Hippo"
func get_description() -> String: return "Will consume cards clicked over it and add its rank to itself, up until total value would be higher than 13"
func get_frame() -> int: return 2

var consumed_cards : Array[CardData]
func on_card_dropped_on(bot_card:CardData, top_card:CardData) -> void:
	pass
	#if self.data.card:
		#if self.data == bot_card and bot_card.card and bot_card.card.top_card \
				#and bot_card.card.top_card.data == top_card:
			#if bot_card.rank is PipRankNumeral and top_card.rank is PipRankNumeral:
				#if bot_card.rank.value + top_card.rank.value <= 13:
					#pass
					##await card_shake(eat_card.bind(top_card))

func eat_card(ate_data:CardData) -> void:
	#if CardEnvironment.CURRENT: await CardEnvironment.CURRENT.card_shrink(ate_data.card)
	#self.data.card.top_card = null
	#ate_data.card.queue_free()
	# Take the eaten card OFF the board state entirely (same erase path as discard_data),
	# otherwise it would live both on the board and in consumed_cards (I1 violation) and
	# get double-added back at game end. Stage.DATA = held as data only, in no collection.
	if game:
		var vec3 : Vector3i = game.find_data_vec3(ate_data)
		if vec3 != Vector3i.MIN and vec3.z > -1:
			game.get_zone_from_vec3(vec3)[vec3.y].datas.erase(ate_data)
	consumed_cards.append(ate_data)
	ate_data.stage = CardData.Stage.DATA
	self.data.rank.value += ate_data.rank.value
	if not game: return
	game.state.total_score += ate_data.rank.value
	game.state.revision += 1  # AFTER the state is consistent (MUTATION GUIDELINES)

# Oh boy this needs to handle all PipRank Types
func on_game_end() -> void:
	if consumed_cards.is_empty(): return
	for card in consumed_cards:
		self.data.rank.value -= card.rank.value
		card.stage = CardData.Stage.DRAW
		if game: game.state.draw_deck.append(card)
	consumed_cards.clear()
	if game: game.state.revision += 1  # AFTER the state is consistent

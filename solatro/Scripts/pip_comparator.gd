class_name PipComparator
# Checks card pips against each other 

# 1. Before running default comparisons, checks all card effects first
# 2. Checks all cards for if comparison is blacklisted by an effect effect first
# 3. Then checks all cards again for if comparison is whitelisted
# In both cases first effect that returns true determines determines the comparison result

#func can_add_card(stack : Card, to_stack : Card) -> bool:
	#
	#if stack.top_card == to_stack and to_stack == held_card:
		#return true
	#if true: #not stack.top_card:
		#if true:#stack.stack_limit < 0 or (stack.stack_limit >= to_stack.get_stack_size()):
			#if stack.is_zone:
				#return true
			#if stack.data.suit.value != to_stack.data.suit.value:
				#if to_stack.data.rank.value == stack.data.rank - 1:
					#return true
				#if to_stack.data.rank == stack.data.rank + 1:
					#return true
	#return false
#
#func can_pickup_stack(stack : Card, to_stack : Card) -> bool:
	##return true
	#if stack.is_zone:
		#return true
	#if stack.data.suit != to_stack.data.suit:
		#if to_stack.data.rank == stack.data.rank - 1:
			#return true
		#if to_stack.data.rank == stack.data.rank + 1:
			#return true
	#return false

# use Game.CURRENT.run_all_mods
#
#func run_all_mods(function: StringName, params:Array=[]) -> void:
	#for data in CardDataIterator.new():
		#for mod : CardModifier in [data.type, data.stamp, data.skill]:
			#if mod:
				#await Callable(mod, function).callv(params)
#
#func on_mod_triggered(triggered_data:CardData, triggered_mod:Callable) -> void:
	#await run_all_mods(&"on_trigger", [triggered_data, triggered_mod])

@abstract
class_name CardEnvironment
extends Node

static var CURRENT : CardEnvironment = null

static func get_current_game() -> Game:
	if CURRENT is Game: return CURRENT
	return null

func _enter_tree() -> void:
	CURRENT = self

func _exit_tree() -> void:
	if CURRENT == self:
		CURRENT = null

func get_delay() -> float:
	return SettingsManager.settings.base_delay

func get_card_collections() -> Array[Variant]:
	return []

func get_rules_collections() -> Array[CardData]:
	return []

func is_data_in_rules(data: CardData) -> bool:
	return data in get_rules_collections()

#Dispatch is INSTANCE-based: each environment runs mods over its own collections.
#CURRENT is only the "environment on screen" pointer used at the boundaries
#(CardModifier.env/game accessors, PipComparator, UI) — not inside dispatch.
func run_all_mods(function: StringName, ...params:Array) -> void:
	#print(function)
	for data in CardDataIterator.new(self):
		#print(data)
		for mod : CardModifier in [data.type, data.stamp]:
			if mod and mod.has_method(function):
				await Callable(mod, function).callv(params)
				await skill_active_check()
		var skill : CardModifierSkill = data.skill
		if skill and skill.has_method(function) and skill.active:
			await Callable(skill, function).callv(params)
			await skill_active_check()
	var passive_effects := &"on_anything"
	if function != passive_effects:
		await run_all_mods(passive_effects)

func return_first_compare_mod_result(function: StringName, ...params:Array) -> float:
	for data in CardDataIterator.new(self):
		for mod : CardModifier in [data.type, data.stamp]:
			if mod and mod.has_method(function):
				return await Callable(mod, function).callv(params)
		var skill : CardModifierSkill = data.skill
		if skill and skill.has_method(function) and skill.active:
			return await Callable(skill, function).callv(params)
	return NAN

func return_first_data_array_result(function: StringName, ...params:Array) -> Array[CardData]:
	for data in CardDataIterator.new(self):
		for mod : CardModifier in [data.type, data.stamp]:
			if mod and mod.has_method(function):
				var result : Array[CardData] = await Callable(mod, function).callv(params)
				if result: return result
		var skill : CardModifierSkill = data.skill
		if skill and skill.has_method(function) and skill.active:
			var result : Array[CardData] = await Callable(skill, function).callv(params)
			if result: return result
	return []

func skill_active_check() -> void:
	for data in CardDataIterator.new(self):
		var skill : CardModifierSkill = data.skill
		if skill:
			if not skill.active and skill.is_active():
				skill.active = true
				if skill.has_method(&"on_active"):
					await Callable(skill, &"on_active").call()
			elif skill.active and not skill.is_active():
				skill.active = false
				if skill.has_method(&"on_deactive"):
					await Callable(skill, &"on_deactive").call()

func on_mod_triggered(triggered_data:CardData, triggered_mod:Callable) -> void:
	#loose varargs: wrapping in [..] would deliver ONE Array arg to on_trigger(data, mod)
	await run_all_mods(&"on_trigger", triggered_data, triggered_mod)

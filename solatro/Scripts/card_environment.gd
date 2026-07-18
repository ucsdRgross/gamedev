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

## Elapsed-processing accounting hook: Game overrides this to feed the runaway event cap
## (one call per mod invoked + per prop slot entry). No-op in base environments (map, tests).
func note_processing(_weight := 1) -> void:
	pass

## Hook: a mod handler actually ran for `function`. Game overrides to feed the act
## combo (SCORING_MATH_PLAN §15a mod-activation U). No-op in base environments.
func _note_mod_fired(_mod: CardModifier, _function: StringName) -> void:
	pass

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
	var triggered := false
	# P1 gate: on a cacheable environment (Game — _revision_key non-empty) consult the SE1
	# implementer cache first; when NOTHING on the board implements this hook the walk is a
	# pure no-op scan, so skip it. Base envs (tests, map) return an empty key and always
	# walk — building the list uncached would itself cost the walk being saved.
	if _revision_key().is_empty() or not _compare_implementers(function).is_empty():
		for data in CardDataIterator.new(self):
			#print(data)
			# statuses join type/stamp as a SNAPSHOT copy (append_array) so a status removing
			# itself mid-hook can't corrupt this walk. Statuses self-scope targeted hooks.
			var mods : Array[CardModifier] = [data.type, data.stamp]
			mods.append_array(data.statuses)
			for mod : CardModifier in mods:
				if mod and mod.has_method(function):
					triggered = true
					note_processing()
					await Callable(mod, function).callv(params)
					_note_mod_fired(mod, function)
					await skill_active_check()
			var skill : CardModifierSkill = data.skill
			if skill and skill.has_method(function) and skill.active:
				triggered = true
				note_processing()
				await Callable(skill, function).callv(params)
				_note_mod_fired(skill, function)
				await skill_active_check()
	# P1 owner ruling (2026-07-16): the passive on_anything tail only runs when this event
	# actually invoked a mod — if nothing ran, nothing could have changed.
	if triggered and function != &"on_anything":
		await run_all_mods(&"on_anything")

#SE1: comparators run per card-compare, so the "which mods implement this hook" walk
#is cached while the board hasn't mutated. Skills stay in the list regardless of
#`active` and are gate-checked at use time (the active flag flips without a mutation).
var _compare_cache : Dictionary[StringName, Array] = {}
var _compare_cache_key : Array = []

## Base environments (tests, map) are uncacheable: their collections mutate freely.
## Game overrides this with [state id, state.revision].
func _revision_key() -> Array:
	return []

func _compare_implementers(function: StringName) -> Array:
	var key := _revision_key()
	if key:
		if key != _compare_cache_key:
			_compare_cache.clear()
			_compare_cache_key = key
		if _compare_cache.has(function):
			return _compare_cache[function]
	var impl : Array[CardModifier] = []
	for data in CardDataIterator.new(self):
		var mods : Array[CardModifier] = [data.type, data.stamp]
		mods.append_array(data.statuses)
		for mod : CardModifier in mods:
			if mod and mod.has_method(function): impl.append(mod)
		if data.skill and data.skill.has_method(function): impl.append(data.skill)
	if key:
		_compare_cache[function] = impl
	return impl

func return_first_compare_mod_result(function: StringName, ...params:Array) -> float:
	for mod : CardModifier in _compare_implementers(function):
		if mod is CardModifierSkill and not (mod as CardModifierSkill).active: continue
		return await Callable(mod, function).callv(params)
	return NAN

func return_first_data_array_result(function: StringName, ...params:Array) -> Array[CardData]:
	for data in CardDataIterator.new(self):
		var mods : Array[CardModifier] = [data.type, data.stamp]
		mods.append_array(data.statuses)
		for mod : CardModifier in mods:
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

## Run `function` on ONE card's own modifiers — type, stamp, suit, a statuses snapshot, then
## the active skill. The ONLY dispatch that sees suits; the board-wide run_all_mods iterator
## stays suit-free. Used by the prop tick loop's 3-phase pass (on_prop_passing/passed).
## Cost: O(mods on this card). Statuses are appended as a copy (safe if one self-removes).
func run_card_mods(card: CardData, function: StringName, ...params: Array) -> void:
	var mods : Array[CardModifier] = [card.type, card.stamp, card.suit]
	mods.append_array(card.statuses)
	for mod : CardModifier in mods:
		if mod and mod.has_method(function):
			note_processing()
			await Callable(mod, function).callv(params)
	var skill : CardModifierSkill = card.skill
	if skill and skill.active and skill.has_method(function):
		note_processing()
		await Callable(skill, function).callv(params)

func on_mod_triggered(triggered_data:CardData, triggered_mod:Callable) -> void:
	#loose varargs: wrapping in [..] would deliver ONE Array arg to on_trigger(data, mod)
	await run_all_mods(&"on_trigger", triggered_data, triggered_mod)

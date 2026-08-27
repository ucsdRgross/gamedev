@abstract
class_name CardEnvironment
extends Node

## One or more cards just TRANSITIONED into the spotlight (design chart T, `Q149`=b): the
## momentary activation cue. Fire-and-forget — phase 1 wires the seam, the light layer draws it.
## ⚠ Emitted once per `skill_spotlight_check()` sweep that saw any transition, carrying every
## card that transitioned in it (`Q247`=a: one cue covering all of them, not one per card), and
## only for cards whose skill implements `on_spotlight` (`Q246`=a — anything else has nothing to
## announce). A card that was ALREADY spotlit never appears here (`Q13`, `Q15`), which is also
## why loading a save emits nothing: `spotlit` is `@export_storage`, so a card saved spotlit
## loads spotlit and transitions nothing (`Q248`=b — no suppression code, the case cannot arise).
signal spotlight_cued(cards: Array[CardData])

## THE SCORING BEAM'S MEMBERSHIP: every card in the section being scored right now, or EMPTY when
## the act releases (design `Q16`=c, chart E, chart H/I; plan step S14). Emitted by
## `Game._spotlight_section()` as each section takes the light, and once more empty from
## `Game._release_spotlight()`.
##
## ⚠ **THIS IS NOT `spotlight_cued`, AND CONFLATING THE TWO IS GAP-005.** They answer different
## questions and the difference is not cosmetic:
##
##   * `spotlight_cued` — *which cards have a TALENT to announce.* Correctly filtered by `Q246`=(a)
##     to skills implementing `on_spotlight`, because a card with nothing to show should not flash.
##   * `spotlight_section_changed` — *which cards are BEING SCORED.* Filtered by nothing: a scored
##     row is mostly plain numeral cards with no skill at all, and the beam lights the row.
##
## ⚠ Drawing the beam from the cue instead makes it **invisible in the running game while every
## test passes** — no shipped board-stage skill implements `on_spotlight`, but the test fixture does
## (`design/spotlight/gaps/GAP-005.md`).
##
## ⚠ **THE SET REPLACES, IT DOES NOT ACCUMULATE** — `Q16`=(c)'s travelling light. An empty array is
## what retires the light and lowers the dim (`QR2`=d); there is deliberately no separate "stop"
## signal, because a second way to lower the dim can disagree with the light set.
signal spotlight_section_changed(cards: Array[CardData])

## The section's REVEAL is over and its scoring is about to happen — the beat where the spotlight and
## the dim fade out (owner, GAP-006):
##
## > *"spotlight + dim occurs as cards of section get revealed, with both spotlight and dim effect
## > fading away as scoring starts to happen. When next section is revealed, spotlight and dim effect
## > are visible again, moving to new location, then fade away again."*
##
## ⚠ **THE LIGHTS ARE NOT RETIRED BY THIS — ONLY HIDDEN.** `spotlight_section_changed` owns the light
## SET; this owns its VISIBILITY. Keeping the set alive across the fade is what lets the next section
## TRAVEL from these positions rather than respawn at new ones, which chart E forbids outright
## (*"no instant movements or spawning in and out"*).
signal spotlight_reveal_ended()

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
## combo (SCORING_MATH_PLAN §15a mod-activation U). No-op in base
## environments. ⚠️ Fired from EVERY dispatch path (run_all_mods, return_first_*, run_card_mods),
## which is what makes it the one place that sees the whole mod firing order for the event log.
## `feeds_combo` keeps scoring untouched: only the run_all_mods path may register a combo class,
## so the other paths (comparators, legality queries, the prop tick's per-card hooks) are
## LOGGED but never scored.
func _note_mod_fired(_mod: CardModifier, _function: StringName,
		_feeds_combo := true) -> void:
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
					await skill_spotlight_check()
			var skill : CardModifierSkill = data.skill
			if skill and skill.has_method(function) and skill.spotlit:
				triggered = true
				note_processing()
				await Callable(skill, function).callv(params)
				_note_mod_fired(skill, function)
				await skill_spotlight_check()
	# P1 owner ruling: the passive on_anything tail only runs when this event
	# actually invoked a mod — if nothing ran, nothing could have changed.
	if triggered and function != &"on_anything":
		await run_all_mods(&"on_anything")

#SE1: comparators run per card-compare, so the "which mods implement this hook" walk
#is cached while the board hasn't mutated. Skills stay in the list regardless of
#`spotlit` and are gate-checked at use time (the spotlit flag flips without a mutation).
var _compare_cache : Dictionary[StringName, Array] = {}
var _compare_cache_key : Array = []

## Base environments (tests, map) are uncacheable: their collections mutate freely.
## Game overrides this with [state id, state.revision].
func _revision_key() -> Array:
	return []

# TODO(non-card rule sources, QR7=a / comparator_buckets DEFERRED.md D3): The Fire Marshal is a
# TOWN HAZARD — a modifier with no board card to live on — and this walk only ever visits
# `CardDataIterator`, i.e. board and rules cards. It needs a run-level modifier list the iterator
# also visits, plus a ruling on whether undo rewinds it (design Q69, Q70, both written and unasked).
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
		if mod is CardModifierSkill and not (mod as CardModifierSkill).spotlit: continue
		var result : float = await Callable(mod, function).callv(params)
		_note_mod_fired(mod, function, false)
		return result
	return NAN

# ==============================================================================
# THE COMPARATOR SURFACE'S DISPATCH (comparator_buckets DESIGN charts D and I)
# ⚠ The verdict cache is NOT here: it lives on PipComparator and is scoped to the scoring pass
# (owner ruling, gaps/GAP-003.md). The SE1 implementer cache below is a different question with
# a different lifetime — "does anything implement this hook", not "what did it answer".
# ==============================================================================

## Shared empty result, so the overwhelmingly common "nothing implements this" answer costs no
## allocation on a path asked once per pair per pass. ⚠ Never mutate it.
const _NO_IMPLEMENTERS : Array[CardModifier] = []

## Every implementer of `hook` that may act right now: board order (Q10=a), unspotlit skills
## dropped (Q5=a). ⚠ The ONE walk every helper below shares — the spotlit gate lived in four
## copies before. A rule applies whether or not its own card is in the hand (Q18=a).
func active_implementers(hook: StringName) -> Array[CardModifier]:
	var all := _compare_implementers(hook)
	if all.is_empty(): return _NO_IMPLEMENTERS
	var out : Array[CardModifier] = []
	for mod : CardModifier in all:
		if mod is CardModifierSkill and not (mod as CardModifierSkill).spotlit: continue
		out.append(mod)
	return out

## ⚠ **HOIST OUT OF PER-CARD AND PER-ITERATION LOOPS.** A dictionary lookup on Game, but base
## environments (tests, map) return an empty revision key, so `_compare_implementers` caches
## nothing and WALKS EVERY BOARD CARD.
func has_implementer(hook: StringName) -> bool:
	return not _compare_implementers(hook).is_empty()

## C3/C4: does either pass of this situation have an implementer? When no, profiling takes the
## identity path — zero dispatches, byte-identical to the buckets this replaced.
func any_pair_implementer(deny: StringName, allow: StringName) -> bool:
	return has_implementer(deny) or has_implementer(allow)

## First implementer wins, answer returned verbatim; null when nothing implements `hook`.
## The Q84 shape for hooks whose answer is not a boolean pass — the wrap bounds.
func return_first_mod_variant(hook: StringName, ...params: Array) -> Variant:
	for mod : CardModifier in active_implementers(hook):
		var result : Variant = await Callable(mod, hook).callv(params)
		_note_mod_fired(mod, hook, false)
		return result
	return null

## EVERY implementer's answer — for hooks whose answers COMPOSE rather than take precedence.
## Extra rank values are class MEMBERSHIPS, not a scalar verdict, so a second card offering
## another value must not be silenced by the first.
func collect_mod_results(hook: StringName, ...params: Array) -> Array:
	var out : Array = []
	for mod : CardModifier in active_implementers(hook):
		out.append(await Callable(mod, hook).callv(params))
		_note_mod_fired(mod, hook, false)
	return out

## Q89(b): is this CardData somewhere in this environment's collections? THE check that lets a
## grouping rule PULL a board card into a meld while refusing to let it INVENT one — the refusal
## that keeps multiplicity (QR5=a, DEFERRED D1) out of scope rather than reachable sideways.
func has_card_data(data: CardData) -> bool:
	if not data: return false
	for d in CardDataIterator.new(self):
		if d == data: return true
	return false

## ONE pass of the two-pass sameness question (PLAN §1.2): the FIRST true answers and STOPS the
## pass, so later rules are never asked.
## ⚠ Raw dispatch — callers go through `PipComparator.ask_pass`, which memoises for the hand.
func return_first_true_pair_result(hook: StringName, a: Variant, b: Variant) -> bool:
	for mod : CardModifier in active_implementers(hook):
		var verdict : bool = await Callable(mod, hook).call(a, b)
		_note_mod_fired(mod, hook, false)
		if verdict: return true
	return false


func return_first_data_array_result(function: StringName, ...params:Array) -> Array[CardData]:
	for data in CardDataIterator.new(self):
		var mods : Array[CardModifier] = [data.type, data.stamp]
		mods.append_array(data.statuses)
		for mod : CardModifier in mods:
			if mod and mod.has_method(function):
				var result : Array[CardData] = await Callable(mod, function).callv(params)
				_note_mod_fired(mod, function, false)
				if result: return result
		var skill : CardModifierSkill = data.skill
		if skill and skill.has_method(function) and skill.spotlit:
			var result : Array[CardData] = await Callable(skill, function).callv(params)
			_note_mod_fired(skill, function, false)
			if result: return result
	return []

## THE activation sweep (design chart B). Walks every card and reconciles the cached `spotlit`
## flag with the live rule, firing `on_spotlight` / `on_unspotlight` on the EDGE only — a card
## that was already spotlit is not re-announced (Q13, Q15).
func skill_spotlight_check() -> void:
	# The momentary cue (design chart T, S10): every card that transitioned to spotlit during
	# THIS sweep and has something to announce. Q247=a — ONE cue covering all of them, so it is
	# collected across the walk and emitted once at the end, not per card.
	var cued : Array[CardData] = []
	for data in CardDataIterator.new(self):
		var skill : CardModifierSkill = data.skill
		if skill:
			if not skill.spotlit and skill.is_spotlit():
				skill.spotlit = true
				if skill.has_method(&"on_spotlight"):
					# Q246=a: only a skill with an on_spotlight hook has anything to show.
					cued.append(data)
					await Callable(skill, &"on_spotlight").call()
			elif skill.spotlit and not skill.is_spotlit():
				skill.spotlit = false
				if skill.has_method(&"on_unspotlight"):
					await Callable(skill, &"on_unspotlight").call()
	if cued:
		spotlight_cued.emit(cued)

## Run `function` on ONE card's own modifiers — type, stamp, suit, a statuses snapshot, then
## the spotlit skill. The ONLY dispatch that sees suits; the board-wide run_all_mods iterator
## stays suit-free. Used by the prop tick loop's 3-phase pass (on_prop_passing/passed).
## Cost: O(mods on this card). Statuses are appended as a copy (safe if one self-removes).
func run_card_mods(card: CardData, function: StringName, ...params: Array) -> void:
	var mods : Array[CardModifier] = [card.type, card.stamp, card.suit]
	mods.append_array(card.statuses)
	for mod : CardModifier in mods:
		if mod and mod.has_method(function):
			note_processing()
			await Callable(mod, function).callv(params)
			_note_mod_fired(mod, function, false)
	var skill : CardModifierSkill = card.skill
	if skill and skill.spotlit and skill.has_method(function):
		note_processing()
		await Callable(skill, function).callv(params)
		_note_mod_fired(skill, function, false)

func on_mod_triggered(triggered_data:CardData, triggered_mod:Callable) -> void:
	#loose varargs: wrapping in [..] would deliver ONE Array arg to on_trigger(data, mod)
	await run_all_mods(&"on_trigger", triggered_data, triggered_mod)

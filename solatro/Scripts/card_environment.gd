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
func note_processing(_weight := 1, _key := "") -> void:
	pass

#⚠ A MOD HANDLER RAN, AND EVERY DISPATCH PATH FIRES THIS -- the one place that sees the whole mod
#firing order for the event log. The flags keep scoring untouched: a question is LOGGED and never
#scored, a broadcast is worth a combo class only inside an act, an activation always is.
func _note_mod_fired(_mod: CardModifier, _function: StringName,
		_feeds_act_combo := true, _counts_as_activation := false) -> void:
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

#⚠ A MARK IS A CELL WEARING A COPIED FACE, AND THE FACE IS NOT ON THE BOARD: its rank, suit, stamp
#and skill answer the two mark hooks and nothing else, while the cell's own type goes on ruling its
#square. THE exclusion, written once -- every board-wide walk below takes its modifiers from here.

#Statuses join type and stamp as a SNAPSHOT copy, so a status removing itself mid-hook cannot
#corrupt the walk asking it, and the skill comes last because that is the order a card is asked in.
func _dispatch_mods(data: CardData) -> Array[CardModifier]:
	var mods : Array[CardModifier] = [data.type]
	if BoardPlan.is_marked(data): return mods
	mods.append(data.stamp)
	mods.append_array(data.statuses)
	if data.skill: mods.append(data.skill)
	return mods

#⚠ THE P1 GATE: on a cacheable environment (Game) a hook nothing on the board implements makes the
#walk a pure no-op scan, so it is skipped. Base envs (tests, map) carry no revision key and always
#walk -- building the implementer list uncached would itself cost the walk it saves.

#The passive on_anything tail runs only where this event actually invoked a mod (owner ruling): if
#nothing ran, nothing could have changed.
func run_all_mods(function: StringName, ...params:Array) -> void:
	var triggered := false
	if _revision_key().is_empty() or not _compare_implementers(function).is_empty():
		for data in CardDataIterator.new(self):
			for mod : CardModifier in _dispatch_mods(data):
				if not mod or not mod.has_method(function): continue
				if mod is CardModifierSkill and not (mod as CardModifierSkill).spotlit: continue
				triggered = true
				note_processing(1, "%d:%s" % [mod.get_instance_id(), function])
				await Callable(mod, function).callv(params)
				_note_mod_fired(mod, function)
				await skill_spotlight_check()
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
		for mod : CardModifier in _dispatch_mods(data):
			if mod and mod.has_method(function): impl.append(mod)
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

#⚠ A MARK ANSWERS FALSE: a marked cell is a square wearing a copied face and never a card in play,
#so a grouping rule cannot pull one into a meld to score it. The modifier half of the same rule is
#`_dispatch_mods`; the meaning of "marked" is `BoardPlan`'s, so neither spells it for itself.

## Q89(b): is this CardData somewhere in this environment's collections? THE check that lets a
## grouping rule PULL a board card into a meld while refusing to let it INVENT one — the refusal
## that keeps multiplicity (QR5=a, DEFERRED D1) out of scope rather than reachable sideways.
func has_card_data(data: CardData) -> bool:
	if not data or BoardPlan.is_marked(data): return false
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
		for mod : CardModifier in _dispatch_mods(data):
			if not mod or not mod.has_method(function): continue
			if mod is CardModifierSkill and not (mod as CardModifierSkill).spotlit: continue
			var result : Array[CardData] = await Callable(mod, function).callv(params)
			_note_mod_fired(mod, function, false)
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

#THE ONLY dispatch that sees suits -- the board-wide run_all_mods iterator stays suit-free. The prop
#tick's 3-phase pass asks rather than fires, so this path charges no processing.
## Run `function` on ONE card's own modifiers, the spotlit skill included.
func run_card_mods(card: CardData, function: StringName, ...params: Array) -> void:
	await _run_own_mods(card, function, params, card.skill != null and card.skill.spotlit, false)

#One hook, two recipients: a MARK's copied modifiers and the card that covered it. A mark's skill is
#carried in (never spotlit, so the gate would silence it); a real card keeps the spotlight rule.
## Run a mark hook on one card's own modifiers — an EFFECT firing, so it counts as processing.
func run_mark_mods(card: CardData, function: StringName, ...params: Array) -> void:
	await _run_own_mods(card, function, params, _mark_hooks_see_skill(card), true)

#⚠ A QUESTION, ASKED OF THE SAME MODIFIERS THE MARK HOOKS REACH: it charges no processing and
#registers no combo class, so an effect that only answers it is never an activation. Every answer
#counts -- the shares SUM, so a second modifier offering one is not silenced by the first.
func run_mark_query(card: CardData, function: StringName, ...params: Array) -> float:
	var total := 0.0
	for mod : CardModifier in _own_mods(card, _mark_hooks_see_skill(card)):
		if mod and mod.has_method(function):
			var share : float = await Callable(mod, function).callv(params)
			total += share
			_note_mod_fired(mod, function, false)
	return total

#A mark is never spotlit, so the skill gate would silence the copied face; a real card keeps it.
func _mark_hooks_see_skill(card: CardData) -> bool:
	return BoardPlan.is_marked(card) or (card.skill != null and card.skill.spotlit)

#Statuses are appended as a COPY, so a status removing itself mid-hook cannot corrupt the walk
#asking it, and the skill comes last because that is the order a card is asked in.
func _own_mods(card: CardData, with_skill: bool) -> Array[CardModifier]:
	var mods : Array[CardModifier] = [card.type, card.stamp, card.suit]
	mods.append_array(card.statuses)
	if with_skill and card.skill: mods.append(card.skill)
	return mods

#⚠ A QUESTION IS NOT AN EFFECT FIRING (owner: "it shouldnt trigger on checks, but only when effect
#actually triggers"), so the per-card path charges nothing; `counts_as_activation` is what a caller
#dispatching a real effect passes, and it charges the ramp, the runaway cap and the combo alike.
func _run_own_mods(card: CardData, function: StringName, params: Array, with_skill: bool,
		counts_as_activation: bool) -> void:
	for mod : CardModifier in _own_mods(card, with_skill):
		if mod and mod.has_method(function):
			if counts_as_activation:
				note_processing(1, "%d:%s" % [mod.get_instance_id(), function])
			await Callable(mod, function).callv(params)
			_note_mod_fired(mod, function, false, counts_as_activation)

#Loose varargs: wrapping in [..] would deliver ONE Array arg to on_trigger(data, mod).
func on_mod_triggered(triggered_data:CardData, triggered_mod:Callable) -> void:
	await run_all_mods(&"on_trigger", triggered_data, triggered_mod)

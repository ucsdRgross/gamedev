class_name MarkMatch
## Which printed properties of a card agree with the mark on its own cell, and what a match pays.

enum Property { RANK = 1, SUIT = 2, TALENT = 4, HAT = 8 }

#THE spellings of the mark's own leniency surface -- hooks are duck-typed, so a name retyped at a
#call site silently disables the mechanic. A mark asks its OWN family and never falls back to the
#meld or stack hooks: content loosening one situation must not loosen another.
const MARK_RANKS_DENY : StringName = &"on_mark_ranks_deny"
const MARK_RANKS_ALLOW : StringName = &"on_mark_ranks_allow"
const MARK_SUITS_DENY : StringName = &"on_mark_suits_deny"
const MARK_SUITS_ALLOW : StringName = &"on_mark_suits_allow"

#The hooks a mark's own copied modifiers answer, spelled here for the same reason as the leniency
#family above: a retyped name disables the effect and nothing reports it. The first two ACT, at the
#landing and at every line score; the third is the QUESTION a composition asks for its multiplier.
const MARK_HIT : StringName = &"on_mark_hit"
const MARK_COVERED : StringName = &"on_mark_covered"
const MARK_LINE_MULT : StringName = &"on_mark_line_mult"

#Derived on EVERY call and cached NOWHERE: a modifier changing a card's suit emits `data_changed`
#rather than bumping `revision`, so a remembered verdict would answer stale. Any card in the cell
#may be asked, not just the one at height 0, and each property is answered on its own.
static func matches_at(state: GameData, card: CardData, coord: BoardCoord) -> int:
	var mark := state.cell_type_at(coord)
	if not mark or not BoardPlan.is_marked(mark): return 0
	var matched := 0
	if await _pip_same(card.rank, mark.rank, MARK_RANKS_DENY, MARK_RANKS_ALLOW):
		matched |= Property.RANK
	if await _pip_same(card.suit, mark.suit, MARK_SUITS_DENY, MARK_SUITS_ALLOW):
		matched |= Property.SUIT
	if _slot_same(card.skill, mark.skill): matched |= Property.TALENT
	if _slot_same(card.stamp, mark.stamp): matched |= Property.HAT
	return matched

#What a RANK match pays: what the card prints, scaled and rounded UP so a fractional rank never
#pays less than its neighbour below. A rank that is ABSENT and one whose value is not a number are
#ONE case -- no integer value, so both pay the flat fallback and neither is one the ace test reads.
static func flat_bonus(card: CardData, matched: int) -> int:
	if not (matched & Property.RANK): return 0
	var settings := SettingsManager.settings
	if not card.rank or not is_finite(card.rank.value): return settings.plan_rank_flat_fallback
	if PipComparator.is_ace(card.rank): return settings.plan_ace_value
	return ceili(card.rank.value * settings.plan_rank_match_step)

#What the TALENT and HAT matches pay. They SUM rather than multiply each other, and the sum IS the
#whole multiplier -- so one contribution of 1 changes nothing and two of 2 make 4.
static func mult_bonus(_card: CardData, matched: int) -> float:
	var settings := SettingsManager.settings
	var mult := 0.0
	if matched & Property.TALENT: mult += settings.plan_talent_mult
	if matched & Property.HAT: mult += settings.plan_hat_mult
	return mult

#A printed pip agrees when the mark's own leniency rules say so and OTHERWISE only when BOTH cards
#print one -- so two present pips are the comparator's own unmemoised sameness, while an ABSENT one
#is asked of the two passes alone and printed identity's null-equals-null is never reached.
static func _pip_same(a: Variant, b: Variant, deny: StringName, allow: StringName) -> bool:
	if a and b: return await PipComparator.pair_is_same(a, b, deny, allow, false)
	if await PipComparator.ask_pass(deny, a, b, null, null, false): return false
	return await PipComparator.ask_pass(allow, a, b, null, null, false)

#A talent or hat agrees when BOTH slots are filled and name the same script: a mark carries its own
#COPY of what the source printed, so the class is the identity, and the both-present half is the
#printed rule `_pip_same` falls through to.
static func _slot_same(a: CardModifier, b: CardModifier) -> bool:
	if not a or not b: return false
	return PipComparator.modifier_script(a) == PipComparator.modifier_script(b)

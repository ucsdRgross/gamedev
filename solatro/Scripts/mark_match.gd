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

#Derived on EVERY call and cached NOWHERE: a modifier changing a card's suit emits `data_changed`
#rather than bumping `revision`, so a remembered verdict would answer stale. Any card in the cell
#may be asked, not just the one at height 0, and each property is answered on its own.
static func matches_at(state: GameData, card: CardData, coord: BoardCoord) -> int:
	if not state.has_cell(coord): return 0
	var grid : GridData = state.grids[coord.grid]
	var mark : CardData = grid.cell_types[grid.cell_index(coord.x, coord.y)]
	if not BoardPlan.is_marked(mark): return 0
	var matched := 0
	if await PipComparator.pair_is_same(card.rank, mark.rank,
			MARK_RANKS_DENY, MARK_RANKS_ALLOW, false):
		matched |= Property.RANK
	if await PipComparator.pair_is_same(card.suit, mark.suit,
			MARK_SUITS_DENY, MARK_SUITS_ALLOW, false):
		matched |= Property.SUIT
	if _slot_same(card.skill, mark.skill): matched |= Property.TALENT
	if _slot_same(card.stamp, mark.stamp): matched |= Property.HAT
	return matched

#What a RANK match pays: what the card prints, scaled and rounded UP so a fractional rank never
#pays less than its neighbour below. ⚠ The finite test comes first because a value that is not a
#number is not one the ace test can read either.
static func flat_bonus(card: CardData, matched: int) -> int:
	if not (matched & Property.RANK): return 0
	var settings := SettingsManager.settings
	if not is_finite(card.rank.value): return settings.plan_rank_flat_fallback
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

#A talent or hat agrees when BOTH slots are filled and name the same script: a mark carries its own
#COPY of what the source printed, so the class is the identity -- and two EMPTY slots agree about
#nothing, which is why printed identity's null-equals-null is not the test here.
static func _slot_same(a: CardModifier, b: CardModifier) -> bool:
	if not a or not b: return false
	return PipComparator.modifier_script(a) == PipComparator.modifier_script(b)

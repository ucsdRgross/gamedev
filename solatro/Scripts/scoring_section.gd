## One scorer invocation's worth of cards. Rows and columns are the only shapes today; a future
## scorer may evaluate a diagonal, several rows at once, or an arbitrary set, and NOTHING that
## consumes this may assume otherwise (design Q260=a, Q266=a).
class_name ScoringSection
extends RefCounted

## Every card participating in the hand. THIS IS THE SPOTLIGHT SET (design Q31=d) — it is not
## derived from geometry and it is not `result.meld`.
var cards : Array[CardData] = []
## Opaque provenance, for logging and the tuning tool only. NEVER branched on for behaviour.
var origin : StringName = &""          # e.g. &"row", &"col"
var index : int = -1
var zone : Array = []
## How `refresh()` re-collects — captured at construction so `origin` stays pure provenance and a
## future non-line shape supplies its own re-derivation instead of being misread as a column.
var _recollect : Callable = Callable()

## The section one `Game.score_line(result, is_row, zone, index)` call evaluates, re-derived from
## the LIVE board. ⚠ Never cache the result across a hook — `Q252`=(b) requires a re-read after
## every one, because a handler may have added a card to the section or compacted one out of it.
## Ragged rows are the reason for the `row < a.size()` guard: it mirrors `SkillEvalPokerBest`
## exactly, so the section is the same card list the scorer evaluated.
# TODO(multi-meld membership, Q54=a / comparator_buckets DEFERRED.md D4): The Courier straddles two
# columns and The Puszta Five belongs to every one — one card scoring in SEVERAL MELDS. That is
# "which hand is this card in", which is decided HERE and in `Game.score_line`, not by grouping.
# ⚠ Do not conflate it with multiplicity (D1) or with a grouping rule's pull-in (Q14=d): those are
# one meld reaching outward, this is one card belonging to several.
static func of_line(zone: Array, is_row: bool, index: int) -> ScoringSection:
	var section := ScoringSection.new()
	section.origin = &"row" if is_row else &"col"
	section.index = index
	section.zone = zone
	section._recollect = collect.bind(zone, is_row, index)
	section.cards = collect(zone, is_row, index)
	return section

## THE card list for a row or a column of `zone`. Static and pure so a re-derive is one call.
static func collect(zone: Array, is_row: bool, index: int) -> Array[CardData]:
	var out : Array[CardData] = []
	if is_row:
		for a : ArrayCardData in zone:
			if index < a.datas.size(): out.append(a.datas[index])
	elif index >= 0 and index < zone.size():
		var col : ArrayCardData = zone[index]
		if col: out.append_array(col.datas)
	return out

## Re-read this section's cards from the board (`Q252`=b). Returns true when the set CHANGED,
## which is what ends the activation sweep's loop.
func refresh() -> bool:
	if not _recollect.is_valid(): return false
	var fresh : Array[CardData] = _recollect.call()
	if fresh == cards:
		return false
	cards = fresh
	return true

class_name SkillLineDetector
extends CardModifierSkill

## Every kind this pass scores, in the deterministic order a mutation completing several
## lines at once must score them: rows, then columns, then diagonals. HEIGHT_V is enumerated
## by `LineGeometry` but its own completeness rule (multiple-of-5 windowing) lands separately,
## so it never reaches this loop yet.
const _SCORED_KINDS : Array[ScoringSection.LineKind] = [
	ScoringSection.LineKind.ROW, ScoringSection.LineKind.COL, ScoringSection.LineKind.DIAG,
]

func get_str() -> String: return TRANSLATION.find('LINE_DETECTOR_CARD')
func get_description() -> String: return TRANSLATION.find('LINE_DETECTOR_CARD_DESCRIPTION')
func get_frame() -> int: return 9

## Engine scorer machinery: never a combo class -- a constant baseline every act, like the
## other rules-deck scorers.
func combo_key(_hook: StringName = &"") -> String: return ""

## Answers the grid mutation broadcast: enumerates every line through the mutated cell and
## scores whichever of them is complete, in ROW/COL/DIAG order. A compaction (drop-only move)
## scores nothing.
##
## THERE IS NO LINE-SCORED MEMORY: a complete line scores every time this fires, so an effect
## that removes and replaces a card in a complete line re-scores it every cycle. That is a
## legitimate archetype, not a bug -- "re-scanning" a line an effect completed elsewhere is just
## that effect's own board mutation broadcasting `on_board_mutated` again and this handler
## running again, recursively, for as long as scoring keeps triggering more mutations. The ONLY
## thing that stops an unbounded cycle is the caller's runaway guard, checked here so an
## overrun act stops scoring instead of recursing further.
func on_board_mutated(coord: BoardCoord, is_compaction: bool) -> void:
	if is_compaction: return
	if not game: return
	if game.act_overrun or game.act_cancelled: return
	var grids : Array[GridData] = game.state.grids
	if coord.grid < 0 or coord.grid >= grids.size(): return
	var grid : GridData = grids[coord.grid]
	if not grid: return
	var lines := LineGeometry.lines_through(grid, coord.x, coord.y, coord.h)
	for kind : ScoringSection.LineKind in _SCORED_KINDS:
		for line : LineGeometry.Line in lines:
			if line.kind != kind: continue
			if not _is_complete(game.state, coord.grid, line): continue
			var section := ScoringSection.of_geometric_line(game.state, coord.grid, line)
			# No result is computed here ON PURPOSE. score_line re-evaluates the hand
			# itself, over whatever is in the section after every spotlight effect has
			# fired, and THAT is what banks -- so a result computed now would only be
			# thrown away, and computing one would imply it survived the cascade.
			await game.score_line(null, section)
			if game.act_overrun or game.act_cancelled: return

## A line is complete when every cell it runs through holds a card -- a taller stack still has
## a card at the queried height, so `LineGeometry` already accounts for that; this only checks
## occupancy.
func _is_complete(state: GameData, grid: int, line: LineGeometry.Line) -> bool:
	for c : Vector3i in line.cells:
		if state.card_at(BoardCoord.new(grid, c.x, c.y, c.z)) == null:
			return false
	return true

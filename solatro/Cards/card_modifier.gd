@tool
@abstract class_name CardModifier
extends Resource
## ⚠ `@tool` IS REQUIRED: a non-tool base loads in the editor as a placeholder that strips every member of every subclass.

enum Rarity {COMMON, UNCOMMON, RARE, EPIC, LEGENDARY}

# TODO(rarity/tags): Rarity above is carried by nothing yet. If modifiers grow rarity/tags,
# expose them as abstract getters like get_str/get_frame, not @export vars.

#The backref to the owning card is WEAK because card<->modifier was a RefCounted CYCLE and Godot
#has no cycle collector. ⚠ duplicate_deep does NOT remap a WeakRef, and a save carries none — both
#relink through GameData.relink_card_backrefs.
var _data_ref : WeakRef = null
var data : CardData:
	set(value):
		_data_ref = weakref(value) if value else null
	get:
		return _data_ref.get_ref() as CardData if _data_ref else null

## The environment a modifier dispatches through — there is deliberately NO `game` property, because a change to Game's shape would then break every card at once.
var env : CardEnvironment:
	get: return CardEnvironment.CURRENT
## THE seam every effect runs through — null outside a game (deck viewers, boosters), so ask `api.is_live()` first.
var api : CardEffectApi:
	get:
		var g := CardEnvironment.get_current_game()
		return g.effect_api if g else null

@abstract func get_str() -> String
@abstract func get_description() -> String
@abstract func get_frame() -> int
@abstract func set_texture(polygon2d:Polygon2D) -> void

func with_data(data:CardData) -> CardModifier:
	self.data = data
	return self

#⚠ NEVER CLEAR THE MATERIAL HERE. The polygons are pooled and reused across cards, so assigning
#null strips the outline rim off whichever card lands on a recycled polygon; stale uniforms are
#solved by OVERWRITING them in `CardOutline.material_of` instead.

## How this modifier's element fills its BODY — the sheet's own colours, which `PipSuit` overrides to flatten its art to the suit's role.
func set_material(polygon2d:Polygon2D) -> void: CardOutline.fill_texture(polygon2d)

## Combo identity: one class per modifier script by default, "" to opt out, or the hook appended to count hooks as separate classes.
func combo_key(_hook: StringName = &"") -> String:
	var script : Script = get_script()
	return script.resource_path




# Hooks are duck-typed: implementing a method named after an event opts the modifier in
# (dispatch checks has_method — see CardEnvironment.run_all_mods). ⚠ The maintained hook list
# with signatures lives in ARCHITECTURE_REVIEW.md §1.4 — keep THAT current, never a copy here.

# ==============================================================================
# THE COMPARATOR SURFACE — "are these two cards the same?"
# ==============================================================================

#⚠ COMMENTS, NOT METHODS, AND THAT IS THE MECHANISM. Dispatch asks `has_method`, so a real no-op
#here would opt EVERY modifier in and the printed-identity path could never be taken. ⚠ A typo
#silently disables a rule — call sites name `PipComparator.MELD_RANKS_DENY`, never the spelling.

#SEPARATE HOOKS PER SITUATION, NO FALLBACK BETWEEN THEM. Blacklist or whitelist is declared BY
#WHICH HOOK IS IMPLEMENTED, never by a flag or a return value.

#MELD sameness, two passes. true = "this pass answers yes for this pair".
#   func on_meld_ranks_deny(r1: PipRank, r2: PipRank) -> bool
#   func on_meld_ranks_allow(r1: PipRank, r2: PipRank) -> bool

#   func on_meld_suits_deny(s1: PipSuit, s2: PipSuit) -> bool
#   func on_meld_suits_allow(s1: PipSuit, s2: PipSuit) -> bool

#STACK legality sameness — the same two passes, its OWN hooks. No fallback from meld.
#   func on_stack_ranks_deny(r1: PipRank, r2: PipRank) -> bool
#   func on_stack_ranks_allow(r1: PipRank, r2: PipRank) -> bool

#   func on_stack_suits_deny(s1: PipSuit, s2: PipSuit) -> bool
#   func on_stack_suits_allow(s1: PipSuit, s2: PipSuit) -> bool

#WHOLE-HAND grouping, stage 1.
#   func on_meld_group_ranks(cards: Array[CardData], groups: Array[Array]) -> Array[Array]
#   func on_meld_group_suits(cards: Array[CardData], groups: Array[Array]) -> Array[Array]

#ADJACENCY.
#   func on_meld_extra_rank_values(card: CardData) -> Array[float]
#   func on_meld_wrap_bounds(low: float, high: float) -> Vector2

#⚠ ORDERING IS NOT PART OF THIS SURFACE. `on_compare_ranks` / `on_compare_suits` ask "which is
#greater", which has nothing to deny or allow, and melding no longer calls them.

#⚠ NO `compare_uncacheable`, and nothing needs one: a rule's answer is fixed for the hand being
#scored, so a random rule is safe to write and has nothing to declare.

#⚠ THE ORDER OF THESE CHECKS IS THE RULE. A mark is excluded, and a forced spotlight read, AFTER
#the stage check, so a stale entry for a card that left the board cannot light it; the beam then
#comes BEFORE the coverage rules, bypassing both Revealing and blocks_spotlight.

## Effective spotlight = NATURAL (this rule) OR FORCED (the scoring beam, `GameData.forced_spotlight`).
func is_spotlit() -> bool:
	if CardEnvironment.CURRENT and CardEnvironment.CURRENT.is_data_in_rules(data):
		return true
	if data.stamp is StampGlobal:
		return true
	if not api or not api.is_live(): return false
	if data.stage != CardData.Stage.PLAY and data.stage != CardData.Stage.ZONE:
		return false
	if _is_mark(): return false
	if api and api.forced_spotlight().has(data):
		return true
	if data.stamp is StampRevealing:
		return true
	return not _blocked_from_above()

#Blocking is the DEFAULT because a covering card is exactly what makes the card beneath dark, and
#one Kuroko / Ghost Light modifier opting out is enough for its whole card. ⚠ `false` as the
#default would spotlight every covered card on the board.

## Does this card HIDE the talents of whatever is stacked under it? A mark hides nothing.
func blocks_spotlight() -> bool:
	return not _is_mark()

#⚠ A MARK IS NEVER SPOTLIT AND BLOCKS NOTHING, whatever it copied and whatever covers it: its
#copied modifiers answer the mark hooks and nothing else, so a copied skill must never answer the
#board's broadcasts. `is_marked` asks only for a printed pip, so the type check is what scopes it.
func _is_mark() -> bool:
	return data.type is TypeGridCell and BoardPlan.is_marked(data)

#⚠ DEGENERATE LOOKUPS FAIL CLOSED (blocked -> dark): `position_of` is a revision-cached index, so
#a card read mid-mutation can miss, and failing OPEN would spotlight a card the board cannot even
#locate. A zone/type header (`coord.z == -1`) is blocked by any card in its column.

## Is this card hidden by anything stacked above it in its own column? The FIRST blocker ends the walk.
func _blocked_from_above() -> bool:
	var coord := api.position_of(data) if api else Vector3i.MIN
	if coord == Vector3i.MIN: return true
	var zone := api.get_zone_from_vec3(coord) if api else ([] as Array[ArrayCardData])
	if coord.y < 0 or coord.y >= zone.size(): return true
	var col : ArrayCardData = zone[coord.y]
	if not col: return true
	for z in range(maxi(coord.z + 1, 0), col.datas.size()):
		if _card_blocks(col.datas[z]): return true
	return false

## Does `above` hide what is stacked under it? A card stops blocking the moment ANY ONE of its modifiers opts out.
static func _card_blocks(above: CardData) -> bool:
	for mod : CardModifier in [above.skill, above.type, above.stamp, above.suit]:
		if mod and not mod.blocks_spotlight(): return false
	for st : CardModifierStatus in above.statuses:
		if not st.blocks_spotlight(): return false
	return true

# TODO(card feedback popups): the old card_shake / card_raise / card_lower / _do_popup flow was
# never ported to the CardVisual rewrite. SkillExtraPoint and SkillHungryHippo still reference
# card_shake in comments and want it back when a visual-feedback pass happens.

## THE definition of sheet geometry: one frame's size in source texels, DERIVED from the image so re-exporting art at another resolution cannot leave a stale number.
static func frame_size(source_sheet: Texture2D, h_frame: int, v_frame: int) -> Vector2:
	return source_sheet.get_size() / Vector2(float(h_frame), float(v_frame))

## Source rect of one frame — the same window update_polygon_uv_frame maps UVs into, as a Rect2 for prop art.
static func frame_rect(source_sheet: Texture2D, h_frame: int, v_frame: int,
		target_frame: int) -> Rect2:
	var size := frame_size(source_sheet, h_frame, v_frame)
	return Rect2(Vector2(float(target_frame % h_frame), float(target_frame / h_frame)) * size, size)

## Robust runtime UV framing method that automatically adapts to ANY texture size
static func update_polygon_uv_frame(polygon2d: Polygon2D, source_sheet: Texture2D, h_frame: int, v_frame: int, target_frame: int) -> void:
	if not polygon2d or polygon2d.polygon.is_empty():
		return

	if polygon2d.texture != source_sheet:
		polygon2d.texture = source_sheet

	var src := frame_rect(source_sheet, h_frame, v_frame, target_frame)
	var frame_w := src.size.x
	var frame_h := src.size.y
	var u_left := src.position.x
	var v_top := src.position.y

	var base_points := polygon2d.polygon
	var shifted_uvs := PackedVector2Array()
	shifted_uvs.resize(base_points.size())
	
	var min_p := base_points[0]
	var max_p := base_points[0]
	for idx in range(1, base_points.size()):
		var pt := base_points[idx]
		min_p.x = min(min_p.x, pt.x)
		min_p.y = min(min_p.y, pt.y)
		max_p.x = max(max_p.x, pt.x)
		max_p.y = max(max_p.y, pt.y)
		
	var poly_w := max_p.x - min_p.x
	var poly_h := max_p.y - min_p.y
	
	if poly_w == 0.0: poly_w = 1.0
	if poly_h == 0.0: poly_h = 1.0
	
	for i in range(base_points.size()):
		var p := base_points[i]
		
		var norm_x := (p.x - min_p.x) / poly_w
		var norm_y := (p.y - min_p.y) / poly_h
		
		var uv_x := u_left + (norm_x * frame_w)
		var uv_y := v_top + (norm_y * frame_h)
		
		shifted_uvs[i] = Vector2(uv_x, uv_y)
		
	polygon2d.uv = shifted_uvs

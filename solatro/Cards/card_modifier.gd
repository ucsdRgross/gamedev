@tool
@abstract class_name CardModifier
extends Resource
## ⚠ `@tool` for the reason spelled out on `CardData`: the FX editor previews a REAL card, and a
## placeholder base takes every member of every subclass with it — a `@tool` pip on a non-tool base
## still came back as a bare `Resource`. Nothing here needs a running game: `env` and `game` read
## `CardEnvironment` STATICS, which simply answer null outside one.

enum Rarity {COMMON, UNCOMMON, RARE, EPIC, LEGENDARY}

# TODO(rarity/tags): Rarity above is carried by nothing yet. If modifiers grow
# rarity/tags, expose them as abstract getters (like get_str/get_frame), not @export vars.
# Weak backref to the owning card. WEAK on purpose: card<->modifier was a RefCounted
# CYCLE (Godot has no cycle collector), and manual unlink discipline at every drop site
# kept failing. A WeakRef means the cycle never exists — a card graph dies when its last
# external reference drops, no unlink needed. Not serialized (WeakRef can't be; saves
# carry no backref, same as before). ⚠️ duplicate_deep does NOT remap a WeakRef: every
# deep-copy site must relink its copies (GameData.relink_card_backrefs).
var _data_ref : WeakRef = null
var data : CardData:
	set(value):
		_data_ref = weakref(value) if value else null
	get:
		return _data_ref.get_ref() as CardData if _data_ref else null

## The environment a modifier dispatches through. `api` below is how it reads and changes the
## game; there is deliberately NO `game` property, because a modifier that can reach the game
## directly will, and then a change to Game's shape breaks every card at once.
var env : CardEnvironment:
	get: return CardEnvironment.CURRENT
## THE seam every effect runs through. Null outside a game (deck viewers, boosters), so
## always null-check — or call `api.is_live()`, which every accessor already guards on.
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

## How this modifier's element fills its BODY. The default draws the sheet's own colours, which is
## right for every sheet authored in the palette (types, suit pips, stamps); `PipSuit` overrides it to
## flatten the suit-agnostic art to the suit's role.
##
## ⚠ **This used to assign `null`,** deliberately — the polygons are pooled and reused across cards, so
## a stale ShaderMaterial from a previous binding would survive a rebind. Every element is now an
## outline client, so clearing the material is exactly what must not happen: it silently strips the rim
## off whichever cards happen to land on a recycled polygon. The stale-state problem is solved by
## OVERWRITING the uniforms instead (`CardOutline.material_of`).
func set_material(polygon2d:Polygon2D) -> void: CardOutline.fill_texture(polygon2d)

## Combo identity for SCORING_MATH_PLAN §15a mod-activation U. Default: one combo class per
## modifier script, whatever hook fired. Overrides may return "" (opt this mod — or specific
## hooks — out of combo) or append the hook to count hooks as separate classes.
func combo_key(_hook: StringName = &"") -> String:
	var script : Script = get_script()
	return script.resource_path




# Hooks are duck-typed: implementing a method named after an event opts the modifier in
# (dispatch checks has_method — see CardEnvironment.run_all_mods). ⚠ The maintained hook list
# with signatures lives in ARCHITECTURE_REVIEW.md §1.4 — keep THAT current, never a copy here.

# ==============================================================================
# THE COMPARATOR SURFACE — "are these two cards the same?" (comparator_buckets PLAN §1.1)
# ------------------------------------------------------------------------------
# ⚠ **COMMENTS, NOT METHODS, AND THAT IS THE MECHANISM.** Dispatch asks `has_method`, so a real
# no-op here would opt EVERY modifier in and the identity path (chart C4) could never be taken.
# ⚠ A typo silently disables a rule — call sites name `PipComparator.MELD_RANKS_DENY` and friends
# rather than retyping the spelling.
#
# QR3(c)/Q62(a)/Q97: SEPARATE HOOKS PER SITUATION, NO FALLBACK BETWEEN THEM. Q80(a): blacklist or
# whitelist is declared BY WHICH HOOK IS IMPLEMENTED, never by a flag or a return value.
#
#   # MELD sameness, two passes. true = "this pass answers yes for this pair".
#   func on_meld_ranks_deny(r1: PipRank, r2: PipRank) -> bool
#   func on_meld_ranks_allow(r1: PipRank, r2: PipRank) -> bool
#   func on_meld_suits_deny(s1: PipSuit, s2: PipSuit) -> bool
#   func on_meld_suits_allow(s1: PipSuit, s2: PipSuit) -> bool
#
#   # STACK legality sameness — the same two passes, its OWN hooks. No fallback from meld.
#   func on_stack_ranks_deny(r1: PipRank, r2: PipRank) -> bool
#   func on_stack_ranks_allow(r1: PipRank, r2: PipRank) -> bool
#   func on_stack_suits_deny(s1: PipSuit, s2: PipSuit) -> bool
#   func on_stack_suits_allow(s1: PipSuit, s2: PipSuit) -> bool
#
#   # WHOLE-HAND grouping, stage 1.
#   func on_meld_group_ranks(cards: Array[CardData], groups: Array[Array]) -> Array[Array]
#   func on_meld_group_suits(cards: Array[CardData], groups: Array[Array]) -> Array[Array]
#
#   # ADJACENCY.
#   func on_meld_extra_rank_values(card: CardData) -> Array[float]
#   func on_meld_wrap_bounds(low: float, high: float) -> Vector2
#
# ⚠ ORDERING is NOT part of this surface. `on_compare_ranks` / `on_compare_suits` keep their
# meaning, callers and first-implementer-wins composition (Q55=a): they ask "which is greater",
# which has nothing to deny or allow. Melding no longer calls them.
# ==============================================================================

# ⚠ **NO `compare_uncacheable`, and nothing needs one** (gaps/GAP-003.md). A rule's answer is
# fixed for the hand being scored, so a random rule is safe to write and has nothing to declare.

## THE spotlight rule (design chart A). Renamed off the old `active` vocabulary (Q2=b):
## "spotlit" is the one word for it everywhere — the mechanical state and the light show are the
## same fact. Effective spotlight = NATURAL (this rule) OR FORCED (GameData.forced_spotlight, the
## scoring beam) — see design §2.
func is_spotlit() -> bool:
	#rules cards are always spotlit
	if CardEnvironment.CURRENT and CardEnvironment.CURRENT.is_data_in_rules(data):
		return true
	#Global: spotlit from anywhere (deck, discard, covered, ...)
	if data.stamp is StampGlobal:
		return true
	#everything else must be on the board
	if not api or not api.is_live(): return false
	if data.stage != CardData.Stage.PLAY and data.stage != CardData.Stage.ZONE:
		return false
	#A6 (design chart A): the scoring beam is literally on this card. Placed AFTER the stage
	#check so a stale entry for a card that left the board cannot force it, and BEFORE the
	#coverage rules so a forced spotlight bypasses both Revealing and blocks_spotlight (Q6=a).
	if api and api.forced_spotlight().has(data):
		return true
	#Revealing is a property of THIS card: spotlit anywhere on the board, even covered.
	if data.stamp is StampRevealing:
		return true
	#A8 (Q9=a): THE COVERAGE RULE, as the general question rather than "am I last". A card
	#stacked on top HIDES the talent underneath it, so it blocks — that is the default, and a
	#Kuroko-style modifier on the covering card is what stops it blocking, unhiding the card
	#beneath (owner, GAP-001 answer 2026-08-04). This REPLACES is_data_topmost: with every
	#modifier blocking, "nothing above me" and "I am topmost" are the same statement, so today's
	#behaviour is unchanged.
	return not _blocked_from_above()

## Does this card HIDE the talents of whatever is stacked under it? Default `true` — a covering
## card is exactly what makes the card beneath dark (design Q9=a, chart A8). A Kuroko / Ghost
## Light modifier overrides it to `false`, and one such modifier is enough for its whole card
## (see `_card_blocks`). Content that uses it is OUT of scope here (Q185=a).
## ⚠ `PLAN.md` §1.4 specifies the opposite default; it is wrong — with `false` every covered card
## on the board would be spotlit, which contradicts the design's own U2. See gaps/GAP-001.md.
func blocks_spotlight() -> bool:
	return true

## A8: is this card hidden by anything stacked above it in its own column? The FIRST blocker
## ends the walk, and since blocking is the default that is almost always the card immediately
## above — so a covered card costs one comparison, not a column scan. A zone/type header
## (`coord.z == -1`) is blocked by any card in its column, which is the same rule
## `is_data_topmost` expressed for headers ("topmost exactly when its column is empty").
func _blocked_from_above() -> bool:
	# ⚠ **DEGENERATE LOOKUPS FAIL CLOSED (blocked → dark), exactly as `is_data_topmost` did.**
	# `position_of` is a revision-cached index, so a card read mid-mutation (before the bump) can
	# miss — and failing OPEN would spotlight a card the board cannot even locate.
	var coord := api.position_of(data) if api else Vector3i.MIN
	if coord == Vector3i.MIN: return true
	var zone := api.get_zone_from_vec3(coord) if api else ([] as Array[ArrayCardData])
	if coord.y < 0 or coord.y >= zone.size(): return true
	var col : ArrayCardData = zone[coord.y]
	if not col: return true
	for z in range(maxi(coord.z + 1, 0), col.datas.size()):
		if _card_blocks(col.datas[z]): return true
	return false

## Does `above` hide what is stacked under it? A card blocks by default and stops blocking the
## moment ANY ONE of its modifiers opts out — a single Kuroko stamp unhides the card beneath, it
## does not have to convince the card's type and suit to agree with it.
static func _card_blocks(above: CardData) -> bool:
	for mod : CardModifier in [above.skill, above.type, above.stamp, above.suit]:
		if mod and not mod.blocks_spotlight(): return false
	for st : CardModifierStatus in above.statuses:
		if not st.blocks_spotlight(): return false
	return true

# TODO(card feedback popups): the old card_shake / card_raise / card_lower / _do_popup
# flow (spawn a temp visual off the deck/discard pile, raise it, run the effect, lower
# and free it) was never ported to the CardVisual rewrite. SkillExtraPoint and
# SkillHungryHippo still reference card_shake in comments and want it back when a
# visual-feedback pass happens.

## Size of ONE frame of a uniform sprite sheet, in source texels — DERIVED from the image, never
## retyped next to it, so re-exporting art at a different resolution cannot leave a hardcoded number
## lying. THE definition of sheet geometry for the whole project: cards frame sheets through
## update_polygon_uv_frame below, props through PropVisual._draw_frame, and both come here.
static func frame_size(source_sheet: Texture2D, h_frame: int, v_frame: int) -> Vector2:
	return source_sheet.get_size() / Vector2(float(h_frame), float(v_frame))

## Source rect of one frame — the same window update_polygon_uv_frame maps UVs into, as a Rect2 for
## the `draw_texture_rect_region` callers (prop art).
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

	# The frame's pixel window in the sheet (frame_rect above is the one definition of this maths).
	var src := frame_rect(source_sheet, h_frame, v_frame, target_frame)
	var frame_w := src.size.x
	var frame_h := src.size.y
	var u_left := src.position.x
	var v_top := src.position.y

	var base_points := polygon2d.polygon
	var shifted_uvs := PackedVector2Array()
	shifted_uvs.resize(base_points.size())
	
	# 3. Dynamically find the min/max bounds of the physical mesh shape
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
	
	# 4. Map the physical vertices directly to the newly calculated texture coordinates
	for i in range(base_points.size()):
		var p := base_points[i]
		
		# Normalize the physical coordinate space to a clean 0.0 - 1.0 range
		var norm_x := (p.x - min_p.x) / poly_w
		var norm_y := (p.y - min_p.y) / poly_h
		
		# Translate normalized space into the exact pixel window of the new frame
		var uv_x := u_left + (norm_x * frame_w)
		var uv_y := v_top + (norm_y * frame_h)
		
		shifted_uvs[i] = Vector2(uv_x, uv_y)
		
	polygon2d.uv = shifted_uvs

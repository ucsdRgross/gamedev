@abstract class_name CardModifier
extends Resource

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

## Current environment / game shortcuts so every modifier doesn't have to re-derive them.
## Read-only convenience: null when no environment / not in a game — always null-check.
## State MUTATION should still go through Game's API (move_data_*, discard_data, ...).
var env : CardEnvironment:
	get: return CardEnvironment.CURRENT
var game : Game:
	get: return CardEnvironment.get_current_game()

@abstract func get_str() -> String
@abstract func get_description() -> String
@abstract func get_frame() -> int
@abstract func set_texture(polygon2d:Polygon2D) -> void

func with_data(data:CardData) -> CardModifier:
	self.data = data
	return self

func set_material(polygon2d:Polygon2D) -> void: polygon2d.material = null

## Combo identity for SCORING_MATH_PLAN §15a mod-activation U. Default: one combo class per
## modifier script, whatever hook fired. Overrides may return "" (opt this mod — or specific
## hooks — out of combo) or append the hook to count hooks as separate classes.
func combo_key(_hook: StringName = &"") -> String:
	var script : Script = get_script()
	return script.resource_path




# Hooks are duck-typed: implementing a method named after an event opts the modifier in
# (dispatch checks has_method — see CardEnvironment.run_all_mods). The MAINTAINED hook
# list with signatures lives in ARCHITECTURE_REVIEW.md §1.4; keep THAT current when
# adding events. (The stale copy that used to sit here was purged 2026-07-16, D7 override.)

func is_active() -> bool:
	#rules cards are always active
	if CardEnvironment.CURRENT and CardEnvironment.CURRENT.is_data_in_rules(data):
		return true
	#Global: active from anywhere (deck, discard, covered, ...)
	if data.stamp is StampGlobal:
		return true
	#everything else must be on the board
	if not game: return false
	if data.stage != CardData.Stage.PLAY and data.stage != CardData.Stage.ZONE:
		return false
	#Revealing: active on the board even when covered
	if data.stamp is StampRevealing:
		return true
	#default: active while uncovered (topmost of its stack)
	return game.is_data_topmost(data)

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

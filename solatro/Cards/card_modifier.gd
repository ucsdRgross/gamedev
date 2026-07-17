@abstract class_name CardModifier
extends Resource

enum Rarity {COMMON, UNCOMMON, RARE, EPIC, LEGENDARY}

# TODO(rarity/tags): Rarity above is carried by nothing yet. If modifiers grow
# rarity/tags, expose them as abstract getters (like get_str/get_frame), not @export vars.
@export_storage var data : CardData

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

## Robust runtime UV framing method that automatically adapts to ANY texture size
static func update_polygon_uv_frame(polygon2d: Polygon2D, source_sheet: Texture2D, h_frame: int, v_frame: int, target_frame: int) -> void:
	if not polygon2d or polygon2d.polygon.is_empty():
		return
		
	if polygon2d.texture != source_sheet:
		polygon2d.texture = source_sheet
		
	# 1. Dynamically read the incoming texture sizing
	var sheet_size := source_sheet.get_size()
	var frame_w := sheet_size.x / h_frame
	var frame_h := sheet_size.y / v_frame
	
	# 2. Find row, column, and pixel offset positions for the new layout
	var col := target_frame % h_frame
	var row := target_frame / h_frame
	var u_left := col * frame_w
	var v_top := row * frame_h
	
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

@abstract class_name PipSuit
extends CardModifier
## A card's suit. Now a CardModifier (was Resource): reached ONLY via run_card_mods +
## spawn_props, never through the suit-free run_all_mods iterator. Suits are NOMINAL, not
## ordinal — there is no `value`; switching uses PipSuit.from_index, never value ± 1.

## CardData.suit's setter connects this (card_data.gd:9-13). Suits no longer mutate
## themselves, but the seam stays for future dynamic suits.
signal data_changed

const SUIT_TEXTURE : Texture2D = preload("res://Assets/suit_pips.png")   # 8x8 frames
const SUIT_TEXTURE_H_FRAMES : int = 8
const SUIT_TEXTURE_V_FRAMES : int = 8
const ART_TEXTURE : Texture2D = preload("res://Assets/suit_art.png")     # 13x13 frames
const ART_TEXTURE_H_FRAMES : int = 13
const ART_TEXTURE_V_FRAMES : int = 13
const COLOR_PICKER_SHADER = preload("res://Assets/color_picker.tres")
## Palette colour by suit index; 5th (Firework) is placeholder art. TODO real Firework art.
const PALETTE : Array[int] = [8, 11, 14, 2, 6]

## 0..4 — art/palette slot ONLY, never orderable.
@abstract func get_suit_index() -> int
## PURE factory: the spawners this suit launches when its card is scored in a meld.
## Empty when the card is talented (data.skill) or off-board. NO mutation in here.
@abstract func spawn_props() -> Array[PropSpawner]

func get_frame() -> int: return get_suit_index()

func set_texture(polygon2d:Polygon2D) -> void:
	CardModifier.update_polygon_uv_frame(
		polygon2d, SUIT_TEXTURE, SUIT_TEXTURE_H_FRAMES, SUIT_TEXTURE_V_FRAMES, get_suit_index())
	set_material(polygon2d)

func set_material(polygon2d:Polygon2D) -> void:
	var material := ShaderMaterial.new()
	material.shader = COLOR_PICKER_SHADER
	material.set_shader_parameter("color_x", PALETTE[get_suit_index()])
	polygon2d.material = material

func set_art_texture(polygon2d:Polygon2D, rank:PipRank) -> void:
	if rank is PipRankNumeral:
		var numeral : PipRankNumeral = rank
		CardModifier.update_polygon_uv_frame(
			polygon2d, ART_TEXTURE, ART_TEXTURE_H_FRAMES, ART_TEXTURE_V_FRAMES,
			13 * get_suit_index() + (numeral.value - 1))
	else:
		polygon2d.texture = null
	set_material(polygon2d)

## Registry + switching (replaces all `value` math). Firework excluded: never random.
static var STANDARD : Array[GDScript] = [PipSuitHoop, PipSuitKnife, PipSuitBall, PipSuitFire]
static func from_index(i:int) -> PipSuit: return STANDARD[i].new()
static func random_standard() -> PipSuit: return STANDARD[randi() % STANDARD.size()].new()

## Fire-buff readers (self-inspection of the OWN card's statuses at spawn time). fire_mult
## multiplies the suit-effect prop COUNT only (one knob; v1's double-dip was dropped).
func fire_stacks() -> int:
	if not data: return 0
	for s : CardModifierStatus in data.statuses:
		if s is StatusBurning: return s.stacks
	return 0
func fire_mult() -> int:
	return 1 + fire_stacks()

# --- Shared spawn preamble (Phase 3) --------------------------------------------------------

## The board slot this suit launches from, or Vector3i.MIN when it spawns nothing: a talented
## card (its skill suppresses its own suit effect — locked) or an off-board card.
func _spawn_origin() -> Vector3i:
	if data.skill: return Vector3i.MIN
	if not game: return Vector3i.MIN
	return game.find_data_vec3(data)

## Prop count = rank × fire_mult (fire buffs count only). Non-numeral ranks count as 1.
func _spawn_count() -> int:
	var rank_value := 1
	if data.rank is PipRankNumeral:
		rank_value = int((data.rank as PipRankNumeral).value)
	return rank_value * fire_mult()

## PropBurning mod list to fold onto every emitted prop when this card is Burning (else empty).
func _burning_mods() -> Array[PropModifier]:
	var stacks := fire_stacks()
	if stacks > 0:
		return [PropBurning.new(stacks)] as Array[PropModifier]
	return [] as Array[PropModifier]

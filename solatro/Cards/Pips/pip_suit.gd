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
## (Return type is untyped Array until Phase 1 introduces PropSpawner.)
@abstract func spawn_props() -> Array

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

## Fire-buff readers (self-inspection of the OWN card's statuses at spawn time).
## Phase 2 fills this once statuses is an Array[CardModifierStatus] holding StatusBurning.
func fire_stacks() -> int:
	return 0
func fire_mult() -> int:
	return 1 + fire_stacks()

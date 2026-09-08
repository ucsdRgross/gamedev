@tool
@abstract class_name PipSuit
extends CardModifier
## ⚠ `@tool`, and this is the base the owner's editor actually caught: *"Nonexistent function
## 'set_texture' in base 'Resource'"* on a `PipSuitHoop` that IS `@tool` — because a non-tool base makes
## the whole instance a placeholder. See `CardData`. Every concrete suit was already `@tool`.
## A card's suit. Now a CardModifier (was Resource): reached ONLY via run_card_mods +
## spawn_props, never through the suit-free run_all_mods iterator. Suits are NOMINAL, not
## ordinal — there is no `value`; construct the exact suit class (PipSuitHoop.new(), ...)
## or pick from STANDARD, never value ± 1. from_index was deleted: an index hid WHICH suit
## a call site actually produced.

## CardData.suit's setter connects this (`CardData.suit`'s setter). Suits no longer mutate
## themselves, but the seam stays for future dynamic suits.
signal data_changed

## The suit pip sheet. Also drawn by the Ball and Fire PROPS (ball_visual.gd / fire_visual.gd) — the
## props ARE their suits' pips — so both go through these constants and the frame SIZE is derived
## from the image by CardModifier.frame_size rather than written down anywhere.
const SUIT_TEXTURE : Texture2D = preload("res://Assets/suit_pips.png")
const SUIT_TEXTURE_H_FRAMES : int = 8
const SUIT_TEXTURE_V_FRAMES : int = 8
const ART_TEXTURE : Texture2D = preload("res://Assets/suit_art.png")     # 13x13 frames
const ART_TEXTURE_H_FRAMES : int = 13
const ART_TEXTURE_V_FRAMES : int = 13

## 0..4 — art/palette slot ONLY, never orderable.
@abstract func get_suit_index() -> int
## This suit's PaletteDB role, for the polygons that are RECOLOURED (rank pips and card art — both
## drawn as single-colour silhouettes shared by every suit). The suit PIP itself is not recoloured:
## its frames are painted in the palette already, so it draws its own colours (owner).
## Each suit names its own role rather than indexing a magic array — reassigning the colour is
## editing that one named entry in Assets/Palette/roles.tres (T21).
@abstract func palette_role() -> int
## PURE factory: the spawners this suit launches when its card is scored in a meld.
## Empty when the card is talented (data.skill) or off-board. NO mutation in here.
@abstract func spawn_props() -> Array[PropSpawner]

func get_frame() -> int: return get_suit_index()

## The suit PIP draws the sheet's own colours: suit_pips.png is authored in the palette (each frame
## already shaded with its suit's ramp), so recolouring it would flatten that shading to one flat
## index.
##
## ⚠ This used to CLEAR the material (`polygon2d.material = null`), because these polygons are pooled
## and reused across cards and a stale ShaderMaterial would otherwise survive a rebind. The pip is now
## an outline client, so clearing it would strip the rim off whichever cards land on a recycled
## polygon; the stale-state problem is handled by overwriting every uniform instead.
func set_texture(polygon2d:Polygon2D) -> void:
	CardOutline.frame_polygon(
		polygon2d, SUIT_TEXTURE, SUIT_TEXTURE_H_FRAMES, SUIT_TEXTURE_V_FRAMES, get_suit_index())
	CardOutline.fill_texture(polygon2d)

## Recolour `polygon2d` to this suit's palette entry — for the SUIT-AGNOSTIC art it shares with
## every other suit (the rank pip and the card art), never for the suit pip itself.
func set_material(polygon2d:Polygon2D) -> void:
	CardOutline.fill_palette(polygon2d, palette_role())

func set_art_texture(polygon2d:Polygon2D, rank:PipRank) -> void:
	if rank is PipRankNumeral:
		var numeral : PipRankNumeral = rank
		CardOutline.frame_polygon(
			polygon2d, ART_TEXTURE, ART_TEXTURE_H_FRAMES, ART_TEXTURE_V_FRAMES,
			13 * get_suit_index() + (numeral.value - 1))
	else:
		polygon2d.texture = null
	set_material(polygon2d)

## Registry + switching (replaces all `value` math). Firework excluded: never random.
static var STANDARD : Array[GDScript] = [PipSuitHoop, PipSuitKnife, PipSuitBall, PipSuitFire]
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

## The board slot this suit launches from, or NOWHERE when it spawns nothing: a talented
## card (its skill suppresses its own suit effect — locked) or an off-board card. Reads the
## GRID index (Entrance included), not the legacy zone one -- that is the one `_pos_index`
## never sees a grid or Entrance card through.
func _spawn_origin() -> BoardCoord:
	if data.skill: return BoardCoord.NOWHERE
	if not api or not api.is_live(): return BoardCoord.NOWHERE
	return api.grid_position_of(data)

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

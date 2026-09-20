@tool
@abstract class_name PipSuit
extends CardModifier
## A card's suit: a CardModifier reached ONLY via run_card_mods and spawn_props.

#⚠ IT IS `@tool`, AND A NON-TOOL BASE MAKES THE WHOLE INSTANCE A PLACEHOLDER. The owner's editor
#caught it as *"Nonexistent function 'set_texture' in base 'Resource'"* on a PipSuitHoop that is
#itself @tool. Every concrete suit is @tool for the same reason. See CardData.

#Suits are NOMINAL, not ordinal: there is no `value`, so construct the exact suit class or pick
#from STANDARD, never value +/- 1. There is no from_index, because an index hides WHICH suit a call
#site actually produced.

#Suits no longer mutate themselves, but the seam stays for future dynamic suits.

## CardData.suit's setter connects this.
signal data_changed

#Also drawn by the Ball and Fire PROPS, the props BEING their suits' pips, so both go through these
#constants and the frame SIZE is derived from the image by CardModifier.frame_size.

## The suit pip sheet.
const SUIT_TEXTURE : Texture2D = preload("res://Assets/suit_pips.png")
const SUIT_TEXTURE_H_FRAMES : int = 8
const SUIT_TEXTURE_V_FRAMES : int = 8
#13x13 frames.
const ART_TEXTURE : Texture2D = preload("res://Assets/suit_art.png")
const ART_TEXTURE_H_FRAMES : int = 13
const ART_TEXTURE_V_FRAMES : int = 13

## 0..4 — art/palette slot ONLY, never orderable.
@abstract func get_suit_index() -> int
#For the polygons that are RECOLOURED, the rank pips and card art, both drawn as single-colour
#silhouettes shared by every suit. The suit PIP itself is not recoloured: its frames are painted in
#the palette already, so it draws its own colours (owner).

#Each suit names its own role rather than indexing a magic array, so reassigning the colour is
#editing that one named entry in Assets/Palette/roles.tres.
@abstract func palette_role() -> int
#PURE factory: the spawners this suit launches when its card is scored in a meld. Empty unless the
#card's own cell carries a mark agreeing on SUIT, and empty off-board. NO mutation in here.
@abstract func spawn_props() -> Array[PropSpawner]

func get_frame() -> int: return get_suit_index()

#The suit PIP draws the sheet's own colours: suit_pips.png is authored in the palette, each frame
#already shaded with its suit's ramp, so recolouring it would flatten that shading to one index.

#⚠ IT MUST NOT CLEAR THE MATERIAL. The pip is an outline client, so clearing would strip the rim
#off whichever cards land on a recycled polygon; these polygons are pooled across cards, and the
#stale-state that invites is handled by overwriting every uniform instead.
func set_texture(polygon2d:Polygon2D) -> void:
	CardOutline.frame_polygon(
		polygon2d, SUIT_TEXTURE, SUIT_TEXTURE_H_FRAMES, SUIT_TEXTURE_V_FRAMES, get_suit_index())
	CardOutline.fill_texture(polygon2d)

#For the SUIT-AGNOSTIC art it shares with every other suit, the rank pip and the card art, never
#for the suit pip itself.

## Recolour `polygon2d` to this suit's palette entry.
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

#Self-inspection of the OWN card's statuses at spawn time. fire_mult multiplies the suit-effect
#prop COUNT only: one knob, no double-dip.
func fire_stacks() -> int:
	if not data: return 0
	for s : CardModifierStatus in data.statuses:
		if s is StatusBurning: return s.stacks
	return 0
func fire_mult() -> int:
	return 1 + fire_stacks()

# --- Shared spawn preamble (Phase 3) --------------------------------------------------------

#The board slot this suit launches from, or NOWHERE when it spawns nothing: an off-board card, or one
#whose cell's mark does not agree on SUIT -- a talent suppresses nothing, the mark's agreement is the
#whole gate. Reads the GRID index, not the legacy zone one, which never sees a grid card.
func _spawn_origin() -> BoardCoord:
	if not api or not api.is_live(): return BoardCoord.NOWHERE
	var coord : BoardCoord = api.grid_position_of(data)
	var matched : int = await MarkMatch.matches_at(api.board_state(), data, coord)
	if not (matched & MarkMatch.Property.SUIT): return BoardCoord.NOWHERE
	return coord

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

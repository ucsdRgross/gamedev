@tool
class_name PaletteRoles
extends Resource
## The RESOURCE OF POINTERS: semantic ROLE -> palette index, reached through PaletteDB.

#One named field per thing in the game that has a colour, so reassigning a colour is editing ONE
#entry in ONE place and a palette swap is survivable. The deferred surfaces, the map and the UI
#chrome, are listed in todo.md and warn every test run until their art exists.

#Roles are named for MEANING, like status_flame or suit_hoop, and never for colour: a role called
#`orange` is a literal wearing a costume, and it stops surviving the moment the palette changes.

#Named @export ints rather than a Dictionary (owner ruling): autocomplete-visible, compile-checked
#and inspector-editable. _validate_property() turns each role into a DROPDOWN of the live palette's
#entries and _get_property_list() appends a read-only swatch, both read at inspector time.

@export_group("Suits")
#Filled via Shaders/outline.gdshader's PALETTE fill mode, a Polygon2D having one material while
#these two elements need both the recolour and the rim. NOT the suit pip itself: suit_pips.png is
#authored in the palette and draws its own colours.

## Rank pip and card art on each suit's cards.
@export_range(0, 255, 1) var suit_hoop : int = 30
@export_range(0, 255, 1) var suit_knife : int = 11
@export_range(0, 255, 1) var suit_ball : int = 8
@export_range(0, 255, 1) var suit_fire : int = 2
@export_range(0, 255, 1) var suit_firework : int = 14

@export_group("Statuses")
## The flame drawn on a Burning card's status icon, and the ball on a Juggling one's.
@export_range(0, 255, 1) var status_flame : int = 30
@export_range(0, 255, 1) var status_ball : int = 6

@export_group("Effects")
## The juggled ball's specular dot. Its BODY tones are an ordered ramp, not a role — see PaletteRamp.
@export_range(0, 255, 1) var ball_gloss : int = 31

@export_group("The board plan")
## The outline an element takes while it matches the mark under a held card.
@export_range(0, 255, 1) var match_rim : int = 31
## The outline a matching element takes once the card has landed on that mark.
@export_range(0, 255, 1) var match_rim_active : int = 6

#⚠ `art_outline` AND `alert_glare` LIVE IN `OutlineStyle`, NOT HERE. They are the card outline's
#ink and its glare band, and keeping them here split ONE effect's tuning across two resources:
#judging an ink meant editing a different file from the one holding the rim's width and tempo.

#⚠ THAT IS NOT A BREACH OF THE PALETTE RULE, AND THE PRECEDENT IS PaletteRamp. The rule is no
#raw Color literals, every colour being a palette POINTER with exactly ONE home - not that every
#pointer lives in this file. ramp_fire.tres has always held its own Array[int] of indices.

#This file keeps the single semantic colours of THINGS, a suit or a status; an effect's own index
#set belongs with the effect, and they are still indices, so a palette swap still moves them. Do
#not "restore" them here: two homes for one pointer is worse than either home alone.

#The one list the previews, the range test and any future iteration read. Adding a role means
#adding its @export above and its name here.

## Every role, in inspector order.
const ROLE_NAMES : Array[StringName] = [
	&"suit_hoop", &"suit_knife", &"suit_ball", &"suit_fire", &"suit_firework",
	&"status_flame", &"status_ball",
	&"ball_gloss",
	&"match_rim", &"match_rim_active",
]

#Named access, roles.suit_hoop, is the normal path; this is for the tests and the previews, which
#iterate ROLE_NAMES.

## This role's palette index.
func index_of(role : StringName) -> int:
	return get(role)

#⚠ THERE IS NO `palette` FIELD HERE, and a field filled in by roles.tres while being described as
#"editor preview only" is exactly what let the preview and the game disagree, with only a test
#standing between them.

#Reading PaletteDB.PALETTE directly makes them the same fact rather than two facts pinned together.

## This role's colour, resolved against the LIVE palette.
func color_of(role : StringName) -> Color:
	var pal := PaletteDB.PALETTE
	if not pal: return Color.MAGENTA
	return pal.color(index_of(role))

# --- Editor conveniences (all @tool-only; none of this runs in a build) ----------------------------

#Rebuilt from the image each time the inspector asks, so swapping the palette re-labels every role
#with no code change.

## Turn every role int into a dropdown of the live palette's entries, colour named beside index.
func _validate_property(property : Dictionary) -> void:
	if not Engine.is_editor_hint(): return
	if property.name not in ROLE_NAMES: return
	var palette := PaletteDB.PALETTE
	if not palette or palette.width() == 0: return
	var parts : PackedStringArray = PackedStringArray()
	var cols := palette.colors()
	for i : int in range(cols.size()):
		parts.append("%d  #%s:%d" % [i, cols[i].to_html(false), i])
	property.hint = PROPERTY_HINT_ENUM
	property.hint_string = ",".join(parts)

#So the chosen entry is visible at a glance rather than only as a number.

## Append a read-only Color swatch per role.
func _get_property_list() -> Array[Dictionary]:
	var out : Array[Dictionary] = []
	if not Engine.is_editor_hint(): return out
	out.append({
		"name": "Swatches", "type": TYPE_NIL,
		"usage": PROPERTY_USAGE_GROUP, "hint_string": "swatch_",
	})
	for role : StringName in ROLE_NAMES:
		out.append({
			"name": "swatch_" + role, "type": TYPE_COLOR,
			"usage": PROPERTY_USAGE_EDITOR | PROPERTY_USAGE_READ_ONLY,
		})
	return out

func _get(property : StringName) -> Variant:
	if not property.begins_with("swatch_"): return null
	var role := StringName(String(property).trim_prefix("swatch_"))
	if role not in ROLE_NAMES: return null
	return color_of(role)

@tool
class_name PaletteRoles
extends Resource
## The RESOURCE OF POINTERS (owner T21): semantic ROLE -> palette index. One named field per thing
## in the game that has a colour, so reassigning a colour is editing ONE entry in ONE place, and a
## palette swap is survivable.
##
## Roles are named for MEANING (`status_flame`, `suit_hoop`), never for colour (`orange`) — a role
## called `orange` is a literal wearing a costume, and it is what stops surviving the moment the
## palette changes.
##
## Named @export ints rather than a Dictionary (owner ruling): autocomplete-visible, compile-checked,
## and inspector-editable. Two @tool conveniences make the ints readable while editing:
##   * _validate_property() turns each role into a DROPDOWN listing the live palette's entries with
##     their hex values, so the number is chosen with the colour in view;
##   * _get_property_list() appends a read-only Color swatch per role.
## Both read PaletteDB.PALETTE at inspector time, so neither can go stale against the image.
##
## Reached through PaletteDB. See ARCHITECTURE_REVIEW §4i; the deferred surfaces (map, UI chrome)
## are listed in todo.md and warn every test run until their art exists.

@export_group("Suits")
## Rank pip + card art on each suit's cards, via Assets/color_picker.gdshader. NOT the suit pip itself:
## suit_pips.png is authored in the palette and draws its own colours (ARCHITECTURE_REVIEW §4h).
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

## Every role, in inspector order. The one list the previews, the range test and any future iteration
## read — adding a role means adding its @export above and its name here.
const ROLE_NAMES : Array[StringName] = [
	&"suit_hoop", &"suit_knife", &"suit_ball", &"suit_fire", &"suit_firework",
	&"status_flame", &"status_ball",
	&"ball_gloss",
]

## This role's palette index. Named access (`roles.suit_hoop`) is the normal path; this is for the
## tests and the previews, which iterate ROLE_NAMES.
func index_of(role : StringName) -> int:
	return get(role)

## This role's colour, resolved against the LIVE palette.
##
## ⚠ THERE IS NO `palette` FIELD HERE, and there was one — an `@export` filled in by roles.tres and
## described as "editor preview only" while being what this function actually read. The preview and the
## game could therefore disagree, and only a test standing between them said otherwise (see
## PaletteRamp.colors, which had the same field with no test at all). Reading `PaletteDB.PALETTE`
## directly makes them the same fact rather than two facts pinned together.
func color_of(role : StringName) -> Color:
	var pal := PaletteDB.PALETTE
	if not pal: return Color.MAGENTA
	return pal.color(index_of(role))

# --- Editor conveniences (all @tool-only; none of this runs in a build) ----------------------------

## Turn every role int into a dropdown of the live palette's entries, so the index is picked with the
## colour named beside it. Rebuilt from the image each time the inspector asks, so swapping the
## palette re-labels every role with no code change.
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

## Append a read-only Color swatch per role, so the chosen entry is visible at a glance rather than
## only as a number.
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

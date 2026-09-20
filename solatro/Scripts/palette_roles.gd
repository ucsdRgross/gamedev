@tool
class_name PaletteRoles
extends Resource
## The RESOURCE OF POINTERS: semantic ROLE -> palette index, one field per coloured thing.

# Roles are named for MEANING (`status_flame`, `suit_hoop`), never for colour (`orange`) — a role
# called `orange` is a literal wearing a costume, and stops surviving the moment the palette
# changes.

# Named @export ints rather than a Dictionary (owner ruling): autocomplete-visible, compile-
# checked, inspector-editable. `_validate_property()` turns each into a dropdown of the live
# palette's own colours; `_get_property_list()` adds a read-only swatch per role.

# Reached through PaletteDB. The deferred surfaces (map, UI chrome) are listed in todo.md and warn
# every test run until their art exists.

@export_group("Suits")
## Rank pip + card art via the outline shader's PALETTE fill mode (not the suit pip, which is drawn).
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

@export_group("UI Chrome")
## The sidebar container's flat panel background (`HudContainer`).
@export_range(0, 255, 1) var hud_background : int = 17

## The Goal number once the running total has reached it, one beat before the show resolves.
@export_range(0, 255, 1) var goal_met : int = 9

# `art_outline` and `alert_glare` lived here and were MOVED, not copied, to `OutlineStyle`
# (`Shaders/Styles/outline_default.tres`) — they are one effect's ink and glare band, and splitting
# an effect's tuning across two resources is worse than splitting semantic colours across two homes.

# The rule stays *no raw Color literal; every colour is a palette POINTER with exactly one home* —
# not *every pointer lives in this file*. `ramp_fire.tres` has always kept its own index array
# alongside this one. Do not "restore" the moved fields here.

## Every role, in inspector order — adding one means adding its @export above and its name here.
const ROLE_NAMES : Array[StringName] = [
	&"suit_hoop", &"suit_knife", &"suit_ball", &"suit_fire", &"suit_firework",
	&"status_flame", &"status_ball",
	&"ball_gloss",
	&"hud_background", &"goal_met",
]

## This role's palette index. `roles.suit_hoop` is the normal path; this is for iterating ROLE_NAMES.
func index_of(role : StringName) -> int:
	return get(role)

## This role's colour, resolved against the LIVE palette — never cached, so a swap moves it for free.
func color_of(role : StringName) -> Color:
	var pal := PaletteDB.PALETTE
	if not pal: return Color.MAGENTA
	return pal.color(index_of(role))

# --- Editor conveniences (all @tool-only; none of this runs in a build) ----------------------------

## Turns each role int into a dropdown of the live palette's own entries, so it is picked by colour.
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

## Appends a read-only Color swatch per role, so the chosen entry is visible without decoding a number.
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

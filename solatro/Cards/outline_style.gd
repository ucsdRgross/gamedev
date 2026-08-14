@tool
class_name OutlineStyle
extends Resource
## EVERY TUNABLE OF THE CARD OUTLINE - ink, width, and both alert kinds - in one resource the GAME
## reads. Rules and landmines: ARCHITECTURE_REVIEW §4j. Shipped instance: `CardOutline.STYLE`.
##
## ⚠ **IT EXISTS SO THE ATLAS TOOL CHANGES THE GAME.** The knobs used to be `@export`s on the tool, so
## tuning moved a preview and the numbers still had to be re-typed into code by hand. Same arrangement
## `fx_editor` has with `FxStyle`.
##
## ⚠ **THE COLOURS BELONG HERE, NOT IN `PaletteRoles`.** §4i's rule is *one home per palette pointer*,
## not *every pointer in that file* - `ramp_fire.tres` has always held its own indices. Splitting one
## effect across two resources meant judging an ink here and editing it elsewhere. They were MOVED, not
## copied.
##
## ⚠ **The shipped instance is `CardOutline.STYLE`, not a const in here** - a `.tres` whose script IS
## this class comes back as a bare `Resource` while the class is still parsing, taking every dependent
## script down with it.

@export_group("The rim")
## ONE ink per card (design D7): face, pips and art all wear it, so the card reads as one object. 28 is
## `#290d2c`, the colour every type frame's ring used to be hand-painted in, so the default reproduces
## the old look. ⚠ **AUTHORED, NEVER DERIVED** (owner: *"I don't trust derived"*) - a contrast solver
## was designed and rejected; do not re-propose it. The atlas covers the gap that opened.
@export_range(0, 255, 1) var outline_index : int = 28

## Rim thickness in source texels (= art units on a card).
## ⚠ **IT CANNOT EXCEED `CardOutline.WIDTH`, and nothing enforces that.** That const is GEOMETRY - every
## polygon is baked at `frame + 2 * WIDTH` and `CARD_SIZE` derives from it - so above it the rim CLIPS at
## the polygon edge on every element. Below is safe (0 = off); wider is a scene re-bake. Deliberately not
## clamped: the atlas shows the clipping, and a silent clamp would hide the cost.
@export_range(0, 4, 1) var width : int = 1

@export_group("Glare")
## ONE FULL BOUNCE, as a fraction of `get_delay()`. ⚠ A fraction, never wall-clock (START_HERE rule 4):
## the cue announces a cascade paced the same way, so a fixed clock desyncs from it the moment the
## player changes speed.
@export_range(0.1, 8.0, 0.05) var glare_period_fraction : float = 1.0

## The band's entry. 31 is `#eddcc0`, the light colour most type frames are dominated by, so it reads
## against the dark inks the rim defaults to.
@export_range(0, 255, 1) var glare_color : int = 31

## Band thickness in CARD-SPACE art units. ⚠ Card space, not element space (D9): a band right for the
## card's 40-unit rim may barely register on a 10-unit pip, which sees only the slice crossing it. If it
## cannot serve both, the escape hatch is a per-host thickness scale. Judge it on the atlas's assembled
## card, not the grid.
@export_range(0.5, 40.0, 0.25) var glare_thickness : float = 8.0

## How far from each SIDE the glare stops, in card-space units.
## ⚠ **IT FIXES A STRUCTURAL BLINK, not a tuning accident** (owner): a card's side rims are
## VERTICAL LINES, so the band's centre reaching that x lights the whole side at once and off again - a
## flash, not a sweep. (Top and bottom never do it: they span the width, so the band crosses gradually.)
## The buffer clamps the sweep's endpoints AND suppresses the glare in the dead zone, so the band tapers
## instead of clipping. 0 = the old behaviour exactly.
@export_range(0.0, 20.0, 0.25) var glare_buffer : float = 4.0

@export_group("Throb")
## ONE FULL PULSE, as a fraction of `get_delay()` - its own knob: a sweeping band and a pulsing rim are
## different cues with no reason to share a tempo (owner).
@export_range(0.1, 8.0, 0.05) var throb_period_fraction : float = 0.5

## The entry the rim pulses to. THROB exists so a notification can name a hue (*"like red"*), so unlike
## the glare this is a statement rather than a fallback: 2 is `#e71b40`.
@export_range(0, 255, 1) var throb_color : int = 2

# --- Editor conveniences (all @tool-only; none of this runs in a build) ----------------------------

## The palette-index fields as DROPDOWNS of the live palette with hex values, so an index is picked with
## the colour in view - same shape as `PaletteRoles._validate_property`, and what lets these fields live
## out here without becoming unreadable ints.
const COLOR_FIELDS : Array[StringName] = [&"outline_index", &"glare_color", &"throb_color"]

func _validate_property(property : Dictionary) -> void:
	if not Engine.is_editor_hint(): return
	if property.name not in COLOR_FIELDS: return
	var palette := PaletteDB.PALETTE
	if not palette or palette.width() == 0: return
	var parts : PackedStringArray = PackedStringArray()
	var cols := palette.colors()
	for i : int in range(cols.size()):
		parts.append("%d  #%s:%d" % [i, cols[i].to_html(false), i])
	property.hint = PROPERTY_HINT_ENUM
	property.hint_string = ",".join(parts)

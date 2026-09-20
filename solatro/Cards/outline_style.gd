@tool
class_name OutlineStyle
extends Resource
## EVERY TUNABLE OF THE CARD OUTLINE - ink, width and every alert kind - in one resource.

#⚠ IT EXISTS SO THE ATLAS TOOL CHANGES THE GAME. Knobs that are @exports on the tool mean tuning
#moves a preview and the numbers still have to be re-typed into code by hand. Same arrangement
#fx_editor has with FxStyle.

#⚠ THE COLOURS BELONG HERE, NOT IN PaletteRoles. The rule is one home per palette pointer, not
#every pointer in that file - ramp_fire.tres has always held its own indices - and splitting one
#effect across two resources means judging an ink here and editing it elsewhere.

#⚠ The shipped instance is CardOutline.STYLE, not a const in here: a .tres whose script IS this
#class comes back as a bare Resource while the class is still parsing, taking every dependent
#script down with it.

@export_group("The rim")
#ONE ink per card: face, pips and art all wear it, so the card reads as one object. 28 is #290d2c,
#the colour every type frame's ring is painted in, so the default reproduces that look.

#⚠ AUTHORED, NEVER DERIVED (owner: *"I don't trust derived"*). A contrast solver was designed and
#rejected; do not re-propose it. The atlas covers the gap that opened.

## The card's outline ink, as a palette index.
@export_range(0, 255, 1) var outline_index : int = 28

#⚠ IT CANNOT EXCEED CardOutline.WIDTH, AND NOTHING ENFORCES THAT. That const is GEOMETRY - every
#polygon is baked at frame + 2 * WIDTH and CARD_SIZE derives from it - so above it the rim CLIPS at
#the polygon edge on every element. Below is safe, 0 being off; wider is a scene re-bake.

#Deliberately not clamped: the atlas shows the clipping, and a silent clamp would hide the cost.

## Rim thickness in source texels, which on a card are art units.
@export_range(0, 4, 1) var width : int = 1

@export_group("Glare")
#⚠ A fraction, never wall-clock: the cue announces a cascade paced the same way, so a fixed
#clock desyncs from it the moment the player changes speed.

## ONE FULL BOUNCE, as a fraction of get_delay().
@export_range(0.1, 8.0, 0.05) var glare_period_fraction : float = 1.0

#31 is #eddcc0, the light colour most type frames are dominated by, so it reads against the dark
#inks the rim defaults to.

## The glare band's palette entry.
@export_range(0, 255, 1) var glare_color : int = 31

#⚠ Card space, not element space: a band right for the card's 40-unit rim may barely register on
#a 10-unit pip, which sees only the slice crossing it. If it cannot serve both, the escape hatch is
#a per-host thickness scale. Judge it on the atlas's assembled card, not the grid.

## Band thickness in CARD-SPACE art units.
@export_range(0.5, 40.0, 0.25) var glare_thickness : float = 8.0

#⚠ IT FIXES A STRUCTURAL BLINK, NOT A TUNING ACCIDENT (owner). A card's side rims are VERTICAL
#LINES, so the band's centre reaching that x lights the whole side at once and off again - a flash,
#not a sweep. Top and bottom never do it: they span the width, so the band crosses gradually.

#The buffer clamps the sweep's endpoints AND suppresses the glare in the dead zone, so the band
#tapers instead of clipping. 0 is no buffer at all.

## How far from each SIDE the glare stops, in card-space units.
@export_range(0.0, 20.0, 0.25) var glare_buffer : float = 4.0

@export_group("Throb")
#Its own knob: a sweeping band and a pulsing rim are different cues with no reason to share a
#tempo (owner).

## ONE FULL PULSE, as a fraction of get_delay().
@export_range(0.1, 8.0, 0.05) var throb_period_fraction : float = 0.5

#THROB exists so a notification can name a hue (*"like red"*), so unlike the glare this is a
#statement rather than a fallback: 2 is #e71b40.

## The entry the rim pulses to.
@export_range(0, 255, 1) var throb_color : int = 2

@export_group("Shimmer")
# ITS OWN KNOB, like the other two tempos: three cues with no reason to share a period. The owner
# asked for a SLOW drift, so this is the longest of the three.
## ONE FULL PASS along the ramp and back, as a fraction of `get_delay()`.
@export_range(0.1, 8.0, 0.05) var shimmer_period_fraction : float = 2.0

# A RAMP rather than a second colour: the owner asked for a rainbow, and an ordered list of palette
# entries is this project's one way to say that.
## The entries the rim drifts through, first one first.
@export var shimmer_ramp : PaletteRamp = null:
	set(value):
		shimmer_ramp = value
		_shimmer_tex = null

var _shimmer_tex : ImageTexture = null

## The ramp as an N x 1 strip the shader reads, cached like the ball's tones.
func shimmer_texture() -> ImageTexture:
	if _shimmer_tex: return _shimmer_tex
	if not shimmer_ramp: return null
	_shimmer_tex = shimmer_ramp.tones_texture()
	return _shimmer_tex

# --- Editor conveniences (all @tool-only; none of this runs in a build) ----------------------------

#The same shape as PaletteRoles._validate_property, and what lets these fields live out here
#without becoming unreadable ints.

## The palette-index fields as DROPDOWNS of the live palette, so an index is picked with the colour.
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

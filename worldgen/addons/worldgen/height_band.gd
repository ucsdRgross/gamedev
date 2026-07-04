@tool  # edited in the inspector + used by edit-time repaints
class_name WorldHeightBand
extends Resource

## One elevation band for WorldHeightColorizer: land pixels with height below
## `upper` (and above the previous band's upper) take this band's color. Bands
## are authored in ascending `upper` order; the last band is open-ended.

## Upper height limit of this band (exclusive). The colorizer walks bands in
## array order and uses the first band whose upper exceeds the pixel height.
@export var upper: float = 1.0
## Fill color for heights inside this band.
@export var color: Color = Color.WHITE
## true = lerp from this band's color toward the NEXT band's color across the
## band's height interval (smooth gradient); false = flat fill (hard step).
@export var smooth: bool = false


## Convenience constructor so default band ramps can be built in one line.
static func make(p_upper: float, p_color: Color, p_smooth: bool = false) -> WorldHeightBand:
	var b := WorldHeightBand.new()
	b.upper = p_upper
	b.color = p_color
	b.smooth = p_smooth
	return b

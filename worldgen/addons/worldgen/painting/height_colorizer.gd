@tool  # edited in the inspector + used by edit-time repaints
class_name WorldHeightColorizer
extends Resource

## User-configurable land/water palette for the 2D map. Land is colored by an
## ordered array of height bands (any count, ascending `upper`, last band
## open-ended); water colors cover ocean, lakes, and the river elevation ramp.
## The defaults (make_default) reproduce the classic 6-stop topo look.

## Land bands in ascending `upper` order. The first band whose upper exceeds
## the pixel height wins; a `smooth` band lerps toward the next band's color.
@export var bands: Array[WorldHeightBand] = []
## Fill for pixels below the ocean threshold.
@export var ocean_color: Color = Color("#1a365d")
## River tint at low (near-sea) elevation; rivers ramp from this to river_color_high.
@export var river_color_low: Color = Color("#0c4a6e")
## River tint at high elevation.
@export var river_color_high: Color = Color("#e0f2fe")
## Flat color for lakes (distinct from rivers).
@export var lake_color: Color = Color("#1d4ed8")


## Default band ramp matching the historical topo_color 6-stop look, keyed on
## the current ocean/mountain thresholds so coast and hill cutoffs track them.
static func make_default(oth: float = 0.38, mth: float = 0.65) -> WorldHeightColorizer:
	var c := WorldHeightColorizer.new()
	c.bands = [
		WorldHeightBand.make(oth + 0.04, Color("#2b6cb0")),  # coast shallows
		WorldHeightBand.make(0.46, Color("#2f855a")),        # plains
		WorldHeightBand.make(mth, Color("#ecc94b")),         # hills
		WorldHeightBand.make(0.82, Color("#718096")),        # rock
		WorldHeightBand.make(999.0, Color("#ffffff")),       # snow (open-ended)
	]
	return c


## Shared band walk for ANY ascending band array (this colorizer's bands or a
## WorldBiome's per-biome ramp): first band whose upper exceeds h wins; a
## smooth band lerps to the next band's color across its height interval.
static func eval_bands(p_bands: Array[WorldHeightBand], h: float) -> Color:
	var lower := -INF
	for i in range(p_bands.size()):
		var b := p_bands[i]
		if h >= b.upper and i < p_bands.size() - 1:
			lower = b.upper
			continue
		if b.smooth and i < p_bands.size() - 1:
			var span := maxf(1e-6, b.upper - lower)
			var t := clampf((h - lower) / span, 0.0, 1.0) if lower > -INF else 0.0
			return b.color.lerp(p_bands[i + 1].color, t)
		return b.color
	return Color.MAGENTA  # no bands configured: loud fallback


## Color for a LAND pixel at height `h` from this colorizer's own bands.
## Callers guarantee h >= ocean threshold (water is colored separately).
func land_color(h: float) -> Color:
	return eval_bands(bands, h)


## River color at water-surface height `wv`, ramped low->high over the land
## height range above the ocean threshold `oth`.
func river_color(wv: float, oth: float) -> Color:
	var t := clampf((wv - oth) / maxf(0.001, 1.0 - oth), 0.0, 1.0)
	return river_color_low.lerp(river_color_high, t)

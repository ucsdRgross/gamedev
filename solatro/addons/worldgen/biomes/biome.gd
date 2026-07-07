@tool  # edited in the inspector + read by edit-time repaints
class_name WorldBiome
extends Resource

## One biome the generator can paint: identity + casting flags, a soft climate
## prior used when filling land no graph node claimed, a per-biome height band
## ramp for the painter, and a stack of decoration layers. Collected into a
## WorldBiomeSet; the biome's id at generation time is its index in that set.

## Display / lookup name (also the key used by graph.json biome legends).
@export var name: StringName = &"Biome"

@export_group("Casting")
## May be drawn into the per-seed required cast (the biomes every path is
## guaranteed to encounter).
@export var required_eligible: bool = true
## Never gets gameplay duty (overrides required_eligible); filler/ambient only.
@export var ambient_only: bool = false
## Force this biome into the required cast on every map.
@export var force_include: bool = false

@export_group("Climate prior")
## Filler-score multiplier: higher = this biome fills more unclaimed land.
@export var weight: float = 1.0
## Soft height range [lo, hi] this biome prefers (filler scoring only; pinned
## node biomes go wherever their node is).
@export var height_range: Vector2 = Vector2(0.38, 0.80)
## Soft moisture range [lo, hi] against the baked humidity noise.
@export var moisture_range: Vector2 = Vector2(0.0, 1.0)

@export_group("Look")
## Per-biome land ramp, ascending `upper` order (same band rules as
## WorldHeightColorizer; evaluated via its shared band walk).
@export var bands: Array[WorldHeightBand] = []

@export_group("Decorations")
## Decoration layers stamped inside this biome, each with its own art/density/
## stacking (see WorldDecoLayer). Empty = a clean biome.
@export var decos: Array[WorldDecoLayer] = []


## One-line constructor for default rosters: `opts` may override any exported
## field by property name (e.g. {"weight": 2.0, "ambient_only": true}).
static func make(p_name: StringName, p_bands: Array[WorldHeightBand], opts: Dictionary = {}) -> WorldBiome:
	var b := WorldBiome.new()
	b.name = p_name
	b.bands = p_bands
	for k in opts:
		if k == "decos":
			# set() silently rejects a plain Array into the TYPED decos array;
			# assign() converts element-by-element instead.
			b.decos.assign(opts[k])
		else:
			b.set(k, opts[k])
	return b

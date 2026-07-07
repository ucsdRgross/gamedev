@tool  # edited in the inspector + read by edit-time repaints
class_name WorldDecoLayer
extends Resource

## One decoration layer inside a biome (a WorldBiome holds an ARRAY of these,
## so a forest can stack trees + undergrowth + mushrooms, each with its own
## density). Drop your own pixel art into `textures` -- stamps are scaled by
## `scale_range` and tinted by `color`; with no textures the procedural `mark`
## shape draws instead.

## Procedural marks used when no textures are assigned.
enum Mark { NONE, TREE, ROCK, TUFT, SHARD, MUSHROOM }

## Your stamp art (any Texture2D; small pixel art works best). One is picked at
## random per stamp. Empty = draw the procedural `mark`.
@export var textures: Array[Texture2D] = []
## Procedural fallback shape when `textures` is empty.
@export var mark: Mark = Mark.TREE
## Stamps per 1000 land pixels of this biome (multiplied by the global
## WorldSettings.biome_deco_density_mul). 10-20 reads as a dense forest.
@export var density: float = 6.0
## Random per-stamp scale range [min, max].
@export var scale_range: Vector2 = Vector2(0.8, 1.3)
## Modulate color for textures / fill color for procedural marks.
@export var color: Color = Color.WHITE
## true = may overlap other decorations (undergrowth, ground cover); false =
## keeps a small clearance from other non-stackable stamps.
@export var stackable: bool = false


## One-line constructor for default rosters.
static func make(p_mark: Mark, p_density: float, p_color: Color,
		p_stackable: bool = false, p_scale: Vector2 = Vector2(0.8, 1.3)) -> WorldDecoLayer:
	var d := WorldDecoLayer.new()
	d.mark = p_mark
	d.density = p_density
	d.color = p_color
	d.stackable = p_stackable
	d.scale_range = p_scale
	return d

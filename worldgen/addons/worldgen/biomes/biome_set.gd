@tool  # edited in the inspector + read by edit-time repaints
class_name WorldBiomeSet
extends Resource

## The designer-facing biome configuration: ONE pool of WorldBiome resources
## plus the per-path guarantee count. Per seed, the generator draws a required
## "cast" from the pool (force_include first); every start->end path is then
## guaranteed to cross `required_count` DISTINCT cast biomes -- which ones
## depends on the route. Unclaimed land fills from the same pool by climate
## prior (ambient_only biomes fill but never take gameplay duty).

## The single biome pool. A biome's id at generation time is its index here;
## reordering between Generate and Repaint mismatches colors (regenerate).
@export var biomes: Array[WorldBiome] = []
## N distinct required biomes guaranteed on every start->end path.
@export_range(0, 8) var required_count: int = 3
## Global high-altitude override: land above this height paints snow_color
## regardless of biome (0 = disabled).
@export var snow_line: float = 0.85
## Color used above snow_line.
@export var snow_color: Color = Color("#f5f7fa")


## Draw the per-seed required cast: force_include biomes first (array order),
## then a single rng-shuffled deal of the remaining eligible biomes, truncated
## to `slots`. One deal = rung draws are disjoint by construction.
func draw_required_cast(rng: RandomNumberGenerator, slots: int) -> PackedInt32Array:
	var forced: Array = []
	var pool: Array = []
	for i in range(biomes.size()):
		var b := biomes[i]
		if b == null or b.ambient_only or not b.required_eligible:
			continue
		if b.force_include:
			forced.append(i)
		else:
			pool.append(i)
	for j in range(pool.size() - 1, 0, -1):   # Fisher-Yates with the caller's rng
		var k := rng.randi_range(0, j)
		var tmp = pool[j]
		pool[j] = pool[k]
		pool[k] = tmp
	var cast := PackedInt32Array()
	for i in forced + pool:
		if cast.size() >= slots:
			break
		cast.append(i)
	return cast


## Index of the biome named `p_name`, or -1 (used by legends and lookups).
func index_of(p_name: StringName) -> int:
	for i in range(biomes.size()):
		if biomes[i] != null and biomes[i].name == p_name:
			return i
	return -1


## Three-band ramp helper for the default roster: low band hard, mid band
## smooth (lerps toward the high band), high band open-ended.
static func _ramp(c_low: String, c_mid: String, c_high: String) -> Array[WorldHeightBand]:
	var r: Array[WorldHeightBand] = [
		WorldHeightBand.make(0.46, Color(c_low)),
		WorldHeightBand.make(0.70, Color(c_mid), true),
		WorldHeightBand.make(999.0, Color(c_high)),
	]
	return r


## Shipped 16-biome roster so a drop-in WorldMap2D gets themed maps with zero
## setup. Pure data -- designers add/remove/edit freely in the inspector.
static func make_default() -> WorldBiomeSet:
	var s := WorldBiomeSet.new()
	var M := WorldDecoLayer.Mark
	s.biomes = [
		WorldBiome.make(&"Meadow", _ramp("#8bc34a", "#a5d66f", "#c5e1a5"),
			{"height_range": Vector2(0.38, 0.55), "moisture_range": Vector2(0.30, 0.70),
			"decos": [WorldDecoLayer.make(M.TUFT, 9.0, Color("#5d8f3a"), true)]}),
		WorldBiome.make(&"Forest", _ramp("#2f855a", "#38a169", "#68d391"),
			{"force_include": true, "height_range": Vector2(0.40, 0.65),
			"moisture_range": Vector2(0.40, 0.80),
			"decos": [WorldDecoLayer.make(M.TREE, 14.0, Color("#1d5c3c")),
				WorldDecoLayer.make(M.TUFT, 5.0, Color("#2f7a4d"), true)]}),
		WorldBiome.make(&"Dark Forest", _ramp("#1c3a2a", "#22543d", "#2f5d46"),
			{"height_range": Vector2(0.42, 0.70), "moisture_range": Vector2(0.50, 0.90),
			"decos": [WorldDecoLayer.make(M.TREE, 18.0, Color("#0e211a")),
				WorldDecoLayer.make(M.MUSHROOM, 2.0, Color("#7a6a8f"), true)]}),
		WorldBiome.make(&"Jungle", _ramp("#276749", "#2f9e44", "#69db7c"),
			{"height_range": Vector2(0.38, 0.55), "moisture_range": Vector2(0.70, 1.00),
			"decos": [WorldDecoLayer.make(M.TREE, 22.0, Color("#1a6b2f")),
				WorldDecoLayer.make(M.TUFT, 8.0, Color("#2f9e44"), true)]}),
		WorldBiome.make(&"Swamp", _ramp("#4a5d23", "#6b7f3a", "#8a9a5b"),
			{"height_range": Vector2(0.38, 0.46), "moisture_range": Vector2(0.70, 1.00),
			"decos": [WorldDecoLayer.make(M.TUFT, 12.0, Color("#39481c"), true),
				WorldDecoLayer.make(M.TREE, 3.0, Color("#3a4526"))]}),
		WorldBiome.make(&"Savanna", _ramp("#a98f3e", "#c2a94e", "#d9c26b"),
			{"height_range": Vector2(0.40, 0.55), "moisture_range": Vector2(0.20, 0.50),
			"decos": [WorldDecoLayer.make(M.TREE, 3.0, Color("#6e5c26")),
				WorldDecoLayer.make(M.TUFT, 4.0, Color("#8f7a33"), true)]}),
		WorldBiome.make(&"Desert", _ramp("#c9a25f", "#e3c078", "#edd9a3"),
			{"height_range": Vector2(0.38, 0.60), "moisture_range": Vector2(0.00, 0.30),
			"decos": [WorldDecoLayer.make(M.ROCK, 3.0, Color("#8f7440"))]}),
		WorldBiome.make(&"Badlands", _ramp("#8f4a33", "#b05b3b", "#c97a4a"),
			{"height_range": Vector2(0.50, 0.75), "moisture_range": Vector2(0.00, 0.35),
			"decos": [WorldDecoLayer.make(M.ROCK, 5.0, Color("#5f3122"))]}),
		WorldBiome.make(&"Tundra", _ramp("#8fa39a", "#a8b8b0", "#c4d1c9"),
			{"height_range": Vector2(0.45, 0.70), "moisture_range": Vector2(0.20, 0.60),
			"decos": [WorldDecoLayer.make(M.ROCK, 3.0, Color("#66756e")),
				WorldDecoLayer.make(M.TUFT, 2.0, Color("#7d8f83"), true)]}),
		WorldBiome.make(&"Frozen Wastes", _ramp("#b8cbdc", "#dfe9f2", "#ffffff"),
			{"height_range": Vector2(0.40, 0.90),
			"decos": [WorldDecoLayer.make(M.SHARD, 4.0, Color("#8fa8bf"))]}),
		WorldBiome.make(&"Ashlands", _ramp("#3b3138", "#5a4a4a", "#8a4a3e"),
			{"height_range": Vector2(0.55, 1.00), "moisture_range": Vector2(0.00, 0.40),
			"decos": [WorldDecoLayer.make(M.ROCK, 5.0, Color("#241d22")),
				WorldDecoLayer.make(M.SHARD, 1.5, Color("#b0502f"))]}),
		WorldBiome.make(&"Highlands", _ramp("#718096", "#8b9bb0", "#a0aec0"),
			{"height_range": Vector2(0.60, 0.95),
			"decos": [WorldDecoLayer.make(M.ROCK, 6.0, Color("#4a5568"))]}),
		WorldBiome.make(&"Mushroom Grove", _ramp("#6d5a92", "#9f7aea", "#c3a6e8"),
			{"height_range": Vector2(0.40, 0.60), "moisture_range": Vector2(0.50, 0.90),
			"decos": [WorldDecoLayer.make(M.MUSHROOM, 14.0, Color("#4c3d6b")),
				WorldDecoLayer.make(M.TUFT, 4.0, Color("#8a76ad"), true)]}),
		WorldBiome.make(&"Blighted", _ramp("#3e2f45", "#4d3b52", "#6d4c6e"),
			{"height_range": Vector2(0.38, 0.80),
			"decos": [WorldDecoLayer.make(M.SHARD, 6.0, Color("#2a1f30")),
				WorldDecoLayer.make(M.TREE, 2.0, Color("#241a2b"))]}),
		WorldBiome.make(&"Crystal Wastes", _ramp("#4e9ea3", "#6ec6ca", "#a0e7eb"),
			{"height_range": Vector2(0.45, 0.80), "moisture_range": Vector2(0.00, 0.40),
			"decos": [WorldDecoLayer.make(M.SHARD, 5.0, Color("#2f7075"))]}),
		WorldBiome.make(&"Salt Flats", _ramp("#d0cabb", "#e8e4da", "#f5f2ea"),
			{"ambient_only": true, "height_range": Vector2(0.38, 0.45),
			"moisture_range": Vector2(0.00, 0.20)}),
	]
	return s

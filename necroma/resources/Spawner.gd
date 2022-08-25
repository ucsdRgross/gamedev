extends Node

#units made will be stored into Tier folders
#spawner works similar to tft store
#depending on time elapsed, different chance to get units from each tier
#then choose random unit from the tier to spawn in
#for example, minute 1 will have 100% tier 1 units
#minute 2 75% tier 1 units, 25% tier 2 units
#check tft store level system for more detail
#each minute will also have different amount enemies spawned per beat

onready var rng = RandomNumberGenerator.new()
var spawnee_parent : Node

var loot_table_ratios = [100,0,0,0,0]
#example loot table [0,5,20,50,100] 0% tier 0, 5% tier 1, 15% tier 2, 30% tier 3, 50% tier 4
var enemies_per_spawn : int = 1
var spawn_tiles : PoolVector2Array

func _ready():
	randomize()
	
func setup(tiles : PoolVector2Array, node_path : Node) -> void:
	spawn_tiles = tiles
	spawnee_parent = node_path

func spawn() -> void:
	var tiles : Array = spawn_tiles
	tiles.shuffle()
	for i in enemies_per_spawn:
		if i > tiles.size():
			break
		var enemy: Unit = random_unit()
		spawnee_parent.add_child(enemy)
		enemy.setup(tiles[i])
		print(tiles[i])

#choose random unit based off current loot table
func random_unit() -> Node:
	var rng_roll : int = rng.randi_range(0,100)
	var tier : int
	#get tier
	for i in loot_table_ratios.size():
		if rng_roll <= loot_table_ratios[i]:
			tier = i
			break
	#get random unit from tier
	var parent : Node = get_node("Tier " + str(tier))
	var table : Array = parent.get_children()
	var unit : InstancePlaceholder = table[rng.randi() % table.size()]
	var instance : Unit = unit.create_instance()
	parent.remove_child(instance)
	return instance

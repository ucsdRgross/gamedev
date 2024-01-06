extends Node3D

@export var spawn_cap : int = 10
@export var spawn_interval : float = 5
@export var spawn_radius : float = 10

@onready var timer = $Timer
@onready var spawnlings = $Spawnlings

# Called when the node enters the scene tree for the first time.
func _ready():
	timer.wait_time = spawn_interval
	timer.start()

func _on_timer_timeout():
	if spawn_cap <= 0:
		timer.stop()
		return
	spawn_cap -= 1
	var spawnling = spawnlings.get_children().pick_random().create_instance()
	spawnlings.remove_child(spawnling)
	spawnling.position = rand_point_ring()
	spawnling.team = spawn_cap
	owner.add_child(spawnling)
	
	
func rand_point_ring() -> Vector3:
	var r = spawn_radius * sqrt(randf())
	var theta = randf() * 2 * PI
	var x = global_position.x + r * cos(theta)
	var z = global_position.z + r * sin(theta)
#	var angle := randf() * PI * 2
#	return Vector3(cos(angle)*spawn_radius, 1, sin(angle)*spawn_radius)
	return Vector3(x, global_position.y + 5, z)
	

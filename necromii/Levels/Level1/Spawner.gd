extends Node3D

@export var spawn_cap : int = 10
@export var spawn_interval : float = 5

@onready var timer = $Timer
@onready var spawnlings = $Spawnlings

# Called when the node enters the scene tree for the first time.
func _ready():
	timer.wait_time = spawn_interval
	timer.start()

func _on_timer_timeout():
	spawn_cap -= 1
	#var spawnling = spawnlings.get_children().pick_random().create_instance(false, get_parent())
	#print(spawnling)
	#print(spawnling)
	#spawnling.position.y = 10
	#get_parent().add_child(spawnling)
	
	if spawn_cap <= 0:
		timer.stop()
	
	

extends Node3D
class_name AI 

@onready var body : Unit = get_parent()

var lock : Callable = Callable()

#func _ready():
	#body.state_process.connect(tick)

func tick(state: PhysicsDirectBodyState3D):
	pass

func interrupt():
	if lock: 
		lock.call()
		lock = Callable()

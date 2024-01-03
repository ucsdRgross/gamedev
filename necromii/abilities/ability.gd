extends Node3D
class_name Ability

@onready var body : Unit = get_parent()

func lock():
	body.lock(Callable())

func unlock():
	body.unlock()

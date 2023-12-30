extends Node3D
class_name Ability

func _ready():
	assert(get_parent() is Unit)

func can_cast() -> bool:
	return true

func lock():
	get_parent().lock(Callable())

func unlock():
	get_parent().unlock()

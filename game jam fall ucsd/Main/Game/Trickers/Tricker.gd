extends Node2D

onready var pf = get_parent()

export var start_pos = 0.0
export var speed = 150

func _ready():
	pf.set_offset(start_pos)

func _physics_process(delta):
	var prepos = pf.get_global_position()
	pf.set_offset(pf.get_offset() + speed * delta)
	var pos = pf.get_global_position()
	rotate(5*delta)

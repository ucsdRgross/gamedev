extends Node2D


onready var board = $grid
onready var sprite = $guy

func _ready():
	sprite.global_position = board.global_position



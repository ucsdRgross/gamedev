extends Camera3D

@onready var character = $"../Character"

@onready var offset = global_position - character.global_position

# Called when the node enters the scene tree for the first time.
func _ready():
	pass

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	position = character.global_position + offset
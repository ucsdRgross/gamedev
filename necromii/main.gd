extends Node3D

@onready var selection_tool = $SelectionTool
@onready var player = $Player



# Called when the node enters the scene tree for the first time.
func _ready():
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	var i = selection_tool.in_selection(player.position)
	print(i)

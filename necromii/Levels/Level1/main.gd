extends Node3D

#@onready var selection_tool = $SelectionTool
#@onready var player = $Player
@export var camera : Camera3D


# Called when the node enters the scene tree for the first time.
func _ready():
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	#var i = selection_tool.in_selection(player.position)
	#print(i)
	pass

func _physics_process(delta):
	if Input.is_action_pressed("Left Click"):
		var mouse_pos := get_viewport().get_mouse_position()
		var ray_length := 100
		var from := camera.project_ray_origin(mouse_pos)
		var to := from + camera.project_ray_normal(mouse_pos) * ray_length
		var space := get_world_3d().direct_space_state
		var ray_query := PhysicsRayQueryParameters3D.new()
		ray_query.from = from
		ray_query.to = to
		ray_query.collide_with_areas = true
		var raycast_result := space.intersect_ray(ray_query)
		var posa : Vector3 = raycast_result["position"]
		var posb : Vector3 = $Player.position
		var dir := (posa-posb)
		dir.y /= 2
		$Player.movement_physics.set_look_direction(dir.normalized())
	

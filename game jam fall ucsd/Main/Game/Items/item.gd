class_name Item
extends KinematicBody2D

var knock_back = Vector2.ZERO

const FRICT = 1200
const ACCEL = 300

var interactable = false

onready var hitbox = $Hitbox
onready var label = $Label

var id = "Item"

var knockback_enabled = true
#func _init(item_name):
#	id = item_name

func _ready():
	setup()
	label.text = id
	
func setup():
	pass
	
func new_id(name):
	id = name
	label.text = id
	
func _physics_process(delta):
	if knock_back != Vector2.ZERO:
		knock_back = knock_back.move_toward(Vector2.ZERO, FRICT * delta)
		knock_back = move_and_slide(knock_back)

func enable_detection(value):
	knockback_enabled = value
	hitbox.set_collision_layer_bit(0,value)
	hitbox.set_collision_mask_bit(0,value)
	#hitbox.set_collision_layer_bit(1,value)
	#hitbox.set_collision_mask_bit(1,value)
	set_collision_layer_bit(0,value)
		
#	hitbox.monitorable = value
#	hitbox.monitoring = value

func _on_Hitbox_area_entered(area):
	if area.name == "Detector":
		interactable = true
		return
	if knockback_enabled:
		knock_back = global_position - area.get_parent().global_position
		knock_back = knock_back.normalized() * ACCEL

func _on_Hitbox_area_exited(area):
	if area.name == "Detector":
		interactable = false


func _on_Hitbox_input_event(viewport, event, shape_idx):
	if event.is_action_pressed("click") and interactable and PlayerHolding.is_empty():
		enable_detection(false)
		get_parent().remove_child(self)
		PlayerHolding.path.add_child(self)
		self.global_position = PlayerHolding.path.global_position
		

func _on_Hitbox_mouse_entered():
	label.visible = true


func _on_Hitbox_mouse_exited():
	label.visible = false

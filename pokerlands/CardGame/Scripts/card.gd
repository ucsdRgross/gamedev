extends RigidBody2D
class_name Card

var rank : int = 0 :
	set (value):
		rank = value
		($Markings/Rank as Label).text = str(rank)
		($Markings2/Rank as Label).text = str(rank)
var suit : int = 0 :
	set (value):
		suit = value
		var suits : String = "♠♣♥♦"
		($Markings/Suit as Label).text = suits[suit]
		($Markings2/Suit as Label).text = suits[suit]
var held := false
var in_play := true
var goal_position : Vector2
var tween : Tween
var parent_zone : CardZone

static var num_cards : int = 0

@onready var back_face: Sprite2D = $CollisionShape2D/BackFace
@onready var front_face: Sprite2D = $CollisionShape2D/FrontFace

signal clicked

func _ready() -> void:
	show_back()

func _enter_tree() -> void:
	num_cards += 1
	
func _exit_tree() -> void:
	num_cards -= 1

func _physics_process(_delta:float) -> void:
	if held:
		pass

func _on_control_gui_input(event: InputEvent) -> void:
	process_event(event)

			
func process_event(event:InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_event : InputEventMouseButton = event
		if mouse_event.button_index == MOUSE_BUTTON_LEFT and mouse_event.pressed:
			#print("clicked")
			if in_play:
				clicked.emit(self)

func pickup() -> void:
	if held:
		return
	held = true
	z_index = num_cards	

func drop() -> void:
	if held:
		held = false
		z_index = 0

func show_front()  -> void:
	front_face.show()
	back_face.hide()

func show_back()  -> void:
	front_face.hide()
	back_face.show()

func tween_move(pos : Vector2 = goal_position, anim_time : float = 0.2):
	if tween and tween.is_running():
		tween.kill()
	tween = create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "global_position", pos, anim_time)
	if abs(int(rotation_degrees)) % 180 != 0:
		tween.parallel().set_ease(Tween.EASE_IN_OUT)
		tween.tween_property(self, "rotation", roundf(rotation/PI)*PI, anim_time)

extends RigidBody3D
class_name Unit 

@export var ai : AI = AI.new()
@export var texture : Texture2D
@export var stats : Stats = Stats.new()
#@export var effects : Array[Effect]

var team : int

@export_category('Abilities')
@export var movement_ability : Movement = Movement.new()
@export var attack_ability : Attack = Attack.new()
@export var action_ability : Action = Action.new()

@onready var collision : CollisionShape3D = $Collision
@onready var hurt_box : Area3D = $HurtBox
@onready var navigation_agent : NavigationAgent3D = $NavigationAgent3D
@onready var health_bar : Sprite3D = $HealthBar
@onready var mesh : MeshInstance3D = $ShearTransform/MeshInstance3D
@onready var attack_range : Area3D = $AttackRange
@onready var detect_range : Area3D = $DetectRange
@onready var ground_cast : ShapeCast3D = $GroundCast
@onready var animation_player : AnimationPlayer = $AnimationPlayer

func _ready():
	replaceAI(ai)

func _physics_process(delta):
	ai.tick(delta)

func replaceAI(new_ai : AI):
	ai = new_ai.duplicate()
	ai.setup(self)

#pass in callable for interrupting locked state
#for example, if locked due to action, callable interrupts action before unlocking
func lock(interrupt : Callable):
	ai.lock = interrupt

func unlock():
	ai.lock = Callable()

func interrupt():
	ai.interrupt()

func replaceMovement(m : Movement):
	movement_ability.queue_free()
	movement_ability = m
	movement_ability.setup(self)

func move(delta : float, dir : Vector3):
	movement_ability.move(delta, dir)

func can_move() -> bool:
	return movement_ability.can_cast()

func replaceAction(a : Action):
	action_ability.queue_free()
	action_ability = a
	action_ability.setup(self)

func action():
	action_ability.action()

func can_action() -> bool:
	return action_ability.can_cast()
	
func replaceAttack(a : Attack):
	attack_ability.queue_free()
	attack_ability = a
	attack_ability.setup(self)

func attack(target : RigidBody3D):
	attack_ability.attack(target)

func can_attack() -> bool:
	return attack_ability.can_cast()

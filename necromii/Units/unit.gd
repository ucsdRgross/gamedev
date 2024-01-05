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

@onready var sphere : CollisionShape3D = $Sphere
@onready var box : CollisionShape3D = $Box
@onready var hurt_box : Area3D = $HurtBox
@onready var navigation_agent : NavigationAgent3D = $NavigationAgent3D
@onready var health_bar : Sprite3D = $HealthBar
@onready var model : MeshInstance3D = $ShearTransform/MeshInstance3D
@onready var model_transform : Node3D = $ShearTransform

func _physics_process(delta):
	ai.tick(delta)

func replaceAI(new_ai : AI):
	pass
	#ai = new_ai.duplicate()
	#ai.setup(self)

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
	pass
	#movement_ability.setup(self)

func move(delta : float, dir : Vector3):
	movement_ability.move(delta, dir)

#func can_move() -> bool:
	#return movement_ability.can_cast()

func replaceAction(a : Action):
	action_ability.queue_free()
	action_ability = a
	pass
	#action_ability.setup(self)

func action():
	action_ability.action()

#func can_action() -> bool:
	#return action_ability.can_cast()
	
func replaceAttack(a : Attack):
	attack_ability.queue_free()
	attack_ability = a
	pass
	#attack_ability.setup(self)

func attack():
	attack_ability.attack()

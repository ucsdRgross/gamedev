extends RigidBody3D
class_name Unit 

@export var ai : AI
@export var texture : Texture2D
@export var stats : Stats = Stats.new()
#@export var effects : Array[Effect]

var team : int

@export_category('Abilities')
@export var movement_ability : Movement
@export var action_ability : Action
@export var attack_ability : Attack

@onready var collision : CollisionShape3D = $Collision
@onready var navigation_agent : NavigationAgent3D = $NavigationAgent3D
@onready var health_bar : Sprite3D = $HealthBar
@onready var mesh : MeshInstance3D = $ShearTransform/MeshInstance3D
@onready var attack_range : Area3D = $AttackRange
@onready var detect_range : Area3D = $DetectRange
@onready var ground_cast : ShapeCast3D = $GroundCast
@onready var animation_player : AnimationPlayer = $AnimationPlayer

func _ready():
	replaceAI(ai if ai else AI.new())
	replaceMovement(movement_ability if movement_ability else Movement.new())
	replaceAction(action_ability if action_ability else Action.new())
	replaceAttack(attack_ability if attack_ability else Attack.new())

func _physics_process(delta):
	ai.tick(delta)

func replaceAI(new_ai : AI):
	ai = new_ai.duplicate()
	ai.setup(self)

func replaceMovement(m : Movement):
	movement_ability = m.duplicate()
	movement_ability.setup(self)

func move(delta : float, dir : Vector3):
	movement_ability.move(delta, dir)

func replaceAction(a : Action):
	action_ability = a.duplicate()
	action_ability.setup(self)

func action():
	action_ability.action()
	
func replaceAttack(a : Attack):
	attack_ability = a.duplicate()
	attack_ability.setup(self)

func attack(target : Unit):
	attack_ability.attack(target)

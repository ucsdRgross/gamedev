extends RigidBody3D
class_name Unit 

@export var ai : AI

var team : int

@export_category('Abilities')
@export var movement_ability : Ability
@export var jump_ability : Ability
@export var attack_ability : Ability
@export var special_ability : Ability

@onready var collision : CollisionShape3D = $Collision
@onready var navigation_agent : NavigationAgent3D = $NavigationAgent3D
@onready var health_bar : Sprite3D = $HealthBar
@onready var mesh : MeshInstance3D = $ShearTransform/MeshInstance3D
@onready var ground_cast = $GroundCast
@onready var animation_player = $AnimationPlayer

func _ready():
	replaceAI(ai if ai else AI.new())
	replaceMovement(movement_ability if movement_ability else Ability.new())
	replaceJump(jump_ability if jump_ability else Ability.new())
	replaceAttack(attack_ability if attack_ability else Ability.new())
	replaceSpecial(special_ability if special_ability else Ability.new())
	

func replaceAI(new_ai : AI):
	ai = new_ai.duplicate()
	ai.setup(self)

func replaceMovement(new_m : Ability):
	movement_ability = new_m.duplicate()
	movement_ability.setup(self)

func move(delta : float, dir : Vector3):
	movement_ability.move(delta, dir)

func replaceJump(new_j : Ability):
	jump_ability = new_j.duplicate()
	jump_ability.setup(self)

func jump():
	jump_ability.jump()
	
func replaceAttack(new_a : Ability):
	attack_ability = new_a.duplicate()
	attack_ability.setup(self)

func attack(target : Unit):
	attack_ability.attack(target)
	
func replaceSpecial(new_s : Ability):
	special_ability = new_s.duplicate()
	special_ability.setup(self)

func special(target : Unit):
	special_ability.special(target)

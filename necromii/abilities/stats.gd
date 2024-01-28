extends Resource
class_name Stats 

signal health_changed(new_health:float)

#@export var species : String
@export var base_health : float = 100:
	set(value):
		base_health = value
		health = base_health
var health : float = base_health:
	set(value):
		health = value
		health_changed.emit(health)

@export var base_damage : float = 10:
	set(value):
		base_damage = value
		damage = base_damage * damage_modifier
var damage_modifier : float = 1.0:
	set(value):
		damage_modifier = value
		damage = base_damage * damage_modifier
var damage : float  = base_damage * damage_modifier

@export var base_defense : float = 0:
	set(value):
		base_defense = value
		defense = base_defense * defense_modifier
var defense_modifier : float = 1.0:
	set(value):
		defense_modifier = value
		defense = base_defense * defense_modifier
var defense : float  = base_defense * defense_modifier

@export var base_haste : float = 0
var haste : float = base_haste

@export var base_mana : float = 100
var mana : float = base_mana

@export var base_speed : float = 10
@export var speed := base_speed

@export var base_accel_force : float = 200
var accel_force : float = base_accel_force

@export var base_accel_force_cap : float = 150
var accel_force_cap : float = base_accel_force_cap

#for abilities with non general attributes
#ex: increasing this value increasees jump height and spell size
@export var general_effectiveness : float = 1.0

extends Resource
class_name HealthManager

signal health_changed(new_health:int)

@export_subgroup("Health")
@export var max_health : int = 100:
	set(val):
		max_health = val
@export var health : int = 100:
	set(val):
		health = clamp(val, 0, max_health)
		health_changed.emit(health)
		
func damage(dmg : int):
	health = health - dmg
	emit_changed()

func heal(h : int):
	health = health + h
	emit_changed()

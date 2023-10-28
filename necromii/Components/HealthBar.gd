extends Sprite3D
class_name HealthBar

@onready var bar = $SubViewport/ProgressBar

@export_subgroup("Health")
@export var max_health : int = 100:
	set(val):
		max_health = val
		health = health
		set_bar_max_health(max_health)
@export var health : int = 100:
	set(val):
		health = clamp(val, 0, max_health)
		set_bar_health(health)
		if health <= 0:
			get_parent().queue_free()

func _ready():
#	texture = ViewportTexture.new()
#	texture.viewport_path = $SubViewport.get_path()
	set_bar_max_health(max_health)
	set_bar_health(health)
	get_parent().add_to_group("damageable")

func damage(dmg : int):
	health = health - dmg

func heal(h : int):
	health = health + h

func set_bar_health(val:int):
	if bar:
		bar.value = val
	
func set_bar_max_health(val:int):
	if bar:
		bar.max_value = val

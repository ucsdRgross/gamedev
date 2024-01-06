extends Sprite3D
class_name HealthBar

@onready var bar : ProgressBar = $SubViewport/ProgressBar
@onready var fill_stylebox : StyleBoxFlat = bar.get_theme_stylebox('fill')
const color_gradient : GradientTexture1D = preload("res://resources/HealthGradient.tres")

signal no_health

@export_subgroup("Health")
@export var max_health : float = 100:
	set(val):
		max_health = val
		health = health
		set_bar_max_health(max_health)
@export var health : float = 100:
	set(val):
		health = clamp(val, 0, max_health)
		set_bar_health(health)
		if health <= 0:
			#get_parent().interrupt()
			no_health.emit()

func _ready():
#	texture = ViewportTexture.new()
#	texture.viewport_path = $SubViewport.get_path()
	set_bar_max_health(max_health)
	set_bar_health(health)
	get_parent().add_to_group("damageable")
	no_health.connect(get_parent().death)

func damage(dmg : float):
	health = health - dmg

func heal(h : float):
	health = health + h

func set_bar_health(val:float):
	if bar:
		bar.value = val
		fill_stylebox.bg_color = color_gradient.gradient.sample(health/max_health)
	
func set_bar_max_health(val:float):
	if bar:
		bar.max_value = val

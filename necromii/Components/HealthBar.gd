@tool
extends Sprite3D
class_name HealthBar

@onready var body : Unit = get_parent()
@onready var bar : ProgressBar = $SubViewport/ProgressBar
@onready var fill_stylebox : StyleBoxFlat = bar.get_theme_stylebox('fill')
const color_gradient : GradientTexture1D = preload("res://resources/HealthGradient.tres")
const dead_gradient : GradientTexture1D = preload("res://resources/DeadHealthGradient.tres")
@export var hover : Vector3 = Vector3(0,1,0)

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
		if health <= 0 and body.alive:
			body.death()
		if health >= 100 and not body.alive:
			body.undeath()

func _ready():
#	texture = ViewportTexture.new()
#	texture.viewport_path = $SubViewport.get_path()
	if not get_parent() is Unit:
		set_process(false)
	set_bar_max_health(max_health)
	set_bar_health(health)

func _process(delta):
	global_position = body.global_position + hover

func damage(dmg : float):
	health = health - dmg

func heal(h : float):
	health = health + h

func set_bar_health(val:float):
	if bar:
		bar.value = val
		if body.alive:
			fill_stylebox.bg_color = color_gradient.gradient.sample(health/max_health)
		else:
			fill_stylebox.bg_color = dead_gradient.gradient.sample(health/max_health)
		
			
	
func set_bar_max_health(val:float):
	if bar:
		bar.max_value = val

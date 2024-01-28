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
	#set(val):
		#health = clamp(val, 0, max_health)
		#set_bar_health(health)
		#if health <= 0 and body.alive:
			#body.death()
		#if health >= 100 and not body.alive:
			#body.undeath()

func _ready():
#	texture = ViewportTexture.new()
#	texture.viewport_path = $SubViewport.get_path()
	if not get_parent() is Unit:
		set_process(false)
	else:
		set_bar_max_health(body.stats.base_health)
		on_health_changed(body.stats.health)
		await body.ready
		body.stats.health_changed.connect(on_health_changed)

func _process(delta):
	global_position = body.global_position + hover

func on_health_changed(new_health:float):
	bar.value = new_health
	if body.alive or bar.value >= bar.max_value:
		fill_stylebox.bg_color = color_gradient.gradient.sample(body.stats.health/body.stats.base_health)
	else:
		fill_stylebox.bg_color = dead_gradient.gradient.sample(body.stats.health/body.stats.base_health)

func set_bar_max_health(val:float):
	if bar:
		bar.max_value = val

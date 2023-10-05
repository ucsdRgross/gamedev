extends Sprite3D
class_name HealthBar

@onready var bar = $SubViewport/ProgressBar

func set_health(val:int):
	bar.value = val
	
func set_max_health(val:int):
	bar.max_value = val

func attach(hd:HealthManager):
	set_max_health(hd.max_health)
	set_health(hd.health)
	hd.health_changed.connect(set_health)

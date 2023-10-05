extends Sprite3D
class_name HealthBar

@onready var bar = $SubViewport/ProgressBar

func set_health(val:int):
	bar.value = val
	
func set_max_health(val:int):
	bar.max_value = val

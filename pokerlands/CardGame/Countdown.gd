extends Label

@onready var timer: Timer = $Timer

func _process(delta: float) -> void:
	text = "%.01f" % timer.time_left

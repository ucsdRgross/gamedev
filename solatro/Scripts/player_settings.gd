class_name PlayerSettings
extends Resource

signal settings_changed

@export var base_delay : float = 1:
	set(value):
		base_delay = value
		settings_changed.emit()
@export var card_scale : float = 2.5:
	set(value):
		card_scale = value
		settings_changed.emit()
@export var card_separation_scale : float = 1:
	set(value):
		card_separation_scale = value
		settings_changed.emit()
		

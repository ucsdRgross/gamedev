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
## Seconds a prop spends crossing ONE board slot = base_delay-derived get_delay() * this. Bigger
## = slower / more visible props. Read live by PropLayer every frame (SUIT_PROPS_PLAN §4).
@export var prop_tick_fraction : float = 0.45:
	set(value):
		prop_tick_fraction = value
		settings_changed.emit()
		

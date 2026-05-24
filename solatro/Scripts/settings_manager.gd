extends Node

const SAVE_PATH := "user://settings.tres"

var settings: PlayerSettings

func _ready() -> void:
	if ResourceLoader.exists(SAVE_PATH):
		settings = ResourceLoader.load(SAVE_PATH)
	
	# Fallback if file is missing, corrupt, or old
	if not settings:
		settings = PlayerSettings.new()
		
	# Instantly apply hardware rules on launch
	#Engine.max_fps = data.max_fps

func save_settings() -> void:
	ResourceSaver.save(settings, SAVE_PATH)

class PlayerSettings extends Resource:
	@export var base_delay : float = 1

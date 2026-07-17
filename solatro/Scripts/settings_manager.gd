class_name SettingsManagerClass
extends Node

signal settings_changed

const SAVE_PATH := "user://settings.tres"

@export var settings: PlayerSettings:
	set(value):
		#N9 idiom: drop the old resource's connection so re-assignment can't double-fire
		#or keep the replaced settings object reachable
		if settings and settings.settings_changed.is_connected(on_settings_changed):
			settings.settings_changed.disconnect(on_settings_changed)
		settings = value
		if settings:
			settings.settings_changed.connect(on_settings_changed)

func _init() -> void:
	if ResourceLoader.exists(SAVE_PATH):
		settings = ResourceLoader.load(SAVE_PATH)
	
	# Fallback if file is missing, corrupt, or old
	if not settings:
		settings = PlayerSettings.new()
		
	# Instantly apply hardware rules on launch
	#Engine.max_fps = data.max_fps
	

func save_settings() -> void:
	ResourceSaver.save(settings, SAVE_PATH)
	
func on_settings_changed() -> void:
	save_settings()
	settings_changed.emit()

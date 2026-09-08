class_name SettingsManagerClass
extends Node

signal settings_changed

const SAVE_PATH := "user://settings.tres"

## ⚠ **TESTS OWN THEIR SETTINGS; THEY NEVER TOUCH THE PLAYER'S FILE.** While this is set, nothing
## here writes `user://settings.tres` — a suite scribbles on its own `PlayerSettings` instance and
## the player's tuning is untouchable, so tuning a knob cannot break a test and a test cannot
## overwrite a knob.
##
## ⚠ It exists because the alternative FAILED IN PRACTICE. Suites used to park the real file and
## restore it at the end; a run killed by its timeout never reaches the restore, and test values
## became the player's live settings — measured: `act_event_cap` 6000 -> 60, `booster_reroll_pool`
## 5 -> 0, `wall_selection_repeat_delay` 0.4 -> 0.05, after which the suite stopped completing at
## an unchanged commit. A write that never happens cannot be left half-undone.
var isolated := false

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
	if isolated: return
	ResourceSaver.save(settings, SAVE_PATH)

## Load the player's own settings back off disk, dropping whatever a suite was using.
func reload_from_disk() -> void:
	var loaded : PlayerSettings = ResourceLoader.load(SAVE_PATH) if ResourceLoader.exists(SAVE_PATH) 			else null
	settings = loaded if loaded else PlayerSettings.new()
	
func on_settings_changed() -> void:
	save_settings()
	settings_changed.emit()

class_name ProfileManagerClass
extends Node
## Autoload `ProfileManager`. Which pictures each save slot has unlocked. Persists with
## `settings_manager.gd`'s exists-first / `ResourceSaver` pattern, not `RunManagerClass`'s
## background-thread saver: a profile write is one small resource, once per unlock.

## Emitted by unlock() when `picture_id` was newly unlocked -- never for one already unlocked.
signal picture_unlocked(picture_id: StringName)

const SAVE_PATH := "user://profile.tres"

## The only slot today. `PlayerProfile.unlocked` is keyed by slot anyway, so adding more slots
## needs no format migration.
const ACTIVE_SLOT := 0

@export var profile : PlayerProfile = null

func _init() -> void:
	_load()

## Loads the profile, falling back to defaults. A MISSING file is not an error and is silent. A
## file that exists but does not load as a `PlayerProfile` is corruption and is reported once
## rather than degrading silently — `Tests/all_tests.gd`'s `ENGINE_ERROR_ALLOW` expects it.
func _load() -> void:
	if ResourceLoader.exists(SAVE_PATH):
		var loaded : Resource = ResourceLoader.load(SAVE_PATH)
		if loaded is PlayerProfile:
			profile = loaded
		else:
			push_error("ProfileManagerClass: %s exists but did not load as a PlayerProfile -- "
					% SAVE_PATH + "using defaults")
	if not profile:
		profile = PlayerProfile.new()

## Whether `id` is unlocked in the active slot. `wall_unlock_all` bypasses the profile entirely
## and never touches the file.
func is_unlocked(id: StringName) -> bool:
	if SettingsManager.settings.wall_unlock_all: return true
	var slot : Array = profile.unlocked.get(ACTIVE_SLOT, [])
	return id in slot

## Unlocks `id` in the active slot. Returns true when it was NEW, so a caller can tell whether to
## run the unlock reaction. Saves immediately, and emits `picture_unlocked` only on a real
## unlock.
func unlock(id: StringName) -> bool:
	var slot : Array = profile.unlocked.get(ACTIVE_SLOT, [])
	if id in slot:
		return false
	slot.append(id)
	profile.unlocked[ACTIVE_SLOT] = slot
	ResourceSaver.save(profile, SAVE_PATH)
	picture_unlocked.emit(id)
	return true

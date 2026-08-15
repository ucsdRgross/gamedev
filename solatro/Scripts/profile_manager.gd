class_name ProfileManagerClass
extends Node
## Autoload `ProfileManager`. Which pictures each save slot has unlocked (B9, K1, K5, K7,
## PLAN.md §1.5). Persistence mirrors Scripts/settings_manager.gd:19-31's
## ResourceLoader.exists-first / ResourceSaver pattern -- explicitly NOT RunManagerClass's
## background-thread saver: a profile write is one small resource, once per unlock, and never
## worth a thread.

## Emitted by unlock() when `picture_id` was newly unlocked -- never for one already unlocked.
signal picture_unlocked(picture_id: StringName)

const SAVE_PATH := "user://profile.tres"

## Slot 0 is the only slot in v1 (Q213=a); `PlayerProfile.unlocked` is keyed by slot from day one
## so a later multi-slot save needs no format migration.
const ACTIVE_SLOT := 0

@export var profile : PlayerProfile = null

func _init() -> void:
	_load()

## The ResourceLoader.exists-first / fallback-to-defaults pattern settings_manager.gd:19-31 uses,
## not RunManagerClass's threaded one. A missing file is not an error (R5): `exists` simply says
## no, and the fallback below is silent. A file that EXISTS but fails to load as a PlayerProfile
## (R6) is a real corruption and reports it -- exactly once -- rather than degrading silently,
## per this repo's "no silent failure paths" rule (Tests/all_tests.gd's ENGINE_ERROR_ALLOW carries
## a "ProfileManagerClass:" entry for this deliberate, expected error, same status as
## LeakSentinel's and test_palette's).
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

## Whether `id` is unlocked in the active slot. `wall_unlock_all` (Q159=a, K11) bypasses the
## profile entirely and never touches the file.
func is_unlocked(id: StringName) -> bool:
	if SettingsManager.settings.wall_unlock_all: return true
	var slot : Array = profile.unlocked.get(ACTIVE_SLOT, [])
	return id in slot

## Unlocks `id` in the active slot. Returns true when it was new (false when already unlocked, so
## a caller can tell whether to run the unlock reaction). Saves immediately (Q153=a) and only
## emits picture_unlocked on a genuine new unlock.
func unlock(id: StringName) -> bool:
	var slot : Array = profile.unlocked.get(ACTIVE_SLOT, [])
	if id in slot:
		return false
	slot.append(id)
	profile.unlocked[ACTIVE_SLOT] = slot
	ResourceSaver.save(profile, SAVE_PATH)
	picture_unlocked.emit(id)
	return true

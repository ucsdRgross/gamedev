extends TestSuite
# res://Tests/Wall/test_wall_profile.gd
# ==============================================================================
# WALL PROFILE (S7): PlayerProfile + ProfileManager -- which pictures a save slot has unlocked.
# PLAN.md §1.5; TEST_PLAN.md §3, R1-R6.
#
# Drives the LIVE `ProfileManager` autoload directly (same idiom as RUN MANAGER's suite,
# Tests/Map/test_run_manager.gd): the real on-disk user://profile.tres is moved aside for the
# whole suite and restored after, the live in-memory ProfileManager.profile is snapshotted and
# restored too, and the real settings.tres is parked (backup_real_settings) because R4 has to
# toggle the live SettingsManager.settings.wall_unlock_all, which saves on every change. This
# suite never depends on -- nor can corrupt -- an actual player's unlocked set or settings.
#
# CATEGORY MAP: R1-R4 are BEHAVIOR -- the unlock contract a player/designer relies on. R5-R6 are
# IMPLEMENTATION -- TEST_PLAN.md §3 is explicit that R6 exists only because this repo forbids
# silent failure paths, which is a coding-rule pin rather than a design-doc rule.
# ==============================================================================

const REAL_PATH := ProfileManagerClass.SAVE_PATH
const PARKED_PATH := REAL_PATH + ".testbak"

var _real_profile : PlayerProfile = null
var _had_real_file := false

func suite_name() -> String:
	return "WALL PROFILE"

func _ready() -> void:
	TestLog.line("============ WALL PROFILE TEST PASS ============")
	backup_real_settings()
	_real_profile = ProfileManager.profile
	_park_real_file()
	_reset_to_defaults()

	behavior_section("UNLOCK / IS_UNLOCKED")
	test_unlock_is_idempotent_and_reports_newness()
	_reset_to_defaults()
	test_round_trip_through_resource_saver()
	_reset_to_defaults()
	test_format_is_slot_keyed()
	_reset_to_defaults()
	test_debug_flag_bypasses_the_file()
	_reset_to_defaults()

	implementation_section("MISSING / CORRUPT FILE (no silent failure paths)")
	test_missing_file_is_not_an_error()
	test_corrupt_file_degrades_to_defaults()

	_restore_real_file()
	ProfileManager.profile = _real_profile
	restore_real_settings()
	finish()

# ------------------------------------------------------------------ fixtures

## Moves any real user://profile.tres aside so the suite's disk tests run full without ever
## reading or destroying an actual player's unlocked set.
func _park_real_file() -> void:
	if FileAccess.file_exists(REAL_PATH):
		_had_real_file = true
		DirAccess.rename_absolute(ProjectSettings.globalize_path(REAL_PATH),
				ProjectSettings.globalize_path(PARKED_PATH))

## Puts the real file back exactly where _park_real_file found it (or leaves it absent, if it
## was absent). Drops whatever the suite itself left behind first (S7 caution 1: never leave a
## corrupt or stale profile save at REAL_PATH on this machine).
func _restore_real_file() -> void:
	if FileAccess.file_exists(REAL_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(REAL_PATH))
	if _had_real_file:
		DirAccess.rename_absolute(ProjectSettings.globalize_path(PARKED_PATH),
				ProjectSettings.globalize_path(REAL_PATH))

## Clean slate between R-tests: no file on disk, and a fresh empty PlayerProfile live on the
## autoload -- so an earlier test's unlocks can never leak into a later one's assertions.
func _reset_to_defaults() -> void:
	if FileAccess.file_exists(REAL_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(REAL_PATH))
	ProfileManager.profile = PlayerProfile.new()

# ------------------------------------------------------------------ R1-R4 (BEHAVIOR)

## R1: unlock &"deck" twice -> true then false.
func test_unlock_is_idempotent_and_reports_newness() -> void:
	var seen : Array[StringName] = []
	var on_unlocked := func(id: StringName) -> void: seen.append(id)
	ProfileManager.picture_unlocked.connect(on_unlocked)
	var first := ProfileManager.unlock(&"deck")
	var second := ProfileManager.unlock(&"deck")
	ProfileManager.picture_unlocked.disconnect(on_unlocked)
	check(first, "the first unlock of a new id reports true (it was new)")
	check(not second, "unlocking the same id again reports false (already unlocked)")
	check(seen == ([&"deck"] as Array[StringName]),
			"picture_unlocked fires exactly once, only for the genuinely new unlock", str(seen))

## R2: unlock 3 ids, save, load into a FRESH PlayerProfile, compare sets.
func test_round_trip_through_resource_saver() -> void:
	ProfileManager.unlock(&"start_menu")
	ProfileManager.unlock(&"map")
	ProfileManager.unlock(&"deck")
	# CACHE_MODE_IGNORE: a plain load() would hand back the SAME cached instance unlock() already
	# wrote through (ResourceLoader caches by path), which would prove nothing about the actual
	# disk round-trip. This forces an independent read, which is what "a FRESH PlayerProfile" means.
	var fresh := ResourceLoader.load(REAL_PATH, "", ResourceLoader.CACHE_MODE_IGNORE) as PlayerProfile
	check(fresh != null, "the saved file loads back as a PlayerProfile")
	check_impl(fresh != ProfileManager.profile,
			"the fresh load is a distinct instance, not the resource cache's copy")
	var expected : Array[StringName] = [&"start_menu", &"map", &"deck"]
	var loaded_slot : Array = fresh.unlocked.get(0, [])
	check(loaded_slot.size() == expected.size(), "the loaded slot has the same number of ids",
			str(loaded_slot))
	for id : StringName in expected:
		check(id in loaded_slot, "the loaded set contains %s" % id, str(loaded_slot))

## R3: unlock into slot 0 -> assert slot 1 reads empty.
func test_format_is_slot_keyed() -> void:
	ProfileManager.unlock(&"deck")
	var slot0 : Array = ProfileManager.profile.unlocked.get(0, [])
	var slot1 : Array = ProfileManager.profile.unlocked.get(1, [])
	check(slot0.size() == 1, "slot 0 holds the unlock", str(slot0))
	check(slot1.is_empty(), "slot 1 reads empty -- unlock() only ever touches the active slot",
			str(slot1))

## R4: wall_unlock_all = true with an EMPTY profile -> every id unlocked AND the file is NOT
## written.
func test_debug_flag_bypasses_the_file() -> void:
	check(ProfileManager.profile.unlocked.is_empty(), "fixture starts with an empty profile")
	check(not FileAccess.file_exists(REAL_PATH), "fixture starts with no profile.tres on disk")
	var prev := SettingsManager.settings.wall_unlock_all
	SettingsManager.settings.wall_unlock_all = true
	var ids : Array[StringName] = [&"start_menu", &"map", &"game", &"deck", &"settings", &"book"]
	var all_unlocked := true
	for id : StringName in ids:
		if not ProfileManager.is_unlocked(id): all_unlocked = false
	check(all_unlocked, "every id reads unlocked while the flag is set, with an empty profile")
	check(not FileAccess.file_exists(REAL_PATH),
			"the file is still not written -- is_unlocked() never touches disk for the flag")
	SettingsManager.settings.wall_unlock_all = prev

# ------------------------------------------------------------------ R5-R6 (IMPLEMENTATION)

## R5: delete user://profile.tres, reload -> defaults, no push_error. Silent by construction:
## ProfileManagerClass._load()'s push_error sits inside the `ResourceLoader.exists()` branch, and
## a missing file never enters it. Not directly counted here (GDScript has no push_error hook) --
## if this path DID push unexpectedly, run_tests.py's exit-time engine-error scan would report it
## as UNEXPECTED, since "missing file" is not in Tests/all_tests.gd's ENGINE_ERROR_ALLOW.
func test_missing_file_is_not_an_error() -> void:
	if FileAccess.file_exists(REAL_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(REAL_PATH))
	ProfileManager.profile = null
	ProfileManager._load()
	check(ProfileManager.profile != null, "a missing file still produces a usable PlayerProfile")
	check(ProfileManager.profile.unlocked.is_empty(), "and it is the plain default (empty)",
			str(ProfileManager.profile.unlocked))

## R6: write garbage to the path, reload -> defaults, EXACTLY ONE push_error.
func test_corrupt_file_degrades_to_defaults() -> void:
	var abs_path := ProjectSettings.globalize_path(REAL_PATH)
	var f := FileAccess.open(abs_path, FileAccess.WRITE)
	f.store_string("this is not a valid Godot resource file")
	f.close()
	ProfileManager.profile = null
	# ⚠ THE ONE DELIBERATE push_error THIS TEST TRIGGERS is ProfileManagerClass's own --
	# "... exists but did not load as a PlayerProfile" -- allow-listed in Tests/all_tests.gd's
	# ENGINE_ERROR_ALLOW ("ProfileManagerClass:"), same status as LeakSentinel's and test_palette's
	# deliberate errors (see those files). "Exactly one" is not counted inside this suite (GDScript
	# cannot hook push_error) -- it is what run_tests.py's exit-time engine-error scan actually
	# holds to account: a run where this path pushed zero (silent) or more than one (redundant)
	# time would show as UNEXPECTED there even though it is allow-listed for THIS one message.
	ProfileManager._load()
	check(ProfileManager.profile != null,
			"a corrupt file still produces a usable PlayerProfile (the push_error above is "
			+ "deliberate)")
	check(ProfileManager.profile.unlocked.is_empty(), "and it is the plain default (empty)",
			str(ProfileManager.profile.unlocked))
	# The garbage file must not survive this suite (S7 caution 1) -- _restore_real_file() only
	# clears REAL_PATH right before putting the parked real file back, but doing it here too means
	# a failure between this line and that one still leaves no corrupt file behind.
	DirAccess.remove_absolute(abs_path)

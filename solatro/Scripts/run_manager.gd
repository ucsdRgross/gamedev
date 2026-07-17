class_name RunManagerClass
extends Node

## Autoload owning the current run: lifecycle (new/load/save/clear on user://run_save/),
## and the fame/luck/goal balance formulas (DESIGN_DOC §15, no tips). Persistence follows
## the SettingsManager ResourceSaver/Loader pattern.

const SAVE_DIR := "user://run_save"
const RUN_PATH := "user://run_save/run.tres"
## WorldMap2D.bake_directory for the run's map (composite.png + graph.json live here).
const MAP_BAKE_DIR := "user://run_save/map"

# --- balance (tunable) ---------------------------------------------------------
const BASE_GOAL := 100              # matches GameData.goal default
const GOAL_GROWTH_PER_STEP := 1.15  # per progress rank along the lap
const BOSS_MULT := 2.0              # lap-target anchor node
const LAP_MULT := 2.5               # per completed lap (endless scaling)
const OVERSCORE_RATE := 0.25        # how hard overscoring inflates future goals
const OVERSCORE_EXP := 1.5          # >1 = accelerating (nonlinear requirement growth)
const LUCK_CAP := 0.6               # max per-component chance in booster generation
const FAME_HALF := 5000.0           # fame at which luck reaches half of LUCK_CAP

var run : RunState = null

# --- background save queue -----------------------------------------------------
# Every player action requests a save (anti-cheat: closing can't rewind a mistake). To
# avoid main-thread hitches when the run + full undo history is large, the write runs on a
# background thread; rapid requests coalesce (only the latest payload is written). If the
# player quits within the brief lag, the last action is lost — an accepted tradeoff (it is
# as if the action never happened, which is NOT a free rewind of an already-saved state).
var _saver_thread : Thread = null
var _saver_sem : Semaphore = null
var _saver_mutex : Mutex = null
var _pending_payload : RunState = null
var _saver_exit := false
# Cached serialization-ready copies of the run deck; rebuilt only when the deck changes
# (mark_deck_dirty), so in-show saves don't re-copy the (stable) deck every action.
var _saveable_deck : Array[CardData] = []
var _saveable_rules : Array[CardData] = []
var _deck_dirty := true

func _exit_tree() -> void:
	_shutdown_saver()

## True when a resumable run exists on disk. Gated on the run doc ONLY: the map bake
## (composite.png etc.) is a deterministic cache of run.world_seed, and WorldMapController
## .start_run regenerates+rebakes it whenever it's missing. Requiring the bake here made
## Continue fragile — a deleted/half-written cache (or a run saved before its first bake)
## would wrongly disable resume even though the run is fully recoverable from run.tres.
func has_save() -> bool:
	return FileAccess.file_exists(RUN_PATH)

## Start a fresh run: deep-copy the chosen deck/rules and pin a non-zero world seed
## (seed 0 would regenerate a different world on Continue).
func new_run(cards: Array[CardData], rules: Array[CardData]) -> RunState:
	clear_save()
	run = RunState.new()
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	run.world_seed = rng.randi_range(1, 2147483646)
	run.card_datas = cards.duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
	run.rule_datas = rules.duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
	mark_deck_dirty()
	save_run()
	return run

## Resume the run saved on disk (callers gate on has_save()). Relinks the run deck's
## modifier backrefs; history snapshots stay in saveable form (Game rebuilds each to
## runtime when it pulls one for resume/undo).
func load_run() -> RunState:
	run = ResourceLoader.load(RUN_PATH, "", ResourceLoader.CACHE_MODE_IGNORE)
	_relink_cards(run.card_datas)
	_relink_cards(run.rule_datas)
	mark_deck_dirty()
	return run

## The run deck changed — the cached serialization-ready copies must be rebuilt next save.
func mark_deck_dirty() -> void:
	_deck_dirty = true

## Synchronous write (blocks) — for infrequent, small saves (map traversal, boosters, run
## start) where a background hop isn't worth it.
func save_run() -> void:
	if run == null: return
	_write_payload(_build_payload())

## Queue an asynchronous, coalesced write — for frequent in-game saves (every action).
func request_save() -> void:
	if run == null: return
	var payload := _build_payload()
	_ensure_saver()
	_saver_mutex.lock()
	_pending_payload = payload
	_saver_mutex.unlock()
	_saver_sem.post()

# Assemble an INDEPENDENT RunState safe to hand to the writer thread: scalars copied, the
# run deck taken from the (cached) serialization-ready copies, and the history array
# shallow-copied (its GameData snapshots are already saveable + immutable).
func _build_payload() -> RunState:
	var p := RunState.new()
	p.world_seed = run.world_seed
	p.current_node_id = run.current_node_id
	p.lap = run.lap
	p.fame = run.fame
	p.overscore_ratio_sum = run.overscore_ratio_sum
	p.traveled = run.traveled.duplicate()
	p.pending_goal = run.pending_goal
	p.pending_node_id = run.pending_node_id
	p.game_submits = run.game_submits
	p.pending_action = run.pending_action
	if _deck_dirty:
		_saveable_deck = _to_saveable_cards(run.card_datas)
		_saveable_rules = _to_saveable_cards(run.rule_datas)
		_deck_dirty = false
	p.card_datas = _saveable_deck
	p.rule_datas = _saveable_rules
	p.game_history = run.game_history.duplicate()  # entries already saveable + immutable
	p.game_history_trimmed = run.game_history_trimmed
	return p

# Deep-copy a card array and unlink the modifier self-cycles → serialization-ready and
# independent (the live cards keep their backrefs). The modifier slot list lives in
# GameData's static per-card helpers so this path can't drift from the board save path.
func _to_saveable_cards(cards: Array[CardData]) -> Array[CardData]:
	var out : Array[CardData] = cards.duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
	for card in out:
		GameData.unlink_card_backrefs(card)
	return out

func _relink_cards(cards: Array[CardData]) -> void:
	for card in cards:
		GameData.relink_card_backrefs(card)

func _write_payload(payload: RunState) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SAVE_DIR))
	# Write to a temp file then rename, so an interrupted/threaded write can't leave a
	# half-written run.tres. The temp MUST keep a .tres extension: ResourceSaver picks its
	# format from the extension, so "run.tres.tmp" fails with ERR_FILE_UNRECOGNIZED (15) and
	# nothing is ever written — the bug that left no run.tres and disabled Continue.
	var tmp := RUN_PATH.get_basename() + ".tmp.tres"
	if ResourceSaver.save(payload, tmp) == OK:
		DirAccess.rename_absolute(ProjectSettings.globalize_path(tmp),
			ProjectSettings.globalize_path(RUN_PATH))

func _ensure_saver() -> void:
	if _saver_thread != null: return
	_saver_sem = Semaphore.new()
	_saver_mutex = Mutex.new()
	_saver_thread = Thread.new()
	_saver_thread.start(_saver_loop)

func _saver_loop() -> void:
	while true:
		_saver_sem.wait()
		if _saver_exit:
			return
		_saver_mutex.lock()
		var payload : RunState = _pending_payload
		_pending_payload = null
		_saver_mutex.unlock()
		if payload != null:
			_write_payload(payload)

# Flush any queued write and join the thread (called on app exit).
func _shutdown_saver() -> void:
	if _saver_thread == null: return
	_saver_mutex.lock()
	var payload : RunState = _pending_payload
	_pending_payload = null
	_saver_mutex.unlock()
	if payload != null:
		_write_payload(payload)
	_saver_exit = true
	_saver_sem.post()
	_saver_thread.wait_to_finish()
	_saver_thread = null

## Discard the run: cancel any queued write, delete the run doc and the baked map. Called
## on loss and new_run.
func clear_save() -> void:
	run = null
	if _saver_mutex != null:
		_saver_mutex.lock()
		_pending_payload = null  # don't let a stale write resurrect the file
		_saver_mutex.unlock()
	if FileAccess.file_exists(RUN_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(RUN_PATH))
	var map_dir := DirAccess.open(MAP_BAKE_DIR)
	if map_dir:
		for file in map_dir.get_files():
			map_dir.remove(file)

## A won game feeds progression: FULL total_score (incl. overscore) becomes fame, and
## the overscore ratio compounds into future goal requirements.
func record_win(total_score: int, goal: int) -> void:
	if run == null: return
	run.fame += total_score
	run.overscore_ratio_sum += maxf(0.0, float(total_score - goal)) / float(maxi(goal, 1))

## Luck grows with fame on a saturating curve: 0 at no fame, LUCK_CAP/2 at FAME_HALF,
## asymptote LUCK_CAP. Used as the per-component non-null chance in booster generation.
func luck() -> float:
	if run == null: return 0.0
	return LUCK_CAP * float(run.fame) / (float(run.fame) + FAME_HALF)

## Fame requirement for a game node. `progress` = steps from the lap origin (forward lap:
## depth; reversed lap: max_depth - depth). Overscoring past goals nonlinearly inflates
## all future requirements; lap scaling is capped to avoid int overflow in endless mode.
func goal_for(progress: int, lap: int, is_boss: bool) -> int:
	var overscore_mult := pow(1.0 + OVERSCORE_RATE * (run.overscore_ratio_sum if run else 0.0), OVERSCORE_EXP)
	var goal := BASE_GOAL * pow(GOAL_GROWTH_PER_STEP, progress) \
		* pow(LAP_MULT, mini(lap, 30)) * overscore_mult
	if is_boss:
		goal *= BOSS_MULT
	return maxi(int(goal), 1)

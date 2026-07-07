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

## True when a resumable run exists on disk (run doc AND baked map image).
func has_save() -> bool:
	return FileAccess.file_exists(RUN_PATH) \
		and FileAccess.file_exists(MAP_BAKE_DIR.path_join("composite.png"))

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
	save_run()
	return run

## Resume the run saved on disk (callers gate on has_save()). Relinks the card graph and
## rebuilds the in-progress show's score arrays.
func load_run() -> RunState:
	run = ResourceLoader.load(RUN_PATH, "", ResourceLoader.CACHE_MODE_IGNORE)
	_set_modifier_backrefs(run, true)
	if run.game_state:
		run.game_state.restore_scores(run.game_scores)
	return run

## Persist the current run document (the map bake is written separately, once, by
## WorldMapController right after generation).
## ResourceSaver can't write two things in the card graph: the cyclic CardModifier.data
## back-references (unlinked here, relinked right after), and the RefCounted BigNumber
## score arrays of an embedded in-progress game_state (flattened to primitives in
## game_scores and cleared for the write, then restored). Both are lossless.
func save_run() -> void:
	if run == null: return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SAVE_DIR))
	if run.game_state:
		run.game_scores = run.game_state.scores_to_data()
		run.game_state.scores_row_upper.clear()
		run.game_state.scores_row_lower.clear()
		run.game_state.scores_col.clear()
	_set_modifier_backrefs(run, false)
	ResourceSaver.save(run, RUN_PATH)
	_set_modifier_backrefs(run, true)
	if run.game_state:
		run.game_state.restore_scores(run.game_scores)

# A modifier's data backref always points at its owning card (CardData.with_skill/type/
# stamp), so relinking is lossless. Covers the run deck, rules, AND any in-progress
# game_state's board/decks (ZoneAdder.card_data is a plain forward ref — no cycle — so it
# survives the write untouched).
static func _set_modifier_backrefs(r: RunState, link: bool) -> void:
	if r == null: return
	var collections: Array = [r.card_datas, r.rule_datas]
	if r.game_state:
		collections.append(r.game_state.all_card_datas())
	for cards: Array[CardData] in collections:
		for card in cards:
			for mod: CardModifier in [card.skill, card.type, card.stamp]:
				if mod:
					mod.data = card if link else null

## Discard the run: delete the run doc and the baked map. Called on loss and new_run.
func clear_save() -> void:
	run = null
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

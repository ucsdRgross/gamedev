# SOLATRO — Scoring/Goal Rework Implementation Plan

> **Status:** plan only — no game code changed. Authoritative design spec:
> [SCORING_MATH_PLAN.md §15](solatro/SCORING_MATH_PLAN.md) (§15a scoring, §15b goals,
> §8c′ overscore removal rationale). This document expands §15c into a mechanical,
> file-by-file execution plan. On approval, copy this file to
> `solatro/SCORING_IMPL_PLAN.md` so it lives with the repo docs.

## Context

The scoring-math research phase (sim harness `solatro/tools/scoring_sim.py`, 2000-trial
calibrations) is complete and the owner has ruled on the design. The game currently pays
`row_total × col_total` per act, uses a geometric goal curve inflated by an overscore
tax, and starts with a 24-card deck containing talent cards. The settled design replaces
this with: **act payout = R × C × combo** (combo = 1 + 0.1·U, U = distinct meld classes
+ first-activation mod effects, reset per act), a **map-structure-driven goal curve**
`G0·(N̂/N0)^ALPHA·difficulty·BOSS^is_boss·LAP^lap` with a monotone clamp, **overscore
retired**, a **20-card start deck** (ranks 1–5 × 4 suits, no talents), a **δ fallback
lever** (ships off), and a **combo UI label**. Calibrated constants: `N0=20, G0≈130,
ALPHA≈4.2, BOOSTER_YIELD=5` (from `py solatro/tools/scoring_sim.py --final --q 0.35`;
the sim's `nhat(k) = 20 + 5*(k//3)` confirms BOOSTER_YIELD=5).

## Hard project rules (restated — the implementer MUST follow these)

- **Never run headless Godot while the owner's editor is open.** Verification = add
  prints/TestLog lines, owner runs `scenes/all_tests.tscn` and the game themselves.
- **No `git add`, no commits** (owner uses GitHub Desktop). Just edit files.
- Warnings-as-errors: **type every array and every for-loop variable**
  (`for col : ArrayCardData in ...`).
- **Do not touch `ScoreModel` hand formulas** — `test_scoring.gd` SECTION 8 leaderboard
  must stay green.
- Tests follow the TestSuite pattern (`Tests/Support/test_base.gd`); never use
  `Decks/deck.gd` in tests — use `Tests/Support/test_decks.gd`; respect TestLog.
- Tuning knobs go in `Scripts/player_settings.gd` via `SettingsManager.settings`,
  setters emit `settings_changed`.
- Keep commented-out code; `##` purpose comments on new methods.
- Anything per-act must live on **GameData** (undo/save snapshots carry GameData;
  BigNumber is RefCounted and invisible to ResourceSaver — combo state is
  `Array[String]`, which serializes fine via `@export_storage`).
- User-facing strings via `TRANSLATION.find` + `solatro/Locale/localization.csv`, never
  literals.
- `.tscn` edits: coordinate with the owner (open editor rewrites files). Do scene edits
  as text edits and tell the owner to close/reopen the editor around them.

---

## Ordered change list (each step leaves the game runnable)

### Step 1 — Settings knobs (inert until read)  `Scripts/player_settings.gd`

Add after the existing knob groups, following the exact `base_delay` pattern
(lines 15–18):

```gdscript
@export_group("Balance")
## Global goal multiplier (§15b "difficulty"): ±15% ≈ one persona band. THE dial for
## run win-rate; default 1.0.
@export var difficulty : float = 1.0:
	set(value):
		difficulty = value
		settings_changed.emit()

## δ fallback lever (§15a): duplicate-CLASS melds score ×δ. 1.0 = off (ship default);
## only lower during playtest if dump crushes everything.
@export var duplicate_class_scale : float = 1.0:
	set(value):
		duplicate_class_scale = value
		settings_changed.emit()
```

No readers yet — game behavior unchanged.

### Step 2 — Meld class key (read-only addition)  `Scripts/scoring.gd`

Add a static func on `Scoring` (top level, near the `Result` class at line 82). It maps
`Result.types` (`Array[MELD_TYPE]`, see enum at lines 3–11) + `copy_size` +
`copies_count` to a class string. Rank and suit deliberately absent. The `MULTI` flag is
redundant with `copies_count` and is not encoded separately.

```gdscript
## §15a combo identity: archetype + sub-hand size + copy count, with flush-variant
## flags appended so straight flush / full flush / multi-flush stay distinct classes.
## Rank and suit do NOT differentiate (pair of 2s == pair of 3s).
static func class_key(r: Result) -> String:
	var arch := "HIGH"
	if r.types.has(MELD_TYPE.FULL_HOUSE):    arch = "HOUSE"
	elif r.types.has(MELD_TYPE.STRAIGHT):    arch = "STRAIGHT"
	elif r.types.has(MELD_TYPE.X_OF_KIND):   arch = "XKIND"
	elif r.types.has(MELD_TYPE.FLUSH):       arch = "FLUSH"   # pure flush, no structure
	var key := "%s:%dx%d" % [arch, r.copy_size, r.copies_count]
	if r.types.has(MELD_TYPE.ALL_SAME_SUIT):
		key += ":FF"    # full flush / straight flush / flush five family
	elif r.types.has(MELD_TYPE.FLUSH) and arch != "FLUSH":
		key += ":MF"    # multi-flush of structural copies
	return key
```

Both the sub-hand **size** and the **copy count** differentiate classes (owner
ruling 2026-07-17, re-confirmed at plan review): `1× pair` ≠ `5× pair` ≠ `10× pair`
(`"XKIND:2x1"` / `"XKIND:2x5"` / `"XKIND:2x10"`), pair ≠ trips ≠ quad
(`"XKIND:2x1"` / `"XKIND:3x1"` / `"XKIND:4x1"`), and a 5-straight ≠ a 6-straight
(`"STRAIGHT:5x1"` / `"STRAIGHT:6x1"`). The `%dx%d` format encodes exactly this —
`copy_size` then `copies_count`.

Examples the tests must pin: pair `"XKIND:2x1"`, trips `"XKIND:3x1"`, quad
`"XKIND:4x1"`, 2× quad `"XKIND:4x2"`, 5× pair `"XKIND:2x5"` vs 10× pair
`"XKIND:2x10"` (distinct), straight `"STRAIGHT:5x1"` vs 6-card straight
`"STRAIGHT:6x1"` (distinct), straight flush `"STRAIGHT:5x1:FF"`, flush house
`"HOUSE:5x1:FF"`, suited multi-set `"XKIND:3x2:MF"`, pure flush `"FLUSH:5x1"`, lone
high card `"HIGH:1x1"` (excluded from U at the game layer, not here).
**No ScoreModel change.**

### Step 3 — Combo state + payout  `Scripts/game_data.gd`

3a. New field next to `submits_used` (~line 46), same rationale comment style:

```gdscript
## Distinct combo classes scored THIS act (§15a U; a set — Array for serialization).
## Lives ON the board state so undo/act-cancel/pending-action replay reset it for free:
## every snapshot restore brings back the pre-act (empty) set, same reason submits_used
## lives here.
@export_storage var combo_classes : Array[String] = []
```

(No setter needed — the label updates ride a dedicated `Game.combo_changed` signal,
Step 4. `duplicate_state()`'s `duplicate_deep(DEEP_DUPLICATE_ALL)` and
`to_saveable()`/`@export_storage` carry an `Array[String]` with no extra work.)

3b. Combo math (const + helper + payout), replacing line 52's
`mult_score = row_total * col_total`:

```gdscript
## §15a: promote to player_settings only if playtest wants COMBO_STEP live (0.1 vs 0.2).
const COMBO_STEP := 0.1

## Current act multiplier: 1.0 + COMBO_STEP per distinct class scored this act.
func combo_mult() -> float:
	return 1.0 + COMBO_STEP * combo_classes.size()

func apply_act_score() -> void:
	# §15a: round ONCE per act payout — combo applies to the R×C product, not per line.
	mult_score = int(row_total * col_total * combo_mult())
	total_score += mult_score
	row_total = 0
	col_total = 0
	combo_classes.clear()   # U resets every act, alongside the gutters below
	# (existing gutter clears + comment stay)
	scores_row_upper.clear()
	scores_row_lower.clear()
	scores_col.clear()
```

With `combo_classes` empty this is numerically identical to today — game still runnable
before Step 4 lands.

### Step 4 — Collecting U  `Levels/game.gd`, `Scripts/card_environment.gd`, `Cards/card_modifier.gd`, prop/status seams

4a. **Game signal + registrar** (`Levels/game.gd`, near the signals at lines 15–23):

```gdscript
signal combo_changed(count: int)   # a NEW class registered this act (view pop + label)

## Add a combo class key to this act's U set. Returns true when it was new.
## Empty keys never register (opt-out hook for engine mods).
func register_combo(key: String) -> bool:
	if key.is_empty() or state.combo_classes.has(key):
		return false
	state.combo_classes.append(key)
	combo_changed.emit(state.combo_classes.size())
	return true
```

4b. **Meld classes + δ lever in `score_line()`** (lines 566–579). Insert before/around
the existing `add_line_score` call; note the δ scale must be decided BEFORE the class
registers, and high cards never enter U:

```gdscript
func score_line(result : Scoring.Result, is_row : bool, zone : Array, index : int) -> void:
	if act_cancelled: return
	# (existing score_zone selection unchanged)
	var key := Scoring.class_key(result)
	var counts_for_combo := not result.types.has(Scoring.MELD_TYPE.HIGH_CARD)  # beats a lone high card
	var amount := result.score
	# δ fallback (§15a, ships 1.0 = off): duplicate-CLASS melds score ×δ at accumulation.
	var delta : float = SettingsManager.settings.duplicate_class_scale
	if counts_for_combo and delta < 1.0 and state.combo_classes.has(key):
		amount = int(amount * delta)
	if view: await view.animate_meld(result)
	add_line_score(is_row, score_zone, index, amount)   # was: result.score
	if counts_for_combo:
		register_combo(key)
	# (rest unchanged: show_meld_score, _run_score_effects, reset_meld)
```

4c. **Mod-effect U at the dispatch point.** In `Scripts/card_environment.gd`
`run_all_mods` (lines 38–67), after each of the two invocation sites (mod at ~line 56,
skill at ~line 62) add `_note_mod_fired(mod, function)` / `_note_mod_fired(skill,
function)`, with a base no-op:

```gdscript
## Hook: a mod handler actually ran for `function`. Game overrides to feed the act
## combo (§15a mod-activation U).
func _note_mod_fired(_mod: CardModifier, _function: StringName) -> void:
	pass
```

Override in `Levels/game.gd`:

```gdscript
func _note_mod_fired(mod: CardModifier, function: StringName) -> void:
	if not _act_active: return
	register_combo(mod.combo_key(function))   # "" keys never register (opt-out)
```

`_act_active` is a new `Game` bool set `true` in `_begin_act()` and cleared after
`apply_act_score()` in `_perform_submit` and in `_restore_pre_act_board()` (act cancel).
Verify against `_act_cancellable`'s lifecycle when implementing — if `_act_cancellable`
already brackets exactly the resolution window, reuse it instead of a new flag.

4d. **Identity key on modifiers** (`Cards/card_modifier.gd`, plus the prop-modifier base
if props don't extend CardModifier — check `Cards/Props/prop_modifier.gd`).
**Owner ruling 2026-07-17:** all non-engine mods count by DEFAULT; exclusion is a
per-mod opt-out on the modifier itself (NOT an `is_data_in_rules` check), and the key
takes the hook name so a mod implementing several hooks can opt each in or out (or key
them separately) on its own:

```gdscript
## Combo identity for §15a mod-activation U. Default: one combo class per modifier
## script, whatever hook fired. Overrides may return "" (opt this mod — or specific
## hooks — out of combo) or append the hook to count hooks as separate classes.
func combo_key(_hook: StringName = &"") -> String:
	var script : Script = get_script()
	return script.resource_path
```

4d′. **Engine opt-outs.** Add `func combo_key(_hook: StringName = &"") -> String:
return ""` overrides to the rules-engine modifier scripts so the scorer machinery
doesn't add a constant U baseline every act: `skill_scorer_cascade_lower.gd`,
`skill_eval_poker_best.gd`, and every other mod script referenced by `rules1` in
`Decks/deck.gd` (enumerate `_build_rules1` when implementing). Player-deck talents
(e.g. `SkillExtraPoint`, still present in old-save decks) keep the default and count.

4e. **Prop/status score seams.** The non-meld `add_line_score` callers self-register at
their seam (spec §15c-3 "Prop effects likewise"): in
`Cards/Props/Mods/prop_bank_col_score.gd:15`, `prop_score_talents.gd:15`,
`prop_score_props.gd:15`, and `Cards/Statuses/status_juggling.gd:20`, add before the
`add_line_score` call:

```gdscript
g.register_combo(combo_key())
```

(`status_juggling` also reaches the dispatch hook via `run_all_mods`; `register_combo`
is idempotent so double-registration is harmless. Prop mods run through the prop tick's
`run_card_mods` path which does NOT get the 4c hook — the seam call is what covers
them.)

### Step 5 — Goal authority rework  `Scripts/run_manager.gd`

5a. Constants block (lines 13–21) — replace, keeping retired lines commented per
convention:

```gdscript
# --- balance (tunable) ---------------------------------------------------------
const G0 := 130.0             # goal at the 20-card start deck (§15b; re-fit via sim --final)
const GOAL_ALPHA := 4.2       # power on N-hat/N0 (log-fit of the §15b table)
const N0 := 20.0              # start-deck size the curve is anchored to
const BOOSTER_YIELD := 5.0    # expected cards per booster-role node (dupes, 5 cards)
const BOSS_MULT := 2.0        # lap-target anchor node
const LAP_MULT := 2.5         # per completed lap (endless scaling — owner-required term)
#const BASE_GOAL := 100              # retired 2026-07: replaced by G0/N-hat curve (§15b)
#const GOAL_GROWTH_PER_STEP := 1.15  # retired 2026-07
#const OVERSCORE_RATE := 0.25        # retired 2026-07 (§8c′: overscore tax removed)
#const OVERSCORE_EXP := 1.5          # retired 2026-07
const LUCK_CAP := 0.6
const FAME_HALF := 5000.0
```

5b. `goal_for` (lines 210–216) — new signature; **grep every caller**
(`map_node_roles.gd:30,38`, `Tests/Map/test_run_manager.gd:65–88`):

```gdscript
## §15b goal curve. boosters_on_path = booster-role nodes between the lap origin and
## this node (opportunities to grow, not purchases). Monotone clamp is applied by the
## per-path baker (MapNodeRoles), not here.
func goal_for(boosters_on_path: int, lap: int, is_boss: bool) -> int:
	var n_hat := N0 + BOOSTER_YIELD * boosters_on_path
	var difficulty : float = SettingsManager.settings.difficulty
	var goal := G0 * pow(n_hat / N0, GOAL_ALPHA) * difficulty * pow(LAP_MULT, mini(lap, 30))
	if is_boss:
		goal *= BOSS_MULT
	return maxi(int(goal), 1)
```

5c. `record_win` (lines 196–199) — fame only:

```gdscript
func record_win(total_score: int, _goal: int) -> void:
	if run == null: return
	run.fame += total_score
	# Overscore tax retired (§8c′): overscore_ratio_sum stays ON RunState unread for
	# save-compat; delete the field (+ _build_payload copy at run_manager.gd:106 and
	# run_state.gd:19) at the next save-version break.
```

Keep the `_goal` parameter (callers pass it; the signature staying put avoids touching
`exit_show()`). Keep `run_state.gd:19` and the `_build_payload` copy at line 106 as-is.

5d. Update the class header comment (line 5 "fame/luck/goal balance formulas") to point
at SCORING_MATH_PLAN §15b.

### Step 6 — Map-driven N̂ + monotone clamp  `Scripts/Map/map_node_roles.gd` (+ `Levels/map.gd:68`)

Because boosters are **whole ranks** (`_booster_ranks`, lines 47–56), every path crosses
the same booster set, so `boosters_on_path` reduces exactly to "booster ranks strictly
before this node's progress" and the max-booster-path rule on convergent branches is
trivially satisfied. Bake a per-progress goal ladder once per `assign()` with the clamp
applied, then read it per node. (If per-node boosters ever replace whole ranks,
generalize `_boosters_before` to a max-count DAG walk over `overlay` edges.)

```gdscript
static func assign(overlay: WorldGraphOverlay, world_seed: int, run: RunState) -> void:
	var max_depth : int = overlay.graph_data.get("max_depth", 0)
	var booster_ranks := _booster_ranks(world_seed, max_depth)
	var ladder := _goal_ladder(max_depth, booster_ranks, run)
	for n : WorldGraphNode in overlay.nodes():
		if n.is_start or n.is_end:
			n.meta[ROLE_KEY] = ROLE_ANCHOR
			var is_target := n.is_start if run.is_reversed() else n.is_end
			# Boss sees every booster of the lap; never below the last game goal.
			var boss_goal := maxi(RunManager.goal_for(booster_ranks.size(), run.lap, true), ladder[max_depth])
			n.meta[GOAL_KEY] = boss_goal if is_target else 0
			n.meta.erase(BOOSTER_KEY)
		elif booster_ranks.has(n.depth):
			# (unchanged booster branch)
		else:
			n.meta[ROLE_KEY] = ROLE_GAME
			n.meta[GOAL_KEY] = ladder[_progress(n, max_depth, run)]
			n.meta.erase(BOOSTER_KEY)

## §15b ladder: goal per progress step, monotone-clamped so the ladder never descends.
static func _goal_ladder(max_depth: int, booster_ranks: Dictionary, run: RunState) -> Array[int]:
	var ladder : Array[int] = []
	var running := 0
	for p : int in range(max_depth + 1):
		var b := _boosters_before(p, max_depth, booster_ranks, run)
		running = maxi(running, RunManager.goal_for(b, run.lap, false))
		ladder.append(running)
	return ladder

## Booster ranks crossed strictly before reaching progress p, in lap direction.
static func _boosters_before(p: int, max_depth: int, booster_ranks: Dictionary, run: RunState) -> int:
	var count := 0
	for rank : int in booster_ranks.keys():
		var rank_progress := (max_depth - rank) if run.is_reversed() else rank
		if rank_progress < p:
			count += 1
	return count
```

`Levels/map.gd:68` reads `node.meta.get(GOAL_KEY, RunManager.BASE_GOAL)` — with
BASE_GOAL retired, change the fallback to `maxi(int(RunManager.G0), 1)`.

### Step 7 — Starting deck  `Decks/deck.gd`

Add a lazy `deck12` beside `deck11` (keep `_build_deck11` intact per keep-code
convention) and flip the getter:

```gdscript
## 20-card start deck (2026-07 scoring rework §15b): ranks 1–5 × 4 suits, no talents —
## the deck the goal curve (N0=20) is calibrated against.
var deck12 : Array[CardData]:
	get:
		if deck12 == null or deck12.is_empty():
			deck12 = _build_deck12()
		return deck12

func _build_deck12() -> Array[CardData]:
	var cards : Array[CardData] = []
	for suit : GDScript in ALL_SUITS:
		for rank : int in range(1, 6):
			cards.append(_card(suit, rank))
	return cards

func get_deck() -> Array[CardData]:
	return deck12   # was deck11 (24 cards incl. SkillExtraPoint talents)
```

(Match the exact lazy-getter idiom the file already uses for deck11 — N6, lines 42–47.)
Tests are unaffected (frozen `TestDecks`); `Tests/Engine/test_game_headless.gd:267`
concatenates `get_deck() + get_rules()` — verify it doesn't assert a card count.

### Step 8 — UI: combo label  `Levels/game_view.gd`, `Levels/game_view.tscn` (or wherever `%MultScore` lives), `Locale/localization.csv`

- **Scene:** add a `Label` named `Combo` under the `%MultScore` container (siblings
  `Col`, `Row` exist — mult display becomes R × C × combo). Text-edit the `.tscn` with
  the owner's editor CLOSED, or ask the owner to drop the node in.
  **Owner ruling 2026-07-17:** this placement confirmed; label hidden at x1.0, empties
  again after payout (U resets per act).
- **Localization** (`Locale/localization.csv`, format `key,en,?context`): add
  `GAME_COMBO,COMBO x%.1f,` — the editor recompiles `localization.en.translation` on
  import.
- **game_view.gd:**
  - node ref beside line 34–38 refs: `@onready var combo_label : Label = %MultScore/Combo`
  - `_refresh_hud()` (lines 119–126) addition:
    ```gdscript
    var combo := state.combo_mult()
    combo_label.text = TRANSLATION.find('GAME_COMBO') % combo
    combo_label.visible = combo > 1.0   # owner ruling: hidden at x1.0
    ```
  - Connect `game.combo_changed` where the view binds Game signals:
    ```gdscript
    func _on_combo_changed(_count: int) -> void:
    	_refresh_hud()   # combo_classes.append() doesn't emit state_changed — this signal is the live path
    	# pulse: same shape as BigNumberLabel.anim_pop (UI/big_number_label.gd:11-26):
    	# EASE_OUT/TRANS_BACK tween, scale to 1.15 over delay*.3, back to 1.0 over delay*.2
    ```
  - `sync_scores()` / `state_changed` already re-run `_refresh_hud`, which resyncs the
    label after `apply_act_score` clears the set.

### Step 9 — Docs

- `SCORING_MATH_PLAN.md`: mark §15c header `✅ implemented 2026-MM-DD` and tick each
  numbered item; leave §15d (open knobs) as-is.
- `DESIGN_DOC.md`: §5 Scoring — record the settled aggregation
  (`act payout = R × C × combo`, combo = 1 + 0.1·U distinct classes/act; the §5 item-3
  "combo system" idea is now the shipped design); §9 vocabulary table — mark the
  "Overscore bonus | Tips" row retired (§8c′); §15 Map & World — goal formula pointer to
  SCORING_MATH_PLAN §15b (run_manager.gd's header references DESIGN_DOC §15).
- `Locale/localization.csv` row (Step 8).

---

## Migration / save-compat notes

- **`RunState.overscore_ratio_sum`**: ~~field stays for save-compat~~ **DELETED
  2026-07-17** (owner ruling after the tests passed): field, `_build_payload` copy,
  and the fuzz coverage all removed. Old saves drop the unknown property on load.
- **Old goals:** node goals are NEVER persisted (`MapNodeRoles` header, meta doesn't
  round-trip) — resuming an old save re-runs `assign()` and gets NEW-formula goals
  immediately. Only `run.pending_goal` (a show already in progress) keeps its old
  number for that one show; `game.gd:154` clamps it ≥ 1. Acceptable and self-healing.
- **Old deck mid-run:** the run's deck is deep-copied into `RunState.card_datas` at
  `new_run` — existing runs keep their 24-card deck to completion; only new runs get
  deck12. No migration needed.
- **`combo_classes` on old snapshots:** absent from old serialized GameData → Resource
  default `[]` on load. Correct, because U is intra-act only: every committed snapshot
  is taken between acts (`save_state` at the end of `_perform_submit`), where the set is
  empty by definition.
- **Undo / act-cancel / pending_action replay:** all three restore `state` from a
  snapshot (`_runtime_state`), which resets `combo_classes` to the pre-act (empty) set
  automatically — that is WHY it lives on GameData. A replayed `&"on_run_scorer"`
  re-collects U deterministically from the same replayed scoring.
- **Resume re-running `_resolve_game`** (`_resume_after_visuals`, game.gd:193–204): no
  combo interaction — payout was already applied into `mult_score`/`total_score`.

## Test plan

**New suite** `Tests/Engine/test_combo.gd` (`suite_name() -> "COMBO"`, style of
`Tests/Engine/test_act_score.gd`; add as child in `Tests/all_tests.tscn`):
- `test_class_key_table` — pin the Step-2 examples verbatim (build `Scoring.Result` via
  `Result.create` + manual `copies_count`/`copy_size` overrides; include: pair, trips,
  quad, 2× quad, 5× pair ≠ 10× pair ≠ 1× pair, 5-straight ≠ 6-straight, straight flush
  `:FF`, flush house `:FF`, suited multi-set `:MF`, pure flush, high card; plus
  rank-independence: two pairs of different ranks → same key).
- `test_apply_act_score_combo` — `GameData` with `row_total=10, col_total=5,
  combo_classes=["a","b","c"]` → `mult_score == 65` (`int(50·1.3)`), set cleared,
  totals zeroed; rounding case `7×3` with one class → `int(23.1) == 23`; empty set →
  exact legacy `row×col`.
- `test_snapshot_carries_combo` — `duplicate_state()` copies `combo_classes`
  independently (mutate original after duplicating, copy unchanged) — this is the undo
  guarantee.
- `test_register_combo` — via a headless `Game` (pattern from
  `Tests/Engine/test_game_headless.gd`): duplicate key returns false and doesn't emit;
  empty key never registers; δ: with `duplicate_class_scale = 0.5` a second same-class
  `score_line` banks `int(score·0.5)` (restore the setting after — settings resource is
  shared).

**Rework** `Tests/Map/test_run_manager.gd` (`test_goal_curve` lines 65–88,
`test_record_win` 90–95):
- `goal_for(0,0,false) == int(G0 · difficulty)`; strictly monotone in
  `boosters_on_path`; boss = 2× (within int rounding); lap multiplies by LAP_MULT and
  caps at `mini(lap,30)`; `difficulty` scales (set via
  `SettingsManager.settings.difficulty`, restore after).
- `test_record_win`: fame += total_score; `overscore_ratio_sum` UNCHANGED (the old
  inflation assertions are deleted).

**Extend** `Tests/Map/test_map_roles.gd` (has `_line_export(max_depth)` synthetic
overlay + `_run_with` already):
- goals equal across ranks before the first booster rank; strictly higher after each
  booster rank crossing; monotone non-descending along the line for BOTH lap parities;
  boss goal ≥ every game goal; determinism (existing test) still holds.
- crafted-graph boosters_on_path: with `_booster_ranks` known from the seed, assert
  `ladder[p]` matches a hand-computed `goal_for(count_of_ranks_below_p, ...)`.

**Must stay green (run `scenes/all_tests.tscn`, owner-run):** `test_scoring.gd` incl.
SECTION 8 leaderboard (ScoreModel untouched), `test_act_score.gd` (empty-combo payout
identical), `test_game_headless.gd`, `test_prop_engine.gd`, `test_map_traversal.gd`,
`test_persistence_fuzz.gd`.

**Owner verification script (one in-game show):**
1. With a pre-change `run.tres` present: resume → map opens, node goals show the new
   curve, the in-progress show keeps its old goal; finish it; `record_win` banks fame.
2. New run → deck picker shows 20 cards, ranks 1–5, no talents.
3. Play one show with temporary prints in `apply_act_score`
   (`print("act: R=%d C=%d U=%d payout=%d")`): combo label appears/pulses on pair →
   trips (two ticks), does NOT tick on a second pair; payout matches hand-computed
   `int(R·C·(1+0.1U))`; after Submit the label resets.
4. Undo across a Submit → score and combo state rewind together.
5. Run `scenes/all_tests.tscn` → all suites green (owner runs it; agent never launches
   Godot headless while the editor is open).

## Sequencing & sim-oracle checkpoints

Steps 1→9 in order; the game is runnable after every step (Step 3 is payout-neutral
until Step 4; Step 5+6 land together in one edit session since `goal_for`'s signature
changes and `map_node_roles` is its only game caller).

Sim re-runs (`py solatro/tools/scoring_sim.py --final --q 0.35`, Python 3.9 via `py`):
- After Step 7 (deck swap): confirm the printed fit still reads `g0≈130, alpha≈4.2` —
  the sim already models exactly this deck, so no drift is expected; if the owner
  changed booster content meanwhile, re-fit and update `G0`/`GOAL_ALPHA`.
- `--baseline` must keep reproducing §3 (combo off in baseline mode) — no sim edits in
  this pass.

## Owner rulings already obtained (2026-07-17, during planning)

1. **Mod-activation U scope + identity — RESOLVED:** all non-engine mods count by
   default. Exclusion mechanism is a per-mod `combo_key()` opt-out override on the
   modifier itself (NOT an `is_data_in_rules` membership check), and `combo_key(hook)`
   takes the hook name so a mod implementing multiple hooks can opt individual hooks in
   or out on itself. Engine rules-deck mod scripts get `return ""` overrides (Step 4d′).
2. **Combo label — RESOLVED:** inside `%MultScore` beside Row/Col; hidden at x1.0;
   empties after payout (U resets per act).

## Remaining open questions for the owner (minor; recommended defaults stated)

3. **`GameData.goal` default** is 100 (always overwritten by `pending_goal` in real
   flow). Update to 130 to match G0, or leave? (cosmetic; recommend leave + comment).
4. **LAP_MULT stays 2.5?** §15b requires the term but doesn't re-price the constant;
   2.5 is the incumbent. Recommend keep, flag as a §15d playtest knob.
5. **overscore_ratio_sum deletion timing** — RESOLVED 2026-07-17: deleted immediately
   (owner ruling after the verification pass).

---

## COPY-PASTE HANDOFF FOR THE IMPLEMENTING AGENT

```
# HANDOFF — Solatro scoring rework: EXECUTE the implementation plan

Repo: C:\Users\khanr\Documents\GitHub\gamedev (Godot 4.7 project in solatro/).

READ FIRST, in order:
1. solatro/SCORING_IMPL_PLAN.md  — the approved step-by-step plan you are executing
   (pseudocode per file, migration notes, test plan, sequencing). Follow it
   mechanically; it was verified against current source line numbers.
2. solatro/SCORING_MATH_PLAN.md §15 — the authoritative DESIGN spec (§15a scoring,
   §15b goals, §8c′ why overscore is removed). The design is FINAL — do not relitigate.

Mission: implement Steps 1–9 of SCORING_IMPL_PLAN.md:
 1. player_settings.gd: difficulty + duplicate_class_scale knobs.
 2. scoring.gd: static Scoring.class_key(Result) (NO ScoreModel changes).
 3. game_data.gd: @export_storage combo_classes, COMBO_STEP, combo_mult(),
    apply_act_score = int(R*C*combo) + clear.
 4. game.gd/card_environment.gd/card_modifier.gd + prop seams: register_combo,
    combo_changed signal, score_line class collection + δ lever, _note_mod_fired
    dispatch hook, combo_key(hook) on modifiers (default = script path; engine
    rules mods override to "" — owner ruled opt-out lives on the mod, per-hook
    capable, NOT an is_data_in_rules check).
 5. run_manager.gd: goal_for(boosters_on_path, lap, is_boss) with
    G0=130/GOAL_ALPHA=4.2/N0=20/BOOSTER_YIELD=5, record_win = fame only
    (overscore retired, RunState field stays unread).
 6. map_node_roles.gd: per-progress goal ladder with monotone clamp,
    _boosters_before rank count; map.gd:68 fallback → int(G0).
 7. Decks/deck.gd: deck12 = ranks 1–5 × 4 suits, 20 cards, no talents;
    get_deck() returns it (keep deck11 code).
 8. UI: combo label under %MultScore + GAME_COMBO row in Locale/localization.csv +
    game_view.gd refresh/pulse. Scene edit needs the owner's editor CLOSED.
 9. Docs: mark SCORING_MATH_PLAN §15c implemented; DESIGN_DOC §5/§9/§15 updates.
Plus the new Tests/Engine/test_combo.gd suite and the test reworks in
Tests/Map/test_run_manager.gd and Tests/Map/test_map_roles.gd, per the plan's
Test plan section.

HARD RULES (owner conventions — non-negotiable):
- NEVER run headless Godot while the owner's editor is open. Verification = add
  prints, then ASK THE OWNER to run scenes/all_tests.tscn and the in-game
  verification script in the plan.
- No `git add`, no commits (owner uses GitHub Desktop).
- Warnings-as-errors: type EVERY array and EVERY for-loop variable
  (`for col : ArrayCardData in ...`).
- Do NOT modify Scoring.ScoreModel hand formulas; test_scoring.gd SECTION 8 must
  stay green.
- Tests: TestSuite pattern (Tests/Support/test_base.gd), never Decks/deck.gd in
  tests (use Tests/Support/test_decks.gd), respect TestLog.
- Tuning knobs via Scripts/player_settings.gd + SettingsManager.settings,
  setters emit settings_changed.
- Keep commented-out code; `##` purpose comments on every new method.
- User-facing text via TRANSLATION.find + Locale/localization.csv, never literals.
- Per-act state lives on GameData (snapshots/saves/undo carry it), never on Game.

The plan's "Owner rulings already obtained" section records two decided
questions (mod-U opt-out mechanism, combo label placement/visibility) — they are
already baked into the steps; follow them as written. For the three "Remaining
open questions" (GameData.goal default, LAP_MULT value, overscore field deletion
timing) use the plan's recommended defaults and list what you assumed in your
final report.

Sim oracle: after the deck swap, run `py solatro/tools/scoring_sim.py --final
--q 0.35` and confirm the fit still prints g0≈130 / alpha≈4.2 (safe to run —
Python, not Godot).

Deliver: code + tests + doc edits per plan, then a summary of every file touched,
which open-question defaults you applied, and the owner's verification checklist.
```

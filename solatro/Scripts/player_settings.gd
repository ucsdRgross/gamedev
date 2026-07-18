class_name PlayerSettings
# TODO: move settings that dont need to be saved back to their files after done testing

extends Resource
## The player-tunable knobs, saved to user://settings.tres by SettingsManager on EVERY change
## (each setter emits settings_changed) and read LIVE by the views — changing any of these
## mid-run re-lays the board / retimes running animations immediately, nothing captures a value
## at spawn. Shared adjustable/speed-up tuning belongs HERE, not as constants in the code.

signal settings_changed

## Master animation pacing: the baseline seconds per game step (card moves, score pops, the
## base of every prop-tick duration). Smaller = a faster game everywhere. Read via
## Game.get_delay(), which also applies the act speed-up compression below while resolving.
@export var base_delay : float = 1:
	set(value):
		base_delay = value
		settings_changed.emit()
## Card size multiplier: scales the card footprint, the board layout pitch, formation offsets,
## and the prop art (props scale by card_scale / PropVisual.AUTHORED_CARD_SCALE).
@export var card_scale : float = 2.5:
	set(value):
		card_scale = value
		settings_changed.emit()
## How far stacked cards fan apart, as a multiplier of the base strip height (CARD_SEPARATION).
## Also the live projection factor for spread_by_separation prop formations — their height
## tracks this, capped at exactly one full card.
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

@export_group("Animation flourishes (fractions of get_delay)")
## Every flourish length is a FRACTION of the live get_delay() — so all animations respect the
## global pacing (and the act compression below) and can never run longer than the delay allows.
## Despawn/void-exit fade length.
@export var prop_fade_fraction : float = 0.15:
	set(value):
		prop_fade_fraction = value
		settings_changed.emit()
## Ballistic poof (scale-up + fade in place at the target) length.
@export var prop_poof_fraction : float = 0.12:
	set(value):
		prop_poof_fraction = value
		settings_changed.emit()
## Teleport blink flash decay length.
@export var prop_flash_fraction : float = 0.15:
	set(value):
		prop_flash_fraction = value
		settings_changed.emit()
## Card jump: time to raise into the held pose (anim_jump's return value — callers wait this).
@export var card_jump_raise_fraction : float = 0.4:
	set(value):
		card_jump_raise_fraction = value
		settings_changed.emit()
## Card jump: scale-pulse up time.
@export var card_jump_pulse_fraction : float = 0.3:
	set(value):
		card_jump_pulse_fraction = value
		settings_changed.emit()
## Card jump: pulse settle-back time.
@export var card_jump_settle_fraction : float = 0.2:
	set(value):
		card_jump_settle_fraction = value
		settings_changed.emit()

@export_group("Act speed-up (per-activation compression)")
## Long/looping score cascades shrink their per-step delay per unit of WORK PROCESSED
## (Game.act_calls — the same counter act_event_cap trips on), so the speed-up is deterministic
## and incremental: every mod/prop activation advances it one notch, never a wall-clock read.
## Normal play never compresses (SUIT_PROPS_PLAN §1.6, reworked 2026-07-16). Delay multiplier =
## compress_ratio ^ (act_calls / compress_step_calls): smaller ratio = harder speed-up per step.
@export_range(0.5, 1.0, 0.01) var compress_ratio : float = 0.85:
	set(value):
		compress_ratio = value
		settings_changed.emit()
## Activations per compression step — smaller = the speed-up ramps sooner.
@export var compress_step_calls : float = 50.0:
	set(value):
		compress_step_calls = value
		settings_changed.emit()
## Floor of the compression ramp: the delay never shrinks below this fraction of base_delay
## (until the soft cutoff below snaps it to instant).
@export_range(0.0, 1.0, 0.01) var compress_min_factor : float = 0.05:
	set(value):
		compress_min_factor = value
		settings_changed.emit()
## Past this many activations inside ONE act, pacing snaps to instant (delay 0) outright.
@export var compress_soft_calls : int = 2000:
	set(value):
		compress_soft_calls = value
		settings_changed.emit()
## Runaway-chain safety: an act that processes more than this many units (mod invocations, prop
## slot entries) is cut off — "the audience went home" (Game.note_processing).
@export var act_event_cap : int = 6000:
	set(value):
		act_event_cap = value
		settings_changed.emit()

@export_group("Balance — act scoring (SCORING_MATH_PLAN §15a)")
## §15a combo step: each distinct combo class this act adds this to the act multiplier
## (combo = 1 + step·U). 0.1 shipped; 0.2 = twice as swingy.
@export var combo_step : float = 0.1:
	set(value):
		combo_step = value
		settings_changed.emit()

## δ fallback lever (§15a): duplicate-CLASS melds score ×δ. 1.0 = off (ship default);
## only lower during playtest if dump crushes everything.
@export var duplicate_class_scale : float = 1.0:
	set(value):
		duplicate_class_scale = value
		settings_changed.emit()

## TEST variant (2026-07-17, unpriced): act payout = (R + C) × combo instead of
## (R × C) × combo. Linearizes payout growth — re-fit goal_g0/goal_alpha (sim
## `--final --additive`) before judging difficulty with this on. Ships OFF.
@export var score_additive : bool = false:
	set(value):
		score_additive = value
		settings_changed.emit()

@export_group("Balance — goal curve (SCORING_MATH_PLAN §15b)")
## Global goal multiplier (§15b "difficulty"): ±15% ≈ one persona band. THE dial for
## run win-rate; default 1.0.
@export var difficulty : float = 1.0:
	set(value):
		difficulty = value
		settings_changed.emit()

## Goal at the 20-card start deck (re-fit via `py solatro/tools/scoring_sim.py --final`).
@export var goal_g0 : float = 130.0:
	set(value):
		goal_g0 = value
		settings_changed.emit()

## Power on N̂/N0 (log-fit of the §15b table): how hard goals ramp per booster crossed.
@export var goal_alpha : float = 4.2:
	set(value):
		goal_alpha = value
		settings_changed.emit()

## Start-deck size the curve is anchored to (only meaningful alongside the start deck).
@export var goal_n0 : float = 20.0:
	set(value):
		goal_n0 = value
		settings_changed.emit()

## Expected cards per booster-role node (dupes packs, 5 cards) — the N̂ growth per booster.
@export var booster_yield : float = 5.0:
	set(value):
		booster_yield = value
		settings_changed.emit()

## Lap-target anchor (boss show) goal multiplier.
@export var boss_mult : float = 2.0:
	set(value):
		boss_mult = value
		settings_changed.emit()

## Per completed lap goal multiplier (endless scaling — owner-required term, §15d knob).
@export var lap_mult : float = 2.5:
	set(value):
		lap_mult = value
		settings_changed.emit()

@export_group("Leak sentinel (debug builds only)")
## Master switch for the playtest leak sentinel (Scripts/leak_sentinel.gd): compares live
## CardData against the cards reachable from legitimate owners at quiescent moments and
## push_errors a source-naming histogram on sustained excess. No effect in release builds.
@export var leak_sentinel_enabled : bool = true:
	set(value):
		leak_sentinel_enabled = value
		settings_changed.emit()
## Unreachable cards tolerated before a check counts as a strike (transient drops settle).
@export var leak_sentinel_slack : int = 8:
	set(value):
		leak_sentinel_slack = value
		settings_changed.emit()
## Consecutive over-slack checks before the sentinel reports (one-off spikes stay quiet).
@export var leak_sentinel_strikes : int = 3:
	set(value):
		leak_sentinel_strikes = value
		settings_changed.emit()
## Seconds between periodic sentinel checks (checks also run on map entry / show exit).
@export var leak_sentinel_interval : float = 30.0:
	set(value):
		leak_sentinel_interval = value
		settings_changed.emit()

@export_group("Balance — luck (booster generation)")
## Max per-component non-null chance in booster generation (luck() asymptote).
@export var luck_cap : float = 0.6:
	set(value):
		luck_cap = value
		settings_changed.emit()

## Fame at which luck() reaches half of luck_cap.
@export var fame_half : float = 5000.0:
	set(value):
		fame_half = value
		settings_changed.emit()

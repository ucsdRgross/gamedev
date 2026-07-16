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

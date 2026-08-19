@tool
# ⚠ **`@tool` BECAUSE EDITOR-SIDE TOOLS CALL METHODS ON THIS RESOURCE.** Without it the editor loads
# PlayerSettings as a PLACEHOLDER instance: properties still read, but any method call throws
# *"Attempt to call a method on a placeholder instance"* — which is exactly what
# `spotlight_reveal_beat_fraction` did from `spotlight_tool.gd` (owner report). The other
# resources these tools edit (`FxStyle` and every subclass) are already `@tool` for the same reason.
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

@export_group("Visual effects")
## How long a status's visual effect takes to grow into a stack change, as a fraction of ONE PROP
## TICK. The owner's metric is "fast enough before the next status effect gets applied", and
## statuses land on prop ticks — so this is derived from the live tick, never a wall-clock number.
## Below 1.0 a change always completes with margin, at any pacing, under any compression.
@export var fx_transition_fraction : float = 0.6:
	set(value):
		fx_transition_fraction = value
		settings_changed.emit()
## Master effect strength: multiplies every effect's brightness and reaches ZERO for a "reduce
## effects" accessibility setting. Flicker and pulse are separate levers in FxStyle so
## photosensitivity can be addressed without dimming the whole board.
@export_range(0.0, 2.0, 0.05) var fx_intensity : float = 1.0:
	set(value):
		fx_intensity = value
		settings_changed.emit()

@export_group("Animation flourishes (fractions of get_delay)")
## Every flourish length is a FRACTION of the live get_delay() — so all animations respect the
## global pacing (and the act compression below) and can never run longer than the delay allows.
## Share of a void-exit's LEG spent fading out (1 = it fades the whole way off the board). NOT a
## fraction of get_delay like its neighbours: the fade has to happen WHILE the prop is still
## crossing the last visible strip. It used to be a short tween that started only once the prop had
## already reached its void point, which the play-area rect clips — so props read as vanishing
## rather than leaving (owner report).
@export_range(0.05, 1.0, 0.05) var prop_exit_fade_share : float = 1.0:
	set(value):
		prop_exit_fade_share = value
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

@export_group("Spotlight")
## How dark the dim goes under the light layer, 0 = untouched and 1 = the dim colour outright.
##
## ⚠ **`Q84`=(b) PUT THIS ON THE STYLE RESOURCE AND `Q168`=(a) CALLS IT A PLAYER SETTING. The plan
## resolves to `Q84`, style-only — but the light layer has no style resource** (`FxGlowStyle`'s three
## `.tres` are the GLOW's, and §16 keeps the layer's own knobs separate). Living here is the reading
## that exists; if that is wrong, file a gap rather than splitting the difference — see
## `design/spotlight/PLAN.md` §1.11's G0 note.
## ⚠ **0.0 IS THE OFF SWITCH, AND IT IS SUPPORTED ON PURPOSE** (owner: *"make sure dim
## can be turned off if needed by tunables, it just occured to me that dim might flash if speed is
## high"*). `LightLayer._dim_target()` multiplies by this, so 0 means the dim never rises at any
## speed while beams, circles and glow all still play. **That is the remedy if the per-section pulse
## (GAP-006) reads as a flash at high act speed** — and it is a different control from `fx_intensity`,
## which `Q83` forbids from removing the dim (gate G2.4). Between them: `fx_intensity = 0` keeps the
## dim and drops the lights; `spotlight_dim_target = 0` keeps the lights and drops the dim.
## ⚠ Pinned by `test_the_dim_can_be_turned_off_entirely()` — an off switch nothing asserts is an off
## switch that quietly stops working.
@export_range(0.0, 1.0, 0.01) var spotlight_dim_target : float = 0.75:
	set(value):
		spotlight_dim_target = value
		settings_changed.emit()
## The dim's rise, as a FRACTION of `Game.get_delay()` (`Q167`=a — never wall-clock, so the whole
## effect follows the game's pacing and the act speed-up compresses it with everything else).
@export var spotlight_dim_in_fraction : float = 0.5:
	set(value):
		spotlight_dim_in_fraction = value
		settings_changed.emit()
## The dim's fall, same units.
@export var spotlight_dim_out_fraction : float = 0.5:
	set(value):
		spotlight_dim_out_fraction = value
		settings_changed.emit()
## ⚠ **A SHALLOWER DIM OUTSIDE SCORING THAN INSIDE IT** (`Q245`=c). The spotlight fires whenever a
## card becomes active — including every placement in ordinary play — and the owner's own scrutiny
## note on that question is *"(a) means the screen pulses dark on every single card you place"*. This
## multiplies `spotlight_dim_target` when the cue is not part of a scoring act.
@export_range(0.0, 1.0, 0.01) var spotlight_dim_casual_scale : float = 0.35:
	set(value):
		spotlight_dim_casual_scale = value
		settings_changed.emit()
## **THE HOLD BEAT** — how long a revealed section stays lit before its scoring starts, as a fraction
## of `Game.get_delay()` (design chart D's **D13**, `Q68`=a *"yes, ~half a delay"*, `PLAN.md` §1.11).
##
## ⚠ **WITHOUT THIS THE PER-SECTION PULSE IS INVISIBLE, WHICH IS HOW IT WAS FOUND.** GAP-006 made the
## show fade as scoring begins; the trace then showed `revealed` and `reveal_faded` landing on the
## SAME FRAME with `show=0.000`, because nothing between them ever waited. The dim eases toward a
## target it was already being pulled away from, so it never left zero. A spotlight you cannot see is
## the same as no spotlight.
## ⚠ A FRACTION, never wall-clock: it compresses with the act speed-up like every other duration here.
@export var spotlight_hold_fraction : float = 0.5:
	set(value):
		spotlight_hold_fraction = value
		settings_changed.emit()
## **HOW LONG A ROW TAKES TO EXPAND OR COLLAPSE** — `DESIGN.md` §16, chart D6 (*"PlayArea grows each
## reveal row's gap to a full card, TWEENED over reveal_fraction"*), a fraction of `Game.get_delay()`
## like everything else (`Q167`=a).
##
## ⚠ **THE REVEAL ITSELF (S16) IS NOT BUILT — this knob times the SIMULATION of it** in
## `Tools/spotlight_tool.tscn`, which draws the answer so it can be judged before it is implemented.
## It is here rather than in the tool because §16 says so and because S16 will want the same number:
## a second copy in the tool would be a knob the shipped reveal then disagreed with.
## ⚠ Added after the owner reported *"row separation is not smooth. cards jump to their new
## spot instantly"* — there was no duration to ease over because there was no knob.
@export var spotlight_reveal_fraction : float = 0.4:
	set(value):
		spotlight_reveal_fraction = value
		settings_changed.emit()
## **HOW FAST THE LIGHTS THEMSELVES RISE AND FALL — separate from the DIM's own rate.**
##
## ⚠ **THESE EXIST BECAUSE THE TWO USED TO BE ONE PAIR.** `LightLayer._show` (which scales every
## light's intensity) and `LightLayer._dim` both eased over `spotlight_dim_in_fraction` /
## `spotlight_dim_out_fraction`, so the beams and the darkness always reached full at the same instant
## and there was no way to separate them. Owner: *"allow tuning brightness and dimness to
## reach their max effect at different rates instead of both lerping to full at exact same time, like
## allowing dimness to happen twice as fast before beams finish"*.
##
## ⚠ **THE SPLIT IS SHOW vs DIM, NOT IN vs OUT.** `spotlight_dim_*_fraction` now drives ONLY the dim;
## these drive the lights. Set `dim_in` to half of `show_in` and the room darkens before the beams
## arrive, which is the effect asked for.
## ⚠ Fractions of `Game.get_delay()` like every other duration (`Q167`=a), so they compress with the
## act speed-up rather than running to a wall clock.
@export var spotlight_show_in_fraction : float = 0.5:
	set(value):
		spotlight_show_in_fraction = value
		settings_changed.emit()
@export var spotlight_show_out_fraction : float = 0.5:
	set(value):
		spotlight_show_out_fraction = value
		settings_changed.emit()
## **HOW LONG A REVEAL BEAT ACTUALLY NEEDS — the RISE plus the HOLD, as one number both the game and
## the tuning tool read.**
##
## ⚠ **THE HOLD RAN CONCURRENTLY WITH THE RISE, SO IT BOUGHT NO TIME AT FULL.** `Game`'s reveal beat
## waited `get_delay() * spotlight_hold_fraction` and then ended the reveal — while `LightLayer._show`
## was still climbing over `spotlight_show_in_fraction`, and the lights over `spawn`/`travel`. At the
## shipped defaults those are all 0.5, so the show reached full at the exact instant the reveal ended:
## the fade-out played honestly and the spotlight was never held. Owner: *"it doesnt cut
## out immediately but still does the fadeout"*.
##
## ⚠ **ONE ACCESSOR, TWO CALLERS.** `Game._score_section`'s beat and `spotlight_tool._beat()` both use
## it — a second copy of this arithmetic is the two-representations defect that produced most of this
## stream's bugs, and it would let the tool show a hold the game does not have.
## ⚠ `spotlight_hold_fraction` is TIME AT FULL (§16: *"the beat after `on_active`"*), which is why it
## is ADDED rather than compared.
func spotlight_reveal_beat_fraction() -> float:
	var rise : float = maxf(spotlight_show_in_fraction,
			maxf(spotlight_spawn_fraction, spotlight_travel_fraction))
	return rise + maxf(spotlight_hold_fraction, 0.0)

## **HOW FAR A REVEALED ROW OPENS** — `DESIGN.md` chart K10b, **GAP-009**.
##
## ⚠ **THE DERIVED OPENING IS RETIRED, AND THE OWNER'S COUNTER-EXAMPLE IS WHY.** K10b used to size the
## gap so there was *"no visible gap"*, measured from the lowest card that had to be seen. On a FLUSH
## every card in the row is lit and jumps, so the lowest such card is the lowest card on the board —
## and the opening then lifted rows *"that arent part of actual scored set"*. A rule meant to uncover
## one buried card moved the whole board, so the size no longer depends on any card's position.
##
## ⚠ **"ALLOW CHOOSING BETWEEN" IS THE ANSWER ITSELF, WHICH IS WHY THIS IS A KNOB AND NOT A CONSTANT.**
## The owner picks by eye in `Tools/spotlight_tool.tscn`.
## ⚠ `Q43`=(a) (a fixed full card height) is NO LONGER superseded — it is `CARD_HEIGHT`.
enum SeparationMode {
	## One full card height: the row opens completely and nothing stays covered.
	CARD_HEIGHT,
	## Card height MINUS the jump rise, so a card that does not jump stays slightly covered — the
	## jumping cards clear the row while the rest still read as stacked.
	JUMP_ADJUSTED,
}
@export var spotlight_separation_mode : SeparationMode = SeparationMode.CARD_HEIGHT:
	set(value):
		spotlight_separation_mode = value
		settings_changed.emit()
## **CHART E's TRAVEL** — how long a light takes to move from one card to the next, as a fraction of
## `Game.get_delay()`. The brief's whole requirement for it: *"spotlights spawned during scoring phase
## need to move their spotlights to next row/col after done with current set, **no instant movements
## or spawning in and out**"*.
## ⚠ `Q63`=(a) — it holds FULL SIZE in transit, like a real followspot; it does not dim or shrink.
## ⚠ `Q64`=(a) — every travelling light moves at once, not staggered.
@export var spotlight_travel_fraction : float = 0.5:
	set(value):
		spotlight_travel_fraction = value
		settings_changed.emit()
## A brand-new light fading in. ⚠ `Q65`=(a): it **fades in already aimed at its target**, rather than
## travelling in along its beam from the origin — the searchlight-sweep reading was declined.
@export var spotlight_spawn_fraction : float = 0.3:
	set(value):
		spotlight_spawn_fraction = value
		settings_changed.emit()
## A surplus light fading out, in place, on the card it was already on (chart E3).
@export var spotlight_retire_fraction : float = 0.3:
	set(value):
		spotlight_retire_fraction = value
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

## Goal at the 20-card start deck (re-fit via `py solatro/Tools/scoring_sim.py --final`).
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

@export_group("Patience (idle-move pressure)")
## Emitted when patience_max GROWS, with the increase. Owner ruling A1: raising the
## cap also raises the LIVE counter by the same amount (a rule card granting patience takes effect
## this round); lowering it does NOT touch the live counter. Game listens and edits state.patience.
signal patience_max_increased(delta: int)

## Idle card moves allowed per round before Next auto-fires. Also the value patience resets to.
## Floored at 1 — a round must always allow at least one move.
@export var patience_max : int = 3:
	set(value):
		var clamped : int = maxi(value, 1)
		var delta : int = clamped - patience_max
		patience_max = clamped
		if delta > 0:
			patience_max_increased.emit(delta)
		settings_changed.emit()

## Which card STAGES' triggered modifiers hold the countdown (a move that fires one of them was
## interesting, so it costs no patience). Default: only cards in play on the board count.
@export var patience_influence_play : bool = true:
	set(value):
		patience_influence_play = value
		settings_changed.emit()
@export var patience_influence_zone : bool = false:
	set(value):
		patience_influence_zone = value
		settings_changed.emit()
@export var patience_influence_draw : bool = false:
	set(value):
		patience_influence_draw = value
		settings_changed.emit()
@export var patience_influence_discard : bool = false:
	set(value):
		patience_influence_discard = value
		settings_changed.emit()
@export var patience_influence_rules : bool = false:
	set(value):
		patience_influence_rules = value
		settings_changed.emit()

## Track already-seen modifiers (like the combo class set): the SECOND time the same modifier
## triggers this round it no longer holds patience. Off = every trigger holds.
@export var patience_track_uniques : bool = true:
	set(value):
		patience_track_uniques = value
		settings_changed.emit()

## When the seen-set clears: false (default) = every Next, true = only after a Submit act.
@export var patience_reset_uniques_on_act : bool = false:
	set(value):
		patience_reset_uniques_on_act = value
		settings_changed.emit()

## Hooks that never count toward patience even from an approved stage (e.g. add
## &"on_can_place_stack" to stop the placement legality query itself from holding the counter).
## Empty = every hook counts.
@export var patience_disabled_hooks : Array[StringName] = []:
	set(value):
		patience_disabled_hooks = value
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

## Free rerolls a pack opening starts with — ONE shared pool across every shown card
## (ChoiceViewer.Data.rerolls). Future reroll modifiers adjust the viewer's pool from here.
@export var booster_reroll_pool : int = 5:
	set(value):
		booster_reroll_pool = maxi(value, 0)
		settings_changed.emit()

## Fame at which luck() reaches half of luck_cap.
@export var fame_half : float = 5000.0:
	set(value):
		fame_half = value
		settings_changed.emit()

@export_group("Picture wall")
## Debug flag (`Q159`=a, node K11): makes `ProfileManager.is_unlocked()` return true for every
## picture WITHOUT touching `user://profile.tres` at all -- the file is neither read for this nor
## written because of it. `DESIGN.md` §5's tunables table omits this row; `wall_debug_readout`
## (`Q210`) shows debug flags belong in this group regardless, so the omission is a documentation
## bug against `Q159`'s own source rather than a reason to leave the flag out (gap-protocol rule 4).
@export var wall_unlock_all : bool = false:
	set(value):
		wall_unlock_all = value
		settings_changed.emit()

## Every row below is `DESIGN.md` §5's tunables table, transcribed exactly -- names, defaults, no
## extras, no re-defaults (PLAN.md §2, S8's done-when). `wall_view_texture_scale` is deliberately
## ABSENT: §5 marks it *derived*, and §1.8 (GAP-002) writes `SubViewport.size` straight from the
## on-screen footprint clamped by `wall_view_min_texture_px` -- there is no resolution manager and
## nothing left for a scale factor to do, so exporting it would be a knob that silently does
## nothing (see ASSUMPTIONS.md).
##
## ⚠ GAP-008 (owner-answered, option a): `wall_gap`, `wall_view_margin`,
## `wall_ellipse_aspect_min` and `wall_ellipse_aspect_max` are NOT transcribed here even though
## §5 lists them. `WallLayout` (Scripts/Wall/wall_layout.gd, PLAN.md §1.2) wins as their one home
## -- `gap_px`, `view_margin`, `ellipse_aspect_min`, `ellipse_aspect_max` -- because `WallPacker`
## is a pure function that reads only the layout's copies (§1.3) and never touches this singleton,
## so a settings-side duplicate would have no reader. See ASSUMPTIONS.md.

## The wall's own transition clock, independent of `Game.get_delay()` (`Q46`).
@export var wall_transition_delay : float = 0.6:
	set(value):
		wall_transition_delay = value
		settings_changed.emit()
## Share of the transition spent zooming out (`Q47`).
@export var wall_zoom_out_fraction : float = 0.35:
	set(value):
		wall_zoom_out_fraction = value
		settings_changed.emit()
## Share spent travelling (`Q47`).
@export var wall_travel_fraction : float = 0.40:
	set(value):
		wall_travel_fraction = value
		settings_changed.emit()
## Share spent zooming in -- phases overlap, so the three shares sum past 1 (`Q47`).
@export var wall_zoom_in_fraction : float = 0.35:
	set(value):
		wall_zoom_in_fraction = value
		settings_changed.emit()
## Extra share of the picture's size revealed beyond the frame at the zoom-out stop (`Q35`, `Q48`).
@export var wall_frame_reveal_margin : float = 0.08:
	set(value):
		wall_frame_reveal_margin = value
		settings_changed.emit()
## Replaces transitions with cross-fades (`Q172`).
@export var wall_reduced_motion : bool = false:
	set(value):
		wall_reduced_motion = value
		settings_changed.emit()
## Info mode toggle (`Q135`). ⚠ SESSION STATE, NOT A SAVED SETTING -- deliberately NOT `@export`
## and deliberately silent. `J1`/`Q135` and PLAN.md §4's anti-scope item 9 both say info mode does
## not survive a quit, so persisting it was never wanted; every toggle nevertheless wrote the whole
## of `user://settings.tres` (every setter here emits `settings_changed`, which `SettingsManager`
## saves on) and woke the four listeners that recompute card sizes and FX styling, none of which
## read this. Without `@export` it is not stored, so C3 holds by construction rather than by the
## startup clear -- which STAYS anyway, because a `settings.tres` written by an older build still
## carries the key and `ResourceLoader` will happily set it on load.
var wall_info_mode : bool = false
## Floor on a wall-view texture's short axis, in px -- feeds `SubViewport.size` (`Vector2i`)
## directly, so this stays an integer pixel count (`Q87`, GAP-002).
@export var wall_view_min_texture_px : int = 64:
	set(value):
		wall_view_min_texture_px = value
		settings_changed.emit()
## Held-stick repeat delay, in seconds (`Q116`).
@export var wall_selection_repeat_delay : float = 0.4:
	set(value):
		wall_selection_repeat_delay = value
		settings_changed.emit()
## M9 (PICTURE_WALL.md): three §5 rows were STRUCK here rather than wired, because the source
## answers put their value somewhere else or rejected the feature outright -- the same call GAP-008
## made for `wall_gap`/`wall_view_margin`/`wall_ellipse_aspect_min`/`_max`. See
## `ASSUMPTIONS.md` for the citations:
##   `wall_frame_thickness_fraction` -- `Q36`'s note: "should be authored per picture"
##                                      (`PictureEntry.frame_px`); this was `Q36`'s option (b).
##   `wall_live_screen_cap`          -- `Q204` is gated on `Q203`=b; `Q203`=a keeps every screen.
##   `wall_design_height`            -- `Q30` is gated on `Q29`=a; `Q29`=b is per-screen
##                                      (`PictureEntry.design_size`).
## MINOR (PICTURE_WALL.md): the transition's easing curves were typed into `wall_transition.gd`
## and `main.gd` as `Tween.TRANS_*`/`EASE_*` literals, which §1.8 forbids for a design choice and
## which S34's own done-when forbids twice over -- its tool must expose "the easing selections", and
## "no knob above requires editing a `.tres` or a `.gd` by hand to change". `DESIGN.md` §5 simply had
## no rows for them; these are those rows. Defaults are exactly the shipped literals, so this
## promotes without changing a frame.
##
## Typed as `Tween.TransitionType`/`Tween.EaseType` so the Inspector (and S34's tool) shows named
## curves rather than raw ints.
## Travel curve (`Q53`=b): "a gentler, more even glide than the zoom".
@export var wall_travel_trans : Tween.TransitionType = Tween.TRANS_SINE:
	set(value):
		wall_travel_trans = value
		settings_changed.emit()
@export var wall_travel_ease : Tween.EaseType = Tween.EASE_IN_OUT:
	set(value):
		wall_travel_ease = value
		settings_changed.emit()
## Zoom curve, shared by both legs; the two legs differ only in their EASE (`C4`-`C6`, §1.10).
@export var wall_zoom_trans : Tween.TransitionType = Tween.TRANS_EXPO:
	set(value):
		wall_zoom_trans = value
		settings_changed.emit()
@export var wall_zoom_out_ease : Tween.EaseType = Tween.EASE_OUT:
	set(value):
		wall_zoom_out_ease = value
		settings_changed.emit()
@export var wall_zoom_in_ease : Tween.EaseType = Tween.EASE_IN:
	set(value):
		wall_zoom_in_ease = value
		settings_changed.emit()
## Debug instrumentation, debug builds only (`Q210`).
@export var wall_debug_readout : bool = false:
	set(value):
		wall_debug_readout = value
		settings_changed.emit()
## Touch target size in millimetres (`Q123`, GAP-004) -- converted through live DPI, so this stays
## a float alongside the mm-to-px math that reads it.
@export var wall_touch_target_mm : float = 9.0:
	set(value):
		wall_touch_target_mm = value
		settings_changed.emit()
## Clamp floor on the touch target, in px -- a bad DPI reading cannot make controls smaller than
## this (GAP-004). Float: clamped alongside the continuous mm-to-px conversion, not a whole-pixel
## SubViewport size like `wall_view_min_texture_px`.
@export var wall_touch_target_min_px : float = 32.0:
	set(value):
		wall_touch_target_min_px = value
		settings_changed.emit()
## Clamp ceiling on the touch target, in px -- nor larger (GAP-004).
@export var wall_touch_target_max_px : float = 96.0:
	set(value):
		wall_touch_target_max_px = value
		settings_changed.emit()
## Distance delta before a two-finger drag counts as a pinch, in px (GAP-003) -- compared against
## a continuously computed touch distance, hence a float.
@export var wall_pinch_threshold_px : float = 24.0:
	set(value):
		wall_pinch_threshold_px = value
		settings_changed.emit()
## How far a focused picture overfills the window at rest, as a multiplier on `focused_scale()`'s
## fill zoom (`H3`, GAP-011) -- was a typed literal in `wall_picture.gd` (`_OVERFILL_MARGIN`),
## which §1.8 forbids for anything an author could reasonably argue with. 1.0 would leave the
## frame exactly flush with the window edge on a matching aspect; > 1.0 guarantees it stays hidden.
@export var wall_overfill_margin : float = 1.02:
	set(value):
		wall_overfill_margin = value
		settings_changed.emit()
## S25 (B10, Q7=b): ONE authored light position, shared by the whole wall, so every picture's
## shadow is offset the same way -- "pictures across the wall are lit consistently." Was a typed
## literal in `wall_picture.gd` (`WallPicture.SHADOW_OFFSET`), which §1.8 forbids; this default
## (18, 26) is that exact prior value, so promoting it changes no observable behaviour. In wall
## SPACE (the same units `PictureEntry.frame_px` and `WallLayout.gap_px` use), not screen pixels.
@export var wall_light_offset : Vector2 = Vector2(18.0, 26.0):
	set(value):
		wall_light_offset = value
		settings_changed.emit()
## S27 (Q129=a): the info card's own fixed width, in screen px -- anchored to the bottom of the
## WINDOW (screen space, not diegetic), so its width is a screen-pixel count like the touch-target
## trio, never a wall-space size.
@export var wall_info_card_width : float = 480.0:
	set(value):
		wall_info_card_width = value
		settings_changed.emit()
## S27 (J12/Q140 override -- "text size never shrinks... the card SCROLLS UPWARD over the whole
## picture" once content exceeds this): the height, in screen px, past which the card stops
## growing and scrolls instead of continuing to expand.
@export var wall_info_card_max_height : float = 320.0:
	set(value):
		wall_info_card_max_height = value
		settings_changed.emit()
## GAP-013 (owner-answered a): the drop shadow's own alpha -- was a typed literal in
## `wall_picture.gd` (`Color(0.0, 0.0, 0.0, 0.35)`, since S10), which §1.8 forbids for a visible
## design choice. ONE value for the whole wall (unlike `frame_colour`, which is per-picture),
## same "one authored value for everyone" shape `wall_light_offset` already set for shadows.
## Default 0.35 is that exact prior value -- promoting it changes no observable behaviour.
@export var wall_shadow_opacity : float = 0.35:
	set(value):
		wall_shadow_opacity = value
		settings_changed.emit()
## GAP-014 (owner-answered a): a multiplier on the ordinary transition clock
## (`base_delay * wall_transition_delay`), applied ONLY to M2's one-off opening reveal (choosing a
## save, every launch) -- never to an ordinary Wall-button press, which stays at the plain clock.
## > 1.0 makes the reveal slower/longer than an ordinary transition, matching M2's "distinct...
## longer, slower" requirement with one number rather than a second, independent duration/easing.
@export var wall_reveal_delay_scale : float = 1.8:
	set(value):
		wall_reveal_delay_scale = value
		settings_changed.emit()
## PICTURE_WALL.md B2: how far a selected picture lifts off the wall in wall-view (S36, F11,
## Q70=c's "shape and motion, not colour"). Was a typed literal in `wall_picture.gd`
## (`_SELECTED_LIFT := Vector2(0.0, -14.0)`); §1.8 makes a visible design choice like this a
## defect, same category as `wall_overfill_margin`/`wall_light_offset`. Default (0, -14) is that
## exact prior value -- promoting it changes no observable behaviour.
@export var wall_selected_lift : Vector2 = Vector2(0.0, -14.0):
	set(value):
		wall_selected_lift = value
		settings_changed.emit()

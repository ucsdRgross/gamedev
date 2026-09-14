@tool
#⚠ `@tool` BECAUSE EDITOR-SIDE TOOLS CALL METHODS ON THIS RESOURCE. Without it the editor loads
#PlayerSettings as a PLACEHOLDER instance: properties still read, but any method call throws
#"Attempt to call a method on a placeholder instance".

#The other resources those tools edit, FxStyle and every subclass, are already @tool for the same
#reason.
class_name PlayerSettings
# TODO: move settings that dont need to be saved back to their files after done testing

extends Resource
#Saved to user://settings.tres by SettingsManager on EVERY change, each setter emitting
#settings_changed, and read LIVE by the views: changing any of these mid-run re-lays the board and
#retimes running animations immediately, nothing capturing a value at spawn.

#Shared adjustable and speed-up tuning belongs HERE, not as constants in the code.

## The player-tunable knobs.

signal settings_changed

#Smaller is a faster game everywhere. Read via Game.get_delay(), which also applies the act
#speed-up compression below while resolving.

## Master animation pacing: the baseline seconds per game step.
@export var base_delay : float = 1:
	set(value):
		base_delay = value
		settings_changed.emit()
#It scales the card footprint, the board layout pitch, formation offsets, and the prop art, which
#scales by card_scale over PropVisual.AUTHORED_CARD_SCALE.

## Card size multiplier.
@export var card_scale : float = 1.0:
	set(value):
		card_scale = value
		settings_changed.emit()
#Also the live projection factor for spread_by_separation prop formations, whose height tracks
#this, capped at exactly one full card.

## How far stacked cards fan apart, as a multiplier of the base strip height.
@export var card_separation_scale : float = 1:
	set(value):
		card_separation_scale = value
		settings_changed.emit()
#Bigger is slower and more visible props. Read live by PropLayer every frame.

## Seconds a prop spends crossing ONE board slot, as get_delay() times this.
@export var prop_tick_fraction : float = 0.45:
	set(value):
		prop_tick_fraction = value
		settings_changed.emit()

@export_group("Visual effects")
#The owner's metric is "fast enough before the next status effect gets applied", and statuses land
#on prop ticks, so this is derived from the live tick and never a wall-clock number. Below 1.0 a
#change always completes with margin, at any pacing and under any compression.

## How long a status's visual effect takes to grow into a stack change, as a fraction of ONE TICK.
@export var fx_transition_fraction : float = 0.6:
	set(value):
		fx_transition_fraction = value
		settings_changed.emit()
#It reaches ZERO for a "reduce effects" accessibility setting. Flicker and pulse are separate
#levers in FxStyle, so photosensitivity can be addressed without dimming the whole board.

## Master effect strength: multiplies every effect's brightness.
@export_range(0.0, 2.0, 0.05) var fx_intensity : float = 1.0:
	set(value):
		fx_intensity = value
		settings_changed.emit()

@export_group("Animation flourishes (fractions of get_delay)")
#Every flourish length is a FRACTION of the live get_delay(), so all animations respect the global
#pacing and the act compression and can never run longer than the delay allows.

#⚠ This one is NOT a fraction of get_delay like its neighbours: the fade has to happen WHILE the
#prop is still crossing the last visible strip, because the play-area rect clips the void point and
#a fade starting there reads as vanishing rather than leaving.

## Share of a void-exit's LEG spent fading out; 1 fades the whole way off the board.
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
#⚠ 0.0 IS THE OFF SWITCH, AND IT IS SUPPORTED ON PURPOSE (owner: *"make sure dim can be turned
#off if needed by tunables, it just occured to me that dim might flash if speed is high"*).
#LightLayer._dim_target() multiplies by this, so 0 means the dim never rises at any speed.

#It is a different control from fx_intensity, which must never remove the dim: fx_intensity = 0
#keeps the dim and drops the lights, while this at 0 keeps the lights and drops the dim.

#It lives on the player settings rather than a style resource because the light layer has no style
#resource of its own. Pinned by test_the_dim_can_be_turned_off_entirely(): an off switch nothing
#asserts is an off switch that quietly stops working.

## How dark the dim goes under the light layer: 0 is untouched, 1 is the dim colour outright.
@export_range(0.0, 1.0, 0.01) var spotlight_dim_target : float = 0.75:
	set(value):
		spotlight_dim_target = value
		settings_changed.emit()
#Never wall-clock, so the effect follows the game's pacing and the act speed-up compresses it.

## The dim's rise, as a FRACTION of Game.get_delay().
@export var spotlight_dim_in_fraction : float = 0.5:
	set(value):
		spotlight_dim_in_fraction = value
		settings_changed.emit()
## The dim's fall, same units.
@export var spotlight_dim_out_fraction : float = 0.5:
	set(value):
		spotlight_dim_out_fraction = value
		settings_changed.emit()
#⚠ A SHALLOWER DIM OUTSIDE SCORING THAN INSIDE IT. The spotlight fires whenever a card becomes
#active, including every placement in ordinary play, and dimming equally there would mean *"the
#screen pulses dark on every single card you place"* (owner).

## Multiplies spotlight_dim_target when the cue is not part of a scoring act.
@export_range(0.0, 1.0, 0.01) var spotlight_dim_casual_scale : float = 0.35:
	set(value):
		spotlight_dim_casual_scale = value
		settings_changed.emit()
#⚠ WITHOUT THIS THE PER-SECTION PULSE IS INVISIBLE. The show fades as scoring begins, so with
#nothing waiting between them `revealed` and `reveal_faded` land on the SAME FRAME at show=0.000:
#the dim eases toward a target it is already being pulled away from and never leaves zero.

#⚠ A FRACTION, never wall-clock: it compresses with the act speed-up like every duration here.

## THE HOLD BEAT: how long a revealed section stays lit before its scoring starts.
@export var spotlight_hold_fraction : float = 0.5:
	set(value):
		spotlight_hold_fraction = value
		settings_changed.emit()
#PlayArea grows each reveal row's gap to a full card, tweened over this.

#⚠ THE REVEAL ITSELF IS NOT BUILT - this knob times the SIMULATION of it in
#Tools/spotlight_tool.tscn, which draws the answer so it can be judged before it is implemented.

#It is here rather than in the tool because the shipped reveal will want the same number, and a
#second copy in the tool would be a knob the shipped reveal then disagreed with. Without it there
#is no duration to ease over, and cards jump to their new spot instantly (owner report).

## HOW LONG A ROW TAKES TO EXPAND OR COLLAPSE, as a fraction of Game.get_delay().
@export var spotlight_reveal_fraction : float = 0.4:
	set(value):
		spotlight_reveal_fraction = value
		settings_changed.emit()
#⚠ THE SPLIT IS SHOW vs DIM, NOT IN vs OUT. spotlight_dim_*_fraction drives ONLY the dim; these
#drive the lights. Set dim_in to half of show_in and the room darkens before the beams arrive,
#which is the effect the owner asked for.

#Owner: *"allow tuning brightness and dimness to reach their max effect at different rates instead
#of both lerping to full at exact same time, like allowing dimness to happen twice as fast before
#beams finish"*. One pair for both cannot express that at all.

#⚠ Fractions of Game.get_delay() like every other duration, so they compress with the act
#speed-up rather than running to a wall clock.

## HOW FAST THE LIGHTS THEMSELVES RISE AND FALL, separate from the DIM's own rate.
@export var spotlight_show_in_fraction : float = 0.5:
	set(value):
		spotlight_show_in_fraction = value
		settings_changed.emit()
@export var spotlight_show_out_fraction : float = 0.5:
	set(value):
		spotlight_show_out_fraction = value
		settings_changed.emit()
#⚠ THE HOLD MUST NOT RUN CONCURRENTLY WITH THE RISE, OR IT BUYS NO TIME AT FULL. Waiting only
#get_delay() * spotlight_hold_fraction ends the reveal while LightLayer._show is still climbing
#over spotlight_show_in_fraction and the lights over spawn and travel.

#At the shipped defaults those are all 0.5, so the show reaches full at the exact instant the
#reveal ends: the fade-out plays honestly and the spotlight is never held. Owner: *"it doesnt cut
#out immediately but still does the fadeout"*.

#⚠ ONE ACCESSOR, TWO CALLERS: Game._score_section's beat and spotlight_tool._beat(). A second
#copy of this arithmetic would let the tool show a hold the game does not have.

#spotlight_hold_fraction is TIME AT FULL, the beat after on_active, which is why it is ADDED rather
#than compared.

## HOW LONG A REVEAL BEAT ACTUALLY NEEDS: the RISE plus the HOLD, as one number.
func spotlight_reveal_beat_fraction() -> float:
	var rise : float = maxf(spotlight_show_in_fraction,
			maxf(spotlight_spawn_fraction, spotlight_travel_fraction))
	return rise + maxf(spotlight_hold_fraction, 0.0)

#⚠ THE OPENING MUST NOT BE DERIVED FROM ANY CARD'S POSITION. Sizing the gap from the lowest card
#that had to be seen breaks on a FLUSH, where every card in the row is lit, so the opening lifts
#rows *"that arent part of actual scored set"* (owner).

#A rule meant to uncover one buried card moved the whole board. Which of the two modes reads best
#is chosen by eye in Tools/spotlight_tool.tscn, which is why this is a knob and not a constant.

## HOW FAR A REVEALED ROW OPENS.
enum SeparationMode {
	## One full card height: the row opens completely and nothing stays covered.
	CARD_HEIGHT,
	## Card height MINUS the jump rise, so a card that does not jump stays slightly covered.
	JUMP_ADJUSTED,
}
@export var spotlight_separation_mode : SeparationMode = SeparationMode.CARD_HEIGHT:
	set(value):
		spotlight_separation_mode = value
		settings_changed.emit()
#The brief's whole requirement: *"spotlights spawned during scoring phase need to move their
#spotlights to next row/col after done with current set, no instant movements or spawning in and
#out"*.

#⚠ A travelling light holds FULL SIZE in transit, like a real followspot - it does not dim or
#shrink - and every travelling light moves at once, never staggered.

## How long a light takes to move from one card to the next, as a fraction of Game.get_delay().
@export var spotlight_travel_fraction : float = 0.5:
	set(value):
		spotlight_travel_fraction = value
		settings_changed.emit()
#⚠ It fades in already aimed at its target, never travelling in along its beam from the origin.
#There is no searchlight sweep.

## A brand-new light fading in.
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
#Long and looping score cascades shrink their per-step delay per unit of WORK PROCESSED, the same
#counter act_event_cap trips on, so the speed-up is deterministic and incremental: every activation
#advances it one notch, never a wall-clock read.

#Normal play never compresses. The delay multiplier is compress_ratio raised to act_calls over
#compress_step_calls, so a smaller ratio is a harder speed-up per step.
@export_range(0.5, 1.0, 0.01) var compress_ratio : float = 0.85:
	set(value):
		compress_ratio = value
		settings_changed.emit()
## Activations per compression step — smaller = the speed-up ramps sooner.
@export var compress_step_calls : float = 50.0:
	set(value):
		compress_step_calls = value
		settings_changed.emit()
#Until the soft cutoff below snaps it to instant.

## Floor of the compression ramp: the delay never shrinks below this fraction of base_delay.
@export_range(0.0, 1.0, 0.01) var compress_min_factor : float = 0.05:
	set(value):
		compress_min_factor = value
		settings_changed.emit()
## Past this many activations inside ONE act, pacing snaps to instant (delay 0) outright.
@export var compress_soft_calls : int = 2000:
	set(value):
		compress_soft_calls = value
		settings_changed.emit()
#"The audience went home", enforced in Game.note_processing.

## Runaway-chain safety: an act processing more than this many units is cut off.
@export var act_event_cap : int = 6000:
	set(value):
		act_event_cap = value
		settings_changed.emit()

@export_group("Balance — act scoring (SCORING_MATH_PLAN §15a)")
#The combo is 1 + step times the distinct class count. 0.1 shipped; 0.2 is twice as swingy.

## Combo step: each distinct combo class this act adds this to the act multiplier.
@export var combo_step : float = 0.1:
	set(value):
		combo_step = value
		settings_changed.emit()

## What a FIRST-of-its-class meld or effect adds to the combo multiplier.
@export var combo_unique_step : float = 1.0:
	set(value):
		combo_unique_step = value
		settings_changed.emit()

#Melds and effects contribute on the same terms; only whether the class is new decides the step.

## What a REPEAT of a class already seen adds.
@export var combo_repeat_step : float = 0.5:
	set(value):
		combo_repeat_step = value
		settings_changed.emit()

## Ceiling on the combo multiplier. 0 = OFF, no ceiling.
@export var combo_cap : float = 0.0:
	set(value):
		combo_cap = value
		settings_changed.emit()



@export_group("Balance — goal curve (SCORING_MATH_PLAN §15b)")
#Plus or minus 15 % is about one persona band. THE dial for run win-rate; the default is 1.0.

## Global goal multiplier.
@export var difficulty : float = 1.0:
	set(value):
		difficulty = value
		settings_changed.emit()

## Goal at the 20-card start deck; re-fit with `scoring_sim.py --grid-goals --trials 800 --q 0.25`.
@export var goal_g0 : float = 18720.0:
	set(value):
		goal_g0 = value
		settings_changed.emit()

#⚠ FLAT (0) IS A PLACEHOLDER. Measured, a show's score peaks three nodes in and then falls: the
#board holds 25 cells all run, so deck size is the wrong driver and a larger power loses late nodes.

## Power on the deck-size ratio: how hard goals ramp per booster crossed. 0 is flat.
@export var goal_alpha : float = 0.0:
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
#It compares live CardData against the cards reachable from legitimate owners at quiescent moments
#and push_errors a source-naming histogram on sustained excess. No effect in release builds.

## Master switch for the playtest leak sentinel.
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

#ONE shared pool across every shown card. Future reroll modifiers adjust the viewer's pool here.

## Free rerolls a pack opening starts with.
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
## Treat every picture as unlocked. Debug only: never reads or writes the profile.
@export var wall_unlock_all : bool = false:
	set(value):
		wall_unlock_all = value
		settings_changed.emit()

## Seconds for one wall transition, independent of base_delay's game clock.
@export var wall_transition_delay : float = 0.6:
	set(value):
		wall_transition_delay = value
		settings_changed.emit()
## Share of the transition spent zooming out.
@export var wall_zoom_out_fraction : float = 0.35:
	set(value):
		wall_zoom_out_fraction = value
		settings_changed.emit()
## Share of the transition spent travelling.
@export var wall_travel_fraction : float = 0.40:
	set(value):
		wall_travel_fraction = value
		settings_changed.emit()
## Share of the transition spent zooming in. The three phases OVERLAP, so the shares sum past 1.
@export var wall_zoom_in_fraction : float = 0.35:
	set(value):
		wall_zoom_in_fraction = value
		settings_changed.emit()
## Extra share of a picture's size revealed beyond its frame at the zoom-out stop.
@export var wall_frame_reveal_margin : float = 0.08:
	set(value):
		wall_frame_reveal_margin = value
		settings_changed.emit()
## Replace wall transitions with a cross-fade.
@export var wall_reduced_motion : bool = false:
	set(value):
		wall_reduced_motion = value
		settings_changed.emit()
#Info mode is per screen - the map can be left in info mode while the board is not - so the owner
#of the wall keeps a flag per picture and writes the focused one here on every focus change.
#Everything downstream reads this single value, so nothing else has to know the mode is per screen.

#⚠ Session state: NOT @export, so it is never saved or loaded, and toggling it must not emit
#settings_changed - nothing recomputes off it, and a save per toggle would rewrite the whole file.

## Whether info mode is on FOR THE PICTURE CURRENTLY FOCUSED.
var wall_info_mode : bool = false
## Floor on a wall-view texture's short axis, in whole px. Feeds `SubViewport.size` directly.
@export var wall_view_min_texture_px : int = 64:
	set(value):
		wall_view_min_texture_px = value
		settings_changed.emit()
## Seconds a selection stick must be held before it repeats.
@export var wall_selection_repeat_delay : float = 0.4:
	set(value):
		wall_selection_repeat_delay = value
		settings_changed.emit()

## Easing of the travel leg.
@export var wall_travel_trans : Tween.TransitionType = Tween.TRANS_SINE:
	set(value):
		wall_travel_trans = value
		settings_changed.emit()
@export var wall_travel_ease : Tween.EaseType = Tween.EASE_IN_OUT:
	set(value):
		wall_travel_ease = value
		settings_changed.emit()
## Easing of both zoom legs; the two legs differ only in their ease.
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
## Draw the wall's debug readout. Debug builds only.
@export var wall_debug_readout : bool = false:
	set(value):
		wall_debug_readout = value
		settings_changed.emit()
## Touch target size in millimetres, converted through live DPI.
@export var wall_touch_target_mm : float = 9.0:
	set(value):
		wall_touch_target_mm = value
		settings_changed.emit()
## Smallest touch target in px, whatever the DPI reading says.
@export var wall_touch_target_min_px : float = 32.0:
	set(value):
		wall_touch_target_min_px = value
		settings_changed.emit()
## Largest touch target in px.
@export var wall_touch_target_max_px : float = 96.0:
	set(value):
		wall_touch_target_max_px = value
		settings_changed.emit()
## How far two fingers must change distance, in px, before the drag counts as a pinch.
@export var wall_pinch_threshold_px : float = 24.0:
	set(value):
		wall_pinch_threshold_px = value
		settings_changed.emit()
#1.0 leaves the frame flush with the window edge on a matching aspect; above 1.0 hides it.

## How far a focused picture overfills the window at rest, as a multiplier on the fill zoom.
@export var wall_overfill_margin : float = 1.02:
	set(value):
		wall_overfill_margin = value
		settings_changed.emit()
#One light position for the whole wall, so the wall is lit consistently.

## Direction and distance every picture's drop shadow is offset, in wall space.
@export var wall_light_offset : Vector2 = Vector2(18.0, 26.0):
	set(value):
		wall_light_offset = value
		settings_changed.emit()
## The info card's fixed width in screen px; the card is anchored to the window, not the wall.
@export var wall_info_card_width : float = 480.0:
	set(value):
		wall_info_card_width = value
		settings_changed.emit()
## Height in screen px past which the info card stops growing and scrolls its text instead.
@export var wall_info_card_max_height : float = 320.0:
	set(value):
		wall_info_card_max_height = value
		settings_changed.emit()
## Alpha of every picture's drop shadow.
@export var wall_shadow_opacity : float = 0.35:
	set(value):
		wall_shadow_opacity = value
		settings_changed.emit()
#When true the popup behaves as it always has with Info mode off, and MIGRATES to the info card
#when Info mode is on: one description, two places to read it depending on the mode. When false
#there is no popup at all, and a description is only ever visible in Info mode.

#Either way the popup NEVER shows while Info mode is on: one card describes one thing, and two
#panels describing the same card is what having a single info card replaced.

## Whether a screen's own description popup shows while Info mode is OFF.
@export var wall_screen_popups : bool = true:
	set(value):
		wall_screen_popups = value
		settings_changed.emit()
#Info mode zooms out until the whole screen fits in the window ABOVE the card; this is the one part
#the card may cover, so it reads as sitting in FRONT of the picture rather than floating in a band
#of its own. 0 leaves the screen entirely clear of the card.

#⚠ The reserve is measured against wall_info_card_max_height, NOT the card's live height: the
#card sizes itself to its content, and a camera that tracked that would re-zoom on every hover.

## How much of the info card is allowed to OVERLAP the bottom of the screen, in screen px.
@export var wall_info_card_overlap : float = 24.0:
	set(value):
		wall_info_card_overlap = value
		settings_changed.emit()
#1.0 makes entering info mode take exactly as long as an ordinary wall move; below 1.0 it snaps in
#faster, which suits a reveal that only shifts the camera a little way down.

## Multiplier on the transition clock for the info-mode zoom, in and out.
@export var wall_info_zoom_scale : float = 1.0:
	set(value):
		wall_info_zoom_scale = value
		settings_changed.emit()
#So it runs slower and longer than an ordinary wall move.

## Multiplier on the transition clock for the one-off opening reveal.
@export var wall_reveal_delay_scale : float = 1.8:
	set(value):
		wall_reveal_delay_scale = value
		settings_changed.emit()
## How far a selected picture lifts off the wall in wall-view, in wall space.
@export var wall_selected_lift : Vector2 = Vector2(0.0, -14.0):
	set(value):
		wall_selected_lift = value
		settings_changed.emit()

@export_group("Balance — grid board")
#The grid count target is ceil(deck_size_at_game_start / this), clamped to [1, grid_max_count].

## Deck size per unlocked grid.
@export var grid_cards_per_unlock : int = 52:
	set(value):
		grid_cards_per_unlock = maxi(value, 1)
		settings_changed.emit()
## Hard cap on the number of grids the deck-size allotment will ever create.
@export var grid_max_count : int = 3:
	set(value):
		grid_max_count = maxi(value, 1)
		settings_changed.emit()
#⚠ A SubViewport OVER THE GPU'S MAXIMUM TEXTURE SIZE FAILS SILENTLY: the framebuffer is
#destroyed and the size is internally set to 0 while the script property still reports the
#oversized value.

#Older GPUs cap at 4096 and this project ships the Compatibility renderer, so the clamp is the only
#thing standing between a wide picture and a black screen. The layout stays at full size; only the
#resolution is capped.

## The largest render target the game picture may ask the GPU for, per axis, in pixels.
@export_range(256, 16384, 1) var game_picture_max_render_px : int = 4096:
	set(value):
		game_picture_max_render_px = maxi(value, 256)
		settings_changed.emit()
## How long the view takes to travel from one grid to the next, in seconds. 0 snaps.
@export_range(0.0, 2.0, 0.01, "or_greater") var grid_pan_duration : float = 0.35:
	set(value):
		grid_pan_duration = maxf(value, 0.0)
		settings_changed.emit()
#It is spent as VELOCITY into the scroll container's own overdrag, which supplies the counterforce
#and carries the board back to rest, so 0 silences the bounce without touching the pan and no value
#can leave the board parked off its edge.

## How hard a pan past the outermost grid pushes the board, in pixels per second.
@export_range(0.0, 4000.0, 1.0, "or_greater") var grid_bounce_velocity_px : float = 900.0:
	set(value):
		grid_bounce_velocity_px = maxf(value, 0.0)
		settings_changed.emit()
#⚠ Millimetres, not pixels: the same physical swipe must mean the same thing on every screen.

#⚠ A DISTANCE TO TRAVEL IS NOT A THING TO HIT, AND THE PLATFORMS KEEP THEM APART. Clamped to the
#touch-target bounds, whose floor of 32 px is about 8.5 mm at 96 DPI, an 8 mm default sits BELOW its
#own floor and turning the knob down does nothing at all.

#Android carries three separate quantities: a touch target at about 9 mm, plain touch slop - how far
#a touch may wander before it is a scroll - at about 1.5 mm, and a PAGING touch slop for a swipe
#between pages, which is this gesture, defined as exactly twice the plain slop, about 3 mm.

#A swipe threshold sized like a fingertip is roughly three times what the platform asks for.

## How far a finger must travel before a one-finger drag counts as a pan, in MILLIMETRES.
@export_range(0.0, 40.0, 0.1, "or_greater") var grid_swipe_threshold_mm : float = 3.0:
	set(value):
		grid_swipe_threshold_mm = maxf(value, 0.0)
		settings_changed.emit()
#The guard against a wild DPI reading. The defaults bracket the gesture rather than the fingertip:
#the floor is plain touch slop, below which a tap's own wander would page the board, and the ceiling
#is a touch target, above which a swipe costs more travel than a button costs width.

## The swipe threshold's OWN bounds, in millimetres.
@export_range(0.0, 40.0, 0.1, "or_greater") var grid_swipe_threshold_min_mm : float = 1.5:
	set(value):
		grid_swipe_threshold_min_mm = maxf(value, 0.0)
		settings_changed.emit()
@export_range(0.0, 40.0, 0.1, "or_greater") var grid_swipe_threshold_max_mm : float = 9.0:
	set(value):
		grid_swipe_threshold_max_mm = maxf(value, 0.0)
		settings_changed.emit()
#OFF by default: each grid sizes its own rows, so a deep stack in one grid does not stretch the
#same row in every other. ON, row r takes a SHARED maximum across every grid, and the boards read
#as one ruled sheet.

#⚠ PURELY VISUAL - it must never affect scoring, and a test asserts the same board scores
#identically with it on and off.

## Cross-grid row alignment.
@export var grid_align_rows_globally : bool = false:
	set(value):
		grid_align_rows_globally = value
		settings_changed.emit()
#Its OWN vertical scroll, independent of the board's, covers whatever a deep stack adds past this.

## The pinned Entrance strip's height, as a multiple of one card's height.
@export var entrance_visible_rows : float = 1.5:
	set(value):
		entrance_visible_rows = maxf(value, 0.5)
		settings_changed.emit()

#The split is exactly what it reads as: the HUD gets this share of the width and the board gets the
#rest. Nothing sizes anything else - the picture's own width is derived from the board alone, and
#the HUD is then scaled to its share of whatever that came to.

## The share of the board's width the HUD column occupies; the furniture is SCALED to fit it.
@export var hud_width_fraction : float = 0.25:
	set(value):
		hud_width_fraction = clampf(value, 0.0, 0.9)
		settings_changed.emit()

#0 turns it off, which is what a phone-sized screen wants: on a short screen the band costs more of
#the board than the breathing room is worth.

## The clear band above the board and below the Entrance, in CARD ROWS.
@export var board_edge_pad_rows : float = 1.0:
	set(value):
		board_edge_pad_rows = maxf(value, 0.0)
		settings_changed.emit()

@export_group("Balance — board plan")
## A rank match pays the rank the card prints times this, rounded up.
@export var plan_rank_match_step : float = 1.0:
	set(value):
		plan_rank_match_step = value
		settings_changed.emit()
## What a rank match pays when the rank has no value a whole number can hold.
@export var plan_rank_flat_fallback : int = 10:
	set(value):
		plan_rank_flat_fallback = value
		settings_changed.emit()
## What a rank match on an Ace pays, in place of the value it prints.
@export var plan_ace_value : int = 10:
	set(value):
		plan_ace_value = value
		settings_changed.emit()
## A talent match's share of the line's multiplier, which is the SUM of every share -- 1 is neutral.
@export var plan_talent_mult : float = 1.0:
	set(value):
		plan_talent_mult = value
		settings_changed.emit()
## A hat match's share of that same sum, and 1 is neutral there too.
@export var plan_hat_mult : float = 1.0:
	set(value):
		plan_hat_mult = value
		settings_changed.emit()
## The WHOLE opening deal's length as a multiple of get_delay(); the cells start total/cells apart.
@export var plan_reveal_multiplier : float = 1.0:
	set(value):
		plan_reveal_multiplier = value
		settings_changed.emit()

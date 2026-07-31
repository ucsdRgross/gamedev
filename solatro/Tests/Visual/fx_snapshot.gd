extends SnapshotScene
# res://Tests/Visual/fx_snapshot.gd
# ==============================================================================
# FX SNAPSHOTS — the visual half of the FX test plan.
#
# The headless suite cannot see a single pixel: --headless uses the dummy renderer, which never
# compiles a shader program, so a GLSL syntax error, an inverted sign, a flame growing DOWNWARD or
# an effect that draws nothing at all all pass it silently. This scene is the same code path run
# WINDOWED, where the GPU compiles and rasterizes for real: it lays out a grid of cases, captures
# the viewport, writes PNGs, and quits. A human (or an agent) reviews the images.
#
# Run it after ANY shader edit:
#     Godot --path solatro res://Tests/Visual/fx_snapshot.tscn
# Output: user://fx_snapshots/*.png — on Windows,
#     %APPDATA%\Godot\app_userdata\Solatro\fx_snapshots\
#
# Deliberately NOT in all_tests.tscn: it needs a window and a GPU, so it stays a separate,
# explicit run rather than something that breaks CI-style headless invocations.
#
# Determinism: the RNG is seeded and each attachment's clock is DRIVEN BY HAND to a fixed time
# rather than left to accumulate from real frame deltas, so two runs of an unchanged shader produce
# identical images and a diff means a real change.
#
# ⚠ EVERY PANEL WITH A **ROTATED** HOST IS NOT REPRODUCIBLE, and that is a property of rotated hosts
# rather than of any one shot. Re-measured 2026-07-30 across all three harnesses, two consecutive runs
# of an unchanged build with the per-host seed pinned: `02_fire_rotation` 12392 px, `05f_ball_rotation`
# 1035 px and `fx_behind`'s `behind_prop_turned` 15506 px, while every UPRIGHT panel in all three sets
# came back byte-identical. So the rotated shots are for EYE review ("are the flames upright, are the
# pixels square") and a pixel diff of one means nothing; `snapshot_diff.py` lists them in NOISY.
#
# ⚠ THE CAUSE IS STILL UNKNOWN AND THE OLD ONE IS RETIRED. This used to blame screen-space
# `fx_bayer(FRAGCOORD.xy)` — a fair hypothesis, but the dither moved onto the FX pixel grid in the
# simplify pass and the flakiness did not go with it. Pinning `_seed` (which this scene was NOT doing
# for fire, see `_attach_for`) does not remove it either. `test_pixels.gd` carries the standing warning
# about what that costs: a real optimisation was reverted on the evidence of one flaky rotated shot.
# ==============================================================================

const OUT_DIR := "user://fx_snapshots"

## Where each shot's clock is parked. Not zero: at t = 0 every noise term is at its starting
## value and the flames look artificially uniform.
const SHOT_TIME := 3.7

## The per-host random every shot pins. `FxAttachment._seed` is otherwise `randf() * 100.0` drawn in
## the constructor, and it drives the fire's noise offset — so leaving it free makes a panel's
## raggedness an artefact of where the global RNG happened to be, which is precisely the input
## `snapshot_diff.py` cannot tolerate. Any value works; this is simply one that is the same every run.
const SHOT_SEED := 12.5

## Largest art-unit-to-pixel blow-up. Cards are 38x50 art units; at 1:1 a whole flame is a few pixels
## and nothing is reviewable. Each shot may use LESS than this — see _zoom_for.
const ZOOM_MAX := 5.0

func _ready() -> void:
	if not begin(OUT_DIR, Vector2i(1280, 760)): return
	await _run()
	get_tree().quit()

## Every shot, in order. Each returns the cases it wants laid out across one screen.
func _run() -> void:
	await _shot("00_cover_field", "GEOMETRY ONLY (noise_amp 0, no dither): the COVER FIELD at 2 / 3 "
			+ "/ 4 / 6 / 8 taps — the bands are the tap ladder, and 4 is what ships", _cover_field())
	await _shot("00b_aperture", "the shape knobs: (aperture, fire_gain) pairs at full noise",
			_aperture_profile())
	await _shot("01_fire_ladder", "THE STACK RATIOS: Burning 1 / 3 / 12 / 40 / 200 stacks — every "
			+ "knob ramps, nothing jumps", _fire_ladder())
	await _shot("02_fire_rotation", "host rotated 0 / 30 / 45 / 90 deg — flames stay vertical",
			_fire_rotation())
	await _shot("02b_card_warp", "the card DEFORMS: corners stretched +0 / 10 / 25 / 45 % — every "
			+ "flame base must sit on the drawn outline, corners included", _card_warp())
	await _shot("03_surfaces","several surfaces in one COLUMN: 1 / 4 / 40 / 200 stacks over a "
			+ "RING — both arcs alight, and no flame ever leaps the hole", _surfaces())
	await _shot("04_shapes", "ring / blade / split-prop halves", _shapes())
	await _shot("05_balls", "juggling 1 / 3 / 8 / 50 balls", _balls())
	await _shot("05b_ball_path", "ONE ball traced around the cycle: phase 0 .. 0.875",
			_ball_path())
	await _shot("05c_ball_sphere", "ONE ball, big to small: banded curvature + on-surface highlight",
			_ball_sphere())
	await _shot("05d_ball_gravity", "the throw's easing: ball_gravity 1.0 / 1.6 / 2.4, evenly spaced "
			+ "in TIME — higher bunches them at the apex", _ball_gravity())
	await _shot("05e_ball_arcs", "the ARC LADDER: 2 / 4 / 6 / 8 arcs at one ball count — lanes fill "
			+ "in evenly between the carry and the throw", _ball_arcs())
	await _shot("05f_ball_rotation", "host rotated 0 / 30 / 45 / 90 deg — the PATTERN must not turn "
			+ "with it: balls stay on the (world-upright) oracle crosses", _ball_rotation())
	await _shot("06_ball_fire", "per-ball fire: 5 balls, 2 lit at different levels", _ball_fire())
	await _shot("06b_ball_fire_cycle", "the SAME two lit balls of six, stepped around the cycle — "
			+ "TWO plumes in every panel, or a lit ball is being suppressed", _ball_fire_cycle())
	await _shot("07_transition", "a stack change mid-ease: fractional counts on a FLAT host and on "
			+ "a CURVED one — the ring panels are where the anchor could pop", _transition())
	await _shot("08_focus_highlight", "host modulate 1.0 vs the card's focus highlight — the "
			+ "effects must brighten WITH their host (ruling 10)", _focus_highlight())
	await _shot_embers()

# ------------------------------------------------------------------ the shots

## THE COVER FIELD, NAKED — `noise_amp = 0` and no dither, so what is on screen is the tap ladder
## and nothing else. Cover is read off the FIRST tap that lands inside the mask, so it steps once per
## tap: at `n` taps the flame is `n` visible horizontal bands, the lowest flush with the card's top
## edge and the highest at exactly `height` above it.
##
## ⚠ THIS SHOT IS THE COST KNOB, NOT A LOOK KNOB. The shader is `mask_level` call count times cost
## per call and nothing else (FX_HANDOFF §9), so these panels are 2x to 4x apart in price. **4 is
## what ships.** What to look for: whether the banding at 4 is still visible once `noise_amp` is
## turned back up — if it is not, 6 and 8 are pure waste, which is the whole bet the noise model
## makes.
##
## The replacement for `00_tendril_count`, which counted a comb that no longer exists.
func _cover_field() -> Array[Case]:
	var out : Array[Case] = []
	for taps : int in [2, 3, 4, 6, 8]:
		var style := StatusBurning.CARD_FIRE_STYLE.duplicate() as FxFireStyle
		style.cover_taps = taps
		style.noise_amp = 0.0
		style.dither = 0.0
		# The RAW ladder is the whole point of this shot, so the phase dither that hides it in every
		# shipped style is off here — and only here.
		style.cover_dither = 0.0
		style.height = 20.0
		var live : Dictionary[StringName, float] = FxFire.stacks_live(6, style)
		var req := FxRequest.make(&"fire", FxFire.FIRE_SHADER, style, live[&"u_height"])
		req.live = live
		out.append(_card_case("%d taps" % taps, [req]))
	return out

## THE TWO SHAPE KNOBS, at full noise — because that is the only state they mean anything in. The
## flame is `cover * (((cover + aperture) * noise - aperture) * gain)`, so:
##  * **aperture** is a CUT: at average noise the value is zero at `cover = aperture`, so it is the
##    cover threshold below which nothing burns. LOW leaves a solid body of fire filling its whole
##    reach; HIGH eats the flame back toward its base.
##  * **gain** is contrast on what survives. Low is a soft gradient over the whole flame; high slams
##    it to the hot end and leaves a thin cool rim.
## They are not interchangeable and the panels have to show that: **0.10/4.0 is a solid bright
## block, 0.35/2.2 is the shipped ragged flame, 0.90/1.2 is a few flecks at the base.** If every
## panel looks the same, the noise is not reaching the shaping term.
##
## ⚠ THE APERTURE'S DIRECTION WAS DOCUMENTED BACKWARDS in the first build of this shot, and this
## panel is what caught it — which is the entire reason it exists.
##
## The replacement for `00b_ogee_profile`, which isolated an arch that no longer exists.
func _aperture_profile() -> Array[Case]:
	var out : Array[Case] = []
	# Three, not five: the quad is sized to the flame HEIGHT, so more panels means a smaller zoom
	# and the texture — the only thing this shot is about — stops being legible.
	var pairs : Array[Vector2] = [Vector2(0.1, 4.0), Vector2(0.35, 2.2), Vector2(0.9, 1.2)]
	for pair : Vector2 in pairs:
		var style := StatusBurning.CARD_FIRE_STYLE.duplicate() as FxFireStyle
		style.aperture = pair.x
		style.fire_gain = pair.y
		style.height = 26.0
		var live : Dictionary[StringName, float] = FxFire.stacks_live(2, style)
		var req := FxRequest.make(&"fire", FxFire.FIRE_SHADER, style, live[&"u_height"])
		req.live = live
		out.append(_card_case("aperture %.2f / gain %.1f" % [pair.x, pair.y], [req]))
	return out

## THE STACK RATIOS, WHICH ARE THE HEADLINE OF THE NOISE BUILD (owner 2026-07-29: *"make sure all
## params have scaling ratios as stacks increase"*). Every knob with a ratio in `FxFireStyle`'s
## "Stack scaling" group is driven from this one slider, in `FxFire.stacks_live`.
##
## What must be true across the five panels, and each is a separate way for the ramps to be wrong:
##  * the flame gets TALLER, HOTTER (further up the ramp) and MORE SOLID as the count rises;
##  * the grain gets COARSER rather than merely denser — `noise_scale_ratio` is negative for that;
##  * **nothing jumps.** At 1 stack every ratio is inert by construction (`log(1) = 0`), so panel one
##    is the base style exactly, and the rest must read as one continuous progression.
func _fire_ladder() -> Array[Case]:
	var out : Array[Case] = []
	for stacks : int in [1, 3, 12, 40, 200]:
		out.append(_card_case("%d" % stacks,
				[FxFire.request(&"fire", stacks, StatusBurning.CARD_FIRE_STYLE)]))
	return out

## Flames are gravity-aligned: the SILHOUETTE turns inside a still quad. Every one of these must
## show upright flames on a tilted card, with square (never diagonal) pixels.
func _fire_rotation() -> Array[Case]:
	var out : Array[Case] = []
	for deg : int in [0, 30, 45, 90]:
		var case := _card_case("%d deg" % deg,
				[FxFire.request(&"fire", 5, StatusBurning.CARD_FIRE_STYLE)])
		case.rotation = deg_to_rad(float(deg))
		out.append(case)
	return out

## THE DEFORMING CARD (owner 2026-07-29: *"I don't see fire effect warping with the card during
## playtesting"*). A card is skinned to a star rig whose animation is on AUTOPLAY, so its top edge is
## never where the authored 38x50 rectangle says it is — and a silhouette baked once at rest left the
## flames standing on a shape the card no longer had.
##
## Each panel stretches the four CORNERS further out, exactly as the rig does, and the outline drawn
## under the flames is the SAME one the attachment was handed. So the check is one glance and needs
## no measuring: **every flame base must sit on the drawn outline**, including out on the corners that
## moved. A flame hanging in the air off a stretched corner, or a corner left bare, is the bug.
##
## The last panel is deliberately past what the rig can reach: the failure it guards against is the
## quad clipping its own flames, and that shows up first at the extreme.
func _card_warp() -> Array[Case]:
	var out : Array[Case] = []
	for warp : float in [0.0, 0.1, 0.25, 0.45]:
		var case := _card_case("corners +%d%%" % roundi(warp * 100.0),
				[FxFire.request(&"fire", 8, StatusBurning.CARD_FIRE_STYLE)])
		case.outline = CardVisual.star_outline(CardVisual.CARD_SIZE, warp)
		out.append(case)
	return out

## MULTIPLE SURFACES IN ONE COLUMN — the behaviour that replaced the deleted `03_fire_wrap`
## (FX_HANDOFF §1.3), on the shape that has it: the ring holds its outer top arc high up and the
## upward-facing inner arc at the bottom of its hole far below, in the SAME columns.
##
## ⚠ IT STOPPED BEING A SPECIAL CASE (2026-07-29). The retired build had to argue that a comb cell
## spanning the ring grew one tendril on each arc; the cover field simply asks "how far above the
## nearest surface BELOW me am I", which every fragment in the hole answers with the inner arc and
## every fragment above the ring answers with the outer one. The stack sweep is kept because it is
## still the state space that matters — the ratios now change the flame's height and grain, and the
## ring is where a too-tall flame would first bridge something it must not.
##
## What to look for, by EYE:
##  * every panel lights BOTH surfaces — the outer arc and the floor of the hole;
##  * the hole's MIDDLE stays empty at every count, at 200 included. A flame bridging the two arcs
##    would be the ENORMOUS FLAME the owner forbade, and it is impossible by construction: no tap
##    reaches further than `height`, and the two arcs are 170 art units apart.
func _surfaces() -> Array[Case]:
	var out : Array[Case] = []
	for n : int in [1, 4, 40, 200]:
		var live : Dictionary[StringName, float] = FxFire.stacks_live(n, PropVisual.PROP_FIRE_STYLE)
		var req := FxRequest.make(&"fire", FxFire.FIRE_SHADER, PropVisual.PROP_FIRE_STYLE,
				live[&"u_height"])
		req.live = live
		out.append(_sprite_case("%d stacks" % n, HoopVisual.SHEET, HoopVisual.FRAMES,
				FxAttachment.Half.WHOLE, [req]))
	return out

## THE SHOT §1 IS ABOUT. Every panel is the REAL art with the REAL mask read out of its alpha, so
## what is on screen is exactly what a prop shows.
##
## What to look for, by EYE (never by counting columns — that is what reported two rejected builds as
## successes): flames on EVERY upward-facing surface, the hoop's inner-bottom arc included, with no
## bare arc anywhere along the ring; every tip vertical; and no flame bridging the hole.
func _shapes() -> Array[Case]:
	var out : Array[Case] = []
	out.append(_sprite_case("ring", HoopVisual.SHEET, HoopVisual.FRAMES, FxAttachment.Half.WHOLE,
			[FxFire.request(&"fire", 4, PropVisual.PROP_FIRE_STYLE)]))
	out.append(_sprite_case("blade", KnifeVisual.SHEET, 1, FxAttachment.Half.WHOLE,
			[FxFire.request(&"fire", 4, PropVisual.PROP_FIRE_STYLE)]))
	out.append(_sprite_case("ring BACK half", HoopVisual.SHEET, HoopVisual.FRAMES,
			FxAttachment.Half.BACK, [FxFire.request(&"fire", 4, PropVisual.PROP_FIRE_STYLE)]))
	out.append(_sprite_case("ring FRONT half", HoopVisual.SHEET, HoopVisual.FRAMES,
			FxAttachment.Half.FRONT, [FxFire.request(&"fire", 4, PropVisual.PROP_FIRE_STYLE)]))
	return out

## The pattern must read as a CLOSED LOOP: a tall arc peaking above the card's top edge and a
## shallow return across the card's centre, roughly half the balls travelling each way.
func _balls() -> Array[Case]:
	var out : Array[Case] = []
	for n : int in [1, 3, 8, 50]:
		out.append(_card_case("%d balls" % n, FxJuggle.requests(n, PackedInt32Array(),
				StatusJuggling.JUGGLE_STYLE, StatusJuggling.BALL_FIRE_STYLE)))
	# The same count with the host's coin landing the other way: every ball mirrors, so this is the
	# other half of what a board actually shows.
	var flipped := _card_case("8 balls, host flipped", FxJuggle.requests(8, PackedInt32Array(),
			StatusJuggling.JUGGLE_STYLE, StatusJuggling.BALL_FIRE_STYLE))
	flipped.ball_dir = -1.0
	out.append(flipped)
	return out

## One ball, stepped around the whole cycle. Laying the loop out phase by phase is the only way to
## see what path the shader ACTUALLY draws: a single frame shows where the balls are, never
## whether the tall arc and the shallow return are the ones the spec asks for.
func _ball_path() -> Array[Case]:
	var out : Array[Case] = []
	for step : int in 8:
		var ph := float(step) / 8.0
		var case := _card_case("phase %.3f" % ph, FxJuggle.requests(1, PackedInt32Array(),
				StatusJuggling.JUGGLE_STYLE, StatusJuggling.BALL_FIRE_STYLE))
		case.phase = ph
		out.append(case)
	return out

## Is a ball a SPHERE? Only a BIG one can answer: at the shipped radius a ball is 6 art units across
## and any shading reads as "a warm blob". So the pattern is collapsed to almost nothing (the quad is
## sized by the arc height, which is what holds the zoom down) and the radius swept from huge to the
## 1-pixel floor. What to look for: bands that CURVE around the light with a bent terminator, a
## highlight sitting on the surface rather than centred, and a ball that is still legible at r = 1.
func _ball_sphere() -> Array[Case]:
	var out : Array[Case] = []
	for radius : float in [14.0, 7.0, 3.0, 1.0]:
		var style := StatusJuggling.JUGGLE_STYLE.duplicate() as FxJuggleStyle
		style.ball_radius = radius
		style.ball_radius_min = radius
		# Park the ball at the top of the throw and flatten the loop, so the quad is small and the
		# zoom can be large. Geometry only — none of it touches the shading under test.
		style.ball_span = 1.0
		style.ball_arc_height = 1.0
		style.ball_return_height = 1.0
		var case := _card_case("r = %.0f" % radius, FxJuggle.requests(1, PackedInt32Array(),
				style, StatusJuggling.BALL_FIRE_STYLE))
		case.phase = 0.3
		out.append(case)
	return out

## GRAVITY on the throw. Eight balls are spaced evenly in TIME around the loop, so where they end up
## in SPACE is a direct read of the easing: at 1.0 they are evenly spread along the arc, and as it
## rises they bunch toward the apex (slow there) and thin out at the ends (fast there). The oracle
## crosses come from the same spec, so the balls must stay on them at every value.
func _ball_gravity() -> Array[Case]:
	var out : Array[Case] = []
	for g : float in [1.0, 1.6, 2.4]:
		var style := StatusJuggling.JUGGLE_STYLE.duplicate() as FxJuggleStyle
		style.ball_gravity = g
		var case := _card_case("gravity %.1f" % g, FxJuggle.requests(8, PackedInt32Array(),
				style, StatusJuggling.BALL_FIRE_STYLE))
		case.style_gravity = g
		out.append(case)
	return out

## THE ARC LADDER. The ball count is held FIXED and the arc count forced, so the only variable is the
## ladder itself: at 2 it is the original throw-and-carry, and each step adds lanes at evenly spaced
## heights between them. Balls are spread around the whole loop, so a taller ladder spreads them over
## more of the space instead of stacking them on one arc. The oracle crosses come from the same spec,
## so they must stay on the balls at every rung.
func _ball_arcs() -> Array[Case]:
	var out : Array[Case] = []
	for arcs : int in [2, 4, 6, 8]:
		var reqs := FxJuggle.requests(12, PackedInt32Array(), StatusJuggling.JUGGLE_STYLE,
				StatusJuggling.BALL_FIRE_STYLE)
		# Forced rather than reached by ball count: the count also changes radius, span and speed,
		# and this shot is about the ladder alone.
		for req : FxRequest in reqs: req.live[&"u_ball_arcs"] = float(arcs)
		out.append(_card_case("%d arcs" % arcs, reqs))
	return out

## THE JUGGLING HALF OF `02_fire_rotation`, and the gap that let §4 go unverified: there was no
## rotated juggling shot anywhere. Fire and juggling answer a turning host DIFFERENTLY, and both
## answers are on purpose:
##  * fire follows its host's silhouette (the mask is the art) while keeping its flames upright;
##  * the juggling pattern does not turn at all — *"juggle effect doesn't rotate with card"* (owner
##    2026-07-30). `juggle.gdshader` never reads `u_shape_rot` and `FxAttachment._push_live`
##    counter-rotates the quad, so the loop holds still in world space, centred on the card.
##
## The oracle crosses are drawn WORLD-UPRIGHT here (`_Ghost.ball_rot`), which is what makes the shot
## self-verifying: the balls must sit on their crosses at every angle, on a card outline that is
## visibly tilted underneath them. A ball following its card would leave every cross behind.
func _ball_rotation() -> Array[Case]:
	var out : Array[Case] = []
	for deg : int in [0, 30, 45, 90]:
		var case := _card_case("%d deg" % deg, FxJuggle.requests(5, PackedInt32Array([3, 0, 0, 3, 0]),
				StatusJuggling.JUGGLE_STYLE, StatusJuggling.BALL_FIRE_STYLE))
		case.rotation = deg_to_rad(float(deg))
		out.append(case)
	return out

## Ruling 10 — a highlighted card highlights its effects too. Both shaders overwrite COLOR, so the
## modulate the renderer folds into it has to be captured and multiplied back or the highlight stops
## at the card's own art. The right-hand panels are the same effects under CardVisual's own focus
## modulate; they must be visibly brighter, not identical.
func _focus_highlight() -> Array[Case]:
	var out : Array[Case] = []
	var highlight := Color(1.825, 1.825, 1.825)
	for lit : bool in [false, true]:
		var fire := _card_case("fire, %s" % ("FOCUSED" if lit else "plain"),
				[FxFire.request(&"fire", 6, StatusBurning.CARD_FIRE_STYLE)] as Array[FxRequest])
		fire.modulate = highlight if lit else Color.WHITE
		out.append(fire)
		var balls := _card_case("balls, %s" % ("FOCUSED" if lit else "plain"),
				FxJuggle.requests(5, PackedInt32Array(), StatusJuggling.JUGGLE_STYLE,
						StatusJuggling.BALL_FIRE_STYLE))
		balls.modulate = highlight if lit else Color.WHITE
		out.append(balls)
	return out

## Fire is PER BALL, at the ball's OWN level. Exactly two plumes here, welded to balls 0 and 3,
## and the all-dark case beside them is the negative that matters.
func _ball_fire() -> Array[Case]:
	var out : Array[Case] = []
	out.append(_card_case("none lit", FxJuggle.requests(5, PackedInt32Array([0, 0, 0, 0, 0]),
			StatusJuggling.JUGGLE_STYLE, StatusJuggling.BALL_FIRE_STYLE)))
	out.append(_card_case("balls 0+3 lit", FxJuggle.requests(5,
			PackedInt32Array([2, 0, 0, 30, 0]),
			StatusJuggling.JUGGLE_STYLE, StatusJuggling.BALL_FIRE_STYLE)))
	out.append(_card_case("card fire + lit balls", _stacked_case()))
	return out

## THE REGRESSION GUARD FOR "a lit ball's plume disappears and comes back" (owner report,
## FX_HANDOFF §2). The bug was PHASE-DEPENDENT — an unlit ball drifting into the column above a lit
## one won the one-ball-per-fragment lookup and forced the fragment dark — so a single frame could
## never have caught it, which is exactly how it got past `06_ball_fire`.
##
## The owner's own repro: six balls, two of them alight, watched across the cycle. What to look for,
## by EYE: **exactly two plumes in every panel**, on the same two balls (0 and 3), with the other four
## balls bare. A panel showing one plume, or none, is the bug back.
func _ball_fire_cycle() -> Array[Case]:
	var out : Array[Case] = []
	var levels := PackedInt32Array([6, 0, 0, 6, 0, 0])
	for step : int in 6:
		var ph := float(step) / 6.0
		var case := _card_case("phase %.2f" % ph, FxJuggle.requests(6, levels,
				StatusJuggling.JUGGLE_STYLE, StatusJuggling.BALL_FIRE_STYLE))
		case.phase = ph
		out.append(case)
	return out

## The stacking case from the design: card fire under the balls, ball fire over them.
func _stacked_case() -> Array[FxRequest]:
	var reqs : Array[FxRequest] = []
	reqs.append(FxFire.request(&"fire", 30, StatusBurning.CARD_FIRE_STYLE))
	reqs.append_array(FxJuggle.requests(5, PackedInt32Array([1, 0, 0, 1, 0]),
			StatusJuggling.JUGGLE_STYLE, StatusJuggling.BALL_FIRE_STYLE))
	return reqs

## Mid-ease frames — owner ruling 16, "a stack change eases, it never jumps".
##
## ⚠ WHAT IS IN FLIGHT CHANGED WITH THE MODEL (2026-07-29). It used to be ONE number: a fractional
## `u_count` grew the newest tendril out of the surface while the established ones shuffled. There
## are no tendrils and the shader does not read `u_count` at all; what eases now is the whole
## "Stack scaling" group at once — reach, aperture, gain, intensity, grain and scroll — so this shot
## pins every one of them between two whole counts, exactly as `FxAttachment._eased` holds them
## mid-tween.
##
## The RING panels are still the ones to read hardest: a curved host puts each column's surface at a
## different height, so a knob that moved discontinuously shows up there first as a flame jumping
## rather than sliding. A flat card can hide it — its top edge is the same height everywhere.
func _transition() -> Array[Case]:
	var out : Array[Case] = []
	for n : float in [1.6, 2.5, 3.4] as Array[float]:
		out.append(_card_case("card %.1f" % n,
				[_counted(StatusBurning.CARD_FIRE_STYLE, n)]))
	for n : float in [1.6, 2.5, 3.4] as Array[float]:
		out.append(_sprite_case("ring %.1f" % n, HoopVisual.SHEET, HoopVisual.FRAMES,
				FxAttachment.Half.WHOLE, [_counted(PropVisual.PROP_FIRE_STYLE, n)]))
	return out

## A fire request pinned BETWEEN two whole stack counts — the state an easing stack change is in,
## and the only state a jump can hide in.
##
## Every live uniform is lerped, not just one, because every one of them now carries a stack ratio.
## That is the same interpolation `FxAttachment._eased` runs; doing it here is what makes the panel
## a picture of a real mid-tween frame rather than of a state the game never reaches.
func _counted(style: FxFireStyle, count: float) -> FxRequest:
	var lo : Dictionary[StringName, float] = FxFire.stacks_live(int(floorf(count)), style)
	var hi : Dictionary[StringName, float] = FxFire.stacks_live(int(ceilf(count)), style)
	var t := count - floorf(count)
	var live : Dictionary[StringName, float] = {}
	for key : StringName in lo:
		# Typed locals, not a `hi.get(...)` inline: a Dictionary lookup is a Variant, and `lerpf`
		# refuses one under this project's warnings-as-errors — which fails at PARSE time, so the scene
		# loads without its script and the run hangs with an empty log (FX_HANDOFF §11's first trap).
		var a : float = lo[key]
		var b : float = hi[key] if hi.has(key) else a
		live[key] = lerpf(a, b, t)
	var req := FxRequest.make(&"fire", FxFire.FIRE_SHADER, style, live[&"u_height"])
	req.live = live
	return req

## EMBERS, from every fire that throws them (owner 2026-07-29: *"all fire effects should leave embers
## like card is currently. dont see embers on props or balls"*). A burning card, a burning hoop, a
## burning knife and a pair of lit balls, side by side.
##
## ⚠ THE ONE SHOT THAT RUNS LIVE, and the second one that is NOT REPRODUCIBLE. Embers are particles:
## they are spawned at random points at random times and then simulated forward, so there is nothing
## to park a clock at — a single frame of a fresh attachment has emitted nothing at all. Every other
## shot drives its clock by hand for exactly the reason this one cannot.
##
## What to look for, by EYE: embers over ALL FOUR hosts, each sized to its own host (the card's are
## the big ones — `ember.tres`; the prop and ball ones are `ember_prop.tres`), and the ball embers
## leaving the BALLS rather than pouring off the card's top edge, which is where a host-relative
## spawn would have put them.
const EMBER_SECS := 1.4

func _shot_embers() -> void:
	var holder := Node2D.new()
	add_child(holder)
	var size := canvas()
	# label, body, shape, requests — the four ember sources the owner named, in one row.
	var cases : Array[Case] = [
		_card_case("card fire", [FxFire.request(&"fire", 8, StatusBurning.CARD_FIRE_STYLE)]),
		_sprite_case("burning hoop", HoopVisual.SHEET, HoopVisual.FRAMES, FxAttachment.Half.WHOLE,
				[FxFire.request(&"fire", 8, PropVisual.PROP_FIRE_STYLE)]),
		_sprite_case("burning knife", KnifeVisual.SHEET, 1, FxAttachment.Half.WHOLE,
				[FxFire.request(&"fire", 8, PropVisual.PROP_FIRE_STYLE)]),
		_card_case("balls 0+3 lit", FxJuggle.requests(5, PackedInt32Array([4, 0, 0, 12, 0]),
				StatusJuggling.JUGGLE_STYLE, StatusJuggling.BALL_FIRE_STYLE)),
	]
	var step := size.x / float(cases.size())
	var zoom := _zoom_for(cases, step)
	# ONE engine for the whole row, scaled with the cases: a spec's sizes are in the ENGINE's units,
	# so an unscaled engine would draw every ember at a sub-pixel speck against blown-up hosts.
	# Positions still land correctly wherever it sits — emit() converts through to_local.
	var engine := ParticleEngine.new()
	engine.scale = Vector2.ONE * zoom
	holder.add_child(engine)
	var atts : Array[FxAttachment] = []
	for i : int in cases.size():
		var case : Case = cases[i]
		var slot := Node2D.new()
		slot.position = Vector2(step * (i + 0.5), size.y * 0.6)
		slot.scale = Vector2.ONE * zoom
		holder.add_child(slot)
		var ghost := _ghost_for(case, zoom)
		slot.add_child(ghost)
		# ambient TRUE — the one place it is, and the whole point: `_emit_embers` early-outs on it,
		# because the motion effects are for a board, not for a viewer full of static cards.
		atts.append(_attach_for(case, slot, true))
		label(holder, case.label, Vector2(step * (i + 0.5), size.y * 0.9))
	# Let it actually burn. Real frame deltas, because that is what drives both the emitters and the
	# engine's own simulation pass.
	var elapsed := 0.0
	while elapsed < EMBER_SECS:
		elapsed += await _tick()
	await capture("09_embers", "EMBERS from every fire — card / hoop / knife / lit balls, run live "
			+ "for %.1f s (NOT reproducible: see the comment)" % EMBER_SECS)
	for att : FxAttachment in atts: att.set_process(false)
	holder.queue_free()
	await get_tree().process_frame

## One frame of real time, and how long it took.
func _tick() -> float:
	await get_tree().process_frame
	return get_process_delta_time()

# ----------------------------------------------------------------- the harness

## One case: a host body drawn for reference with an FxAttachment on top of it. A class, not a
## Dictionary, so every field is typed — warnings are errors in this project.
class Case:
	var label : String = ""
	var body : Vector2 = Vector2.ZERO
	var shape : FxAttachment.Shape = FxAttachment.Shape.BOX
	var half : FxAttachment.Half = FxAttachment.Half.WHOLE
	var requests : Array[FxRequest] = []
	var rotation : float = 0.0
	## The host's DEFORMED outline, walked once around the shape, or empty for an undeformed host.
	## Set means the attachment takes the radius-table mask and the ghost draws the star rather than
	## the box — so the panel shows whether the flames stand on the shape the card actually has.
	var outline : PackedVector2Array = PackedVector2Array()
	## SPRITE cases: the sheet the mask is read out of, and how many frames it holds. Set means the
	## harness both hands the attachment its real art AND draws that art as the reference — an
	## outline cannot show a HOLE, and the hole is the whole point of §1.
	var sheet : Texture2D = null
	var frames : int = 1
	## Phase override for the path trace, or -1 to use the shot's shared phase.
	var phase : float = -1.0
	## The style's ball_top_fraction and ball_gravity, carried so the oracle reads the same split and
	## the same throw easing the shader was handed.
	var style_top_fraction : float = 0.6
	var style_gravity : float = 1.0
	## The host's base ball direction, PINNED rather than left to its per-host coin flip — a snapshot
	## whose pattern mirrors at random cannot be diffed, and the oracle has to be told the same value.
	var ball_dir : float = 1.0
	## Host modulate, for the focus-highlight case (ruling 10): the effects must brighten with their
	## host, which they cannot do if a shader overwrites the modulate the renderer folded into COLOR.
	var modulate : Color = Color.WHITE

func _case(label: String, body: Vector2, shape: FxAttachment.Shape, half: FxAttachment.Half,
		requests: Array[FxRequest]) -> Case:
	var c := Case.new()
	# Read off the live style, never retyped: the oracle has to be told the same path parameters the
	# shader was handed, and a stale copy here would read as a shader bug.
	c.style_top_fraction = StatusJuggling.JUGGLE_STYLE.ball_top_fraction
	c.style_gravity = StatusJuggling.JUGGLE_STYLE.ball_gravity
	c.label = label
	c.body = body
	c.shape = shape
	c.half = half
	c.requests = requests
	return c

func _card_case(label: String, requests: Array[FxRequest]) -> Case:
	return _case(label, CardVisual.CARD_SIZE, FxAttachment.Shape.BOX, FxAttachment.Half.WHOLE,
			requests)

## A case whose mask is a real sheet's ALPHA — every prop kind. The body is derived from the same
## art the kind derives its own from rather than retyped, so a panel here cannot disagree with what
## the game draws.
func _sprite_case(label: String, sheet: Texture2D, frames: int, half: FxAttachment.Half,
		requests: Array[FxRequest]) -> Case:
	var c := _case(label, PropVisual.art_size_for(sheet, frames), FxAttachment.Shape.SPRITE, half,
			requests)
	c.sheet = sheet
	c.frames = frames
	return c

## The host's reference drawing for one case — its real art for a sprite kind, a plain outline
## otherwise, so the effect can be judged against the shape it is supposed to be decorating.
func _ghost_for(case: Case, zoom: float) -> _Ghost:
	var ghost := _Ghost.new()
	ghost.body = case.body
	ghost.outline = case.outline
	ghost.sheet = case.sheet
	ghost.frames = case.frames
	if case.sheet: ghost.art_size = PropVisual.art_size_for(case.sheet, case.frames)
	ghost.px = 1.0 / maxf(zoom, 0.01)
	return ghost

## Build one case's attachment, including handing a sprite kind its REAL sheet — the mask is that
## art's alpha now, so a panel that skipped this would be decorating a plain box.
func _attach_for(case: Case, host: Node2D, ambient: bool) -> FxAttachment:
	var att := FxAttachment.new()
	att.configure(case.body, true, case.shape, case.half, ambient)
	host.add_child(att)
	if case.sheet:
		att.measure_sprite_silhouette(case.sheet,
				CardModifier.frame_rect(case.sheet, case.frames, 1, 0),
				PropVisual.art_size_for(case.sheet, case.frames))
	elif not case.outline.is_empty():
		att.measure_outline(case.outline)
	# BEFORE sync: the quads read the host's randomness as they are built, unlike the clock, which is
	# pushed afterwards.
	#
	# ⚠ THE SEED BELONGS HERE TOO, and only `_ball_dir` was pinned — so every fire panel in this scene
	# rendered on whatever `randf()` the attachment's constructor happened to draw. That is exactly the
	# input `snapshot_diff.py` cannot tolerate: its claim is "these two RUNS are byte-identical", and an
	# unpinned per-host random reduces it to "the RNG happened to land in the same place".
	att._seed = SHOT_SEED
	att._ball_dir = case.ball_dir
	att.sync(case.requests)
	return att

## Lay the cases out across the viewport, drive every clock to the SAME fixed time, wait for the
## frame to actually reach the screen, then capture it.
func _shot(file_name: String, caption: String, cases: Array[Case]) -> void:
	var holder := Node2D.new()
	add_child(holder)
	var size := canvas()
	var step := size.x / float(cases.size())
	var zoom := _zoom_for(cases, step)
	var probes : Array[_Probe] = []
	## Kept so the counter-rotation can be re-read AFTER the capture: a value that is right when it is
	## written and wrong in the captured frame is a different bug from one that was never right.
	var atts : Array[FxAttachment] = []
	for i : int in cases.size():
		var case : Case = cases[i]
		var slot := Node2D.new()
		slot.position = Vector2(step * (i + 0.5), size.y * 0.55)
		slot.scale = Vector2.ONE * zoom
		slot.rotation = case.rotation
		holder.add_child(slot)
		# The host's own silhouette, so "flush with the top edge" and "behind the card" are
		# judgeable rather than guesses about empty space.
		var ghost := _ghost_for(case, zoom)
		slot.add_child(ghost)
		ghost.balls = _oracle(case)
		# The crosses are pinned to WORLD up, not to the tilted host: the pattern does not turn with
		# its card, so an oracle drawn in the slot's rotated frame would sit where the balls are
		# NOT — and the probe below reads the same unrotated positions.
		ghost.ball_rot = -case.rotation
		if not ghost.balls.is_empty():
			var probe := _Probe.new()
			probe.label = case.label
			probe.origin = slot.position
			probe.zoom = zoom
			probe.expected = ghost.balls
			probe.tint = case.modulate
			probes.append(probe)
		# The modulate goes on a PARENT of the attachment, so it reaches the effects the way a card's
		# does — down the tree, not through a uniform. Added AFTER the ghost: the reference geometry
		# has to stay UNDER the effects, or the oracle crosses paint over the very balls they are
		# there to be compared against (which is exactly what happened the first time this node was
		# inserted, and it read as the balls having vanished).
		var host := Node2D.new()
		host.modulate = case.modulate
		slot.add_child(host)
		var att := _attach_for(case, host, false)
		# Park the clock by hand: driving it from real frame deltas would make every run differ,
		# and a snapshot that changes on its own cannot be diffed.
		#
		# ⚠ ORDER MATTERS, and getting it wrong is what a whole debugging pass mistook for a shader
		# bug: `_push_live` ENDS with `set_process(not _fx.is_empty())`, so disabling the process
		# BEFORE pushing silently re-enables it, the two frames awaited below then advance `_phase`
		# and `_time` by real deltas, and every ball ends up ~0.15 of a cycle past the phase the
		# oracle (and the print below) were told about. Disable the process LAST.
		att._time = SHOT_TIME
		att._phase = case.phase if case.phase >= 0.0 else 0.13
		att._push_live(0.0)
		att.set_process(false)
		label(holder, case.label, Vector2(step * (i + 0.5), size.y * 0.9))
		# THE COUNTER-ROTATION, PRINTED — because the rotated panels of this shot have a standing
		# "not reproducible" warning and it was never run to ground. Two consecutive runs of ONE
		# unchanged build (2026-07-29) put the 05f_ball_rotation probes at 1.0 / 2.0 / 5.8 art units for
		# 30 / 45 / 90 degrees in the first and 0.1 in the second — the SAME grows-with-the-angle
		# displacement along +x that got FX_HANDOFF §1b's quad-extent lever reverted. So the pattern
		# rotated with its host in one run and not the other, and these two numbers are the only place
		# that can happen: `_push_live` sets `rotation = -parent.global_rotation`.
		print("  [", file_name, "/", case.label, "] ROT host=", host.global_rotation,
				" att=", att.rotation, " slot=", slot.rotation)
		atts.append(att)
		for id : StringName in att._fx:
			var m : ShaderMaterial = att._fx[id].mat
			print("  [", file_name, "/", case.label, "] zoom=", zoom, " ", id,
					" u_phase=", m.get_shader_parameter("u_phase"),
					" u_count=", m.get_shader_parameter("u_count"),
					" u_arc_height=", m.get_shader_parameter("u_arc_height"),
					" u_ball_radius=", m.get_shader_parameter("u_ball_radius"),
					" u_span=", m.get_shader_parameter("u_span"),
					" u_top_fraction=", m.get_shader_parameter("u_top_fraction"),
					" u_return_height=", m.get_shader_parameter("u_return_height"),
					" u_extent=", m.get_shader_parameter("u_extent"))
	var img : Image = await capture(file_name, caption)
	for att : FxAttachment in atts:
		print("  [", file_name, "] POST-CAPTURE att.rotation=", att.rotation, " global=",
				att.global_rotation, " processing=", att.is_processing())
	for probe : _Probe in probes: _report(img, probe)
	holder.queue_free()
	await get_tree().process_frame

## The blow-up that keeps every case INSIDE its own slot.
##
## Not a constant: a ball quad is ~152 art units across (the pattern's arc height dominates the
## extent) against a card's ~90, so a fixed zoom made neighbouring slots overlap and one case's
## balls drew on top of the next one's. That is a measurement trap as much as an ugly image — it
## sent a whole debugging pass chasing a phase offset that was really the panel next door.
func _zoom_for(cases: Array[Case], step: float) -> float:
	var widest := 1.0
	for case : Case in cases:
		for req : FxRequest in case.requests:
			widest = maxf(widest, case.body.length() + (req.reach + FxAttachment.FX_MARGIN) * 2.0)
	return minf(ZOOM_MAX, step * 0.98 / widest)

# ------------------------------------------------------ measuring the capture, not eyeballing it
# The oracle CROSSES are drawn at 0.5 art units of width, which at the zooms a ball quad forces
# (~1.0) rounds to half a pixel — Godot drops those lines, so half of every cross is missing from
# the PNG and "does the ball sit on its cross" cannot be judged by eye at all. Two sessions of
# ball-position debugging were spent measuring the images by hand instead. So the harness now
# measures ITSELF: it converts each expected position into image pixels, finds the rendered ball
# nearest to it, and prints the disagreement in ART UNITS. That is the number to read.

## One case's expectation, kept until the frame has been captured.
class _Probe:
	var label : String = ""
	## Slot origin in CANVAS units, and the slot's art-unit-to-canvas blow-up.
	var origin : Vector2 = Vector2.ZERO
	var zoom : float = 1.0
	var expected : PackedVector2Array = PackedVector2Array()
	## The host's modulate for this case — a ball's rendered colour is its palette entry times this
	## (ruling 10), so the colour predicate has to be built with it or a FOCUSED panel reads as empty.
	var tint : Color = Color.WHITE

## How far out, in ART UNITS, the probe is willing to look for a ball before calling it missing.
const PROBE_REACH := 24.0

## Print, per expected ball, how far the nearest RENDERED ball pixel actually is — in art units, the
## units the spec is written in. Sub-unit offsets are agreement (the search finds the nearest EDGE
## pixel of a ball, not its centre, so it reads a whole radius pessimistically).
func _report(img: Image, probe: _Probe) -> void:
	var to_img := to_image_scale(img)
	var art_to_img := probe.zoom * to_img
	var reach := int(ceilf(PROBE_REACH * art_to_img))
	# ⚠ THE BALL'S OWN COLOURS, NEVER A HUE GUESS. This read `PixelProbe.is_warm`, which encoded "a
	# ball is orange" and went blind the moment `ramp_ball` was retuned to greens (see that function).
	# Here it also collided with the ORACLE CROSSES, which are green — and a probe that cannot tell a
	# ball from the cross marking where the ball should be is worse than none. This one only PRINTS,
	# so it would have gone on reporting "NO BALL within 24 art units" indefinitely.
	var is_ball := PixelProbe.ball_pixel(StatusJuggling.JUGGLE_STYLE, probe.tint)
	for i : int in probe.expected.size():
		var want : Vector2 = (probe.origin + probe.expected[i] * probe.zoom) * to_img
		var hit := PixelProbe.nearest(img, want, reach, is_ball)
		var off : Vector2 = (hit[&"offset"] as Vector2) / art_to_img
		var found := "nearest rendered ball offset by art (%.1f, %.1f)" % [off.x, off.y] \
				if hit[&"found"] else "NO BALL within %.0f art units" % PROBE_REACH
		print("  PROBE [", probe.label, "] ball ", i, " expected art ", probe.expected[i],
				" -> ", found)

## The expected ball positions for every juggling request in this case, from the SHARED spec oracle
## (PixelProbe.ball_positions — one transcription, also used by the asserting PIXELS suite, and
## deliberately NOT derived from the shader).
func _oracle(case: Case) -> PackedVector2Array:
	var out := PackedVector2Array()
	for req : FxRequest in case.requests:
		if req.phase_period <= 0.0 or req.shader != FxJuggle.JUGGLE_SHADER: continue
		out.append_array(PixelProbe.ball_positions(req.live[&"u_count"],
				case.phase if case.phase >= 0.0 else 0.13, req.live[&"u_span"],
				req.live[&"u_arc_height"], req.live[&"u_return_height"], case.style_top_fraction,
				case.style_gravity, case.ball_dir, req.live[&"u_ball_arcs"]))
	return out

## The host's silhouette, drawn as a plain outline so the effect can be judged against the shape
## it is supposed to be decorating.
class _Ghost extends Node2D:
	var body : Vector2 = Vector2.ZERO
	## A SPRITE case draws its real art instead of an outline: the mask is that art's alpha now, and
	## an outline cannot show the HOLE whose inner-bottom arc §1 exists to light.
	var sheet : Texture2D = null
	var frames : int = 1
	var art_size : Vector2 = Vector2.ZERO
	## A DEFORMED host draws its real outline, or the panel would show flames standing off a box the
	## card is not — which is the exact class of tool lie this harness exists to avoid.
	var outline : PackedVector2Array = PackedVector2Array()
	## Independent expected ball positions, drawn as crosses.
	var balls : PackedVector2Array = PackedVector2Array()
	## Rotation applied to the CROSSES only, cancelling the slot's — the juggling pattern holds
	## still in world space while its host turns, so its oracle has to as well.
	var ball_rot : float = 0.0
	## ART UNITS PER SCREEN PIXEL for this slot (1 / the shot's zoom). Every line width below is a
	## multiple of it, so the outline and the crosses are always ~2 px thick on screen. Fixed 0.5-unit
	## widths were sub-pixel at the zoom a ball quad forces (~1.0) and Godot DROPPED them: half of
	## every cross and both horizontal edges of the outline were simply missing from the PNG, which
	## is what made "does the ball sit on its cross" unjudgeable and sent the last pass measuring
	## pixels by hand.
	var px : float = 1.0
	func _draw() -> void:
		var col := Color(0.45, 0.5, 0.6)
		if sheet:
			draw_texture_rect_region(sheet, Rect2(-art_size * 0.5, art_size),
					CardModifier.frame_rect(sheet, frames, 1, 0))
		elif not outline.is_empty():
			var loop := outline.duplicate()
			loop.append(loop[0])
			draw_polyline(loop, col, 2.0 * px)
		else:
			draw_rect(Rect2(-body * 0.5, body), col, false, 2.0 * px)
		# A centre line: the juggling loop's shallow return arc is specified to ride the card's
		# CENTRE, and that is impossible to eyeball without it.
		draw_line(Vector2(-body.x * 0.5, 0.0), Vector2(body.x * 0.5, 0.0),
				Color(0.35, 0.4, 0.5, 0.7), 1.5 * px)
		# The oracle: where the balls are SUPPOSED to be. A cross that does not sit on a ball is a
		# disagreement between the shader and the spec, readable at a glance and with no pixel
		# measuring — which is what this harness could not do before and cost a long debugging
		# detour.
		# Pinned to WORLD up, cancelling the slot's rotation: the pattern does not turn with its
		# host, so on a tilted card the crosses belong upright — which is what makes the rotation
		# shot self-verifying rather than merely pretty.
		draw_set_transform(Vector2.ZERO, ball_rot, Vector2.ONE)
		for b : Vector2 in balls:
			var c := Color(0.4, 1.0, 0.6)
			var arm := maxf(2.5, 4.0 * px)
			draw_line(b - Vector2(arm, 0.0), b + Vector2(arm, 0.0), c, 1.5 * px)
			draw_line(b - Vector2(0.0, arm), b + Vector2(0.0, arm), c, 1.5 * px)

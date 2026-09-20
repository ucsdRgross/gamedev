extends SnapshotScene
# res://Tests/Visual/fx_snapshot.gd

# FX SNAPSHOTS — the visual half of the FX test plan. --headless uses the dummy renderer, which
# never compiles a shader program, so a GLSL error, an inverted sign or an effect that draws nothing
# at all pass the suite silently. Run this WINDOWED after ANY shader edit; a human reviews the PNGs.

#     Godot --path solatro res://Tests/Visual/fx_snapshot.tscn
# Output: user://fx_snapshots/*.png — on Windows,
#     %APPDATA%\Godot\app_userdata\Solatro\fx_snapshots\

# Deliberately NOT in all_tests.tscn: it needs a window and a GPU.

# Determinism: the RNG is seeded and each attachment's clock is DRIVEN BY HAND to a fixed time
# rather than left to accumulate from real frame deltas, so two runs of an unchanged shader produce
# identical images and a diff means a real change.

# ⚠ A PANEL WITH A ROTATED HOST IS FOR EYE REVIEW ONLY — are the flames upright, are the pixels
# square. Two runs of one unchanged build differed by 12392 px (`02_fire_rotation`), 1035 px
# (`05f_ball_rotation`) and 15506 px (`behind_prop_turned`); every UPRIGHT panel was identical.

# `snapshot_diff.py` lists those panels in NOISY: a pixel diff of one means nothing.

const OUT_DIR := "user://fx_snapshots"

## Where each shot's clock is parked. Not zero: at t = 0 every noise term is at its starting value.
const SHOT_TIME := 3.7

# `FxAttachment._seed` is otherwise `randf() * 100.0` drawn in the constructor and it drives the
# fire's noise offset, so leaving it free makes a panel's raggedness an artefact of where the global
# RNG landed. Any value works; this one is simply the same every run.

## The per-host random every shot pins.
const SHOT_SEED := 12.5

# ⚠ `LIGHT_MAX` must equal `MAX_LIGHTS` in `light.gdshader`: Godot matches an array uniform by
# DECLARED SIZE, and a shorter array is rejected whole rather than partially filled — the same trap
# `FxGlowStyle` pads around.

## The light layer's shader and the size of its uniform arrays.
const LIGHT_SHADER := preload("res://Shaders/light.gdshader")
const LIGHT_MAX := 64

# Several suits, because a real board is mixed and the dim has to be judged over more than one art
# square. A function rather than an array of classes: a class name is not a constant expression in
# GDScript, so `const [PipSuitKnife, …]` will not parse.
func _shot_suit(i: int) -> PipSuit:
	match i % 4:
		0: return PipSuitKnife.new()
		1: return PipSuitBall.new()
		2: return PipSuitHoop.new()
		_: return PipSuitFire.new()

# Cards are 38x50 art units; at 1:1 a whole flame is a few pixels and nothing is reviewable. Each
# shot may use LESS than this — see `_zoom_for`.

## Largest art-unit-to-pixel blow-up.
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
	await _shot("09_glow_falloff", "THE SPOTLIGHT GLOW's field: inverse_square 0 (smooth) / 0.6 "
			+ "(shipped) / 1.0 (pure), then ONE layer against TWO — a lamp, not a smudge",
			_glow_falloff())
	await _shot("09b_glow_over_art", "THE READABILITY CALL (Q216, gate G2.2): inner_alpha 0 / 0.35 "
			+ "(shipped) / 0.6 / 0.9 over a real card face — the rank glyph must stay legible",
			_glow_over_art())
	await _shot_embers()
	await _shot_light_layer()

# ------------------------------------------------------------------ the shots

# Cover is read off the FIRST tap that lands inside the mask, so it steps once per tap: at `n` taps
# the flame is `n` horizontal bands, the lowest flush with the card's top edge and the highest at
# exactly `height` above it.

# ⚠ THIS SHOT IS THE COST KNOB, NOT A LOOK KNOB: the shader costs `mask_level` call count times cost
# per call and nothing else, so the panels are 2x to 4x apart in price. 4 is what ships. Look at
# whether the banding at 4 is still visible once `noise_amp` is back up; if not, 6 and 8 are waste.

# `cover_dither` is zeroed here and ONLY here: the phase dither every shipped style carries is what
# hides the raw ladder this shot exists to show.

## THE COVER FIELD, NAKED — `noise_amp = 0` and no dither, so on screen is the tap ladder alone.
func _cover_field() -> Array[Case]:
	var out : Array[Case] = []
	for taps : int in [2, 3, 4, 6, 8]:
		var style := StatusBurning.CARD_FIRE_STYLE.duplicate() as FxFireStyle
		style.cover_taps = taps
		style.noise_amp = 0.0
		style.dither = 0.0
		style.cover_dither = 0.0
		style.height = 20.0
		var live : Dictionary[StringName, float] = FxFire.stacks_live(6, style)
		var req := FxRequest.make(&"fire", FxFire.FIRE_SHADER, style, live[&"u_height"])
		req.live = live
		out.append(_card_case("%d taps" % taps, [req]))
	return out

# The flame is `cover * (((cover + aperture) * noise - aperture) * gain)`. APERTURE is a CUT — the
# cover threshold below which nothing burns, so HIGH eats the flame back toward its base. GAIN is
# contrast on what survives: low is a soft gradient, high slams it to the hot end over a cool rim.

# The panels must not look alike, or the noise is not reaching the shaping term: 0.10/4.0 a solid
# bright block, 0.35/2.2 the shipped ragged flame, 0.90/1.2 a few flecks at the base. Three panels,
# not five — the quad is sized to the flame HEIGHT, so more panels zoom out past legible.

## THE TWO SHAPE KNOBS, at full noise — the only state they mean anything in.
func _aperture_profile() -> Array[Case]:
	var out : Array[Case] = []
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

# Every knob in `FxFireStyle`'s "Stack scaling" group is driven from this one slider, in
# `FxFire.stacks_live`.

# Three ways the ramps can be wrong: the flame must get TALLER, HOTTER and MORE SOLID as the count
# rises; the grain must get COARSER rather than merely denser (`noise_scale_ratio` is negative for
# that); NOTHING JUMPS — at 1 stack every ratio is inert (`log(1) = 0`), so panel one is the base.

## THE STACK RATIOS: every param scales as stacks increase.
func _fire_ladder() -> Array[Case]:
	var out : Array[Case] = []
	for stacks : int in [1, 3, 12, 40, 200]:
		out.append(_card_case("%d" % stacks,
				[FxFire.request(&"fire", stacks, StatusBurning.CARD_FIRE_STYLE)]))
	return out

# Every one of these must show upright flames on a tilted card, with square (never diagonal) pixels.

## Flames are gravity-aligned: the SILHOUETTE turns inside a still quad.
func _fire_rotation() -> Array[Case]:
	var out : Array[Case] = []
	for deg : int in [0, 30, 45, 90]:
		var case := _card_case("%d deg" % deg,
				[FxFire.request(&"fire", 5, StatusBurning.CARD_FIRE_STYLE)])
		case.rotation = deg_to_rad(float(deg))
		out.append(case)
	return out

# A card is skinned to a star rig, so its top edge is never where the authored 38x50 rectangle says
# it is, and a silhouette baked once at rest leaves the flames standing on a shape the card does not
# have. Each panel stretches the four CORNERS as the rig does.

# The outline drawn under the flames is the SAME one the attachment was handed, so the check needs no
# measuring: EVERY FLAME BASE MUST SIT ON THE DRAWN OUTLINE, stretched corners included. The last
# panel is past what the rig can reach — a quad clipping its own flames shows up first at the extreme.

## THE DEFORMING CARD: the fire effect warps with the card.
func _card_warp() -> Array[Case]:
	var out : Array[Case] = []
	for warp : float in [0.0, 0.1, 0.25, 0.45]:
		var case := _card_case("corners +%d%%" % roundi(warp * 100.0),
				[FxFire.request(&"fire", 8, StatusBurning.CARD_FIRE_STYLE)])
		case.outline = CardVisual.star_outline(CardVisual.CARD_SIZE, warp)
		out.append(case)
	return out

# The ring holds its outer top arc high up and the upward-facing inner arc at the bottom of its hole
# far below, in the SAME columns. The cover field asks only "how far above the nearest surface BELOW
# me am I", which the hole answers with the inner arc and everything above the ring with the outer.

# By EYE: every panel lights BOTH surfaces, and the hole's MIDDLE stays empty at every count, 200
# included. A flame bridging the two arcs is impossible by construction — no tap reaches further
# than `height`, and the two arcs are 170 art units apart.

## MULTIPLE SURFACES IN ONE COLUMN, on the one shape that has them.
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

# By EYE, never by counting columns — counting reported two rejected builds as successes. Flames on
# EVERY upward-facing surface, the hoop's inner-bottom arc included, no bare arc anywhere along the
# ring, every tip vertical, and no flame bridging the hole.

## Every panel is the REAL art with the REAL mask read out of its alpha: what a prop actually shows.
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

# The pattern must read as a CLOSED LOOP: a tall arc peaking above the card's top edge and a shallow
# return across the card's centre, roughly half the balls travelling each way. The flipped panel is
# the host's coin landing the other way — every ball mirrors, and a board shows both.

## The juggling pattern at 1 / 3 / 8 / 50 balls.
func _balls() -> Array[Case]:
	var out : Array[Case] = []
	for n : int in [1, 3, 8, 50]:
		out.append(_card_case("%d balls" % n, FxJuggle.requests(n, PackedInt32Array(),
				StatusJuggling.JUGGLE_STYLE, StatusJuggling.BALL_FIRE_STYLE)))
	var flipped := _card_case("8 balls, host flipped", FxJuggle.requests(8, PackedInt32Array(),
			StatusJuggling.JUGGLE_STYLE, StatusJuggling.BALL_FIRE_STYLE))
	flipped.ball_dir = -1.0
	out.append(flipped)
	return out

# Laying the loop out phase by phase is the only way to see what path the shader ACTUALLY draws: a
# single frame shows where the balls are, never whether the tall arc and the shallow return are the
# ones the spec asks for.

## One ball, stepped around the whole cycle.
func _ball_path() -> Array[Case]:
	var out : Array[Case] = []
	for step : int in 8:
		var ph := float(step) / 8.0
		var case := _card_case("phase %.3f" % ph, FxJuggle.requests(1, PackedInt32Array(),
				StatusJuggling.JUGGLE_STYLE, StatusJuggling.BALL_FIRE_STYLE))
		case.phase = ph
		out.append(case)
	return out

# Only a BIG ball can answer: at the shipped radius a ball is 6 art units across and any shading
# reads as a warm blob. The pattern is collapsed to almost nothing — the quad is sized by the arc
# height, which is what holds the zoom down — and the radius swept to the 1-pixel floor.

# Look for bands that CURVE around the light with a bent terminator, a highlight sitting on the
# surface rather than centred, and a ball still legible at r = 1. Flattening the loop is geometry
# only: none of it touches the shading under test.

## Is a ball a SPHERE?
func _ball_sphere() -> Array[Case]:
	var out : Array[Case] = []
	for radius : float in [14.0, 7.0, 3.0, 1.0]:
		var style := StatusJuggling.JUGGLE_STYLE.duplicate() as FxJuggleStyle
		style.ball_radius = radius
		style.ball_radius_min = radius
		style.ball_span = 1.0
		style.ball_arc_height = 1.0
		style.ball_return_height = 1.0
		var case := _card_case("r = %.0f" % radius, FxJuggle.requests(1, PackedInt32Array(),
				style, StatusJuggling.BALL_FIRE_STYLE))
		case.phase = 0.3
		out.append(case)
	return out

# Eight balls are spaced evenly in TIME around the loop, so where they end up in SPACE is a direct
# read of the easing: at 1.0 evenly spread along the arc, and as it rises bunched toward the apex.
# The oracle crosses come from the same spec, so the balls must stay on them at every value.

## GRAVITY on the throw.
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

# At 2 arcs it is the original throw-and-carry, and each step adds lanes at evenly spaced heights
# between them, so a taller ladder spreads the balls over more space instead of stacking them on one
# arc. The oracle crosses come from the same spec and must stay on the balls at every rung.

# The arc count is FORCED rather than reached by ball count: the count also changes radius, span and
# speed, and this shot is about the ladder alone.

## THE ARC LADDER, at one fixed ball count.
func _ball_arcs() -> Array[Case]:
	var out : Array[Case] = []
	for arcs : int in [2, 4, 6, 8]:
		var reqs := FxJuggle.requests(12, PackedInt32Array(), StatusJuggling.JUGGLE_STYLE,
				StatusJuggling.BALL_FIRE_STYLE)
		for req : FxRequest in reqs: req.live[&"u_ball_arcs"] = float(arcs)
		out.append(_card_case("%d arcs" % arcs, reqs))
	return out

# Fire and juggling answer a turning host DIFFERENTLY, both on purpose: fire follows its host's
# silhouette while keeping its flames upright, and the juggling pattern does not turn at all —
# `juggle.gdshader` never reads `u_shape_rot` and `FxAttachment._push_live` counter-rotates the quad.

# The oracle crosses are drawn WORLD-UPRIGHT (`_Ghost.ball_rot`), which makes the shot
# self-verifying: the balls must sit on their crosses at every angle, over a visibly tilted card
# outline. A ball following its card would leave every cross behind.

## THE JUGGLING HALF OF `02_fire_rotation`: the pattern must NOT turn with the card.
func _ball_rotation() -> Array[Case]:
	var out : Array[Case] = []
	for deg : int in [0, 30, 45, 90]:
		var case := _card_case("%d deg" % deg, FxJuggle.requests(5, PackedInt32Array([3, 0, 0, 3, 0]),
				StatusJuggling.JUGGLE_STYLE, StatusJuggling.BALL_FIRE_STYLE))
		case.rotation = deg_to_rad(float(deg))
		out.append(case)
	return out

#Both shaders overwrite COLOR, so the modulate the renderer folds into it has to be captured and
#multiplied back or it stops at the host's own art. The right-hand panels are the same effects under
#a brightening modulate, and they must be visibly brighter, not identical.

## A host's modulate reaches the effects it carries, not just its own art.
func _focus_highlight() -> Array[Case]:
	var out : Array[Case] = []
	var lift : float = PlayArea.settings().highlight_glow
	var highlight := Color(lift, lift, lift)
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

# Exactly two plumes here, welded to balls 0 and 3; the all-dark case beside them is the negative
# that matters.

## Fire is PER BALL, at the ball's OWN level.
func _ball_fire() -> Array[Case]:
	var out : Array[Case] = []
	out.append(_card_case("none lit", FxJuggle.requests(5, PackedInt32Array([0, 0, 0, 0, 0]),
			StatusJuggling.JUGGLE_STYLE, StatusJuggling.BALL_FIRE_STYLE)))
	out.append(_card_case("balls 0+3 lit", FxJuggle.requests(5,
			PackedInt32Array([2, 0, 0, 30, 0]),
			StatusJuggling.JUGGLE_STYLE, StatusJuggling.BALL_FIRE_STYLE)))
	out.append(_card_case("card fire + lit balls", _stacked_case()))
	return out

# The failure is PHASE-DEPENDENT: an unlit ball drifting into the column above a lit one wins the
# one-ball-per-fragment lookup and forces the fragment dark, which no single frame can catch. Six
# balls, two alight, watched across the cycle.

# By EYE: EXACTLY TWO PLUMES IN EVERY PANEL, on the same two balls (0 and 3), the other four bare.
# A panel showing one plume, or none, is the bug.

## THE REGRESSION GUARD FOR a lit ball's plume disappearing and coming back.
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

# What eases is the whole "Stack scaling" group at once — reach, aperture, gain, intensity, grain
# and scroll — so this shot pins every one of them between two whole counts, exactly as
# `FxAttachment._eased` holds them mid-tween.

# Read the RING panels hardest: a curved host puts each column's surface at a different height, so a
# knob that moved discontinuously shows up there first as a flame jumping rather than sliding. A
# flat card hides it — its top edge is the same height everywhere.

## Mid-ease frames: a stack change eases, it never jumps.
func _transition() -> Array[Case]:
	var out : Array[Case] = []
	for n : float in [1.6, 2.5, 3.4] as Array[float]:
		out.append(_card_case("card %.1f" % n,
				[_counted(StatusBurning.CARD_FIRE_STYLE, n)]))
	for n : float in [1.6, 2.5, 3.4] as Array[float]:
		out.append(_sprite_case("ring %.1f" % n, HoopVisual.SHEET, HoopVisual.FRAMES,
				FxAttachment.Half.WHOLE, [_counted(PropVisual.PROP_FIRE_STYLE, n)]))
	return out

# Every live uniform is lerped, not just one, because each carries a stack ratio. That is the same
# interpolation `FxAttachment._eased` runs, which is what makes the panel a picture of a real
# mid-tween frame rather than of a state the game never reaches.

# ⚠ Typed locals, not a `hi.get(...)` inline: a Dictionary lookup is a Variant and `lerpf` refuses
# one under this project's warnings-as-errors — which fails at PARSE time, so the scene loads
# without its script and the run hangs with an empty log.

## A fire request pinned BETWEEN two whole stack counts — the only state a jump can hide in.
func _counted(style: FxFireStyle, count: float) -> FxRequest:
	var lo : Dictionary[StringName, float] = FxFire.stacks_live(int(floorf(count)), style)
	var hi : Dictionary[StringName, float] = FxFire.stacks_live(int(ceilf(count)), style)
	var t := count - floorf(count)
	var live : Dictionary[StringName, float] = {}
	for key : StringName in lo:
		var a : float = lo[key]
		var b : float = hi[key] if hi.has(key) else a
		live[key] = lerpf(a, b, t)
	var req := FxRequest.make(&"fire", FxFire.FIRE_SHADER, style, live[&"u_height"])
	req.live = live
	return req

## How long the ember row is left to burn, in seconds.
const EMBER_SECS := 1.4

# ⚠ THE ONE SHOT THAT RUNS LIVE, and the second one that is NOT REPRODUCIBLE. Embers are particles,
# spawned at random points at random times and simulated forward, so there is no clock to park — a
# single frame of a fresh attachment has emitted nothing at all.

# By EYE: embers over ALL FOUR hosts, each sized to its own host (the card's are the big ones,
# `ember.tres`; the prop and ball ones are `ember_prop.tres`), and the ball embers leaving the BALLS
# rather than pouring off the card's top edge, where a host-relative spawn would put them.

# ONE engine, scaled with the cases: a spec's sizes are in the ENGINE's units, so unscaled it draws
# sub-pixel specks against blown-up hosts. `ambient` is TRUE here alone — `_emit_embers` early-outs
# on it — and the loop runs on real frame deltas, which drive the emitters and the simulation pass.

## EMBERS from every fire that throws them: a burning card, hoop and knife, and a pair of lit balls.
func _shot_embers() -> void:
	var holder := Node2D.new()
	add_child(holder)
	var size := canvas()
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
		atts.append(_attach_for(case, slot, true))
		label(holder, case.label, Vector2(step * (i + 0.5), size.y * 0.9))
	var elapsed := 0.0
	while elapsed < EMBER_SECS:
		elapsed += await _tick()
	await capture("09_embers", "EMBERS from every fire — card / hoop / knife / lit balls, run live "
			+ "for %.1f s (NOT reproducible: see the comment)" % EMBER_SECS)
	for att : FxAttachment in atts: att.set_process(false)
	holder.queue_free()
	await get_tree().process_frame

# `_shot()`'s clock discipline applied to CARDS: leaving the card clocks running moved
# `10_light_layer` by up to 78834 px between runs of one unchanged build. ⚠ ORDER — `floating` (the
# `Time.get_ticks_msec()` term) FIRST, `set_process(false)` LAST or the next frame re-advances it.

# ⚠ A REST POSE, not a freeze of whatever the cards drifted into: a frozen arbitrary pose is
# reproducible only if the freeze is. Snap to the anchor rather than ease toward it — `exp(-10 *
# delta)` is frame dependent, and two frames leave a card visibly short of its slot.

# ⚠ THE BONE RIG HAS ITS OWN CLOCK AND `set_process(false)` DOES NOT REACH IT, so it is seeked and
# paused too (`update = true` applies the pose). Kept though `CardVisual.RIG_ANIM` no longer
# autoplays: if it is turned back on, the skinned pose stays pinned instead of drifting.
func _park_cards(root: Node) -> void:
	for node : Node in root.get_children():
		if not (node is ControlCard): continue
		var card : CardVisual = (node as ControlCard).child
		if not card or not is_instance_valid(card): continue
		card.floating = false
		card.basis3d = Basis.looking_at(Vector3(0.0, 0.0, -3.5))
		if card.visual: card.visual.position.y = 0.0
		if card.control_anchor and is_instance_valid(card.control_anchor):
			card.global_position = card.get_card_control_center(card.control_anchor)
		card.rotation_degrees = 0.0
		var rig := card.get_node_or_null(^"AnimationPlayer") as AnimationPlayer
		if rig:
			rig.seek(0.0, true)
			rig.pause()
		card.set_process(false)

# Not a `Case` row: the light surface is ONE screen-space quad over everything, so it has no host,
# no silhouette and no per-panel zoom, and is staged directly. The card visuals are added DEFERRED,
# so two frames are awaited before the capture or the board would be empty.

# ⚠ WHERE THE REAL SURFACE SITS IS NOT DECIDED, and this shot does not answer it. It shows what a
# light fragment COMPUTES, which is identical under every option on the table.

# ⚠ REAL CARDS, NOT RECTANGLES (project rule 9). A flat stand-in has no rank glyph to lose, no art
# square and no dark ink beside light paper, so it can never show the one thing a dim can get wrong,
# which is legibility. The TYPE is what draws the paper: without it there is no body to judge.

# By EYE: the board visibly DARKER outside the light and at full brightness inside it; the two
# crossing beams brighter where they cross without blowing out to white; each circle opening the dim
# COMPLETELY where the beam only thins it, and the beam WIDER at the card than at its origin.

# ⚠ THE BEAM STOPS ON ITS CIRCLE'S FAR ARC and its mouth is exactly the circle's width. Two earlier
# builds cut it at `t = 1`, the circle's CENTRE, ending the cone on a straight chord halfway across
# the pool — A STRAIGHT EDGE NEAR A BEAM END IS THAT BUG. Crop and magnify before judging.

# Also by EYE: the circle reads as its own pool inside the beam, brighter than the shaft feeding it,
# at all three radii, with the card under it keeping its rank and pips; the beams carry visible
# grain that is not screen static; the dim is a dark palette colour, NOT black, and not a vignette.

# Three lights, TWO CROSSING on purpose, at circle radii 46 / 70 / 100 px (the shipped 16 art units
# is ~46 px here), so the mouth and end cap, both derived from the radius, are looked at over three
# sizes. A beam's `.w` is FLARE past the circle; 0 means the mouth is exactly the circle it serves.

## THE LIGHT LAYER over a stand-in board.
func _shot_light_layer() -> void:
	var holder := Node2D.new()
	add_child(holder)
	var size := canvas()
	var ranks : Array[int] = [5, 11, 2, 9, 13, 7]
	for row : int in 3:
		for col : int in 6:
			var data := CardData.new() \
					.with_rank(PipRankNumeral.new().with_value(ranks[(col + row) % ranks.size()])) \
					.with_suit(_shot_suit(col + row * 2)) \
					.with_type(TypePaper.new())
			var control := ControlCard.add_child_control_card(holder, data,
					CardVisual.DisplayContext.PLAY_AREA)
			control.position = Vector2(70.0 + float(col) * 190.0, 130.0 + float(row) * 180.0)
	await get_tree().process_frame
	await get_tree().process_frame
	_park_cards(holder)
	var rect := ColorRect.new()
	rect.size = size
	var mat := ShaderMaterial.new()
	mat.shader = LIGHT_SHADER
	rect.material = mat
	holder.add_child(rect)

	var centres : Array[Vector2] = [Vector2(318.0, 395.0), Vector2(678.0, 395.0),
			Vector2(1128.0, 220.0)]
	var origins : Array[Vector2] = [Vector2(760.0, -240.0), Vector2(300.0, -190.0),
			Vector2(1150.0, -260.0)]
	var radii : Array[float] = [46.0, 70.0, 100.0]
	var lights := PackedVector4Array()
	var beams := PackedVector4Array()
	lights.resize(LIGHT_MAX)
	beams.resize(LIGHT_MAX)
	for i : int in centres.size():
		lights[i] = Vector4(centres[i].x, centres[i].y, radii[i], 1.0)
		beams[i] = Vector4(origins[i].x, origins[i].y, 26.0, 0.0)
	mat.set_shader_parameter(&"u_lights", lights)
	mat.set_shader_parameter(&"u_beams", beams)
	mat.set_shader_parameter(&"u_light_count", centres.size())
	mat.set_shader_parameter(&"u_dim", 0.75)
	mat.set_shader_parameter(&"u_time", SHOT_TIME)
	await capture("10_light_layer", "THE LIGHT LAYER (chart H): dim 0.75, three lights, two CROSSING "
			+ "(the overlap brighter, Q100=a, not blown out, Q101=a) at circle radius 46 / 70 / 100 "
			+ "— the beam's mouth and cap scale WITH the circle, and no size shows a straight edge")
	holder.queue_free()
	await get_tree().process_frame

## One frame of real time, and how long it took.
func _tick() -> float:
	await get_tree().process_frame
	return get_process_delta_time()

# ----------------------------------------------------------------- the harness

# A class, not a Dictionary, so every field is typed — warnings are errors in this project.

# `outline` set makes the attachment take the radius-table mask and the ghost draw the star rather
# than the box; `sheet` set hands the attachment its real art AND draws that art as the reference,
# because an outline cannot show a HOLE.

# `ball_dir` is pinned because a pattern that mirrors at random cannot be diffed, and the oracle has
# to be told the same value.

## One case: a host body drawn for reference with an FxAttachment on top of it.
class Case:
	var label : String = ""
	var body : Vector2 = Vector2.ZERO
	var shape : FxAttachment.Shape = FxAttachment.Shape.BOX
	var half : FxAttachment.Half = FxAttachment.Half.WHOLE
	var requests : Array[FxRequest] = []
	var rotation : float = 0.0
	## The host's DEFORMED outline, walked once around the shape, or empty for an undeformed host.
	var outline : PackedVector2Array = PackedVector2Array()
	## SPRITE cases: the sheet the mask is read out of, and how many frames it holds.
	var sheet : Texture2D = null
	var frames : int = 1
	## Phase override for the path trace, or -1 to use the shot's shared phase.
	var phase : float = -1.0
	## Carried so the oracle reads the split and throw easing the shader was handed.
	var style_top_fraction : float = 0.6
	var style_gravity : float = 1.0
	## The host's base ball direction, PINNED rather than left to its per-host coin flip.
	var ball_dir : float = 1.0
	## Host modulate: the effects must brighten with their host.
	var modulate : Color = Color.WHITE

# The style parameters are read off the LIVE style, never retyped: the oracle has to be told the
# same path parameters the shader was handed, and a stale copy here would read as a shader bug.
func _case(label: String, body: Vector2, shape: FxAttachment.Shape, half: FxAttachment.Half,
		requests: Array[FxRequest]) -> Case:
	var c := Case.new()
	c.style_top_fraction = StatusJuggling.JUGGLE_STYLE.ball_top_fraction
	c.style_gravity = StatusJuggling.JUGGLE_STYLE.ball_gravity
	c.label = label
	c.body = body
	c.shape = shape
	c.half = half
	c.requests = requests
	return c

# `inverse_square` is the one knob that decides whether the light reads as A LAMP or as A SMUDGE, so
# the first three panels are that knob alone and nothing else moves. The last two are the layer
# count: one falloff against the shipped tight-core-plus-wide-halo pair.

# Three ways the field can be wrong. NO RECTANGLE: the halo must fade to nothing before the quad's
# edge, which is what `falloff()`'s FLOOR constant exists to force. NO SEAM at the card's edge:
# `sink` starts the field inside the silhouette, so a bright line there means it is not applied.

# THE PURE-INVERSE-SQUARE PANEL HAS A VISIBLY HOTTER, TIGHTER CORE than the smooth one. If the three
# panels look alike, the knob is not reaching the shader.

## THE GLOW'S FIELD, ISOLATED.
func _glow_falloff() -> Array[Case]:
	var out : Array[Case] = []
	for k : float in [0.0, 0.6, 1.0]:
		out.append(_card_case("inv_sq %.1f" % k, [_glow_request(0.35, k, 2)]))
	out.append(_card_case("1 layer", [_glow_request(0.35, 0.6, 1)]))
	out.append(_card_case("2 layers", [_glow_request(0.35, 0.6, 2)]))
	return out

# ⚠ A READABILITY CALL THAT CANNOT BE MADE FROM A DESCRIPTION (project rule 5). The knob is the
# alpha the light draws at where it covers the host's own art: light ADDS, so the first thing to go
# is the rank glyph, the smallest dark feature on the card.

# The panels exist to be tuned against, not to confirm a number. 0 is the honest floor — pure
# addition outside the silhouette and nothing over the art — and 0.9 is what "the card is genuinely
# lit" costs. The shipped value is 0.35.

# ⚠ A plain BOX host is the LENIENT case. The real scenario is the spotlight CIRCLE at full
# intensity over the busiest card face the game can build, and it needs the light layer to exist
# before it can be staged.
func _glow_over_art() -> Array[Case]:
	var out : Array[Case] = []
	for a : float in [0.0, 0.35, 0.6, 0.9]:
		out.append(_card_case("inner_alpha %.2f" % a, [_glow_request(a, 0.6, 2)]))
	return out

# ⚠ The reach is `reach + sink`, the same budget `FxFire.request` uses and for the same reason: the
# field starts `sink` units INSIDE the silhouette, so a quad sized for `reach` alone clips the halo.

# `reach` is widened to 12.0 to READ at snapshot zoom. The shipped 4 is a rim, which is right on a
# board and wrong for judging a falloff curve in a still.

## One glow request off the shipped card style, with the two knobs a panel varies overridden.
func _glow_request(inner_alpha: float, inverse_square: float, layers: int) -> FxRequest:
	var style := load("res://Shaders/Styles/glow_card.tres").duplicate() as FxGlowStyle
	style.inner_alpha = inner_alpha
	style.inverse_square = inverse_square
	style.layers = layers
	style.reach = 12.0
	return FxRequest.make(&"glow", FxGlowStyle.GLOW_SHADER, style,
			style.reach + maxf(style.sink, 0.0))

func _card_case(label: String, requests: Array[FxRequest]) -> Case:
	return _case(label, CardVisual.CARD_SIZE, FxAttachment.Shape.BOX, FxAttachment.Half.WHOLE,
			requests)

# The body is derived from the same art the kind derives its own from rather than retyped, so a
# panel here cannot disagree with what the game draws.

## A case whose mask is a real sheet's ALPHA — every prop kind.
func _sprite_case(label: String, sheet: Texture2D, frames: int, half: FxAttachment.Half,
		requests: Array[FxRequest]) -> Case:
	var c := _case(label, PropVisual.art_size_for(sheet, frames), FxAttachment.Shape.SPRITE, half,
			requests)
	c.sheet = sheet
	c.frames = frames
	return c

## The host's reference drawing — its real art for a sprite kind, a plain outline otherwise.
func _ghost_for(case: Case, zoom: float) -> _Ghost:
	var ghost := _Ghost.new()
	ghost.body = case.body
	ghost.outline = case.outline
	ghost.sheet = case.sheet
	ghost.frames = case.frames
	if case.sheet: ghost.art_size = PropVisual.art_size_for(case.sheet, case.frames)
	ghost.px = 1.0 / maxf(zoom, 0.01)
	return ghost

# A sprite kind is handed its REAL sheet: the mask is that art's alpha, so a panel that skipped this
# would be decorating a plain box.

# The seed and ball direction are pinned BEFORE `sync`, unlike the clock which is pushed afterwards,
# because the quads read the host's randomness as they are built. An unpinned per-host random
# reduces `snapshot_diff.py`'s claim to "the RNG happened to land in the same place".

## Build one case's attachment.
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
	att._seed = SHOT_SEED
	att._ball_dir = case.ball_dir
	att.sync(case.requests)
	return att

# ⚠ THE ROTATED-PANEL NONDETERMINISM. `FxAttachment._rot_tight` defaults to true and is re-evaluated
# in one place, guarded by `if moved and on_screen:`. A first `_push_live` in the frame the
# attachment is added can see `_on_screen()` FALSE, and then `_rot_tight` never flips.

# For a ROTATED host that is the whole bug: `_size_quad` only widens the quad to the diagonal bound
# when `not _rot_tight`, so a turned card's flames render against a quad sized for an upright one.
# Bistable, never drifting — 8248 px apart every time for `02_fire_rotation`, because it is a bool.

# ⚠ A HARNESS BUG, NOT A GAME BUG: in play the attachment is never parked, so the frame the host
# comes back on screen re-evaluates the flag. Do not "fix" `fx_attachment.gd` for it. The fix is
# here — settle, then re-push and re-park.

# ⚠ TWO frames, not one: `_push_live` SKIPS ITS UPLOADS ENTIRELY when `_on_screen()` is false, and
# one frame was not always enough for the canvas transform to settle — measured on
# `behind_prop_turned`, which stayed bistable at one frame.

# ⚠ ORDER, the same rule as the build loop's: push FIRST, disable the process LAST, or
# `_push_live`'s trailing `set_process(not _fx.is_empty())` silently re-enables it and the awaited
# frames advance the clocks off `SHOT_TIME`.
func _settle_poses(atts: Array[FxAttachment]) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	for att : FxAttachment in atts:
		if not is_instance_valid(att): continue
		att._push_live(0.0)
		att.set_process(false)

# ⚠ ORDER MATTERS, and getting it wrong was mistaken for a shader bug: `_push_live` ENDS with
# `set_process(not _fx.is_empty())`, so disabling the process BEFORE pushing re-enables it, the
# awaited frames advance `_phase` by real deltas, and every ball lands ~0.15 of a cycle off.

# The ghost is added UNDER the effects and the modulate goes on a PARENT of the attachment, so it
# reaches them down the tree as a card's does. Ghost last would paint the oracle crosses over the
# very balls they exist to be compared against, which reads as the balls having vanished.

# The crosses are pinned to WORLD up, not to the tilted host: the pattern does not turn with its
# card, so an oracle drawn in the slot's rotated frame would sit where the balls are NOT — and the
# probe reads the same unrotated positions.

# The first `_push_live` seeds `_time`/`_phase`; `_settle_poses` re-pushes after a settle frame. The
# counter-rotation is printed before AND after the capture — `_push_live` sets `rotation =
# -parent.global_rotation`, and right-when-written but wrong-in-the-frame is its own bug.

## Lay the cases out, drive every clock to the SAME fixed time, wait for the frame, then capture.
func _shot(file_name: String, caption: String, cases: Array[Case]) -> void:
	var holder := Node2D.new()
	add_child(holder)
	var size := canvas()
	var step := size.x / float(cases.size())
	var zoom := _zoom_for(cases, step)
	var probes : Array[_Probe] = []
	var atts : Array[FxAttachment] = []
	for i : int in cases.size():
		var case : Case = cases[i]
		var slot := Node2D.new()
		slot.position = Vector2(step * (i + 0.5), size.y * 0.55)
		slot.scale = Vector2.ONE * zoom
		slot.rotation = case.rotation
		holder.add_child(slot)
		var ghost := _ghost_for(case, zoom)
		slot.add_child(ghost)
		ghost.balls = _oracle(case)
		ghost.ball_rot = -case.rotation
		if not ghost.balls.is_empty():
			var probe := _Probe.new()
			probe.label = case.label
			probe.origin = slot.position
			probe.zoom = zoom
			probe.expected = ghost.balls
			probe.tint = case.modulate
			probes.append(probe)
		var host := Node2D.new()
		host.modulate = case.modulate
		slot.add_child(host)
		var att := _attach_for(case, host, false)
		att._time = SHOT_TIME
		att._phase = case.phase if case.phase >= 0.0 else 0.13
		att._push_live(0.0)
		att.set_process(false)
		label(holder, case.label, Vector2(step * (i + 0.5), size.y * 0.9))
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
	await _settle_poses(atts)
	var img : Image = await capture(file_name, caption)
	for att : FxAttachment in atts:
		print("  [", file_name, "] POST-CAPTURE att.rotation=", att.rotation, " global=",
				att.global_rotation, " processing=", att.is_processing())
	for probe : _Probe in probes: _report(img, probe)
	holder.queue_free()
	await get_tree().process_frame

# Not a constant: a ball quad is ~152 art units across (the pattern's arc height dominates the
# extent) against a card's ~90, so a fixed zoom overlaps neighbouring slots and one case's balls draw
# on top of the next one's — a measurement trap, read once as a phase offset in the panel next door.

## The blow-up that keeps every case INSIDE its own slot.
func _zoom_for(cases: Array[Case], step: float) -> float:
	var widest := 1.0
	for case : Case in cases:
		for req : FxRequest in case.requests:
			widest = maxf(widest, case.body.length() + (req.reach + FxAttachment.FX_MARGIN) * 2.0)
	return minf(ZOOM_MAX, step * 0.98 / widest)

# ------------------------------------------------------ measuring the capture, not eyeballing it

# A line narrower than a pixel is DROPPED by Godot, so at the zoom a ball quad forces (~1.0) half of
# every oracle cross is missing from the PNG and "does the ball sit on its cross" cannot be judged by
# eye. The harness measures itself instead, printing the disagreement in ART UNITS.

## One case's expectation, kept until the frame has been captured.
class _Probe:
	var label : String = ""
	## Slot origin in CANVAS units, and the slot's art-unit-to-canvas blow-up.
	var origin : Vector2 = Vector2.ZERO
	var zoom : float = 1.0
	var expected : PackedVector2Array = PackedVector2Array()
	## The host's modulate: a ball's rendered colour is its palette entry times this.
	var tint : Color = Color.WHITE

## How far out, in ART UNITS, the probe is willing to look for a ball before calling it missing.
const PROBE_REACH := 24.0

# Sub-unit offsets are agreement: the search finds the nearest EDGE pixel of a ball, not its centre,
# so it reads a whole radius pessimistically.

# ⚠ THE BALL'S OWN COLOURS, NEVER A HUE GUESS. A "a ball is orange" predicate goes blind the moment
# `ramp_ball` is retuned, and it collides with the ORACLE CROSSES, which are green — a probe that
# cannot tell a ball from its cross is worse than none, and this one only PRINTS, so it fails quiet.

# The colour predicate is built WITH the host's modulate, or a FOCUSED panel reads as empty.

## Print, per expected ball, how far the nearest RENDERED ball pixel is, in ART UNITS.
func _report(img: Image, probe: _Probe) -> void:
	var to_img := to_image_scale(img)
	var art_to_img := probe.zoom * to_img
	var reach := int(ceilf(PROBE_REACH * art_to_img))
	var is_ball := PixelProbe.ball_pixel(StatusJuggling.JUGGLE_STYLE, probe.tint)
	for i : int in probe.expected.size():
		var want : Vector2 = (probe.origin + probe.expected[i] * probe.zoom) * to_img
		var hit := PixelProbe.nearest(img, want, reach, is_ball)
		var off : Vector2 = (hit[&"offset"] as Vector2) / art_to_img
		var found := "nearest rendered ball offset by art (%.1f, %.1f)" % [off.x, off.y] \
				if hit[&"found"] else "NO BALL within %.0f art units" % PROBE_REACH
		print("  PROBE [", probe.label, "] ball ", i, " expected art ", probe.expected[i],
				" -> ", found)

# `PixelProbe.ball_positions` is ONE transcription of the spec, shared with the asserting PIXELS
# suite and deliberately NOT derived from the shader.

## The expected ball positions for every juggling request in this case.
func _oracle(case: Case) -> PackedVector2Array:
	var out := PackedVector2Array()
	for req : FxRequest in case.requests:
		if req.phase_period <= 0.0 or req.shader != FxJuggle.JUGGLE_SHADER: continue
		out.append_array(PixelProbe.ball_positions(req.live[&"u_count"],
				case.phase if case.phase >= 0.0 else 0.13, req.live[&"u_span"],
				req.live[&"u_arc_height"], req.live[&"u_return_height"], case.style_top_fraction,
				case.style_gravity, case.ball_dir, req.live[&"u_ball_arcs"]))
	return out

# A SPRITE case draws its real art instead of an outline (an outline cannot show a HOLE), and a
# DEFORMED host draws its real outline, or the panel shows flames standing off a box the card is not
# — the exact class of tool lie this harness exists to avoid.

# ⚠ EVERY LINE WIDTH IS A MULTIPLE OF `px`, so the outline and the crosses stay ~2 px thick on
# screen. Fixed 0.5-unit widths were sub-pixel at the zoom a ball quad forces (~1.0) and Godot
# DROPPED them, leaving half of every cross and both horizontal card edges out of the PNG.

## The host's silhouette, drawn so the effect can be judged against the shape it decorates.
class _Ghost extends Node2D:
	var body : Vector2 = Vector2.ZERO
	## A SPRITE case's sheet and frame count; the mask is that art's alpha.
	var sheet : Texture2D = null
	var frames : int = 1
	var art_size : Vector2 = Vector2.ZERO
	## A DEFORMED host's real outline.
	var outline : PackedVector2Array = PackedVector2Array()
	## Independent expected ball positions, drawn as crosses.
	var balls : PackedVector2Array = PackedVector2Array()
	## Rotation applied to the CROSSES only, cancelling the slot's.
	var ball_rot : float = 0.0
	## ART UNITS PER SCREEN PIXEL for this slot (1 / the shot's zoom).
	var px : float = 1.0
# The centre line exists because the juggling loop's shallow return arc is specified to ride the
# card's CENTRE, which is impossible to eyeball without it. The crosses are the oracle: one that
# does not sit on a ball is a disagreement between the shader and the spec, readable at a glance.
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
		draw_line(Vector2(-body.x * 0.5, 0.0), Vector2(body.x * 0.5, 0.0),
				Color(0.35, 0.4, 0.5, 0.7), 1.5 * px)
		draw_set_transform(Vector2.ZERO, ball_rot, Vector2.ONE)
		for b : Vector2 in balls:
			var c := Color(0.4, 1.0, 0.6)
			var arm := maxf(2.5, 4.0 * px)
			draw_line(b - Vector2(arm, 0.0), b + Vector2(arm, 0.0), c, 1.5 * px)
			draw_line(b - Vector2(0.0, arm), b + Vector2(0.0, arm), c, 1.5 * px)

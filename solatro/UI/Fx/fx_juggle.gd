class_name FxJuggle
extends RefCounted
## How a juggling stack count becomes a pattern of balls, and the fire riding them.
##
## The two quads are built HERE, from ONE computation, and handed identical geometry. Two copies
## of the arc maths is the bug that makes flames trail their balls by a frame; the shared
## fx_common include prevents it in the shader, and this prevents it on the script side.

const JUGGLE_SHADER := preload("res://Shaders/juggle.gdshader")

## Ball count is genuinely UNCAPPED (owner ruling 5): the shader's closed-form lookup has no loop
## over it, so 500 balls cost what 5 do. What scales with the count is size, arc height and speed.
static func requests(stacks: int, levels: PackedInt32Array, balls_style: FxStyle,
		fire_style: FxStyle) -> Array[FxRequest]:
	var out : Array[FxRequest] = []
	if stacks <= 0: return out
	var geo := geometry(stacks, balls_style)
	var reach : float = geo[&"u_arc_height"] + geo[&"u_ball_radius"]

	var balls := FxRequest.make(&"balls", JUGGLE_SHADER, balls_style, reach)
	balls.live = geo
	balls.phase_period = period(stacks, balls_style)
	out.append(balls)

	# The ball-fire quad exists only while a ball is actually alight. A card with StatusBurning
	# and unlit balls shows NO ball fire — the negative case is the point of ruling 3.
	var fire_tex := fire_texture(stacks, levels, fire_style)
	if not fire_tex: return out
	var fire := FxRequest.make(&"ball_fire", FxFire.FIRE_SHADER, fire_style,
			reach + fire_style.height)
	fire.mode = FxAttachment.Mode.BALLS
	fire.live = geo.duplicate()
	# A ball's flame level comes from the TEXTURE, per ball. The card's stack level is deliberately
	# absent: ball fire and card fire are separate effects (owner ruling 21).
	fire.live[&"u_intensity"] = fire_style.intensity
	fire.live[&"u_height"] = fire_style.height
	fire.snap[&"u_ball_fire"] = fire_tex
	fire.phase_period = balls.phase_period
	out.append(fire)
	return out

## The pattern's geometry at a given ball count — the single source both quads read.
static func geometry(stacks: int, style: FxStyle) -> Dictionary[StringName, float]:
	var n := float(maxi(stacks, 1))
	var geo : Dictionary[StringName, float] = {}
	geo[&"u_count"] = n
	geo[&"u_span"] = style.ball_span
	# Balls SHRINK to fit as the count grows (owner ruling 5): area-preserving 1/sqrt(n), so the
	# total mass of ball on screen stays roughly constant, with a floor — past it they read as a
	# stream, which is the honest way to show 200 of them.
	geo[&"u_ball_radius"] = maxf(style.ball_radius / sqrt(n), style.ball_radius_min)
	# The throw arc gets TALLER to hold more balls without bunching (owner ruling 13); log, not
	# linear, or 50 balls would throw the arc off the top of the screen. The return arc stays
	# shallow — it is the "flat part", riding across the card's centre.
	geo[&"u_arc_height"] = style.ball_arc_height * (1.0 + log(n) * 0.35)
	geo[&"u_return_height"] = style.ball_return_height
	# Balls spin, and spin faster at higher counts (owner ruling 25).
	geo[&"u_ball_spin"] = style.ball_spin * (1.0 + log(n) * style.ball_spin_per_count)
	return geo

## Seconds for one full loop. The pattern QUICKENS with the count (owner ruling 12) — but note
## this fights the taller arc physically, since a higher throw means a longer flight, so the
## coefficient stays small. Most of the added busyness is free anyway: n balls on one loop of
## period T already cross any point at rate n/T.
##
## Expressed in BASE seconds, not live ones: the attachment's clock is already pacing-scaled, so
## deriving the period from the compressed delay too would speed the pattern up twice over.
static func period(stacks: int, style: FxStyle) -> float:
	var n := float(maxi(stacks, 1))
	var base := SettingsManager.settings.base_delay * style.ball_period_fraction
	return maxf(base / (1.0 + log(n) * 0.20), 0.05)

## The per-ball fire levels as a 1xN data texture, or null when no ball is alight.
##
## Uniform arrays need a constant size and the ball count is unbounded, so the levels travel as a
## texture — one texel per ball, r = that ball's own normalized level. Built when the status
## changes and NEVER per frame.
static func fire_texture(stacks: int, levels: PackedInt32Array,
		style: FxStyle) -> ImageTexture:
	var n := maxi(stacks, 1)
	var any := false
	var img := Image.create(n, 1, false, Image.FORMAT_RGBA8)
	for i : int in n:
		var raw : int = levels[i] if i < levels.size() else 0
		if raw <= 0:
			img.set_pixel(i, 0, Color(0.0, 0.0, 0.0, 1.0))
			continue
		any = true
		img.set_pixel(i, 0, Color(FxFire.level(raw, style), 0.0, 0.0, 1.0))
	return ImageTexture.create_from_image(img) if any else null

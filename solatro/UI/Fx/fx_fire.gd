@tool
class_name FxFire
extends RefCounted
## How a fire stack count becomes fire. One place, shared by every host that can burn — a card's
## StatusBurning, a prop's fire_stacks, a juggled ball's own level — so a knife and a card at the
## same stack count show the same fire, only sized differently.
##
## ⚠ THERE IS NO TENDRIL BUDGET ANY MORE. `FX_MAX_TENDRILS` was a cap on how many flames a crown
## grew before surplus stacks were spent on intensity instead; with the comb retired
## there is nothing to count, and every knob now ramps continuously from ONE stack rather than
## sitting flat until the twelfth. Owner: *"make sure all params have scaling ratios as stacks
## increase"*.

## The fire request for `stacks` stacks in `style`. Surplus stacks are spent on intensity, reach,
## aperture and the noise, all logarithmically: 100 stacks should look terrifying, not 100 times
## brighter than one stack.
static func request(id: StringName, stacks: int, style: FxFireStyle) -> FxRequest:
	var live := stacks_live(stacks, style)
	# HOW FAR PAST THE SILHOUETTE THE QUAD MUST REACH, and it is EXACT rather than an estimate: the
	# cover ladder is measured from `p.y - sink`, so the topmost fragment that can light sits
	# `height + sink` above the surface and none can sit higher. The retired build padded this by
	# `height_var` instead, which no longer exists.
	#
	# ⚠ `sink` BELONGS IN HERE AND LEAVING IT OUT CLIPPED THE FLAMES (owner report: *"fire
	# is clipped at edges"*). It shifts the whole ladder UP, so a prop at `sink = 1.5` drew 1.5 art
	# units of flame outside a quad sized for `height` alone and the top of every plume came off
	# square. `body_near` in the shader has carried the `+ sink` margin all along; the QUAD is what
	# did not. Negative sink lowers the ladder and needs no extra room, hence the `max`.
	var req := FxRequest.make(id, FIRE_SHADER, style, live[&"u_height"] + maxf(style.sink, 0.0))
	req.live = live
	return req

const FIRE_SHADER := preload("res://Shaders/fire.gdshader")

## The data-derived uniforms for a stack count: everything that changes when the count does, and
## nothing that changes per frame. Kept separate from request() so a host can refresh a live
## effect's numbers without rebuilding its quad.
##
## ⚠ THIS IS THE ONE MAPPING FROM STACKS TO UNIFORMS and it stays that (FX_HANDOFF §0d). Every knob
## with a stack ratio is scaled HERE and nowhere else; the ratios themselves are art, so they live
## on the style where the owner can reach them.
##
## ⚠ EVERY VALUE HERE MUST BE CONTINUOUS AND MONOTONE IN `stacks` (owner ruling 16: a stack change
## eases, it never jumps). `FxAttachment._eased` tweens these, and it can only tween what is
## continuous — a knob that stepped at an integer count would make the whole effect pop.
static func stacks_live(stacks: int, style: FxFireStyle) -> Dictionary[StringName, float]:
	var count := maxi(stacks, 1)
	var g := growth(count)
	var live : Dictionary[StringName, float] = {}
	# ⚠ KEPT, AS AN INTENSITY. `fire.gdshader` does not read it — it was the comb's cell count — but
	# `FxAttachment._emit_embers` reads it out of this dictionary as the ember RATE, so it has to
	# survive with nothing left to partition. Uncapped now: the cap was the tendril budget.
	live[&"u_count"] = float(count)
	live[&"u_intensity"] = style.intensity * ramp(g, style.intensity_ratio)
	live[&"u_height"] = style.height * ramp(g, style.height_ratio)
	live[&"u_aperture"] = style.aperture * ramp(g, style.aperture_ratio)
	live[&"u_fire_gain"] = style.fire_gain * ramp(g, style.gain_ratio)
	live[&"u_noise_scale"] = style.noise_scale * ramp(g, style.noise_scale_ratio)
	live[&"u_noise_scroll"] = style.noise_scroll * ramp(g, style.noise_scroll_ratio)
	live[&"u_level"] = level(count, style)
	return live

## How far up the stack ladder a count sits, as the number every ratio multiplies. `log`, so the
## effect crawls rather than saturating: 0 at one stack, 2.5 at twelve, 5.3 at two hundred.
static func growth(stacks: int) -> float:
	return log(float(maxi(stacks, 1)))

## One ratio applied. Clamped at zero because a large negative ratio at a high count would otherwise
## drive a knob through zero and out the far side — a flame with a negative grain size, which reads
## as the effect inverting rather than as a tuning mistake.
static func ramp(g: float, ratio: float) -> float:
	return maxf(1.0 + g * ratio, 0.0)

## Where a stack count sits on the palette ramp's v axis (owner ruling 14: colour shifts with the
## count). Logarithmic, so the colour CRAWLS rather than saturating at three stacks: at a
## reference of ~120 most of the ramp is spent on the first ~20 stacks — where the game actually
## lives — while a difference stays visible all the way up.
static func level(stacks: int, style: FxFireStyle) -> float:
	var ref := maxf(style.level_ref, 2.0)
	return clampf(log(float(maxi(stacks, 1))) / log(ref), 0.0, 1.0)

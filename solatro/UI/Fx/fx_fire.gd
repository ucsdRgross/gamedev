@tool
class_name FxFire
extends RefCounted
## How a fire stack count becomes fire. One place, shared by every host that can burn — a card's
## StatusBurning, a prop's fire_stacks, a juggled ball's own level — so a knife and a card at the
## same stack count show the same fire, only sized differently.

## How many flames still read as DISTINCT. One tendril budget for EVERY host: flame width scales
## with the host exactly like flame height, so the same count fits everywhere and a small object
## simply gets a small version of the same fire (owner correction 2026-07-26). Deriving the count
## from the host's width instead gave a knife fewer, relatively FATTER flames, which distorts the
## proportions the linear scaling exists to preserve.
##
## This is not a stack cap — no cap exists anywhere in the pipeline (owner ruling 4). Past this
## many stacks the fire gets FIERCER rather than sprouting more slivers.
const FX_MAX_TENDRILS := 12

## The fire request for `stacks` stacks in `style`. Surplus stacks are spent on intensity, height
## and merging instead of on more tendrils, all logarithmically: 100 stacks should look
## terrifying, not 100 times brighter than one stack.
static func request(id: StringName, stacks: int, style: FxStyle) -> FxRequest:
	var live := stacks_live(stacks, style)
	# The flames' own length is exactly how far past the silhouette the quad must reach — the mask
	# model bounds a flame at exactly `height`, in every column on every shape, so this is a true
	# bound and not an estimate.
	var req := FxRequest.make(id, FIRE_SHADER, style, live[&"u_height"])
	req.live = live
	# A lerp between "merged" and "not merged" means nothing, so the sheet snaps on. It only ever
	# flips at high stacks, where the crown is already a solid mass and the change does not read.
	req.snap[&"u_merge"] = 1 if merged(stacks, style) else 0
	return req

const FIRE_SHADER := preload("res://Shaders/fire.gdshader")

## The data-derived uniforms for a stack count: everything that changes when the count does, and
## nothing that changes per frame. Kept separate from request() so a host can refresh a live
## effect's numbers without rebuilding its quad.
static func stacks_live(stacks: int, style: FxStyle) -> Dictionary[StringName, float]:
	var count := maxi(stacks, 1)
	var over := overflow(count)
	var live : Dictionary[StringName, float] = {}
	live[&"u_count"] = float(mini(count, FX_MAX_TENDRILS))
	live[&"u_intensity"] = style.intensity * (1.0 + log(over) * 0.45)
	live[&"u_height"] = style.height * (1.0 + log(over) * 0.30)
	live[&"u_level"] = level(count, style)
	return live

## How much fire each tendril is carrying: 1.0 until the crown is full, then above it. This is
## what surplus stacks are spent on instead of more slivers.
static func overflow(stacks: int) -> float:
	var count := maxi(stacks, 1)
	return float(count) / float(mini(count, FX_MAX_TENDRILS))

## Whether the tendrils fuse into a sheet. On once they are carrying more than their share; off
## below that, because the 3-tap max triples the tendril evaluations — the shader's main cost.
static func merged(stacks: int, style: FxStyle) -> bool:
	return style.merge or overflow(stacks) > 1.5

## Where a stack count sits on the palette ramp's v axis (owner ruling 14: colour shifts with the
## count). Logarithmic, so the colour CRAWLS rather than saturating at three stacks: at a
## reference of ~120 most of the ramp is spent on the first ~20 stacks — where the game actually
## lives — while a difference stays visible all the way up.
static func level(stacks: int, style: FxStyle) -> float:
	var ref := maxf(style.level_ref, 2.0)
	return clampf(log(float(maxi(stacks, 1))) / log(ref), 0.0, 1.0)

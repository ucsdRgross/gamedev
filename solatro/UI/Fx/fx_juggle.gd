@tool
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
static func requests(stacks: int, levels: PackedInt32Array, balls_style: FxJuggleStyle,
		fire_style: FxFireStyle) -> Array[FxRequest]:
	var out : Array[FxRequest] = []
	if stacks <= 0: return out
	var geo := geometry(stacks, balls_style)
	var reach : float = geo[&"u_arc_height"] + geo[&"u_ball_radius"]
	var balls := FxRequest.make(&"balls", JUGGLE_SHADER, balls_style, reach)
	# The pattern does NOT turn with its host (owner 2026-07-30), so this quad keeps the cheap box
	# bound even on a spinning card — see FxRequest.rotates_with_host. Both quads of the pair must
	# say the same thing, or their lattices differ and the plume anchors off its ball.
	balls.rotates_with_host = false
	balls.live = geo
	balls.phase_period = period(stacks, balls_style)
	out.append(balls)

	# The ball-fire quad exists only while a ball is actually alight. A card with StatusBurning
	# and unlit balls shows NO ball fire — the negative case is the point of ruling 3.
	var fire_tex := fire_texture(stacks, levels, fire_style)
	if not fire_tex: return out
	var fire := FxRequest.make(&"ball_fire", FxFire.FIRE_SHADER, fire_style,
			reach + fire_style.height)
	# The fire shader has no emitter modes: a ball is a SHAPE whose mask is the union of the discs,
	# and everything above that mask — march, anchor, comb, ogee, onion shells, ramp — is literally
	# the same code a card runs (owner 2026-07-30).
	fire.shape = FxAttachment.Shape.BALLS
	# Its mask is the BALLS, and `mask_level`'s ball branch returns before `u_shape_rot` is ever read
	# — so this quad does not turn with the host either, and must match the balls quad exactly.
	fire.rotates_with_host = false
	# The plume anchors to the ball centre the BALLS quad drew, so it must snap on the BALLS quad's
	# lattice — a different extent and a different `pixel` from this quad's. Named, so the attachment
	# reads that quad's real size rather than rebuilding it here (FxRequest.partner_id).
	fire.partner_id = balls.id
	fire.partner_pixel = balls_style.pixel
	fire.live = geo.duplicate()
	# ONE FLAME PER BALL, as wide as its ball. `u_emit_width` is a DIAMETER: a ball's arch is anchored
	# to the ball's own centre, so this is the flame's width and nothing else. A comb across the quad
	# would put a ~30-unit cell against a ball of radius ~1.3 and let one flame straddle the pattern —
	# and, being anchored to the quad while the ball travels, would blink the plume in and out
	# (FX_HANDOFF §2).
	fire.live[&"u_count"] = 1.0
	fire.live[&"u_emit_width"] = geo[&"u_ball_radius"] * 2.0
	# The BALL COUNT is its own uniform now that `u_count` means tendrils: the mask needs it to find
	# which ball a fragment is over.
	fire.live[&"u_ball_count"] = geo[&"u_count"]
	# A ball's flame level comes from the TEXTURE, per ball. The card's stack level is deliberately
	# absent: ball fire and card fire are separate effects (owner ruling 21).
	fire.live[&"u_intensity"] = fire_style.intensity
	fire.live[&"u_height"] = fire_style.height
	fire.snap[&"u_ball_fire"] = fire_tex
	fire.lit = lit_balls(stacks, levels)
	fire.phase_period = balls.phase_period
	out.append(fire)
	return out

## The pattern's geometry at a given ball count — the single source both quads read.
static func geometry(stacks: int, style: FxJuggleStyle) -> Dictionary[StringName, float]:
	var n := float(maxi(stacks, 1))
	var geo : Dictionary[StringName, float] = {}
	geo[&"u_count"] = n
	geo[&"u_span"] = style.ball_span
	# Balls SHRINK to fit as the count grows (owner ruling 5): area-preserving 1/sqrt(n), so the
	# total mass of ball on screen stays roughly constant, with a floor — past it they read as a
	# stream, which is the honest way to show 200 of them.
	geo[&"u_ball_radius"] = maxf(style.ball_radius / sqrt(n), style.ball_radius_min)
	# The throw arc gets TALLER to hold more balls without bunching (owner ruling 13); log, not
	# linear, or 50 balls would throw the arc off the top of the screen. CAPPED at ball_arc_max: the
	# pattern may peak above the card's top edge but not far enough to cover the card behind it
	# (owner 2026-07-28) — past the cap, the balls' own shrink is what makes room. The return arc
	# stays shallow — it is the "flat part", riding across the card's centre.
	# The ceiling applies to the drawn BALL, not its centre, so the radius comes out of the budget —
	# otherwise the topmost ball overshoots by its own radius.
	geo[&"u_arc_height"] = minf(style.ball_arc_height * (1.0 + log(n) * 0.35),
			maxf(style.ball_arc_max - geo[&"u_ball_radius"], 0.0))
	geo[&"u_return_height"] = style.ball_return_height
	# THE PATH'S TIMING, HANDED TO BOTH QUADS FROM ONE PLACE. These used to ride in `FxStyle.apply()`,
	# which meant the ball-fire quad read them off the FIRE style (`fire_ball.tres`) while the balls
	# read them off the JUGGLE style — two resources that had to agree about the same path, with
	# nothing checking that they did, and a plume sliding off its ball if they ever drifted. They
	# agreed only because both were left at their script defaults. The juggle style owns the path, so
	# it owns these; the same reason `u_ball_arcs` is here rather than in apply().
	geo[&"u_top_fraction"] = style.ball_top_fraction
	geo[&"u_ball_gravity"] = style.ball_gravity
	# Balls spin, and spin faster at higher counts (owner ruling 25).
	geo[&"u_ball_spin"] = style.ball_spin * (1.0 + log(n) * style.ball_spin_per_count)
	geo[&"u_ball_arcs"] = float(arcs(stacks, style))
	return geo

## How many ARCS the loop is made of at this ball count. Lanes appear between the throw and the carry
## as the count rises (owner 2026-07-28) so the balls have more of the space to travel through
## instead of one arc getting ever taller. ALWAYS EVEN — arcs alternate direction, so an odd count
## would leave the loop open in x — and capped by the style, which is also the shader's cost ceiling
## (the nearest-ball lookup does fixed work per arc).
##
## ⚠ This is an INTEGER and it steps: the arc count changing IS a change of path, so the pattern
## re-shapes when a stack crosses a lane boundary. That is the one place ruling 16's "no visual
## jumps" does not hold — the alternative is interpolating between two different path topologies.
static func arcs(stacks: int, style: FxJuggleStyle) -> int:
	var n := float(maxi(stacks, 1))
	var lanes := 1 + int(floorf(log(n) * style.ball_arcs_per_count))
	return clampi(lanes * 2, 2, style.ball_arcs_max - (style.ball_arcs_max % 2))

## Seconds for one full loop. The pattern QUICKENS with the count (owner ruling 12) — but note
## this fights the taller arc physically, since a higher throw means a longer flight, so the
## coefficient stays small. Most of the added busyness is free anyway: n balls on one loop of
## period T already cross any point at rate n/T.
##
## REAL seconds from the style, NOT scaled by `base_delay`. The attachment's clock is already
## pacing-scaled, so act compression still quickens the loop; folding the player's global speed knob
## in on top of that made the whole cycle 0.12 s at base_delay 0.1 and the balls unreadable (owner
## report 2026-07-28). How fast juggling looks is an art decision, not a consequence of how fast the
## player set the game's step.
static func period(stacks: int, style: FxJuggleStyle) -> float:
	var n := float(maxi(stacks, 1))
	return maxf(style.ball_period_secs / (1.0 + log(n) * 0.20), 0.05)

## Which ball indices are alight. Built from the SAME levels the fire texture is, right beside it, so
## the emitter and the shader can never disagree about which balls are burning.
static func lit_balls(stacks: int, levels: PackedInt32Array) -> PackedInt32Array:
	var out := PackedInt32Array()
	for i : int in maxi(stacks, 1):
		if i < levels.size() and levels[i] > 0: out.append(i)
	return out

## Height of arc `j` of `arcs`: the tall throw at j = 0 down to the flat carry at the last one.
static func _arc_height(j: float, arcs: float, h_top: float, h_bot: float) -> float:
	return lerpf(h_top, h_bot, j / maxf(arcs - 1.0, 1.0))

## ONE GRAVITY FOR THE LADDER: an arc's share of the cycle is proportional to sqrt of its own height
## — the flight time one gravity gives it — with `f` biasing the throw's hang time about the purely
## physical 0.5.
static func _arc_weight(j: float, arcs: float, h_top: float, h_bot: float, f: float) -> float:
	var w := sqrt(maxf(_arc_height(j, arcs, h_top, h_bot), 1e-4))
	return w * (maxf(f, 0.05) / 0.5) if j < 0.5 else w

## Where ball `i` is, in ART UNITS from the host's centre — the script side of `fx_ball_pos`.
##
## ⚠ THIS IS A SECOND COPY OF THE PATH, and fx_common.gdshaderinc exists precisely because two copies
## drift (§4g: flames trailing their balls by a frame). It is here because EMBERS ARE PARTICLES: they
## are spawned by GDScript into ParticleEngine's world space, so "where is the burning ball" cannot
## be answered in the shader at all. Nothing else on the script side may call the path — anything the
## shader draws still reads the include, which is what keeps the copies down to exactly one.
##
## The drift is PINNED rather than merely warned about. test_fx_attachment's
## `test_ball_pos_matches_the_oracle` holds this to PixelProbe.ball_positions — the independent
## oracle transcribed from the SPEC, not from the include — and test_pixels.gd holds that oracle to
## the rendered frame. So this disagreeing with juggle.gdshader fails headless, in milliseconds.
static func ball_pos(i: float, n: float, phase: float, span: float, h_top: float, h_bot: float,
		f: float, g: float, dir: float, arcs: float) -> Vector2:
	var a_count := maxf(arcs, 2.0)
	var total := 0.0
	for k : int in int(a_count):
		total += _arc_weight(float(k), a_count, h_top, h_bot, f)
	total = maxf(total, 1e-5)
	var u := fposmod(phase + i / maxf(n, 1e-4), 1.0)
	# Which arc, and how far along it in TIME. Walked rather than solved: the shares are not uniform.
	var j := a_count - 1.0
	var a := 0.0
	var acc := 0.0
	for k : int in int(a_count):
		var share := _arc_weight(float(k), a_count, h_top, h_bot, f) / total
		if u < acc + share or float(k) >= a_count - 1.0:
			j = float(k)
			a = (u - acc) / maxf(share, 1e-5)
			break
		acc += share
	a = clampf(a, 0.0, 1.0)
	# The eased value drives BOTH axes, so the PATH is untouched and only the speed along it changes.
	if g > 1.0:
		var d := 2.0 * a - 1.0
		a = 0.5 + 0.5 * signf(d) * pow(absf(d), g)
	# Even arcs run +x -> -x, odd ones the reverse, so consecutive arcs chain end to end.
	var sweep := 1.0 if int(j) % 2 == 0 else -1.0
	return Vector2(span * 0.5 * (1.0 - 2.0 * a) * sweep * dir,
			-_arc_height(j, a_count, h_top, h_bot) * sin(a * PI))

## The per-ball fire levels as a 1xN data texture, or null when no ball is alight.
##
## Uniform arrays need a constant size and the ball count is unbounded, so the levels travel as a
## texture — one texel per ball, r = that ball's own normalized level. Built when the status
## changes and NEVER per frame.
static func fire_texture(stacks: int, levels: PackedInt32Array,
		style: FxFireStyle) -> ImageTexture:
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

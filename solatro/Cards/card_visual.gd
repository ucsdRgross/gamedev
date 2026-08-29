@tool
extends Node2D
class_name CardVisual

const CARD_VISUAL = preload("uid://bynh2btoahe5i")

## THE CARD FACE AS THE SHEET DRAWS IT — one frame of `card_types.png`, in art units (= source texels).
## The card the player sees is this plus the outline shader's rim on all four sides.
const CARD_ART_SIZE := Vector2(38, 52)
## The rim `Shaders/outline.gdshader` paints, in art units. Not a second opinion — `CardOutline` owns it.
const ART_OUTLINE := CardOutline.WIDTH
## The DRAWN card: 40x54, and stated as art + rim rather than typed as a number.
##
## ⚠ **THE MASK AND THE DRAWN EDGE AGREE ONLY BECAUSE THE RIM EXACTLY FILLS THE POLYGON, AND NOTHING
## ELSE IN THE CODE SAYS SO.** A card's FX mask is GEOMETRY-derived — `_ready` hands `fx` the star rig's
## arm tips, which know nothing about what a shader painted — so if the outline were ever switched off,
## the art would shrink to 38x52 while the mask still said 40x54 and every flame would root itself one
## art unit off the art on all four sides (2.5 screen px at the default card_scale, against a fire that
## reaches 7 units). It would not snap back. Writing the size this way is what makes that coupling
## visible; the mask insets by `ART_OUTLINE`, so setting the rim to zero moves both together.
##
## ⚠ **It is NOT a one-line "remove the outline", and should not be sold as one.** The 16 bones are
## AUTHORED in card_visual.tscn, not derived from anything here, so a real removal is still a scene edit
## plus a skin re-bake. This constant makes the shader and the mask follow; the skeleton cannot.
##
## ⚠ **And do not "fix" the mask by reading it from alpha instead.** The rig is what DEFORMS: alpha can
## describe the shape at rest but cannot say where it went when `Arm_TopLeft` swings out 26 %. Reading
## the mask from the rig is what makes flames track a bending card at all.
const CARD_SIZE := CARD_ART_SIZE + Vector2.ONE * ART_OUTLINE * 2.0
## The strip of a covered card that stays visible in a stack, in art units.
##
## Stacks grow UPWARD, so the strip that stays visible is the card's BOTTOM band, and what has to
## fit inside it is that card's pip row. Derived from where the pips actually sit in
## `card_visual.tscn` -- the Rank/Suit polygons are centred at y = 18 with a +/-5 extent, so the
## pips span [13, 23] and the card's bottom edge is at 27:
##
##     4 (margin below the pips) + 10 (the outlined pip) = 14
##     14 + 2 (clearance for the idle rig)               = 16
##
## ⚠ **IT IS A BOARD-LAYOUT NUMBER, NOT JUST A CARD ONE** -- it is the board's row pitch, so
## moving it moves every stacked card and every prop anchored to a slot. The 2 is the only part
## that is a choice rather than a measurement (owner: *"pip added 2 pixels, need 2 unit clearance
## to account for animations"*); everything else follows from the art, and
## `test_outline.test_card_separation_derives_from_the_pip_row` re-derives it from the scene so
## an art pass that moves the pips cannot silently leave the pitch behind.
const CARD_SEPARATION : int = 16
## How far anim_jump lifts a card, in UNSCALED units. Shared, not a literal inside the animation:
## props a card jumps INTO (the hoop) ride at exactly this height so the two CENTRES coincide —
## `PropVisual.rides_card_jump` reads `jump_rise_play` for that. Change it here and the ring
## follows; hardcode it in either place and the card jumps through the side of the hoop.
const CARD_JUMP_RISE := CARD_SIZE.y / 5.0

## The rig's idle ("wiggle") animation in `card_visual.tscn`.
##
## ⚠ **NAMED HERE BECAUSE IT IS NO LONGER ON `autoplay`, AND FIVE INSTRUMENTS USED TO DISCOVER IT
## THROUGH THAT FLAG** (owner: the idle was only ever on to eyeball that the VFX overlay
## tracked a moving rig, so it is off in the shipped card). `test_pixels`, `tools/fx_editor`,
## `tools/outline_atlas` and `tools/spotlight_tool` all read `AnimationPlayer.autoplay` purely to
## learn the animation's NAME and then seek it themselves.
##
## ⚠ **CLEARING `autoplay` WITHOUT THIS CONSTANT SILENTLY GUTS THE PIXELS SUITE.** Every one of those
## sites is guarded by `if ap.autoplay != ""`, so an empty flag skips the seek, the card stays at its
## REST pose, and `test_the_card_mask_is_the_card_the_player_sees` goes on "passing" at t=0.15 / 0.30
## / 0.45 while measuring the rest pose three more times — the pose where the corner model is exact
## by construction, which is the one case that proves nothing. The deformed-pose signature to check
## after any change here is the suite's own printout: worst edge/corner **0.00/0.00 at t=0.00,
## 0.48/1.21 at t=0.15, 1.50/2.45 at t=0.30**. All-zero everywhere means the rig stopped moving.
const RIG_ANIM : StringName = &"new_animation_2"

@export_tool_button("Update Visual") var editor_update_visual : Callable = update_visual

enum DisplayContext {PLAY_AREA, MAP, DECK_VIEWER, PREVIEW}
@export var current_context: DisplayContext = DisplayContext.PLAY_AREA
var control_anchor: Control = null
## Which EDGE of `control_anchor` the card hangs from. A grid cell's stack grows UPWARD and every
## card in a row shares a BOTTOM edge, so a covered card shows its bottom strip -- which is where
## the pips are. The Entrance still fans DOWNWARD from its control tops. PlayArea sets this per
## card when it binds the slot.
var bottom_anchored := false

var card_size : Vector2
var card_separation: int
var card_separation_custom: int

## The settings a card reads. `@tool` and the FX EDITOR are why this is not `SettingsManager.settings`
## directly: the editor instantiates NO autoloads, and the tool stands up a REAL card (owner
## 2026-07-29: *"no useless mocks when you can just use actual original scene"*), so every settings read
## on the construction path has to survive their absence. The shipped defaults stand in, which is also
## what a tuning tool should be showing.
##
## ⚠ ONE ACCESSOR, DELEGATED — this used to be its own copy of `FxAttachment.settings()` body and its own
## `static var _editor_settings`, which meant the editor held TWO PlayerSettings instances: the FX editor
## tuned `fx_intensity` against one object while the real card it was previewing sized itself against
## another, so the one tool that shows both could quietly disagree with itself. `FxAttachment` is the
## right home because a card already depends on it and it depends on no host.
static func settings() -> PlayerSettings:
	return FxAttachment.settings()

static var card_size_play : Vector2:
	get():
		return CARD_SIZE * settings().card_scale
static var card_separation_play : int:
	get():
		return CARD_SEPARATION * settings().card_scale
static var card_separation_play_custom : int:
	get():
		return card_separation_play * settings().card_separation_scale
## CARD_JUMP_RISE in SCREEN pixels — the jump lives on `offset`, inside the card root's card_scale,
## so anything outside the card (PropLayer) has to scale it the same way to line up.
static var card_jump_rise_play : float:
	get():
		return CARD_JUMP_RISE * settings().card_scale

var focused : bool = false:
	set(value):
		focused = value
		if focused: modulate = Color(1.825, 1.825, 1.825)
		else: modulate = Color(1.0, 1.0, 1.0)
@export var data : CardData:
	set(value):
		if data == value: return
		#N9 idiom: this visual follows exactly ONE data — drop the old resource's
		#connections on swap so it can't keep updating a re-purposed visual
		if data:
			if data.data_changed.is_connected(update_visual):
				data.data_changed.disconnect(update_visual)
			if data.stage_changed.is_connected(on_stage_changed):
				data.stage_changed.disconnect(on_stage_changed)
		data = value
		if data:
			data.data_changed.connect(update_visual)
			data.stage_changed.connect(on_stage_changed)
		update_visual()

		if current_context != DisplayContext.PLAY_AREA: return
		if is_node_ready() and data:
			on_stage_changed()
var can_move_anim := true
var can_rot_anim := true
var floating : bool = true:
	set(value):
		floating = value
		if not floating:
			if not is_node_ready():
				await ready
			basis3d = Basis.looking_at(Vector3(0, 0, -3.5 * (-1 if data and data.flipped else 1)))
			if Engine.is_editor_hint():
				visual.position.y = 0

var basis3d : Basis = Basis(Vector3(-1,0,0), Vector3(0,1,0), Vector3(0,0,-1)):
	set(value):
		basis3d = value
		visual.transform.x = Vector2(basis3d.x[0], basis3d.x[1])
		visual.transform.y = Vector2(basis3d.y[0], basis3d.y[1])
		show_front = basis3d.z[2] > 0
#change flipped instead
var show_front := false :
	set(value):
		if value != show_front:
			show_front = value
			update_visual()

func update_visual() -> void:
	# @onready polygon nodes only exist once ready — await BEFORE choosing the branch so the
	# front/placeholder decision reflects the current show_front. Deciding first and awaiting
	# inside a branch let an early (pre-_ready) call resume into a now-stale branch and clobber
	# a face already set during _ready (e.g. the instant-face snap for non-drawn cards).
	if not is_node_ready():
		await ready
	if fx:
		# FX draws OUTSIDE the silhouette, so it would leak a face-down card's statuses unless
		# gated — a hidden card must reveal zero information (owner ruling 23). This is the one
		# deliberate exception to "no visual jumps": show_front flips at the basis3d midpoint,
		# when the card is edge-on and a sliver, so the cut is invisible.
		fx.visible = show_front and data != null
		fx.sync(_fx_requests())
	if show_front and data:
		if data.rank:
			data.rank.set_texture(rank)
			rank.show()
		else: rank.hide()
		if data.suit:
			# The pip keeps its OWN colours (its sheet is authored in the palette); only the
			# suit-agnostic art — the rank pip here, the card art below — is recoloured to the suit's
			# palette entry. Both wear the outline material either way; what differs is the fill mode.
			data.suit.set_texture(suit)
			data.suit.set_material(rank)
			suit.show()
		else:
			suit.hide()
			# Suitless preview cards have no palette role to recolour their rank to, so it draws the
			# sheet's own colours. NOT `material = null`: that would take the rim with it, and on a
			# pooled polygon it would do so only for the cards that happened to land there.
			CardOutline.fill_texture(rank)

		if data.type:
			data.type.set_texture(type)
			type.show()
		else: type.hide()
			
		if data.stamp:
			data.stamp.set_texture(stamp)
			stamp.show()
		else: stamp.hide()
			
		if data.skill:
			data.skill.set_texture(art)
			data.skill.set_material(art)
			art.show()
		elif data.suit and data.rank:
			data.suit.set_art_texture(art, data.rank)
			data.suit.set_material(art)
			art.show()
		else: art.hide()  # rankless suit cards have no art (a bare colored polygon otherwise)

	else:
		rank.hide()
		stamp.hide()
		suit.hide()
		art.hide()

		#placeholder
		CardOutline.frame_polygon(
			type,CardModifierType.TYPE_TEXTURE,
			CardModifierType.H_FRAMES,
			CardModifierType.V_FRAMES,
			1)
		CardOutline.fill_texture(type)
		type.show()
	_push_outline_ink()

## ONE OUTLINE INK PER CARD, resolved here and pushed to all five polygons (design D7 / §2e).
##
## ⚠ **THIS INVERTS WHO OWNS THE MATERIAL, and that is the structural half of this feature.** Every
## modifier still sets its own polygon's TEXTURE and FILL — those are facts about the element. The
## outline colour is a fact about the CARD, so resolving it inside each modifier would derive the same
## thing five times and leave nowhere for a per-type override to land. It is resolved once, here.
##
## The value comes from the card's TYPE, because the type is the card's whole face and the ink has to
## work against it. A card with no type (a placeholder, a stripped test card) falls back to the shared
## `art_outline` role, which is the same default an unauthored type answers with.
func _push_outline_ink() -> void:
	var style := outline_style()
	for poly : Polygon2D in [type, rank, stamp, suit, art]:
		CardOutline.set_rim(poly, style, CARD_SIZE)
	_push_alert()

## THIS CARD'S OUTLINE STYLE — its TYPE's, or the shipped default when it has no type (a placeholder, a
## stripped test card). The type owns it because the type is the card's face and the ink's job is to
## read against that face.
func outline_style() -> OutlineStyle:
	if data and data.type: return data.type.outline_style()
	return CardOutline.STYLE

## THE LIVE ALERT, re-derived from the card's statuses and pushed to all five polygons.
##
## ⚠ **RE-DERIVED, NOT TOGGLED** — see `CardModifierStatus.alert_request`. Because this runs on every
## refresh and reads the whole status list, an alert whose status was removed, merged away or rewound
## is already off, and two simultaneous alerts cannot switch each other off. There is deliberately no
## "stop alerting" method to call, and adding one would reintroduce exactly the leak this avoids.
##
## The shader runs ONE kind at a time, so when several statuses alert together the LAST declared wins —
## the same "later draws on top" tie-break `_fx_requests` uses, for the same reason: the status list is
## ordered and the order is the card's own.
func _push_alert() -> void:
	var reqs := _alert_requests()
	_alert = reqs[reqs.size() - 1] if not reqs.is_empty() else null
	var style := outline_style()
	for poly : Polygon2D in [type, rank, stamp, suit, art]:
		CardOutline.set_alert(poly, _alert, style)
	if not _alert:
		# Park the phase at rest so a card that alerted and stopped is bit-identical to one that never
		# did — otherwise the next alert would start wherever the last one happened to be interrupted.
		_alert_clock = 0.0
		_push_alert_clock()

## Every outline alert this card's statuses ask for, in status order. The alert twin of `_fx_requests`,
## and generic in the same way: CardVisual never names an alert.
func _alert_requests() -> Array[CardAlert]:
	var reqs : Array[CardAlert] = []
	if not data: return reqs
	for status : CardModifierStatus in data.statuses:
		reqs.append_array(status.alert_request())
	return reqs

func _push_alert_clock() -> void:
	for poly : Polygon2D in [type, rank, stamp, suit, art]:
		CardOutline.set_clock(poly, _alert_clock)

## The alert currently running on this card's outline, or null. Null is the overwhelmingly common case
## and is what makes the per-frame cost of this feature one null check on a resting board.
var _alert : CardAlert = null
## The alert's phase, in TURNS — one full bounce per unit. Advanced in `_process` while `_alert` is
## live; the shader takes `fract()` of it, so it never needs wrapping here.
var _alert_clock : float = 0.0

## Advance the alert's phase over a period that is a FRACTION OF THE LIVE DELAY, so the cue quickens
## with act compression exactly as the cascade it is announcing does (START_HERE rule 4).
##
## ⚠ Note this does NOT also multiply by `FxAttachment.pacing()`, and must not: `pacing()` IS
## `base_delay / get_delay()`, so dividing by a period already built from `get_delay()` applies the
## same compression a second time and the alert would race the board it is pacing against.
func _advance_alert(delta : float) -> void:
	var delay : float = settings().base_delay
	if CardEnvironment.CURRENT: delay = CardEnvironment.CURRENT.get_delay()
	# get_delay() reaches zero under the compression floor and on an undo-cancel snap; a zero period
	# would divide by nothing and NaN the uniform, so floor it the way anim_spin_start does.
	# The period follows the same three-layer resolution the colours do: this alert's own value if it
	# named one, else THIS CARD's style — and glare and throb read different fields of it, because they
	# are different cues and share no tempo.
	var period := maxf(_alert.resolved_period(outline_style()) * delay, 0.05)
	_alert_clock += delta / period
	_push_alert_clock()

## Every visual effect this card's statuses ask for, in status order (later draws on top). Generic
## by construction: CardVisual never names an effect — statuses declare their own via fx_request().
func _fx_requests() -> Array[FxRequest]:
	var reqs : Array[FxRequest] = []
	if not data: return reqs
	for status : CardModifierStatus in data.statuses:
		reqs.append_array(status.fx_request())
	return reqs

var num : int = 0
var move_tween : Tween
var tilt_tween : Tween
var spin_tween : Tween
var held : int = 0
var hover : bool = false

@onready var offset: Node2D = $Offset
@onready var visual: Node2D = $Offset/Visual
@onready var type: Polygon2D = $Offset/Visual/Type
@onready var rank: Polygon2D  = $Offset/Visual/Rank
@onready var stamp: Polygon2D = $Offset/Visual/Stamp
@onready var suit: Polygon2D  = $Offset/Visual/Suit
@onready var art: Polygon2D = $Offset/Visual/Art

## **WHERE A SPOTLIGHT CIRCLE GOES ON THIS CARD** — the centre of the ART SQUARE, not the card's own
## origin (design `Q85`: *"Radius 16 art units, centred on the card's art-square centre"*).
##
## ⚠ **THE TWO ARE NOT THE SAME POINT AND THE DIFFERENCE IS VISIBLE.** `Art` sits at `(0, 6)` inside
## `Visual` and its polygon spans ±17, so the square is 34 art units across — 32 of drawing plus the
## shader's 1-unit rim on each side, which is why `Q85`'s radius of 16 became 17. Centring on the card
## origin instead put the pool high and made it
## ambiguous WHICH card in a stack was lit, which is what the owner reported on 2026-08-04:
## *"hard to tell which card circle it is on currently"*.
## ⚠ **ASKED OF THE CARD, never re-derived by the caller.** The offset is authored in
## `card_visual.tscn` and rides `Offset`'s own transform (the scoring jump lives there), so a second
## copy in the director would be a constant that silently disagrees the moment a card moves. Both
## `SpotlightDirector` and `Tools/spotlight_tool.gd` call this.
func spotlight_center() -> Vector2:
	# `art` is `@onready`; a card asked before it is in the tree answers with the honest fallback
	# rather than crashing, and the caller's own `is_inside_tree` guard is what normally prevents it.
	return art.global_position if art else global_position
## Shader effects for this card's statuses — created at runtime (no .tscn slot, and OWNERLESS: this
## script is `@tool`, so an owned child would be written into card_visual.tscn by the editor), and a
## child of OFFSET rather than of `visual` (see _ready).
##
## ⚠ **IT IS NOW A STATUS'S ONLY CARD-SIDE PRESENCE.** The `StatusLayer` that used to sit in the card's
## top-left drawing a placeholder icon and a stack count per status is DELETED (owner: *"no
## more status icons, they are represented by status effects like fire and juggling shader... stack
## count and status names stay in description at top"*). See `CardModifierStatus.fx_request` for the
## standing rule that creates.
var fx : FxAttachment

# --- THE STAR RIG, AS THE FX SEE IT ---------------------------------------------------------------
## The rig's root and its arm bones, in the order the bake laid them down — which walks once around
## the card (top edge left to right, then right, bottom, left). That order IS `FxAttachment
## .measure_outline`'s contract, and it is what makes the outline resolvable in one pass.
var _rig_root : Bone2D = null
var _rig_arms : Array[Bone2D] = []
## The arm tips in the card's own art units, rebuilt in place each frame — never reallocated, since
## this runs on every card on the board. Longer than the arm count when the art clips its corners: the
## bite needs three points where the rig has one (`_rig_outline`).
var _rig_outline_buf : PackedVector2Array = PackedVector2Array()
## How far into each corner this card's TYPE art bites, as a fraction of the corner cell's two edges.
## Resolved once in `_bind_rig`; zero for a frame with square corners (the boosters).
var _notch_frac : Vector2 = Vector2.ZERO

## A card silhouette with its four CORNERS pulled outward by `warp` of their rest reach, as the 16
## points the star rig hands over and IN THE ORDER it hands them over: one walk around the shape,
## corner first, then the three interior points of that edge.
##
## The interior points stay on the rest edge, so the box becomes a STAR rather than simply growing.
## It lives here, on the class that owns the rig, because four separate places need to stand a card up
## without one: the FX editor's warp slider, `fx_snapshot`'s warp panel, `fx_behind`'s seam shots and
## `fx_cost`'s deformed-card row. A private copy in any of them is a copy that can drift from the rig.
##
## ⚠ IT IS A HAND MODEL OF THE RIG AND THE RIG NEVER EXACTLY MAKES IT — measured, 2026-07-29, by
## `test_pixels.gd`'s `test_the_card_mask_is_the_card_the_player_sees` against the REAL animation:
## **the closest `warp` is off by 2.3 to 3.3 art units** at four points of the loop. Two reasons, both
## structural rather than a matter of picking a better number:
##  * the shipped animation moves the four MID-EDGE arms as well (`Arm_Right_2` swings 19 -> 21.3 -> 16,
##    `Arm_Left_2` the other way), so a real card BULGES and PINCHES its long edges; one radial `warp`
##    cannot express that at all.
##  * its corners do not move together — at t=0.15 the top-left arm is 2.9 units out while the
##    top-right is 0.5 — so the real shape is not symmetric and this is.
##
## What that means for a reader: every warp claim made on a harness panel is a claim about THIS shape,
## and the only place a real `CardVisual` is stood up is that PIXELS check. Use it for anything the
## difference could matter to — the mask's own fidelity, above all.
static func star_outline(body: Vector2, warp: float,
		notch: Vector2 = SHIPPED_CORNER_NOTCH) -> PackedVector2Array:
	var h := body * 0.5
	var corners : Array[Vector2] = [Vector2(-h.x, -h.y), Vector2(h.x, -h.y), Vector2(h.x, h.y),
			Vector2(-h.x, h.y)]
	var frac := notch_fraction(body, notch)
	var out := PackedVector2Array()
	for i : int in 4:
		var from : Vector2 = corners[i]
		var to : Vector2 = corners[(i + 1) % 4]
		var back : Vector2 = corners[(i + 3) % 4]
		# The edges alternate horizontal / vertical around the walk, so which of the notch's two
		# dimensions belongs to which of a corner's edges alternates with it.
		var h_first := i % 2 == 0
		out.append_array(corner_points(from * (1.0 + warp), back.lerp(from, 0.75),
				from.lerp(to, 0.25), frac.y if h_first else frac.x,
				frac.x if h_first else frac.y))
		for step : int in [1, 2, 3]:
			out.append(from.lerp(to, float(step) * 0.25))
	return out

## The corner bite every shipped card type but the boosters has, in ART UNITS — one texel, and on a card
## one texel IS one art unit (`test_fx_pixel_is_the_games_pixel` pins that). It is the DEFAULT for
## `star_outline` so the harnesses model a real card without naming a type; the game measures its own
## card's type instead (`CardModifierType.corner_notch`), which is exact for all of them.
const SHIPPED_CORNER_NOTCH := Vector2.ONE

## How far along each of a corner's two edges the notch reaches, as a FRACTION of that edge — the form
## the outline builders need, since a deformed edge is not its rest length. The perimeter points sit at
## quarter points, so a corner's own cell is a quarter of the card in each direction.
static func notch_fraction(body: Vector2, notch: Vector2) -> Vector2:
	return Vector2(notch.x / maxf(body.x * 0.25, 1e-4), notch.y / maxf(body.y * 0.25, 1e-4))

## ONE CORNER OF THE SILHOUETTE, as the three points its clipped art actually has: in along the edge we
## arrive on, across the bite, then out along the edge we leave on. `prev` and `next` are the neighbouring
## perimeter points, `frac` what `notch_fraction` returned.
##
## ⚠ **THE MIDDLE POINT IS THE CELL'S BILINEAR CORNER**, which is what makes this exact under
## deformation and not just at rest: the art's corner texel is a fixed fraction of the corner grid cell
## in each direction, so when the rig stretches or SHEARS that cell the bite follows it — a parallelogram,
## which three points describe exactly.
##
## ⚠ A ZERO notch returns the corner alone, so a booster (whose frame has square corners) keeps a
## 16-point outline and pays nothing.
static func corner_points(corner: Vector2, prev: Vector2, next: Vector2, frac_prev: float,
		frac_next: float) -> PackedVector2Array:
	if frac_prev <= 0.0 or frac_next <= 0.0: return PackedVector2Array([corner])
	var along_prev := (prev - corner) * frac_prev
	var along_next := (next - corner) * frac_next
	return PackedVector2Array([corner + along_prev, corner + along_prev + along_next,
			corner + along_next])

## Find the rig once. Absent (a stripped card in a test, or art without a skeleton) simply means the
## caller falls back to the baked polygon.
func _bind_rig() -> void:
	_rig_root = get_node_or_null("Offset/Visual/Skeleton2D/Bone_Center") as Bone2D
	if not _rig_root: return
	for child : Node in _rig_root.get_children():
		var bone := child as Bone2D
		if bone: _rig_arms.append(bone)
	# THE CORNER BITE, resolved ONCE: it comes from this card's own type frame and never changes at
	# runtime, and `_rig_outline` runs every frame on every card on the board.
	_notch_frac = Vector2.ZERO
	if data and data.type:
		var frame_px := CardModifier.frame_size(CardModifierType.TYPE_TEXTURE,
				CardModifierType.H_FRAMES, CardModifierType.V_FRAMES)
		# Texels into ART UNITS: the size of one of the drawing's own pixels — 1.0 on a card, derived
		# rather than assumed.
		#
		# ⚠ **DIVIDE BY THE INNER RECT, NOT BY `CARD_SIZE`.** This read `CARD_SIZE / frame_px` and was
		# exactly 1.0 only because the type frame WAS the card. It is not any more: the frame is 38x52
		# inside a 40x54 polygon, so the old expression gives (1.0526, 1.0385) and silently inflates
		# every corner notch by 4-5 % — under a comment still asserting the value is 1.0. Nothing about
		# the line looks size-dependent, which is what made it the likeliest thing in this change to be
		# missed. `test_pixels` now asserts the 1.0 directly.
		var inner := CARD_SIZE - Vector2.ONE * ART_OUTLINE * 2.0
		var per_texel := inner / Vector2(maxf(frame_px.x, 1.0), maxf(frame_px.y, 1.0))
		_notch_frac = notch_fraction(CARD_SIZE, data.type.corner_notch() * per_texel)
	# Three points per corner instead of one, wherever there is a bite to describe.
	var extra := 8 if _notch_frac.x > 0.0 and _notch_frac.y > 0.0 else 0
	_rig_outline_buf.resize(_rig_arms.size() + extra)

## The rig's arm tips, in the card's UNSCALED art space.
##
## ⚠ Composed from the bones' own local transforms, NOT from `global_position`: the rig hangs under
## `visual`, which carries the basis3d flip (a basis that goes SINGULAR edge-on) and the bob. Neither
## may reach the effects — ruling 1 — and going through globals would fold both in, so a flipping
## card's silhouette would collapse to a line and take its flames with it.
## ⚠ AND IT CARRIES THE ART'S CORNER BITE. Every shipped type frame clips its corners (`TypePaper` one
## texel), while the RIG is the full rectangle — so an outline of bare arm tips puts one FX pixel of
## flame on nothing at each corner. The bite is emitted as the three points it really is, from the live
## neighbours, so it stretches and shears with the cell (`corner_points`). FX_HANDOFF §0c.5.
func _rig_outline() -> PackedVector2Array:
	var root := _rig_root.transform
	var n := _rig_arms.size()
	if _rig_outline_buf.size() == n:
		for i : int in n:
			_rig_outline_buf[i] = root * _rig_arms[i].position
		return _rig_outline_buf
	# ARMS PER EDGE — four on a 16-arm rig, and the corners are every fourth arm in bake order.
	var per_edge := n / 4
	var at := 0
	for i : int in n:
		var tip := root * _rig_arms[i].position
		if i % per_edge != 0:
			_rig_outline_buf[at] = tip
			at += 1
			continue
		# A CORNER. Its neighbours are the arms either side of it, live, and which of the notch's two
		# dimensions belongs to which edge alternates around the walk exactly as in `star_outline`.
		var prev := root * _rig_arms[(i + n - 1) % n].position
		var next := root * _rig_arms[(i + 1) % n].position
		var h_first := (i / per_edge) % 2 == 0
		for p : Vector2 in corner_points(tip, prev, next,
				_notch_frac.y if h_first else _notch_frac.x,
				_notch_frac.x if h_first else _notch_frac.y):
			_rig_outline_buf[at] = p
			at += 1
	return _rig_outline_buf

## Hand the DEFORMED outline to the effects. Every frame, because the rig can be posed by a jump, a
## spin or a warp at any time; the attachment early-outs when nothing moved, so a settled card costs
## the walk below and no upload.
##
## ⚠ **THIS USED TO SAY "because the rig's animation is on autoplay and a card is never actually at
## rest". THAT IS NO LONGER TRUE** — the idle was cleared (owner: it was only ever on to
## eyeball that the VFX overlay tracked a moving rig; see [[RIG_ANIM]] above). A card with no active
## tween now IS at rest, which makes the early-out fire far more often than the comment assumed.
## ⚠ **There is a real optimisation sitting here and it is deliberately NOT taken:** with the idle
## off, this walk could be skipped entirely while the rig is unposed rather than merely uploading
## nothing. FX performance is PAUSED by owner ruling (VFX.md §6) and PERFORMANCE.md's "78
## AnimationPlayers on autoplay, the rig animation is *always* running" figure is now stale — re-read
## that section before pricing anything here.
func _track_fx_outline() -> void:
	if not fx or _rig_arms.is_empty(): return
	fx.track_outline(_rig_outline())


static func add_child_card_visual(parent:Node,connected_data:CardData, context:DisplayContext, target_control: Control = null) -> CardVisual:
	var card : CardVisual = (CARD_VISUAL.instantiate() as CardVisual).with_data(connected_data)
	card.current_context = context
	card.control_anchor = target_control if target_control else (parent as Control)
	card.recalculate_size()
	#wait for play area containers to update control positions at next frame
	parent.call_deferred("add_child", card)
	return card

func _ready() -> void:
	type.hide()
	rank.hide()
	stamp.hide()
	suit.hide()
	art.hide()
	# FX hangs off OFFSET, never off `visual`: `visual` carries the basis3d flip, which squashes
	# its basis to ZERO at edge-on (:66-71), and the effects' quads must never inherit a singular
	# matrix. Added after `visual`, so it draws above the card's own face while the whole
	# CardVisual subtree stays one unit in CardLayer's draw order. Runtime-only and OWNERLESS: this
	# script is @tool, and an owned child would be written into card_visual.tscn by the editor.
	# THE RIG IS BOUND IN EITHER MODE, because the FX EDITOR previews a REAL card and needs the same
	# outline the game hands over (owner: *"no useless mocks when you can just use actual
	# original scene"*). It is a `get_node_or_null` and a child walk; nothing about it needs a game.
	_bind_rig()
	if not Engine.is_editor_hint():
		fx = FxAttachment.new()
		fx.name = "Fx"
		# Motion effects (embers, the cape) only on the board: they exist for cards that travel
		# and are dropped, and the deck viewer — 50+ cards, all showing their statuses — is the
		# densest screen in the game. The flames and balls themselves are identical everywhere.
		fx.configure(CARD_SIZE, true, FxAttachment.Shape.BOX, FxAttachment.Half.WHOLE,
				current_context == DisplayContext.PLAY_AREA)
		offset.add_child(fx)
		# The real card outline, taken from the STAR RIG rather than from the rest polygon: the rig is
		# what deforms the card, and a silhouette baked once left the flames standing on a shape the
		# card no longer had. Re-read every frame by _track_fx_outline. (The rig no longer autoplays —
		# see RIG_ANIM — but jumps, spins and warps still pose it, so the outline is still live.)
		if _rig_arms.is_empty(): fx.measure_silhouette(type.polygon)
		else: fx.measure_outline(_rig_outline())
		fx.visible = show_front and data != null
		fx.sync(_fx_requests())
		SettingsManager.settings_changed.connect(recalculate_size)
	recalculate_size()
	match data.previous_stage:
		data.Stage.PLAY, data.Stage.ZONE:
			# The anchor may not exist yet (a visual built the same frame as its control), and a
			# viewer/preview visual never gets one at all -- the SAME guard `on_stage_changed()`
			# already puts on this exact call. Without it, a preview card whose previous_stage is
			# PLAY/ZONE threw "Invalid access to property 'global_position' on Nil" whenever ANY
			# CardEnvironment was on screen, which a live `Map` (one itself) makes most of the time.
			if CardEnvironment.CURRENT and is_instance_valid(control_anchor):
				global_position = get_card_control_center(control_anchor)
		data.Stage.DRAW:
			if _game_view():
				global_position = get_control_center(_game_view().deck_ui)
		data.Stage.DISCARD:
			if _game_view():
				global_position = get_control_center(_game_view().discard_ui)
		data.Stage.RULES:
			if _game_view():
				global_position = get_control_center(_game_view().rules_ui)
	# Only a card drawn from the deck ONTO THE BOARD flips into view: it keeps the default
	# face-down basis3d and the floating anim slerps it to front. Everything else — non-draw
	# board cards AND every viewer card (deck/pack/preview), even ones whose previous_stage is
	# DRAW — spawns already showing its resting face (respecting data.flipped). Without this the
	# slerp would flip every card from back to front on init.
	if not (current_context == DisplayContext.PLAY_AREA and data.previous_stage == data.Stage.DRAW):
		basis3d = Basis.looking_at(Vector3(0, 0, -3.5 * (-1 if data.flipped else 1)))
	on_stage_changed()

func recalculate_size() -> void:
	match current_context:
		DisplayContext.DECK_VIEWER:
			card_size = CARD_SIZE * 2#settings().card_scale
			card_separation = CARD_SEPARATION * settings().card_scale
			card_separation_custom = card_separation * settings().card_separation_scale
			scale = Vector2.ONE * 2
		DisplayContext.PLAY_AREA:
			card_size = CARD_SIZE * settings().card_scale
			card_separation = CARD_SEPARATION * settings().card_scale
			card_separation_custom = card_separation * settings().card_separation_scale
			scale = Vector2.ONE * settings().card_scale
		_:
			card_size = CARD_SIZE * settings().card_scale
			card_separation = CARD_SEPARATION * settings().card_scale
			card_separation_custom = card_separation * settings().card_separation_scale
			scale = Vector2.ONE * settings().card_scale

func on_stage_changed() -> void:
	if current_context != DisplayContext.PLAY_AREA: return
	if not data: return
	if data.stage == data.previous_stage: return
	match data.stage:
		data.Stage.PLAY, data.Stage.ZONE:
			#anchor may not exist yet (visual created same frame as its control)
			if not control_anchor or not is_instance_valid(control_anchor): return
			var target_pos := get_card_control_center(control_anchor)
			create_move_tween(target_pos)
			await move_tween.finished
		data.Stage.DRAW:
			if _game_view():
				var target_pos := get_control_center(_game_view().deck_ui)
				create_move_tween(target_pos).tween_callback(queue_free)
		data.Stage.DISCARD:
			if _game_view():
				var target_pos := get_control_center(_game_view().discard_ui)
				create_move_tween(target_pos).tween_callback(queue_free)
		data.Stage.RULES:
			if _game_view():
				var target_pos := get_control_center(_game_view().rules_ui)
				create_move_tween(target_pos).tween_callback(queue_free)

## The active game's view (the UI layer that owns the deck/discard/rules anchors + PlayArea).
## Null when headless (no view) — every caller null-checks, so those visual moves simply skip.
func _game_view() -> GameView:
	var game := CardEnvironment.get_current_game()
	return game.view if game else null

## Where this card's centre sits on its anchor control. Hanging from the control's BOTTOM edge is
## the whole of the shared-bottom-edge rule: a thin strip control then shows the card's bottom
## while the rest of it rises over the card beneath.
func get_card_control_center(control:Control) -> Vector2:
	var y := (control.size.y - card_size.y / 2) if bottom_anchored else (card_size.y / 2)
	return control.global_position + Vector2(control.size.x / 2, y)

func get_control_center(control:Control) -> Vector2:
	return control.global_position + control.size/2

func _process(delta: float) -> void:
	delta_self_moving_logic(delta)
	if floating: delta_floating_anim(delta)
	_track_fx_outline()
	# Gated on an alert being live, so a resting board — which is nearly every card, nearly always —
	# pays one null check rather than five `set_shader_parameter` calls per frame.
	if _alert: _advance_alert(delta)

var rot_delta : float
var y_delta : float
func delta_self_moving_logic(delta:float) -> void:
	# TODO(discard animation): needs a stage check — a card leaving to the discard pile
	# should play a discard animation BEFORE this queue_free, not vanish instantly.
	match current_context:
		DisplayContext.PLAY_AREA:
			#one lookup per frame, not two (N-E2)
			var gv := _game_view()
			if gv and data not in gv.play_area.data_ui: queue_free()
		_:
			if not Engine.is_editor_hint() and (not control_anchor or not is_instance_valid(control_anchor)): queue_free()
	if (not (move_tween and move_tween.is_running())) and control_anchor:
		var target : Vector2 = get_card_control_center(control_anchor)
		if held:
			#where card orients itself relative to mouse
			var offset : int =  card_size.y/2 - card_separation/2
			offset += (held - 1) * card_separation_custom
			target = get_global_mouse_position() + Vector2(0, offset)
		target.y -= y_delta
		var move : Vector2 = target - global_position
		# Only PLAY_AREA cards ease toward their slot — that smooths slot-to-slot moves and the
		# fly-in from the deck/discard/rules pile (initial position seeded in _ready). Every
		# other context (deck/pack viewers, map, preview) is a static display that tracks its
		# anchor exactly, so it never eases in from the origin (no first-card fly-in). The
		# difference is inherent to the context, so it branches on the context, not on a flag.
		# NOTE: PLAY_AREA cards live on PlayArea's CardLayer INSIDE the scroll content, so a
		# scroll shifts card and anchor globals identically — the ease sees no scroll motion
		# and only ever animates genuine anchor-relative travel (no scroll lag).
		if current_context == DisplayContext.PLAY_AREA:
			# lerp is bad, frame dependent — should be a tween when data is moving slots, but
			# something must keep the card attached to its control between moves.
			global_position = target + (global_position - target) * exp(-10 * delta)
		else:
			global_position = target
		
		# Tilt/bob juice reacts to `move` — but only PLAY_AREA cards actually travel. Viewer
		# cards snap straight to their anchor (above), so their one-frame settle would otherwise
		# read as a big `move.x` and spin them into place. Gate the juice to PLAY_AREA.
		if current_context == DisplayContext.PLAY_AREA and can_rot_anim and data and data.stage != data.Stage.ZONE:
			y_delta = lerpf(y_delta, move.y, 15 * delta)
			y_delta = clampf(y_delta, -4, 4)
			
			rot_delta = lerpf(rot_delta, move.x, 15 * delta)
			var clamp_degree : float = sqrt(abs(rot_delta) as float) * 5
			rot_delta = clampf(rot_delta, -clamp_degree, clamp_degree)
			rotation_degrees = rot_delta

func delta_floating_anim(delta:float) -> void:
	var x : float = sin(num + float(Time.get_ticks_msec()) / 2000) * (0.3 if hover else 0.6)
	var y : float = cos(num + float(Time.get_ticks_msec()) / 2000) * (0.3 if hover else 0.6)
	
	if hover:
		var mouse_pos : Vector2 = -get_local_mouse_position().normalized()
		x += mouse_pos.x/1.5
		y += mouse_pos.y/1.5
	var bobbing := sin(2 * num + float(Time.get_ticks_msec()) / 2000)
	if data and data.stage == data.Stage.ZONE:
		x = 0
		y = 0
		bobbing = 0
	var drift : Vector3 = Vector3(x, y, -3.5 * (-1 if data and data.flipped else 1))
	basis3d = basis3d.slerp(Basis.looking_at(drift), 6.5 * delta)
	visual.position.y = lerpf(visual.position.y, bobbing, 10 * delta)

func with_data(data:CardData) -> CardVisual:
	self.data = data  # the setter wires data_changed/stage_changed (and unwires on swap)
	return self

func reset_tween(tween:Tween) -> void:
	if tween and tween.is_running():
		tween.custom_step(INF)

func create_move_tween(target_pos:Vector2) -> Tween:
	reset_tween(move_tween)
	var delay := CardEnvironment.CURRENT.get_delay()
	move_tween = create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN_OUT)
	move_tween.tween_property(self, "global_position", target_pos, delay*0.3)
	if target_pos.x - global_position.x > 10:
		move_tween.parallel().tween_property(self, "rotation_degrees", 10, delay*0.2)
	elif global_position.x - target_pos.x > 10:
		move_tween.parallel().tween_property(self, "rotation_degrees", -10, delay*0.2)
	#tween.set_ease(Tween.EASE_OUT)
	move_tween.tween_property(self, "rotation_degrees", 0, delay*0.1)
	return move_tween

func anim_jump() -> float:
	# offset (@onready) is null until this visual's _ready runs; a freshly built board adds
	# visuals deferred, so guard rather than tween a null target (rp_target null error).
	if not offset: return 0.0
	reset_tween(move_tween)
	# Phase lengths are PlayerSettings fractions of the live delay (tunable, and every animation
	# respects the pacing/compression — nothing runs on a fixed wall-clock length).
	var delay := CardEnvironment.CURRENT.get_delay()
	var s := SettingsManager.settings
	move_tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	move_tween.tween_callback(func()->void: floating = false)
	move_tween.tween_property(offset, "position:y", -CARD_JUMP_RISE,
			delay * s.card_jump_raise_fraction)
	move_tween.tween_property(offset, "scale", Vector2.ONE * 1.15,
			delay * s.card_jump_pulse_fraction)
	move_tween.tween_property(offset, "scale", Vector2.ONE,
			delay * s.card_jump_settle_fraction)
	return delay * s.card_jump_raise_fraction

func anim_spin() -> float:
	# Mirrors anim_jump (:342) but drives rotation, so it COMPOSES with a concurrent jump
	# (offset:y vs offset:rotation are independent properties). Guard the null offset the same.
	# A held spin loop owns the rotation — never custom_step an INFINITE tween (it won't end).
	if not offset or _spin_holding: return 0.0
	reset_tween(spin_tween)
	var delay := CardEnvironment.CURRENT.get_delay()
	spin_tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	spin_tween.tween_property(offset, "rotation", TAU, delay * .6)
	spin_tween.tween_callback(func()->void: offset.rotation = 0.0)
	return delay * .6

## Held-spin state (PropLayer SPIN hold): true while the looping spin owns offset.rotation.
var _spin_holding : bool = false

## Continuous spin (owner spec 2026-07-13): one full revolution per pulse, LOOPING until
## anim_spin_stop — a stream of spin-hinting props keeps the card turning instead of
## restarting a one-shot per prop. Self-guarding: calling again while held is a no-op.
func anim_spin_start() -> void:
	if not offset or _spin_holding: return
	_spin_holding = true
	if spin_tween and spin_tween.is_running(): spin_tween.kill()
	# Floor the revolution time: get_delay() can be 0 (undo-cancel snap / compression floor),
	# and a zero-duration LOOPING tween trips Godot's infinite-loop guard every frame.
	var delay := maxf(CardEnvironment.CURRENT.get_delay(), 0.2)
	spin_tween = create_tween().set_loops().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	spin_tween.tween_property(offset, "rotation", TAU, delay * .6).from(0.0)

## Wind the held spin down: kill the loop and close the CURRENT revolution once, then rest.
func anim_spin_stop() -> void:
	if not _spin_holding: return
	_spin_holding = false
	if not offset: return
	if spin_tween and spin_tween.is_running(): spin_tween.kill()
	var delay := maxf(CardEnvironment.CURRENT.get_delay(), 0.2)
	spin_tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	spin_tween.tween_property(offset, "rotation", TAU, delay * .3)
	spin_tween.tween_callback(func()->void: offset.rotation = 0.0)

func anim_reset() -> void:
	if not offset: return
	reset_tween(move_tween)
	var delay := CardEnvironment.CURRENT.get_delay()
	move_tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	move_tween.tween_property(offset, "position:y", 0, delay * .4)
	move_tween.tween_callback(func()->void: floating = true)

# --- EDITOR BAKE INSPECTOR UTILITIES ---
@export_group("Mesh Generation Configuration")
@export var target_polygon_node: Polygon2D
@export var bake_sample_texture: Texture2D
@export var bake_h_frames: int = 8
@export var bake_v_frames: int = 8
## Default horizontal cut lines set cleanly to 1
@export var subdivisions_x: int = 1
## Default vertical cut lines set cleanly to 1
@export var subdivisions_y: int = 1

@export_tool_button("Bake Selected Mesh & UVs") 
var editor_bake_mesh : Callable = func() -> void:
	if not target_polygon_node or not bake_sample_texture:
		printerr("CardVisual Tool: Please assign a target node and sample texture!")
		return
	generate_editor_mesh(target_polygon_node, bake_sample_texture, bake_h_frames, bake_v_frames, subdivisions_x, subdivisions_y)
	print("CardVisual Tool: Successfully baked ", target_polygon_node.name, " diamond grid structure!")

## Bakes a pristine diamond grid while isolating internal vertices from the perimeter chain.
##
## ⚠ **THE POLYGON IS THE FRAME PLUS THE OUTLINE'S MARGIN, NOT THE FRAME.** This built the mesh at
## exactly frame size, which is correct for a polygon that draws nothing but its art and WRONG for
## every polygon on a card, because `Shaders/outline.gdshader` can only write inside its own polygon:
## with no margin there is nowhere for the rim to go, and `CardOutline.frame_polygon` would stretch the
## art over the whole box instead. Re-baking without this pad is therefore a silent way to delete the
## outline from one element and make its art 25 % too big — which is exactly the kind of thing that
## gets found weeks later, so the pad lives here rather than in a checkbox someone has to remember.
func generate_editor_mesh(poly: Polygon2D, tex: Texture2D, h_f: int, v_f: int, subdiv_x: int, subdiv_y: int) -> void:
	poly.texture = tex

	var sheet_size := tex.get_size()
	var frame_w := sheet_size.x / h_f + ART_OUTLINE * 2.0
	var frame_h := sheet_size.y / v_f + ART_OUTLINE * 2.0

	var x_segments := subdiv_x + 1
	var y_segments := subdiv_y + 1
	
	var perimeter_vertices := PackedVector2Array()
	var internal_vertices := PackedVector2Array()
	var triangles: Array[PackedInt32Array] = []
	
	# --- STEP 1: COLLECT AND SEPARATE VERTICES ---
	# To make Godot happy, we map structural grid loops into memory arrays first
	var grid_pts: Array[Array] = []
	grid_pts.resize(y_segments + 1)
	
	for y in range(y_segments + 1):
		grid_pts[y] = []
		grid_pts[y].resize(x_segments + 1)
		var t_y := float(y) / y_segments 
		var pos_y : float = lerp(-frame_h / 2.0, frame_h / 2.0, t_y)
		
		for x in range(x_segments + 1):
			var t_x := float(x) / x_segments
			var pos_x : float = lerp(-frame_w / 2.0, frame_w / 2.0, t_x)
			grid_pts[y][x] = Vector2(pos_x, pos_y)

	# Append the exact 4 outer-most perimeter boundaries FIRST in clockwise winding order
	perimeter_vertices.append(grid_pts[0][0] as Vector2)                       # Top-Left
	perimeter_vertices.append(grid_pts[0][x_segments] as Vector2)              # Top-Right
	perimeter_vertices.append(grid_pts[y_segments][x_segments] as Vector2)     # Bottom-Right
	perimeter_vertices.append(grid_pts[y_segments][0] as Vector2)              # Bottom-Left

	# Gather all other internal line splits safely into the internal vertex list array
	for y in range(y_segments + 1):
		for x in range(x_segments + 1):
			# Skip the 4 corners we already manually saved above
			if (y == 0 and x == 0) or (y == 0 and x == x_segments) or \
			   (y == y_segments and x == x_segments) or (y == y_segments and x == 0):
				continue
			internal_vertices.append(grid_pts[y][x] as Vector2)

	# Add cell quadrant centers into the internal vertices array to establish the "X" cuts
	var cell_center_start_idx := 4 + internal_vertices.size()
	var centers: Array[Vector2] = []
	
	for y in range(y_segments):
		for x in range(x_segments):
			var c_pos : Vector2 = (grid_pts[y][x] + grid_pts[y][x+1] + grid_pts[y+1][x] + grid_pts[y+1][x+1]) / 4.0
			centers.append(c_pos)
			internal_vertices.append(c_pos)

	# Merge everything into the primary polygon vertex buffer
	var final_vertices := perimeter_vertices + internal_vertices
	
	# O(1) vertex index lookup (E11 — was a linear scan per corner, O(V^2) over the bake).
	# Exact Vector2 keys are safe: every queried point is bit-identical to its grid_pts source.
	var v_index : Dictionary[Vector2, int] = {}
	for i in range(final_vertices.size()):
		if final_vertices[i] not in v_index:
			v_index[final_vertices[i]] = i
	var get_v_idx := func(pos: Vector2) -> int:
		return v_index.get(pos, 0)

	# --- STEP 2: DIAMOND "X" TRIANGULATION ---
	var center_counter := 0
	for y in range(y_segments):
		for x in range(x_segments):
			var tl : int = get_v_idx.call(grid_pts[y][x] as Vector2)
			var tr : int = get_v_idx.call(grid_pts[y][x+1] as Vector2)
			var bl : int = get_v_idx.call(grid_pts[y+1][x] as Vector2)
			var br : int = get_v_idx.call(grid_pts[y+1][x+1] as Vector2)
			var cc := cell_center_start_idx + center_counter
			center_counter += 1
			
			triangles.append(PackedInt32Array([tl, tr, cc])) # Top Triangle
			triangles.append(PackedInt32Array([tr, br, cc])) # Right Triangle
			triangles.append(PackedInt32Array([br, bl, cc])) # Bottom Triangle
			triangles.append(PackedInt32Array([bl, tl, cc])) # Left Triangle

	poly.polygon = final_vertices
	poly.polygons = triangles
	poly.internal_vertex_count = internal_vertices.size()

	# --- STEP 3: ASSIGN FIXED BASELINE UV MAP (FRAME 0) ---
	# The padded window of frame 0, so this baseline agrees with what `CardOutline.frame_polygon`
	# writes at runtime: the frame's own texels sit in the middle and the polygon's outer ring hangs
	# `ART_OUTLINE` texels OUTSIDE the sheet on the top and left. That overhang is intentional and
	# harmless — the shader's frame clamp reads everything beyond the frame as empty either way.
	var initial_uvs := PackedVector2Array()
	initial_uvs.resize(final_vertices.size())
	for i in range(final_vertices.size()):
		var p := final_vertices[i]
		var norm_x := (p.x / frame_w) + 0.5
		var norm_y := (p.y / frame_h) + 0.5
		initial_uvs[i] = Vector2(norm_x * frame_w, norm_y * frame_h) - Vector2.ONE * ART_OUTLINE
	poly.uv = initial_uvs
	poly.notify_property_list_changed()

# --- STAR SKELETON SETUP AND BINDING UTILITIES ---
@export_group("Skeleton Automation Configuration")
## Number of progressive bone nodes dividing each directional arm of the star (1 = 8 bones, 2 = 16 bones)
@export var arm_segments: int = 1
## Changes how many structural arms the star splits into based on edge segments (1 = 8 arms, 2 = 12 arms, 3 = 16 arms)
@export var edge_subdivisions: int = 1

@export_tool_button("Generate Star Skeleton & Bind")
var editor_setup_skeleton : Callable = func() -> void:
	var visual_container := get_node_or_null("Offset/Visual")
	if not visual_container or visual_container.get_child_count() == 0:
		printerr("CardVisual Tool: 'Offset/Visual' path empty or missing!")
		return
	
	# 1. Dynamically scan vertices to determine the spatial bounding box boundaries
	var highest_y: float = INF
	var lowest_y: float = -INF
	var max_x: float = -INF
	var polygon_layers: Array[Polygon2D] = []
	
	for child in visual_container.get_children():
		if child is Polygon2D:
			polygon_layers.append(child as Polygon2D)
			for vertex in (child as Polygon2D).polygon:
				var card_local_pos := to_local((child as Polygon2D).to_global(vertex))
				highest_y = min(highest_y, card_local_pos.y)
				lowest_y = max(lowest_y, card_local_pos.y)
				max_x = max(max_x, abs(card_local_pos.x))

	# Compute the midpoint of the card geometry bounds to find the absolute center
	var half_height := (lowest_y - highest_y) / 2.0
	var center_pos := Vector2(0, highest_y + half_height)
	
	var radius_vertical := half_height
	var radius_horizontal := max_x
	
	# Define the four absolute corner poles of our bounding frame box
	var tl := Vector2(-radius_horizontal, highest_y)
	var tr := Vector2(radius_horizontal, highest_y)
	var br := Vector2(radius_horizontal, lowest_y)
	var bl := Vector2(-radius_horizontal, lowest_y)

	# 2. Reset and build the clean Skeleton2D node layer.
	#
	# ⚠ **UNDER `Offset/Visual`, BESIDE THE POLYGONS — NOT UNDER THE ROOT.** This looked the skeleton up
	# at `"Skeleton2D"` and re-added it with `add_child(self)`, while the shipped scene keeps it at
	# `Offset/Visual/Skeleton2D` and `_bind_rig` looks it up at
	# `Offset/Visual/Skeleton2D/Bone_Center`. So a re-bake found no existing skeleton to replace, left
	# the real one in place, and parented a SECOND one at the root — where it inherits neither the bob
	# nor the basis3d flip the polygons ride, and where `_bind_rig` never sees it.
	#
	# ⚠ It still `queue_free`s the outgoing skeleton, which orphans both animations' track paths until
	# the regenerated bone names match. They do at `edge_subdivisions = 3`; at any other value the
	# animation tracks must be re-pointed by hand.
	var skeleton: Skeleton2D = visual_container.get_node_or_null("Skeleton2D") as Skeleton2D
	if skeleton:
		# Renamed before freeing: `queue_free` is deferred, so the outgoing node still holds the name
		# when the new one is added and Godot would silently make the new one "Skeleton2D2".
		skeleton.name = "Skeleton2D_outgoing"
		skeleton.queue_free()
	skeleton = Skeleton2D.new()
	skeleton.name = "Skeleton2D"
	visual_container.add_child(skeleton)
	skeleton.owner = get_tree().edited_scene_root

	# 3. CREATE THE SINGLE SHARED CENTRAL CORE ROOT BONE
	var center_bone := Bone2D.new()
	center_bone.name = "Bone_Center"
	center_bone.position = center_pos
	center_bone.rotation = 0.0
	center_bone.set_length(10.0)
	
	skeleton.add_child(center_bone)
	center_bone.owner = get_tree().edited_scene_root
	center_bone.rest = center_bone.transform

	# 4. GENERATE DIRECTIONAL TARGET PATHS BY SUBDIVIDING RECTANGLE EDGES
	var directions: Array[Vector2] = []
	var arm_names: Array[String] = []
	
	# Total steps per border edge wall
	var wall_steps := edge_subdivisions + 1
	
	# Edge A: Top Wall (Left to Right)
	for i in range(wall_steps):
		var target := tl.lerp(tr, float(i) / wall_steps)
		directions.append(target - center_pos)
		if i == 0:
			arm_names.append("TopLeft")
		elif edge_subdivisions == 1:
			arm_names.append("Top")
		else:
			arm_names.append("Top_" + str(i))
		
	# Edge B: Right Wall (Top to Bottom)
	for i in range(wall_steps):
		var target := tr.lerp(br, float(i) / wall_steps)
		directions.append(target - center_pos)
		if i == 0:
			arm_names.append("TopRight")
		elif edge_subdivisions == 1:
			arm_names.append("Right")
		else:
			arm_names.append("Right_" + str(i))
		
	# Edge C: Bottom Wall (Right to Left)
	for i in range(wall_steps):
		var target := br.lerp(bl, float(i) / wall_steps)
		directions.append(target - center_pos)
		if i == 0:
			arm_names.append("BottomRight")
		elif edge_subdivisions == 1:
			arm_names.append("Bottom")
		else:
			arm_names.append("Bottom_" + str(i))
		
	# Edge D: Left Wall (Bottom to Top)
	for i in range(wall_steps):
		var target := bl.lerp(tl, float(i) / wall_steps)
		directions.append(target - center_pos)
		if i == 0:
			arm_names.append("BottomLeft")
		elif edge_subdivisions == 1:
			arm_names.append("Left")
		else:
			arm_names.append("Left_" + str(i))

	# Setup explicit tracking array sets for structural weight calculations
	var bone_paths: Array[String] = ["Bone_Center"]
	var bone_nodes: Array[Bone2D] = [center_bone]

	# 5. GENERATE THE DYNAMIC STAR ARMS AS NESTED HIERARCHIES
	for arm_idx in range(directions.size()):
		var dir_vector := directions[arm_idx]
		var total_arm_length := dir_vector.length()
		var segment_length := total_arm_length / float(arm_segments)
		
		var previous_joint: Node = center_bone
		var path_accumulator := "Bone_Center"
		
		for segment_idx in range(arm_segments):
			var arm_bone := Bone2D.new()
			var b_name := ""
			
			if segment_idx == 0:
				b_name = "Arm_" + arm_names[arm_idx]
				arm_bone.position = dir_vector / float(arm_segments)
			else:
				b_name = "Arm_" + arm_names[arm_idx] + "_Seg_" + str(segment_idx)
				arm_bone.position = dir_vector / float(arm_segments)
				
			arm_bone.name = b_name
			arm_bone.rotation = 0.0
			arm_bone.set_length(segment_length)
			
			path_accumulator += "/" + b_name
			bone_paths.append(path_accumulator)
			
			previous_joint.add_child(arm_bone)
			arm_bone.owner = get_tree().edited_scene_root
			arm_bone.rest = arm_bone.transform
			
			bone_nodes.append(arm_bone)
			previous_joint = arm_bone

	# 6. COMPUTE DYNAMIC PROXIMITY WEIGHT MATRICES ACROSS ALL LAYERS
	for poly in polygon_layers:
		poly.skeleton = poly.get_path_to(skeleton)
		poly.clear_bones()
		
		var vertices := poly.polygon
		if vertices.is_empty(): continue
		
		# Pre-allocate weight matrices matching layout tracks
		var weights_by_bone: Array[PackedFloat32Array] = []
		for b_idx in range(bone_paths.size()):
			var w_arr := PackedFloat32Array()
			w_arr.resize(vertices.size())
			w_arr.fill(0.0)
			weights_by_bone.append(w_arr)
			
		for v_idx in range(vertices.size()):
			var v_glob := poly.to_global(vertices[v_idx])
			
			var distance_factors := PackedFloat32Array()
			distance_factors.resize(bone_paths.size())
			var running_weight_denominator := 0.0
			
			# Sample absolute spatial proximity lengths across all created joints
			for b_idx in range(bone_paths.size()):
				var dist := v_glob.distance_to(bone_nodes[b_idx].global_position)
				if dist < 0.1: dist = 0.1
				
				var falloff_factor := 1.0 / (dist * dist)
				distance_factors[b_idx] = falloff_factor
				running_weight_denominator += falloff_factor
				
			# Normalize ratios to sum up to 1.0 per vertex point
			for b_idx in range(bone_paths.size()):
				weights_by_bone[b_idx][v_idx] = distance_factors[b_idx] / running_weight_denominator

		# Add paths and calculated weight arrays cleanly through the engine profile structure
		for b_idx in range(bone_paths.size()):
			poly.add_bone(NodePath(bone_paths[b_idx]), weights_by_bone[b_idx])
			
		poly.notify_property_list_changed()
	print("CardVisual Tool: Custom ", directions.size(), "-Way Star rig generated with optimized naming schemes!")

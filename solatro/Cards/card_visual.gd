@tool
extends Node2D
class_name CardVisual

const CARD_VISUAL = preload("uid://bynh2btoahe5i")

## The card face as the sheet draws it - one frame of card_types.png, in art units (= source texels).
const CARD_ART_SIZE := Vector2(38, 52)
## The rim `Shaders/outline.gdshader` paints, in art units. Not a second opinion — `CardOutline` owns it.
const ART_OUTLINE := CardOutline.WIDTH
#⚠ THE MASK AND THE DRAWN EDGE AGREE ONLY BECAUSE THE RIM EXACTLY FILLS THE POLYGON, AND NOTHING
#ELSE IN THE CODE SAYS SO. Switch the outline off and the art shrinks to 38x52 while the
#geometry-derived mask still says 40x54, rooting every flame one art unit off on all four sides.

#⚠ It is NOT a one-line "remove the outline": the 16 bones are AUTHORED in card_visual.tscn, so a
#real removal is a scene edit plus a skin re-bake. This constant makes the shader and the mask
#follow; the skeleton cannot.

#⚠ Do not read the mask from alpha instead. The rig is what DEFORMS, and alpha can describe the
#shape at rest but not where it went when Arm_TopLeft swings out 26 %.

## The DRAWN card: 40x54, stated as art + rim so the shader and the FX mask move together.
const CARD_SIZE := CARD_ART_SIZE + Vector2.ONE * ART_OUTLINE * 2.0
#Stacks grow UPWARD, so the visible strip of a covered card is its BOTTOM band and that card's pip
#row has to fit inside it. The Rank/Suit polygons sit at y = 18 with a +/-5 extent and the bottom
#edge at 27, so the pitch is 4 (margin) + 10 (the outlined pip) + 2 (idle-rig clearance).

#⚠ IT IS A BOARD-LAYOUT NUMBER, NOT JUST A CARD ONE: it is the board's row pitch, so moving it
#moves every stacked card and every prop anchored to a slot. Only the 2 is a choice (owner: *"pip
#added 2 pixels, need 2 unit clearance to account for animations"*); test_outline re-derives the rest.

## The strip of a covered card that stays visible in a stack, in art units.
const CARD_SEPARATION : int = 16
#Props a card jumps INTO (the hoop) ride at exactly this height so the two CENTRES coincide, which
#is what PropVisual.rides_card_jump reads jump_rise_play for. Hardcode it in either place and the
#card jumps through the side of the hoop.

## How far anim_jump lifts a card, in UNSCALED units.
const CARD_JUMP_RISE := CARD_SIZE.y / 5.0

#NAMED HERE BECAUSE IT IS NOT ON `autoplay`: the idle is off in the shipped card (owner: it was only
#ever on to eyeball that the VFX overlay tracked a moving rig), and test_pixels, fx_editor,
#outline_atlas and spotlight_tool each need the animation's NAME so they can seek it themselves.

#⚠ THOSE FOUR SITES GUARD ON `if ap.autoplay != ""`, so without this constant the seek is skipped,
#the card stays at its REST pose, and the mask check goes on passing while measuring the one pose
#where the corner model is exact by construction - the case that proves nothing.

#The deformed-pose signature to check after any change here is the suite's own printout: worst
#edge/corner 0.00/0.00 at t=0.00, 0.48/1.21 at t=0.15, 1.50/2.45 at t=0.30. All-zero everywhere
#means the rig stopped moving.

## The rig's idle ("wiggle") animation in card_visual.tscn.
const RIG_ANIM : StringName = &"new_animation_2"

@export_tool_button("Update Visual") var editor_update_visual : Callable = update_visual

enum DisplayContext {PLAY_AREA, MAP, DECK_VIEWER, PREVIEW}
@export var current_context: DisplayContext = DisplayContext.PLAY_AREA
var control_anchor: Control = null
#A grid cell's stack grows UPWARD and every card in a row shares a BOTTOM edge, so a covered card
#shows its bottom strip, which is where the pips are. The Entrance still fans DOWNWARD from its
#control tops, and PlayArea sets this per card when it binds the slot.

## Which EDGE of `control_anchor` the card hangs from.
var bottom_anchored := false

## False while the opening deal has not reached this cell yet, which is the whole of the reveal.
var mark_drawn := true:
	set(value):
		if mark_drawn == value: return
		mark_drawn = value
		update_visual()

var card_size : Vector2
var card_separation: int
var card_separation_custom: int

#NOT `SettingsManager.settings`: this script is @tool and the FX editor instantiates no autoloads
#while standing up a REAL card (owner: *"no useless mocks when you can just use actual original
#scene"*), so every settings read on the construction path has to survive their absence.

#⚠ ONE ACCESSOR, DELEGATED. FxAttachment is the right home because a card already depends on it
#and it depends on no host; a second copy leaves the editor holding TWO PlayerSettings, tuning
#fx_intensity against one object while the card it previews sizes itself against the other.
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
#The jump lives on `offset`, inside the card root's card_scale, so anything outside the card -
#PropLayer - has to scale it the same way to line up.

## CARD_JUMP_RISE in SCREEN pixels.
static var card_jump_rise_play : float:
	get():
		return CARD_JUMP_RISE * settings().card_scale

var focused : bool = false:
	set(value):
		focused = value
		if focused: modulate = Color(1.825, 1.825, 1.825)
		else: modulate = Color(1.0, 1.0, 1.0)
#This visual follows exactly ONE data, so the setter drops the old resource's connections on a swap:
#otherwise a re-purposed resource goes on updating a visual that no longer shows it.
@export var data : CardData:
	set(value):
		if data == value: return
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

#@onready polygon nodes only exist once ready, so the await comes BEFORE the branch: deciding first
#and awaiting inside a branch lets an early call resume into a now-stale branch and clobber a face
#already set during _ready.

#⚠ FX DRAWS OUTSIDE THE SILHOUETTE, so it is gated on show_front - a hidden card must reveal zero
#information (owner). This is the one deliberate exception to "no visual jumps": show_front flips at
#the basis3d midpoint, when the card is edge-on and a sliver, so the cut is invisible.

#The pip keeps its OWN colours, its sheet being authored in the palette; only suit-agnostic art is
#recoloured to the suit's palette entry. A suitless card falls back to the sheet's own colours
#through fill_texture - never `material = null`, which would take the rim with it.
func update_visual() -> void:
	if not is_node_ready():
		await ready
	if fx:
		fx.visible = show_front and data != null
		fx.sync(_fx_requests())
	if show_front and data:
		if data.rank:
			data.rank.set_texture(rank)
			rank.show()
		else: rank.hide()
		if data.suit:
			data.suit.set_texture(suit)
			data.suit.set_material(rank)
			suit.show()
		else:
			suit.hide()
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
		else: art.hide()

	else:
		rank.hide()
		stamp.hide()
		suit.hide()
		art.hide()

		CardOutline.frame_polygon(
			type,CardModifierType.TYPE_TEXTURE,
			CardModifierType.H_FRAMES,
			CardModifierType.V_FRAMES,
			1)
		CardOutline.fill_texture(type)
		type.show()
	_hold_mark_back()
	_push_outline_ink()

# A MARK IS PRINTED ON THE CELL'S OWN ZONE CARD, so it rides the polygons a played card's rank and
# suit ride. Held back rather than redrawn: the opening reveal deals a cell by letting its printed
# properties appear, and the cell frame under them is never touched.
func _hold_mark_back() -> void:
	if mark_drawn: return
	for poly : Polygon2D in [rank, stamp, suit, art]:
		poly.hide()

#⚠ THIS INVERTS WHO OWNS THE MATERIAL, and that is the structural half of the feature. A modifier
#still sets its own polygon's TEXTURE and FILL, which are facts about the element; the outline
#colour is a fact about the CARD, so it is resolved once here instead of five times over.

#The value comes from the card's TYPE, because the type is the card's whole face and the ink has to
#work against it. A card with no type falls back to the shared `art_outline` role, which is what an
#unauthored type answers with anyway.
func _push_outline_ink() -> void:
	var style := outline_style()
	CardOutline.set_rim(type, style, CARD_SIZE)
	CardOutline.set_rim(rank, _rim_of(MarkMatch.Property.RANK, style), CARD_SIZE)
	CardOutline.set_rim(suit, _rim_of(MarkMatch.Property.SUIT, style), CARD_SIZE)
	CardOutline.set_rim(art, _rim_of(MarkMatch.Property.TALENT, style), CARD_SIZE)
	CardOutline.set_rim(stamp, _rim_of(MarkMatch.Property.HAT, style), CARD_SIZE)
	_push_alert()

#SET TOGETHER: a mask with no ink draws nothing and an ink with no mask has nothing to draw. The
#board re-derives both on every refresh, so a rebuild restores them and an undo leaves nothing.
## Which of this card's elements wear the match rim, and in which ink -- a MarkMatch.Property mask.
func set_match_rim(properties : int, palette_index : int) -> void:
	if matched_properties == properties and match_rim_index == palette_index: return
	matched_properties = properties
	match_rim_index = palette_index
	update_visual()

var matched_properties : int = 0
var match_rim_index : int = -1

# The rim ONE element draws: the card's own, or the match ink when that element is one of the
# properties agreeing with its cell's mark.
func _rim_of(property : int, style : OutlineStyle) -> OutlineStyle:
	if not (matched_properties & property): return style
	return _match_style(match_rim_index)

# THE SHIPPED RIM IN ANOTHER INK, built once per ink: a mark's own style draws no rim at all, so an
# element that lights has to take a width back as well as a colour.
static func _match_style(palette_index : int) -> OutlineStyle:
	if not _match_styles.has(palette_index):
		var style : OutlineStyle = CardOutline.STYLE.duplicate()
		style.outline_index = palette_index
		_match_styles[palette_index] = style
	return _match_styles[palette_index]

static var _match_styles : Dictionary[int, OutlineStyle] = {}

#THIS CARD'S OUTLINE STYLE - its TYPE's, or the shipped default when it has no type. The type owns
#it because the type is the card's face and the ink's job is to read against that face.
func outline_style() -> OutlineStyle:
	if data and data.type: return data.type.outline_style()
	return CardOutline.STYLE

#⚠ RE-DERIVED, NOT TOGGLED (see CardModifierStatus.alert_request). Because this runs on every
#refresh and reads the whole status list, an alert whose status was removed, merged away or rewound
#is already off, and adding a "stop alerting" method would reintroduce exactly that leak.

#The shader runs ONE kind at a time, so when several statuses alert together the LAST declared wins,
#the status list being ordered and the order the card's own. The shimmer is declared by no status,
#so it yields to any status that is alerting.

#The phase is parked at rest so a card that alerted and stopped is bit-identical to one that never
#did, and a shimmer parks it too, not being a status alert. Pushed either way, so a card built
#mid-drift opens on the phase the board is already running.
func _push_alert() -> void:
	var reqs := _alert_requests()
	_alert = reqs[reqs.size() - 1] if not reqs.is_empty() else _shimmer_request()
	var style := outline_style()
	var elements := _alert_elements()
	for poly : Polygon2D in elements:
		CardOutline.set_alert(poly, _alert_of(elements[poly]), style)
	if not _card_alert(): _alert_clock = 0.0
	_push_alert_clock()

#THE FIVE POLYGONS AND THE PRINTED PROPERTY EACH ONE DRAWS. The card frame draws none, so it asks
#with 0 and takes the card's own alert -- the per-element shimmer is a fact about a printed slot.
func _alert_elements() -> Dictionary[Polygon2D, int]:
	return {type: 0, rank: MarkMatch.Property.RANK, suit: MarkMatch.Property.SUIT,
			art: MarkMatch.Property.TALENT, stamp: MarkMatch.Property.HAT}

# THE ACTIVATED RIM IS THE ONE THAT MOVES: an element wearing the realized ink drifts along the
# style's ramp, whose first entry IS that ink, so a rim at rest and a rim at phase 0 are one colour.
func _activated(property : int) -> bool:
	return (matched_properties & property) != 0 \
			and match_rim_index == PaletteDB.ROLES.match_rim_active

# The card's alert as its non-matching elements run it. The shimmer is per ELEMENT, so it is dropped
# here rather than lighting the four elements that agreed with nothing.
func _card_alert() -> CardAlert:
	if _alert and _alert.kind == CardOutline.Alert.SHIMMER: return null
	return _alert

# The alert ONE element runs: the shimmer while it wears the activated match rim, else the card's.
func _alert_of(property : int) -> CardAlert:
	if _activated(property): return _SHIMMER
	return _card_alert()

# The shimmer as the card's own alert, which is what advances the phase in `_process`. Null unless
# some element is wearing the activated rim -- a card with none pays nothing for this.
func _shimmer_request() -> CardAlert:
	return _SHIMMER if _activated(matched_properties) else null

# ONE SHARED REQUEST FOR THE WHOLE GAME: a shimmer names no colour, tempo or thickness of its own, so
# every activated rim is asking for exactly the same thing and a per-element copy would say nothing.
static var _SHIMMER : CardAlert = CardAlert.shimmer()

#Every outline alert this card's statuses ask for, in status order. The alert twin of _fx_requests,
#and generic in the same way: CardVisual never names an alert.
func _alert_requests() -> Array[CardAlert]:
	var reqs : Array[CardAlert] = []
	if not data: return reqs
	for status : CardModifierStatus in data.statuses:
		reqs.append_array(status.alert_request())
	return reqs

func _push_alert_clock() -> void:
	var elements := _alert_elements()
	for poly : Polygon2D in elements:
		CardOutline.set_clock(poly, _clock_of(_alert_of(elements[poly])))

#THE PHASE ONE ELEMENT READS: the board-wide one for a shimmer, this card's own for the other kinds.
func _clock_of(alert : CardAlert) -> float:
	if alert and alert.kind == CardOutline.Alert.SHIMMER: return _shimmer_clock
	return _alert_clock

#The alert currently running on this card's outline, or null. Null is the overwhelmingly common case
#and is what makes the per-frame cost of this feature one null check on a resting board.
var _alert : CardAlert = null
## This card's GLARE or THROB phase, in TURNS -- one bounce per unit; the shader takes `fract()`.
var _alert_clock : float = 0.0

#The phase advances over a period that is a FRACTION OF THE LIVE DELAY, so the cue quickens with act
#compression exactly as the cascade it is announcing does.

#⚠ It does NOT also multiply by FxAttachment.pacing(): pacing() IS base_delay / get_delay(), so a
#period already built from get_delay() would take the same compression twice and the alert would
#race the board it is pacing against.
func _advance_alert(delta : float) -> void:
	var delay : float = settings().base_delay
	if CardEnvironment.CURRENT: delay = CardEnvironment.CURRENT.get_delay()
	if _shimmer_request(): _advance_shimmer(delta, delay)
	if _alert.kind != CardOutline.Alert.SHIMMER:
		_alert_clock += delta / _alert_period(_alert, outline_style(), delay)
	_push_alert_clock()

#The period is this alert's own fraction of the live delay when it named one, else the style's --
#glare, throb and shimmer read different fields, being different cues. Floored because get_delay()
#reaches zero under the compression floor and on an undo-cancel snap, which would NaN the uniform.
static func _alert_period(alert : CardAlert, style : OutlineStyle, delay : float) -> float:
	return maxf(alert.resolved_period(style) * delay, 0.05)

#ONE PHASE FOR EVERY SHIMMER ON THE BOARD (owner, from playtest: a per-card phase is distracting):
#the first card to reach it in a frame moves it and every other card that frame reads what it wrote.
#Its tempo is the SHIPPED style's, because a board-wide clock can take no one card's type override.
static func _advance_shimmer(delta : float, delay : float) -> void:
	if _shimmer_frame == Engine.get_process_frames(): return
	_shimmer_frame = Engine.get_process_frames()
	_shimmer_clock += delta / _alert_period(_SHIMMER, CardOutline.STYLE, delay)

## The phase every shimmering rim on the board reads, in TURNS -- one full bounce per unit.
static var _shimmer_clock : float = 0.0
## The frame it last advanced on, so a hundred shimmering cards move it once between them.
static var _shimmer_frame : int = -1

#Every visual effect this card's statuses ask for, in status order, later drawing on top. Generic by
#construction: CardVisual never names an effect - statuses declare their own via fx_request().
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

#WHERE A SPOTLIGHT CIRCLE GOES ON THIS CARD: the centre of the ART SQUARE at radius 17 art units,
#not the card's own origin. `Art` sits at (0, 6) inside `Visual` and spans +/-17 - 32 of drawing plus
#the shader's 1-unit rim each side - and centring on the origin put the pool high and read ambiguous.

#⚠ ASKED OF THE CARD, never re-derived by the caller. The offset is authored in card_visual.tscn
#and rides `Offset`'s own transform, which the scoring jump lives on, so a second copy in the
#director would disagree the moment a card moves.

#`art` is @onready, so a card asked before it is in the tree answers with the honest fallback rather
#than crashing; the caller's own is_inside_tree guard is what normally prevents it.
func spotlight_center() -> Vector2:
	return art.global_position if art else global_position
#Created at runtime - there is no .tscn slot - and OWNERLESS, because this script is @tool and an
#owned child would be written into card_visual.tscn by the editor.

#⚠ IT IS A STATUS'S ONLY CARD-SIDE PRESENCE: the card carries no status icons at all (owner: *"no
#more status icons, they are represented by status effects like fire and juggling shader... stack
#count and status names stay in description at top"*). CardModifierStatus.fx_request declares them.

## Shader effects for this card's statuses.
var fx : FxAttachment

#The bones come in the order the bake laid them down: one walk around the card, top edge left to
#right, then right, bottom, left. That order IS FxAttachment.measure_outline's contract, and it is
#what makes the outline resolvable in one pass.

## The rig's root and its arm bones.
var _rig_root : Bone2D = null
var _rig_arms : Array[Bone2D] = []
#Rebuilt in place each frame and never reallocated, since this runs on every card on the board.
#Longer than the arm count when the art clips its corners: the bite needs three points where the rig
#has one.

## The arm tips in the card's own art units.
var _rig_outline_buf : PackedVector2Array = PackedVector2Array()
#Resolved once in _bind_rig; zero for a frame with square corners, which is the boosters.

## How far into each corner this card's TYPE art bites, as a fraction of the corner cell's two edges.
var _notch_frac : Vector2 = Vector2.ZERO

#A card silhouette with its four CORNERS pulled outward by `warp` of their rest reach, as the 16
#points the star rig hands over and IN THE ORDER it hands them over. The interior points stay on the
#rest edge, so the box becomes a STAR rather than simply growing.

#The edges alternate horizontal / vertical around the walk, so which of the notch's two dimensions
#belongs to which of a corner's edges alternates with it.

#It lives on the class that owns the rig because four harnesses need to stand a card up without one
#- the FX editor's warp slider, fx_snapshot's warp panel, fx_behind's seam shots and fx_cost's
#deformed-card row - and a private copy in any of them can drift from the rig.

#⚠ IT IS A HAND MODEL AND THE RIG NEVER EXACTLY MAKES IT: measured against the real animation, the
#closest `warp` is off by 2.3 to 3.3 art units at four points of the loop, because the shipped
#animation bulges and pinches the long edges and the corners do not move together (2.9 against 0.5).

#So a warp claim made on a harness panel is a claim about THIS shape; the only place a real
#CardVisual is stood up is the card-mask check in test_pixels.gd.
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
		var h_first := i % 2 == 0
		out.append_array(corner_points(from * (1.0 + warp), back.lerp(from, 0.75),
				from.lerp(to, 0.25), frac.y if h_first else frac.x,
				frac.x if h_first else frac.y))
		for step : int in [1, 2, 3]:
			out.append(from.lerp(to, float(step) * 0.25))
	return out

#The DEFAULT for star_outline, so the harnesses model a real card without naming a type; the game
#measures its own card's type instead, through CardModifierType.corner_notch, which is exact for all
#of them.

## The corner bite every shipped type but the boosters has, in ART UNITS - one texel, one art unit.
const SHIPPED_CORNER_NOTCH := Vector2.ONE

#The outline builders need a FRACTION because a deformed edge is not its rest length. The perimeter
#points sit at quarter points, so a corner's own cell is a quarter of the card in each direction.

## How far along each of a corner's two edges the notch reaches, as a fraction of that edge.
static func notch_fraction(body: Vector2, notch: Vector2) -> Vector2:
	return Vector2(notch.x / maxf(body.x * 0.25, 1e-4), notch.y / maxf(body.y * 0.25, 1e-4))

#ONE CORNER OF THE SILHOUETTE, as the three points its clipped art actually has: in along the edge
#we arrive on, across the bite, then out along the edge we leave on. `prev` and `next` are the
#neighbouring perimeter points, `frac` what notch_fraction returned.

#⚠ THE MIDDLE POINT IS THE CELL'S BILINEAR CORNER, which is what makes this exact under deformation
#and not only at rest: the art's corner texel is a fixed fraction of the corner grid cell in each
#direction, so a stretched or SHEARED cell carries the bite with it as a parallelogram.

#⚠ A ZERO notch returns the corner alone, so a booster - whose frame has square corners - keeps a
#16-point outline and pays nothing.
static func corner_points(corner: Vector2, prev: Vector2, next: Vector2, frac_prev: float,
		frac_next: float) -> PackedVector2Array:
	if frac_prev <= 0.0 or frac_next <= 0.0: return PackedVector2Array([corner])
	var along_prev := (prev - corner) * frac_prev
	var along_next := (next - corner) * frac_next
	return PackedVector2Array([corner + along_prev, corner + along_prev + along_next,
			corner + along_next])

#Find the rig once. Absent - a stripped card in a test, or art without a skeleton - simply means the
#caller falls back to the baked polygon.

#The corner bite is resolved ONCE here because it comes from this card's own type frame and never
#changes at runtime, while _rig_outline runs every frame on every card on the board. It needs three
#points per corner instead of one, wherever there is a bite to describe.

#⚠ DIVIDE BY THE INNER RECT, NOT BY `CARD_SIZE`, when turning texels into art units. The frame is
#38x52 inside a 40x54 polygon, so CARD_SIZE gives (1.0526, 1.0385) and inflates every corner notch
#by 4-5 %; the value must be exactly 1.0, and test_pixels asserts that directly.
func _bind_rig() -> void:
	_rig_root = get_node_or_null("Offset/Visual/Skeleton2D/Bone_Center") as Bone2D
	if not _rig_root: return
	for child : Node in _rig_root.get_children():
		var bone := child as Bone2D
		if bone: _rig_arms.append(bone)
	_notch_frac = Vector2.ZERO
	if data and data.type:
		var frame_px := CardModifier.frame_size(CardModifierType.TYPE_TEXTURE,
				CardModifierType.H_FRAMES, CardModifierType.V_FRAMES)
		var inner := CARD_SIZE - Vector2.ONE * ART_OUTLINE * 2.0
		var per_texel := inner / Vector2(maxf(frame_px.x, 1.0), maxf(frame_px.y, 1.0))
		_notch_frac = notch_fraction(CARD_SIZE, data.type.corner_notch() * per_texel)
	var extra := 8 if _notch_frac.x > 0.0 and _notch_frac.y > 0.0 else 0
	_rig_outline_buf.resize(_rig_arms.size() + extra)

#⚠ COMPOSED FROM THE BONES' OWN LOCAL TRANSFORMS, never from global_position: the rig hangs under
#`visual`, which carries the bob and the basis3d flip, a basis that goes SINGULAR edge-on. Neither
#may reach the effects, or a flipping card's silhouette collapses to a line and takes its flames.

#⚠ AND IT CARRIES THE ART'S CORNER BITE. Every shipped type frame clips its corners by one texel
#while the RIG is the full rectangle, so an outline of bare arm tips puts one FX pixel of flame on
#nothing at each corner. The bite is emitted from the live neighbours, so it shears with the cell.

#There are four arms per edge on a 16-arm rig and the corners are every fourth arm in bake order; a
#corner's neighbours are the arms either side of it, live, and which of the notch's two dimensions
#belongs to which edge alternates around the walk exactly as in star_outline.

## The rig's arm tips, in the card's UNSCALED art space.
func _rig_outline() -> PackedVector2Array:
	var root := _rig_root.transform
	var n := _rig_arms.size()
	if _rig_outline_buf.size() == n:
		for i : int in n:
			_rig_outline_buf[i] = root * _rig_arms[i].position
		return _rig_outline_buf
	var per_edge := n / 4
	var at := 0
	for i : int in n:
		var tip := root * _rig_arms[i].position
		if i % per_edge != 0:
			_rig_outline_buf[at] = tip
			at += 1
			continue
		var prev := root * _rig_arms[(i + n - 1) % n].position
		var next := root * _rig_arms[(i + 1) % n].position
		var h_first := (i / per_edge) % 2 == 0
		for p : Vector2 in corner_points(tip, prev, next,
				_notch_frac.y if h_first else _notch_frac.x,
				_notch_frac.x if h_first else _notch_frac.y):
			_rig_outline_buf[at] = p
			at += 1
	return _rig_outline_buf

#Hand the DEFORMED outline to the effects every frame, because a jump, a spin or a warp can pose the
#rig at any time; the attachment early-outs when nothing moved, so a settled card costs this walk
#and no upload.

#⚠ A REAL OPTIMISATION IS DELIBERATELY NOT TAKEN HERE: with the idle animation off, the walk could
#be skipped entirely while the rig is unposed. FX performance is PAUSED by owner ruling, and
#PERFORMANCE.md's "always running" figure for the rig no longer holds - re-read it before pricing.
func _track_fx_outline() -> void:
	if not fx or _rig_arms.is_empty(): return
	fx.track_outline(_rig_outline())


#Added deferred, so the play area's containers have a frame to update their control positions first.
static func add_child_card_visual(parent:Node,connected_data:CardData, context:DisplayContext, target_control: Control = null) -> CardVisual:
	var card : CardVisual = (CARD_VISUAL.instantiate() as CardVisual).with_data(connected_data)
	card.current_context = context
	card.control_anchor = target_control if target_control else (parent as Control)
	card.recalculate_size()
	parent.call_deferred("add_child", card)
	return card

#⚠ FX HANGS OFF OFFSET, NEVER OFF `visual`: `visual` carries the basis3d flip, whose basis goes
#ZERO edge-on, and the effects' quads must never inherit a singular matrix. Added after `visual`, so
#it draws above the card's face while the whole subtree stays one unit in CardLayer's draw order.

#The FX child is runtime-only and OWNERLESS, this script being @tool. The rig, by contrast, is bound
#in EITHER mode, because the FX editor previews a REAL card and needs the same outline the game
#hands over (owner: *"no useless mocks when you can just use actual original scene"*).

#Motion effects - embers, the cape - are board-only: they exist for cards that travel and are
#dropped, and the deck viewer, 50+ cards all showing their statuses, is the densest screen in the
#game. The flames and balls themselves are identical everywhere.

#The outline comes from the STAR RIG rather than from the rest polygon, because the rig is what
#deforms the card and a silhouette baked once leaves the flames standing on a shape the card no
#longer has. Jumps, spins and warps still pose it, so _track_fx_outline re-reads it every frame.

#A visual built the same frame as its control has no anchor yet, and a viewer or preview visual
#never gets one - hence the same guard on_stage_changed puts on that call. Without it a preview card
#whose previous_stage is PLAY or ZONE crashes whenever any CardEnvironment is on screen.

#Only a card drawn from the deck ONTO THE BOARD flips into view: it keeps the face-down basis3d and
#the floating anim slerps it to front. Every other card spawns already showing its resting face, or
#the slerp would flip all of them from back to front on init.
func _ready() -> void:
	type.hide()
	rank.hide()
	stamp.hide()
	suit.hide()
	art.hide()
	_bind_rig()
	if not Engine.is_editor_hint():
		fx = FxAttachment.new()
		fx.name = "Fx"
		fx.configure(CARD_SIZE, true, FxAttachment.Shape.BOX, FxAttachment.Half.WHOLE,
				current_context == DisplayContext.PLAY_AREA)
		offset.add_child(fx)
		if _rig_arms.is_empty(): fx.measure_silhouette(type.polygon)
		else: fx.measure_outline(_rig_outline())
		fx.visible = show_front and data != null
		fx.sync(_fx_requests())
		SettingsManager.settings_changed.connect(recalculate_size)
	recalculate_size()
	match data.previous_stage:
		data.Stage.PLAY, data.Stage.ZONE:
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
	if not (current_context == DisplayContext.PLAY_AREA and data.previous_stage == data.Stage.DRAW):
		basis3d = Basis.looking_at(Vector3(0, 0, -3.5 * (-1 if data.flipped else 1)))
	on_stage_changed()

func recalculate_size() -> void:
	match current_context:
		DisplayContext.DECK_VIEWER:
			card_size = CARD_SIZE * 2
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

#The anchor may not exist yet, a visual being created the same frame as its control.
func on_stage_changed() -> void:
	if current_context != DisplayContext.PLAY_AREA: return
	if not data: return
	if data.stage == data.previous_stage: return
	match data.stage:
		data.Stage.PLAY, data.Stage.ZONE:
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

#Null when headless, and every caller null-checks, so those visual moves simply skip.

## The active game's view: the UI layer owning the deck, discard and rules anchors and PlayArea.
func _game_view() -> GameView:
	var game := CardEnvironment.get_current_game()
	return game.view if game else null

#⚠ A CONTROL-LOCAL LENGTH IS NOT A GLOBAL ONE. global_position carries every scale above the
#control - the board's zoom lives on the scroll container - while `size` and `card_size` never do.
#Adding them raw spread one row's zone cards by 69.74 px at board_zoom 2.29, and by 0 at 1.0.
func _control_scale(control:Control) -> Vector2:
	return control.get_global_transform().get_scale()

func get_card_control_center(control:Control) -> Vector2:
	var y := (control.size.y - card_size.y / 2) if bottom_anchored else (card_size.y / 2)
	return control.global_position + Vector2(control.size.x / 2, y) * _control_scale(control)

func get_control_center(control:Control) -> Vector2:
	return control.global_position + control.size / 2.0 * _control_scale(control)

#The alert advance is gated on one being live, so a resting board - which is nearly every card,
#nearly always - pays one null check rather than five set_shader_parameter calls per frame.
func _process(delta: float) -> void:
	delta_self_moving_logic(delta)
	if floating: delta_floating_anim(delta)
	_track_fx_outline()
	if _alert: _advance_alert(delta)

var rot_delta : float
var y_delta : float
#TODO(discard animation): this needs a stage check - a card leaving to the discard pile should play
#a discard animation BEFORE the queue_free, not vanish instantly.

#Only PLAY_AREA cards ease toward their slot, which smooths slot-to-slot moves and the fly-in from
#the deck, discard or rules pile. Every other context is a static display that tracks its anchor
#exactly, so the difference is inherent to the context and branches on it rather than on a flag.

#PLAY_AREA cards live on PlayArea's CardLayer INSIDE the scroll content, so a scroll shifts card and
#anchor globals identically: the ease sees no scroll motion and never lags behind a scroll.

#The ease is a frame-dependent lerp and should be a tween when data is moving slots, but something
#has to keep the card attached to its control between moves.

#Tilt and bob juice react to `move`, and only PLAY_AREA cards actually travel: a viewer card's
#one-frame settle would otherwise read as a big move.x and spin it into place.
func delta_self_moving_logic(delta:float) -> void:
	match current_context:
		DisplayContext.PLAY_AREA:
			var gv := _game_view()
			if gv and data not in gv.play_area.data_ui: queue_free()
		_:
			if not Engine.is_editor_hint() and (not control_anchor or not is_instance_valid(control_anchor)): queue_free()
	if (not (move_tween and move_tween.is_running())) and control_anchor:
		var target : Vector2 = get_card_control_center(control_anchor)
		if held:
			var offset : int =  card_size.y/2 - card_separation/2
			offset += (held - 1) * card_separation_custom
			target = get_global_mouse_position() + Vector2(0, offset)
		target.y -= y_delta
		var move : Vector2 = target - global_position
		if current_context == DisplayContext.PLAY_AREA:
			global_position = target + (global_position - target) * exp(-10 * delta)
		else:
			global_position = target
		
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
	self.data = data
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
	move_tween.tween_property(self, "rotation_degrees", 0, delay*0.1)
	return move_tween

#`offset` is @onready and null until this visual's _ready runs, and a freshly built board adds its
#visuals deferred, so the guard is what stops a tween being aimed at a null target.

#Phase lengths are PlayerSettings fractions of the live delay, so the jump respects the pacing and
#compression instead of running on a fixed wall-clock length.
func anim_jump() -> float:
	if not offset: return 0.0
	reset_tween(move_tween)
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

#THE SPRING: a card riding a jump that happened BENEATH it, as if the jumping card had every card
#above it on its shoulder. It mirrors anim_jump's phase fractions and holds for exactly as long as
#the jumping card holds its pose, so the stack moves as ONE RIGID BODY with it.

#The SCALE PULSE is deliberately omitted: the pulse belongs to the card the effect is happening to,
#and pulsing the whole stack reads as five cards being hit rather than one card lifting the others.

#⚠ It rides `offset`, which lives INSIDE the card root and is invisible to the containers, so a
#springing stack OVERLAPS the rows above it and the board does not re-flow. That is the one place
#the "rows never overlap" rule is deliberately broken, and it is broken here rather than found later.
func anim_spring_lift() -> float:
	if not offset: return 0.0
	reset_tween(move_tween)
	var delay := CardEnvironment.CURRENT.get_delay()
	var s := SettingsManager.settings
	move_tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	move_tween.tween_callback(func()->void: floating = false)
	move_tween.tween_property(offset, "position:y", -CARD_JUMP_RISE,
			delay * s.card_jump_raise_fraction)
	move_tween.tween_interval(delay * s.card_jump_pulse_fraction)
	move_tween.tween_property(offset, "position:y", 0.0,
			delay * s.card_jump_settle_fraction)
	return delay * s.card_jump_raise_fraction

# Rotation rather than offset:y, so a spin COMPOSES with a concurrent jump; offset is null until this
# visual's _ready has run, and a held spin loop owns the rotation (never custom_step an INFINITE
# tween). PACED BY ITS CALLER: the reveal awaits between cells, so the board hands in its own delay.
func anim_spin(delay: float) -> float:
	if not offset or _spin_holding: return 0.0
	reset_tween(spin_tween)
	spin_tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	spin_tween.tween_property(offset, "rotation", TAU, delay * .6)
	spin_tween.tween_callback(func()->void: offset.rotation = 0.0)
	return delay * .6

## Held-spin state (PropLayer SPIN hold): true while the looping spin owns offset.rotation.
var _spin_holding : bool = false

#One full revolution per pulse, LOOPING until anim_spin_stop, so a stream of spin-hinting props
#keeps the card turning instead of restarting a one-shot per prop (owner spec). Self-guarding:
#calling it again while held is a no-op.

#The revolution time is floored because get_delay() can be 0, on an undo-cancel snap or at the
#compression floor, and a zero-duration LOOPING tween trips Godot's infinite-loop guard every frame.
func anim_spin_start() -> void:
	if not offset or _spin_holding: return
	_spin_holding = true
	if spin_tween and spin_tween.is_running(): spin_tween.kill()
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

#⚠ THE POLYGON IS THE FRAME PLUS THE OUTLINE'S MARGIN, NOT THE FRAME. Shaders/outline.gdshader can
#only write inside its own polygon, so with no margin there is nowhere for the rim to go and
#CardOutline.frame_polygon stretches the art over the whole box instead.

#Re-baking without that pad is a silent way to delete the outline from one element and make its art
#25 % too big, so the pad lives here rather than in a checkbox someone has to remember.

#Exact Vector2 keys are safe in the vertex index: every queried point is bit-identical to its
#grid_pts source. The index is what keeps the bake linear rather than quadratic in vertices.

#The baseline UVs are the PADDED window of frame 0, so they agree with what CardOutline.frame_polygon
#writes at runtime: the frame's own texels sit in the middle and the polygon's outer ring hangs
#ART_OUTLINE texels outside the sheet, which the shader's frame clamp reads as empty either way.

## Bakes a pristine diamond grid while isolating internal vertices from the perimeter chain.
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

	perimeter_vertices.append(grid_pts[0][0] as Vector2)
	perimeter_vertices.append(grid_pts[0][x_segments] as Vector2)
	perimeter_vertices.append(grid_pts[y_segments][x_segments] as Vector2)
	perimeter_vertices.append(grid_pts[y_segments][0] as Vector2)

	for y in range(y_segments + 1):
		for x in range(x_segments + 1):
			if (y == 0 and x == 0) or (y == 0 and x == x_segments) or \
			   (y == y_segments and x == x_segments) or (y == y_segments and x == 0):
				continue
			internal_vertices.append(grid_pts[y][x] as Vector2)

	var cell_center_start_idx := 4 + internal_vertices.size()
	var centers: Array[Vector2] = []
	
	for y in range(y_segments):
		for x in range(x_segments):
			var c_pos : Vector2 = (grid_pts[y][x] + grid_pts[y][x+1] + grid_pts[y+1][x] + grid_pts[y+1][x+1]) / 4.0
			centers.append(c_pos)
			internal_vertices.append(c_pos)

	var final_vertices := perimeter_vertices + internal_vertices
	
	var v_index : Dictionary[Vector2, int] = {}
	for i in range(final_vertices.size()):
		if final_vertices[i] not in v_index:
			v_index[final_vertices[i]] = i
	var get_v_idx := func(pos: Vector2) -> int:
		return v_index.get(pos, 0)

	var center_counter := 0
	for y in range(y_segments):
		for x in range(x_segments):
			var tl : int = get_v_idx.call(grid_pts[y][x] as Vector2)
			var tr : int = get_v_idx.call(grid_pts[y][x+1] as Vector2)
			var bl : int = get_v_idx.call(grid_pts[y+1][x] as Vector2)
			var br : int = get_v_idx.call(grid_pts[y+1][x+1] as Vector2)
			var cc := cell_center_start_idx + center_counter
			center_counter += 1
			
			triangles.append(PackedInt32Array([tl, tr, cc]))
			triangles.append(PackedInt32Array([tr, br, cc]))
			triangles.append(PackedInt32Array([br, bl, cc]))
			triangles.append(PackedInt32Array([bl, tl, cc]))

	poly.polygon = final_vertices
	poly.polygons = triangles
	poly.internal_vertex_count = internal_vertices.size()

	var initial_uvs := PackedVector2Array()
	initial_uvs.resize(final_vertices.size())
	for i in range(final_vertices.size()):
		var p := final_vertices[i]
		var norm_x := (p.x / frame_w) + 0.5
		var norm_y := (p.y / frame_h) + 0.5
		initial_uvs[i] = Vector2(norm_x * frame_w, norm_y * frame_h) - Vector2.ONE * ART_OUTLINE
	poly.uv = initial_uvs
	poly.notify_property_list_changed()

@export_group("Skeleton Automation Configuration")
## Number of progressive bone nodes dividing each directional arm of the star (1 = 8 bones, 2 = 16 bones)
@export var arm_segments: int = 1
## Changes how many structural arms the star splits into based on edge segments (1 = 8 arms, 2 = 12 arms, 3 = 16 arms)
@export var edge_subdivisions: int = 1

#⚠ THE SKELETON GOES UNDER `Offset/Visual`, BESIDE THE POLYGONS, NOT UNDER THE ROOT. _bind_rig
#looks it up at Offset/Visual/Skeleton2D/Bone_Center, and a root-parented one inherits neither the
#bob nor the basis3d flip the polygons ride, so the rig is never found and never deforms.

#⚠ The outgoing skeleton is queue_freed, which orphans both animations' track paths until the
#regenerated bone names match. They do at `edge_subdivisions = 3`; at any other value the animation
#tracks must be re-pointed by hand.

#It is renamed before freeing because queue_free is deferred: the outgoing node still holds the name
#when the new one is added, and Godot would silently make the new one "Skeleton2D2".
@export_tool_button("Generate Star Skeleton & Bind")
var editor_setup_skeleton : Callable = func() -> void:
	var visual_container := get_node_or_null("Offset/Visual")
	if not visual_container or visual_container.get_child_count() == 0:
		printerr("CardVisual Tool: 'Offset/Visual' path empty or missing!")
		return
	
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

	var half_height := (lowest_y - highest_y) / 2.0
	var center_pos := Vector2(0, highest_y + half_height)
	
	var radius_vertical := half_height
	var radius_horizontal := max_x
	
	var tl := Vector2(-radius_horizontal, highest_y)
	var tr := Vector2(radius_horizontal, highest_y)
	var br := Vector2(radius_horizontal, lowest_y)
	var bl := Vector2(-radius_horizontal, lowest_y)

	var skeleton: Skeleton2D = visual_container.get_node_or_null("Skeleton2D") as Skeleton2D
	if skeleton:
		skeleton.name = "Skeleton2D_outgoing"
		skeleton.queue_free()
	skeleton = Skeleton2D.new()
	skeleton.name = "Skeleton2D"
	visual_container.add_child(skeleton)
	skeleton.owner = get_tree().edited_scene_root

	var center_bone := Bone2D.new()
	center_bone.name = "Bone_Center"
	center_bone.position = center_pos
	center_bone.rotation = 0.0
	center_bone.set_length(10.0)
	
	skeleton.add_child(center_bone)
	center_bone.owner = get_tree().edited_scene_root
	center_bone.rest = center_bone.transform

	var directions: Array[Vector2] = []
	var arm_names: Array[String] = []
	
	var wall_steps := edge_subdivisions + 1
	
	for i in range(wall_steps):
		var target := tl.lerp(tr, float(i) / wall_steps)
		directions.append(target - center_pos)
		if i == 0:
			arm_names.append("TopLeft")
		elif edge_subdivisions == 1:
			arm_names.append("Top")
		else:
			arm_names.append("Top_" + str(i))
		
	for i in range(wall_steps):
		var target := tr.lerp(br, float(i) / wall_steps)
		directions.append(target - center_pos)
		if i == 0:
			arm_names.append("TopRight")
		elif edge_subdivisions == 1:
			arm_names.append("Right")
		else:
			arm_names.append("Right_" + str(i))
		
	for i in range(wall_steps):
		var target := br.lerp(bl, float(i) / wall_steps)
		directions.append(target - center_pos)
		if i == 0:
			arm_names.append("BottomRight")
		elif edge_subdivisions == 1:
			arm_names.append("Bottom")
		else:
			arm_names.append("Bottom_" + str(i))
		
	for i in range(wall_steps):
		var target := bl.lerp(tl, float(i) / wall_steps)
		directions.append(target - center_pos)
		if i == 0:
			arm_names.append("BottomLeft")
		elif edge_subdivisions == 1:
			arm_names.append("Left")
		else:
			arm_names.append("Left_" + str(i))

	var bone_paths: Array[String] = ["Bone_Center"]
	var bone_nodes: Array[Bone2D] = [center_bone]

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

	for poly in polygon_layers:
		poly.skeleton = poly.get_path_to(skeleton)
		poly.clear_bones()
		
		var vertices := poly.polygon
		if vertices.is_empty(): continue
		
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
			
			for b_idx in range(bone_paths.size()):
				var dist := v_glob.distance_to(bone_nodes[b_idx].global_position)
				if dist < 0.1: dist = 0.1
				
				var falloff_factor := 1.0 / (dist * dist)
				distance_factors[b_idx] = falloff_factor
				running_weight_denominator += falloff_factor
				
			for b_idx in range(bone_paths.size()):
				weights_by_bone[b_idx][v_idx] = distance_factors[b_idx] / running_weight_denominator

		for b_idx in range(bone_paths.size()):
			poly.add_bone(NodePath(bone_paths[b_idx]), weights_by_bone[b_idx])
			
		poly.notify_property_list_changed()
	print("CardVisual Tool: Custom ", directions.size(), "-Way Star rig generated with optimized naming schemes!")

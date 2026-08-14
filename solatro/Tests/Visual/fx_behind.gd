extends SnapshotScene
# res://Tests/Visual/fx_behind.gd
# ==============================================================================
# THE SEAM INSTRUMENT — the one thing fx_snapshot.tscn cannot show.
#
#     Godot --path solatro res://Tests/Visual/fx_behind.tscn
#     Output: user://fx_behind/*.png
#
# FX_HANDOFF §0c is a LOOK bug that passed a metric ("0 fire pixels over the art") twice, and §0g's
# standing lesson is why: every FX bug that reached the owner was invisible in fx_snapshot, which
# draws its hosts as an OUTLINE. An outline cannot show a seam. The question here is not "where does
# the flame stand" but "does the boundary between flame and art read as OCCLUSION" — and that is only
# answerable against a host drawn the way the game draws it: FILLED, OPAQUE, at the game's own pixel
# size, blown up enough that one FX pixel is unmistakable.
#
# So each panel is one host, face filled flat, fire on top, at a zoom where 1 art unit is ZOOM
# pixels. What to look for, in one sentence: the flame's lower boundary must follow the ART's edge,
# not a staircase of its own.
#  * A STAIRCASE with ~ZOOM-pixel treads running along a straight or diagonal art edge is the
#    quantized cut (§0c) — the cut is testing the mask at the FX-grid-snapped point, so its boundary
#    has the grid's resolution and the art's edge does not.
#  * The flame's own pixels are SUPPOSED to be chunky. It is pixel art. Only the CUT has to be sharp.
#  * BACKDROP-coloured notches between flame and art are the gap the owner is seeing; flame colour
#    lying over the face is the other half of the same error.
#
# ⚠ `behind_prop_turned` IS NOT REPRODUCIBLE — two consecutive runs of an unchanged build differ by
# ~15k pixels (measured 2026-07-30), while the three UPRIGHT panels here are byte-identical. It is the
# same rotated-host phenomenon `fx_snapshot.gd`'s header describes, and it is worth knowing about
# HERE because this is the one panel someone reaches for after a mask change: a diff of it says
# nothing either way. Judge it by eye, and pin a mask claim with `test_pixels.gd` instead.
# ==============================================================================

const OUT_DIR := "user://fx_behind"

## Parked clock, matching fx_snapshot so the two harnesses show the same frame of the same noise.
const SHOT_TIME := 3.7

## The LARGEST art-unit-to-pixel blow-up. Deliberately big: a card's FX pixel is 1.0 art unit, so at
## 6 a staircase tread is 6 px and an eye can see it without a crop. Each shot takes LESS if its
## hosts need it — a shot whose panels overlap is a tool that lies about which flame belongs to which
## host, and that trap already cost fx_snapshot a debugging pass (its _zoom_for note).
const ZOOM_MAX := 6.0

## How many stacks the fire burns at. 8, not 1: at one stack the flame is short and dark and the seam
## is the hardest thing in the image to see (§0b — every ratio is inert at 1 stack).
const STACKS := 8

func _ready() -> void:
	if not begin(OUT_DIR, Vector2i(1280, 760)): return
	await _run()
	get_tree().quit()

func _run() -> void:
	# THE CARD, at the four states its seam can be wrong in. Rotation is the one the owner named
	# ("rotating still shows jaggedness") and 45 degrees is its worst case: a diagonal art edge
	# against an axis-aligned FX grid is where a quantized cut has the longest tread.
	var rot : Array[_Panel] = [_card(0.0), _card(15.0), _card(45.0)]
	await _shot("behind_card_rot", "CARD, face FILLED, burning %d — 0 / 15 / 45 deg. The flame's "
			% STACKS + "foot must follow the art EDGE, not a staircase of its own", rot)
	# THE DEFORMED CARD — the game's real card is never the 38x50 rectangle (§7), and the radius-table
	# mask is a different code path in mask_level from the box.
	var warp : Array[_Panel] = [_warp(0.0), _warp(0.25), _warp(0.45)]
	await _shot("behind_card_warp", "the SAME seam on a DEFORMED card: corners +0 / 25 / 45 %", warp)
	# THE SPRITE MASK, at rest and TURNED — and the two are different questions, which is exactly what
	# an earlier edition of this scene missed. A prop's art is pixel art, so the FX grid and the art's
	# texels are the same SIZE (2.5 art units) — but the art turns with its host and the FX grid never
	# turns, so they only share an orientation at 0 degrees. Two panels each, for the zoom: a prop's
	# FX pixel is 2.5 art units, and a seam a whole FX pixel wide needs room to be seen.
	var rest : Array[_Panel] = [_prop(HoopVisual.SHEET, HoopVisual.FRAMES, 0.0),
			_prop(KnifeVisual.SHEET, 1, 0.0)]
	await _shot("behind_prop_rest", "SPRITE masks AT REST — ring / blade, both upright", rest)
	var turned : Array[_Panel] = [_prop(HoopVisual.SHEET, HoopVisual.FRAMES, 25.0),
			_prop(KnifeVisual.SHEET, 1, 25.0)]
	await _shot("behind_prop_turned", "the SAME props TURNED 25 deg — the art's texels are diagonal "
			+ "now and the FX grid is not (owner report: props have no nice seams)", turned)

# ------------------------------------------------------------------ the panels

## One panel: a host to draw filled, an FX shape, and the requests over it.
class _Panel:
	var label : String = ""
	var body : Vector2 = Vector2.ZERO
	var shape : FxAttachment.Shape = FxAttachment.Shape.BOX
	var requests : Array[FxRequest] = []
	var rotation : float = 0.0
	## Set for a deformed host: the attachment takes the radius table and the face is drawn as this
	## polygon rather than as the body rectangle.
	var outline : PackedVector2Array = PackedVector2Array()
	var sheet : Texture2D = null
	var frames : int = 1

func _fire(style: FxFireStyle) -> Array[FxRequest]:
	return [FxFire.request(&"fire", STACKS, style)]

func _card(deg: float) -> _Panel:
	var p := _Panel.new()
	p.label = "%d deg" % roundi(deg)
	p.body = CardVisual.CARD_SIZE
	p.rotation = deg_to_rad(deg)
	p.requests = _fire(StatusBurning.CARD_FIRE_STYLE)
	return p

func _warp(warp: float) -> _Panel:
	var p := _card(0.0)
	p.label = "corners +%d%%" % roundi(warp * 100.0)
	p.outline = CardVisual.star_outline(CardVisual.CARD_SIZE, warp)
	return p

func _prop(sheet: Texture2D, frames: int, deg: float) -> _Panel:
	var p := _Panel.new()
	p.label = "%s %d deg" % ["ring" if frames > 1 else "blade", roundi(deg)]
	p.body = PropVisual.art_size_for(sheet, frames)
	p.shape = FxAttachment.Shape.SPRITE
	p.sheet = sheet
	p.frames = frames
	p.rotation = deg_to_rad(deg)
	p.requests = _fire(PropVisual.PROP_FIRE_STYLE)
	return p

# ------------------------------------------------------------------ the harness

## The host's FACE, drawn the way the game draws it: filled and OPAQUE. This is the whole difference
## between this scene and fx_snapshot's outline ghost.
##
## ⚠ A sprite host draws its REAL art, not a silhouette, because its mask is that art's alpha — a
## flat fill would answer a different question from the one the panel is asking.
class _Face extends Node2D:
	## Repeated here rather than read off the outer script: an inner class cannot see the outer
	## script's constants in GDScript.
	const FILL := Color(0.30, 0.36, 0.52)
	var body : Vector2 = Vector2.ZERO
	var outline : PackedVector2Array = PackedVector2Array()
	var sheet : Texture2D = null
	var frames : int = 1
	var art_size : Vector2 = Vector2.ZERO
	func _draw() -> void:
		if sheet:
			draw_texture_rect_region(sheet, Rect2(-art_size * 0.5, art_size),
					CardModifier.frame_rect(sheet, frames, 1, 0))
		elif not outline.is_empty():
			draw_colored_polygon(outline, FILL)
		else:
			draw_rect(Rect2(-body * 0.5, body), FILL)

## The blow-up that keeps every panel INSIDE its own slot — a host takes its DIAGONAL, because a
## rotated card's quad does and its flames are drawn out to it.
func _zoom_for(panels: Array[_Panel], step: float) -> float:
	var widest := 1.0
	for panel : _Panel in panels:
		for req : FxRequest in panel.requests:
			widest = maxf(widest, panel.body.length() + (req.reach + FxAttachment.FX_MARGIN) * 2.0)
	return minf(ZOOM_MAX, step * 0.98 / widest)

func _shot(file_name: String, caption: String, panels: Array[_Panel]) -> void:
	var holder := Node2D.new()
	add_child(holder)
	var size := canvas()
	var step := size.x / float(panels.size())
	var zoom := _zoom_for(panels, step)
	# Collected so every pose can be re-pushed after a settle frame — see the block below the loop.
	var atts : Array[FxAttachment] = []
	for i : int in panels.size():
		var panel : _Panel = panels[i]
		var slot := Node2D.new()
		# Low on the canvas: every flame goes UP, so the interesting half of the panel is the top and
		# the host's own bottom edge is worth nothing here.
		slot.position = Vector2(step * (i + 0.5), size.y * 0.72)
		slot.scale = Vector2.ONE * zoom
		slot.rotation = panel.rotation
		holder.add_child(slot)
		var face := _Face.new()
		face.body = panel.body
		face.outline = panel.outline
		face.sheet = panel.sheet
		face.frames = panel.frames
		if panel.sheet: face.art_size = PropVisual.art_size_for(panel.sheet, panel.frames)
		slot.add_child(face)
		# AFTER the face, so the effects draw over it — which is the state §0c is trying to change and
		# therefore the state this instrument has to show honestly.
		var host := Node2D.new()
		slot.add_child(host)
		var att := FxAttachment.new()
		att.configure(panel.body, true, panel.shape, FxAttachment.Half.WHOLE, false)
		host.add_child(att)
		if panel.sheet:
			att.measure_sprite_silhouette(panel.sheet,
					CardModifier.frame_rect(panel.sheet, panel.frames, 1, 0),
					PropVisual.art_size_for(panel.sheet, panel.frames))
		elif not panel.outline.is_empty():
			att.measure_outline(panel.outline)
		# ⚠ THE SEED GOES IN BEFORE `sync`, AND IT USED TO GO IN AFTER — where it did nothing at all.
		# `u_seed` is written to the material in `_make_quad`, i.e. while `sync` BUILDS the quad, and
		# nothing re-pushes it afterwards (`_push_live` carries the clock, not the randomness). So the
		# assignment below the sync set a GDScript field the shader had already read, and every panel
		# here rendered with the random seed the attachment was constructed with. Same rule
		# `test_pixels._host_balls` and `fx_snapshot._attach_for` state for `_ball_dir` (VFX.md §4.4).
		att._seed = 0.37
		att.sync(panel.requests)
		# Park the clock by hand — and DISABLE THE PROCESS LAST, because _push_live re-enables it
		# (the trap documented in fx_snapshot._shot).
		att._time = SHOT_TIME
		att._push_live(0.0)
		att.set_process(false)
		atts.append(att)
		label(holder, panel.label, Vector2(step * (i + 0.5), size.y * 0.93))
	print("  [", file_name, "] zoom=", zoom, " (", zoom, " screen px per art unit)")
	# ⚠ **SETTLE, THEN RE-PUSH AND RE-PARK — `behind_prop_turned`'s nondeterminism, same cause as
	# `fx_snapshot`'s rotated panels.** `FxAttachment._rot_tight` defaults TRUE and is
	# only re-evaluated under `if moved and on_screen:`; the loop above pushes in the frame the node
	# is added, when `get_global_transform_with_canvas()` is not settled yet, so `_on_screen()` can
	# be false and a ROTATED host keeps the tight quad bound. Parking immediately after means that
	# push is the only chance the flag gets. Full write-up: `fx_snapshot.gd::_settle_poses`.
	# ⚠ Push FIRST, disable the process LAST — `_push_live` re-enables it.
	await get_tree().process_frame
	await get_tree().process_frame
	for att : FxAttachment in atts:
		if not is_instance_valid(att): continue
		att._push_live(0.0)
		att.set_process(false)
	await capture(file_name, caption)
	holder.queue_free()
	await get_tree().process_frame

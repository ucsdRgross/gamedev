extends Node2D
# res://Tests/Visual/prop_art_snapshot.gd
# ==============================================================================
# PROP ART SNAPSHOTS — the visual half of "props draw real sprites".
#
# The headless suite cannot see a pixel, and every claim about the prop art is a claim about
# pixels: that a prop texel is the SAME SIZE as a card texel at every card_scale (owner
# 2026-07-27), that a directional prop MIRRORS rather than turning when it heads the other way,
# and that the hoop's two halves add back up to the whole ring. This scene rasterizes all three.
#
# Run it after any change to prop art, art_size, or the facing rule:
#     Godot --path solatro res://Tests/Visual/prop_art_snapshot.tscn
# Output: user://prop_art_snapshots/*.png — on Windows,
#     %APPDATA%\Godot\app_userdata\Solatro\prop_art_snapshots\
#
# Deliberately NOT in all_tests.tscn: it needs a window and a GPU (same reasoning as
# fx_snapshot.gd, which this scene deliberately mirrors rather than extends — that scene is about
# shader effects, this one is about sprites).
# ==============================================================================

const OUT_DIR := "user://prop_art_snapshots"

## Card scales to check the "one pixel size for all art" rule across. 2.5 is the shipped default
## (PropVisual.AUTHORED_CARD_SCALE), so the two neighbours are what would expose a prop that
## scales by the wrong factor — or not at all.
const SCALES : Array[float] = [1.5, 2.5, 4.0]

func _ready() -> void:
	DisplayServer.window_set_size(Vector2i(1280, 800))
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	var bg := ColorRect.new()
	bg.color = Color(0.09, 0.09, 0.12)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	await _shot_kinds()
	await _shot_pixel_scale()
	await _shot_facing()
	await _shot_hoop_halves()
	await _shot_recolour()
	get_tree().quit()

# ------------------------------------------------------------------ the shots

## Every kind at the default card scale, each beside a card outline, so the props can be judged
## against the thing they fly over: a hoop must be an opening a card fits through, a knife and the
## ballistic pair must read as small objects next to it.
func _shot_kinds() -> void:
	var holder := Node2D.new()
	add_child(holder)
	var kinds : Array[GDScript] = [HoopVisual, KnifeVisual, BallVisual, FireVisual, FireworkVisual]
	var step := _canvas().x / float(kinds.size())
	for i : int in kinds.size():
		var at := Vector2(step * (float(i) + 0.5), _canvas().y * 0.48)
		_card_ghost(holder, at, 2.5)
		var vis : PropVisual = _place(holder, kinds[i].new() as PropVisual, at, 2.5)
		_label(holder, "%s  art %.0fx%.0f" % [kinds[i].get_global_name(), vis.art_size.x,
				vis.art_size.y], Vector2(at.x, _canvas().y * 0.94))
	await _write("10_prop_kinds", "every kind at card_scale 2.5, over a card outline")
	holder.queue_free()
	await get_tree().process_frame

## THE pixel-size rule: a prop texel is the same size as a card texel at every card_scale. The ball
## prop and the card's Ball pip are the SAME 8x8 source frame, so the two squares here must match
## exactly, in all three columns. Any drift is a wrong scale factor in PropVisual.ART_PIXEL_SCALE.
func _shot_pixel_scale() -> void:
	var holder := Node2D.new()
	add_child(holder)
	var step := _canvas().x / float(SCALES.size())
	for i : int in SCALES.size():
		var s : float = SCALES[i]
		var at := Vector2(step * (float(i) + 0.5), _canvas().y * 0.45)
		_card_ghost(holder, at, s)
		# The card's own pip, drawn exactly as CardVisual does it: an 8x8 frame across an 8x8
		# unscaled polygon, the whole card then scaled by card_scale.
		var offset := Vector2((CardVisual.CARD_SIZE.x * 0.5 + 8.0) * s, 0.0)
		var pip := _Pip.new()
		pip.frame = BallVisual.FRAME
		pip.position = at - offset
		pip.scale = Vector2.ONE * s
		holder.add_child(pip)
		# The prop, scaled the way PropLayer scales it.
		_place(holder, BallVisual.new(), at + offset, s)
		_label(holder, "card_scale %.1f — pip | prop" % s, Vector2(at.x, _canvas().y * 0.94))
	await _write("11_prop_pixel_scale", "one pixel size for all art: the two squares must match")
	holder.queue_free()
	await get_tree().process_frame

## Directional art MIRRORS, never rotates: heading right must give the same blade with its top
## still on top (a 180-degree turn would put the crossguard's notch on the other side).
func _shot_facing() -> void:
	var holder := Node2D.new()
	add_child(holder)
	var flips : Array[bool] = [false, true]
	for i : int in flips.size():
		var at := Vector2(_canvas().x * (0.25 + 0.5 * float(i)), _canvas().y * 0.45)
		var knife := KnifeVisual.new()
		knife.flipped = flips[i]
		_place(holder, knife, at, 10.0)   # blown up: the blade is only 12x5 texels
		_label(holder, "flipped = %s (heading %s)" % [flips[i], "right" if flips[i] else "left"],
				Vector2(at.x, _canvas().y * 0.94))
	await _write("12_prop_facing", "the knife mirrors L<->R; its top edge stays its top edge")
	holder.queue_free()
	await get_tree().process_frame

## The hoop's halves are the FULL frame cut down the middle: side by side they must reassemble the
## whole ring with no seam, no doubled column and nothing missing.
func _shot_hoop_halves() -> void:
	var holder := Node2D.new()
	add_child(holder)
	var labels : Array[String] = ["whole ring", "back half (far side)", "front half (near side)",
			"both halves together"]
	var step := _canvas().x / float(labels.size())
	for i : int in labels.size():
		var at := Vector2(step * (float(i) + 0.5), _canvas().y * 0.45)
		var hoop := HoopVisual.new()
		_place(holder, hoop, at, 2.0)
		if i > 0:
			# Split active: the body stops drawing and the bracket nodes take over. They live under
			# CardLayer in the game, so the harness parents and places them itself.
			hoop.set_split_active(true)
			if i != 2: _place_half(holder, hoop.ensure_back(), at, 2.0)
			if i != 1: _place_half(holder, hoop.ensure_front(), at, 2.0)
		_label(holder, labels[i], Vector2(at.x, _canvas().y * 0.94))
	await _write("13_hoop_halves", "back + front are the full frame split at its vertical diameter")
	holder.queue_free()
	await get_tree().process_frame

## The recolour split, one column per suit, driven through the REAL PipSuit calls CardVisual makes:
## the suit PIP must keep the sheet's own multi-tone colours, while the RANK pip and the card ART —
## both suit-AGNOSTIC drawings shared by every suit — come out flattened to that suit's palette
## entry. Bare Polygon2Ds rather than card_visual.tscn: the card's polygons are skinned to its
## Skeleton2D rig, which only a live board sets up, and the rig is not what this shot is about.
func _shot_recolour() -> void:
	var holder := Node2D.new()
	add_child(holder)
	var suits : Array[GDScript] = PipSuit.STANDARD
	var step := _canvas().x / float(suits.size())
	for i : int in suits.size():
		var suit : PipSuit = suits[i].new() as PipSuit
		var rank := PipRankNumeral.new().with_value(7) as PipRankNumeral
		var at := Vector2(step * (float(i) + 0.5), _canvas().y * 0.4)
		# Suit pip: set_texture frames it AND clears the material (its own colours).
		var pip := _quad(holder, PipSuit.SUIT_FRAME_PX, at + Vector2(-70.0, 0.0), 6.0)
		suit.set_texture(pip)
		# Rank pip: same 8x8 polygon, framed by the RANK, recoloured by the suit.
		var rank_pip := _quad(holder, PipSuit.SUIT_FRAME_PX, at, 6.0)
		rank.set_texture(rank_pip)
		suit.set_material(rank_pip)
		# Card art: the 32x32 art frame for this suit and rank, also recoloured.
		var art := _quad(holder, Vector2(32, 32), at + Vector2(90.0, 0.0), 2.5)
		suit.set_art_texture(art, rank)
		_label(holder, "%s — pip | rank | art" % suit.get_str(),
				Vector2(at.x, _canvas().y * 0.94))
	await _write("14_recolour", "suit pip keeps its own colours; rank + art take the suit's")
	holder.queue_free()
	await get_tree().process_frame

## A Polygon2D the size CardVisual authors for a face element, ready for
## CardModifier.update_polygon_uv_frame (which derives its UVs from these bounds).
func _quad(holder: Node2D, size_px: Vector2, at: Vector2, zoom: float) -> Polygon2D:
	var poly := Polygon2D.new()
	var h := size_px * 0.5
	poly.polygon = PackedVector2Array([Vector2(-h.x, -h.y), Vector2(h.x, -h.y), Vector2(h.x, h.y),
			Vector2(-h.x, h.y)])
	poly.position = at
	poly.scale = Vector2.ONE * zoom
	holder.add_child(poly)
	return poly

# ----------------------------------------------------------------- the harness

## One prop, scaled the way PropLayer scales it every frame (card_scale / AUTHORED_CARD_SCALE).
func _place(holder: Node2D, vis: PropVisual, at: Vector2, card_scale: float) -> PropVisual:
	vis.position = at
	vis.scale = Vector2.ONE * (card_scale / PropVisual.AUTHORED_CARD_SCALE)
	holder.add_child(vis)
	return vis

## One bracket half, placed by hand — in the game PropLayer mirrors the prop's transform onto it.
func _place_half(holder: Node2D, half: Node2D, at: Vector2, card_scale: float) -> void:
	half.position = at
	half.scale = Vector2.ONE * (card_scale / PropVisual.AUTHORED_CARD_SCALE)
	holder.add_child(half)

## A card's footprint at this card_scale, so prop size is judged against a card and not guessed.
func _card_ghost(holder: Node2D, at: Vector2, card_scale: float) -> void:
	var ghost := _Ghost.new()
	ghost.body = CardVisual.CARD_SIZE * card_scale
	ghost.position = at
	holder.add_child(ghost)

## The layout space. NOT the window size: `window/stretch/mode` is `canvas_items`, so the canvas has
## its own resolution and the captured image is that canvas scaled to the window — laying out
## against window pixels put the last column off the right edge of the very first run.
func _canvas() -> Vector2:
	return get_viewport_rect().size

## Wait for the frame to actually reach the screen, then capture it.
func _write(file_name: String, caption: String) -> void:
	_label(self, "%s — %s" % [file_name, caption], Vector2(_canvas().x * 0.5, 30.0))
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := "%s/%s.png" % [OUT_DIR, file_name]
	img.save_png(path)
	print("wrote ", ProjectSettings.globalize_path(path))
	# The caption is parented to self (it must not vanish with the shot's holder), so clear it here.
	for child in get_children():
		if child is Label: child.queue_free()

## Centred caption. Plain Label, no theme — a diagnostic, so its strings are deliberately literal
## rather than localized.
func _label(parent: Node, text: String, at: Vector2) -> void:
	var lab := Label.new()
	lab.text = text
	lab.add_theme_color_override("font_color", Color(0.75, 0.78, 0.85))
	lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lab.size = Vector2(400, 20)
	lab.position = at - Vector2(200, 10)
	parent.add_child(lab)

## A card's outline plus its centre line — the reference every prop is judged against.
class _Ghost extends Node2D:
	var body : Vector2 = Vector2.ZERO
	func _draw() -> void:
		draw_rect(Rect2(-body * 0.5, body), Color(0.45, 0.5, 0.6), false, 1.0)

## One suit pip drawn the way CardVisual draws it: the 8x8 frame across an 8x8 UNSCALED polygon,
## with card_scale applied by the node's own scale. The prop beside it must come out the same size.
class _Pip extends Node2D:
	var frame : int = 0
	func _draw() -> void:
		var src := PropVisual.sheet_frame(PipSuit.SUIT_TEXTURE, PipSuit.SUIT_TEXTURE_H_FRAMES,
				PipSuit.SUIT_TEXTURE_V_FRAMES, frame)
		draw_texture_rect_region(PipSuit.SUIT_TEXTURE,
				Rect2(-PipSuit.SUIT_FRAME_PX * 0.5, PipSuit.SUIT_FRAME_PX), src)

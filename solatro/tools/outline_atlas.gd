@tool
class_name OutlineAtlas
extends Node2D
#EVERY OUTLINED FRAME IN THE GAME ON ONE SCREEN, THROUGH THE REAL DRAW PATH: change the ink in the
#inspector and judge it against every non-empty frame at once (owner: "test different outlines ...
#against all sprites at same time"). The frame count is PRINTED on each rebuild, never written down.

#⚠ LOAD-BEARING: the ink is AUTHORED, not derived (owner: "I don't trust derived"), and no assertion
#can tell a legible ink from an illegible one. `test_outline.gd` proves the rim's geometry; only this
#surface shows whether the art READS.

#It exposes: detail thinner than the rim being swallowed; details 2 px apart merging; an authored
#type ink failing on its own card; and whether a card-space GLARE reads on a pip at all - a pip is
#~10 units of the card's sweep, so it flashes briefly. A per-host thickness scale is the escape hatch.

#⚠ NO MOCKS: every frame is a real `Polygon2D`, UV'd by `CardOutline.frame_polygon`, wearing the real
#`outline.gdshader` material. A tool that re-implements framing cannot disagree with the game, so it
#cannot find anything.

#`@tool` with no autoloads: nothing on the construction path touches `SettingsManager` or
#`CardEnvironment` (`PaletteDB` is statics). Everything built is OWNERLESS and rebuilt, or the editor
#would SAVE it into `outline_atlas.tscn`.

## One sheet's worth of frames, as data: adding a sheet is a row in `_sheets`.
class SheetSpec extends RefCounted:
	var label : String
	var sheet : Texture2D
	var h_frames : int
	var v_frames : int
	## Authored in the palette (draws its own colours), or a silhouette flattened to the suit's role.
	var fill : int
	## Whether this sheet sits ON A CARD FACE, which picks its backdrop (`_backdrop_for`).
	var on_face : bool
	## This sheet's element as a card-space offset, read off a real `CardVisual` (`_card_offsets`).
	var card_offset : Vector2 = Vector2.ZERO
	func _init(l : String, s : Texture2D, h : int, v : int, f : int, face := true) -> void:
		label = l; sheet = s; h_frames = h; v_frames = v; fill = f; on_face = face

func _sheets() -> Array[SheetSpec]:
	var at := _card_offsets()
	var out : Array[SheetSpec] = [
		SheetSpec.new("card types (%dx%d -> %dx%d)" % [CardVisual.CARD_ART_SIZE.x,
				CardVisual.CARD_ART_SIZE.y, CardVisual.CARD_SIZE.x, CardVisual.CARD_SIZE.y], CardModifierType.TYPE_TEXTURE,
				CardModifierType.H_FRAMES, CardModifierType.V_FRAMES, CardOutline.Fill.TEXTURE,
				false),
		SheetSpec.new("rank pips (recoloured)", PipRankNumeral.RANK_TEXTURE,
				PipRankNumeral.H_FRAMES, PipRankNumeral.V_FRAMES, CardOutline.Fill.PALETTE),
		SheetSpec.new("suit pips (own colours)", PipSuit.SUIT_TEXTURE,
				PipSuit.SUIT_TEXTURE_H_FRAMES, PipSuit.SUIT_TEXTURE_V_FRAMES,
				CardOutline.Fill.TEXTURE),
		SheetSpec.new("stamp pips (own colours)", CardModifierStamp.STAMP_TEXTURE,
				CardModifierStamp.H_FRAMES, CardModifierStamp.V_FRAMES, CardOutline.Fill.TEXTURE),
		SheetSpec.new("suit art (recoloured)", PipSuit.ART_TEXTURE,
				PipSuit.ART_TEXTURE_H_FRAMES, PipSuit.ART_TEXTURE_V_FRAMES, CardOutline.Fill.PALETTE),
		SheetSpec.new("skill art (recoloured)", CardModifierSkill.SKILL_TEXTURE,
				CardModifierSkill.H_FRAMES, CardModifierSkill.V_FRAMES, CardOutline.Fill.PALETTE),
	] as Array[SheetSpec]
	for i : int in out.size():
		out[i].card_offset = at[i]
	return out

#⚠ WHAT MAKES THE ALERT VISIBLE: the band sweeps CARD space inside the card's extent, so a frame
#carrying its GRID position never lights - measured, only three frames glowed before this existed.
## Where each sheet's element sits on a real card, READ OFF A REAL `CardVisual` in sheet order.
func _card_offsets() -> Array[Vector2]:
	var p := _card_polygons()
	if p.is_empty():
		return [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO,
				Vector2.ZERO] as Array[Vector2]
	return [p[0].position, p[1].position, p[2].position, p[3].position, p[4].position,
			p[4].position] as Array[Vector2]

#⚠ `@onready` IS NOT SAFE FROM A TOOL: those vars are set on tree entry, so a card built inside a
#`SubViewport` mid-frame reads five nulls. The node paths are true from instantiation, the same
#paths `CardVisual` declares, so they are no second source of truth.

## The preview card's five face polygons, BY NODE PATH.
func _card_polygons() -> Array[Polygon2D]:
	if not is_instance_valid(_card): return []
	var out : Array[Polygon2D] = []
	for name : String in ["Type", "Rank", "Suit", "Stamp", "Art"]:
		var poly := _card.get_node_or_null("Offset/Visual/" + name) as Polygon2D
		if not poly: return []
		out.append(poly)
	return out

@export_tool_button("Rebuild") var editor_rebuild : Callable = rebuild

@export_group("The ink (preview overrides)")
#⚠ PREVIEW-ONLY: the shipping values are on `style` below. Hold a candidate against every frame
#before committing it; leave these at -1 to see exactly what the board draws.
## The resting outline entry; -1 uses the style's `outline_index`.
@export_range(-1, 255, 1) var outline_index : int = -1:
	set(v): outline_index = v; _push()
#⚠ Above `CardOutline.WIDTH` the rim CLIPS at the polygon edge, as the game would: visible on purpose.
## The rim's thickness in source texels; -1 uses the style's `width`.
@export_range(-1, 4, 1) var outline_width : int = -1:
	set(v): outline_width = v; _push()
#A silhouette is drawn in a different colour on every suit, so cycle this against all of them.
## The entry the recoloured sheets flatten to; -1 uses `suit_fire`.
@export_range(-1, 255, 1) var fill_index : int = -1:
	set(v): fill_index = v; _push()

@export_group("The alert")
#⚠ The same `outline_default.tres` the board loads through `CardAlert.STYLE`, so what is tuned here
#is what every alerting card uses - numbers re-typed into code afterwards drift. It holds the
#COLOURS too, as palette indices, so an ink is judged and edited in one place.

## THE SHIPPED TUNING: editing this changes the game, not just this preview.
@export var style : OutlineStyle = CardOutline.STYLE:
	set(v): style = v; _push()
#Typed as the enum so the inspector shows the NAMES a status writes in (`CardAlert.kind`).
## Which alert runs.
@export var alert_kind : CardOutline.Alert = CardOutline.Alert.NONE:
	set(v): alert_kind = v; _push()
## PREVIEW override for the alert's palette entry; -1 uses the style's colour for the running kind.
@export_range(-1, 255, 1) var alert_color : int = -1:
	set(v): alert_color = v; _push()
#⚠ Off by default: an `@tool` script must idle cheaply, or it competes with the editor.
## Run the alert's clock.
@export var animate : bool = false:
	set(v):
		animate = v
		set_process(animate)
#An eye call needs the same frame twice.
## The alert phase when not animating - "pin the pose", so a still is reproducible.
@export_range(0.0, 1.0, 0.01) var phase : float = 0.0:
	set(v): phase = v; _push()

@export_group("Layout")
@export_range(1, 8, 1) var zoom : int = 3:
	set(v): zoom = v; rebuild()
@export var gap : int = 6:
	set(v): gap = v; rebuild()
## Wrap each sheet's row at this many frames.
@export_range(4, 32, 1) var per_row : int = 16:
	set(v): per_row = v; rebuild()
#A card is never the rectangle it measures, so an ink judged at an arbitrary frame is judged at a
#different shape each time.
## Where in the idle animation the preview card is frozen, as a fraction of its length.
@export_range(0.0, 1.0, 0.01) var rig_pose : float = 0.0:
	set(v): rig_pose = v; rebuild()
@export var unskin_preview : bool = true:
	set(v): unskin_preview = v; rebuild()
#⚠ TWO BACKDROPS ARE THIS TOOL'S HONESTY: a pip never sits on the board, it sits on the card's FACE.
#The card's rim reads against this one, a pip's against `face_backdrop`; one ink per card means the
#tool must show both halves, or a dark ink looks damning for the wrong reason.

## Behind the CARD TYPES - the board, which is what a card's own rim has to read against.
@export var backdrop : Color = Color(0.10, 0.09, 0.12):
	set(v): backdrop = v; queue_redraw()
#`#eddcc0` dominates seven of the eight shipped type frames. ⚠ Set it to a type you worry about
#(frame 3 is mostly `#e71b40`) and look again: that is the check the authored ink must pass.
## Behind everything that sits ON a card: the pips and the art.
@export var face_backdrop : Color = Color("eddcc0"):
	set(v): face_backdrop = v; queue_redraw()

@export_group("Capture")
## Where "Save PNG" writes; the button prints the absolute path it used.
@export var png_path : String = "user://outline_atlas.png"
#The capture lives beside the knobs, or every image is of the DEFAULTS rather than what was tuned.
## Render the whole atlas offscreen and write it to `png_path`.
@export_tool_button("Save PNG") var editor_save_png : Callable = save_png

var _polys : Array[Polygon2D] = []
var _labels : Array[Dictionary] = []
## One band per sheet, drawn behind its frames in the colour that sheet actually sits on.
var _bands : Array[Rect2] = []
var _band_on_face : Array[bool] = []
var _extent : Vector2 = Vector2.ZERO
## Set on the offscreen copy `save_png` builds, so it renders once and never captures in turn.
var _is_capture_copy : bool = false
var _card : CardVisual = null
var _card_polys : Array[Polygon2D] = []

func _ready() -> void:
	set_process(animate)
	rebuild()
	if Engine.is_editor_hint() or _is_capture_copy: return
	for arg : String in OS.get_cmdline_user_args():
		if not arg.ends_with(".png"): continue
		png_path = arg
		await save_png()
		get_tree().quit()
		return

func _draw() -> void:
	draw_rect(Rect2(Vector2(-gap, -gap), _extent + Vector2(gap, gap) * 2.0), backdrop)
	for i : int in _bands.size():
		if _band_on_face[i]: draw_rect(_bands[i], face_backdrop)
	var font := ThemeDB.fallback_font
	for i : int in _labels.size():
		var entry := _labels[i]
		var on_face : bool = _band_on_face[i] if i < _band_on_face.size() else false
		draw_string(font, entry["at"] as Vector2, entry["text"] as String,
				HORIZONTAL_ALIGNMENT_LEFT, -1.0, 11,
				Color(0.15, 0.13, 0.16) if on_face else Color(0.85, 0.85, 0.85))

func _process(delta : float) -> void:
	phase = fposmod(phase + delta, 1.0)

# ------------------------------------------------------------------ the assembled card

#⚠ ONLY THE CONTEXT IS SET HERE: `data`'s setter awaits `ready`, so data assigned before the card is
#IN THE TREE suspends forever and the card draws nothing while reporting visible. PREVIEW, since
#PLAY_AREA chases a `control_anchor` a tool has none of.

## A REAL `CardVisual`, the scene the game instantiates - the card's own geometry, not a look-alike.
func _spawn_card() -> CardVisual:
	var card := CardVisual.CARD_VISUAL.instantiate() as CardVisual
	card.current_context = CardVisual.DisplayContext.PREVIEW
	return card

#⚠ THE ONLY PLACE ONE CARD-SPACE BAND CAN BE SEEN: five elements at their real offsets show a GLARE
#as one band crossing the card, where a per-element one reads as five bands at different speeds.
#Added to the tree FIRST (see `_spawn_card`) and parked, its alert clock off so `phase` owns it.

## The card preview: every element at its TRUE card position, stacked as the player sees them.
func _build_card_preview(at : Vector2) -> Vector2:
	var card := _spawn_card()
	if not card: return Vector2.ZERO
	add_child(card)
	card.set_process(false)
	card.floating = false
	card.data = CardData.new().with_type(TypePaper.new()) \
			.with_suit(PipSuitHoop.new() as PipSuit) \
			.with_rank(PipRankNumeral.new().with_value(7))
	card.data.stamp = StampGlobal.new()
	card.scale = Vector2.ONE * float(zoom)
	card.position = at + CardVisual.CARD_SIZE * 0.5 * float(zoom)
	var ap := card.get_node_or_null("AnimationPlayer") as AnimationPlayer
	if ap and ap.has_animation(CardVisual.RIG_ANIM):
		var anim := ap.get_animation(CardVisual.RIG_ANIM)
		if anim:
			ap.play(CardVisual.RIG_ANIM)
			ap.seek(rig_pose * anim.length, true)
			ap.pause()
	card.show_front = true
	card.update_visual()
	_card = card
	for poly : Polygon2D in _card_polygons():
		if unskin_preview: poly.skeleton = NodePath()
		_polys.append(poly)
		_card_polys.append(poly)
	return CardVisual.CARD_SIZE * float(zoom)

#Read from the IMAGE, so a re-exported sheet needs no edit here.
## Which frames of a sheet have any art at all.
func _non_empty(sheet : Texture2D, h_frames : int, v_frames : int) -> Array[int]:
	var out : Array[int] = []
	var img := sheet.get_image()
	if not img: return out
	for i : int in h_frames * v_frames:
		var r := CardModifier.frame_rect(sheet, h_frames, v_frames, i)
		var found := false
		for y : int in int(r.size.y):
			for x : int in int(r.size.x):
				if img.get_pixel(int(r.position.x) + x, int(r.position.y) + y).a > 0.0:
					found = true
					break
			if found: break
		if found: out.append(i)
	return out

#The card's polygons are freed WITH the card, never one by one, or it is left with holes. The card
#goes first, as the reference every row decomposes; the sheets are resolved once, since each read
#spawns a throwaway card.

## Tear the atlas down and build it again.
func rebuild() -> void:
	for p : Polygon2D in _polys:
		if is_instance_valid(p) and p not in _card_polys:
			remove_child(p)
			p.queue_free()
	if is_instance_valid(_card):
		remove_child(_card)
		_card.queue_free()
	_card = null
	_card_polys.clear()
	_polys.clear()
	_labels.clear()
	_bands.clear()
	_band_on_face.clear()

	var y := 0.0
	var widest := 0.0
	var total := 0

	_labels.append({"at": Vector2(4.0, y + 12.0),
			"text": "a real CardVisual — every element at its true card offset (the D9 check)"})
	_band_on_face.append(false)
	var card_band_top := y
	y += 18.0
	var card_size := _build_card_preview(Vector2(0.0, y))
	widest = maxf(widest, card_size.x)
	y += card_size.y + gap
	_bands.append(Rect2(Vector2(0.0, card_band_top), Vector2(widest, y - card_band_top)))
	y += gap * 2.0

	var sheets := _sheets()
	for spec : SheetSpec in sheets:
		var frames := _non_empty(spec.sheet, spec.h_frames, spec.v_frames)
		total += frames.size()
		var frame_size := CardModifier.frame_size(spec.sheet, spec.h_frames, spec.v_frames)
		var box := (frame_size + Vector2.ONE * CardOutline.WIDTH * 2.0) * float(zoom)
		_labels.append({"at": Vector2(4.0, y + 12.0),
				"text": "%s  —  %d frames, %d x %d source"
				% [spec.label, frames.size(), int(frame_size.x), int(frame_size.y)]})
		_band_on_face.append(spec.on_face)
		var band_top := y
		y += 18.0
		var col := 0
		var row_top := y
		for idx : int in frames:
			if col >= per_row:
				col = 0
				row_top += box.y + gap
			var at := Vector2(col * (box.x + gap), row_top)
			var poly := Polygon2D.new()
			var h := (frame_size * 0.5 + Vector2.ONE * CardOutline.WIDTH) * float(zoom)
			poly.polygon = PackedVector2Array([Vector2(-h.x, -h.y), Vector2(h.x, -h.y),
					Vector2(h.x, h.y), Vector2(-h.x, h.y)])
			poly.position = at + box * 0.5
			CardOutline.frame_polygon(poly, spec.sheet, spec.h_frames, spec.v_frames, idx)
			CardOutline.set_card_offset(poly, spec.card_offset)
			if spec.fill == CardOutline.Fill.PALETTE:
				CardOutline.fill_palette(poly, _fill())
			else:
				CardOutline.fill_texture(poly)
			add_child(poly)
			_polys.append(poly)
			col += 1
			widest = maxf(widest, at.x + box.x)
		y = row_top + box.y + gap
		_bands.append(Rect2(Vector2(0.0, band_top), Vector2(widest, y - band_top)))
		y += gap * 2.0
	_extent = Vector2(widest, y)
	_push()
	queue_redraw()
	print("OutlineAtlas: %d non-empty frames across %d sheets, plus one assembled card"
			% [total, sheets.size()])

#⚠ A FRESH ATLAS WITH THIS ONE'S KNOBS, not a `duplicate()` (it copies the ~700 built children, and
#the copy rebuilt "0 frames" over them) nor this node (reparenting tears it from the editor viewport).
## The knobs `save_png` copies onto its offscreen atlas.
const CAPTURED_KNOBS : Array[StringName] = [
	&"outline_index", &"outline_width", &"fill_index",
	&"alert_kind", &"alert_color", &"phase",
	&"style", &"zoom", &"gap", &"per_row", &"rig_pose", &"backdrop", &"face_backdrop",
]

func save_png() -> void:
	var copy := OutlineAtlas.new()
	copy._is_capture_copy = true
	for knob : StringName in CAPTURED_KNOBS:
		copy.set(knob, get(knob))
	copy.position = Vector2(gap, gap) * 2.0
	var vp := SubViewport.new()
	vp.size = Vector2i(_extent + Vector2(gap, gap) * 4.0)
	vp.disable_3d = true
	vp.transparent_bg = false
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	add_child(vp)
	vp.add_child(copy)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	var err := img.save_png(png_path)
	print("OutlineAtlas: saved %s -> %s" % [error_string(err),
			ProjectSettings.globalize_path(png_path)])
	vp.queue_free()

func _style() -> OutlineStyle:
	return style if style else CardOutline.STYLE
func _ink() -> int:
	return _style().outline_index if outline_index < 0 else outline_index
func _width() -> int:
	return _style().width if outline_width < 0 else outline_width
func _fill() -> int:
	return PaletteDB.ROLES.suit_fire if fill_index < 0 else fill_index
## -1 means "let the alert resolve it against the style", which is what the game does.
func _alert_ink() -> int:
	return alert_color

#Uniform writes, never a rebuild: rebuilding ~130 ShaderMaterials per keystroke stops it being
#immediate. The alert is the same `CardAlert` a status declares, so the preview IS the alert.
## Push every live knob onto every frame's material.
func _push() -> void:
	var st := _style()
	var alert : CardAlert = null
	if alert_kind == CardOutline.Alert.GLARE:
		alert = CardAlert.glare(-1.0, -1.0, _alert_ink())
	elif alert_kind == CardOutline.Alert.THROB:
		alert = CardAlert.throb(_alert_ink())
	var shown := st.duplicate() as OutlineStyle
	shown.outline_index = _ink()
	shown.width = _width()
	for poly : Polygon2D in _polys:
		if not is_instance_valid(poly): continue
		CardOutline.set_rim(poly, shown, CardVisual.CARD_SIZE)
		CardOutline.set_alert(poly, alert, st)
		CardOutline.set_clock(poly, phase)
		var mat := CardOutline.material_of(poly)
		if mat.get_shader_parameter(&"u_fill_mode") == CardOutline.Fill.PALETTE:
			mat.set_shader_parameter(&"u_fill_index", _fill())

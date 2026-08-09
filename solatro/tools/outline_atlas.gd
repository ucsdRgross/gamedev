@tool
class_name OutlineAtlas
extends Node2D
## **EVERY OUTLINED FRAME IN THE GAME, ON ONE SCREEN, THROUGH THE REAL DRAW PATH** — open
## `outline_atlas.tscn`, change the ink in the inspector, and see it against every non-empty frame
## at once (owner 2026-08-04: *"seems like this will need its own tool editor to check outline against
## all art in the entire game as a massive recreated sprite sheet and test different outlines and
## outline shader effects against all sprites at same time"*).
##
## ── WHY THIS TOOL IS LOAD-BEARING AND NOT A CONVENIENCE ───────────────────────────────────────────
## The outline ink is **AUTHORED, not derived** (design D7 — owner: *"allow authoring with default to
## same one colour if no authoring, I don't trust derived"*). A derived scheme would have had a
## contrast solver to unit-test. An authored one has a person choosing, and **no assertion can tell a
## legible ink from an illegible one.** `Tests/Visual/test_outline.gd` can prove the clamp holds, the
## rim is 8-directional and exactly one unit, and the corner bite survives — none of that says the art
## READS. This is the only surface where that can be judged, which is why D7 turned it from convenient
## into the place a bad ink gets caught.
##
## ── THE SCALE IS KNOWN, NOT GUESSED ───────────────────────────────────────────────────────────────
## 126 non-empty frames (2026-08-06) — one screen at a readable size, which is what makes this a review
## surface rather than a spot check: it shows every frame every time instead of sampling. ⚠ The count is
## PRINTED on each rebuild, never written down — IMPACT.md §11's "114" is already stale.
##
## ── THE SPECIFIC FAILURES IT EXISTS TO EXPOSE ─────────────────────────────────────────────────────
##  * **Detail thinner than the rim.** A 1-unit rim around a 1-px feature swallows it. On the 8x8 pips,
##    where 18 of 19 suit frames fill their cell, there is nowhere for a swallowed detail to hide.
##  * **Details 2 px apart merging** into a blob once each grows its own rim.
##  * **An authored type ink that fails on its own card** — the gap D7 knowingly opened.
##  * **Whether a card-space GLARE reads on an 8x8 pip at all.** ⚠ Expect it not to, at first: a pip is
##    ~10 units of a ~40-unit sweep, so it FLASHES for about a quarter of the pass while the card's own
##    rim glows steadily. D9 answers the COHERENCE half (one card-space band, so the pip shows the
##    slice crossing it) and leaves the LEGIBILITY half open. The escape hatch is a per-host thickness
##    scale — one more uniform — and this is where that gets decided.
##
## ── RULES IT INHERITS ─────────────────────────────────────────────────────────────────────────────
##  1. ⚠ **NO MOCKS** (CLAUDE.md rule 5). Every frame here is a real `Polygon2D`, UV'd by the real
##     `CardOutline.frame_polygon`, wearing the real `Shaders/outline.gdshader` material. It does NOT
##     hand-roll `draw_texture_rect_region`. `fx_editor.gd` is the precedent that earned this rule — it
##     *"paid for itself within hours of no longer being a mock"* by immediately showing the corner-texel
##     bug. **A tool that re-implements framing cannot disagree with the game, which means it cannot
##     find anything.**
##  2. **`@tool`, and no autoloads.** The editor instantiates none, so nothing on the construction path
##     may touch `SettingsManager` or `CardEnvironment`. Nothing here does — `PaletteDB` is statics and
##     `const preload`, which is exactly why it was built that way.
##  3. **Everything it builds is OWNERLESS and rebuilt from scratch.** An owned child would be SAVED
##     into `outline_atlas.tscn` by the editor — the same trap that stops `CardVisual` building its FX
##     in the editor at all.

## One sheet's worth of frames. Declared as data rather than as six near-identical build calls, so
## adding a sheet is a row here.
class SheetSpec extends RefCounted:
	var label : String
	var sheet : Texture2D
	var h_frames : int
	var v_frames : int
	## Whether this sheet's art is AUTHORED IN THE PALETTE (draws its own colours) or is a
	## suit-agnostic silhouette that the game flattens to the suit's role. Not a style choice — see
	## `CardOutline.Fill`.
	var fill : int
	## Does this sheet sit ON A CARD FACE, or is it the face itself? It decides what colour is drawn
	## behind these frames — see `_backdrop_for`, which is the difference between this tool telling the
	## truth and flattering the ink.
	var on_face : bool
	## WHICH ELEMENT OF A CARD THIS SHEET IS, as a card-space offset — the thing the alert band is
	## evaluated against. Filled in from a REAL `CardVisual`'s own polygon positions (`_card_offsets`),
	## never typed in here: the offsets are authored in `card_visual.tscn` and a second copy in a tool
	## is a copy that drifts the first time a pip moves.
	var card_offset : Vector2 = Vector2.ZERO
	func _init(l : String, s : Texture2D, h : int, v : int, f : int, face := true) -> void:
		label = l; sheet = s; h_frames = h; v_frames = v; fill = f; on_face = face

func _sheets() -> Array[SheetSpec]:
	var at := _card_offsets()
	var out : Array[SheetSpec] = [
		SheetSpec.new("card types (38x52 -> 40x54)", CardModifierType.TYPE_TEXTURE,
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

## Where each sheet's element sits on a real card, READ OFF A REAL `CardVisual` in sheet order.
##
## ⚠ **THIS IS WHAT MAKES THE ALERT VISIBLE ON MORE THAN THREE FRAMES.** The band sweeps CARD space and
## exists only inside the card's own extent, so a frame carrying its GRID position as its card position
## is almost always outside the band and never lights. Measured before this existed: exactly three
## frames in the whole atlas glowed — the first pip of the rank, suit and stamp rows, each of which
## happened to land at x≈15, inside ±20. Everything else looked like it did not support the alert.
func _card_offsets() -> Array[Vector2]:
	var p := _card_polygons()
	if p.is_empty():
		return [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO,
				Vector2.ZERO] as Array[Vector2]
	# Sheet order: type, rank, suit, stamp, suit art, skill art — the last two share the Art polygon.
	return [p[0].position, p[1].position, p[2].position, p[3].position, p[4].position,
			p[4].position] as Array[Vector2]

## The preview card's five face polygons, BY NODE PATH rather than through `CardVisual`'s `@onready`
## accessors.
##
## ⚠ **`@onready` IS NOT SAFE TO READ FROM A TOOL, AND THIS COST A DEBUG CYCLE.** Those vars are
## assigned when the node enters the tree, so their value depends on WHEN the host happened to add the
## card — which differs between the scene Godot instantiates for you and one a tool builds inside a
## `SubViewport` mid-frame. Reading them at the wrong moment gives five nulls and takes the whole atlas
## down with an "Invalid access to property 'position' on a base object of type 'Nil'". The node paths
## are true the instant the scene is instantiated, and they are the SAME paths `CardVisual` itself
## declares, so this is not a second source of truth about where the polygons live.
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
## ⚠ **THESE THREE ARE PREVIEW-ONLY. THE SHIPPING VALUES ARE ON `style` BELOW.** They exist to hold a
## candidate up against all 126 frames before committing it — leave them at -1 to see exactly what the
## board draws.
## The resting outline entry; -1 uses the style's `outline_index`.
@export_range(-1, 255, 1) var outline_index : int = -1:
	set(v): outline_index = v; _push()
## The rim's thickness in source texels; -1 uses the style's `width`.
## ⚠ Above `CardOutline.WIDTH` the polygons hold no margin for it and the rim CLIPS at their edge —
## honestly, since the game would clip identically. That visible clipping is the point.
@export_range(-1, 4, 1) var outline_width : int = -1:
	set(v): outline_width = v; _push()
## The entry the recoloured sheets flatten to; -1 uses `suit_fire`. A suit-agnostic silhouette is drawn
## in a different colour on every suit, so cycle this — the ink has to work against all of them.
@export_range(-1, 255, 1) var fill_index : int = -1:
	set(v): fill_index = v; _push()

@export_group("The alert")
## **THE SHIPPED TUNING — EDITING THIS CHANGES THE GAME, NOT JUST THIS PREVIEW.**
##
## ⚠ It is the same `Shaders/Styles/outline_default.tres` the board loads through `CardAlert.STYLE`, so
## the band's tempo, thickness and side buffer tuned here are the ones every alerting card will use.
## That is the whole arrangement `fx_editor` has with `FxStyle`, and the reason this tool is worth
## opening: a tuning surface whose numbers have to be re-typed into code afterwards is a surface that
## drifts from the game the first time someone forgets.
##
## ⚠ It holds the COLOURS too — the rim's ink and each alert kind's entry — as palette INDICES. They
## were moved out of `roles.tres` on 2026-08-06 because splitting one effect's tuning across two files
## meant judging an ink here and editing it somewhere else. `PaletteRamp` is the standing precedent for
## an effect owning its own indices; see `OutlineStyle`'s header.
@export var style : OutlineStyle = CardOutline.STYLE:
	set(v): style = v; _push()
## Which alert runs. Typed as `CardOutline.Alert` rather than as a bare int, so the inspector shows the
## NAMES — the enum is the vocabulary a status writes in (`CardAlert.kind`), and a tool that asks for
## "0, 1 or 2" makes the reader hold the mapping in their head and guess wrong once.
@export var alert_kind : CardOutline.Alert = CardOutline.Alert.NONE:
	set(v): alert_kind = v; _push()
## PREVIEW override for the alert's palette entry; -1 uses the style's own `glare_color` / `throb_color`
## for whichever kind is running. See `style` above — the shipping colour is there, not here.
@export_range(-1, 255, 1) var alert_color : int = -1:
	set(v): alert_color = v; _push()
## Run the alert's clock. ⚠ Off by default: an `@tool` script must idle cheaply (START_HERE's coding
## rules), and a tool that redraws every frame while nobody is looking at it competes with the editor.
@export var animate : bool = false:
	set(v):
		animate = v
		set_process(animate)
## The alert phase when not animating — the "pin the pose" slider, so a still is reproducible. `Q6a` is
## an eye call and an eye call needs the same frame twice.
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
## Where in the idle animation the preview card is frozen, as a fraction of its length. The rig
## autoplays in game and a card is never the rectangle it measures, so an ink judged at an arbitrary
## frame is judged at a different shape each time.
@export_range(0.0, 1.0, 0.01) var rig_pose : float = 0.0:
	set(v): rig_pose = v; rebuild()
@export var unskin_preview : bool = true:
	set(v): unskin_preview = v; rebuild()
## Behind the CARD TYPES — the board, which is what a card's own rim has to read against.
##
## ⚠ **THE TWO BACKDROPS ARE THE WHOLE HONESTY OF THIS TOOL, AND THE FIRST VERSION HAD ONE.** With one
## dark backdrop every pip and every art square floated on the board, where the default dark ink is
## nearly invisible — which looks like a damning finding and is simply the wrong question. **A pip
## never sits on the board. It sits on the card's FACE.** The rim on a pip has to read against
## `face_backdrop`; the rim on the card has to read against this one. That is exactly the tension D7
## accepted by choosing ONE ink per card, so the tool has to show both halves of it or it is arguing
## against a straw man.
@export var backdrop : Color = Color(0.10, 0.09, 0.12):
	set(v): backdrop = v; queue_redraw()
## Behind everything that sits ON a card: the pips and the art. Defaults to `#eddcc0`, the entry that
## dominates seven of the eight shipped type frames — i.e. what a pip is actually drawn on top of.
## ⚠ Change it to a type you are worried about (frame 3 is mostly `#e71b40`) and look again; that is
## the check D7's authored ink exists to pass.
@export var face_backdrop : Color = Color("eddcc0"):
	set(v): face_backdrop = v; queue_redraw()

@export_group("Capture")
## Where "Save PNG" writes. A `user://` path lands in the Godot app-data folder and the button prints
## the absolute path it used.
@export var png_path : String = "user://outline_atlas.png"
## Render the whole atlas offscreen and write it to `png_path`.
##
## ⚠ **THIS USED TO BE A SEPARATE `outline_atlas_shot.tscn`, AND THAT WAS THE WRONG SHAPE.** A second
## scene whose only job is to instantiate the first one is useless to the person actually using the
## tool: the knobs live here, so the capture has to live here too, or every image is of the DEFAULTS
## rather than of whatever was just tuned. It renders through a `SubViewport` at nearest filtering
## because the rim is a one-texel feature and a bilinear read smears exactly the thing being judged.
@export_tool_button("Save PNG") var editor_save_png : Callable = save_png

var _polys : Array[Polygon2D] = []
var _labels : Array[Dictionary] = []
## One band per sheet, drawn behind its frames in the colour that sheet actually sits on.
var _bands : Array[Rect2] = []
var _band_on_face : Array[bool] = []
var _extent : Vector2 = Vector2.ZERO
## The assembled-card preview and its five polygons. Held separately from `_polys` only so the card can
## be freed as a unit on rebuild — it is a scene, not a loose polygon.
## Set on the offscreen copy `save_png` builds, so it renders once and never captures in turn.
var _is_capture_copy : bool = false
var _card : CardVisual = null
var _card_polys : Array[Polygon2D] = []

func _ready() -> void:
	set_process(animate)
	rebuild()
	# RUNNING the scene with a .png in the user args captures and quits — the headless path, so the
	# image can be produced (and looked at) without opening the editor:
	#     Godot --path solatro res://tools/outline_atlas.tscn -- <out.png>
	# Same code as the inspector button; there is no second scene and no second copy of the maths.
	# ⚠ The capture copy must NOT re-enter this, or every copy captures another copy — measured: it
	# recursed until the run was killed, each level dutifully reporting 126 frames.
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
		# Label contrast follows its own band, or a light label on a light face is unreadable.
		var on_face : bool = _band_on_face[i] if i < _band_on_face.size() else false
		draw_string(font, entry["at"] as Vector2, entry["text"] as String,
				HORIZONTAL_ALIGNMENT_LEFT, -1.0, 11,
				Color(0.15, 0.13, 0.16) if on_face else Color(0.85, 0.85, 0.85))

func _process(delta : float) -> void:
	# One full bounce per second while animating. NOT a `get_delay()` fraction like the game's clock —
	# there is no game here, and a tool that paced itself off a Game it does not have would simply be
	# reading the fallback. The GAME's pacing rule is asserted where it applies (`CardVisual`).
	phase = fposmod(phase + delta, 1.0)

# ------------------------------------------------------------------ the assembled card

## A REAL `CardVisual`, posed and parked — the scene the game instantiates, with real data behind it,
## so the preview's geometry is the card's own rather than five polygons a tool arranged to look like
## one. Same construction `fx_editor._new_card` uses, and for the same reason (CLAUDE.md rule 5).
## ⚠ **NOTHING IS CONFIGURED HERE BUT THE CONTEXT, AND THAT ORDERING IS THE WHOLE BUG THIS FUNCTION
## USED TO HAVE.** `CardVisual.data`'s setter calls `update_visual()`, which opens with
## `if not is_node_ready(): await ready` — so assigning `data` to a card that is not yet IN THE TREE
## turns the face build into a coroutine suspended on a signal that has not fired, and it never
## resumes in time. The result is a card that reports `visible = true`, with all five polygons visible,
## textured, and at correct global transforms — and draws **nothing**. `test_pixels._real_card` and
## `fx_editor` both add first and configure after; this now does too.
func _spawn_card() -> CardVisual:
	var card := CardVisual.CARD_VISUAL.instantiate() as CardVisual
	# NOT PLAY_AREA: `delta_self_moving_logic` chases a `control_anchor` a tool has none of.
	card.current_context = CardVisual.DisplayContext.PREVIEW
	return card

## The card preview: every element at its TRUE card position, stacked as the player sees them.
##
## ⚠ **THIS IS THE ONLY PLACE THE D9 CLAIM CAN ACTUALLY BE CHECKED.** The grid above shows each frame
## against the ink, but every frame there is a lone element — a single band crossing a card is a claim
## about five polygons AT DIFFERENT OFFSETS, and five separated cells cannot show whether their bands
## line up. Here the type, the three pips and the art sit at their real offsets, so a GLARE that is
## genuinely card-space reads as ONE band crossing the whole card, and one that is secretly per-element
## reads as five bands starting together and moving at different speeds.
func _build_card_preview(at : Vector2) -> Vector2:
	var card := _spawn_card()
	if not card: return Vector2.ZERO
	# IN THE TREE FIRST — see `_spawn_card`. Everything below runs against a card that is already ready,
	# so `data`'s `update_visual()` completes synchronously instead of suspending.
	add_child(card)
	# ⚠ PARKED, or it deletes itself the moment this scene is RUN rather than edited, and its `_process`
	# does nothing the preview wants (anchor chasing, the bob, its own alert clock — which would fight
	# this tool's `phase` knob for the same uniform).
	card.set_process(false)
	card.floating = false
	card.data = CardData.new().with_type(TypePaper.new()) \
			.with_suit(PipSuitHoop.new() as PipSuit) \
			.with_rank(PipRankNumeral.new().with_value(7))
	card.data.stamp = StampGlobal.new()
	# AFTER `_ready`, which sets `scale` from `card_scale` — this tool works in art units at its own zoom.
	card.scale = Vector2.ONE * float(zoom)
	card.position = at + CardVisual.CARD_SIZE * 0.5 * float(zoom)
	# The idle animation never plays by itself here — it was editor-inert already, and since 2026-08-07
	# it does not autoplay at runtime either (`CardVisual.RIG_ANIM`) — which is what makes
	# `rig_pose` the honest knob: every pose it seeks is one the shipped idle actually passes through,
	# and it holds still while an ink is judged (§11 rule 3, "pin the pose").
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
	# Its five polygons join the push list, so the ink / width / alert knobs drive them too. Their
	# `u_card_offset` is already correct — `frame_polygon` took it from each node's real position, which
	# on a real card IS its card-space position. That is exactly what the grid above has to fake.
	for poly : Polygon2D in _card_polygons():
		if unskin_preview: poly.skeleton = NodePath()
		_polys.append(poly)
		_card_polys.append(poly)
	return CardVisual.CARD_SIZE * float(zoom)

## Which frames of a sheet have any art at all. Read from the IMAGE, so a re-exported sheet with more
## art needs no edit here — and the count is what makes "every frame, one screen" a fact rather
## than a claim.
func _non_empty(sheet : Texture2D, h_frames : int, v_frames : int) -> Array[int]:
	var out : Array[int] = []
	var img := sheet.get_image()
	if not img: return out
	for i : int in h_frames * v_frames:
		var r := CardModifier.frame_rect(sheet, h_frames, v_frames, i)
		var found := false
		for y : int in int(r.size.y):
			for x : int in int(r.size.x):
				if img.get_pixel(int(r.position.x) + x, int(r.position.y) + y).a > 0.5:
					found = true
					break
			if found: break
		if found: out.append(i)
	return out

## Tear the atlas down and build it again. Everything is ownerless — see the header's rule 3.
func rebuild() -> void:
	# The card preview's polygons belong to the card and are freed WITH it — removing them individually
	# would leave a CardVisual with holes in it.
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

	# THE ASSEMBLED CARD FIRST — it is the reference every row below is a decomposition of, and the only
	# place a card-space band can be seen to be one band.
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

	# Resolved ONCE: `_sheets()` reads the card offsets off the preview built above, and calling it per
	# use would re-read them (and spawn a throwaway card) each time.
	var sheets := _sheets()
	for spec : SheetSpec in sheets:
		var frames := _non_empty(spec.sheet, spec.h_frames, spec.v_frames)
		total += frames.size()
		var frame_size := CardModifier.frame_size(spec.sheet, spec.h_frames, spec.v_frames)
		# THE POLYGON IS THE FRAME PLUS THE RIM'S MARGIN — the one rule every outline client obeys, and
		# the reason this tool cannot just draw the sheet: the padding is where the rim lives.
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
			# ⚠ THE REAL PATH, and the zoom is in the POLYGON rather than in a node `scale`, so
			# `frame_polygon`'s bounding-box mapping still sees a box that is exactly frame + 2 * rim in
			# proportion. A `scale` would have worked too; doing it in the geometry keeps the one
			# invariant this whole feature rests on (1 texel = 1 unit) visible in one place.
			CardOutline.frame_polygon(poly, spec.sheet, spec.h_frames, spec.v_frames, idx)
			# ⚠ AND THEN OVERRIDE THE CARD OFFSET `frame_polygon` JUST DERIVED. On a real card a
			# polygon's node position IS its card-space position, which is why the game needs no such
			# call; in a grid it is the cell this frame happens to be laid out in, which is nowhere near
			# the card. Leaving it made the alert appear on exactly three frames in the whole atlas.
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
	for poly : Polygon2D in _card_polys:
		print("DBG2 %s in_tree=%s gxform=%s vis_in_tree=%s poly0=%s" % [poly.name,
			poly.is_inside_tree(), poly.get_global_transform() if poly.is_inside_tree() else "n/a",
			poly.is_visible_in_tree(), poly.polygon[0] if poly.polygon.size() > 0 else "empty"])
	queue_redraw()
	print("OutlineAtlas: %d non-empty frames across %d sheets, plus one assembled card"
			% [total, sheets.size()])

## Render the atlas AS IT IS RIGHT NOW into an offscreen viewport and write it to `png_path`.
##
## ⚠ **IT CAPTURES A FRESH ATLAS CARRYING THIS ONE'S KNOBS, NOT A `duplicate()` AND NOT THIS NODE.**
## Reparenting the live atlas into a SubViewport would tear it out of the editor's viewport mid-frame.
## `duplicate()` is the trap that looks like the answer: `Node.duplicate` ALWAYS copies children, so it
## brings across the ~700 polygons and the CardVisual this node built at runtime, and then the copy's
## `_ready` rebuilds on top of them — measured, it produced a second atlas reporting "0 frames" over the
## wreckage of the first. A fresh node plus an explicit knob copy is both smaller and honest about what
## is being captured.
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
	# ⚠ A SubViewport carries its OWN filter and defaults to LINEAR — it does not inherit the project's
	# `default_texture_filter = 0`. The rim is a one-texel feature and a bilinear read smears exactly
	# the thing being judged.
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

## Push every live knob onto every frame's material. Uniform writes, never a rebuild: the whole point
## of the tool is turning a knob and seeing every frame answer at once, and rebuilding ~130
## ShaderMaterials per keystroke is how that stops being immediate.
func _push() -> void:
	# THE SAME OBJECT A STATUS WOULD DECLARE, resolved against the same style the game reads — so what
	# this tool previews is not an approximation of the alert, it IS the alert.
	var st := _style()
	var alert : CardAlert = null
	if alert_kind == CardOutline.Alert.GLARE:
		alert = CardAlert.glare(-1.0, -1.0, _alert_ink())
	elif alert_kind == CardOutline.Alert.THROB:
		alert = CardAlert.throb(_alert_ink())
	# The preview overrides ride on top of the style, so the grid can show a candidate ink without the
	# style being edited. A `.duplicate()` rather than a mutation: writing to `st` would write to the
	# shipped resource, and the editor would save it.
	var shown := st.duplicate() as OutlineStyle
	shown.outline_index = _ink()
	shown.width = _width()
	for poly : Polygon2D in _polys:
		if not is_instance_valid(poly): continue
		# The card extent the alert sweeps. Every frame here is judged as if it were on a card, because
		# that is where it will be — a pip lit by a band scaled to a pip would tell you nothing about
		# what the pip does on a real card (D9).
		CardOutline.set_rim(poly, shown, CardVisual.CARD_SIZE)
		CardOutline.set_alert(poly, alert, st)
		CardOutline.set_clock(poly, phase)
		var mat := CardOutline.material_of(poly)
		if mat.get_shader_parameter(&"u_fill_mode") == CardOutline.Fill.PALETTE:
			mat.set_shader_parameter(&"u_fill_index", _fill())

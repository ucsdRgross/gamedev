@tool
class_name WallEditor
extends Node2D
## The picture-wall layout tool. Open `Tools/wall_editor.tscn`, edit any field in the Inspector,
## and the packed wall rebuilds live. Every wall number is an editable field here, never a
## constant in code.
##
## Three Inspector panels, no custom UI — the Inspector already gives every field, array
## add/remove and undo for free, as `fx_editor.gd` and `spotlight_tool.gd` also rely on:
##  * `layout` — every `WallLayout` field, and every `PictureEntry` field per picture.
##  * `preview_settings` — a standalone `PlayerSettings`. Never `SettingsManager.settings`: a
##    knob tuned here must not rewrite the player's `user://settings.tres`.
##  * the tool's own state — `preview_aspect`, `unlocked_ids`, the transition picker, content
##    mode, Info mode, and save/revert.
##
## `save_now` / `revert_now` / `play_transition` are booleans acting as BUTTONS: they run on the
## rising edge and reset themselves. This Godot version has no `@export` button annotation.
##
## ⚠ EDITOR CONSTRAINTS:
##  * **Every script this tool loads or builds must be `@tool`** (`WallLayout`, `PictureEntry`,
##    `WallPicture`). A non-`@tool` script loads in the editor as a PLACEHOLDER: reads work, but a
##    method call throws *"Attempt to call a method on a placeholder instance"*, and SAVING a
##    `.tres` whose script is a placeholder silently DROPS every property the editor could not
##    see — which would corrupt the layout the game loads.
##  * **The editor instantiates no autoloads**, so `SettingsManager` is absent here. The wall asks
##    `WallPicture.settings()`, and this tool assigns `WallPicture.editor_settings` — an override
##    that wins in BOTH contexts. Editor-only would be the bug `LightLayer` already paid for: a
##    PLAYED tool scene would read the player's saved `settings.tres` while this panel kept showing
##    its own resource, and the preview would stop being evidence.
##  * **`Camera2D` does not drive the editor's 2D viewport** — only a RUNNING scene's window
##    follows a current camera. Every field is live either way, but the transition preview is only
##    watchable when this scene is actually RUN (F6).
##  * **Every preview `WallPicture` is OWNERLESS** and rebuilt on each re-pack; an owned child
##    would be saved into `wall_editor.tscn` itself.
##  * This script never references `ProfileManager` or `user://profile.tres`. `unlocked_ids` is an
##    in-memory simulation only.

const LAYOUT_PATH := "res://Assets/Wall/layout_default.tres"
const WALL_PICTURE_SCENE := preload("res://UI/Wall/wall_picture.tscn")
## The screens `Main` reparents onto the wall at runtime, so a RUN tool shows the same content the
## game does. Ids with no entry here draw their `background_texture`, or nothing.
const INFO_CARD_SCENE := preload("res://UI/Wall/info_card.tscn")
const OVERLAY_SCENE := preload("res://UI/Wall/wall_overlay.tscn")
const WALL_SCENE := preload("res://UI/Wall/wall.tscn")
const LIVE_SCREENS : Dictionary[StringName, PackedScene] = {
	&"start_menu": preload("res://Levels/menu.tscn"),
	&"map": preload("res://Levels/map.tscn"),
	&"game": preload("res://Levels/game_view.tscn"),
}
## How often to re-read every Inspector-visible field for an edit nothing notifies us of: a plain
## `@export var` with no setter does not announce being edited in place inside a nested panel.
const WATCH_SECS := 0.25
## Knobs the EDITOR preview cannot exercise. Empty when RUN: F6 hosts a real `Wall`, so every knob
## reaches the same code the game runs it through. These four need that `Wall` (or, for
## `wall_reveal_delay_scale`, the `play_reveal` button), and `Wall` is not `@tool`.
const EDITOR_INERT_KNOBS : Array[String] = ["wall_selection_repeat_delay", "wall_debug_readout",
		"wall_reveal_delay_scale", "wall_unlock_all"]

## The layout this tool edits and saves — `layout_default.tres`, the same resource the game loads.
## Seeded from `Wall.initial_layout()` the first time the tool runs with no file on disk.
@export var layout : WallLayout = null:
	set(v):
		layout = v
		_seed_unlocked_ids()
		_repack()

## The settings the whole preview reads, in the editor and when played alike. A STANDALONE
## resource carrying the shipped defaults — never the player's `user://settings.tres`, so tuning
## here cannot rewrite a real save. Never null: a null assignment falls back to fresh defaults
## rather than leaving the preview with nothing to read.
@export var preview_settings : PlayerSettings = PlayerSettings.new():
	set(v):
		preview_settings = v if v else PlayerSettings.new()
		_apply_preview_settings()
		_repack()

## Window aspect ratio to pack against. The range runs well outside `WallLayout`'s own ellipse
## clamps so the clamping itself is visible at the extremes.
##
## ⚠ SEEDED FROM THE LIVE WINDOW in `_ready()`, never left at a rounded literal. `focused_scale()`
## skips its overfill margin only when the two axis ratios are EXACTLY equal, and a rounded aspect
## misses that by ~1.4e-05 — just past `is_equal_approx` — so the margin fires and crops 2% off a
## focused picture that the game shows uncropped. Measured: the start menu's `Profile` and
## `Language` buttons lost their outer edges, which reads as a menu-layout bug and is not one.
@export_range(0.5, 4.0, 0.01) var preview_aspect : float = 1.7778:
	set(v):
		preview_aspect = v
		_repack()

## Which picture ids to treat as unlocked. Seeded with EVERY id in the layout the first time one
## loads, so the tool opens on the whole wall rather than on the subset a fresh save would see —
## tuning spacing against pictures that are not there is the mistake that default prevents. Delete
## ids to simulate a partial unlock; an id absent here is locked.
@export var unlocked_ids : Array[StringName] = []:
	set(v):
		unlocked_ids = v
		_repack()

@export_group("Transition preview")
## The two ids to move between; both must be in `unlocked_ids`. Seeded when a layout loads —
## `home_id` and the picture packed furthest from it, which is the longest move on the wall and so
## the one that shows the curves most clearly.
@export var preview_source_id : StringName = &""
@export var preview_dest_id : StringName = &""
## BUTTON. Plays a real `WallTransition` between the two picked pictures. Only watchable in a
## running window (F6) — see the "Camera2D does not drive the editor's viewport" note above.
@export var play_transition : bool = false:
	set(v):
		play_transition = false
		if v: _play_transition()

@export_group("Content mode")
## Draw empty frames instead of hosting each picture's real screen. Faster to re-pack while
## dragging geometry numbers, but defects that only show with real content are then invisible, so
## this is off by default.
##
## ⚠ Real content needs the tool RUN (F6), not previewed: `start_menu`/`map`/`game` are ordinary
## game scenes and instantiating them inside the editor is not safe. Previewing in the Inspector
## therefore draws empty frames whatever this says, which is correct for geometry work.
@export var use_placeholder_content : bool = false:
	set(v):
		use_placeholder_content = v
		_repack()

@export_group("Focus")
## Which picture is FOCUSED, or `&""` for wall view. Focusing poses the camera at that picture's
## resting pose and calls the real `WallPicture.focus()`; everything else is `unfocus()`ed at its
## wall-view footprint — so render targets, texture filters and sizes match the running game.
##
## ⚠ A focused picture at rest is the state a player is in most of the time, and the one where a
## too-small `wall_overfill_margin` shows a sliver of frame or bare wall at a window edge. Wall view
## alone cannot show that.
@export var preview_focus_id : StringName = &"":
	set(v):
		preview_focus_id = v
		_apply_focus()
## Which picture carries the wall-view selection cursor, or `&""` for none. Drives the real
## `WallPicture.set_selected()`, so `wall_selected_lift` is visible. Ignored while a picture is
## focused — the lift is a wall-view affordance.
@export var preview_selected_id : StringName = &"":
	set(v):
		preview_selected_id = v
		_apply_selection()
## Render every UNFOCUSED picture at its wall-view FOOTPRINT resolution, as the running game does,
## instead of at full `design_size`. This is what `wall_view_min_texture_px` governs and the only
## way to judge how sharp the wall actually looks.
##
## ⚠ OFF BY DEFAULT, and the reason is worth knowing: a screen laid out for its `design_size` does
## NOT re-flow into a smaller viewport, it CROPS — so at wall-view resolution the pictures show an
## enlarged top-left corner rather than a shrunken screen. Whether that is also true of the running
## game has not been checked; if it is, it is a product defect, not a tool artefact.
@export var preview_wall_view_resolution : bool = false:
	set(v):
		preview_wall_view_resolution = v
		_repack()

@export_group("Info mode")
## Turns Info mode on for the preview: the camera drops to `preview_focus_id`'s info pose — zoomed
## just far enough to reveal the BOTTOM frame, with top, left and right still covered — and the real
## `InfoCard` shows that picture's real `get_info()` entry. Needs a focused picture; in wall view
## there is no single frame to reveal, exactly as in the game.
##
## ⚠ This is the ONLY way to reach `wall_info_mode` from an Inspector. That flag is deliberately not
## `@export`ed on `PlayerSettings` (it is session state and must never persist), so it does not
## appear in the `preview_settings` panel above and nothing else here would set it.
##
## With this on, `play_transition` also previews the INFO transition, which is a pure travel at a
## constant zoom rather than the ordinary zoom-out/travel/zoom-in.
@export var preview_info_mode : bool = false:
	set(v):
		preview_info_mode = v
		if preview_settings: preview_settings.wall_info_mode = v
		# ⚠ Keep the overlay's own toggle in step. The button is the source of truth in the game —
		# `Main` presses it rather than writing the flag — so a tool that sets the flag from the
		# Inspector without moving the button reproduces exactly the divergence that rule prevents:
		# info mode on, button reading un-pressed. Assigning an unchanged value emits nothing, so
		# this cannot loop back through `_on_overlay_info_toggled()`.
		if is_instance_valid(_overlay):
			var button := _overlay.get_node_or_null(^"InfoButton") as Button
			if button and button.button_pressed != v: button.button_pressed = v
		_apply_info_mode(true)

## BUTTON. Plays the one-off OPENING REVEAL — the move `Main` runs when a save is chosen, scaled by
## `wall_reveal_delay_scale` so it reads as longer and slower than an ordinary Wall press. This is
## the only thing that exercises that knob.
@export var play_reveal : bool = false:
	set(v):
		play_reveal = false
		if v: _play_reveal()

@export_group("Gestures")
## Route real touch input through the REAL `WallInput.PinchTracker`, so
## `wall_pinch_threshold_px` is tunable against actual fingers: pinch OUT enters the selected
## picture, pinch IN goes to wall view.
##
## ⚠ Needs a touch device, or `emulate_mouse_from_touch` turned OFF — on desktop Godot converts
## touches to mouse events before they ever reach a tracker. `_gesture_log` below records what the
## tracker actually saw, so a threshold that never fires is visible rather than merely silent.
@export var preview_pinch : bool = false:
	set(v):
		preview_pinch = v
		_pinch = WallInput.PinchTracker.new()   # a fresh tracker, never a half-finished gesture
		_gesture_log = ""
## The last gesture the tracker reported, for reading back in the Inspector.
@export var gesture_log : String = "":
	set(_v): pass
	get: return _gesture_log

@export_group("Honesty")
## ⚠ READ-ONLY, and EMPTY when the tool is RUN — F6 hosts a real `Wall`, so every knob reaches the
## same code the game runs it through. In the Inspector preview there is no `Wall` (it is not
## `@tool`), so the four knobs that need one are listed here rather than silently doing nothing.
@export var knobs_this_preview_does_not_drive : String = "":
	set(_v): pass
	get: return "" if is_instance_valid(_wall) else ", ".join(EDITOR_INERT_KNOBS)

@export_group("Save")
## BUTTON. Writes `layout` to `LAYOUT_PATH` — the resource the game loads, not a copy.
@export var save_now : bool = false:
	set(v):
		save_now = false
		if v: _save()
## BUTTON. Discards every in-memory edit and reloads `layout` from disk (or reseeds
## `Wall.initial_layout()` if nothing has been saved yet).
@export var revert_now : bool = false:
	set(v):
		revert_now = false
		if v: _revert()

var _watch_wait := 0.0
## Every Inspector-visible value of `layout` and `preview_settings` as of the last rebuild.
var _watched : Array = []

var _pictures_root : Node2D = null
var _viewports_root : Node = null
var _camera : Camera2D = null
var _preview_pictures : Dictionary[StringName, WallPicture] = {}
## The real `Wall` when RUN, null in the editor preview.
var _wall : Wall = null
var _overlay : WallOverlay = null
var _info_card : InfoCard = null
## Real Back/Forward history behind the overlay's own buttons. Seeded from `preview_focus_id`.
var _focus_stack : FocusStack = null
## True while a preview move owns the camera. The overlay stays PRESSABLE throughout on purpose —
## the game locks wall INPUT during a move, not the overlay's buttons, and whether that is right is
## one of the things this tool exists to let you feel.
var _move_active : bool = false
var _pinch := WallInput.PinchTracker.new()
var _gesture_log : String = ""

## Feeds real input through the real pinch tracker. `Wall` does this from its own
## `_unhandled_input` for the same reason: a gesture must be derived from the events that actually
## arrived, never re-simulated.
func _unhandled_input(event: InputEvent) -> void:
	if not preview_pinch or Engine.is_editor_hint() or _move_active: return
	var gesture := _pinch.feed(event, preview_settings.wall_pinch_threshold_px)
	if gesture == WallInput.PinchTracker.Gesture.PINCH_OUT:
		_gesture_log = "PINCH_OUT -> enter %s" % preview_selected_id
		if preview_selected_id != &"": await _move_to(preview_selected_id)
	elif gesture == WallInput.PinchTracker.Gesture.PINCH_IN:
		_gesture_log = "PINCH_IN -> wall view"
		await _move_to(&"")
var _last_rects : Array[PictureRect] = []

## Whatever `WallPicture.editor_settings` held before this tool claimed it, restored on the way
## out so a played tool scene leaves the shipped game reading `SettingsManager` again.
var _previous_editor_settings : PlayerSettings = null

func _ready() -> void:
	# ⚠ `Wall._ready()` pauses the whole tree and this tool KEEPS that pause, because it is what
	# makes an unfocused screen freeze the way the game freezes it. Everything here must therefore
	# opt out, exactly as `Wall`, `%Camera2D` and `%Overlay` do in `wall.tscn`.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_previous_editor_settings = WallPicture.editor_settings
	var window := _viewport_size()
	if window.y > 0.0: preview_aspect = window.x / window.y
	_apply_preview_settings()
	_build_preview_scaffold()
	if layout:
		_seed_unlocked_ids()
		_repack()
	else:
		layout = _load_or_seed_layout()   # setter itself seeds + repacks

func _exit_tree() -> void:
	WallPicture.editor_settings = _previous_editor_settings

func _process(delta: float) -> void:
	_watch_wait += delta
	if _watch_wait < WATCH_SECS: return
	_watch_wait = 0.0
	if _fingerprint() != _watched:
		_repack()

# ============================================================== Settings override

## Points the whole wall at `preview_settings`. One assignment, no node, no autoload — and it wins
## whether this scene is previewed or played.
func _apply_preview_settings() -> void:
	WallPicture.editor_settings = preview_settings

# ============================================================== Layout load / save / revert

## Loads `LAYOUT_PATH` fresh off disk, bypassing the resource path cache so a revert discards
## in-memory edits rather than handing back the same mutated object.
func _load_or_seed_layout() -> WallLayout:
	if ResourceLoader.exists(LAYOUT_PATH):
		return ResourceLoader.load(LAYOUT_PATH, "", ResourceLoader.CACHE_MODE_IGNORE) as WallLayout
	# Nothing on disk yet: seed from the same starting content the game boots with, so there is
	# something real to tune immediately.
	return Wall.initial_layout()

func _save() -> void:
	if not layout:
		push_warning("WallEditor: nothing to save -- layout is null")
		return
	DirAccess.make_dir_recursive_absolute(LAYOUT_PATH.get_base_dir())
	var err := ResourceSaver.save(layout, LAYOUT_PATH)
	if err == OK:
		print("WallEditor: saved ", LAYOUT_PATH)
	else:
		push_error("WallEditor: save to %s FAILED, error %d" % [LAYOUT_PATH, err])

func _revert() -> void:
	layout = _load_or_seed_layout()
	print("WallEditor: reverted -- ", ("loaded " + LAYOUT_PATH) if ResourceLoader.exists(LAYOUT_PATH)
			else "no saved file yet, reseeded Wall.initial_layout()")

## Seeds EVERY id in the layout the first time one is assigned — an empty `unlocked_ids` means
## "nothing chosen yet", not "everything locked". Never overwrites a simulation already in
## progress.
func _seed_unlocked_ids() -> void:
	if not layout or not unlocked_ids.is_empty(): return
	var seeded : Array[StringName] = []
	for e : PictureEntry in layout.pictures:
		seeded.append(e.id)
	unlocked_ids = seeded   # fires this field's own setter -> one extra harmless repack

## Seeds the transition picker with `home_id` and the picture packed furthest from it — the
## longest move the wall can make, and so the clearest look at the curves. Only fills a blank
## field, so a pair chosen by hand survives a re-pack.
func _seed_transition_ids() -> void:
	if not layout or _last_rects.is_empty(): return
	if preview_source_id == &"": preview_source_id = layout.home_id
	if preview_dest_id != &"": return
	var origin := Vector2.ZERO
	for rect : PictureRect in _last_rects:
		if rect.id == preview_source_id: origin = rect.centre
	var best_id := &""
	var best_distance := -1.0
	for rect : PictureRect in _last_rects:
		if rect.id == preview_source_id: continue
		var distance := origin.distance_to(rect.centre)
		if distance > best_distance:
			best_distance = distance
			best_id = rect.id
	preview_dest_id = best_id

# ============================================================== Live preview scaffold

## Builds the roots and camera the preview lives under. ⚠ Deliberately NOT a real `Wall`:
## `Wall._ready()` sets `get_tree().paused = true` GLOBALLY, which would freeze the editor's own
## tree and every other open `@tool` scene. `WallPicture`/`WallPacker`/`WallTransition` are used
## directly — the real code, just not the pausing shell around it.
func _build_preview_scaffold() -> void:
	# RUNNING: the real shell, so every knob reaches the code the game runs it through.
	if not Engine.is_editor_hint():
		_build_real_wall()
		return
	_pictures_root = Node2D.new()
	_pictures_root.name = "PreviewPictures"
	add_child(_pictures_root)   # NO owner -- see the class doc comment
	_viewports_root = Node.new()
	_viewports_root.name = "PreviewViewports"
	add_child(_viewports_root)
	_camera = Camera2D.new()
	_camera.name = "PreviewCamera"
	add_child(_camera)
	_camera.make_current()

## The REAL `wall.tscn` — surface, camera, pictures, viewports, overlay, info card and both music
## players, the whole shell the game runs inside. Replaces everything built above.
##
## ⚠ RUNNING ONLY. `Wall` is not `@tool`, so in the Inspector it loads as a PLACEHOLDER and every
## call throws; the hand-built scaffold above is what the editor preview keeps. This is why
## `EDITOR_INERT_KNOBS` exists.
##
## ⚠ `Wall._ready()` sets `get_tree().paused = true` GLOBALLY, and it is KEPT — that is what the
## game does, and it is what makes an unfocused screen freeze. This node is `PROCESS_MODE_ALWAYS`
## so the tool itself keeps running under it, exactly as `Wall`, `%Camera2D` and `%Overlay` are.
func _build_real_wall() -> void:
	_wall = WALL_SCENE.instantiate()
	add_child(_wall)   # NO owner
	_pictures_root = _wall.get_node(^"%Pictures")
	_viewports_root = _wall.get_node(^"%Viewports")
	_camera = _wall.get_node(^"%Camera2D")
	_camera.make_current()
	_overlay = _wall.get_node(^"%Overlay")
	_info_card = _wall.get_node(^"%Overlay/InfoCard")
	_connect_overlay()
	# The wall's OWN input: arrow selection with its held-direction repeat, click to enter,
	# `wall_jump_N`, pinch, Back/Forward/Wall/Info actions. All of it now reaches the preview.
	_wall.picture_enter_requested.connect(func(id: StringName) -> void: _move_to(id))
	_wall.wall_view_entered.connect(func() -> void: _move_to(&""))
	_wall.back_requested.connect(_on_overlay_back)
	_wall.forward_requested.connect(_on_overlay_forward)
	_wall.info_toggle_requested.connect(func() -> void: _overlay.toggle_info())
	_focus_stack = FocusStack.new()

func _connect_overlay() -> void:
	_overlay.back_pressed.connect(_on_overlay_back)
	_overlay.forward_pressed.connect(_on_overlay_forward)
	_overlay.wall_pressed.connect(_on_overlay_wall)
	_overlay.info_toggled.connect(_on_overlay_info_toggled)

func _teardown_preview_pictures() -> void:
	for wp : WallPicture in _preview_pictures.values():
		if is_instance_valid(wp): wp.teardown()
	_preview_pictures.clear()

# ============================================================== Re-pack

## The one place every live edit converges: re-runs `WallPacker.pack()` over `layout`'s current
## fields, `unlocked_ids` and `preview_aspect`, rebuilds every preview `WallPicture` through the
## real `WallPicture.build()`, and reframes the camera to the packed extent.
func _repack() -> void:
	if not layout or not _pictures_root: return
	_teardown_preview_pictures()
	var by_id : Dictionary[StringName, PictureEntry] = {}
	for e : PictureEntry in layout.pictures: by_id[e.id] = e
	var ids : Array[StringName] = []
	for id : StringName in unlocked_ids:
		if by_id.has(id): ids.append(id)
	# `wall_unlock_all` is a real knob with a real effect in the game, so it has one here. Honoured
	# by widening the SIMULATED unlock set rather than by reading `ProfileManager`, which this tool
	# must never touch.
	if preview_settings.wall_unlock_all:
		ids.clear()
		for e : PictureEntry in layout.pictures: ids.append(e.id)
	var rects := WallPacker.pack(layout, ids, preview_aspect)
	for rect : PictureRect in rects:
		var wp : WallPicture = WALL_PICTURE_SCENE.instantiate()
		_pictures_root.add_child(wp)   # NO owner
		wp.build(rect, _build_entry(by_id[rect.id]), _viewports_root, _live_screen(rect.id))
		_preview_pictures[rect.id] = wp
	_last_rects = rects
	# `Wall` records placement order here, which is what `wall_jump_N` counts by. Geometry is a
	# no-op -- every picture was just built at exactly this rect.
	if is_instance_valid(_wall):
		var rects_by_id : Dictionary[StringName, PictureRect] = {}
		for rect : PictureRect in rects: rects_by_id[rect.id] = rect
		_wall.apply_layout(rects_by_id, false)
	_seed_transition_ids()
	_apply_focus()
	_print_debug_readout()
	# Recorded here, not only inside _process()'s poll -- a repack triggered by one of THIS
	# script's own setters (layout/preview_settings/preview_aspect/unlocked_ids all call _repack()
	# directly, for instant feedback) must not leave _watched stale, or the very next poll tick
	# would see a "changed" fingerprint and redundantly repack a second time for the same edit.
	_watched = _fingerprint()
	print("WallEditor: packed %d/%d pictures at aspect %.3f" \
			% [rects.size(), layout.pictures.size(), preview_aspect])

## The real screen for `id`, so the tool shows the wall the way the game does rather than a grid
## of empty frames. `layout_default.tres` carries no `PackedScene` on any entry — the game's
## screens are reparented in by `Main` at runtime — so without this there is nothing to draw.
##
## ⚠ RUNNING ONLY (F6). These are ordinary game scenes: instantiating `menu.tscn`/`map.tscn` inside
## the EDITOR runs their `_ready()` against absent autoloads. Previewing in the Inspector therefore
## draws empty frames, which is the right trade for geometry work; press F6 to see content.
## Freed with the rest of the preview by `_teardown_preview_pictures()` -> `WallPicture.teardown()`.
func _live_screen(id: StringName) -> Node:
	if use_placeholder_content or Engine.is_editor_hint(): return null
	var scene : PackedScene = LIVE_SCREENS.get(id)
	return scene.instantiate() if scene else null

## The authored entry for `id`, or null -- what the music crossfade reads `.music` off.
func _entry_for(id: StringName) -> PictureEntry:
	if not layout: return null
	for e : PictureEntry in layout.pictures:
		if e.id == id: return e
	return null

## The entry `_repack()` builds from: the real entry, or — under `use_placeholder_content` — a
## copy with `scene = null`. Never mutates the real `PictureEntry`, which `save_now` would persist.
func _build_entry(entry: PictureEntry) -> PictureEntry:
	if not use_placeholder_content or entry.scene == null: return entry
	var stand_in := PictureEntry.new()
	stand_in.id = entry.id
	stand_in.slot = entry.slot
	stand_in.size_multiplier = entry.size_multiplier
	stand_in.design_size = entry.design_size
	stand_in.frame_px = entry.frame_px
	stand_in.frame_texture = entry.frame_texture
	stand_in.unlocked_by_default = entry.unlocked_by_default
	stand_in.keep_aspect = entry.keep_aspect
	stand_in.music = entry.music
	stand_in.frame_colour = entry.frame_colour
	stand_in.background_texture = entry.background_texture
	stand_in.scene = null   # the one field placeholder mode actually changes
	return stand_in

## Poses the camera for whatever the preview currently shows — wall view, a focused picture at
## rest, or that picture's info pose. The ONE place the camera is written, so the three cannot
## disagree; the same reason `Main` funnels everything through `_settle_camera()`, and this mirrors
## it branch for branch.
func _pose_camera() -> void:
	if not _camera: return
	var rect := _rect_for(preview_focus_id)
	if rect == null:
		_frame_camera(_last_rects)
		return
	if preview_info_mode:
		var state := WallPicture.info_zoom_state(rect, _viewport_size(), preview_settings)
		_camera.position = state["position"] as Vector2
		_camera.zoom = Vector2.ONE * (state["zoom"] as float)
		return
	_camera.position = rect.centre
	_camera.zoom = Vector2.ONE * WallPicture.focused_scale(rect.size, _viewport_size(),
			preview_settings.wall_overfill_margin)

## Focuses `preview_focus_id` and unfocuses everything else, through the REAL
## `WallPicture.focus()`/`unfocus()`. That is what puts each picture's SubViewport at the resolution
## and texture filter the running game gives it, so `wall_view_min_texture_px` and the sharpness of
## an unfocused picture are visible here rather than only in the game.
func _apply_focus() -> void:
	for id : StringName in _preview_pictures:
		var wp : WallPicture = _preview_pictures[id]
		if not is_instance_valid(wp): continue
		if id == preview_focus_id:
			wp.focus()
			continue
		# ⚠ EVERY non-focused picture is really `unfocus()`ed, never merely skipped. Skipping it
		# leaves `is_focused` true on whatever was focused last, and `Wall._focused_picture()` then
		# reports a picture that is not focused -- which silently kills the wall's filter updates
		# and its held-direction selection repeat, both of which bail when anything is focused.
		#
		# `preview_wall_view_resolution` chooses only the SIZE passed in: the real wall-view
		# footprint, or the viewport's current size, which makes the resize a no-op. Shrinking is
		# off by default because a screen laid out for its `design_size` does not re-flow into a
		# smaller viewport -- it CROPS.
		var footprint := _footprint(_rect_for(id)) if preview_wall_view_resolution 				else Vector2(wp.viewport.size)
		wp.unfocus(footprint)
		# `unfocus()` leaves the viewport at UPDATE_DISABLED, which is right in the game because the
		# picture rendered while it was focused. Here it may never have rendered at all -- so
		# repaint once through the real frozen-texture path.
		wp.mark_for_rerender()
	_apply_selection()
	_apply_info_mode()
	if _focus_stack != null and preview_focus_id != &"" and _focus_stack.current() != preview_focus_id:
		_focus_stack.visit(preview_focus_id)
	_refresh_overlay()

## The on-screen pixel footprint a picture gets while NOT focused, at the tool's own wall-view zoom
## — the same quantity `Main._footprint()` computes for the running game.
func _footprint(rect: PictureRect) -> Vector2:
	if rect == null: return Vector2.ONE
	return rect.size * _wall_view_zoom()

## Applies the wall-view selection cursor. A focused picture is not in wall view, so nothing is
## lifted while one is focused — `WallPicture` enforces that itself; this only chooses the id.
func _apply_selection() -> void:
	for id : StringName in _preview_pictures:
		var wp : WallPicture = _preview_pictures[id]
		if is_instance_valid(wp): wp.set_selected(id == preview_selected_id)

## Tweens the camera to whatever `_pose_camera()` would have snapped it to, over the info clock —
## `wall_transition_delay * wall_info_zoom_scale`, exactly what `Main` gives the real toggle.
##
## ⚠ Snapping here is what made info mode read as instant in the tool while the game animated it.
## A tool whose timing differs from the product cannot be used to judge timing, which is most of
## what this panel is for.
func _animate_camera_to_pose() -> void:
	var before_pos := _camera.position
	var before_zoom := _camera.zoom
	_pose_camera()
	var target_pos := _camera.position
	var target_zoom := _camera.zoom
	_camera.position = before_pos
	_camera.zoom = before_zoom
	var duration := WallTransition.total_duration(preview_settings) \
			* preview_settings.wall_info_zoom_scale
	var tween := _camera.create_tween()
	tween.set_parallel(true)
	tween.tween_property(_camera, "position", target_pos, duration) \
			.set_trans(preview_settings.wall_travel_trans) \
			.set_ease(preview_settings.wall_travel_ease)
	tween.tween_property(_camera, "zoom", target_zoom, duration) \
			.set_trans(preview_settings.wall_travel_trans) \
			.set_ease(preview_settings.wall_travel_ease)

## `wall_debug_readout`'s call site — the same gate `Main` uses, on the same quiescent moments.
func _print_debug_readout() -> void:
	if not is_instance_valid(_wall) or not preview_settings.wall_debug_readout: return
	print(_wall.debug_memory_readout())

## Plays the one-off opening reveal: whatever is focused zooms out to wall view over the ordinary
## clock multiplied by `wall_reveal_delay_scale`, which is the only thing that reads that knob.
func _play_reveal() -> void:
	if Engine.is_editor_hint():
		push_warning("WallEditor: the reveal only plays when the tool is RUN (F6)")
		return
	if preview_focus_id == &"":
		push_warning("WallEditor: focus a picture first -- the reveal is a zoom OUT to wall view")
		return
	_move_to(&"", true, preview_settings.wall_reveal_delay_scale)

## The packed rect for `id`, or null when it is locked or absent from this pack.
func _rect_for(id: StringName) -> PictureRect:
	for rect : PictureRect in _last_rects:
		if rect.id == id: return rect
	return null

## Shows or hides the real `InfoCard` and re-poses the camera. Called by both Info-mode setters and
## by every re-pack, so a width knob or a layout edit is reflected without a second toggle.
##
## ⚠ The card is RUNNING ONLY (F6), like the live screens: it measures itself from theme fonts and
## anchors to the real window, neither of which the Inspector preview has. The camera's info POSE is
## pure arithmetic and works in both.
func _apply_info_mode(animate: bool = false) -> void:
	if animate and not Engine.is_editor_hint() and _camera and _rect_for(preview_focus_id) != null:
		_animate_camera_to_pose()
	else:
		_pose_camera()
	if not is_instance_valid(_info_card): return
	if not preview_info_mode:
		_info_card.reset()
		return
	var wp : WallPicture = _preview_pictures.get(preview_focus_id)
	if wp: _info_card.show_entry(wp.get_info())
	else: _info_card.reset()

## The wall-view zoom, computed exactly as `Wall.wall_view_zoom()` does.
##
## ⚠ THE CROP BIAS IS `layout.view_margin`, NOT `wall_overfill_margin`. They are different knobs
## for different jobs — `wall_overfill_margin` is a PICTURE's own overfill when focused — and using
## the picture knob here framed the preview ~4% tighter than the game while making `view_margin`
## do nothing at all. A tool that composes the wall differently from the product cannot be used to
## rule on composition, which is the one job this framing has.
func _wall_view_zoom() -> float:
	var extent := _wall_extent()
	if extent.size.x <= 0.0 or extent.size.y <= 0.0: return 1.0
	return WallPicture.focused_scale(extent.size, _viewport_size(), 1.0 + layout.view_margin)

## The union of every packed frame-outer rect — the wall's bounding box, as `Wall._wall_extent()`.
func _wall_extent() -> Rect2:
	var extent := Rect2()
	var first := true
	for rect : PictureRect in _last_rects:
		var frame := WallPacker.frame_outer_rect(rect)
		extent = frame if first else extent.merge(frame)
		first = false
	return extent

## Fits the preview camera to the whole wall, through the same formula the game's wall view uses.
func _frame_camera(rects: Array[PictureRect]) -> void:
	if rects.is_empty() or not _camera: return
	var extent := Rect2()
	var first := true
	for rect : PictureRect in rects:
		var frame := WallPacker.frame_outer_rect(rect)
		extent = frame if first else extent.merge(frame)
		first = false
	_camera.position = extent.get_center()
	_camera.zoom = Vector2.ONE * _wall_view_zoom()

func _viewport_size() -> Vector2:
	if is_inside_tree():
		var vp := get_viewport()
		if vp:
			var size := vp.get_visible_rect().size
			if size.x > 0.0 and size.y > 0.0: return size
	return Vector2(1280.0, 720.0)

# ============================================================== Overlay

## Reflects the preview's state back onto the real overlay: Back/Forward enabled from the real
## `FocusStack`, the Wall button hidden below two pictures.
func _refresh_overlay() -> void:
	if not is_instance_valid(_overlay) or _focus_stack == null: return
	_overlay.refresh(_focus_stack, _preview_pictures.size(), preview_focus_id == &"")

func _on_overlay_back() -> void:
	if _move_active: return
	if preview_focus_id == &"":
		var top := _focus_stack.current()
		if top != &"": await _move_to(top, false)
		return
	var target := _focus_stack.back()
	await _move_to(target, false)

func _on_overlay_forward() -> void:
	if _move_active: return
	var target := _focus_stack.forward()
	if target != &"": await _move_to(target, false)

func _on_overlay_wall() -> void:
	if _move_active: return
	await _move_to(&"", false)

func _on_overlay_info_toggled(active: bool) -> void:
	preview_info_mode = active

## Moves the preview to `dest_id` (`&""` = wall view) with a REAL animation, so the overlay and a
## running transition genuinely contend the way they do in the game.
##
## ⚠ This is the tool's OWN mover, not a second copy of `Main`'s orchestration — it drives the
## camera and the focus state and nothing else. It does not touch profiles, screens, music or the
## input lock, all of which are `Main`'s and none of which this tool has.
func _move_to(dest_id: StringName, record: bool = true, duration_scale: float = 1.0) -> void:
	if _move_active or dest_id == preview_focus_id: return
	var source_rect := _rect_for(preview_focus_id)
	var dest_rect := _rect_for(dest_id)
	if dest_id != &"" and dest_rect == null: return
	_move_active = true
	if is_instance_valid(_wall):
		_wall.begin_music_crossfade(_entry_for(dest_id))
	if source_rect != null and dest_rect != null:
		# Picture to picture: the real `WallTransition`, on the real curves.
		var source_wp : WallPicture = _preview_pictures[preview_focus_id]
		var dest_wp : WallPicture = _preview_pictures[dest_id]
		var transition := WallTransition.new()
		var landed : Array[bool] = [false]   # boxed -- lambdas capture locals BY VALUE
		transition.landed.connect(func(_id: StringName) -> void: landed[0] = true)
		transition.request(_camera, source_wp, source_rect, dest_wp, dest_rect, _viewport_size(),
				preview_settings)
		while not landed[0]:
			if is_instance_valid(_wall):
				_wall.update_travel_music(source_rect.centre, dest_rect.centre, _camera.position)
			await get_tree().process_frame
	else:
		# Wall view is one end of this move, which `WallTransition` cannot express -- it only ever
		# runs picture to picture. A plain tween on the authored travel curve, same clock.
		var target_pos := dest_rect.centre if dest_rect else _wall_extent().get_center()
		var target_zoom := _wall_view_zoom()
		if dest_rect:
			target_zoom = WallPicture.focused_scale(dest_rect.size, _viewport_size(),
					preview_settings.wall_overfill_margin)
		var tween := _camera.create_tween()
		tween.set_parallel(true)
		var duration := WallTransition.total_duration(preview_settings) * duration_scale
		var audio_from := source_rect.centre if source_rect else _wall_extent().get_center()
		var audio_to := dest_rect.centre if dest_rect else _wall_extent().get_center()
		tween.tween_method(func(_p: float) -> void:
				if is_instance_valid(_wall):
					_wall.update_travel_music(audio_from, audio_to, _camera.position),
				0.0, 1.0, duration)
		tween.tween_property(_camera, "position", target_pos, duration) \
				.set_trans(preview_settings.wall_travel_trans) \
				.set_ease(preview_settings.wall_travel_ease)
		tween.tween_property(_camera, "zoom", Vector2.ONE * target_zoom, duration) \
				.set_trans(preview_settings.wall_travel_trans) \
				.set_ease(preview_settings.wall_travel_ease)
		await tween.finished
	if is_instance_valid(_wall):
		_wall.finish_music_crossfade()
	_move_active = false
	if record and dest_id != &"": _focus_stack.visit(dest_id)
	# Wall view re-seeds the wall's own selection cursor to the picture just left, as the game does.
	if is_instance_valid(_wall) and dest_id == &"" and preview_focus_id != &"":
		_wall.enter_wall_view(preview_focus_id)
	preview_focus_id = dest_id   # setter re-poses, re-selects and refreshes the overlay

# ============================================================== Transition preview

func _play_transition() -> void:
	if preview_source_id == preview_dest_id or preview_source_id == &"" or preview_dest_id == &"":
		push_warning("WallEditor: pick two DIFFERENT picture ids to preview a transition")
		return
	if not _preview_pictures.has(preview_source_id) or not _preview_pictures.has(preview_dest_id):
		push_warning("WallEditor: both ids must be in unlocked_ids and currently packed")
		return
	var src := _preview_pictures[preview_source_id]
	var dst := _preview_pictures[preview_dest_id]
	var transition := WallTransition.new()
	# Re-frame the preview camera back over the whole wall once the move lands, so the tool is
	# never left staring at just the two pictures the last preview used.
	transition.landed.connect(func(_id: StringName) -> void: _pose_camera())
	transition.request(_camera, src, src.rect, dst, dst.rect, _viewport_size(), preview_settings)
	print("WallEditor: previewing %s -> %s with the real WallTransition curves" \
			% [preview_source_id, preview_dest_id])

# ============================================================== Live-edit watch (WATCH_SECS)

## Every Inspector-visible value of `layout` (recursing into its `PictureEntry` array) and
## `preview_settings`, flattened for comparison. Polled rather than driven by per-field setters so
## it cannot go stale when a field is added to either class.
func _fingerprint() -> Array:
	var out : Array = []
	_read_into(layout, out, 3)
	_read_into(preview_settings, out, 1)
	return out

func _read_into(res: Resource, out: Array, depth: int) -> void:
	if not res or depth <= 0:
		out.append(null)
		return
	for prop : Dictionary in res.get_property_list():
		var usage : int = prop["usage"]
		if not (usage & PROPERTY_USAGE_EDITOR): continue
		var key : StringName = prop["name"]
		var value : Variant = res.get(key)
		# ⚠ Copy the reference types: `Array`/`Dictionary` are references, so an entry edited in
		# place would compare equal to itself forever.
		if value is Array: value = (value as Array).duplicate()
		elif value is Dictionary: value = (value as Dictionary).duplicate()
		out.append(value)
		if value is Resource:
			_read_into(value as Resource, out, depth - 1)
		elif value is Array:
			for item : Variant in (value as Array):
				if item is Resource: _read_into(item as Resource, out, depth - 1)

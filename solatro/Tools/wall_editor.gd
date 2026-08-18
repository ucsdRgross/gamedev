@tool
class_name WallEditor
extends Node2D
## S34 (PLAN.md Phase 8; M5-M9, Q179, Q181-Q183, Q185, Q200) — THE PICTURE-WALL LAYOUT TOOL.
## Open `Tools/wall_editor.tscn` (same "open it, drag the knobs in the Inspector" UX
## `Tools/fx_editor.tscn`/`Tools/spotlight_tool.tscn` already establish) and every
## `WallLayout`/`PictureEntry`/`PlayerSettings` "Picture wall" field is live-editable, with the
## packed wall rebuilt on every change. "THE TOOL IS WHERE THE NUMBERS GET DECIDED, NOT THE
## PLAN DOCUMENT" (PLAN.md §2 S34) — every value below is a live, editable field, never a
## constant.
##
## WHAT IT EDITS (three separate `@export` resources/fields, each shown as its own Inspector
## panel — no custom UI was built; the Inspector already gives every field, add/remove-array
## support and undo for free, the same reason `fx_editor.gd`/`spotlight_tool.gd` never built one
## either):
##  * `layout` — every `WallLayout` field (`pictures`, `home_id`, `gap_px`, the ellipse clamps,
##    `view_margin`) AND every `PictureEntry` field per picture (the Inspector's own
##    `Array[PictureEntry]` editor expands each entry — `slot`, `size_multiplier`, `design_size`,
##    `frame_px`, `frame_texture`, `frame_colour` (GAP-013=a), `keep_aspect`, `music` (S33),
##    `background_texture` (GAP-015=a); `ring` is correctly ABSENT — GAP-009 deleted it, and
##    NAMES.md fixes no field of that name to reintroduce).
##  * `preview_settings` — a REAL, standalone `PlayerSettings` (never the shipped
##    `user://settings.tres`, M9/Q200: "never reads or writes profile data" applies to any player
##    state, and a knob tuned here must never silently move a real player's save). Every
##    `@export_group("Picture wall")` row shows here, live, because it is the SAME class
##    `player_settings.gd` already is (`@tool` for the SAME placeholder-instance reason this file
##    needs it, see `PlayerSettings`'s own header).
##  * `preview_aspect` / `unlocked_ids` / `preview_source_id` / `preview_dest_id` /
##    `play_transition` / `save_now` / `revert_now` — the tool's OWN state: Q181=a's aspect
##    slider, Q182=a's unlock simulation, Q183=a's transition picker, and M8's save/revert.
##    `save_now`/`revert_now`/`play_transition` are booleans that act as BUTTONS and reset
##    themselves the instant they run — there is no `@export`-button annotation in this Godot
##    version, and this is the established, purely-declarative way to get one without a custom
##    scene (no other tool in this repo needed a button at all, so there is no in-repo precedent
##    to follow instead).
##
## ⚠ EDITOR FACTS, same category as `fx_editor.gd`'s own header (each cost real time there):
##  * **Every script this tool loads/builds must be `@tool`** (`WallLayout`, `PictureEntry`,
##    `WallPicture` — `WallFrame` does not exist as a script; `%Frame` is a bare `NinePatchRict`
##    node, so there is nothing to annotate). A non-`@tool` script loads in the editor as a
##    PLACEHOLDER: reads still work, but a method call throws "Attempt to call a method on a
##    placeholder instance", and — the sharper trap — SAVING a `.tres` whose script is a
##    placeholder silently DROPS every property the editor could not see (`fx_editor.gd`'s own
##    scar, `fire_card.tres` losing fields on 2026-07-28). `Q185`=a ("the SAME resource, directly")
##    makes this load-bearing: a placeholder-corrupted save would corrupt the file the GAME loads.
##  * **The editor instantiates NO autoloads.** `WallPicture.build()` reads
##    `SettingsManager.settings.wall_light_offset` directly (its own established idiom — it is not
##    a pure function the way `WallPacker`/`WallTransition.sample_at()` are, ASSUMPTIONS.md), so
##    this tool stands in a REAL `SettingsManagerClass` at `/root/SettingsManager` ONLY when one is
##    genuinely absent (in-editor; an F6-run already has the real one), seeded with THIS tool's own
##    `preview_settings` — so `wall_light_offset` is live from the SAME knob every other field
##    reads. Never touches an ALREADY-PRESENT `SettingsManager` (an F6-run's real one, or a second
##    tool instance's), and frees only the one it created itself.
##  * **`Camera2D` does not drive the EDITOR's own 2D viewport.** Only a RUNNING scene's window
##    follows a current camera — the editor's pan/zoom is the user's own, independent of any node.
##    `preview_aspect`/`unlocked_ids`/every layout field are equally live either way (the packed
##    result simply appears at whatever the editor is scrolled to), but Q183's transition preview
##    — "play the camera move" — is only something to WATCH when this scene is actually RUN (F6 or
##    the console exe), exactly like `Tests/Visual/*_snapshot.gd` diagnostics already are.
##  * **Every preview `WallPicture` is OWNERLESS and rebuilt from scratch on every re-pack**
##    (`fx_editor.gd`'s own "every node this builds is OWNERLESS" rule) — an owned child would be
##    SAVED into `wall_editor.tscn` itself.
##
## Q200=a: this script never references `ProfileManager` or `user://profile.tres` anywhere —
## `unlocked_ids` is a plain in-memory simulation, never a read OR a write of real profile data.

const LAYOUT_PATH := "res://Assets/Wall/layout_default.tres"
const WALL_PICTURE_SCENE := preload("res://UI/Wall/wall_picture.tscn")
## How often the tool re-reads every inspector-visible field of `layout`/`preview_settings` for a
## change nothing else notifies it of — `fx_editor.gd`'s own `WATCH_SECS`, same reason: a plain
## `@export var` with no custom setter (every `WallLayout`/`PictureEntry` field) does not announce
## being edited IN PLACE inside a nested Inspector panel.
const WATCH_SECS := 0.25

## Q179=c, Q185=a: the authored pattern this tool edits and saves — `res://Assets/Wall/
## layout_default.tres` directly, the SAME resource the game loads. Seeded from `Wall.
## initial_layout()` (the same starting content the real game boots with) the first time this
## tool runs and no file exists yet — THIS is the step that writes it for the first time.
@export var layout : WallLayout = null:
	set(v):
		layout = v
		_seed_unlocked_ids()
		_repack()

## A REAL, STANDALONE `PlayerSettings` — never `SettingsManager.settings` (M9/Q200: this tool
## must never read or write real player state, and "Picture wall" knobs are player-tunable, not
## profile data, but treating them identically to profile data here costs nothing and removes any
## risk of a tuning session silently rewriting `user://settings.tres`). Every "Picture wall" row
## shows in the Inspector because this IS `player_settings.gd`'s own class.
@export var preview_settings : PlayerSettings = PlayerSettings.new():
	set(v):
		preview_settings = v
		_apply_settings_stand_in()
		_repack()

## Q181=a: "an aspect slider that re-packs live." 0.5-4.0 spans well outside `WallLayout`'s own
## ellipse clamps (1.2-2.6 at their shipped defaults) on purpose, so the CLAMPING behaviour itself
## is visible at the extremes, not just the range it does nothing in.
@export_range(0.5, 4.0, 0.01) var preview_aspect : float = 1.7778:
	set(v):
		preview_aspect = v
		_repack()

## Q182=a: which picture ids are simulated as unlocked. Seeded from every `unlocked_by_default`
## id the first time a layout loads (never left empty/blank by default); edit freely afterward —
## an id absent here is LOCKED, matching `Q158`=a's own "absent entirely, not a placeholder"
## semantics for the real game.
@export var unlocked_ids : Array[StringName] = []:
	set(v):
		unlocked_ids = v
		_repack()

@export_group("Transition preview (Q183=a)")
## The two ids to preview a move between — must both be currently unlocked (in `unlocked_ids`)
## for `play_transition` to do anything.
@export var preview_source_id : StringName = &""
@export var preview_dest_id : StringName = &""
## Acts as a BUTTON: flips true, runs once, resets itself to false. Builds a REAL
## `WallTransition` between the two picked pictures' REAL packed rects and REAL `Camera2D` — "the
## real curves" (Q183=a), not a private re-derivation. Most meaningful watched through an actual
## running window (F6/console exe) — see the class doc comment's "Camera2D does not drive the
## editor's own 2D viewport" note.
@export var play_transition : bool = false:
	set(v):
		play_transition = false
		if v: _play_transition()

@export_group("Content mode (GAP-017=c)")
## GAP-017 (owner-answered c): an author-facing toggle, DEFAULT REAL CONTENT -- `/CLAUDE.md` rule 5
## ("no mocks in tools") governs the DEFAULT path, honouring `Q180`'s own default without silently
## withdrawing M6, which asked for placeholders. Flipping this true trades truth for speed while
## tuning geometry (M6's own motive: the tool must re-pack instantly while an author drags numbers,
## and hosting live screens is heavier than drawing empty frames) -- an EXPLICIT, visible opt-in,
## never silent, so a defect that only shows with real content on the wall (this run found three:
## the overfill margin clipping start_menu's own buttons, the overlay covering Profile/Options,
## frame-corner behaviour at extreme sizes) cannot hide behind a placeholder by default.
@export var use_placeholder_content : bool = false:
	set(v):
		use_placeholder_content = v
		_repack()

@export_group("Save (M8, Q185=a)")
## Acts as a BUTTON. Writes `layout` to `LAYOUT_PATH` directly — the same resource the game loads,
## never a copy (Q185=a).
@export var save_now : bool = false:
	set(v):
		save_now = false
		if v: _save()
## Acts as a BUTTON. Discards every in-memory edit and reloads `layout` fresh from `LAYOUT_PATH`
## (or reseeds `Wall.initial_layout()` if nothing has been saved yet).
@export var revert_now : bool = false:
	set(v):
		revert_now = false
		if v: _revert()

var _watch_wait := 0.0
## Every inspector-visible value of `layout` and `preview_settings`, as of the last rebuild — see
## `_fingerprint()`.
var _watched : Array = []

var _pictures_root : Node2D = null
var _viewports_root : Node = null
var _camera : Camera2D = null
var _preview_pictures : Dictionary[StringName, WallPicture] = {}
var _last_rects : Array[PictureRect] = []

## True only when THIS instance created `/root/SettingsManager` itself — see the class doc
## comment's "no autoloads in the editor" note.
var _owns_settings_stand_in := false

func _ready() -> void:
	_ensure_settings_stand_in()
	_build_preview_scaffold()
	if layout:
		_seed_unlocked_ids()
		_repack()
	else:
		layout = _load_or_seed_layout()   # setter itself seeds + repacks

func _exit_tree() -> void:
	if not _owns_settings_stand_in: return
	var root := get_tree().root if is_inside_tree() else null
	if root and root.has_node(^"SettingsManager"):
		root.get_node(^"SettingsManager").queue_free()

func _process(delta: float) -> void:
	_watch_wait += delta
	if _watch_wait < WATCH_SECS: return
	_watch_wait = 0.0
	if _fingerprint() != _watched:
		_repack()

# ============================================================== SettingsManager stand-in

func _ensure_settings_stand_in() -> void:
	if not is_inside_tree(): return
	var root := get_tree().root
	if root.has_node(^"SettingsManager"):
		return
	var stand_in := SettingsManagerClass.new()
	stand_in.name = "SettingsManager"
	root.add_child(stand_in)
	_owns_settings_stand_in = true
	_apply_settings_stand_in()

func _apply_settings_stand_in() -> void:
	if not _owns_settings_stand_in or not is_inside_tree(): return
	var root := get_tree().root
	if root.has_node(^"SettingsManager"):
		(root.get_node(^"SettingsManager") as SettingsManagerClass).settings = preview_settings

# ============================================================== Layout load / save / revert

## Q185=a: the SAME resource the game loads, loaded fresh off disk (never the editor's resource
## path cache, so a Revert genuinely discards in-memory edits rather than handing back the same
## mutated object — the same `CACHE_MODE_IGNORE` reasoning `test_wall_profile.gd`'s R2 already
## established for "a real disk read, not the path cache").
func _load_or_seed_layout() -> WallLayout:
	if ResourceLoader.exists(LAYOUT_PATH):
		return ResourceLoader.load(LAYOUT_PATH, "", ResourceLoader.CACHE_MODE_IGNORE) as WallLayout
	# S34 is the step that writes this resource for the first time -- seed from the SAME starting
	# content the real game boots with (Wall.initial_layout()) rather than an empty layout, so
	# there is something real to tune immediately.
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

## Q182=a: seeds every `unlocked_by_default` id the FIRST time a layout is assigned (an empty
## `unlocked_ids` reads as "nothing chosen yet", not "everything locked on purpose") -- never
## overwrites a simulation already in progress.
func _seed_unlocked_ids() -> void:
	if not layout or not unlocked_ids.is_empty(): return
	var seeded : Array[StringName] = []
	for e : PictureEntry in layout.pictures:
		if e.unlocked_by_default: seeded.append(e.id)
	unlocked_ids = seeded   # fires this field's own setter -> one extra harmless repack

# ============================================================== Live preview scaffold

## The tool's own minimal stand-in for `Wall` -- deliberately NOT a real `Wall` instance
## (`Wall._ready()` sets `get_tree().paused = true` GLOBALLY, which would freeze the EDITOR's own
## tree and every other open `@tool` scene alongside it; `TestWallRender`'s own suite hit exactly
## this hang and had to undo it immediately for the same reason, ASSUMPTIONS.md's S10 entry).
## Reuses `WallPicture`/`WallPacker`/`WallTransition` directly -- the real packing and framing
## code, never a re-derivation -- just not the pausing shell around them.
func _build_preview_scaffold() -> void:
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

func _teardown_preview_pictures() -> void:
	for wp : WallPicture in _preview_pictures.values():
		if is_instance_valid(wp): wp.teardown()
	_preview_pictures.clear()

# ============================================================== Re-pack

## The one place every live edit converges: re-runs the REAL `WallPacker.pack()` over `layout`'s
## current fields, `unlocked_ids` and `preview_aspect`, rebuilds every preview `WallPicture`
## through the REAL `WallPicture.build()` (Q180's own default, "no mocks in tools" — CLAUDE.md
## rule 5 — a picture whose `PictureEntry.scene` is set hosts that REAL scene; one left null shows
## exactly what the real game shows for it too, Q214=a's "registered but unbuilt"), and reframes
## the preview camera to the packed extent.
func _repack() -> void:
	if not layout or not _pictures_root: return
	_teardown_preview_pictures()
	var by_id : Dictionary[StringName, PictureEntry] = {}
	for e : PictureEntry in layout.pictures: by_id[e.id] = e
	var ids : Array[StringName] = []
	for id : StringName in unlocked_ids:
		if by_id.has(id): ids.append(id)
	var rects := WallPacker.pack(layout, ids, preview_aspect)
	for rect : PictureRect in rects:
		var wp : WallPicture = WALL_PICTURE_SCENE.instantiate()
		_pictures_root.add_child(wp)   # NO owner
		wp.build(rect, _build_entry(by_id[rect.id]), _viewports_root)
		_preview_pictures[rect.id] = wp
	_last_rects = rects
	_frame_camera(rects)
	# Recorded here, not only inside _process()'s poll -- a repack triggered by one of THIS
	# script's own setters (layout/preview_settings/preview_aspect/unlocked_ids all call _repack()
	# directly, for instant feedback) must not leave _watched stale, or the very next poll tick
	# would see a "changed" fingerprint and redundantly repack a second time for the same edit.
	_watched = _fingerprint()
	print("WallEditor: packed %d/%d pictures at aspect %.3f" \
			% [rects.size(), layout.pictures.size(), preview_aspect])

## GAP-017=c: the entry `_repack()` actually builds FROM -- the real entry unchanged (default,
## Q180/CLAUDE.md rule 5), or a placeholder STAND-IN with `scene = null` when
## `use_placeholder_content` is on (M6's own speed motive). Never mutates the real `PictureEntry`
## `save_now` would otherwise persist -- a fresh copy, every field but `scene` carried over exactly.
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

## Fits the preview camera to the union of every packed frame-outer rect -- `WallPicture.
## focused_scale()`'s own fill formula (H3), the SAME one `Wall.wall_view_zoom()` uses for the
## real game's wall view, just applied here instead of re-derived.
func _frame_camera(rects: Array[PictureRect]) -> void:
	if rects.is_empty() or not _camera: return
	var extent := Rect2()
	var first := true
	for rect : PictureRect in rects:
		var frame := WallPacker.frame_outer_rect(rect)
		extent = frame if first else extent.merge(frame)
		first = false
	_camera.position = extent.get_center()
	_camera.zoom = Vector2.ONE * WallPicture.focused_scale(extent.size, _viewport_size(),
			preview_settings.wall_overfill_margin)

func _viewport_size() -> Vector2:
	if is_inside_tree():
		var vp := get_viewport()
		if vp:
			var size := vp.get_visible_rect().size
			if size.x > 0.0 and size.y > 0.0: return size
	return Vector2(1280.0, 720.0)

# ============================================================== Transition preview (Q183=a)

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
	transition.landed.connect(func(_id: StringName) -> void: _frame_camera(_last_rects))
	transition.request(_camera, src, src.rect, dst, dst.rect, _viewport_size(), preview_settings)
	print("WallEditor: previewing %s -> %s with the real WallTransition curves" \
			% [preview_source_id, preview_dest_id])

# ============================================================== Live-edit watch (WATCH_SECS)

## `fx_editor.gd`'s own `_fingerprint()`/`_read_into()`, applied to `layout` (recursing into its
## `pictures : Array[PictureEntry]` -- the one extension this needed beyond fx_editor's own
## version, which never held an array of sub-resources) and `preview_settings`. Polling rather
## than hand-written setters on every `WallLayout`/`PictureEntry` field: one place, and it cannot
## go stale when a field is added to either class.
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
		# ⚠ COPY THE REFERENCE TYPES -- `Array`/`Dictionary` are references in GDScript, so an
		# entry edited IN PLACE would otherwise compare equal to itself forever (fx_editor.gd's own
		# measured trap: "the fire ramp was the one thing the watch could not see").
		if value is Array: value = (value as Array).duplicate()
		elif value is Dictionary: value = (value as Dictionary).duplicate()
		out.append(value)
		if value is Resource:
			_read_into(value as Resource, out, depth - 1)
		elif value is Array:
			for item : Variant in (value as Array):
				if item is Resource: _read_into(item as Resource, out, depth - 1)

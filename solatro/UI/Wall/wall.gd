class_name Wall
extends Node2D
## The picture-wall shell root — owns the camera, the pictures and (from S35) the overlay
## (PLAN.md §1.6, NAMES.md). S9 skeleton only for construction/pause; S36 adds wall-view framing
## (G9), clamped pan (G10) and selection (F10-F12) over whatever pictures already exist under
## %Pictures -- population from a real WallLayout is still a later (Phase 7) step, same as every
## existing Wall-render test (TestWallRender, TestWallPause) already builds its own fixture
## pictures externally rather than through this class.

## Pauses the whole tree once, at construction, and NEVER clears it (§1.6, `QR6`=a) — the wall's
## own root and `%Camera2D` are `PROCESS_MODE_ALWAYS` so they keep running regardless, and each
## screen opts back in individually via its own process mode (S12).
func _ready() -> void:
	get_tree().paused = true

## S30/S31 (M1-M4, B7, K6, Q211=a, L1) + register-settings-book correction (coordinator): the
## wall's own starting content -- SIX registered ids, matching NAMES.md's full picture-id table in
## full, not the four this run originally shipped. `start_menu` (home, Q9=a), `map`, `deck` and
## `game` are basic navigation, every one `unlocked_by_default`. `entry.scene` stays null on all
## six: `start_menu`/`map` are ALREADY-INSTANTIATED, PERSISTENT nodes (Q141=a) the caller
## reparents via `WallPicture.build()`'s `live_screen` parameter; `game` is attached later, per
## show, via `attach_screen()` (S31, L2); `deck` has no dedicated persistent screen built yet (see
## ASSUMPTIONS.md); `settings`/`book` are "registered ids with no scene" PER PLAN.md §4 anti-scope
## item 2 -- registered, not absent -- and stay that way: building either's CONTENTS is explicitly
## forbidden by that same anti-scope item, `null` is the correct, permanent-for-this-run value of
## `entry.scene`, not a placeholder waiting to be filled in this pass.
##
## `settings.unlocked_by_default = true`: a settings/options screen is conventionally reachable
## from first launch in every genre this design otherwise follows, and nothing in DESIGN.md gates
## it -- Q212's own text treats it as "a registered picture on the wall" now, contents later, never
## as content the K-chart's unlock system is FOR. `book.unlocked_by_default = false`: the
## information book is the one registered picture with no navigational necessity (unlike the other
## five, none of which the app can do without), making it the natural first real instance of
## QR2=a's own stated point ("pictures unlock over time... the wall grows the way that player
## played") -- Q6=c's "unlockable... set dressing" is the closest tonal parallel DESIGN.md draws
## for gated wall content. Neither line is a literal design citation (none exists for either
## picture's lock state specifically) -- both are reasoned readings, recorded here rather than
## picked silently, exactly per gap-protocol rule 1. `book` being locked also gives F12 (S38) a
## REAL locked-then-unlocked id to exercise K2's "no reveal ceremony" half against the real wiring,
## which the four-picture layout could not provide (every one of THOSE four is `unlocked_by_default`).
##
## `frame_texture` uses the one shared style (S24) on all six. `slot` values are starting angles
## only -- GAP-010's unconditional rebalancing (ASSUMPTIONS.md) decides the resolved angles
## regardless of what is authored here; their relative ORDER is what is authored, not the literal
## degrees.
const LAYOUT_PATH := "res://Assets/Wall/layout_default.tres"

## NAMES.md's files-on-disk table: `res://Assets/Wall/layout_default.tres` is the layout the game
## runs on, and S34's tool edits that same resource (Q179=c, Q185=a). Nothing loaded it before —
## `Main` called `initial_layout()` directly, so every value an author tuned in the tool was
## discarded (ADVERSARIAL_REVIEW C6), and the authored pattern lived as literals in a `.gd`, which
## §1.8 forbids.
##
## Falls back to `initial_layout()` when the file is absent, so a fresh checkout still boots. `path`
## is a parameter purely so a test can point at a temp file and prove the returned layout really
## came from disk rather than from the fallback — no mock, just the real loader on a real file.
static func load_layout(path: String = LAYOUT_PATH) -> WallLayout:
	if ResourceLoader.exists(path):
		var loaded : Resource = ResourceLoader.load(path)
		if loaded is WallLayout: return loaded as WallLayout
		push_error("Wall.load_layout: %s exists but did not load as a WallLayout -- " % path
				+ "falling back to the built-in layout")
	return initial_layout()

static func initial_layout() -> WallLayout:
	var layout := WallLayout.new()
	layout.home_id = &"start_menu"
	var start_menu := PictureEntry.new()
	start_menu.id = &"start_menu"
	start_menu.slot = 0
	start_menu.unlocked_by_default = true
	start_menu.frame_texture = WallPicture.shared_frame_texture()
	var book := PictureEntry.new()
	book.id = &"book"
	book.slot = 45
	book.unlocked_by_default = false
	book.frame_texture = WallPicture.shared_frame_texture()
	var map := PictureEntry.new()
	map.id = &"map"
	map.slot = 90
	map.unlocked_by_default = true
	map.frame_texture = WallPicture.shared_frame_texture()
	var deck := PictureEntry.new()
	deck.id = &"deck"
	deck.slot = 180
	deck.unlocked_by_default = true
	deck.frame_texture = WallPicture.shared_frame_texture()
	var game := PictureEntry.new()
	game.id = &"game"
	game.slot = 270
	game.unlocked_by_default = true
	game.frame_texture = WallPicture.shared_frame_texture()
	var settings := PictureEntry.new()
	settings.id = &"settings"
	settings.slot = 315
	settings.unlocked_by_default = true
	settings.frame_texture = WallPicture.shared_frame_texture()
	layout.pictures = [start_menu, book, map, deck, game, settings]
	return layout

## S31 (G9's own formula, exposed): the wall-view camera's TARGET POSITION -- the centre of every
## packed picture's own frame-outer-rect union. `wall_view_zoom()` already exposes the matching
## target ZOOM; this is its position counterpart, needed by whatever animates the camera TO wall
## view (M2's reveal, or an ordinary Back-to-wall-view) since `_wall_extent()` itself is private.
func wall_view_centre() -> Vector2:
	return _wall_extent().get_center()

## S30 (K6, Q145=b, Q149=a): "wall state does not survive a quit -- every launch opens on the
## start-menu picture." A FRESH `FocusStack`, pre-visited with `&"start_menu"` -- the one and only
## authored starting point, never read back from any save file (`FocusStack` itself persists
## nothing, ASSUMPTIONS.md; nothing on `PlayerProfile`/`PlayerSettings` holds a "current picture"
## field either, `TestWallFocus` F13 asserts both halves). Calling this twice must produce two
## INDEPENDENT stacks -- mutating one must never affect the other, which is what "does not
## survive" actually cashes out to for a value that is never written anywhere in between.
static func cold_launch_focus_stack() -> FocusStack:
	var stack := FocusStack.new()
	stack.visit(&"start_menu")
	return stack

## An explicit request for WALL VIEW itself, not for Back: the Wall button, and pinch-in
## (Q119=a, "pinch in goes to wall view"). Q65=a's "Back at the bottom of the stack goes to wall
## view" is NOT this signal -- that fall-through is the `FocusStack`'s own verdict, reached through
## `back_requested` below, and only `Main` holds the stack to ask.
signal wall_view_entered

## M2 (ADVERSARIAL_REVIEW): Back was pressed (`ui_cancel`, with the focused screen taking first
## refusal per I5/Q100=a). `ui_cancel` used to emit `wall_view_entered` outright, so keyboard Back
## did WALL -- it skipped the history entirely and dropped the player to the overview from any
## depth, which Q65=a forbids ("Back retraces the FocusStack one step at a time"). `Wall` does not
## own the stack, so it announces the INTENT and `Main._on_back_pressed()` -- the SAME handler the
## overlay's own Back button already uses, so the two paths cannot diverge -- decides what Back
## means, including falling through to wall view once the stack reports nothing behind.
signal back_requested

## M3 (ADVERSARIAL_REVIEW): Forward was pressed -- `wall_forward` (R1/RB). Same shape and the same
## reason as `back_requested`: only `Main` holds the `FocusStack`, so only it can say whether there
## is anything ahead. Nothing read `wall_forward` at all before this, so a controller had no Forward.
signal forward_requested

## M3 (ADVERSARIAL_REVIEW): Info was toggled from the KEYBOARD (`wall_info`, `I`). Carries no state:
## `WallOverlay`'s own toggle button is the single source of truth for whether Info is on (J1's
## "persistent toggle... always accessible"), so `Main` flips THAT and lets its existing
## `info_toggled` chain run, rather than writing `wall_info_mode` from a second place and leaving the
## button reading un-pressed -- which is exactly the state C3 already had to clean up once.
signal info_toggle_requested

## A4 (CODE_REVIEW.md): NAMES.md's signal table fixes these three; nothing declared or emitted
## them until now. `Wall` does not orchestrate focus/transitions itself -- `Main` does (the same
## "camera and clock only" boundary ASSUMPTIONS.md already draws for `WallTransition`) -- so these
## are emitted BY `Main`, at the exact moments they occur in its own orchestration, not re-derived
## or guessed at here.
signal focus_changed(picture_id: StringName)
signal transition_started(from_id: StringName, to_id: StringName)
signal transition_landed(picture_id: StringName)

## S31 (I3/I4 design nodes, Q88=a "click enters immediately", Q99=a "ui_accept enters the
## selected picture"): fired from WALL VIEW when the player commits to a destination -- a click
## landing inside an UNFOCUSED picture's own frame-outer rect, or `ui_accept` on whichever picture
## is currently `selected_id`. NOT in NAMES.md's own signal table (written before any step reached
## real navigation); named to match `wall_view_entered`'s own "the wall announces player INTENT,
## the caller decides what that means" shape -- `Wall` has no notion of GameView/menu/map at all,
## so acting on this (building a fresh screen, attaching one, or just focusing what is already
## there) is deliberately the caller's job, not this class's (ASSUMPTIONS.md).
signal picture_enter_requested(id: StringName)

## A3 (CODE_REVIEW.md, GAP-003=a): one tracker for the whole wall's touch session -- `Wall` is the
## thing that actually owns input routing/focus state, so this is where `WallInput.PinchTracker`
## (built and tested in isolation by S23, never wired) belongs, per `wall_input.gd`'s own doc
## comment naming "Wall" as the eventual owner.
var _pinch := WallInput.PinchTracker.new()

## S19/S21 (Q100=a): the wall reads input in `_unhandled_input` ONLY, so a focused screen's own
## Controls/`_unhandled_input` always get FIRST REFUSAL -- the same pattern
## `world_map_controller.gd:217` already uses. Routes to the focused picture via `WallInput.route()`
## first; if that picture's OWN viewport marks the event handled, the wall does nothing more (I3).
## Q103=a/Q115=a: arrow-key SELECTION only ever runs with NO picture focused (wall view) -- "the
## wall never listens while a screen is focused" (I14). `ui_cancel`/pinch-in (Back) and
## `wall_jump_N` are the only wall-level actions still meaningful either way.
func _unhandled_input(event: InputEvent) -> void:
	var focused := _focused_picture()
	if focused:
		WallInput.route(event, focused)
		if focused.viewport and focused.viewport.is_input_handled():
			return
	else:
		if event.is_action_pressed(&"ui_up"):
			move_selection(Vector2.UP)
			get_viewport().set_input_as_handled()
			return
		if event.is_action_pressed(&"ui_down"):
			move_selection(Vector2.DOWN)
			get_viewport().set_input_as_handled()
			return
		if event.is_action_pressed(&"ui_left"):
			move_selection(Vector2.LEFT)
			get_viewport().set_input_as_handled()
			return
		if event.is_action_pressed(&"ui_right"):
			move_selection(Vector2.RIGHT)
			get_viewport().set_input_as_handled()
			return
		# Q99=a: ui_accept enters the currently selected picture.
		if event.is_action_pressed(&"ui_accept") and selected_id != &"":
			get_viewport().set_input_as_handled()
			picture_enter_requested.emit(selected_id)
			return
		# Q88=a: a click landing inside an unfocused picture's own frame enters it immediately --
		# hit-tested in WALL SPACE. Reads the EVENT's own `position` through the viewport's own
		# `canvas_transform` (which already reflects the active camera's position/zoom), rather
		# than `get_global_mouse_position()` (the OS cursor's CURRENT position) -- the two agree
		# for a real click, but only the event-driven read is something a synthetic test event can
		# actually control without moving the real mouse cursor.
		if event is InputEventMouseButton:
			var mb := event as InputEventMouseButton
			if mb.button_index == MOUSE_BUTTON_LEFT:
				if not mb.pressed:
					_panning = false
				else:
					var wall_pos : Vector2 = get_viewport().canvas_transform.affine_inverse() * mb.position
					var clicked_id := _picture_at(wall_pos)
					if clicked_id != &"":
						get_viewport().set_input_as_handled()
						picture_enter_requested.emit(clicked_id)
						return
					# M4/G10: a press on BARE WALL still does nothing by itself (Q93=a) -- it only
					# ARMS a pan drag, which moves nothing until the pointer actually moves, and
					# nothing at all on a window already showing the whole wall (`pan_by()`).
					_panning = true
		elif _panning and event is InputEventMouseMotion:
			get_viewport().set_input_as_handled()
			pan_by((event as InputEventMouseMotion).relative)
			return
	# A3 (Q119=a): pinch reaches here only if the focused screen (if any) did not consume the touch
	# itself first -- the same "first refusal" contract every other wall-level action already gets
	# (Q100=a), since this runs after the `WallInput.route()`/`is_input_handled()` early-return
	# above. Pinch-OUT mirrors ui_accept's own scope (Q99=a, wall-view only, commits the current
	# selection); pinch-IN is Q119=a's own literal "pinch in goes to wall view", which is why it
	# stays on `wall_view_entered` while `ui_cancel` below is Back (M2).
	var gesture := _pinch.feed(event, SettingsManager.settings.wall_pinch_threshold_px)
	if gesture == WallInput.PinchTracker.Gesture.PINCH_OUT:
		if not focused and selected_id != &"":
			get_viewport().set_input_as_handled()
			picture_enter_requested.emit(selected_id)
			return
	elif gesture == WallInput.PinchTracker.Gesture.PINCH_IN:
		get_viewport().set_input_as_handled()
		wall_view_entered.emit()
		return
	# M2/I5/Q100=a: keyboard Back, after the focused screen's first refusal above. Announces Back,
	# never wall view -- see `back_requested`'s own doc comment.
	if event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		back_requested.emit()
		return
	# M3 (ADVERSARIAL_REVIEW): the four `wall_*` InputMap actions had NO READER anywhere, so Tab,
	# L1/LB, R1/RB and `I` all did nothing and a controller had no Back, Forward or Wall at all.
	# Read here, alongside `ui_cancel` and `wall_jump_N`, because I6/Q102=a makes them ordinary
	# rebindable actions and I9/Q103=a/Q115=a scopes only the SELECTION keys to wall view -- these
	# four are meaningful focused or not, and each gets the same first refusal as everything above.
	if event.is_action_pressed(&"wall_overview"):
		get_viewport().set_input_as_handled()
		wall_view_entered.emit()
		return
	if event.is_action_pressed(&"wall_back"):
		get_viewport().set_input_as_handled()
		back_requested.emit()
		return
	if event.is_action_pressed(&"wall_forward"):
		get_viewport().set_input_as_handled()
		forward_requested.emit()
		return
	if event.is_action_pressed(&"wall_info"):
		get_viewport().set_input_as_handled()
		info_toggle_requested.emit()
		return
	for n : int in range(1, 10):
		if event.is_action_pressed(StringName("wall_jump_%d" % n)):
			_jump_to_index(n - 1)
			get_viewport().set_input_as_handled()
			return

## The one picture currently `is_focused`, or null in wall view (at most one, by construction --
## `focus()`/`unfocus()` are the caller's own responsibility to keep exclusive, same contract
## `WallPicture.focus()`'s own doc comment already states).
func _focused_picture() -> WallPicture:
	for child : Node in %Pictures.get_children():
		var wp := child as WallPicture
		if wp and wp.is_focused: return wp
	return null

## Q88=a's own hit-test: the id of whichever picture's FRAME OUTER rect contains `wall_pos`, or
## `&""` if none does. Frame outer (not the bare picture rect) so clicking the frame itself --
## which is what most of a picture reads as at wall-view zoom -- counts too.
func _picture_at(wall_pos: Vector2) -> StringName:
	for child : Node in %Pictures.get_children():
		var wp := child as WallPicture
		if wp and wp.rect and WallPacker.frame_outer_rect(wp.rect).has_point(wall_pos):
			return wp.rect.id
	return &""

## I7 (Q104=a): `wall_jump_N` enters the Nth picture in PLACEMENT order -- GAP-009 deleted "ring";
## the packer's own output order (slot-ascending, home first) is what's left to count by, so this
## reads `%Pictures`' own child order directly rather than re-deriving it. Silently does nothing
## past the last picture -- no "ring order" defines a jump target that does not exist.
## I7/Q104=a: `wall_jump_N` enters the Nth picture. ADVERSARIAL_REVIEW C4 found two defects here.
##
## It called `focus()` directly — no unfocus of the current picture, no camera move, no FocusStack
## update, no overlay refresh — so pressing a digit while a picture was focused left TWO screen
## roots at PROCESS_MODE_ALWAYS, breaking §1.6's "exactly one" invariant (Q74=a) that the Phase-3
## gate exists to protect. It now emits `picture_enter_requested`, the SAME signal a click and
## `ui_accept` use, so a jump cannot diverge from the entry path again.
##
## It also indexed `%Pictures` child order, which stops matching placement order as soon as
## `_repack_wall()` appends a newly-unlocked picture — after unlocking `book`, `wall_jump_2` landed
## on the wrong picture. Ordered by the packer's own result instead, which is what "the Nth picture"
## means to a player looking at the wall.
func _jump_to_index(index: int) -> void:
	var ordered := _packed_ids_in_placement_order()
	if index < 0 or index >= ordered.size(): return
	picture_enter_requested.emit(ordered[index])

## Placement order as the packer resolved it, recorded by apply_layout(). Empty until the first
## layout is applied, which is why _jump_to_index() range-checks rather than assuming.
var _placement_order : Array[StringName] = []

func _packed_ids_in_placement_order() -> Array[StringName]:
	return _placement_order

## F11 (Q69=a): exactly one picture is selected in wall view, always -- empty only before the wall
## has any pictures to select. Set by enter_wall_view()/move_selection(), never directly.
var selected_id : StringName = &""

## Q105=b: the selection cursor renders only after the first directional input -- a mouse-only
## session never sees a keyboard cursor. move_selection() is the only thing that latches this true;
## nothing ever clears it back to false (same one-way-latch shape WallTransition's own pause/
## unpause/input-unlock booleans use).
var selection_visible : bool = false

## Every currently packed picture, id -> node, read from %Pictures' own children (each one's
## `rect` was set by WallPicture.build()). Pictures with no rect yet (never built()'ed) are
## skipped -- the same "un-built fixture" shape T9/T10 already rely on elsewhere. Typed (not a bare
## Dictionary) so callers get WallPicture back, not Variant -- warnings-as-errors otherwise rejects
## `.rect`/`.set_selected()` on an inferred Variant.
func _pictures_by_id() -> Dictionary[StringName, WallPicture]:
	var out : Dictionary[StringName, WallPicture] = {}
	for child : Node in %Pictures.get_children():
		var wp := child as WallPicture
		if wp and wp.rect:
			out[wp.rect.id] = wp
	return out

## F10 ("the wall remembers its selected picture... starting at the one you came from") + F11
## ("starting at the one you came from", Q69=a): entering wall view always re-seeds the selection
## to whichever picture the player is coming FROM. A screen's own internal Control focus (F10's
## other half, "every picture remembers its internal focus for the session") needs no code here --
## screen_root nodes are never destroyed/recreated across a wall-view visit (§1.6/§1.8), so Godot's
## own Control focus state already persists on the same node instance (ASSUMPTIONS.md).
func enter_wall_view(from_id: StringName) -> void:
	selected_id = from_id

## Q98=a (I4, TEST_PLAN I5): moves the selection to the geometrically NEAREST OTHER picture whose
## centre lies at least partly in `direction`'s half-plane from the current selection. Q106=a
## (TEST_PLAN I6): wraps -- when nothing lies in that direction at all (the current selection is
## already the extreme one that way), picks whichever picture is MOST OPPOSITE `direction` instead,
## which is exactly "the first" from the far end of that same axis. Also latches
## `selection_visible` true (Q105=b) -- the cursor was invisible until this, the first directional
## input, ever ran.
func move_selection(direction: Vector2) -> void:
	selection_visible = true
	var pictures := _pictures_by_id()
	if pictures.is_empty(): return
	if selected_id == &"" or not pictures.has(selected_id):
		selected_id = pictures.keys()[0]
		return
	var dir := direction.normalized()
	var current : PictureRect = pictures[selected_id].rect
	var best_id := &""
	var best_dist := INF
	var wrap_id := &""
	var wrap_dot := INF
	for id : StringName in pictures:
		if id == selected_id: continue
		var candidate : PictureRect = pictures[id].rect
		var offset : Vector2 = candidate.centre - current.centre
		if offset.is_zero_approx(): continue
		var d := offset.normalized().dot(dir)
		if d > 0.0:
			var dist := offset.length()
			if dist < best_dist:
				best_dist = dist
				best_id = id
		if d < wrap_dot:
			wrap_dot = d
			wrap_id = id
	var new_id := best_id if best_id != &"" else wrap_id
	if new_id == &"": return
	if pictures.has(selected_id): pictures[selected_id].set_selected(false)
	selected_id = new_id
	pictures[selected_id].set_selected(true)

## S36's own done-when: how many pictures currently exist to overview -- the only piece of state
## only the wall itself knows, needed by the overlay's Wall-button visibility (refresh_overlay()).
func picture_count() -> int:
	return %Pictures.get_child_count()

## G9 (Q5=b): wall view's own camera framing -- FILL AND CROP the whole wall's extent (the union of
## every packed picture's frame outer rect) into the window, the SAME larger-of-two-axis-ratios
## formula WallPicture.focused_scale() already uses for a single picture at rest (H3), just applied
## to the wall's whole bounding box instead of one picture's native size. 1.0 (no-op) when nothing
## is packed yet.
func wall_view_zoom(window_size: Vector2) -> float:
	var extent := _wall_extent()
	if extent.size.x <= 0.0 or extent.size.y <= 0.0: return 1.0
	return WallPicture.focused_scale(extent.size, window_size,
			SettingsManager.settings.wall_overfill_margin)

## M4/G10 (Q1 note, Q3 note): a pan drag is in progress -- the left button went down on BARE WALL
## in wall view and has not come up. Latched here rather than read off `Input` so a synthetic event
## sequence drives exactly the same path a real pointer does.
var _panning : bool = false

## M4 (ADVERSARIAL_REVIEW): `clamp_pan()`'s ONE call site -- free pan was fully implemented and
## unreachable, so G10 did not exist and two tests guarded maths nothing ran. Drags the wall-view
## camera by a SCREEN-space pointer delta: the camera moves OPPOSITE the pointer (dragging right
## pulls the wall right, i.e. looks further left) and divides by the live zoom, which is direct
## magnification here (ASSUMPTIONS.md), so the wall tracks the pointer 1:1 on screen at any zoom.
##
## G10's "on a large screen everything is visible and panning is off" needs no check of its own:
## `clamp_pan()` already collapses each axis whose extent fits inside the visible rect to the
## extent's own centre, so this is a no-op exactly when it should be.
##
## Touch needs no separate path -- Godot's `emulate_mouse_from_touch` (left at its default) already
## delivers a one-finger drag as these same mouse events, and a TWO-finger drag is consumed by the
## pinch tracker before it can reach here.
func pan_by(delta: Vector2) -> void:
	var camera : Camera2D = %Camera2D
	var zoom := camera.zoom.x
	if zoom <= 0.0: return
	camera.position = clamp_pan(camera.position - delta / zoom,
			get_viewport().get_visible_rect().size)

## G10: free pan is clamped so the visible window never shows past the wall's own extent ("never
## pans into void"), and collapses to the extent's own centre on whichever axis the extent is
## already smaller than the visible window -- panning is a no-op there, matching G10's "on a large
## screen everything is visible and panning is off." `target` is the camera position a drag/stick
## is requesting; the return value is what the camera should actually be set to.
func clamp_pan(target: Vector2, window_size: Vector2) -> Vector2:
	var extent := _wall_extent()
	if extent.size.x <= 0.0 or extent.size.y <= 0.0: return Vector2.ZERO
	var zoom := wall_view_zoom(window_size)
	var visible := window_size / zoom
	var half_visible := visible * 0.5
	var min_pos := extent.position + half_visible
	var max_pos := extent.position + extent.size - half_visible
	var x := clampf(target.x, min_pos.x, max_pos.x) if min_pos.x <= max_pos.x \
			else extent.get_center().x
	var y := clampf(target.y, min_pos.y, max_pos.y) if min_pos.y <= max_pos.y \
			else extent.get_center().y
	return Vector2(x, y)

## The union of every packed picture's frame outer rect -- the wall's own bounding box in wall
## space. Empty (zero size) when nothing is packed yet.
func _wall_extent() -> Rect2:
	var extent := Rect2()
	var first := true
	for child : Node in %Pictures.get_children():
		var wp := child as WallPicture
		if wp and wp.rect:
			var frame := WallPacker.frame_outer_rect(wp.rect)
			extent = frame if first else extent.merge(frame)
			first = false
	return extent

## S38 (K2-K4): re-applies a fresh packed layout to every ALREADY-BUILT picture under %Pictures --
## geometry only (`WallPicture.reposition()`/`animate_reposition()`), never touching a viewport,
## screen_root or focus state. `animate` true (K3: "if the player is IN wall view... the re-pack
## animates live in front of them") tweens every moved/resized picture together on ONE shared
## parallel tween over the ordinary transition clock; false (K4: "if they are inside a picture, the
## wall re-packs silently") snaps instantly -- correct either way, since nothing here is visible
## off-focus regardless of which branch runs. `rects` ids with NO existing WallPicture are skipped
## -- building a brand-new picture node needs its own `PictureEntry`/screen, which only the caller
## (`Main`) has; this method only repositions what already exists. The `FocusStack` is never read
## or written here (K4's own "Back still works because the stack holds ids, not positions") --
## nothing in this method can invalidate it, by construction, since it never touches an id, only a
## rect.
func apply_layout(rects: Dictionary[StringName, PictureRect], animate: bool) -> void:
	# `rects` is built by iterating WallPacker's own returned Array, so its key order IS
	# placement order. Kept because %Pictures child order diverges from it the moment a repack
	# appends a newly-unlocked picture, and `wall_jump_N` means the Nth picture as PLACED
	# (I7/Q104=a), not the Nth node added (ADVERSARIAL_REVIEW C4).
	_placement_order.assign(rects.keys())
	var pictures := _pictures_by_id()
	var tween : Tween = null
	for id : StringName in rects:
		if not pictures.has(id): continue
		var wp := pictures[id]
		var new_rect : PictureRect = rects[id]
		if not animate:
			wp.reposition(new_rect)
			continue
		if wp.rect and wp.rect.centre.is_equal_approx(new_rect.centre) \
				and wp.rect.size.is_equal_approx(new_rect.size):
			continue
		if tween == null:
			tween = create_tween()
			tween.set_parallel(true)
		wp.animate_reposition(tween, new_rect, SettingsManager.settings.wall_transition_delay)

## S39 (E9, Q210=a -- "yes, behind the same debug gate as the leak sentinel"): a live count of
## instantiated screens (`WallPicture.screen_root != null`, E8's own "all screens stay instantiated"
## quantity) and an ESTIMATE of their combined texture memory. Godot has no cheap per-texture VRAM
## query, so this assumes RGBA8 (4 bytes/pixel, the format every wall SubViewport actually renders
## in) times each viewport's own `.size` -- a measured approximation, same admitted-inexact category
## as this repo's other debug numbers, not a claim of byte-exact GPU accounting. Pure -- reads only
## %Pictures' own children, no engine singletons -- so it is headless-testable and callable from
## anywhere without wiring a new dependency.
func debug_memory_readout() -> String:
	var screens := 0
	var viewports := 0
	var texture_bytes := 0
	for child : Node in %Pictures.get_children():
		var wp := child as WallPicture
		if not wp: continue
		if wp.screen_root: screens += 1
		if wp.viewport:
			viewports += 1
			texture_bytes += wp.viewport.size.x * wp.viewport.size.y * 4
	return "WALL DEBUG: %d screens instantiated, %d viewports, ~%.2f MB texture memory" \
			% [screens, viewports, texture_bytes / 1048576.0]

## S33 (Q167=c, Q171=b): the wall's own two "ping-pong" music players (`%MusicA`/`%MusicB` in
## `wall.tscn`), both on the SAME pre-existing "Music" bus `main.tscn`'s own legacy player already
## uses -- no new bus. Exactly one is ever the FOREGROUND player between crossfades; `_music_active`
## says which index (0 or 1). Cached `@onready`, same typed-unique-node convention
## `WallPicture._frame`/`_screen`/`_shadow` already use.
@onready var _music_a : AudioStreamPlayer = %MusicA
@onready var _music_b : AudioStreamPlayer = %MusicB
var _music_active : int = 0

func _music_player(index: int) -> AudioStreamPlayer:
	return _music_a if index == 0 else _music_b

## S33 (Q167=c): starts `entry.music` on the foreground player immediately, at full volume, with no
## fade -- the cold-launch case (M1: "the camera starts already focused, no wall-view flash"), where
## there is nothing yet to cross-fade FROM. A null `entry.music` leaves the wall silent.
func start_music(entry: PictureEntry) -> void:
	_music_player(1 - _music_active).stop()
	var fg := _music_player(_music_active)
	if entry == null or entry.music == null:
		fg.stop()
		return
	fg.stream = entry.music
	fg.volume_db = 0.0
	fg.play()

## S33 (Q167=c, Q168=c, Q170=b): arms the BACKGROUND player with `dest_entry`'s own track (or
## silence, `dest_entry == null`/`dest_entry.music == null`), ready for `update_travel_music()` to
## blend per frame. A no-op when `dest_entry.music` is literally the SAME stream already playing in
## the foreground (e.g. stepping back and forth between two pictures that share a track) -- no
## restart, no audible glitch.
func begin_music_crossfade(dest_entry: PictureEntry) -> void:
	var fg := _music_player(_music_active)
	if dest_entry != null and dest_entry.music != null and fg.stream == dest_entry.music \
			and fg.playing:
		return
	var bg := _music_player(1 - _music_active)
	bg.stream = dest_entry.music if dest_entry != null else null
	bg.volume_db = -80.0
	if bg.stream != null:
		bg.play()
	else:
		bg.stop()

## S33 (Q170=b -- "a live screen you are travelling toward gets louder"): the per-frame blend during
## a camera move -- `t` is the camera's own fractional progress from `source_centre` toward
## `dest_centre` (0 at the source, 1 at the destination), so the crossfade is driven by the SAME real
## camera position the transition is already animating, not a separate authored timing curve (no new
## `PlayerSettings` knob needed). This also realises Q168=c's "fades out over the [move]" for the
## OUTGOING picture, since its volume falls as the camera's real distance to it grows, exactly in
## step with however much of the move has actually happened -- see ASSUMPTIONS.md for the reading
## taken (camera-distance-driven, not zoom-out-phase-specific). Guards `source_centre == dest_centre`
## (division by zero) even though no real caller reaches this with equal points.
func update_travel_music(source_centre: Vector2, dest_centre: Vector2, camera_pos: Vector2) -> void:
	var total := source_centre.distance_to(dest_centre)
	var t := 1.0 if total <= 0.0 else \
			clampf(1.0 - camera_pos.distance_to(dest_centre) / total, 0.0, 1.0)
	_music_player(_music_active).volume_db = linear_to_db(clampf(1.0 - t, 0.001, 1.0))
	_music_player(1 - _music_active).volume_db = linear_to_db(clampf(t, 0.001, 1.0))

## S33: resolves a crossfade begun by `begin_music_crossfade()` -- stops and silences the OLD
## foreground player outright (never left merely quiet) and flips which player is foreground, so the
## next crossfade's "background" player is the one that just finished fading out.
func finish_music_crossfade() -> void:
	var old_fg := _music_player(_music_active)
	old_fg.stop()
	old_fg.volume_db = -80.0
	_music_active = 1 - _music_active
	_music_player(_music_active).volume_db = 0.0

## S36's own done-when ("the wall button is hidden while only one picture exists"): forwards to the
## overlay, adding the one piece of state only the wall itself knows.
func refresh_overlay(stack: FocusStack) -> void:
	var overlay : WallOverlay = %Overlay
	overlay.refresh(stack, picture_count())

## §1.8 "window restored from minimise" (E7, Q208=b): every frozen picture texture may have been
## discarded by the GPU while the window was minimised, so every picture is force-rendered once.
## Godot has no dedicated "un-minimise" signal on desktop — `NOTIFICATION_APPLICATION_FOCUS_IN` is
## the closest built-in event (it also fires on a plain alt-tab back, Q207=a; harmless here, since a
## forced re-render costs one frame and E6 already treats a frozen-texture re-render as cheap by
## construction). See ASSUMPTIONS.md.
func _notification(what: int) -> void:
	if what != NOTIFICATION_APPLICATION_FOCUS_IN:
		return
	for child : Node in %Pictures.get_children():
		var wp := child as WallPicture
		if wp:
			wp.mark_for_rerender()

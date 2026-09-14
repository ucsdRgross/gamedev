extends TestSuite
# WALL RENDER: the wall's construction and its render gating.

# Builds a real res://UI/Wall/wall.tscn plus a few real WallPicture instances from a small
# PROGRAMMATIC WallLayout, never the authored layout resource, which is the layout tool's output and
# out of scope here, then inspects the constructed tree.

const WALL_SCENE := preload("res://UI/Wall/wall.tscn")
const WALL_PICTURE_SCENE := preload("res://UI/Wall/wall_picture.tscn")
const MAIN_SCENE := preload("res://Levels/main.tscn")

func suite_name() -> String:
	return "WALL RENDER"

var _wall : Wall = null
var _pictures : Array[WallPicture] = []

func _ready() -> void:
	TestLog.line("============ WALL RENDER TEST PASS ============")
	behavior_section("CONSTRUCTION")
	_build_wall()
	test_every_subviewport_is_explicitly_nearest()
	test_no_subviewport_container_anywhere()
	behavior_section("RENDER GATING")
	test_unvisited_picture_has_rendered_once()
	test_non_focused_picture_keeps_texture()
	test_wall_view_size_written_and_clamped()
	test_restore_from_minimise_rerenders()
	test_layout_is_loaded_from_disk_not_hardcoded()
	test_filter_swaps_on_zoom_not_pan()
	await test_the_wall_actually_drives_the_filter_swap_as_the_camera_zooms()
	behavior_section("OVERFILL MARGIN (H3, GAP-011)")
	test_overfill_margin_knob_actually_changes_the_scale()
	test_overfill_margin_only_applies_when_aspect_mismatches()
	behavior_section("SELECTED LIFT (PICTURE_WALL.md B2)")
	test_selected_lift_knob_actually_changes_the_position()
	behavior_section("LIVE SCREEN REPARENTING (S30, B7, Q211=a)")
	test_build_reparents_a_live_screen_unchanged()
	behavior_section("SCREEN PERSISTENCE (S39, E8, Q203=a)")
	test_screen_root_survives_repeated_focus_unfocus_cycles()
	behavior_section("A SECOND RE-PACK CANCELS THE FIRST")
	await test_a_second_repack_kills_the_first_ones_tween()
	behavior_section("MOVING BETWEEN TWO PICTURES THAT SHARE A TRACK (S33)")
	test_a_crossfade_between_pictures_sharing_a_track_keeps_playing()
	behavior_section("THE SELECTION LIFT IS PART OF WHERE A PICTURE IS")
	test_selection_lift_survives_a_repack_and_yields_to_focus()
	behavior_section("FRAME NINE-SLICE (S24, QR4=b, C6)")
	test_nine_slice_applies_to_the_layout_the_game_actually_loads()
	behavior_section("DRAWN EXTENT TRACKS THE RECT, NOT THE RENDER TARGET")
	test_screen_draws_at_rect_size_through_every_render_target_change()
	behavior_section("MEMORY READOUT (S39, E9, Q210=a)")
	test_debug_memory_readout_counts_screens_and_viewports()
	test_debug_readout_gated_by_wall_debug_readout_flag()
	behavior_section("THE WALL RE-PACKS AROUND THE WIDER GAME PICTURE (H20)")
	test_game_picture_keeps_its_real_width_not_squashed_to_window_aspect()
	test_default_layout_repacks_without_dropping_or_overlapping_any_picture()
	behavior_section("PER-GRID CAMERA POSE")
	test_grid_state_steps_by_the_grid_pitch_and_reproduces_rest_at_the_resting_grid()
	test_panned_state_is_the_offset_primitive_grid_state_delegates_to()
	behavior_section("THE SAVED PAN SNAPS TO A WHOLE GRID (S32, H19, Q173, Q179)")
	test_snap_pan_to_grid_rounds_to_a_whole_step_and_clamps_into_the_board()
	behavior_section("THE WALL EDITOR DRIVES EVERY KNOB IT SHOWS (TP-120, Q186=a)")
	await test_the_wall_editor_drives_every_knob_it_shows()
	_teardown_wall()
	finish()

# ------------------------------------------------------------------ fixture

func _entry(id: StringName, slot_deg: int, size_multiplier: float,
		frame_px: Vector4) -> PictureEntry:
	var e := PictureEntry.new()
	e.id = id
	e.slot = slot_deg
	e.size_multiplier = size_multiplier
	e.frame_px = frame_px
	return e

# A small, varied, PROGRAMMATIC layout: three pictures with different sizes and frame thicknesses,
# enough to exercise real construction without authoring the tool's own layout resource.
func _make_layout() -> WallLayout:
	var l := WallLayout.new()
	l.gap_px = 24.0
	l.ellipse_aspect_min = 1.2
	l.ellipse_aspect_max = 2.6
	l.home_id = &"a"
	var pics : Array[PictureEntry] = [
		_entry(&"a", 0, 1.0, Vector4(16, 16, 16, 16)),
		_entry(&"b", 90, 1.3, Vector4(8, 8, 40, 8)),
		_entry(&"c", 210, 0.8, Vector4(24, 24, 24, 24)),
	]
	l.pictures = pics
	return l

func _build_wall() -> void:
	_wall = WALL_SCENE.instantiate()
	add_child(_wall)
# ⚠ Wall._ready() sets get_tree().paused = true GLOBALLY by design: correct standalone, but this
# suite runs CONCURRENTLY with ~33 others that need normal processing to ever finish, and a global
# pause with no unpause hangs the whole run with no banner (measured: a 600 s timeout, no finish).

# Safe to undo immediately: add_child() above already ran Wall._ready() SYNCHRONOUSLY, the parent
# being in the tree already, and nothing else can run between that call and this line, because
# GDScript only yields at an explicit await.
	get_tree().paused = false
	var layout := _make_layout()
	var unlocked : Array[StringName] = [&"a", &"b", &"c"]
	var rects := WallPacker.pack(layout, unlocked, 1.6)
	var by_id : Dictionary[StringName, PictureEntry] = {}
	for e : PictureEntry in layout.pictures: by_id[e.id] = e
	var viewports : Node = _wall.get_node(^"%Viewports")
	var pictures_root : Node = _wall.get_node(^"%Pictures")
	for rect : PictureRect in rects:
		var wp : WallPicture = WALL_PICTURE_SCENE.instantiate()
		pictures_root.add_child(wp)
		wp.build(rect, by_id[rect.id], viewports)
		_pictures.append(wp)

# Frees every constructed picture and its off-tree SubViewport, which is teardown()'s whole reason
# to exist, plus the wall itself, so this suite leaves nothing behind for its siblings.
func _teardown_wall() -> void:
	for wp : WallPicture in _pictures: wp.teardown()
	_pictures.clear()
	if _wall and is_instance_valid(_wall): _wall.queue_free()
	_wall = null

# ------------------------------------------------------------------ construction

# Every SubViewport constructed for the wall is explicitly NEAREST, which is the trap this repo has
# hit four times.
func test_every_subviewport_is_explicitly_nearest() -> void:
	check(_pictures.size() == 3, "3 pictures were constructed", str(_pictures.size()))
	for wp : WallPicture in _pictures:
		check(wp.viewport != null, "%s has a SubViewport" % wp.name)
		if wp.viewport:
			check(wp.viewport.canvas_item_default_texture_filter
					== Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST,
					"%s's SubViewport is explicitly NEAREST" % wp.name)

# No SubViewportContainer exists anywhere in the wall, which is the decision this defends.
func test_no_subviewport_container_anywhere() -> void:
	check(not _has_subviewport_container(_wall), "no SubViewportContainer anywhere in the wall")

func _has_subviewport_container(node: Node) -> bool:
	if node is SubViewportContainer: return true
	for child : Node in node.get_children():
		if _has_subviewport_container(child): return true
	return false

# ------------------------------------------------------------------ render gating

# Every picture has a non-null texture straight out of build(), before any focus() call is made
# anywhere in this suite. It runs first in the render-gating group on purpose, so later tests'
# focus() and unfocus() calls cannot retroactively make this claim vacuous.
func test_unvisited_picture_has_rendered_once() -> void:
	for wp : WallPicture in _pictures:
		check(wp.viewport.get_texture() != null,
				"%s's texture is non-null before any focus() call" % wp.name)

# A non-focused picture reports UPDATE_DISABLED, but its already-rendered texture persists: never
# null, never zero-size.
func test_non_focused_picture_keeps_texture() -> void:
	var wp := _pictures[0]
	wp.focus()
	wp.unfocus(Vector2(200, 120))
	check(wp.viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED,
			"a non-focused picture's SubViewport reports UPDATE_DISABLED")
	var tex := wp.viewport.get_texture()
	check(tex != null, "its texture is non-null")
	check(tex != null and tex.get_size() != Vector2.ZERO, "its texture is non-zero-size",
			str(tex.get_size()) if tex else "null")

# SubViewport.size is written straight from the on-screen footprint, each axis independently clamped
# below by settings.wall_view_min_texture_px, so shrinking one axis to 10px clamps that short axis
# to the floor without disturbing the other.
func test_wall_view_size_written_and_clamped() -> void:
	var wp := _pictures[0]
	wp.unfocus(Vector2(10, 500))
	var min_px := SettingsManager.settings.wall_view_min_texture_px
	check(mini(wp.viewport.size.x, wp.viewport.size.y) == min_px,
			"a 10px footprint clamps the short axis to wall_view_min_texture_px",
			str(wp.viewport.size))

# Restoring from minimise re-renders every picture once. Wall._notification hooks
# NOTIFICATION_APPLICATION_FOCUS_IN, the closest built-in un-minimise event on desktop, and calls
# mark_for_rerender() on every WallPicture under %Pictures.
func test_restore_from_minimise_rerenders() -> void:
# ⚠ ONE PICTURE IS FOCUSED. Settling EVERY picture to UPDATE_DISABLED leaves none live, so the
# notification could not possibly harm one and the row asserts a property that cannot fail.

# The rule is that every FROZEN texture is re-rendered, not every picture: the focused one is not
# frozen, it is UPDATE_ALWAYS, and forcing UPDATE_ONCE on it freezes the live screen for the rest
# of the session. The loop below settles the rest first.
	for wp : WallPicture in _pictures:
		wp.viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	var live : WallPicture = _pictures[0]
	live.focus()
	check(live.viewport.render_target_update_mode == SubViewport.UPDATE_ALWAYS,
			"the focused picture is live before the restore notification")
	_wall.notification(NOTIFICATION_APPLICATION_FOCUS_IN)
	check(live.viewport.render_target_update_mode == SubViewport.UPDATE_ALWAYS,
			"the FOCUSED picture stays UPDATE_ALWAYS across a restore -- alt-tabbing during a show "
			+ "must not freeze the live screen")
	for wp : WallPicture in _pictures:
		if wp == live: continue
		check(wp.viewport.render_target_update_mode == SubViewport.UPDATE_ONCE,
				"%s (frozen) went UPDATE_ONCE after the restore notification" % wp.name)
	live.unfocus(Vector2(200.0, 120.0))

# The authored layout resource had ZERO production readers, because Main called the hardcoded
# Wall.initial_layout(), so everything an author tuned in the tool was discarded.

# This proves the loader really reads the FILE rather than the fallback, by pointing it at a temp
# resource carrying a value the built-in layout could never produce, and proves the fallback still
# works when the file is absent. No mock: a real WallLayout, really saved, really loaded.
func test_layout_is_loaded_from_disk_not_hardcoded() -> void:
	var temp_path := "user://_test_layout_probe.tres"
	var probe := WallLayout.new()
# A value initial_layout() never sets.
	probe.gap_px = 1234.5
	probe.home_id = &"probe_home"
	var saved := ResourceSaver.save(probe, temp_path)
	check(saved == OK, "the probe layout saved to disk")
	var from_disk := Wall.load_layout(temp_path)
	check(is_equal_approx(from_disk.gap_px, 1234.5),
			"load_layout() returns the layout ON DISK -- gap_px %.1f, not the built-in default"
			% from_disk.gap_px)
	check(from_disk.home_id == &"probe_home",
			"load_layout() returns the disk layout's home_id, not initial_layout()'s")
	var missing := Wall.load_layout("user://_test_layout_absent.tres")
	check(missing != null and missing.home_id == &"start_menu",
			"a missing file falls back to the built-in layout so a fresh checkout still boots")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(temp_path))

# The filter swaps on zoom, not on pan: pure translation must never flip it. The full camera-driven
# wiring is pinned by the test below; this one pins the method's own contract directly.
func test_filter_swaps_on_zoom_not_pan() -> void:
	var wp := _pictures[0]
	var screen : Sprite2D = wp.get_node(^"%Screen")
	wp.update_filter(false)
	check(screen.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST,
			"pan only (zoom unchanged) leaves the filter NEAREST")
	wp.update_filter(true)
	check(screen.texture_filter == CanvasItem.TEXTURE_FILTER_LINEAR,
			"a zoom change flips the filter to LINEAR")

# update_filter(true) with NO CALLER leaves the focused picture sampling NEAREST through every zoom,
# and the wiring dead. The test above pins the METHOD; this pins the WIRING, with a REAL camera
# zoom, on a REAL Wall, across REAL frames. It goes red if Wall._process()'s tracking is removed.

# The half most easily lost is that a pure PAN must leave the filter alone. It is asserted after a
# position change large enough that any position-sensitive implementation would have flipped it.
func test_the_wall_actually_drives_the_filter_swap_as_the_camera_zooms() -> void:
	var wp := _pictures[0]
	var screen : Sprite2D = wp.get_node(^"%Screen")
	var camera : Camera2D = _wall.get_node(^"%Camera2D")
# Exactly ONE focused picture, by construction: _focused_picture() returns the FIRST it finds, so an
# earlier test leaving another one focused would silently point this test at the wrong picture and
# it would then prove nothing about `wp` at all.
	for other : WallPicture in _pictures:
		if other != wp: other.unfocus(Vector2(100.0, 100.0))
	wp.focus()

# One settling frame so the tracker has a zoom to compare against, then a frame at rest.
	await get_tree().process_frame
	await get_tree().process_frame
	check(screen.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST,
			"at rest the focused picture samples NEAREST (H5)")

	camera.zoom = camera.zoom * 1.5
	await get_tree().process_frame
	check(screen.texture_filter == CanvasItem.TEXTURE_FILTER_LINEAR,
			"the frame the camera ZOOMED, the wall swapped the focused picture to LINEAR -- "
			+ "nothing called update_filter(true) at all before M5")

	await get_tree().process_frame
	check(screen.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST,
			"and it snaps back to NEAREST the moment the zoom stops changing (QR7=c)")

	camera.position += Vector2(500.0, 500.0)
	await get_tree().process_frame
	check(screen.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST,
			"Q34=c: a pure PAN never flips the filter -- only zoom does")

	wp.unfocus(Vector2(100.0, 100.0))
	camera.zoom = camera.zoom * 1.5
	await get_tree().process_frame
	check(screen.texture_filter == CanvasItem.TEXTURE_FILTER_LINEAR,
			"H5: with nothing focused the picture stays LINEAR unconditionally, zoom or not")

# ------------------------------------------------------------------ the overfill margin

# wall_overfill_margin is a real, READ knob, not a promoted-but-ignored export, a knob nothing reads
# being the defect. focused_scale() takes the margin as a REQUIRED parameter with no default, so
# this also proves the parameter is wired through rather than merely present on PlayerSettings.

# Two visibly different margins on the SAME native and window sizes must produce two DIFFERENT
# scales, and each must equal the plain fill ratio times its own margin exactly - not just
# "different", which a sign flip or an unrelated bug could also produce.
func test_overfill_margin_knob_actually_changes_the_scale() -> void:
	var native := Vector2(400, 300)
	var window := Vector2(1280, 720)
	var fill_ratio := maxf(window.x / native.x, window.y / native.y)

	var scale_a := WallPicture.focused_scale(native, window, 1.02)
	var scale_b := WallPicture.focused_scale(native, window, 1.10)
	check(not is_equal_approx(scale_a, scale_b),
			"two different wall_overfill_margin values produce two different focused_scale() results",
			"scale_a=%.6f scale_b=%.6f" % [scale_a, scale_b])
	check(is_equal_approx(scale_a, fill_ratio * 1.02),
			"the 1.02 result equals the plain fill ratio times exactly that margin, not a fixed 1.02",
			"scale_a=%.6f expected=%.6f" % [scale_a, fill_ratio * 1.02])
	check(is_equal_approx(scale_b, fill_ratio * 1.10),
			"the 1.10 result equals the plain fill ratio times exactly that margin",
			"scale_b=%.6f expected=%.6f" % [scale_b, fill_ratio * 1.10])

	var settings := PlayerSettings.new()
	check(is_equal_approx(settings.wall_overfill_margin, 1.02),
			"PlayerSettings.wall_overfill_margin defaults to 1.02 (GAP-011's answered value)",
			"%.4f" % settings.wall_overfill_margin)

# The picture overfills whenever its aspect does not match the window's, so the margin is
# CONDITIONAL.

# Measured defect, not theorised: the unconditional version cropped the real start-menu picture's
# own bottom button row at an ordinary 1280x720-in-1152x648 case, both 16:9 - a case with NOTHING to
# hide, since fill and fit already coincide at matching aspect.
func test_overfill_margin_only_applies_when_aspect_mismatches() -> void:
# Matching aspect and the same magnitude too, both 16:9 with native equal to window over 4/3, makes
# the fill ratio itself exactly 1.0, so a correct result here is REQUIRED to be exactly 1.0 rather
# than "some value the margin did not touch", which is the owner's own literal ask.
	var matching_native := Vector2(1152, 648)
	var matching_window := Vector2(1280, 720)
	var matching_scale := WallPicture.focused_scale(matching_native, matching_window, 1.02)
	check(is_equal_approx(matching_scale, 1.1111111),
			"matching aspect gives the EXACT fill ratio, margin not applied at all",
			"scale=%.6f expected=1.111111" % matching_scale)

# Mismatched aspect, 4:3 native in a 16:9 window and the same fixture the sibling test above uses.
# The margin MUST still apply here, so this row cannot pass by disabling the margin outright; it has
# to be genuinely conditional.
	var mismatched_native := Vector2(400, 300)
	var mismatched_window := Vector2(1280, 720)
	var fill_ratio := maxf(mismatched_window.x / mismatched_native.x,
			mismatched_window.y / mismatched_native.y)
	var mismatched_scale := WallPicture.focused_scale(mismatched_native, mismatched_window, 1.02)
	check(is_equal_approx(mismatched_scale, fill_ratio * 1.02),
			"mismatched aspect still applies the margin exactly",
			"scale=%.6f expected=%.6f" % [mismatched_scale, fill_ratio * 1.02])
	check(not is_equal_approx(mismatched_scale, fill_ratio),
			"...and that margin is not silently zero -- the mismatched case is genuinely "
			+ "different from a bare fill ratio", "scale=%.6f fill=%.6f" % [mismatched_scale, fill_ratio])

# ------------------------------------------------------------------ the selected lift

# wall_selected_lift is a REAL, READ knob rather than a typed literal in wall_picture.gd, the same
# category as wall_overfill_margin and wall_light_offset.

# Two different lift values on the SAME picture must produce two different position results after
# set_selected(true), each exactly the rect centre plus the configured lift - not just "different",
# the same rigor the overfill-margin test above already established.
func test_selected_lift_knob_actually_changes_the_position() -> void:
	backup_real_settings()
	var wp := _pictures[0]
	var settings := SettingsManager.settings
	var prev := settings.wall_selected_lift

	settings.wall_selected_lift = Vector2(0.0, -14.0)
	wp.set_selected(true)
	var pos_a := wp.position

	settings.wall_selected_lift = Vector2(0.0, -40.0)
	wp.set_selected(true)
	var pos_b := wp.position

	check(not pos_a.is_equal_approx(pos_b),
			"two different wall_selected_lift values produce two different lifted positions",
			"a=%s b=%s" % [pos_a, pos_b])
	check(pos_b.is_equal_approx(wp.rect.centre + Vector2(0.0, -40.0)),
			"the lifted position equals rect.centre + the exact configured lift",
			"got=%s want=%s" % [pos_b, wp.rect.centre + Vector2(0.0, -40.0)])

	wp.set_selected(false)
	settings.wall_selected_lift = prev
	restore_real_settings()

# ------------------------------------------------------------------ a live screen, reparented

# build()'s live_screen parameter REPARENTS an already-instantiated node as screen_root: it never
# instantiates a copy and never touches its children or state.

# Proven by IDENTITY, not by "a screen_root exists": the exact same object handed in comes back out,
# still holding the marker child it had BEFORE build() ever ran, and is a real child of the
# picture's own SubViewport afterward.
func test_build_reparents_a_live_screen_unchanged() -> void:
	var live := Node.new()
	live.name = "PersistentMenuStandIn"
	var marker := Node.new()
	marker.name = "MarkerChildFromBeforeBuild"
	live.add_child(marker)

	var wp : WallPicture = WALL_PICTURE_SCENE.instantiate()
	add_child(wp)
	var viewports := Node.new()
	add_child(viewports)
	var rect := PictureRect.new(&"live_test", Vector2.ZERO, Vector2(400, 300),
			Vector4(20, 20, 20, 20))
	var entry := PictureEntry.new()
	entry.id = &"live_test"
	entry.design_size = Vector2i(400, 300)
	wp.build(rect, entry, viewports, live)

	check(wp.screen_root == live,
			"screen_root IS the exact live node handed in, by identity -- not a copy")
	check(is_instance_valid(marker) and marker.get_parent() == live,
			"the live node's own pre-existing child survived build() untouched")
	check(live.get_parent() == wp.viewport,
			"the live node is now a real child of the picture's own SubViewport")

	wp.teardown()
	viewports.queue_free()

# ------------------------------------------------------------------ screen lifecycle

# The leak canary structurally cannot watch this: it never builds a Wall or WallPicture at all, and
# its own header locks it to run LAST and ALONE because OBJECT_COUNT is engine-global.

# Retrofitting a Wall into it would be the wrong suite for a screen-lifecycle question and would
# pollute the very CardData deltas it exists to measure.

# "All screens stay instantiated for the whole session, nothing is ever torn down" is proven here by
# IDENTITY across several focus and unfocus cycles: the SAME screen_root node survives every cycle,
# never freed and rebuilt, which is the exact thing a session actually does.
func test_screen_root_survives_repeated_focus_unfocus_cycles() -> void:
	var live := Node.new()
	live.name = "PersistentScreenStandIn"

	var wp : WallPicture = WALL_PICTURE_SCENE.instantiate()
	add_child(wp)
	var viewports := Node.new()
	add_child(viewports)
	var rect := PictureRect.new(&"persist_test", Vector2.ZERO, Vector2(400, 300),
			Vector4(20, 20, 20, 20))
	var entry := PictureEntry.new()
	entry.id = &"persist_test"
	entry.design_size = Vector2i(400, 300)
	wp.build(rect, entry, viewports, live)

	for cycle : int in 5:
		wp.focus()
		check(wp.screen_root == live and is_instance_valid(live),
				"cycle %d: screen_root is still the SAME live node while focused" % cycle)
		wp.unfocus(Vector2(100, 75))
		check(wp.screen_root == live and is_instance_valid(live),
				"cycle %d: screen_root is still the SAME live node, still alive, once unfocused -- "
				% cycle + "never freed and rebuilt")

	wp.teardown()
	viewports.queue_free()

# Wall.debug_memory_readout() counts instantiated screens and viewports correctly against a KNOWN
# fixture: two pictures with a live screen, so screens_instantiated is 2, plus one registered but
# unbuilt picture with no scene at all, whose screen_root stays null.

# That proves the count is screens ACTUALLY instantiated, not just pictures that exist. The reported
# string must also name both numbers rather than a placeholder message, since a check that could
# pass on an empty or malformed string is the "prints something, proves nothing" trap.
func test_debug_memory_readout_counts_screens_and_viewports() -> void:
	var wall : Wall = WALL_SCENE.instantiate()
	add_child(wall)
	get_tree().paused = false
	var viewports : Node = wall.get_node(^"%Viewports")
	var pictures_root : Node = wall.get_node(^"%Pictures")
	var built : Array[WallPicture] = []

	for id : StringName in [&"one", &"two"]:
		var wp : WallPicture = WALL_PICTURE_SCENE.instantiate()
		pictures_root.add_child(wp)
		var rect := PictureRect.new(id, Vector2.ZERO, Vector2(200, 150), Vector4(10, 10, 10, 10))
		var entry := PictureEntry.new()
		entry.id = id
		entry.design_size = Vector2i(200, 150)
		wp.build(rect, entry, viewports, Node.new())
		built.append(wp)
# "unbuilt": no scene and no live_screen, so screen_root stays null on purpose.
	var unbuilt_wp : WallPicture = WALL_PICTURE_SCENE.instantiate()
	pictures_root.add_child(unbuilt_wp)
	var unbuilt_rect := PictureRect.new(&"unbuilt", Vector2.ZERO, Vector2(200, 150),
			Vector4(10, 10, 10, 10))
	var unbuilt_entry := PictureEntry.new()
	unbuilt_entry.id = &"unbuilt"
	unbuilt_entry.design_size = Vector2i(200, 150)
	unbuilt_wp.build(unbuilt_rect, unbuilt_entry, viewports)
	built.append(unbuilt_wp)

	var readout := wall.debug_memory_readout()
	check("2 screens instantiated" in readout,
			"the readout names exactly the 2 pictures with a real screen_root, not the 3 that exist",
			readout)
	check("3 viewports" in readout,
			"the readout counts every picture's own SubViewport, including the unbuilt one",
			readout)

	for wp : WallPicture in built: wp.teardown()
	wall.queue_free()

# The readout must print under the debug flag, on a REAL Main. Main._wall_debug_readout_text() is
# the gate, and _print_wall_debug_readout() prints whatever it returns, so it is tested directly
# rather than by capturing stdout, a print() call having no return value to assert on.

# BOTH directions are checked on the SAME Main, one right after the other, because the false case is
# an "assert it did not happen" shape and has to be able to fail. The ON check just above proves
# this exact fixture and flag produce non-empty text, so the OFF check going empty is a real change.

# backup_real_settings() and restore_real_settings() park the real settings file for the toggle's
# duration, because SettingsManager saves on every change. test_wall_profile.gd uses the identical
# pattern for the same reason around wall_unlock_all.
func test_debug_readout_gated_by_wall_debug_readout_flag() -> void:
	check(OS.is_debug_build(),
			"sanity: this suite runs via the debug console exe -- OS.is_debug_build() is true, "
			+ "the OTHER half of the gate this test does not flip")

	backup_real_settings()
# ⚠ CONSTRUCTING A Main CLEARS THE SHARED wall_info_mode, which is main.gd's own startup rule, and
# WALL FOCUS's info-toggle test sets that same flag on the same live PlayerSettings and then awaits
# a camera move.

# This suite does not wait for it, so a Main built here during that await clobbers the flag and
# fails that suite - measured, 2 runs in 3. Preserved and put straight back: production really does
# clear it, so the fix belongs on whichever side is the interloper, and that is this one.
	var info_mode_before : bool = SettingsManager.settings.wall_info_mode
	var main : Main = MAIN_SCENE.instantiate()
	add_child(main)
# Main._ready() reaches Wall._ready(), which sets get_tree().paused = true GLOBALLY. It is undone
# immediately, for the reason every Wall- and Main-building test in this suite family documents.
	get_tree().paused = false
	SettingsManager.settings.wall_info_mode = info_mode_before

	var settings := SettingsManager.settings
	var prev := settings.wall_debug_readout

	settings.wall_debug_readout = true
	var on_text := main._wall_debug_readout_text()
	check(on_text != "" and "screens instantiated" in on_text,
			"the readout text appears -- and is the REAL readout, not a placeholder -- when the "
			+ "flag is true", on_text)

	settings.wall_debug_readout = false
	var off_text := main._wall_debug_readout_text()
	check(off_text == "",
			"the readout is genuinely ABSENT when the flag is false -- proven able to fail, since "
			+ "the ON check just above used this exact Main and got real text",
			"got=%s" % [off_text])

	settings.wall_debug_readout = prev
	restore_real_settings()
	main.queue_free()

# ------------------------------------------------------------------ the game picture's width

# The game picture's rect keeps its OWN authored width, unstretched to the window aspect. Without
# that the packer squashes a 3656x685 picture down to about 1218x685.
func test_game_picture_keeps_its_real_width_not_squashed_to_window_aspect() -> void:
	var layout := Wall.load_layout()
	var game_entry : PictureEntry = null
	for e : PictureEntry in layout.pictures:
		if e.id == Wall.GAME_PICTURE_ID: game_entry = e
	check(game_entry != null, "the layout carries a game picture entry")
	if game_entry == null: return
	check(game_entry.keep_aspect,
			"the game entry keeps its own aspect -- the packer's window-aspect stretch never "
			+ "reaches it", str(game_entry.keep_aspect))

	var unlocked : Array[StringName] = [Wall.GAME_PICTURE_ID]
	var rects := WallPacker.pack(layout, unlocked, 1152.0 / 648.0)
	check(rects.size() == 1, "the game picture produced a rect", str(rects.size()))
	if rects.is_empty(): return
	var expected_width : float = float(game_entry.design_size.x) * game_entry.size_multiplier
	check(is_equal_approx(rects[0].size.x, expected_width),
			"the packed width is the picture's own authored width, not a window-aspect-derived "
			+ "sliver", "packed=%.3f expected=%.3f" % [rects[0].size.x, expected_width])

# Packing the wall's real default-unlocked layout around the much wider game picture still produces
# a rect for every unlocked picture, and none of their FRAME rects overlap: at the default window
# aspect, at a narrower aspect, and with every registered picture unlocked at once.

# That last case is the one that actually forces the wider game frame to push a neighbour to a new
# position - measured: `settings` sits at centre (2237.354, -641.244) with the fix and elsewhere
# without it, which proves the re-pack rather than just the absence of an error.
func test_default_layout_repacks_without_dropping_or_overlapping_any_picture() -> void:
	var layout := Wall.load_layout()
	var default_unlocked : Array[StringName] = []
	var all_ids : Array[StringName] = []
	for e : PictureEntry in layout.pictures:
		all_ids.append(e.id)
		if e.unlocked_by_default: default_unlocked.append(e.id)

	for window_aspect : float in [1152.0 / 648.0, 9.0 / 16.0, 1.0]:
		var rects := WallPacker.pack(layout, default_unlocked, window_aspect)
		check(rects.size() == default_unlocked.size(),
				"every default-unlocked picture produced a rect at window aspect %.4f"
						% window_aspect, "%d of %d" % [rects.size(), default_unlocked.size()])
		check(not _rects_overlap(rects),
				"no two frame rects overlap at window aspect %.4f" % window_aspect)

	var all_rects := WallPacker.pack(layout, all_ids, 1152.0 / 648.0)
	check(all_rects.size() == all_ids.size(),
			"every registered picture (book included) produced a rect with the wide game picture "
			+ "in the mix", "%d of %d" % [all_rects.size(), all_ids.size()])
	check(not _rects_overlap(all_rects),
			"no two frame rects overlap with every picture unlocked at once")
	var settings_rect : PictureRect = null
	for r : PictureRect in all_rects:
		if r.id == &"settings": settings_rect = r
	check(settings_rect != null and not settings_rect.centre.is_equal_approx(Vector2(1224.0, 0.0)),
			"settings was pushed off its narrow-game-picture position -- the wall genuinely "
			+ "re-arranged around the wider picture, not merely avoided an error",
			str(settings_rect.centre) if settings_rect else "missing")

# Whether any two of `rects`' FRAME OUTER rects intersect, the same idiom test_wall_packer.gd's own
# overlap helper uses.
func _rects_overlap(rects: Array[PictureRect]) -> bool:
	for i : int in rects.size():
		for j : int in range(i + 1, rects.size()):
			var ri : PictureRect = rects[i]
			var rj : PictureRect = rects[j]
			if WallPacker.frame_outer_rect(ri).intersects(WallPacker.frame_outer_rect(rj)):
				return true
	return false

# ------------------------------------------------------------------ drawn extent

# What a picture DRAWS must equal its PictureRect, in every render-target state.

# ⚠ %Screen and %Shadow are Sprite2Ds whose texture IS the SubViewport render target, so their drawn
# size is viewport.size * scale, NOT design_size * scale. Dividing a scale by _design_size is only
# equal to viewport.size while a picture is focused.

# viewport.size is rewritten to the wall-view footprint on unfocus() and on every resize, so an
# unfocused picture collapses to rect.size * footprint / design_size - measured on a real Main, a
# 1152x648 picture drew 385x216 inside its own full-size 1200x696 frame after one Wall press.

# Asserted through the ENGINE's own Sprite2D.get_rect() rather than by re-deriving the scale: an
# assertion on the scale field would re-prove this test's own arithmetic and could not fail for the
# mismatch it exists to catch.
func test_screen_draws_at_rect_size_through_every_render_target_change() -> void:
	var wp := _pictures[0]
	var screen : Sprite2D = wp.get_node(^"%Screen")
	var shadow : Sprite2D = wp.get_node(^"%Shadow")

# An explicit arbitrary render-target size first: earlier tests in this suite have already unfocused
# this picture, so "straight out of build()" would be a lie about the state.
	wp.update_wall_view_size(Vector2(100, 100))
	_check_drawn(wp, screen, shadow, "with the render target at an arbitrary small size")
	wp.focus()
	_check_drawn(wp, screen, shadow, "focused (render target back at design_size)")
# The wall-view footprint a real Main passes, much smaller than the rect, which is the whole point:
# render-target pixels are spent on what is actually on screen.
	wp.unfocus(wp.rect.size * 0.25)
	_check_drawn(wp, screen, shadow, "unfocused (render target shrunk to the footprint)")
# The resize path: Main._on_window_resized() calls this directly on every unfocused picture, with no
# focus() or unfocus() around it.
	wp.update_wall_view_size(wp.rect.size * 0.1)
	_check_drawn(wp, screen, shadow, "after a bare update_wall_view_size(), as a resize does")
# And a re-pack to a genuinely different rect while the render target stays small.
	var moved := PictureRect.new(wp.rect.id, wp.rect.centre + Vector2(40, 40),
			wp.rect.size * 1.7, wp.rect.frame_px)
	wp.reposition(moved)
	_check_drawn(wp, screen, shadow, "after a re-pack to a bigger rect")
	wp.focus()

func _check_drawn(wp: WallPicture, screen: Sprite2D, shadow: Sprite2D, when: String) -> void:
	var drawn := screen.get_rect().size * screen.scale
	check(drawn.is_equal_approx(wp.rect.size),
			"the screen sprite draws exactly rect.size %s" % when,
			"drawn=%s rect=%s viewport=%s" % [drawn, wp.rect.size, wp.viewport.size])
	var shadow_drawn := shadow.get_rect().size * shadow.scale
	check(shadow_drawn.is_equal_approx(wp.rect.size),
			"...and the shadow sprite does too %s" % when,
			"drawn=%s rect=%s" % [shadow_drawn, wp.rect.size])

# ------------------------------------------------------------------ nine-slice

# The frame is a genuine nine-slice in the REAL game, built from the REAL layout resource the game
# loads.

# ⚠ A gate of `entry.frame_texture == shared_frame_texture()` is reference identity, and a texture
# deserialised from that .tres is a different instance, so patch margins never get set and a 40x40
# bevel smears across the whole frame.

# Every fixture in this repo assigns the shared texture DIRECTLY, so nothing there can see it; this
# test deliberately goes through the file.
func test_nine_slice_applies_to_the_layout_the_game_actually_loads() -> void:
	var layout := Wall.load_layout()
	var entry : PictureEntry = layout.pictures[0]
	check(entry.frame_texture != null, "sanity: the authored layout really carries a frame texture")
	if entry.frame_texture == null: return
# The whole point: same pixels, different object. If these were the same instance an identity gate
# would pass and this test would prove nothing.
	check(entry.frame_texture != WallPicture.shared_frame_texture(),
			"sanity: the .tres texture is a DIFFERENT instance from the generated shared one -- "
			+ "if this ever becomes false, this test has stopped covering the defect it exists for")

	var rect := PictureRect.new(entry.id, Vector2.ZERO, Vector2(1330, 745), Vector4(24, 24, 24, 24))
	var wp : WallPicture = WALL_PICTURE_SCENE.instantiate()
	add_child(wp)
	wp.build(rect, entry, _wall.get_node(^"%Viewports"))
	var frame : NinePatchRect = wp.get_node(^"%Frame")
	check(frame.patch_margin_left > 0 and frame.patch_margin_top > 0
			and frame.patch_margin_right > 0 and frame.patch_margin_bottom > 0,
			"the authored frame texture gets real nine-slice margins",
			"l=%d t=%d r=%d b=%d" % [frame.patch_margin_left, frame.patch_margin_top,
					frame.patch_margin_right, frame.patch_margin_bottom])
# The margins must fit the texture, or the corners are degenerate - the failure an identity gate
# only approximates, expressed here as a property of the texture itself.
	var tex_size := entry.frame_texture.get_size()
	check(frame.patch_margin_left + frame.patch_margin_right <= int(tex_size.x)
			and frame.patch_margin_top + frame.patch_margin_bottom <= int(tex_size.y),
			"...and opposing margins never meet or cross inside the texture",
			"margins=%d+%d of %s" % [frame.patch_margin_left, frame.patch_margin_right, tex_size])
	wp.teardown()

# A deliberately TINY texture: still a valid nine-slice, never a degenerate one.
	var tiny := PictureEntry.new()
	tiny.id = &"tiny"
	tiny.design_size = Vector2i(64, 64)
	tiny.frame_texture = ImageTexture.create_from_image(
			Image.create(8, 8, false, Image.FORMAT_RGBA8))
	var tiny_wp : WallPicture = WALL_PICTURE_SCENE.instantiate()
	add_child(tiny_wp)
	tiny_wp.build(PictureRect.new(&"tiny", Vector2.ZERO, Vector2(400, 400), Vector4(8, 8, 8, 8)),
			tiny, _wall.get_node(^"%Viewports"))
	var tiny_frame : NinePatchRect = tiny_wp.get_node(^"%Frame")
	check(tiny_frame.patch_margin_left > 0 and tiny_frame.patch_margin_left * 2 <= 8,
			"an 8px frame texture gets a REAL corner it can actually carry, not the shared 14 "
			+ "and not zero", str(tiny_frame.patch_margin_left))
	tiny_wp.teardown()

# ------------------------------------------------------------------ selection lift

# The lift is part of WHERE a picture is, so it survives a re-pack, and it yields to focus, because
# a focused picture is not in wall view.

# ⚠ Two halves that can contradict each other. reposition() writing position = rect.centre flat
# silently un-lifts a selected picture with nothing re-rendering the selection afterwards, and a
# focus() that never clears the lift leaves a keyboard-entered picture 14 units high.

# Both are derived in one place from `is_selected and not is_focused`.
func test_selection_lift_survives_a_repack_and_yields_to_focus() -> void:
	var wp := _pictures[0]
	var lift : Vector2 = SettingsManager.settings.wall_selected_lift
	check(lift != Vector2.ZERO, "sanity: the lift is non-zero, so this test can fail", str(lift))
	wp.unfocus(wp.rect.size * 0.25)
	wp.set_selected(true)
	check(wp.position.is_equal_approx(wp.rect.centre + lift),
			"a selected picture in wall view is lifted", str(wp.position))

# THE RE-PACK: a new rect while the selection is live.
	var moved := PictureRect.new(wp.rect.id, wp.rect.centre + Vector2(90, 70), wp.rect.size,
			wp.rect.frame_px)
	wp.reposition(moved)
	check(wp.position.is_equal_approx(moved.centre + lift),
			"...and it is STILL lifted after a re-pack, at its new centre", str(wp.position))

# Entering it drops the lift; leaving it brings the lift back, because it is still selected.
	wp.focus()
	check(wp.position.is_equal_approx(moved.centre),
			"focusing it drops the lift -- a focused picture is not in wall view", str(wp.position))
	wp.unfocus(moved.size * 0.25)
	check(wp.position.is_equal_approx(moved.centre + lift),
			"...and leaving it restores the lift, because the selection never went away",
			str(wp.position))

	wp.set_selected(false)
	check(wp.position.is_equal_approx(moved.centre),
			"deselecting puts it back down", str(wp.position))
	wp.reposition(_pictures[0].rect)
	wp.focus()

# ------------------------------------------------------------------ shared-track crossfade

# Stepping between two pictures that share a music track must not stop the music.

# ⚠ begin_music_crossfade() early-returns without arming the background player when the
# destination's stream is ALREADY the one playing, deliberately, so a shared track does not restart
# and glitch.

# A finish_music_crossfade() that flips _music_active regardless promotes the silent, never-armed
# player to foreground and the music stops dead, which is precisely the glitch the early return
# exists to prevent. It is latent only because no authored layout entry carries music yet.

# The stream below is a real, playable one, so no asset is needed.
func test_a_crossfade_between_pictures_sharing_a_track_keeps_playing() -> void:
	var track := AudioStreamGenerator.new()
	var entry := PictureEntry.new()
	entry.id = &"shared"
	entry.music = track

	_wall.start_music(entry)
	var playing_before : AudioStreamPlayer = _wall.get_node(^"%MusicA")
	if not playing_before.playing:
		playing_before = _wall.get_node(^"%MusicB")
	check(playing_before.playing and playing_before.stream == track,
			"sanity: the shared track is playing before the move")

# The move: the same entry as destination, i.e. the same stream.
	_wall.begin_music_crossfade(entry)
	_wall.update_travel_music(Vector2.ZERO, Vector2(100, 0), Vector2(50, 0))
	_wall.finish_music_crossfade()

	var a : AudioStreamPlayer = _wall.get_node(^"%MusicA")
	var b : AudioStreamPlayer = _wall.get_node(^"%MusicB")
	var live := a if a.playing else b
	check(live.playing and live.stream == track,
			"the shared track is STILL playing after the move -- the crossfade did not swap to a "
			+ "silent player", "A(playing=%s) B(playing=%s)" % [a.playing, b.playing])
	check(live.volume_db > -40.0,
			"...and it is audible, not left faded out", "volume_db=%.1f" % live.volume_db)

	a.stop()
	b.stop()

# ------------------------------------------------------------------ overlapping re-packs

# A live tween from an earlier re-pack keeps writing `position` toward targets computed from the
# OLD rects while `rect` already says otherwise, so a second `apply_layout()` must cancel the first.
# ⚠ PINS base_delay = 1.0: at the run's pacing the long leg below would end inside the wait.
func test_a_second_repack_kills_the_first_ones_tween() -> void:
	backup_real_settings()
	var settings := SettingsManager.settings
	var prev_delay : float = settings.wall_transition_delay
	var wp := _pictures[0]
	var start := wp.rect
	var far := PictureRect.new(start.id, start.centre + Vector2(1200, 900), start.size,
			start.frame_px)
	var near := PictureRect.new(start.id, start.centre + Vector2(40, 30), start.size,
			start.frame_px)

# ⚠ THE FIRST ANIMATION MUST OUTLIVE THE SECOND, or this test is vacuous. Both tweens write position
# every frame and the later-created one's write lands last, so with equal durations the second
# simply paints over the first and the picture ends up correct ANYWAY.

# Measured: with equal durations the test passed with the kill removed. A long first and a short
# second is what leaves the stale tween still writing after the real one has finished.
	settings.base_delay = 1.0
	settings.wall_transition_delay = 2.0
	var by_id : Dictionary[StringName, PictureRect] = {}
	by_id[start.id] = far
	_wall.apply_layout(by_id, true)
	await get_tree().process_frame
	await get_tree().process_frame
	check(_wall._layout_tween != null and _wall._layout_tween.is_valid(),
			"sanity: the first, LONG re-pack really is animating")

	settings.wall_transition_delay = 0.05
	var second : Dictionary[StringName, PictureRect] = {}
	second[start.id] = near
	_wall.apply_layout(second, true)
# Long enough for the SHORT second tween to have finished and the LONG first one to still be running
# if it was never killed.
	for _i : int in range(30):
		await get_tree().process_frame

	check(wp.rect.centre.is_equal_approx(near.centre),
			"the picture's rect is the SECOND re-pack's", str(wp.rect.centre))
	check(wp.position.distance_to(near.centre) < 40.0,
			"...and it is DRAWN there, not dragged onward by the first re-pack's surviving tween",
			"drawn=%s second=%s first=%s" % [wp.position, near.centre, far.centre])

	settings.wall_transition_delay = prev_delay
	apply_test_speed()
	var restore : Dictionary[StringName, PictureRect] = {}
	restore[start.id] = start
	_wall.apply_layout(restore, false)
	restore_real_settings()

# ------------------------------------------------------------------ per-grid camera pose

# WallPicture.grid_state() on a 3-grid board: the resting grid, index 1 under PlayArea's own "middle
# of the grids" rule for an odd count, must reproduce resting_state() exactly.

# Each neighbour must sit exactly one PlayArea.grid_position_size_px() pitch away, so the step
# between consecutive grids' positions must equal that pitch rather than "some" offset, and a
# neutralisation that drops the offset term still fails here.
func test_grid_state_steps_by_the_grid_pitch_and_reproduces_rest_at_the_resting_grid() -> void:
	var settings := SettingsManager.settings
	var rect := PictureRect.new(&"probe", Vector2(1828.0, 342.5), Vector2(3656.0, 685.0),
			Vector4.ZERO)
	var window := Vector2(1152.0, 648.0)
	var resting_grid := 1

	var pitch := PlayArea.grid_position_size_px(settings).x

	var rest := WallPicture.resting_state(rect, window, settings)
	var s0 := WallPicture.grid_state(rect, window, settings, 0, resting_grid, pitch)
	var s1 := WallPicture.grid_state(rect, window, settings, 1, resting_grid, pitch)
	var s2 := WallPicture.grid_state(rect, window, settings, 2, resting_grid, pitch)

	var rest_pos : Vector2 = rest["position"]
	var pos0 : Vector2 = s0["position"]
	var pos1 : Vector2 = s1["position"]
	var pos2 : Vector2 = s2["position"]
	var zoom1 : float = s1["zoom"]
	var rest_zoom : float = rest["zoom"]

	check(pos1.is_equal_approx(rest_pos),
			"the resting grid's pose equals resting_state()'s exactly",
			"pos1=%s rest=%s" % [pos1, rest_pos])
	check(is_equal_approx(zoom1, rest_zoom),
			"zoom is unchanged from resting_state() at the resting grid",
			"zoom1=%.6f rest_zoom=%.6f" % [zoom1, rest_zoom])
	check(is_equal_approx(pos1.x - pos0.x, pitch),
			"the step from grid 0 to grid 1 equals grid_position_size_px().x exactly",
			"step=%.4f pitch=%.4f" % [pos1.x - pos0.x, pitch])
	check(is_equal_approx(pos2.x - pos1.x, pitch),
			"the step from grid 1 to grid 2 equals grid_position_size_px().x exactly",
			"step=%.4f pitch=%.4f" % [pos2.x - pos1.x, pitch])
	check(is_equal_approx(pos0.y, rest_pos.y) and is_equal_approx(pos2.y, rest_pos.y),
			"position.y is unchanged from resting_state() at every grid, only x steps",
			"y0=%.4f y2=%.4f rest_y=%.4f" % [pos0.y, pos2.y, rest_pos.y])

# WallPicture.panned_state(), the offset primitive grid_state() is expressed in terms of. This
# proves it directly, then proves the two AGREE on the identity that makes grid_state() a delegation
# rather than a second, separately-maintained computation.
func test_panned_state_is_the_offset_primitive_grid_state_delegates_to() -> void:
	var settings := SettingsManager.settings
	var rect := PictureRect.new(&"probe", Vector2(1828.0, 342.5), Vector2(3656.0, 685.0),
			Vector4.ZERO)
	var window := Vector2(1152.0, 648.0)
	var pitch := PlayArea.grid_position_size_px(settings).x
	var resting_grid := 1
	var grid_index := 2

	var rest := WallPicture.resting_state(rect, window, settings)
	var zero_offset := WallPicture.panned_state(rect, window, settings, 0.0)
	var rest_pos : Vector2 = rest["position"]
	var zero_pos : Vector2 = zero_offset["position"]
	var rest_zoom : float = rest["zoom"]
	var zero_zoom : float = zero_offset["zoom"]
	check(zero_pos.is_equal_approx(rest_pos) and is_equal_approx(zero_zoom, rest_zoom),
			"a zero offset reproduces resting_state() exactly",
			"pos=%s rest=%s zoom=%.6f rest_zoom=%.6f" % [zero_pos, rest_pos, zero_zoom, rest_zoom])

	var offset_x := 137.0
	var offset_state := WallPicture.panned_state(rect, window, settings, offset_x)
	var offset_pos : Vector2 = offset_state["position"]
	var offset_zoom : float = offset_state["zoom"]
	check(is_equal_approx(offset_pos.x - rest_pos.x, offset_x),
			"a non-zero offset moves position.x by exactly that amount",
			"delta=%.4f offset=%.4f" % [offset_pos.x - rest_pos.x, offset_x])
	check(is_equal_approx(offset_pos.y, rest_pos.y),
			"...and leaves position.y untouched", "offset_y=%.4f rest_y=%.4f" % [offset_pos.y, rest_pos.y])
	check(is_equal_approx(offset_zoom, rest_zoom),
			"...and leaves zoom untouched", "offset_zoom=%.6f rest_zoom=%.6f" % [offset_zoom, rest_zoom])

# THE identity: grid_state() must equal panned_state() called at the same offset the grid implies,
# or grid_state() has drifted into a second, separately-maintained computation.
	var via_grid := WallPicture.grid_state(rect, window, settings, grid_index, resting_grid, pitch)
	var via_offset := WallPicture.panned_state(rect, window, settings,
			pitch * float(grid_index - resting_grid))
	var via_grid_pos : Vector2 = via_grid["position"]
	var via_offset_pos : Vector2 = via_offset["position"]
	check(via_grid_pos.is_equal_approx(via_offset_pos),
			"grid_state() agrees with panned_state() called at the equivalent offset -- one "
			+ "computation, not two", "grid=%s offset=%s" % [via_grid_pos, via_offset_pos])

# WallPicture.snap_pan_to_grid(), the arithmetic between a SAVED pan and the board it is restored
# onto. Three separate obligations, and a neutralisation that drops any one of them fails here.

# It rounds a pan that fell between two grids onto a whole step, it clamps a pan that names a grid
# the board no longer has, and it leaves a pan that already names a real grid exactly alone.

# resting_grid is 1 throughout, an odd board's middle, so a NEGATIVE offset is a real grid rather
# than an out-of-range one, which is what makes the clamp check below distinguishable from the
# round check.
func test_snap_pan_to_grid_rounds_to_a_whole_step_and_clamps_into_the_board() -> void:
	var pitch := 846.0
	var resting := 1

	check(is_equal_approx(WallPicture.snap_pan_to_grid(pitch, pitch, resting, 3), pitch),
			"a pan that already names a real grid is returned untouched",
			str(WallPicture.snap_pan_to_grid(pitch, pitch, resting, 3)))
	check(is_equal_approx(WallPicture.snap_pan_to_grid(-pitch, pitch, resting, 3), -pitch),
			"...and so is a NEGATIVE one, which is grid 0 on a board resting on grid 1",
			str(WallPicture.snap_pan_to_grid(-pitch, pitch, resting, 3)))
	check(is_equal_approx(WallPicture.snap_pan_to_grid(pitch * 0.6, pitch, resting, 3), pitch),
			"a pan BETWEEN two grids rounds to the nearer whole step, not to the one it passed",
			str(WallPicture.snap_pan_to_grid(pitch * 0.6, pitch, resting, 3)))
	check(is_equal_approx(WallPicture.snap_pan_to_grid(pitch * 0.4, pitch, resting, 3), 0.0),
			"...and rounds the other way below the halfway point, so the round is a real round",
			str(WallPicture.snap_pan_to_grid(pitch * 0.4, pitch, resting, 3)))
	check(is_equal_approx(WallPicture.snap_pan_to_grid(pitch * 5.0, pitch, resting, 3), pitch),
			"a pan naming a grid past the LAST one clamps to the last grid the board has",
			str(WallPicture.snap_pan_to_grid(pitch * 5.0, pitch, resting, 3)))
	check(is_equal_approx(WallPicture.snap_pan_to_grid(pitch * -5.0, pitch, resting, 3), -pitch),
			"...and one past the FIRST clamps to grid 0",
			str(WallPicture.snap_pan_to_grid(pitch * -5.0, pitch, resting, 3)))
	check(is_equal_approx(WallPicture.snap_pan_to_grid(pitch, pitch, 0, 1), 0.0),
			"a one-grid board has nowhere to pan to, so every pan collapses to its centre",
			str(WallPicture.snap_pan_to_grid(pitch, pitch, 0, 1)))
	check(is_equal_approx(WallPicture.snap_pan_to_grid(pitch, pitch, 0, 0), 0.0),
			"a board with NO grids answers 0 rather than dividing by a pitch it cannot use",
			str(WallPicture.snap_pan_to_grid(pitch, pitch, 0, 0)))
	check(is_equal_approx(WallPicture.snap_pan_to_grid(pitch, 0.0, resting, 3), 0.0),
			"...and so does a zero pitch, which is what a board measured before layout reports",
			str(WallPicture.snap_pan_to_grid(pitch, 0.0, resting, 3)))


# Tools/wall_editor.tscn DRIVES EVERY KNOB IT SHOWS. The tool's whole promise is that a number tuned
# on its panel reaches the same code the game runs it through; otherwise the preview is not evidence
# about anything.

# knobs_this_preview_does_not_drive is the tool's own honest answer, and this asserts it is EMPTY on
# a real run.

# ⚠ THE FIELD MUST BE A READING, NOT A CLAIM. One that returns "" for any run with a Wall at all
# passes while the board knobs on the panel are ignored outright by the hosted GameView.

# The second check below is what gives the first any weight: the SCREENS the tool hosts must resolve
# to the same preview_settings the panel edits.

# ⚠ A REAL wall_editor.tscn, NOT A STAND-IN: the thing under test is the tool's own wiring, and a
# hand-built copy of it could only ever agree with itself.
func test_the_wall_editor_drives_every_knob_it_shows() -> void:
	var previous := WallPicture.editor_settings
	var editor_scene : PackedScene = load("res://Tools/wall_editor.tscn")
	var editor : WallEditor = editor_scene.instantiate()
	add_child(editor)
# Wall._ready() pauses the tree globally, exactly as it does in the game, and it is undone here the
# same way every other Main-hosted fixture in this repo undoes it.
	get_tree().paused = false
	for _i : int in 4:
		await get_tree().process_frame

	check(editor.preview_settings != null,
			"precondition: the tool has its own settings resource to tune (TP-120)")
	check(PlayArea.settings() == editor.preview_settings,
			"a knob tuned on the tool's panel reaches the BOARD it hosts -- `PlayArea.settings()` "
			+ "resolves the same override the tool sets, so `board_edge_pad_rows` and the rest are "
			+ "not silently inert (TP-120)",
			"board reads %s, panel edits %s" % [PlayArea.settings(), editor.preview_settings])
	check(WallPicture.settings() == editor.preview_settings,
			"...and so does the WALL, through the accessor both halves share (TP-120)")
	var undriven := editor.undriven_knobs()
	check(undriven.is_empty(),
			"`knobs_this_preview_does_not_drive` is EMPTY when the editor is run (TP-120, Q186=a)",
			"undriven: %s" % [undriven])

	editor.queue_free()
	await get_tree().process_frame
	WallPicture.editor_settings = previous

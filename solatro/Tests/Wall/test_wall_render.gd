extends TestSuite
# res://Tests/Wall/test_wall_render.gd
# ==============================================================================
# WALL RENDER (S10 CONSTRUCTION group: N1, N5. S11 RENDER GATING group: N2, N3, N4, N6, N7).
# PLAN.md §1.7, §1.8; TEST_PLAN.md §7.
#
# Builds a real res://UI/Wall/wall.tscn plus a few real WallPicture instances from a small
# PROGRAMMATIC WallLayout (never res://Assets/Wall/layout_default.tres -- that is the layout
# TOOL's output, S34, out of scope here), then inspects the constructed tree.
# ==============================================================================

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
	behavior_section("DRAWN EXTENT TRACKS THE RECT, NOT THE RENDER TARGET")
	test_screen_draws_at_rect_size_through_every_render_target_change()
	behavior_section("MEMORY READOUT (S39, E9, Q210=a)")
	test_debug_memory_readout_counts_screens_and_viewports()
	test_debug_readout_gated_by_wall_debug_readout_flag()
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

## A small, varied, PROGRAMMATIC layout -- three pictures, different sizes and frame thicknesses,
## enough to exercise real construction without authoring the tool's own layout resource.
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
	# ⚠ Wall._ready() sets get_tree().paused = true, GLOBALLY, by design (§1.6) -- correct
	# standalone, but this suite runs CONCURRENTLY with ~33 others that need normal processing to
	# ever finish, and a global pause with no unpause hangs the whole run with no banner (measured:
	# a 600s timeout, no suite ever signals finished). Safe to undo immediately: add_child() above
	# already ran Wall._ready() SYNCHRONOUSLY (the parent was already in the tree), and nothing else
	# can run between that call and this line since GDScript only yields at an explicit await.
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

## Frees every constructed picture (and its off-tree SubViewport, teardown()'s whole reason to
## exist) plus the wall itself, so this suite leaves nothing behind for its siblings.
func _teardown_wall() -> void:
	for wp : WallPicture in _pictures: wp.teardown()
	_pictures.clear()
	if _wall and is_instance_valid(_wall): _wall.queue_free()
	_wall = null

# ------------------------------------------------------------------ N1, N5

## N1: every SubViewport constructed for the wall is explicitly NEAREST -- the trap this repo has
## hit four times (§1c).
func test_every_subviewport_is_explicitly_nearest() -> void:
	check(_pictures.size() == 3, "3 pictures were constructed", str(_pictures.size()))
	for wp : WallPicture in _pictures:
		check(wp.viewport != null, "%s has a SubViewport" % wp.name)
		if wp.viewport:
			check(wp.viewport.canvas_item_default_texture_filter
					== Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST,
					"%s's SubViewport is explicitly NEAREST" % wp.name)

## N5: no SubViewportContainer exists anywhere in the wall (GAP-001=b -- the decision this defends).
func test_no_subviewport_container_anywhere() -> void:
	check(not _has_subviewport_container(_wall), "no SubViewportContainer anywhere in the wall")

func _has_subviewport_container(node: Node) -> bool:
	if node is SubViewportContainer: return true
	for child : Node in node.get_children():
		if _has_subviewport_container(child): return true
	return false

# ------------------------------------------------------------------ N2, N3, N4, N6, N7 (S11)

## N3 (E4, Q78=b): every picture has a non-null texture straight out of build(), before any focus()
## call is made anywhere in this suite -- run first in the RENDER GATING group on purpose so later
## tests' focus()/unfocus() calls cannot retroactively make this claim vacuous.
func test_unvisited_picture_has_rendered_once() -> void:
	for wp : WallPicture in _pictures:
		check(wp.viewport.get_texture() != null,
				"%s's texture is non-null before any focus() call" % wp.name)

## N2 (E3, Q82=a): a non-focused picture reports UPDATE_DISABLED, but its already-rendered texture
## persists -- never null, never zero-size.
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

## N4 (§1.8, GAP-002): SubViewport.size is written straight from the on-screen footprint, each axis
## independently clamped below by settings.wall_view_min_texture_px -- shrinking one axis to 10px
## clamps that (short) axis to the floor without disturbing the other.
func test_wall_view_size_written_and_clamped() -> void:
	var wp := _pictures[0]
	wp.unfocus(Vector2(10, 500))
	var min_px := SettingsManager.settings.wall_view_min_texture_px
	check(mini(wp.viewport.size.x, wp.viewport.size.y) == min_px,
			"a 10px footprint clamps the short axis to wall_view_min_texture_px",
			str(wp.viewport.size))

## N6 (E7, Q208=b): restoring from minimise re-renders every picture once. Wall._notification hooks
## NOTIFICATION_APPLICATION_FOCUS_IN (ASSUMPTIONS.md -- the closest built-in "un-minimise" event on
## desktop) and calls mark_for_rerender() on every WallPicture under %Pictures.
func test_restore_from_minimise_rerenders() -> void:
	# ⚠ ONE PICTURE IS FOCUSED. The original fixture settled EVERY picture to UPDATE_DISABLED, so
	# none was live and the notification could not possibly harm one -- it asserted a property that
	# could not fail (PICTURE_WALL.md C1). E7 and Q208=b both say every FROZEN texture is
	# re-rendered, not every picture: the focused one is not frozen, it is UPDATE_ALWAYS, and
	# forcing UPDATE_ONCE on it freezes the live screen for the rest of the session.
	for wp : WallPicture in _pictures:
		wp.viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED  # simulate "settled"
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

## PICTURE_WALL.md C6: `res://Assets/Wall/layout_default.tres` had ZERO production readers --
## `Main` called the hardcoded `Wall.initial_layout()`, so everything an author tuned in S34's tool
## was discarded. Proves the loader really reads the FILE (not the fallback) by pointing it at a temp
## resource carrying a value the built-in layout could never produce, and proves the fallback still
## works when the file is absent. No mock: a real WallLayout, really saved, really loaded.
func test_layout_is_loaded_from_disk_not_hardcoded() -> void:
	var temp_path := "user://_test_layout_probe.tres"
	var probe := WallLayout.new()
	probe.gap_px = 1234.5   # a value initial_layout() never sets
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

## N7 (H6, Q34): the filter swaps on zoom, not on pan -- pure translation must never flip it. Owed
## to S11 per TEST_PLAN.md §7's own suite header ("S10, S11"), even though the full camera-driven
## wiring is S13's job (§1.7); this pins the method's own contract directly.
func test_filter_swaps_on_zoom_not_pan() -> void:
	var wp := _pictures[0]
	var screen : Sprite2D = wp.get_node(^"%Screen")
	wp.update_filter(false)
	check(screen.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST,
			"pan only (zoom unchanged) leaves the filter NEAREST")
	wp.update_filter(true)
	check(screen.texture_filter == CanvasItem.TEXTURE_FILTER_LINEAR,
			"a zoom change flips the filter to LINEAR")

## M5 (PICTURE_WALL.md, S13, QR7=c, H4/H5, Q34=c): `update_filter(true)` had NO CALLER, so the
## focused picture sampled NEAREST through every zoom and S13 was dead. The test above pins the
## METHOD; this pins the WIRING -- a REAL camera zoom, on a REAL `Wall`, across REAL frames. It goes
## red if `Wall._process()`'s tracking is removed.
##
## Q34=c is the half most easily lost: a pure PAN must leave the filter alone. Asserted after a
## position change large enough that any position-sensitive implementation would have flipped it.
func test_the_wall_actually_drives_the_filter_swap_as_the_camera_zooms() -> void:
	var wp := _pictures[0]
	var screen : Sprite2D = wp.get_node(^"%Screen")
	var camera : Camera2D = _wall.get_node(^"%Camera2D")
	# Exactly ONE focused picture, by construction: `_focused_picture()` returns the FIRST it finds,
	# so an earlier test leaving another one focused would silently point this test at the wrong
	# picture and it would then prove nothing about `wp` at all.
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

# ------------------------------------------------------------------ GAP-011 (H3)

## GAP-011: `wall_overfill_margin` is a real, READ knob, not a promoted-but-ignored export -- the
## exact defect §1.8 exists to prevent ("a knob nothing reads is the defect"). `focused_scale()`
## takes the margin as a REQUIRED parameter (no default), so this also proves the parameter is
## actually wired through, not merely present on `PlayerSettings`. Two visibly different margins on
## the SAME native/window sizes must produce two DIFFERENT scales, and each must equal the plain
## fill-ratio times its own margin exactly -- not just "different", which a sign flip or an
## unrelated bug could also produce.
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

## H3's own words: the picture overfills "whenever its aspect does not match" the window's -- the
## margin is CONDITIONAL. Measured defect, not theorised: the unconditional version cropped the
## real start-menu picture's own bottom button row at an ordinary 1280x720-in-1152x648 case (both
## 16:9) -- a case with NOTHING to hide, since fill and fit already coincide at matching aspect.
func test_overfill_margin_only_applies_when_aspect_mismatches() -> void:
	# Matching aspect, same magnitude too (both 16:9, native == window / (4/3)) -- the fill ratio
	# itself is exactly 1.0, so a correct result here is REQUIRED to be exactly 1.0, not merely
	# "some value the margin didn't touch" -- the coordinator's own literal ask.
	var matching_native := Vector2(1152, 648)
	var matching_window := Vector2(1280, 720)   # 1280/1152 == 720/648 == 1.1111... -- same ratio
	var matching_scale := WallPicture.focused_scale(matching_native, matching_window, 1.02)
	check(is_equal_approx(matching_scale, 1.1111111),
			"matching aspect gives the EXACT fill ratio, margin not applied at all",
			"scale=%.6f expected=1.111111" % matching_scale)

	# Mismatched aspect (4:3 native in a 16:9 window, same fixture the sibling test above already
	# uses) -- the margin MUST still apply here, so this row cannot pass by disabling the margin
	# outright; it has to be genuinely conditional.
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

# ------------------------------------------------------------------ PICTURE_WALL.md B2

## PICTURE_WALL.md B2: `wall_selected_lift` is a REAL, READ knob -- was a typed literal
## (`_SELECTED_LIFT`) in `wall_picture.gd`, same category `wall_overfill_margin`/`wall_light_offset`
## already promoted. Two different lift values on the SAME picture must produce two different
## `position` results after `set_selected(true)`, each exactly `rect.centre + the configured lift`
## -- not just "different", the same rigor `test_overfill_margin_knob_actually_changes_the_scale`
## above already established.
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

# ------------------------------------------------------------------ S30 (B7, Q211=a)

## S30 (B7, Q211=a, Q141=a): `build()`'s new `live_screen` parameter REPARENTS an
## already-instantiated node as `screen_root` -- never instantiates a copy, never touches its
## children/state. Proven by IDENTITY (`==`, not just "a screen_root exists"): the exact same
## object handed in comes back out, still holding the marker child it had BEFORE `build()` ever
## ran, and is a real child of the picture's own SubViewport afterward.
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

# ------------------------------------------------------------------ S39 (E8, E9, Q203=a, Q210=a)

## E8/Q203=a (S39's own coverage-hole close -- TestLeakCanary structurally cannot watch this: it
## never builds a Wall/WallPicture at all, and its own header explicitly locks it to run LAST and
## ALONE because OBJECT_COUNT is engine-global, so retrofitting a Wall into it would both be the
## wrong suite for a screen-lifecycle question and would pollute the very CardData deltas it exists
## to measure). "All screens stay instantiated for the whole session... nothing is ever torn down"
## proven by IDENTITY across several focus()/unfocus() cycles: the SAME screen_root node survives
## every cycle, never freed and rebuilt -- which is what "nothing is ever torn down" cashes out to
## for a picture that keeps getting focused and unfocused over and over, the exact thing a session
## actually does.
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

## S39 (E9, Q210=a): `Wall.debug_memory_readout()` counts instantiated screens and viewports
## correctly against a KNOWN fixture -- two pictures with a live screen (screens_instantiated == 2)
## plus one "registered but unbuilt" picture with no scene at all (Q214=a's own case, screen_root
## stays null) -- proving the count is screens ACTUALLY instantiated, not just pictures that exist.
## Also asserts the reported string actually names both numbers, not just a placeholder message --
## a check() that could pass on an empty/malformed string would be the exact "prints something,
## proves nothing" trap this run keeps finding new forms of.
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
	# "unbuilt" (Q214=a): no scene, no live_screen -- screen_root stays null on purpose.
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

## S39 done-when's OTHER half ("the readout prints under the debug flag"), on a REAL `Main` --
## `Main._wall_debug_readout_text()` is the gate `_print_wall_debug_readout()` prints whatever it
## returns; tested directly rather than by capturing stdout (a `print()` call has no return value
## to assert on). BOTH directions checked on the SAME `Main`, one right after the other -- the
## coordinator's own instruction: "the false case is the 'assert it did not happen' shape, so make
## sure it can fail." It can: the ON check just above proves this exact fixture, this exact flag,
## produces non-empty text when true, so the OFF check going empty immediately after is a real
## state change being observed, not a fixture that was always going to read empty regardless.
## `backup_real_settings()`/`restore_real_settings()` park the real `user://settings.tres` for the
## toggle's duration -- `SettingsManager` saves on every change (`test_wall_profile.gd`'s R4 uses
## the identical pattern for the same reason, `wall_unlock_all`).
func test_debug_readout_gated_by_wall_debug_readout_flag() -> void:
	check(OS.is_debug_build(),
			"sanity: this suite runs via the debug console exe -- OS.is_debug_build() is true, "
			+ "the OTHER half of the gate this test does not flip")

	backup_real_settings()
	var main : Main = MAIN_SCENE.instantiate()
	add_child(main)
	# Main._ready() -> Wall._ready() sets get_tree().paused = true GLOBALLY -- undone immediately,
	# same established reason every Wall/Main-building test in this suite family documents.
	get_tree().paused = false

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

# ------------------------------------------------------------------ drawn extent

## What a picture DRAWS must equal its `PictureRect`, in every render-target state.
##
## ⚠ `%Screen`/`%Shadow` are `Sprite2D`s whose texture IS the `SubViewport` render target, so their
## drawn size is `viewport.size * scale` -- NOT `design_size * scale`. Every scale site here used to
## divide by `_design_size`, which is only equal to `viewport.size` while a picture is focused.
## GAP-002 rewrites `viewport.size` to the wall-view footprint on `unfocus()` and on every resize,
## so an unfocused picture collapsed to `rect.size * footprint / design_size` -- measured on a real
## `Main`, a 1152x648 picture drew 385x216 inside its own full-size 1200x696 frame after one Wall
## press, and shrank again on every resize.
##
## Asserted through the ENGINE's own `Sprite2D.get_rect()` rather than by re-deriving the scale:
## an assertion on the scale field would re-prove this test's own arithmetic and could not fail for
## the mismatch it exists to catch ([[tests-that-prove-nothing]] trap 6).
func test_screen_draws_at_rect_size_through_every_render_target_change() -> void:
	var wp := _pictures[0]
	var screen : Sprite2D = wp.get_node(^"%Screen")
	var shadow : Sprite2D = wp.get_node(^"%Shadow")

	# An explicit arbitrary render-target size first: earlier tests in this suite have already
	# unfocused this picture, so "straight out of build()" would be a lie about the state.
	wp.update_wall_view_size(Vector2(100, 100))
	_check_drawn(wp, screen, shadow, "with the render target at an arbitrary small size")
	wp.focus()
	_check_drawn(wp, screen, shadow, "focused (render target back at design_size)")
	# The wall-view footprint a real `Main` passes: much smaller than the rect, which is the whole
	# point -- GAP-002 spends render-target pixels on what is actually on screen.
	wp.unfocus(wp.rect.size * 0.25)
	_check_drawn(wp, screen, shadow, "unfocused (render target shrunk to the footprint)")
	# The resize path: `Main._on_window_resized()` calls this directly on every unfocused picture,
	# with no focus()/unfocus() around it.
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

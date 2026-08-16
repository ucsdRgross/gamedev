extends TestSuite
# res://Tests/Wall/test_wall_pause.gd
# ==============================================================================
# WALL PAUSE (S12): the engine's own pause system wired to the wall -- Wall/%Camera2D ALWAYS,
# every picture and screen root PAUSABLE by default, exactly one screen root ALWAYS while focused,
# Pacing vs a bare create_timer under the pause.
# PLAN.md §1.6; TEST_PLAN.md §4, U1-U7.
#
# ⚠ RUNS DEAD LAST, ALONE, AFTER LEAK CANARY -- see the SUITE ORDERING chain in test_base.gd. This
# suite constructs a REAL Wall, whose _ready() sets get_tree().paused = true GLOBALLY AND
# PERMANENTLY (§1.6, QR6=a). U1 requires this test to NOT undo that afterward (ASSUMPTIONS.md) --
# unlike test_wall_render.gd's fixture, which unpauses immediately as a concurrency workaround
# because IT runs alongside ~34 other suites that need normal frame processing to finish. That
# workaround would make U1 pass vacuously (proving only that paused briefly became true, never that
# it STAYS true), so this suite instead waits for literally everyone else to finish first
# (await_siblings_except([])) and is the one suite every other waiter now excludes by name.
#
# ⚠ WallOverlay (NAMES.md, S35) does not exist in this run -- U2 asserts Wall and %Camera2D only.
# Reported, not silently dropped; see ASSUMPTIONS.md.
# ==============================================================================

const WALL_SCENE := preload("res://UI/Wall/wall.tscn")
const WALL_PICTURE_SCENE := preload("res://UI/Wall/wall_picture.tscn")

func suite_name() -> String:
	return "WALL PAUSE"

var _wall : Wall = null
var _pictures : Array[WallPicture] = []

func _ready() -> void:
	await await_siblings_except([])
	TestLog.line("============ WALL PAUSE TEST PASS ============")
	behavior_section("PAUSE WIRING")
	_build_wall()
	await test_tree_paused_and_stays_paused()
	test_shell_stays_always()
	test_exactly_one_screen_live()
	test_wall_view_leaves_zero_live()
	test_info_mode_does_not_pause_focused_screen()
	behavior_section("PACING VS A BARE TIMER UNDER PAUSE")
	await test_pacing_wait_does_not_tick_while_paused()
	await test_bare_create_timer_ticks_while_paused()
	finish()

# ------------------------------------------------------------------ fixture

## A throwaway PackedScene wrapping a bare Node, standing in for a real screen -- U3/U4/U7 only
## need something instantiable whose process_mode they can read (ASSUMPTIONS.md).
func _dummy_scene() -> PackedScene:
	var root := Node.new()
	root.name = "DummyScreen"
	var packed := PackedScene.new()
	packed.pack(root)
	root.free()
	return packed

## One authored picture entry at the given angle, always carrying a _dummy_scene() so its packed
## WallPicture has a real "screen root" to flip process_mode on.
func _entry(id: StringName, slot_deg: int) -> PictureEntry:
	var e := PictureEntry.new()
	e.id = id
	e.slot = slot_deg
	e.scene = _dummy_scene()
	return e

## A small, programmatic three-picture layout -- never res://Assets/Wall/layout_default.tres (the
## layout tool's own output, S34, out of scope here), same convention as test_wall_render.gd.
func _make_layout() -> WallLayout:
	var l := WallLayout.new()
	l.gap_px = 24.0
	l.ellipse_aspect_min = 1.2
	l.ellipse_aspect_max = 2.6
	l.home_id = &"a"
	var pics : Array[PictureEntry] = [
		_entry(&"a", 0), _entry(&"b", 120), _entry(&"c", 240),
	]
	l.pictures = pics
	return l

## U1 (D1, QR6=a): constructing a real Wall pauses the tree globally and PERMANENTLY -- unlike
## every other suite that builds a Wall, this one deliberately never clears it afterward. Safe only
## because this suite runs dead last and alone (see header).
func _build_wall() -> void:
	_wall = WALL_SCENE.instantiate()
	add_child(_wall)
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

## Leaves exactly `target` focused (screen root ALWAYS) and unfocuses every other picture --
## simulating the arbitration wall_picture.gd's own docstring says is the caller's job (S12+'s real
## caller, not yet built, will do the same).
func _focus_only(target: WallPicture) -> void:
	for wp : WallPicture in _pictures:
		if wp == target: wp.focus()
		else: wp.unfocus(Vector2(200, 120))

## How many of _pictures currently have an ALWAYS screen root -- U3/U4's own invariant, read out.
func _always_screen_count() -> int:
	var n := 0
	for wp : WallPicture in _pictures:
		if wp.screen_root and wp.screen_root.process_mode == Node.PROCESS_MODE_ALWAYS:
			n += 1
	return n

# ------------------------------------------------------------------ U1-U4, U7

## U1 (D1, QR6=a): the tree is paused right after construction, and STAYS paused across at least
## one frame boundary with nothing in this test undoing it.
func test_tree_paused_and_stays_paused() -> void:
	check(get_tree().paused, "the tree is paused immediately after constructing a real Wall")
	await get_tree().process_frame
	check(get_tree().paused, "the tree is STILL paused one frame later -- nothing cleared it")

## U2 (D2): Wall and %Camera2D are PROCESS_MODE_ALWAYS. WallOverlay is S35 and does not exist in
## this run (see header) -- deliberately not asserted, not silently dropped.
func test_shell_stays_always() -> void:
	check(_wall.process_mode == Node.PROCESS_MODE_ALWAYS, "Wall is PROCESS_MODE_ALWAYS")
	var camera : Node = _wall.get_node(^"%Camera2D")
	check(camera.process_mode == Node.PROCESS_MODE_ALWAYS, "%Camera2D is PROCESS_MODE_ALWAYS")

## U3 (D4, Q74=a): focus each of 3 pictures in turn -> exactly one screen root is ALWAYS each time.
func test_exactly_one_screen_live() -> void:
	for target : WallPicture in _pictures:
		_focus_only(target)
		check(_always_screen_count() == 1,
				"exactly one screen root is ALWAYS while %s is focused" % target.name,
				str(_always_screen_count()))

## U4 (D8, Q74=a): wall view -- every picture unfocused -- leaves zero screen roots ALWAYS.
func test_wall_view_leaves_zero_live() -> void:
	for wp : WallPicture in _pictures:
		wp.unfocus(Vector2(200, 120))
	check(_always_screen_count() == 0, "wall view leaves zero screen roots ALWAYS",
			str(_always_screen_count()))

## U7 (D9, Q138=a): info mode does not pause the focused screen. Info mode itself is S26-S29, out
## of scope here, so there is no real "enter info mode" call to make -- this pins the invariant at
## the level that exists now: the pause rule keys off focus()/unfocus() alone (the wall's
## TRANSITION machinery, not yet built, is the only intended caller), never off zoom. A regression
## guard for the day info mode's zoom-only code path lands: it must not call unfocus().
func test_info_mode_does_not_pause_focused_screen() -> void:
	var target := _pictures[0]
	_focus_only(target)
	check(target.screen_root.process_mode == Node.PROCESS_MODE_ALWAYS,
			"the focused screen's root is still ALWAYS with nothing info-mode-shaped touching it")

# ------------------------------------------------------------------ U5, U6

## U5 (D6, Q75=b): Pacing.wait must NOT fire within a bounded escape window while the tree is
## paused. ⚠ Exactly the trap ASSUMPTIONS.md's pause-model-spike entry names: `await some_timer`
## (missing `.timeout`) resolves IMMEDIATELY and would make this pass while asserting nothing --
## `.timeout` is awaited explicitly below. ⚠ A SECOND, DIFFERENT trap of the same shape lives here
## too: a GDScript lambda captures an outer local BY VALUE, so `func(): fired = true` writes a
## throwaway copy and the outer `fired` never moves -- `not fired` then holds regardless of whether
## the timer actually fired, which is exactly as vacuous as the missing-`.timeout` slip. `fired` is
## a one-element typed Array below so the closure mutates the SAME boxed value the check reads.
func test_pacing_wait_does_not_tick_while_paused() -> void:
	var fired : Array[bool] = [false]
	Pacing.wait(0.1).timeout.connect(func() -> void: fired[0] = true)
	await get_tree().create_timer(0.5, true).timeout   # escape hatch -- bare timer, ticks regardless
	check(not fired[0], "Pacing.wait(0.1) did NOT fire within a 0.5s escape while paused")

## U6 (D6): the trap this whole design defends against, kept green ON PURPOSE -- a BARE
## create_timer ticks straight through the pause (process_always defaults true), exactly why every
## game-code call site was swept onto Pacing in S6. If this ever goes red, a future Godot changed
## process_always's default and Pacing can be retired (TEST_PLAN.md §4's own note on this row).
## Same boxed-Array closure fix as U5 above -- see its comment.
func test_bare_create_timer_ticks_while_paused() -> void:
	var fired : Array[bool] = [false]
	get_tree().create_timer(0.1).timeout.connect(func() -> void: fired[0] = true)
	await get_tree().create_timer(0.5, true).timeout
	check(fired[0], "a bare create_timer(0.1) DID fire within 0.5s while paused")

extends TestSuite
# res://Tests/Wall/test_wall_info.gd
# ==============================================================================
# WALL INFO (S26-S29): TEST_PLAN.md §8, rows J1-J7.
# PLAN.md §1.11; NAMES.md fixes InfoEntry/InfoCard's class/file/signal names.
#
# J1/J3 are "assert hidden" rows -- the most dangerous shape (HANDOFF traps section): a card that
# was never constructed is ALSO hidden, so every row here first asserts the card genuinely EXISTS
# (is_instance_valid) before asserting anything about its visibility. J2's "still shown" asserts
# the entry's OWN IDENTITY (`==` on the InfoEntry object, not merely `card.visible`) -- a card that
# silently swapped in some OTHER entry would still read "visible" and pass a weaker check. J6
# samples the transition and asserts the sample count is nonzero before asserting the samples all
# agree, same "the loop actually ran" discipline the rest of this run's suites already use.
# ==============================================================================

const INFO_CARD_SCENE := preload("res://UI/Wall/info_card.tscn")
const WALL_PICTURE_SCENE := preload("res://UI/Wall/wall_picture.tscn")

func suite_name() -> String:
	return "WALL INFO"

func _ready() -> void:
	TestLog.line("============ WALL INFO TEST PASS ============")
	behavior_section("CARD HIDDEN UNTIL FIRST HOVER (J1)")
	_test_card_hidden_before_first_hover()
	behavior_section("LAST ENTRY PERSISTS ACROSS EMPTY HOVER (J2)")
	_test_card_keeps_last_entry_across_empty_hover()
	behavior_section("LEAVING INFO MODE RESETS TO HIDDEN (J3)")
	_test_leaving_info_mode_resets_to_hidden()
	behavior_section("CARD SIZES TO CONTENT (J4)")
	_test_card_sizes_to_content()
	behavior_section("INFO ZOOM REVEALS THE BOTTOM FRAME ONLY (J5)")
	_test_info_zoom_reveals_bottom_frame_only()
	behavior_section("A TRANSITION IN INFO MODE DOES NOT ZOOM (J6)")
	_test_transition_in_info_mode_has_constant_zoom()
	behavior_section("TOGGLING INFO MODE MID-TRANSITION RETARGETS IMMEDIATELY (design J9)")
	_test_toggling_info_mode_mid_transition_retargets_immediately()
	behavior_section("THE FOCUSED SCREEN STAYS LIVE AT THE INFO ZOOM (design J11)")
	_test_focused_screen_stays_live_through_info_zoom_code_path()
	behavior_section("THE MAP'S HOVER STILL WORKS AFTER MIGRATION (J7)")
	_test_map_hover_still_produces_info_entry()
	finish()

# ------------------------------------------------------------------ fixtures

func _build_card() -> InfoCard:
	var card : InfoCard = INFO_CARD_SCENE.instantiate()
	add_child(card)
	return card

func _entry(title: String, body: String) -> InfoEntry:
	var e := InfoEntry.new()
	e.title = title
	e.body = body
	return e

# ------------------------------------------------------------------ J1

## J1: a freshly constructed card shows NOTHING before the first hover. Asserts the card actually
## EXISTS first -- a card that was never built is also, trivially, "hidden" (HANDOFF traps).
func _test_card_hidden_before_first_hover() -> void:
	var card := _build_card()
	check(is_instance_valid(card), "the info card was actually constructed, not merely absent")
	check(not card.visible, "a freshly constructed card is hidden before any hover")
	check(card.current_entry == null, "and remembers no entry yet")
	card.queue_free()

# ------------------------------------------------------------------ J2

## J2: hover a, then hover nothing (there is no method to call for "hovering nothing" at all --
## the caller simply stops calling show_entry()) -> a is STILL shown. Checked by the entry's own
## IDENTITY, not merely `card.visible` -- a card that silently swapped to some OTHER entry would
## still read "visible" and pass a weaker check (HANDOFF traps).
func _test_card_keeps_last_entry_across_empty_hover() -> void:
	var card := _build_card()
	var entry_a := _entry("A", "body a")
	card.show_entry(entry_a)
	check(card.visible, "showing an entry makes the card visible (sanity check)")
	# "Hover nothing" -- deliberately no call here. The card must not react to an absence.
	check(card.visible, "the card is STILL visible after hovering nothing (does not blink)")
	check(card.current_entry == entry_a,
			"the SAME entry object is still shown, by identity, not just something visible")
	card.queue_free()

# ------------------------------------------------------------------ J3

## J3: leaving info mode (reset()) hides the card and drops the remembered entry. Same
## exists-then-hidden discipline as J1.
func _test_leaving_info_mode_resets_to_hidden() -> void:
	var card := _build_card()
	card.show_entry(_entry("A", "body a"))
	check(card.visible, "showing an entry makes the card visible (sanity check before reset)")
	card.reset()
	check(is_instance_valid(card), "the card still exists after reset() -- reset() hides, it does not free")
	check(not card.visible, "reset() (leaving info mode) hides the card")
	check(card.current_entry == null, "reset() also drops the remembered entry")
	card.queue_free()

# ------------------------------------------------------------------ J4

## J4 (Q130): a short and a long entry produce DIFFERENTLY SIZED cards -- proof the card measures
## its own content rather than using one fixed size regardless of what is in it.
func _test_card_sizes_to_content() -> void:
	var card := _build_card()
	card.show_entry(_entry("Short", "One line."))
	var short_h := card.size.y
	var long_body := "This is a much longer description that will wrap across several lines of " \
			+ "text, enough that its measured height should differ noticeably from the short " \
			+ "entry's own height, proving the card actually measures its content rather than " \
			+ "using one fixed size for every entry regardless of what is actually in it."
	card.show_entry(_entry("Long", long_body))
	var long_h := card.size.y
	check(not is_equal_approx(short_h, long_h),
			"a short and a long entry produce DIFFERENT card heights",
			"short=%.1f long=%.1f" % [short_h, long_h])
	check(long_h > short_h, "the longer entry produces the TALLER card",
			"short=%.1f long=%.1f" % [short_h, long_h])
	card.queue_free()

# ------------------------------------------------------------------ J5

## J5 (Q128/J2-design override): the info zoom reveals the BOTTOM frame edge and ONLY the bottom
## -- the top edge must NOT be inside the visible rect. Both halves asserted; asserting only the
## bottom would prove nothing about "only" (the coordinator's own instruction).
func _test_info_zoom_reveals_bottom_frame_only() -> void:
	var rect := PictureRect.new(&"a", Vector2.ZERO, Vector2(400, 300), Vector4(20, 20, 20, 20))
	var settings := PlayerSettings.new()
	var window := Vector2(1280, 720)
	var state := WallPicture.info_zoom_state(rect, window, settings)
	var position : Vector2 = state["position"]
	var zoom : float = state["zoom"]
	check(zoom > 0.0, "the info zoom is a real, positive scale before asserting anything about it",
			"%.4f" % zoom)
	var visible := Rect2(position - window / (2.0 * zoom), window / zoom)
	var frame := WallPacker.frame_outer_rect(rect)
	var bottom_inside := frame.end.y >= visible.position.y and frame.end.y <= visible.end.y
	check(bottom_inside, "the BOTTOM frame edge is inside the visible rect",
			"frame_bottom=%.2f visible=%s" % [frame.end.y, visible])
	var top_not_inside := frame.position.y < visible.position.y
	check(top_not_inside, "the TOP frame edge is NOT inside the visible rect",
			"frame_top=%.2f visible=%s" % [frame.position.y, visible])

# ------------------------------------------------------------------ J6

## J6 (Q137/J10-design override): with Info mode on, a transition's camera ZOOM is constant across
## the whole transition ("a pure travel"). Scans a real range of elapsed values via `sample_at()`
## (pure, synchronous -- no real Tween, no real-time flakiness) and asserts the SAMPLE COUNT is
## nonzero before asserting anything about the samples themselves (HANDOFF traps: a scan whose
## body never ran would otherwise pass this check vacuously).
func _test_transition_in_info_mode_has_constant_zoom() -> void:
	var settings := PlayerSettings.new()
	settings.wall_info_mode = true
	settings.base_delay = 1.0
	settings.wall_transition_delay = 1.0
	# Deliberately DIFFERENT sizes -- if zoom were wrongly re-derived per-picture instead of held
	# constant from the source, a symmetric fixture would hide that bug entirely.
	var source := PictureRect.new(&"a", Vector2(-500, 0), Vector2(400, 300), Vector4(20, 20, 20, 20))
	var dest := PictureRect.new(&"b", Vector2(500, 0), Vector2(700, 500), Vector4(30, 30, 30, 30))
	var window := Vector2(1280, 720)
	var total := WallTransition.total_duration(settings)
	const SCAN_STEPS := 20
	var zooms : Array[float] = []
	for i : int in (SCAN_STEPS + 1):
		var elapsed := total * float(i) / float(SCAN_STEPS)
		var s := WallTransition.sample_at(elapsed, total, source, dest, window, settings)
		zooms.append(s.camera_zoom)
	check(zooms.size() == SCAN_STEPS + 1,
			"the scan actually sampled every step before asserting anything about the samples",
			"sampled=%d" % zooms.size())
	var first : float = zooms[0]
	var all_constant := true
	for z : float in zooms:
		if not is_equal_approx(z, first): all_constant = false
	check(all_constant,
			"camera zoom is CONSTANT across the whole transition in info mode (J10: pure travel)",
			"zooms=%s" % [zooms])
	# Position, meanwhile, DOES move -- otherwise this would be a picture that never travels,
	# not a "pure travel" transition (J10's other half).
	var start_pos := WallTransition.sample_at(0.0, total, source, dest, window, settings) \
			.camera_position
	var end_pos := WallTransition.sample_at(total, total, source, dest, window, settings) \
			.camera_position
	check(not start_pos.is_equal_approx(end_pos),
			"camera POSITION still travels even though zoom does not",
			"start=%s end=%s" % [start_pos, end_pos])

# ------------------------------------------------------------------ design J9 (S28, Q136=b)

## Design J9 (Q136=b): toggling Info mode mid-transition takes effect IMMEDIATELY, retargeting the
## camera -- not deferred to landing (that would be Q136=a, the option NOT chosen). No TEST_PLAN
## §8 row names this, but PLAN.md §2 still lists S28 as owing it (§1's own "you may ADD tests"
## case) -- a missing row does not delete the behaviour.
##
## `WallTransition.sample_at()` is a PURE function that reads `settings.wall_info_mode` fresh on
## every call -- never cached, never latched at `request()` time -- so "immediate" falls out of
## the architecture already: sampling the SAME elapsed instant before and after flipping the SAME
## live `PlayerSettings` object must disagree, with no tween restart and no waiting for landing.
func _test_toggling_info_mode_mid_transition_retargets_immediately() -> void:
	var settings := PlayerSettings.new()
	settings.wall_info_mode = false
	settings.base_delay = 1.0
	settings.wall_transition_delay = 1.0
	var source := PictureRect.new(&"a", Vector2(-500, 0), Vector2(400, 300), Vector4(20, 20, 20, 20))
	var dest := PictureRect.new(&"b", Vector2(500, 0), Vector2(400, 300), Vector4(20, 20, 20, 20))
	var window := Vector2(1280, 720)
	var total := WallTransition.total_duration(settings)
	var mid_elapsed := total * 0.5

	var before := WallTransition.sample_at(mid_elapsed, total, source, dest, window, settings)
	# Toggle mid-flight, on the SAME settings object a live transition would already be holding a
	# reference to (`WallTransition._settings`) -- no new request(), no restart.
	settings.wall_info_mode = true
	var after := WallTransition.sample_at(mid_elapsed, total, source, dest, window, settings)

	check(not is_equal_approx(before.camera_zoom, after.camera_zoom),
			"the SAME elapsed instant produces a DIFFERENT camera zoom the instant the live "
			+ "setting flips -- retargeted immediately, not deferred to landing",
			"before=%.4f after=%.4f" % [before.camera_zoom, after.camera_zoom])
	var expected_info := WallPicture.info_zoom_state(source, window, settings)
	check(is_equal_approx(after.camera_zoom, expected_info["zoom"] as float),
			"the post-toggle sample matches the info-zoom formula exactly, not some intermediate "
			+ "or stale value", "after=%.4f expected=%.4f" % [after.camera_zoom, expected_info["zoom"]])

# ------------------------------------------------------------------ design J11 (S28, Q138=a)

## Design J11 (Q138=a): the focused screen stays LIVE at the info zoom -- "the pause rule keys off
## the transition, not the zoom." U7 (test_wall_pause.gd) already pins this at the level that
## existed before S28: focus()/unfocus() alone govern `process_mode`, and nothing about ZOOM ever
## touches it. U7's OWN doc comment names exactly this test as its future regression guard ("the
## day info mode's zoom-only code path lands"). This does not re-assert U7's own check (a real
## `Wall`/pause-tree fixture, out of this suite's scope) -- it proves the SPECIFIC NEW S28 code
## path (`WallPicture.info_zoom_state()`, and `WallTransition.sample_at()`'s info-mode branch)
## never calls `focus()`/`unfocus()` at all: both are called here against an already-focused
## picture, and `process_mode` must read back UNCHANGED, because neither function touches a node.
func _test_focused_screen_stays_live_through_info_zoom_code_path() -> void:
	var wp := WALL_PICTURE_SCENE.instantiate() as WallPicture
	add_child(wp)
	var rect := PictureRect.new(&"a", Vector2.ZERO, Vector2(400, 300), Vector4(20, 20, 20, 20))
	var entry := PictureEntry.new()
	entry.id = &"a"
	entry.design_size = Vector2i(400, 300)
	# A real, throwaway screen_root -- build() only sets `screen_root` when `entry.scene` is
	# non-null (Q214=a, "registered but unbuilt" is the null case), and this test reads
	# `wp.screen_root.process_mode` directly, so it needs the non-null case (T13's own
	# PackedScene.new()+pack(Node.new()) idiom, ASSUMPTIONS.md).
	var template := Node.new()
	var packed := PackedScene.new()
	packed.pack(template)
	template.free()
	entry.scene = packed
	var viewports := Node.new()
	add_child(viewports)
	wp.build(rect, entry, viewports)
	wp.focus()
	check(wp.screen_root.process_mode == Node.PROCESS_MODE_ALWAYS,
			"sanity check: focus() itself leaves the screen ALWAYS before any info-zoom code runs")

	var settings := PlayerSettings.new()
	settings.wall_info_mode = true
	var window := Vector2(1280, 720)
	WallPicture.info_zoom_state(rect, window, settings)   # the S28 code path under test
	check(wp.screen_root.process_mode == Node.PROCESS_MODE_ALWAYS,
			"info_zoom_state() alone does not touch the focused screen's process_mode")

	var dest_rect := PictureRect.new(&"b", Vector2(500, 0), Vector2(400, 300), Vector4(20, 20, 20, 20))
	var total := WallTransition.total_duration(settings)
	WallTransition.sample_at(total * 0.5, total, rect, dest_rect, window, settings)
	check(wp.screen_root.process_mode == Node.PROCESS_MODE_ALWAYS,
			"sample_at()'s info-mode branch does not touch the focused screen's process_mode "
			+ "either -- agrees with U7 rather than duplicating its fixture")

	wp.teardown()
	viewports.queue_free()

# ------------------------------------------------------------------ J7

## J7 (Q132=a, Q133=b, Q130, S29) -- TEST_PLAN's own wording is "assert an InfoEntry WITH THE
## NODE'S PREVIEW": title/body alone is not this row. The preview strip (booster possible-contents
## cards) is exactly what S29's migration risks silently dropping, so this asserts `entry.visual`
## is a REAL, POPULATED container -- not merely non-null, which a container that stayed empty
## would also satisfy. Forces the fixture node to `ROLE_BOOSTER` directly (hand-authored meta,
## same fixture-construction spirit as `Tests/Map/test_map_roles.gd`'s own hand-built exports)
## rather than relying on a seed happening to land a booster inside a 4-node graph.
func _test_map_hover_still_produces_info_entry() -> void:
	var run := RunState.new()
	run.world_seed = 12345
	run.lap = 0
	var real_run : RunState = RunManager.run
	RunManager.run = run

	var overlay := WorldGraphOverlay.new()
	add_child(overlay)
	var export := _line_export(3)
	overlay.populate(export, Vector2(200, 200))

	var node : WorldGraphNode = overlay.node(1)
	node.meta[MapNodeRoles.ROLE_KEY] = MapNodeRoles.ROLE_BOOSTER
	node.meta[MapNodeRoles.BOOSTER_KEY] = TypeBoosterBasic.new()

	# get_info() is STATIC (ASSUMPTIONS.md) -- no MapHoverPanel instance needed to reach it.
	var entry := MapHoverPanel.get_info(node, run, overlay.end_node())

	check(entry != null, "get_info() returned a real InfoEntry, not null")
	check(not entry.title.is_empty(), "the entry carries the node's own title", entry.title)
	check(not entry.body.is_empty(), "the entry carries the node's own description body", entry.body)
	check(entry.visual != null,
			"a BOOSTER node's entry carries a visual -- the preview this row exists to check for",
			str(entry.visual))
	if entry.visual:
		check(entry.visual.get_child_count() > 0,
				"the visual is not just an empty placeholder -- it holds the actual preview cards",
				"children=%d" % entry.visual.get_child_count())

	# `entry.visual` (a FlowContainer with ControlCard children) is a real Node, never parented
	# anywhere -- get_info() hands it over as a fresh, ownerless "copy" (§1.11), so THIS caller
	# owns freeing it explicitly or it leaks (the `Game.new()`/`Node.new()` trap, generalised).
	if entry.visual: entry.visual.queue_free()
	overlay.queue_free()
	RunManager.run = real_run

## A straight-line graph, one node per depth -- same minimal recipe test_map_roles.gd's own
## `_line_export()` uses, duplicated rather than shared (that helper is private to its own suite,
## and this is the only row here that needs a real graph at all).
func _line_export(max_depth: int) -> Dictionary:
	var nodes : Array = []
	for i : int in max_depth + 1:
		var outs : Array = []
		if i < max_depth:
			outs.append({"to": i + 1, "ferry": false,
					"points": PackedVector2Array([Vector2(i * 10, 0), Vector2(i * 10 + 10, 0)])})
		nodes.append({"id": i, "pos": Vector2(i * 10, 0), "depth": i,
				"landmass": 0, "height": 0.5, "biome": -1, "out": outs})
	return {"start": 0, "end": max_depth, "max_depth": max_depth, "biomes": [], "nodes": nodes}

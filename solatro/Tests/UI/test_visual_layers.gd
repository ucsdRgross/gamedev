extends TestSuite
# res://Tests/UI/test_visual_layers.gd
# ==============================================================================
# VISUAL LAYERS (LAYERING.md): the board's STRUCTURAL draw order. After the
# z_index -> tree-structure migration, every board CanvasItem stays at z_index 0
# and order is decided purely by sibling position + parent nesting:
#   TopLevelVBox children: … CardLayer -> PropLayer -> OverlayLayer  (later = on top)
#   CardLayer children: CardVisuals in row-major order (+ hoop back-halves interleaved)
#   inside a card: face polygons then StatusLayer (last = on top)
#
# A reusable dumper (dump_draw_order) prints the live draw-order tree at snapshot
# moments so a human can eyeball layout; the invariant checks assert the parts
# that must never drift, reading the EFFECTIVE draw order (not raw z) so they
# survive the z->structure change. The core new feature — a card passing THROUGH
# a hoop (back arc behind the card, front arc in front, back arc still above the
# row above) — is driven directly and checked here.
#
# CATEGORY MAP: BEHAVIOR — what the player sees layered correctly (prop over card,
# hoop split, overlay on top, held card lifted, status on the face). IMPLEMENTATION
# pins: all board CanvasItems at z_index 0, CardLayer/PropLayer/OverlayLayer sibling
# order, the hoop halves parented into CardLayer bracketing their anchor row
# (back before the row's first card, front after its last — see LAYERING.md).
#
# Ordering: shares CardEnvironment.CURRENT with UI PROPS, so it waits for every
# sibling EXCEPT E2E (UI PROPS excludes THIS suite to break the cycle) — chain is
# …engine -> UI PROPS -> VISUAL LAYERS -> E2E. Isolates real saves/settings like
# UI PROPS when it drives a GameView.
# ==============================================================================

const PLAY_AREA_SCENE := preload("res://UI/play_area.tscn")
const GAME_VIEW_SCENE := preload("res://Levels/game_view.tscn")

const WATCHDOG_SECS := 10.0

const REAL_SETTINGS_PATH := "user://settings.tres"
const REAL_SETTINGS_BAK := "user://settings.tres.testbak2"

func suite_name() -> String:
	return "VISUAL LAYERS"

func _ready() -> void:
	# Runs after UI PROPS (shares CardEnvironment.CURRENT) and before E2E. Excludes only E2E (which
	# waits on everything). See TestSuite.await_siblings_except and its DEADLOCK RULE.
	await await_siblings_except(["E2E RUN", "LEAK CANARY"])
	TestLog.line("============ VISUAL LAYERS TEST PASS ============")
	_backup_settings()
	var prev_delay := SettingsManager.settings.base_delay
	SettingsManager.settings.base_delay = TestLog.speed_base_delay
	implementation_section("STRUCTURAL ORDER (no z_index anywhere)")
	await test_fresh_deal_structure()
	behavior_section("PROP / CARD / OVERLAY LAYERING")
	await test_normal_prop_above_cards()
	await test_held_card_above_resting()
	await test_status_above_face()
	await test_overlay_above_everything()
	behavior_section("HOOP PASSES THROUGH A CARD (front/back split)")
	await test_hoop_back_half_interleaves()
	await test_hoop_split_multi_column()
	await test_hoop_short_column_row_hold()
	behavior_section("FULL VIEW SNAPSHOTS (real GameView)")
	await test_game_view_deal_snapshot()
	await test_end_screen_above_board()
	SettingsManager.settings.base_delay = prev_delay
	_restore_settings()
	finish()

# ==============================================================================
# SETTINGS ISOLATION (SettingsManager writes settings.tres on every change)
# ==============================================================================
func _backup_settings() -> void:
	if FileAccess.file_exists(REAL_SETTINGS_PATH):
		DirAccess.rename_absolute(ProjectSettings.globalize_path(REAL_SETTINGS_PATH),
				ProjectSettings.globalize_path(REAL_SETTINGS_BAK))

func _restore_settings() -> void:
	if not FileAccess.file_exists(REAL_SETTINGS_BAK):
		return
	if FileAccess.file_exists(REAL_SETTINGS_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(REAL_SETTINGS_PATH))
	DirAccess.rename_absolute(ProjectSettings.globalize_path(REAL_SETTINGS_BAK),
			ProjectSettings.globalize_path(REAL_SETTINGS_PATH))

# ==============================================================================
# THE REUSABLE DRAW-ORDER DUMPER
# Mirrors Godot's canvas ordering: for every CanvasItem under a root compute its
# EFFECTIVE z (walk parents: add z_index when z_as_relative, else absolute), then
# depth-first pre-order (parent before children, earlier siblings first) gives the
# tie-break at equal z. Stable-sort by (effective_z, traversal index): the LAST
# entry renders ON TOP. Returns Array[Dictionary]{node, z, order, depth, visible}.
# ==============================================================================
func collect_draw_order(root: Node) -> Array[Dictionary]:
	var out : Array[Dictionary] = []
	var counter : Array[int] = [0]
	_walk_draw(root, 0, 0, out, counter, root)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["z"] != b["z"]: return a["z"] < b["z"]
		return a["order"] < b["order"])
	return out

## Depth-first draw-order walk that STOPS at nested-scene boundaries: any descendant instanced from
## its own .tscn (scene_file_path set) is emitted as ONE leaf and not recursed into — so a
## CardVisual/TextPopup/PlayArea shows once, not as its hundreds of polygons/bones (output overflow).
## The root itself is always expanded (that's the scene under inspection).
func _walk_draw(node: Node, parent_z: int, depth: int, out: Array[Dictionary],
		counter: Array[int], root: Node) -> void:
	var z := parent_z
	if node is CanvasItem:
		var ci := node as CanvasItem
		z = (parent_z + ci.z_index) if ci.z_as_relative else ci.z_index
		out.append({"node": node, "z": z, "order": counter[0], "depth": depth,
				"visible": ci.is_visible_in_tree()})
		counter[0] += 1
	# Halt at a dedicated sub-scene (unless it's the root we were asked to expand).
	if node != root and not node.scene_file_path.is_empty():
		return
	for child in node.get_children():
		_walk_draw(child, z, depth + 1, out, counter, root)

## Route the ordered list to TestLog as ONE line (top = drawn first = underneath; bottom = on top).
## A single combined string avoids flooding the terminal with hundreds of separate print() calls
## (output-overflow); it still lands in test_output_all.log and shows in terminal only in ALL mode.
func dump_draw_order(label: String, root: Node) -> Array[Dictionary]:
	var order := collect_draw_order(root)
	var lines : PackedStringArray = []
	lines.append("\n---- DRAW ORDER: %s (bottom of list renders ON TOP) ----" % label)
	for entry : Dictionary in order:
		var node : Node = entry["node"]
		var indent := "  ".repeat(entry["depth"] as int)
		lines.append("  [z=%d] %s%s (%s)%s" % [entry["z"], indent, node.name,
				node.get_class(), "" if entry["visible"] else " [hidden]"])
	TestLog.line("\n".join(lines))
	return order

## Draw rank of `node` in the sorted order (higher = renders more on top); -1 if absent.
func draw_rank(order: Array[Dictionary], node: Node) -> int:
	for i in order.size():
		if order[i]["node"] == node: return i
	return -1

## True iff every CanvasItem in the order sits at effective z 0 (the structural invariant).
func all_zero_z(order: Array[Dictionary]) -> Array[Node]:
	var offenders : Array[Node] = []
	for entry : Dictionary in order:
		if (entry["z"] as int) != 0: offenders.append(entry["node"])
	return offenders

# ==============================================================================
# FIXTURES (mirrors test_ui_props.make_board_game / make_play_area / settle)
# ==============================================================================
func make_board_game(cols: int) -> Game:
	var g := Game.new()
	var s := GameData.new()
	var types : Array[CardData] = []
	var columns : Array[ArrayCardData] = []
	for col in cols:
		var h := TestFactories.m_card(1, TestFactories.uc()); h.stage = CardData.Stage.ZONE
		types.append(h)
		var card := TestFactories.m_card(col + 2, TestFactories.uc())
		card.stage = CardData.Stage.PLAY
		columns.append(TestFactories.col([card] as Array[CardData]))
	s.upper_zone_type = types
	s.upper_zone = columns
	g.state = s
	g._begin_act()
	CardEnvironment.CURRENT = g
	return g

## One upper column stacked `rows` deep (row 0 on top of the column visually — later rows draw
## over earlier ones), so there is a genuine "card in the row above" for the hoop-split test.
func make_stack_game(rows: int) -> Game:
	var g := Game.new()
	var s := GameData.new()
	var h := TestFactories.m_card(1, TestFactories.uc()); h.stage = CardData.Stage.ZONE
	var cards : Array[CardData] = []
	for r in rows:
		var card := TestFactories.m_card(r + 2, TestFactories.uc())
		card.stage = CardData.Stage.PLAY
		cards.append(card)
	s.upper_zone_type = [h] as Array[CardData]
	s.upper_zone = [TestFactories.col(cards)] as Array[ArrayCardData]
	g.state = s
	g._begin_act()
	CardEnvironment.CURRENT = g
	return g

## `cols` columns each stacked `rows` deep — the multi-column grid the single-column hoop test was
## blind to (TASK 4, owner playtest 2026-07-15): cross-column draw order, ring overlap against
## EVERY card, and mid-leg split state are checked on this shape.
func make_grid_game(cols: int, rows: int) -> Game:
	var per_col : Array[int] = []
	for col : int in cols:
		per_col.append(rows)
	return make_ragged_game(per_col)

## Ragged board: one column per entry, stacked `rows_per_col[i]` deep — SHORT columns are the
## shape whose fanned last card pokes down through later rows (the wrong-row bracket bug).
func make_ragged_game(rows_per_col: Array[int]) -> Game:
	var g := Game.new()
	var s := GameData.new()
	var types : Array[CardData] = []
	var columns : Array[ArrayCardData] = []
	for rows : int in rows_per_col:
		var h := TestFactories.m_card(1, TestFactories.uc()); h.stage = CardData.Stage.ZONE
		types.append(h)
		var cards : Array[CardData] = []
		for r : int in rows:
			var card := TestFactories.m_card(r + 2, TestFactories.uc())
			card.stage = CardData.Stage.PLAY
			cards.append(card)
		columns.append(TestFactories.col(cards))
	s.upper_zone_type = types
	s.upper_zone = columns
	g.state = s
	g._begin_act()
	CardEnvironment.CURRENT = g
	return g

func make_play_area() -> PlayArea:
	var pa : PlayArea = PLAY_AREA_SCENE.instantiate()
	add_child(pa)
	pa.size = Vector2(1152, 648)
	# Formations add a view-only lane_offset per prop; disable them so these layering tests place
	# props on exact slot geometry (mark every kind formation-checked with none present).
	for kind : int in range(PropFormationSet.KIND_NAMES.size()):
		pa.prop_layer._formation_checked[kind] = true
	return pa

func settle(pa: PlayArea) -> void:
	var waited := 0.0
	while not pa.visuals_ready() and waited < WATCHDOG_SECS:
		await get_tree().process_frame
		waited += get_process_delta_time()
	var last := pa.slot_center_global(Vector3i(0, 0, 0))
	var stable := 0
	while stable < 3 and waited < WATCHDOG_SECS:
		await get_tree().process_frame
		waited += get_process_delta_time()
		var now := pa.slot_center_global(Vector3i(0, 0, 0))
		stable = stable + 1 if now.is_equal_approx(last) else 0
		last = now

func cleanup(g: Game, pa: PlayArea) -> void:
	pa.queue_free()
	CardEnvironment.CURRENT = null
	await get_tree().process_frame  # let the PlayArea actually free before the Game does
	g.free()

func run_tick(pl: PropLayer, live: Array, spawned: Array, movers: Array,
		relocated: Array) -> bool:
	var sig := pl.begin_prop_tick(live, spawned, movers, relocated)
	var fired : Array[bool] = [false]
	var handler := func() -> void: fired[0] = true
	sig.connect(handler)
	var waited := 0.0
	while not fired[0] and waited < WATCHDOG_SECS:
		await get_tree().process_frame
		waited += get_process_delta_time()
	sig.disconnect(handler)
	return fired[0]

# ==============================================================================
# TESTS
# ==============================================================================

## Fresh board: every board CanvasItem at z 0, CardLayer/PropLayer/OverlayLayer sibling order,
## CardVisuals row-major in CardLayer.
func test_fresh_deal_structure() -> void:
	var g := make_board_game(3)
	var pa := make_play_area()
	await settle(pa)
	var order := dump_draw_order("fresh deal (bare PlayArea)", pa)

	var offenders := all_zero_z(order)
	check(offenders.is_empty(),
			"every board CanvasItem stays at effective z_index 0 (pure structural order)",
			"nonzero: %s" % str(offenders.map(func(n: Node) -> String: return String(n.name))))

	var top := pa.get_node("SmoothScrollContainer/TopLevelVBox")
	var card_layer := top.get_node("CardLayer")
	var prop_layer := top.get_node("PropLayer")
	var overlay := top.get_node("OverlayLayer")
	check_impl(card_layer.get_index() < prop_layer.get_index()
			and prop_layer.get_index() < overlay.get_index(),
			"TopLevelVBox order is CardLayer -> PropLayer -> OverlayLayer (later = on top)",
			"idx %d/%d/%d" % [card_layer.get_index(), prop_layer.get_index(), overlay.get_index()])

	# CardVisuals hold row-major order in CardLayer (later child = drawn on top), none with a z.
	var last_idx := -1
	var monotone := true
	var any_z := false
	for i in 3:
		var data := g.state.upper_zone[i].datas[0]
		var vis : CardVisual = pa.data_card.get(data)
		if not vis: continue
		if vis.z_index != 0: any_z = true
		if vis.get_index() <= last_idx: monotone = false
		last_idx = vis.get_index()
	check_impl(not any_z, "no CardVisual sets a z_index (order is its CardLayer child index)")
	check(monotone, "CardVisuals are in ascending row-major child order in CardLayer")
	await cleanup(g, pa)

## A normal prop (knife — no back half) renders above every board card by tree order.
func test_normal_prop_above_cards() -> void:
	var g := make_board_game(3)
	var pa := make_play_area()
	await settle(pa)
	var pl := pa.prop_layer
	var p := PropData.new()
	p.kind = 1   # knife — has_back_half() == false
	p.at = Vector3i(0, 1, 0)
	p.route = [Vector3i(0, 2, 0)] as Array[Vector3i]
	var ok := await run_tick(pl, [p], [p], [p], [])
	check(ok, "knife spawn/move tick completes")
	var vis : PropVisual = pl._visuals.get(p)
	var order := dump_draw_order("normal knife over the board", pa)
	var prop_rank := draw_rank(order, vis)
	var above_all := prop_rank >= 0
	for i in 3:
		var cv : CardVisual = pa.data_card.get(g.state.upper_zone[i].datas[0])
		if cv and draw_rank(order, cv) > prop_rank: above_all = false
	check(above_all, "a back-half-less prop renders above every board card")
	check(not vis.has_back_half(), "the knife opts out of the back-half split (default)")
	await cleanup(g, pa)

## Picking up a card lifts it above every resting card in its zone (structural move_child(-1)).
func test_held_card_above_resting() -> void:
	var g := make_board_game(3)
	var pa := make_play_area()
	await settle(pa)
	var held := g.state.upper_zone[1].datas[0]
	pa.grab_cards([held] as Array[CardData])
	await get_tree().process_frame
	var order := dump_draw_order("held card lifted", pa)
	var held_vis : CardVisual = pa.data_card.get(held)
	var held_rank := draw_rank(order, held_vis)
	var above := held_rank >= 0
	for i in 3:
		if i == 1: continue
		var cv : CardVisual = pa.data_card.get(g.state.upper_zone[i].datas[0])
		if cv and draw_rank(order, cv) > held_rank: above = false
	check(above, "a held/dragged card renders above all resting cards")
	check_impl(held_vis.z_index == 0, "the held card carries no z_index (move_child, not z)")
	pa.ungrab_cards()
	await cleanup(g, pa)

## A card's StatusLayer draws above its own face polygons (last child of `visual`).
func test_status_above_face() -> void:
	var g := make_board_game(2)
	var pa := make_play_area()
	await settle(pa)
	var card := g.state.upper_zone[0].datas[0]
	card.add_status(CardModifierStatus.stacked(StatusJuggling, 2))
	var vis : CardVisual = pa.data_card.get(card)
	await get_tree().process_frame
	check(vis != null and vis.status_layer != null and vis.status_layer.visible,
			"the card shows its status layer")
	var order := dump_draw_order("card with a status", vis)
	var status_rank := draw_rank(order, vis.status_layer)
	var art_rank := draw_rank(order, vis.art)
	check(status_rank > art_rank,
			"StatusLayer renders above the card's Art (and every face polygon)",
			"status %d vs art %d" % [status_rank, art_rank])
	check_impl(vis.status_layer.z_index == 0, "StatusLayer carries no z_index (last-child order)")
	await cleanup(g, pa)

## The OverlayLayer (focus inspector) renders above every card and prop.
func test_overlay_above_everything() -> void:
	var g := make_board_game(3)
	var pa := make_play_area()
	await settle(pa)
	var pl := pa.prop_layer
	var p := PropData.new()
	p.kind = 1
	p.at = Vector3i(0, 1, 0)
	p.route = [Vector3i(0, 2, 0)] as Array[Vector3i]
	await run_tick(pl, [p], [p], [p], [])
	var control : Control = pa.data_ui.get(g.state.upper_zone[0].datas[0])
	control.grab_focus()
	await get_tree().process_frame
	check(pa._focus_info != null and pa._focus_info.visible, "the focus inspector is shown")
	var order := dump_draw_order("overlay (focus panel) over board + prop", pa)
	var panel_rank := draw_rank(order, pa._focus_info)
	var ok := panel_rank >= 0
	var prop_vis : PropVisual = pl._visuals.get(p)
	if prop_vis and draw_rank(order, prop_vis) > panel_rank: ok = false
	for i in 3:
		var cv : CardVisual = pa.data_card.get(g.state.upper_zone[i].datas[0])
		if cv and draw_rank(order, cv) > panel_rank: ok = false
	check(ok, "the focus inspector renders above every prop and card (OverlayLayer last sibling)")
	check_impl(pa._focus_info.get_parent() == pa.overlay_layer,
			"the focus panel lives on OverlayLayer")
	pa.hide_focus_info()
	await cleanup(g, pa)

## THE CORE FEATURE: a hoop's back half renders BELOW the card it occupies and ABOVE the card in
## the row above; its FRONT half renders in front of the occupied card but BELOW the card in the row
## BELOW — the ring brackets the occupied card so it passes through. Driven on a 3-deep stacked
## column: row 0 above, row 1 occupied, row 2 below.
func test_hoop_back_half_interleaves() -> void:
	var g := make_stack_game(3)
	var pa := make_play_area()
	await settle(pa)
	var pl := pa.prop_layer
	var above_card := g.state.upper_zone[0].datas[0]   # row 0 — the card in the row above
	var occupied := g.state.upper_zone[0].datas[1]     # row 1 — the card the hoop sits on
	var below_card := g.state.upper_zone[0].datas[2]   # row 2 — the card in the row below
	var p := PropData.new()
	p.kind = 0   # hoop — has_back_half() == true
	p.at = Vector3i(0, 0, 1)
	p.route = [] as Array[Vector3i]
	var ok := await run_tick(pl, [p], [p], [], [])
	check(ok, "hoop spawn tick completes")
	var vis : PropVisual = pl._visuals.get(p)
	check(vis != null and vis.has_back_half(), "the hoop opts into the front/back split")
	# Park the hoop directly over the occupied (row-1) card and let the per-frame interleave run.
	if vis:
		vis.global_position = pa.slot_center_global(Vector3i(0, 0, 1))
	for _i in 6:
		await get_tree().process_frame
	var back : Node2D = vis.back_node if vis else null
	var front : Node2D = vis.front_node if vis else null
	check(back != null and is_instance_valid(back) and front != null and is_instance_valid(front),
			"the hoop built both half nodes")
	check_impl(back != null and back.get_parent() == pa.card_layer
			and front != null and front.get_parent() == pa.card_layer,
			"both halves are parented into the STABLE CardLayer (not the card)")

	var order := dump_draw_order("hoop occupying the row-1 card", pa)
	var occ_vis : CardVisual = pa.data_card.get(occupied)
	var above_vis : CardVisual = pa.data_card.get(above_card)
	var below_vis : CardVisual = pa.data_card.get(below_card)
	var back_rank := draw_rank(order, back)
	var occ_rank := draw_rank(order, occ_vis)
	var above_rank := draw_rank(order, above_vis)
	var below_rank := draw_rank(order, below_vis)
	var front_rank := draw_rank(order, front)
	check(back_rank >= 0 and occ_rank >= 0 and above_rank >= 0 and below_rank >= 0 and front_rank >= 0,
			"both halves and all three cards are in the draw order",
			"back %d occ %d above %d below %d front %d"
			% [back_rank, occ_rank, above_rank, below_rank, front_rank])
	check(back_rank < occ_rank,
			"the hoop BACK half renders BEHIND the occupied card (card passes through the ring)",
			"back %d vs occupied %d" % [back_rank, occ_rank])
	check(back_rank > above_rank,
			"the back half still renders ABOVE the card in the row above",
			"back %d vs row-above %d" % [back_rank, above_rank])
	check(front_rank > occ_rank,
			"the hoop FRONT half renders in front of the occupied card",
			"front %d vs occupied %d" % [front_rank, occ_rank])
	check(front_rank < below_rank,
			"the FRONT half renders BELOW the card in the row below (not over the whole board)",
			"front %d vs row-below %d" % [front_rank, below_rank])

	# OFF-CARD (the playtest regression): move the RING over an empty region. The bracket is
	# purely GEOMETRIC now (data occupancy bracketed cards the ring visibly wasn't over), so
	# drive the visual itself: no card under the ring → halves hide and the PropVisual draws the
	# whole ring — otherwise stale half ordering left the ring floating on top of the board.
	vis.global_position = pa.slot_center_global(Vector3i(0, 0, 9))   # far past the built rows
	for _j in 4:
		await get_tree().process_frame
	check(not vis._split_active, "off a card, the hoop is NOT split (whole ring drawn by PropVisual)")
	check(not back.visible and not front.visible,
			"off a card, both half nodes are hidden (no stale ring floating over the board)",
			"back.visible %s front.visible %s" % [back.visible, front.visible])
	# Back over the occupied card → splits again (state is reversible per frame).
	vis.global_position = pa.slot_center_global(Vector3i(0, 0, 1))
	for _j in 4:
		await get_tree().process_frame
	check(vis._split_active and back.visible and front.visible,
			"back over a card, the hoop splits again (both halves shown)")
	# Despawn frees BOTH half nodes with the visual (no leak).
	p.done = true
	p.route = [] as Array[Vector3i]
	await run_tick(pl, [p], [], [], [])
	var waited := 0.0
	while is_instance_valid(vis) and not vis.is_queued_for_deletion() and waited < WATCHDOG_SECS:
		await get_tree().process_frame
		waited += get_process_delta_time()
	await get_tree().process_frame
	check((back == null or not is_instance_valid(back) or back.is_queued_for_deletion())
			and (front == null or not is_instance_valid(front) or front.is_queued_for_deletion()),
			"both half nodes are freed with the prop visual (no leak)")
	await cleanup(g, pa)

## TASK 4 (owner playtest 2026-07-15): the single-column hoop test passed while playtest layering
## looked wrong — the blind spots were OTHER columns, MID-LEG occupancy, and separation levels.
## On a 3x3 grid, at several card separations, a parked hoop must: take NO formation offset and
## sit exactly on the occupied card's visual center (TASK 3a — the ring threads the card center at
## every separation); bracket the occupied card, staying above EVERY same-column card above and
## below EVERY same-column card below (fanned stacks overlap more than one row at small
## separations); geometrically overlap NO card in any other column (what makes bracketing one card
## sufficient — catches art outgrowing the card footprint); and NOT split while its visual is
## between two cards even though its DATA slot is occupied (the mid-leg wrong-card bracket).
func test_hoop_split_multi_column() -> void:
	var prev_sep := SettingsManager.settings.card_separation_scale
	for sep_scale : float in [0.5, 1.0, 2.0] as Array[float]:
		SettingsManager.settings.card_separation_scale = sep_scale
		var g := make_grid_game(3, 3)
		var pa := make_play_area()
		await settle(pa)
		var pl := pa.prop_layer
		# Inject a big-offset formation for the hoop kind: TASK 3a says hoops NEVER take one.
		var fdata := PropFormationData.new()
		fdata.points = PackedVector2Array([Vector2(30.0, 40.0)])
		var fset := PropFormationSet.new()
		fset.formations = [fdata] as Array[PropFormationData]
		pl._formation_sets[0] = fset
		pl._formation_checked[0] = true
		var occupied := g.state.upper_zone[1].datas[1]   # middle column, middle row
		var p := PropData.new()
		p.kind = 0
		p.at = Vector3i(0, 1, 1)
		p.route = [] as Array[Vector3i]
		var ok := await run_tick(pl, [p], [p], [], [])
		check(ok, "hoop spawn tick completes (separation %.1f)" % sep_scale)
		var vis : PropVisual = pl._visuals.get(p)
		check(vis != null and vis.lane_offset == Vector2.ZERO,
				"a hoop takes NO formation offset even with an authored set (separation %.1f)" % sep_scale,
				str(vis.lane_offset) if vis else "no visual")
		for _i in 6:
			await get_tree().process_frame
		var occ_vis : CardVisual = pa.data_card.get(occupied)
		check(vis != null and occ_vis != null
				and (vis.global_position - occ_vis.global_position).length() < 4.0,
				"the parked hoop threads the occupied card's visual CENTER (separation %.1f)" % sep_scale,
				"%s vs %s" % [vis.global_position if vis else Vector2.INF,
				occ_vis.global_position if occ_vis else Vector2.INF])
		check(vis != null and vis._split_active
				and vis.back_node != null and vis.front_node != null,
				"the parked hoop splits over its card (separation %.1f)" % sep_scale)
		if vis == null or occ_vis == null:
			await cleanup(g, pa)
			continue
		var order := dump_draw_order("hoop over grid center, separation %.1f" % sep_scale, pa)
		var back_rank := draw_rank(order, vis.back_node)
		var front_rank := draw_rank(order, vis.front_node)
		var occ_rank := draw_rank(order, occ_vis)
		check(back_rank >= 0 and front_rank >= 0 and occ_rank >= 0
				and back_rank < occ_rank and occ_rank < front_rank,
				"the halves bracket the occupied card (separation %.1f)" % sep_scale,
				"back %d occ %d front %d" % [back_rank, occ_rank, front_rank])
		# ROW-WIDE consistency (owner spec 2026-07-16): the back half renders behind EVERY card of
		# the hoop's row and the front half in front of EVERY card of the row — not just the
		# threaded one — so the ring can never show an arc sandwiched wrongly near a column gap.
		for col : int in 3:
			var row_vis : CardVisual = pa.data_card.get(g.state.upper_zone[col].datas[1])
			var row_rank := draw_rank(order, row_vis)
			check(back_rank < row_rank and front_rank > row_rank,
					"the halves bracket the WHOLE row — column %d (separation %.1f)"
					% [col, sep_scale],
					"back %d card %d front %d" % [back_rank, row_rank, front_rank])
		# Same column: back above EVERY row above, front below EVERY row below (fanned stacks
		# overlap several rows at small separations, so adjacent-row checks are not enough).
		for row : int in 3:
			if row == 1: continue
			var cvis : CardVisual = pa.data_card.get(g.state.upper_zone[1].datas[row])
			var r := draw_rank(order, cvis)
			if row < 1:
				check(back_rank > r,
						"back half renders above the same-column card in row %d (separation %.1f)"
						% [row, sep_scale], "back %d vs card %d" % [back_rank, r])
			else:
				check(front_rank < r,
						"front half renders below the same-column card in row %d (separation %.1f)"
						% [row, sep_scale], "front %d vs card %d" % [front_rank, r])
		# Other columns: the ring must geometrically overlap NONE of their cards — bracketing the
		# ONE occupied card is only sufficient while this holds (the cross-column ambiguity,
		# hypothesis 1). Ring rect = art_size around the visual's center.
		var ring_half := vis.art_size * 0.5
		var card_half := CardVisual.card_size_play * 0.5
		var overlaps : Array[String] = []
		for col : int in [0, 2] as Array[int]:
			for row : int in 3:
				var cvis : CardVisual = pa.data_card.get(g.state.upper_zone[col].datas[row])
				if not cvis: continue
				var d := vis.global_position - cvis.global_position
				if absf(d.x) < ring_half.x + card_half.x and absf(d.y) < ring_half.y + card_half.y:
					overlaps.append("col %d row %d (d %s)" % [col, row, d])
		check(overlaps.is_empty(),
				"the ring overlaps no card outside its own column (separation %.1f)" % sep_scale,
				"; ".join(overlaps))
		# MID-GAP (owner 2026-07-15: "back should always be behind"): the visual sits between two
		# columns' cards — the column gap is narrower than the ring, so it touches BOTH. The back
		# half must render behind EVERY card the ring touches; whatever the data slot says, the
		# bracket follows the ring's geometry.
		vis.global_position = (pa.slot_center_global(Vector3i(0, 1, 1))
				+ pa.slot_center_global(Vector3i(0, 2, 1))) * 0.5
		for _j in 6:
			await get_tree().process_frame
		check(vis._split_active,
				"a hoop straddling the gap between two cards stays split (separation %.1f)" % sep_scale)
		order = dump_draw_order("hoop mid-gap between columns 1 and 2, separation %.1f" % sep_scale, pa)
		back_rank = draw_rank(order, vis.back_node)
		var left_rank := draw_rank(order, pa.data_card.get(g.state.upper_zone[1].datas[1]) as CardVisual)
		var right_rank := draw_rank(order, pa.data_card.get(g.state.upper_zone[2].datas[1]) as CardVisual)
		check(back_rank >= 0 and back_rank < left_rank and back_rank < right_rank,
				"mid-gap, the back half renders BEHIND both straddled cards (separation %.1f)" % sep_scale,
				"back %d left %d right %d" % [back_rank, left_rank, right_rank])
		var front_mid := draw_rank(order, vis.front_node)
		check(front_mid > left_rank and front_mid > right_rank,
				"mid-gap, the front half renders IN FRONT of both straddled cards (separation %.1f)"
				% sep_scale,
				"front %d left %d right %d" % [front_mid, left_rank, right_rank])
		# ROW CHANGE (future reroute modifiers): the DATA moves the prop down a row — a real
		# mover tick retargets the visual and re-pins its anchor slot, and the bracket follows
		# the anchor onto the new row: back behind the new row's cards but in front of the old
		# row's, front in front of the new row.
		p.at = Vector3i(0, 1, 2)
		ok = await run_tick(pl, [p], [], [p], [])
		check(ok, "the row-change mover tick completes (separation %.1f)" % sep_scale)
		for _j in 6:
			await get_tree().process_frame
		order = dump_draw_order("hoop dropped toward row 2, separation %.1f" % sep_scale, pa)
		back_rank = draw_rank(order, vis.back_node)
		front_rank = draw_rank(order, vis.front_node)
		var old_row_rank := draw_rank(order, pa.data_card.get(g.state.upper_zone[1].datas[1]) as CardVisual)
		var new_row_rank := draw_rank(order, pa.data_card.get(g.state.upper_zone[1].datas[2]) as CardVisual)
		check(back_rank > old_row_rank and back_rank < new_row_rank and front_rank > new_row_rank,
				"a row-changed hoop re-brackets the row it is now over (separation %.1f)" % sep_scale,
				"back %d front %d old-row %d new-row %d"
				% [back_rank, front_rank, old_row_rank, new_row_rank])
		await cleanup(g, pa)
	SettingsManager.settings.card_separation_scale = prev_sep

## Owner report 2026-07-16: a hoop crossing a row over a SHORT COLUMN (no card in its row there)
## was bracketed to the wrong row — back arc behind the zone header and rows above — because the
## short column's fanned last card is a full card TALL and "contained" the ring's center. The
## bracket row comes from the prop's ANCHOR SLOT now, and geometry (the prop's authored body
## rect) only decides WHETHER it is over cards: crossing row 1 over a 1-card column, the ring
## stays bracketed to row 1 — back IN FRONT of the short column's row-0 card and the headers,
## behind only its own row's cards.
func test_hoop_short_column_row_hold() -> void:
	var g := make_ragged_game([3, 1, 3] as Array[int])
	var pa := make_play_area()
	await settle(pa)
	var pl := pa.prop_layer
	var p := PropData.new()
	p.kind = 0
	p.at = Vector3i(0, 1, 1)   # middle column has NO card at row 1 — the empty-slot crossing
	p.route = [] as Array[Vector3i]
	var ok := await run_tick(pl, [p], [p], [], [])
	check(ok, "short-column hoop spawn tick completes")
	var vis : PropVisual = pl._visuals.get(p)
	for _i in 6:
		await get_tree().process_frame
	check(vis != null and vis._split_active,
			"the ring splits while its body overlaps the short column's fanned card")
	if vis == null or not vis._split_active:
		await cleanup(g, pa)
		return
	var order := dump_draw_order("hoop over the empty row-1 slot of a short column", pa)
	var back_rank := draw_rank(order, vis.back_node)
	var front_rank := draw_rank(order, vis.front_node)
	var short_top := draw_rank(order, pa.data_card.get(g.state.upper_zone[1].datas[0]) as CardVisual)
	var header_rank := draw_rank(order, pa.data_card.get(g.state.upper_zone_type[1]) as CardVisual)
	var left_row1 := draw_rank(order, pa.data_card.get(g.state.upper_zone[0].datas[1]) as CardVisual)
	var right_row1 := draw_rank(order, pa.data_card.get(g.state.upper_zone[2].datas[1]) as CardVisual)
	check(back_rank > short_top and back_rank > header_rank,
			"the back half renders IN FRONT of the short column's card and the zone header (rows above)",
			"back %d short-top %d header %d" % [back_rank, short_top, header_rank])
	check(back_rank < left_row1 and back_rank < right_row1,
			"the back half stays BEHIND the hoop's own row",
			"back %d row1 %d/%d" % [back_rank, left_row1, right_row1])
	check(front_rank > left_row1 and front_rank > right_row1,
			"the front half renders in front of the hoop's own row",
			"front %d row1 %d/%d" % [front_rank, left_row1, right_row1])
	await cleanup(g, pa)

# ==============================================================================
# FULL VIEW SNAPSHOTS (real GameView)
# ==============================================================================
func test_game_view_deal_snapshot() -> void:
	backup_real_save()
	var prev_run : RunState = RunManager.run
	var prev_save_info : RunState = Main.save_info
	var src_cards := TestDecks.seeded_deck()
	var src_rules := TestDecks.standard_rules()
	var run := RunManager.new_run(src_cards, src_rules)
	Main.save_info = run
	run.pending_goal = 1
	run.pending_node_id = 2
	seed(424242)
	var view : GameView = GAME_VIEW_SCENE.instantiate()
	add_child(view)
	await get_tree().process_frame
	await get_tree().process_frame
	var g := view.game
	await g.next()
	await g.next()
	var pa := view.play_area
	pa.flush_rebuild()
	await get_tree().process_frame
	var order := dump_draw_order("fresh GameView deal", view)
	var offenders := all_zero_z(order)
	# The map/HUD is out of scope, but the PLAY AREA subtree must stay all-zero-z.
	var pa_order := collect_draw_order(pa)
	var pa_offenders := all_zero_z(pa_order)
	check(pa_offenders.is_empty(),
			"the real dealt board keeps every PlayArea CanvasItem at z 0",
			"nonzero: %s" % str(pa_offenders.map(func(n: Node) -> String: return String(n.name))))
	check(order.size() > 0, "the dumper walked the full GameView tree", str(order.size()))
	await _teardown_view(view, prev_run, prev_save_info)

func test_end_screen_above_board() -> void:
	backup_real_save()
	var prev_run : RunState = RunManager.run
	var prev_save_info : RunState = Main.save_info
	var src_cards := TestDecks.seeded_deck()
	var src_rules := TestDecks.standard_rules()
	var run := RunManager.new_run(src_cards, src_rules)
	Main.save_info = run
	run.pending_goal = 1
	run.pending_node_id = 2
	var view : GameView = GAME_VIEW_SCENE.instantiate()
	add_child(view)
	await get_tree().process_frame
	await get_tree().process_frame
	var g := view.game
	await g.next()
	await g.next()
	# Force the win overlay directly (the seam _on_show_resolved does the real UI work).
	view._on_show_resolved(true, 100, 1)
	await get_tree().process_frame
	var order := dump_draw_order("end screen (win) over the board", view)
	var win_rank := draw_rank(order, view.win_screen)
	var pa_rank := draw_rank(order, view.play_area)
	check(view.win_screen.visible, "the win overlay is shown")
	check(win_rank > pa_rank, "the win/lose overlay renders above the whole PlayArea",
			"win %d vs playarea %d" % [win_rank, pa_rank])
	await _teardown_view(view, prev_run, prev_save_info)

func _teardown_view(view: GameView, prev_run: RunState, prev_save_info: RunState) -> void:
	view.queue_free()
	await get_tree().process_frame
	CardEnvironment.CURRENT = null
	RunManager._shutdown_saver()
	RunManager.clear_save()
	restore_real_save()
	RunManager.run = prev_run
	Main.save_info = prev_save_info

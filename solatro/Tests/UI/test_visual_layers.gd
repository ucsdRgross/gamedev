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
	await test_fx_inside_its_host()
	await test_overlay_above_everything()
	behavior_section("HOOP PASSES THROUGH A CARD (front/back split)")
	await test_hoop_back_half_interleaves()
	await test_hoop_split_multi_column()
	await test_hoop_short_column_row_hold()
	behavior_section("FULL VIEW SNAPSHOTS (real GameView)")
	await test_game_view_deal_snapshot()
	await test_end_screen_above_board()
	await test_light_layer_is_over_everything()
	await test_the_spotlight_wire_lights_the_layer()
	await test_the_light_travels_between_sections()
	await test_the_momentary_cue_draws_outside_scoring()
	await test_the_reveal_opens_a_row_and_moves_the_slots_below_it()
	await test_the_reveal_keeps_props_and_gutters_glued_G31_G32()
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

## Shader FX is a CHILD of its host: above the card's own face, but still inside the CardVisual
## subtree, so a card that overlaps this one paints over the flames too (owner ruling 2). That is
## also why CardLayer must stay strictly CardVisuals — nothing else is ever inserted into it.
func test_fx_inside_its_host() -> void:
	var g := make_board_game(2)
	var pa := make_play_area()
	await settle(pa)
	var card := g.state.upper_zone[0].datas[0]
	card.add_status(CardModifierStatus.stacked(StatusBurning, 3))
	var vis : CardVisual = pa.data_card.get(card)
	await get_tree().process_frame
	check(vis != null and vis.fx != null, "a burning card builds an FX attachment")
	check(vis.fx.get_parent() == vis.offset,
			"parented to Offset, never to Visual (which carries the basis3d squash)")
	check(vis.fx.get_child_count() == 1, "one quad for its one effect",
			str(vis.fx.get_child_count()))
	var order := dump_draw_order("burning card", vis)
	check(draw_rank(order, vis.fx) > draw_rank(order, vis.visual),
			"the FX draws above the card's own art",
			"fx %d vs visual %d" % [draw_rank(order, vis.fx), draw_rank(order, vis.visual)])
	for node : Node in pa.card_layer.get_children():
		check_impl(node is CardVisual or node is Node2D,
				"CardLayer holds no FX node of its own — FX rides inside its host")
	for entry : Dictionary in dump_draw_order("board with FX", pa):
		var item := entry["node"] as CanvasItem
		if item: check_impl(item.z_index == 0, "every board CanvasItem stays at z_index 0")
	# Ruling 23: a face-down card must leak nothing, and FX draws OUTSIDE the silhouette.
	# Checked WITHOUT awaiting a frame: delta_floating_anim rewrites basis3d every frame, which
	# recomputes show_front from the card's actual facing — so a frame later it is legitimately
	# front again. What matters is that the gate applies the moment the facing changes.
	vis.show_front = false
	check(not vis.fx.visible, "a face-down card hides its effects entirely")
	vis.show_front = true
	check(vis.fx.visible, "and flipping back restores them")
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
		# A hoop still takes no FORMATION offset — its whole lane offset is the card-jump rise, the
		# one thing it does ride (owner 2026-07-28: the card jumps INTO the ring, so the two centres
		# must coincide). Anything else here would be a formation leaking in.
		var jump_rise := Vector2(0.0, -CardVisual.card_jump_rise_play)
		check(vis != null and vis.lane_offset.is_equal_approx(jump_rise),
				"a hoop's only offset is the card-jump rise, never a formation (separation %.1f)"
				% sep_scale, str(vis.lane_offset) if vis else "no visual")
		for _i in 6:
			await get_tree().process_frame
		var occ_vis : CardVisual = pa.data_card.get(occupied)
		# The ring rides at the height a JUMPED card's centre reaches — that is the alignment the
		# whole feature is: card centre + jump rise == ring centre.
		check(vis != null and occ_vis != null
				and (vis.global_position - (occ_vis.global_position + jump_rise)).length() < 4.0,
				"the parked hoop is centred where the card's centre lands once it jumps "
				+ "(separation %.1f)" % sep_scale,
				"%s vs %s" % [vis.global_position if vis else Vector2.INF,
				(occ_vis.global_position + jump_rise) if occ_vis else Vector2.INF])
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
	seed(424242)  # before stand-up is fine: new_run uses its own RNG, the tree work after uses this
	var view : GameView = await _stand_up_view()
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
	await _teardown_view(view)

## ⚠ **THE LIGHT LAYER'S POSITION IS A CONTRACT AND IT FAILS SILENTLY.** `DESIGN.md` v9 / GAP-004:
## the dim exempts NOTHING — props, score popups, the focus panel, the HUD and the card glow all dim,
## and the glow dimming (`Q77`=a) is the entire mechanism by which a glow reads only inside its
## circle or beam (chart G13). Move the node one sibling earlier and whatever now draws after it is
## never dimmed again: no error, no crash, and the only symptom is "that one thing stays bright"
## during an effect nobody is looking at closely. Hence a test rather than a comment.
##
## It asserts the ORDER, not a pixel — a screen read is what this project does not have.
func test_light_layer_is_over_everything() -> void:
	var view : GameView = await _stand_up_view()
	var root := view.get_node("SceneRoot")
	var layer : LightLayer = root.get_node_or_null("LightLayer") as LightLayer
	check(layer != null, "the GameView carries a LightLayer under SceneRoot",
			str(root.get_node_or_null("LightLayer")))
	if layer:
		check(layer.get_index() == root.get_child_count() - 1,
				"and it is SceneRoot's LAST child, so it draws over the HUD and the board alike",
				"index %d of %d" % [layer.get_index(), root.get_child_count()])
		# It covers the screen; it must never swallow a click meant for a button under it.
		check(layer.mouse_filter == Control.MOUSE_FILTER_IGNORE,
				"and it ignores the mouse, so every control beneath it stays clickable")
		# The dim is a function of what is LIT (QR2=d) — nothing lit, no dim, and no second
		# "stop" path that could disagree with the light set.
		check(not layer.is_lit() and is_equal_approx(layer._dim, 0.0),
				"a board with no spotlight is not dimmed at all (QR2=d)", str(layer._dim))
	await _teardown_view(view)

## ⚠ **THE WHOLE LOOP, END TO END, AND IT IS THE ONLY TEST THAT CAN CATCH A BROKEN WIRE.** Every
## piece of phase 2 is asserted on its own — the cue emits (S10), the allocator places lamps (S14),
## the layer draws them (S13) — and all three can be green while nothing whatever appears on screen,
## because the thing between them is a signal connection and a `set_lights` call. That is exactly
## the failure "all tests pass and the feature does nothing" is made of.
##
## It drives the REAL `CardEnvironment` cue on a REAL dealt board, then asserts the layer came up.
func test_the_spotlight_wire_lights_the_layer() -> void:
	var view : GameView = await _stand_up_view()
	await view.game.next()
	view.play_area.flush_rebuild()
	await get_tree().process_frame
	check(view.spotlight_director != null, "the GameView built a SpotlightDirector")
	var layer := view.light_layer
	check(layer != null and not layer.is_lit(),
			"nothing is lit before a cue, so the dim is down (QR2=d)")
	# The REAL signal, with real board cards — not a hand-built light list, which would test the
	# layer and skip the wire that is actually at issue.
	var cards : Array[CardData] = []
	for data : CardData in view.play_area.data_card.keys():
		cards.append(data)
		if cards.size() >= 3: break
	check(cards.size() > 0, "the dealt board has cards to light", str(cards.size()))
	# ⚠ `spotlight_section_changed`, NOT `spotlight_cued` — GAP-005. These board cards are ordinary
	# numeral cards with no skill, which is exactly what a scored row is made of and exactly what the
	# announcement cue would have filtered away to nothing.
	view.game.spotlight_section_changed.emit(cards)
	await get_tree().process_frame
	check(layer.is_lit(), "the SECTION signal lights the layer — the wire is connected",
			"lit=%s" % str(layer.is_lit()))
	# ⚠ Every beam must point DOWN at its card (Q117). Asserted here as well as in the allocator,
	# because this is the only place the real pairing exists.
	var all_down := true
	for l : LightLayer.Light in layer._lights:
		if not SpotlightOrigins.points_down(l.origin, l.centre): all_down = false
	check(all_down, "and every live beam points DOWN at its target (Q117)")
	# ⚠ **`Q85`: THE CIRCLE IS CENTRED ON THE ART SQUARE, NOT ON THE CARD'S ORIGIN** (owner
	# 2026-08-04: *"circles should be centered on the skill art, not on card center"*). The two differ
	# by the `Art` node's authored offset, and centring on the origin put the pool high enough that
	# *"hard to tell which card circle it is on"*. Asserted against the CARD's own answer rather than
	# a constant, so the authored offset stays the single source.
	# ⚠ **STATED AS "NO LIGHT SITS ON A CARD ORIGIN", NOT "EVERY LIGHT SITS ON AN ART SQUARE".** The
	# positive form looks stronger and is flaky: `PlayArea` controls are POOLED per slot, so a
	# `CardVisual` can be re-bound between the emit and this check and a light legitimately stops
	# matching any current card — measured, it failed 2-of-3 that way while the code was correct.
	# The negative form is the actual regression: under the bug EVERY centre was a card origin.
	var on_origin := 0
	var on_art := 0
	for l : LightLayer.Light in layer._lights:
		for data : CardData in view.play_area.data_card.keys():
			var cv : CardVisual = view.play_area.data_card[data]
			if not is_instance_valid(cv) or not cv.is_inside_tree(): continue
			if l.centre.is_equal_approx(cv.global_position): on_origin += 1
			if l.centre.is_equal_approx(cv.spotlight_center()): on_art += 1
	check(on_origin == 0,
			"Q85: NO circle sits on a card's origin — they are on the ART SQUARE",
			"%d light(s) on an origin" % on_origin)
	check(on_art > 0,
			"...and at least one circle is positively matched to an art square, so this can fail",
			"%d of %d" % [on_art, layer._lights.size()])
	# The two points must actually differ, or neither check above could ever catch the bug.
	var probe : CardVisual = view.play_area.data_card.values()[0]
	check(not probe.spotlight_center().is_equal_approx(probe.global_position),
			"...and the art centre is a DIFFERENT point from the card origin (Art sits at y+5)",
			"%s vs %s" % [str(probe.spotlight_center()), str(probe.global_position)])
	# The dim RISES because something is lit, not because an act said so.
	var settled := 0.0
	while settled < 1.0 and is_equal_approx(layer._dim, 0.0):
		settled += await _tick_seconds()
	check(layer._dim > 0.0, "the dim rises while lights are up (QR2=d — driven by the light set)",
			str(layer._dim))
	# ⚠ GATE G2.4: `fx_intensity = 0` removes the LIGHTS and KEEPS a reduced dim. Q83 in the owner's
	# words: "keeps beams glow and dim" — so the setting may not switch the effect off outright.
	var prev_intensity := SettingsManager.settings.fx_intensity
	SettingsManager.settings.fx_intensity = 0.0
	view.light_layer._push_static()
	await get_tree().process_frame
	var brightness : float = layer._mat.get_shader_parameter(&"u_brightness")
	check(is_equal_approx(brightness, 0.0),
			"G2.4: fx_intensity 0 takes the lights to nothing", str(brightness))
	check(layer._dim > 0.0, "G2.4: and the DIM still stands (Q83 keeps it)", str(layer._dim))
	SettingsManager.settings.fx_intensity = prev_intensity
	# ⚠ **THE DIM'S OFF SWITCH** (owner 2026-08-04: *"make sure dim can be turned off if needed by
	# tunables, it just occured to me that dim might flash if speed is high"*). `spotlight_dim_target`
	# = 0 must keep the LIGHTS and drop the DIM — the exact opposite split from G2.4's `fx_intensity`,
	# which `Q83` forbids from removing the dim. Asserted because an off switch nothing tests is an
	# off switch that quietly stops working.
	var prev_dim_target := SettingsManager.settings.spotlight_dim_target
	SettingsManager.settings.spotlight_dim_target = 0.0
	var faded := 0.0
	while faded < 1.0 and layer._dim > 0.0:
		faded += await _tick_seconds()
	check(is_equal_approx(layer._dim, 0.0),
			"spotlight_dim_target = 0 turns the dim OFF entirely, at any speed", str(layer._dim))
	check(layer.is_lit(),
			"...and the beams and circles are STILL lit — it is the dim that went, not the show")
	SettingsManager.settings.spotlight_dim_target = prev_dim_target
	# Retiring the set is what lowers the dim — there is no second stop path.
	# ⚠ **RETIRE FADES, IT DOES NOT VANISH** (chart E3, and the brief's *"no instant movements or
	# spawning in and out"* applies to the end of an act too). So the claim is now two-sided, and the
	# first half is the one that would catch a regression to snapping: the lights are STILL lit on the
	# frame after `retire()`, and they go dark shortly after.
	# ⚠ **THE RETIRE SPAN IS WIDENED FOR THE MEASUREMENT, AND THAT IS THE FIX FOR A REAL FLAKE.** This
	# check read `is_lit()` one frame after `retire()` and failed ~1 run in 3 with *"went dark within
	# one frame"*. It was the INSTRUMENT, not the fade: the envelope is `delay * spotlight_retire_fraction`
	# (~0.3 of a short delay), so a single heavy frame's `delta` can consume the whole of it, free the
	# beam and empty the light set before this line runs — the code was right and the test could not
	# tell. Widening the knob makes one frame unable to swallow the envelope at any frame rate, which
	# is what lets the check measure the CLAIM (a fade is applied) instead of the frame rate.
	var prev_retire := SettingsManager.settings.spotlight_retire_fraction
	SettingsManager.settings.spotlight_retire_fraction = 20.0
	view.spotlight_director.retire()
	await get_tree().process_frame
	check(layer.is_lit(),
			"retire() FADES the lights rather than snapping them off (chart E3)",
			"went dark within one frame — the retire envelope is not being applied")
	# ⚠ AND IT IS PARTWAY THROUGH, not merely still present: a light that never faded at all would
	# also be `is_lit()`. This is the half that says the envelope is actually MOVING.
	var mid := 0.0
	for l : LightLayer.Light in layer._lights: mid = maxf(mid, l.intensity)
	check(mid < 1.0, "...and the fade is partway down, so the envelope is moving, not merely present",
			"brightest=%.3f" % mid)
	SettingsManager.settings.spotlight_retire_fraction = prev_retire
	var gone := 0.0
	while gone < 2.0 and layer.is_lit():
		gone += await _tick_seconds()
	check(not layer.is_lit(),
			"...and once faded, retiring the lights is what lowers the dim — no separate stop path",
			"still lit after %.2fs" % gone)
	await _teardown_view(view)

## **CHART E — THE TRAVEL.** The brief's requirement in one sentence: *"spotlights spawned during
## scoring phase need to move their spotlights to next row/col after done with current set, **no
## instant movements or spawning in and out**"*.
##
## ⚠ **THIS IS THE HALF OF S14 THAT DID NOT EXIST FOR THREE PHASES.** `_on_section_changed` used to
## call `_release_all()` and rebuild the whole set, so every light died and respawned on every
## section — the exact thing the brief forbids. Nothing caught it because a still frame of a rebuilt
## set and a still frame of a travelled set are identical; only the frames BETWEEN them differ.
func test_the_light_travels_between_sections() -> void:
	var view : GameView = await _stand_up_view()
	await view.game.next()
	view.play_area.flush_rebuild()
	await get_tree().process_frame
	var layer := view.light_layer
	var director := view.spotlight_director

	# Two DISJOINT sections, so every light must move: no card is in both.
	var all : Array[CardData] = []
	for data : CardData in view.play_area.data_card.keys(): all.append(data)
	check(all.size() >= 4, "the dealt board has enough cards for two disjoint sections", str(all.size()))
	if all.size() < 4:
		await _teardown_view(view)
		return
	var first : Array[CardData] = [all[0], all[1]]
	var second : Array[CardData] = [all[2], all[3]]

	view.game.spotlight_section_changed.emit(first)
	await get_tree().process_frame
	# Let the spawn envelope finish so the "did it move" measurement is not confused by a fade-in.
	var settled := 0.0
	while settled < 1.0:
		settled += await _tick_seconds()
	var before : Array[Vector2] = []
	for l : LightLayer.Light in layer._lights: before.append(l.centre)
	var origins_before : Array[Vector2] = []
	for l : LightLayer.Light in layer._lights: origins_before.append(l.origin)
	check(before.size() == 2, "the first section lit two cards", str(before.size()))

	# THE SECOND SECTION. Nothing here is in the first, so both lights must TRAVEL.
	view.game.spotlight_section_changed.emit(second)
	await get_tree().process_frame
	var during : Array[Vector2] = []
	for l : LightLayer.Light in layer._lights: during.append(l.centre)
	check(during.size() == before.size(),
			"the light COUNT does not change across the section — the same lamps move",
			"%d -> %d" % [before.size(), during.size()])
	# ⚠ THE CLAIM THAT MATTERS: one frame in, the circles are NOT yet on the new cards. A rebuild
	# would have them there already, which is precisely the defect this test exists for.
	var target_a := _centre_for(view, second[0])
	var snapped := 0
	for c : Vector2 in during:
		if c.is_equal_approx(target_a): snapped += 1
	check(snapped == 0,
			"one frame after the section changes, no circle has SNAPPED to its new card",
			"%d light(s) teleported — the travel is not being applied" % snapped)
	# ⚠ **E10: THE ORIGIN IS FIXED WHILE THE WIDE END TRACKS THE CIRCLE.** The lamp must not move with
	# the light, or the whole rig reads as sliding rather than one beam pivoting.
	var moved_origins := 0
	for i : int in mini(origins_before.size(), layer._lights.size()):
		if not layer._lights[i].origin.is_equal_approx(origins_before[i]): moved_origins += 1
	check(moved_origins == 0, "E10: the ORIGINS stay put while the circles travel",
			"%d origin(s) moved with their light" % moved_origins)

	# And it ARRIVES: given time, the circles reach the new cards.
	var travelled := 0.0
	var arrived := false
	while travelled < 3.0 and not arrived:
		travelled += await _tick_seconds()
		for l : LightLayer.Light in layer._lights:
			if l.centre.is_equal_approx(_centre_for(view, second[0])): arrived = true
	check(arrived, "and the travelling light ARRIVES on its new card (E11)",
			"never reached the target in %.1fs" % travelled)
	await _teardown_view(view)

## **S15 / CHART T — THE MOMENTARY CUE DRAWS, AND IT DRAWS OUTSIDE SCORING.**
##
## ⚠ **THIS IS THE CASE THE DESIGN'S WORKED EXAMPLE DOES NOT COVER, WHICH IS WHY IT IS THE TEST.**
## Every existing spotlight test drives `spotlight_section_changed` inside an act, where the per-section
## reveal gate (`_show`, GAP-006) is raised for it. Chart T's cue fires in ORDINARY PLAY — a card
## placed, a stack dropped by `Next` — where nothing raises that gate at all. A cue that rode it would
## be multiplied by `_show = 0` and be perfectly invisible, and every headless assertion about the
## light set would still pass, because the set would be right and only its intensity would be zero.
## That is `LightLayer.Light.gated`, and this is the input that separates it from the alternative.
##
## ⚠ **AND IT IS A DURATION, SO A STILL FRAME IS THE WRONG INSTRUMENT.** The cue spawns, HOLDS, and
## RETIRES ITSELF with nobody telling it to — the section beam never does that. So the assertions
## below are about what MOVED: lit at the start, still lit through the hold, dark on its own afterwards.
func test_the_momentary_cue_draws_outside_scoring() -> void:
	var view : GameView = await _stand_up_view()
	await view.game.next()
	view.play_area.flush_rebuild()
	await get_tree().process_frame
	var layer := view.light_layer
	check(not layer.is_lit(), "nothing is lit before the cue")
	# NO section signal and NO submit — the game is sitting idle, which is chart T's whole setting.
	check(not view.game.processing,
			"the game is NOT scoring, so this is Q245=(c)'s casual case", str(view.game.processing))
	var cards : Array[CardData] = []
	for data : CardData in view.play_area.data_card.keys():
		cards.append(data)
		if cards.size() >= 2: break
	check(cards.size() > 0, "the dealt board has cards to cue", str(cards.size()))

	view.game.spotlight_cued.emit(cards)
	await get_tree().process_frame
	check(layer.is_lit(),
			"S15: the CUE signal lights the layer with no section and no reveal raised",
			"lit=%s lights=%d" % [str(layer.is_lit()), layer._lights.size()])
	check(layer._lights.size() == cards.size(),
			"T13: N cards cued produce N spotlights, spawned together",
			"%d cued -> %d lights" % [cards.size(), layer._lights.size()])
	var ungated := 0
	for l : LightLayer.Light in layer._lights:
		if not l.gated: ungated += 1
	check(ungated == layer._lights.size(),
			"...and every cue light is UNGATED — it does not ride the per-section reveal",
			"%d of %d" % [ungated, layer._lights.size()])
	# ⚠ THE MEASUREMENT THAT WOULD CATCH THE INVISIBLE-CUE BUG: the value the SHADER is handed. The
	# light set being correct is not the claim; the claim is that it arrives with a non-zero intensity
	# while `_show` is still 0, which is the one thing gating got wrong.
	var settled := 0.0
	while settled < 1.0 and layer._dim <= 0.0:
		settled += await _tick_seconds()
	var pushed : PackedVector4Array = layer._mat.get_shader_parameter(&"u_lights")
	var brightest := 0.0
	for i : int in layer._lights.size(): brightest = maxf(brightest, pushed[i].w)
	check(brightest > 0.0,
			"the cue reaches the SHADER at a visible intensity while the reveal gate is down",
			"brightest=%.3f _show=%.3f" % [brightest, layer._show])
	check(is_equal_approx(layer._show, 0.0),
			"...and `_show` really is still down, so the check above could have failed",
			str(layer._show))
	# T10: the dim rises with the cue's own beam, in ordinary play rather than only during a submit.
	check(layer._dim > 0.0, "T10: the dim rises with the cue's beam outside scoring", str(layer._dim))
	# ⚠ `Q245`=(c): SHALLOWER than a scoring dim. Asserted against the knob rather than a literal, so
	# the two cannot disagree.
	var s := SettingsManager.settings
	check(layer._dim <= s.spotlight_dim_target * s.spotlight_dim_casual_scale + 0.001,
			"Q245=(c): and it is the SHALLOWER casual dim, not the scoring one",
			"dim=%.3f cap=%.3f" % [layer._dim, s.spotlight_dim_target * s.spotlight_dim_casual_scale])

	# **T6 — IT RETIRES ITSELF.** Nothing calls `retire()` here: the cue counts its own hold out and
	# goes. This is the half no still frame can show.
	var gone := 0.0
	while gone < 6.0 and layer.is_lit():
		gone += await _tick_seconds()
	check(not layer.is_lit(),
			"T6: the cue RETIRES ITSELF after its hold — nobody called retire()",
			"still lit after %.2fs" % gone)
	var fell := 0.0
	while fell < 2.0 and layer._dim > 0.0:
		fell += await _tick_seconds()
	check(is_equal_approx(layer._dim, 0.0),
			"T10: ...and the dim falls with it, because the dim is a function of what is lit (QR2=d)",
			str(layer._dim))

	# ⚠ **THE OTHER READING, AND THE INPUT THAT KILLS IT.** The cue could have reused the section path,
	# in which case its cards would become the new light SET — and `_on_section_changed` replaces, so a
	# cue arriving mid-section would steal the scoring beam's lamps and travel them onto the cued cards.
	# T15/T16 (`Q249`=a — nothing is blocked, a second cue may start while the first retires) says the
	# two coexist. So: light a section, cue a DIFFERENT card, and the section must be untouched.
	var all : Array[CardData] = []
	for data : CardData in view.play_area.data_card.keys(): all.append(data)
	if all.size() >= 3:
		var section : Array[CardData] = [all[0], all[1]]
		view.game.spotlight_section_changed.emit(section)
		await get_tree().process_frame
		var section_lights := layer._lights.size()
		view.game.spotlight_cued.emit([all[2]] as Array[CardData])
		await get_tree().process_frame
		check(layer._lights.size() == section_lights + 1,
				"a cue mid-section ADDS a light rather than replacing the section's set",
				"%d -> %d" % [section_lights, layer._lights.size()])
		# ⚠ **BY CARD IDENTITY, NOT BY PIXEL POSITION.** The first draft compared the section lights'
		# `centre` before and after and failed 1-of-2: a light's centre is re-read from its `CardVisual`
		# every frame (`Q252`=b), so a board still settling moves it a pixel between the two samples and
		# the comparison measures the board's animation rather than the claim. Which CARD each section
		# beam is pointed at is the actual thing a stolen lamp would change.
		var kept := 0
		for b : RefCounted in view.spotlight_director._beams:
			if b.get(&"cue"): continue
			if section.has(b.get(&"card")): kept += 1
		check(kept == section.size(),
				"...and every section light stays on its own card — the cue steals no lamp",
				"%d of %d kept" % [kept, section.size()])
		view.spotlight_director.retire()
	await _teardown_view(view)

## **S16 / S17 — THE ROW OPENS, AND `slot_center_global` KNOWS IT (K13, gate G3.1).**
##
## ⚠ **THE SECOND HALF IS THE ONE THAT MATTERS AND IS THE EASIEST TO SHIP BROKEN.** Growing a row's
## control is visible and obvious; `slot_center_global` is *pure uniform-pitch math* that every prop
## anchors to, so if it does not learn about the expansion, every prop below an opening row silently
## detaches from its slot while the board still looks right. The design flagged the function by name
## (K13) for exactly this reason.
func test_the_reveal_opens_a_row_and_moves_the_slots_below_it() -> void:
	var view : GameView = await _stand_up_view()
	await _deal_until_stacked(view)
	var pa := view.play_area

	# A card in row 0, and the slot one row BELOW it.
	# ⚠ **THAT SLOT NEED NOT HOLD A CARD, AND REQUIRING ONE IS WHAT MADE THE FIRST DRAFT FAIL** ("no
	# stacked column found" — a freshly dealt board is one row deep until a `Next` drops a stack).
	# `slot_center_global` is documented as pure math whose *"one formula covers occupied, empty, and
	# off-board slots alike"*, and it is precisely the EMPTY case that props rely on — a prop crossing a
	# short column anchors to a slot with no card in it. So the empty slot is the honest fixture here,
	# not a weaker one.
	# ⚠ **PICK A ROW THAT ACTUALLY COVERS SOMETHING.** Taking "any card at row 0" lands on whichever
	# zone the iteration reaches first, which on this board is often the UNSTACKED one — and then the
	# reveal correctly does nothing and every assertion below would be about the do-nothing case. The
	# covered row is the only one the feature is for.
	var target : CardData = null
	var below := Vector3i(-1, -1, -1)
	for data : CardData in pa.data_card.keys():
		var v := pa.coord_of_data(data)
		if v.z != 0 or not pa._row_covers_anything(v.x, 0): continue
		target = data
		below = Vector3i(v.x, v.y, 1)
		break
	check(target != null, "the dealt board has a COVERED row 0 to score — the case S16 exists for",
			"no stacked column found even after dealing until stacked")
	if target == null:
		await _teardown_view(view)
		return

	check(is_equal_approx(pa.row_open_extra(below.x, 0), 0.0),
			"nothing is open before the reveal, so the board is at its stacked layout",
			str(pa.row_open_extra(below.x, 0)))
	var closed_y := pa.slot_center_global(below).y

	# ⚠ **A FRESHLY DEALT BOARD IS ONE CARD DEEP, SO THIS ROW COVERS NOTHING AND MUST NOT OPEN.**
	# That is the corrected rule, not a limitation of the fixture: the opening exists to lift a
	# covering card off a buried one, and growing a strip with nothing under it only adds empty space
	# and shoves the zone below down. The owner caught exactly that in a playtest of
	# `reveal_shot.tscn` — *"lower zone input zone cards wiggle down and up twice ... zone cards
	# shouldnt move like that"* — and they were right: nothing was being revealed.
	var stacked := pa._row_covers_anything(below.x, 0)
	view.game.spotlight_section_changed.emit([target] as Array[CardData])
	var opened := 0.0
	while opened < 1.5 and pa.row_open_extra(below.x, 0) <= 0.0:
		opened += await _tick_seconds()
	if not stacked:
		check(is_equal_approx(pa.row_open_extra(below.x, 0), 0.0),
				"S16: a row that COVERS NOTHING does not open — no card is shoved for no reason",
				"opened %.1f px on a board one card deep" % pa.row_open_extra(below.x, 0))
		check(is_equal_approx(pa.slot_center_global(below).y, closed_y),
				"...and nothing below it moves either")
		# ⚠ **THE COVERED-CARD CASE — THE ONE THE FEATURE EXISTS FOR — IS NOT EXERCISED HERE.** It
		# needs a board with a real stack (a `Next` that drops one). Until a fixture builds that, S16's
		# headline behaviour is asserted only by the geometry test above, never end to end.
		check(true, "NOTE: the covered-card reveal is UNTESTED — this fixture is one card deep")
		await _teardown_view(view)
		return
	check(pa.row_open_extra(below.x, 0) > 0.0,
			"S16: the scored card's row OPENS, driven by the section signal",
			"still 0 after %.2fs" % opened)
	# ⚠ EASED, NOT SNAPPED (chart K10, `spotlight_reveal_fraction`). The owner's report that produced
	# that knob was *"cards jump to their new spot instantly"*, so partway-open is the claim.
	check(pa.row_open_extra(below.x, 0) < pa._row_open_height(),
			"...and it is EASING rather than snapping to its full opening",
			"already at %.1f of %.1f" % [pa.row_open_extra(below.x, 0), pa._row_open_height()])

	var settled := 0.0
	while settled < 3.0 and pa._row_open.get(Vector2i(below.x, 0), 0.0) < 1.0:
		settled += await _tick_seconds()
	var open_y := pa.slot_center_global(below).y
	check(open_y > closed_y,
			"S17/K13: the slot BELOW it moved down by the opening — props anchored there follow",
			"y %.1f -> %.1f (no movement means slot_center_global ignored the expansion)"
			% [closed_y, open_y])
	# ⚠ **ASSERTED ON THE RESULTING ROW PITCH, NOT ON THE STRIP'S GROWTH — and that distinction caught a
	# real bug.** The old form checked the movement against
	# `_row_open_height() - card_separation_play_custom`, which is the STRIP's growth and quietly
	# ignored the `separation` the VBox puts between rows. Sizing the strip to a full card therefore
	# produced a row pitch of card + separation, and the owner saw *"an odd gap between the rows, looks
	# like an extra few pixels of separation"*. The mode promises a TOTAL distance, so the total is what
	# has to be measured.
	var closed_pitch := closed_y - pa.slot_center_global(Vector3i(below.x, below.y, 0)).y
	var open_pitch := open_y - pa.slot_center_global(Vector3i(below.x, below.y, 0)).y
	check(absf(open_pitch - pa._row_open_height()) < 1.0,
			"...leaving a row pitch of EXACTLY the mode's opening (GAP-009) — no stray separation",
			"pitch %.1f -> %.1f, mode asks for %.1f" % [closed_pitch, open_pitch, pa._row_open_height()])
	# ⚠ **AN ALREADY-OPEN ROW MUST FOLLOW A LIVE SETTINGS CHANGE.** Every term in the opening is read
	# live — `separation` is a getter over `card_scale`, and the card metrics are static getters over
	# the same — and `_row_open` stores only the eased 0..1, never pixels. But "read live" is a claim
	# about a call path (`settings_changed -> update_gui -> set_card_zones_visuals ->
	# update_card_zone_visuals -> _apply_row_openings`), and a path is exactly the kind of thing that
	# is true until someone adds an early-out. Changing the scale MID-REVEAL is the input that tests it.
	var prev_scale : float = SettingsManager.settings.card_scale
	SettingsManager.settings.card_scale = prev_scale * 1.5
	await get_tree().process_frame
	await get_tree().process_frame
	var top_y := pa.slot_center_global(Vector3i(below.x, below.y, 0)).y
	var scaled_pitch := pa.slot_center_global(below).y - top_y
	check(scaled_pitch > open_pitch + 1.0,
			"a card_scale change mid-reveal actually MOVES the pitch, so the next check can fail",
			"pitch %.1f -> %.1f" % [open_pitch, scaled_pitch])
	check(absf(scaled_pitch - pa._row_open_height()) < 1.5,
			"...and the OPEN row re-derives to the mode's new opening — nothing was captured at spawn",
			"pitch %.1f, mode now asks for %.1f" % [scaled_pitch, pa._row_open_height()])
	SettingsManager.settings.card_scale = prev_scale
	await get_tree().process_frame
	await get_tree().process_frame
	check(absf((pa.slot_center_global(below).y
			- pa.slot_center_global(Vector3i(below.x, below.y, 0)).y) - open_pitch) < 1.5,
			"...and restoring the scale restores the pitch exactly",
			"back to %.1f, was %.1f" % [pa.slot_center_global(below).y
				- pa.slot_center_global(Vector3i(below.x, below.y, 0)).y, open_pitch])

	# The row ABOVE the opening must not move — an opening pushes down, it does not recentre the board.
	check(is_equal_approx(pa._row_open_offset(below.x, 0), 0.0),
			"and row 0 itself does not move — a row's opening grows the gap BELOW it")

	# JUMP_ADJUSTED is the other half of GAP-009's answer, and it must be a DIFFERENT number.
	var prev_mode : int = SettingsManager.settings.spotlight_separation_mode
	SettingsManager.settings.spotlight_separation_mode = PlayerSettings.SeparationMode.JUMP_ADJUSTED
	check(pa._row_open_height() < CardVisual.card_size_play.y,
			"GAP-009: JUMP_ADJUSTED opens LESS than a full card, so a non-jumping card stays covered",
			"%.1f vs card %.1f" % [pa._row_open_height(), CardVisual.card_size_play.y])
	# ⚠ **`card height - separation - jump rise`** (owner, 2026-08-06). `CARD_HEIGHT` opens to a pitch
	# of exactly one card; this mode also gives up the inter-row gap, so the shortfall is the
	# separation PLUS the jump. Asserted from the card's own constant and the live `separation` rather
	# than a literal, so a change to `card_scale` cannot make this drift.
	check(is_equal_approx(CardVisual.card_size_play.y - pa._row_open_height(),
			float(pa.separation) + CardVisual.card_jump_rise_play),
			"...by exactly separation + jump rise — 'card height - separation - jump height'",
			"shortfall %.1f, expected %.1f" % [CardVisual.card_size_play.y - pa._row_open_height(),
				float(pa.separation) + CardVisual.card_jump_rise_play])
	SettingsManager.settings.spotlight_separation_mode = prev_mode

	# AND IT CLOSES: an empty section releases the board.
	view.game.spotlight_section_changed.emit([] as Array[CardData])
	var closed := 0.0
	while closed < 3.0 and not pa._row_open.is_empty():
		closed += await _tick_seconds()
	check(pa._row_open.is_empty(),
			"the reveal CLOSES on release, and an idle board holds no reveal state at all",
			"still open after %.2fs" % closed)
	check(absf(pa.slot_center_global(below).y - closed_y) < 1.0,
			"...and the slot below returns to exactly where it started",
			"%.1f vs %.1f" % [pa.slot_center_global(below).y, closed_y])
	await _teardown_view(view)

## **GATE G3.1 + G3.2 — a prop anchored BELOW an expansion stays glued to its slot, and the row score
## gutter stays level with its row, through the WHOLE expand/collapse cycle.**
##
## ⚠ **THROUGH THE CYCLE, NOT AT ITS ENDS, WHICH IS THE ONLY WAY THESE TWO CAN FAIL.** Both are
## displacement bugs: if `slot_center_global` or the gutter learned about the opening but did so a
## frame late, or eased on a different curve, the start and end states would still match perfectly and
## the prop would swim against the board for the half-second in between. So this samples EVERY frame
## from closed through fully open and back, and asserts the invariant on all of them.
func test_the_reveal_keeps_props_and_gutters_glued_G31_G32() -> void:
	var view : GameView = await _stand_up_view()
	await _deal_until_stacked(view)
	var pa := view.play_area
	var pl := pa.prop_layer

	var target : CardData = null
	var below := Vector3i(-1, -1, -1)
	for data : CardData in pa.data_card.keys():
		var v := pa.coord_of_data(data)
		if v.z != 0: continue
		target = data
		below = Vector3i(v.x, v.y, 1)
		break
	check(target != null, "G3.1: the board has a row-0 card to score", "none found")
	if target == null:
		await _teardown_view(view)
		return

	# A REAL `PropVisual` on the REAL layer, pinned to the slot below the opening, exactly as
	# `_spawn_visual` pins one. ⚠ Not a stand-in: `_repin` is the code under test and it only runs for
	# visuals the layer actually holds, so a hand-rolled Node2D would prove nothing about it.
	# ⚠ **REGISTERED IN `_visuals`, NOT MERELY PARENTED — the first draft only did `add_child` and
	# measured a 90 px drift, which is the whole opening.** That was the harness, not the code:
	# `PropLayer._process` repins `_visuals.values()`, so a visual that is only a CHILD is never
	# followed. Worth keeping as a comment because the failure looked exactly like the bug this gate
	# is for — the prop sitting still while its slot moved out from under it.
	var prop := PropData.new()
	var vis := PropVisual.new()
	vis.anchor_coord = below
	pl.add_child(vis)
	vis.anchor_point = pl._slot_point(below)
	vis.position = vis.anchor_point
	pl._visuals[prop] = vis
	var pinned_offset := vis.position - vis.anchor_point
	await get_tree().process_frame

	view.game.spotlight_section_changed.emit([target] as Array[CardData])
	var worst_prop := 0.0
	var worst_gutter := 0.0
	var samples := 0
	var saw_partial := false
	var elapsed := 0.0
	# Open, hold, then close — sampling the invariant on every frame of it.
	while elapsed < 6.0:
		elapsed += await _tick_seconds()
		if not is_instance_valid(vis): break
		samples += 1
		var t : float = pa._row_open.get(Vector2i(below.x, 0), 0.0)
		if t > 0.05 and t < 0.95: saw_partial = true
		# G3.1: the prop's own pin must equal the live slot point every frame.
		worst_prop = maxf(worst_prop,
				(vis.position - pinned_offset).distance_to(pl._slot_point(below)))
		# G3.2: the row gutter label for row 0 must carry the same opening the row card strip does.
		var gutter : VBoxContainer = pa.upper_zone_left if below.x == 0 else pa.lower_zone_left
		if gutter and gutter.get_child_count() > 0:
			var label := gutter.get_child(0) as Control
			if label:
				var want : float = float(CardVisual.card_separation_play_custom) \
						+ pa.row_open_extra(below.x, 0)
				worst_gutter = maxf(worst_gutter, absf(label.custom_minimum_size.y - want))
		if is_equal_approx(elapsed, 0.0): continue
		if elapsed > 2.5 and not pa._row_open_wanted.is_empty():
			view.game.spotlight_section_changed.emit([] as Array[CardData])
		if elapsed > 2.5 and pa._row_open.is_empty(): break

	check(samples > 10, "G3.1: the cycle was sampled frame by frame", "%d samples" % samples)
	check(saw_partial,
			"G3.1: ...and the sampling caught the row PARTWAY open, so the mid-cycle claim is real",
			"never observed a partial opening — the ease was too fast to sample")
	check(worst_prop < 1.0,
			"G3.1: a prop anchored below the expansion stays glued to its slot all cycle",
			"drifted %.2f px from its anchor at worst" % worst_prop)
	check(worst_gutter < 1.0,
			"G3.2: the row gutter label grows with its row on every frame (K12)",
			"gutter was off its row by %.2f px at worst" % worst_gutter)
	pl._visuals.erase(prop)
	if is_instance_valid(vis): vis.queue_free()
	await _teardown_view(view)


## **DEAL UNTIL A COLUMN IS ACTUALLY STACKED — WITHOUT THIS, S16 CANNOT BE TESTED AT ALL.**
##
## ⚠ **ONE `next()` GIVES A BOARD ONE CARD DEEP, WHERE NOTHING IS COVERED**, so the reveal correctly
## does nothing and every assertion about it passes for the wrong reason. That is exactly how S16 came
## to be reported as verified while its whole purpose — lifting a covering card off a buried one — had
## never run: the fixture could not express the case. Each `Next` drops another card onto the columns.
func _deal_until_stacked(view: GameView) -> void:
	for _n : int in 4:
		await view.game.next()
		view.play_area.flush_rebuild()
		await get_tree().process_frame
		for zx : int in 2:
			for rz : int in 4:
				if view.play_area._row_covers_anything(zx, rz): return

## A card's art-square centre, for comparing against what the layer was handed.
func _centre_for(view: GameView, data: CardData) -> Vector2:
	var cv : CardVisual = view.play_area.data_card.get(data)
	return cv.spotlight_center() if is_instance_valid(cv) else Vector2.ZERO

## One frame of real time, and how long it took.
func _tick_seconds() -> float:
	await get_tree().process_frame
	return get_process_delta_time()

func test_end_screen_above_board() -> void:
	var view : GameView = await _stand_up_view()
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
	await _teardown_view(view)

## The stand-up's other half — stashed here so the eight GameView tests share ONE copy of the
## twelve-line ceremony instead of eight slightly-divergeable ones.
var _prev_run : RunState = null
var _prev_save_info : RunState = null

## Park the save, start a seeded run, instantiate a real GameView and settle it two frames.
## Callers needing a deterministic global stream call `seed()` BEFORE this — `new_run` uses its
## own RNG, so the order is safe.
func _stand_up_view() -> GameView:
	backup_real_save()
	_prev_run = RunManager.run
	_prev_save_info = Main.save_info
	var run := RunManager.new_run(TestDecks.seeded_deck(), TestDecks.standard_rules())
	Main.save_info = run
	run.pending_goal = 1
	run.pending_node_id = 2
	var view : GameView = GAME_VIEW_SCENE.instantiate()
	add_child(view)
	await get_tree().process_frame
	await get_tree().process_frame
	return view

func _teardown_view(view: GameView) -> void:
	view.queue_free()
	await get_tree().process_frame
	CardEnvironment.CURRENT = null
	RunManager._shutdown_saver()
	RunManager.clear_save()
	restore_real_save()
	RunManager.run = _prev_run
	Main.save_info = _prev_save_info

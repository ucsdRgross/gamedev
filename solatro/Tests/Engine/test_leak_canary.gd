extends TestSuite
# res://Tests/Engine/test_leak_canary.gd
# ==============================================================================
# MEMORY-LEAK CANARY (owner-approved 2026-07-17; reworked 2026-07-18 for the
# weakref conversion): CardModifier.data backrefs are now WeakRefs, so the old
# CardData<->modifier RefCounted cycle CANNOT exist — a dropped card graph just
# dies, with no unlink discipline anywhere. This suite is the tripwire proving
# that class of leak stays dead: build + tear down a full headless Game N times
# WITH NO UNLINKING and assert Performance.OBJECT_COUNT returns to baseline.
# If someone reintroduces a strong backref (or a new strong cycle), the growth
# check fails here.
#
# ⚠️ Runs LAST (of the engine-object-count suites) and ALONE: OBJECT_COUNT is engine-global, so
# any concurrent suite would make the numbers meaningless. See the SUITE ORDERING chain in
# test_base.gd — every earlier waiter excludes "LEAK CANARY".
#
# ⚠️ One suite now runs AFTER this one: WALL PAUSE (S12) constructs a real Wall whose _ready()
# pauses the tree GLOBALLY AND PERMANENTLY (never cleared — that is the behaviour it tests), so it
# must be the true tail of the whole chain or every suite after it would freeze mid-flight. This
# suite excludes "WALL PAUSE" below so the two do not deadlock waiting on each other.
# ==============================================================================

# CATEGORY MAP: all IMPLEMENTATION — object counts pin HOW memory behaves, not a
# player-visible rule.
#
# SECTION 2 (owner-endorsed 2026-07-17, ARCHITECTURE_REVIEW.md §6): the
# PRODUCTION SESSION CANARY simulates a real play session end-to-end per cycle —
# DeckPicker/DeckViewer open+close, run start, map traversal + hover panel + booster
# pack, a real show WITH a GameView (Nexts, grab/place, discard, Submit with real
# scoring/props, undo across the Submit), quit-mid-show -> resume, the win path
# (exit_show -> return_to_map) AND the loss path, then clear_save — and asserts
# OBJECT_COUNT returns to a post-warm-up baseline. This proves every PRODUCTION
# drop site (Game.undo, return_to_map, exit_show loss, RunManager.clear_save,
# DeckPicker close, MapHoverPanel previews) releases its card graphs — with the
# weakref backrefs no unlink call exists anywhere in these paths.

func suite_name() -> String:
	return "LEAK CANARY"

const CYCLES := 10
## Session cycles are a whole double-show each — keep the count small.
const SESSION_CYCLES := 3
const WATCHDOG_SECS := 10.0

const GAME_VIEW_SCENE := preload("res://Levels/game_view.tscn")
const HOVER_PANEL_SCENE := preload("res://UI/map_hover_panel.tscn")

## LEAK SENTINEL section fixture: cards deliberately held alive-but-unreachable.
var _sentinel_leaked : Array[CardData] = []

# ==============================================================================
# FORENSICS FOR AN INTERMITTENT NOBODY HAS CAUGHT IN THE ACT
#
# ⚠ **THE PROBLEM IS NOT THAT THE FAILURE IS HARD TO UNDERSTAND — IT IS THAT IT IS HARD TO BE
# PRESENT FOR.** Measured 2026-08-07: 3 failures in the session's first ~8 runs, then 0 in the next
# ~30, including a deliberate 14-run hunt that never tripped once. Anything that requires a human or
# an agent to be watching when it fires will keep costing whole sessions and keep coming back empty.
#
# So the design goal here is NOT "explain the leak". It is: **when it next fires — on the owner's
# machine, in a run nobody is watching, months from now — it must leave behind, unprompted, enough
# evidence to close the question without a reproduction.** Everything below is collected on EVERY
# run (it is cheap and allocates no Objects, so it cannot perturb the very count being measured) and
# printed + written to disk only when the check actually fails.
#
# The four things a bare "growth 2" cannot tell you, and what answers each:
#   * WHICH CLASS grew            -> _object_census (engine monitors: node / resource / other)
#   * WHERE IN THE SESSION        -> _mark_phase, a census after each of the 6 session phases
#   * WHAT KIND OF THING          -> _tree_histogram, node counts by class+script, diffed
#   * WHETHER IT IS A REAL LEAK   -> the per-cycle table: a leak grows EVERY cycle, lazy init
#                                    grows once. Two failures both read "growth 2", and those are
#                                    completely different bugs.
#
# ⚠ **Dictionaries, Arrays and Strings are Variants, not Objects**, so building these records does
# not move OBJECT_COUNT. That is what makes always-on collection safe here; anything that allocated
# an Object per phase would corrupt the measurement it exists to explain.
# ==============================================================================

## One census per phase per cycle: {cycle:int, label:String, census:Dictionary, tree:Dictionary}.
var _phase_marks : Array[Dictionary] = []
var _cycle_index : int = 0

## Called at the end of each phase of _session_cycle. Cheap, and silent unless something fails.
func _mark_phase(label: String) -> void:
	_phase_marks.append({
		"cycle": _cycle_index,
		"label": label,
		"census": _object_census(),
		"tree": _tree_histogram(),
	})

## Every node currently in the tree, counted by class (plus script file where it has one).
##
## ⚠ **THIS IS THE INSTRUMENT `print_orphan_nodes()` COULD NOT BE.** That prints nodes with NO
## parent; a node still parented to something retained — a viewer left in the tree, a panel never
## freed — is not an orphan and never appears there, which is exactly why the standing "next thing
## to try" was a dead end. A histogram sees anything in the tree regardless of who holds it.
func _tree_histogram() -> Dictionary:
	var counts : Dictionary[String, int] = {}
	var stack : Array[Node] = [get_tree().root]
	while not stack.is_empty():
		var node : Node = stack.pop_back()
		var key := node.get_class()
		# ⚠ Typed as Variant on purpose: get_script() is untyped, and warnings-as-errors rejects an
		# inferred-from-Variant local (`var scr := ...`) as a PARSE error, not a runtime one.
		var scr : Variant = node.get_script()
		if scr and scr is Resource and not (scr as Resource).resource_path.is_empty():
			key += " <" + (scr as Resource).resource_path.get_file() + ">"
		var seen : int = counts.get(key, 0)
		counts[key] = seen + 1
		for child : Node in node.get_children():
			stack.append(child)
	return counts

## Entries of `after` that are larger than in `before`, biggest growth first, as report lines.
## ⚠ Every Dictionary/Array read goes through a TYPED local rather than `int(...)`: subscripting an
## untyped Dictionary yields Variant, and `int(Variant)` is a parse error under warnings-as-errors.
func _histogram_growth(before: Dictionary, after: Dictionary) -> Array[String]:
	var grown : Array[Array] = []
	for key : String in after:
		var now : int = after[key]
		var was : int = before.get(key, 0)
		if now > was: grown.append([now - was, key, was, now])
	grown.sort_custom(func(a: Array, b: Array) -> bool:
		var ad : int = a[0]
		var bd : int = b[0]
		return ad > bd)
	var out : Array[String] = []
	for row : Array in grown:
		out.append("      +%-4d %s  (%d -> %d)" % [row[0], row[1], row[2], row[3]])
	return out

func _ready() -> void:
	await await_siblings_except(["WALL PAUSE"])
	TestLog.line("============ LEAK CANARY TEST PASS ============")
	implementation_section("REFCOUNT-CYCLE CANARY")

	# 0. Prove the canary CAN catch a leak: deliberately abandon a few Nodes (never
	# freed, never in the tree). A dropped CARD no longer leaks (weakref backrefs),
	# so a stray Node is the representative leak class the sentinel/canary watch for.
	# (This deliberately leaks the nodes for the rest of the process — done before
	# the baseline snapshot so it can't pollute the growth check below.)
	await _settle()
	var before_leak := _object_count()
	for i in 4:
		var stray := Node.new()
		stray.set_meta(&"deliberate_canary_leak", true)
	await _settle()
	check_impl(_object_count() > before_leak,
			"canary detects deliberately abandoned Nodes",
			"before %d, after %d" % [before_leak, _object_count()])

	# 1. Warm-up cycle: first build touches lazy one-time allocations (deck
	# caches, static registries) that must not count against the loop.
	_clean_cycle()
	await _settle()
	var baseline_census := _object_census()
	var baseline : int = baseline_census.total

	# 2. N clean build/teardown cycles must return to the warm baseline.
	for i in range(CYCLES):
		_clean_cycle()
	await _settle()
	var after_census := _object_census()
	var after : int = after_census.total
	check_impl(after <= baseline,
			"OBJECT_COUNT returns to baseline after %d clean Game build/free cycles" % CYCLES,
			"baseline %d, after %d (growth %d)" % [baseline, after, after - baseline])
	if after > baseline:
		_report_growth(baseline_census, after_census)

	implementation_section("PRODUCTION SESSION CANARY")
	# Isolation: the cycles write run.tres + settings.tres and swap the run singletons —
	# park the real ones and restore after (same discipline as VISUAL LAYERS / E2E).
	backup_real_save(suite_tag())
	backup_real_settings()
	var real_run : RunState = RunManager.run
	var real_save_info : RunState = Main.save_info
	var prev_delay : float = SettingsManager.settings.base_delay
	SettingsManager.settings.base_delay = TestLog.speed_base_delay

	# Warm-up session: first cycle touches lazy one-time allocations (scene caches, shader
	# state, translation table, static registries) that must not count against the loop.
	_cycle_index = 0
	await _session_cycle()
	await _drain()
	var session_baseline_census := _object_census()
	var session_baseline : int = session_baseline_census.total

	for i : int in range(SESSION_CYCLES):
		_cycle_index = i + 1
		await _session_cycle()
	await _drain()
	var session_after_census := _object_census()
	var session_after : int = session_after_census.total
	check_impl(session_after <= session_baseline,
			"OBJECT_COUNT returns to baseline after %d full simulated play sessions" % SESSION_CYCLES,
			"baseline %d, after %d (growth %d)"
			% [session_baseline, session_after, session_after - session_baseline])
	if session_after > session_baseline:
		_report_growth(session_baseline_census, session_after_census)

	implementation_section("LEAK SENTINEL")
	# The sentinel is quiet under the test runner (TestLog._started), so drive tick()
	# directly: cards held alive but unreachable from any legitimate owner must raise the
	# unreachable count, and enough over-slack ticks must fire the report (which resets
	# the strike counter — that reset is the observable proof the report branch ran).
	var n0 := LeakSentinel.tick()
	for i : int in 20:
		_sentinel_leaked.append(TestFactories.m_card(1, TestFactories.uc()))
	var n1 := LeakSentinel.tick()
	check_impl(n1 >= n0 + 20,
			"the sentinel counts force-leaked linked cards as unreachable",
			"before %d, after %d" % [n0, n1])
	LeakSentinel._strikes = 0
	for i : int in SettingsManager.settings.leak_sentinel_strikes:
		LeakSentinel.tick()
	# exactly `strikes` over-slack ticks reach the threshold on the last one, so the report
	# fired and reset the counter; any other end state means the report branch never ran
	check_impl(LeakSentinel._strikes == 0,
			"enough over-slack checks fire the sentinel report (the push_error above is deliberate)")
	_sentinel_leaked.clear()

	SettingsManager.settings.base_delay = prev_delay
	restore_real_settings()
	restore_real_save(suite_tag())
	RunManager.run = real_run
	Main.save_info = real_save_info
	finish()

func _object_count() -> int:
	return int(Performance.get_monitor(Performance.OBJECT_COUNT))

## OBJECT_COUNT split by what the engine can actually distinguish, for the failure report below.
## Nodes and Resources are counted separately by the engine; everything else (plain RefCounted —
## Tweens, Callables' bound objects, WeakRefs, script instances) is the remainder.
func _object_census() -> Dictionary:
	var nodes := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var resources := int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT))
	var total := _object_count()
	return {
		"total": total,
		"nodes": nodes,
		"resources": resources,
		"other": total - nodes - resources,
		"orphans": int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)),
		# ⚠ **THE PRIME SUSPECT FOR THE "other" BUCKET, AND THE ONE THING THE ENGINE MONITORS CANNOT
		# SPLIT OUT.** A `Tween` is RefCounted (so it lands in `other`, never in nodes or resources)
		# and it KEEPS ITSELF ALIVE while it is running — so a tween still ticking when `_drain()`
		# gives up survives the drain and reads as a leak. That fits every observed property of this
		# intermittent: RefCounted rather than a Node, timing-dependent, invisible in the per-phase
		# totals (which are dominated by live objects mid-cycle) and only visible AFTER the drain.
		# Counting them turns "growth 2, class unknown" into a yes/no.
		"tweens": get_tree().get_processed_tweens().size(),
	}

## ⚠ **`print_orphan_nodes()` IS THE WRONG INSTRUMENT FOR THIS CHECK, AND WAS THE STANDING "NEXT
## THING TO TRY" FOR MONTHS.** Measured 2026-08-07 on a run that FAILED with growth 2: it printed
## exactly four strays, and all four are the DELIBERATE ones this suite abandons above to prove the
## canary can see a leak at all. The real growth showed up in none of them — because it is not a
## Node, so an orphan-node dump cannot contain it however many times it is run.
##
## So report the CENSUS instead: which of the three classes the growth actually landed in. That is
## the fact that narrows the search, and it is one subtraction rather than a hunt.
func _report_growth(before: Dictionary, after: Dictionary) -> void:
	var lines : Array[String] = []
	lines.append("growth by class — total %+d: nodes %+d, resources %+d, other %+d"
			% [after.total - before.total, after.nodes - before.nodes,
			   after.resources - before.resources, after.other - before.other])
	lines.append("orphan nodes %d -> %d. ⚠ A growth of 0 in `nodes` means print_orphan_nodes() "
			% [before.orphans, after.orphans]
			+ "cannot help — the leak is a Resource or a plain RefCounted.")
	# ⚠ Typed locals, not `int(...)`: a Dictionary subscript is Variant and `int(Variant)` is a PARSE
	# error under warnings-as-errors — which makes the whole SUITE fail to load while the run still
	# reports "PASSED" at a suite count of 29. Cost 8 wasted runs on 2026-08-08.
	var tw_before : int = before.tweens
	var tw_after : int = after.tweens
	var tween_delta : int = tw_after - tw_before
	lines.append("RUNNING TWEENS %d -> %d (%+d). ⚠ A Tween is RefCounted, so it lands in `other`, and"
			% [tw_before, tw_after, tween_delta]
			+ " it keeps ITSELF alive while running — if this delta matches the `other` delta above,")
	lines.append("  the 'leak' is simply a tween still ticking when _drain() gave up, and the fix is"
			+ " the DRAIN (wait for tweens), not a retained reference anywhere.")
	# IS the leak; all-zero means the suspect list is wrong and needs widening.

	# --- WHERE IN THE SESSION, and IS IT LINEAR -------------------------------------------------
	# One row per phase, one column per cycle. A real per-cycle leak climbs steadily along a row;
	# a lazy one-time allocation steps once and then flattens. Both report "growth 2" without this.
	if not _phase_marks.is_empty():
		var labels : Array[String] = []
		for mark : Dictionary in _phase_marks:
			if not labels.has(mark.label as String): labels.append(mark.label as String)
		lines.append("")
		lines.append("PER-PHASE OBJECT_COUNT (cycle 0 = warm-up; a LEAK climbs every cycle, a lazy")
		lines.append("one-time allocation steps once and flattens — that difference is the diagnosis):")
		for label : String in labels:
			var row := "  %-38s" % label
			var prev := -1
			for mark : Dictionary in _phase_marks:
				if mark.label as String != label: continue
				var total : int = (mark.census as Dictionary).total
				row += "%7d%s" % [total, "" if prev < 0 else ("(%+d)" % (total - prev))]
				prev = total
			lines.append(row)

		# --- WHAT KIND OF THING ------------------------------------------------------------------
		# Same phase, first measured cycle vs last: any node class that grew is named here.
		var first_of : Dictionary = {}
		var last_of : Dictionary = {}
		for mark : Dictionary in _phase_marks:
			var key : String = mark.label as String
			if not first_of.has(key): first_of[key] = mark.tree
			last_of[key] = mark.tree
		lines.append("")
		lines.append("NODE CLASSES THAT GREW between the first and last cycle of a phase")
		lines.append("(⚠ these are nodes IN THE TREE — the thing an orphan dump structurally cannot show):")
		var any := false
		for label : String in labels:
			var grown := _histogram_growth(first_of[label] as Dictionary, last_of[label] as Dictionary)
			if grown.is_empty(): continue
			any = true
			lines.append("    %s" % label)
			for line : String in grown: lines.append(line)
		if not any:
			lines.append("    (none — every node class is flat, so the growth is NOT a tree node.")
			lines.append("     Combined with `nodes +0` above that points at a Resource or a plain")
			lines.append("     RefCounted: a Tween, a bound Callable, a WeakRef or a script instance.)")

	for line : String in lines:
		TestLog.line("  [leak forensics] " + line, true)
	_write_forensics(lines)

## ⚠ **THE CONSOLE IS NOT WHERE THIS WILL BE READ.** This fires on a rare, unwatched run — very
## likely the owner's, months from now, in a log that scrolls or gets overwritten by the next run
## (`test_output_*.log` are truncated every run, by design). A durable, timestamped artifact is the
## whole point: one failure anywhere is then enough to close the question, with no reproduction.
func _write_forensics(lines: Array[String]) -> void:
	var stamp := Time.get_datetime_string_from_system().replace(":", ".")
	var path := "user://logs/leak_forensics_%s.txt" % stamp
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://logs"))
	var f := FileAccess.open(path, FileAccess.WRITE)
	if not f:
		TestLog.line("  [leak forensics] ⚠ could not write %s — the console above is all there is."
				% path, true)
		return
	f.store_line("LEAK CANARY forensics — %s" % stamp)
	f.store_line("Suite: %s | %d session cycles | %d phase marks"
			% [suite_name(), SESSION_CYCLES, _phase_marks.size()])
	f.store_line("Read this with todo.md's 'LEAK CANARY' entry and ARCHITECTURE_REVIEW §6.")
	f.store_line("")
	for line : String in lines: f.store_line(line)
	f.close()
	TestLog.line("  [leak forensics] ⚠ WRITTEN TO %s — attach this file, it is the whole finding."
			% ProjectSettings.globalize_path(path), true)

## Two idle frames so queued deletions/refcount releases settle before counting. Also
## prunes the sentinel registry: its per-card WeakRefs are benign growth that would
## otherwise fail the object-count checks.
func _settle() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	LeakSentinel.prune()

## One full lifecycle with NO unlinking — the weakref backrefs mean dropping the
## Game must release every card and modifier on their own.
func _clean_cycle() -> void:
	var g := _make_game()
	CardEnvironment.CURRENT = null
	g.free()

# ==============================================================================
# PRODUCTION SESSION CANARY (section 2 — see the header): one full simulated play
# session per cycle, through the real production objects and drop sites.
# ==============================================================================

## Bounded post-cycle drain before a count: every action above was awaited to completion,
## so this only catches the last self-freeing popup/tween queue_free tails; the settle
## frames then flush queued deletions. Identical before the baseline and the final count,
## so any steady-state floor cancels out.
## ⚠ **0.6 s, AND THE NUMBER IS LOAD-BEARING: IT MUST OUTLAST THE LONGEST ONE-SHOT TIMER THE GAME
## CREATES.** `PlayArea._ready()` calls `FxAttachment.warm()`, which walks
## `[FxFire.FIRE_SHADER, FxJuggle.JUGGLE_SHADER]` and creates a **0.5 s** `SceneTreeTimer` per shader
## to free its warm-up quad. A `SceneTreeTimer` is **RefCounted**, so two of them pending land in the
## census's `other` bucket — not `nodes`, not `resources` — and at 0.25 s this drain returned while
## they were still alive. That is the whole of the canary's intermittent "growth 2": two pending
## warm-up timers, not a leak. Every property matches — RefCounted, exactly 2, invisible to
## `print_orphan_nodes()`, absent from the exit-time dump because they fire long before exit.
##
## ⚠ **DO NOT "FIX" THIS BY DRAINING REPEATEDLY.** Each `_drain()` creates a timer of its own, so a
## retry loop allocates into the very bucket it measures — measured: growth went 2 -> 3 and the
## failure rate doubled. One LONGER wait is correct; more waits are not.
## ⚠ If a new one-shot timer longer than 0.6 s is ever added to a startup path, raise this to match.
func _drain() -> void:
	await get_tree().create_timer(0.6).timeout
	await _settle()

## ⚠⚠ **DEAD END — DO NOT ADD A "DRAIN HARDER / RETRY THE DRAIN" REMEDY. IT IS SELF-DEFEATING, AND
## THAT IS WHY EVERY PREVIOUS ATTEMPT FAILED.**
##
## Tried and reverted: retry `_drain()` until the count returns to the baseline, capped at 6 extra
## drains. Result over 10 runs — 5 failures, and on every one of them the growth SURVIVED all six
## extra drains. So the objects are not merely slow to release.
##
## ⚠ **AND THE REMEDY MAKES IT WORSE, MEASURABLY: growth went 2 -> 3 and the failure rate roughly
## doubled.** `_drain()` calls `get_tree().create_timer()`, and a `SceneTreeTimer` **is RefCounted**,
## so every extra drain allocates into the exact bucket (`other`) the check is measuring — and it does
## so ASYMMETRICALLY, because the baseline drains once while the after-path drains up to seven times.
## Any drain-based remedy inflates the number it is trying to reduce. This almost certainly explains
## the earlier "settle until stable" attempt's failure too.
##
## ⚠ A remedy in this direction would first have to make the drain ALLOCATION-FREE (frames only, no
## `create_timer`), and even then the evidence above says more draining does not release these.

func _session_cycle() -> void:
	# --- 1. Menus: DeckPicker open (builds every starter deck list), inspect one in a
	# DeckViewer, close it, then Pick. No deck_picked listener on purpose: the run below
	# starts from the FROZEN TestDecks so per-cycle allocations stay replay-stable, while
	# the picker still exercises its full build + drop path (incl. the rules list).
	var picker := DeckPicker.add_to_scene(self)
	await _settle()
	var first_deck : Array[CardData] = picker._deck.get_deck_list()[0]["cards"]
	var deck_viewer := DeckViewer.show_deck(picker, first_deck)
	await _settle()
	deck_viewer._close()
	await _settle()
	picker._on_pick(first_deck)
	await _settle()

	_mark_phase("1 menus (DeckPicker/DeckViewer)")
	# --- 2. Run start (production path: new_run deep-duplicates; the sources drop here).
	var cards := TestDecks.seeded_deck()
	var rules := TestDecks.standard_rules()
	var run := RunManager.new_run(cards, rules)
	Main.save_info = run

	_mark_phase("2 run start (new_run)")
	# --- 3. Map: enter (synthetic line graph, no world generation — the MAP TRAVERSAL rig
	# pattern), traverse two nodes, hover-panel a booster node, open + confirm its pack.
	var controller := _build_map_rig(run)
	var overlay : WorldGraphOverlay = controller.map.overlay()
	await controller.move_to(overlay.node(1))
	await controller.move_to(overlay.node(2))
	var booster_node : WorldGraphNode = null
	for n : WorldGraphNode in overlay.nodes():
		if n.meta.get(MapNodeRoles.ROLE_KEY, "") as String == MapNodeRoles.ROLE_BOOSTER:
			booster_node = n
			break
	check_impl(booster_node != null, "the synthetic map assigns at least one booster node")
	if booster_node:
		var panel : MapHoverPanel = HOVER_PANEL_SCENE.instantiate()
		add_child(panel)
		await panel.show_for_node(booster_node, run, controller.lap_target(), Vector2(100, 100))
		await _settle()
		panel.hide_panel()
		panel.queue_free()
		await _settle()
		# Booster pack: take-all ChoiceViewer; confirmed cards join the run deck (mirrors
		# Map._open_booster / _on_booster_confirmed).
		var booster : BoosterTemplate = booster_node.meta[MapNodeRoles.BOOSTER_KEY]
		var viewer : ChoiceViewer = await booster.on_map_picked(self)
		viewer.confirmed.connect(func(taken: Array[CardData]) -> void:
			for card : CardData in taken:
				Main.save_info.card_datas.append(card)
			RunManager.mark_deck_dirty()
			RunManager.save_run())
		await _settle()
		viewer._on_confirm_pressed()
		await _settle()
	controller.queue_free()
	await _settle()

	_mark_phase("3 map + booster")
	# --- 4. A real show WITH a GameView: Nexts, grab/place, discard, a real placement pass with
	# real scoring (props spawn + finish inside the awaited resolution -- see the placement fill
	# below), UNDO across it (the quiescent Game.undo() drops the popped snapshot), redo,
	# quit-mid-show -> resume, win.
	run.pending_goal = 1
	run.pending_node_id = 2
	seed(424242)
	var view : GameView = GAME_VIEW_SCENE.instantiate()
	add_child(view)
	await _settle()
	var g := view.game
	await g.next()
	# Fill row 0 through the real placement path: the fifth card completes the row, the
	# detector scores it, and the scoring cascade allocates the prop visuals and beams that
	# are the whole point of a leak canary. This is also what makes the show winnable below.
	var placed : Array[CardData] = await TestGridFixtures.place_row_from_deck(g, 0, 0, 5)
	# Discard one of the placed cards through the real path.
	if placed:
		await g.discard_data(placed[0])
	g.undo()
	await _settle()

	# Quit-mid-show -> resume: the abandoned show's board drops with the view.
	RunManager._shutdown_saver()
	RunManager.save_run()
	view.queue_free()
	await get_tree().process_frame
	CardEnvironment.CURRENT = null
	var loaded := RunManager.load_run()
	Main.save_info = loaded
	var view2 : GameView = GAME_VIEW_SCENE.instantiate()
	add_child(view2)
	await _settle()
	var g2 := view2.game
	var waited := 0.0
	while g2.processing and waited < WATCHDOG_SECS:  # resume holds the lock until visuals sync
		await get_tree().process_frame
		waited += get_process_delta_time()
	check_impl(not g2.processing, "the resumed show hands the board back to the player")

	var won : Array[bool] = []
	g2.show_resolved.connect(func(w: bool, _score: int, _goal: int) -> void: won.append(w))
	# The resumed board is whatever the quit committed; score a line on it so the goal of 1 is
	# met through the real path rather than by assuming the pre-quit score survived.
	await TestGridFixtures.place_row_from_deck(g2, 0, 1, 5)
	g2.end_show()
	check_impl(won.size() == 1 and won[0], "the seeded show resolves as a win", str(won))
	g2.exit_show()   # win path: return_to_map banks the deck into the run doc
	await _settle()
	view2.queue_free()
	await _settle()
	CardEnvironment.CURRENT = null

	_mark_phase("4 show + placement + undo + resume + win")
	# --- 5. The loss path: an unreachable goal, three repeated Nexts (the grid game's
	# repeatable, allocating act -- see place_card_in_grid's "the thing a Submit used to be"),
	# exit_show ends the run (the whole doomed board drops with the view).
	loaded.pending_goal = 1000000000
	loaded.pending_node_id = 1
	seed(31337)
	var view3 : GameView = GAME_VIEW_SCENE.instantiate()
	add_child(view3)
	await _settle()
	var g3 := view3.game
	await g3.next()
	await g3.next()
	await g3.next()
	g3.exit_show()
	await _settle()
	view3.queue_free()
	await _settle()
	CardEnvironment.CURRENT = null

	_mark_phase("5 loss path")
	# --- 6. Run over: drop the save + run doc.
	RunManager._shutdown_saver()
	RunManager.clear_save()
	Main.save_info = RunState.new()
	_mark_phase("6 run over (clear_save)")

## The topmost card of the first non-empty lower-zone column at or after `from_col`.
func _topmost_lower(g: Game, from_col: int) -> CardData:
	for i : int in range(from_col, g.state.lower_zone.size()):
		var col : ArrayCardData = g.state.lower_zone[i]
		if col.datas.size() > 0:
			return col.datas[-1]
	return null

## MAP TRAVERSAL's rig, production-shaped: WorldMapController + camera/token (unique-named
## for the @onready %lookups), a stub WorldMap2D that never generates, a synthetic line
## graph populated by hand, and roles assigned via the controller's own _on_graph_populated
## (which also parks the token on the lap origin). Expect one harmless "baked composite not
## found" warning from the stub map.
func _build_map_rig(run: RunState) -> WorldMapController:
	var controller := WorldMapController.new()
	var cam := Camera2D.new()
	cam.name = "Camera2D"
	controller.add_child(cam)
	cam.owner = controller
	cam.unique_name_in_owner = true
	var token := MapPlayerToken.new()
	token.name = "Token"
	controller.add_child(token)
	token.owner = controller
	token.unique_name_in_owner = true
	add_child(controller)
	var map := WorldMap2D.new()
	map.generate_on_ready = false
	map.bake_directory = "user://__leak_canary_no_bake__"
	controller.add_child(map)
	controller.map = map
	controller.run = run
	map.overlay().populate(_line_export(4), Vector2(50, 10))
	controller._on_graph_populated()
	return controller

## A straight-line graph, one node per depth 0..max_depth (MAP ROLES' shape — its booster
## window guarantee puts at least one booster on the mid ranks). Tiny distances keep the
## token travel tweens fast.
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

func _rules_card(skill: CardModifierSkill) -> CardData:
	var c := CardData.new().with_skill(skill)
	c.stage = CardData.Stage.RULES
	skill.spotlit = true
	return c

## Same minimal-but-real headless fixture as test_game_headless.make_game():
## rules deck with the classic skills + two zones of typed 2-card columns —
## every modifier slot the unlink helpers cover is exercised.
func _make_game() -> Game:
	var g := Game.new()
	var s := GameData.new()
	s.rules_deck = [
		_rules_card(SkillGrabberOgLower.new()),
		_rules_card(SkillPlacerOgLower.new()),
		_rules_card(SkillScorerCascadeLower.new()),
		_rules_card(SkillEvalPokerBest.new()),
	] as Array[CardData]
	for zone_x in 2:
		var types: Array[CardData] = []
		var cols: Array[ArrayCardData] = []
		for c in 2:
			var h := TestFactories.m_card(1, TestFactories.uc()); h.stage = CardData.Stage.ZONE
			types.append(h)
			var card_lo := TestFactories.m_card(3, TestFactories.uc())
			var card_hi := TestFactories.m_card(4, TestFactories.uc())
			card_lo.stage = CardData.Stage.PLAY
			card_hi.stage = CardData.Stage.PLAY
			cols.append(TestFactories.col([card_lo, card_hi] as Array[CardData]))
		if zone_x == 0:
			s.upper_zone_type = types
			s.upper_zone = cols
		else:
			s.lower_zone_type = types
			s.lower_zone = cols
	g.state = s
	CardEnvironment.CURRENT = g
	return g

extends Node
## Debug-build playtest leak sentinel (2026-07-18 leak rework, workstream B). At quiescent
## moments (map entry / show exit via request_check, plus a slow timer — never mid-act) it
## prunes CardData.sentinel_registry, counts the cards still alive, and counts the cards
## REACHABLE from every legitimate owner (run doc, live game, open viewers). A sustained
## excess of alive over reachable means something is holding dropped cards — push_error
## prints the counts plus a histogram of the unreachable cards by stage and modifier
## classes, which is what NAMES the leak source. Tunables live in player_settings.gd
## (leak_sentinel_*). Idle in release builds and under the test runner (suites abandon
## cards on purpose; the LEAK CANARY suite drives tick() directly instead).

## Set true by the test runner (TestLog.begin) — suites deliberately abandon cards, so the
## sentinel's own timer/hooks stay quiet there (the LEAK CANARY suite drives tick() itself).
static var test_mode : bool = false

var _strikes : int = 0
var _timer : Timer = null

func _ready() -> void:
	if not OS.is_debug_build():
		return
	_timer = Timer.new()
	_timer.one_shot = false
	_timer.wait_time = maxf(SettingsManager.settings.leak_sentinel_interval, 1.0)
	_timer.timeout.connect(_on_timer)
	add_child(_timer)
	_timer.start()
	SettingsManager.settings.settings_changed.connect(func() -> void:
		if _timer: _timer.wait_time = maxf(SettingsManager.settings.leak_sentinel_interval, 1.0))

func _on_timer() -> void:
	if not _enabled(): return
	# never mid-act: a resolving submit holds transient copies that are not leaks
	var game : Game = CardEnvironment.get_current_game()
	if game and game.processing: return
	tick()

## Quiescent-moment hook (map entry, show exit): check after the drops settle (two idle
## frames), skipping like the timer does when a game is still resolving.
func request_check() -> void:
	if not _enabled(): return
	await get_tree().process_frame
	await get_tree().process_frame
	var game : Game = CardEnvironment.get_current_game()
	if game and game.processing: return
	tick()

func _enabled() -> bool:
	return OS.is_debug_build() and not test_mode \
			and SettingsManager.settings.leak_sentinel_enabled

## One full check (public so the LEAK CANARY suite can drive the strike logic directly).
## Returns the unreachable-card count.
func tick() -> int:
	var alive := _alive_cards()
	var reachable := _reachable_set()
	var unreachable : Array[CardData] = []
	for card : CardData in alive:
		if not reachable.has(card):
			unreachable.append(card)
	var s : PlayerSettings = SettingsManager.settings
	if unreachable.size() > s.leak_sentinel_slack:
		_strikes += 1
		if _strikes >= s.leak_sentinel_strikes:
			push_error("LeakSentinel: %d CardData alive, %d reachable — %d unreachable for %d checks.\n%s"
					% [alive.size(), reachable.size(), unreachable.size(), _strikes,
					_histogram(unreachable)])
			_strikes = 0
	else:
		_strikes = 0
	return unreachable.size()

## Prune dead registry weakrefs without a full check. The LEAK CANARY suite calls this
## before each object count so benign registry growth (one WeakRef per card ever built,
## normally pruned on the sentinel's own ticks) can't fail its growth assertions.
func prune() -> void:
	var _alive := _alive_cards()

# Prune dead weakrefs from the registry and return the cards still alive.
func _alive_cards() -> Array[CardData]:
	var kept : Array[WeakRef] = []
	var out : Array[CardData] = []
	for ref : WeakRef in CardData.sentinel_registry:
		var card : CardData = ref.get_ref() as CardData
		if card:
			kept.append(ref)
			out.append(card)
	CardData.sentinel_registry = kept
	return out

# Every card reachable from a legitimate owner, as a Dictionary set.
func _reachable_set() -> Dictionary[CardData, bool]:
	var seen : Dictionary[CardData, bool] = {}
	# 1. the run document (Main.save_info always mirrors RunManager.run, but root both)
	_add_run_state(seen, Main.save_info)
	_add_run_state(seen, RunManager.run)
	# 2. RunManager's serialization-ready cached copies + any queued background payload
	_add_cards(seen, RunManager._saveable_deck)
	_add_cards(seen, RunManager._saveable_rules)
	if RunManager._saver_mutex != null:
		RunManager._saver_mutex.lock()
		_add_run_state(seen, RunManager._pending_payload)
		RunManager._saver_mutex.unlock()
	# 3. the live environment: board collections + undo history + the fallback Deck
	var game : Game = CardEnvironment.get_current_game()
	if game:
		_add_cards(seen, game.state.all_card_datas())
		for snap : GameData in game.save_history:
			_add_cards(seen, snap.all_card_datas())
		if game.deck:
			_add_cards(seen, game.deck.get_deck())
			_add_cards(seen, game.deck.get_rules())
	elif CardEnvironment.CURRENT:
		for collection : Variant in CardEnvironment.CURRENT.get_card_collections():
			_add_collection(seen, collection)
	# 4. open UI owners (viewers/pickers list live or preview decks)
	_scan_ui(seen, get_tree().root)
	return seen

func _add_run_state(seen: Dictionary[CardData, bool], rs: RunState) -> void:
	if rs == null: return
	_add_cards(seen, rs.card_datas)
	_add_cards(seen, rs.rule_datas)
	for snap : GameData in rs.game_history:
		_add_cards(seen, snap.all_card_datas())

func _add_cards(seen: Dictionary[CardData, bool], cards: Array[CardData]) -> void:
	for card : CardData in cards:
		seen[card] = true

# A get_card_collections entry: Array[CardData] or Array[ArrayCardData] (zone columns).
func _add_collection(seen: Dictionary[CardData, bool], collection: Variant) -> void:
	if collection is not Array: return
	for entry : Variant in collection as Array:
		if entry is CardData:
			seen[entry as CardData] = true
		elif entry is ArrayCardData:
			_add_cards(seen, (entry as ArrayCardData).datas)

# Walk the tree for the UI owners that hold card lists while open.
func _scan_ui(seen: Dictionary[CardData, bool], node: Node) -> void:
	if node is DeckViewer:
		_add_cards(seen, (node as DeckViewer).deck)
	elif node is DeckPicker:
		var picker : DeckPicker = node
		for entry : Dictionary in picker._deck.get_deck_list():
			_add_cards(seen, entry["cards"] as Array[CardData])
		if picker._rules_built:
			_add_cards(seen, picker._deck.get_rules())
	elif node is MapHoverPanel:
		_add_cards(seen, (node as MapHoverPanel)._preview_cards)
	elif node is ChoiceViewer:
		var viewer : ChoiceViewer = node
		if viewer.data:
			_add_cards(seen, viewer.data.current_choices)
	for child : Node in node.get_children():
		_scan_ui(seen, child)

# The report body: unreachable cards bucketed by stage + modifier class names, count-sorted.
func _histogram(cards: Array[CardData]) -> String:
	var buckets : Dictionary[String, int] = {}
	for card : CardData in cards:
		var mods : Array[String] = []
		for mod : CardModifier in [card.skill, card.type, card.stamp, card.suit]:
			if mod: mods.append((mod.get_script() as Script).resource_path.get_file())
		for st : CardModifierStatus in card.statuses:
			mods.append((st.get_script() as Script).resource_path.get_file())
		var key := "%s [%s]" % [CardData.Stage.find_key(card.stage), ", ".join(mods)]
		buckets[key] = buckets.get(key, 0) + 1
	var lines : Array[String] = []
	for key : String in buckets:
		lines.append("  %3dx %s" % [buckets[key], key])
	lines.sort()
	lines.reverse()
	return "\n".join(lines)

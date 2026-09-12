extends CardEnvironment
class_name Map

## The world-map screen: hosts the WorldMapController (worldgen addon + token traversal),
## resolves node arrivals into games / booster packs, shows the node hover panel, and is
## the CardEnvironment the booster generation mods run against (collections = the run
## deck in Main.save_info).

signal enter_game

@onready var controller: WorldMapController = %WorldMapController
@onready var ui_layer: CanvasLayer = $UI
## Hovering a map node PUBLISHES its `InfoEntry` and stops there. ⚠ The map must NOT mount an
## `InfoCard` of its own: there is ONE card, on the wall's overlay, anchored to the WINDOW, and a
## second instance is not what `Main` resets, so it could never be dismissed. `Main` decides
## whether Info mode wants this shown.
## `MapHoverPanel`'s SCENE is no longer instantiated on the map; the class stays as `get_info()`'s
## home.
signal info_hovered(entry: InfoEntry)

# Set by `Main` before this screen's picture is built, the same hand-over `GameView.hud_container`
# gets. Fame/Lap/Luck/the Deck button live on its `MapHud` child, not on this scene's own `$UI`.
var hud_container : HudContainer = null

var run : RunState = null
# start_run can arrive before this scene ever entered the tree (Main pre-instantiates it);
# the pending run is consumed by _ready.
var _pending_run : RunState = null

func get_card_collections() -> Array:
	return [
		Main.save_info.card_datas,
		Main.save_info.rule_datas
	]

func get_rules_collections() -> Array[CardData]:
	return Main.save_info.rule_datas

func _ready() -> void:
	_bind_hud_container()
	controller.node_entered.connect(_on_node_entered)
	controller.node_hovered.connect(_on_node_hovered)
	# Deliberately NO node_unhovered connection: the card keeps showing its last entry across
	# empty hover rather than blinking out, the same persistence contract Info mode's card uses.
	controller.map_ready.connect(_update_hud)
	if _pending_run:
		var pending := _pending_run
		_pending_run = null
		start_run(pending)

const HUD_CONTAINER_SCENE := preload("res://UI/hud_container.tscn")

# Same hand-over shape as `GameView._bind_hud_container()`: a standalone fixture with no `Main`
# gets its own private container instead of a null one.
func _bind_hud_container() -> void:
	if hud_container == null:
		hud_container = HUD_CONTAINER_SCENE.instantiate() as HudContainer
		add_child(hud_container)
	_connect_container(hud_container.map_deck_button.pressed, _on_deck_clicked)
	_connect_container(hud_container.container_rect_changed, _publish_map_inset)
	_publish_map_inset()

# The container OUTLIVES this screen in the real game, but a test may `remove_child` a standalone
# `Map` -- same teardown shape as `GameView._exit_tree()`.
var _container_connections : Array[Array] = []

func _connect_container(sig: Signal, callable: Callable) -> void:
	sig.connect(callable)
	_container_connections.append([sig, callable])

func _exit_tree() -> void:
	for pair : Array in _container_connections:
		var sig : Signal = pair[0] as Signal
		var callable : Callable = pair[1] as Callable
		if sig.is_connected(callable):
			sig.disconnect(callable)

# The map has no picture to convert through: `container_px` is handed to the controller's camera
# offset directly, in window px, with no `picture_scale` division.
func _publish_map_inset() -> void:
	var window := hud_container.get_viewport().get_visible_rect().size
	var rect := hud_container.container_rect()
	if HudContainer.container_is_top(window, SettingsManager.settings):
		controller.apply_container_inset(Vector2(0.0, rect.size.y))
	else:
		controller.apply_container_inset(Vector2(rect.size.x, 0.0))

# Begin (or resume) a run on this map screen. Safe to call before the scene is in the
# tree — the map generates/reloads once _ready has run.
func start_run(new_run: RunState) -> void:
	run = new_run
	if not is_node_ready():
		_pending_run = new_run
		return
	controller.start_run(new_run)

## Node arrival dispatch: games (incl. the lap-target boss) launch a show, boosters open
## a take-all pack, the lap-origin anchor is just a rest stop.
func _on_node_entered(node: WorldGraphNode) -> void:
	var role :String= node.meta.get(MapNodeRoles.ROLE_KEY, "")
	if role == MapNodeRoles.ROLE_BOOSTER:
		await _open_booster(node)
	elif role == MapNodeRoles.ROLE_GAME or node == controller.lap_target():
		_start_show(node)
	else:
		RunManager.save_run()
	_update_hud()

# A game node (or the boss anchor): stash the goal + node for Game._ready (persisted, so
# a quit mid-show resumes into this game) and switch scenes.
func _start_show(node: WorldGraphNode) -> void:
	run.pending_goal = node.meta.get(MapNodeRoles.GOAL_KEY,
			maxi(int(SettingsManager.settings.goal_g0), 1))
	run.pending_node_id = node.id
	RunManager.save_run()
	enter_game.emit()

# Booster node: all generated cards are force-added on confirm (rerolls/extra picks come
# later from modifiers).
func _open_booster(node: WorldGraphNode) -> void:
	var booster: BoosterTemplate = node.meta.get(MapNodeRoles.BOOSTER_KEY)
	var viewer := await booster.on_map_picked(ui_layer)
	viewer.confirmed.connect(_on_booster_confirmed)

func _on_booster_confirmed(cards: Array[CardData]) -> void:
	for card in cards:
		Main.save_info.card_datas.append(card)
	RunManager.mark_deck_dirty()  # run deck grew
	RunManager.save_run()
	_update_hud()

## Called by Main when a won game hands back to the map: clear the pending show, complete
## the lap if the resolved node was the lap-target boss, persist. Boss-ness is derived
## from the persisted pending_node_id (not a transient flag), so it survives quit/resume.
func returned_from_game() -> void:
	var was_boss := run.pending_node_id == controller.lap_target().id
	run.pending_goal = 0
	run.pending_node_id = -1
	if was_boss:
		_show_lap_summary()
	else:
		RunManager.save_run()
	_update_hud()

# Lap complete: summary popup, then reverse direction and rescale goals on continue.
func _show_lap_summary() -> void:
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	var box := VBoxContainer.new()
	panel.add_child(box)
	var label := Label.new()
	label.text = "Tour complete!\nFame: %d\nThe tour now runs back the other way — shows get bigger." % run.fame
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(label)
	var button := Button.new()
	button.text = "Continue tour"
	box.add_child(button)
	ui_layer.add_child(panel)
	button.pressed.connect(func() -> void:
		panel.queue_free()
		controller.on_lap_completed()
		RunManager.save_run()
		_update_hud())

## Routes through `get_info()` rather than `MapHoverPanel.show_for_node()`, and only PUBLISHES the
## entry: the card anchors itself to the WINDOW's bottom, not the node's screen position, so there
## is no placement to compute here, and the map has no business deciding whether Info mode wants
## it shown.
func _on_node_hovered(node: WorldGraphNode) -> void:
	# Published regardless: `Main` decides whether Info mode wants it, and the map has no business
	# knowing. `wall_screen_popups` governs the map's own panel, which no longer exists as a live
	# scene — so there is nothing to suppress here today. See `PlayArea._popups_allowed()`.
	info_hovered.emit(MapHoverPanel.get_info(node, run, controller.lap_target()))

func _update_hud() -> void:
	if run == null: return
	hud_container.fame_label.text = "Fame: %d" % run.fame
	hud_container.lap_label.text = "Lap: %d %s" % [run.lap + 1, "◀" if run.is_reversed() else "▶"]
	hud_container.luck_label.text = "Luck: %d%%" % int(RunManager.luck() * 100.0)

func _on_deck_clicked() -> void:
	DeckViewer.show_deck(self, Main.save_info.card_datas)

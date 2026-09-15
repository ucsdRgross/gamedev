extends CardEnvironment
class_name Map

## The world-map screen: hosts the WorldMapController (worldgen addon + token traversal),
## resolves node arrivals into games / booster packs, names the hovered node on the map, and is
## the CardEnvironment the booster generation mods run against (collections = the run
## deck in Main.save_info).

signal enter_game

@onready var controller: WorldMapController = %WorldMapController
@onready var ui_layer: CanvasLayer = $UI
@onready var name_popup: MapNamePopup = %NamePopup
## Published and nothing more: the wall's one `HudContainer` decides what is shown.
signal info_hovered(entry: InfoEntry)

# Set by `Main` before this screen's picture is built, the same hand-over `GameView.hud_container`
# gets. Fame/Lap/Luck/the Deck button live on its `MapHud` child, not on this scene's own `$UI`.
var hud_container : HudContainer = null

# Set by `Main` alongside `hud_container`, the same hand-over `Menu.wall_picture` gets -- lets
# `_publish_map_inset()` convert `hud_container`'s rects into this picture's own space.
var wall_picture : WallPicture = null

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

# Same hand-over shape as `GameView._bind_hud_container()`: a standalone fixture with no `Main`
# gets its own private container instead of a null one.
func _bind_hud_container() -> void:
	hud_container = HudContainer.ensure(hud_container, self)
	hud_container.connect_for_screen(self, hud_container.map_deck_button.pressed,
			_on_deck_clicked)
	hud_container.connect_for_screen(self, hud_container.container_rect_changed, _publish_map_inset)
	hud_container.connect_for_screen(self, hud_container.active_screen_changed,
			name_popup.hide_name)
	_publish_map_inset()

# The map DOES sit in a `WallPicture`, so the container's window px converts through that picture's
# own cover scale -- `HudContainer.rect_beside()` is that one conversion, shared with `Menu`.
func _publish_map_inset() -> void:
	var remaining := hud_container.rect_beside(wall_picture)
	var screen_size := controller.camera.get_viewport_rect().size
	controller.apply_container_shift(screen_size / 2.0 - remaining.get_center())

# Begin (or resume) a run on this map screen. Safe to call before the scene is in the tree. The
# map persists across runs but its content is the run, so the last run's description goes here.
func start_run(new_run: RunState) -> void:
	run = new_run
	if not is_node_ready():
		_pending_run = new_run
		return
	name_popup.hide_name()
	hud_container.release_screen(HudContainer.MAP_SCREEN)
	controller.start_run(new_run)

## Node arrival dispatch: games (incl. the lap-target boss) launch a show, boosters open
## a take-all pack, the lap-origin anchor is just a rest stop.
func _on_node_entered(node: WorldGraphNode) -> void:
	name_popup.hide_name()
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
	var viewer : ChoiceViewer = await booster.on_map_picked(ui_layer)
	viewer.confirmed.connect(_on_booster_confirmed)
	hud_container.host_viewer(viewer, wall_picture, info_hovered)

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

# The description goes to the container, which anchors itself and needs no placement from here.
# The NAME is anchored to the node itself, because a map node is a bare dot: the same entry feeds
# both, so the two can never disagree about what the node is called.
func _on_node_hovered(node: WorldGraphNode) -> void:
	var entry := MapHoverPanel.get_info(node, run, controller.lap_target())
	info_hovered.emit(entry)
	name_popup.show_above(entry.title, node)

func _update_hud() -> void:
	if run == null: return
	hud_container.fame_label.text = "Fame: %d" % run.fame
	hud_container.lap_label.text = "Lap: %d %s" % [run.lap + 1, "◀" if run.is_reversed() else "▶"]
	hud_container.luck_label.text = "Luck: %d%%" % int(RunManager.luck() * 100.0)

func _on_deck_clicked() -> void:
	hud_container.host_viewer(DeckViewer.show_deck(self, Main.save_info.card_datas,
			hud_container.map_deck_button), wall_picture, info_hovered)

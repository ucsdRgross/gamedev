extends CardEnvironment
class_name Map

## The world-map screen: it is the CardEnvironment the booster generation mods run against, its collections being the run deck in Main.save_info.

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

# No node_unhovered connection on purpose: the card keeps showing its last entry across empty
# hover rather than blinking out.
func _ready() -> void:
	_bind_hud_container()
	controller.node_entered.connect(_on_node_entered)
	controller.node_hovered.connect(_on_node_hovered)
	controller.node_selected.connect(_on_node_selected)
	controller.selection_cleared.connect(_on_selection_cleared)
	controller.travel_focus_requested.connect(travel_button.grab_focus)
	controller.map_ready.connect(_update_hud)
	controller.map_ready.connect(_publish_map_inset)
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
	hud_container.connect_for_screen(self, hud_container.active_screen_changed,
			controller.clear_selection)
	hud_container.connect_for_screen(self, hud_container.description_dismissed,
			controller.clear_selection)
	_build_selection_buttons()
	_publish_map_inset()

## The row of buttons the sidebar shows BESIDE a picked node's description -- this screen's, hung in the panel and hidden whenever nothing is picked. It FLOWS, the sidebar being narrow enough that three buttons do not fit on one line.
var selection_buttons : HFlowContainer = null

## Travels to the picked node. Also where accept on the map hands the pad, a map node being no Control.
var travel_button : Button = null

## Opens the run deck from the description side, the MapHud's own Deck button being hidden while a description shows.
var selection_deck_button : Button = null

## Shows the picked pack's possible contents again -- only a pack node has one.
var possible_cards_button : Button = null

# THE SIDEBAR CARRIES THE HUD OR THE DESCRIPTION AND NEVER BOTH, so the buttons a picked node needs
# are the DESCRIPTION's, built here and owned here: the panel is handed a row and never learns what
# any of it does.
func _build_selection_buttons() -> void:
	selection_buttons = HFlowContainer.new()
	selection_buttons.visible = false
	selection_buttons.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	travel_button = _add_selection_button('MAP_TRAVEL', _on_travel_pressed)
	selection_deck_button = _add_selection_button('MAP_DECK', _on_deck_clicked)
	possible_cards_button = _add_selection_button('MAP_POSSIBLE_CARDS', _on_possible_cards_pressed)
	hud_container.mount_description_buttons(selection_buttons)

func _add_selection_button(key: StringName, on_pressed: Callable) -> Button:
	var button := Button.new()
	button.text = TRANSLATION.find(key)
	button.pressed.connect(on_pressed)
	selection_buttons.add_child(button)
	return button

# The row is the PANEL's child once it is mounted, so a teardown that takes the container first
# leaves nothing to free -- measured as orphaned nodes everywhere else this container outlives a screen.
func _exit_tree() -> void:
	if is_instance_valid(selection_buttons) and selection_buttons.get_parent() == null:
		selection_buttons.queue_free()

func _on_travel_pressed() -> void:
	controller.move_to(controller.selected())

func _on_possible_cards_pressed() -> void:
	await _show_possible_cards(controller.selected())

# The map DOES sit in a `WallPicture`, so the container's window px converts through that picture's
# own cover scale -- `HudContainer.rect_beside()` is that one conversion, shared with `Menu`. Also
# re-run on `map_ready`: the shift is divided by a zoom that only settles once the world exists.
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
	_packs_shown.clear()
	hud_container.release_screen(HudContainer.MAP_SCREEN)
	controller.start_run(new_run)

## Node arrival dispatch: a game or the lap-target boss launches a show, a booster opens a take-all pack, the lap-origin anchor is just a rest stop.
func _on_node_entered(node: WorldGraphNode) -> void:
	name_popup.hide_name()
	_packs_shown.clear()
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
	RunManager.mark_deck_dirty()
	RunManager.save_run()
	_update_hud()

## Called by Main when a won game hands back to the map; boss-ness is derived from the persisted pending_node_id, not a transient flag, so it survives quit/resume.
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

# A HOVER ONLY NAMES: the sidebar describes what the player PICKED, so passing the cursor over a
# neighbour can never leave the description and the Travel button aimed at different nodes.
func _on_node_hovered(node: WorldGraphNode) -> void:
	name_popup.show_above(_info_for(node).title, node)

# The description goes to the container, which anchors itself and needs no placement from here.
# The NAME is anchored to the node itself, because a map node is a bare dot: the same entry feeds
# both, so the two can never disagree about what the node is called.
func _on_node_selected(node: WorldGraphNode) -> void:
	var entry := _info_for(node)
	info_hovered.emit(entry)
	name_popup.show_above(entry.title, node)
	selection_buttons.visible = true
	possible_cards_button.visible = _booster_of(node) != null
	await _open_possible_cards_once(node)

# Back to the basic view: the HUD, with its own Deck button, and no row of the description's buttons
# left in anyone's focus chain.
func _on_selection_cleared() -> void:
	selection_buttons.visible = false
	name_popup.hide_name()
	if hud_container.showing_description(): hud_container.show_hud()

## The pack nodes whose contents have already been shown where the token stands -- cleared by travelling and by a new run, which is what "before travelling" means.
var _packs_shown : Dictionary[int, bool] = {}

# THE FIRST PICK OF A PACK NODE LISTS ITS CONTENTS AND NO LATER ONE DOES: the sidebar is too small
# to read them in, and re-opening a viewer the player has just closed would fight them. The button
# stays, so they can ask again whenever they want.
func _open_possible_cards_once(node: WorldGraphNode) -> void:
	if _booster_of(node) == null or _packs_shown.has(node.id): return
	_packs_shown[node.id] = true
	await _show_possible_cards(node)

# Every card this pack could roll, in the SAME viewer the run deck opens in and hosted the same way,
# so its cards publish to the sidebar as any viewer's do. Closing it comes back to the node.
func _show_possible_cards(node: WorldGraphNode) -> void:
	var cards := await _booster_of(node).get_possible_preview_cards()
	_host_map_viewer(DeckViewer.show_deck(self, cards, possible_cards_button))

# ⚠ HOSTED FIRST, REPUBLISHED SECOND: the container's close handler takes the viewer's card out of
# the sidebar, so a pick put back before it would be wiped by it. The pick is what every viewer
# this screen opens comes back to.
func _host_map_viewer(viewer: DeckViewer) -> void:
	if viewer == null: return
	selection_buttons.visible = false
	hud_container.host_viewer(viewer, wall_picture, info_hovered)
	viewer.highlight_cleared.connect(_republish_the_pick)

# Nothing picked is the HUD's own Deck button opening the viewer from the basic view; the container
# takes itself back to the HUD and there is no description to return to.
func _republish_the_pick() -> void:
	var picked := controller.selected()
	selection_buttons.visible = picked != null
	if picked: info_hovered.emit(_info_for(picked))

func _info_for(node: WorldGraphNode) -> InfoEntry:
	return MapHoverPanel.get_info(node, run, controller.lap_target())

## The pack `node` opens on arrival, or null for every node that is not a talent pack.
func _booster_of(node: WorldGraphNode) -> BoosterTemplate:
	return node.meta.get(MapNodeRoles.BOOSTER_KEY)

func _update_hud() -> void:
	if run == null: return
	hud_container.fame_label.text = "Fame: %d" % run.fame
	hud_container.lap_label.text = "Lap: %d %s" % [run.lap + 1, "◀" if run.is_reversed() else "▶"]
	hud_container.luck_label.text = "Luck: %d%%" % int(RunManager.luck() * 100.0)

# The run deck is reachable from the basic view AND from beside a pick, so the viewer is handed
# whichever of the two buttons actually opened it to put a pad player's focus back on.
func _on_deck_clicked() -> void:
	var opener : Button = selection_deck_button if selection_buttons.visible \
			else hud_container.map_deck_button
	_host_map_viewer(DeckViewer.show_deck(self, Main.save_info.card_datas, opener))

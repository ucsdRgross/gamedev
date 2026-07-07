class_name MapHoverPanel
extends PanelContainer

## Tooltip panel for world-map nodes (lives on the map's UI CanvasLayer, so the map
## camera never drags it): shows the node kind + biome, the fame requirement for shows,
## and for booster nodes the pack's POSSIBLE contents as preview cards in a scrollable
## strip. The panel stays open while the cursor is over it (so the preview cards can be
## hovered/focused to inspect their modifiers via ControlCard.describe_card in %CardInfo),
## and only hides once the cursor is off BOTH the node and the panel for the grace period.
## Visibility is polled by rect in _process because the panel's own mouse_entered never
## fires — the child containers cover it.

const MOUSE_OFFSET := Vector2(24, 12)
## Keep the panel this far from the screen edges (so it never touches an edge).
const SCREEN_MARGIN := Vector2(24, 24)
## Grace after leaving the node/panel before hiding, so the cursor can cross the gap.
const HIDE_GRACE_MS := 350.0

@onready var title_label: Label = %Title
@onready var info_label: Label = %Info
@onready var cards_scroll: ScrollContainer = %CardsScroll
@onready var cards_flow: FlowContainer = %Cards
@onready var card_info: Label = %CardInfo

# A node is currently hovered (keeps the panel open regardless of cursor position).
var _engaged : bool = false
# msec timestamp to hide at; < 0 = not scheduled.
var _hide_at : float = -1.0

## Populate and place the panel for `node` beside `anchor_screen_pos` (the node's screen
## position — correct for both mouse hover and keyboard selection). `lap_target` marks
## the boss anchor.
func show_for_node(node: WorldGraphNode, run: RunState, lap_target: WorldGraphNode,
		anchor_screen_pos: Vector2) -> void:
	_engaged = true
	_hide_at = -1.0
	_clear_cards()
	var role :String= node.meta.get(MapNodeRoles.ROLE_KEY, "")
	var lines: Array[String] = []
	var biome_name :String= node.meta.get("biome_name", "")
	if biome_name:
		lines.append(biome_name)
	var booster: BoosterTemplate = null
	if role == MapNodeRoles.ROLE_BOOSTER:
		title_label.text = "Talent pack"
		lines.append("Take all %d cards into your deck.\nPossible contents:" % 5)
		booster = node.meta.get(MapNodeRoles.BOOSTER_KEY)
	elif role == MapNodeRoles.ROLE_ANCHOR and node != lap_target:
		title_label.text = "Rest stop"
		lines.append("The tour %s here. Nothing to perform." % ("turns around" if run.lap > 0 else "starts"))
	else:
		title_label.text = "Final show" if node == lap_target else "Show"
		lines.append("Fame required: %d" % (node.meta.get(MapNodeRoles.GOAL_KEY, 0) as int))
		lines.append("3 acts to reach it — or the tour ends.")
	info_label.text = "\n".join(lines)
	cards_scroll.visible = booster != null
	visible = true
	# Clamp inside the screen margin (never touches an edge); position BEFORE the preview
	# cards spawn so their visuals anchor to the final layout (no fly-in).
	reset_size()
	var vp := get_viewport_rect().size
	position = (anchor_screen_pos + MOUSE_OFFSET).clamp(SCREEN_MARGIN, vp - size - SCREEN_MARGIN)
	if booster:
		_populate_cards.call_deferred(booster)

# One frame later than show_for_node (call_deferred) so the containers are laid out
# before the CardVisuals pick their anchor positions.
func _populate_cards(booster: BoosterTemplate) -> void:
	if not visible or not cards_scroll.visible:
		return
	for data in booster.get_possible_preview_cards():
		var card := ControlCard.add_child_control_card(
			cards_flow, data, CardVisual.DisplayContext.DECK_VIEWER)
		card.mouse_entered.connect(_on_card_inspected.bind(data))
		card.focus_entered.connect(_on_card_inspected.bind(data))

## Inspector: hovering/focusing a preview card explains its parts via their own
## get_str/get_description.
func _on_card_inspected(data: CardData) -> void:
	card_info.text = ControlCard.describe_card(data)
	card_info.visible = not card_info.text.is_empty()

## The node is no longer hovered (node_unhovered): start the hide grace unless the cursor
## is over the panel.
func request_hide() -> void:
	_engaged = false

func _process(_delta: float) -> void:
	if not visible:
		return
	if _engaged or _mouse_over_panel():
		_hide_at = -1.0
		return
	# Off both the node and the panel: schedule, then hide once the grace elapses.
	if _hide_at < 0.0:
		_hide_at = Time.get_ticks_msec() + HIDE_GRACE_MS
	elif Time.get_ticks_msec() >= _hide_at:
		hide_panel()

func _mouse_over_panel() -> bool:
	return get_global_rect().has_point(get_global_mouse_position())

func hide_panel() -> void:
	_engaged = false
	_hide_at = -1.0
	visible = false
	_clear_cards()

func _clear_cards() -> void:
	card_info.text = ""
	card_info.visible = false
	for child in cards_flow.get_children():
		cards_flow.remove_child(child)
		child.queue_free()

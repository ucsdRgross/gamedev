class_name ControlCard
extends Control

const CONTROL_CARD := preload("uid://dbmfhito00wc")

var child : CardVisual

# A card is a focus stop for key/pad play: the arrows navigate the board through Godot's own
# spatial neighbour search, and a focused card lights up exactly as a hovered one does.
func _ready() -> void:
	SettingsManager.settings_changed.connect(set_min_size)
	set_min_size()
	focus_mode = Control.FOCUS_ALL
	focus_entered.connect(_set_child_focus.bind(true))
	focus_exited.connect(_set_child_focus.bind(false))

func _set_child_focus(value: bool) -> void:
	if child:
		child.focused = value

func set_min_size() -> void:
	if child:
		custom_minimum_size = child.card_size

# ⚠ THE SIZE GOES ON THE CARD ITSELF, never on a scale above it: a Container resets a child's
# `scale` every layout pass and `CardVisual._ready()` re-runs `recalculate_size()`, undoing both.
func size_preview_to(px: Vector2) -> void:
	child.preview_size = px
	child.recalculate_size()
	set_min_size()

static func add_child_control_card(parent:Node,connected_data:CardData, context:CardVisual.DisplayContext) -> ControlCard:
	var new_control : ControlCard = CONTROL_CARD.instantiate()
	var card : CardVisual = CardVisual.add_child_card_visual(
		new_control, connected_data, context, new_control)
	new_control.child = card
	new_control.set_min_size()
	parent.add_child(new_control)
	return new_control

## The one human-readable summary of a card's parts, shared by every surface that describes a card: rank, suit and each NAMED modifier, a nameless one being a bare dash.
static func describe_card(data: CardData) -> String:
	var lines : Array[String] = []
	if data.rank: lines.append(data.rank.get_str())
	if data.suit: lines.append("%s — %s" % [data.suit.get_str(), data.suit.get_description()])
	for mod : CardModifier in [data.skill, data.stamp, data.type]:
		if mod and not mod.get_str().is_empty():
			lines.append("%s — %s" % [mod.get_str(), mod.get_description()])
	for status : CardModifierStatus in data.statuses:
		lines.append("%s ×%d — %s" % [status.get_str(), status.stacks, status.get_description()])
	return "\n".join(lines)

class_name ControlCard
extends Control

const CONTROL_CARD := preload("uid://dbmfhito00wc")

var child : CardVisual

func _ready() -> void:
	SettingsManager.settings_changed.connect(set_min_size)
	set_min_size()
	# Keyboard/controller support: cards are focus stops (arrow keys use Godot's spatial
	# neighbor search) and light up like the mouse hover does.
	focus_mode = Control.FOCUS_ALL
	focus_entered.connect(_set_child_focus.bind(true))
	focus_exited.connect(_set_child_focus.bind(false))

func _set_child_focus(value: bool) -> void:
	if child:
		child.focused = value

func set_min_size() -> void:
	if child:
		custom_minimum_size = child.card_size

static func add_child_control_card(parent:Node,connected_data:CardData, context:CardVisual.DisplayContext) -> ControlCard:
	var new_control : ControlCard = CONTROL_CARD.instantiate()
	var card : CardVisual = CardVisual.add_child_card_visual(
		new_control, connected_data, context, new_control)
	new_control.child = card
	new_control.set_min_size()
	parent.add_child(new_control)
	return new_control

## Human-readable summary of a card's parts (rank/suit + each modifier's name and
## description) — the shared text for inspector tooltips over preview cards.
static func describe_card(data: CardData) -> String:
	var lines : Array[String] = []
	if data.rank: lines.append(data.rank.get_str())
	if data.suit: lines.append(data.suit.get_str())
	for mod : CardModifier in [data.skill, data.stamp, data.type]:
		# Skip nameless modifiers (e.g. TypePaper) so they don't render a blank " — " line.
		if mod and not mod.get_str().is_empty():
			lines.append("%s — %s" % [mod.get_str(), mod.get_description()])
	return "\n".join(lines)

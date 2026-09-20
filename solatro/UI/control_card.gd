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

## The description's large font: the title's size, which every effect NAME shares.
const NAME_FONT_SIZE := 20

## The card's title -- "<Rank> of <Suit>", or whichever of the two a face card carries on its own.
static func card_title(data: CardData) -> String:
	if data.rank and data.suit:
		return TRANSLATION.find('CARD_TITLE') % [data.rank.get_str(), data.suit.get_str()]
	if data.rank: return data.rank.get_str()
	if data.suit: return data.suit.get_str()
	return ""

## One effect, for a surface that reads BBCode: its NAME in the large font, its description under it.
static func _effect_block(name_text: String, description: String) -> String:
	return "[font_size=%d]%s[/font_size]\n%s" % [NAME_FONT_SIZE, name_text, description]

## The one human-readable summary of a card, shared by every surface that describes one: the title on the first line, then one block per suit, NAMED skill, stamp, status and type.

# The SUIT keeps a block although the ruling's list of blocks does not name it: the title carries
# its NAME only, and its description is where a card's own prop effect is written down.

static func describe_card(data: CardData) -> String:
	var lines : Array[String] = [card_title(data)]
	if data.suit:
		lines.append(_effect_block(data.suit.get_str(), data.suit.get_description()))
	for mod : CardModifier in [data.skill, data.stamp]:
		if mod and not mod.get_str().is_empty():
			lines.append(_effect_block(mod.get_str(), mod.get_description()))
	for status : CardModifierStatus in data.statuses:
		lines.append(_effect_block("%s ×%d" % [status.get_str(), status.stacks],
				status.get_description()))
	if data.type and not data.type.get_str().is_empty():
		lines.append(_effect_block(data.type.get_str(), data.type.get_description()))
	return "\n".join(lines)

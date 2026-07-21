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
	# Suit now describes its prop effect too (Phase 5): "Knife — <what it does>".
	if data.suit: lines.append("%s — %s" % [data.suit.get_str(), data.suit.get_description()])
	# Patience (2026-07-20): inside a show with unique-tracking on, each modifier line says
	# whether the audience has already seen it this round (a seen mod no longer holds patience).
	# Preview contexts (booster/deck viewers, no Game) show nothing.
	var g := CardEnvironment.get_current_game()
	var show_seen := g != null and SettingsManager.settings.patience_track_uniques
	for mod : CardModifier in [data.skill, data.stamp, data.type]:
		# Skip nameless modifiers (e.g. TypePaper) so they don't render a blank " — " line.
		if mod and not mod.get_str().is_empty():
			lines.append("%s — %s%s" % [mod.get_str(), mod.get_description(),
					_seen_marker(g, mod) if show_seen else ""])
	# One line per active status: "Juggling ×2 — <effect>".
	for status : CardModifierStatus in data.statuses:
		lines.append("%s ×%d — %s%s" % [status.get_str(), status.stacks, status.get_description(),
				_seen_marker(g, status) if show_seen else ""])
	return "\n".join(lines)

## " (seen)" / " (new)" for one modifier, keyed the same way the patience seen-set is
## (CardModifier.combo_key). Modifiers that opt out of combo (empty key) show no marker.
static func _seen_marker(g: Game, mod: CardModifier) -> String:
	var key := mod.combo_key()
	if key.is_empty(): return ""
	return " " + TRANSLATION.find('PATIENCE_SEEN' if g.state.patience_seen_mods.has(key)
			else 'PATIENCE_UNSEEN')

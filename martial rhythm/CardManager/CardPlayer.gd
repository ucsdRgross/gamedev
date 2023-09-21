extends Control

@onready var left := %Left
@onready var right := %Right
@onready var deck := %Deck

const card := preload("res://CardManager/card.tscn")


# Called when the node enters the scene tree for the first time.
func _ready():
	randomize()

	for p in [left, right, deck]:
		for c in p.get_children():
			c.free()
		
	for i in range(50):
		var new_card := card.instantiate()
		var rect := new_card.get_child(0)
		rect.texture.region = Rect2((randi() % 14) * 16, 0, 16, 16)
		deck.add_child(new_card)
		
	for h in [left, right]:
		if deck.get_child_count() > 0:
			deck.get_child(0).reparent(h, false)

func _input(event):
	if visible:
		if event.is_action_pressed("LClick"):
			if not play_card(left):
				play_card(right)
		elif event.is_action_pressed("RClick"):
			if not play_card(right):
				play_card(left)

func play_card(hand : Control) -> bool:
	var played := false
	if hand.get_child_count() > 0:
		hand.get_child(0).free()
		played = true
	if deck.get_child_count() > 0:
		deck.get_child(0).reparent(hand, false)
		hand.get_child(0).position = Vector2.ZERO
	return played

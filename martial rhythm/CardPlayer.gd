extends Control

@onready var left := %Left
@onready var right := %Right
@onready var deck := %Deck

const card := preload("res://card.tscn")

signal hand_empty

# Called when the node enters the scene tree for the first time.
func _ready():

	clear_hand()
		
#	for i in range(50):
#		var new_card := card.instantiate()
#		var rect := new_card.get_child(0)
#		rect.texture.region = Rect2((randi() % 14) * 16, 0, 16, 16)
#		deck.add_child(new_card)
		


func _input(event):
	if visible:
		if event.is_action_pressed("LClick"):
			if not play_card(left):
				play_card(right)
			check_hand_empty()
		elif event.is_action_pressed("RClick"):
			if not play_card(right):
				play_card(left)
			check_hand_empty()
	
func check_hand_empty():
	if left.get_child_count() + right.get_child_count() == 0:
		hand_empty.emit()

func play_card(hand : Control) -> bool:
	var played := false
	if hand.get_child_count() > 0:
		hand.get_child(0).free()
		played = true
	if deck.get_child_count() > 0:
		deck.get_child(0).reparent(hand, false)
		hand.get_child(0).position = Vector2.ZERO
	return played

func clear_hand():
	for p in [left, right, deck]:
		for c in p.get_children():
			c.free()

func fill_hand(cards : Array[Node]):
	for c in cards:
		deck.add_child(c)
	for h in [left, right]:
		if h.get_child_count() == 0 and deck.get_child_count() > 0:
			deck.get_child(0).reparent(h, false)

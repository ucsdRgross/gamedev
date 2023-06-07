extends Control

@onready var hand = $Cards/Hand
@onready var left = $Cards/Hand/Left
@onready var right = $Cards/Hand/Right
@onready var deck = $Cards/Deck

const card := preload("res://card.tscn")


# Called when the node enters the scene tree for the first time.
func _ready():
	randomize()

	for p in [left, right, deck]:
		for c in p.get_children():
			c.free()
		
	for i in range(50):
		var new_card := card.instantiate()
		var sprite := new_card.get_child(0)
		sprite.frame = randi() % 84
		deck.add_child(new_card)
		
	for h in [left, right]:
		if deck.get_child_count() > 0:
			deck.get_child(0).reparent(h, false)

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	
	if Input.is_action_just_pressed("LClick"):
		if left.get_child_count() > 0:
			left.get_child(0).free()
		if deck.get_child_count() > 0:
			deck.get_child(0).reparent(left, false)
	
	elif Input.is_action_just_pressed("RClick"):
		if right.get_child_count() > 0:
			right.get_child(0).free()
		if deck.get_child_count() > 0:
			deck.get_child(0).reparent(right, false)

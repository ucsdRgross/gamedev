extends Node3D
class_name Map

signal card_clicked(card:Card)

const CARD_CONTROL = preload("res://UI/card_control.tscn")
const CARD = preload("res://Cards/card.tscn")

var containers : Array 
var index_to_card : Dictionary
var card_to_index : Dictionary
var tween_transition : Tween
@onready var triangle_map: TriangleMap = $TiltedGUI/SubViewport/TriangleMap
#@onready var grid_container: GridContainer = $TiltedGUI/SubViewport/Map2D/GridContainer
@onready var preview_card: Card = $Preview/Card
@onready var preview_label: Label = $Preview/Label
@onready var flow_container: FlowContainer = %FlowContainer
@onready var deck_viewer: CanvasLayer = $DeckViewer

func _ready() -> void:
	triangle_map.card_clicked.connect(_on_card_clicked)
	triangle_map.card_hovered.connect(_on_card_hover_entered)
	#($Preview as Control).hide()
	preview_label.text = ""
	triangle_map.deck_clicked.connect(_on_deck_clicked)
	#containers = grid_container.get_children()
	#var cols : int = grid_container.columns
	#var i : int = 0
	#for c:Control in containers:
		#var card : Card = CARD.instantiate()
		#card.data = CardData.new()\
						#.with_suit(randi() % 4 + 1)\
						#.with_rank(randi() % 13 + 1)
		#card.can_move_anim = false
		#card.clicked.connect(_on_card_clicked)
		#card.hover_entered.connect(_on_card_hover_entered)
		#var zone : Card = c.get_child(0)
		#zone.front.self_modulate.a = 0
		#c.add_child(card)
		#zone.add_card(card)
		#var row := i / cols
		#var col := i % cols
		#card_to_index[card] = Vector2i(row,col)
		#index_to_card[Vector2i(row,col)] = card
		#i+=1
	#
	#for coord:Vector2i in [Vector2i(0,0),Vector2i(0,cols-1),Vector2i(cols-1,0),Vector2i(cols-1,cols-1)]:
		#index_to_card[coord].flipped = false

func _on_card_clicked(card : Card) -> void:
	#if card.flipped or (tween_transition and tween_transition.is_running()):
		#return
	#var surroundings : Array[Vector2i] = [#Vector2(-1,-1),
										#Vector2i(0,-1),
										##Vector2(1,-1),
										#Vector2i(-1,0),
										##Vector2(0,0),
										#Vector2i(1,0),
										##Vector2(-1,1),
										#Vector2i(0,1),
										##Vector2(1,1)
										#]
	card.z_index = card.num_cards
	tween_transition = create_tween()
	tween_transition.tween_property(card, 'scale', Vector2(2,2), 1).as_relative()
	#var cols : int = grid_container.columns
	#tween_transition.parallel().tween_property(card, 'global_position', (index_to_card[Vector2i(cols/2,cols/2)] as Card).global_position, 1)
	tween_transition.tween_callback(card.hide)
	tween_transition.tween_callback(func()->void: card_clicked.emit(card))
	add_card(card.data)
	#tween_transition.tween_callback(card.queue_free)
	
	#for s : Vector2i in surroundings:
		#var index : Vector2i = card_to_index[card] + s
		#if index in index_to_card:
			#var c : Card = index_to_card[index]
			#if c.flipped:
				#c.flipped = false
			#else:
				#c.flipped = true
				#var tween_hide := create_tween()
				#tween_hide.tween_property(c, 'rotation', (1 if randi() % 2 == 0 else -1) * TAU, 0.5).as_relative()
				#tween_hide.parallel().tween_property(c, "scale", Vector2(0.1,0.1), 0.5)
				#tween_hide.tween_callback(c.hide)
	#await tween_transition.finished

func _on_card_hover_entered(card : Card) -> void:
	if not card.flipped:
		preview_card.data = card.data
	preview_card.flipped = card.flipped
	preview_card.update_visual()
	var description : String
	if card.data.skill:
		description += card.data.skill.name + "\n" + card.data.skill.description + "\n"
	if card.data.stamp:
		description += card.data.stamp.name + "\n" + card.data.stamp.description + "\n"
	if card.data.type:
		description += card.data.type.name + "\n" + card.data.type.description + "\n"
	preview_label.text = description
	#($Preview as Control).show()

func add_card(data:CardData) -> void:
	var card : Card = CARD.instantiate()
	card.add_data(data)
	card.can_move_anim = false
	card.flipped = false
	var control : Control = CARD_CONTROL.instantiate()
	control.add_child(card)
	flow_container.add_child(control)
	
func _on_deck_clicked(card: Card) -> void:
	deck_viewer.show()

func _on_margin_container_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_event : InputEventMouseButton = event
		if mouse_event.button_index == MOUSE_BUTTON_LEFT and mouse_event.pressed:
			deck_viewer.hide()

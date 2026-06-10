# world_viewer.gd
extends Node2D

@onready var generator: WorldGenerator = $WorldGenerator
@onready var texture_rect: TextureRect = $CanvasLayer/TextureRect
@onready var label: Label = $CanvasLayer/Label

var current_view: String = "Heightmap"

func _ready() -> void:
	generator.generation_step_finished.connect(_on_step_finished)
	generator.generate_world_map()

func _on_step_finished(step_name: String) -> void:
	print("Finished step: ", step_name)
	label.text = "Last Step: " + step_name
	_update_display()

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_right"):
		_cycle_view()

func _cycle_view() -> void:
	match current_view:
		"Heightmap": current_view = "Biomes"
		"Biomes": current_view = "Heightmap"
	_update_display()

func _update_display() -> void:
	if current_view == "Heightmap":
		_display_heightmap()
	else:
		_display_biomemap()
	queue_redraw()

func _display_heightmap() -> void:
	if generator.height_map.is_empty(): return
	var img = Image.create(generator.settings.map_width, generator.settings.map_height, false, Image.FORMAT_RGB8)
	for pos in generator.height_map.keys():
		var val = generator.height_map[pos]
		img.set_pixel(pos.x, pos.y, Color(val, val, val))
	texture_rect.texture = ImageTexture.create_from_image(img)

func _display_biomemap() -> void:
	if generator.biome_map.is_empty(): return
	var img = Image.create(generator.settings.map_width, generator.settings.map_height, false, Image.FORMAT_RGB8)
	var colors = {
		"Ocean": Color.BLUE,
		"Arctic": Color.WHITE,
		"Tundra": Color.LIGHT_GRAY,
		"Desert": Color.YELLOW,
		"Rainforest": Color.DARK_GREEN,
		"Savanna": Color.GOLDENROD,
		"Forest": Color.GREEN
	}
	for pos in generator.biome_map.keys():
		var b = generator.biome_map[pos]
		img.set_pixel(pos.x, pos.y, colors.get(b, Color.BLACK))
	texture_rect.texture = ImageTexture.create_from_image(img)

func _draw() -> void:
	if generator.gameplay_graph.is_empty(): return
	
	# Draw edges
	for start_p in generator.gameplay_graph.keys():
		for end_p in generator.gameplay_graph[start_p]:
			draw_line(start_p, end_p, Color(1, 1, 1, 0.5), 2.0)
			
	# Draw nodes
	for node in generator.city_nodes:
		var color = Color.WHITE
		if node.distance_to(generator.start_node) < 1.0: color = Color.GREEN
		elif node.distance_to(generator.end_node) < 1.0: color = Color.RED
		draw_circle(node, 4.0, color)

extends Control

@onready var paint_root: Control = $PaintRoot
@onready var drawing_area: Panel = paint_root.drawing_area_bg
@onready var paint_control: Control = paint_root.paint_control
@onready var texture_rect: TextureRect = paint_root.texture
@onready var point_rect: TextureRect = $PaintRoot/HSplitContainer/DrawingAreaBG/TextureRect/TextureRect

@export var s : float = 1

class Point:
	var id : int
	var branches : Array[Point]
	var leafs : Array[Point]

class Circle:
	func _init(pos : Vector2, radius : float) -> void:
		self.pos = pos
		self.radius = radius
	var pos : Vector2
	var radius : float
	var color : Color = Color.GREEN

var img : Image
var point_img : Image
var first_point : Point
var circles : Array[Circle]

func _process(_delta):
	if Input.is_action_just_pressed("rightclick"):
		texture_rect.hide()
		await get_tree().process_frame
		img = paint_control.get_viewport().get_texture().get_image().get_region(Rect2(drawing_area.position, drawing_area.size))
		point_img = paint_control.get_viewport().get_texture().get_image().get_region(Rect2(drawing_area.position, drawing_area.size))
		point_rect.texture = ImageTexture.create_from_image(point_img)
		texture_rect.show()
		start(get_global_mouse_position())
		
func start(pos):
	
	print(img.get_size())
	var new_size = img.get_size() / s
	
	img.resize(new_size.x,new_size.y, 0)
	circles.clear()
	#point_rect.s = s	
	print(img.get_size())
	pos -= drawing_area.global_position 
	var res : Vector2 = img.get_size()
	var rel : Vector2i = pos/(drawing_area.size as Vector2) * res
	#img.set_pixel(rel.x, rel.y, Color(0.5,0,1,1))
	texture_rect.texture = ImageTexture.create_from_image(img)
	spread(rel)

var neighbors := [Vector2i(-1,-1), Vector2i(0,-1), Vector2i( 1,-1),
				 Vector2i(-1, 0), 				  Vector2i( 1, 0),
				 Vector2i(-1, 1), Vector2i(0, 1), Vector2i( 1, 1)]
const horizontal_neighbors := [Vector2i(0,-1), Vector2i(-1, 0), Vector2i( 1, 0), Vector2i(0, 1)]
const diagonal_neighbors := [Vector2i(-1,-1),  Vector2i( 1,-1), Vector2i(-1, 1), Vector2i( 1, 1)]
const sqrt2 = sqrt(2.0) - 1

func spread(start : Vector2i):
	var count = 0
	var layer : Dictionary = {}
	layer[start] = null
	while layer:
		var new_image := img.get_region(img.get_used_rect())
		var next_layer : Dictionary = {}
		for pixel in layer.keys():
			var next_pixels : Array[Vector2i]
			#color pixel based on surroundings
			var hn : Array[Color]
			var dn : Array[Color]
			for neighbor in horizontal_neighbors:
				var color := img.get_pixelv(pixel + neighbor)
				if color.b > 0 and not color.is_equal_approx(Color.WHITE):
					hn.append(color)
			for neighbor in diagonal_neighbors:
				var color := img.get_pixelv(pixel + neighbor)
				if color.b > 0 and not color.is_equal_approx(Color.WHITE):
					dn.append(color)
			var num_horizontal := hn.size()
			var num_diagonals := dn.size()
			
			#if zero pixel nearby, first pixel
			if num_horizontal + num_diagonals == 0:
				new_image.set_pixelv(pixel, Color(0.5,0,1,1))
			#if one pixel nearby
			elif num_horizontal + num_diagonals == 1:
				if num_horizontal:
					new_image.set_pixelv(pixel, hn[0])
				elif dn[0].r + sqrt2 < 1:
					dn[0].r += sqrt2
					new_image.set_pixelv(pixel, dn[0])
			#if two pixel nearby
			elif num_horizontal + num_diagonals == 2:
				if num_horizontal == 1:
					new_image.set_pixelv(pixel, (dn[0] + hn[0])/2)
				elif num_horizontal == 2:
					hn.sort_custom(sort_colors_asc)
					new_image.set_pixelv(pixel, hn[1])
				else:
					dn.sort_custom(sort_colors_asc)
					if dn[0].r + sqrt2 < 1:
						dn[0].r += sqrt2
						new_image.set_pixelv(pixel, dn[0])
			#if three pixels nearby
			elif num_horizontal + num_diagonals == 3:
				if num_horizontal == 1:
					new_image.set_pixelv(pixel, hn[0])
				elif num_horizontal == 2:
					dn[0].r += sqrt2
					if dn[0].r > 1:
						dn[0].r -= 1
					new_image.set_pixelv(pixel, dn[0])
				else:
					if num_diagonals:
						dn.sort_custom(sort_colors_desc)
						dn[0].r += sqrt2
						if dn[0].r > 1:
							dn[0].r -= 1
						new_image.set_pixelv(pixel, dn[0])
					else:
						new_image.set_pixelv(pixel, Color(sqrt2,0,1,1))
			else:
				if num_diagonals:
					dn.sort_custom(sort_colors_desc)
					dn[0].r += sqrt2
					if dn[0].r > 1:
						dn[0].r -= 1
					new_image.set_pixelv(pixel, dn[0])
				else:
					new_image.set_pixelv(pixel, Color(sqrt2,0,1,1))
			
			if not new_image.get_pixelv(pixel).is_equal_approx(Color.BLACK):
				for neighbor in neighbors:
					next_layer[pixel + neighbor] = null
			
		img = new_image
		texture_rect.texture = ImageTexture.create_from_image(img)
		
		for pixel in next_layer.keys():
			if not img.get_pixelv(pixel).is_equal_approx(Color.BLACK):
				next_layer.erase(pixel)
		
		#point logic
		var next_layer_tracker := next_layer.duplicate()
		var pixel_groups : Array[Array] = []		
		while next_layer_tracker:
			var first_pixel = next_layer_tracker.keys()[0]
			next_layer_tracker.erase(first_pixel)
			var new_group = []
			var pixel_stack : Array[Vector2i] = [first_pixel]
			while pixel_stack:
				var stack_pixel = pixel_stack.pop_back()
				new_group.append(stack_pixel)
				for neighbor in neighbors:
					var next_pixel : Vector2i = stack_pixel + neighbor
					if next_layer_tracker.has(next_pixel):
						next_layer_tracker.erase(next_pixel)
						pixel_stack.append(next_pixel)
			pixel_groups.append(new_group)
		
		for group in pixel_groups:
			var pos := Vector2i(0,0)
			for pixel in group:
				pos += pixel
			var avg_pos : Vector2 = pos / group.size()
			
			var global_pos := texture_rect.size * avg_pos / Vector2(img.get_size())
			#var closest_pixel : Vector2i = group[0]
			var longest_dist : float = -1
			for pixel in group:
				var new_dist := global_pos.distance_squared_to(pixel)
				if new_dist > longest_dist:
					longest_dist = new_dist
					
			var circle = Circle.new(global_pos, sqrt(longest_dist) / (s * 2))
			circles.append(circle)
		
		point_rect.circles = circles
		point_rect.queue_redraw()

		layer = next_layer
		
		count += 1
		if count > 0:
			await get_tree().process_frame
			#await get_tree().create_timer(0.1).timeout
			count = 0



func sort_colors_asc(a:Color,b:Color) -> bool:
	return a.r < b.r

func sort_colors_desc(a:Color,b:Color) -> bool:
	return a.r > b.r

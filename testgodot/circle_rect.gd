extends TextureRect

var circles : Array

func _draw():
	for circle in circles:
		draw_circle(circle.pos, circle.radius, circle.color)
		draw_circle(circle.pos, 1, Color.WHITE)

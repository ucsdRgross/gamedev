extends Area2D

var rowcol : Vector2 = Vector2.ZERO

signal hex_hovered(rowcol)

func setup(rc):
	self.rowcol = rc
	self.connect('hex_hovered', get_parent(), 'on_hex_hovered')
	
func _on_CollisionHex_mouse_entered():
	emit_signal('hex_hovered', rowcol)
	print(rowcol)

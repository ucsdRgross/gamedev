extends Area3D

var damaged:Array[Node3D] = []

func _on_body_entered(body:Node3D):
	if owner != body and body not in damaged:
		if body.is_in_group("damageable"):
			body.health_bar.damage(1)
			damaged.append(body)

func _on_area_entered(area:Area3D):
	if owner != area.owner and area not in damaged:
		if area.is_in_group("damageable"):
			area.health_bar.damage(1)
			damaged.append(area)

func reset():
	damaged.clear()

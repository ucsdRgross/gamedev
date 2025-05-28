extends Node2D

func _ready() -> void:
	var a = [1,2,3]
	print(a)
	modify(a)
	print(a)

func modify(x : Array) -> void:
	#x[0] = 10
	x.assign([3, 2, 1])

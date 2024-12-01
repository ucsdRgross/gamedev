extends Node2D

#func _ready() -> void:
	#var arr = [1,2,3,4,5,6,7,8,9]
	#for i in arr.size():
		#print(arr[i])
		#arr.resize(arr.size() - 1)

func _ready() -> void:
	var a = {1:null}
	var b = a.duplicate()
	b.erase(1)
	print(a)

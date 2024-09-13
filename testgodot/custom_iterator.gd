extends Node

class timerator:
	var start
	var current
	#var end
	var increment
	var time
	
	func _init(time):
		self.start = Time.get_ticks_msec()
		self.current = start
		#self.end = stop
		self.increment = 1
		self.time = time + start

	func should_continue():
		return (Time.get_ticks_msec() < time)

	func _iter_init(arg):
		current = start
		return should_continue()

	func _iter_next(arg):
		current += increment
		return should_continue()

	func _iter_get(arg):
		return current

func _ready():
	var itr = timerator.new(10)
	for i in itr:
		print(i)

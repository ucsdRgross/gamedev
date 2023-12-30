extends Resource
class_name AI 

var body : Unit
var lock : Callable = Callable()

func setup(body : Unit):
	self.body = body

func tick(delta : float):
	pass

func interrupt():
	if lock: 
		lock.call()
		lock = Callable()

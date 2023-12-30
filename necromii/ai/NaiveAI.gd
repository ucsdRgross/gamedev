extends AI
class_name NaiveAI
#Move towards closest enemy and attack closest enemy in range

#var body : Unit

func setup(body : Unit):
	self.body = body

func tick(delta : float):
	pass
	#await attack()
	#move()

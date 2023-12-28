extends Resource
class_name Ability

var body : Unit

func setup(body : Unit):
	self.body = body

func move(delta : float, dir : Vector3):
	pass

func jump():
	pass

func attack(target : Unit):
	pass
	
func special(target : Unit):
	pass

extends Node2D

@onready var a = $A
@onready var c = $C
@onready var x = $X
@onready var y = $Y
@onready var e = $E


# Called when the node enters the scene tree for the first time.
func intersect():
	print("a", a.position)
	print("c", c.position)
	print("x", x.position)
	print("y", y.position)
	var t = 0;
	
	var xY = y.position.x
	var yY = -y.position.y
	var xX = x.position.x
	var yX = -x.position.y
	var xA = a.position.x
	var yA = -a.position.y
	var xC = c.position.x
	var yC = -c.position.y
	
	if(xY == xX):
		t =  max((yA - yX)/(yY - yX), (yC - yX)/(yY - yX));
	else:
		if(yY == yX):
			t = max((xA - xX)/(xY - xX), (xC - xX)/(xY - xX));
		else:
			if(xY > xX):
				if(yY > yX):
					t = min((xC - xX)/(xY - xX), (yC - yX)/(yY - yX));
				else:
					t = min((xC - xX)/(xY - xX), (yA - yX)/(yY - yX));
			else:
				if(yY > yX):
					t = min((xA - xX)/(xY - xX), (yC - yX)/(yY - yX));
				else:
					t = min((xA - xX)/(xY - xX), (yA - yX)/(yY - yX));

	var xE = t * xY + (1 - t) * xX;
	var yE = t * yY + (1 - t) * yX;
	e.position.x = xE
	e.position.y = -yE
	print(xE,yE)

func _physics_process(delta):
	var input_dir = Input.get_vector("move_left", "move_right", "move_forward", "move_backward",)
	x.position += input_dir
	input_dir = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	y.position += input_dir
	intersect()

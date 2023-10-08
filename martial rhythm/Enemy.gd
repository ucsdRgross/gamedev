extends RigidBody3D

@onready var health_bar : HealthBar = $HealthBar


func _input(event):
	if event.is_action_pressed("LClick"):
		$PunchCard.execute(self)


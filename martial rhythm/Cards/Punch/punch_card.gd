extends Card

@onready var punch_ability := $PunchAbility

func execute(parent : Node):
	var ability : Node = punch_ability.create_instance()
	remove_child(ability)
	parent.add_child(ability)

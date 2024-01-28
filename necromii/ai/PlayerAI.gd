extends AI
class_name PlayerAI

const keys : Array[StringName] = [&'ui_accept',&"Left", &"Right", &"Forward", &"Back"]
@onready var mana_bar : ProgressBar = $ManaBar
var contact : Unit = null
var last_y_vel : float

func _ready():
	#body.state_process.connect(tick)
	body.body_entered.connect(_on_body_entered)
	body.body_exited.connect(_on_body_exited)
	body.contact_monitor = true
	body.max_contacts_reported = 1
	mana_bar.max_value = body.stats.base_mana
	mana_bar.value = 0

func _exit_tree():
	body.body_entered.disconnect(_on_body_entered)
	body.body_exited.disconnect(_on_body_exited)
	body.contact_monitor = false
	body.max_contacts_reported = 0

func tick():
	last_y_vel = body.linear_velocity.y
	mana_bar.value += 9.0/60
	if contact:
		if not contact.alive:
			var cur_mana := mana_bar.value
			var drain_rate := 10.0/60
			if drain_rate > cur_mana:
				drain_rate = cur_mana
			mana_bar.value -= drain_rate
			contact.damage(-drain_rate)
	
	var pressed = false
	for k : StringName in keys:
		if Input.is_action_pressed(k):
			pressed = true
			break
	if not pressed:
		body.attack()
	else:
		body.interrupt()
	
	if lock:
		return
		
	var input_dir := Input.get_vector(&"Left", &"Right", &"Forward", &"Back")
	var target := Vector3(input_dir.x, 0, input_dir.y) * 10 + body.global_position
	body.move(target)
	
	if Input.is_action_pressed(&'ui_accept'):
		body.action()
	
			#var pos = raycast_from_mouse()
			#if pos:
				#var fake_unit : RigidBody3D = RigidBody3D.new()
				#
				#print(pos)
				#fake_unit.position = pos
				#print(fake_unit.position)
				#body.attack(fake_unit)

#func raycast_from_mouse():
	#var ray_length := 1000.0
	#var mouse_position = body.get_viewport().get_mouse_position()
	#var camera = body.get_viewport().get_camera_3d()
	#var ray_start = camera.project_ray_origin(mouse_position)
	#var ray_end = ray_start + camera.project_ray_normal(mouse_position) * ray_length
	#var world3d : World3D = body.get_world_3d()
	#var space_state = world3d.direct_space_state
	#
	#if space_state == null:
		#return
	#
	#var query = PhysicsRayQueryParameters3D.create(ray_start, ray_end, 1)
	#query.collide_with_bodies = true
#
	#var result = space_state.intersect_ray(query)
	#
	##print(mouse_position, camera,ray_start,ray_end,world3d,space_state,result)
	#if result.size() > 0:
		#return result.position
	#return null


func _on_body_entered(body:PhysicsBody3D):
	if body.has_method('damage'):
		if not body.alive:
			contact = body
			body.team = self.body.team
			var cur_mana := mana_bar.value
			var drain : float = 2.0 * max(0, -last_y_vel)
			print(drain)
			if drain > cur_mana:
				drain = cur_mana
			mana_bar.value -= drain
			body.damage(-drain)

func _on_body_exited(body:PhysicsBody3D):
	if contact == body:
		contact = null

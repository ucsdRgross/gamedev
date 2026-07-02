@tool
extends Node2D
class_name CardVisual

const CARD_VISUAL = preload("uid://bynh2btoahe5i")

const CARD_SIZE := Vector2(38,50)
const CARD_SEPARATION : int = 14

@export_tool_button("Update Visual") var editor_update_visual : Callable = update_visual

enum DisplayContext {PLAY_AREA, MAP, DECK_VIEWER, PREVIEW}
@export var current_context: DisplayContext = DisplayContext.PLAY_AREA
var control_anchor: Control = null

var card_size : Vector2
var card_separation: int
var card_separation_custom: int

static var card_size_play : Vector2:
	get():
		return CARD_SIZE * SettingsManager.settings.card_scale
static var card_separation_play : int:
	get():
		return CARD_SEPARATION * SettingsManager.settings.card_scale
static var card_separation_play_custom : int:
	get():
		return card_separation_play * SettingsManager.settings.card_separation_scale

var focused : bool = false:
	set(value):
		focused = value
		if focused: modulate = Color(1.825, 1.825, 1.825)
		else: modulate = Color(1.0, 1.0, 1.0)
@export var data : CardData:
	set(value):
		if data == value: return
		data = value
		update_visual()
		
		if current_context != DisplayContext.PLAY_AREA: return
		if is_node_ready() and data:
			on_stage_changed()
var can_move_anim := true
var can_rot_anim := true
var floating : bool = true:
	set(value):
		floating = value
		if not floating:
			if not is_node_ready():
				await ready
			basis3d = Basis.looking_at(Vector3(0, 0, -3.5 * (-1 if data and data.flipped else 1)))
			if Engine.is_editor_hint():
				visual.position.y = 0

var basis3d : Basis = Basis(Vector3(-1,0,0), Vector3(0,1,0), Vector3(0,0,-1)):
	set(value):
		basis3d = value
		visual.transform.x = Vector2(basis3d.x[0], basis3d.x[1])
		visual.transform.y = Vector2(basis3d.y[0], basis3d.y[1])
		show_front = basis3d.z[2] > 0
#change flipped instead
var show_front := false :
	set(value):
		if value != show_front:
			show_front = value
			update_visual()

#func set_flipped_instant(flip:bool) -> void:
	#flipped = flip
	#basis3d = Basis.looking_at(Vector3(0, 0, -3.5 * (-1 if flip else 1)))

func update_visual() -> void:
	if show_front and data:
		if data.rank:
			data.rank.set_texture(rank)
			rank.show()
		else: rank.hide()
		if data.suit:
			data.suit.set_texture(suit)
			data.suit.set_material(suit)
			data.suit.set_material(rank)
			suit.show()
		else: suit.hide()
			
		if data.type:
			data.type.set_texture(type)
			type.show()
		else: type.hide()
			
		if data.stamp:
			data.stamp.set_texture(stamp)
			stamp.show()
		else: stamp.hide()
			
		if data.skill:
			data.skill.set_texture(art)
			data.skill.set_material(art)
			art.show()
		elif data.suit:
			data.suit.set_art_texture(art, data.rank)
			data.suit.set_material(art)
			art.show()
		else: art.hide()

	else:
		if not is_node_ready():
			await ready
		rank.hide()
		stamp.hide()
		suit.hide()
		art.hide()
		
		#placeholder
		CardModifier.update_polygon_uv_frame(
			type,CardModifierType.TYPE_TEXTURE, 
			CardModifierType.H_FRAMES,
			CardModifierType.V_FRAMES,
			1)
		type.show()

#static var num_cards : int = 0
#static var child_offset : Vector2 = Vector2(0, 55)
var num : int = 0
var move_tween : Tween
var tilt_tween : Tween
var held : int = 0
var hover : bool = false

@onready var offset: Node2D = $Offset
@onready var visual: Node2D = $Offset/Visual
@onready var type: Polygon2D = $Offset/Visual/Type
@onready var rank: Polygon2D  = $Offset/Visual/Rank
@onready var stamp: Polygon2D = $Offset/Visual/Stamp
@onready var suit: Polygon2D  = $Offset/Visual/Suit
@onready var art: Polygon2D = $Offset/Visual/Art
	
	
static func add_child_card_visual(parent:Node,connected_data:CardData, context:DisplayContext, target_control: Control = null) -> CardVisual:
	var card : CardVisual = (CARD_VISUAL.instantiate() as CardVisual).with_data(connected_data)
	card.current_context = context
	card.control_anchor = target_control if target_control else (parent as Control)
	card.recalculate_size()
	#wait for play area containers to update control positions at next frame
	parent.call_deferred("add_child", card)
	return card

func _ready() -> void:
	#if not Engine.is_editor_hint(): data = null
	type.hide()
	rank.hide()
	stamp.hide()
	suit.hide()
	art.hide()
	#if not (data and data.stage == CardData.Stage.ZONE):
		#front.frame = 3
		##num_cards += 1
		##num = num_cards
	#else:
		#front.frame = 0
		##child_offset = Vector2(0,0)
		#basis3d = Basis(Vector3(-1,0,0), Vector3(0,1,0), Vector3(0,0,-1))
	SettingsManager.settings_changed.connect(recalculate_size)
	recalculate_size()
	match data.previous_stage:
		data.Stage.PLAY, data.Stage.ZONE:
			if CardEnvironment.CURRENT:
				global_position = get_card_control_center(control_anchor)
		data.Stage.DRAW:
			if CardEnvironment.get_current_game():
				global_position = get_control_center(CardEnvironment.get_current_game().deck_ui)
		data.Stage.DISCARD:
			if CardEnvironment.get_current_game():
				global_position = get_control_center(CardEnvironment.get_current_game().discard_ui)
		data.Stage.RULES:
			if CardEnvironment.get_current_game():
				global_position = get_control_center(CardEnvironment.get_current_game().rules_ui)
	on_stage_changed()

func recalculate_size() -> void:
	match current_context:
		DisplayContext.DECK_VIEWER:
			card_size = CARD_SIZE * 2#SettingsManager.settings.card_scale
			card_separation = CARD_SEPARATION * SettingsManager.settings.card_scale
			card_separation_custom = card_separation * SettingsManager.settings.card_separation_scale
			scale = Vector2.ONE * 2
		DisplayContext.PLAY_AREA:
			card_size = CARD_SIZE * SettingsManager.settings.card_scale
			card_separation = CARD_SEPARATION * SettingsManager.settings.card_scale
			card_separation_custom = card_separation * SettingsManager.settings.card_separation_scale
			scale = Vector2.ONE * SettingsManager.settings.card_scale
		_:
			card_size = CARD_SIZE * SettingsManager.settings.card_scale
			card_separation = CARD_SEPARATION * SettingsManager.settings.card_scale
			card_separation_custom = card_separation * SettingsManager.settings.card_separation_scale
			scale = Vector2.ONE * SettingsManager.settings.card_scale

func on_stage_changed() -> void:
	if current_context != DisplayContext.PLAY_AREA: return
	if not data: return
	if data.stage == data.previous_stage: return
	match data.stage:
		data.Stage.PLAY, data.Stage.ZONE:
			#anchor may not exist yet (visual created same frame as its control)
			if not control_anchor or not is_instance_valid(control_anchor): return
			var target_pos := get_card_control_center(control_anchor)
			create_move_tween(target_pos)
			await move_tween.finished
		data.Stage.DRAW:
			if CardEnvironment.get_current_game():
				var target_pos := get_control_center(CardEnvironment.get_current_game().deck_ui)
				create_move_tween(target_pos).tween_callback(queue_free)
		data.Stage.DISCARD:
			if CardEnvironment.get_current_game():
				var target_pos := get_control_center(CardEnvironment.get_current_game().discard_ui)
				create_move_tween(target_pos).tween_callback(queue_free)
		data.Stage.RULES:
			if CardEnvironment.get_current_game():
				var target_pos := get_control_center(CardEnvironment.get_current_game().rules_ui)
				create_move_tween(target_pos).tween_callback(queue_free)

func get_card_control_center(control:Control) -> Vector2:
	return control.global_position + Vector2(control.size.x/2, card_size.y / 2)

func get_control_center(control:Control) -> Vector2:
	return control.global_position + control.size/2

func _process(delta: float) -> void:
	delta_self_moving_logic(delta)
	if floating: delta_floating_anim(delta)

var rot_delta : float
var y_delta : float
func delta_self_moving_logic(delta:float) -> void:
	# Needs state check, if discard then discard animation first before free
	match current_context:
		DisplayContext.PLAY_AREA:
			if CardEnvironment.get_current_game() and data not in CardEnvironment.get_current_game().play_area.data_ui: queue_free()
		_:
			if not Engine.is_editor_hint() and (not control_anchor or not is_instance_valid(control_anchor)): queue_free()
	if (not (move_tween and move_tween.is_running())) and control_anchor:
			#and data and (data.stage == data.Stage.PLAY or data.stage == data.Stage.ZONE)):		
		var target : Vector2 = get_card_control_center(control_anchor)
		if held:
			#where card orients itself relative to mouse
			var offset : int =  card_size.y/2 - card_separation/2
			offset += (held - 1) * card_separation_custom
			target = get_global_mouse_position() + Vector2(0, offset)
		#if held or not bot_card:
			#target = target_pos
		#else:
			#target = bot_card.global_position
			#if not bot_card.is_zone:
				#target += bot_card.child_offset.rotated(bot_card.global_rotation*1.75)
			#y_delta += bot_card.y_delta * 0.5
			
		target.y -= y_delta
		var move : Vector2 = target - global_position
		# lerp is bad, frame dependent
		# should be a tween instead when data is moving slots
		# still need something to keep card attached to control though
		# probably some sort of flag to trigger on next move instead of attach
		# global_position = global_position.lerp(target, .2)
		global_position = target + (global_position - target) * exp(-10 * delta)
		
		if can_rot_anim and data and data.stage != data.Stage.ZONE:
			y_delta = lerpf(y_delta, move.y, 15 * delta)
			y_delta = clampf(y_delta, -4, 4)
			
			rot_delta = lerpf(rot_delta, move.x, 15 * delta)
			var clamp_degree : float = sqrt(abs(rot_delta) as float) * 5
			rot_delta = clampf(rot_delta, -clamp_degree, clamp_degree)
			rotation_degrees = rot_delta

func delta_floating_anim(delta:float) -> void:
	var x : float = sin(num + float(Time.get_ticks_msec()) / 2000) * (0.3 if hover else 0.6)
	var y : float = cos(num + float(Time.get_ticks_msec()) / 2000) * (0.3 if hover else 0.6)
	
	if hover:
		var mouse_pos : Vector2 = -get_local_mouse_position().normalized()
		x += mouse_pos.x/1.5
		y += mouse_pos.y/1.5
	var bobbing := sin(2 * num + float(Time.get_ticks_msec()) / 2000)
	if data and data.stage == data.Stage.ZONE:
		x = 0
		y = 0
		bobbing = 0
	var drift : Vector3 = Vector3(x, y, -3.5 * (-1 if data and data.flipped else 1))
	basis3d = basis3d.slerp(Basis.looking_at(drift), 6.5 * delta)
	visual.position.y = lerpf(visual.position.y, bobbing, 10 * delta)

func with_data(data:CardData) -> CardVisual:
	self.data = data
	data.data_changed.connect(update_visual)
	data.stage_changed.connect(on_stage_changed)
	return self

func reset_tween(tween:Tween) -> void:
	if tween and tween.is_running():
		tween.custom_step(INF)

func create_move_tween(target_pos:Vector2) -> Tween:
	reset_tween(move_tween)
	var delay := CardEnvironment.CURRENT.get_delay()
	move_tween = create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN_OUT)
	move_tween.tween_property(self, "global_position", target_pos, delay*0.3)
	if target_pos.x - global_position.x > 10:
		move_tween.parallel().tween_property(self, "rotation_degrees", 10, delay*0.2)
	elif global_position.x - target_pos.x > 10:
		move_tween.parallel().tween_property(self, "rotation_degrees", -10, delay*0.2)
	#tween.set_ease(Tween.EASE_OUT)
	move_tween.tween_property(self, "rotation_degrees", 0, delay*0.1)
	return move_tween

func anim_jump() -> float:
	reset_tween(move_tween)
	var delay := CardEnvironment.CURRENT.get_delay()
	move_tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	move_tween.tween_callback(func()->void: floating = false)
	move_tween.tween_property(offset, "position:y", -CARD_SIZE.y / 5.0, delay * .4)
	move_tween.tween_property(offset, "scale", Vector2.ONE * 1.15, delay * .3)
	move_tween.tween_property(offset, "scale", Vector2.ONE, delay * .2)
	return delay * .4

func anim_reset() -> void:
	reset_tween(move_tween)
	var delay := CardEnvironment.CURRENT.get_delay()
	move_tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	move_tween.tween_property(offset, "position:y", 0, delay * .4)
	move_tween.tween_callback(func()->void: floating = true)

#print(result.score_name, "\nscore: ", result.score)
				##tween = create_tween().set_parallel(true)
				##tween.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_BACK)
				#for c:Card in result.card_combo:
					#var card_tween : Tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
					#c.floating = false
					#card_tween.tween_property(c.front, "position:y", -7 * 1.5, base_delay * .5)
					#card_tween.tween_property(c.front, "position:y", -7, base_delay * .5)
					#print('suit: ', c.data.suit.get_str(), c.data.suit.value, ' rank: ', c.data.rank.get_str(), c.data.rank.value)
				#for c:Card in last_scored_cards:
					#if c not in result.card_combo:
						#var card_tween : Tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
						#card_tween.tween_property(c.front, "position:y", 0, base_delay)
						#card_tween.tween_callback(func()->void: c.floating = true)
						##card_tween.tween_property(c, "floating", true, base_delay * .1)
				#
				##tween.tween_interval(score_delay)
				#last_scored_cards = result.card_combo
				#var combo_pos : Vector2 = Vector2.ZERO
				#for card in result.card_combo:
					#combo_pos += card.global_position
				#combo_pos /= result.card_combo.size()
				#var score_name_popup := TextPopup.new_popup(result.score_name, combo_pos)
				#game_container.add_child(score_name_popup)
				#
				#row_add_score(row_to_score, result.score)
				##var popup := (TEXT_POPUP.instantiate() as TextPopup).with(result.score_name, score_delay)
				##popup.global_position = combo_pos
				##add_child(popup)
				#await get_tree().create_timer(base_delay).timeout
				#for card in result.card_combo:
					#await run_all_mods(&"on_score", card)
				#await run_all_mods(&"on_after_score")
				#
				##await get_tree().create_timer(score_delay).timeout
				#score_name_popup.queue_free()
				#

# --- EDITOR BAKE INSPECTOR UTILITIES ---
@export_group("Mesh Generation Configuration")
@export var target_polygon_node: Polygon2D
@export var bake_sample_texture: Texture2D
@export var bake_h_frames: int = 8
@export var bake_v_frames: int = 8
## Default horizontal cut lines set cleanly to 1
@export var subdivisions_x: int = 1
## Default vertical cut lines set cleanly to 1
@export var subdivisions_y: int = 1

@export_tool_button("Bake Selected Mesh & UVs") 
var editor_bake_mesh : Callable = func() -> void:
	if not target_polygon_node or not bake_sample_texture:
		printerr("CardVisual Tool: Please assign a target node and sample texture!")
		return
	generate_editor_mesh(target_polygon_node, bake_sample_texture, bake_h_frames, bake_v_frames, subdivisions_x, subdivisions_y)
	print("CardVisual Tool: Successfully baked ", target_polygon_node.name, " diamond grid structure!")

## Bakes a pristine diamond grid while isolating internal vertices from the perimeter chain
func generate_editor_mesh(poly: Polygon2D, tex: Texture2D, h_f: int, v_f: int, subdiv_x: int, subdiv_y: int) -> void:
	poly.texture = tex
	
	var sheet_size := tex.get_size()
	var frame_w := sheet_size.x / h_f
	var frame_h := sheet_size.y / v_f
	
	var x_segments := subdiv_x + 1
	var y_segments := subdiv_y + 1
	
	var perimeter_vertices := PackedVector2Array()
	var internal_vertices := PackedVector2Array()
	var triangles: Array[PackedInt32Array] = []
	
	# --- STEP 1: COLLECT AND SEPARATE VERTICES ---
	# To make Godot happy, we map structural grid loops into memory arrays first
	var grid_pts: Array[Array] = []
	grid_pts.resize(y_segments + 1)
	
	for y in range(y_segments + 1):
		grid_pts[y] = []
		grid_pts[y].resize(x_segments + 1)
		var t_y := float(y) / y_segments 
		var pos_y : float = lerp(-frame_h / 2.0, frame_h / 2.0, t_y)
		
		for x in range(x_segments + 1):
			var t_x := float(x) / x_segments
			var pos_x : float = lerp(-frame_w / 2.0, frame_w / 2.0, t_x)
			grid_pts[y][x] = Vector2(pos_x, pos_y)

	# Append the exact 4 outer-most perimeter boundaries FIRST in clockwise winding order
	perimeter_vertices.append(grid_pts[0][0] as Vector2)                       # Top-Left
	perimeter_vertices.append(grid_pts[0][x_segments] as Vector2)              # Top-Right
	perimeter_vertices.append(grid_pts[y_segments][x_segments] as Vector2)     # Bottom-Right
	perimeter_vertices.append(grid_pts[y_segments][0] as Vector2)              # Bottom-Left

	# Gather all other internal line splits safely into the internal vertex list array
	for y in range(y_segments + 1):
		for x in range(x_segments + 1):
			# Skip the 4 corners we already manually saved above
			if (y == 0 and x == 0) or (y == 0 and x == x_segments) or \
			   (y == y_segments and x == x_segments) or (y == y_segments and x == 0):
				continue
			internal_vertices.append(grid_pts[y][x] as Vector2)

	# Add cell quadrant centers into the internal vertices array to establish the "X" cuts
	var cell_center_start_idx := 4 + internal_vertices.size()
	var centers: Array[Vector2] = []
	
	for y in range(y_segments):
		for x in range(x_segments):
			var c_pos : Vector2 = (grid_pts[y][x] + grid_pts[y][x+1] + grid_pts[y+1][x] + grid_pts[y+1][x+1]) / 4.0
			centers.append(c_pos)
			internal_vertices.append(c_pos)

	# Merge everything into the primary polygon vertex buffer
	var final_vertices := perimeter_vertices + internal_vertices
	
	# Helper lambda function to index points quickly inside the flat final array
	var get_v_idx := func(pos: Vector2) -> int:
		for i in range(final_vertices.size()):
			if final_vertices[i].is_equal_approx(pos): return i
		return 0

	# --- STEP 2: DIAMOND "X" TRIANGULATION ---
	var center_counter := 0
	for y in range(y_segments):
		for x in range(x_segments):
			var tl : int = get_v_idx.call(grid_pts[y][x] as Vector2)
			var tr : int = get_v_idx.call(grid_pts[y][x+1] as Vector2)
			var bl : int = get_v_idx.call(grid_pts[y+1][x] as Vector2)
			var br : int = get_v_idx.call(grid_pts[y+1][x+1] as Vector2)
			var cc := cell_center_start_idx + center_counter
			center_counter += 1
			
			triangles.append(PackedInt32Array([tl, tr, cc])) # Top Triangle
			triangles.append(PackedInt32Array([tr, br, cc])) # Right Triangle
			triangles.append(PackedInt32Array([br, bl, cc])) # Bottom Triangle
			triangles.append(PackedInt32Array([bl, tl, cc])) # Left Triangle

	poly.polygon = final_vertices
	poly.polygons = triangles
	poly.internal_vertex_count = internal_vertices.size()

	# --- STEP 3: ASSIGN FIXED BASELINE UV MAP (FRAME 0) ---
	var initial_uvs := PackedVector2Array()
	initial_uvs.resize(final_vertices.size())
	for i in range(final_vertices.size()):
		var p := final_vertices[i]
		var norm_x := (p.x / frame_w) + 0.5
		var norm_y := (p.y / frame_h) + 0.5
		initial_uvs[i] = Vector2(norm_x * frame_w, norm_y * frame_h)
	poly.uv = initial_uvs
	poly.notify_property_list_changed()

# --- STAR SKELETON SETUP AND BINDING UTILITIES ---
@export_group("Skeleton Automation Configuration")
## Number of progressive bone nodes dividing each directional arm of the star (1 = 8 bones, 2 = 16 bones)
@export var arm_segments: int = 1
## Changes how many structural arms the star splits into based on edge segments (1 = 8 arms, 2 = 12 arms, 3 = 16 arms)
@export var edge_subdivisions: int = 1

@export_tool_button("Generate Star Skeleton & Bind")
var editor_setup_skeleton : Callable = func() -> void:
	var visual_container := get_node_or_null("Offset/Visual")
	if not visual_container or visual_container.get_child_count() == 0:
		printerr("CardVisual Tool: 'Offset/Visual' path empty or missing!")
		return
	
	# 1. Dynamically scan vertices to determine the spatial bounding box boundaries
	var highest_y: float = INF
	var lowest_y: float = -INF
	var max_x: float = -INF
	var polygon_layers: Array[Polygon2D] = []
	
	for child in visual_container.get_children():
		if child is Polygon2D:
			polygon_layers.append(child as Polygon2D)
			for vertex in (child as Polygon2D).polygon:
				var card_local_pos := to_local((child as Polygon2D).to_global(vertex))
				highest_y = min(highest_y, card_local_pos.y)
				lowest_y = max(lowest_y, card_local_pos.y)
				max_x = max(max_x, abs(card_local_pos.x))

	# Compute the midpoint of the card geometry bounds to find the absolute center
	var half_height := (lowest_y - highest_y) / 2.0
	var center_pos := Vector2(0, highest_y + half_height)
	
	var radius_vertical := half_height
	var radius_horizontal := max_x
	
	# Define the four absolute corner poles of our bounding frame box
	var tl := Vector2(-radius_horizontal, highest_y)
	var tr := Vector2(radius_horizontal, highest_y)
	var br := Vector2(radius_horizontal, lowest_y)
	var bl := Vector2(-radius_horizontal, lowest_y)

	# 2. Reset and build the clean Skeleton2D node layer
	var skeleton: Skeleton2D = get_node_or_null("Skeleton2D")
	if skeleton: skeleton.queue_free()
	skeleton = Skeleton2D.new()
	skeleton.name = "Skeleton2D"
	add_child(skeleton)
	skeleton.owner = get_tree().edited_scene_root

	# 3. CREATE THE SINGLE SHARED CENTRAL CORE ROOT BONE
	var center_bone := Bone2D.new()
	center_bone.name = "Bone_Center"
	center_bone.position = center_pos
	center_bone.rotation = 0.0
	center_bone.set_length(10.0)
	
	skeleton.add_child(center_bone)
	center_bone.owner = get_tree().edited_scene_root
	center_bone.rest = center_bone.transform

	# 4. GENERATE DIRECTIONAL TARGET PATHS BY SUBDIVIDING RECTANGLE EDGES
	var directions: Array[Vector2] = []
	var arm_names: Array[String] = []
	
	# Total steps per border edge wall
	var wall_steps := edge_subdivisions + 1
	
	# Edge A: Top Wall (Left to Right)
	for i in range(wall_steps):
		var target := tl.lerp(tr, float(i) / wall_steps)
		directions.append(target - center_pos)
		if i == 0:
			arm_names.append("TopLeft")
		elif edge_subdivisions == 1:
			arm_names.append("Top")
		else:
			arm_names.append("Top_" + str(i))
		
	# Edge B: Right Wall (Top to Bottom)
	for i in range(wall_steps):
		var target := tr.lerp(br, float(i) / wall_steps)
		directions.append(target - center_pos)
		if i == 0:
			arm_names.append("TopRight")
		elif edge_subdivisions == 1:
			arm_names.append("Right")
		else:
			arm_names.append("Right_" + str(i))
		
	# Edge C: Bottom Wall (Right to Left)
	for i in range(wall_steps):
		var target := br.lerp(bl, float(i) / wall_steps)
		directions.append(target - center_pos)
		if i == 0:
			arm_names.append("BottomRight")
		elif edge_subdivisions == 1:
			arm_names.append("Bottom")
		else:
			arm_names.append("Bottom_" + str(i))
		
	# Edge D: Left Wall (Bottom to Top)
	for i in range(wall_steps):
		var target := bl.lerp(tl, float(i) / wall_steps)
		directions.append(target - center_pos)
		if i == 0:
			arm_names.append("BottomLeft")
		elif edge_subdivisions == 1:
			arm_names.append("Left")
		else:
			arm_names.append("Left_" + str(i))

	# Setup explicit tracking array sets for structural weight calculations
	var bone_paths: Array[String] = ["Bone_Center"]
	var bone_nodes: Array[Bone2D] = [center_bone]

	# 5. GENERATE THE DYNAMIC STAR ARMS AS NESTED HIERARCHIES
	for arm_idx in range(directions.size()):
		var dir_vector := directions[arm_idx]
		var total_arm_length := dir_vector.length()
		var segment_length := total_arm_length / float(arm_segments)
		
		var previous_joint: Node = center_bone
		var path_accumulator := "Bone_Center"
		
		for segment_idx in range(arm_segments):
			var arm_bone := Bone2D.new()
			var b_name := ""
			
			if segment_idx == 0:
				b_name = "Arm_" + arm_names[arm_idx]
				arm_bone.position = dir_vector / float(arm_segments)
			else:
				b_name = "Arm_" + arm_names[arm_idx] + "_Seg_" + str(segment_idx)
				arm_bone.position = dir_vector / float(arm_segments)
				
			arm_bone.name = b_name
			arm_bone.rotation = 0.0
			arm_bone.set_length(segment_length)
			
			path_accumulator += "/" + b_name
			bone_paths.append(path_accumulator)
			
			previous_joint.add_child(arm_bone)
			arm_bone.owner = get_tree().edited_scene_root
			arm_bone.rest = arm_bone.transform
			
			bone_nodes.append(arm_bone)
			previous_joint = arm_bone

	# 6. COMPUTE DYNAMIC PROXIMITY WEIGHT MATRICES ACROSS ALL LAYERS
	for poly in polygon_layers:
		poly.skeleton = poly.get_path_to(skeleton)
		poly.clear_bones()
		
		var vertices := poly.polygon
		if vertices.is_empty(): continue
		
		# Pre-allocate weight matrices matching layout tracks
		var weights_by_bone: Array[PackedFloat32Array] = []
		for b_idx in range(bone_paths.size()):
			var w_arr := PackedFloat32Array()
			w_arr.resize(vertices.size())
			w_arr.fill(0.0)
			weights_by_bone.append(w_arr)
			
		for v_idx in range(vertices.size()):
			var v_glob := poly.to_global(vertices[v_idx])
			
			var distance_factors := PackedFloat32Array()
			distance_factors.resize(bone_paths.size())
			var running_weight_denominator := 0.0
			
			# Sample absolute spatial proximity lengths across all created joints
			for b_idx in range(bone_paths.size()):
				var dist := v_glob.distance_to(bone_nodes[b_idx].global_position)
				if dist < 0.1: dist = 0.1
				
				var falloff_factor := 1.0 / (dist * dist)
				distance_factors[b_idx] = falloff_factor
				running_weight_denominator += falloff_factor
				
			# Normalize ratios to sum up to 1.0 per vertex point
			for b_idx in range(bone_paths.size()):
				weights_by_bone[b_idx][v_idx] = distance_factors[b_idx] / running_weight_denominator

		# Add paths and calculated weight arrays cleanly through the engine profile structure
		for b_idx in range(bone_paths.size()):
			poly.add_bone(NodePath(bone_paths[b_idx]), weights_by_bone[b_idx])
			
		poly.notify_property_list_changed()
	print("CardVisual Tool: Custom ", directions.size(), "-Way Star rig generated with optimized naming schemes!")

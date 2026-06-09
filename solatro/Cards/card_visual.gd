@tool
extends Node2D
class_name CardVisual

const CARD_VISUAL = preload("uid://bynh2btoahe5i")

const CARD_SIZE := Vector2(38,50)
const CARD_SEPERATION : int = 14

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
static var card_seperation_play : int:
	get():
		return CARD_SEPERATION * SettingsManager.settings.card_scale
static var card_seperation_play_custom : int:
	get():
		return card_seperation_play * SettingsManager.settings.card_seperation_scale

var focused : bool = false:
	set(value):
		focused = value
		if focused: modulate = Color(1.825, 1.825, 1.825)
		else: modulate = Color(1.0, 1.0, 1.0)
@export var data : CardData:
	set(value):
		data = value
		update_visual()
		if current_context != DisplayContext.PLAY_AREA: return
		if not is_node_ready():
			await ready
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
			0)
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
	
	
@export_group("Mesh Generation Configuration")
## Drag and drop the targeted layer child node here (e.g. Type, Art, Rank)
@export var target_polygon_node: Polygon2D
## Reference texture sheet layout to sample dimensions from
@export var bake_sample_texture: Texture2D
@export var bake_h_frames: int = 8
@export var bake_v_frames: int = 8
@export var subdivisions_x: int = 1
@export var subdivisions_y: int = 3
	
	
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

func recalculate_size() -> void:
	match current_context:
		DisplayContext.DECK_VIEWER:
			card_size = CARD_SIZE * 2#SettingsManager.settings.card_scale
			card_separation = CARD_SEPERATION * SettingsManager.settings.card_scale
			card_separation_custom = card_separation * SettingsManager.settings.card_seperation_scale
			scale = Vector2.ONE * 2
		DisplayContext.PLAY_AREA:
			card_size = CARD_SIZE * SettingsManager.settings.card_scale
			card_separation = CARD_SEPERATION * SettingsManager.settings.card_scale
			card_separation_custom = card_separation * SettingsManager.settings.card_seperation_scale
			scale = Vector2.ONE * SettingsManager.settings.card_scale
		_:
			card_size = CARD_SIZE * SettingsManager.settings.card_scale
			card_separation = CARD_SEPERATION * SettingsManager.settings.card_scale
			card_separation_custom = card_separation * SettingsManager.settings.card_seperation_scale
			scale = Vector2.ONE * SettingsManager.settings.card_scale

func on_stage_changed() -> void:
	if current_context != DisplayContext.PLAY_AREA: return
	if data.stage == data.previous_stage: return
	match data.stage:
		data.Stage.PLAY, data.Stage.ZONE:
			var target_pos := get_card_control_center(control_anchor)
			create_move_tween(target_pos)
		data.Stage.DRAW:
			if CardEnvironment.get_current_game():
				var target_pos := get_control_center(CardEnvironment.get_current_game().discard_ui)
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
		global_position = target + (global_position - target) * exp(-5 * delta)
		
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


@export_tool_button("Bake Selected Mesh & UVs") 
var editor_bake_mesh : Callable = func() -> void:
	if not target_polygon_node or not bake_sample_texture:
		printerr("CardVisual Tool: Please assign a target node and sample texture inside the inspector group!")
		return
	generate_editor_mesh(target_polygon_node, bake_sample_texture, bake_h_frames, bake_v_frames, subdivisions_x, subdivisions_y)
	print("CardVisual Tool: Successfully baked ", target_polygon_node.name, " mesh data structure!")

## Bakes an optimized, X-subdivided geometric grid with centralized diamond triangulation
func generate_editor_mesh(poly: Polygon2D, tex: Texture2D, h_f: int, v_f: int, subdiv_x: int, subdiv_y: int) -> void:
	poly.texture = tex
	
	var sheet_size := tex.get_size()
	var frame_w := sheet_size.x / h_f
	var frame_h := sheet_size.y / v_f
	
	var vertices := PackedVector2Array()
	var triangles: Array[PackedInt32Array] = []
	
	var x_segments := subdiv_x + 1
	var y_segments := subdiv_y + 1
	
	# --- STEP 1: GENERATE CORNER GRID VERTICES ---
	# We store where the main grid corners sit so we can map them cleanly
	var grid_width_vertices := x_segments + 1
	
	for y in range(y_segments + 1):
		var t_y := float(y) / y_segments 
		var pos_y :float= lerp(-frame_h / 2.0, frame_h / 2.0, t_y)
		for x in range(grid_width_vertices):
			var t_x := float(x) / x_segments
			var pos_x :float= lerp(-frame_w / 2.0, frame_w / 2.0, t_x)
			vertices.append(Vector2(pos_x, pos_y))
			
	# --- STEP 2: GENERATE CELL CENTERS AND TRIANGULATE "X" ---
	# We append center vertices to the END of the array to keep index tracking simple
	var center_start_index := vertices.size()
	var center_counter := 0
	
	for y in range(y_segments):
		for x in range(x_segments):
			# Calculate indices for the 4 outer corners of this specific cell
			var tl := y * grid_width_vertices + x
			var tr := tl + 1
			var bl := (y + 1) * grid_width_vertices + x
			var br := bl + 1
			
			# Find the physical midpoint position for the center vertex
			var center_pos := (vertices[tl] + vertices[tr] + vertices[bl] + vertices[br]) / 4.0
			vertices.append(center_pos)
			
			# Determine the index of our newly created center point
			var cc := center_start_index + center_counter
			center_counter += 1
			
			# Construct 4 triangles meeting at the center to form the "X" shape
			triangles.append(PackedInt32Array([tl, tr, cc])) # Top Triangle
			triangles.append(PackedInt32Array([tr, br, cc])) # Right Triangle
			triangles.append(PackedInt32Array([br, bl, cc])) # Bottom Triangle
			triangles.append(PackedInt32Array([bl, tl, cc])) # Left Triangle
			
	# Update the Godot Polygon2D node structures
	poly.polygon = vertices
	poly.polygons = triangles
	poly.internal_vertex_count = vertices.size() - 4
	
	# --- STEP 3: GENERATE CORRESPONDING UV COORDINATES (FRAME 0 BASELINE) ---
	var initial_uvs := PackedVector2Array()
	initial_uvs.resize(vertices.size())
	
	for i in range(vertices.size()):
		var p := vertices[i]
		# Map the (-w/2, w/2) range back to a normalized (0.0 to 1.0) space
		var norm_x := (p.x / frame_w) + 0.5
		var norm_y := (p.y / frame_h) + 0.5
		initial_uvs[i] = Vector2(norm_x * frame_w, norm_y * frame_h)
		
	poly.uv = initial_uvs
	
	# Commit properties to the editor engine interface
	poly.notify_property_list_changed()

# --- SKELETON SETUP AND BINDING UTILITIES ---
@export_group("Skeleton Automation Configuration")
## The number of deformation bone segments to build up the middle of the card mesh bounds
@export var bone_segments: int = 5

@export_tool_button("Generate Skeleton & Bind Layers")
var editor_setup_skeleton : Callable = func() -> void:
	# 1. Gather all active Polygon2D nodes from your visual layer tree
	var visual_container := get_node_or_null("Offset/Visual")
	if not visual_container:
		printerr("CardVisual Tool: Could not find 'Offset/Visual' node pathway!")
		return
		
	var polygon_layers: Array[Polygon2D] = []
	for child in visual_container.get_children():
		if child is Polygon2D:
			polygon_layers.append(child)
			
	if polygon_layers.is_empty():
		printerr("CardVisual Tool: No Polygon2D layers detected inside Offset/Visual!")
		return

	# 2. Dynamically scan all vertices to locate the top-most and bottom-most points in local space
	var highest_y: float = INF
	var lowest_y: float = -INF
	
	for poly in polygon_layers:
		for vertex in poly.polygon:
			# Convert the local vertex position to CardVisual's local coordinate space
			var card_local_pos := to_local(poly.to_global(vertex))
			if card_local_pos.y < highest_y:
				highest_y = card_local_pos.y # Top-most vertex (smallest Y)
			if card_local_pos.y > lowest_y:
				lowest_y = card_local_pos.y # Bottom-most vertex (largest Y)

	# Fallback safety check if meshes are completely invalid
	if highest_y == INF or lowest_y == -INF:
		printerr("CardVisual Tool: Could not calculate mesh bounds. Are the layer polygons empty?")
		return

	# Determine the real, total height of the combined geometry
	var absolute_height := lowest_y - highest_y
	var segment_height := absolute_height / float(bone_segments)

	# 3. Setup or clean the Skeleton2D container
	var skeleton: Skeleton2D = get_node_or_null("Skeleton2D")
	if skeleton:
		for child in skeleton.get_children():
			child.queue_free()
	else:
		skeleton = Skeleton2D.new()
		skeleton.name = "Skeleton2D"
		add_child(skeleton)
		skeleton.owner = get_tree().edited_scene_root

	# 4. Generate the vertical Bone2D chain from BOTTOM to TOP based on real vertices
	var bones: Array[Bone2D] = []
	var previous_bone: Node = skeleton
	
	for i in range(bone_segments):
		var bone := Bone2D.new()
		bone.name = "Bone_" + str(i)
		
		# Root bone is placed exactly at the lowest (bottom-most) vertex position
		if i == 0:
			bone.position = Vector2(0, lowest_y)
		else:
			# Successive children climb straight up the card (-Y axis in Godot)
			bone.position = Vector2(0, -segment_height)
			
		# Rotate the root bone -90 degrees so the chain visually aims straight up the spine
		bone.rotation = -PI/2.0 if i == 0 else 0.0
		
		previous_bone.add_child(bone)
		bone.owner = get_tree().edited_scene_root
		
		# Lock the current position as the neutral rest pose to prevent mesh warping on bind
		bone.rest = bone.transform
		bones.append(bone)
		previous_bone = bone

	# 5. Bind every discovered layer layer-by-layer to this new custom-fit skeleton
	for poly in polygon_layers:
		_bind_layer_to_bones(poly, skeleton, bones)
		
	print("CardVisual Tool: Symmetrically built bone chain from Y:", lowest_y, " to Y:", highest_y, " across ", bone_segments, " segments!")


## Internal weight-painting logic mapping vertices safely using dynamic vertical proximity
func _bind_layer_to_bones(poly: Polygon2D, skeleton: Skeleton2D, bones: Array[Bone2D]) -> void:
	poly.skeleton = poly.get_path_to(skeleton)
	poly.clear_bones()
	
	# Register each bone path track inside the Polygon engine profile
	for bone in bones:
		poly.add_bone(poly.get_path_to(bone), PackedFloat32Array())
		
	var vertices := poly.polygon
	if vertices.is_empty():
		return
		
	# Pre-allocate weight sheets for each bone
	var bone_weight_matrices: Array[PackedFloat32Array] = []
	for b in bones:
		var weight_sheet := PackedFloat32Array()
		weight_sheet.resize(vertices.size())
		weight_sheet.fill(0.0)
		bone_weight_matrices.append(weight_sheet)
		
	# Loop through vertices and assign 100% rigid weight to the closest vertical bone split
	for v_idx in range(vertices.size()):
		var vertex_pos := vertices[v_idx]
		
		var closest_bone_idx := 0
		var shortest_vertical_distance := INF
		
		for b_idx in range(bones.size()):
			# Evaluate the bone position directly inside this specific polygon node's space
			var bone_local_pos := poly.to_local(bones[b_idx].global_position)
			var v_dist :float= abs(vertex_pos.y - bone_local_pos.y)
			
			if v_dist < shortest_vertical_distance:
				shortest_vertical_distance = v_dist
				closest_bone_idx = b_idx
				
		# Map full influence to the closest calculated segment point
		bone_weight_matrices[closest_bone_idx][v_idx] = 1.0

	# Apply weight allocations directly to the engine properties
	for b_idx in range(bones.size()):
		poly.set_bone_weights(b_idx, bone_weight_matrices[b_idx])
		
	poly.notify_property_list_changed()

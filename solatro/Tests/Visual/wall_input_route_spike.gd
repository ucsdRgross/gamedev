extends Node
# res://Tests/Visual/wall_input_route_spike.gd
# ==============================================================================
# INVESTIGATION (debugging TestWallInput's I1 failure): does an isolated SubViewport's Camera2D
# zoom correctly propagate into %Screen's get_global_transform_with_canvas(), and does
# WallInput.route()'s inverse+scale formula correctly round-trip back to the sprite's local
# origin, at zoom 0.5/1.0/2.0? Prints the raw numbers. Self-quits. Not a regression test.
# ==============================================================================

const WALL_PICTURE_SCENE := preload("res://UI/Wall/wall_picture.tscn")

func _ready() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	var camera := Camera2D.new()
	viewport.add_child(camera)
	camera.make_current()
	var pictures_viewports := Node.new()
	viewport.add_child(pictures_viewports)

	var design_size := Vector2i(200, 150)
	var rect := PictureRect.new(&"a", Vector2(300, -150), Vector2(design_size), Vector4(10, 10, 10, 10))
	var entry := PictureEntry.new()
	entry.id = &"a"
	entry.design_size = design_size
	var wp : WallPicture = WALL_PICTURE_SCENE.instantiate()
	viewport.add_child(wp)
	wp.build(rect, entry, pictures_viewports)
	wp.focus()
	var screen : Sprite2D = wp.get_node(^"%Screen")

	for zoom : float in [0.5, 1.0, 2.0]:
		camera.zoom = Vector2(zoom, zoom)
		await get_tree().process_frame
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var global_xform := screen.get_global_transform_with_canvas()
		var event_pos : Vector2 = global_xform * Vector2.ZERO
		var inverse := global_xform.affine_inverse()
		var scale_factor := Vector2(wp.viewport.size) / (Vector2(screen.texture.get_size()) * screen.scale)
		var combined := inverse.scaled(scale_factor)
		var round_trip : Vector2 = combined * event_pos
		var half_vp := Vector2(wp.viewport.size) * 0.5
		# What WallInput.route() ACTUALLY does now: xformed_by(combined, half_vp) on a real
		# InputEventMouseButton -- read back its own .position to see xformed_by()'s TRUE local_ofs
		# order empirically, rather than trusting an assumption about it.
		var probe_event := InputEventMouseButton.new()
		probe_event.position = event_pos
		var xformed := probe_event.xformed_by(combined, half_vp) as InputEventMouseButton
		print("SPIKE zoom=%.1f camera.zoom=%s event_pos=%s round_trip=%s half_vp=%s xformed_by_result=%s "
				% [zoom, camera.zoom, event_pos, round_trip, half_vp, xformed.position]
				+ "expected_button_centre=(100,75)")

	wp.teardown()
	print("SPIKE_DONE")
	get_tree().quit()

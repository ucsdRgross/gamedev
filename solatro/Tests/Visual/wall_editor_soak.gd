extends Node2D
# res://Tests/Visual/wall_editor_soak.gd
# ==============================================================================
# WALL EDITOR SOAK — drives the REAL Tools/wall_editor.tscn through many settings combinations and
# presses the REAL overlay buttons, reporting what it observed. A diagnostic, not a suite member:
# it prints and screenshots, and the screenshots are the evidence. Nothing here asserts a look.
#
# It DOES assert the things that are mechanically checkable — a button that should be disabled, a
# focus that should have changed, a camera that should have moved — because those are the failures
# a screenshot cannot show and a human would not notice.
#
# Run windowed, WITH AN EXTERNAL KILLING TIMEOUT:
#     OUT_DIR=<abs path> <console exe> --path solatro res://Tests/Visual/wall_editor_soak.tscn
# ==============================================================================

const WALL_EDITOR_SCENE := preload("res://Tools/wall_editor.tscn")

var _editor : WallEditor = null
var _problems : Array[String] = []
var _checks := 0

func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("wall_editor_soak needs a REAL renderer. Re-run WITHOUT --headless.")
		get_tree().quit(1)
		return
	DisplayServer.window_set_size(Vector2i(1280, 720))
	_editor = WALL_EDITOR_SCENE.instantiate()
	add_child(_editor)
	await _settle()

	await _case_defaults_on_open()
	await _case_overlay_buttons()
	await _case_overlay_during_a_move()
	await _case_extreme_aspects()
	await _case_extreme_knobs()
	await _case_partial_unlock()
	await _case_reduced_motion()
	await _case_the_real_wall_is_what_is_hosted()
	await _case_wall_view_render_resolution()
	await _case_authoring_extremes()
	await _case_info_mode_reaches_a_hosted_screen()
	await _case_info_transition_does_not_snap()
	await _case_the_card_visual_is_inert()
	await _case_info_mode_is_per_picture()

	print("\n======== WALL EDITOR SOAK: %d checks, %d problem(s) ========" % [_checks, _problems.size()])
	for line : String in _problems:
		printerr("[PROBLEM] " + line)
	get_tree().quit(_problems.size())

# ============================================================== cases

## Everything a fresh open should already be, with nothing typed in.
func _case_defaults_on_open() -> void:
	_check(_editor.layout != null, "a layout is loaded on open")
	_check(_editor.preview_settings != null, "preview_settings is never null")
	_check(_editor.unlocked_ids.size() == _editor.layout.pictures.size(),
			"every picture is unlocked by default, so the whole wall is visible",
			"%d of %d" % [_editor.unlocked_ids.size(), _editor.layout.pictures.size()])
	_check(_editor.preview_source_id != &"" and _editor.preview_dest_id != &"",
			"the transition pair is seeded, not blank",
			"%s -> %s" % [_editor.preview_source_id, _editor.preview_dest_id])
	_check(_editor.preview_source_id != _editor.preview_dest_id,
			"...and the seeded pair is two DIFFERENT pictures")
	# ⚠ The default must be the LIVE window aspect, not a rounded literal: `focused_scale()` skips
	# its overfill margin only on EXACT ratio equality, so a rounded default crops 2% off every
	# focused picture and makes real UI look like it overflows.
	var window := Vector2(get_viewport().get_visible_rect().size)
	_check(is_equal_approx(_editor.preview_aspect, window.x / window.y),
			"preview_aspect opens at the REAL window aspect, not a rounded literal",
			"%.8f vs %.8f" % [_editor.preview_aspect, window.x / window.y])
	_check(_overlay() != null, "the real overlay exists")
	_check(_info_card() != null, "the real info card exists")
	_shot("01_defaults")

## Every overlay button, pressed for real, with its enabled state checked before and after.
func _case_overlay_buttons() -> void:
	var ov := _overlay()
	_check(_button(ov, "BackButton").disabled,
			"Back starts DISABLED in wall view with an empty history")
	_check(_button(ov, "ForwardButton").disabled, "Forward starts DISABLED")
	_check(_button(ov, "WallButton").visible,
			"the Wall button is visible with more than one picture")

	# Enter a picture, then use Back to leave it.
	var first := _editor.layout.home_id
	await _editor._move_to(first)
	_check(_editor.preview_focus_id == first, "entering a picture focuses it",
			str(_editor.preview_focus_id))
	_shot("02_focused_via_move")

	var second := _other_id(first)
	await _editor._move_to(second)
	_check(_editor.preview_focus_id == second, "a second move lands on the second picture",
			str(_editor.preview_focus_id))
	_check(not _button(ov, "BackButton").disabled,
			"Back is ENABLED once there is history behind the current picture")

	_press(_button(ov, "BackButton"))
	await _wait_for_move()
	_check(_editor.preview_focus_id == first, "pressing Back retraces exactly one step",
			str(_editor.preview_focus_id))
	_check(not _button(ov, "ForwardButton").disabled, "...and Forward is now ENABLED")

	_press(_button(ov, "ForwardButton"))
	await _wait_for_move()
	_check(_editor.preview_focus_id == second, "pressing Forward redoes that step",
			str(_editor.preview_focus_id))

	_press(_button(ov, "WallButton"))
	await _wait_for_move()
	_check(_editor.preview_focus_id == &"", "pressing Wall returns to wall view",
			str(_editor.preview_focus_id))
	_shot("03_wall_view_via_button")

	# Info is a toggle button; pressing it must drive the tool's own info mode.
	var info_button := _button(ov, "InfoButton")
	await _editor._move_to(first)

	# ⚠ INFO MODE MUST ANIMATE, NOT SNAP. The game tweens the camera to the info pose over
	# `wall_transition_delay * wall_info_zoom_scale`; a tool that jumps there instead cannot be used
	# to judge how the reveal feels, which is most of what the panel is for. Sampled two frames
	# apart and again later: it must be MOVING at first and STILL by the end.
	# ⚠ INFO MODE ZOOMS OUT; IT DOES NOT PAN. The camera stays CENTRED on the picture, so `zoom` is
	# the observable, not `position` -- panning down would crop the top of the screen, which is the
	# whole thing info mode must not do.
	var rest_zoom := _editor._camera.zoom.x
	var rest_pos := _editor._camera.position
	info_button.button_pressed = true
	await get_tree().process_frame
	await get_tree().process_frame
	var mid_zoom := _editor._camera.zoom.x
	_check(not is_equal_approx(mid_zoom, rest_zoom),
			"toggling info mode starts the camera zooming")
	_check(not is_equal_approx(mid_zoom, _expected_info_zoom(first)),
			"...and it is ANIMATING, not already at the info zoom two frames in",
			"mid %.5f vs target %.5f" % [mid_zoom, _expected_info_zoom(first)])
	await _wait_for_camera()
	_check(is_equal_approx(_editor._camera.zoom.x, _expected_info_zoom(first)),
			"...and it arrives at the info zoom",
			"%.5f vs %.5f" % [_editor._camera.zoom.x, _expected_info_zoom(first)])
	_check(_editor._camera.position.y > rest_pos.y,
			"...shifting DOWN only as far as the reserved card band, never cropping the top",
			"%s vs rest %s" % [_editor._camera.position, rest_pos])
	_check(_editor._camera.zoom.x < rest_zoom,
			"...and it zooms OUT, never in", "%.5f vs rest %.5f" % [_editor._camera.zoom.x, rest_zoom])
	# Nothing may be cropped while info mode is on: the visible rect must contain the whole picture.
	var info_rect := _editor._rect_for(first)
	var picture := Rect2(info_rect.centre - info_rect.size * 0.5, info_rect.size)
	_check(_camera_visible_rect().encloses(picture),
			"the WHOLE screen is visible in info mode -- nothing cropped by the window",
			"visible %s vs picture %s" % [_camera_visible_rect(), picture])
	# ⚠ AND NOTHING COVERED BY THE CARD EITHER. That is the point of moving the camera at all: the
	# picture's on-screen bottom edge must clear the card, bar the authored overlap.
	var card := _info_card()
	var vis := _camera_visible_rect()
	var zoom_now : float = _editor._camera.zoom.x
	var picture_bottom_px : float = (picture.end.y - vis.position.y) * zoom_now
	var card_top_px : float = float(get_viewport().get_visible_rect().size.y) - card.size.y
	var overlap : float = _editor.preview_settings.wall_info_card_overlap
	_check(card.size.y < _editor.preview_settings.wall_info_card_max_height - 1.0,
			"sanity: this entry is SHORTER than the cap, so reserving the cap would over-zoom",
			"card %.0f vs cap %.0f" % [card.size.y,
			_editor.preview_settings.wall_info_card_max_height])
	_check(picture_bottom_px <= card_top_px + overlap + 1.0,
			"...and the card covers no more of the screen than wall_info_card_overlap allows",
			"picture bottom %.0f px vs card top %.0f + overlap %.0f"
			% [picture_bottom_px, card_top_px, overlap])
	_check(_editor.preview_info_mode, "the Info BUTTON turns info mode on")
	_check(_info_card().visible, "...and the info card is actually showing")
	# The card carries a preview image BESIDE its text. It must be at least as tall as that image,
	# or it scrolls content it had room to show -- and `wall_info_card_max_height` is then tuning
	# against a height the card never reaches.
	var slot := card.get_node(^"%VisualSlot") as Control
	var visual_h : float = slot.get_combined_minimum_size().y if slot else 0.0
	_check(visual_h > 0.0, "the info entry really did carry a visual", "%.0f px" % visual_h)
	_check(card.size.y >= visual_h - 0.5,
			"the card is at least as tall as the preview beside its text",
			"card %.0f vs visual %.0f" % [card.size.y, visual_h])
	_check(card.size.y <= _editor.preview_settings.wall_info_card_max_height + 0.5,
			"...and never taller than wall_info_card_max_height",
			"card %.0f vs cap %.0f" % [card.size.y,
			_editor.preview_settings.wall_info_card_max_height])
	_shot("04_info_via_button")
	info_button.button_pressed = false
	await _wait_for_camera()
	_check(not _editor.preview_info_mode, "...and pressing it again turns it off")
	_check(not _info_card().visible, "...and the card is hidden again")

	# The other direction: setting the FLAG must move the BUTTON, or the two can disagree —
	# info mode on with the control that caused it reading un-pressed.
	_editor.preview_info_mode = true
	await _settle()
	_check(info_button.button_pressed,
			"setting info mode from the Inspector presses the overlay's own button")
	_editor.preview_info_mode = false
	await _settle()
	_check(not info_button.button_pressed, "...and clearing it releases the button")
	await _editor._move_to(&"")

## The interaction the overlay exists here to expose: pressing a button WHILE a move runs.
func _case_overlay_during_a_move() -> void:
	var ov := _overlay()
	var a := _editor.layout.home_id
	var b := _other_id(a)
	await _editor._move_to(a)

	# Start a move and press Wall two frames in, while it is genuinely still running.
	_editor._move_to(b)
	await get_tree().process_frame
	await get_tree().process_frame
	_check(_editor._move_active, "sanity: the move really is in flight when the button is pressed")
	_check(not _button(ov, "WallButton").disabled,
			"the overlay stays PRESSABLE during a move -- the game locks wall input, not these")
	_press(_button(ov, "WallButton"))
	await _wait_for_move()
	_check(_editor.preview_focus_id == b,
			"a press during a move is IGNORED, not half-applied -- the move still lands on its own "
			+ "destination", str(_editor.preview_focus_id))
	_check(not _editor._move_active, "...and nothing is left stuck in flight")
	_shot("05_after_press_during_move")
	await _editor._move_to(&"")

## The clamps only do anything at the extremes, so that is where they get looked at.
func _case_extreme_aspects() -> void:
	for aspect : float in [0.5, 1.0, 1.7778, 3.0, 4.0]:
		_editor.preview_aspect = aspect
		await _settle()
		_check(_editor._last_rects.size() == _editor.unlocked_ids.size(),
				"every unlocked picture still packs at aspect %.2f" % aspect,
				"%d rects" % _editor._last_rects.size())
		_check(not _overlapping(), "...and no two frames overlap at aspect %.2f" % aspect)
		_shot("06_aspect_%.2f" % aspect)
	_editor.preview_aspect = 1.7778
	await _settle()

## Values an author will reach for, including the ones that look like they should break something.
func _case_extreme_knobs() -> void:
	var layout := _editor.layout
	var original_gap := layout.gap_px
	for gap : float in [0.0, 200.0]:
		layout.gap_px = gap
		_editor._repack()
		await _settle()
		_check(_editor._last_rects.size() == _editor.unlocked_ids.size(),
				"every picture packs at gap_px = %.0f" % gap)
		_check(not _overlapping(), "...and none overlap at gap_px = %.0f" % gap)
		_shot("07_gap_%.0f" % gap)
	layout.gap_px = original_gap

	var original_margin : float = _editor.preview_settings.wall_overfill_margin
	_editor.preview_settings.wall_overfill_margin = 1.0
	_editor.preview_focus_id = _editor.layout.home_id
	await _settle()
	_shot("08_overfill_1.00_focused")   # a frame sliver here is the defect this knob prevents
	# H3 as ARITHMETIC: at rest the camera's visible rect must sit strictly inside the picture's
	# own rect, so no frame and no bare wall can reach a window edge. A screenshot shows this at
	# one aspect; this shows it at the one the tool is set to, every run.
	_check(_visible_rect_inside_picture(_editor.layout.home_id),
			"a focused picture at rest covers the whole window -- no frame at any edge",
			_coverage_detail(_editor.layout.home_id))
	# ⚠ AT A MATCHING ASPECT THE MARGIN MUST NOT FIRE. `focused_scale()` only skips it on EXACT
	# ratio equality, and a rounded `preview_aspect` misses that by ~1.4e-05 -- so the picture gets
	# cropped 2% and real UI loses its outer edges, which the game never does.
	var window := Vector2(get_viewport().get_visible_rect().size)
	_editor.preview_aspect = window.x / window.y
	await _settle()
	var rect := _editor._rect_for(_editor.layout.home_id)
	var visible := _camera_visible_rect()
	_check(is_equal_approx(visible.size.x, rect.size.x) and is_equal_approx(visible.size.y, rect.size.y),
			"at a matching aspect a focused picture is shown WHOLE -- no overfill crop",
			"visible %s vs picture %s" % [visible.size, rect.size])
	_editor.preview_settings.wall_overfill_margin = 1.25
	await _settle()
	_shot("09_overfill_1.25_focused")
	_editor.preview_settings.wall_overfill_margin = original_margin
	_editor.preview_focus_id = &""
	await _settle()

	var original_view_margin := layout.view_margin
	for margin : float in [0.0, 0.5]:
		layout.view_margin = margin
		_editor._repack()
		await _settle()
		_shot("10_view_margin_%.2f" % margin)
		# ⚠ THE SEAM. The tool must frame the wall by the SAME formula `Wall.wall_view_zoom()` uses,
		# or composition judged here is composition the game never draws. Computed independently
		# from the layout and the window, never read back off the tool.
		var extent := _editor._wall_extent()
		var expected := WallPicture.focused_scale(extent.size,
				Vector2(get_viewport().get_visible_rect().size), 1.0 + margin)
		_check(is_equal_approx(_editor._camera.zoom.x, expected),
				"wall view is framed by view_margin = %.2f, exactly as the game frames it" % margin,
				"tool %.5f vs game %.5f" % [_editor._camera.zoom.x, expected])
	layout.view_margin = original_view_margin
	_editor._repack()
	await _settle()

## A locked wall, which is what a real save looks like early on.
func _case_partial_unlock() -> void:
	var full : Array[StringName] = _editor.unlocked_ids.duplicate()
	var two : Array[StringName] = [_editor.layout.home_id, _other_id(_editor.layout.home_id)]
	_editor.unlocked_ids = two
	await _settle()
	_check(_editor._last_rects.size() == 2, "a two-picture wall packs",
			"%d rects" % _editor._last_rects.size())
	_shot("11_two_pictures")

	_editor.unlocked_ids = [_editor.layout.home_id] as Array[StringName]
	await _settle()
	_check(_editor._last_rects.size() == 1, "a ONE-picture wall packs",
			"%d rects" % _editor._last_rects.size())
	_check(not _button(_overlay(), "WallButton").visible,
			"the Wall button HIDES with a single picture -- nothing to overview")
	_shot("12_one_picture")
	_editor.unlocked_ids = full
	await _settle()

## The accessibility path, which replaces the whole camera move with a cross-fade.
func _case_reduced_motion() -> void:
	_editor.preview_settings.wall_reduced_motion = true
	var a := _editor.layout.home_id
	var b := _other_id(a)
	await _editor._move_to(a)
	await _editor._move_to(b)
	_check(_editor.preview_focus_id == b, "a reduced-motion move still lands", str(_editor.preview_focus_id))
	var rect := _editor._rect_for(b)
	_check(_editor._camera.position.is_equal_approx(rect.centre),
			"...and rests on the destination, not wherever the fade stopped",
			"%s vs %s" % [_editor._camera.position, rect.centre])
	_shot("13_reduced_motion_landed")
	_editor.preview_settings.wall_reduced_motion = false
	await _editor._move_to(&"")

## The point of hosting a real `Wall`: the knobs that only IT can reach must actually reach it.
## Every check here would have been impossible against the hand-built scaffold.
func _case_the_real_wall_is_what_is_hosted() -> void:
	var wall : Wall = _editor._wall
	_check(wall != null, "the tool hosts a REAL Wall when run, not a stand-in")
	if wall == null: return
	_check(get_tree().paused,
			"...and KEEPS its global pause, which is what freezes an unfocused screen")
	_check(_editor.process_mode == Node.PROCESS_MODE_ALWAYS,
			"...while the tool itself opts out, or it would freeze with everything else")
	_check(_editor.knobs_this_preview_does_not_drive == "",
			"no knob is inert when the real Wall is hosted",
			_editor.knobs_this_preview_does_not_drive)

	# ARROW SELECTION and its held-direction repeat -- `Wall._process`, unreachable before.
	await _editor._move_to(&"")
	wall.enter_wall_view(_editor.layout.home_id)
	# ⚠ Nothing may still report as focused in wall view. A stale `is_focused` makes
	# `Wall._focused_picture()` non-null, and both the filter update and the selection repeat bail
	# on that -- silently, with no other symptom.
	_check(wall._focused_picture() == null,
			"nothing is left focused in wall view", str(wall._focused_picture()))
	var before := wall.selected_id
	wall.move_selection(Vector2.RIGHT)
	_check(wall.selected_id != before, "the wall's own arrow selection moves the cursor",
			"%s -> %s" % [before, wall.selected_id])
	_check(wall.selection_visible, "...and the cursor becomes visible once earned")
	_shot("14_wall_selection")

	# `wall_selection_repeat_delay`: a held direction must repeat, and the KNOB must set the pace.
	_editor.preview_settings.wall_selection_repeat_delay = 0.05
	var start_id := wall.selected_id
	wall._hold(Vector2.RIGHT)
	var moved := 0
	for _i : int in 30:
		await get_tree().process_frame
		if wall.selected_id != start_id:
			moved += 1
			start_id = wall.selected_id
	wall._release(Vector2.RIGHT)
	_check(moved > 0, "a HELD direction repeats -- wall_selection_repeat_delay is live",
			"%d repeats in 30 frames" % moved)

	# `wall_debug_readout` -- Wall.debug_memory_readout(), also unreachable before.
	var readout := wall.debug_memory_readout()
	_check(readout.contains("screens instantiated"), "the debug readout reports real numbers",
			readout)

	# `wall_unlock_all` must widen the wall exactly as it does in the game.
	var two : Array[StringName] = [_editor.layout.home_id]
	_editor.unlocked_ids = two
	await _settle()
	var locked_count := _editor._last_rects.size()
	_editor.preview_settings.wall_unlock_all = true
	_editor._repack()
	await _settle()
	_check(_editor._last_rects.size() > locked_count,
			"wall_unlock_all widens the wall past unlocked_ids, as it does in the game",
			"%d -> %d" % [locked_count, _editor._last_rects.size()])
	_editor.preview_settings.wall_unlock_all = false
	_editor.unlocked_ids = _all_ids()
	await _settle()

	# `wall_reveal_delay_scale` -- the opening reveal, the last knob with no other driver.
	await _editor._move_to(_editor.layout.home_id)
	_editor.preview_settings.wall_reveal_delay_scale = 3.0
	var started := Time.get_ticks_msec()
	_editor.play_reveal = true
	await _wait_for_move()
	var slow_ms := Time.get_ticks_msec() - started
	await _editor._move_to(_editor.layout.home_id)
	_editor.preview_settings.wall_reveal_delay_scale = 0.1
	started = Time.get_ticks_msec()
	_editor.play_reveal = true
	await _wait_for_move()
	var fast_ms := Time.get_ticks_msec() - started
	_check(slow_ms > fast_ms * 2,
			"the reveal's LENGTH tracks wall_reveal_delay_scale",
			"scale 3.0 took %d ms, scale 0.1 took %d ms" % [slow_ms, fast_ms])
	_editor.preview_settings.wall_reveal_delay_scale = 1.8
	_shot("15_after_reveal")

## SETTLES whether a screen re-flows into its wall-view render target or CROPS.
##
## ⚠ This is evidence about the SHIPPED GAME, not only about the tool. `Main._build_pictures()` and
## `_repack_wall()` both call the same `WallPicture.update_wall_view_size(_footprint(...))` on every
## non-focused picture, so whatever this renders is what the game renders. Read
## `16_wall_view_resolution.png` and compare it with `01_defaults.png`.
func _case_wall_view_render_resolution() -> void:
	await _editor._move_to(&"")
	var home := _editor.layout.home_id
	var before := Vector2i((_editor._preview_pictures[home] as WallPicture).viewport.size)
	_editor.preview_wall_view_resolution = true
	await _settle()
	# ⚠ RE-FETCH. Setting the flag repacks, which tears down and rebuilds every preview picture, so
	# a handle taken before the await points at a freed node.
	var after := Vector2i((_editor._preview_pictures[home] as WallPicture).viewport.size)
	_check(after != before,
			"the flag really does resize the render target -- the numbers below mean something",
			"%s -> %s" % [before, after])
	print("  WALL-VIEW RESOLUTION: %s design -> %s footprint (%.0f%% of each axis)"
			% [before, after,
			100.0 * float(after.x) / maxf(float(before.x), 1.0)])
	# ⚠ THE GUARD FOR THE CROP. `size` is the render RESOLUTION; `size_2d_override` is what keeps
	# the CANVAS at design size so the screen shrinks instead of showing its top-left corner.
	# Without it a 1152x648 start menu rendered as a giant "S" at this target.
	var vp : SubViewport = (_editor._preview_pictures[home] as WallPicture).viewport
	_check(vp.size_2d_override == Vector2i(1152, 648),
			"an unfocused picture LAYS OUT at design size while rendering at its footprint",
			"override %s, size %s" % [vp.size_2d_override, vp.size])
	_check(vp.size_2d_override_stretch,
			"...and the override actually stretches onto the render target")
	_shot("16_wall_view_resolution")

	# Focused renders 1:1, so the override must be OFF -- `WallInput.route()` maps into a plain
	# viewport and a stale override would displace every click inside a focused screen.
	await _editor._move_to(home)
	var focused_vp : SubViewport = (_editor._preview_pictures[home] as WallPicture).viewport
	_check(focused_vp.size_2d_override == Vector2i.ZERO,
			"a FOCUSED picture clears the override -- input routing depends on it",
			str(focused_vp.size_2d_override))
	await _editor._move_to(&"")
	_editor.preview_wall_view_resolution = false
	await _settle()

## Values an AUTHOR can reach through the Inspector but no fixture has ever used. Each one is a
## field on `PictureEntry`, so any of them can be typed into `layout_default.tres` tomorrow.
func _case_authoring_extremes() -> void:
	await _editor._move_to(&"")
	var entry : PictureEntry = _editor.layout.pictures[0]
	var keep := {"size": entry.size_multiplier, "design": entry.design_size,
			"frame": entry.frame_px, "aspect": entry.keep_aspect}

	for mult : float in [0.05, 8.0]:
		entry.size_multiplier = mult
		_editor._repack()
		await _settle()
		_check(_editor._last_rects.size() == _editor.unlocked_ids.size(),
				"every picture still packs at size_multiplier %.2f" % mult)
		_check(not _overlapping(), "...and none overlap at size_multiplier %.2f" % mult)
		_check(_finite_rects(), "...and every rect is finite at size_multiplier %.2f" % mult)
	entry.size_multiplier = keep["size"]

	# A frame thicker than the picture it surrounds -- the packer measures gaps against frame OUTER
	# rects, so this is the case where the frame, not the picture, decides the layout.
	entry.frame_px = Vector4(400, 400, 400, 400)
	_editor._repack()
	await _settle()
	_check(not _overlapping(), "a frame thicker than its picture still packs without overlap")
	_check(_finite_rects(), "...and produces finite rects")
	_shot("17_fat_frame")
	entry.frame_px = keep["frame"]

	# keep_aspect: the picture must NOT stretch to the window, at an aspect far from its own.
	entry.keep_aspect = true
	_editor.preview_aspect = 3.0
	_editor._repack()
	await _settle()
	var rect := _editor._rect_for(entry.id)
	_check(rect != null and is_equal_approx(rect.size.x / rect.size.y,
			float(entry.design_size.x) / float(entry.design_size.y)),
			"keep_aspect holds the AUTHORED aspect at a 3.0 window",
			"%s vs design %s" % [rect.size if rect else "null", entry.design_size])
	_shot("18_keep_aspect")
	entry.keep_aspect = keep["aspect"]

	# A tiny design size: the render target must still clear wall_view_min_texture_px.
	entry.design_size = Vector2i(16, 9)
	_editor._repack()
	await _settle()
	var wp : WallPicture = _editor._preview_pictures[entry.id]
	var floor_px : int = _editor.preview_settings.wall_view_min_texture_px
	_check(wp.viewport.size.x >= 1 and wp.viewport.size.y >= 1,
			"a 16x9 design size never asks the GPU for a degenerate target",
			str(wp.viewport.size))
	_editor.preview_wall_view_resolution = true
	await _settle()
	wp = _editor._preview_pictures[entry.id]
	_check(wp.viewport.size.x >= floor_px and wp.viewport.size.y >= floor_px,
			"...and wall_view_min_texture_px is the floor it clamps to",
			"%s vs floor %d" % [wp.viewport.size, floor_px])
	_editor.preview_wall_view_resolution = false
	entry.design_size = keep["design"]
	_editor.preview_aspect = _window_aspect()
	_editor._repack()
	await _settle()

## Does Info mode actually reach a SCREEN hosted inside a picture? The whole of GAP-023 depends on
## `PlayArea._info_mode()` seeing the tool's own knob, and nothing else proves that seam: the
## board's popup and the click gate both read it, and both fail silently if it is false.
func _case_info_mode_reaches_a_hosted_screen() -> void:
	var game_wp : WallPicture = _editor._preview_pictures.get(&"game")
	_check(game_wp != null, "the game picture is packed")
	if game_wp == null: return
	_check(game_wp.screen_root != null, "...and hosts a real screen", str(game_wp.screen_root))
	if game_wp.screen_root == null: return
	var pa := _find_play_area(game_wp.screen_root)
	_check(pa != null, "...whose board is a real PlayArea")
	if pa == null: return

	_editor.preview_info_mode = false
	await _settle()
	_check(not pa._info_mode(), "with info mode OFF the board sees it off")
	_editor.preview_info_mode = true
	await _settle()
	_check(pa._info_mode(),
			"⚠ THE SEAM: with the tool's info mode ON the hosted board sees it ON",
			"settings instance match=%s" % str(WallPicture.settings() == _editor.preview_settings))
	_check(pa._focus_info == null or not pa._focus_info.visible,
			"...and the board's own popup is not showing")

	# ⚠ END TO END: a card clicked inside a hosted screen must reach the tool's OWN info card.
	# `_info_mode()` being true proves the board is willing; nothing proved anyone was LISTENING,
	# and nobody was -- the tool never connected `info_requested`, so every entry went nowhere.
	var control := _any_card_control(pa)
	_check(control != null, "the hosted board has a card control to click")
	if control != null:
		_info_card().reset()
		pa.on_control_focus_entered(control)
		pa.info_requested.emit(PlayArea.card_info(pa.ui_data[control]))
		await _settle()
		_check(_info_card().visible,
				"clicking a card in a hosted screen SHOWS it on the wall's info card")
		_check(_info_card().current_entry != null
				and not _info_card().current_entry.title.is_empty(),
				"...carrying that card's own name, not an empty entry",
				_info_card().current_entry.title if _info_card().current_entry else "<null>")
	_editor.preview_info_mode = false
	await _settle()

## ⚠ THE VISUAL IN THE CARD IS A REAL GAME NODE, AND MUST NOT BE ABLE TO ACT LIKE ONE.
## `ControlCard._ready()` makes itself `FOCUS_ALL`, and any `Control` defaults to
## `MOUSE_FILTER_STOP` — so an un-neutered preview would be a focus stop controller navigation can
## land on, and would swallow clicks aimed behind the card. `InfoCard._make_inert()` strips both
## recursively; this proves it on the real entry, every run.
func _case_the_card_visual_is_inert() -> void:
	await _editor._move_to(_editor.layout.home_id)
	_editor.preview_info_mode = true
	await _wait_for_camera()
	var card := _info_card()
	_check(card.current_entry != null and card.current_entry.visual != null,
			"the entry really carries a visual, or the checks below are vacuous")
	if card.current_entry != null and card.current_entry.visual != null:
		var offenders : Array[String] = []
		_collect_interactive(card.current_entry.visual, offenders)
		_check(offenders.is_empty(),
				"every node of the card's visual is non-focusable and mouse-transparent",
				", ".join(offenders))
	_editor.preview_info_mode = false
	await _wait_for_camera()
	await _editor._move_to(&"")

func _collect_interactive(node: Node, out: Array[String]) -> void:
	var control := node as Control
	if control:
		if control.focus_mode != Control.FOCUS_NONE:
			out.append("%s focus_mode=%d" % [control.name, control.focus_mode])
		if control.mouse_filter != Control.MOUSE_FILTER_IGNORE:
			out.append("%s mouse_filter=%d" % [control.name, control.mouse_filter])
	for child : Node in node.get_children():
		_collect_interactive(child, out)

## Info mode is PER PICTURE: turning it on for one screen must not turn it on for another, and a
## screen left in it must still be in it when the player comes back.
func _case_info_mode_is_per_picture() -> void:
	var a := _editor.layout.home_id
	var b := _other_id(a)
	await _editor._move_to(a)
	_editor.preview_info_mode = true
	await _wait_for_camera()
	_check(_editor.preview_info_mode, "info mode is on for the first picture")

	await _editor._move_to(b)
	_check(not _editor.preview_info_mode,
			"...and OFF for a different picture -- the toggle is per screen, not global")

	await _editor._move_to(a)
	_check(_editor.preview_info_mode,
			"...and still ON when the first picture is entered again -- each screen remembers")
	_editor.preview_info_mode = false
	await _wait_for_camera()
	await _editor._move_to(&"")

## Any focusable card control on a hosted board, or null when the board has no cards dealt.
## A transition WITH Info mode on must begin and end exactly where the camera already rests, or it
## visibly jumps at each end.
##
## ⚠ Two separate snaps lived here. The move used to hold the SOURCE's zoom throughout, so a
## differently-sized destination was reached at the wrong zoom and the settle cut to the right one;
## and `sample_at()` computed its pose without the card height, reserving the authored CAP while the
## resting pose reserved the card's LIVE height -- so it jumped the instant the move began.
func _case_info_transition_does_not_snap() -> void:
	var a := _editor.layout.home_id
	var b := _other_id(a)
	# ⚠ THE TWO PICTURES MUST BE DIFFERENT SIZES. At equal sizes their info zooms coincide, so
	# holding the source's zoom and interpolating produce the same numbers and the test cannot tell
	# the readings apart — it passed with the fix removed until this fixture changed.
	var entry_b := _entry_for(b)
	var kept_multiplier : float = entry_b.size_multiplier if entry_b else 1.0
	if entry_b: entry_b.size_multiplier = kept_multiplier * 2.5
	_editor._repack()
	await _settle()
	_check(not is_equal_approx(_editor._rect_for(a).size.y, _editor._rect_for(b).size.y),
			"sanity: the two pictures really are different sizes, or this proves nothing",
			"%s vs %s" % [_editor._rect_for(a).size, _editor._rect_for(b).size])
	await _editor._move_to(a)
	_editor.preview_info_mode = true
	await _wait_for_camera()

	var rest_pos := _editor._camera.position
	var rest_zoom := _editor._camera.zoom.x
	var settings := _editor.preview_settings
	var total := WallTransition.total_duration(settings)
	var card_h := _editor._info_card_height()
	var first := WallTransition.sample_at(0.0, total, _editor._rect_for(a), _editor._rect_for(b),
			Vector2(get_viewport().get_visible_rect().size), settings, card_h)
	_check(first.camera_position.is_equal_approx(rest_pos)
			and is_equal_approx(first.camera_zoom, rest_zoom),
			"an info-mode move STARTS exactly at the resting pose -- no jump on the first frame",
			"start %s/%.5f vs rest %s/%.5f"
			% [first.camera_position, first.camera_zoom, rest_pos, rest_zoom])

	var last := WallTransition.sample_at(total, total, _editor._rect_for(a), _editor._rect_for(b),
			Vector2(get_viewport().get_visible_rect().size), settings, card_h)
	var dest_state := WallPicture.info_zoom_state(_editor._rect_for(b),
			Vector2(get_viewport().get_visible_rect().size), settings, card_h)
	_check(last.camera_position.is_equal_approx(dest_state["position"] as Vector2)
			and is_equal_approx(last.camera_zoom, dest_state["zoom"] as float),
			"...and ENDS exactly on the destination's info pose -- nothing left for a cut",
			"end %s/%.5f vs dest %s/%.5f" % [last.camera_position, last.camera_zoom,
			dest_state["position"], dest_state["zoom"]])
	_editor.preview_info_mode = false
	await _wait_for_camera()
	if entry_b: entry_b.size_multiplier = kept_multiplier
	_editor._repack()
	await _editor._move_to(&"")

## The authored entry for `id`, or null.
func _entry_for(id: StringName) -> PictureEntry:
	for e : PictureEntry in _editor.layout.pictures:
		if e.id == id: return e
	return null

## Any focusable card control on a hosted board, or null when the board has no cards dealt.
func _any_card_control(pa: PlayArea) -> Control:
	for control : Control in pa.ui_data:
		if is_instance_valid(control): return control
	return null

func _find_play_area(node: Node) -> PlayArea:
	var pa := node as PlayArea
	if pa: return pa
	for child : Node in node.get_children():
		var found := _find_play_area(child)
		if found: return found
	return null

func _window_aspect() -> float:
	var w := Vector2(get_viewport().get_visible_rect().size)
	return w.x / w.y if w.y > 0.0 else 1.0

func _finite_rects() -> bool:
	for rect : PictureRect in _editor._last_rects:
		if not (is_finite(rect.centre.x) and is_finite(rect.centre.y)
				and is_finite(rect.size.x) and is_finite(rect.size.y)):
			return false
		if rect.size.x <= 0.0 or rect.size.y <= 0.0: return false
	return true

func _all_ids() -> Array[StringName]:
	var out : Array[StringName] = []
	for e : PictureEntry in _editor.layout.pictures: out.append(e.id)
	return out

# ============================================================== helpers

## Read straight off the tool rather than by node path: when RUN it hosts a real `wall.tscn`, so
## the overlay is that Wall's `%Overlay`, not a node this harness can name.
func _overlay() -> WallOverlay:
	return _editor._overlay

func _info_card() -> InfoCard:
	return _editor._info_card

func _button(ov: WallOverlay, name: String) -> Button:
	return ov.get_node_or_null(NodePath(name)) as Button if ov else null

## A real press, through the same signal a mouse click raises. `disabled` is honoured by hand
## because `emit_signal` bypasses it, and a test that ignores it would report a dead button working.
func _press(button: Button) -> void:
	if button == null or button.disabled:
		_problems.append("tried to press %s but it was disabled/absent"
				% (button.name if button else "<null>"))
		return
	button.pressed.emit()

## The info zoom the tool should end at, computed independently of the tool.
func _expected_info_zoom(id: StringName) -> float:
	var rect := _editor._rect_for(id)
	if rect == null: return 0.0
	var card := _info_card()
	var card_h : float = card.size.y if card and card.visible else -1.0
	var state := WallPicture.info_zoom_state(rect,
			Vector2(get_viewport().get_visible_rect().size), _editor.preview_settings, card_h)
	return state["zoom"] as float

## Waits for the camera to stop moving, rather than for a fixed number of frames.
func _wait_for_camera() -> void:
	var started := Time.get_ticks_msec()
	var last := Vector3(_editor._camera.position.x, _editor._camera.position.y,
			_editor._camera.zoom.x)
	var still := 0
	while still < 4 and Time.get_ticks_msec() - started < 8000:
		await get_tree().process_frame
		var now := Vector3(_editor._camera.position.x, _editor._camera.position.y,
				_editor._camera.zoom.x)
		still = still + 1 if now.is_equal_approx(last) else 0
		last = now
	await _settle()

func _wait_for_move() -> void:
	var started := Time.get_ticks_msec()
	while _editor._move_active and Time.get_ticks_msec() - started < 8000:
		await get_tree().process_frame
	await _settle()

func _other_id(besides: StringName) -> StringName:
	for rect : PictureRect in _editor._last_rects:
		if rect.id != besides: return rect.id
	return &""

## Rule 6 from the packer, checked from outside it: no two frame outer rects may intersect.
func _overlapping() -> bool:
	var frames : Array[Rect2] = []
	for rect : PictureRect in _editor._last_rects:
		var frame := WallPacker.frame_outer_rect(rect)
		for other : Rect2 in frames:
			if frame.intersects(other): return true
		frames.append(frame)
	return false

## The camera's visible rect in wall space, at its current pose.
func _camera_visible_rect() -> Rect2:
	var size := Vector2(get_viewport().get_visible_rect().size) / _editor._camera.zoom.x
	return Rect2(_editor._camera.position - size * 0.5, size)

func _visible_rect_inside_picture(id: StringName) -> bool:
	var rect := _editor._rect_for(id)
	if rect == null: return false
	var picture := Rect2(rect.centre - rect.size * 0.5, rect.size)
	return picture.encloses(_camera_visible_rect())

func _coverage_detail(id: StringName) -> String:
	var rect := _editor._rect_for(id)
	if rect == null: return "no rect"
	return "visible %s vs picture %s" % [_camera_visible_rect(),
			Rect2(rect.centre - rect.size * 0.5, rect.size)]

func _check(ok: bool, what: String, detail: String = "") -> void:
	_checks += 1
	if ok: return
	_problems.append(what + ("" if detail.is_empty() else "  (got: %s)" % detail))

func _settle() -> void:
	for _i : int in 3:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw

func _shot(name: String) -> void:
	var img := get_viewport().get_texture().get_image()
	var out_dir := OS.get_environment("OUT_DIR")
	if out_dir.is_empty(): out_dir = "user://wall_editor_soak"
	var out_path := out_dir.path_join(name + ".png")
	if out_path.begins_with("user://"):
		DirAccess.make_dir_recursive_absolute(out_path.get_base_dir())
	img.save_png(out_path)

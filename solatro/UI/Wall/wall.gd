class_name Wall
extends Node2D
## The picture-wall shell root — owns the camera, the pictures and (from S35) the overlay
## (PLAN.md §1.6, NAMES.md). S9 skeleton only: the tree exists and pauses itself permanently;
## packing, rendering, transitions and the overlay all land in later steps.

## Pauses the whole tree once, at construction, and NEVER clears it (§1.6, `QR6`=a) — the wall's
## own root and `%Camera2D` are `PROCESS_MODE_ALWAYS` so they keep running regardless, and each
## screen opts back in individually via its own process mode (S12).
func _ready() -> void:
	get_tree().paused = true

## §1.8 "window restored from minimise" (E7, Q208=b): every frozen picture texture may have been
## discarded by the GPU while the window was minimised, so every picture is force-rendered once.
## Godot has no dedicated "un-minimise" signal on desktop — `NOTIFICATION_APPLICATION_FOCUS_IN` is
## the closest built-in event (it also fires on a plain alt-tab back, Q207=a; harmless here, since a
## forced re-render costs one frame and E6 already treats a frozen-texture re-render as cheap by
## construction). See ASSUMPTIONS.md.
func _notification(what: int) -> void:
	if what != NOTIFICATION_APPLICATION_FOCUS_IN:
		return
	for child : Node in %Pictures.get_children():
		var wp := child as WallPicture
		if wp:
			wp.mark_for_rerender()

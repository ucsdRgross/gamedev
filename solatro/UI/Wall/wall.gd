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

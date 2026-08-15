extends Node2D
# res://Tests/Visual/reduce_animation_spike.gd
# ==============================================================================
# PHASE 0 SPIKE (picture-wall PLAN.md S2) — accessibility_should_reduce_animation() on Windows.
# Implements K8, GAP-005.
#
# ⚠ READ-ONLY HALF ONLY, BY OWNER INSTRUCTION. This script does not toggle any OS or accessibility
# setting by any means — it only reads and prints DisplayServer.accessibility_should_reduce_animation
# ()'s current value once, plus whether the query exists on this build at all. The
# toggle-and-reprint half of S2's done-when ("toggle the Windows animation setting, print again") is
# parked for the owner to run by hand; a single reading cannot answer "does it track".
#
# `has_method` is checked and logged first; the actual read is a direct typed call, confirmed safe
# on this build (Godot 4.7.1 — it compiles and runs). A build genuinely old enough to lack the
# method (pre-4.5, per GAP-005) would fail to PARSE this file at that call regardless of any runtime
# guard — GDScript resolves a typed singleton's methods against the compiled engine API, so dynamic
# dispatch is the only way around that, and an earlier draft that tried it (routing through
# Object.call()) got back an int rather than the documented bool — unreliable, and worse than the
# direct call this file actually runs under.
#
# Run windowed by hand, WITH AN EXTERNAL TIMEOUT (it prints and calls get_tree().quit() itself, but
# a caller should still bound the process):
#     <console exe> --path solatro res://Tests/Visual/reduce_animation_spike.tscn
# ==============================================================================

func _ready() -> void:
	var has := DisplayServer.has_method(&"accessibility_should_reduce_animation")
	print("REDUCE_ANIMATION_SPIKE has_method=%s" % str(has))
	if has:
		var v : bool = DisplayServer.accessibility_should_reduce_animation()
		print("REDUCE_ANIMATION_SPIKE value=%s" % str(v))
	get_tree().quit()

extends Node

## Verifies WorldGenerator.generate_up_to() runs a strict prefix of the pipeline
## AND that the per-step toggles pass through correctly. Run this scene (F6).
## Prints PASS/FAIL lines, then quits.
##   1. Stop at EROSION -> "Erosion" present; "Rivers_Only"/"Graph" absent; the
##      deleted "Climate" snapshot never appears.
##   2. Disable Erosion, run up to RIVERS -> "Erosion" skipped, "Rivers_Only"
##      still produced (pass-through), final_snapshot() == "Rivers_Only".

func _ready() -> void:
	print("=== generate_up_to test ===")
	var gen := WorldGenerator.new()
	gen.settings = WorldSettings.new()
	add_child(gen)
	await get_tree().process_frame

	# --- 1: strict prefix ----------------------------------------------------
	await gen.generate_up_to(WorldGenerator.GenStep.EROSION)
	var has_erosion: bool = gen.snapshots.has("Erosion")
	var has_rivers: bool = gen.snapshots.has("Rivers_Only")
	var has_climate: bool = gen.snapshots.has("Climate")
	print("  [prefix] has 'Erosion'    : ", has_erosion, "  (expected true)")
	print("  [prefix] has 'Rivers_Only': ", has_rivers, "  (expected false)")
	print("  [prefix] has 'Climate'    : ", has_climate, "  (expected false; step deleted)")
	print("  [prefix] final_snapshot   : ", gen.final_snapshot(), "  (expected Erosion)")
	var ok1 := has_erosion and not has_rivers and not has_climate \
		and gen.final_snapshot() == "Erosion"

	# --- 2: toggle pass-through ---------------------------------------------
	gen.settings.enable_erosion = false
	await gen.generate_up_to(WorldGenerator.GenStep.RIVERS)
	var skipped_erosion: bool = not gen.snapshots.has("Erosion")
	var rivers_ok: bool = gen.snapshots.has("Rivers_Only")
	print("  [toggle] Erosion skipped  : ", skipped_erosion, "  (expected true)")
	print("  [toggle] has 'Rivers_Only': ", rivers_ok, "  (expected true)")
	print("  [toggle] final_snapshot   : ", gen.final_snapshot(), "  (expected Rivers_Only)")
	var ok2 := skipped_erosion and rivers_ok and gen.final_snapshot() == "Rivers_Only"

	print("  snapshot keys (run 2)     : ", gen.snapshots.keys())
	print("  RESULT: ", "PASS" if (ok1 and ok2) else "FAIL")
	print("=== generate_up_to test complete ===")
	get_tree().quit()

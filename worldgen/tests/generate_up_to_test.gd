extends Node

## Verifies WorldGenerator.generate_up_to() runs a strict prefix of the pipeline:
## stopping at EROSION must populate the "Erosion" snapshot but NOT "Climate".
## Run this scene (F6). Prints a PASS/FAIL line, then quits.

func _ready() -> void:
	print("=== generate_up_to test ===")
	var gen := WorldGenerator.new()
	gen.settings = WorldSettings.new()
	add_child(gen)
	await get_tree().process_frame

	await gen.generate_up_to(WorldGenerator.GenStep.EROSION)

	var has_erosion: bool = gen.snapshots.has("Erosion")
	var has_climate: bool = gen.snapshots.has("Climate")
	print("  has 'Erosion'           : ", has_erosion, "  (expected true)")
	print("  has 'Climate'           : ", has_climate, "  (expected false)")
	print("  snapshot keys           : ", gen.snapshots.keys())

	var ok := has_erosion and not has_climate
	print("  RESULT: ", "PASS" if ok else "FAIL")
	print("=== generate_up_to test complete ===")
	get_tree().quit()

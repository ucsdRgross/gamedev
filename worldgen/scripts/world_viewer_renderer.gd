class_name WorldViewerRenderer
extends WorldViewer

## Draws the colorized image (from WorldViewer) and overlays text legends.
## Legends are screen-only — they are intentionally NOT part of the exported PNG.

func _draw() -> void:
	super._draw()
	if current_step_index < 0 or step_names.is_empty(): return
	var step := step_names[current_step_index]
	if step == "All_Steps_Grid":
		return  # grid is busy enough without nine legends
	_draw_legend(step)

func _draw_legend(step: String) -> void:
	var items: Array = []
	if step in ["Landmass", "PeaksAndValleys", "Erosion"]:
		items = [
			{"c": Color("#1a365d"), "n": "Ocean"}, {"c": Color("#2b6cb0"), "n": "Shallows"},
			{"c": Color("#2f855a"), "n": "Plains"}, {"c": Color("#ecc94b"), "n": "Hills"},
			{"c": Color("#718096"), "n": "Rock"}, {"c": Color("#ffffff"), "n": "Snow"},
		]
	elif step == "Tectonics_Debug":
		items = [
			{"c": Color("#f43f5e"), "n": "Continental"}, {"c": Color("#0ea5e9"), "n": "Oceanic"},
			{"c": Color("#a855f7"), "n": "Fault Line"},
		]
	elif step == "ErosionDebug":
		items = [{"c": RIVER, "n": "Carved (erosion only)"}, {"c": SUBSTRATE, "n": "Untouched"}]
	elif step == "Rivers_Only":
		items = [{"c": RIVER, "n": "River Network"}, {"c": SUBSTRATE, "n": "Substrate"}]
	elif step == "Graph":
		items = [
			{"c": Color("#ecc94b"), "n": "Node"}, {"c": Color.GREEN, "n": "Start"},
			{"c": Color.RED, "n": "End"}, {"c": Color.WHITE, "n": "Route"},
		]
	else:  # Climate / Biomes (27 distinct biomes from temp x humidity x height)
		items = [
			{"c": Color("#1a365d"), "n": "Ocean"},
			{"c": RIVER_OVERLAY, "n": "River"},
			{"c": Color("#ecc94b"), "n": "City"},
		]

	var font := ThemeDB.get_fallback_font()
	var y := get_viewport_rect().size.y - 30.0
	for i in range(items.size()):
		var x := 16.0 + (i * 135.0)
		draw_rect(Rect2(x, y, 14, 14), items[i].c, true)
		draw_string(font, Vector2(x + 20, y + 12), items[i].n, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color.WHITE)

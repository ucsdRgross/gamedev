class_name TestMainHost
## Hosts a real `Main` the way the OS window does: inside a SubViewport of the window's size.

const MAIN_SCENE := preload("res://Levels/main.tscn")

# The wall, its overlay and the one `HudContainer` all end up in the viewport a player's input
# enters, which is what makes a routed release testable. ⚠ `Wall._ready()` sets
# `get_tree().paused = true` GLOBALLY -- undone here, as every suite that builds a wall undoes it.
static func boot(parent: Node, size: Vector2i) -> Array:
	var viewport := SubViewport.new()
	viewport.size = size
	parent.add_child(viewport)
	var main : Main = MAIN_SCENE.instantiate()
	viewport.add_child(main)
	parent.get_tree().paused = false
	await parent.get_tree().process_frame
	await parent.get_tree().process_frame
	return [viewport, main]

# The `Main` goes first, so its screens tear down inside a live viewport rather than under one
# already freed.
static func free_booted(viewport: SubViewport, main: Main) -> void:
	main.queue_free()
	await viewport.get_tree().process_frame
	viewport.queue_free()

class_name TestMainHost
## Hosts a real `Main` the way the OS window does: inside a SubViewport of the window's size.

const MAIN_SCENE := preload("res://Levels/main.tscn")

## The metadata key a mounted node carries its tree's `paused` value from before the mount under.
const PAUSED_BEFORE_BOOT := &"paused_before_boot"

# The wall, its overlay and the one `HudContainer` all end up in the viewport a player's input
# enters, which is what makes a routed release testable.
static func boot(parent: TestSuite, size: Vector2i, scene: PackedScene = MAIN_SCENE) -> Array:
	var viewport := SubViewport.new()
	viewport.size = size
	parent.add_child(viewport)
	var node := mount(parent, viewport, scene)
	await parent.get_tree().process_frame
	await parent.get_tree().process_frame
	return [viewport, node]

# ⚠ The tree stays paused as `Wall._ready()` leaves it, so an unfocused screen is frozen here exactly
# as it is in the game. The prior value rides on the node so `unmount` can hand it back.
static func mount(parent: TestSuite, host: Node, scene: PackedScene) -> Node:
	var node := scene.instantiate()
	node.set_meta(PAUSED_BEFORE_BOOT, parent.get_tree().paused)
	host.add_child(node)
	parent.check(parent.get_tree().paused,
			"the booted wall runs under its session-long pause, as the game does")
	return node

# A wall never clears its own pause, so a later suite with no wall of its own would inherit it and
# freeze. The one place a test writes the flag, and only after the wall is gone.
static func unmount(parent: TestSuite, node: Node) -> void:
	var paused_before : bool = node.get_meta(PAUSED_BEFORE_BOOT)
	node.queue_free()
	await parent.get_tree().process_frame
	parent.get_tree().paused = paused_before
	await parent.get_tree().process_frame
	parent.check(parent.get_tree().paused == paused_before,
			"the tree's pause is back to what it was before the wall was mounted")

# The node goes first, so its screens tear down inside a live viewport rather than under one
# already freed.
static func free_booted(parent: TestSuite, viewport: SubViewport, node: Node) -> void:
	await unmount(parent, node)
	viewport.queue_free()

class_name TestGameViewHost
## Hosts a real GameView the way production does: inside a SubViewport sized to
## `game_picture_design_size` (production lays the board out at that size inside the wall's own
## SubViewport, `UI/Wall/wall_picture.gd`), never against the OS window (GAP-040). Instantiating
## GameView directly into a suite's own tree lays it out against the OS window instead, which
## drifted from production once PlayContainer's height stopped matching the window height.
## Shared by every suite that hosts a real GameView, so the hosting logic exists once.

## Adds a design-sized SubViewport under `parent`, then `view` under that. Returns the
## SubViewport -- `queue_free()` it to free the view (and its Game child) too.
static func host(parent: Node, view: GameView) -> SubViewport:
	var vp := SubViewport.new()
	vp.size = PlayArea.game_picture_design_size(SettingsManager.settings)
	parent.add_child(vp)
	vp.add_child(view)
	return vp

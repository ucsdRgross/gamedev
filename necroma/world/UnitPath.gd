extends Line2D
class_name UnitPath

export var grid: Resource

var _pathfinder: PathFinder

## Creates a new PathFinder that uses the AStar algorithm to find a path between two cells among
## the `walkable_cells`.
func initialize(walkable_cells: Array) -> void:
	_pathfinder = PathFinder.new(grid, walkable_cells)


## Finds and draws the path between `cell_start` and `cell_end`
func draw(cell_start: Vector2, cell_end: Vector2) -> void:
	points = _pathfinder.calculate_point_path(cell_start, cell_end)
	show()

## Stops drawing, clearing the drawn path and the `_pathfinder`.
func stop() -> void:
	hide()

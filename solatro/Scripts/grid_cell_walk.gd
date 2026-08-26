class_name GridCellWalk
extends RefCounted
## Marks one grid's row-major cell array (`GridData.cells`) for `CardDataIterator`: walk cell by
## cell in array order (already row-major, per `GridData.cell_index`), and within each cell walk
## its stack bottom to top with NO early stop -- a grid is sparse by nature.
## A thin wrapper, not a plain `Array[ArrayCardData]`, because that type is already the legacy
## zone shape, whose depth-major walk needs the early stop just to terminate; the two shapes
## share a static type but not a traversal.

var cells : Array[ArrayCardData]

func _init(grid_cells: Array[ArrayCardData]) -> void:
	cells = grid_cells

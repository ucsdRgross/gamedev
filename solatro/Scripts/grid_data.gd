class_name GridData
extends Resource
## One grid on the board: its own size, a row-major cell array (one ArrayCardData per
## CELL, each holding that cell's stack bottom-to-top -- a grid is sparse by nature), and a
## row-major array of grid_width * grid_height real cell zone cards (25 at the default 5x5).

@export_storage var grid_width : int = 5
@export_storage var grid_height : int = 5
@export_storage var cells : Array[ArrayCardData] = []
@export_storage var cell_types : Array[CardData] = []

## Row-major index of cell (x, y) within this grid's own width.
func cell_index(x: int, y: int) -> int:
	return y * grid_width + x

## (Re)builds `cells` and `cell_types` to grid_width * grid_height entries -- a fresh empty
## stack and a fresh TypeGridCell card per cell. Existing entries are discarded.
func build_cells() -> void:
	var count := grid_width * grid_height
	var new_cells : Array[ArrayCardData] = []
	var new_types : Array[CardData] = []
	for i in count:
		new_cells.append(ArrayCardData.new())
		var type_card := CardData.new().with_type(TypeGridCell.new())
		type_card.stage = CardData.Stage.ZONE
		new_types.append(type_card)
	cells = new_cells
	cell_types = new_types

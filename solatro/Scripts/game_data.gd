class_name GameData
extends Resource

signal state_changed

@export_storage var goal : int = 100:
	set(value):
		goal = value
		state_changed.emit()
@export_storage var total_score : int = 0:
	set(value):
		total_score = value
		state_changed.emit()
@export_storage var mult_score : int = 0:
	set(value):
		mult_score = value
		state_changed.emit()
@export_storage var col_total : int = 0:
	set(value):
		col_total = value
		state_changed.emit()
@export_storage var row_total : int = 0:
	set(value):
		row_total = value
		state_changed.emit()

@export_storage var draw_deck : Array[CardData]
@export_storage var discard_deck : Array[CardData]
@export_storage var rules_deck : Array[CardData]
@export_storage var upper_zone_type : Array[CardData]
@export_storage var upper_zone : Array[ArrayCardData]
@export_storage var lower_zone_type : Array[CardData]
@export_storage var lower_zone : Array[ArrayCardData]
@export_storage var scores_row_upper : Array[BigNumber]
@export_storage var scores_row_lower : Array[BigNumber]
@export_storage var scores_col : Array[BigNumber]

func print_board() -> void:
	var s : String = "Upper Type,"
	for c in upper_zone_type:
		s += c.to_string() + ","
	s += "\n"
	var rows : int = upper_zone.map(func(a:ArrayCardData)->int:return a.datas.size()).max()
	for r in rows:
		s += str(r) + ","
		for col in upper_zone:
			if r < col.datas.size():
				s += col.datas[r].to_string()
			s += ","
		s += "\n"
	s += "Lower Type,"
	for c in lower_zone_type:
		s += c.to_string() + ","
	s += "\n"
	rows = lower_zone.map(func(a:ArrayCardData)->int:return a.datas.size()).max()
	for r in rows:
		s += str(r) + ","
		for col in lower_zone:
			if r < col.datas.size():
				s += col.datas[r].to_string()
			s += ","
		s += "\n"
	print(s)

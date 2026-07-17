extends Resource
class_name ArrayCardData

@export_storage var datas : Array[CardData]

func with_datas(d : Array[CardData]) -> ArrayCardData:
	datas = d
	return self

func size() -> int: return datas.size()

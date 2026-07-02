class_name CardDataIterator

var env : CardEnvironment
var next_card_data : CardData
var collections : Array[Variant] = []
var collection_index : int = 0
var current_row : int = 0
var current_col : int = 0
var is_row_empty := true

#defaults to CURRENT so ad-hoc `CardDataIterator.new()` still walks the live game
func _init(environment: CardEnvironment = null) -> void:
	env = environment if environment else CardEnvironment.CURRENT

func _iter_init(_arg:Variant) -> bool:
	if not env:
		return false
	collections = env.get_card_collections()
	collection_index = 0
	current_row = 0
	current_col = 0
	is_row_empty = true
	return should_continue()

func _iter_next(_arg:Variant) -> bool:
	return should_continue()

func _iter_get(_arg:Variant) -> CardData:
	return next_card_data

func should_continue() -> bool:
	if collection_index >= collections.size():
		return false
	
	var current_coll : Variant = collections[collection_index]
	
	# Handle null/empty collections
	if not current_coll:
		collection_index += 1
		return should_continue()

	# Handle 2D Arrays (Array[ArrayCardData])
	if current_coll is Array[ArrayCardData] and (current_coll as Array).size() > 0:
		while true:
			if current_col < (current_coll as Array).size():
				var col : Array[CardData] = current_coll[current_col].datas
				if current_row < col.size():
					next_card_data = col[current_row]
					current_col += 1
					is_row_empty = false
					return true
				else:
					current_col += 1
			else:
				if is_row_empty: 
					break
				current_row += 1
				current_col = 0
				is_row_empty = true
		
		# Move to next collection
		collection_index += 1
		current_row = 0
		current_col = 0
		is_row_empty = true
		return should_continue()
	
	# Handle 1D Arrays (Array[CardData])
	elif current_coll is Array[CardData]:
		if current_col < (current_coll as Array).size():
			next_card_data = current_coll[current_col]
			current_col += 1
			return true
		else:
			collection_index += 1
			current_col = 0
			return should_continue()

	# Skip unrecognized types
	collection_index += 1
	return should_continue()

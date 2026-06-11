class_name Step7Graph
extends GenerationStep

func execute(gen: WorldGenerator, settings: WorldSettings) -> void:
	if gen.city_nodes.size() < 4: return
	
	var left_city = gen.city_nodes[0]
	var right_city = gen.city_nodes[0]
	
	for city in gen.city_nodes:
		if city.x < left_city.x: left_city = city
		if city.x > right_city.x: right_city = city
		
	gen.start_node = left_city
	gen.end_node = right_city
	
	var travel_vec = gen.end_node - gen.start_node
	var travel_normalized = travel_vec.normalized()
	var step_size = travel_vec.length() / settings.path_steps
	
	var layers: Array = []
	for i in range(settings.path_steps + 1):
		var typed_inner: Array[Vector2] = []
		layers.append(typed_inner)
		
	for city in gen.city_nodes:
		var projection = (city - gen.start_node).dot(travel_normalized)
		var idx = clampi(int(projection / step_size), 0, settings.path_steps)
		layers[idx].push_back(city)
		
	var layers_has_start = false
	for layer in layers:
		if layer.has(gen.start_node): layers_has_start = true; break
	if not layers_has_start: layers[0].push_back(gen.start_node)
		
	var layers_has_end = false
	if layers[settings.path_steps].has(gen.end_node): layers_has_end = true
	if not layers_has_end: layers[settings.path_steps].push_back(gen.end_node)
	
	for i in range(1, settings.path_steps):
		if layers[i].is_empty():
			var fallback_pos = gen.start_node + (travel_normalized * (step_size * i))
			gen.city_nodes.append(fallback_pos)
			layers[i].push_back(fallback_pos)
			
	for i in range(settings.path_steps + 1):
		layers[i].sort_custom(func(a, b): return a.y < b.y)
			
	for i in range(settings.path_steps):
		var current_layer = layers[i]
		var next_layer = layers[i+1]
		
		for current in current_layer:
			gen.gameplay_graph[current] = []
			var valid_targets = []
			
			for candidate in next_layer:
				var d = current.distance_to(candidate)
				if d >= settings.min_path_dist and d <= settings.max_path_search_dist:
					var penalty = gen._evaluate_raycast_cost(current, candidate)
					if penalty >= 0.0:
						valid_targets.append({"pos": candidate, "score": d + penalty})
						
			if valid_targets.is_empty():
				for candidate in next_layer:
					var d = current.distance_to(candidate)
					var penalty = gen._evaluate_raycast_cost(current, candidate)
					if penalty >= 0.0:
						valid_targets.append({"pos": candidate, "score": d + penalty + 5000.0})
						
			valid_targets.sort_custom(func(a, b): return a.score < b.score)
			var target_branches = min(randi_range(settings.min_choices, settings.max_choices), valid_targets.size())
			for b in range(target_branches):
				gen.gameplay_graph[current].append(valid_targets[b].pos)
				
	gen.gameplay_graph[gen.end_node] = []
	
	var dynamic_valid_nodes := {}
	_map_valid_routes_dfs(gen.start_node, 0, dynamic_valid_nodes, gen.gameplay_graph, gen.end_node, settings.path_steps)
	
	var pruned_graph := {}
	for parent in gen.gameplay_graph.keys():
		var parent_key = Vector2i(parent.snapped(Vector2(0.01, 0.01)))
		if dynamic_valid_nodes.has(parent_key):
			pruned_graph[parent] = []
			for child in gen.gameplay_graph[parent]:
				var child_key = Vector2i(child.snapped(Vector2(0.01, 0.01)))
				if dynamic_valid_nodes.has(child_key):
					pruned_graph[parent].push_back(child)
					
	gen.gameplay_graph = pruned_graph
	gen.gameplay_graph[gen.end_node] = []
	
	var validated_cities: Array[Vector2] = []
	for city in gen.city_nodes:
		var city_key = Vector2i(city.snapped(Vector2(0.01, 0.01)))
		var end_key = Vector2i(gen.end_node.snapped(Vector2(0.01, 0.01)))
		if dynamic_valid_nodes.has(city_key) or city_key == end_key:
			validated_cities.push_back(city)
	gen.city_nodes = validated_cities
	
	gen._save_snapshot("Graph")

func _map_valid_routes_dfs(node: Vector2, depth: int, valid_map: Dictionary, graph: Dictionary, end_n: Vector2, max_steps: int) -> bool:
	var node_key = Vector2i(node.snapped(Vector2(0.01, 0.01)))
	var end_key = Vector2i(end_n.snapped(Vector2(0.01, 0.01)))
	
	if node_key == end_key: return depth == max_steps
	if depth >= max_steps or not graph.has(node): return false
	
	var path_leads_to_valid_end = false
	for next_node in graph[node]:
		var valid_branch = _map_valid_routes_dfs(next_node, depth + 1, valid_map, graph, end_n, max_steps)
		if valid_branch:
			path_leads_to_valid_end = true
			var next_key = Vector2i(next_node.snapped(Vector2(0.01, 0.01)))
			valid_map[next_key] = true
			
	if path_leads_to_valid_end: 
		valid_map[node_key] = true
	return path_leads_to_valid_end

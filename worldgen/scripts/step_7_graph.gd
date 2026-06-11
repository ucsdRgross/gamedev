class_name Step7Graph
extends GenerationStep

func execute(gen: WorldGenerator, settings: WorldSettings) -> void:
	if gen.city_nodes.size() < 2: return
	
	var best_pair: Array[Vector2] = [Vector2.ZERO, Vector2.ZERO]
	var max_d = 0.0
	
	for i in range(gen.city_nodes.size()):
		for j in range(i + 1, gen.city_nodes.size()):
			var d = gen.city_nodes[i].distance_to(gen.city_nodes[j])
			if d > max_d:
				max_d = d
				best_pair = [gen.city_nodes[i], gen.city_nodes[j]]
				
	if best_pair[0].x <= best_pair[1].x:
		gen.start_node = best_pair[0]
		gen.end_node = best_pair[1]
	else:
		gen.start_node = best_pair[1]
		gen.end_node = best_pair[0]
	
	var travel_vec = gen.end_node - gen.start_node
	var travel_normalized = travel_vec.normalized()
	var step_size = travel_vec.length() / settings.path_steps
	var is_horizontal: bool = abs(travel_normalized.x) > abs(travel_normalized.y)
	
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
		if layer.has(gen.start_node): 
			layers_has_start = true
			break
	if not layers_has_start: 
		layers[0].push_back(gen.start_node)
		
	var layers_has_end = false
	if layers[settings.path_steps].has(gen.end_node): 
		layers_has_end = true
	if not layers_has_end: 
		layers[settings.path_steps].push_back(gen.end_node)
		
	for i in range(1, settings.path_steps):
		if layers[i].is_empty():
			var fallback_pos = gen.start_node + (travel_normalized * (step_size * i))
			gen.city_nodes.append(fallback_pos)
			layers[i].push_back(fallback_pos)
			
	for i in range(settings.path_steps + 1):
		if is_horizontal: 
			layers[i].sort_custom(func(a, b): return a.y < b.y)
		else: 
			layers[i].sort_custom(func(a, b): return a.x < b.x)
			
	for i in range(settings.path_steps):
		var current_layer = layers[i]
		var next_layer = layers[i+1]
		
		for current in current_layer:
			gen.gameplay_graph[current] = []
			var valid_targets = []
			
			for candidate in next_layer:
				var d = current.distance_to(candidate)
				if d >= settings.min_path_dist and d <= settings.max_path_dist:
					var penalty = gen._evaluate_raycast_cost(current, candidate)
					if penalty >= 0.0:
						valid_targets.append({"pos": candidate, "score": d + penalty})
						
			if valid_targets.is_empty():
				for candidate in next_layer:
					var d = current.distance_to(candidate)
					if d <= settings.max_path_search_dist:
						var penalty = gen._evaluate_raycast_cost(current, candidate)
						if penalty >= 0.0:
							valid_targets.append({"pos": candidate, "score": d + penalty + 1500.0})
							
			valid_targets.sort_custom(func(a, b): return a.score < b.score)
			var target_branches = min(randi_range(settings.min_choices, settings.max_choices), valid_targets.size())
			for b in range(target_branches):
				gen.gameplay_graph[current].append(valid_targets[b].pos)
				
	gen.gameplay_graph[gen.end_node] = []
	
	# DFS PROGRESSION CLEANUP SWEEP
	var dynamic_valid_nodes := {}
	_map_valid_routes_dfs(gen.start_node, 0, dynamic_valid_nodes, gen.gameplay_graph, gen.end_node, settings.path_steps)
	
	var pruned_graph := {}
	for parent in gen.gameplay_graph.keys():
		if dynamic_valid_nodes.has(parent):
			pruned_graph[parent] = []
			for child in gen.gameplay_graph[parent]:
				if dynamic_valid_nodes.has(child):
					pruned_graph[parent].push_back(child)
					
	gen.gameplay_graph = pruned_graph
	gen.gameplay_graph[gen.end_node] = []
	
	var validated_cities: Array[Vector2] = []
	for city in gen.city_nodes:
		if dynamic_valid_nodes.has(city) or city == gen.end_node:
			validated_cities.push_back(city)
	gen.city_nodes = validated_cities
	
	gen._save_snapshot("Graph")

func _map_valid_routes_dfs(node: Vector2, depth: int, valid_map: Dictionary, graph: Dictionary, end_n: Vector2, max_steps: int) -> bool:
	if node == end_n: 
		return depth == max_steps
	if depth >= max_steps or not graph.has(node): 
		return false
	var path_leads_to_valid_end = false
	for next_node in graph[node]:
		var valid_branch = _map_valid_routes_dfs(next_node, depth + 1, valid_map, graph, end_n, max_steps)
		if valid_branch:
			path_leads_to_valid_end = true
			valid_map[next_node] = true
	if path_leads_to_valid_end: 
		valid_map[node] = true
	return path_leads_to_valid_end

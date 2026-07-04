class_name StepGraph
extends GenerationStep

## Combined graph step -- runs right after Rivers. Mirrors the reference flow in
## tests/graph_placement_test.gd:
##   A) GraphSpec.build_nodes  : abstract layered DAG (pure data)
##   B) GraphPlacement.place   : lay the ladder on the real map (water-rule aware:
##      lakes count as ocean, nodes never sit on rivers)
##   C) GraphDetail.compute_curves : terrain-fitting curved edges (A*)
##   then export_graph -> the plain-data gameplay graph the game walks.
## CPU only; no await.

func execute(gen: WorldGenerator, settings: WorldSettings) -> void:
	var field : GraphPlacement.MapField = GraphPlacement.MapField.from_generator(gen)
	# layer_min/layer_max are unused by v4 ladder placement (node counts come from
	# land width); passed as nominal values for the spec's over-provisioning.
	var g := GraphSpec.build_nodes(settings.spec_cities,
		settings.spec_nodes_between_cities, 2, 5, settings.main_seed)
	var res := GraphPlacement.place(g, field, settings, settings.main_seed, settings.place_opts())
	var ctx = res["ctx"]
	var curves := GraphDetail.compute_curves(ctx, field)

	gen.map_field = field
	gen.graph_ctx = ctx
	gen.graph_curves = curves
	gen.graph_export = GraphPlacement.export_graph(ctx, field, curves)
	gen._save_snapshot_bridge("Graph")

class_name Step2Tectonics
extends GenerationStep

## GPU two-pass tectonics:
##   blueprint -> domain-warped Voronoi plate cells (drift vectors + plate id)
##   deform    -> drifts the landmass along plate vectors and raises/lowers
##                height at convergent/divergent boundaries.
## The blueprint snapshot ("Tectonics_Debug") carries the plate-id field that
## the viewer turns into fault lines, plus the plate markers/vectors.
func execute(gen: WorldGenerator, settings: WorldSettings) -> void:
	# Deterministic path: one CPU pass covers BOTH shaders, since the blueprint and
	# the deform pass recompute the same warped-Voronoi nearest plates. Note the
	# deform shader samples viewport_texture("landmass"); that viewport is never
	# rendered here, so the twin reads gen.height_buffer instead. See
	# worldgen/DETERMINISM_FINDINGS.md.
	if settings.deterministic_terrain and GenerationStep._native:
		var res: Array = GenerationStep._native.terrain_tectonics(
			gen.height_buffer,
			gen.noise_img("warp_x").get_data(),
			gen.noise_img("warp_y").get_data(),
			gen.plate_data, gen.plate_is_land,
			settings.map_width, settings.map_height, settings.plate_count,
			settings.warp_strength, float(settings.map_width),
			settings.drift_intensity, settings.plate_move, settings.tectonic_band,
			settings.land_rift_damping, settings.tectonic_height_cap)
		gen.height_buffer = res[0]
		gen.plate_id_buffer = res[1]
		gen._save_snapshot_bridge("Tectonics_Debug")
		gen._save_snapshot_bridge("Tectonics")
		return

	# --- Pass A: plate blueprint -------------------------------------------
	var blue := gen.get_material("blueprint")
	blue.set_shader_parameter("plate_count", settings.plate_count)
	blue.set_shader_parameter("plate_tex", gen.plate_tex)
	blue.set_shader_parameter("warp_x_tex", gen.noise_tex("warp_x"))
	blue.set_shader_parameter("warp_y_tex", gen.noise_tex("warp_y"))
	blue.set_shader_parameter("warp_strength", settings.warp_strength)
	blue.set_shader_parameter("map_px", float(settings.map_width))

	var blue_img := await gen.flush("blueprint")
	gen.read_plate_ids_from_image(blue_img)

	# --- Pass B: deformation ------------------------------------------------
	var deform := gen.get_material("deform")
	deform.set_shader_parameter("landmass_tex", gen.viewport_texture("landmass"))
	deform.set_shader_parameter("plate_count", settings.plate_count)
	deform.set_shader_parameter("plate_tex", gen.plate_tex)
	deform.set_shader_parameter("plate_land_tex", gen.plate_land_tex)
	deform.set_shader_parameter("warp_x_tex", gen.noise_tex("warp_x"))
	deform.set_shader_parameter("warp_y_tex", gen.noise_tex("warp_y"))
	deform.set_shader_parameter("warp_strength", settings.warp_strength)
	deform.set_shader_parameter("map_px", float(settings.map_width))
	deform.set_shader_parameter("drift_intensity", settings.drift_intensity)
	deform.set_shader_parameter("plate_move", settings.plate_move)
	deform.set_shader_parameter("tectonic_band", settings.tectonic_band)
	deform.set_shader_parameter("land_rift_damping", settings.land_rift_damping)
	deform.set_shader_parameter("tectonic_height_cap", settings.tectonic_height_cap)

	var def_img := await gen.flush("deform")
	gen.read_height_from_image(def_img)
	# Snapshot AFTER deform so the debug slot shows the deformed heightmap
	# (with plate cells + arrows on top), making plate motion actually visible.
	gen._save_snapshot_bridge("Tectonics_Debug")
	gen._save_snapshot_bridge("Tectonics")

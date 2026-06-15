class_name Step2Tectonics
extends GenerationStep

## GPU two-pass tectonics:
##   blueprint -> domain-warped Voronoi plate cells (drift vectors + plate id)
##   deform    -> drifts the landmass along plate vectors and raises/lowers
##                height at convergent/divergent boundaries.
## The blueprint snapshot ("Tectonics_Debug") carries the plate-id field that
## the viewer turns into fault lines, plus the plate markers/vectors.
func execute(gen: WorldGenerator, settings: WorldSettings) -> void:
	# --- Pass A: plate blueprint -------------------------------------------
	var blue := gen.get_material("blueprint")
	blue.set_shader_parameter("plate_count", settings.plate_count)
	blue.set_shader_parameter("plate_tex", gen.plate_tex)
	blue.set_shader_parameter("warp_x_tex", gen.noise_tex("warp_x"))
	blue.set_shader_parameter("warp_y_tex", gen.noise_tex("warp_y"))
	blue.set_shader_parameter("warp_strength", settings.warp_strength)

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
	deform.set_shader_parameter("drift_intensity", settings.drift_intensity)
	deform.set_shader_parameter("plate_move", settings.plate_move)
	deform.set_shader_parameter("tectonic_band", settings.tectonic_band)
	deform.set_shader_parameter("land_rift_damping", settings.land_rift_damping)

	var def_img := await gen.flush("deform")
	gen.read_height_from_image(def_img)
	# Snapshot AFTER deform so the debug slot shows the deformed heightmap
	# (with plate cells + arrows on top), making plate motion actually visible.
	gen._save_snapshot_bridge("Tectonics_Debug")
	gen._save_snapshot_bridge("Tectonics")

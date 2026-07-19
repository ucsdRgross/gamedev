class_name Step1Landmass
extends GenerationStep

## GPU: Perlin-style base landmass with a central island mask baked in
## (see landmass.gdshader). Reads the resulting height into the buffer.
func execute(gen: WorldGenerator, settings: WorldSettings) -> void:
	# Deterministic path: same formula on the CPU, so the map does not depend on
	# the player's GPU/driver. Skips the SubViewport entirely (no flush, no frame
	# waits). See worldgen/START_HERE.md "Determinism".
	if settings.deterministic_terrain and GenerationStep._native:
		gen.height_buffer = GenerationStep._native.terrain_landmass(
			gen.noise_img("landmass").get_data(),
			gen.noise_img("warp_x").get_data(),
			gen.noise_img("warp_y").get_data(),
			settings.map_width, settings.map_height,
			settings.island_radius, settings.land_contrast,
			settings.edge_jag, settings.island_falloff)
		gen._save_snapshot_bridge("Landmass")
		return
	var mat := gen.get_material("landmass")
	mat.set_shader_parameter("noise_tex", gen.noise_tex("landmass"))
	mat.set_shader_parameter("warp_x_tex", gen.noise_tex("warp_x"))
	mat.set_shader_parameter("warp_y_tex", gen.noise_tex("warp_y"))
	mat.set_shader_parameter("island_radius", settings.island_radius)
	mat.set_shader_parameter("land_contrast", settings.land_contrast)
	mat.set_shader_parameter("edge_jag", settings.edge_jag)
	mat.set_shader_parameter("island_falloff", settings.island_falloff)

	var img := await gen.flush("landmass")
	gen.read_height_from_image(img)
	gen._save_snapshot_bridge("Landmass")

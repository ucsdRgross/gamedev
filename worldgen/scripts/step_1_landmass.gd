class_name Step1Landmass
extends GenerationStep

## GPU: Perlin-style base landmass with a central island mask baked in
## (see step_1_landmass.gdshader). Reads the resulting height into the buffer.
func execute(gen: WorldGenerator, settings: WorldSettings) -> void:
	var mat := gen.get_material("landmass")
	mat.set_shader_parameter("noise_tex", gen.noise_tex("landmass"))
	mat.set_shader_parameter("warp_x_tex", gen.noise_tex("warp_x"))
	mat.set_shader_parameter("warp_y_tex", gen.noise_tex("warp_y"))
	mat.set_shader_parameter("island_radius", settings.island_radius)
	mat.set_shader_parameter("land_contrast", settings.land_contrast)
	mat.set_shader_parameter("edge_jag", settings.edge_jag)

	var img := await gen.flush("landmass")
	gen.read_height_from_image(img)
	gen._save_snapshot_bridge("Landmass")

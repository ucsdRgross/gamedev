class_name Step4Erosion
extends GenerationStep

## GPU directional-gabor erosion (erosion.gdshader). A single-pass noise
## that carves branching gullies and ridges by steering anisotropic gabor stripes
## along the terrain's own slope. The shader reads the current heightmap (its base)
## and writes base + erosion*amplitude back. Replaces the old CPU flow-accumulation
## erosion entirely. Runs before rivers.
##
## Two flushes: pass 0 = final eroded height (read into the buffer); pass 1 = the
## erosion field on its own, stashed as the "erosion_field" noise map so the viewer
## can show "starting height -> erosion noise -> final".
func execute(gen: WorldGenerator, settings: WorldSettings) -> void:
	var w := settings.map_width
	var h := settings.map_height

	var mat := gen.get_material("erosion")
	mat.set_shader_parameter("height_tex", gen.height_texture())
	mat.set_shader_parameter("tex_size", Vector2(w, h))
	mat.set_shader_parameter("octaves", settings.erosion_octaves)
	mat.set_shader_parameter("amplitude", settings.erosion_amplitude)
	mat.set_shader_parameter("frequency", settings.erosion_frequency)
	mat.set_shader_parameter("gain", settings.erosion_gain)
	mat.set_shader_parameter("lacunarity", settings.erosion_lacunarity)
	mat.set_shader_parameter("branch_angle", deg_to_rad(settings.erosion_branch_angle_deg))
	mat.set_shader_parameter("ridge_rounding", settings.erosion_ridge_rounding)
	mat.set_shader_parameter("gully_rounding", settings.erosion_gully_rounding)
	mat.set_shader_parameter("detail", settings.erosion_detail)
	mat.set_shader_parameter("steepness_scale", settings.erosion_steepness_scale)
	mat.set_shader_parameter("min_elevation", settings.erosion_min_elevation)
	mat.set_shader_parameter("elevation_falloff", settings.erosion_elevation_falloff)

	# Pass 0: final eroded heightmap.
	mat.set_shader_parameter("output_mode", 0)
	var final_img := await gen.flush("erosion")

	# Pass 1: erosion field only -> expose as a noise map for the debug view.
	mat.set_shader_parameter("output_mode", 1)
	var field_img := await gen.flush("erosion")
	gen.noise_maps["erosion_field"] = {
		"img": field_img,
		"tex": ImageTexture.create_from_image(field_img),
	}

	gen.read_height_from_image(final_img)
	gen._save_snapshot_bridge("Erosion")

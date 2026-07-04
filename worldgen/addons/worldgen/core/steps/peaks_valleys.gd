class_name Step3PeaksAndValleys
extends GenerationStep

## GPU: layers high-frequency ridged + detail noise onto land to build
## micro-topography (see peaks_and_valleys.gdshader).
func execute(gen: WorldGenerator, settings: WorldSettings) -> void:
	var mat := gen.get_material("peaks")
	# Read the CPU height buffer (R channel = current height) rather than the deform
	# viewport, so this step consumes whatever the previous ENABLED step produced --
	# if Tectonics is toggled off, height_buffer still holds the landmass output.
	mat.set_shader_parameter("deformed_tex", gen.height_texture())
	mat.set_shader_parameter("ridge_tex", gen.noise_tex("peaks_ridge"))
	mat.set_shader_parameter("billow_tex", gen.noise_tex("peaks_billow"))
	mat.set_shader_parameter("detail_tex", gen.noise_tex("peaks_detail"))
	mat.set_shader_parameter("warp_x_tex", gen.noise_tex("warp_x"))
	mat.set_shader_parameter("warp_y_tex", gen.noise_tex("warp_y"))
	mat.set_shader_parameter("ocean_threshold", settings.ocean_threshold)
	mat.set_shader_parameter("boundary_radius", settings.boundary_radius)
	mat.set_shader_parameter("edge_jag", settings.edge_jag)
	mat.set_shader_parameter("peak_uplift", settings.peak_uplift)
	mat.set_shader_parameter("highland_range", settings.highland_range)
	mat.set_shader_parameter("peak_detail_strength", settings.peak_detail_strength)
	mat.set_shader_parameter("peak_billow_strength", settings.peak_billow_strength)
	mat.set_shader_parameter("peak_height_cap", settings.peak_height_cap)
	mat.set_shader_parameter("detail_min_elevation", settings.peak_detail_min_elevation)
	mat.set_shader_parameter("detail_falloff", settings.peak_detail_falloff)
	mat.set_shader_parameter("boundary_falloff", settings.boundary_falloff)
	mat.set_shader_parameter("lowland_flatten", settings.lowland_flatten)

	var img := await gen.flush("peaks")
	gen.read_height_from_image(img)
	gen._save_snapshot_bridge("PeaksAndValleys")

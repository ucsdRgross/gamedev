class_name Step3PeaksAndValleys
extends GenerationStep

## GPU: layers high-frequency ridged + detail noise onto land to build
## micro-topography (see step_4_peaks_and_valleys.gdshader).
func execute(gen: WorldGenerator, settings: WorldSettings) -> void:
	var mat := gen.get_material("peaks")
	mat.set_shader_parameter("deformed_tex", gen.viewport_texture("deform"))
	mat.set_shader_parameter("ridge_tex", gen.noise_tex("peaks_ridge"))
	mat.set_shader_parameter("detail_tex", gen.noise_tex("peaks_detail"))
	mat.set_shader_parameter("ocean_threshold", settings.ocean_threshold)
	mat.set_shader_parameter("boundary_radius", settings.boundary_radius)
	mat.set_shader_parameter("peak_uplift", settings.peak_uplift)
	mat.set_shader_parameter("highland_range", settings.highland_range)
	mat.set_shader_parameter("peak_detail_strength", settings.peak_detail_strength)

	var img := await gen.flush("peaks")
	gen.read_height_from_image(img)
	gen._save_snapshot_bridge("PeaksAndValleys")

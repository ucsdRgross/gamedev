class_name Step3PeaksAndValleys
extends GenerationStep

## GPU: layers high-frequency ridged + detail noise onto land to build
## micro-topography (see step_4_peaks_and_valleys.gdshader).
func execute(gen: WorldGenerator, settings: WorldSettings) -> void:
	var mat := gen.get_material("peaks")
	mat.set_shader_parameter("deformed_tex", gen.viewport_texture("deform"))
	mat.set_shader_parameter("ocean_threshold", settings.ocean_threshold)
	mat.set_shader_parameter("ridge_frequency", settings.ridge_frequency)
	mat.set_shader_parameter("detail_frequency", settings.detail_frequency)
	mat.set_shader_parameter("boundary_radius", settings.boundary_radius)
	mat.set_shader_parameter("seed", settings.main_seed + 2)

	var img := await gen.flush("peaks")
	gen.read_height_from_image(img)
	gen._save_snapshot_bridge("PeaksAndValleys")

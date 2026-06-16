class_name Step5Climate
extends GenerationStep

## GPU: classifies a biome id per pixel from temperature/humidity/height noise.
## Reads the CPU-carved height + river network (uploaded as a float texture)
## so the GPU can run the per-pixel classification while erosion stays on CPU.
## Shader writes the biome id into the red channel; we read it back so the
## viewer can colorize + legend, and so civ/graph can avoid water.
func execute(gen: WorldGenerator, settings: WorldSettings) -> void:
	var state := gen.build_state_texture()  # R = height, G = river flag
	var mat := gen.get_material("climate")
	mat.set_shader_parameter("state_tex", state)
	mat.set_shader_parameter("temp_tex", gen.noise_tex("temperature"))
	mat.set_shader_parameter("humid_tex", gen.noise_tex("humidity"))  # shared with rivers
	mat.set_shader_parameter("ocean_threshold", settings.ocean_threshold)
	mat.set_shader_parameter("mountain_threshold", settings.mountain_threshold)
	mat.set_shader_parameter("height_bands", settings.height_bands)
	mat.set_shader_parameter("temp_bands", settings.temp_bands)
	mat.set_shader_parameter("humid_bands", settings.humid_bands)

	var img := await gen.flush("climate")
	gen.read_biomes_from_image(img)
	gen._save_snapshot_bridge("Climate")

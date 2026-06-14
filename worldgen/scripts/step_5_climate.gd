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
	mat.set_shader_parameter("seed_t", settings.main_seed + 3)
	mat.set_shader_parameter("seed_h", settings.main_seed + 4)
	mat.set_shader_parameter("ocean_threshold", settings.ocean_threshold)
	mat.set_shader_parameter("mountain_threshold", settings.mountain_threshold)
	mat.set_shader_parameter("temp_frequency", settings.temp_frequency)
	mat.set_shader_parameter("humid_frequency", settings.humid_frequency)

	var img := await gen.flush("climate")
	gen.read_biomes_from_image(img)
	gen._save_snapshot_bridge("Climate")

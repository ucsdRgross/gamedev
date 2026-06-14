class_name GenerationStep
extends RefCounted

## Virtual base for one map-generation pass.
##
## Each concrete step owns a single shader (or a small ping-pong group),
## configures its uniforms, flushes the GPU, and reads the result back into
## the generator's CPU buffers. `execute` is a coroutine — callers must
## `await` it because every GPU flush waits for real rendered frames.
func execute(_gen: WorldGenerator, _settings: WorldSettings) -> void:
	pass

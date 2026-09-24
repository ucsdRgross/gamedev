extends SceneTree

# Loads the script after the project's autoloads are registered: `--check-only` skips them and
# reports every autoload name as "Identifier not found".
func _initialize() -> void:
	var path: String = OS.get_cmdline_user_args()[0]
	var script: GDScript = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
	quit(0 if script != null and script.can_instantiate() else 1)

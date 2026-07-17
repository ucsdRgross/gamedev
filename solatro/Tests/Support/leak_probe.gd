extends Node
## One-off leak-attribution harness (todo.md §Memory). Runs a SINGLE suite scene, waits
## for it, then quits — so the engine's exit-time "N ObjectDB instances were leaked"
## report measures that suite alone. Usage:
##   Godot --headless --path . res://Tests/Support/leak_probe.tscn -- <suite_scene_respath>
## e.g. ... leak_probe.tscn -- res://Tests/Engine/test_scoring.gd (pass the .tscn path).
## Not part of all_tests; safe to delete once residual-leak attribution is closed.

func _enter_tree() -> void:
	TestLog.begin(false)

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		push_error("leak_probe: pass a suite scene path after --")
		get_tree().quit(1)
		return
	var scene : PackedScene = load(args[0])
	var suite : TestSuite = scene.instantiate()
	add_child(suite)
	if not suite.finished:
		await suite.suite_finished
	print("LEAK_PROBE done: %s pass=%d fail=%d" % [suite.suite_name(), suite._pass, suite._fail])
	get_tree().quit(mini(suite._fail, 125))

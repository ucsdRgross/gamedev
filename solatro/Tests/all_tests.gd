extends Node
## Root of all_tests.tscn: waits for every SolatroTest child suite to finish, prints a
## grand total split by category, and — when running headless (CI / agent runs via
## `godot --headless res://Tests/all_tests.tscn`) — quits with exit code = failure count.
## In the editor the tree stays alive so the output can be inspected.

func _ready() -> void:
	var suites: Array[SolatroTest] = []
	for child in get_children():
		if child is SolatroTest:
			suites.append(child)
	for suite in suites:
		if not suite.finished:
			await suite.suite_finished
	var passed := 0
	var failed := 0
	var failed_behavior := 0
	var failed_impl := 0
	for suite in suites:
		passed += suite._pass
		failed += suite._fail
		failed_behavior += suite._fail_behavior
		failed_impl += suite._fail_impl
	print("")
	if failed == 0:
		print("======== ALL %d SUITES: %d CHECKS PASSED ========" % [suites.size(), passed])
	else:
		printerr("======== ALL %d SUITES: %d passed, %d FAILED (%d behavior, %d implementation) ========"
				% [suites.size(), passed, failed, failed_behavior, failed_impl])
	if DisplayServer.get_name() == "headless":
		get_tree().quit(mini(failed, 125))

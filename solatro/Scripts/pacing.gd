class_name Pacing
extends RefCounted
## Pause-respecting timer. `SceneTree.create_timer` defaults `process_always = true`, so a bare
## `create_timer` keeps counting through a pause and a "frozen" screen advances anyway. This
## replaces every `get_tree().create_timer()` in game code (PLAN.md §1.6, D6) — not wall-specific,
## which is why it lives here rather than under Scripts/Wall/.

## Pause-respecting timer. `secs` seconds, same usage as `get_tree().create_timer(secs).timeout`.
## `Engine.get_main_loop()` is typed `MainLoop`, which has no `create_timer` (only its `SceneTree`
## subtype does) — the cast is required for this to compile under warnings-as-errors; the game
## always runs under a SceneTree, so it never fails.
static func wait(secs: float) -> SceneTreeTimer:
	return (Engine.get_main_loop() as SceneTree).create_timer(secs, false)

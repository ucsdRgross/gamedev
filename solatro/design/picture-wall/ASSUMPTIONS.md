# ASSUMPTIONS.md — reversible calls made while executing PLAN.md, one line each, citing the node

- **S1 (D7, D10, Q222):** the shipped burning-card effect does NOT advance under
  `get_tree().paused = true` — `Tests/Visual/pause_time_spike.gd`, a real `PlayArea` card with
  `CardModifierStatus.stacked(StatusBurning, 3)` attached the ordinary way (same fixture pattern as
  `Tests/UI/test_visual_layers.gd:test_fx_inside_its_host`), windowed run: 0/746496 px differed
  between t=0 and t=+20s, confirmed by eye — the two captures are indistinguishable. Its clock is
  `FxAttachment._process` (`UI/Fx/fx_attachment.gd:961`), which advances the script-pushed `u_time`
  uniform every shipped shader reads instead of built-in `TIME` (`fire.gdshader:107`);
  `FxAttachment` and every ancestor up to the tree root carry the default `PROCESS_MODE_INHERIT` —
  nothing in shipped game code writes `process_mode` at all, apart from the editor-only
  `Tools/fx_editor.gd:229` — so `_process` does not run while paused and the flame's clock freezes
  outright. (Secondary, engine-level fact, not what D7 rests on: built-in GLSL `TIME` itself DOES
  keep advancing under the same pause, measured separately on a throwaway shader that reads it
  directly — but no shipped shader reads it.) Proceeding exactly as D7 says regardless: accepted,
  hidden by the non-focused picture's frozen `SubViewport` texture (`UPDATE_DISABLED`, §1.8) — and
  now doubly so, since the flame's own clock stops as well.
- **S1 (PLAN.md §0 gap protocol rule 1 — spike scene location):** `pause_time_spike.gd` /
  `pause_time_spike.tscn` live under `solatro/Tests/Visual/`, matching the existing one-off windowed
  diagnostic scenes there (`fx_snapshot`, `prop_art_snapshot`, `reveal_shot`) — PLAN.md's SETUP note
  for this run permits `Tests/` or `Tools/` for the S1 spike and does not fix a name for it.
- **S2 (K8, GAP-005) — ⚠ INCOMPLETE, READ-ONLY HALF ONLY, by owner instruction:** the toggle half of
  S2's done-when ("toggle the Windows animation setting, print again") is deliberately NOT done here
  — the owner is running it by hand. Do not read this entry as a conclusion about whether the query
  tracks the OS setting; one reading cannot answer that.
  Observed just now, this machine, Godot 4.7.1.stable, via `Tests/Visual/reduce_animation_spike.gd`
  (a real windowed run, killed by an external hard timeout rather than relying on the scene to close
  its own window — it does call `get_tree().quit()`, but the caller still bounds it):
    - `DisplayServer.has_method(&"accessibility_should_reduce_animation")` = **true**, and the direct
      typed call compiles and runs (this is more than GAP-005's "arrived in 4.5" claim — it is
      confirmed present and callable on this exact 4.7.1 build, not inferred from the version number).
    - `DisplayServer.accessibility_should_reduce_animation()` = **false**, right now, on this machine.
    - The corresponding OS-level setting, read via `user32.dll SystemParametersInfo` with
      `SPI_GETCLIENTAREAANIMATION` (0x1042) — a GET, never a SET — = **true** (animations enabled).
      Read-only; nothing was written. This is the "before" half of the clean before/after pair the
      owner asked for; the "after" half is theirs once they toggle the Windows setting and this
      script is re-run unchanged.
  Toggle half outstanding. Neither eventual answer (tracks / does not track) is a gap per GAP-005.
- **S6 (D6) — `addons/yard`'s 3 bare `create_timer` calls are exempt from the sweep.** PLAN.md §2's
  done-when says the grep should return "only Scripts/pacing.gd and test files"; `addons/yard/...
  dynamic_table.gd` is neither, but PLAN.md §0's own rule 7 (`addons/` is vendored, never edited
  here) wins over the done-when's imprecise wording — and the file is `editor_only`, so it never
  runs in the shipped game and sweeping it would be both forbidden and pointless. Not a gap: only
  one defensible choice exists once the vendored-addon rule applies.
- **S6 (D6) — `Scripts/pacing.gd`'s body is not PLAN.md §1.6's literal text.** `Engine.get_main_loop()`
  returns `MainLoop`, which has no `create_timer` — only its `SceneTree` subtype does — so the
  literal `return Engine.get_main_loop().create_timer(secs, false)` fails to compile under this
  project's warnings-as-errors. Resolved with an explicit `as SceneTree` cast, identical runtime
  behaviour. Not a gap: the fix is reversible, has no observable behaviour difference, and `SceneTree`
  is the only type carrying `create_timer`, so exactly one correction is defensible.

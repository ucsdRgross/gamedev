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

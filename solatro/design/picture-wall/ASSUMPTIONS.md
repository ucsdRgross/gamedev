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
- **S2 (K8, GAP-005) — CLOSED. The Windows toggle did not take effect; no tracking verdict is
  possible from this pair, and none is asserted.** `DisplayServer.has_method(&"accessibility_should_reduce_animation")`
  = **true** throughout, and the direct typed call compiles and runs on this exact Godot 4.7.1.stable
  build (confirmed callable, not inferred from GAP-005's "arrived in 4.5" claim).

  **Before** (owner had not yet toggled anything), via `Tests/Visual/reduce_animation_spike.gd` (real
  windowed run, killed by an external hard timeout though the scene also calls `get_tree().quit()`
  itself) and, same source, a read-only `user32.dll SystemParametersInfo(SPI_GETCLIENTAREAANIMATION
  = 0x1042)` GET:
    - `DisplayServer.accessibility_should_reduce_animation()` = **false**
    - `SPI_GETCLIENTAREAANIMATION` = **true** (animations enabled)

  **After** (owner reports having flipped "Show animations in Windows"), same two reads, same
  machine, re-run just now:
    - `DisplayServer.accessibility_should_reduce_animation()` = **false** — unchanged
    - `SPI_GETCLIENTAREAANIMATION` = **true** — unchanged (confirmed stable across two consecutive
      read-only calls plus a `HKCU:\Control Panel\Desktop\UserPreferencesMask` cross-check, all
      read-only; nothing was written by this session)

  **Verdict: the Windows-side reading never flipped, so the toggle did not take effect on this
  machine/session** — not "does not track". Per GAP-005 this is the fallback path regardless of the
  reason: `wall_reduced_motion` defaults `false` and the first-launch seed from this query is
  skipped. Neither this outcome nor an eventual tracks/does-not-track answer is a gap.
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
- **S7 (Q159, K11) — `wall_unlock_all` added to `PlayerSettings` in THIS step, not S8.** `DESIGN.md`
  §5's tunables table omits the row, but `Q159`=(a) ("yes -- a PlayerSettings flag", DESIGN.md:1098)
  is the source, and `wall_debug_readout` (`Q210`) shows debug flags belong in that group regardless
  -- so §5's table is a documentation bug against its own source (gap-protocol rule 4), not a reason
  to leave §1.5's required flag unbuilt. `@export var wall_unlock_all : bool = false` in
  `player_settings.gd`'s new `@export_group("Picture wall")`, with the same `settings_changed`
  setter every other knob uses. S8 adds exactly `DESIGN.md` §5's rows to this group and no more.
- **S8 (Q86, Q87, GAP-002) — `wall_view_texture_scale` is NOT exported.** `DESIGN.md` §5 marks it
  *derived*, and its own header says derived values are computed, not authored; GAP-002 supersedes
  it in any case -- §1.8 writes `SubViewport.size` straight from the on-screen footprint, clamped by
  `wall_view_min_texture_px`, with no resolution manager and nothing left for a scale factor to do.
  Exporting it would ship a knob that silently does nothing. Not a gap: no observable behaviour
  difference, trivially reversible, and exactly one defensible reading once GAP-002 is read.
- **S8 (GAP-008, owner option a) — `wall_gap`, `wall_view_margin`, `wall_ellipse_aspect_min`,
  `wall_ellipse_aspect_max` are NOT exported on `PlayerSettings`**, though `DESIGN.md` §5 lists
  them. `WallLayout` is their one home (`gap_px`, `view_margin`, `ellipse_aspect_min`,
  `ellipse_aspect_max`, already built in S3) because `WallPacker` stays a pure function reading
  only the layout's copies (§1.3). The "Picture wall" `@export_group` therefore holds 19 exports
  (18 of §5's rows plus `wall_unlock_all`, S7/GAP-007), not the 23 §5's table taken literally would
  produce. S8's done-when ("every row of §5") is knowingly not met to the letter here -- the owner
  struck these four rows; this is GAP-008's resolution overriding the plan text, not a deviation.
- **S9 (PLAN.md §0 gap protocol rule 1 — diagnostic scene location):** `wall_skeleton_snapshot.gd`
  / `.tscn` live under `solatro/Tests/Visual/`, the same precedent S1 already used (`pause_time_spike`,
  `reduce_animation_spike`) -- PLAN.md's SETUP note permits `Tests/` or `Tools/` for a spike/snapshot
  scene and fixes no name for it, and NAMES.md does not name this diagnostic either.
- **S9 (B10, Q2=b) — `%WallSurface`'s `color` is a plain literal on the ColorRect, not routed
  through `PaletteDB`.** `DESIGN.md` chart B10 calls for "a flat colour from the palette", but which
  palette role is B10/Q2's own wiring and no later step name for it exists in NAMES.md yet -- inventing
  one here would be exactly the kind of unfixed choice S9 is not allowed to make, and the coordinator's
  instruction was explicit: the colour is a scene property, not a settings knob. `test_palette.gd`'s
  drift scan correctly flags it as one new `[WARN][PLACEHOLDER] hardcoded colour` (18 -> 19 this run) --
  by its own doc comment this is exactly what the channel is for, "a colour still hardcoded in a
  surface whose art has not been made yet", and it does not touch `_fail` or the exit code. Not a gap:
  the literal is reversible the moment B10's actual wiring step picks a palette role.

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
- **S4 (GAP-009) — `PictureEntry.slot : int` is read as an authored ANGLE IN DEGREES**, the owner's
  own assumption stated in `gaps/GAP-009.md`'s resolution, recorded here per that note: kept the
  shipped field shape rather than renaming it and forcing a `NAMES.md` change. `ring` is deleted
  from `PictureEntry` (nothing read it; GAP-009's resolution).
- **S4 (GAP-009, PLAN.md §1.3 rule 1) — the ellipse's anisotropic scale is baked into each
  picture's RADIUS-SEARCH RAY, not applied as a post-hoc stretch of finished positions.**
  `WallPacker._direction(slot_degrees, aspect)` uses `Vector2(cos(rad) * aspect, sin(rad))`,
  normalized, as the unit ray a picture's radius travels along. GAP-009 fixes the aspect SCALAR
  (`clamp(window_aspect, ellipse_aspect_min, ellipse_aspect_max)`) and calls the result "an
  anisotropic scale on the whole arrangement" but not its exact per-axis split -- this is the one
  formula choice left open. Baking it into the search ray (rather than scaling positions after the
  fact) is not just simpler: it is what keeps rule 6 ("no two rects overlap") true BY
  CONSTRUCTION, since gap_px is then always checked in the real final coordinates. Reversible:
  nothing downstream reads the exact per-axis split, only the resolved scalar aspect (P7) and the
  no-overlap invariant (P10/P12), both of which hold under any anisotropic split.
- **S4 (PLAN.md §1.3 rule 2) — the window-aspect stretch holds a picture's HEIGHT fixed and
  derives its width** (`WallPacker._picture_size`), matching the "height is the anchor, width
  derived" convention `PlayerSettings.wall_design_height` already documents. Rule 2's original text
  ("stretched to the window aspect") never named which axis is the anchor; this predates GAP-009
  and was never resolved by it either. Not a gap: the two conventions in this project already point
  the same way, and P8/P9 pin the resulting behaviour (aspect ratio matches window; keep_aspect
  leaves size untouched) rather than which axis moved to get there.
- **S4 (P2'/P3', S4 brief) — the first-placed picture is EXCLUDED from the "same radius" /
  "unaffected" comparisons; it is compared to 0 (P2') or to its own baseline (P3') instead of to
  its siblings.** The S4 brief's P2' says "3 pictures at angles 0, 120, 240 ... assert all three
  sit at the SAME radius." Under rule 3+4 as amended (smallest radius that clears
  ALREADY-PLACED frames, slot ascending), the picture placed FIRST has no already-placed frames to
  clear, so its minimal radius is 0 by the rule itself -- the identical fact P11 pins for a lone
  picture, just reached here on the first of several rather than the only one. It can never equal
  the other two's nonzero radius, for ANY picture sizes or gap_px > 0; this is not a bug in the
  packer, it is rule 3 doing exactly what GAP-009 specifies. Implemented instead: `a`'s radius is
  asserted to be exactly 0, and `b`/`c` (both placed after it, both 120 degrees from it) are
  asserted equal to EACH OTHER and nonzero -- the same claim the brief is making ("radius is
  computed per picture and minimised, converges by symmetry"), stated in the form the algorithm can
  actually satisfy. P3' inherited the same issue (asserting `a` and `b`'s radii equal each other,
  which was never true even at ordinary size) and is fixed the same way: `a`/`b` are compared
  against their own P2'-baseline values (same fixture, ordinary-sized `c`), proving "unaffected by
  the oversized picture placed after them" without the false "equal to each other" premise. Not
  filed as a gap: the fix does not touch the algorithm, only which comparison the test makes, and
  the property actually proved is the one the brief names.
- **S4-fix (Q9=a, GAP-009) — `layout.home_id` is placed FIRST, ahead of slot order, so it always
  takes the centre (radius 0).** `Q9`=(a) fixes the home picture as the ellipse's centre, and the
  deleted `ring` field (GAP-009) used to carry this as ring 0 = "the home ring" -- with rings gone,
  nothing else marks home as innermost, so `pack()` special-cases it: after the slot-ascending
  sort, `home_id` (if present in `unlocked`) is moved to the front. Falls back to plain slot
  ascending, unchanged, when `home_id` is locked or absent from this pack -- never centres a
  picture that produced no rect. Not a gap: gap-protocol rule 1 (`home_id` has no other purpose,
  the deleted field already said home is innermost, one line to reverse). `TestWallPacker` P13
  pins it.
- **S10 (Q7=b, B10) — the shadow offset is a single PROVISIONAL constant,
  `WallPicture.SHADOW_OFFSET`, not an authored WallLayout field.** §1.7 requires `%Shadow` "offset
  from one authored light position shared by the whole wall," but no field for it exists anywhere
  in `WallLayout`/`PlayerSettings`/`DESIGN.md` §5, and S25 ("shadows from one light position") is
  the step that actually authors/tunes it. Same constant used for every picture regardless of its
  own position, which is what "shared" means, so §1.7's requirement is met literally; only the
  exact value is provisional. Not a gap: S25 owns relocating or retuning it, and nothing downstream
  in this run reads the constant's value.
- **S10 (§1.7, done-when) — `%Frame`'s texture is whatever `PictureEntry.frame_texture` says,
  INCLUDING null.** `WallPicture.build()` is faithful to its input and invents nothing: a null
  `frame_texture` draws an empty `NinePatchRect`, mirroring the same "null is expected and
  correct" rule the coordinator stated for `PictureEntry.scene`/Q214=a. The S10 snapshot's own
  fixture (`Tests/Visual/wall_picture_construction_snapshot.gd`) assigns each frame a flat
  runtime-generated swatch colour purely so frame GEOMETRY reads in the shot -- diagnostic
  scaffolding in the same spirit as `SnapshotScene.BACKDROP`, not authored frame art (S24's job,
  patch margins and all). `TestWallRender`'s fixture leaves `frame_texture` unset (null)
  throughout, since N1/N5 only assert structure, never appearance.
- **S10 (PLAN.md §0 gap protocol rule 1 — diagnostic scene location):**
  `wall_picture_construction_snapshot.gd` / `.tscn` live under `solatro/Tests/Visual/`, the same
  precedent S1 and S9 already used -- PLAN.md's SETUP note permits `Tests/` or `Tools/` for a
  spike/snapshot scene and fixes no name for it, and NAMES.md does not name this diagnostic either.
- **S10 (§1.6 collides with the suite harness) — `TestWallRender` undoes `Wall`'s own pause
  immediately after constructing one.** `Wall._ready()` sets `get_tree().paused = true` GLOBALLY
  by design (§1.6, verified correct in S9) -- fine standalone, but `all_tests.tscn` runs ~34 suites
  CONCURRENTLY, and a global pause with nothing to clear it hangs the ENTIRE run with no banner
  (measured: 600s timeout, no suite signals finished, on the first attempt at this suite). Fixed
  with one line, `get_tree().paused = false`, immediately after `add_child(_wall)` -- safe because
  `add_child()` on an already-in-tree parent runs `Wall._ready()` SYNCHRONOUSLY, and GDScript only
  yields at an explicit `await`, so nothing else can run in the gap. ⚠ **Any later step that
  instantiates a real `Wall` inside `Tests/Wall/*.gd` (S11 render gating owns the render-mode
  states; anything after it inherits this) must do the same** or hit the identical hang -- not a
  gap, a one-line harness-interaction trap worth a flag for the next reader.
- **S10 -- `WallPicture._shadow.self_modulate`'s `Color(0.0, 0.0, 0.0, 0.35)` is a second new
  hardcoded-colour placeholder warning (20th; S9 added the first), same mechanism as `wall.tscn`'s
  `%WallSurface` colour.** A dark, partly-transparent tint for the drop shadow, not routed through
  `PaletteDB` -- same reasoning as the S9 entry above: no palette role for it exists yet, inventing
  one would be a gap, and `test_palette.gd`'s drift scan is correctly flagging real, deliberate,
  temporary art (`_fail`/exit code untouched). Reversible the moment a real shadow-tint role exists.
- **Pause-model spike (D6, Q75, QR6) -- MEASUREMENT ONLY, no §1.6 or production code changed.**
  `Tests/Visual/pause_model_spike.gd`, run windowed by hand, printed:
    - **Q-A** `paused=true`, `PROCESS_MODE_ALWAYS` node: ticked 12 times over 0.30s real time --
      **KEPT PROCESSING**. Confirms §1.6's load-bearing claim: the wall/camera are not frozen by
      the global pause flag.
    - **Q-B** `paused=false`, `PROCESS_MODE_DISABLED` node: ticked 0 times over 0.30s -- **STOPPED**.
      `PROCESS_MODE_DISABLED` halts `_process` unconditionally, independent of the tree's own
      paused state.
    - **Q-C** (the decisive one) `paused=false`, `PROCESS_MODE_DISABLED` node, `.timeout` on a
      `get_tree().create_timer()` the node's OWN script started BEFORE being disabled: **THE AWAIT
      RESUMED ANYWAY** (`resumed=true`). Confirms the coordinator's expectation exactly: a
      `SceneTreeTimer` is owned by the `SceneTree`, not by any node, so a node's `process_mode` has
      NO power to stop a timer/await already in flight on that node's own script -- only
      `process_mode` gates `_process`/`_physics_process` notifications, nothing else. **This means
      the owner's proposed model ("wall never paused, pictures `PROCESS_MODE_DISABLED` by default")
      would NOT actually freeze a "disabled" screen's in-flight timers or awaits** -- exactly the
      trap the coordinator named going in.
    - **Q-D** `paused=true`, `PROCESS_MODE_PAUSABLE` node (today's ordinary default), run twice
      (D1: timer created while already paused, watched to +0.60s; D2: timer already counting, THEN
      paused mid-flight, watched to +0.666s), matching TEST_PLAN.md U5's own fixture shape: a bare
      `get_tree().create_timer()` (`process_always=true`, the default) correctly fired at its
      nominal delay in both trials (+297ms, +316ms for a 0.3s request, paused throughout).
      **`Pacing.wait()` correctly did NOT fire in either trial** (`fired=false` at the point the
      spike stopped watching) -- `Scripts/pacing.gd` IS pause-respecting, as designed. An earlier
      version of this entry recorded the opposite (`Pacing.wait` firing at ~0ms) from a run before
      the trap below was found and fixed; that record was itself wrong and is superseded by this one.
  ⚠ **TRAP (found auditing this spike; not one of the four questions, but why the previous
  Q-D run above lied) -- `await some_timer` on a bare `SceneTreeTimer` value resolves IMMEDIATELY
  without suspending; GDScript's `await` only actually suspends on a `Signal` (or a running
  coroutine's function state).** Only `await some_timer.timeout` suspends correctly. The spike's
  Q-D fixture (`TimerNodeD._run_pacing()`) originally wrote `await Pacing.wait(0.3)` -- missing
  `.timeout` -- so the await returned immediately with the `SceneTreeTimer` object itself as its
  value instead of waiting for the signal, which is why it previously reported `fired=true` at
  ~0-1ms and looked exactly like `Pacing.wait` resolves instantly. That was a bug in the spike's
  measurement, not a defect in `pacing.gd`; confirmed by an independent throwaway probe (not
  reusing the spike's code) that explicitly awaited `.timeout` and observed `Pacing.wait(0.3)`
  correctly NOT firing within a 1.0s bound while paused. Fixed at `pause_model_spike.gd:112`
  (`await Pacing.wait(0.3).timeout`); every other `await` in the file was audited and already
  targets a real `.timeout` signal or a coroutine call. **TEST_PLAN.md's U5 and U6 are exactly
  this shape** (asserting on a `Pacing.wait(...)` await) and will walk straight into the same
  false result at S12 unless they also await `.timeout`.

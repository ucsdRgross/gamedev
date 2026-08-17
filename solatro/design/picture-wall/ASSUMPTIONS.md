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
- **S10 (Q7=b, B10) — SUPERSEDED by S25.** The shadow offset started as a single PROVISIONAL
  constant, `WallPicture.SHADOW_OFFSET`; S25 promoted it to `PlayerSettings.wall_light_offset`
  (default unchanged, (18, 26)) once §1.8's rule made the literal a defect rather than a
  placeholder. See the S25 entry below for the live knob.
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
- **S11 (E7, Q208=b) — `NOTIFICATION_APPLICATION_FOCUS_IN` is the "restore from minimise" hook.**
  §1.8's row requires re-rendering every picture "on window restore from minimise", but neither
  DESIGN.md nor PLAN.md names an engine event for it, and Godot has no dedicated un-minimise signal
  on desktop. `NOTIFICATION_APPLICATION_FOCUS_IN` is the closest built-in match; it also fires on a
  plain alt-tab back (Q207=a, "nothing special"), which is harmless here since `mark_for_rerender()`
  costs one `UPDATE_ONCE` frame and E6 already calls a frozen-texture re-render cheap by
  construction. `Wall._notification` hooks it in `wall.gd`. Not a gap: reversible (a future step can
  swap the constant with no observable change to anything downstream), and no more specific desktop
  signal exists to prefer.
- **S11/S12 — `WallPicture.screen_root` is a new public field, named for §1.6/§1.8's own prose
  ("screen root"), not fixed by NAMES.md.** Mirrors `viewport` (already public on this class for the
  same reason: callers and tests need to read/flip its state). Holds `entry.scene.instantiate()`, or
  null when the entry has none (Q214=a). `focus()`/`unfocus()` flip its `process_mode` between
  `ALWAYS` and `PAUSABLE` (D3/D4); `build()` sets it `PAUSABLE` by default. Not a gap: NAMES.md fixes
  identifiers for things it enumerates, and an internal field on an already-named class holding an
  already-named concept ("screen root") is not among them — inventing a *class* or *scene* name
  would be.
- **S12 (D2, NAMES.md) — U2 originally asserted `Wall` and `%Camera2D` only, because `WallOverlay`
  (S35) did not exist yet and building it to backfill a test would have been out of scope for S12.
  SUPERSEDED by S35: U2 now asserts all three** (`Wall`, `%Camera2D`, `%Overlay`), since `WallOverlay`
  is mounted at `%Overlay` in `wall.tscn` as `PROCESS_MODE_ALWAYS`, matching D2 in full.
- **S12 — `TestWallPause` is spliced into the suite-wait chain as the new permanent tail, ahead of
  `LEAK CANARY`.** U1 requires a REAL `Wall`'s pause to be asserted, unmodified, by a test that never
  clears it (see the pause-model-spike entry above and the trap it documents) — but `get_tree().paused
  = true` is global, and every earlier Wall-render suite (S10, S11) had to *undo* that pause
  immediately after construction specifically so the ~34 OTHER concurrently-running suites would not
  freeze waiting on their own `_process`/timer-driven work. Those two requirements are incompatible
  for a suite that runs concurrently with anything else, so `TestWallPause` instead waits
  (`await_siblings_except([])`, i.e. for literally everyone) and never undoes the pause it triggers —
  safe only because, by the time it starts, every other suite has already called `finish()`. This
  required moving `LEAK CANARY` (previously the true tail, `await_siblings_except([])`) one link
  earlier: it now excludes `"WALL PAUSE"` so the two do not deadlock waiting on each other, and
  `INTERACTION`/`UI PROPS`/`VISUAL LAYERS`/`E2E RUN` (which all transitively waited on "everyone",
  i.e. on `LEAK CANARY` and therefore now also on anything `LEAK CANARY` itself waits for) each
  gained `"WALL PAUSE"` in their own exclude lists too, per `test_base.gd`'s own DEADLOCK RULE
  ("add its name to the excludes of every suite BEFORE it"). `test_base.gd`'s SUITE ORDERING comment
  is updated to name the new order. Not a gap: mechanical, reversible, and the only way to give U1 a
  real (non-vacuous) assertion without corrupting a sibling suite.
- **S12 — `TestWallPause`'s three fixture pictures use a throwaway `PackedScene` built at runtime
  (`PackedScene.new()` + `.pack()` on a bare `Node`) as their `entry.scene`, standing in for a real
  screen.** U3/U4/U7 need an actual instantiated "screen root" node to read `process_mode` off of;
  no existing screen scene is a lighter fixture, and NAMES.md fixes no test-fixture scene for this.
  Not a gap: purely a test-side fixture choice, same shape as `test_wall_render.gd`'s own
  programmatic `WallLayout`/`PictureEntry` fixtures (never `res://Assets/Wall/layout_default.tres`).
- **S12 (U5, U6) — a SECOND trap in the same family as the pause-model-spike's `.timeout` slip,
  found running this suite for real: a GDScript lambda captures an outer local variable BY VALUE,
  not by reference.** `Pacing.wait(0.1).timeout.connect(func(): fired = true)` compiles clean and
  looks correct, but the closure writes a throwaway copy of `fired` -- the outer variable the
  `check()` call reads never moves, so `check(not fired, ...)` passes REGARDLESS of whether the
  timer fired. Caught because U6 (`check(fired, ...)`, the trap-detector row TEST_PLAN.md says must
  stay green) went red first: the real bare timer WAS firing, but its handler's write never reached
  the outer scope either. Fixed by boxing the flag in a one-element `Array[bool]` and mutating
  `fired[0]` inside the closure -- Arrays are reference types, so the same backing value is read
  outside. Both `test_wall_pause.gd` U5 and U6 use this shape now. Not a gap: mechanical, and this
  is now the second documented case (after `await` vs `await x.timeout`) of a syntactically-valid
  GDScript idiom that silently produces a vacuous pass-by-construction test -- worth flagging for
  whoever next writes a `fired`/`done`-flag-in-a-closure test in this codebase.
- **GAP-010 (owner: "snapping in place") — the rebalancing formula.** The resolution fixes that
  authored angles become starting positions and that lopsidedness must be reduced, but not the exact
  formula. Implemented in `WallPacker._rebalanced_angles()`: when every authored non-home picture in
  the layout is unlocked, there is nothing to close a gap for, and the resolved angle is the literal
  authored `slot`, byte-for-byte unchanged from before GAP-010 -- this is why P2'/P6/P7/P9/P10/P12/P13
  (all full-unlock fixtures) needed no changes at all. When some are locked, the surviving ring is
  re-sequenced in AUTHORED order (sorted by `slot`, never by `unlocked`'s own order) and evenly
  redistributed around the full 360 degrees, anchored at the smallest-slot survivor's own authored
  angle. Reversible, and the one property every reading of "reduce lopsidedness" agrees on (perfectly
  even gaps) rather than a partial-credit compromise; picked over a locked-neighbour-only "gap
  absorption" scheme because the latter does NOT reduce to the identity at full unlock in general
  (Voronoi-style wedge midpoints shift even a fully-unlocked, unevenly-authored ring off its literal
  angles, which every full-unlock test above would have caught as a regression).
- **GAP-010 — TEST_PLAN.md P4' fixture adds a 4th, always-unlocked `home` picture not part of the
  6-picture authored ring.** Needed so the 3 tested ring pictures (p0/p1/p3) all negotiate a
  genuinely nonzero radius against `home` (which always takes the centre, Q9=a) -- without it,
  whichever ring picture sorts first would itself land at radius 0 (rule 3, "nothing yet to clear")
  and `Vector2.ZERO.angle()` reads 0 regardless of that picture's true resolved angle, making an
  angle-based imbalance measurement meaningless for that one picture. Not a gap: a test-fixture
  choice, and the imbalance measure itself (max-gap-minus-min-gap across the 3 ring pictures,
  asserted near zero; TEST_PLAN.md's own ask for "a concrete, defensible imbalance measure") is
  unaffected by which picture happens to occupy the centre.
- **S35 (`WallOverlay`) — signal names (`back_pressed`, `forward_pressed`, `wall_pressed`,
  `info_toggled`) and the `refresh(stack: FocusStack)` method are new identifiers NAMES.md does not
  fix.** NAMES.md fixes the scene/script path, `class_name`, `extends` and node names (`%BackButton`
  etc. are this implementer's own choice too, same reasoning) but names no signals or methods for
  this class, unlike `Wall`'s own signals which ARE listed. Not a gap: internal wiring on an
  already-named class, same category as `WallPicture.screen_root` above. `refresh()` takes a
  `FocusStack` directly rather than two bare bools (`can_back`, `can_forward`) because that is
  exactly the information `Wall` already holds and passing the object is simpler than the caller
  unpacking it first; nothing downstream is coupled to the choice.
- **S35 — Back/Forward/Wall are laid out bottom-left, Info top-right, via individual per-Button
  anchors on the `CanvasLayer` (no `HBoxContainer`).** DESIGN.md fixes ONLY that Info is top-right
  (B8/F7); Back/Forward/Wall's exact position is unspecified. Not a gap and not by-eye-verified:
  S35's own PLAN.md done-when is purely testable (controls exist, localised, Back disables
  correctly) — unlike S13/S24/S25/S37, nothing in S35's step requires a by-eye sign-off, so the
  layout is functional scaffolding for Phase 3+ (which wires real navigation) rather than a
  finished look; Phase 5/6 art steps or a dedicated layout pass may reposition it freely.
- **S35 — `WALL_BACK`/`WALL_FORWARD`/`WALL_OVERVIEW`/`WALL_INFO` localised as "Back"/"Forward"/
  "Wall"/"Info" in `Locale/localization.csv`, inserted under the existing `UI` section** (after
  `CHOICE_REROLLS_LEFT`, before the blank rows preceding `CARDS`) since no `WALL` section header
  exists and NAMES.md fixes the keys but not their English text or file placement. Not a gap: plain,
  literal English labels for exactly what each control does: reversible whenever real copy lands.
- **S37 (H3, Q27=c) — `WallPicture.focused_scale()` is a new pure static method, and its
  `_OVERFILL_MARGIN` (1.02) is a numerical safety constant, not a `PlayerSettings` knob.** DESIGN.md
  names no field for the tiny always-overfill margin Q27=c requires even at an exact aspect match
  (a corkboard-square picture in a square window); §1.8's "no literal outside PlayerSettings/
  WallLayout/PictureEntry" rule is written for render-gating specifically, and this is the same
  category of thing as `wall_packer.gd`'s own `_EPS`/`_BISECT_ITERATIONS` -- an algorithmic
  tolerance nobody would want to retune per-player, not a design lever. `focused_scale()` itself
  (a pure `Vector2, Vector2 -> float` function, no picture/camera state) is new because nothing
  computed a fill-and-crop scale before S37; S14's real camera-tracking is its intended future
  caller.
- **S37/S13 — measured, not assumed: `Camera2D.zoom` in this project acts as DIRECT magnification**
  (`zoom = 2.0` doubles apparent size), not the inverse convention some Godot docs phrasing suggests.
  Confirmed by rendering `focused_scale()`'s output both ways and reading which one actually
  overfills the window (`Tests/Visual/wall_overfill_snapshot.gd`). Also measured: `window/stretch/
  mode="canvas_items"` + `aspect="expand"` (`project.godot`) means 2D nodes -- Camera2D included --
  operate in a LOGICAL canvas size that is NOT the raw window pixel size: one axis stays anchored to
  the project's base width (1152) and the other expands to match the window's aspect (e.g. a
  1064x800 OS window reads back as `get_viewport().get_visible_rect().size` == `(1152, 866)`).
  `wall_overfill_snapshot.gd` reads `get_visible_rect()` AFTER awaiting two `process_frame`s past
  `DisplayServer.window_set_size()` rather than trusting the requested size directly, and any future
  code computing `focused_scale()` from a live window must do the same.
- **S13 — `WallPicture.build()`/`focus()`/`unfocus()` now own `%Screen.texture_filter` outright**
  (H5): `build()` sets it explicitly to LINEAR (the "non-focused" baseline -- CanvasItem.texture_
  filter otherwise inherits the PROJECT default, which `project.godot` sets to NEAREST for pixel
  art, the wrong default here), `focus()` calls `update_filter(false)` (NEAREST, entering focus is
  always "at rest"), and `unfocus()` resets to LINEAR explicitly rather than through `update_filter`
  (whose zoom-branching is only meaningful for the picture that IS focused). `update_filter()`
  itself (S11) and its zoom-vs-pan contract (N7) are unchanged.
- **S13 — `Tests/Visual/wall_filter_swap_snapshot.gd` renders a coarse (4px-cell, 32x32) synthetic
  checkerboard, not a real screen, as both pictures' `entry.scene`.** Fine per-pixel detail is what
  makes a NEAREST/LINEAR difference visually unmistakable once magnified; no other content in this
  run has that property on demand. Diagnostic scaffolding only (same category as S10's flat-swatch
  frame textures), not authored content.
- **S14 (Q46=b, §1.10) — the coordinator's ruling: total duration is `settings.base_delay *
  settings.wall_transition_delay`, using the EXISTING S8-built knob.** §1.10's own text names
  `settings.wall_transition_delay_scale`, which does not exist and which NAMES.md does not fix --
  S8 built `wall_transition_delay` (default 0.6), the name `DESIGN.md` §5 and NAMES.md both fix, and
  NAMES.md is normative for settings keys. §1.10's stale name is a documentation bug against its own
  source (gap-protocol rule 4), not a reason to add a second knob. At defaults, `1.0 * 0.6 = 0.6`,
  consistent with §5's own "0.6 s" annotation. `WallTransition.total_duration()` implements exactly
  this formula. No new knob added; the existing one not renamed.
- **S14 (Q47=b, §1.10's phase table) — the three phase fractions overlap by splitting their excess
  evenly at each of the two phase boundaries.** `wall_zoom_out_fraction + wall_travel_fraction +
  wall_zoom_in_fraction` sums to 1.10 at defaults (`player_settings.gd`'s own comment: "phases
  overlap, so the three shares sum past 1"), but no formula in PLAN.md or DESIGN.md fixes HOW the
  0.10 excess maps to actual overlap. `WallTransition.sample_at()` splits it evenly
  (`overlap = (sum - 1.0) / 2`) between the zoom-out/travel boundary and the travel/zoom-in boundary
  -- the one construction that needs no new authored knob, degrades to a hard cut at overlap=0 (no
  excess), and always lands zoom-in exactly at t=1.0 for ANY three fraction values, not just the
  defaults. Reversible: nothing outside `sample_at()` depends on the exact split, only on the two
  invariants T3 and T1/T5 actually check (position starts moving before zoom-out's OWN window ends;
  total duration and travel's own duration are pure functions of settings).
- **S14-fix (Q48=b, `wall_frame_reveal_margin`, DESIGN.md §5, overseer ruling) — the margin is a
  fraction of the LARGER of the source and destination PICTURES' OWN sizes** (`PictureRect.size`,
  never the frame outer rect and never the union), replacing an earlier build that scaled it off
  the union bounding box. `DESIGN.md` §5 names it "extra share of the picture's size" -- singular,
  though a transition has two -- and the union reading made the margin grow with separation (two
  distant pictures pulled the zoom-out back further the further they were apart, instead of
  revealing a consistent sliver past each frame). The overseer's ruling: use the larger of the two
  pictures' sizes, componentwise per axis -- it guarantees at least the configured share of EACH
  picture is revealed and satisfies Q48=b's "show both frames plus the margin" without adding a
  second knob. `WallTransition._wide_zoom()` implements it.
- **S14-fix (T4 asymmetric variant) — `_wide_zoom()` also had to stop assuming the union bounding
  box is centred on the camera's own fixed position.** The wide-zoom plateau's camera position is
  the straight-line MIDPOINT of the two picture centres (Q51=a; proven equal to `sample_at()`'s own
  travel-eased position there, since TRANS_SINE/EASE_IN_OUT sits at exactly progress 0.5 at the
  plateau instant with this run's default fractions). The original build fit `union.size` as if it
  were centred on that midpoint, true only for a symmetric fixture (same size, opposite offset).
  Adding a genuinely asymmetric T4 variant (different `size_multiplier` and different `frame_px` on
  the two pictures -- `Tests/Wall/test_wall_transition.gd:test_zoom_out_shows_both_frames_plus_margin_asymmetric`)
  reproduced the flagged limitation for real: the dest frame's far edge fell outside the fitted
  window (measured, before the fix: visible x-max 917 vs dest frame x-max 1060, for centres at
  ±600, source size 200x200/frame 10, dest size 800x400/frame 60, window 1280x720, default 0.08
  margin). Fixed in `_wide_zoom()` by computing each axis's needed half-extent as the largest
  ONE-SIDED reach from the fixed midpoint to either frame's near or far edge, not half of the raw
  union width/height -- the two coincide exactly in the symmetric case, so T4's original assertions
  are unaffected. Not a gap: reversible, and the fix stays entirely inside `_wide_zoom()` (camera
  position / straight-line travel, Q51=a, is untouched).
- **S14/S15/S16 — `WallTransition` never touches `SubViewport.render_target_update_mode` or
  `%Screen.texture_filter`.** Landing leaves the destination mid-focus: its `screen_root` is
  `PROCESS_MODE_ALWAYS` (via the `dest_visible` latch) but its viewport keeps whatever render mode
  S11's wall-view sizing last left it at, and its filter keeps whatever S13 last set. A full
  `focus()`/`unfocus()` handoff at landing (§1.8's UPDATE_ALWAYS + full design_size, §1.7's filter)
  needs the WALL's own wall-view camera state (this class only ever sees two pictures at a time, not
  the whole wall), which is a later integration step's job, not named by any T1-T10 row. Not a gap:
  NAMES.md scopes this class to "the camera tween and its phase clock" alone.
- **S14 (T2) — a THIRD trap in the "test passes while asserting nothing / test silently corrupts
  the run" family this branch keeps finding, this time on the exit-time leak gate rather than a
  check().** `Game extends CardEnvironment extends Node` -- NOT `RefCounted` -- so `Game.new()`
  inside a test, used only to read `get_delay()` and discarded, is a genuine Node leak unless freed
  explicitly (`queue_free()`'s deferred path is not even needed, since it is never added to a tree --
  a plain `.free()` suffices). Missing this made `run_tests.py`'s exit-time gate fail
  ("N resources still in use at exit") despite every suite banner reading green -- caught by
  bisecting `test_wall_transition.gd`'s own tests down to T2 alone, since `all_tests.gd`'s own
  in-run engine-error scan cannot see exit-time leaks by construction (`run_tests.py`'s own header
  comment explains why). Fixed with one `game.free()` line. Worth flagging alongside the `.timeout`
  and lambda-capture-by-value traps: any test that does `SomeNodeSubclass.new()` for a quick read
  and never adds it to a tree needs an explicit `.free()`, not just reference-drop.
- **S17 (C16, Q26=a) — `WallTransition.retarget()` swaps geometry fields the running tween's own
  per-frame callback re-reads, never restarts the tween.** `request()`'s `tween_method` closure used
  to capture `source_rect`/`dest_rect`/`window_size`/`settings` as ordinary locals; moved to instance
  fields (`_source_rect` etc.) so `retarget(new_source_rect, new_dest_rect, new_window_size)` can
  overwrite them mid-flight and have the very next `_apply()` call sample the new geometry, with
  `_dest_id`, `_total` and every latched pause/unpause/input-unlock boundary untouched. T11 proves
  two things: the resulting position discontinuity is bounded by the resize's own geometry shift (a
  lerp of two points that each moved by at most `max_shift` cannot itself move by more than
  `max_shift`, for any travel progress -- a provable bound, not a tolerance guess), and the SAME
  tween instance keeps running to completion afterward (a real short Tween, landing on the original
  `_dest_id`). Not a gap: reversible, and this is the only way to satisfy "continues" (Q26=a) without
  a second Tween or a restart.
- **S17 — the actual RE-PACK that produces new geometry on resize/fullscreen (G7, G8) is NOT this
  class's job and is not built here.** `WallPacker`/`Wall` own repacking the layout instantly on
  resize (G8: "re-pack snaps instantly... fullscreen toggle also snaps"); `WallTransition.retarget()`
  only accepts whatever new `PictureRect`s/window size that already-instant repack produces and keeps
  the camera tween running against them. Not a gap: NAMES.md scopes this class to the camera tween
  and clock alone, same boundary the class doc comment already draws elsewhere.
- **S18 (K8, Q172=a) — reduced motion is "a cross-fade at a fixed zoom," and the fixed zoom chosen is
  `_wide_zoom()`'s own "show both frames" framing, held for the entire duration (camera position
  included, at the straight-line midpoint of the two centres).** Neither PLAN.md nor DESIGN.md fixes
  WHICH zoom level "fixed" means; reusing `_wide_zoom()` needs no new tunable, guarantees both frames
  stay in view for the whole cross-fade (consistent with K9, "wall view still exists under reduced
  motion, reached by cross-fade" -- the same wide framing serves both), and makes `sample_at()`'s
  branch a handful of lines instead of a new code path. Not a gap: reversible, only `sample_at()`
  reads this choice, and T12 (the only gated done-when clause, "camera zoom is constant") holds under
  any fixed value.
- **S18 — the actual cross-fade (blending the two SCREENS' opacity) is NOT built here**, same
  "camera and clock only" boundary S14-S16 already drew for the landing handoff. `sample_at()`'s
  reduced-motion branch supplies a motionless camera Sample; whatever later step wires real screens
  into the wall (Phase 7) owns fading their opacity against it. Not a gap: no T-row asks for opacity,
  and NAMES.md names no field for it.
- **Phase-3-close (Q175=b, K10) — `wall_transition_speed` REMOVED from `PlayerSettings` and from
  `DESIGN.md` §5's tunables table.** S8 built it (unused) only because §5's table listed it; S18
  then flagged the table against chart K10, which states outright "there is no separate
  transition-speed knob -- the always-instant setting IS the reduced-motion flag" (`DESIGN.md:755`)
  -- i.e. `Q175`=(b), not the table's implied (a). Overseer ruling: gap-protocol rule 4 (both
  documents restate one answer, so go to the answer) -- a documentation bug against the source,
  not a decision to escalate. Nothing read the export (confirmed by grep before removal), so
  deleting it is behaviour-neutral. The "Picture wall" `@export_group` now holds 18 exports.
- **S36 — selection/framing/pan land on `Wall` itself, not a new class.** NAMES.md fixes
  `Scripts/Wall/wall_input.gd`/`WallInput` as "event ROUTING: wall-space hit test,
  make_input_local, push_input" (Phase 4, S19-S23) -- a narrower job than F10-F12/G9-G11's
  selection state and wall-view framing/pan, which is inherently about the pictures `Wall` already
  owns (NAMES.md: "owns the camera, the pictures, the overlay"). Inventing a second, unnamed class
  for it would be exactly the kind of choice NAMES.md's own header forbids; `Wall` is the one
  already-named class whose role covers it. Not a gap: one defensible reading once NAMES.md's own
  role description is read literally.
- **S36 (Q98=a, TEST_PLAN I5/I6) — `Wall.move_selection()`'s exact algorithm: nearest candidate
  whose offset has a positive dot product with the pressed direction; wrap picks whichever
  candidate's offset has the MOST NEGATIVE dot product instead.** Neither PLAN.md nor DESIGN.md
  writes the formula -- Q98's own text only says "spatially -- the nearest picture in that
  direction" plus Q106 "wraps." This is the one construction that (a) needs no ring/angle
  bookkeeping PictureRect does not carry post-pack, (b) reduces to "wraps to the far extreme" for
  any picture arrangement, not just a fixture-specific one, and (c) is provably well-defined
  (some candidate always has the most negative dot unless there is exactly one picture, handled
  separately). `Tests/Wall/test_wall_input.gd`'s I5/I6 fixture places six pictures at distinct,
  non-tied distances specifically so "nearest" and "most opposite" each have exactly one
  unambiguous winner -- a real property of the geometry, not a fixture tuned to dodge a limitation
  (the T4 lesson from Task A2, applied here by construction instead of retrofit).
- **S36 (F10) — "every picture remembers its internal focus for the session" needs no code.**
  `screen_root` nodes are built once by `WallPicture.build()` and never destroyed/recreated across
  a wall-view visit (§1.6/§1.8's whole model), so any `Control` focus a screen sets on itself
  already persists on that same node instance with zero help from `Wall`. Not a gap: the
  architecture already guarantees the property: nothing to build.
- **S36 (F11, Q69=a) — "starting at the one you came from" is implemented as a full re-seed on
  every `enter_wall_view(from_id)` call, not a separate "remembered last selection" that
  `from_id` might override.** F10's "the wall remembers its selected picture" and F11's "starting
  at the one you came from" read as being in tension (remember vs. always reset) if taken as two
  independent behaviours; the one reading that makes both true simultaneously, with no second
  piece of state, is that "remembering" IS "re-seeding to the picture you're standing in front of"
  -- which is always well-defined the moment you press the wall-overview action from inside a
  screen. Not a gap: PLAN's own words ("starting at the one you came from") fix this outcome for
  every entry, and nothing else names a DIFFERENT value the memory should hold instead.
- **S36 (F12, Q71=c) — "every picture is always enterable" needs no code.** No disabled/locked-
  but-visible state exists anywhere in `PictureRect`/`PictureEntry`/`WallPacker` (`WallPacker`
  simply omits a locked picture from its output, §1.3 rule -- Q158=a, "locked pictures are not
  drawn at all"), so every packed `PictureRect` already denotes an enterable picture by
  construction. Not a gap: nothing to build, the same shape as GAP-protocol rule 1.
- **S36 (G11, Q4=b) — "no free zoom in wall view" needs no code either, for now.** No zoom input is
  wired to anything wall-related yet (that wiring is S22/S23, Phase 4); the requirement is
  satisfied vacuously by `Wall` simply not exposing a zoom-input handler. Flagged, not a gap: S22/
  S23 must NOT add one for wall view (any zoom input there is instead "a request to enter a
  picture," Q4=b), a constraint on a step this run does not build.
- **S36 (G9, Q5=b) — `Wall.wall_view_zoom()`/`clamp_pan()` are NOT gated by any T/I-row and are
  therefore UNVERIFIED by this run's own suite** (S36's done-when only names I5, I6, I9, and the
  Wall-button clause). Built anyway because PLAN.md's own S36 line names G9/G10/G11 as "implements,"
  and leaving fill-crop/pan entirely unbuilt would leave S36 half-done rather than merely
  untested. `wall_view_zoom()` reuses `WallPicture.focused_scale()`'s existing fill formula (H3)
  against the union of every packed frame's outer rect (`_wall_extent()`), the direct generalisation
  of "one picture, fill and crop" to "the whole wall, fill and crop." `clamp_pan()` bounds the
  camera to the extent, collapsing to the extent's own centre on whichever axis is already fully
  visible (G10's "on a large screen... panning is off"). Nothing currently CALLS either method
  (no camera-driving step exists yet for wall view -- that is S19-S23's job), so this is
  provisional, unverified plumbing in the same spirit as S10's shadow-offset constant, not a
  finished, exercised feature. Flagged for whoever wires wall-view camera input to add coverage
  then.
- **S36 — `WallPicture.rect` (the packed rect `build()` was given) and `WallPicture.set_selected()`
  (the lift-only selection highlight) are new public members NAMES.md does not fix**, same
  category as `screen_root` (S11/S12) and `focused_scale()` (S37) before them -- internal surface
  on an already-named class, not a new class/scene/signal identifier. `set_selected()`'s frame-glow
  half is deliberately NOT built (no frame art/shader input exists yet, S24); only the Y-offset
  lift (`_SELECTED_LIFT`, a provisional constant, same shape as `SHADOW_OFFSET`) is. Not a gap:
  S24 owns the glow once there is a frame to glow.
- **S36 — `WallOverlay.refresh()`'s signature grew a second, DEFAULTED parameter
  (`picture_count: int = 2`)** rather than a new method, so the existing F8/F9 tests
  (`test_wall_focus.gd`, calling `refresh(fs)` with one argument) keep compiling and keep meaning
  "visible" (any value > 1) unless a caller says otherwise. NAMES.md already notes `refresh()`'s
  signature is not fixed by it (S35 entry above). Not a gap: additive, reversible, and the only
  change that does not also touch S35's already-committed test file.
- **latch-fix (Q72=a) — a real bug, not a gap (owner's own correction, overriding an earlier
  GAP-012 that was withdrawn): the source-pause latch is now scheduled by a precomputed TIME,
  never by re-checking the live `source_frame_in_view` condition per sampled frame.** Measured
  directly (`Tests/Visual/wall_transition_latch_timing_spike.gd`, kept as a diagnostic): that raw
  condition is TRANSIENT, not monotonic-to-completion -- true only across roughly the first half of
  a transition, then false again all the way to landing -- so a real per-frame Tween callback can
  validly sample zero frames inside the window and never observe it, leaving the source stuck
  `ALWAYS` forever (measured failing 3/3 real trials at `wall_transition_delay=0.02s`, and
  intermittently even at the 0.1s duration T13 itself uses). `_find_source_pause_time()` scans
  `sample_at()` ONCE at `request()`/`retarget()` time (cheap; never per rendered frame) for the
  first instant the condition holds, and `_apply()` compares the tween's own `elapsed` against that
  stored time rather than re-testing the geometry -- frame-rate independent, since the tween is
  guaranteed to eventually reach `elapsed == total` at landing. Falls back to the end of the
  zoom-out phase if no crossing exists for a given geometry at all (§1.6's "exactly one ALWAYS
  screen root" is absolute and outranks hitting the precise instant). `retarget()` (S17)
  recomputes it against the new geometry, since a precomputed crossing time from the OLD rects is
  meaningless once they change.
- **latch-fix — regression test added and VERIFIED RED-then-GREEN, not merely written.**
  `test_wall_transition.gd:test_source_pauses_under_real_sparse_frame_sampling` drives a REAL,
  unforced transition at `wall_transition_delay=0.02s` (the measured 3/3 failure point) -- unlike
  T13, which forces a sample at the plateau and is blind to this class of bug by construction. Run
  against the pre-fix code: FAILED both assertions (`source process_mode=3` i.e. still `ALWAYS`,
  `always_count=2`). Run against the fix: PASSED, three consecutive full-suite runs, 38 suites
  green each time. T13's own forced plateau sample is kept (a deterministic gate is still right for
  the dest-side latches it also exercises), but no longer carries the source-pause guarantee alone.
- **S22 (owner's own ruling: "automated coverage for now") — controller's done-when is RELAXED,
  NOT MET.** PLAN.md requires "the controller driven by hand through one full
  navigate-enter-back-wall cycle"; that has not happened. `TestWallInput`'s I10
  (`_test_most_recent_device_wins_controller_after_mouse`) covers only what a synthetic
  `InputEventJoypadButton` can prove headless — that a controller-shaped action press latches the
  selection indicator after a mouse move alone did not. **Still owed, untested by anything in this
  run: deadzones, analogue-stick ramps/repeat timing (`wall_selection_repeat_delay`'s own
  controller-held-stick case), and device hotplug/disconnect mid-session.**
- **S23 (GAP-003=a, GAP-004=b) — `WallInput.PinchTracker` and `touch_target_px()`/`mm_to_px()`
  are NEW members of `WallInput`, not fixed by §1.9's code block (which pins only `route()`'s own
  signature).** The prose bullets ("track two ids, compare distance delta"; the clamp formula) are
  normative; the exact shape holding that state across events is not, so a nested `RefCounted`
  class (`WallInput.PinchTracker`, one instance per in-progress two-finger gesture, `feed(event,
  threshold_px) -> Gesture`) was chosen — same "class docs pin the contract, not literally
  everything" latitude S6's `Pacing` cast and S8's knob placement already used. `Gesture` LATCHES
  once per two-finger session (fires at most one `PINCH_OUT`/`PINCH_IN` even as the fingers keep
  moving further past threshold), matching Q119=a's "pinch is a one-shot request, not a continuous
  stream" — the same reasoning `WallTransition`'s own pause/unpause/input-unlock booleans already
  rest on. `touch_target_px(dpi, settings)` takes DPI as a parameter rather than reading
  `DisplayServer.screen_get_dpi()` internally, purely so `TestWallInput` I13 can feed synthetic
  absurd values; the real call site (not built this batch — nothing yet asks for a live target
  size) is `WallInput.touch_target_px(DisplayServer.screen_get_dpi(), settings)`.
- **GAP-011 (owner-answered a): `wall_overfill_margin` replaces `wall_picture.gd`'s
  `_OVERFILL_MARGIN` literal.** `WallPicture.focused_scale()` gained a REQUIRED third parameter
  (`overfill_margin: float`, no default) rather than reading `SettingsManager` internally — it
  stays a pure function (same discipline `WallPacker`/`WallTransition.sample_at()` already use),
  so every caller supplies the live value itself: `SettingsManager.settings.wall_overfill_margin`
  from `Wall.wall_view_zoom()` and the two `Tests/Visual` snapshot scripts (no engine-singleton
  restriction there), `settings.wall_overfill_margin` from `WallTransition.sample_at()` (already
  took `settings: PlayerSettings` as a parameter, same pure-function contract as `WallPacker`).
  Behaviour is UNCHANGED at the default (1.02 in, 1.02 out, same as the old constant) — every
  existing call site was updated to pass the knob, none dropped or gained the multiplier.
  `test_wall_render.gd` (`test_overfill_margin_knob_actually_changes_the_scale`) proves the knob
  is actually read: two different margins on the same sizes produce two different, exactly-
  predicted scales — the "a knob nothing reads is the defect" trap this run's own HANDOFF names.
- **GAP-010 (amended, owner) — rebalancing is UNCONDITIONAL.** `WallPacker._rebalanced_angles()`
  dropped the "full unlock is the identity" branch entirely; every unlock set, complete or
  partial, re-sequences its non-home ring by ascending `slot` and spreads it evenly around the
  full circle, anchored at the smallest-slot survivor. Lost the `all_pictures` parameter (nothing
  reads it now — keeping an unused one would be a warnings-as-errors failure). `TestWallPacker`'s
  P4′ was rewritten a second time (`test_rebalancing_reduces_lopsidedness_full_and_partial`) to
  assert balance for BOTH a clustered full set and a clustered partial one — a genuinely clustered
  fixture in each case, not one already evenly spaced by arithmetic coincidence (the first draft
  of the full-set fixture picked every-3rd-of-12, which stays evenly spaced regardless of whether
  rebalancing fires at all — caught and replaced with 4 consecutive/clustered picks, same "fixture
  chosen so the code passes" trap this run's HANDOFF names). One other row needed a fixture fix:
  **P7** (`test_ellipse_aspect_follows_window_clamped`) read its resolved ellipse aspect off
  picture `&"b"`'s centre ratio, relying on `&"b"` staying at its literal authored 45° angle —
  true under the old identity rule, false now. Fixed by making `&"a"` `home_id`, leaving `&"b"`
  the ONLY ring entry: a ring of size 1 always resolves to its own authored `slot` regardless of
  rebalancing (anchor = that one entry's own slot, step = 360°/1 = a full turn, so `i=0` lands
  back on the anchor) — isolates rule 1 (ellipse aspect) from rule 3a (angle resolution) again,
  same fixture-isolation discipline P2′/P3′ already use. P2′, P3′, P5, P6, P10, P12, P13 needed no
  change: none of their assertions read a resolved angle's exact value, only radius/overlap/
  centredness, or (P2′/P3′) used fixtures already evenly spaced by construction.
- **`PictureEntry.slot`'s doc comment and `wall_packer.gd`'s own rule-3a comment were updated** to
  say "placement-order key," not "authored angle" — the field's actual meaning changed with the
  amendment; leaving the old wording would mislead the next reader into thinking a literal slot
  value survives into the wall.
- **GAP-013 (filed, open) — QR4=b's frame "colour" parameter has no fixed home.** `PLAN.md` §1.1's
  `PictureEntry` field list is exhaustive and has no colour field; adding one is a real decision,
  not an implementation detail, so it was filed rather than invented. S24 shipped everything else
  QR4=b/B6 asks for without it — see `gaps/GAP-013.md`.
- **S24 (QR4=b, GAP-013) — the one shared frame texture is CODE-GENERATED placeholder art, not a
  design tunable.** `WallPicture.shared_frame_texture()` (cached `static var`, generated once) is
  a simple depth-from-nearest-edge bevel, `_FRAME_TEXTURE_SIZE`/`_FRAME_CORNER_PX`/the two bevel
  colours all left as constants — same "diagnostic/placeholder art generation is not an
  author-tunable number" category `Tests/Visual`'s `_swatch_texture()` helpers already sit in
  (QR4=b's own text defers "the shader and art pass," so nothing here claims to be final art).
  `WallPicture.build()` sets `%Frame`'s 9-slice patch margins ONLY when `entry.frame_texture` is
  literally the SAME object as `shared_frame_texture()` (identity check, not "any texture is
  set") — applying that fixed corner size to some OTHER, smaller texture (every existing
  `Tests/Visual` diagnostic swatch is 8×8) would push the patch margins past that texture's own
  bounds, the exact degenerate-corner failure mode measured and fixed during this run's snapshot
  work. This keeps every existing diagnostic fixture rendering exactly as before — none of them
  reference the shared texture, so none of them gain patch margins they were never written for.
- **S25 (B10, Q7=b) — `wall_light_offset` replaces `WallPicture.SHADOW_OFFSET`.** Same GAP-011
  pattern: a typed literal §1.8 forbids, promoted to a `PlayerSettings` knob, default unchanged
  ((18, 26)) so behaviour does not move. `WallPicture.build()` reads
  `SettingsManager.settings.wall_light_offset` directly (the same pattern
  `update_wall_view_size()` already uses for `wall_view_min_texture_px` — `build()`/`focus()`/
  `unfocus()` are not pure functions the way `WallPacker`/`WallTransition.sample_at()` are, so
  reading the singleton directly is the established idiom here, not a parameter thread-through).
  Q41 (frameless picture still gets a shadow) needed no code: `%Shadow`'s texture is always the
  viewport's own `ViewportTexture`, set unconditionally regardless of whether `entry.frame_texture`
  is null, so a frameless picture was already shadowed by construction. Shadow OPACITY
  (`Color(0.0, 0.0, 0.0, 0.35)`, `wall_picture.gd`) is a pre-existing S10 literal, untouched here —
  outside what the coordinator asked this pass to fix (light POSITION, not shadow darkness); it is
  the same kind of number GAP-011 targeted and is flagged here rather than silently left, but not
  filed as its own gap without an explicit ask.
- **S28 (Q128/J2-design override) — `WallPicture.info_zoom_state()` reuses `wall_frame_reveal_
  margin` rather than adding a new knob for "how far past the bottom frame edge to clear."** Same
  conceptual role that knob already plays for the transition's own zoom-out stop ("extra share of
  the picture's size revealed beyond the frame") — a second, near-duplicate number for an
  equivalent concept would itself be the kind of thing §1.8 exists to prevent, not satisfy.
  PROVEN correct for every `frame_px`, not assumed: shifting the camera straight down by any
  `delta > 0` (zoom held at the unchanged at-rest fill value) can never reveal the top edge,
  because H3 already guarantees `frame.top < visible_top` at rest and a downward shift only grows
  that gap — see the function's own doc comment for the one-paragraph proof. `test_wall_info.gd`'s
  J5 asserts both halves (bottom revealed AND top not revealed), not just the one a shallower test
  might have stopped at.
- **S28 (Q137/J10-design override) — in Info mode, `WallTransition.sample_at()` holds zoom
  CONSTANT at the SOURCE picture's own info-zoom scale for the whole transition, never blended
  toward the destination's.** "The camera never leaves the info zoom" was read as ONE fixed value,
  not a smooth interpolation between two (which could not even be literally "constant" if the two
  pictures are different sizes, since each picture's own info-zoom scale depends on its own
  `rect.size`). `test_wall_info.gd`'s J6 fixture deliberately uses DIFFERENTLY SIZED source/dest
  rects specifically so a wrongly-reintroduced per-picture zoom would show up as non-constant
  samples, not be hidden by a symmetric fixture (the exact trap this run's HANDOFF names).
  J9 (toggling mid-transition retargets immediately) and J11 (focused screen stays live at the
  info zoom) are DESIGN chart J9/J11 -- NOT owed by any of TEST_PLAN §8's seven rows -- and were
  not built; flagged here rather than silently left undone.
- **S27 — `InfoCard._resize_to_content()` sets `.size` explicitly at every level down to the
  labels themselves, never relying on Godot's own deferred container-layout pass.** Measured
  directly: the first version set only `custom_minimum_size` on the `ScrollContainer`, which does
  NOT force an immediate resize on a `layout_mode=0` (manual position/size) Control — the labels'
  actual render width stayed at whatever tiny default they started with, and text wrapped to ONE
  CHARACTER PER LINE in the snapshot. A caller/test reading `card.size` (or looking at the
  rendered card) immediately after `show_entry()` — with no `await` in between, which is the
  whole point of J4's synchronous assertion — needs the real, final layout already in place.
- **S29 (Q133=b) — `get_info()` for a map node lives on `MapHoverPanel` (`get_info(node, run,
  lap_target) -> InfoEntry`), not on `WorldGraphNode` itself.** `WorldGraphNode` is vendored
  (`addons/worldgen/overlay/graph_map_node.gd`), and this repo does not edit vendored code, so the
  literal "the hovered node implements get_info()" reading is unavailable; `MapHoverPanel` — the
  thing that already knows how to read a `WorldGraphNode`'s role/biome/fame meta into text — is
  the closest defensible stand-in. `_describe_node()` factors the SAME title/body logic
  `show_for_node()` already used into a shared helper (a pure refactor, not a behaviour change),
  and `get_info()` is additive alongside it.
- **S29's migration is now COMPLETE** (superseding the earlier "incomplete" entry this replaces).
  `Levels/map.tscn`'s `%HoverPanel` (a live `MapHoverPanel` instance) is gone, replaced by
  `%InfoCard` (`res://UI/Wall/info_card.tscn`). `map.gd._on_node_hovered()` now calls
  `MapHoverPanel.get_info(node, run, controller.lap_target())` and hands the result to
  `info_card.show_entry()` — `hover_panel`/`%HoverPanel` no longer appear anywhere in `map.gd`.
  `get_info()`, `_describe_node()` and `_populate_preview_visual()` were made STATIC (none read
  any `self` state), so the map's live hover routing never needs to instantiate a whole
  `MapHoverPanel` scene just to reach `get_info()`.
  - **Booster preview reproduced, not narrowed.** `get_info()` on a booster node builds `entry.
    visual` as a FRESH `FlowContainer` (a real "copy of the hovered thing", §1.11/Q130, never a
    live reference into any panel's own `%Cards`) and populates it via the SAME `CardsViewer`
    listing `_populate_cards()` already used, aimed at the new container. Not `await`ed by
    `get_info()` itself (which must stay synchronous per §1.11's fixed signature) — safe in
    practice, not merely assumed: `_populate_cards()`'s own comment already establishes
    `get_possible_preview_cards()` never actually suspends today, so the un-awaited coroutine
    still runs to completion before `get_info()`'s own caller regains control. `TestWallInfo` J7
    asserts the visual is non-null AND populated (`get_child_count() > 0`), verified RED (visual
    dropped) then GREEN (visual restored) by hand.
  - **A real, accepted behaviour change, not a bug:** the info card no longer follows the cursor
    (`MapHoverPanel`'s `MOUSE_OFFSET`/`SCREEN_MARGIN` clamping) and no longer auto-hides on a
    grace period after leaving hover (`node_unhovered` is no longer connected to anything card-
    hiding at all). Both are `InfoCard`'s OWN contract (Q129=a: anchored to the window's bottom;
    J2/Q131: keeps the last entry until something else replaces it) — adopting them wholesale is
    what "becoming the info card" (Q134=c, "so there is only one system") means, not a narrowing.
  - **`TestMapTraversal` run standalone both before and after the rewire, not just as part of the
    full suite:** `ALL 35 CHECKS PASSED` in both — byte-for-byte the same suite total, no
    regression. `Tests/Engine/test_leak_canary.gd`'s own `MapHoverPanel` exercise (`show_for_node`/
    `hide_panel` on a standalone instance, unrelated to the map's live scene tree) is unaffected:
    the class and scene file were not deleted, only retired from `map.tscn`'s own tree.
  - **`MapHoverPanel`'s file/class deliberately still exists** — PLAN.md's "deletes its role as a
    separate system" was read as "the map no longer INSTANTIATES it as its live hover display",
    not "the file must be deleted"; `get_info()`'s natural home is still the class that already
    knows how to read a `WorldGraphNode`'s meta (see the earlier entry on why it is not on
    `WorldGraphNode` itself).
- ⚠ **S30 is SCOPED, not complete, and this is a deliberate stopping point, not an oversight.**
  What shipped, real and tested:
  - `WallPicture.build()` gained an optional `live_screen: Node = null` parameter (default
    preserves every existing call site unchanged) that REPARENTS an already-instantiated,
    persistent node as `screen_root` instead of instantiating fresh from `entry.scene` (B7,
    Q211=a "reparented unchanged"; Q141=a "the screen stays in the tree, paused"). Proven by
    identity, not just presence: `test_wall_render.gd`'s new row confirms the exact object comes
    back out, its own pre-existing child survives untouched, and it ends up a real child of the
    picture's own `SubViewport`.
  - `Wall.initial_layout()` — a static factory for the wall's starting content: `start_menu`
    (home), `map`, `deck`, all `unlocked_by_default`, all using the shared frame style (S24).
  - `Wall.cold_launch_focus_stack()` — K6's own contract as a real, callable function: a FRESH
    `FocusStack` pre-visited with `start_menu`, proven independent across calls (mutating one
    instance never reaches another) and proven that no `PlayerProfile`/`PlayerSettings` field
    even names a current-picture/focus concept (`TestWallFocus` F13, both halves, red/green
    verified by hand on the independence assertion).
  - **What did NOT ship: `Levels/main.gd` is UNCHANGED.** `Main` still drives navigation through
    its own `switch_scene()`/menu-map-game swap; nothing calls `Wall.initial_layout()` or
    `Wall.cold_launch_focus_stack()` from production code yet. The cold-launch camera choreography
    (M1: camera starts already zoomed into start-menu, no wall-view flash; M2: choosing a save
    triggers a ONE-OFF, LONGER/SLOWER zoom-out reveal to wall view, distinct from an ordinary Wall
    button press; M3: that reveal happens on every launch) is not built.
  - **Why stopped here, specifically:** `main.gd` is referenced by at least seven test suites
    (`test_e2e_run`, `test_game_headless`, `test_leak_canary`, `test_interaction`, `test_ui_props`,
    `test_visual_layers`, `reveal_shot`) — by far the highest-blast-radius file in the codebase,
    and the coordinator's own framing named Phase 7 "the highest-regression work in the plan."
    Genuinely underspecified decisions remain, not just missing time: the exact reveal duration/
    knob for M2's "longer, slower" zoom-out (no `PlayerSettings` field names one — a candidate
    GAP under §1.8, not yet filed), and whether the reveal lands settled on WALL VIEW itself or
    auto-focuses the destination picture afterward (both readings are consistent with M2/M3's own
    text). Rather than guess at either and rewire the app's entry point on that guess, this was
    left for an explicit ruling. **Still owed:** file the reveal-duration gap, get a ruling on the
    landing behaviour, then replace `Main`'s `switch_scene()` calls for menu/map/deck with
    `WallPicture.focus()`/the wall's own camera, seeded by `initial_layout()` and
    `cold_launch_focus_stack()` — both of which are now ready for that call site to use.
- **S31 — the freeze mechanism is built and PROVEN, on the same scoped pattern as S30.**
  - `WallPicture.attach_screen(live_screen)` / `detach_screen()` — swaps a picture's `screen_root`
    for a NEW live node (freeing whatever was there), unlike `build()`'s own `live_screen`
    parameter (set ONCE, for a session-long persistent screen). This is for `game`: L2 requires
    `GameView` "still built fresh per show and freed after" while the WallPicture itself (frame,
    position) stays put on the wall — the picture persists, only its screen content is rebuilt.
  - **The freeze itself needed NO new mechanism at all** — `focus()`/`unfocus()` already flip
    `screen_root.process_mode` between `ALWAYS`/`PAUSABLE` (S12), and a `PAUSABLE` node under a
    globally paused tree simply stops (`_process` never runs, `Pacing.wait` never fires) —
    exactly L4/L5's "freezes where it stands... bit-identical" requirement, already proven true
    by construction back in S1/S6/S9-S12. S31's job was proving that guarantee holds for a REAL,
    running `Game`, not a fixture standing in for one.
  - **Proof: `Tests/Visual/wall_game_freeze_soak.gd`** (standalone — needs a REAL
    `get_tree().paused = true`, fatal to share with 38 other suites, same reasoning as the earlier
    fuzz soak). Builds ONE real `GameView` (the SAME fixture recipe `test_leak_canary.gd`'s own "a
    real show WITH a GameView" section already uses: `TestDecks.seeded_deck()`/`standard_rules()`,
    `RunManager.new_run()`, `pending_goal`/`pending_node_id`, then `g.next()` into mid-act),
    attaches it to a real `WallPicture`, then cycles `unfocus()`→wait 1-6 random frames→assert
    `GameData.revision` unchanged→`focus()`, 50 times, seed 20260817 (`FREEZE_SEED` env override),
    `ALL 153 CHECKS PASSED`. Each cycle asserts the `process_mode` transition DIRECTLY (not just
    the revision, which alone could be weakly vacuous if nothing was ever going to mutate revision
    in a few idle frames regardless) — verified RED (temporarily forced `process_mode` back to
    `ALWAYS` right after `unfocus()`) then GREEN by hand.
  - **The five suites TEST_PLAN §9 names as threatened were run STANDALONE, before AND after,**
    not just folded into the full-suite number: `TestGameHeadless` 73→73, `TestActScore` 16→16,
    `TestCombo` 31→31, `TestVisualLayers` 192→192, `TestLeakCanary` 17→17 — every one identical,
    zero regression. Expected: this batch touched no file under `UI/Fx/`, `Levels/game.gd`,
    `Levels/game_view.gd`, `Levels/game_view.tscn`, or `Levels/main.gd` — only additive methods on
    `WallPicture` and one new standalone diagnostic. `TestLeakCanary`'s own "leak" assumptions
    (screens freed normally) are UNDISTURBED because nothing yet makes the wall's freeze-instead-
    of-free behaviour live in the real game (see below) — Q203=a's actual leak-semantics change
    is still owed, not yet exercised.
  - **What did NOT ship, same reasoning as S30: `Levels/main.gd` is unchanged.** `Main.enter_game()`
    still builds a fresh `GameView` and frees it on `game_ended()`/`_on_run_lost()` — leaving
    mid-act still ends the show today, it does not freeze it. Wiring "Back/Wall while inside the
    game picture calls `unfocus()` instead of freeing" is real, remaining work, gated on the SAME
    main.gd blast-radius concern as S30 plus one more genuinely unfixed piece: **L3** ("when there
    is no GameView, the picture shows an authored default background image") names an ASSET no
    `PictureEntry`/`WallLayout`/`PlayerSettings` field holds — the same shape as GAP-013's frame
    colour, not yet filed as its own gap pending the coordinator's steer on whether it blocks the
    main.gd wire-up or can ship picture-blank (Q214=a's existing "registered but unbuilt" look)
    until real art exists.
- **S30/S31 WIRE-UP (coordinator's own third call, after twice deferring) — `Levels/main.gd` is
  now the wall.** `switch_scene()`/`current_scene` are gone; `Main` owns one real `Wall`, packs
  `Wall.initial_layout()` (now 4 pictures: `start_menu`, `map`, `deck`, `game` -- `game` added
  this pass), reparents `menu_scene`/`map_scene` as `live_screen`, and drives every navigation
  through picture focus.
  - **Two things Q88=a/Q99=a require were genuinely MISSING, not merely unwired, and had to be
    built to make wall view a place a player can leave.** Design chart I3/I4: "click enters
    immediately" and "`ui_accept` enters the selected picture" -- neither existed anywhere in
    S19-S23's own input work (confirmed: no TEST_PLAN §6 row covers either). Added `Wall.
    picture_enter_requested(id)` (a NEW signal, not in NAMES.md's own table -- named to match
    `wall_view_entered`'s existing "the wall announces intent, the caller decides what it means"
    shape) plus a `_picture_at(wall_pos)` hit-test (frame-outer rect, not the bare picture rect)
    inside `Wall._unhandled_input()`'s existing wall-view branch.
  - **Camera orchestration: `WallTransition` for picture-to-picture, a plain parallel `Tween` for
    the two moves it cannot express.** `WallTransition.request()` only ever runs BETWEEN two real
    pictures (it already latches pause/unpause correctly mid-flight, S14-S18/S28) -- there is no
    "wall view" endpoint. `Main._animate_camera()` is the wall-view <-> picture half (M2's own
    reveal, and the ordinary "Back to wall view" case), sharing `WallTransition.total_duration()`
    for its own duration so both feel like the same clock, but built by hand since it is a
    genuinely different shape of move, not a `WallTransition` variant.
  - **`FocusStack` is finally live-wired**, not just tested in isolation: the overlay's Back
    button retraces one step (`_focus_stack.back()`, refocusing the returned id) before falling
    through to wall view once the stack itself reports nothing behind the current picture --
    keyboard `ui_cancel` keeps its existing, simpler "always straight to wall view" behaviour
    (`Wall`'s own `_unhandled_input`, unchanged), so the two Back affordances are NOT identical on
    purpose (matching `wall_view_entered`'s own doc comment, which already named both cases as
    landing on the same signal).
  - **L4 is live**: `enter_game()` checks whether the `game` picture ALREADY holds a screen_root
    before building anything -- a previous mid-act Back left it there, frozen, PROCESS_MODE
    PAUSABLE; finding one RESUMES (focus only, no rebuild) rather than discarding it. Only a
    genuinely finished show (`game_ended()`/`_on_run_lost()`) calls `detach_screen()`.
  - **`deck` ships with no live screen, on purpose, matching L3's own "cosmetic, not structural"
    ruling for `game`.** `DeckViewer` is a SELF-CLOSING modal (`_close()` frees itself on Escape),
    a real structural mismatch with a PERSISTENT wall picture -- adapting it would be editing an
    existing screen's behaviour, which anti-scope item 1 forbids outright. The picture exists on
    the wall (so the wall genuinely has 4 pictures, M4's "more than one" holds), renders blank;
    the map's own existing Deck button still opens the same modal `DeckViewer` exactly as before,
    completely unaffected. Not filed as a gap: no coordinator ruling asked for one, and the
    existing access path already works.
  - **M2's own reveal uses the ORDINARY transition clock, as instructed** -- GAP-014's distinct
    longer/slower one-off choreography is NOT built. This is a plain, recorded shortfall, not a
    silent substitution.
  - **Verified, not just written:** cold launch screenshotted (`Tests/Visual/
    main_boot_snapshot.gd`, a new by-eye diagnostic reusing `Levels/main.tscn` unmodified) --
    shows the real Menu screen (title, Play, the bottom button row) focused immediately, Back/
    Forward correctly disabled, Wall button correctly visible (4 pictures). Full suite green (`ALL
    39 SUITES`). The five suites TEST_PLAN §9 names, standalone, before this pass -> after:
    `TestGameHeadless` 73->73, `TestActScore` 16->16, `TestCombo` 31->31, `TestVisualLayers`
    192->192, `TestLeakCanary` 17->17 -- all unchanged.
  - ⚠ **`TestLeakCanary` staying at 17 is NOT evidence Q203=a's leak semantics are exercised --
    it is evidence they are NOT, and that is the honest reading, not a quieter way of claiming
    success.** Confirmed by grep: `test_leak_canary.gd` builds its own `GameView`/map-controller
    fixtures directly and never once calls into `Main` (`grep -rn "Main\." Tests` outside
    `Main.save_info` returns nothing, for any test in this repo). The suite was ALWAYS testing the
    underlying classes' own leak behaviour in isolation from whichever orchestrator drives them,
    so wiring `Main` could not have changed what it measures. The freeze mechanism is proven twice
    over regardless -- S31's own soak (isolated fixture) and this pass's real boot+full-suite
    green (live fixture) -- but "screens now stay alive for the session" specifically has no
    AUTOMATED test watching it yet. Flagged plainly rather than left implied.
  - **Interactive navigation beyond cold launch (Play -> new run -> wall reveal -> entering map ->
    entering a show -> Back mid-act -> resume) is verified by CODE REVIEW and the full green
    suite, not by a screenshot of every step** -- time did not extend to a full by-eye walk of
    the whole flow this pass. The boot itself and the freeze mechanism (S31's soak, using this
    exact `attach_screen()`/`focus()`/`unfocus()` API) are the two highest-risk pieces and both
    are independently verified; the orchestration code connecting them uses only already-tested
    building blocks (`WallTransition`, `FocusStack`, `WallPicture`).

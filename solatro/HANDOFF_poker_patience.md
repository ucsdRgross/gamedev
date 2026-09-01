# HANDOFF — poker patience

**Goal:** turn Solatro's two-zone tableau into the poker-patience grid game — the engine, then the
board the player sees. Done when a player can deal, place, score, undo and End a show on a grid
they can look at.

**State:** **Phases 1-5 are complete, and so is Phase 8.** The engine scores grids, the legacy zones
are gone, the Entrance is pinned to the bottom of the window with its slots under their columns, the
board stacks UPWARD off a fixed floor, rows ease into their height, a jump carries the stack above
it, and every row, column and stack shows its own score. Phase 10's CSV half (`S42`, `S43`) landed
out of order at the owner's instruction.

**PHASE 6 IS COMPLETE** (`S26`-`S30`, all committed and overseer-verified): two view modes, a
Back/Forward zoom level stack, discrete centred panning, cross-grid arrow selection, touch swipe, and
refocus on removal. Its by-eye gate at 1, 2 and 3 grids was rendered and looked at, and an
adversarial pass at the boundary found four defects that a green suite could not — including a
**touch swipe that no finger could reach while both its tests passed.**

**PHASE 7 IS IN PROGRESS.** Landed and committed: `S31` (the wide picture, height rule, render
clamp), `S31b` (the focused zoom — `GAP-017` part 3), `S31c` (clipping, so "other grids out of view"
is true of the PIXELS), `S31d` (the picture widened to three grid positions, giving the camera a
real step). Phase 9 is the owner's call; Phase 10's remaining three steps are last.

⚠⚠ **START HERE: `S31e` IS COMMITTED, UNVERIFIED, AND HAS A REAL PRODUCT DEFECT.** It is commit
`6ed95277`, committed deliberately to carry the work across a session boundary — **not because it
works.** There is no red-then-green and no by-eye pass. Its brief is `GAP-021`'s answer — one grid
per grid position, furniture NOT duplicated (`Q39` has the Entrance follow the camera, `Q40`=(a) has
it stay with its committed grid).

⚠ **THE COMMIT MESSAGE UNDERCOUNTS THE DAMAGE. Measured by controlled comparison — same box, same
poisoned settings, only the code varying:**

```
58b223aa (pre-S31e): 3802 passed, 2 FAILED   GRID VIEW 178/178, INTERACTION 52/52, GRID LAYOUT 69/71
6ed95277 (S31e):     3790 passed, 5 FAILED   GRID VIEW 176/178, INTERACTION 51/52, GRID LAYOUT 69/71
```
GRID VIEW totals 178 in BOTH runs, so nothing aborted and the comparison is sound.

**`S31e` introduced THREE failures, not two:**
1. `GRID VIEW: precondition: in the OVERVIEW a neighbouring grid is in frame beside the middle one
   (TP-140) -- grid 0 false grid 2 false`
2. `GRID VIEW: ...and that grid is in frame -- [0]`
3. ⚠⚠ `INTERACTION: a mouse click over a card emits its selection -- 0` — **UNDOCUMENTED IN THE
   COMMIT MESSAGE, and it is the player's primary verb.**

⚠ **(3) IS A TEST-FIXTURE RACE, NOT A PRODUCT DEFECT — MEASURED, and the first reading was wrong.**
The click LANDS (the viewport's focus owner after it is the correct control), which rules out rects,
routing, `mouse_filter` and `S31c`'s clipping. The gate that fails is in `_on_gui_input`
(`UI/play_area.gd:973-980`): `focused_control == moused_hovered_control`, and
`moused_hovered_control` (`UI/play_area.gd:35`) is cleared by a native `mouse_exited` between the
hover event and the button-down.
**Why: `test_interaction.gd` waits 2 FRAMES after `focus_grid(0)`, and the Entrance track eases for
~11.** Measured series, no input, `entrance_h_track.position.x`:
```
3 grids: -94.93  26.22  31.08  34.92  36.52  37.72  38.29  38.65  38.78  38.81  38.8112 (flat)
1 grid:  173.59 354.75 357.88 360.63 362.10 363.13 363.83 364.27 364.54 364.72 364.8052 (flat)
```
**It SETTLES** — asymptotic, bit-stable by frame ~11-13, and it reproduces at 1 grid exactly as at 3,
so this is NOT the `_physics_process` never-settles trap and NOT specific to the multi-position
spread. Causal proof: the same fixture clicking after 2 frames gets `selections: 0`; waiting 15
frames for the ease to converge gets `selections: 1`. **The Entrance moving on a view change is
`Q39` working as designed** (*"follows the camera, think of it like a player hand"*).
⚠ **The fix is `_settle_layout`, never a frame count and never a widened tolerance** — the standing
rule below already says so. ⚠ **STILL OPEN: why the pre-`S31e` code won this race.** Nobody has
diffed the ease DURATION or confirmed the old `_sync_entrance_x` converged faster. Until that is
answered, "stale fixture" is the leading reading, not a proven one.
⚠ **Worth an owner glance, not blocking:** for ~11 frames after a view change a click on an Entrance
card silently does nothing, because the card is sliding out from under the cursor. Defensible (the
card is visibly moving) but it is a real player-facing wart.

⚠ **THE SECOND GRID VIEW FAILURE WAS MISFILED.** It is **`TP-109`'s swipe test**, not a `TP-140`
companion — the commit message and the earlier handoff text both got this wrong. `TP-109` and the
INTERACTION failure are now **FIXED and green**. What remains red is `TP-140`'s own two OUT-OF-VIEW
assertions, and they are **blocked on `GAP-022`, not on calibration:**

⚠⚠ **`S31e` SILENTLY STRETCHED `PlayContainer` TO THE WHOLE PICTURE — SEE `GAP-022`.**
`Levels/game_view.tscn` went from `anchors_preset = 0, offset_left = 423, offset_right = 1142` to
`anchors_preset = -1, anchor_right = 1.0`. Measured board window: **x (0.0 .. 3640.476)** of a 3656
px picture. **No grid can leave a window that wide**, so `TP-140`'s assertions and `H22` are
STRUCTURALLY UNSATISFIABLE, and `S31c`'s clip has nothing left to clip against. This is `GAP-021`
option (a) implemented without a ruling, against `GAP-021`'s own instruction to *"report it rather
than assuming"*. **The two assertions are left RED, unweakened and undeleted** — a check that cannot
express its intent must not be softened into passing.
⚠ **OWNER HAS PULLED `H20` (`S33`) AHEAD OF `S32`**, which bears directly on `GAP-022`: until the
wall re-packs, what a "window" of the picture IS remains undefined, so (a) vs (b) cannot be answered
against stable geometry.

✅ **THE WALL SQUASH IS FIXED (`H20`, first half of `S33`).** `Wall._size_game_picture()` now also
pins `keep_aspect = true` on the game entry, so `WallPacker._picture_size()` takes its early return
instead of the window-aspect stretch that discarded `design_size.x`. Sprite scale
**(0.333, 1.0) -> (1.0, 1.0)**; packed rect **(1217.778, 685) -> (3656, 685)**.
**BY EYE: cards are correctly proportioned and their ranks and suits are readable.**
⚠ **`Q180`=(a) was the authority and the old behaviour was the REJECTED (b)** — the footprint had
been capped to window aspect with the board squashed inside it, which is (b) plus `Q181`=(a), and
`Q181` only exists under (b).
⚠ **The packer risk was measured at the case that FORCES contention**, not the easy one: with all
six pictures unlocked, `settings` moved `(1224.0, -350.808) -> (2237.354, -641.244)` — the wall
genuinely re-arranged. Count stayed 6, no overlap, no drop, at three window aspects. `size_multiplier`
untouched at 1.0.
⚠ **The camera now frames ~1194 of 3656 wall units — about ONE GRID POSITION.** `H22`'s premise is
true in the pixels for the first time.

⚠⚠ **AND THE HUD IS NOW OFF SCREEN AT REST — ANSWERED: THE WHOLE HUD FOLLOWS THE CAMERA.** See
`GAP-022`'s follow-on ruling. Reuse `_sync_entrance_x`'s mechanism; do not invent a second writer.

⚠ **WHY IT PASSED TWO BY-EYE GATES: EVERY SHOT WAS BLIND TO IT.** `grid_zoom_shot` and
`grid_layer_shot` both instantiate `GameView` DIRECTLY and never touch the `WallPicture` sprite path.
**`Tests/Visual/wall_game_squash_probe.{gd,tscn}` is the only instrument that renders the product's
REAL framing.** ⚠ It now builds its `PictureEntry` from `Wall.load_layout()` rather than a
hand-duplicated copy — **it had silently gone stale against the fix.** A by-eye instrument that
duplicates production setup drifts from it and then certifies the wrong thing. Still not registered
in `all_tests.tscn`; the suite stays at 45. Delete the throwaway
`Tests/Visual/interaction_click_probe.{gd,tscn}`, whose findings are recorded above.

⚠⚠ **THERE IS NO GREEN COMMIT ON THIS BRANCH. `58b223aa` IS NOT GREEN EITHER** — it reproduces 2
GRID LAYOUT failures across two runs, so they are reproducible, not flake, and they are **NOT the
documented flaky family** (neither is the Entrance-stacks push-up nor the lowest-card-clears-Entrance
assertion):
```
GRID LAYOUT: ...the arithmetic lands on the same point the card's own CONTROL does, at every
             height -- worst 116.0 px out
GRID LAYOUT: TP-85: caught mid-growth, the row is PART WAY to its new height -- row 78.0,
             was 58.0, will be 78.0
```
⚠ **LIVE CANDIDATE CAUSE — `user://settings.tres` IS POISONED AND STAYS POISONED.** After a run that
exited 0 it holds test values (`base_delay = 0.1`, `wall_transition_delay = 0.001`) and its **mtime
is MID-run, not at the run's end** — so the suite writes test settings at start and the restore does
not run on the normal exit route. This is not a one-off from some killed run; every run leaves it.
A geometry-affecting setting moves every row on the board, which is why this is a candidate for the
116 px failure. **NOT YET INVESTIGATED. Do not overwrite `settings.tres` by guessing — those may be
the owner's real values.** Recover a pristine default from the repo, or ask.

**Entry docs:** `START_HERE.md`; `design/poker-patience/{PLAN.md,DESIGN.md,TEST_PLAN.md,NAMES.md}`;
`design/grid-view/DESIGN.md`; `design/card-effect-api/DESIGN.md`; `HEADLESS_TESTING.md`.
⚠ Flowchart **H — the one Phase 6 implements — is §36 of `design/poker-patience/DESIGN.md`**, not of
the grid-view design, whose charts are J/K/L/M/N/P.

## Design provenance and gap protocol — COPY THIS BLOCK INTO ANYTHING DERIVED FROM THIS DOCUMENT

Derived from `design/poker-patience/DESIGN.md` version 2 and `design/grid-view/DESIGN.md` version 2.

If you are executing this and you reach a decision the design does not cover:
1. Reversible and clearly within intent -> do it, and append one line to `ASSUMPTIONS.md` citing the
   node you were working on. Never silently.
2. Otherwise -> **park that thread, file a gap, keep working on unaffected threads, tell the owner.**
3. The design contradicts itself or the code -> always a gap, highest priority.
4. ⚠ Two documents disagreeing is NOT automatically (3) — read the answer they are both restating.

File gaps at `design/<slug>/gaps/GAP-NNN.md`, options in the questionnaire grammar. Do not resolve
a gap by picking an answer. Do not delete a gap — it is closed by a new design version.

## Environment — traps that have each cost real time

- Godot here is **4.7.2**; `.claude/memory/machine-profiles.md` records it per box. ⚠ That table
  still lists **4.7.1** for Box A, which is STALE — Box A now has
  `Godot_v4.7.2-stable_win64_console.exe` and the suite runs on it. ⚠ **A cache built
  by a different Godot build CRASHES the suite** with `0xC0000005` and no banner. Fix:
  `<godot> --headless --path solatro --import`, then re-run. Do that once on a machine you have not
  run the suite on before.
- Suite: `GODOT_BIN=<4.7.2 console exe> py solatro/Tools/run_tests.py --timeout 400` from the repo
  root. Runs WINDOWED, ~4 min, self-quits. **Close the owner's editor first.**
- ⚠ **PARSE-CHECK A TEST FILE BEFORE SPENDING THE FULL RUN ON IT**:
  `<godot> --headless --path . --check-only --script <file> 2>&1 | grep <file>`. Real `Parse Error`
  lines name their line number; the trailing `Compilation failed` at the first autoload reference is
  noise this mode always produces. ⚠ **GDScript treats "Variant provided where a subtype is
  required" as a PARSE ERROR** — `dict.get(...)` and `Array.min()` both return Variant, so assign
  them to a typed local first. A suite that fails to parse HANGS every suite waiting on it, and the
  run dies on the 400 s timeout with no banner.
- ⚠ **A new `class_name` referenced from an existing script HANGS the suite** rather than failing to
  parse. Fix: `--headless --path . --import`. Always pass `--timeout` so a hang fails fast.
- ⚠ `export PYTHONIOENCODING=utf-8` before any python heredoc, or the console encoding kills the
  script MID-EDIT and leaves a source file half-written.
- ⚠ **Judge by the failure SET and the SUITE COUNT, never the check total** — the total varies run to
  run, and a suite that fails to compile silently drops out (measured: 43 -> 41, twice). Read the log
  for `SCRIPT ERROR` even when the banner says all passed.
- ⚠⚠ **A KILLED SUITE POISONS `user://` AND LATER RUNS THEN HANG WITH NO BANNER.** Suites park the
  real save and the real SETTINGS and restore them at the end; a run killed by `--timeout` never
  reaches the restore, so TEST values become the live `user://settings.tres`. The save backup is
  self-healing (`backup_real_save` restores first); the SETTINGS are not. **Before blaming your own
  diff for a no-banner run, check `user://settings.tres` for test values and `user://run_save/` for
  a leftover `*.testbak`.**
- ⚠ **NEVER RUN TWO SUITES AT ONCE.** Two Godot processes write the same log, and the console banner
  and the log banner then DISAGREE (measured: console "3465 CHECKS PASSED" against the log's
  "3 FAILED"). Check no `Godot_v4.7.2-stable_win64_console` process is alive before starting, and
  make console and log agree before believing either.
- ⚠ **THE TEST LOG IS `<user data>/Solatro/logs/test/test_output_all.log`.** A file of the SAME NAME
  sits directly under `Solatro/` and is months stale — it greps clean while the banner reports
  failures. Check the mtime.
- ⚠ **`doc_check.py --changed` is STRICTER than the full run on design-id citations.** Touch an old
  file and it reports the standing backlog as errors in that file. The full run is the gate: 0
  errors, 7 warnings. Judge a regression by the full run plus a diff check for ADDED ids.
- By-eye rendering: `<godot> --path solatro res://Tests/Visual/reveal_shot.tscn` and
  `res://Tests/Visual/grid_layer_shot.tscn`, which write `user://reveal_shots/*.png`. They stand up a
  REAL `GameView`; they are the only things that show the board. ⚠ **`grid_layer_shot` now shoots
  the board at 1, 2 AND 3 grids** (`grid_board_1/2/3.png`) and prints each grid's panel centre, the
  window centre and per-grid off-screen px — a picture plus the numbers behind it. It is NOT
  registered in `all_tests.tscn`; the suite stays at 45.
  ⚠⚠ **SINCE `S31`, `grid_layer_shot` NO LONGER SHOWS THE PRODUCT'S FRAMING FOR MULTI-GRID BOARDS.**
  It renders the board in a **1152x648** window, but `S31` sized the game picture to fit three grids
  (far wider). So its n=3 shot reports grids 0 and 2 cut off by ~185/~193 px — **that is HARNESS
  framing, not the product.** n=1 and n=2 still read true (they fit either way). **Whoever next
  needs a by-eye pass on a 3-grid board must render inside the real picture**, or the image is
  answering a question nobody asked.

## Standing rules this stream paid for — do not rediscover them

**Scoring and the engine**
- The runaway guard (`act_event_cap`, `MAX_TICKS`) is CORRECTNESS-critical: there is no line-scored
  memory and no within-pass guard, so a remove-and-replace effect re-scores forever without it.
- `save_state()` is called LAST in `place_card_in_grid` — the scores live on `state`, so an earlier
  snapshot rewinds the board without rewinding what it scored.
- **`upper_zone` IS the Entrance**, and `BoardCoord` always named it `ENTRANCE_ROW`. The LOWER zone
  stays deliberately unmapped; a path that needs it is a real gap.
- Prop routes REUSE `LineGeometry.row_cells`, which structurally cannot leave its grid.

**The board's geometry**
- ⚠ **THE UNIT OF A GRID "ROW" IS THE HEIGHT LAYER `h`, NOT THE CELL ROW `y`.**
  `_append_grids_row_major` orders grid cards `for h: for every cell`, so a height layer is
  contiguous in `card_layer` and a row `y` is not — and only the contiguous unit is bracketable.
- **ONE CONTAINER PER ROW** (owner ruling), not a `GridContainer`, which gives every cell the row's
  full height so a cell has nothing to bottom-align against. **The cell's own frame is the LAST child
  of the slot** — it marks the CELL and does not rise with the stack.
- **The floor comes from `TopLevelVBox` via `ALIGNMENT_END`**, not `size_flags_vertical`. Caching it
  is safe because it does not move when a stack deepens; a per-PANEL rect cache lagged a whole depth
  pitch and slid every row on the board. ⚠ Do not refresh a rect cache from `_physics_process` if the
  floor code writes to that rect — the board never settles.
- **The panel and the cell block are NOT the same rect.** Everything that walks rows goes through
  `_cells_root`, and `_grid_slot_center_global` measures from the CELL block; reading the panel put
  every card a gutter off its cell. The Entrance x-slaves to the COLUMNS for the same reason.
- **Cross-grid alignment lives in `_measure_grid_row_height` and nowhere else** — that is what keeps
  it purely visual, since scoring never reads a row height.
- **A setting that changes geometry must be part of the row-height memo's key**; it moves every row
  on the board without touching `state.revision`.
- **An eased row height cannot use the revision memo** — while easing it is a function of time, and
  the memo froze the animation on its first frame.
- **Growth is tracked separately from the reveal** (`_layer_grown`): a reveal opens and then CLOSES,
  and `set_reveal_cards` replaces its wanted-set every section, so growth living there would shrink
  a row under a card still on it.
- **The Entrance's visible strip and its own height are two different numbers.** Only the FLOOR
  clears the real height; the strip stays the player's setting.
- **Board knowledge lives in `PlayArea.jump_card_with_its_stack`, never in `CardVisual`.** The lift
  rides `offset`, inside the card root and invisible to the containers — the one place the "rows
  never overlap" rule is deliberately broken.
- **The height label is positioned by arithmetic in `card_layer`, not parented into the cell**, or it
  would add its own height to `_measure_grid_row_height`, the arithmetic every card and prop is
  placed by.
- **One label per (line, height)** (`GAP-015`), bottom-aligned with `h` rising.
- ⚠ **ONE RENDERER AT A TIME** if this area is ever reworked — the pinned Entrance only landed on the
  third attempt, after the coordinate migrated and the zones stopped rendering. And ⚠ **two
  independent draw orderings sharing one index space re-queue every frame until the stack
  overflows.**

**The view, the camera and the wall**
- ⚠⚠ **AN INTEGER INDEX BEATS A MEASURED POSITION.** The furniture's pan shift is
  `pan_grid * grid_position_size_px().x` — nothing to settle, nothing to latch, nothing to go stale.
  Two earlier fixes were both managing the consequences of choosing a MEASURED quantity as the
  reference, and both were deleted when the arithmetic replaced them.
- ⚠ **A FRESHLY-ADDED PANEL'S `Cells` NODE EXISTS BEFORE ITS `global_position` IS VALID** — the
  deferred sort has not run, so a null-check is NOT enough to know a measured position is settled,
  and the stale value can equal the very value you are trying to avoid.
- ⚠ **THE ARROW READER MUST SIT ON THE CELL'S OWN `gui_input`.** The viewport's focus-neighbour
  search runs in the GUI pass and CONSUMES any arrow that finds a neighbour, so an
  `_unhandled_input` reader never runs while a cell has focus. Arrows are MODE-DEPENDENT
  (`Q162`=b): cells when FOCUSED, whole grids in the OVERVIEW.
- **The zoom level stack is focused -> overview -> wall.** Back zooms out one level and, once in the
  overview, FALLS THROUGH so `wall_back` still reaches the wall. That fall-through is the case the
  owner's example does not cover.
- **A board narrower than the window parks LEFT** -- a `ScrollContainer` hands its content the
  content's own minimum width. Fixed by `SIZE_EXPAND_FILL` on `TopLevelVBox`, **HORIZONTAL ONLY**;
  the floor is `ALIGNMENT_END` and must stay untouched.
- ⚠ **THE SCALE MUST LIVE ON THE SCROLL CONTAINER, NOT ITS CONTENT** -- a `Container` rewrites its
  children's scale on every sort. Its rect is divided by the same factor so the window keeps its
  pixels. **The scale is NOT animated**: the scroller clamps every aim against the reach it can see
  at that instant, so an eased scale destroys the aim issued with it.
- ⚠ **`SubViewport.size` LIES WHEN OVERSIZED** -- past the GPU cap the framebuffer is destroyed and
  the size set to 0 internally while the GDScript property still reports what it was given. Assert
  the pure `clamped_render_size()` and that the writer engaged `size_2d_override`, never a read-back.
- ⚠ **`focused_scale()` RESTS THE CAMERA BY OVERFILLING**, so a picture whose aspect IS the window's
  is framed WHOLE at rest at any size. **A wider picture alone gives the camera no step** -- the
  aspect minimum applies to ONE GRID POSITION, and the picture is `grid_max_count` positions wide.
- ⚠ **A BY-EYE INSTRUMENT THAT DUPLICATES PRODUCTION SETUP DRIFTS FROM IT** and then certifies the
  wrong thing. `wall_game_squash_probe` builds its `PictureEntry` from `Wall.load_layout()` for
  exactly this reason. `grid_zoom_shot`/`grid_layer_shot` instantiate `GameView` DIRECTLY and are
  structurally blind to the whole wall composite -- that blindness is why the squash passed two gates.

**Tests**
- **A test must wait for the geometry to STOP MOVING** (`_settle_layout`), not for a frame count: a
  container sorts its children a frame after the rebuild that changed them.
- **A test waiting for a jump to settle waits for `absf(y)` to fall, not for the sign to flip** — the
  descent is `TRANS_BACK` and overshoots.
- **A test helper must not be named `run_*`** — that is the registration gate's entry-point
  convention and it will demand the helper be called from `_ready`.
- **A touch test must run AFTER the mouse tests**: a touch leaves no HOVER and the mouse selection
  path needs one.
- **`SettingsManager.isolated` is set run-wide by `all_tests`, not per suite.** `use_own_settings()`
  (a fresh `PlayerSettings`) is opt-in and must be called before a suite builds anything — swapping
  the resource mid-suite orphans every reference already taken.
- **The sentinel gate's needles are built by concatenation**, or it flags its own constant.

## Tasks

⚠ **The stale-step tooling only recognises `S<digits>`.** `designloop/src/gaps.mjs::planSteps()` does
NOT see the lettered ids (`S19b`, `S20b4b`, `S31b`...), so a gap whose blast radius names a lettered
step will not appear in its stale list. Check lettered steps by hand.

⚠ **LANDED STEPS CARRY NO FORENSICS HERE.** The evidence is in the commit messages, the decisions in
the gap files, and the durable rules in "Standing rules" above. This ledger records only what is
true now.

```yaml
- id: S1
  description: 'BoardCoord; GridData and grid storage; the position index; the cell mutation API.'
  status: done
- id: S5
  description: 'CardDataIterator over grids; line enumeration (ROW, COL, DIAG, HEIGHT_V); the section.'
  status: done
- id: S9
  description: 'The detector card, the scoring wiring, height scoring, the buckets, grid_score.'
  status: done
- id: S14
  description: 'The combo model; the allotment and creator meta cards; TypeInput refill; commit.'
  status: done
- id: S19
  description: 'THE REBUILD: rules1 becomes the grid game; six suites follow it.'
  status: done
- id: S19b
  description: 'The legacy coordinate migration -- SUPERSEDED, folded into S20b by GAP-009.'
  status: superseded
- id: S20
  description: 'THE VIEW REPLACEMENT: GridPanel/CellSlot, zone renderers deleted, the pinned Entrance.'
  status: done
  notes: 'Covers S20b1-S20c. Game.next()/_perform_next() STAY -- only the BUTTON retired.'
- id: S20b4b
  description: 'The layering port: hoop split and reveal both take a BoardCoord; 5 fixtures ported.'
  status: done
  notes: 'The three Entrance hoop tests are deliberately NOT ported -- porting would delete coverage.'
- id: S21
  description: 'PHASE 5, the flipped board: upward stacks, eased row heights, the spring, score labels.'
  status: done
  notes: 'Covers S21-S25. TP-93 is a RATCHET against grid subtotals -- it proves it can SEE labels first.'
- id: S21settings
  description: 'Tests own the settings they test with, and sweep the range. SETTINGS RANGE suite.'
  status: done
- id: S35
  description: 'Phase 8: every placement an undo step; pending_action replay; validate() aliasing.'
  status: done
- id: S37
  description: 'The closing pass: adversarial review, /simplify, /docs; CARD_SEPARATION re-derived.'
  status: done
- id: S42
  description: 'PHASE 10, CSV HALF, out of order: CARD_CATALOG axis columns, superseded marks.'
  status: done
  notes: 'AXIS COLUMNS ARE KEYWORD-DERIVED, a filter aid, NOT a contract -- nothing may branch on them.'
- id: S43
  description: 'The draft appended, the post-grid curated effects CSV, the accepted-ideas CSV, blinds.'
  status: done
  notes: 'EVERY BLIND PAYS FOR PLAYING INTO IT (owner ruling); asserted: no empty payoff.'

# --- PHASE 6: the view. PLAN.md section 3; flowchart H is DESIGN.md section 36. ALL LANDED.
- id: S26
  description: 'Two view modes; opens zoomed out; a click in the overview ORIENTS instead of placing.'
  status: done
- id: S27
  description: 'Back/Forward zoom as a level stack; discrete centred panning; edge bounce.'
  status: done
- id: S28
  description: 'The one-scroll-container ratchet; >3 grids shifts which are in frame.'
  status: done
  notes: 'NO product code changed. grid_max_count governs UNLOCKING, not Board.add_grid.'
- id: S29
  description: 'Cross-grid arrow selection, the overview grid cursor, and touch swipe.'
  status: done
  notes: 'THE SWIPE SHIPPED DEAD AND ITS TESTS PASSED -- prove the ROUTE, not the handler.'
- id: S30
  description: 'Refocus the left survivor on removal; re-centre on EVERY removal.'
  status: done
  notes: 'Q318=(a) OVERRODE ITS DEFAULT: nearest survivor PREFERRING THE LEFT, not nearest to centre.'

# --- PHASE 7: the wall.
- id: S31
  description: 'The game picture sized for 3 grids, the height rule, the render-target clamp.'
  status: done
- id: S31b
  description: 'THE FOCUSED ZOOM: the focused grid is as tall as its window (GAP-017 part 3).'
  status: done
- id: S31c
  description: 'Clip the board scroll container, so "other grids out of view" is true of the PIXELS.'
  status: done
  notes: 'TP-141 COUNTS PAINTED PIXELS, NOT GEOMETRY -- and that is the whole point.'
- id: S31d
  description: 'WIDEN THE GAME PICTURE to grid_max_count grid positions, so the camera has a step.'
  status: done
- id: S31e
  description: 'One grid per grid position (GAP-021), furniture not duplicated.'
  status: blocked
  notes: >
    PART-LANDED, commit 1c8a2ae1. The INTERACTION click race and TP-109 are FIXED and green.
    TP-140's two out-of-view assertions are RED and DELIBERATELY UNWEAKENED, blocked on GAP-022's
    camera boundary. See the State section.
- id: S33
  description: 'PHASE 7: H20 the wall re-packs around the wider picture; H21 Info mode.'
  status: in_progress
  notes: >
    PULLED AHEAD OF S32 by owner ruling. H20 LANDED, commit 112424c5 -- keep_aspect on the game
    entry, the squash gone, verified by eye. H21/TP-119 (Q178=(a)) is the remaining half.
- id: S33hud
  description: 'GAP-022 follow-on: the whole HUD follows the camera.'
  status: done
  notes: >
    Code landed, suite clean. NOT blocked on the camera -- that earlier claim was wrong.
    pan_window_left_x() is extracted from the expression _sync_entrance_x already computed, so
    there is ONE writer read twice. Undo IS included per owner ruling.
    ⚠ THE REAL DEFECT, measured: _recapture_pan_origin() is deferred off board_changed and one
    deferred call fires while the new grid panel's cell subtree does not exist, so
    pan_window_left_x() takes its SILENT FALLBACK to grid_container.global_position.x (4.0)
    instead of the settled 1723.0. The origin is captured ONCE and latched, leaving the furniture
    permanently 1719 px out. _sync_entrance_x survives the identical fallback because it
    RE-DERIVES EVERY FRAME.
    ⚠⚠ A VALUE THAT IS SAFE TO READ PER-FRAME IS NOT AUTOMATICALLY SAFE TO CAPTURE ONCE.
    FIXED, and verified by eye: shift is now pan_grid * grid_position_size_px().x. All the
    furniture is on screen with the board.
- id: S32
  description: 'The saved pan and resting_state() (H18, H19).'
  status: pending
  notes: 'GAP-020=(b): resize first, then implement H18 literally.'
- id: S34
  description: 'Tools/wall_editor.tscn drives every new wall knob (Q186=a).'
  status: pending
- id: S40
  description: 'PHASE 10: ARCHITECTURE_REVIEW.'
  status: pending
- id: S41
  description: 'PHASE 10: alternate design docs.'
  status: pending
- id: S44
  description: 'PHASE 10: the remaining doc updates.'
  status: pending
```

## Verified vs assumed

- **Verified** — `ALL 44 SUITES: 3624 CHECKS PASSED`, zero failures, console banner and log banner
  AGREEING (see the two-process trap in Environment). 23 placeholder warnings; 22 ObjectDB instances
  leaked at exit plus two PagedAllocator/resource errors, which is the standing exit-time noise the
  wrapper reports and the in-run gate cannot see (they are in the process streams, not `godot.log`).
  `py .claude/tools/doc_check.py`: 0 errors, 7 warnings (the standing style backlog). Zero design ids
  in product code.
- **Verified** — `npm --prefix designloop run check -- solatro/poker-patience`: 0 errors, 0 warnings,
  0 dag defects, 0 stale chart nodes, 10 gaps closed and 0 open. The standing notes it does report
  are 41 prose answers with no option and 23 `⚑contract` questions no PLAN §1 block cites.
- **Verified by eye** — `grid_occupied.png` from `Tests/Visual/grid_layer_shot.tscn`: cards cover
  their cells, empty cells still frame, the Entrance strip is welded to the BOTTOM OF THE WINDOW with
  its five slots exactly under the five grid columns, and the scored line fired. At 4x on the top
  row, each hoop ring passes BEHIND the card faces on its upper arc and IN FRONT across the lower —
  a GRID-anchored prop bracketing, which did not happen before.
- **Assumed, not checked** — that `card_scale` 1.0 suits every OTHER screen (deck viewer, map, info
  card). Only the play area was looked at.
- ⚠ **Measured, and NOT a defect**: sampling showed 0 of 16 props moving over 90 frames. A HARNESS
  artefact — `run_props` is awaited inside `place_card_in_grid`, so the flight is over before any
  polling loop starts. To watch motion you must sample DURING the placement await.

## The three gates a change here must satisfy

1. **The card effect API** — a modifier may NOT touch `Game`, `GameData` or `Board` directly;
   everything goes through `CardEffectApi` as `CardModifier.api`, and a suite gate fails on any
   direct reference inside a modifier. ⚠ Extending the layer (with a `##` comment) is the sanctioned
   move. The gate matches the substring `"Board."`, so `BoardCoord` passes but `Board.locate_in_cell`
   would trip it. The five `PipSuit` subclasses are gated; `PropModifier` is not. See
   `design/card-effect-api/DESIGN.md`.
2. **The sentinel gate** — nothing anywhere writes `== BoardCoord.NOWHERE` or `!=`. `NOWHERE` is a
   shared instance and `==` on a RefCounted is IDENTITY, so a rebuilt sentinel is not equal to it.
   Use `is_nowhere()`; compare coords with `equals()`; key dictionaries and `Array.find` on `pack()`.
   Comment lines are exempt, which is how the rule can be written down.
3. **The zone-only ratchet** — `test_game_headless.gd::ZONE_ONLY_TESTS` lists the 6 test files that
   assert against the legacy renderer. The set may SHRINK, never grow, and porting a file fails the
   gate until its name is struck off, so the list cannot rot.

## Gaps — twenty-two filed, ONE OPEN (`GAP-018`); `GAP-022` = (a)

`design/poker-patience/gaps/GAP-001..009` and `GAP-015..016`, `design/grid-view/gaps/GAP-010..014`.
Answers are quoted verbatim at the top of each and **outrank `PLAN.md` and `NAMES.md`, because they
are newer.**

⚠ **`GAP-018` IS OPEN — `grid_swipe_threshold_mm`'s default is dead against its own clamp.** 8 mm at
96 DPI is 30.2 px, under the `[32, 96]` touch-target floor, so turning the knob down does nothing and
turning it up does nothing until ~8.47 mm. `Q190`=(a) fixes the CLAMP and the settings table fixes
the DEFAULT at 8; they disagree, and which gives way is the owner's call. Blocks nothing.

**`GAP-017` = answered** (the escalation below is what it was answering) (escalated from a timing question by
the by-eye gate — the absent knob is producing wrong geometry now, not later). `grid_buffer_px` and `grid_overview_margin`
are registered in `NAMES.md` §6 against `S28`, which after `GAP-016`=(d) has no site for either —
but the missing buffer is what makes the 3-grid board 731 px wide in a 703 px viewport.
⚠ **The gap as filed claimed `Q35` is unanswered; it is not — `Q35`=(b)** fixes that grids are
spaced by their CELL blocks with the labels in the buffer, so only the TIMING is open. Corrected in
the file. `S29`/`S30` are unaffected; the natural home is `S31`.

**`GAP-016` = (d)**, the fourth option found per `GAP-014`'s lesson: Phase 6 finishes on the
scroller and the camera migration lands in Phase 7 with the picture it needs. `TP-105` moved from
`S28` to `S31`; no design node amended. ⚠ **This does NOT license the scroller keeping grid-stepping
forever — Phase 7 still owes the migration.**
`GAP-014` is NOT A GAP — resolved as a defect, because a fourth option existed. It is kept because it
was filed correctly and the reasoning matters: **check for a fourth option before filing.**

## Owner working agreements

- **Reuse, do not reinvent.** Verbatim: *"reducing duplicate code as much as possible and no
  reinventing existing setups, or using existing engine methods when available."* ⚠ Put it in every
  step brief. Declining reuse is fine ON RECORD, with the reason in the file.
- **The light layer is out of scope.**
- **No design ids in product code** — not in a comment, not in an `@export_group` label. `Tests/` is
  exempt.
- **By-eye beats green.** The draw-order defect was found by the owner looking, not by 44 suites.
- **Old tests do not block the rebuild.** Verbatim: *"dont let tests from old version stop you since
  they need to be remade too."*

## Open bugs

- ⚠ **~8 px OF THE FOCUSED GRID'S TOP ROW IS NOW CUT.** The zoom overshoots its window by 7.8 px
  (the focused grid's cells measure `y [-4.8 .. 558.0]` against a board window of `y [3.0 .. 558.0]`),
  and clipping turned that overshoot from "drawn over the DEBUG button row" into "cut". **The
  overshoot is the ZOOM's, not the clip's** — `focused_board_zoom` sizes the CELL BLOCK to the
  window, and the row's outline rim sits outside it. Cosmetic, and the fix belongs with the zoom's
  sizing rather than the clip.
- ⚠ **`pan_to_grid` measures the scroll container's FULL rect**, so it aims ~4 px right of the
  visible window once the vertical scrollbar shows (measured: the middle grid rests at 775.0 against
  a window centre of 778.5). Deliberately left alone — fixing it moves every pan on the board.
- ⚠⚠ **THE SUITE HAS A FLAKY FAMILY, AND A SINGLE GREEN RUN IS NOT EVIDENCE ON IT.** Three
  assertions, all the same shape — **a fixed tick allowance racing an EASED layout or scroll** —
  fail intermittently on IDENTICAL production code:
  - `test_visual_layers.gd` *"a light follows its card across a board SCROLL"* (measured 2 failures
    in 4 runs; `373.00 px off` when it fails). It writes `scroll_horizontal` directly and allows 3
    ticks for a SMOOTH scroller to catch up.
  - `test_grid_layout.gd` *"a card on the GRID is pushed UP when the Entrance stacks"*
    (`496.0 -> 504.0`) and *"the board's LOWEST card clears the Entrance's real height"*
    (`lowest card bottom 531.0 vs Entrance top 501.0`). Measured: **both failed on one overseer run
    and both passed on the very next run of the same tree**, which then read
    `ALL 45 SUITES: 3782 CHECKS PASSED`.
  - `test_grid_view.gd` **`TP-112`** — **measured 2 failures in 5 runs** of unchanged code. *"...and it TRAVELLED there — mid-move it is further off centre
    than at rest"* (`94.2 px mid-move vs 93.8 px at rest`). **Measured 1 failure in 3 runs of one
    unchanged tree** — sub-pixel margin, same shape. NOT fallout from the `TP-140`/`TP-109` fixture
    change, which was the competing reading and was ruled out by re-running.
  ⚠ **The fix is a settle-until-still wait (`_settle_layout` / `_settle_scroll` already exist and
  are the right instrument), NEVER a widened tolerance** — widening would silence the only thing
  telling you the geometry had not finished moving.
  ⚠ **Practical consequence for anyone verifying: on a failure in this family, RE-RUN before
  believing it, and say which run you are quoting.**
- ⚠ **AN EMPTY CELL'S ZONE CARD COUNTS AS "ON A CARD"** for `H17`'s drag-vs-pan discrimination
  (`S29`), because it is the cell's drop target. `Q192`=(a) says *"a drag that STARTS on a card is a
  placement; a drag that starts on empty board is a pan"* and this follows it literally — but if the
  owner meant an empty cell reads as empty BOARD, it is a one-line change in
  `PlayArea._card_control_at`. **Worth an owner ruling before Phase 7.**
- ⚠ **THE SCROLL CONTENT'S OWN ORIGIN CAN SHIFT** as the region around it resizes (measured: its top
  moved -1 -> +7 when the Entrance's reservation changed). The board tracks the FLOOR exactly, which
  is correct — but "the board moved by exactly X" is an identity the layout does not owe, and a test
  asserting one will fail on a board that is behaving. ⚠ **Phase 6 rewrites this path; read it
  first.**
- ⚠ **THE PAN IS THE SCROLLER DOING THE CAMERA'S JOB UNTIL PHASE 7.** `GAP-016`=(d) parked this
  deliberately: `QR3`=a and `H11`/`H23` put grid-stepping on the wall's camera, `S27` shipped it on
  the `SmoothScrollContainer`, and the migration lands in **`S31`** with the wide picture a camera
  pan needs. ⚠ **Phase 7 owes it — do not let `S31` close without it.**
- ⚠ **SIX test files still assert only against the legacy renderer, and NONE of them can port.**
  `ZONE_ONLY_TESTS` is now entirely MACHINERY (3 — `test_board`, `test_mods`, `test_spotlight`)
  testing legacy code that is still LIVE (`find_data_vec3` has 9 product callers,
  `get_zone_from_vec3` 7, `is_data_topmost` 7, `add_column`/`remove_column` 9), plus ENTRANCE-ONLY
  (3) naming `upper_zone`, which IS the Entrance. Any of these leaving the list would be a BUG, not
  progress. A name APPEARING there means a new zone-only test was written.
- ⚠ **`Tools/spotlight_tool.gd` traces no cascade.** PRE-EXISTING: `git log -S place_card_in_grid` on
  it is empty — it has only ever used `move_data_to_coord` into the legacy lower zone.
- ⚠ **`Tests/Interaction/test_interaction.gd:459` is `check(true, ...)`** — a parked check that can
  never fail. Restore it to assert `game.processing` once a placement is a paced, cancellable act.
- **The COMBO label draws over the End button** — visible in `grid_occupied.png`.
- **`skill_scorer_cascade_lower.gd`** is an orphan in production, still a fixture in three suites.
- **`PLAN.md` §3 says `S26` implements H22; `TEST_PLAN.md` assigns H22's only test (TP-105) to
  `S28`.** Resolved in favour of the test plan — H22 lands with H23 in `S28`. The PLAN.md
  parenthetical for `S26` should read *(implements H4, H6)*; it was left unedited.
- **`PLAN.md` 1.1 / `TEST_PLAN.md` TP-02 state an arithmetically wrong example** — *"5 columns left
  of (grid 1, x 0) is (grid 0, x 4)"*. At width 5 it is ONE column left. Tests assert the correct
  behaviour; the docs were left unedited.

## Next up

⚠ **`S31e` IS PART-LANDED AND BLOCKED ON `GAP-022`, NOT ABANDONED.** Verified by two overseer runs
of the tree as it stands (quoting the second):
```
GRID VIEW 176/178   INTERACTION 52/52   GRID LAYOUT 69/71 (pre-existing)
```
Fixed and green: the INTERACTION click race (`_settle_layout` on the Entrance track — the ease is
UNCHANGED between the two trees, the Entrance simply travels ~151 px instead of ~25) and `TP-109`'s
swipe. Still red and DELIBERATELY NOT WEAKENED: `TP-140`'s two out-of-view assertions, which now
fail with a message naming the real cause (`vs window (0.0, 3640.476)`) instead of a vacuous
precondition.

1. ⚠⚠ **THE CAMERA MIGRATION (`TP-105`/`H22`) GATES `TP-140` — BUT NOT THE HUD.**
   `GAP-022`=(a) means "out of view" resolves against the CAMERA's rect, so `TP-140`'s two
   assertions cannot be satisfied until the camera exists. Today it is static at the picture centre
   and reads nothing about `pan_grid` (`resting_state()` returns `rect.centre`).
   ⚠⚠ **CORRECTION — commit `5e7fb2cf`'s message and an earlier version of this section BOTH say the
   HUD is blocked on the camera. THAT IS WRONG.** It was an inherited inference, promoted without
   testing. **Measured:** `pan_grid` rests correctly at 1 and holds through frame 120; the HUD was
   off screen because of a latched-origin bug in the new code (below), not because of the camera.
   ⚠ **THE LESSON, which this stream keeps re-paying for:** a plausible cause is not a measured one.
   The discriminating observation cost one render.
2. ⚠⚠ **`GAP-022` = (a) — ANSWERED. `PlayContainer` KEEPS the stretch, and "out of view" now means
   OUTSIDE THE CAMERA'S RECT, not outside the scroll container.** ⚠ **This makes the camera
   load-bearing before `S31e` can close**: `TP-105` stops being a step that follows `S31e` and
   becomes part of what makes it verifiable. `S31b`'s zoom and `S31c`'s clip must be re-pointed at
   the camera; ⚠ **`TP-141`'s painted-pixel evidence must be RE-EARNED, not re-labelled** — a
   position-based assertion passed both before and after the defect it once proved. `TP-140` is then
   satisfiable and must be re-measured, still not loosened. ⚠ **The HUD is off screen at rest under
   this answer and NOTHING RULES ON IT** — `Q39` covers only the Entrance. Raise a gap rather than
   assuming; assuming is exactly what `S31e` did.
2. **`S33`'s `H20` — the wall re-packs around the wider picture.** Pulled forward by owner ruling.
   ⚠ **This is now the gating step for the whole phase**: until it lands the product renders
   horizontally squashed to ~1/3 width, so every by-eye gate on this branch is either blind (the
   `GameView`-direct shots) or shows a broken board. `_picture_size()` never reading `design_size.x`
   is the mechanism.
3. **Promote `Tests/Visual/wall_game_squash_probe.{gd,tscn}` into a permanent named shot** — it is
   the ONLY instrument that renders the product's real framing, and its absence is why the squash
   passed two by-eye gates. Not in `all_tests.tscn`; the suite stays at 45. Delete
   `Tests/Visual/interaction_click_probe.{gd,tscn}`, whose findings are recorded above.
4. **Chase the `user://settings.tres` restore bug** (owner ruling: chase it). The suite writes test
   values at run start and the restore does not run on the normal exit route. Live suspect for the
   two pre-existing GRID LAYOUT failures, which are why **there is no green commit on this branch.**
   ⚠ Do not overwrite the file by guessing — recover a pristine default from the repo or ask.
5. **`TP-105`** (the camera steps between grid positions), then **`S32`**, then `S34`.
6. **Then Phase 9** (owner's call) and **Phase 10's remaining `S40`, `S41`, `S44`.**

⚠ **THIS FILE IS ~720 LINES AGAINST A ~300-LINE RULE.** Prune it before adding more: the landed-step
`notes:` blocks are the bulk and their forensics belong in the commits and the gap files.

**Open, not blocking, owner's call when convenient:**
- **The rest of the HUD at rest** — under `GAP-022`=(a) the Deck, score column and buttons sit at
  the picture's edges while the camera rests on the middle position. Reachable only by panning,
  which no answered node asks for. Needs a ruling before `S32`.
- **`GAP-018`** — `grid_swipe_threshold_mm`'s 8 mm default is 30.2 px at 96 DPI, under its own
  `[32, 96]` clamp, so the knob is dead at its default. `Q190`=(a) fixes the clamp and the settings
  table fixes the default; they disagree.
- **`grid_buffer_px` is 220 RAW px against a 216 px grid block** — §1i's table is stated at
  `card_scale` 2.5 and the game ships at 1.0. The owner has twice declined to rule.
- **For ~11 frames after a view change a click on an Entrance card silently does nothing**, because
  the card is easing out from under the cursor. Defensible (the card is visibly moving), but real.
- **Two cosmetic residues**: ~8 px of the focused grid's top row is cut, and the COMBO label draws
  over the End button.

### Opening prompt for the next session

```
Continue the poker-patience grid work on branch `poker-patience`.

READ IN THIS ORDER:
  1. solatro/HANDOFF_poker_patience.md - THIS FILE. Its State, Environment, "Standing rules",
     "three gates" and Open bugs sections are the traps; do not rediscover them.
  2. solatro/design/poker-patience/PLAN.md section 3 (Phase 7), section 1 (contracts).
  3. solatro/design/poker-patience/DESIGN.md section 36 - FLOWCHART H, which Phase 7 implements.
  4. The gap files: TWENTY-ONE filed. GAP-016, 017, 019, 020, 021 are the Phase 6/7 chain and
     their OWNER ANSWER sections OUTRANK PLAN.md, TEST_PLAN.md and NAMES.md.
  5. solatro/design/card-effect-api/DESIGN.md - modifiers reach the game only via
     CardModifier.api, and a suite gate enforces it.

FIRST, BEFORE ANYTHING ELSE: run the suite. HEAD (6ed95277) is S31e, which is COMMITTED BUT
UNVERIFIED and leaves 2 GRID VIEW failures - finish it properly or `git revert 6ed95277`.
Last fully verified commit is 58b223aa.

GROUND TRUTH (see Environment for the import trap on a new box):
    GODOT_BIN="<godot 4.7.2 console exe>" py solatro/Tools/run_tests.py --timeout 400
  Expect ALL 45 SUITES, zero failures. Judge by the failure SET and the SUITE COUNT, never
  the check total. ⚠ A single green run is NOT evidence: three assertions race an eased
  layout and flake - but two of them were a REAL regression once, so re-run to
  discriminate and never widen their tolerances.

THE WORK: S31e, then TP-105, then S32, S33, S34.

NON-NEGOTIABLES, each of which caught a real defect on this stream:
  - RED-THEN-GREEN for every new test, and check the red failed the checks you EXPECTED.
    Compare PER-SUITE counts across the red and green runs: if they match, nothing aborted.
    Do the red runs YOURSELF; never accept a self-reported green.
  - VERIFY VISUALS BY EYE, with the RIGHT instrument. grid_zoom_shot renders inside the REAL
    picture; grid_layer_shot renders a bare 1152x648 window and its multi-grid framing is a
    harness artefact. grid_clip_flight_shot shows a card in flight, frame by frame.
  - ASSERT WHAT IS PAINTED OR MEASURED, not an int the code just assigned itself.
  - MEASURE BEFORE YOU BUILD. Four Phase 7 steps ended `blocked` because a premise was false;
    each was worth more than the code would have been.
  - NO COMMENT INSIDE A METHOD BODY (owner rule). A `##` comment above the method says WHY it
    exists. Wanting an inline comment means the code needs a NAME.
  - COMMITS ARE ALLOWED on this branch (owner: "you are allowed to commit when its not in
    main branch"), one verified step per commit, evidence in the message.
  - REUSE, don't reinvent. Declining reuse is fine ON RECORD with the reason in the file.

If you hit a decision no document fixes: file a gap at solatro/design/<slug>/gaps/GAP-NNN.md
following GAP-001's shape, park that thread, keep the unaffected ones moving, and QUOTE the
gap's own option text to the owner. A bug is not a gap. ⚠ CHECK FOR A FOURTH OPTION FIRST -
five gaps on this stream were answered with an option nobody had listed, two of them written
by the owner. ⚠ And VERIFY A CLAIM BEFORE BUILDING A GAP ON IT: GAP-017 was filed claiming a
question was unanswered when it was answered, and GAP-016 arose from citing Q182, which sits
on a pruned branch.
```

## References

- `design/poker-patience/PLAN.md` - the steps; section 1 the normative contracts.
- `design/poker-patience/DESIGN.md` - the authority on the game's behaviour; section 36 is chart H.
- `design/grid-view/DESIGN.md` - the view's design, its answers and its six charts.
- `design/poker-patience/TEST_PLAN.md` and `NAMES.md` - every planned test; every identifier.
- `design/card-effect-api/DESIGN.md` - the modifier boundary the first gate enforces.
- `ARCHITECTURE_REVIEW.md` - the engine's contracts (undo, pending-action replay, layering).

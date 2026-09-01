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

**Next is PHASE 7 — the wall** (`S31`-`S34`). ⚠ `S31` also owes `TP-105` and the camera migration
`GAP-016`=(d) deferred to it, and **part 3 of `GAP-017`'s ruling: the focused grid sized to the
viewport height with the other grids out of view** — a zoom Phase 6 deliberately does not have.
Phase 9 is the owner's call; Phase 10's remaining three steps are last.

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

- Godot here is **4.7.2**; `.claude/memory/machine-profiles.md` records it per box. ⚠ **A cache built
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

⚠ **The stale-step tooling only recognises `S<digits>`.** `designloop/src/gaps.mjs::planSteps()`
does NOT see the lettered ids (`S19b`, `S20b2b`, `S20c`, …), so a gap whose blast radius names a
lettered step will not appear in its stale list. The lettered convention predates this stream and is
used in `PLAN.md` too; renumbering would break its citations. Check lettered steps by hand.

```yaml
# --- LANDED. Evidence is in the commit messages; forensics are in the gap files; the durable
# --- rules are in "Standing rules" above.
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
- id: S35
  description: 'Phase 8: every placement an undo step; pending_action replay; validate() aliasing.'
  status: done
- id: S19b
  description: 'The legacy coordinate migration -- SUPERSEDED, folded into S20b by GAP-009.'
  status: superseded
- id: S37
  description: 'The closing pass: adversarial review, /simplify, /docs; CARD_SEPARATION re-derived.'
  status: done
- id: S20
  description: 'THE VIEW REPLACEMENT: GridPanel/CellSlot, the zone renderers deleted, the pinned Entrance.'
  status: done
  notes: >
    Covers S20b1, S20b2, S20b2b0, S20b2b, S20b3, S20b4a, S20bDraw, S20bRatchet, S20bPort and S20c.
    Game.next()/_perform_next() STAY -- only the BUTTON retired; _perform_next still serves the
    &"on_next" replay. ⚠ S20bDraw was found BY EYE through 43 green suites: _order_board_cards never
    ordered grid cards, so a card drew BEHIND its own cell.
- id: S20b4b
  description: 'The layering port: the hoop split and the reveal both take a BoardCoord; 5 fixtures ported.'
  status: done
  notes: >
    All three sub-steps landed. PlayArea.coord_of_data is DELETED -- GameData.grid_position_of
    already answered for the whole board. The three Entrance hoop tests are deliberately NOT ported:
    porting them would delete coverage rather than add it.
- id: S21
  description: 'PHASE 5, the flipped board: upward stacks, eased row heights, the spring, score labels.'
  status: done
  notes: >
    Covers S21 (upward stacks, one container per row, the board floor), S22 (a row eases into its
    height; the Entrance is row -1 and raises the board; _reveal_geometry_exists DELETED), S23 (the
    spring), S24 (score labels, one per line AND per height -- GAP-015) and S25 (cross-grid row
    alignment, off by default, proven not to touch scoring).
    ⚠ TP-93 is a RATCHET against grid subtotals: it passes trivially and fails the day a panel
    displays one. It proves it can SEE labels before asserting none is a subtotal.
- id: S21settings
  description: 'Tests own the settings they test with, and sweep the range. SETTINGS RANGE suite.'
  status: done
  notes: >
    Owner ruling: "tests should have its own settings it tests with over range of possible settings
    values, that way tuning settings wont break tests, and tests that any setting is valid."
    Verified: user://settings.tres byte-identical after a full run AND after one killed by its
    timeout -- the damage this fixes.
- id: S42
  description: 'PHASE 10, CSV HALF, taken out of order: CARD_CATALOG axis columns, superseded marks.'
  status: done
  notes: >
    ⚠ THE AXIS COLUMNS ARE KEYWORD-DERIVED FROM THE EFFECT TEXT, NOT HAND-JUDGED -- a filter aid, not
    a contract; nothing should branch on them. `scope` is the exception: only `grid-local` and
    `global` are legal, per the owner. 378 rows -> 599.
- id: S43
  description: 'The draft appended, the post-grid curated effects CSV, the accepted-ideas CSV, blinds.'
  status: done
  notes: >
    ⚠ COVERAGE IS MECHANICALLY PROVEN, not asserted: every row cites its source line and a checker
    expands the ranges -- 2788 non-blank lines, none missed. NEW, not in PLAN.md: blinds.csv, 90 rows.
    ⚠ EVERY BLIND PAYS FOR PLAYING INTO IT (owner ruling); asserted: no empty `payoff`.

# --- PHASE 6: the view. PLAN.md section 3; flowchart H is DESIGN.md section 36.
- id: S26
  description: 'Two view modes; opens zoomed out; a click in the overview ORIENTS instead of placing.'
  status: done
  evidence: 'Commit 842e95c5. Overseer-verified green; TP-97, TP-98.'
  notes: >
    ⚠ Q147=b is the discriminating case: in the overview a click FOCUSES and must NOT place. Opening
    zoomed out runs in `_ready()`, deliberately NOT `setup_gui()`, which is also the undo-rebuild
    path and would zoom out on every undo. PLAN.md §3 also lists H22 here; TEST_PLAN routes H22's
    only assertion (TP-105) to S31, and the test plan won.
- id: S27
  description: 'Back/Forward zoom as a level stack; discrete centred panning; edge bounce.'
  status: done
  evidence: 'Commit 4cf42f8e. Overseer-verified green; TP-99 - TP-103.'
  notes: >
    ⚠ THE LEVEL STACK reconciles Q148 with Q187: focused -> overview -> wall. Back zooms out one
    level and, once in the overview, FALLS THROUGH so wall_back still reaches the wall. That
    fall-through is the case the owner's example does not cover.
    ⚠ TP-103 CAUGHT A REAL DEFECT: a board narrower than the window parked LEFT, because a
    ScrollContainer hands its content the content's own minimum width. Fixed by
    `size_flags_horizontal = SIZE_EXPAND_FILL` on TopLevelVBox -- HORIZONTAL ONLY; the floor is
    ALIGNMENT_END and is untouched.
- id: S28
  description: 'The one-scroll-container ratchet; >3 grids shifts which are in frame.'
  status: done
  evidence: 'Commit 7d114a0a. Overseer-verified green; TP-104, TP-106. NO product code changed.'
  notes: >
    ⚠ TP-104 PROVES ITS INSTRUMENT FIRST -- it asserts the finder can SEE more than one
    ScrollContainer before asserting the board holds exactly one. An assertion that counts zero
    things passes trivially.
    ⚠ TP-106 reaches the 4+ grid case Q7's cap hides by standing up five grids directly:
    `grid_max_count` governs UNLOCKING, not `Board.add_grid`.
- id: S29
  description: 'Cross-grid arrow selection, the overview grid cursor, and touch swipe.'
  status: done
  evidence: 'Commit 82670456, plus the swipe route fix in ee9dea68. TP-107 - TP-110.'
  notes: >
    ⚠ ARROWS ARE MODE-DEPENDENT (Q162=b): cells when FOCUSED, whole grids in the OVERVIEW.
    ⚠ THE ARROW READER MUST SIT ON THE CELL'S OWN `gui_input`. The viewport's focus-neighbour search
    runs in the GUI pass and CONSUMES any arrow that finds a neighbour, so an `_unhandled_input`
    reader never runs while a cell has focus.
    ⚠ TP-109's FIXTURE IS FIVE GRIDS ON PURPOSE: from grid 1 of THREE, a doubling swipe reader's
    second step bounces off the board's end and lands on the SAME pan_grid a correct reader
    produces -- the defect hides.
    ⚠⚠ **THE SWIPE SHIPPED DEAD AND ITS TESTS PASSED** -- see Open bugs' entry on proving the ROUTE.
- id: S31
  description: 'PHASE 7: the game picture sized for 3 grids, the height rule, the render-target clamp.'
  status: done
  evidence: >
    Overseer-verified: ALL 45 SUITES: 3789 CHECKS PASSED, zero failures, console and log agreeing.
    doc_check 0 errors / 7 warnings; no design ids, sentinel violations or tunable literals added.
    RED (the clamp call and the _size_game_picture call removed): 5 FAILED -- TP-113's margin check
    and all four TP-114 wiring checks. GRID VIEW 159 of 159 in BOTH runs, so nothing aborted.
    BY EYE at 2 grids: a clean 220 px gap, symmetric at -218.0/+218.0, nothing cut off.
  notes: >
    ⚠ **Q166=(a) OVERRODE ITS OWN DEFAULT**: `design_size` stays AUTHORED data sized for exactly 3
    grids, NOT computed at show start from the actual grid count (the rejected (c)).
    ⚠ **`SubViewport.size` LIES WHEN OVERSIZED** -- over the GPU cap the framebuffer is destroyed and
    the size set to 0 internally while the GDScript property still reports the value it was given.
    So TP-114 asserts the pure `clamped_render_size()` at and past the cap, and that `build()` and
    `focus()` each WROTE the clamped value and engaged `size_2d_override` -- never a read-back.
    ⚠ **`grid_buffer_px` LANDED HERE** as the cell-block-to-cell-block gap (`Q35`=b), applied as a
    dynamically computed HBox separation (buffer less the measured label gutters) because one
    container separation cannot vary per pair.
    ⚠ ONE existing check reacted -- TP-106's `before.has(0)`. Investigated, not loosened: at a 220 px
    buffer only the grid the view RESTS on is wholly in frame, and a sliced neighbour is explicitly
    not a defect under GAP-017 part 1. Re-pointed at `before.has(pa.pan_grid)`, the identity the
    layout owes.
    ⚠ TP-113's 7th check ("sized by the rule, not the entry default") was added AFTER the red run,
    so it alone is not red-proven -- at test `card_scale` the 1152 px default still passed the
    three-grid width check, which is why it exists.
- id: S31b
  description: 'THE FOCUSED ZOOM: the focused grid is as tall as its window (GAP-017 ruling part 3).'
  status: done
  evidence: >
    Overseer-verified: ALL 45 SUITES: 3805 CHECKS PASSED, zero failures. GRID VIEW 160 -> 170.
    doc_check 0 errors; no design ids or sentinel violations added.
    RED (the wiring cut -- focus_grid's call to the zoom removed, nothing else): 4 FAILED, and
    GRID VIEW read 170 of 170 in BOTH runs, GRID LAYOUT 71 in both, VISUAL LAYERS 220 in both, so
    nothing aborted.
    BY EYE via the new `grid_zoom_shot`, which renders inside the REAL picture: the focused grid
    measures y [3.0 .. 558.0] against a board window of y [3.0 .. 558.0] -- **the grid's height IS
    the viewport's height, exactly.**
  notes: >
    ⚠ **THE SCALE MUST LIVE ON THE SCROLL CONTAINER, NOT ITS CONTENT** -- a `Container` rewrites its
    children's scale on every sort (measured: `TopLevelVBox` was back at 1 the next frame). Its rect
    is divided by the same factor so the window keeps its pixels.
    ⚠ **THE SCALE IS NOT ANIMATED** (`Q145`: "no intermediate zoom exists", read literally) and
    measured: the scroller clamps every aim against the reach it can see at that instant, so an
    eased scale DESTROYS the aim issued with it. The transition the player sees is the pan.
    ⚠ **EVERY SITE THAT ADDED A MEASURED GLOBAL POSITION TO A LOCAL SIZE HAD TO BECOME ZOOM-AWARE.**
    The suite's own `_window_x` / `_cut_off_px` mixed the two -- a latent error the zoom exposed;
    corrected to read the engine's global transform, not widened.
    ⚠ **TWO "FLAKY FAMILY" FAILURES HERE WERE A REAL REGRESSION, NOT FLAKE** -- the board's floor was
    made to read the SCROLLER's window, which the Entrance's RESERVATION carves out, while the floor
    must clear its ACTUAL height. They differ exactly when the Entrance stacks. **So that family is
    not pure noise: it caught a real bug. Investigate before dismissing a failure there.**
- id: S31c
  description: 'Clip the board scroll container, so "other grids out of view" is true of the PIXELS.'
  status: done
  evidence: >
    Overseer-verified: ALL 45 SUITES: 3801 CHECKS PASSED, zero failures. GRID VIEW 170 -> 175.
    doc_check 0 errors.
    RED: 1 FAILED, and per-suite counts were identical across the two runs for all 45 except GRID
    VIEW (the added check) and the randomised BOARD FUZZ -- nothing aborted.
    BY EYE, on a mid-flight frame the overseer looked at: **the flying card is drawn WHOLE, no cut
    edge**, and the left column of UI (Deck, Goal, Total, skill text, Discard, Rules) is clean where
    a whole grid used to paint over it.
  notes: >
    ⚠ **TP-141 COUNTS PAINTED PIXELS, NOT GEOMETRY -- and that is the whole point.** The neighbours
    were ALREADY positioned outside the window before this fix, so any position-based assertion
    passes both before and after and proves nothing. It renders into a picture-sized viewport and
    counts the pixels OUTSIDE the container's rect that change when a non-focused panel is hidden:
    **100,908 px red, 0 px green.**
    ⚠ **CLIPPING DOES NOT CUT A CARD IN FLIGHT** -- the risk that made this a decision. Verified by
    building `Tests/Visual/grid_clip_flight_shot`, which calls the real `place_card_in_grid` WITHOUT
    awaiting it and saves 14 consecutive frames. A held Entrance card never enters the question: it
    stays in `EntranceCardLayer`, outside the clip.
    A jumping card at the top of the board and a hoop bracketing a card near the edge were both
    checked and draw whole.
- id: S31d
  description: 'WIDEN THE GAME PICTURE to grid_max_count grid positions, so the camera has a step.'
  status: done
  evidence: >
    Overseer-verified: ALL 45 SUITES: 3806 CHECKS PASSED, zero failures. doc_check 0 errors; no
    design ids added to product code.
    RED: exactly 3 failures, all TP-113 -- and NOTHING else reacted. TP-101, TP-103, TP-106, TP-114,
    TP-138-TP-141 and the whole flaky family stayed green in both runs, which is the evidence that
    none of them was calibrated to the old picture width.
    Picture 1219x685 -> **3656x685**. Camera slack at rest **0.6 px -> 2438 px (~2 grid positions)**.
  notes: >
    ⚠⚠ **THE HEIGHT RULE APPLIED TO THE WHOLE PICTURE IS PROVABLY INCOMPATIBLE WITH `H22` AT ANY
    WIDTH.** `focused_scale()` rests the camera by OVERFILLING (the max of the axis ratios), so a
    picture whose aspect IS the window's is framed WHOLE at rest -- at 1219x685 and equally at
    3456x1944 (zoom 0.3333 on both axes, 100% visible). **A wider picture alone does not give the
    camera a step; the overseer's suggested 3456x1944 would NOT have worked.**
    The resolution: apply `H2`'s aspect minimum to **ONE GRID POSITION**, not the whole picture, and
    make the picture `grid_max_count` positions wide. `Q160` states it literally -- *"camera will pan
    over 3 possible grid positions since that is size of picture frame"*. Recorded in ASSUMPTIONS.md.
    ⚠ The clamp does NOT bite at 3656 (< 4096) and `size_2d_override` stays ZERO. At
    `grid_max_count` 4 it would (6096 -> 4096 on x) and the override then holds the layout at 6096.
    ⚠ **`grid_buffer_px` is untouched and still 220 raw px against a 216 px block** -- it lives
    entirely inside one grid position, so this step neither improved nor worsened it. Still unruled.
- id: S30
  description: 'Refocus the left survivor on removal; re-centre on EVERY removal.'
  status: done
  evidence: 'Commit d5d0b172. Overseer-verified green; TP-111, TP-112, TP-138.'
  notes: >
    ⚠ Chart G's G16-no edge goes STRAIGHT to G18 and G17 also flows into it, so the re-centre
    happens on EVERY removal and only the refocus is conditional. A test that only removes the
    FOCUSED grid cannot tell a correct implementation from one that re-centres solely on that path.
    ⚠ TWO WEAKER TP-112 FIXTURES WERE REJECTED AND ONE PASSED WITH THE WIRING CUT: at three grids
    the survivors FIT so the layout centres them with no scroll, and near an edge the clamp lands
    the board where a re-centre would. The middle grid of FIVE has slack both sides.
    ⚠ The resting claim is an identity the layout OWES -- the board lands where an explicit
    `pan_to_grid` lands -- not an absolute centre.
    Q318=(a) OVERRODE ITS OWN DEFAULT: nearest survivor PREFERRING THE LEFT, not nearest to centre.
```

After Phase 6 comes Phase 7 (`S31`-`S34`, the wall), then Phase 9 (goal-curve refit, the owner's
call). ⚠ **Phase 10 was taken out of order, and only its CSV half.** `S42` and `S43` are done; `S40`
(ARCHITECTURE_REVIEW), `S41` (alternate design docs) and `S44` (the remaining doc updates) are NOT,
and the plan's dependency note — Phase 10 depends on everything and runs last — still holds for them.

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

## Gaps — eighteen filed, seventeen resolved, ONE OPEN

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

1. **`S30`** — refocus when the focused grid is removed, and re-centring (`G16`-`G18`). It is the
   last step of Phase 6.
2. **Phase 7** — `S31`-`S34`: the wall. ⚠ **`S31` now also owes `TP-105` and the camera migration
   `GAP-016` deferred to it.**

⚠ **`doc_check.py` CANNOT EXPRESS A FILENAME CONTAINING SPACES.** Its reference regex keeps only the
last space-free run, so spelling out the post-grid curated effects CSV in a living doc reports a
dangling reference to a name that is really just its tail. The exact spelling lives in
`START_HERE.md`'s read-first table; every other doc calls it "the post-grid curated effects CSV".
That file is where any new card idea now goes, and every row there must declare `scope` as
`grid-local` or `global`.

### Opening prompt for the next session

```
Continue the poker-patience grid work on branch `poker-patience`.

READ IN THIS ORDER:
  1. solatro/HANDOFF_poker_patience.md - THIS FILE. Its Environment, "Standing rules", "three
     gates" and Open bugs sections are the traps; do not rediscover them.
  2. solatro/design/poker-patience/PLAN.md section 3 (Phase 6), section 1 (contracts).
  3. solatro/design/poker-patience/DESIGN.md section 36 - FLOWCHART H, which Phase 6 implements.
  4. solatro/design/grid-view/DESIGN.md - charts J, K, L, M, N, P.
  5. The gap files: SEVENTEEN filed, sixteen resolved, GAP-017 open but blocking nothing. Answers are quoted verbatim at the top of
     each and OUTRANK PLAN.md and NAMES.md.
  6. solatro/design/card-effect-api/DESIGN.md - modifiers reach the game only via
     CardModifier.api, and a suite gate enforces it.

GROUND TRUTH BEFORE TRUSTING ANY `done` (see Environment for the import trap on a new box):
    GODOT_BIN="<godot 4.7.2 console exe>" py solatro/Tools/run_tests.py --timeout 400
  Expect ALL 44 SUITES, zero failures. Last verified 3624 CHECKS PASSED.

THE WORK: S26-S29 are LANDED and committed. Next is S30, the last step of Phase 6, then
  Phase 7 - where S31 owes TP-105 and the camera migration GAP-016 deferred to it, plus
  GAP-017's two knobs if the owner puts them there.

NON-NEGOTIABLES, each of which caught a real defect on this stream:
  - RED-THEN-GREEN for every new test, and check the red failed the checks you EXPECTED.
    Do the red runs YOURSELF; never accept a self-reported green.
  - VERIFY VISUALS BY EYE. Tests/Visual/grid_layer_shot.tscn shows a POPULATED grid and
    prints card-vs-cell draw indices. A green suite is not evidence about pixels - the owner
    found a card drawing behind its own cell that 43 green suites did not.
  - CHECK THE SUITE COUNT (44) and the failure SET, never the check total, which swings by
    tens between runs.
  - AT EVERY PHASE BOUNDARY: read the diff, run an adversarial pass tracing what a PLAYER
    does, and run `py .claude/tools/doc_check.py` (baseline: 0 errors, 7 warnings).
  - Every step brief names THE CALL SITE. Never accept `done` on a component whose consumer
    does not exist.
  - REUSE, don't reinvent. Declining reuse is fine ON RECORD with the reason in the file.

If you hit a decision no document fixes: file a gap at solatro/design/<slug>/gaps/GAP-NNN.md
following GAP-001's shape, park that thread, keep the unaffected ones moving, and QUOTE the
gap's own option text to the owner. A bug is not a gap: if exactly one choice is defensible
it is a defect - fix it and record it. And check for a FOURTH option before filing: GAP-014
was filed correctly and still turned out to be a defect.
```

## References

- `design/poker-patience/PLAN.md` - the steps; section 1 the normative contracts.
- `design/poker-patience/DESIGN.md` - the authority on the game's behaviour; section 36 is chart H.
- `design/grid-view/DESIGN.md` - the view's design, its answers and its six charts.
- `design/poker-patience/TEST_PLAN.md` and `NAMES.md` - every planned test; every identifier.
- `design/card-effect-api/DESIGN.md` - the modifier boundary the first gate enforces.
- `ARCHITECTURE_REVIEW.md` - the engine's contracts (undo, pending-action replay, layering).

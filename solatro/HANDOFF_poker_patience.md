# HANDOFF — poker patience

**Goal:** turn Solatro's two-zone tableau into the poker-patience grid game — the engine, then the
board the player sees. Done when a player can deal, place, score, undo and End a show on a grid
they can look at.

**State:** **Phases 1-5 are complete, and so is Phase 8.** The engine scores grids, the legacy zones
are gone, the Entrance is pinned to the bottom of the window with its slots under their columns, the
board stacks UPWARD off a fixed floor, rows ease into their height, a jump carries the stack above
it, and every row, column and stack shows its own score. Phase 10's CSV half (`S42`, `S43`) landed
out of order at the owner's instruction.

**Next is PHASE 6 — the view** (`S26`-`S30`: two view modes, zoom, pan, keyboard/controller
selection across grids), then Phase 7 (the wall). Phase 9 is the owner's call; Phase 10's remaining
three steps are last.

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
  REAL `GameView`; they are the only things that show the board.

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
    Covers the lettered sub-steps S20b1, S20b2, S20b2b0, S20b2b, S20b3, S20b4a, S20bDraw,
    S20bRatchet, S20bPort and S20c. The coordinate migrated (slot_center_global takes a BoardCoord),
    the LowerZone and MiddleZone renderers are gone, the Entrance became a pinned strip outside the
    board's scroll, and the act (Submit / the Next button) retired. Game.next()/_perform_next() STAY
    -- only the BUTTON retired, and _perform_next still serves the &"on_next" replay.
    ⚠ S20bDraw was found BY EYE through 43 green suites: _order_board_cards never ordered grid cards,
    so a card drew BEHIND its own cell.
- id: S20b4b
  description: 'The layering port: the hoop split and the reveal both take a BoardCoord; 5 fixtures ported.'
  status: done
  notes: >
    All three sub-steps landed (S20b4b1 hoop split, S20b4b2 reveal key, S20b4b3 the fixture ports).
    PlayArea.coord_of_data is DELETED -- GameData.grid_position_of already answered for the whole
    board off a revision-keyed index. The three Entrance hoop tests are deliberately NOT ported: the
    Entrance is a live, differently-shaped half of the board with its own CardLayer, so porting them
    would delete coverage rather than add it.
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
    ⚠ THE OWNER'S BAR WAS "AT LEAST 1 ENTRY PER LINE", SO COVERAGE IS MECHANICALLY PROVEN. Every row
    cites the line it came from and a checker expands the ranges: 2788 non-blank lines, none missed.
    A row whose idea already existed gets the second source APPENDED, not a new row.
    NEW, not in PLAN.md: blinds.csv, 90 rows. ⚠ EVERY BLIND PAYS FOR PLAYING INTO IT -- the owner's
    ruling that a hazard must reward the risk. Asserted: no row has an empty `payoff`.

# --- PHASE 6: the view. PLAN.md section 3; flowchart H is DESIGN.md section 36.
- id: S26
  description: >
    Two view modes. The show OPENS zoomed out on the all-grids view; the picture frame holds 3 grid
    positions and the camera steps between them; clicking a grid zooms in on it. Implements H4, H6,
    H22.
  files_touched: [solatro/UI/play_area.gd, solatro/Tests/UI/test_grid_view.gd,
    solatro/Tests/UI/test_grid_view.tscn, solatro/Tests/all_tests.tscn,
    solatro/Tests/Support/test_base.gd, solatro/Tests/Interaction/test_interaction.gd,
    solatro/Tests/UI/test_ui_props.gd, solatro/Tests/UI/test_visual_layers.gd]
  verification_command: 'GODOT_BIN=<4.7.2 console exe> py solatro/Tools/run_tests.py --timeout 400'
  verification_kind: suite
  status: done
  evidence: >
    Overseer-run, not self-reported: ALL 45 SUITES: 3646 CHECKS PASSED, zero failures, console and
    log banners agreeing, log mtime fresh, test_output_errors.log 0 bytes. Suite count 44 -> 45 as
    the registry predicted; GRID VIEW: 13 CHECKS PASSED. doc_check 0 errors / 7 warnings, and the
    diff added ZERO design ids and ZERO numeric literals to product code.
    RED A (open_zoomed_out removed from _ready): 7 FAILED, exactly the expected set -- the
    opens-zoomed-out and nothing-focused checks plus the four TP-98 checks that depend on starting
    in the overview. RED B (_consume_as_focus_click forced false): 5 FAILED -- TP-97 green, TP-98's
    zoom/focus/no-selection checks red. Each red failed the checks EXPECTED, not the test itself.
  notes: >
    ⚠ **S26 SHIPS THE MODE AND THE INPUT CONSEQUENCE, NOT A CAMERA MOVE.** `PLAN.md` §3 says S26
    implements H4, H6 AND H22 -- but `TEST_PLAN.md` routes H22's only assertion, TP-105 ("the camera
    steps between the 3 grid positions the frame holds"), to **S28**. The test plan is the one with
    an observable behind it, so H22 lands with H23 in S28 and PLAN.md's parenthetical is the error.
    ⚠ **THE DISCRIMINATING CASE IS Q147=b**: in the overview a click FOCUSES and must NOT place; the
    same click focused places. That is what TP-98 turns on, and RED B is what proves it.
    CALL SITES: opening zoomed out runs in `PlayArea._ready()` after `setup_gui()` -- deliberately
    NOT in `setup_gui()`, which is also the undo-rebuild path and would zoom out on every undo. The
    focusing click arrives through the scene-connected `_on_gui_input` and `_unhandled_input`'s
    `ui_accept` branch on the real bound cell control; the test posts an InputEventMouseButton and
    never calls `focus_grid` itself.
    The overview intercepts `ui_accept` as well as the mouse, because Q147 puts placement behind
    focus regardless of device. Grid SELECTION in the overview is S29's.
    INTERACTION now calls `focus_grid(0)` in its fixture -- placement happens focused, which is the
    new premise rather than a workaround.
- id: S27
  description: >
    Back zooms out a level and Forward returns to the previous view; panning gets its OWN bindings
    while the wall keeps its shoulder buttons; a pan steps one grid and always lands centred; the
    board edge bounces; Camera2D limit and smoothing clamp, collapsing to centre on any axis that
    already fits. Implements H7-H12.
  files_touched: [solatro/UI/play_area.gd, solatro/Scripts/player_settings.gd,
    solatro/project.godot, solatro/Tests/UI/test_grid_view.gd,
    solatro/design/poker-patience/ASSUMPTIONS.md]
  verification_command: 'GODOT_BIN=<4.7.2 console exe> py solatro/Tools/run_tests.py --timeout 400'
  verification_kind: suite
  status: done
  evidence: >
    Overseer-run: ALL 45 SUITES: 3677 CHECKS PASSED, zero failures, console and log agreeing, log
    mtime fresh, errors log 0 bytes. doc_check 0 errors / 7 warnings; ZERO design ids and ZERO
    numeric literals added to product code.
    RED (fall-through removed only): 1 FAILED, and it was the RIGHT one -- "Back in the all-grids
    view is NOT swallowed -- it reaches the wall". RED (zoom-out, pan step, bounce and centring all
    neutralised): 10 FAILED, all in the expected set (2 TP-99, 1 TP-100, 4 TP-101, 1 TP-102,
    2 TP-103).
    BY EYE (grid_layer_shot.tscn, rendered and looked at): the grid is centred at x~785 in a
    1152-wide window, matching the measured fix (was 555, window centre 782). The clipped top row
    no longer reproduces.
  notes: >
    ⚠ **TP-103 CAUGHT A REAL DEFECT, it did not just pass**: a board narrower than the window was
    parked at the LEFT EDGE instead of collapsing to centre, because a ScrollContainer hands its
    content exactly the content's own minimum width. Fixed by `TopLevelVBox` taking
    `size_flags_horizontal = SIZE_EXPAND_FILL`, so centring is the LAYOUT's answer rather than
    arithmetic in the pan. ⚠ This is HORIZONTAL only -- the floor still comes from `ALIGNMENT_END`
    and is untouched.
    ⚠ **THE LEVEL STACK is what reconciles Q148 with Q187**: focused -> overview -> wall. Back zooms
    out one level and, once in the overview, FALLS THROUGH so `wall_back` still reaches the wall.
    That fall-through is the case the owner's example does not cover, and it is the single check the
    first red run reddened.
    ⚠⚠ **THE PAN RIDES THE `SmoothScrollContainer`, NOT A CAMERA -- AND THE DESIGN SAYS CAMERA.**
    The implementer justified this with `Q182` ("the existing SmoothScrollContainer, driven
    programmatically"), but `Q182` is gated `[QR3=b]` and **QR3 = (a)**, so Q182 sits on a pruned
    branch and is UNANSWERED. Under `QR3`=a the wall's camera pans over a wide picture, and `H11`
    says "Camera2D limit and smoothing do the clamping". The practical defence stands -- the play
    area has no `Camera2D` today and the wide picture is `S31`'s -- but the citation does not.
    **`S28` must settle it**: `H23` divides the two explicitly ("the camera steps between the 3 grid
    positions; the scroller reveals more of ONE grid"), and today the scroller is doing the
    camera's job. See Open bugs.
- id: S28
  description: >
    ONE scroll container inside the picture, for tall stacks and oversized grids; the camera steps
    between the 3 grid positions while the scroller reveals more of ONE grid; with more than 3 grids
    panning shifts WHICH 3 are in frame. Implements H13, H23, H24.
  files_touched: []
  verification_command: 'GODOT_BIN=<4.7.2 console exe> py solatro/Tools/run_tests.py --timeout 400'
  verification_kind: suite
  status: blocked
  evidence: ''
  notes: >
    ⚠ **BLOCKED ON GAP-016.** S27 shipped grid-stepping on the SmoothScrollContainer; QR3=a and
    H11/H23 put it on the wall's camera, and H23's whole content is that the two never contend
    because they move different things. S28 is the step where that has to be settled, and TP-105
    ("the camera steps between the 3 grid positions the frame holds") cannot be satisfied before
    S31 builds the wide picture in Phase 7. Do NOT start this until the owner answers.
    ⚠ H24 is unreachable in the shipped game (Q7 caps grids at 3) but the design carries it, and
    game_picture_max_render_px is what keeps a wider board from silently exceeding the render
    target.
- id: S29
  description: >
    Arrow keys move the cell selection across grid boundaries and the camera follows; in the
    all-grids view arrows select a GRID and Enter focuses it; one-finger swipe read as ScreenDrag
    with emulated events filtered by device -1; a drag starting on a card places, on empty board it
    pans. Implements H14-H17.
  files_touched: []
  verification_command: 'GODOT_BIN=<4.7.2 console exe> py solatro/Tools/run_tests.py --timeout 400'
  verification_kind: suite
  status: pending
  evidence: ''
  notes: 'Done-when: TP-107 - TP-110 green. A touch test must run AFTER the mouse tests.'
- id: S30
  description: 'Refocus when the focused grid is removed, and re-centring. Implements G16, G17, G18.'
  files_touched: []
  verification_command: 'GODOT_BIN=<4.7.2 console exe> py solatro/Tools/run_tests.py --timeout 400'
  verification_kind: suite
  status: pending
  evidence: ''
  notes: 'Phase done-when: TP-97 - TP-110 green, plus a by-eye pass at 1, 2 and 3 grids.'
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

## Gaps — sixteen filed, fifteen resolved, ONE OPEN

`design/poker-patience/gaps/GAP-001..009` and `GAP-015..016`, `design/grid-view/gaps/GAP-010..014`.
Answers are quoted verbatim at the top of each and **outrank `PLAN.md` and `NAMES.md`, because they
are newer.**

⚠ **`GAP-016` IS OPEN AND BLOCKS `S28`.** Grid-stepping rides the `SmoothScrollContainer` while
`QR3`=a and `H11`/`H23` put it on the wall's camera. Four options, (d) being the fourth found per
`GAP-014`'s lesson. **Quote its option text to the owner; do not pick one.**
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

- ⚠ **THE SCROLL CONTENT'S OWN ORIGIN CAN SHIFT** as the region around it resizes (measured: its top
  moved -1 -> +7 when the Entrance's reservation changed). The board tracks the FLOOR exactly, which
  is correct — but "the board moved by exactly X" is an identity the layout does not owe, and a test
  asserting one will fail on a board that is behaving. ⚠ **Phase 6 rewrites this path; read it
  first.**
- ⚠⚠ **THE PAN IS THE SCROLLER DOING THE CAMERA'S JOB, AND `S28` OWNS THE RECKONING.** `QR3` = (a):
  *"the wall's camera pans over a wide picture"*. `H11` says "Camera2D limit and smoothing do the
  clamping" and `H23` divides the two mechanisms explicitly — **the camera steps between the 3 grid
  positions, the scroller reveals more of ONE grid, and they never contend because they move
  different things.** `S27` shipped the grid-stepping pan on the `SmoothScrollContainer`. The
  defence is real (there is no `Camera2D` in the play area, and the wide picture is `S31`'s), but
  the citation offered for it — `Q182` — is gated `[QR3=b]` on a branch `QR3`=a pruned, and is
  **unanswered**. Either `S28` migrates the grid-stepping to the camera, or the design's division
  needs an owner ruling. **Do not let `S28` inherit this silently.**
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

1. ⚠ **ANSWER `GAP-016` FIRST — it blocks `S28`, and `S29`/`S30` are built on whatever it decides.**
   Quote its four options to the owner verbatim.
2. **`S28`** once unblocked, then **`S29`**-**`S30`** — keyboard and controller selection across
   grids, refocus when a grid is removed.
3. **Phase 7** — `S31`-`S34`: the wall. ⚠ If `GAP-016` resolves as (a) or (d), `S31` moves ahead of
   the migration, because the wide picture is what a camera pan needs.

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
  5. The gap files: SIXTEEN filed, fifteen resolved, GAP-016 OPEN. Answers are quoted
     verbatim at the top of each and OUTRANK PLAN.md and NAMES.md.
  6. solatro/design/card-effect-api/DESIGN.md - modifiers reach the game only via
     CardModifier.api, and a suite gate enforces it.

GROUND TRUTH BEFORE TRUSTING ANY `done` (see Environment for the import trap on a new box):
    GODOT_BIN="<godot 4.7.2 console exe>" py solatro/Tools/run_tests.py --timeout 400
  Expect ALL 44 SUITES, zero failures. Last verified 3624 CHECKS PASSED.

THE WORK: S26 and S27 are LANDED and committed. GAP-016 is OPEN and blocks S28 -
  answer it before writing any code. Then S28-S30, then Phase 7 (the wall).

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

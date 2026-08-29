# HANDOFF — poker patience

**Goal:** turn Solatro's two-zone tableau into the poker-patience grid game — the engine, then the
board the player sees. Done when a player can deal, place, score, undo and End a show on a grid
they can look at.

**State:** **The engine is complete, the board draws and reacts, the legacy zones are gone, and the
Entrance is PINNED.** A scored grid line fires props; the Entrance stays welded to the bottom of the
window with its slots under their columns while the board scrolls.

Landed: `S1`-`S19`, `S35`-`S37`, `S37b`, `S20`, all of `S20b`, `S20c`, and **`S21`-`S24` — the
board stacks UPWARD off a fixed floor, rows ease into their height, a jump carries the stack above
it, and every row, column and stack shows its score**. Suite green at
**44 suites / 3616 CHECKS PASSED**, console and log agreeing.

**Also landed: tests own the settings they test with** (`S21settings`). `SettingsManager.isolated`
is set run-wide by `all_tests`, so no suite can write `user://settings.tres` — verified
byte-identical after a full run AND after one killed by its timeout. The new **SETTINGS RANGE**
suite sweeps the geometry across each knob's range, so tuning cannot break a test and any value
stays valid.

**`S22` has landed too**: a grid row now EASES into its new height on the reveal's own clock, the
Entrance is row −1 whose own height raises the board, and `_reveal_geometry_exists` is DELETED —
nothing about the reveal is Entrance-only any more.

**`S23` has landed too** — the spring: a jumping card lifts the whole stack above it rigidly, the
board overlaps rather than re-flowing, and a hoop rides the card that actually jumped.

**`S24` has landed**, and with it `GAP-015`'s answer: a row/column bucket is keyed
`(grid, index, height)`, every entry gets a label, and the heights stack in the same order as the
cards beside them. **`S25` closes PHASE 5** — cross-grid row alignment, off by default, proven not
to touch scoring.

**Next is PHASE 6** (`S26`-`S30`: two view modes, zoom, pan, keyboard/controller selection across
grids), then Phase 7 (the wall). Phase 9 is the owner's call; Phase 10 is last.

**Entry docs:** `START_HERE.md`; `design/poker-patience/{PLAN.md,DESIGN.md,TEST_PLAN.md,NAMES.md}`;
`design/grid-view/DESIGN.md` (the view's own design, answered and confirmed);
`design/card-effect-api/DESIGN.md`; `HEADLESS_TESTING.md`.

## Design provenance and gap protocol — COPY THIS BLOCK INTO ANYTHING DERIVED FROM THIS DOCUMENT

Derived from `design/poker-patience/DESIGN.md` version 2 and `design/grid-view/DESIGN.md` version 2.

If you are executing this and you reach a decision the design does not cover:
1. Reversible and clearly within intent → do it, and append one line to `ASSUMPTIONS.md` citing the
   node you were working on. Never silently.
2. Otherwise → **park that thread, file a gap, keep working on unaffected threads, tell the owner.**
3. The design contradicts itself or the code → always a gap, highest priority.
4. ⚠ Two documents disagreeing is NOT automatically (3) — read the answer they are both restating.

File gaps at `design/<slug>/gaps/GAP-NNN.md`, options in the questionnaire grammar. Do not resolve
a gap by picking an answer. Do not delete a gap — it is closed by a new design version.

## Environment — traps that have each cost real time

- Godot here is **4.7.2**; `.claude/memory/machine-profiles.md` now records it per box. ⚠ **A cache
  built by a different Godot build CRASHES the suite** with `0xC0000005` and no banner. Fix:
  `<godot> --headless --path solatro --import`, then re-run. Do that once on a machine you have not
  run the suite on before.
- Suite: `GODOT_BIN=<4.7.2 console exe> py solatro/Tools/run_tests.py --timeout 400` from the repo
  root. Runs WINDOWED, ~90 s, self-quits. **Close the owner's editor first.**
- ⚠ **PARSE-CHECK A TEST FILE BEFORE SPENDING 90 s ON IT**:
  `<godot> --headless --path . --check-only --script <file> 2>&1 | grep <file>`. Real `Parse Error`
  lines name their line number; the trailing `Compilation failed` at the first autoload reference is
  noise this mode always produces. ⚠ **GDScript treats "Variant provided where a subtype is
  required" as a PARSE ERROR** -- `dict.get(...)` and `Array.min()` both return Variant, so assign
  them to a typed local first. Measured: a suite that fails to parse HANGS every suite waiting on
  it, and the run dies on the 400 s timeout with no banner.
- ⚠ **A new `class_name` referenced from an existing script HANGS the suite** rather than failing to
  parse. Symptom: `test_interaction` spinning on `submits_used` against a Nil. Fix: run
  `--headless --path . --import`. Always pass `--timeout` so a hang fails fast.
- ⚠ `export PYTHONIOENCODING=utf-8` before any python heredoc, or the console encoding kills the
  script MID-EDIT and leaves a source file half-written.
- ⚠ **Judge by the failure SET, never the check total** — the total varies run to run. And read the
  log for `SCRIPT ERROR` and check the SUITE COUNT even when the banner says all passed: a suite
  that fails to compile silently drops out (measured: 43 → 41, twice).
- ⚠⚠ **A KILLED SUITE POISONS `user://` AND LATER RUNS THEN HANG WITH NO BANNER.** Suites park the
  real save and the real SETTINGS and restore them at the end; a run killed by `--timeout` never
  reaches the restore, so TEST values become the live `user://settings.tres`. Measured: after
  several timed-out runs the live settings held `act_event_cap = 60` (test_line_detect),
  `booster_reroll_pool = 0` (test_ui_viewers) and `wall_selection_repeat_delay = 0.05`
  (test_wall_input) — and a tree that had been green all session stopped producing a banner at all,
  at an UNCHANGED commit. **Before blaming your own diff for a no-banner run, check
  `user://settings.tres` for test values and `user://run_save/` for a leftover `*.testbak`.**
  The save backup is self-healing (`backup_real_save` restores first); the SETTINGS are not.
- ⚠ **NEVER RUN TWO SUITES AT ONCE, and never background one.** Two Godot processes write the same
  log, and the console banner and the log banner then DISAGREE (measured: console "3465 CHECKS
  PASSED" against the log's "3 FAILED"). Check no `Godot_v4.7.2-stable_win64_console` process is
  alive before starting, and make console and log agree before believing either.
- ⚠ **THE TEST LOG IS `...\Solatro\logs	est	est_output_all.log`.** A file of the SAME NAME sits
  directly under `Solatro\` and is months stale -- it greps clean while the banner reports failures.
  Check the mtime. `START_HERE.md` named the stale path and has been corrected.
- ⚠ **`doc_check.py --changed` is STRICTER than the full run on design-id citations.** Touch an old
  file and it reports the standing backlog as errors in that file. The full run is the gate: it
  reads 0 errors, 7 warnings. Judge a regression by the full run plus a diff check for ADDED ids.
- By-eye rendering: `<godot> --path solatro res://Tests/Visual/reveal_shot.tscn`, writes
  `user://reveal_shots/*.png`. It stands up a REAL `GameView`; it is the only thing that shows the
  board.

## Tasks

⚠ **The stale-step tooling only recognises `S<digits>`.** `designloop/src/gaps.mjs::planSteps()`
reads 23 ids out of this ledger — `S1`–`S19`, `S35`–`S37`, `S20` — and does NOT see the lettered
ones (`S19b`, `S37b`, `S20b1`, `S20b2b`, `S20c`, …). So a gap whose blast radius names a lettered
step will not appear in its stale list. The lettered convention predates this stream and is used in
`PLAN.md` too; renumbering would break the citations in `PLAN.md` and `TEST_PLAN.md`. Check
lettered steps by hand when closing a gap.

```yaml
# --- LANDED. Evidence is in the commit messages; forensics are in the gap files. ---
- id: S1
  description: 'BoardCoord: grid/x/y/h, NOWHERE, ENTRANCE_ROW, two-axis step over an unbounded lattice.'
  status: done
- id: S2
  description: 'GameData grid storage: GridData, the grid list, 25 cell zone cards per grid.'
  status: done
- id: S3
  description: 'Position index extended to grids, plus the reverse index and its invariant.'
  status: done
- id: S4
  description: 'Board mutation API for cells: place, move, remove-with-compaction.'
  status: done
- id: S5
  description: 'CardDataIterator over grids; the early stop REMOVED.'
  status: done
- id: S6
  description: 'Line enumeration: ROW, COL, DIAG (10 directions), HEIGHT_V, within one grid.'
  status: done
  notes: 'LineGeometry._row is already within-one-grid and left-to-right -- REUSE it for prop routes.'
- id: S7
  description: 'ScoringSection gains kind and line_key; score_line loses is_row/zone/index.'
  status: done
- id: S8
  description: 'The mutation broadcast, the explicit compaction flag, and the board lock.'
  status: done
- id: S9
  description: 'The detector card: enumerate, score, re-scan until nothing new completes.'
  status: done
  notes: >
    The runaway guard (act_event_cap, MAX_TICKS) is CORRECTNESS-critical -- there is no
    line-scored memory and no within-pass guard, so a remove-and-replace effect re-scores
    forever without it. Do not tune it away; S35 nearly did.
- id: S10
  description: 'Wire the section into Scoring.PokerHands.score() and the spotlight cascade.'
  status: done
- id: S11
  description: 'Height scoring: multiples of 5, whole stack, drops never score.'
  status: done
- id: S12
  description: 'The three buckets per grid, pack/unpack, duplicate_state hand-copy.'
  status: done
- id: S13
  description: 'grid_score as the product of positive buckets; board_total as their sum.'
  status: done
- id: S14
  description: 'The combo model; MAX_SUBMITS, submits_used, score_additive and patience retired.'
  status: done
- id: S15
  description: 'The meta allotment card (SkillGridAllotment).'
  status: done
- id: S16
  description: 'The grid creator card (SkillGridCreator).'
  status: done
- id: S17
  description: 'TypeInput with on_next removed, and the left-to-right refill.'
  status: done
- id: S18
  description: 'Commit, silent commitment, and the lift when no legal placement remains.'
  status: done
- id: S19
  description: 'THE REBUILD: rules1 becomes the grid game; six suites follow it.'
  status: done
- id: S35
  description: 'Every placement one undo step; scores rewind with the board.'
  status: done
  notes: >
    save_state() is called LAST in place_card_in_grid -- the scores live on `state`, so an
    earlier snapshot rewinds the board without rewinding what it scored. Guarded on
    `not processing` so an effect's placement stays part of the act that caused it.
- id: S36
  description: 'pending_action carries a placement (Entrance SLOT + coord) and replays it.'
  status: done
- id: S37
  description: 'validate() grid aliasing invariants; headless/viewed parity gate.'
  status: done
- id: S19b
  description: 'The legacy coordinate migration -- SUPERSEDED, folded into S20b by GAP-009.'
  status: superseded
- id: S37b
  description: 'The closing pass: adversarial review, /simplify, /docs.'
  status: done
- id: S20
  description: 'CARD_SEPARATION re-derived from the measured bottom-edge pip offset.'
  status: done
- id: S20b1
  description: 'The grid view: %GridContainer, one GridPanel per grid, a CellSlot per cell.'
  status: done
- id: S20b2
  description: 'Old zone frame on cells; grid on top; Entrance aligned beneath; card_scale 2.5 -> 1.'
  status: done
- id: S20c
  description: 'Retire the act: Game.submit, _perform_submit, the on_run_scorer branch, the Next button.'
  status: done
  notes: >
    Game.next()/_perform_next() STAY -- only the BUTTON retired, and _perform_next still serves the
    &"on_next" replay. ⚠ A touch test must run AFTER the mouse tests: a touch leaves no HOVER and
    the mouse selection path needs one.
- id: S20bDraw
  description: 'Fix: _order_board_cards never ordered grid cards, so a card drew BEHIND its own cell.'
  status: done
  notes: 'Found BY EYE, through 43 green suites. _append_grids_row_major mirrors the zone helper.'
- id: S20bRatchet
  description: 'The zone-only test ratchet, and the sentinel gate for BoardCoord.NOWHERE.'
  status: done
- id: S20b2b0
  description: 'BoardCoord gains equals(), pack() -> Vector4i, unpack(), is_nowhere(); null retires.'
  status: done
  notes: >
    The SENTINEL GATE (test_game_headless.gd) is what makes this verifiable: nothing may write
    == / != BoardCoord.NOWHERE, because NOWHERE is a shared instance and a rebuilt sentinel is not
    identical to it. Its needles are built by concatenation or the gate flags its own constant.
- id: S20b2b
  description: >
    THE COORDINATE MIGRATION. slot_center_global takes a BoardCoord; the prop chain rides it; routes
    stay inside one grid.
  status: done
  notes: >
    ⚠ THE RULING THAT UNBLOCKED IT: upper_zone IS the Entrance, and BoardCoord always named that as
    ENTRANCE_ROW -- so _scan_grid_positions indexes Entrance cards and card_at/grid_position_of
    answer for the WHOLE board.
    ⚠ The LOWER zone stays deliberately unmapped. A path that needs it is a real gap.
    Routes REUSE LineGeometry.row_cells, which structurally cannot leave its grid.
- id: S20bPort
  description: 'Tests/UI/test_visual_layers.gd gets real grid coverage; struck off ZONE_ONLY_TESTS.'
  status: done
  notes: 'The suite whose absence let a card draw behind its own cell through 43 green suites.'
- id: S20b4a
  description: 'Delete the LowerZone and MiddleZone rendering; Entrance deliberately untouched.'
  status: done
  notes: >
    Landed alone so the Entrance could move later against ONE renderer. GameData.lower_zone storage
    remains, populated and serialized; nothing renders it. Same for scores_row_lower.
- id: S20b3
  description: >
    The Entrance is a pinned %EntranceStrip outside the board's scroll, x slaved to it, with its
    own vertical scroll and its own card layer.
  status: done
  notes: >
    ⚠ THIRD ATTEMPT, after two backouts. It worked because it ran against a SINGLE renderer -- the
    coordinate migrated at S20b.2b and the zones stopped rendering at S20b.4a. ⚠ **KEEP THAT RULE
    IF THIS AREA IS EVER REWORKED: one renderer at a time.**
    Scene: EntranceStrip (child of PlayArea, OUTSIDE SmoothScrollContainer) > EntranceHTrack >
    EntranceVScroll > EntranceContent > { UpperZone, EntranceCardLayer }.
    ⚠ TWO INDEPENDENT DRAW ORDERINGS: one shared index space across two layers re-queues every
    frame until the stack overflows. Renaming upper_zone -> entrance stays deferred; cosmetic.
- id: S20b4b
  description: >
    Grid equivalents for the reveal and the hoop split; port the 5 PORTABLE fixtures. Split into
    three sub-steps below -- it is too big to verify as one.
  status: in_progress
  notes: >
    Unfinished GAP-012 scope: _row_open_offset -> _row_covers_anything (the reveal) and
    _row_bounds -> PlayArea.row_card_visuals (the hoop front/back split) are still zone-indexed and
    have no grid form. They are why 6 layering tests still sit on the Entrance.
    ⚠ **THE UNIT OF A GRID "ROW" IS THE HEIGHT LAYER `h`, NOT THE CELL ROW `y`.** Two readings
    existed; `_append_grids_row_major` decides between them. It orders grid cards
    `for h: for every cell`, so a HEIGHT LAYER is contiguous in `card_layer` and a row `y` is NOT.
    `_row_bounds` brackets `[first..last]` of the set it is given, so only the contiguous unit is
    bracketable -- and `_row_bounds` already passes `v.h` as the row. The Entrance agrees: its
    `row_z` is a DEPTH within a fanned column, not a screen row.
    ⚠ Only FIVE fixtures are portable -- see the ratchet's own categories.
- id: S20b4b1
  description: >
    The hoop split's grid form: row_card_visuals takes a BoardCoord and answers for a grid height
    layer; _apply_split drops its Entrance-only guard. Unblocks the 3 hoop layering tests.
  files_touched: [solatro/UI/play_area.gd, solatro/UI/prop_layer.gd, solatro/Tests/UI/test_visual_layers.gd]
  verification_command: 'GODOT_BIN=<4.7.2 console exe> py solatro/Tools/run_tests.py --timeout 400'
  verification_kind: suite
  status: done
  evidence: >
    RED (old product code, new test): ALL 43 SUITES, 3490 passed, 3 FAILED -- exactly the expected
    set: `_split_active false`, and both halves stranded past every card (back 25 / front 27 vs
    cards [21,22] and [23,24]). GREEN: ALL 43 SUITES: 3528 CHECKS PASSED, console and log agreeing,
    VISUAL LAYERS 201 -> 204 (the count went UP).
  notes: >
    `row_card_visuals` now takes a `BoardCoord`; the grid branch reads STATE
    (`grids[g].cells[*].datas[h]`) while the Entrance keeps its control walk, because the Entrance's
    fanned columns ARE its structure. `_apply_split`'s Entrance-only guard is gone; the only guard
    left is `is_nowhere()` plus the geometric body-overlap test.
    The three Entrance hoop tests are NOT ported and that is deliberate -- the Entrance is a live,
    differently-shaped half of the board with its own CardLayer, so porting them would delete
    coverage rather than add it. Their stale "BLOCKED ON A GRID PORT" comments are rewritten.
- id: S20b4b2
  description: >
    The reveal's grid form: the open-row key becomes (grid, h) with the Entrance a RESERVED grid
    index (Q6=a); _row_covers_anything / row_open_extra / _row_open_offset take a BoardCoord;
    coord_of_data answers for grid cards. Unblocks the 3 reveal layering tests.
  files_touched: [solatro/UI/play_area.gd, solatro/Tests/UI/test_visual_layers.gd,
    solatro/Tests/Visual/reveal_shot.gd]
  verification_command: 'GODOT_BIN=<4.7.2 console exe> py solatro/Tools/run_tests.py --timeout 400'
  verification_kind: suite
  status: done
  evidence: >
    ALL 43 SUITES: 3489 CHECKS PASSED, console and log agreeing, VISUAL LAYERS 204 -> 209.
    ⚠ The board-wide claims are asserted, not assumed: a grid coord keys `(grid, h)`, the Entrance
    keys the reserved index, a 3-deep grid layer reads as COVERING SOMETHING (it read false for
    every grid before), the deepest layer covers nothing, and a coord naming no grid answers
    instead of erroring. All three reveal fixtures still FIND their targets, so nothing went
    vacuous when their selection loops moved onto the engine index.
  notes: >
    `PlayArea.coord_of_data` is DELETED. `GameData.grid_position_of` already answered for the whole
    board off a revision-keyed index; the control walk it replaced could only ever find an Entrance
    card and was a second, staler answer. Its three test call sites moved with it.
    ⚠ SCOPE LINE. Chart K's row-band GROWTH (a grid cell control actually getting taller, and
    _grid_slot_center_global carrying the offset) is S22's work -- PLAN.md gives S22 "_row_open
    inverted, Entrance at y == -1 pushing the board up". This sub-step ports the KEY and the
    QUERIES so nothing is zone-indexed; it does not ship the un-designed grid band growth.
- id: S21
  description: 'Upward stacks, shared bottom edge, one container per row, the board floor (E7-E11).'
  status: done
  notes: >
    ⚠ **ONE CONTAINER PER ROW** (owner ruling), not a `GridContainer`: a GridContainer gives every
    cell the row's full height, so a cell has nothing to bottom-align against. A row of its own is
    the original zone's shape turned 90 degrees, and cells `SIZE_SHRINK_END` inside it are what keep
    a row's zone cards on ONE y.
    ⚠ **THE CELL'S OWN FRAME IS THE LAST CHILD OF THE SLOT.** It marks the CELL, which sits on the
    row's bottom line and does not rise with the stack. First, it drew a full card ABOVE an occupied
    cell and put frames on the row above.
    ⚠ **THE FLOOR COMES FROM `TopLevelVBox`, VIA `ALIGNMENT_END`** — NOT `size_flags_vertical`, which
    has no slack to align inside. Every panel is bottom-aligned against that one line, and unlike a
    panel it does not move when a stack deepens, so caching it is safe. A per-PANEL rect cache lagged
    a whole depth pitch and slid every row on the board.
    ⚠ **DO NOT REFRESH A RECT CACHE FROM `_physics_process`** if the floor code writes to that rect:
    the board never settles. `_board_floor_y` reads ONE control the floor code does not write per
    frame, which is why it is safe there.
    ⚠ **A TEST MUST WAIT FOR THE GEOMETRY TO STOP MOVING** (`_settle_layout`), not for a frame count:
    a container sorts its children a frame after the rebuild that changed them.
- id: S22
  description: 'A grid row EASES into its height; the Entrance is row -1 and raises the board.'
  status: done
  notes: >
    ⚠ **GROWTH IS TRACKED SEPARATELY FROM THE REVEAL** (`_layer_grown`), sharing its key shape and
    clock but not its semantics: a reveal opens and then CLOSES, and `set_reveal_cards` REPLACES its
    wanted-set every section — growth living there would shrink a row under a card still on it.
    Arrived height is permanent; an entry is erased at 1 and an absent key reads as arrived.
    ⚠ **`Q77`=b RECONCILES WITH TP-87**: the re-derived guard asks whether the STACK has the height
    to contribute, not whether anything sits above it. A row with nothing above it still grows.
    ⚠ **THE VISIBLE STRIP AND THE ENTRANCE'S OWN HEIGHT ARE TWO DIFFERENT NUMBERS.** Making the strip
    track the Entrance's depth re-lays out everything anchored INSIDE it (a prop drifted 4 px, an
    Entrance slot moved 17). The strip stays the player's setting; only the FLOOR clears the real
    height.
    ⚠ **AN EASED ROW HEIGHT CANNOT USE THE REVISION MEMO** — while easing it is a function of time,
    and the memo froze the animation on its first frame. An idle board still takes the cached path.
    ⚠ **ONLY AN ENTRANCE KEY NEEDS THE CONTROL PASS**; a grid row's height is resolved by its own
    containers.
- id: S23
  description: 'THE SPRING: a jump lifts the stack above it rigidly, overlapping rather than re-flowing.'
  status: done
  notes: >
    ⚠ **THE BOARD KNOWLEDGE LIVES IN `PlayArea.jump_card_with_its_stack`**, never in `CardVisual` —
    a card visual cannot know what is stacked on it. Every caller goes through it.
    ⚠ **`Q312`=a COMES FOR FREE**: the lift rides `offset`, INSIDE the card root and invisible to the
    containers, so a springing stack overlaps and nothing re-flows. That is the one place the "rows
    never overlap" rule is deliberately broken.
    ⚠ `anim_spring_lift` omits `anim_jump`'s SCALE PULSE on purpose: the pulse belongs to the card the
    effect is happening to.
    ⚠ A test waiting for a jump to settle must wait for `absf(y)` to fall, not for the sign to flip —
    the descent is TRANS_BACK and OVERSHOOTS.
    ⚠ **A TEST HELPER MUST NOT BE NAMED `run_*`** — that is the registration gate's entry-point
    convention and it will demand the helper be called from `_ready`.

- id: S24
  description: 'Score labels: rows left, columns below, one special label right, height above stacks.'
  status: done
  notes: >
    ⚠ **ONE LABEL PER (LINE, HEIGHT)** — GAP-015's answer. A line's labels are their own VBox built
    exactly like a `CellSlot`, bottom-aligned with `h` rising, so the height-0 score is level with
    the height-0 cards. That ordering is the discriminating case; reversed, the test reads
    `bottom '22' top '11'`.
    ⚠ **THE PANEL AND THE CELL BLOCK ARE NO LONGER THE SAME RECT.** Everything that walks rows goes
    through `_cells_root`, and `_grid_slot_center_global` measures from the CELL block — reading the
    panel put every card a gutter's width off its cell (20 px sideways, 27 px vertically). The
    Entrance x-slaves to the COLUMNS for the same reason.
    ⚠ **THE HEIGHT LABEL IS POSITIONED BY ARITHMETIC IN `card_layer`, NOT PARENTED INTO THE CELL.**
    Inside the `CellSlot` it would add its own height to `_measure_grid_row_height` — the
    arithmetic every card and prop is placed by. Riding `slot_center_global` instead means it
    follows a growth ease, a spring and a reveal for free.
    ⚠ TP-93 is a RATCHET against grid subtotals: it passes trivially and fails the day a panel
    displays one. It proves it can SEE labels before asserting none is a subtotal.
- id: S25
  description: 'Cross-grid row alignment, and the proof it never touches scoring (§1.14).'
  status: done
  notes: >
    ⚠ **THE ALIGNMENT LIVES IN `_measure_grid_row_height` AND NOWHERE ELSE.** Putting it in the one
    function every row height comes from is what keeps it PURELY VISUAL — scoring never reads a row
    height, which is why the same board scores identically either way (`Q251`=b, asserted).
    ⚠ **A SETTING THAT CHANGES GEOMETRY MUST BE PART OF THE ROW-HEIGHT MEMO'S KEY.** It moves every
    row on the board without touching `state.revision`, so a memo keyed on revision alone served the
    pre-toggle answer — measured: a shallow grid stayed at its own 58 where the shared max was 98.
    ⚠ The fixture is UNEVEN on purpose: two grids whose row 0 is the same depth align trivially and
    the two settings would agree, proving nothing.
- id: S21settings
  description: >
    Tests own the settings they test with, and sweep the range (owner ruling). SETTINGS RANGE suite.
  files_touched: [solatro/Scripts/settings_manager.gd, solatro/Tests/Support/test_base.gd,
    solatro/Tests/all_tests.gd, solatro/Tests/UI/test_settings_range.gd,
    solatro/Tests/Wall/test_wall_focus.gd]
  verification_command: 'GODOT_BIN=<4.7.2 console exe> py solatro/Tools/run_tests.py --timeout 400'
  verification_kind: suite
  status: done
  evidence: >
    ALL 44 SUITES: 3586 CHECKS PASSED. `user://settings.tres` is byte-identical after a full run
    AND after a run killed by its timeout -- the damage this fixes.
  notes: >
    Owner ruling: *"tests should have its own settings it tests with over range of possible
    settings values, that way tuning settings wont break tests, and tests that any setting is
    valid."*
    ⚠ **`SettingsManager.isolated` IS SET RUN-WIDE BY `all_tests`, NOT PER SUITE.** Per-suite
    covered only the eleven that call `backup_real_settings()`; `test_line_detect` is not one and
    went on writing `act_event_cap = 60` into the player's file every run. `restore_real_settings`
    deliberately does NOT clear it.
    ⚠ **`use_own_settings()` (a FRESH PlayerSettings) is opt-in and must be called before a suite
    builds anything.** Swapping the resource mid-suite orphans every reference already taken -- a
    live Wall went on reading the settings it captured in `_ready` and two of its checks failed.
    ⚠ A file-existence probe is the WRONG instrument for "did this knob save" once nothing writes
    at all; `test_wall_focus` now counts `settings_changed` instead, which is the mechanism the
    claim was always about.
- id: S20b4b3
  description: 'Port the 5 PORTABLE fixtures off ZONE_ONLY_TESTS.'
  files_touched: [solatro/Tests/Engine/test_fuzz.gd, solatro/Tests/Engine/test_game_data.gd,
    solatro/Tests/Map/test_persistence_fuzz.gd, solatro/Tests/Map/test_run_manager.gd,
    solatro/Tests/Visual/pause_time_spike.gd, solatro/Tests/Engine/test_game_headless.gd]
  verification_command: 'GODOT_BIN=<4.7.2 console exe> py solatro/Tools/run_tests.py --timeout 400'
  verification_kind: suite
  status: done
  evidence: >
    ALL 43 SUITES: 3538 CHECKS PASSED, console and log agreeing; the ratchet's own honesty check
    passes with all five struck off. BOARD FUZZ green at 500 iterations with the grid actions in
    the walk.
    ⚠ THE RATCHET EARNED ITS KEEP: the first run FAILED on test_persistence_fuzz.gd, which had real
    grid coverage but no GRID_MARKER substring. Fixed by indexing `a.grids[g]` in `_diff_grids`
    (natural code), NOT by widening the marker list.
  notes: >
    Each port ADDS grid coverage rather than moving an assertion sideways. test_fuzz: the random
    walk now runs on a board that HAS grids (two, of DIFFERENT shapes -- a square one hides
    width/height confusion) with place/move/remove-cell actions, so validate(), the card census,
    the position index and duplicate_state's remap finally see a grid; board_hash covers grids too,
    or "a rejected move left the board bit-identical" is a claim about half the board.
    test_persistence_fuzz: grids are FUZZED, dimensions included -- a round-trip that dropped
    grid_width would look clean against a hard-coded 5x5. test_game_data / test_run_manager: the
    modifier-carrying card moved from the dead lower zone onto a grid cell, so the backref,
    aliasing and save claims are about a board the player can see. pause_time_spike: burning card
    on a grid cell.
    ⚠ `place_in_cell` lifts a card out of a ZONE COLUMN but NOT out of a deck -- the fuzz has to
    erase it from draw_deck itself or validate() reports the I1 duplicate.
- id: S42
  description: 'CARD_CATALOG.csv: the four axis columns, the seen-flag reset, superseded marks.'
  files_touched: [solatro/CARD_CATALOG.csv, solatro/START_HERE.md]
  verification_command: 'py .claude/tools/doc_check.py'
  status: done
  notes: >
    `Q286`=a added `scope` / `axis` / `needs_height` / `needs_grids`, plus `status` and `source`.
    ⚠ **THE AXIS COLUMNS ARE KEYWORD-DERIVED FROM THE EFFECT TEXT, NOT HAND-JUDGED.** They are a
    filter aid, which is what `Q286` asked for; they are NOT a contract and nothing should branch
    on them. `scope` is the exception -- only `grid-local` and `global` are legal, per the owner.
    `Q284`=b said reset the seen flag only where the premise depended on the tableau. Read all 23
    reviewed rows by hand: exactly ONE qualifies -- **Water**, whose premise is the drop-down
    ("on Next, flows sideways into a shorter column"). Everything else was rank renames, suit
    props or stacking, none of which the grid touched. `Q285`=a marks and never deletes: 3
    superseded (Ring Column, Cascade Scorer, Water), 1 vetoed (The Anarchist, per the
    recommendations), 41 remapped where only the act/Submit/Next TIMING died.
    221 new cards appended from the post-grid CSV (`Q221`=b), 378 rows -> 599.
- id: S43
  description: 'The draft appended, the post-grid effects CSV, the accepted-ideas CSV, blinds.'
  files_touched: [solatro/gam draft.txt, the post-grid curated effects CSV,
    solatro/accepted-ideas.csv, solatro/blinds.csv, solatro/START_HERE.md]
  verification_command: 'py .claude/tools/doc_check.py'
  status: done
  notes: >
    `Q282`=b: the draft's newest block was appended (1451 -> 1494 lines). The repo copy was STALE
    -- the owner had edited two of its last lines on another machine, so the tail was resynced
    rather than duplicated.
    `Q288`=a: `curated effects post grid.csv`, 1457 rows, pre-grid file untouched as its archive.
    ⚠ **THE OWNER'S BAR WAS "AT LEAST 1 ENTRY PER LINE", SO COVERAGE IS MECHANICALLY PROVEN, NOT
    ASSERTED.** Every row's `source` cites the line it came from (`draft:412`, `refs:305-309`), and
    a checker expands the ranges against each file: 980/980 draft, 36/36 braindump, 305/305
    recommendations, 688/688 references, 779/779 design doc -- 2788 non-blank lines, none missed.
    ⚠ A row whose idea already existed gets the second source APPENDED (`draft:67;random:2-17`)
    rather than a duplicate row, or the file would carry the same card three times.
    `Q287`=b: `accepted-ideas.csv`, 185 rows. Its own note predicted this -- **the acceptance
    signal mostly does not exist**, so 157 of 185 are `proposed` and the `evidence` column says so
    per row. Only the catalog's `seen?` column and the pre-grid file's "already added" marker are
    real signals; the random-effects sheet and the recommendations carry none.
    NEW, not in `PLAN.md`: `blinds.csv`, 90 rows, the owner's new category. One row is one blind
    EFFECT (a level draws one, a boss two); `weight` 2 is a heavy negative such as losing a grid.
    ⚠ **EVERY BLIND PAYS FOR PLAYING INTO IT** -- the owner's ruling that a hazard must reward the
    risk, not just be a different level. Asserted: no row has an empty `payoff`.
```

After `S20c`, `PLAN.md` §3 governs: `S21`–`S25` (the flipped board — **this is where cards start
stacking UPWARD**), Phase 6 (zoom, pan, focus), Phase 7 (the wall), Phase 9 (goal-curve refit,
owner's call), Phase 10 (documentation).

⚠ **Phase 10 WAS TAKEN OUT OF ORDER, at the owner's instruction, and only its CSV half.** `S42`
and `S43` are done; `S40` (ARCHITECTURE_REVIEW), `S41` (alternate design docs) and `S44` (the
remaining doc updates) are NOT. The plan's own dependency note — Phase 10 depends on everything
and runs last — still holds for those three.

## Verified vs assumed

- **Verified** - `ALL 43 SUITES: 3538 CHECKS PASSED`, zero failures, console banner and log banner
  AGREEING (see the two-process trap in Environment). `py .claude/tools/doc_check.py`: 0 errors,
  7 warnings (the standing style backlog). Zero design ids in product code.
- **Verified by eye** - `grid_occupied.png` from `Tests/Visual/grid_layer_shot.tscn`: cards cover
  their cells, empty cells still frame, the Entrance strip is welded to the BOTTOM OF THE WINDOW
  with its five slots exactly under the five grid columns, and the scored line fired (38 /
  COMBO x19.0). At 4x on the top row, each hoop ring passes BEHIND the card faces on its upper arc
  and IN FRONT across the lower - a GRID-anchored prop bracketing, which did not happen before.
- ⚠ **Seen in that same shot, NOT from this stream's changes** (grid geometry is untouched; a
  grid's `_row_open_offset` is always 0 while the reveal guard holds): **the occupied top row is
  CLIPPED by the window's top edge.** The grid grows upward and the shot's viewport does not scroll
  to fit. Worth an owner look before Phase 6 does the zoom/pan work.
- ⚠ **Measured, and NOT a defect**: sampling showed 0 of 16 props moving over 90 frames. A HARNESS
  artefact - `run_props` is awaited inside `place_card_in_grid`, so the flight is over before any
  polling loop starts. The score changing is what proves the cascade ran; to watch motion you must
  sample DURING the placement await.
- **Assumed, not checked** - that `card_scale` 1.0 suits every OTHER screen (deck viewer, map, info
  card). Only the play area was looked at.


## The card effect API - a suite gate enforces it

A card modifier may NOT touch `Game`, `GameData` or `Board` directly - everything goes through
`CardEffectApi` as `CardModifier.api`, and a suite gate fails on any direct reference inside a
modifier. ⚠ **Extending the layer (with a `##` comment) is the sanctioned move.** See
`design/card-effect-api/DESIGN.md`.
⚠ The gate matches the substring `"Board."`, so `BoardCoord` passes but `Board.locate_in_cell` would
trip it. The five `PipSuit` subclasses are gated; `PropModifier` is not.

## The three gates a change here must satisfy

1. **Card effect API** (above) - modifiers reach the game only through `api`.
2. **The sentinel gate** - nothing anywhere writes `== BoardCoord.NOWHERE` or `!=`. `NOWHERE` is a
   shared instance and `==` on a RefCounted is IDENTITY, so a rebuilt sentinel is not equal to it.
   Use `is_nowhere()`; compare coords with `equals()`; key dictionaries and `Array.find` on
   `pack()`. Comment lines are exempt, which is how the rule can be written down.
3. **The zone-only ratchet** - `test_game_headless.gd::ZONE_ONLY_TESTS` lists the 6 test files that
   assert against the legacy renderer and never touch a grid. The set may SHRINK, never grow, and
   porting a file fails the gate until its name is struck off, so the list cannot rot.

## Gaps - fifteen filed, fifteen resolved

`design/poker-patience/gaps/GAP-001..009`, `design/grid-view/gaps/GAP-010..014`. Answers are quoted
verbatim at the top of each and **outrank `PLAN.md` and `NAMES.md`, because they are newer.**

- **GAP-010** the Entrance is pinned, x slaved, independently scrollable - ⚠ **read before S20b.3**.
- **GAP-011**=(a) `BoardCoord` keeps one type, gained value affordances - landed.
- **GAP-012**=(c) panels publish their origin on `resized`; `slot_center_global` reads the cache.
  Fully landed: `_row_covers_anything` and `row_card_visuals` both take a `BoardCoord` and answer
  for grids, and neither added a tree read to the anchor path.
- **GAP-013**=(a)+(c) the ratchet and the layering port - both landed.
- **GAP-015**=(a) a row/column bucket is per row/column AND per height, keyed
  `Vector3i(grid, index, height)`; every entry is displayed, heights stacked in card order - landed.
- **GAP-014** NOT A GAP, resolved as a defect: a fourth option existed (name the zone the test
  measures, and stock it). Kept because it was filed correctly and the reasoning matters.

## Owner working agreements

- **Reuse, do not reinvent.** Verbatim: *"reducing duplicate code as much as possible and no
  reinventing existing setups, or using existing engine methods when available."* ⚠ Put it in every
  step brief. Declining reuse is fine ON RECORD, with the reason in the file.
- **The light layer is out of scope.**
- **No design ids in product code** - not in a comment, not in an `@export_group` label. `Tests/` is
  exempt. One leaked (`M5/M6`) and was caught and removed; the count is back to zero.
- **By-eye beats green.** The draw-order defect was found by the owner looking, not by 43 suites.
- **Old tests do not block the rebuild.** Verbatim: *"dont let tests from old version stop you since
  they need to be remade too."*

## Open bugs

- ⚠ **`test_visual_layers.gd` FAILS ITS OWN VACUITY GUARD: the scrolled board barely scrolls.**
  `scrolling really did move the lit card` wants `moved > 20.0` and measures **11.3 px, then 11.5 px
  on a re-run** — reproducible, not flaky. The guard is doing exactly its job: `scrollable` passes
  (the board overflows by *at least* 1 px) while the card it lights travels ~11 px, so the real
  assertion under it — *a light follows its card across a board SCROLL* — is very nearly vacuous.
  ⚠ **Read it as a finding about the BOARD, not about the test:** at `card_scale = 5.0` the play
  area should overflow its container by far more than eleven pixels, and Phase 5 rewrote every
  width in that path. Fix the width before touching the threshold — lowering 20.0 to 10.0 would
  silence the one thing telling you the board stopped being wide.
  Not caused by the Phase 10 CSV work: nothing under `Scripts/`, `UI/`, `Levels/` or `Cards/` reads
  any of those files, and all six design CSVs are `importer="keep"`, so the engine never imports
  them. Verified by grep, not by argument.
- ⚠ **THE SCROLL CONTENT'S OWN ORIGIN CAN SHIFT** as the region around it resizes (measured: its
  top moved −1 → +7 when the Entrance's reservation changed). The board tracks the FLOOR exactly,
  which is correct — but it means "the board moved by exactly X" is an identity the layout does not
  owe, and a test asserting one will fail on a board that is behaving.
- ⚠ **SIX test files still assert only against the legacy renderer, and NONE of them can port.**
  `test_game_headless.gd::ZONE_ONLY_TESTS` is now entirely **MACHINERY** (3 - `test_board`,
  `test_mods`, `test_spotlight`) testing legacy code that is still LIVE (find_data_vec3 has 9
  product callers, get_zone_from_vec3 7, is_data_topmost 7, add_column/remove_column 9), plus
  **ENTRANCE-ONLY** (3) naming `upper_zone`, which IS the Entrance. Any of these leaving the list
  would be a BUG, not progress. A name APPEARING there means a new zone-only test was written.
- ⚠ **`Tools/spotlight_tool.gd` traces no cascade.** PRE-EXISTING: `git log -S place_card_in_grid`
  on it is empty - it has only ever used `move_data_to_coord` into the legacy lower zone.
- ⚠ **`Tests/Interaction/test_interaction.gd:459` is `check(true, ...)`** - a parked check that can
  never fail, unlike the props one which self-unparked. Restore it to assert `game.processing` once
  a placement is a paced, cancellable act.
- **The COMBO label draws over the End button** - visible in `grid_occupied.png`.
- **`skill_scorer_cascade_lower.gd`** is an orphan in production, still a fixture in three suites.
- **`PLAN.md` 1.1 / `TEST_PLAN.md` TP-02 state an arithmetically wrong example** - *"5 columns left
  of (grid 1, x 0) is (grid 0, x 4)"*. At width 5 it is ONE column left. Tests assert the correct
  behaviour; the docs were left unedited.

## Next up

1. **`S26`** - two view modes; the board opens zoomed OUT; clicking a grid zooms in (`H4`, `H6`,
   `H22`). Read `design/grid-view/DESIGN.md` chart `H` first — Phase 6 is all view, and the
   geometry it pans over is now stable.
2. **`S27`**-**`S30`** - Back/Forward intercepted for zoom, the one scroll container, keyboard and
   controller selection across grids, refocus when a grid is removed.
3. **Phase 7** - `S31`-`S34`: the wall.
4. **Phase 9** is the owner's call. **Phase 10's remaining half** is `S40`, `S41` and `S44` — the
   architecture and design-doc rewrites. Its CSV half (`S42`, `S43`) already landed out of order;
   the post-grid curated effects CSV is where any new card idea now goes, and every row there must
   declare `scope` as `grid-local` or `global`.
   ⚠ **`doc_check.py` CANNOT EXPRESS A FILENAME CONTAINING SPACES.** Its reference regex keeps only
   the last space-free run, so spelling that file out in a living doc reports a dangling reference
   to a name that is really just its tail. The name is `Q288`=a verbatim and matches its pre-grid
   sibling, so it stays: the exact spelling lives in `START_HERE.md`'s read-first table, and every
   other doc calls it "the post-grid curated effects CSV". Rename it only if you would rather have
   the references than the recorded name.

### Opening prompt for the next session

```
Continue the poker-patience grid work on branch `poker-patience`.

READ IN THIS ORDER:
  1. solatro/HANDOFF_poker_patience.md - THIS FILE. Its Environment, "three gates" and Open
     bugs sections are the traps; do not rediscover them.
  2. solatro/design/poker-patience/PLAN.md section 3 (S21-S25), section 1 (contracts).
  3. solatro/design/grid-view/DESIGN.md - charts J, K, L, M, N, P.
  4. The gap files: FOURTEEN filed, all resolved. Answers are quoted verbatim at the top of
     each and OUTRANK PLAN.md and NAMES.md.
  5. solatro/design/card-effect-api/DESIGN.md - modifiers reach the game only via
     CardModifier.api, and a suite gate enforces it.

GROUND TRUTH BEFORE TRUSTING ANY `done` (see Environment for the import trap on a new box):
    GODOT_BIN="<godot 4.7.2 console exe>" py solatro/Tools/run_tests.py --timeout 400
  Expect ALL 43 SUITES, zero failures. Last verified 3538 CHECKS PASSED.

THE WORK: S21, then S22 (which deletes PlayArea._reveal_geometry_exists), then S23-S25,
Phase 6, Phase 7.

NON-NEGOTIABLES, each of which caught a real defect on this stream:
  - RED-THEN-GREEN for every new test, and check the red failed the checks you EXPECTED.
    Do the red runs YOURSELF; never accept a self-reported green.
  - VERIFY VISUALS BY EYE. Tests/Visual/grid_layer_shot.tscn shows a POPULATED grid and
    prints card-vs-cell draw indices. A green suite is not evidence about pixels - the owner
    found a card drawing behind its own cell that 43 green suites did not.
  - CHECK THE SUITE COUNT (43) and the failure SET, never the check total, which swings by
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
- `design/poker-patience/DESIGN.md` - the authority on the game's behaviour.
- `design/grid-view/DESIGN.md` - the view's design, its answers and its six charts.
- `design/poker-patience/TEST_PLAN.md` and `NAMES.md` - every planned test; every identifier.
- `ARCHITECTURE_REVIEW.md` - the engine's contracts (undo, pending-action replay, layering).

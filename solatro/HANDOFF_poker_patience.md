# HANDOFF — poker patience

**Goal:** turn Solatro's two-zone tableau into the poker-patience grid game — the engine, then the
board the player sees. Done when a player can deal, place, score, undo and End a show on a grid
they can look at.

**State:** Phases 1-6, 8 and Phase 10's CSV half are landed. **Phase 7 is nearly done**: the wall
packs the game picture at its real width, the HUD follows the camera, `H22`'s camera stepping is
proven end-to-end through a real key route, and `TP-105` exists and is green for the first time.
**The suite sits at 5 failures and every one is attributed** — none is a mystery.

**Entry docs:** `START_HERE.md`; `design/poker-patience/{PLAN.md,DESIGN.md,TEST_PLAN.md,NAMES.md}`;
`design/grid-view/DESIGN.md`; `design/card-effect-api/DESIGN.md`; `HEADLESS_TESTING.md`.
⚠ Flowchart **H is §36 of `design/poker-patience/DESIGN.md`**, not of the grid-view design.

## ⚠ THE FIVE FAILURES, AND WHO OWNS EACH

```
2  GRID LAYOUT  116.0 px card-on-cell, TP-85 mid-growth   CROSS-SUITE INTERFERENCE
3  GRID VIEW    TP-140 precondition, TP-106 x2            GAP-027, owner ruling
```
- ⚠ **GRID LAYOUT ALONE IS `ALL 85 CHECKS PASSED`** with a 0.0 px delta at every height. The
  failures exist only in the full suite. **Deterministic interference reads exactly like a
  deterministic bug** — a constant `116.0` survived five wrong diagnoses before isolation settled
  it. See the settings-isolation entry under Open bugs.
- The three GRID VIEW ones are `GAP-027`: the overview frames exactly ONE grid.

## The board's settled geometry — facts, not open questions

All of this is implemented; the code is the authority. Recorded here only because it is expensive to
re-derive and easy to contradict by accident.

- **The picture is 3 GRIDS wide**, not 3 grid POSITIONS. It used to be 3 positions of 3 grids each —
  nine grids of width to hold three — which is where ~1000 px of empty board between grids came from.
- **The camera KEEPS A STEP inside those 3**: it rests on one grid and steps between them, and
  zooming out is what shows all three. `H22` and `H9` stay literally intact.
- **The gap between grids and the gap at the picture's edge are ONE number**, and it is DERIVED, not
  stored: `PlayArea.isolating_grid_buffer_px()` solves in closed form for the buffer at which a
  FOCUSED grid isolates its neighbours. ⚠ It obtains its coefficients by SAMPLING the real
  `grid_position_size_px()` at two candidate buffers, never by re-deriving its formula — that is what
  stops it drifting from the function it inverts. **Do not replace it with a hand-derived formula.**
- **`focused_board_zoom()` is a closed-form FIXED POINT**, `size.y / (block_h + base_strip)`. It was
  once an order-dependent read that returned different answers depending on how many times the layout
  loop had run. ⚠ **Do not "simplify" it back.**
- **`PlayContainer`'s height tracks `game_picture_design_size().y`**, as its width already tracked the
  design width. The old authored offset capped the play area at 636 px while the picture was 841, and
  every zoom read that height.
- **Entrance and grid cards scale together**; the Entrance is unclipped rather than resized, and the
  board's FLOOR — not the visible strip — tracks the Entrance's real depth. ⚠ Resizing the strip
  itself re-lays out everything anchored inside it and drifts a prop 4-17 px off its slot. That is
  measured, and it has bitten twice.

## Design provenance and gap protocol — COPY THIS BLOCK INTO ANYTHING DERIVED FROM THIS DOCUMENT

Derived from `design/poker-patience/DESIGN.md` v2 and `design/grid-view/DESIGN.md` v2.

Reaching a decision the design does not cover:
1. Reversible and clearly within intent -> do it, append one line to `ASSUMPTIONS.md` citing the
   node. Never silently.
2. Otherwise -> **park that thread, file a gap, keep unaffected threads moving, tell the owner.**
3. The design contradicts itself or the code -> always a gap, highest priority.
4. ⚠ Two documents disagreeing is NOT automatically (3) — read the answer they are both restating.

Gaps live at `design/<slug>/gaps/GAP-NNN.md`, options in the questionnaire grammar. Do not resolve a
gap by picking an answer. Do not delete one — it is closed by a new design version.
⚠ **CHECK FOR A FOURTH OPTION FIRST.** Six gaps here were answered with an option nobody listed,
including `GAP-023`, where the owner replied with a CRITERION (touch-drag feel) that invalidated all
four options as written.

## Environment — traps that have each cost real time

- Godot here is **4.7.2**; `.claude/memory/machine-profiles.md` records the binary per box.
  ⚠ A cache built by a different build CRASHES the suite with `0xC0000005` and no banner — fix with
  `<godot> --headless --path solatro --import`.
- Suite: `GODOT_BIN=<4.7.2 console exe> py solatro/Tools/run_tests.py --timeout 600` from the repo
  root. WINDOWED.
  ⚠ **THE OWNER'S GODOT EDITOR STAYS OPEN — IT HOSTS THE `godot-ai` MCP.** Owner ruling: it "should
  not cause any issues". **Do NOT close it and do NOT ask to.** This SUPERSEDES the older
  "close the owner's editor first" instruction. The one-process rule still binds for GAME and TEST
  processes: never run two of those at once.
  ⚠ **USE 600, NOT 400.** `--timeout` is a GLOBAL wall-clock limit on the whole 45-suite run (one
  Godot process; `run_tests.py` `process.wait(timeout=...)`), and the runner's own default is 600.
  **Warm the run is ~190 s, but COLD — right after the editor closes — it exceeds 400 s** and dies
  with `NO SUITE BANNER`, which reads exactly like a hang. That cost two 400 s runs to rediscover.
  ⚠ A standalone test scene **does not quit after printing its banner** — it idles. That idle is not
  a hang either; read the banner and stop it.
- ⚠ **RUN ONE SUITE ALONE to discriminate interference**:
  `<godot> --path solatro res://Tests/UI/test_grid_layout.tscn --windowed`, ~2 min. This is the
  cheapest discriminating test in the repo and it was overlooked for hours.
- ⚠ **`--check-only --script` IS NOT USABLE HERE** — it fails on unresolved autoloads for every test
  file. **Launch one scene for two seconds instead**; a compile break is instant to see.
- ⚠ **A COMPILE ERROR CASCADES AND NAMES NONE OF ITS SYMPTOMS.** One bad call in `game_view.gd` took
  down `card_data.gd`/`pip_suit.gd` and surfaced as "the map won't start a game" and "cards have no
  pips". ⚠ **Confirm a method EXISTS** (`ClassDB.class_get_method_list`) before calling it;
  `Camera2D.get_global_transform_interpolated()` does not exist in 4.7.2.
- ⚠ **NEVER TWO GAME OR TEST PROCESSES AT ONCE** — console and log banners then disagree. Check
  before every run. ⚠ **Never kill by image name** (a hook blocks it; it has twice closed the owner's
  editor). List `Id, MainWindowTitle`; only `Solatro (DEBUG)` is a harness orphan.
  ⚠ **`Solatro - Godot Engine` is the owner's editor and it is EXPECTED to be running** — it hosts
  the `godot-ai` MCP. Leave it alone; do not stop it, and do not treat it as a blocker.
  ⚠ It uses `Godot_v4.7.2-stable_win64.exe` (GUI); the suite uses `..._console.exe`. Different
  binaries, so both being present is normal.
- ⚠ **Judge by the failure SET and PER-SUITE counts, never the check total.**
- ⚠ **The log is `<user data>/Solatro/logs/test/test_output_all.log`** — a same-named file under
  `Solatro/` is months stale. Check the mtime.
- `export PYTHONIOENCODING=utf-8` before any python heredoc.
- ⚠ **`user://settings.tres` is POISONED with test values and stays that way.** `isolated` suppresses
  writes, so a poisoned file simply persists. A pristine default is recoverable from
  `PlayerSettings.new()`. **Do not overwrite it without the owner.**

## Standing rules this stream paid for — do not rediscover them

**Instruments and evidence**
- ⚠ **BY-EYE BEATS GREEN, and it has caught four defects the suite could not**: the wall squash, both
  label bugs, and a fix whose own purpose-built check passed while the render showed the defect.
- ⚠ **RED-THEN-GREEN IS NECESSARY, NOT SUFFICIENT.** It proves a check responds to a change, not that
  it measures what a player sees.
- ⚠ **THE FIXTURE MUST VARY THE QUANTITY THAT DRIVES THE DEFECT, NOT THE ONE THAT DESCRIBES IT.**
  Uneven card DEPTHS was the symptom; uneven banked score LEVELS was the driver. A zoom bug is
  invisible while a harness never leaves zoom 1.0, because `1.0 * anything == anything`.
- ⚠ **AN INSTRUMENT THAT DUPLICATES PRODUCTION SETUP DRIFTS FROM IT** and then certifies the wrong
  thing. `wall_game_squash_probe` builds its `PictureEntry` from `Wall.load_layout()` for that
  reason. `grid_zoom_shot`/`grid_layer_shot` instantiate `GameView` DIRECTLY and are blind to the
  whole wall composite — that blindness is why the squash passed two by-eye gates.
- ⚠ **A STILL FRAME IS THE WRONG INSTRUMENT FOR ANYTHING WITH A DURATION.** Run it, report what MOVED.

**The board's geometry**
- ⚠ **THE UNIT OF A GRID ROW IS THE HEIGHT LAYER `h`, NOT THE CELL ROW `y`.**
- **ONE CONTAINER PER ROW** (owner ruling). The cell's own frame is the LAST child of the slot.
- **The floor comes from `TopLevelVBox` via `ALIGNMENT_END`.** Do not refresh a rect cache from
  `_physics_process` if the floor code writes to that rect.
- **The panel and the cell block are NOT the same rect.** Everything that walks rows goes through
  `_cells_root`.
- **Cross-grid alignment lives in `_measure_grid_row_height` and nowhere else.**
- **An eased row height cannot use the revision memo** — the memo froze the animation on frame one.
- ⚠ **EVERY SITE THAT ADDS A MEASURED GLOBAL TO A LOCAL SIZE MUST BE ZOOM-AWARE.** Height labels were
  47 px out in focused mode for exactly this reason.
- ⚠ **`custom_minimum_size` IS A FLOOR, NOT A CAP.** A `VBoxContainer` is
  `max(own minimum, sum of children + separations)`, so surplus children push a bottom-aligned
  gutter's rows upward and the error accumulates.
- ⚠ **A VALUE SAFE TO READ PER-FRAME IS NOT SAFE TO CAPTURE ONCE.** `_sync_entrance_x` survives a
  fallback it re-derives every frame; a latched copy was poisoned forever.
- ⚠ **A FRESHLY-ADDED PANEL'S `Cells` NODE EXISTS BEFORE ITS `global_position` IS VALID** — a
  null-check is not enough to know a measured position has settled.

**The view, the camera and the wall**
- ⚠ **THE ARROW READER MUST SIT ON THE CELL'S OWN `gui_input`** — the viewport's focus-neighbour
  search consumes arrows in the GUI pass.
- **The zoom level stack is focused -> overview -> wall**, with Back falling through in the overview.
- ⚠ **THE SCALE MUST LIVE ON THE SCROLL CONTAINER, NOT ITS CONTENT** — a `Container` rewrites its
  children's scale on every sort. **It is not animated**: the scroller clamps every aim against the
  reach it can see that instant.
- ⚠ **`SubViewport.size` LIES WHEN OVERSIZED** — past the GPU cap the framebuffer is destroyed while
  the property still reports what it was given. Assert the pure `clamped_render_size()`.
- ⚠ **THE WALL CAMERA FRAMES A `Sprite2D` OF THE SUBVIEWPORT'S TEXTURE**, not the live scene. So
  camera zoom MAGNIFIES a fixed render target: at the focused `board_zoom` of 1.94 that visibly
  softens the card art, which is why `GAP-024` was answered (b). ⚠ **Zooming OUT minifies and is
  safe**; only magnification costs sharpness.
- ⚠ **`focused_scale()` PICKS ITS ZOOM FROM THE PICTURE'S HEIGHT**, so the camera's visible WIDTH is
  ~1218 px however wide the picture is. No width change widens the view.
- ⚠ **PHYSICS INTERPOLATION FORCES `Camera2D` ONTO THE PHYSICS TICK** while `_process` reads on idle,
  so a sampled position is not the rendered one. This is the open HUD jitter.

**Tests**
- **A test must wait for the geometry to STOP MOVING** (`_settle_layout`), never a frame count.
  ⚠ `_settle_layout` polls the COMPUTED SLOT, not a visual's tween — `_settle_visuals` exists for
  checks that compare an ANIMATED position.
- **A test helper must not be named `run_*`** — that is the registration gate's entry-point rule.
- **A touch test must run AFTER the mouse tests.**
- ⚠ **`use_own_settings()` and `restore_real_settings()` REASSIGN A GLOBAL**; `backup_real_settings()`
  alone does not.

## Tasks

⚠ `designloop/src/gaps.mjs::planSteps()` only sees `S<digits>` — lettered ids (`S31b`, `S33cam`) must
be checked by hand.

```yaml
- id: S1
  description: 'BoardCoord; GridData; the position index; the cell mutation API.'
  status: done
- id: S5
  description: 'CardDataIterator; line enumeration (ROW, COL, DIAG, HEIGHT_V); the section.'
  status: done
- id: S9
  description: 'The detector card, scoring wiring, height scoring, the buckets, grid_score.'
  status: done
- id: S14
  description: 'The combo model; allotment and creator meta cards; TypeInput refill; commit.'
  status: done
- id: S19
  description: 'THE REBUILD: rules1 becomes the grid game; six suites follow it.'
  status: done
- id: S20
  description: 'THE VIEW REPLACEMENT: GridPanel/CellSlot, zone renderers deleted, pinned Entrance.'
  status: done
- id: S21
  description: 'PHASE 5: upward stacks, eased row heights, the spring, score labels.'
  status: done
- id: S26
  description: 'PHASE 6: two view modes; opens zoomed out; a click in the overview ORIENTS.'
  status: done
- id: S27
  description: 'Back/Forward zoom as a level stack; discrete centred panning; edge bounce.'
  status: done
- id: S28
  description: 'The one-scroll-container ratchet; >3 grids shifts which are in frame.'
  status: done
- id: S29
  description: 'Cross-grid arrow selection, the overview grid cursor, touch swipe.'
  status: done
  notes: 'THE SWIPE SHIPPED DEAD AND ITS TESTS PASSED -- prove the ROUTE, not the handler.'
- id: S30
  description: 'Refocus the left survivor on removal; re-centre on EVERY removal.'
  status: done
- id: S31
  description: 'PHASE 7: the picture sized for 3 grids, the height rule, the render clamp.'
  status: done
  notes: 'Covers S31b (focused zoom), S31c (clip), S31d (widen), S31e (one grid per position).'
- id: S33
  description: 'H20 the wall re-packs; H21 Info mode; plus the camera work GAP-024 pulled in.'
  status: in_progress
  notes: >
    H20 LANDED: keep_aspect on the game entry, squash gone, verified by eye. The camera steps in
    OVERVIEW (GAP-024=(b)), the bounce follows it (GAP-025), and the HUD follows the camera.
    REMAINING: H21/TP-119 (Info mode, Q178=(a)), and the HUD jitter.
- id: S35
  description: 'Phase 8: every placement an undo step; pending_action replay; validate() aliasing.'
  status: done
- id: S37
  description: 'The closing pass: adversarial review, /simplify, /docs.'
  status: done
- id: S42
  description: 'PHASE 10, CSV half: CARD_CATALOG axis columns, superseded marks.'
  status: done
- id: S43
  description: 'The curated effects CSV, the accepted-ideas CSV, blinds.'
  status: done
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

## The three gates a change here must satisfy

1. **The card effect API** — a modifier reaches the game only through `CardEffectApi` as
   `CardModifier.api`; a suite gate fails on any direct `Game`/`GameData`/`Board` reference inside
   one. The gate matches the substring `"Board."`, so `BoardCoord` passes.
2. **The sentinel gate** — nothing writes `== BoardCoord.NOWHERE`. `NOWHERE` is a shared instance and
   `==` on a RefCounted is IDENTITY. Use `is_nowhere()`, `equals()`, and `pack()` for keys.
3. **The zone-only ratchet** — `ZONE_ONLY_TESTS` lists the 6 files asserting against the legacy
   renderer. The set may SHRINK, never grow. All six test live legacy machinery; any leaving would
   be a bug.

## Gaps

**Open and genuinely undecided:** `GAP-018` (`grid_swipe_threshold_mm`'s default dead against its own
clamp), `GAP-028`'s `H24` half, `GAP-030` (settings isolation — ruled (b) staged, not yet built),
`GAP-037` (an Entrance column deeper than the render target; owner deferred, *"no limit for now"*).

⚠ **A gap is a DECISION THE DESIGN DOES NOT COVER — not a bug.** If exactly one choice is defensible
it is a defect: fix it, and let the commit be the record. **Do not file a gap for a solved bug or for
an instruction that arrived with its own answer** — a directory of settled items is pure cost to the
next reader, and the code is the source of truth for anything already built.

## Owner working agreements

- **Never commit to `main`** — the owner drives it through GitHub Desktop. **On any other branch
  committing is fine and needs no permission**; one verified step per commit, evidence in the message.
- **Reuse, do not reinvent.** Declining reuse is fine ON RECORD with the reason.
- **The light layer is out of scope.**
- **No design ids in product code** — not in a comment, not in an `@export_group` label. `Tests/` is
  exempt.
- **No comment inside a method body.** A `##` above it says WHY.
- **Online research is allowed and expected** when a blocker may be a misunderstanding of engine
  mechanics. Cite the source; keep "the docs say X" separate from "I measured X here".
- **Old tests do not block the rebuild.**

## Open bugs

- ⚠⚠ **THE SETTINGS-ISOLATION ARCHITECTURE PROBLEM — owns 2 of the 5 failures.**
  `use_own_settings()` and `restore_real_settings()` REASSIGN the global `SettingsManager.settings`;
  `backup_real_settings()` alone does not. Three suites swap it — `SETTINGS RANGE` (chained),
  `GRID LAYOUT` and `WALL FOCUS` (unchained). **The ordering chain only orders its own
  participants**, so a non-participant is unordered against everyone and no chain position helps.
  ⚠ **TWO ATTEMPTS TO SERIALISE VIA `await_siblings_except` DEADLOCKED** (`GRID LAYOUT` ↔
  `SETTINGS RANGE`, then ↔ `GRID VIEW`; identical exclusion lists both times), each costing a 400 s
  timeout. **DO NOT TRY A THIRD SHAPE WITHOUT MAPPING THE WHOLE WAIT GRAPH.** The chain is
  `INTERACTION → UI PROPS → VISUAL LAYERS → GRID VIEW → SETTINGS RANGE → E2E RUN → LEAK CANARY →
  WALL PAUSE`, each excluding everything after it.
  Candidate fixes, none picked: (a) every settings-touching suite joins the chain; (b) stop
  `use_own_settings()` mutating a global; (c) snapshot values rather than swapping the object.
- ⚠ **THE HUD JITTERS DURING A PAN.** It no longer leaves the screen, but its offset oscillates
  ±150-360 px because physics interpolation puts `Camera2D` on the physics tick while
  `GameView._process` reads it on idle. ⚠ **The fix is NOT a smoothing lerp** — that is a second
  easing mechanism chasing the first.
- **Two cosmetic overlaps**: the Deck and Undo draw over the wall shell's Back/Forward/Wall buttons,
  and the skill text is clipped at x~0.
- **~8 px of the focused grid's top row is cut** — the zoom overshoots its window by 7.8 px.
- **`pan_to_grid` measures the scroll container's FULL rect**, aiming ~4 px right of the visible
  window once the vertical scrollbar shows. Deliberately left alone.
- ⚠ **An empty cell's zone card counts as "on a card"** for the drag-vs-pan discrimination. `Q192`=(a)
  read literally; worth an owner ruling if an empty cell should read as empty BOARD.
- **For ~11 frames after a view change, a click on an Entrance card silently does nothing** — the
  card is easing out from under the cursor.
- **`Tests/Interaction/test_interaction.gd:459` is `check(true, ...)`** — a parked check.
- **The COMBO label draws over the End button.**
- **`skill_scorer_cascade_lower.gd`** is an orphan in production, still a fixture in three suites.

## Next up — the queue, in order

### 1. Row score labels sit TOO HIGH on their card
**Owner:** *"score labels should be aligned with bottom of card instead of top of card now that pip
row is on bottom of card"*, then, when asked what should actually differ: *"the label sits too high
on the card."* **The label BAND's position within its row must move** — not text alignment inside it.

⚠ **A previous attempt shipped and was WRONG; it is reverted work, not new work.** Setting
`vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM` is INERT: measured on a real scored label,
`label.size (16,17)` vs autosized text `(14,17)` — **zero vertical slack**, so top and bottom render
identically. Giving it slack via `size_flags_vertical = SIZE_EXPAND_FILL` then broke the pitch match
with the card rows, which is the misalignment the owner reported.

**Do:** revert both of those in `_fill_label_stack` (restores the pitch match), then **MEASURE** the
label band's global rect against its own card's bottom edge and REPORT before moving anything.
⚠ The geometry is not obvious: a card is ~110 px tall but the fan pitch is ~17 px, so a covered card
shows only a ~17 px bottom strip — the same height as the label band.
⚠ **`custom_minimum_size` IS A FLOOR, NOT A CAP** — growing children past the stack's sum pushes a
bottom-aligned gutter's rows upward and ACCUMULATES. That is the owner-reported bug whose FIRST FIX
WAS A FALSE GREEN.

### 2. The Entrance must stack UPWARD
**Owner:** *"entrance cards should also stack upwards too since their pips are on bottom of cards
like all other cards."*

⚠ **NOT a `bottom_anchored := true` flip.** `CardVisual.get_card_control_center()` hangs a
bottom-anchored card from its OWN control's bottom edge, so the grid **reverses control-build order**
— newest card is child 0, the cell's frame card LAST (`_bind_grid_panel`, `update_grid_zone_visuals`).
The Entrance builds header-first, so a naive flip renders the header **upside-down off the top of the
strip**. The real change:
- mirror the grid's reversed-order convention in `set_card_zone` / `update_card_zone_visuals`;
- rewrite `_entrance_slot_center_global` (documented as fanning *"from control tops"*) to measure
  from a FLOOR the way `_grid_slot_center_global` does.

**Owner ruling on the fallout:** the bespoke selected/held highlight in `update_card_zone_visuals`
(Entrance-specific `vbox.get_child(0)`/`get_child(1)` indices) is **DROPPED** in favour of the grid's
own `on_control_focus_entered` widening. ⚠ The highlight's appearance when picking up from the
Entrance WILL change — verify by eye.

⚠ Watch: the known **~11-frame dead-click window** on Entrance cards runs through this code — check
whether it widens. And an upward Entrance stack grows TOWARD the board; confirm it cannot occlude the
grid's bottom row.

### 3. Verify the Entrance transitions smoothly between grids
**Owner note:** *"if entrance is not snapped to a grid, it should smoothly transition between them.
Shouldn't really be an issue though since entrance should be tied to camera or view looking at each
grid first."* Likely already true — `_sync_entrance_x` re-derives X from the board's pan every frame.
⚠ **Verify by RUNNING it** — a still frame is the wrong instrument for anything with a duration.

### 4. The focused grid's clipped top row
Visible in the composite render; the standing note records the zoom overshooting its window by
7.8 px, and it looks worse than that now.

### 5. Settings isolation — the staged migration (a TRUE GAP, see `gaps/GAP-030.md`)
Owner ruled **(b)**, staged: build the injection seam, then migrate the **77 read sites across 22
files** in batches heaviest-first (`play_area` 18, `main` 16, `prop_layer` 11), each batch its own
commit with a full suite between. Clears the last 2 standing failures.

### 6. `H24`'s board-scrolls-within-3 (`GAP-028`)
⚠ Still owes its clipping question and re-opens scroller-vs-camera contention. Expect a follow-up
gap, not an implementer's judgement call.

**Deferred by owner ruling — see `gaps/GAP-037.md`:** an Entrance column deeper than the render
target renders off-screen. *"No limit for now."* Known, not safe; reachability still unmeasured.

## ⚠ Test fixtures that still lay out at OS-window size

`Tests/Support/test_game_view_host.gd` hosts a `GameView` at `game_picture_design_size`, the way
production does. **`test_e2e_run`, `test_leak_canary`, `test_grid_layout` and several
`Tests/Visual/` probes still `add_child(view)` directly**, so they lay out against the OS window.
They pass today and carry the same latent drift that silently broke UI PROPS, VISUAL LAYERS and
INTERACTION once the play area stopped matching the window height.

## ⚠ The GRID LAYOUT interference is NOT fully deterministic

The handoff previously called it deterministic. **Measured otherwise:** `TP-85` PASSED in one run and
FAILED in others within the same tree. The `116.0 px` check is the stable one. Judge that suite by
which checks fail, never by the count alone.

## Known coverage gap — not closed

`TP-113`'s *"camera sees the WHOLE picture within a block's slack"* assertion did **not** go red under
a synthetic span defect, because `WallPicture.focused_scale()` auto-fits whatever `design_size` it is
given. It guards camera-fits-design, **not** span-is-3-grids. Narrow but real; disclosed rather than
hidden.

### Opening prompt for the next session

```
Continue the poker-patience grid work on branch `poker-patience`, in the worktree
gamedev-poker-patience.

READ IN THIS ORDER:
  1. solatro/HANDOFF_poker_patience.md — THIS FILE. Its "settled geometry",
     Environment, "Standing rules" and Open bugs sections are the traps; do not
     rediscover them.
  2. The gap files, for the FOUR still undecided only: GAP-018, GAP-028's H24 half,
     GAP-030 (settings isolation, ruled (b) staged but not built), GAP-037 (deferred).
     ⚠ A gap is a DECISION THE DESIGN DOES NOT COVER, never a bug. Do not file one for
     a solved bug or for an instruction that came with its own answer — the code is
     the source of truth for anything already built.
  3. solatro/design/poker-patience/DESIGN.md §36 — flowchart H.
     ⚠ §36 is STALE against the shipped board: the picture is now 3 GRIDS wide, not 3
     grid positions. Read it with the "settled geometry" section beside it.

FIRST: run the suite. Expect ALL 45 SUITES with 2 FAILED, both the known GRID LAYOUT
cross-suite interference:
    GODOT_BIN="<godot 4.7.2 console exe>" py solatro/Tools/run_tests.py --timeout 600
  ⚠ USE 600, NOT 400 — it is a GLOBAL limit and a COLD run exceeds 400 s, dying with
    "NO SUITE BANNER" which reads exactly like a hang. Warm it is ~190 s.
  ⚠ Close the owner's editor first. ⚠ Never two Godot processes at once.
  ⚠ RUN ONE SUITE ALONE to discriminate interference — GRID LAYOUT alone is 85/85.

A GODOT MCP IS AVAILABLE THIS SESSION. Use it where it beats the shell:
  - editor_screenshot / project_run for by-eye gates, which caught four defects the
    suite missed;
  - logs_read instead of grepping the log file, and note WHICH log;
  - node_get_properties / scene_get_hierarchy to measure a live rect instead of
    writing a throwaway probe;
  - script_patch for surgical edits.
  ⚠ It does NOT replace the rules: no two Godot processes, by-eye still beats green,
  and a compile error still cascades into scripts that name none of the symptoms.

NON-NEGOTIABLES, each of which caught a real defect:
  - VERIFY VISUALS BY EYE, with an instrument that renders the PRODUCT's framing.
    grid_zoom_shot and grid_layer_shot instantiate GameView directly and are blind to
    the wall composite.
  - RED-THEN-GREEN for every new check — and remember it is NECESSARY, NOT SUFFICIENT.
  - THE FIXTURE MUST VARY THE QUANTITY THAT DRIVES THE DEFECT.
  - CONFIRM AN API EXISTS before calling it (ClassDB.class_get_method_list), then
    launch one scene for two seconds. A compile error cascades.
  - MEASURE BEFORE YOU BUILD. Five Phase 7 threads ended blocked on a false premise.
  - NO COMMENT INSIDE A METHOD BODY; no design ids in product code.
  - COMMITS ARE FINE off `main`, one verified step each.

If you hit a decision no document fixes: file a gap, park that thread, keep the others
moving, and QUOTE the gap's own option text to the owner. ⚠ CHECK FOR A FOURTH OPTION —
six gaps here were answered with an option nobody listed.
```

## References

- `design/poker-patience/PLAN.md` — the steps; §1 the normative contracts.
- `design/poker-patience/DESIGN.md` — the authority on behaviour; §36 is chart H.
- `design/grid-view/DESIGN.md` — the view's design and its charts.
- `design/poker-patience/TEST_PLAN.md`, `NAMES.md` — every planned test; every identifier.
- `design/card-effect-api/DESIGN.md` — the modifier boundary the first gate enforces.

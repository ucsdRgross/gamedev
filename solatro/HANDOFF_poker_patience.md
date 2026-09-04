# HANDOFF — poker patience

**Goal:** turn Solatro's two-zone tableau into the poker-patience grid game — the engine, then the
board the player sees. Done when a player can deal, place, score, undo and End a show on a grid
they can look at.

**State:** Phases 1-6, 8 and Phase 10's CSV half are landed. **Phase 7 is nearly done**: the wall
packs the game picture at its real width, the HUD follows the camera, `H22`'s camera stepping is
proven end-to-end through a real key route, and `TP-105` exists and is green. **The suite sits at 2
failures and both are attributed** — neither is a mystery.

**Entry docs:** `START_HERE.md`; `design/poker-patience/{PLAN.md,DESIGN.md,TEST_PLAN.md,NAMES.md}`;
`design/grid-view/DESIGN.md`; `design/card-effect-api/DESIGN.md`; `HEADLESS_TESTING.md`.
⚠ Flowchart **H is §36 of `design/poker-patience/DESIGN.md`**, not of the grid-view design.

## ⚠ THE NINE FAILURES, AND WHO OWNS EACH

```
2  GRID LAYOUT  116.0 px card-on-cell; TP-85 mid-growth flake   INTERFERENCE, unexplained
6  GRID VIEW    TP-139, TP-140 x2, TP-141, TP-101 x2            GAP-038 + GAP-039, ONE question
1  GRID VIEW    the framing gate's Entrance half                right edge only now
```
⚠ **`TP-141` AND THE SECOND PAN CHECK ARE THE HUD RESERVE**, not a new defect: centring the board in
what the HUD leaves shifts it right by half the reserve, which pushes the left neighbour further
into frame. `GAP-038`'s centring and `GAP-039`'s isolation are the same quantity and **cannot be
closed separately.**
- ⚠ **GRID LAYOUT ALONE IS `ALL 89 CHECKS PASSED`.** `116.0` exists only in the full suite and is
  UNMOVED by the `CardVisual` scale fix, so it is a different mechanism and genuinely open. `TP-85`
  comes and goes.
- **The four `GRID VIEW` geometry failures are `GAP-039`, and they are the owner's own rulings
  landing.** The card-row buffer takes `S` from 367 to 510, which puts the isolating picture width
  at 2029 against the 1512 that "exactly three grids" allows — a **517 px** gap nothing can close.
  ⚠ `TP-139`'s WORDING is now wrong, not just its value: the board's window also holds the panel's
  gutter, the two buffers and the scroller's band, so block == window is no longer the definition of
  the focused fit. **Rewriting a planned row is a gap, not an implementer's call.**
- The framing gate's Entrance half fails on left/right ONLY — the strip spans the picture's full
  width while the camera crops 14.66 px a side. Top and bottom are inside. The cell-block half
  passes.

## ⚠ THE FOCUSED VIEW'S HEIGHT, AS IT NOW STANDS

`PlayContainer` **fills the view** (anchors, no code — `_apply_play_container_height()` is gone), so
it is the window's own height in the wall and in a bare `game_view.tscn` alike. That scene was
unplayable before: the container was forced to the picture's 841 in a 651 px window, so the board
hung below the screen with the Entrance under it.

```
focused_board_zoom = min(height fit, width fit)
height denominator = block + panel gutter + Entrance strip + 2 x edge pad + scroller band
```
- `board_edge_pad_rows` (PlayerSettings, default **1.0**, **0 == off for a phone**) — the clear band
  above the board and below the Entrance, in CARD ROWS, scaled with the board.
- `_panel_gutter_h()` — the column-label row and its gap, 27 px. ⚠ **MEASURED FROM THE PANEL**: the
  label's height is FONT-derived and no constant produces it. Taken as the difference of two MINIMUM
  sizes, which a container answers from its children on demand — no stale rect — and subtracting the
  cells' own minimum takes the stacks' DEPTH back out, so a deepening stack cannot re-scale the
  board.
- `_scroller_frame_h()` — the 8 px band the scroller keeps for its horizontal bar.

⚠ **BOTH SCROLLBARS ARE `SCROLL_MODE_SHOW_NEVER`, AND SIZING ALONE COULD NOT DO IT.** Measured: the
vertical bar shows at EXACT equality of content and page — hidden at 1152x648, shown at 1147x649,
both reading `313 == 313`. Any fit is a coin toss between two widths five pixels apart.
⚠ **SHOW_NEVER HIDES A BAR AND KEEPS ITS BAND**, which is why `_scroller_frame_h()` still exists.

**Verified by eye and by measurement at 1147x649, 1152x648, 1920x600, 800x480 and 412x892:** no
scrollbar, the whole 5x5 block and the Entrance row inside the window, a card-row buffer at each end.
⚠ `DisplayServer.window_set_size` CANNOT go below the project minimum — asking for 412x892 returns
1152x2494 — so `Tests/Visual/standalone_view_shot` hosts the view in a SubViewport of the size under
test. A sweep driven through the real window silently tests one size four times.

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

## ⚠ A CONTROL-LOCAL LENGTH IS NOT A GLOBAL ONE — the rule that cost the most this stream

`CardVisual` read a control's rect as `global_position + Vector2(size.x/2, size.y - card_h/2)`.
`global_position` carries every scale above the control — **the board's zoom lives on the scroll
container** — while `size` and `card_size` never do. Measured, one row at depths 3/1/0/5/2 at
`board_zoom` 2.2916: **69.74 px of spread across that row's zone cards**, and exactly **0.00 at
zoom 1.0**. Fixed by scaling the control-local offset by the control's own global transform scale.

⚠ **THE CONTAINERS WERE ALWAYS RIGHT.** Every occupied slot's frame control sat on one line and the
empty cell's full-card control ended there — `SIZE_SHRINK_END` on the slot does exactly its job.
Only the card drew somewhere else. **Do not go rewriting the layout tree for this class of bug.**

⚠ **THE SAME MIXTURE IS LATENT EVERYWHERE.** It was in `TP-103` and in 22 checks across
`GRID LAYOUT`, `VISUAL LAYERS` and `SETTINGS RANGE`, invisible while the board only ever rested
unzoomed. **Read a control's drawn rect as `get_global_transform() * Rect2(Vector2.ZERO, size)`,
never from `position` and `size` directly.**

⚠ Two things MEASURED AND FALSE, so nobody re-runs them: `on_control_focus_entered`'s
`custom_minimum_size` writes are INERT (`set_card_zones_visuals()` overwrites them in the same
call — every rect identical before and after a real hover), and this is NOT a container-stretch
problem.

⚠ **Residual, measured and open:** the frame line sits 19.4 px below the h 0 card where the
arithmetic says one separation (9.2 px) — the control tree's row bottom and
`_grid_slot_center_global`'s disagree by ~10 px. Same family as the standing `116.0 px` check.
`Tests/Visual/zone_drift_probe` is the instrument.

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
`GAP-037` (an Entrance column deeper than the render target; owner deferred, *"no limit for now"*),
`GAP-038` (the HUD-scales-with-the-picture ruling contradicts the board's own units — the whole
HUD-and-offset pass is parked on it), `GAP-039` (isolation, exactly-three and no-clipping are
mutually unsatisfiable — **the clipping IS the slack**).

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

## ⚠ PHASE 7 PROGRESS — 4 of 9 done-when rows green

`PLAN.md` Phase 7's done-when is **`TP-105` and `TP-113`-`TP-120` green**, plus
`knobs_this_preview_does_not_drive` still empty.

```
TP-105 ✅  TP-113 ✅  TP-114 ✅  TP-118 ✅
TP-115 ❌  TP-116 ❌  TP-117 ❌   -- S32: the saved pan and resting_state() (H18, H19)
TP-119 ❌                        -- S33's H21 half: Info mode (Q178=a)
TP-120 ❌                        -- S34: Tools/wall_editor.tscn drives every wall knob (Q186=a)
```

**Three steps close the phase: `S32`, the remainder of `S33`, and `S34`.**

⚠ **MOST RECENT WORK WAS OWNER-DIRECTED REFINEMENT, NOT PLAN STEPS.** The 3-grid canvas, the derived
buffer, the edge margin, `PlayContainer`'s height, Entrance scaling and clipping, label alignment and
scroll-to-bottom are all real and all landed — but **none of them is a plan step and none closes a
done-when row.** That is the whole explanation for effort spent versus phase progress. Anyone
resuming should know the phase closes via `S32`/`S33`/`S34`, not via more refinement.

## ⚠ Zone cards — two rules that are easy to violate

**Owner:**
> *"stacking cards on a zone should not cause the zone to move relative to grid."*

> *"zone cards are not technically part of the board data wise to prevent cards looking below
> themselves and seeing a zone card, so that zones are never interactable outside of UI, which is how
> zones worked before grid and should still work that way now."*

- **A zone does not move when cards stack on it.** The stack grows; the zone stays put relative to
  its grid. ⚠ This is the same failure shape as the Entrance strip: *resizing the thing that holds
  cards re-lays out everything anchored inside it.* Do not let a deepening stack move its zone.
- **Zone cards are NOT board data.** A card must never look below itself and find a zone card, and a
  zone is **never interactable outside the UI**. This is how zones behaved before grids and must keep
  behaving. ⚠ Anything that walks a cell's stack — the iterator, the line detector, `validate()`,
  undo — must not see a zone card as an occupant.

## The runtime leak was the SENTINEL missing an owner — SOLVED, and the trap it left

Kept only because the wrong premise is written down in several places and is expensive to fall for
again. `Game._debug_history` holds a FULL `to_saveable()` duplicate per placement; the sentinel
walked `save_history` and never that, so the first commit of every fresh show read as an entire
leaked board — 25 cell zone cards, 5 Entrance slots, the deck and rules around them. `Game` now
publishes `debug_snapshots()` and the sentinel walks it.

⚠ **"UNREACHABLE BUT ALIVE" DOES NOT IMPLY A CYCLE.** A `RefCounted` also stays alive on a plain
strong reference the reachability scan does not FOLLOW. The cycle premise sent the previous session
hunting an architectural loop that does not exist; the persistent-rules-card hypothesis
(`ZoneAdder.card_data` / `SkillGridCreator.grid_data`) was also tested and is FALSE — zero cards
attributed to either.

⚠ **A RESUMED SHOW CANNOT SEE IT.** `_resume_show()` sets `_debug_history` FROM `save_history`,
sharing objects the sentinel already walks, so only a FRESH show commits a duplicate. One sample of
the wrong show says there is no problem.

`Tests/Visual/leak_holder_probe` is the instrument: it names a holder for every unreachable card and
samples five settled checks, so a transient cannot pass as a leak. Its last stage deliberately drops
the run doc while a local still holds it — a synthetic leak that must stay visible, which is what
proves a sentinel fix taught it an owner rather than blinding it.

⚠ **THE SUITE'S ABSOLUTE UNREACHABLE COUNT IS MEANINGLESS.** Every suite abandons cards on purpose,
so `LeakSentinel.tick() == 0` passes alone and fails by 143 in the full run. Assert the PROPERTY —
no card a known owner holds may read as unreachable.

## ⚠⚠ THE FOCUSED VIEW'S GEOMETRY IS PARKED ON `GAP-038`

**Four owner rulings — the HUD scales with the picture, `PlayContainer` returns to its authored
height, the board is offset by the HUD's rectangle, and the focused view frames the 5x5 block plus
the Entrance — CANNOT ALL BE BUILT AS WRITTEN.** Two measurements settle it, both on the product's
own path:

- **The board lays out DIRECTLY IN PICTURE PIXELS.** `play_area.size` is `(1495, 841)`, the
  picture's design size exactly, and the cell block is `216x286` at `board_zoom` 1.0. Every board
  quantity is in those units and `game_picture_design_size()` IS their span, so scaling `SceneRoot`
  by 1.2977 renders a 1495-wide span at **1940 px inside a 1495 px picture**.
- **Reverting `PlayContainer`'s height regresses `TP-140`.** `GRID VIEW` alone goes 1 failure -> 3,
  both halves of `TP-140` red. The derived buffer sits EXACTLY on the isolation boundary
  (`2.2916 x (211.75 + 108) = 732.7` against a visible half-width of `732.8`).

⚠ **Do not re-derive either of those.** Read `gaps/GAP-038.md`; it carries the four options and
what any answer must not break.

### The clipping is NOT separable, and it is NOT a margin bug — see `GAP-039`

⚠ **THE EARLIER READING HERE WAS WRONG AND IS CORRECTED.** `focused_scale()` does apply
`wall_overfill_margin` (1.02) to a picture that already matches the window's aspect, and that is
the mechanism — but removing it does not fix anything, because the margin is what ISOLATES a
focused grid's neighbours. Three shipped contracts are mutually unsatisfiable:

```
exactly three (TP-113, Q166=a)   W < 7B = 1512
no clipping                      z = W*r / (m*S)          m = the camera's crop
isolation (TP-140)               z*(b + B/2) >= W/(2m)
substituting, W AND m BOTH CANCEL:  b >= S/(2r) - B/2 = 218.22  ->  W >= 1520.89
```

⚠ **`m` CANCELLING IS THE FINDING. THE CLIPPING IS THE SLACK** — the board is sized to the
PICTURE's height while the camera shows less, and that overshoot is the only reason isolation fits
inside "exactly three". Size the board to what the camera really shows and the margin stops helping
at all.

Measured at both corners on the product's own path, not modelled:

```
W=1495 shipped        isolation OK, exactly-three OK, block top cut 5.28, Entrance 11.28, sides 14.66
W=1536 aspect-exact   isolation OK (all four TP-140), block fully framed, sides 0.00,
                      TP-113 red: "1536.0 px, four grids span 1530.0 px"
```

`GAP-039` carries four options and shows the deciding question is narrow: `entrance_visible_rows`
defaults to **1.5**, so the strip is 81 px where one card row is 54, and that 27 px is the whole
difference between infeasible and comfortable. At `S = 340` a `1440x810` picture satisfies all
three with nothing else moving.

⚠ **THE GATE IS `run_the_focused_view_frames_the_block_and_the_entrance_test` IN `GRID VIEW`**, and
it is red on purpose. It asserts against the CAMERA's own visible rect — the right target, because
two scales stack — and names the clipped EDGE rather than a worst case.

## ⚠ THE BY-EYE INSTRUMENT IS FIXED — USE THE NEW ONE

`Tests/Visual/focused_pose_probe` boots the REAL `res://Levels/main.tscn` and enters a show through
`Main.enter_game()`, so the camera pose, the grid count and the board zoom are the product's. It
reports both stacked scales in ONE coordinate system (the picture's design units) and names the
clipped EDGE and the pixels. **Verified by eye against the owner's own report**: top row cut,
Entrance barely in frame.

```
OUT_PATH=<path> <console exe> --path solatro res://Tests/Visual/focused_pose_probe.tscn
      knobs: WINDOW=<w>x<h> (default 1152x648), GRIDS=<n> (default: whatever the deck gives)
```

⚠ **`wall_game_squash_probe`'s framing is still not the product's** — it hand-builds the camera pose
and forces THREE grids where the default deck yields ONE. It carries a warning header now, and it is
still the right instrument for the wall composite and the `GAP-024` magnification measurement.

⚠ **`size` IS NOT THE RENDERED SIZE inside the focused board.** The zoom is a scale on the SCROLL
CONTAINER, so a cell block keeps its authored `216x286` while drawing 2.29x that, and
`global_position` already carries the scale. A rect built from position and size is right in one
corner and wrong in the other. That mixture was latent in `TP-103` and in 22 checks across
`GRID LAYOUT`, `VISUAL LAYERS` and `SETTINGS RANGE`, invisible while a one-grid board opened at
zoom 1.

## Next up — the queue, in order

### 1. Row score labels — MEASURED, not yet moved
The wrong fix (`SIZE_EXPAND_FILL` + `VERTICAL_ALIGNMENT_BOTTOM`) is reverted and the pitch match is
back. Measured with `uneven_stack_score_shot`, overview, card 54 px tall, fan pitch 20 px:

```
row 0, scored     BAND y 402.0..418.0  h 16.0   card y 402.0..456.0   PIP ROW y 442.0..452.0
band centre - pip centre = -37.0 px at EVERY scored band, every height
```

The band occupies the card's TOP 16 px while the pips sit 40..50 px down from the card's top. It
must come DOWN 37 px at `card_scale` 1.0 for its centre to meet the pip row's.

⚠ **The move is not a per-label property.** Every label in a stack shares one pitch, so shifting the
band means shifting the whole stack against a `VBoxContainer` whose `custom_minimum_size` is a FLOOR
and not a cap — the accumulation trap whose first fix was a false green.
⚠ That probe's FOCUSED figures are unusable: it reads `card_size_play`, which does not carry
`board_zoom`, while `slot_center_global` does. Only its overview numbers are sound.

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

### 4. Settings isolation — the staged migration (`gaps/GAP-030.md`)
Owner ruled **(b)**, staged: build the injection seam, then migrate the **77 read sites across 22
files** in batches heaviest-first (`play_area` 18, `main` 16, `prop_layer` 11), each batch its own
commit with a full suite between. Clears the last 2 standing failures.

### 5. `H24`'s board-scrolls-within-3 (`GAP-028`)
⚠ Still owes its clipping question and re-opens scroller-vs-camera contention. Expect a follow-up
gap, not an implementer's judgement call.

**Deferred by owner ruling — see `gaps/GAP-037.md`:** an Entrance column deeper than the render
target renders off-screen. *"No limit for now."* Known, not safe; reachability still unmeasured.

## ⚠ THE LAYOUT SUITES ARE PINNED TO THE OVERVIEW, AND THAT IS A COVERAGE GAP

With one grid the show now opens FOCUSED, so the product's DEFAULT board is zoomed. That put 22
checks red across `GRID LAYOUT`, `VISUAL LAYERS` and `SETTINGS RANGE` — every one measuring a gap
from global positions (which carry `board_zoom`) against a pitch computed from settings (which never
does). Those suites assert the board's LAYOUT ARITHMETIC and were written at the overview's scale, so
their fixtures now latch the opening view and reset to the overview: exactly the state they had.

⚠ **They therefore no longer cover the product's default state.** The zoomed board is `GRID VIEW`'s
subject and the focused-pose probe's. Fixing those 22 to be zoom-aware would be strictly better and
is not done.

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
C:\Users\khanr\Documents\GitHub\gamedev-poker-patience. Do NOT create a worktree.
Committing on this branch is fine and needs no permission: one verified step per commit,
evidence in the message.

READ IN THIS ORDER
  1. solatro/HANDOFF_poker_patience.md -- THIS FILE, in full. Its "settled geometry",
     "Standing rules", Environment and Open bugs sections are traps that each cost real
     time. Do not rediscover them.
  2. solatro/design/poker-patience/PLAN.md -- ACTUALLY READ IT, at least 0-1.13 and 2.
     A previous session ran for a long time having only grepped it, and missed that 1.8
     fixes the pip row at y 13-23 with the card bottom at 27 -- which decides where
     score labels belong.
  3. solatro/design/poker-patience/TEST_PLAN.md -- its rules section and the row table.
     Every step owes named TP rows; dropping a planned row is a gap, not a judgement
     call. Rows marked E are BY-EYE and need the OWNER to sign them off, not you.
  4. DESIGN.md 36 (flowchart H) when you need it. It is the authority on behaviour.

FIRST, BEFORE ANY CODE -- run the suite:
    GODOT_BIN="C:\Users\khanr\Desktop\Godot_v4.7.2-stable_win64_console.exe" py solatro/Tools/run_tests.py --timeout 600
  EXPECT: ALL 45 SUITES, 2 FAILED -- GRID LAYOUT's 116.0 px and its flaky TP-85, both
  known cross-suite interference. GRID LAYOUT ALONE is 85/85; never chase them.
  GRID VIEW's TP-112 is a known timing flake (samples mid-move, lands 0.1-0.3 px from
  at-rest) and may or may not fire.
  ! USE 600, NOT 400 -- it is a GLOBAL limit, and a COLD run exceeds 400 s and dies with
  "NO SUITE BANNER", which reads exactly like a hang. Warm it is ~190 s.
  ! Judge by WHICH checks fail, never the count. Totals wobble 3835-3865.
  ! The owner's Godot editor stays OPEN -- it hosts the MCP. Leave it alone. The
  one-process rule binds GAME and TEST processes only. Never kill by image name or a
  Get-Process|Where-Object pipeline (a hook blocks it); stop a verified
  "Solatro (DEBUG)" orphan by explicit -Id. Agents repeatedly left 3-4 running.

THE TREE IS CLEAN at a verified-green commit. Nothing is half-applied.

THE GEOMETRY PASS IS PARKED ON GAP-038 -- DO NOT RESTART IT
  The four owner rulings (SceneRoot scales, PlayContainer returns to its authored height,
  the board is offset by the HUD rectangle, the focused view frames 5x5 + Entrance)
  cannot all be built as written. Two measurements settle it and BOTH ARE RECORDED:
  the board lays out directly in PICTURE pixels (play_area.size == the design size, so
  scaling SceneRoot renders a 1495-wide span at 1940 px inside a 1495 px picture), and
  reverting PlayContainer's height takes GRID VIEW from 1 failure to 3 with both halves
  of TP-140 red. Read gaps/GAP-038.md and take the owner's answer; do not re-measure.
  ! The CLIPPING has a separable cause the gap records and none of the four options
  fixes: focused_scale() applies wall_overfill_margin 1.02 to a picture that already
  matches the window aspect, costing 8.28 px top and bottom. That is the clipped top row.
  Fixing it moves isolating_grid_buffer_px() too -- one change, not a deletion.

THE BY-EYE INSTRUMENT IS FIXED
  Tests/Visual/focused_pose_probe boots the real main.tscn and enters through
  Main.enter_game(), and it reproduces the owner's report. Use it, not
  wall_game_squash_probe, for any framing evidence.

THE FRAMING GATE IS RED ON PURPOSE -- GAP-039
  GRID VIEW's run_the_focused_view_frames_the_block_and_the_entrance_test asserts
  the 5x5 block and the Entrance sit inside the CAMERA's visible rect. It fails by
  5.28 px at the top and 11.28 at the bottom. Do NOT fix it: isolation,
  exactly-three and no-clipping are mutually unsatisfiable and THE CLIPPING IS THE
  SLACK -- read gaps/GAP-039.md and take the owner's answer. The aspect-exact fix
  was built, measured on both corners, and reverted.

A CONTROL-LOCAL LENGTH IS NOT A GLOBAL ONE
  global_position carries the board zoom (it lives on the scroll container); size
  and card_size never do. That mix put 69.74 px of spread across one row's zone
  cards at zoom 2.29 and exactly 0.00 at zoom 1.0, which is why it survived. Read a
  control's drawn rect as get_global_transform() * Rect2(Vector2.ZERO, size), never
  from position and size directly. The CONTAINERS were always right.

THE RUNTIME LEAK IS SOLVED -- AND ITS PREMISE WAS WRONG
  It was the SENTINEL missing an owner, not a reference cycle: Game._debug_history
  holds a full to_saveable() duplicate per placement and nothing walked it, so the
  first commit of every FRESH show read as a whole leaked board (90 cards, sustained).
  ! "Unreachable but alive" does NOT imply a cycle -- a RefCounted also stays alive on
  a plain strong reference the scan does not FOLLOW. That premise cost a session.
  ! The suite's absolute unreachable count is meaningless (every suite abandons cards
  on purpose); assert the PROPERTY instead. Instrument: Tests/Visual/leak_holder_probe.

THEN, in order
  1. Row score labels. The wrong fix is already reverted and the band is MEASURED: it
     sits 37 px above the pip row's centre at card_scale 1.0, occupying the card's top
     16 px while the pips sit 40..50 px down. Moving it is a whole-stack shift against a
     VBoxContainer whose custom_minimum_size is a FLOOR, not a cap.
  2. The Entrance stacks upward. ! NOT a bottom_anchored := true flip -- the grid
     REVERSES control-build order, and the Entrance builds header-first, so a naive flip
     renders the header upside-down off the top of the strip. Full roadmap is in this
     file's queue section.
  3. GAP-030 (settings migration, staged (b)); then GAP-028=(c).
  4. If the goal is to CLOSE PHASE 7 rather than refine, do S32/S33/S34 -- see "WHERE THE
     PHASE ACTUALLY IS" below. The refinement queue is separate work and the owner should
     be told which one you are doing.

A REVERTED FIX IS PARKED, NOT LOST
  The floor fix (a grown TopLevelVBox drags _board_floor_y into the Entrance, making a
  placed bottom-row card invisible) was reverted to restore a working build, and is
  preserved as a patch in an earlier session's scratchpad (S55_floor_fix.patch).
  ! DO NOT RE-APPLY IT UNCHANGED: its _stick_board_scroll_to_bottom() wrote
  scroll_vertical every physics tick against a SmoothScrollContainer that animates its
  own position -- two writers on one observable, and the likely cause of a scrollbar
  that renders but will not move. The DIAGNOSIS is sound and worth keeping: the grown
  content hangs below the scroll container's window, present in world space (so a
  global-position probe reads fine) but clipped from the render.

GAPS -- THE POLICY
  A gap is a DECISION THE DESIGN DOES NOT COVER. It is NOT a bug, and NOT an instruction
  that arrived with its own answer. 11 files were deleted for being one of those.
  Owner: "code should be source of truth... bugs should never be recorded if they are
  already solved, since all they do is waste time for future readers."
  Only FIVE remain open: GAP-018, GAP-028's H24 half, GAP-030, GAP-037, GAP-038.

NON-NEGOTIABLES, each of which caught a real defect here
  - MEASURE BEFORE YOU BUILD, and say whether a number is measured or inferred. Five
    premises died on contact with a measurement in one session, several of them the
    overseer's own arithmetic.
  - RED-THEN-GREEN for every check, and confirm the red failed the checks you EXPECTED.
    Neutralise the BEHAVIOUR, not the test -- and neutralise the site that owns the
    failing checks: one agent neutralised the wrong fixture and read all-passed.
  - THE FIXTURE MUST VARY THE QUANTITY THAT DRIVES THE DEFECT. A harness sitting at the
    default card_scale cannot see a bug that only appears at a larger one.
  - ASSERT ON OBSERVED GEOMETRY, never on a recomputation of the formula under test.
    ! A global-position assertion CANNOT see render clipping.
    ! A GLOBAL POSITION PLUS A LOCAL SIZE IS NOT A GLOBAL RECT once the board is zoomed:
      global_position carries board_zoom and size never does. That mixture was latent in
      TP-103 and in 22 checks across three suites.
  - CONFIRM AN API EXISTS (ClassDB.class_get_method_list) before calling it; Godot is
    4.7.2. A compile error CASCADES and names none of its symptoms.
  - NO COMMENT INSIDE A METHOD BODY. NO DESIGN IDS IN PRODUCT CODE (Tests/ is exempt) --
    three agents leaked these and they had to be stripped by hand.
  - A tunable literal in a source file is a defect, even when it looks like an epsilon.
  - If a probe mutates settings, use `isolated`. One poisoned user://settings.tres and
    caused a spurious 23-failure run.
  - DO NOT DELETE A COMMENT THAT RECORDS A MEASURED CONSTRAINT. One agent deleted the
    "resizing the strip re-lays out everything anchored inside it (4 px)" comment and
    reproduced that exact 4.00 px drift within one suite run.
  - BACKTICKS DIE INSIDE `py -c "..."` FROM THE BASH TOOL -- bash command-substitutes
    them and silently empties the text. Use a heredoc or write the script to a file.

WHERE THE PHASE ACTUALLY IS
  PLAN.md Phase 7's done-when is TP-105 and TP-113..TP-120 green.
    green  TP-105, TP-113, TP-114, TP-118
    absent TP-115/116/117 (S32), TP-119 (S33's H21), TP-120 (S34)
  4 of 9. THREE STEPS CLOSE THE PHASE: S32, the rest of S33, and S34.
  ! Almost none of the recent work touched those rows -- it was owner-directed visual
  refinement, all landed and all real, but orthogonal to the phase gate.

If you hit a decision no document fixes: file a gap under the policy above, park that
thread, keep the others moving, and QUOTE the gap's own option text to the owner.
! CHECK FOR A FOURTH OPTION FIRST -- seven gaps here were answered with an option nobody
had listed, including one where the owner replied with a criterion that invalidated all
four options as written.
```

## References

- `design/poker-patience/PLAN.md` — the steps; §1 the normative contracts.
- `design/poker-patience/DESIGN.md` — the authority on behaviour; §36 is chart H.
- `design/grid-view/DESIGN.md` — the view's design and its charts.
- `design/poker-patience/TEST_PLAN.md`, `NAMES.md` — every planned test; every identifier.
- `design/card-effect-api/DESIGN.md` — the modifier boundary the first gate enforces.

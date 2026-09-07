# HANDOFF — poker patience

**Goal:** turn Solatro's two-zone tableau into the poker-patience grid game — the engine, then the
board the player sees. Done when a player can deal, place, score, undo and End a show on a grid
they can look at.

**State:** ✅ **EVERY PHASE IS LANDED.** Phases 1-9 and now Phase 10 in full: `S40` amended
`ARCHITECTURE_REVIEW.md` in place, `S41` produced grid versions of the three design companions
with the pre-grid ones archived, and `S44` updated `START_HERE.md`, `PICTURE_WALL.md` and
`LAYERING.md`. `S42`/`S43` (the CSV half) were done out of order earlier and are superseded by the
effect-review stream. **IMPLEMENTED-BY: Claude Opus 5.**

⚠ **PHASE 10 HAS A CROSS-BRANCH CONSEQUENCE THE OWNER HAS TO ACT ON.** The effect-review corpus
(1,409 owner questions) lives on `main` and was mined FROM the pre-grid design documents this
phase just replaced; 228 of its questions, and 7 of the 28 already answered, describe acts,
Submits or patience. the effect review's own handoff on `main` now carries that as task `S12`,
and it is **blocked on this branch being merged** — until then a re-mine would read the archived
pre-grid text and change nothing.

Phases 1-6, 7, 8 and Phase 10's CSV half were landed earlier. **Phase 7 closed with `S34`**: the wall packs the game picture at its real width, the HUD follows the camera, `H22`'s
camera stepping is proven end-to-end through a real key route, and the saved pan (`S32`) is in.
**Every standing failure is attributed** — none is a mystery.

**Entry docs:** `START_HERE.md`; `design/poker-patience/{PLAN.md,DESIGN.md,TEST_PLAN.md,NAMES.md}`;
`design/grid-view/DESIGN.md`; `design/card-effect-api/DESIGN.md`; `HEADLESS_TESTING.md`.
⚠ Flowchart **H is §36 of `design/poker-patience/DESIGN.md`**, not of the grid-view design.

## ⚠ THE NINE FAILURES, AND WHO OWNS EACH

```
1  GRID LAYOUT  116.0 px card-on-cell                              INTERFERENCE, unexplained
8  GRID VIEW    TP-139, TP-140 x2, TP-141, a pan check, the gate's  ONE question -- see below
                Entrance edge, and the 2 clip-window checks
```
- `GRID LAYOUT`'s **116.0 px** is the standing cross-suite interference: that suite ALONE passes and
  the `CardVisual` scale fix did not move it, so it is a different mechanism and still open.
- ⚠ **`TP-140` NOW FAILS SYMMETRICALLY ON BOTH NEIGHBOURS, AND THAT IS PROGRESS, NOT A REGRESSION.**
  It used to fail on the LEFT one only, because the HUD's share was taken off the left and the board
  was measured against the whole picture. Isolation is now measured in the board's OWN area, so both
  neighbours sit the same distance out and both are short by the SAME amount.
- **The remaining shortfall is exactly the terms the derivation cannot see** — see the next section.

## ⚠ THE ISOLATION DERIVATION IS SHORT BY 35 OF 510, AND THE 35 IS FONT AND THEME

```
focused_content_height_px()  475   block 286 + Entrance strip 81 + 2 edge pads 108
the live focused fit divides  510   ...plus the panel's column-label gutter 27 and the
                                    scroller's reserved horizontal band 8
so the solver models z = 834/475 = 1.756 where the board really uses 834/510 = 1.635 -- 7% low
```

⚠ **THE 27 IS A FONT METRIC AND THE 8 IS A THEME ONE**, and `game_picture_design_size()` runs before
any board exists to measure either. That is the whole of what is left of `GAP-039`.
⚠ **DO NOT CLOSE IT BY DELETING THE TWO TERMS FROM THE LIVE FIT.** The gutter is real content and
the band is really reserved; dropping them makes the model agree by letting the board overflow its
window, and the board is bottom-anchored, so the overflow goes off the TOP and the top row clips
again — which is the bug this whole stream started on.

**The cheapest honest route, NOT yet chosen:** measure both once from real controls and cache them,
so the static sizing can read a measured number rather than a derived one. ⚠ It needs a tree to
resolve a theme, and `H1` requires the picture stay ONE fixed size for a run, so where that
measurement happens is a design decision and belongs to the owner.

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
- ⚠ **`user://settings.tres` WAS POISONED, AND RESTORING IT CHANGED TWO THINGS.** It carried
  `base_delay` 0.1 (default 1.0), `prop_tick_fraction` 1.0 (0.45), `act_event_cap` 60 (**6000**),
  `wall_transition_delay` 0.001 (0.6) and `wall_selection_repeat_delay` 0.05 (0.4). Restored to
  defaults by owner permission.
  - ⚠ **THE SUITE GOT MUCH SLOWER, AND THAT IS THE HONEST SPEED.** Suites that do not isolate read
    this file, so a `base_delay` of 0.1 was running every animation at a tenth of its real length.
    `SUIT PROPS` alone went from under 4 minutes to **6m40s**. **Use `--timeout 1800`**; the
    handoff's old "~190 s warm" was measured against the poisoned file.
  - ⚠ **THE STANDING `116.0 px` GRID LAYOUT FAILURE WENT AWAY WITH IT.** With pristine settings the
    whole suite is ONE failure — `TP-85`'s documented mid-growth flake. So `GAP-030`'s "settings
    interference" was substantially this file, not a suite-ordering problem.
  - ⚠ The aggregate banner said `12 FAILED (1 behavior, 0 implementation)` while every per-suite
    banner said `ALL … CHECKS PASSED` except GRID LAYOUT's `133 passed, 1 FAILED of 134`. The
    aggregate tally disagrees with the suites it aggregates; unexplained, and worth a look before
    anyone trusts that number.

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
  status: done
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
  status: done
  notes: >
    WallPicture.saved_pan_x plus the pure snap_pan_to_grid(); Main writes it at the step, reads it
    for every resting pose, re-snaps on a resize, and restores it into the board BEFORE re-focusing.
    Also fixed two defects in the same arithmetic: the non-transition move aimed at the picture's
    CENTRE, and the edge bounce measured its overshoot from the centre while springing back to the
    pan.
- id: S34
  description: 'Tools/wall_editor.tscn drives every new wall knob (Q186=a).'
  status: done
  notes: >
    Owner ruled the editor may host a real board. `PlayArea.settings()` now delegates to
    `WallPicture.settings()` -- the accessor the wall half already shared -- so the hosted GameView
    follows the tool's panel; that is also GAP-030's injection seam, first step.
    `knobs_this_preview_does_not_drive` is DERIVED now, not declared.
- id: S40
  description: 'PHASE 10: ARCHITECTURE_REVIEW amended in place (Q279=a).'
  status: done
  evidence: >
    Sections 1, 2, 3, 5, 7 and 8 rewritten against the code; the rest left. doc_check 0 errors,
    9 warnings -- identical to the pre-edit baseline.
  notes: >
    Section 2 is now 2a grid placement / 2b the legacy zone engine / 2c the shared mutation rule.
    Section 3 gained a 3d for line completeness; 3c KEPT its number because five documents cite
    ARCHITECTURE_REVIEW section 3c for the comparator buckets. Section 8 collected the five suite
    gates that were only in this handoff. Corrected while there: the suite count said 31 and is
    45; the deadlock chain named four suites and has nine.
- id: S41
  description: 'PHASE 10: alternate design docs, older versions archived (Q280=b, Q281).'
  status: done
  evidence: >
    solatro/{DESIGN_DOC,DESIGN_RECOMMENDATIONS,DESIGN_REFERENCES}.md are grid versions;
    the pre-grid files moved unchanged to solatro/archive/ with a README. doc_check 0 errors.
  notes: >
    Owner verbatim (Q281): "alternate versions, lets archive the older versions for now".
    archive/ is NOT in doc_check's LIVING_GLOBS, so the archived files keep their own dated
    timelines without failing the hygiene rules -- which is the point of an archive. Their
    BASENAMES are unchanged, so every pre-grid citation into them still resolves.
    DESIGN_REFERENCES.md's historical corpus is deliberately untouched: it is a quarry and that
    is its whole value. Only the framing and the eleven hooks whose mechanic was literally a
    Submit were re-based.
- id: S44
  description: 'PHASE 10: START_HERE, PICTURE_WALL and LAYERING (Q290=b).'
  status: done
  evidence: >
    doc_check 0 errors, 9 warnings. LAYERING.md's draw-order tree verified against the live
    VISUAL LAYERS dump in the run log, not only against the source.
  notes: >
    The board has TWO card layers and they are not siblings -- CardLayer inside the scroll for
    the grids, EntranceCardLayer on a LATER PlayArea sibling for the Entrance. That is why an
    Entrance card's FX draws in front of every grid, and it is the fact LAYERING.md most needed.
    play_area.gd cited a `_build_grid_panel` that does not exist; the function is
    `_create_grid_panel`. Comment only.
```

## THE SECOND CLOSING PHASE — the GAP-042 stream, with its output

The close over `8eccfc2f~1..HEAD` (24 commits, ~205 inserted / 35 deleted lines of production code
in six files). The first close, below, covered Phase 10 and does NOT cover this range.

**IMPLEMENTED-BY: Claude Opus 5, high effort. REVIEWED-BY: Claude Opus 5, high effort** — at the
floor, not below it. The first close's review used Sonnet against Opus code and was below the
corrected floor; it was redone here and its findings were treated as leads, not coverage.

| # | Item | Result |
|---|---|---|
| 1 | full `doc_check.py` | **0 errors, 9 warnings** — matches baseline exactly |
| 2 | `dup_check` / `diff_shape` baselines | established, below — first run of either on this branch |
| 3 | adversarial review, Opus 5 high | 8 confirmed + 5 suspected; verified each against the code |
| 4 | `/code-review` high | 8 findings (7 confirmed, 1 plausible) |
| 5 | `/simplify` | 2 altitude findings, both recorded and parked, neither fixed |
| 6 | `bloat-reviewer` | 6 findings; 1 of them (the inert panel meta) nothing else caught |
| 7 | `/fx-verify` | **NOT RUN — see "what did not run" below** |
| 8 | fix what 1-7 found | 3 code fixes + 4 fixture/test fixes, each red-then-green |

### THE FIXES, WITH THEIR EVIDENCE

Each was proved by neutralising it, watching the expected checks fail, restoring, watching them pass.

1. **Entrance write-backs bank where the score is read.** `CardEffectApi.line_section_at` still took
   the legacy `of_line` path for an Entrance coordinate, leaving `section.grid == -1`, so the points
   went to `scores_col_legacy` / `col_total` — which `live_total()` does not read — while
   `register_combo` had already moved the multiplier. **This was the GAP-042 defect surviving at a
   third call site** after the two props were fixed. `ScoringSection.of_row_at` is now
   `of_line_for(state, coord, kind)`, the ONE place that resolves which zone a coordinate is in, and
   `line_section_at`'s branch is gone. `of_entrance_column` was DELETED, not wired: it had zero
   callers and bound the ROW collector to a COL section, and the ruling's *"shared bucket the grid
   column uses"* is plain `of_line_at`.
   RED: `grid -1` / `board_total 0.000000` / `col_total 7, legacy entries 1`, 4 of 74 failed.
   GREEN: `GRID ECONOMY: ALL 74 CHECKS PASSED`.
2. **A grid removal carries the commitment with it.** `Board.remove_grid` renumbers via
   `grids.pop_at` and `remove_grid_score_data` re-indexes the buckets on the very next line, but
   `committed_grid` was left naming the old numbering. `Game.place_card_in_grid` refuses every
   placement whose grid is not the committed one, and its only reset sits PAST that guard — so a
   stale commitment soft-locks placement for the rest of the show. `GameData.rebase_commitment`
   fixes it at the removal.
   RED: `committed 1, 1 grids`, 4 of 100 failed. GREEN: `GRID BOARD: ALL 100 CHECKS PASSED`.
3. **Three doc blocks reattached to the functions they describe** (`play_area.gd`). The two new panel
   accessors were inserted BETWEEN `_bind_grid_score_labels` and its documentation, so the GAP-015
   row-label ruling was documenting a one-line meta getter, and `_cell_slot` had no doc at all while
   its doc sat 250 lines away. Also separated TP-85's MEASURED cause (a stolen `CURRENT`) from the
   REASONED one (the growth span collapsing below a frame) in `test_grid_layout.gd`, which the
   commit and the comment had asserted as if each were the single cause.

### ⚠ THE ASSERT IN FIX 2 FOUND WHAT STATIC ANALYSIS MISSED

Both the adversarial reviewer and `bloat-reviewer` concluded, independently and with call-graph
evidence, that **no caller reaches `entrance_row_index`'s out-of-range case.** They were wrong. The
assert fired **×12** on the first full run: two test fixtures build an Entrance-only `GameData` with
NO grids — `test_suit_props.gd::col_game` and `test_ui_props.gd::make_board_game`. Both had been
silently banking into a nonexistent grid's bucket, exactly the loss
`test_suit_props.gd::entrance_game`'s own comment already warned about. Both now build a grid.

⚠ **THE THIRD FIXTURE CANNOT TAKE A GRID, AND THAT IS WHY THE ASSERT WAS BACKED OUT.**
`test_all_kinds_live_in_game_view`'s inline fixture is the assert's remaining source in a FULL run
(not when UI PROPS runs alone — settings interference again), but a grid panel WIDENS the board,
which is the very thing that test measures (*"the widest board the suite builds"*, the board
`GAP-001` was measured on). With a grid it fails its scroll-reach check at `board right edge 1211.2
vs scrollable right 1073.6`. Moving that expected number would calibrate the check to the change, so
the grid came out and **`entrance_row_index` went back to returning a row index rather than
asserting** — the guard now carries the finding at the site. Leaving the suite red to keep an assert
is the wrong trade; its value is already banked in the two fixtures and the one test it corrected.

⚠ **THERE IS A REAL QUESTION UNDER THAT CONFLICT, AND IT IS NOT ANSWERED.** The shipped game ALWAYS
has at least one grid (`SkillGridAllotment.on_game_start` guarantees it). So a boardless Entrance is
a board configuration that **cannot occur in play**, and the geometry test measures one. If that test
were given the grid the real game always has, its scroll-reach check FAILS — which would make
`board right edge 1211.2 vs scrollable right 1073.6` a genuine product finding about column
reachability, not a fixture artefact. **Deciding which it is belongs with `GAP-001`, not with a
close.**

**And it exposed a test calibrated to the defect.** `test_juggling_pays_on_score` asserted
`g.state.col_total == 3` — the RETIRED act total — and therefore **passed because the points were
being lost.** It now asserts the bucket the shown score is derived from. ⚠ Its neighbour
`test_firework_banks_column` still does this, and is left that way deliberately because the defect
under it is not fixed: see "Open bugs".

### ⚠ WHAT DID NOT RUN, AND WHY

- **`/fx-verify` — NOT RUN.** The visual changes in this range (the emptied HUD labels, the Entrance
  height labels) landed and were eye-verified in the FIRST close. This close changed no rendering
  code: fix 3 moved comments, and fixes 1-2 are banking and index arithmetic with no visual output.
  A render pass here would have certified the previous close's work again, not this one's.
- **The intermittent GRID VIEW hang was not attributed**, only characterised. See below.

### ⚠ THE INTERMITTENT HANG — 1 RUN IN 4, NOT DETERMINISTIC

The first full run of this close TIMED OUT. Output, not a claim:

```
======== NO SUITE BANNER — the run did not reach its own verdict ========
[exit-time] TIMEOUT — killed after 1800s. Nothing below is a complete picture.
[exit-time] clean — every engine error this run was already visible to the in-run gate
```

**GRID VIEW printed its banner and then emitted ZERO check output for 27 minutes.** That is a hang,
not slowness — a slow suite still streams `[PASS]` lines, and this one streamed none after its
banner.

**GRID VIEW ALONE IS FINE**, which is the discriminating datum (the handoff's own cheapest test):

```
<godot> --path solatro res://Tests/UI/test_grid_view.tscn --windowed
============ GRID VIEW: ALL 215 CHECKS PASSED ============     0 FAIL, empty errors log
```

⚠ **AN EARLIER VERSION OF THIS SECTION BLAMED CROSS-SUITE INTERFERENCE. THAT WAS WRONG, TWICE, AND
THE CORRECTION IS THE USEFUL PART.**

**Wrong #1 — "GRID VIEW's concurrent siblings".** It has none. GRID VIEW waits for every sibling
except `SETTINGS RANGE`, `E2E RUN`, `LEAK CANARY`, `WALL PAUSE` — and **all four of those wait for
GRID VIEW** (each excludes only the suites after it in the chain). Verified by reading all nine
exclude lists. **GRID VIEW runs alone.** Nothing can be concurrent with it, so no concurrent suite
can have stolen a global from it.

**Wrong #2 — "a settle loop that never settles".** Every wait on the path is bounded:
`_settle_layout` is `while waited < 2.0`, and `_stand_up_grids` only ever awaits
`get_tree().process_frame` a fixed number of times. There is no unbounded loop to spin in.

**WHAT IS ACTUALLY KNOWN, AND IT IS STRANGER THAN EITHER.** `TestLog.line` calls `flush()` on EVERY
line, so the log is write-through and the last line written is genuinely the last line reached. The
last line was the GRID VIEW banner. The very next statement is
`check_all_tests_registered()`, whose FIRST action is `implementation_section("REGISTRATION GATE")`
— another `TestLog.line`, which never appeared. **So the stall is between two consecutive log writes,
in a window that contains no loop, no await and no branch** — while the process burned a full core
(CPU 456s → 1556s over the stall, sampled).

Ordinary GDScript control flow cannot stall there. That makes "GRID VIEW hung" the wrong frame: the
suite is where the log stops, not necessarily where the process is stuck. The suspects are now at the
ENGINE/process level, not the suite level, and nothing here distinguishes them.

⚠ **IT IS INTERMITTENT, NOT A BROKEN HEAD.** One hang in six full runs this close; the other five
went green. `730815bd`'s claimed green result does reproduce, just not every time. "Intermittent" is
not the opposite of "deterministic": the suite seeds its RNG, but frame deltas are real-time, and
`_settle_layout` accumulates `get_process_delta_time()` — so runs differ in timing even at identical
code, and a timing-dependent stall is deterministic only given an interleaving nobody recorded.

### ⚠ WHY IT COULD NOT BE ATTRIBUTED, AND THE ONE FIX THAT DOES NOT NEED ATTRIBUTION

**THE ENGINE LOG FROM THE HUNG RUN IS GONE.** Every later run reopens `test_output_all.log` with
`FileAccess.WRITE`, which truncates. Five runs followed. **Whoever chases this next must preserve the
logs before re-running** — copy the whole `logs/test/` directory aside on the first sign of a stall.
That is the single most expensive mistake this close made.

**THERE IS NO PER-SUITE STALL DETECTION ANYWHERE.** `run_tests.py` has only ONE bound: a global
wall-clock `--timeout` on the whole 45-suite process. So a single stalled suite consumes the entire
budget and the run reports `NO SUITE BANNER — the run did not reach its own verdict`, **discarding
the verdict of all 45 suites**, including the 44 that were fine. That is why one stall costs a
30-minute run AND leaves nothing to attribute it with.

**✅ BUILT — `run_tests.py --stall-timeout`, default 600 s.** It watches the test log's size as a
heartbeat, kills a run that has gone silent, NAMES the suite that started without finishing, and
copies the log directory aside to `logs-stalled-<stamp>` before the kill. Landed in the PYTHON
WRAPPER, not in the harness the suites run under, so it cannot change test behaviour — which is what
made it safe to land here after all. Verified both ways: it fired on an idling standalone scene at
`--stall-timeout 30`, and a full run at the default came back `ALL 45 SUITES: 3979 CHECKS PASSED`
with no preserved directory created. The longest legitimate silence measured in a full run is
~3 minutes, so 600 s has better than 3x margin. See `HEADLESS_TESTING.md`.

**WHAT THE NEXT SESSION SHOULD DO:** run the suite in a loop until it stalls again — the watchdog now
names the suite and keeps the logs for you — and only then attribute it. Do not spend a session
theorising: this document already contained two confident wrong answers, and both were reasoned
rather than measured.

### STEPS 9-13 OF THE CLOSE

- **9 `/docs`** — `doc_check.py` stays at **0 errors, 9 warnings**. The judgement half found four
  things the mechanical half cannot see, all fixed: `GAP-042` still named `of_row_at` and described
  `of_entrance_column` as existing after it was deleted; `design/grid-view/DESIGN.md` still announced
  a rename to `entrance` / `entrance_type` when `entrance_type` exists nowhere in the tree; and
  `GAP-005` / `GAP-015` cite `scores_row_h` / `scores_col_h`, which have ZERO references — those two
  are historical rulings, so each now carries a one-line note saying what shipped instead, rather
  than being rewritten.
- **10 `consolidate-memory`** — 1 memory updated, 0 added. `tests-that-prove-nothing` gains item 13
  (a check asserting a field the product does not READ — distinct from item 7's calibrated
  tolerance) and, under the run-alone section, the fact that cross-suite interference also presents
  as a HANG with no output, which reads exactly like a broken build. Nothing else this close learned
  crosses projects: the rest is solatro's and lives here, or is `/plan-run`'s and lives there.
- **11 feed back into the skills** — 5 additions to `/plan-run`, plus the agent-definition fix.
  ⚠ **THEY ARE DELIBERATELY NOT IN "The reviewer's model floor".** That section exists on BOTH sides
  of the merge and this branch's copy is to be deleted; anything written there would be lost. The
  additions live in "The verification hierarchy" (an `assert` as a reachability oracle, and the
  rule to be ready to back it out) and "Traps that are not about tests" (grep the agent definitions
  when a rule changes; agent definitions resolve from the session root, not the worktree; a test
  asserting an unread field). **Keep them at merge.**
- **12 delete the borrowed tools** — done: `dup_check.py`, `diff_shape.py`, `bloat-reviewer.md` removed.
  They were byte-copied in for this close and belong to `main`, so every command recorded below
  names a tool this worktree deliberately does not carry.
- **13 delete the plan docs** — **DECLINED AGAIN, and the reasons have got STRONGER, not weaker.**
  See "WHY STEP 10 DID NOT RUN" below, which still holds in full. Since it was written: `GAP-042`
  has grown a "WHAT IS NOT BUILT" section that is the entry point for the next piece of work, and
  `GAP-005` / `GAP-015` have been annotated with what shipped. Deleting the directory now would
  destroy the only record of three unbuilt destinations and 314 owner rulings, and `doc_check` would
  go red on the eight living documents that cite it.

### THE TWO NEW TOOL BASELINES — first run of either on this branch

`dup_check.py` and `diff_shape.py` live on `main` (uncommitted); the copies here were removed again.
So the commands below name tools this branch does not carry — run them from `main`, or copy them
in as this close did. Both resolve the repo root from their own location, so these numbers are
about THIS worktree. **Treat them as backlog, not as this close's regressions.**

`py .claude/tools/dup_check.py` (removed after this close) — OUTPUT:

```
[dup-check] 80 duplicated block(s) involving 673 source files.
```

Broken down: **51 of the 80 pairs are in `solatro/`**, and of those **8 have both sides in production
code**, 1 is production-to-test (`Decks/deck.gd` ↔ `Tests/Support/test_decks.gd`) and **42 are
test-to-test setup**. `main`'s comparable numbers are ~30 solatro pairs, ~8 touching production —
so **the production duplication count is IDENTICAL to `main`'s**; the whole excess is test fixtures,
which is what a branch that added this much test surface should look like.

⚠ **ZERO pairs have both sides in production code inside `8eccfc2f~1..HEAD`.** Every pair that
touches a file in the unreviewed range is test-to-test. This close introduced no duplication.

`py .claude/tools/dup_check.py --changed` (removed after this close) — OUTPUT: 4 pairs, ALL of them between
`Tests/Visual/hud_follow_camera_probe.gd` (UNTRACKED owner scratch) and the tracked
`overview_pan_route_probe.gd` it was copied from. **Owner scratch, not this close's, not to be
extracted.**

`py .claude/tools/diff_shape.py --history 400` (removed after this close) — OUTPUT:

```
[diff-shape] baseline over 246 code-touching commit(s) of the last 400
  added 37314, deleted 7177
  deletions are 16.1% of changed lines
  add-only commits (>=25 added, <10% deleted): 121 of 246 (49%)
```

`main`'s comparable deletion share is 19.3%. **16.1% vs 19.3% is not a finding on its own** — this
branch is a feature build-out, where adding is the work. The number to watch is the trend on the
NEXT stream, now that a baseline exists.

## THE FIRST CLOSING PHASE (Phase 10) — what ran, and its output

Every item of `/plan-run`'s numbered close, with the output rather than a claim.

| # | Item | Result |
|---|---|---|
| 1 | full `doc_check.py` | **0 errors, 9 warnings** — identical to the pre-Phase-10 baseline |
| 2 | adversarial review (Sonnet, ≠ Opus 5) | 3 findings; 1 real defect, 1 latent → `GAP-042`, 1 confirmed orphan |
| 3 | `/code-review` high | 2 findings, both in the closing fix itself, both fixed |
| 4 | `/simplify` | 1 altitude finding, recorded not fixed (parked on `GAP-038`); rest clean |
| 5 | `/fx-verify` | **VERIFIED by eye** — rendered `standalone_view_shot`, looked at the PNG |
| 6 | fix + re-run | suite green after every fix; see below |
| 7 | `/docs` | retired-patience backlog deleted, suite count reconciled across 4 docs |
| 8 | `consolidate-memory` | 2 memories updated, 0 added |
| 9 | feed back into skills | 3 edits: `plan-run` ×2, `docs` ×1 |
| 10 | delete the plan docs | **DELIBERATELY NOT DONE — see below** |

**The suite, three full runs, all `ALL 45 SUITES` with every per-suite banner `CHECKS PASSED` and
`0 behavior, 0 implementation`:** 3950 passed before the phase, 3964 after the doc pass, 3963 after
the HUD fix. ⚠ The banner's `N FAILED` field is the ENGINE-ERROR gate, not assertions, and it is
**not deterministic** — 17 errors, then 1, then 1, across identical code. Diff the per-suite banners.
One error is stable across every run and predates this work: `SCRIPT ERROR: Trying to assign invalid
previously freed instance` at teardown. **Not diagnosed. Not this phase's.**

⚠ Only `game_view.gd` changed after the last green run, and only its COMMENTS. The
`standalone_view_shot` render afterwards booted that exact file, laid the view out and printed
correct geometry, so it parses and runs; no fourth suite run was spent on a comment.

### ⚠ WHY STEP 10 DID NOT RUN, AND WHAT WOULD HAVE BEEN DESTROYED

`/plan-run` says to delete the temporary plan documents. **`design/poker-patience/` is not deletable
and deleting it would have been a serious mistake.** The rule assumes a run that has landed, merged
and closed its gaps. This one has done none of those:

- **THREE GAPS ARE OPEN AND A FOURTH IS ANSWERED-BUT-UNBUILT.** `GAP-039` (the isolation derivation,
  short by a font metric and a theme one), `GAP-041` (the goal curve's growth term has the wrong
  sign for most of a run), `GAP-042` (filed by this very close), and `GAP-038` answered `(d)` with
  nothing built. A gap file IS the record of a parked owner decision; deleting it strands the
  decision and the next session re-derives it from nothing.
- **`answers.json` is the owner's 314 rulings.** It is the most expensive artefact in the stream and
  it is not reconstructible. `PLAN.md` §1 quotes the normative ones verbatim precisely so the code
  never has to carry a design id.
- **THE BRANCH IS NOT MERGED.** This handoff is still the resume point, and the effect-review stream
  on `main` is blocked on the merge (its `S12`).
- **Eight living documents cite the directory**, including `START_HERE.md`, which now names
  `design/poker-patience/DESIGN.md` as the authority on the grid's rules, and `ARCHITECTURE_REVIEW.md`,
  which points at `PLAN.md` for the traceability the code deliberately does not carry. Deleting it
  breaks every one of those, and `doc_check` would go red on the spot.

**What SHOULD be deleted, and when:** after the merge, once `GAP-038`/`039`/`041`/`042` are closed
and their residue is folded into `ARCHITECTURE_REVIEW.md`, delete `HANDOFF_poker_patience.md` and
`TEST_PLAN.md`. **Keep `DESIGN.md`, `PLAN.md` §1, `answers.json` and `gaps/`** — they are the design
record, not run scaffolding, and `START_HERE.md` points at them as such.

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

## ⚠ THE TEST SURFACE — first review it has ever had, and what it found

12,463 lines across 75 test files landed on this branch. **No review had ever read them**: the close
scoped `/code-review` to six production files and explicitly told `bloat-reviewer` to ignore tests.
An Opus pass over `Tests/Engine/` found the following. **Everything below I re-verified myself**; where
the reviewer overstated, the correction is noted.

### ⚠⚠ LINE DETECT CANNOT CATCH THE DEFECT CLASS THIS BRANCH HAS NOW HIT FOUR TIMES

`Tests/Engine/test_line_detect.gd` (1201 lines) asserts through `RecordingGame.banked_amounts`, which
records the `amount` ARGUMENT to `add_line_score` and calls `super`. **Verified: the file contains
ZERO references to `live_total`, `board_total`, `grid_score`, `scores_row`, `scores_col`,
`scores_cell` or `section.grid`.** Every assertion in TP-37..TP-45 is taken BEFORE
`add_line_score` branches on `section.grid`, and `grid == -1` routes into `scores_col_legacy` /
`col_total`, which `live_total()` does not read.

**So a regression sending every grid section to the legacy bucket leaves the entire LINE DETECT suite
green while the player's score goes to zero.** That is not hypothetical — it is exactly the defect
found four times on this branch: the two prop mods, `CardEffectApi.line_section_at`, and
`PropBankColScore` (still live). The suite that owns line scoring is blind to it.
⚠ The justifying comments at `test_line_detect.gd:548-551` and `:915-916` — *"which bucket a section
banks into is a later step"*, *"a grid line's bucket does not exist yet"* — are STALE. The buckets
exist and are what the game reads.
**Fix shape:** assert the destination, not the argument — one check on `state.board_total()` or on
`line_score(scores_row, ...)` per scoring test.

### Two more dead functions the handoff did not list

Both verified by grep for callers outside `archive/`:
- **`GameData.discard_lower_board()`** (`game_data.gd:106`) — zero production callers; kept alive
  solely by `test_act_score.gd:100`. The same shape as `apply_act_score`, in the same suite.
- **`Game.move_card_in_grid()` / `Game.remove_card_from_grid()`** (`game.gd:804`, `:815`) — zero
  production callers, and **unreachable from shipped content**: `CardEffectApi` exposes no wrapper,
  and `test_grid_cards.gd`'s own boundary gate forbids a modifier from naming `Game.`/`Board.`. Their
  only callers are six sites in `test_line_detect.gd`, so TP-28's removal leg, TP-29 and TP-45 drive
  a route the product does not have.

### ⚠ COMBO LEAKS A `Game` AND LEAVES THE GLOBAL POINTING AT IT

`Tests/Engine/test_combo.gd:123` `test_register_combo()` does `var g := Game.new()` and
`CardEnvironment.CURRENT = g`, then **never frees it and never nulls `CURRENT`** — verified: the whole
file contains ZERO `free()` and ZERO `CURRENT = null`. It is the LAST test in COMBO's `_ready()`.
`Game extends CardEnvironment extends Node`, so this is checklist **mode 4** (a leaked `Node` needs an
explicit `free()`) AND **mode 8** (global state left behind for whatever suite runs next). Every other
Engine suite nulls `CURRENT` in a teardown helper. A plausible contributor to the standing
*"135 ObjectDB instances were leaked at exit"* note. ⚠ **Not evidence about the stall** — the leaked
`Game` is never added to the tree, so nothing of it runs.

### Checks that assert less than they appear to

| site | what it actually asserts |
|---|---|
| `test_prop_engine.gd:320` | literally `check(true, "...did not hang")`. **The real assertion is REACHING the line**, and its failure mode is a whole-run STALL, not a red check — which until tonight consumed the entire budget unattributably. The new `--stall-timeout` now names it. Worth keeping, worth saying so in the check text. |
| `test_prop_engine.gd:332` | `logs[0] == logs[1]` — two EMPTY logs are equal, and nothing asserts the sample is non-empty first. Checklist mode 5. |
| `test_grid_economy.gd:146` | `special >= row_bucket` where FIX-TRIPLE's four lines all hold `{1,1,1,1,7}` and score identically, so one diagonal satisfies `>=` at equality. Cannot fail for the "both diagonals share one bucket" defect it names. |
| `test_spotlight.gd:562` | `col_total == 0` after scoring — identical to its own precondition, so it passes if the cascade never ran at all. |
| `test_grid_cards.gd:201` | ⚠ **REVIEWER OVERSTATED.** It asserts `total_score == 500`, a value the test wrote, on a field with no live writer in the grid game — a DEAD-FIELD assertion (mode 13). It is not unfailable: zeroing it in `remove_grid` would fail it. Weak, not inert. |

### TEST_PLAN drift — three rows that matter

Twelve `TP-` rows are named by no test; most are merely unlabelled, but three are real gaps:
- **TP-58** — *"a repeat adds `combo_repeat_step`"*. **Verified: `combo_repeat_step` has ZERO
  references in the entire `Tests/` tree.** It is a shipped live knob (default 0.5) that multiplies
  the player's score, and nothing tests it.
- **TP-59** — *"melds and effects contribute on the same terms"* (D11 / `Q323`). No test, and this is
  precisely the live score-shrinking defect at `game.gd:231`. **The ruling has neither an
  implementation nor a test** — see `gaps/GAP-043.md`.
- **TP-135/136** (performance) — `Tools/scoring_parity.gd` states it *"is NOT a test... asserts
  nothing"*, and benches neither of them.

### Not covered even now

`Tests/UI/`, `Tests/Interaction/`, `Tests/Wall/`, `Tests/Visual/`, `Tests/Map/`, `Tests/E2E/` and
`Tests/Support/` have had **no** test-quality review. Within `Tests/Engine/`, eleven files got only a
mechanical sweep (retired accumulators, `check(true)`, await-on-non-signal, lambda capture, unfreed
Nodes) rather than a line-by-line read.

## ⚠ TIER C — the view layer, reviewed at last, and NOT yet acted on

The engine/cards pass declared these unread; an Opus pass covered all seven scope items, including
**every `.tscn` in the diff, which no pass had ever opened**. ⚠ **I re-verified only the two marked
VERIFIED below** — the reproduce loop held the only Godot process, so nothing here has been run, and
none of it is fixed. Treat the rest as a reviewer's claims and reproduce before acting.

### The one defect CLASS worth reading first — four missed zoom sites

The handoff already calls *"EVERY SITE THAT ADDS A MEASURED GLOBAL TO A LOCAL SIZE MUST BE
ZOOM-AWARE"* the rule that cost this stream the most, and records a fix pass over `CardVisual`'s
slot-centre reads. The pass reports **four live sites it missed**, each correct at zoom 1.0 (the
overview) and wrong in focused mode — which is why a suite pinned to the overview cannot see them:

| site | claimed consequence |
|---|---|
| `play_area.gd:1399` `_card_control_at` — `get_global_rect()` ignores scale | a touch on a card arms the pan swipe |
| `prop_layer.gd:193` `_body_over_any_card` | hoops stop bracketing and draw over cards they should thread |
| `play_area.gd:2919` `_position_focus_info` | the inspector lands on top of the card it describes |
| `card_visual.gd:696` held-card grab offset | grab point and multi-card fan pitch drift |

⚠ **THE LAYOUT SUITES ARE PINNED TO THE OVERVIEW** — this document already records that as a known
coverage gap. These four are what that gap costs.

### Two regressions the pass attributes to THIS branch — unverified, and they matter for merge

- **`Levels/main.gd` / `wall_transition.gd`** — the game picture's resting pose became `panned_state`
  (centre + `saved_pan_x`), but `WallTransition` still interpolates between bare rect centres and
  `_on_info_toggled` still aims at unpanned poses, so the trailing `_settle_camera()` cuts a full grid
  pitch. The `else` branch of `_focus_picture` was fixed for exactly this and says so in its comment;
  **the picture-to-picture branch — the route `map → game` actually takes — was not.**
  `sample_at`'s own doc states the rule: *"BOTH ENDS MUST MATCH THE RESTING POSE, OR THE MOVE SNAPS
  AT EACH END."*
- **`UI/Wall/wall_picture.gd:235`** — `focus()` used to force `size_2d_override = Vector2i.ZERO` so
  `WallInput.route()` maps into a plain viewport. The replacement engages a non-identity override on a
  FOCUSED picture whenever the render clamp bites, displacing every click inside the show. Claimed
  reachable by lowering `game_picture_max_render_px` (range floor 256) or `card_scale` past ~2.75.

### Doc blocks attached to the wrong member — the same class already fixed twice here

- ✅ **VERIFIED `Scripts/player_settings.gd:640`** — `entrance_visible_rows`'s documentation sits above
  `grid_align_rows_globally`, and `entrance_visible_rows` ships BARE. ⚠ **These are `@export`s, so
  Godot renders them as INSPECTOR TOOLTIPS**: the owner is shown the wrong help on both knobs. This is
  the user-visible member of the class.
- ✅ **VERIFIED `UI/play_area.gd:403`** — `_row_open_offset`'s paragraph is concatenated above
  `_entrance_open_total`'s own. (The engine pass flagged this one too.)
- Reported and NOT verified: `play_area.gd:204`, `:1629`, `:2317`, `player_settings.gd:662`. Each sits
  100+ lines from the next declaration, so adjudicating them needs a reading pass, not a grep.

### Smaller, all unverified

Hard rule 7: `_row_heights_for(g)` and `_make_visual`'s `at` take parameters nothing uses; hard rule 6:
`prop_layer.gd:310`'s guard is labelled "defensive only" by its own comment. Two unnamed tunable
literals (`prop_layer.gd:598`'s `6.0`, `play_area.gd:1215`'s hard-coded 60 FPS), which this repo treats
as defects. `wall.gd` bypasses the `WallPicture.settings()` accessor that ruling `S34` established.
`card_visual.tscn:11-12` carries two dangling `[ext_resource]` lines left when the branch stripped its
`ShaderMaterial` sub-resources.

⚠ **`play_area.tscn` AUTHORS `clip_contents = true` AND `follow_focus = true`; `setup_gui()` OVERRIDES
BOTH TO FALSE AT RUNTIME.** Not live — `setup_gui` runs in `_ready` — but it violates the convention
stated in `play_area.gd` itself (*"the authored value is not a different number from the one the board
actually runs on"*), and the authored `follow_focus = true` is what two stale comments still describe
as live behaviour.

### ⚠ TWO ITEMS NEED `/fx-verify`, NOT ANOTHER READING PASS

Both have a DURATION, and this document's own rule is that a still frame is the wrong instrument for
one: the `anim_spring_lift` / `anim_jump` mismatch (riders come down while the card beneath stays up),
and whether the hoop-split zoom bug is visible at the shipped focused zoom. **Run them and report what
MOVED.**

## ⚠⚠ THE CHECK TOTAL IS NOT AN ASSERTION COUNT — STOP USING IT AS A GATE

Six full runs at the SAME commit produced **3965, 3979, 3994, 3995** checks and counting. That is a
~30-check spread with no code change between them, and here is why:

**`Tests/Engine/test_fuzz.gd` contains exactly ONE `check(` call and does `_pass += 1` by hand once
per iteration** (`:355`). `test_scoring.gd` does the same. So part of the headline total is an
ITERATION COUNTER, not an assertion count, and it moves whenever a randomised walk takes a different
number of steps.

⚠ **CONSEQUENCE FOR EVERY NUMBER IN THIS DOCUMENT AND IN THE COMMIT MESSAGES.** "3970 checks",
"3974", "3979", "3998" are not comparable to each other and none of them is a gate. This document
already said *"judge by the failure SET and PER-SUITE counts, never the check total"* — that rule is
right, and this is the mechanism behind it. **The real gate is: 45 suites, an EMPTY errors log, and
an unchanged failure set.** ⚠ Also note `test_fuzz` has no check guarding that its walk executed at
all, so a fuzz loop that did nothing would still report its iterations as passes.

## ⚠⚠ THE BRANCH IS NOT RELIABLY GREEN — ~1 RUN IN 4 FAILS, AND NOBODY KNOWS WHY

**Every full run of this close, tallied.** On the FINAL committed code — 8 runs — **2 failed.**

| run | result |
|---|---|
| baseline 1 | **STALL** (27 min silent, timeout, `NO SUITE BANNER`) |
| baseline 2 | green |
| after fix 1+2 | 1 FAILED — my own `assert`, since reverted |
| after the ui_props fixtures | 1 behaviour FAILED — my own fixture change, since reverted |
| after reverting the fixture | 1 FAILED — my own `assert` again |
| after reverting the assert | green ✅ final code |
| watchdog no-false-positive check | green ✅ final code |
| loop 1 | **1 behaviour FAILED** ✅ final code |
| loop 2, 3, 4 | green ✅ final code |
| loop 5 | **1 behaviour FAILED** ✅ final code |
| loop 6 | green ✅ final code |

⚠ **SO "THE SUITE IS GREEN" IS TRUE OF A RUN, NOT OF THE BRANCH.** Roughly 1 run in 4 comes back with
one behaviour failure, at a commit with no code changing between runs. Every green number quoted in
this document and in this close's commit messages is a SAMPLE, not a property.

⚠ **THE STALL IS RARER THAN FIRST RECORDED.** 1 occurrence in 13 full runs, not the "1 in 4" an
earlier draft of this section claimed off a 4-run sample. Six consecutive runs aimed at reproducing
it produced none.

⚠ **AND THE TWO FAULTS ARE DIFFERENT.** A silent hang and a red behaviour check are not obviously the
same bug. Nothing yet connects them; do not assume one explains the other.

## ⚠ THE INTERMITTENT BEHAVIOUR FAILURE — UNATTRIBUTED, AND THE MORE REPRODUCIBLE OF THE TWO

Loop runs 1 AND 5 of 6 each reported `1 FAILED (1 behavior, 0 implementation)`; runs 2, 3, 4 and 6 at
the same commit were clean. **Which check failed is unknown in both cases: run 1's logs were
truncated by run 2, and run 5's by run 6, before either could be read.** At ~1 in 4 it is far more
reproducible than the stall, so it is the one to chase first.

⚠ **THAT IS A DIFFERENT FAULT FROM THE GRID VIEW STALL** — a behaviour check going red, not a silent
hang — and it is a SECOND intermittent fault on this branch. Do not assume one explains the other.

**The tooling gap it exposed is now closed:** `run_tests.py` preserved logs on a STALL but not on a
FAILURE, which is the more common and more perishable case — the reflex after a red run is to run it
again, and every run truncates. It now preserves on any run that is not clean, under a `logs-failed-`
tag. The next occurrence will leave evidence.

## Open bugs

- ⚠⚠⚠ **NO EFFECT ACTIVATION FEEDS THE COMBO ON A PLACEMENT — THE GRID GAME'S ONLY SCORING ACTION.
  THIS CONTRADICTS AN EXPLICIT DESIGN RULING AND SHRINKS EVERY SHOW'S SCORE.**
  `Levels/game.gd:231`: `if feeds_combo and _act_cancellable: register_combo(...)`.
  Verified link by link, not taken on report:
  1. `_act_cancellable` is written in exactly two places, `game.gd:452` and `:455`, both inside
     `_perform_next()`, bracketing the `on_next` window. Nothing else writes it.
  2. `place_card_in_grid` (`game.gd:726`) never sets it, though it does call `_begin_act()`.
  3. `CardEnvironment.run_all_mods` is the ONLY dispatch that passes `feeds_combo = true`
     (`card_environment.gd:113,120`); every other `_note_mod_fired` call site passes `false`.
  4. The placement cascade calls it four times — `on_board_mutated` (`:689`), `on_card_placed`
     (`:770`), `on_score` (`:1145`), `on_after_score` (`:1146`).
  5. The base `CardModifier.combo_key` returns the modifier's script path, which is NON-empty, so
     these mods would register if the gate let them.
  6. `DESIGN.md:1337` **D11: *"melds and effects both feed combo on the same terms"*** (`Q323`=b).
  `live_total() = board_total() * combo_mult()`, so the whole show is multiplied by a number smaller
  than the design specifies, and `exit_show()` banks that smaller number as fame.
  **What still feeds combo, so this is a shortfall not a freeze:** the meld class (`game.gd:989`) and
  the three effects that self-register at their own seam (`prop_score_props.gd:16`,
  `prop_score_talents.gd:16`, `status_juggling.gd:80`).
  ⚠ **THOSE THREE CARRY A NOW-STALE COMMENT** — *"also reaches the dispatch hook via run_all_mods;
  register_combo is idempotent, so the double registration is harmless."* On the placement path the
  dispatch hook does NOT reach it, so those self-registrations are LOAD-BEARING, not redundant.
  ⚠ **ORIGIN: `b36c5336`, a PRE-GRID commit.** `_act_cancellable` meant "an act is resolving" when
  the act WAS the `on_next` cycle. The scoring action moved to placement; the flag did not.
  ⚠⚠ **NOT FIXED, AND THE ONE-LINE FIX WOULD BREAK SCORING OUTRIGHT — see `gaps/GAP-043.md`.**
  Deleting the gate looks obvious and is wrong, because the grid game has NO COMBO RESET:
  `combo_repeats` is never cleared anywhere (`game.gd:210` `+= 1` is its only production write), and
  `combo_classes` is cleared only in `GameData.apply_act_score():94`, which is dead production code.
  The multiplier is uncapped — `player_settings.gd` ships `combo_unique_step 1.0`,
  `combo_repeat_step 0.5`, `combo_cap 0.0`, and a cap of 0 means none. **So the gate is currently the
  only thing bounding combo growth from mod dispatch**; open it and every mod firing on every
  placement adds +0.5 for the length of a show with no ceiling.
  **D11 cannot be delivered by removing the gate. It needs a reset rule, and D13 — *"no act, no
  banking moment"* — deliberately removed the event that used to provide one.** That is a decision
  the design does not cover, so it is `GAP-043`, not a defect to fix in a close. Four options are
  written out there, with the warning to check for a fifth.

- ⚠⚠ **`SkillExtraPoint` AWARDS NOTHING, AND IT IS IN 19 DECK SLOTS.** Its description reads *"Gain 1
  Extra Point Per Score"*. `Cards/Skills/skill_extra_point.gd:19` `add_points()` has **no caller**:
  the only would-be call site is commented out at `:16`, so `on_score` merely re-announces a trigger
  for the visual. Grep for `add_points` outside `archive/` returns the definition and the commented
  line, nothing else. ⚠ Even if rewired, the body disagrees with the card: it calls
  `api.add_total_score(10)`, not 1, and `GameData.total_score` has no other live writer in the grid
  game (`apply_act_score`, above, is dead too). **Pre-existing — dead on `main` as well** — but this
  branch re-plumbed the dead body from `game.state` to `api` and left it dead.
  Same shape one file over: `skill_hungry_hippo.gd:19` `eat_card()`, whose caller `on_card_dropped_on`
  (`:9`) is a `pass` stub. Between them they are the only consumers of
  `CardEffectApi.add_total_score`, which therefore has no live caller either.


- ⚠ **`GameData.apply_act_score()` IS DEAD PRODUCTION CODE, KEPT ALIVE ONLY BY ITS OWN TESTS.**
  `game_data.gd:87`. Grep for callers outside `archive/`: **every one is a test** —
  `test_act_score.gd` (7 calls), `test_combo.gd` (4), `test_game_headless.gd` (1, whose own comment
  says *"there is no button that"* fires it). No production path calls it. It writes `mult_score`
  and `total_score`; `game_view.gd:46` already describes `mult_score` / `col_total` / `row_total` as
  *"the RETIRED act payout's display"* and this close emptied those labels.
  **So the `ACT SCORE` suite, and `test_apply_act_score_combo` inside `COMBO`, are green forever
  while proving nothing about the shipped game.** They are not broken tests — they correctly test a
  function. That function is simply not part of the game any more, and their greenness is what makes
  the dead code look live.
  ⚠ **NOT DELETED HERE — IT IS AN OWNER CALL, NOT A CLOSE'S.** Removing it means deleting production
  code plus a whole suite and part of another, and the question underneath is a design one: is the
  act payout gone for good, or parked? `PLAN.md` §1.6 retired it in favour of the derived
  `live_total()`, which argues for deletion — but that is a ruling to confirm, not to assume.
  ⚠ **THE THREE `check()`s ON `row_total` / `col_total` IN `test_game_headless.gd` ARE DIFFERENT**
  and should stay: they cover `add_line_score`'s LEGACY branch, which is still reachable and still
  has a live defect in it (`PropBankColScore`, above). Do not sweep them up with the act payout.


- ⚠⚠ **`PropBankColScore` LOSES EVERY FIREWORK COLUMN SCORE — LIVE, IN SHIPPED CONTENT, NOT LATENT.**
  `Cards/Props/Mods/prop_bank_col_score.gd:16-19` hand-builds a bare `ScoringSection.new()` and never
  sets `grid`, so it is **always** `-1` and `Game.add_line_score` **always** takes the legacy branch
  into `state.scores_col_legacy` / `state.col_total` — neither of which `GameData.live_total()`
  reads. `register_combo` runs first, so the multiplier moves and the points do not.
  **`PipSuitFirework` is shipped** (`CARD_CATALOG.csv` "Added", granted by deck12), and
  `Game._run_score_effects` runs its spawner over any scored meld, so this fires in a real show.
  ⚠ **NOT FIXED HERE, AND THE REASON IS A REAL EDGE CASE, NOT SHYNESS.** The fix is to build the
  section from a coordinate — `ScoringSection.of_line_for(g.state, <coord>, COL)` — but the obvious
  coordinate does not always exist: `on_finish` fires from `Levels/game.gd:1224` when
  `p.route.is_empty()`, and a firework that starts with an EMPTY rise route never entered a slot, so
  `p.at` is still `BoardCoord.NOWHERE`. That is not a corner case — it is the exact scenario
  `Tests/Engine/test_suit_props.gd::test_firework_banks_column` covers. **Deciding what an
  empty-route firework banks into (almost certainly `prop.source`'s grid position) is the work.**
  ⚠ `test_firework_banks_column` asserts `g.state.col_total == 3` and therefore **passes because the
  defect exists** — the same calibration that hid the Juggling bug. Re-point it at
  `line_score(scores_col, ...)` as part of the fix, or it will keep certifying the loss.
  Found by the second close, from the assert that fix 2 added; outside the range that close reviewed.


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
- ⚠ **`S32`'s two removed camera snaps are UNVERIFIED BY EYE.** Entering a panned show and the edge
  bounce both used to jump, both have a DURATION, and both are now proven only by sampled camera
  positions. Run the game and report what MOVED before calling either done.
- **`skill_scorer_cascade_lower.gd`** is an orphan in production, still a fixture in three suites.

## ⚠ PHASE 7 — CLOSED, 9 of 9 done-when rows green

`PLAN.md` Phase 7's done-when is **`TP-105` and `TP-113`-`TP-120` green**, plus
`knobs_this_preview_does_not_drive` still empty.

```
TP-105 ✅  TP-113 ✅  TP-114 ✅  TP-118 ✅  TP-115 ✅  TP-116 ✅  TP-117 ✅  TP-119 ✅  TP-120 ✅
```

**PHASE 7 IS CLOSED.** Every done-when row is green and
`knobs_this_preview_does_not_drive` is empty when the editor is run.

⚠ **WHAT `S34` NEEDED, kept because it is the shape of the trap:** `knobs_this_preview_does_not_drive`
already returns `""` whenever a real `Wall` exists, so a test that only reads it when the tool is
RUN passes without proving anything. The knobs this stream added — `board_edge_pad_rows` and
`hud_width_fraction` — are **`PlayArea` knobs read through `SettingsManager.settings`**, not through
`WallPicture.settings()`, and the editor's preview hosts `WallPicture`s rather than a live
`GameView`. So the real question `S34` has to answer first is whether the wall editor hosts a real
board at all; if it does not, those two knobs cannot be driven from it and the honest move is an
`EDITOR_INERT_KNOBS` entry plus a gap, not a green check.

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

## ⚠ THE OWNER'S BOARD REPORT — WHAT LANDED AND WHAT IS STILL OPEN

Seven reported bugs. Five are fixed and guarded; the measurements are in the commits.

**Landed:** the special-meld label's box; the column labels' one-column offset; the first card in
a cell widening its row; the card scoring while still held; grid scores never popping; the board
sinking under the Entrance as stacks deepen; the board scrolling itself under the mouse.

**Two latent defects the measurements exposed, both fixed:**
- `ScoringSection.of_line_at()` — the *grid-model* constructor — never stored `grid` or `height`,
  so every section it built read `grid = -1` and banked into the **legacy zone gutters**, which the
  grid board does not render. Three production callers: two prop mods and
  `CardEffectApi.section_for()`.
- `hide_focus_info()` switched off `_process` checking only `_row_open`, never `_layer_grown`, so
  anything closing the inspector mid-growth froze the row arithmetic part-grown.

**Second round, landed:** every score label renders at ONE size (the owner ruled they must match;
it needed a shared BOX *and* a shared font pass, because equal boxes still size different-length
numbers differently), and a row's score sits level with the pip row of the card it names — measured
-1.6 px at every height, from -60.5 uniform before. ⚠ The label stack's pitch must equal the CARD
depth pitch: with the stack's own separation left in, the labels fanned 6.5 px per level.

### ⚠ STILL OPEN

1. **`GAP-040` — the clip that cuts a tall stack IS the clip that isolates a neighbouring grid.**
   The owner proposed turning off the scroll container's clipping and is right about the mechanism
   (`CardLayer < TopLevelVBox < SmoothScrollContainer(clip)`; the block sits 45.8 px above its
   window). But `TP-141` asserts a neighbouring grid paints NOTHING outside that window, so the
   fix retires the isolation contract by construction. **Four options filed; parked on the owner.**
   ⚠ Also measured there: `_give_the_board_a_floor()` reserves `2 * board_edge_pad_px` through a
   `custom_minimum_size`, which is a FLOOR — content 350 against a minimum of 313, so both edge
   pads stop applying the moment the board grows past them.
2. **Verify by eye, in the running game.** Every fix is proven by measurement and by the suite; the
   ones with a DURATION — the card settling before the score, the pop, the growth — have not been
   watched by a human.

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

### 2. The Entrance stacks UPWARD — ✅ LANDED

The Entrance is not a mirror of a cell slot, it **IS** one. `_stack_slot_center()`,
`_size_stack_slot()` and `_bind_stack()` serve both halves of the board (owner: *"all stacking
should use same code. no duplication"*), and an Entrance column is built by `_create_cell_slot()`.

⚠ **THE PROOF THE CODE IS SHARED, NOT MERELY SIMILAR:** binding header-first again breaks the
GRID's checks and the ENTRANCE's together, from one edit.

⚠ **THE ENTRANCE'S RESTING LINE IS DERIVED FROM THE DATA, AND ALL THREE ALTERNATIVES WERE MEASURED
WRONG** — do not "simplify" it back to a control read:
- `upper_zone_right`'s bottom edge is CONTENT-driven; a reveal grows the column and the floor moves
  with it, cancelling the opening. A revealed row appeared not to move at all.
- `entrance_strip`'s bottom is fixed but stops being the columns' line once they outgrow it: 13 px
  out at `card_separation_scale` 1.0, 45 px at 2.0.
- Subtracting the growth back off the hbox works AT REST and lags MID-EASE by a frame — 34 px of
  prop drift during the animation.

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

## ⚠ The cross-suite interference is NOT fully deterministic, and it is not only GRID LAYOUT

**Measured, same tree, two consecutive full runs:** `TP-85` fired in one and not the other, and
`UI VIEWERS`' `repeated show_deck replaces instead of stacking` fired once and not the other — with
`live 0`, no viewer at all, not two. `UI VIEWERS` passes ALONE (`ALL 26 CHECKS`), so it is
interference, not a defect in it. The `116.0 px` check is the stable one.

⚠ **A single full run is therefore not enough to attribute a NEW failure.** Run the suite twice, or
run the suspect suite alone, before blaming a change. `UI VIEWERS` is the one UI suite with no
`await_siblings_except`, which is why it is the one that moves.

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
  3. solatro/design/poker-patience/TEST_PLAN.md -- its rules section and the row table.
     Every step owes named TP rows; dropping a planned row is a gap, not a judgement
     call. Rows marked E are BY-EYE and need the OWNER to sign them off, not you.
  4. DESIGN.md 36 (flowchart H) when you need it. It is the authority on behaviour.

FIRST, BEFORE ANY CODE -- run the suite:
    GODOT_BIN="C:\Users\khanr\Desktop\Godot_v4.7.2-stable_win64_console.exe" py solatro/Tools/run_tests.py --timeout 600
  EXPECT: ALL 45 SUITES, 9 FAILED -- 1 GRID LAYOUT (the standing 116.0 px) and 8 GRID
  VIEW, every one of them attributed below. TP-85's mid-growth flake may or may not fire,
  and so may one UI VIEWERS check -- see the non-determinism section.
  ! USE 600, NOT 400 -- it is a GLOBAL limit and a COLD run exceeds 400 s, dying with
  "NO SUITE BANNER", which reads exactly like a hang. Warm it is ~190 s.
  ! Judge by WHICH checks fail, never the count. A NEW failure needs TWO full runs, or
  the suspect suite run alone, before you blame a change for it.
  ! The owner's Godot editor stays OPEN -- it hosts the MCP. Leave it alone. The
  one-process rule binds GAME and TEST processes only. Never kill by image name or a
  Get-Process|Where-Object pipeline (a hook blocks it); stop a verified
  "Solatro (DEBUG)" orphan by explicit -Id.

THE TREE IS CLEAN. Nothing is half-applied.

THE NINE FAILURES ARE TWO QUESTIONS, NOT NINE BUGS
  8 GRID VIEW = GAP-039's last 7%: the isolation solver divides by 475 where the live
    focused fit divides by 510. The missing 35 is the panel's column-label gutter (27, a
    FONT metric) plus the scroller's reserved band (8, a THEME one), and the picture is
    sized before any board exists to measure either.
    ! TP-140 failing SYMMETRICALLY on both neighbours is PROGRESS -- it used to fail on
    the left one only. Both are now short by the same amount.
    ! DO NOT close it by deleting those two terms from the live fit. The gutter is real
    content and the band is really reserved; dropping them lets the board overflow its
    window, and the board is bottom-anchored, so the overflow goes off the TOP and the
    top row clips again -- the bug the whole stream started on.
  1 GRID LAYOUT 116.0 px = GAP-030's settings interference. That suite ALONE passes.

PICK A TRACK AND TELL THE OWNER WHICH
  Phase 7 is 7 of 9 done-when rows. S32 landed the saved pan; TWO steps are left.

  TO CLOSE THE PHASE (PLAN.md Phase 7):
    S33  TP-119 -- Info mode fits the window-aspect view (H21, Q178=a). The H20 half is
         already landed. Do this first: it is the smaller of the two and entangled with
         nothing GAP-039 holds.
    S34  TP-120 -- Tools/wall_editor.tscn drives every new wall knob (Q186=a), with
         `knobs_this_preview_does_not_drive` empty. ! It has grown knobs this stream:
         board_edge_pad_rows and hud_width_fraction both need driving.

  THE REFINEMENT QUEUE (owner-directed, closes no row):
    1. Row score labels. MEASURED, not moved: the band sits 37 px above the pip row's
       centre at card_scale 1.0, occupying the card's top 16 px while the pips sit 40-50
       px down. The wrong fix (SIZE_EXPAND_FILL + VERTICAL_ALIGNMENT_BOTTOM) is already
       reverted. ! The move is a WHOLE-STACK shift against a VBoxContainer whose
       custom_minimum_size is a FLOOR, not a cap -- the accumulation trap whose first fix
       was a false green. Cheapest item on this list; it is already measured.
    2. The Entrance stacks UPWARD. ! NOT a bottom_anchored := true flip -- the grid
       REVERSES control-build order and the Entrance builds header-first, so a naive flip
       renders the header upside-down off the top of the strip. Full roadmap in this
       file's queue section, including the owner ruling that drops the bespoke
       Entrance-only highlight.
    3. Verify the Entrance transitions smoothly BETWEEN grids. Probably already true
       (_sync_entrance_x re-derives every frame) -- but verify by RUNNING it. A still
       frame is the wrong instrument for anything with a duration.
    4. GAP-030 settings isolation, staged (b): build the injection seam, then migrate 77
       read sites across 22 files heaviest-first (play_area 18, main 16, prop_layer 11),
       each batch its own commit with a full suite between. This is the ONLY thing that
       clears the 116.0 px, and it is the biggest blast radius of the three.
    5. GAP-028's H24 half. Expect a follow-up gap, not a judgement call.

  ! S32 LEFT ONE BY-EYE DEBT. The saved pan removed two camera snaps -- entering a panned
  show, and the edge bounce -- and both have a DURATION, so neither is provable by a still
  frame or by the checks that landed. Run the game, pan off the resting grid, leave to the
  map and come back, and bounce off the board's edge. Report what MOVED.

THE INSTRUMENTS -- USE THEM, THEY ARE WHY THIS STREAM'S NUMBERS ARE TRUSTWORTHY
  Tests/Visual/focused_pose_probe    boots main.tscn, enters via Main.enter_game(); the
                                     product's own pose. Knobs WINDOW=, GRIDS=.
  Tests/Visual/standalone_view_shot  game_view.tscn on its own, hosted in a SubViewport
                                     of the size under test.
  Tests/Visual/zone_drift_probe      a row's zone cards against their controls.
  Tests/Visual/leak_holder_probe     names a HOLDER for every unreachable card.
  ! DisplayServer.window_set_size CANNOT go below the project minimum -- asking for
  412x892 returns 1152x2494 -- so a screen-size sweep driven through the real window
  silently tests one size four times. Host in a SubViewport.

NON-NEGOTIABLES, each of which caught a real defect here
  - MEASURE BEFORE YOU BUILD, and say whether a number is measured or inferred. Three of
    this stream's own recommendations died on contact with a measurement; all three are
    recorded in the gaps so nobody retries them.
  - RED-THEN-GREEN for every check, and confirm the red failed the checks you EXPECTED.
    Neutralise the BEHAVIOUR, not the test. ! S32's red run caught three of its own checks
    asserting a different quantity from the one their message named, and three more that
    pass with the feature deleted. A green new test proves nothing until you have seen it
    red for the right reason.
  - THE FIXTURE MUST VARY THE QUANTITY THAT DRIVES THE DEFECT. A harness at board_zoom
    1.0 cannot see a bug whose error is proportional to the zoom.
  - ASSERT THE PROPERTY, NOT THE TOTAL. Every suite abandons cards on purpose, so an
    absolute leak count passes alone and fails by 143 in the full run.
  - A CONTROL-LOCAL LENGTH IS NOT A GLOBAL ONE. global_position carries the board zoom;
    size and card_size never do. Read a drawn rect as
    get_global_transform() * Rect2(Vector2.ZERO, size).
  - CONFIRM AN API EXISTS (ClassDB.class_get_method_list) before calling it; Godot is
    4.7.2. A compile error CASCADES and names none of its symptoms.
  - NO COMMENT INSIDE A METHOD BODY. NO DESIGN IDS IN PRODUCT CODE (Tests/ is exempt).
  - A tunable literal in a source file is a defect, even when it looks like an epsilon.
  - BACKTICKS DIE INSIDE `py -c "..."` FROM THE BASH TOOL -- bash command-substitutes them
    and silently empties the text. Use a heredoc or write the script to a file. Multi-line
    replace guards fail on invisible whitespace too; prefer the Edit tool for those.

If you hit a decision no document fixes: file a gap, park that thread, keep the others
moving, and QUOTE the gap's own option text to the owner.
! CHECK FOR A FOURTH OPTION FIRST -- the owner has answered with an unlisted option many
times, including twice this stream ("off camera" killing a filed option outright, and
"pretend the 0.75 area is the entire camera view", which shrank the picture below where
it started).
```

## References

- `design/poker-patience/PLAN.md` — the steps; §1 the normative contracts.
- `design/poker-patience/DESIGN.md` — the authority on behaviour; §36 is chart H.
- `design/grid-view/DESIGN.md` — the view's design and its charts.
- `design/poker-patience/TEST_PLAN.md`, `NAMES.md` — every planned test; every identifier.
- `design/card-effect-api/DESIGN.md` — the modifier boundary the first gate enforces.

# HANDOFF — playtest fixes (the combined branch's first playtest)

**Goal:** the sixteen findings of the owner's first playtest on `combine-sidebar-boardplan` fixed
and gated, each against the ruling below, on this branch, ready for the owner to merge.
**State:** P1-P11, P14, P16-P22 are done, each red-then-green and by eye where it draws,
one verified step per commit. Last gate: `ALL 51 SUITES: 6131 CHECKS PASSED`, 21 placeholder
warnings (P6 returned one slot of 22), the fingerprint exit profile, 0 SCRIPT ERROR. Pending: P12, P13,
P15, P23; each carries its site map in `notes:`. Gate at the stream's start:
`ALL 51 SUITES: 5839 CHECKS PASSED`.
**Entry docs:** solatro/START_HERE.md, solatro/design/sidebar/DESIGN.md,
solatro/design/poker-patience/DESIGN.md, solatro/design/grid-view/DESIGN.md,
solatro/design/board-plan/DESIGN.md, solatro/PICTURE_WALL.md
**IMPLEMENTED-BY:** implementers `general-purpose` on `opus` (Opus 5) at default effort, one fix
at a time; overseer Fable 5.1, writes no source; research `Explore` on `opus`.

## Owner rulings (verbatim where quoted; each overturns or extends the design it names)

- **R1 sidebar space (B1, B16)** — overturns sidebar `Q27`=d, D8/D10, `GAP-001..003`.
  Owner: "overlay, never inset. include screen movement to include sidebar sliding in and out of
  view so picture edges match window edges always. for example when initially focusing on a
  picture, no sidebar, edges match. once edges have disappeared, have contents shift to the side as
  sidebar slides in. do exact reverse when leaving the scene. check if this means that we need
  inset around picture that is half or less of sidebar width. such an inset should cover all 4
  edges if needed to accommodate potential sidebar from any edge." The sidebar is also hidden when
  it has nothing to show (the menu) and in wall view.
- **R2 Escape (B6)** — overturns picture-wall `Q100`=a for the keyboard: `ui_cancel` cancels
  everything the second button would AND zooms out to wall view. Back stays on `wall_back` (pad 9,
  `[`); `wall_overview` (Tab, pad 4) still opens the wall.
- **R3 run start (B2)** — extends picture-wall `Q61`/`Q62`: keep the slow wall reveal, then the
  camera enters the MAP without a press. Same on Continue when no show is pending.
- **R4 pack picking and map travel (B3)** — new; overturns `choice_viewer`'s click-takes-the-pack
  and K4's accept-enters-the-node. Owner: "click selects; a take button confirms. choosing next
  path on map should always require pressing dedicated button press in sidebar to choose, so that
  player can click on nodes to preview it first. clicking on node to travel to it is bad since it
  doesnt allow preview of what is being chosen. second sidebar can cover screen without shifting
  remaining screen and moving it. map sidebar should also show a deck button to view current deck
  directly when nothing is focused similar to how game view scene does the same with deck buttons.
  map sidebar should start with this basic view since no path should be auto selected at first.
  path choices should still show deck button since its just 1 button. and doesnt require player to
  cancel current selection just to compare against talent pack." A clicked card is highlighted as
  selected; the second sidebar locks on click and is exited manually.
- **R5 pickup (B12, B13, B14)** — overturns sidebar `QR6`=a (and `Q111`–`Q129` that rest on it),
  `Q262`=a, `Q263`=a, `Q254`=d: nothing is armed until the player acts. A CLICK on an Entrance card
  lifts it (raised, not following). A DRAG from a card follows the cursor while the button is held;
  release over a legal cell places, release anywhere else returns it. With a card lifted, a click
  on a legal cell places it. Right-click and Escape cancel.
- **R6 legal-cell highlight (B7)** — narrows sidebar `GAP-005`: the legal cell's zone-card BACK
  brightens toward white, the way the focus glow lifts paper; the mark's rank and suit pips are
  excluded from the modulate. No colour cast. Follow-up ruling: the FOCUS GLOW takes the same
  exclusion - brightness lands on the card back (the Type polygon) only, never on rank, suit,
  stamp or art, on a held or focused card too.
- **R7 the Entrance (B8)** — answers grid-view's gated `Q34` (its option c); keeps poker-patience `Q40`=a: while no grid
  is committed the Entrance sits centred at the bottom of the window, aligned to no grid, and stays
  there as the view pans. Picking up a card focuses the grid nearest the screen centre and the
  Entrance slides under it. After the first placement it belongs to that grid and leaves the screen
  when the view looks elsewhere.
- **R8 grid views (B10)** — overturns the one-quantity gap ruling in `play_area.gd` (edge gap ==
  inter-grid gap): OVERVIEW draws the grids close, a small fixed gap, the set centred; FOCUSED
  centres the one grid and the isolating buffer pushes its neighbours off-screen (they stay drawn,
  outside the window).
- **R9 preview size (B4)** — overturns sidebar `GAP-004`=b: one preview size on every surface, the
  deck viewer's (`CARD_SIZE * 2`).
- **R10 card text (B5)** — extends sidebar `Q33`=c: the title is "<Rank> of <Suit>" (a face card by
  its name); below it one block per skill, stamp, status and type — the effect's NAME in the large
  font, its description in the small one. `PipRankNumeral.get_str()`'s "NumeralRank5.0" is retired
  with it. Follow-up rulings: the SUIT keeps a block of its own (title "5 of Hoop", then Hoop large
  with its prop effect small); the title uses PLURAL suit names ("King of Knives") through five
  title-only localisation keys, the singular staying everywhere else.
- **Follow-up answers (verbatim), asked after P9/P6/P16/P10/P11 landed.** R5: an off-cell drag
  release - "drag release drops"; `armed_slot()` - "delete armed slot"; HUD buttons behind the
  locked description while a card is lifted - "acceptable"; a cancelled pickup leaves the board
  focused - "yes". R6: the glow no longer lights FX - "ok"; an empty cell reads as a hotter frame
  - "ok"; the two glow values - "both should be same value", then on which - "ok 1.45". R10:
  "plural form, same as hearts spades clubs diamonds" (so "Fires", and the suit-only title is
  plural too). R8: the 100 px gap - "ok for now"; the low grid row - "not sure what this means,
  as long as no overlap and entrance is distinct". R7: any focus takes an uncommitted Entrance -
  "yes"; a committed pickup re-aims nothing - "yes until no more placeable option on grid or
  entrance cards run out"; stays under the focused grid while panning - "yes".
- **Second round of follow-up answers (verbatim).** Flat-white paper at 1.45 - "previous
  highlights looked fine, so use same value for that". The squared glow - "have card outer outline
  change/glow when focused, legal glows the inner art, not the outlines. matching marks get glow
  outline currently." A dropped card - "dropped/placed card should cancel its locked description
  and focus glow, since player should have finished reading it before they took action with the
  card." R1 on the menu - "ii hidden while nothing to show"; the overlay band - "back forward wall
  not being part of sidebar is fine."
- **The two glow clarifications (verbatim).** Which value - "same value should be whatever
  original was. if unknown go with lower value." Focus outline vs the match outline - "no
  difference between focus card outline and mark outline. both should show both outlined."
- **Plain bugs, ruled already:** B9 the drop map obeys `committed_grid` (board-plan ASSUMPTIONS "a
  cell the show cannot place into"); B11 the face-down stock card must not raise the Entrance cards
  above it (sidebar `Q249`/`Q265`: the lift belongs to the held card alone); B15 cancel works from
  anywhere on screen.

## Run rules in force
- One implementer at a time, `general-purpose` on `opus`; never two Godot runners; the second
  subagent slot is read-only work. Implementers run `--logic` and `--filter`; only the overseer
  runs the full windowed gate, and it is the verdict.
- Private `APPDATA` for every run; `GODOT_BIN` from `.claude/memory/machine-profiles.md`.
  Effect-review `.import` files are frozen (`importer="keep"`).
- Every fix: red-then-green on a named test row, `doc_check --changed` silent, one commit per
  verified fix with the evidence.
- The reviewer floor is Opus 5 or above.

## Tasks
```yaml
- id: P1
  description: B9 - the drop map asks only the committed grid once one is committed (the match rim's site is the pattern).
  files_touched: [solatro/UI/play_area.gd, solatro/Tests/Interaction/test_drag_place.gd]
  verification_command: 'run_tests.py --filter DragPlace Sidebar; overseer full gate'
  verification_kind: suite
  status: done
  evidence: 'commit 3fcbea90 (files rode in with the rulings commit). Red: PLAN VISUALS 181 passed, 1 FAILED (TP-63 drop map: 25 of 25 cells of grid 1 still mapped); green FILTERED 3 of 51 [PlanVisuals DragPlace Sidebar]: 1577 CHECKS PASSED; --logic 2990.'
  notes: 'The one call site (_sweep_legal_cells) narrows the grids; legal_cells_for and TypeGridCell untouched. TP-63 already owned the two-grid commitment fixture.'
- id: P2
  description: B15 - a right-click over the sidebar container still cancels; the container passes the second button through to the wall's routing.
  files_touched: [solatro/UI/hud_container.gd, solatro/Tests/Wall/test_sidebar.gd]
  verification_command: 'run_tests.py --filter Sidebar'
  verification_kind: suite
  status: done
  evidence: 'commit 7795568f. Red: SIDEBAR 1230 passed, 1 FAILED (a second-button press over the sidebar still released the held card); green 1231; FILTERED 4 of 51: 1502; --logic 2999.'
  notes: '_gui_input on the container cannot work: the description ScrollContainer and every Button are MOUSE_FILTER_STOP, so the container never receives gui_input, and mouse_filter = PASS still marks the event handled at the viewport. The announce is in _input, ahead of the GUI pass, gated on the container rect. Open: right-clicks over the WallOverlay button band (outside the container) are still eaten by those buttons.'
- id: P3
  description: R2 - ui_cancel zooms out to wall view after the focused screen's first refusal; wall_back stays Back; PICTURE_WALL.md and picture-wall Q100 annotated.
  files_touched: [solatro/UI/Wall/wall.gd, solatro/Tests/Wall/test_wall_input.gd, solatro/PICTURE_WALL.md, solatro/design/picture-wall/DESIGN.md]
  verification_command: 'run_tests.py --filter WallInput'
  verification_kind: suite
  status: done
  evidence: 'commit 7795568f. Red: FILTERED 3 of 51 [WallInput WallFocus Sidebar]: 1441 passed, 5 FAILED (each re-pointed row); green FILTERED 5 of 51: 1602; --logic 3000.'
  notes: 'Five rows asserted Escape = Back, not two: WALL INPUT I3/I4, WALL FOCUS M2 and its transition-lock watcher (moved from back_requested to wall_view_entered or it went vacuous), two SIDEBAR rows. wall_back is asserted at the signal level and end-to-end already.'
- id: P4
  description: R3 - after the wall reveal, Main focuses the map picture through the existing focus route; Continue with nothing pending does the same.
  files_touched: [solatro/Levels/main.gd, solatro/Tests/Wall/test_wall_transition.gd]
  verification_command: 'run_tests.py --filter WallTransition'
  verification_kind: suite
  status: done
  evidence: 'commit af9d4f8e. Red: WALL PAUSE 66 passed, 1 FAILED (the reveal carries on into the MAP picture); green 67; FILTERED 9 of 51: 2056; --logic 3004 and 2992.'
  notes: 'map_scene.start_run generates the world un-awaited and entering the map unpauses it; the WALL PAUSE fixture freed Main mid-generation (0xC0000005 at exit, 3/3 with, 0/4 without) and now latches map_ready first. The timing row stops at wall view, the length the knob scales. A solo windowed --filter WallPause ends in a teardown 0xC0000005 with or without the change - pre-existing.'
- id: P5
  description: B11 - the face-down stock card no longer displaces the Entrance cards one depth pitch up; only a held card is lifted (CardVisual.held_lift_px), and it must read against a flat row.
  files_touched: [solatro/UI/play_area.gd, solatro/Cards/card_visual.gd]
  verification_command: 'run_tests.py --filter Sidebar EntranceStocks DragPlace; by eye'
  verification_kind: snapshot
  status: done
  evidence: 'commit c5c554f0. Red: SIDEBAR 1237 passed, 2 FAILED (699.3 vs 733.3 - a stocked slot's card one pitch above an exhausted one's); green FILTERED 3 of 51: 1440; --logic 3006. By eye entrance_stocks.png: four unheld cards flat and edge-aligned, the held one alone raised, its slot's card back visible beneath. Consequence: the face-down card is unreachable by pointer while its slot holds a card; S21.5b clicks it on an emptied slot.'
  notes: 'B14 is already built (held_lift_px); it does not read because of this. Verify by eye after.'
- id: P6
  description: R6 - the legal-cell highlight brightens the zone card back toward white with the mark pips excluded; legal_cell_tint becomes that brightening, no green.
  files_touched: [solatro/Cards/card_visual.gd, solatro/Shaders/outline.gdshader, solatro/Scripts/player_settings.gd, solatro/Tests/UI/test_plan_visuals.gd]
  verification_command: 'run_tests.py --filter PlanVisuals Sidebar Pixels; by eye'
  verification_kind: snapshot
  status: done
  evidence: 'Red A (brightening forced to 1.0): FILTERED 4 of 51 [PlanVisuals Sidebar Pixels DragPlace]: 1657 passed, 12 FAILED (11 behavior) - the face-lifts-in-every-channel, equal-channel, TP-64 and drop-map rows. Red B (brightening put back on root modulate): 1660 passed, 8 FAILED - the pips-byte-identical rows (19569 bytes differ) and TP-64 no-modulate. Green: FILTERED 5 of 51 (+Palette): 1709 CHECKS PASSED, 21 placeholder warnings (PLAN VISUALS 182 -> 183, SIDEBAR 1233 -> 1238, PIXELS 51 -> 55, DRAG PLACE 191 -> 192, PALETTE 41); --logic 3005. Overseer gate: first run 5872 passed, 2 FAILED - both the known map Deck-button click flake in SIDEBAR; rerun ALL 51 SUITES: 5898 CHECKS PASSED, 21 placeholder warnings, the fingerprint exit profile, 0 SCRIPT ERROR (1 flake in 2 runs). By eye (overseer, A/B of card_lifted.png with the highlight off and shipped): legal-cell frames go (248,195,0)/(231,27,64) -> (255,255,0)/(255,39,93), every channel up or clamped; the mark pips inside the cells keep their colours (19,155,0 green unchanged); the held card paper lifts to pure white with rank, suit, stamp and art at full ink.'
  notes: 'Mechanism: uniform u_brighten on outline.gdshader, rgb only, written to the Type polygon alone from CardVisual._apply_marks via CardOutline.set_brightness (one production call site, following card_outline.gd one-static-per-uniform convention); no board mark writes modulate. legal_cell_tint (Color) -> legal_cell_glow (float, 1.45, the implementer pick); FOCUS_GLOW is a float 1.825. The placeholder-warning count is now 21 of 22. get_shader_parameter on a never-set uniform returns null, not the shader default - TestGridFixtures.brightness_of is the one reader. OPEN for the owner: (1) the focus glow no longer brightens a focused card FX (fire, juggling balls) - R6 says Type only; (2) on an EMPTY cell the back is a saturated dashed frame, so the lift reads as a hotter frame, not paper going white; (3) FOCUS_GLOW 1.825 clamps a held card paper to flat white; (4) legal_cell_glow 1.45 is unruled. OWES a sweep: test_pixels.gd (244 findings), fx_snapshot.gd (196), player_settings.gd (4) -> P18.'
- id: P7
  description: R10 - describe_card/card_info produce a title and per-effect blocks; DescriptionPanel draws names large and bodies small; PipRankNumeral.get_str retired in favour of a display name.
  files_touched: [solatro/UI/control_card.gd, solatro/UI/play_area.gd, solatro/UI/description_panel.gd, solatro/UI/description_panel.tscn, solatro/Cards/Pips/pip_rank_numeral.gd, solatro/Cards/card_data.gd, solatro/UI/map_hover_panel.gd]
  verification_command: 'run_tests.py --filter Sidebar UiViewers; by eye'
  verification_kind: snapshot
  status: done
  evidence: 'commit c5c554f0. Red: 1270 passed, 3 FAILED (NumeralRank5.0 of Knife); green 1273. By eye description.png: 5 of Hoop, then Hoop and Grid Cell large with small descriptions. Interpretations flagged to the owner: the suit keeps a block; suit names are singular (King of Knife).'
  notes: 'todo.md records the wart (NumeralRank5.0) and its wrapping fallout; both close with this. The ONLY consumers of PipRankNumeral.get_str are Cards/card_data.gd ~133 (rank.get_str().trim_suffix(".0") - the workaround itself) and ~146; control_card.gd does not call it. map_hover_panel.gd ~130 also publishes describe_card.'
- id: P8
  description: R9 - every description preview draws at the deck viewer's card size.
  files_touched: [solatro/Levels/game_view.gd, solatro/UI/hud_container.gd, solatro/UI/play_area.gd, solatro/UI/deck_viewer.gd, solatro/UI/choice_viewer.gd, solatro/UI/map_hover_panel.gd, solatro/Tools/wall_editor.gd, solatro/design/sidebar/gaps/GAP-004.md]
  verification_command: 'run_tests.py --filter Sidebar; by eye'
  verification_kind: snapshot
  status: done
  evidence: 'commit c5c554f0. Red: 1247 passed, 2 FAILED (57.6 vs 66.3 px); green 1275. By eye: board- and viewer-published previews occupy identical rectangles. CardVisual.preview_window_px is the one home; cards_viewer.card_window_px deleted.'
  notes: 'Preview publish sites: play_area.gd ~3244, deck_viewer.gd ~68, choice_viewer.gd ~154, map_hover_panel.gd ~130, wall_editor.gd ~513, game_view.gd ~271 and ~513. GAP-004 cites SIDEBAR Q34 (the card-visual size), not grid-view Q34.'
- id: P9
  description: R5 - the pickup model. Auto-arm removed; click lifts; drag follows while held; release places or returns; click on a legal cell places a lifted card.
  files_touched: [solatro/UI/play_area.gd, solatro/Levels/game_view.gd, solatro/Tests/Interaction/test_drag_place.gd, solatro/Tests/Wall/test_sidebar.gd, solatro/Tests/UI/test_plan_visuals.gd]
  verification_command: 'run_tests.py --logic; --filter DragPlace Sidebar Interaction PlanVisuals'
  verification_kind: suite
  status: done
  evidence: 'Red (production parked at HEAD, new tests kept): FILTERED 4 of 51 [DragPlace Sidebar Interaction PlanVisuals]: 1604 passed, 46 FAILED (46 behavior) - every one a named R5 check (nothing in hand after deal/placement/undo/resume; a click does not follow; button-up motion never follows; a new press alone does not restart the follow). Green: FILTERED 4 of 51: 1652 CHECKS PASSED (per suite before -> after: PLAN VISUALS 182 -> 182, INTERACTION 45 -> 46, SIDEBAR 1249 -> 1233, DRAG PLACE 170 -> 191); --logic 2987. Overseer gate: ALL 51 SUITES: 5867 CHECKS PASSED, 22 placeholder warnings, the fingerprint exit profile, 0 SCRIPT ERROR. By eye card_lifted.png (overseer): the clicked 7 of Fire alone sits raised over its own slot, the other four flat on one baseline, its description locked in the sidebar, all 25 cells tinted; implementer read entrance_stocks.png (nothing raised at rest), card_following.png (card at the cursor, slot shows the back), drag_release_returned.png (back in its slot).'
  notes: 'Deleted: PlayArea.arm_leftmost, rest_focus_on_armed, _motion_may_start_following; GameView._arm_the_entrance, arm_after_placement, _rested_the_focus. Following is gated on _drag_began and _press_data; _end_the_gesture ends it. A FRESH show never raises Game.processing, so the opening focus rests from rebuild() as well as the processing false edge (GameView._rest_the_board_focus, two call sites). OPEN for the owner: (1) armed_slot() now has only test callers - delete it and move the query into the two suites, or keep; (2) a click always locks the card description, so End/Undo/Marks sit behind the panel while a card is lifted by click - belongs to P12 if the owner wants them reachable; (3) the pad opening focus rests on the selected grid origin cell. sidebar ASSUMPTIONS.md and PLAN.md still name arm_leftmost as the plan of record.'
- id: P10
  description: R8 - a small fixed overview gap; the isolating buffer applies only while focused.
  files_touched: [solatro/UI/play_area.gd, solatro/Scripts/player_settings.gd, solatro/Tests/UI/test_grid_view.gd]
  verification_command: 'run_tests.py --filter GridView GridLayout; by eye'
  verification_kind: snapshot
  status: done
  evidence: 'Red (the view split in _apply_grid_buffer neutralised): FILTERED 1 of 51 [GridView]: 250 passed, 7 FAILED (7 behavior) - drawn gap 232 vs 100 at 2 and 3 grids, the set off-centre (left 0, right -442), the gap not returning after a focus round trip. Green: FILTERED 4 of 51 [GridView GridLayout DragPlace WallRender]: 707 CHECKS PASSED (GRID VIEW 238 -> 257, the other three unchanged); --logic 2991, 21 placeholder warnings. Overseer gate: ALL 51 SUITES: 5923 CHECKS PASSED, 21 placeholder warnings, the fingerprint exit profile. By eye (overseer, grid_zoom_shot at 3 grids): OVERVIEW three whole grids in one even row ~100 px apart, the set centred in the board window (image-measured gaps 102/102, leftovers 168/168), cards settled; FOCUSED one grid centred (leftovers 405/405), no sliver of a neighbour, neighbours drawn at x 393.7 and 1576.3 against the window 394..1576.'
  notes: 'One line of behaviour: _apply_grid_buffer (still the one per-frame writer) picks PlayArea.overview_grid_gap_px() in OVERVIEW and isolating_grid_buffer_px() in FOCUSED. game_picture_design_size is identical in both views and to before (1576x887); grid_pitch_px FOLLOWS the drawn gap (316 overview, 448 focused) because it is the overview camera step. The gap switch lands within ~0.04 s of the view change - a jump, not a slide. TP-113 and TP-138 needed nothing; TP-106 re-pointed to FOCUSED (four of five grids now fit the overview, so panning no longer shifts the framing). grid_zoom_shot.gd had two instrument bugs, both fixed: it photographed the WINDOW (cropping the 1576 px picture to 1152, so the third grid never appeared in any earlier shot) and it grabbed mid-deal, two frames after printing; it now waits on a probe of every reported rect and every CardVisual being still, and quits nonzero if the probe moves across the grab. OPEN for the owner: grid_overview_gap_cards = 2.5 card widths (100 px) is the implementer pick; the floor is ~88 px, the two score gutters; in the overview the grid row sits low in the window, against the Entrance line (not covered by R8). OWES a sweep: test_grid_view.gd (236 findings), grid_zoom_shot.gd (7), and 5 dead references in poker-patience DESIGN.md ~889, ~1021 and NAMES.md ~197-198 -> P19.'
- id: P11
  description: R7 - the uncommitted Entrance is centred and grid-free; a pickup focuses the nearest grid and the Entrance slides under it; a committed Entrance stays with its grid.
  files_touched: [solatro/UI/play_area.gd, solatro/Levels/game_view.gd, solatro/Tests/UI/test_grid_view.gd, solatro/Tests/Interaction/test_drag_place.gd]
  verification_command: 'run_tests.py --filter GridView DragPlace EntranceStocks; by eye'
  verification_kind: snapshot
  status: done
  evidence: 'Red (home grid forced to pan_grid, slide lerp forced to 1, focus_the_grid_in_view returned at entry): FILTERED 4 of 51 [GridView GridLayout DragPlace Interaction]: 680 passed, 20 FAILED (20 behavior) - 19 named R7 checks (centred 827 vs 985, stayed put while panning, passes through the positions between: 0 of 63 samples, a cancelled pickup leaves the board focused, a drag pickup focuses, the pickup takes grid 1 not the focused grid, the slide finishes after wall view) plus one hit of the known GRID VIEW pan-right flake. Green: FILTERED 7 of 51: 2216 CHECKS PASSED (GRID VIEW 257 -> 278, DRAG PLACE 192 -> 237, GRID LAYOUT 138 -> 139, SIDEBAR 1265 -> 1266, INTERACTION 46, ENTRANCE STOCKS 31); --logic 3003, 21 placeholder warnings. Overseer gate: ALL 51 SUITES: 5998 CHECKS PASSED, 21 placeholder warnings, the fingerprint exit profile, 0 SCRIPT ERROR. By eye (overseer, grid_zoom_shot 3 grids): uncommitted overview - the Entrance centred in the window at the bottom; slide_0 -> slide_1 - the row further right each frame with the clicked Queen raised (implementer image-measured centre 985 -> 1163 -> 1289 -> 1311.5 over ~0.35 s); at rest under the focused grid (0.15 px); committed to grid 0 and looking at grid 2 - no Entrance card anywhere in the window.'
  notes: 'One writer still: _sync_entrance_x lerps between the window-centred x and the home grid columns by _entrance_slide, which _advance_the_entrance_slide moves toward the derived aim every physics frame (no tween, so the ALWAYS-node trap does not arise; a paused tree freezes it and returning finishes it). entrance_home_grid() = committed_grid, else focused_grid while FOCUSED, else NO_GRID. In the OVERVIEW the nearest grid IS pan_grid (the wall camera is the only thing that moves the view); geometry decides only while FOCUSED. OPEN for the owner (readings R7 does not state): (a) a cancelled pickup leaves the board focused and the Entrance under that grid until the overview returns; (b) a drag pickup focuses as a click does; (d) ANY focus of a grid, not only a pickup, takes an uncommitted Entrance under it; (e) once a grid is committed a pickup re-aims nothing; (f) uncommitted and FOCUSED, the Entrance stays under focused_grid when the view pans to a neighbour. Found and filed: P20, P21.'
- id: P12
  description: R1 - the sidebar overlays and slides in after a picture lands and out before it leaves; no picture inset; hidden on the menu and in wall view; the half-width all-edge inset decided on the investigation's numbers.
  files_touched: [solatro/UI/hud_container.gd, solatro/Levels/game_view.gd, solatro/Levels/map.gd, solatro/Levels/menu.gd, solatro/Levels/main.gd, solatro/UI/Wall/wall_picture.gd]
  verification_command: 'run_tests.py --filter Sidebar WallTransition WallRender; by eye'
  verification_kind: snapshot
  status: in_progress
  evidence: ''
  notes: 'IN THE TREE, UNCOMMITTED, NOT ACCEPTED: parts A-D built and every check green (overseer full gate 6174..6211 PASSED) but the ENGINE CRASHES AT EXIT, 0xC0000005 after the banner, in 5 of 5 overseer gates on this tree against 0 of 14 before it. Found so far: cause 1 (await tween.finished + kill() never emits) fixed - Sidebar alone 4/4 -> 0/3; the slide is integrated in _process and waiters await the container slide_settled signal, emitted from _exit_tree too; the six-suite wall filter still 3/3, and 1/3 on HEAD-parked production; one headless --logic run crashed too. A fresh implementer is bisecting with --logic as the reproducer. Also built: the board TRANSLATES the sidebar whole width (394 picture px) while its zoom stays fitted to the resting window (board_zoom 1.7382 in all eight sampled frames); the probe Tests/Visual/sidebar_overlay_probe waits on card stillness. FILE AFTER P12: re-entering a picture from wall view draws the board ~2x for a frame or two (the SubViewport still at its wall-view render size; WallPicture.focus is untouched by P12). RULED: option (ii), hidden while nothing to show; the Back/Forward/Wall band stays where it is. The question was - the menu DOES publish into the container: Levels/menu.gd _on_new_run_pressed opens a DeckPicker whose highlighted cards draw their description there. Option (i) hidden on the menu, full stop - the picker descriptions lose their surface; option (ii) hidden while it has nothing to show - on the menu the container slides in while a description shows and out when dismissed. PHASE 1, measured on the booted Main at 1152x648 (probe Tests/Visual/sidebar_overlay_probe, untracked, PNGs in the scratchpad): every picture ALREADY covers the window edge to edge (menu and map exactly, the game 11.5 px beyond by wall_overfill_margin); container_size_fraction never reaches the camera, only board_inset_left (394 picture px) and Map.apply_container_shift. So there is no picture inset to remove at 16:9; the work is the slide, the content shift and the menu hide. No authored half-width inset is needed: every screen RE-CENTRES in the space beside the container, so content moves HALF the sidebar width (map -144 window px; board centre 788 -> 985 picture px) and the resting geometry is today's - the 394/262.7 gates and the P10/P11/P21 rows stay true at rest. Proposed: HudContainer owns one _slide fraction and a published_rect() that rect_beside and GameView._publish_board_inset read; the tween lives on HudContainer (Overlay is process_mode ALWAYS); one new duration knob; the pre-camera hook on _go_to_wall_view is confirmed missing. The overlay Back/Forward/Wall band is not part of the container and stays put. Earlier investigation: Investigation done. (1) Zero inset = container_size_fraction contributing 0 to visible_rect_beside: board_inset_left/top become the crop alone (0 at the picture aspect). (2) k for a symmetric all-edge inset is EXACTLY 0.5 of the container width (394 picture px at 1152x648 -> 197 px per edge): clearing the sidebar needs kC + shift >= C and not leaving the picture needs shift <= kC, so 2kC >= C; below 0.5 the edge column cannot stay visible. GAP-002 crop contributes 0 at 16:9; wall_overfill_margin 1.02 already draws the picture ~1% off-screen per side. (3) Hooks: transition_landed (main.gd ~477) for slide-IN; slide-OUT before leaving has NO pre-hook on the wall-view path (_go_to_wall_view awaits _animate_camera before set_active_screen(&"")) - add one before the await; picture->picture has transition_started. The container has no animated position today; a slide tween must live on an always-processing node (main.gd ~400-406 trap). (4) Content shift: map (camera offset) and menu (authored re-fit) are per-frame safe; the board re-centres through focus_grid -> _recentre_board, an async settle - drive it once at slide end, not per frame. (5) Overlay coverage at zero inset: the container IS the game HUD (nothing under it) but covers the Entrance strip from x 0 and the wall overlay Back/Forward/Wall buttons sit inside a left band; map dots and menu buttons need a render to say.'
- id: P13
  description: R4 - a second, lockable sidebar for pack previews with a Take button; map travel through a sidebar button after previewing; a Deck button on the map sidebar at rest.
  files_touched: [solatro/UI/hud_container.gd, solatro/UI/hud_container.tscn, solatro/UI/description_panel.gd, solatro/UI/choice_viewer.gd, solatro/Levels/map.gd, solatro/Locale/localization.csv]
  verification_command: 'run_tests.py --filter Sidebar MapTraversal WallInput; by eye'
  verification_kind: snapshot
  status: pending
  evidence: ''
  notes: 'Investigation done. ALREADY SHIPPED: MapHud has MapDeckButton (hud_container.tscn ~142-166, opens DeckViewer over the run deck, map.gd ~55); the pack is taken by ChoiceViewer %ConfirmButton -> _on_confirm_pressed (choice_viewer.gd ~158) - so "Take" exists and a click on a viewer card does NOTHING today (hover/focus previews only). NEW: a click selects + highlights a viewer card (no viewer card has a selected visual; the board has locked_data); the second panel is a second DescriptionPanel added to WallOverlay beside the one HudContainer - NOT a second HudContainer, which would re-emit container_rect_changed and duplicate the screen-keyed lock machinery; it must never emit a rect change. MAP: one click on a reachable dot travels today (world_map_controller.gd ~255-271 _travel_to on release); keyboard has _kb_index as the only selection state; hover -> node_hovered -> MapHoverPanel.get_info -> the sidebar. Travel button belongs in MapHud beside MapDeckButton, wired through connect_for_screen in Map._bind_hud_container, calling controller.move_to(selected). No TAKE/TRAVEL localisation keys exist; Confirm and the map HUD labels are hard-coded in scene/script. Tests that pin the old model: test_sidebar.gd test_one_click_travels_and_leaving_keeps_the_last_nodes_description (~5166, the assertion ~5180: one click enters the node) - contradicts R4; the two-tap assertions ~5192-5201; ~1086 MapHud-holds-exactly-four (a Travel button breaks it), ~1171 camera-offset-beside-container (breaks under R1), ~845/853 the 394/262.7 inset gates; test_ui_viewers.gd ~137 calls _on_confirm_pressed directly. test_map_traversal.gd pins NOTHING here: its rows call controller.move_to directly, which is the API the Travel button calls.'
- id: P14
  description: The comment sweep the fixes owe - main.gd, test_wall_input.gd, test_wall_focus.gd, test_wall_pause.gd leave compliant (whole-file on touch), code byte-identical.
  files_touched: [solatro/Levels/main.gd, solatro/Tests/Wall/test_wall_input.gd, solatro/Tests/Wall/test_wall_focus.gd, solatro/Tests/Wall/test_wall_pause.gd]
  verification_command: 'py .claude/tools/sweep_check.py <each file>; doc_check --changed silent; run_tests.py --filter WallInput WallFocus WallPause'
  verification_kind: suite
  status: done
  evidence: 'commit 6e669b47. Findings 116/123/90/86 -> 0/0/4/0; sweep_check CODE IDENTICAL x4; dup_check no new pair. The four left are one note kept beside each of five fixture sites in test_wall_focus.gd.'
  notes: 'Its own step, after the fixes, never folded into one (plan-run: a sweep once deleted a load-bearing note). ~400 findings across the four; every later step that touches a legacy file owes the same.'
- id: P15
  description: B15 remainder - a right-click over the WallOverlay button band (Back/Forward/Wall, outside the container) still cancels; the owner ruled cancel works from anywhere.
  files_touched: [solatro/UI/Wall/wall_overlay.gd, solatro/UI/Wall/wall.gd, solatro/Tests/Wall/test_sidebar.gd]
  verification_command: 'run_tests.py --filter Sidebar WallInput'
  verification_kind: suite
  status: pending
  evidence: ''
  notes: 'Same announce-ahead-of-the-GUI-pass shape P2 used on the container; the band buttons are MOUSE_FILTER_STOP too.'
- id: P16
  description: R10 follow-up - the title pluralises the suit ("King of Knives"): five title-only localisation keys and one accessor; the singular stays everywhere else.
  files_touched: [solatro/Locale/localization.csv, solatro/UI/control_card.gd, solatro/Cards/Pips/, solatro/Tests/Wall/test_sidebar.gd]
  verification_command: 'run_tests.py --filter Sidebar UiViewers'
  verification_kind: suite
  status: done
  evidence: 'Red (keys and test in, card_title still singular): FILTERED 1 of 51 [Sidebar]: 1255 passed, 10 FAILED (10 behavior) - the numeral and court title of each of the five suits, by name. Green: FILTERED 2 of 51 [Sidebar UiViewers]: 1291 CHECKS PASSED (SIDEBAR 1240 -> 1265, UI VIEWERS 26); --logic 2994, 21 placeholder warnings. Overseer gate: ALL 51 SUITES: 5914 CHECKS PASSED, 21 placeholder warnings, the fingerprint exit profile, 0 SCRIPT ERROR. By eye (overseer) description.png reads "5 of Fires" over a large "Fire" block; viewer_description.png "2 of Hoops" over "Hoop"; one line each, no wrapping.'
  notes: 'PipSuit.get_plural_str(), abstract, one override per suit, one production caller (ControlCard.card_title); keys SUIT_<NAME>_PLURAL: Hoops, Knives, Balls, Fires, Fireworks. localization.en.translation is tracked and regenerated by a headless --import. OPEN for the owner: (1) "Fires" vs the mass noun "5 of Fire"; (2) the suit-only title arm (a card with no rank) stays singular. pip_suit_test.gd owes a sweep (5 legacy findings) -> P18.'
- id: P22
  description: The follow-up answers, built - an off-cell drag release DROPS the card (hand empty, drop map out, description unlocked as a cancel leaves it); PlayArea.armed_slot() deleted, its query moved into the suites; the suit-only title arm uses the plural; legal_cell_glow and FOCUS_GLOW become ONE value in one home.
  files_touched: [solatro/UI/play_area.gd, solatro/UI/control_card.gd, solatro/Cards/card_visual.gd, solatro/Scripts/player_settings.gd, solatro/Tests/Interaction/test_drag_place.gd, solatro/Tests/Wall/test_sidebar.gd, solatro/Tests/Visual/sidebar_snapshot.gd]
  verification_command: 'run_tests.py --filter DragPlace Sidebar Interaction PlanVisuals Pixels; by eye'
  verification_kind: snapshot
  status: done
  evidence: 'Four sub-fixes, each red then green. A (release parked): FILTERED 1 of 51 [DragPlace]: 245 passed, 11 FAILED - the hand not empty, 24/25 cells still lit, the three away-from-the-cells places; green 256. B (the shared helper scan reversed): 1521 passed, 2 FAILED (the refill lands in the leftmost slot; the 6.10 undo row). C (focus arm at 1.825): PIXELS 54 passed, 2 FAILED - SAME multiplier, legal (0.9221,0.8904,0.8479) vs focused (0.9368,0.9075,0.8535); green 56. D (suit-only arm singular): SIDEBAR 1271 passed, 6 FAILED - one per suit plus a lit_cell_count consequence of C; green 1277. Wide: FILTERED 8 of 51: 2231 CHECKS PASSED, 21 placeholder warnings (DRAG PLACE 237 -> 256, SIDEBAR 1266 -> 1277, PIXELS 55 -> 56, others unchanged); --logic 3001. Overseer gate: ALL 51 SUITES: 6109 CHECKS PASSED, 21 placeholder warnings, the fingerprint exit profile, 0 SCRIPT ERROR; after the gate only check() message text and comments changed (design ids stripped), re-run FILTERED 2 of 51 [DragPlace Sidebar]: 1533 CHECKS PASSED. By eye (overseer): card_lifted.png - the clicked Jack raised, 25 frames lit, pips full ink, paper flat white; drag_release_dropped.png - five cards on one baseline, every frame back to amber/dark red, the dropped card paper still white (it holds focus) and its description still locked (it was click-lifted first).'
  notes: 'PlayerSettings.highlight_glow = 1.45 is the one glow, applied once per mark (legal AND focused draws at its square, 2.1025; TestGridFixtures.lit_cell_count expects that). The drop is the cancel route (ungrab_cards) from the one _on_card_dropped decision, only for a gesture that carried the held card; a drag from an already click-lifted card drops too. armed_slot() -> TestGridFixtures.leftmost_entrance_slot(). A suit-only card is player-visible (BoosterTemplate.get_possible_preview_cards). committed_grid clears in Game._commit_placement when no Entrance card has a legal cell on it (an empty Entrance included) and in GameData.rebase_commitment when the grid is removed - the owner condition; asked only after a placement. OPEN for the owner: 1.45 still clamps the paper to (255,255,255) - anything above ~1.08 does; the squared glow on a legal focused cell; a dropped card keeps the focus glow and a click-made description lock. sidebar ASSUMPTIONS.md ~455 and PLAN.md ~170 still name armed_slot/arm_leftmost as the plan of record.'
- id: P23
  description: The second follow-up answers, built - FOCUS is shown by the card OUTER OUTLINE changing/glowing, not by brightening the face; LEGAL brightens the inside of the card and never the outline; a placed or dropped card clears its locked description and its focus glow.
  files_touched: [solatro/Cards/card_visual.gd, solatro/Cards/card_outline.gd, solatro/Shaders/outline.gdshader, solatro/UI/play_area.gd, solatro/Levels/game_view.gd, solatro/Tests/Visual/test_pixels.gd, solatro/Tests/Wall/test_sidebar.gd, solatro/Tests/Interaction/test_drag_place.gd]
  verification_command: 'run_tests.py --filter Pixels PlanVisuals Sidebar DragPlace Interaction; by eye'
  verification_kind: snapshot
  status: pending
  evidence: ''
  notes: 'RULED, both. The original highlight value is KNOWN: CardVisual.FOCUS_GLOW := Color(1.825) at 19ace1be (the legal cell was a green tint then, not a multiplier), so highlight_glow = 1.825. A focused card takes the SAME outline the match rim draws (set_rim) - no difference; a card that is both is simply outlined. So: focus stops brightening the face and asks for the rim; legal brightens the face only. Run AFTER P12 lands (both touch play_area.gd / game_view.gd). The clarifications that were asked: (1) "use same value" - which value is the legal-cell brightening: the earlier 1.825 or the ruled 1.45; (2) the match rim ALREADY glows the outline (set_rim) - how a focused card outline differs from a matching mark outline (a colour, a width, a pulse), and what a card that is both shows. With focus on the outline the squared glow disappears by construction. The drop/place half is unblocked: the drop and the placement both end in ungrab_cards; add clear_lock/dismiss and release the focus there, one route, and invert P22 rows that pinned "exactly what a cancel leaves".'
- id: P20
  description: The SCRIPT ERROR reported in HudContainer.return_to_lock (key game missing from _locked_entry_by_screen) - closed as NOT REPRODUCIBLE on HEAD; a regression net lands instead.
  files_touched: [solatro/Tests/Wall/test_sidebar.gd]
  verification_command: 'run_tests.py --filter Sidebar WallFocus WallInput'
  verification_kind: suite
  status: done
  evidence: 'No production change. The one sighting (run-output 10:45, inside P11 development, before P11 and P22 were committed; trace: return_to_lock from the card mouse_exited lambda, after click-lock, right-click cancel, open_zoomed_out) was driven step for step through real input on the booted Main, plus one and two cancel steps, the P22 drop, the exit X, ui_cancel, wall_overview, Back, a wall-view round trip with a held card, focus to the HUD, New Run: 0 SCRIPT ERROR in 6 runs, the two lock dictionaries agreeing after all 18 events. FILTERED 3 of 51 [Sidebar WallFocus WallInput]: 1535 CHECKS PASSED (SIDEBAR 1294 -> 1320); --logic 2981. Overseer gate: ALL 51 SUITES: 6129 CHECKS PASSED (SIDEBAR 1320), 21 placeholder warnings, 0 SCRIPT ERROR.'
  notes: 'Writers table: lock_to, clear_lock, release_screen and dismiss_description (through show_hud -> clear_lock) write both dictionaries together; the ONE asymmetric writer is _exit_tree (clears the entries only), and GameView.tree_exiting -> release_screen always runs first. A drag pickup never locks (lock_to is reached only from a click). FOR /simplify AT THE CLOSE, approved by the overseer but not applied because no check can go red for it: _lock_by_screen VALUE is never read (only .has) - collapse onto _locked_entry_by_screen, is_locked() reads it, lock_to() loses its dead target parameter (callers game_view.gd, Tools/wall_editor.gd, three test sites, sidebar NAMES.md). Where to look if it recurs: a cancel is refused while the panel is hidden (GameView._on_description_dismiss_requested returns unless showing_description), so _swap_to_hud from set_active_screen can leave is_locked() true with the panel down.'
- id: P21
  description: R8 on an EDGE grid - FOCUSED on the last (or first) of three grids the scroll clamps, the grid sits off-centre (cells 1124..1500 in a window centred at 985) and its neighbour is wholly visible inside the window; P10 measured only the middle grid.
  files_touched: [solatro/UI/play_area.gd, solatro/Tests/UI/test_grid_view.gd, solatro/Tests/Visual/grid_zoom_shot.gd]
  verification_command: 'run_tests.py --filter GridView GridLayout WallRender; by eye'
  verification_kind: snapshot
  status: done
  evidence: 'Measured first in the real Main, fix absent: 2 grids - focused 0 centre 658.21 (-326.79), focused 1 1312.62 (+327.62); 3 grids - 0 at 658.21, 1 at 985.00, 2 at 1311.79; a neighbour inside the window in every edge case, by every route. Red (the multi-grid gate neutralised): GRID VIEW 326 passed, 20 FAILED (20 behavior) of 346 - each edge grid by click, pan and pickup: not centred, neighbour in view; the middle grid stayed green. Green: FILTERED 4 of 51 [GridView GridLayout DragPlace WallRender]: 842 CHECKS PASSED (GRID VIEW 324 -> 346, others unchanged); --logic 3004, 21 placeholder warnings. Overseer gate: ALL 51 SUITES: 6061 CHECKS PASSED, 21 placeholder warnings, the fingerprint exit profile, 0 SCRIPT ERROR. By eye (overseer) shots_p21 grid_zoom_3_committed_elsewhere.png: focused on the last of three, the one grid centred (columns 799..1170, window centre 985), no neighbour, no Entrance; implementer image-measured 984.5 / ~985 on all five focused stills.'
  notes: 'While FOCUSED with more than one grid, _apply_grid_buffer (still the one writer) also sets the scroll container panel content margins to isolating_grid_buffer_px minus the score gutter (188 px), then queue_sort; SmoothScrollContainer clamps a programmatic scroll to the content range and has no overscroll option (addons/SmoothScroll smooth_scroll_container.gd ~613-630, helpers/scroll_layout.gd). The picture size and grid_pitch_px are unchanged. TP-140 was green because it focuses the middle grid, the one index the clamp never bites. A neighbour edge now lands EXACTLY on the window edge at every edge grid (decided with is_equal_approx). OPEN: one TP-105 failure in 8 GridView runs on an intermediate state read edge 316.000 vs 413.119 - 97 px, not a float ULP, not reproduced; do not file it under the known flake without a look.'
- id: P19
  description: The comment sweep P10 owes - test_grid_view.gd and grid_zoom_shot.gd leave compliant, code byte-identical; the five dead references in poker-patience DESIGN.md and NAMES.md resolved.
  files_touched: [solatro/Tests/UI/test_grid_view.gd, solatro/Tests/Visual/grid_zoom_shot.gd, solatro/design/poker-patience/DESIGN.md, solatro/design/poker-patience/NAMES.md]
  verification_command: 'py .claude/tools/sweep_check.py <each .gd>; doc_check --changed silent; run_tests.py --filter GridView; overseer full gate'
  verification_kind: suite
  status: done
  evidence: 'Findings 236/7/9 -> 0/0/0 (test_grid_view, grid_zoom_shot, test_grid_layout) and 5 dead doc references -> 0; sweep_check CODE IDENTICAL x3 (1982, 226, 1266 code lines), re-run by the overseer; doc_check --changed silent; dup_check 82, no new pair. FILTERED 2 of 51 [GridView GridLayout]: 485 CHECKS PASSED (346 + 139); --logic 3006; grid_zoom_shot.tscn quit by itself, 0 SCRIPT ERROR. Overseer gate: ALL 51 SUITES: 6131 CHECKS PASSED, 21 placeholder warnings, the fingerprint exit profile, 0 SCRIPT ERROR.'
  notes: 'Dropped restatements are quoted in the P19 commit message. doc_check FILEREF clips a file name out of a path with spaces (the curated-effects index was read as its last word plus the extension) - the two were reworded, the tool is unchanged. Design ids stay in check() strings (144 and 18). The grid_zoom_shot CUT OFF caption fires on every off-window neighbour by design of the print; misleading, a string, untouched.'
- id: P18
  description: The comment sweep P6 owes - test_pixels.gd, fx_snapshot.gd, player_settings.gd and (owed by P16) Tests/Support/pip_suit_test.gd leave compliant, code byte-identical.
  files_touched: [solatro/Tests/Visual/test_pixels.gd, solatro/Tests/Visual/fx_snapshot.gd, solatro/Scripts/player_settings.gd]
  verification_command: 'py .claude/tools/sweep_check.py <each file>; doc_check --changed silent; run_tests.py --filter Pixels; overseer full gate'
  verification_kind: suite
  status: done
  evidence: 'Findings 254/207/4/5 -> 0/0/0/0 (test_pixels, fx_snapshot, player_settings, pip_suit_test); sweep_check CODE IDENTICAL x4 (655, 555, 383, 13 code lines), re-run by the overseer; doc_check --changed silent, exit 0; dup_check 83, no new pair. FILTERED 1 of 51 [Pixels]: 55 CHECKS PASSED; --logic 3003; fx_snapshot.tscn ran to its last panel, exit 0, 0 SCRIPT ERROR. Overseer gate: ALL 51 SUITES: 5897 CHECKS PASSED, 21 placeholder warnings, the fingerprint exit profile, 0 SCRIPT ERROR.'
  notes: 'Kept above their methods: every measured tolerance with its derivation (EDGE_WEDGE_DRIFT 1.7, CORNER_BITE_DRIFT 2.6), the ordering constraints, the renderer traps, what each still is for. Four restatements dropped, their text in the P18 commit message. OPEN: fx_snapshot.gd header says rotated panels are not reproducible while _settle_poses claims the cause fixed - both kept; reconciling them is a measurement (snapshot_diff.py NOISY, HEADLESS_TESTING.md section 0b). Two capture() captions in fx_snapshot.gd carry design ids (burned into the PNG header) - code, so not swept.'
- id: P17
  description: The comment sweep P9 owes - game.gd and test_interaction.gd leave compliant, code byte-identical; sidebar DESIGN.md loses its three dead file references (~220, ~225, ~485).
  files_touched: [solatro/Levels/game.gd, solatro/Tests/Interaction/test_interaction.gd, solatro/design/sidebar/DESIGN.md]
  verification_command: 'py .claude/tools/sweep_check.py <each .gd>; doc_check --changed silent; run_tests.py --filter Interaction; overseer full gate'
  verification_kind: suite
  status: done
  evidence: 'Findings 8/10 -> 0/0 (game.gd, test_interaction.gd); sweep_check CODE IDENTICAL x2 (827 and 354 code lines); doc_check --changed silent, exit 0; dup_check 83, no new pair. FILTERED 1 of 51 [Interaction]: 46 CHECKS PASSED; --logic 3022. Overseer gate: ALL 51 SUITES: 5864 CHECKS PASSED, 22 placeholder warnings, the fingerprint exit profile, 0 SCRIPT ERROR.'
  notes: 'DESIGN.md dead paths now name UI/description_panel.gd, Tests/Wall/test_sidebar.gd, Tests/Visual/sidebar_snapshot.gd; doc_check does not resolve bare inline-code paths inside a markdown table, so they were fixed by hand. OPEN: the same table (sidebar DESIGN.md "Info mode, as it exists", rows ~214, ~217, ~221, ~224) still names wall_info_mode, _on_info_toggled, info_zoom_state, _apply_info_mode, _restore_info_mode_for, none of which exists in any .gd - for /docs at the close. Design ids stay in two check() strings (test_interaction.gd ~480, ~489), which are code.'
```

## Verified vs assumed
- The research behind every ruling's "overturns" line: two read-only Explore agents on `opus`,
  file:line cited in their reports; not re-read by the overseer.

## Open bugs
- OWNER DECISION, a product crash at quit: quitting (or freeing Main) while the world map is still generating lets the vendored generator resume one more stage on a dying tree - 0xC0000005 at process exit, no backtrace. Isolated: Main._on_continue calls map_scene.start_run un-awaited -> Map.start_run -> WorldMapController.start_run `await map.generate()` -> addons/worldgen/world_map_2d.gd ~169 `await gen.generate_world_map()`, whose stage loop steps on get_tree().process_frame; the last line logged after the banner was the Rivers stage at 0.857, Painting never reached. `test_continue_after_a_mid_show_quit_still_reveals_wall_view` alone crashes 3 of 3 (~2 s), 0 of 3 when it waits 243 ms for generation's true end. Map cannot settle or cancel from _exit_tree and the addon exposes no cancel. Minimal addon-side change (NOT made; worldgen is vendored from worldgen/): a cancel flag the stage loop checks between stages, set on exit, or stepping on its own node instead of the tree's process_frame. P12 only exposes it: its slide adds ~0.5 s per focus move, moving the fixture's free from before the generator spawns to inside its stage loop. The fixture now latches on generation's end, as the reveal test already did.
- The SIDEBAR map Deck-button click flake (HEADLESS_TESTING.md section 4) failed twice after P6 landed - 1 of the overseer's 3 full gates since, and 1 of an implementer's filtered Sidebar runs (its total not counted) - each green on the single rerun; 0 of the 3 overseer gates before P6. Not yet measured whether the rate moved - run `--filter Sidebar` N times at 30143594 and at HEAD before naming a cause.
- A worldgen teardown abort (0xC000001D in addons/worldgen/core/steps/rivers.gd, a river step reading a freed object while a Main is torn down mid-generation - the un-awaited map_scene.start_run path P4 notes) hit 1 abort plus 1 post-banner SCRIPT ERROR in an implementer's 5 Sidebar-including runs during P22; 0 of the overseer's gates.
- `PIXELS: fire brightens when its host is highlighted` failed once (0.272 plain vs 0.250 highlighted) in 1 of 5 overseer gates on the P12 tree, never before; nothing in P12 reaches that suite. Measure before naming a cause.
- none else beyond the tasks. OWNER, R5 reading to confirm: a drag released off a legal cell puts the card back over its slot but it stays IN HAND (lifted, drop map lit) until placed or cancelled - 'release anywhere else returns it' was read as returns-to-slot, not drops-the-hold. From the bloat review of the P9 commit (opus, read-only): `PlayArea.rest_focus_on_board()` keeps a fallback for a held card with no control, whose only named producer was the deleted auto-arm - settle by `assert` plus a suite run, back it out if a fixture fires it; `_release_places` and `follow_cards` each have one call site (both predate P9).

## Next up
1. P12 before P13: both edit hud_container.gd and map.gd and re-point the same inset gates (test_sidebar ~846/854, ~1087, ~1172); P13 inherits P12's rewritten set. P15 is small.
2. After the last step: the rest_focus_on_board assert check and the owner's three open P22 questions (Open bugs / P22 notes), then `/docs` folds this file away; the owner merges the branch.

### Opening prompt for the next session (paste as is)

```
Resume solatro/HANDOFF_playtest_fixes.md on branch combine-sidebar-boardplan (never main; commit per verified step on this branch). Read CLAUDE.md, then the handoff: its rulings R1-R10 are the owner's verbatim decisions and outrank the design questions they name; each pending task row's notes: carries the site map an implementer follows. Confirm the tree is green first: Get-Process shows no Godot, then the full windowed run with a private APPDATA and GODOT_BIN from .claude/memory/machine-profiles.md - expect ALL 51 SUITES ... CHECKS PASSED, 22 placeholder warnings, the 1150 ObjectDB note. Then dispatch P9 to ONE general-purpose implementer on opus (default effort) with the P9 notes as its brief, the run rules from the handoff (implementers run --logic and --filter only; you run the gate; red-then-green on every row; a file it edits leaves doc_check --changed silent, the sweep as a separate pass proven code-identical), and the fixed report schema (FIX/STATUS/FILES/RED/GREEN/BY EYE/DOC_CHECK/NOTES). At most two subagents, only one runs Godot; the second slot is read-only work. Commit each verified step with its evidence, mark the row done in the handoff, run the gate, then the next row in the Next up order. Ask the owner only when a ruling does not cover a decision; record every answer verbatim under the design it changes (the ASSUMPTIONS.md sections titled Owner rulings from the first playtest) and in the handoff.
```

# HANDOFF — playtest fixes (the combined branch's first playtest)

**Goal:** the sixteen findings of the owner's first playtest on `combine-sidebar-boardplan` fixed
and gated, each against the ruling below, on this branch, ready for the owner to merge.
**State:** P1–P5, P7–P9 and the P14 sweep landed, each red-then-green and by eye, committed one
step per commit. Last gate, on the P9 commit: `ALL 51 SUITES: 5867 CHECKS PASSED`, 22 placeholder
warnings, 1150 ObjectDB (the fingerprint). P17 (the sweep P9 owed), P6 and P16 landed too; the P18 sweep, P10 and P11; last gate `5998`, 21 placeholder warnings. P21 (R8 on an edge grid) landed, gate `6061`. Next is P22 (the follow-up answers), P20 (a reachable SCRIPT ERROR), then the P19 sweep; every
later step has its site map in its `notes:`. Gate at the
stream's start: `ALL 51 SUITES: 5839 CHECKS PASSED`, errors log empty.
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
  notes: 'Mechanism: uniform u_brighten on outline.gdshader, rgb only, written to the Type polygon alone from CardVisual._apply_marks via CardOutline.set_brightness (one production call site, following card_outline.gd one-static-per-uniform convention); no board mark writes modulate. legal_cell_tint (Color) -> legal_cell_glow (float, 1.45, the implementer pick); FOCUS_GLOW is a float 1.825. The placeholder-warning count is now 21 of 22. get_shader_parameter on a never-set uniform returns null, not the shader default - TestGridFixtures.brightness_of is the one reader. OPEN for the owner: (1) the focus glow no longer brightens a focused card FX (fire, juggling balls) - R6 says Type only; (2) on an EMPTY cell the back is a saturated dashed frame, so the lift reads as a hotter frame, not paper going white; (3) FOCUS_GLOW 1.825 clamps a held card paper to flat white; (4) legal_cell_glow 1.45 is unruled. OWES a sweep: test_pixels.gd (244 findings), fx_snapshot.gd (196), player_settings.gd (4) -> P18. Site map the step followed: TP-64 pins that the match tints nothing; keep it discriminating. Site map done. A zone card is five Polygon2Ds under Offset/Visual (card_visual.tscn ~705-745): Type (the cell frame, atlas frame 2 via CardOutline.frame_polygon), Rank, Suit, Stamp, Art; a mark draws Rank/Suit/Art onto the same card and _hold_mark_back (card_visual.gd ~264-267) already hides exactly [rank, stamp, suit, art] and leaves Type - the codebase's own back-vs-mark split. Every polygon carries its own runtime outline.gdshader ShaderMaterial (card_outline.gd ~65-87); the shader multiplies by vertex COLOR at ~227, so root modulate reaches all five and self_modulate on the pips would be a second colour writer (forbidden: card_visual.gd ~124-127 is THE ONE PLACE modulate is written; TP-61 ~225-233 pins self_modulate WHITE). The per-element channel that exists: a shader uniform set per polygon from CardVisual._push_outline_ink (~276-286, already five set_rim calls) - add a brightness uniform for Type only, do not collide with u_fill_index/u_fill_mode. Value: an equal-channel multiplier above 1 is what the palette drift scan recognises as brightness, not colour (test_palette.gd ~229-235 allow-lines FOCUS_GLOW := Color(1.825); legal_cell_tint's raw literal is the 22nd of 22 allowed placeholder warnings, todo.md ~186-189 - moving it to that allow-line or a palette role returns the slot). FOCUS_GLOW (1.825) lifts the pips too today; see the owner's answer on whether it takes the same exclusion. TESTS: TP-64 ~998-1004 KEEP if the brightening stays on tint/modulate, RE-POINT if it moves to the uniform; tinted_cell_count (test_grid_fixtures ~275-280, reads modulate) and test_sidebar 6.11 readers _tint_of ~4474 RE-POINT with it; PIXELS 6.12 ~1032-1038 asserts green up AND red down -> RE-POINT (no colour cast); ~1039-1041 whole-card mean == plain x tint -> RE-POINT once pips are excluded; ~1048-1051 WHITE == no tint KEEP. Docs: sidebar TEST_PLAN 6.11/6.12, NAMES.md ~139, GAP-005/GAP-011 status.'
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
  notes: 'Deleted: PlayArea.arm_leftmost, rest_focus_on_armed, _motion_may_start_following; GameView._arm_the_entrance, arm_after_placement, _rested_the_focus. Following is gated on _drag_began and _press_data; _end_the_gesture ends it. A FRESH show never raises Game.processing, so the opening focus rests from rebuild() as well as the processing false edge (GameView._rest_the_board_focus, two call sites). OPEN for the owner: (1) armed_slot() now has only test callers - delete it and move the query into the two suites, or keep; (2) a click always locks the card description, so End/Undo/Marks sit behind the panel while a card is lifted by click - belongs to P12 if the owner wants them reachable; (3) the pad opening focus rests on the selected grid origin cell. sidebar ASSUMPTIONS.md and PLAN.md still name arm_leftmost as the plan of record. Site map the step followed: ARM: the hub is GameView._arm_the_entrance (~399) -> PlayArea.arm_leftmost (~1831), the ONE grab_cards with no press; callers _on_processing_changed (~307, every processing false edge incl. undo and resume), rebuild (~383), arm_after_placement (~389, from game.gd ~784), _on_undo_pressed (~496), _on_card_tapped (~530). Delete arm_leftmost and every arm; keep armed_slot() as a state query; rest_focus_on_board()s bare-cell branch becomes the only opening focus; return_focus_to_board else-branch -> rest_focus_on_board. FOLLOW: (1) _on_pointer_moved ~1726 follows on ANY motion via _motion_may_start_following -> gate on _drag_began with the button down; (2) click follows at once: _on_gui_input ~1639 sets _next_grab_follows = true -> delete that line (a click then reaches grab_cards with held=1, following=false; CardVisual ~816-821 already lifts by held_lift_px in both states); (3) grab_cards ~1763 re-opens the latch -> goes with the arm; (4) _consume_as_card_release ~1603/1604 returns without clearing following -> every release ends following; (5) GAP-007 restart = new press PLUS threshold. Touch needs no code: emulate_mouse_from_touch already routes a finger through the same gesture. Click-on-cell-places (_on_data_selected -> _place_held_onto -> try_place) never reads following; test_interaction.gd ~287-300 already proves it. TESTS: test_sidebar.gd S15 ~4070-4396 and ~4576-4604, ~282-291, ~309-350, ~4914-4946 (DELETE 4070, 4111, 4271, 4288, 4319; RE-POINT the rest); S14 ~3818-4014, ~4625 (DELETE 3835 any-motion, 3873 one-way latch, 3918 clicked-follows -> each replaced by its INVERSE row; RE-POINT the rest off _arm_without_touching ~3790 onto a real click or press+drag); test_drag_place.gd DELETE ~819 (double-click leaves the arm standing), RE-POINT ~467-506 (~490-493 needs travel past the threshold), preconditions at ~612, ~630, ~650, ~727, ~839 via helpers _armed_card ~196 / _drag_the_arm_into_the_grid ~253; sidebar_snapshot.gd ~163, ~205-225, helpers ~683-715. Helpers: _arm_without_touching (biggest re-point), _await_the_board_armed ~4032 (exit on not processing alone), _place_the_arm ~4043 (click first), _pickup_state ~4059 (delete). Fixtures _start_game_fixture / _start_fixture arm only as a product side effect; ~110 rows assume a card in hand and must lift one. DOCS: ARCHITECTURE_REVIEW ~367-373, ~386-389, ~1716-1718; NAMES.md ~81-83, ~103-105; todo.md ~197 and ~199 close as moot; DESIGN.md Q269 -> (b). TestGridFixtures arms nothing.'
- id: P10
  description: R8 - a small fixed overview gap; the isolating buffer applies only while focused.
  files_touched: [solatro/UI/play_area.gd, solatro/Scripts/player_settings.gd, solatro/Tests/UI/test_grid_view.gd]
  verification_command: 'run_tests.py --filter GridView GridLayout; by eye'
  verification_kind: snapshot
  status: done
  evidence: 'Red (the view split in _apply_grid_buffer neutralised): FILTERED 1 of 51 [GridView]: 250 passed, 7 FAILED (7 behavior) - drawn gap 232 vs 100 at 2 and 3 grids, the set off-centre (left 0, right -442), the gap not returning after a focus round trip. Green: FILTERED 4 of 51 [GridView GridLayout DragPlace WallRender]: 707 CHECKS PASSED (GRID VIEW 238 -> 257, the other three unchanged); --logic 2991, 21 placeholder warnings. Overseer gate: ALL 51 SUITES: 5923 CHECKS PASSED, 21 placeholder warnings, the fingerprint exit profile. By eye (overseer, grid_zoom_shot at 3 grids): OVERVIEW three whole grids in one even row ~100 px apart, the set centred in the board window (image-measured gaps 102/102, leftovers 168/168), cards settled; FOCUSED one grid centred (leftovers 405/405), no sliver of a neighbour, neighbours drawn at x 393.7 and 1576.3 against the window 394..1576.'
  notes: 'One line of behaviour: _apply_grid_buffer (still the one per-frame writer) picks PlayArea.overview_grid_gap_px() in OVERVIEW and isolating_grid_buffer_px() in FOCUSED. game_picture_design_size is identical in both views and to before (1576x887); grid_pitch_px FOLLOWS the drawn gap (316 overview, 448 focused) because it is the overview camera step. The gap switch lands within ~0.04 s of the view change - a jump, not a slide. TP-113 and TP-138 needed nothing; TP-106 re-pointed to FOCUSED (four of five grids now fit the overview, so panning no longer shifts the framing). grid_zoom_shot.gd had two instrument bugs, both fixed: it photographed the WINDOW (cropping the 1576 px picture to 1152, so the third grid never appeared in any earlier shot) and it grabbed mid-deal, two frames after printing; it now waits on a probe of every reported rect and every CardVisual being still, and quits nonzero if the probe moves across the grab. OPEN for the owner: grid_overview_gap_cards = 2.5 card widths (100 px) is the implementer pick; the floor is ~88 px, the two score gutters; in the overview the grid row sits low in the window, against the Entrance line (not covered by R8). OWES a sweep: test_grid_view.gd (236 findings), grid_zoom_shot.gd (7), and 5 dead references in poker-patience DESIGN.md ~889, ~1021 and NAMES.md ~197-198 -> P19. Site map the step followed: The one-quantity rule is grid_position_size_px (~352-359: width = span + 2*buffer) and its comment (~341-347); every gap quantity (isolating_grid_buffer_px ~300-322, _apply_grid_buffer ~2767-2773, grid_pitch_px ~2778) is view-blind, only the aim (resting_grid ~986, pan_to_grid ~1196 with the OVERVIEW early return ~1201, focus_grid ~1005, _bounce_board ~1234) reads view_mode. _apply_grid_buffer runs every physics frame (~581), is idempotent and writes only the HBoxContainer separation theme constant, so a view-dependent buffer is a change at ~2770 plus _set_view (~1265, emits view_mode_changed, no listener today). WARNING: the buffer also feeds game_picture_design_size (~375, one fixed size per run -> the wall picture) and grid_pitch_px (the camera step, main.gd ~256/266/300-313): keep the PICTURE derived from the isolating buffer and vary only the drawn separation per view. No overview knob exists (grid_overview_margin is design prose only, GAP-017); separation is the CARD pitch, not the grid gap - every test reading pa.separation is unaffected. TESTS: test_grid_view.gd TP-113 ~1917-1921 asserts leftover = buffer on each side -> RE-POINT (helper _grid_span ~2050); TP-138 ~690-692 precondition (three grids overflow the frame) may stop holding under a small gap -> re-derive; TP-140 ~816-859 is R8 isolation itself -> KEEP, its overview precondition gets stronger; TP-139/101/103/105/106 KEEP; test_wall_render ~872-923 asserts the wall step == grid_position_size_px().x -> KEEP if the picture is unchanged; grid_zoom_shot.gd ~84-90 is the by-eye instrument.'
- id: P11
  description: R7 - the uncommitted Entrance is centred and grid-free; a pickup focuses the nearest grid and the Entrance slides under it; a committed Entrance stays with its grid.
  files_touched: [solatro/UI/play_area.gd, solatro/Levels/game_view.gd, solatro/Tests/UI/test_grid_view.gd, solatro/Tests/Interaction/test_drag_place.gd]
  verification_command: 'run_tests.py --filter GridView DragPlace EntranceStocks; by eye'
  verification_kind: snapshot
  status: done
  evidence: 'Red (home grid forced to pan_grid, slide lerp forced to 1, focus_the_grid_in_view returned at entry): FILTERED 4 of 51 [GridView GridLayout DragPlace Interaction]: 680 passed, 20 FAILED (20 behavior) - 19 named R7 checks (centred 827 vs 985, stayed put while panning, passes through the positions between: 0 of 63 samples, a cancelled pickup leaves the board focused, a drag pickup focuses, the pickup takes grid 1 not the focused grid, the slide finishes after wall view) plus one hit of the known GRID VIEW pan-right flake. Green: FILTERED 7 of 51: 2216 CHECKS PASSED (GRID VIEW 257 -> 278, DRAG PLACE 192 -> 237, GRID LAYOUT 138 -> 139, SIDEBAR 1265 -> 1266, INTERACTION 46, ENTRANCE STOCKS 31); --logic 3003, 21 placeholder warnings. Overseer gate: ALL 51 SUITES: 5998 CHECKS PASSED, 21 placeholder warnings, the fingerprint exit profile, 0 SCRIPT ERROR. By eye (overseer, grid_zoom_shot 3 grids): uncommitted overview - the Entrance centred in the window at the bottom; slide_0 -> slide_1 - the row further right each frame with the clicked Queen raised (implementer image-measured centre 985 -> 1163 -> 1289 -> 1311.5 over ~0.35 s); at rest under the focused grid (0.15 px); committed to grid 0 and looking at grid 2 - no Entrance card anywhere in the window.'
  notes: 'One writer still: _sync_entrance_x lerps between the window-centred x and the home grid columns by _entrance_slide, which _advance_the_entrance_slide moves toward the derived aim every physics frame (no tween, so the ALWAYS-node trap does not arise; a paused tree freezes it and returning finishes it). entrance_home_grid() = committed_grid, else focused_grid while FOCUSED, else NO_GRID. In the OVERVIEW the nearest grid IS pan_grid (the wall camera is the only thing that moves the view); geometry decides only while FOCUSED. OPEN for the owner (readings R7 does not state): (a) a cancelled pickup leaves the board focused and the Entrance under that grid until the overview returns; (b) a drag pickup focuses as a click does; (d) ANY focus of a grid, not only a pickup, takes an uncommitted Entrance under it; (e) once a grid is committed a pickup re-aims nothing; (f) uncommitted and FOCUSED, the Entrance stays under focused_grid when the view pans to a neighbour. Found and filed: P20, P21. Site map the step followed: Depends on P9 for what a pickup is. Site map done. Strip: EntranceStrip is a sibling of the scroll container (play_area.tscn ~73-135, LAYERING.md ~91-97); _sync_entrance_x (~661-678) writes ONE value, entrance_h_track.position.x = columns_x - strip.global_position.x (~676), from _view_grid_cells (~704-708) = grid_container child at pan_grid; runs every physics frame (~585). Only that x-slaving changes, and only while committed_grid == -1; y pinning (_apply_entrance_strip_height ~717-726, hud_reserve_px ~780 is the only view-sensitive edge), the layer split (GAP-010, test_visual_layers ~484-488) and Q40=a stay. committed_grid is set at game.gd ~763-764 inside place_card_in_grid, cleared at _commit_placement ~790-791 and by GameData.rebase_commitment; there is NO committed_grid_changed signal - GameData.board_changed fires at ~775 after the set and reaches PlayArea.queue_rebuild via GameView._on_board_changed (~253). Nearest grid: _board_local_rect (~1225) against _board_window_local (~758) is what pan_to_grid already uses; _grid_index_of returns NO_GRID for the Entrance. Pickup hook: GameView._pick_up (~546, the one pickup route) -> grab_cards; under R5 a click reaches it. Slide: no tween exists on the strip; SmoothScrollContainer.scroll_x_to (addons ~613-630) clamps to content range and its tween is bound to the scroller, which processes only while the game picture is focused (wall.gd pauses the tree; main.gd ~400-406 trap) - a strip tween must be created on an ALWAYS node or the strip itself while focused. Q34 (gated, never answered) option (c) IS R7: "neutral position below the whole board, sliding into the committed grid once it commits"; poker-patience Q39 default (b) is close but R7 fires the nearest-grid rule on PICKUP, not continuously. TESTS: test_drag_place.gd _settle_layout ~163-175 and test_interaction.gd ~102-111 wait on entrance_h_track.position.x stabilising ("it follows the camera") -> RE-POINT to cover the slide and the uncommitted rest; test_sidebar.gd ~1059-1061 "the grid and the Entrance share a centre" -> RE-POINT with the committed precondition; test_grid_layout.gd ~233-247 worst_dx alignment holds on a one-grid FOCUSED board -> add the uncommitted case; test_grid_view ~2159-2191 KEEP; test_entrance_stocks untouched. DOCS: DESIGN_DOC.md ~85, ~148-151; ARCHITECTURE_REVIEW ~25; grid-view DESIGN QR3/Q20/Q34 rows ~201, ~225, ~244, ~285-286; poker-patience Q39/Q41 ~627-629; the knob table at poker-patience DESIGN ~1095-1108 is already stale (52/3 shipped).'
- id: P12
  description: R1 - the sidebar overlays and slides in after a picture lands and out before it leaves; no picture inset; hidden on the menu and in wall view; the half-width all-edge inset decided on the investigation's numbers.
  files_touched: [solatro/UI/hud_container.gd, solatro/Levels/game_view.gd, solatro/Levels/map.gd, solatro/Levels/menu.gd, solatro/Levels/main.gd, solatro/UI/Wall/wall_picture.gd]
  verification_command: 'run_tests.py --filter Sidebar WallTransition WallRender; by eye'
  verification_kind: snapshot
  status: pending
  evidence: ''
  notes: 'Investigation done. (1) Zero inset = container_size_fraction contributing 0 to visible_rect_beside: board_inset_left/top become the crop alone (0 at the picture aspect). (2) k for a symmetric all-edge inset is EXACTLY 0.5 of the container width (394 picture px at 1152x648 -> 197 px per edge): clearing the sidebar needs kC + shift >= C and not leaving the picture needs shift <= kC, so 2kC >= C; below 0.5 the edge column cannot stay visible. GAP-002 crop contributes 0 at 16:9; wall_overfill_margin 1.02 already draws the picture ~1% off-screen per side. (3) Hooks: transition_landed (main.gd ~477) for slide-IN; slide-OUT before leaving has NO pre-hook on the wall-view path (_go_to_wall_view awaits _animate_camera before set_active_screen(&"")) - add one before the await; picture->picture has transition_started. The container has no animated position today; a slide tween must live on an always-processing node (main.gd ~400-406 trap). (4) Content shift: map (camera offset) and menu (authored re-fit) are per-frame safe; the board re-centres through focus_grid -> _recentre_board, an async settle - drive it once at slide end, not per frame. (5) Overlay coverage at zero inset: the container IS the game HUD (nothing under it) but covers the Entrance strip from x 0 and the wall overlay Back/Forward/Wall buttons sit inside a left band; map dots and menu buttons need a render to say.'
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
  notes: 'PipSuit.get_plural_str(), abstract, one override per suit, one production caller (ControlCard.card_title); keys SUIT_<NAME>_PLURAL: Hoops, Knives, Balls, Fires, Fireworks. localization.en.translation is tracked and regenerated by a headless --import. OPEN for the owner: (1) "Fires" vs the mass noun "5 of Fire"; (2) the suit-only title arm (a card with no rank) stays singular. pip_suit_test.gd owes a sweep (5 legacy findings) -> P18. Site map the step followed: Small. The title is built in ControlCard.card_title (CARD_TITLE key); suit names come from the suit pip get_str. Red-then-green on the R10 title rows in test_sidebar.gd.'
- id: P22
  description: The follow-up answers, built - an off-cell drag release DROPS the card (hand empty, drop map out, description unlocked as a cancel leaves it); PlayArea.armed_slot() deleted, its query moved into the suites; the suit-only title arm uses the plural; legal_cell_glow and FOCUS_GLOW become ONE value in one home.
  files_touched: [solatro/UI/play_area.gd, solatro/UI/control_card.gd, solatro/Cards/card_visual.gd, solatro/Scripts/player_settings.gd, solatro/Tests/Interaction/test_drag_place.gd, solatro/Tests/Wall/test_sidebar.gd, solatro/Tests/Visual/sidebar_snapshot.gd]
  verification_command: 'run_tests.py --filter DragPlace Sidebar Interaction PlanVisuals Pixels; by eye'
  verification_kind: snapshot
  status: pending
  evidence: ''
  notes: 'Four small fixes, each its own red-then-green; one commit each if they can be gated apart. The shared glow value is 1.45 (owner: ok 1.45). DRAG PLACE 5.4 (the drop map stays lit after a returned drag) and drag_release_returned.png invert. "until no more placeable option on grid or entrance cards run out" - check that is exactly when committed_grid clears today; if not it is a finding.'
- id: P20
  description: A SCRIPT ERROR a player can reach - HudContainer.return_to_lock reads _locked_entry_by_screen[&"game"] while only _lock_by_screen holds the key (hud_container.gd ~357, from the play_area.gd focus_exited lambda): lock a card description by click, then zoom out with an Entrance card focused.
  files_touched: [solatro/UI/hud_container.gd, solatro/Tests/Wall/test_sidebar.gd]
  verification_command: 'run_tests.py --filter Sidebar WallFocus'
  verification_kind: suite
  status: pending
  evidence: ''
  notes: 'Found by the P11 implementer, who re-ordered its own test around the trigger. Red first: a row that drives the real sequence and fails on the SCRIPT ERROR / the wrong panel state. The two dictionaries are two representations of one fact - find which writer leaves them disagreeing rather than guarding the read (hard rule 7).'
- id: P21
  description: R8 on an EDGE grid - FOCUSED on the last (or first) of three grids the scroll clamps, the grid sits off-centre (cells 1124..1500 in a window centred at 985) and its neighbour is wholly visible inside the window; P10 measured only the middle grid.
  files_touched: [solatro/UI/play_area.gd, solatro/Tests/UI/test_grid_view.gd, solatro/Tests/Visual/grid_zoom_shot.gd]
  verification_command: 'run_tests.py --filter GridView GridLayout WallRender; by eye'
  verification_kind: snapshot
  status: done
  evidence: 'Measured first in the real Main, fix absent: 2 grids - focused 0 centre 658.21 (-326.79), focused 1 1312.62 (+327.62); 3 grids - 0 at 658.21, 1 at 985.00, 2 at 1311.79; a neighbour inside the window in every edge case, by every route. Red (the multi-grid gate neutralised): GRID VIEW 326 passed, 20 FAILED (20 behavior) of 346 - each edge grid by click, pan and pickup: not centred, neighbour in view; the middle grid stayed green. Green: FILTERED 4 of 51 [GridView GridLayout DragPlace WallRender]: 842 CHECKS PASSED (GRID VIEW 324 -> 346, others unchanged); --logic 3004, 21 placeholder warnings. Overseer gate: ALL 51 SUITES: 6061 CHECKS PASSED, 21 placeholder warnings, the fingerprint exit profile, 0 SCRIPT ERROR. By eye (overseer) shots_p21 grid_zoom_3_committed_elsewhere.png: focused on the last of three, the one grid centred (columns 799..1170, window centre 985), no neighbour, no Entrance; implementer image-measured 984.5 / ~985 on all five focused stills.'
  notes: 'While FOCUSED with more than one grid, _apply_grid_buffer (still the one writer) also sets the scroll container panel content margins to isolating_grid_buffer_px minus the score gutter (188 px), then queue_sort; SmoothScrollContainer clamps a programmatic scroll to the content range and has no overscroll option (addons/SmoothScroll smooth_scroll_container.gd ~613-630, helpers/scroll_layout.gd). The picture size and grid_pitch_px are unchanged. TP-140 was green because it focuses the middle grid, the one index the clamp never bites. A neighbour edge now lands EXACTLY on the window edge at every edge grid (decided with is_equal_approx). OPEN: one TP-105 failure in 8 GridView runs on an intermediate state read edge 316.000 vs 413.119 - 97 px, not a float ULP, not reproduced; do not file it under the known flake without a look. Seen first by the overseer in shots_p11 grid_zoom_3_pickup.png and committed_elsewhere.png (the harness has no wall camera). MEASURE FIRST in the real Main at 2 and 3 grids, focusing each grid: centre offset and whether any neighbour rect intersects the board window. If the real game shows it too it is an R8 defect - the ruling says FOCUSED centres the one grid and the buffer pushes its neighbours off-screen. TP-140 claims isolation; find which grid it focuses. The picture size must not change (the P10 warning).'
- id: P19
  description: The comment sweep P10 owes - test_grid_view.gd and grid_zoom_shot.gd leave compliant, code byte-identical; the five dead references in poker-patience DESIGN.md and NAMES.md resolved.
  files_touched: [solatro/Tests/UI/test_grid_view.gd, solatro/Tests/Visual/grid_zoom_shot.gd, solatro/design/poker-patience/DESIGN.md, solatro/design/poker-patience/NAMES.md]
  verification_command: 'py .claude/tools/sweep_check.py <each .gd>; doc_check --changed silent; run_tests.py --filter GridView; overseer full gate'
  verification_kind: suite
  status: pending
  evidence: ''
  notes: 'Best run AFTER P11, which edits test_grid_view.gd again. Same rules as P14, P17, P18.'
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
- The SIDEBAR map Deck-button click flake (HEADLESS_TESTING.md section 4) failed twice after P6 landed - 1 of the overseer's 3 full gates since, and 1 of an implementer's filtered Sidebar runs (its total not counted) - each green on the single rerun; 0 of the 3 overseer gates before P6. Not yet measured whether the rate moved - run `--filter Sidebar` N times at 30143594 and at HEAD before naming a cause.
- none else beyond the tasks. OWNER, R5 reading to confirm: a drag released off a legal cell puts the card back over its slot but it stays IN HAND (lifted, drop map lit) until placed or cancelled - 'release anywhere else returns it' was read as returns-to-slot, not drops-the-hold. From the bloat review of the P9 commit (opus, read-only): `PlayArea.rest_focus_on_board()` keeps a fallback for a held card with no control, whose only named producer was the deleted auto-arm - settle by `assert` plus a suite run, back it out if a fixture fires it; `_release_places` and `follow_cards` each have one call site (both predate P9).

## Next up
1. P22 (the follow-up answers), then P20, then P19 (the sweep P10 and P11 owe; test_grid_layout.gd joins it).
2. P12 before P13: both edit hud_container.gd and map.gd and re-point the same inset gates (test_sidebar ~846/854, ~1087, ~1172); P13 inherits P12's rewritten set. P15 is small.
3. After the last step: `/docs` folds this file away; the owner merges the branch.

### Opening prompt for the next session (paste as is)

```
Resume solatro/HANDOFF_playtest_fixes.md on branch combine-sidebar-boardplan (never main; commit per verified step on this branch). Read CLAUDE.md, then the handoff: its rulings R1-R10 are the owner's verbatim decisions and outrank the design questions they name; each pending task row's notes: carries the site map an implementer follows. Confirm the tree is green first: Get-Process shows no Godot, then the full windowed run with a private APPDATA and GODOT_BIN from .claude/memory/machine-profiles.md - expect ALL 51 SUITES ... CHECKS PASSED, 22 placeholder warnings, the 1150 ObjectDB note. Then dispatch P9 to ONE general-purpose implementer on opus (default effort) with the P9 notes as its brief, the run rules from the handoff (implementers run --logic and --filter only; you run the gate; red-then-green on every row; a file it edits leaves doc_check --changed silent, the sweep as a separate pass proven code-identical), and the fixed report schema (FIX/STATUS/FILES/RED/GREEN/BY EYE/DOC_CHECK/NOTES). At most two subagents, only one runs Godot; the second slot is read-only work. Commit each verified step with its evidence, mark the row done in the handoff, run the gate, then the next row in the Next up order. Ask the owner only when a ruling does not cover a decision; record every answer verbatim under the design it changes (the ASSUMPTIONS.md sections titled Owner rulings from the first playtest) and in the handoff.
```

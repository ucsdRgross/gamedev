# HANDOFF — playtest fixes (the combined branch's first playtest)

**Goal:** the sixteen findings of the owner's first playtest on `combine-sidebar-boardplan` fixed
and gated, each against the ruling below, on this branch, ready for the owner to merge.
**State:** rulings taken; the four small fixes P1–P4 are dispatched to one implementer; a read-only
investigation is measuring the overlay-sidebar and second-sidebar geometry for P12/P13. Gate at the
stream's start: `ALL 51 SUITES: 5839 CHECKS PASSED`, errors log empty.
**Entry docs:** solatro/START_HERE.md, solatro/design/sidebar/DESIGN.md,
solatro/design/poker-patience/DESIGN.md, solatro/design/grid-view/DESIGN.md,
solatro/design/board-plan/DESIGN.md, solatro/PICTURE_WALL.md
**IMPLEMENTED-BY:** implementers `general-purpose` on `opus` (Opus 5) at default effort, one fix
at a time; overseer Fable 5.1, writes no source; research `Explore` on `opus`.

## Owner rulings (verbatim where quoted; each overturns or extends the design it names)

- **R1 sidebar space (B1, B16)** — overturns sidebar `Q24`=a, `Q27`=d, D8/D10, `GAP-001..003`.
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
  excluded from the modulate. No colour cast.
- **R7 the Entrance (B8)** — answers the gated `Q34`; keeps poker-patience `Q40`=a: while no grid
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
  with it.
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
  status: in_progress
  evidence: ''
  notes: ''
- id: P2
  description: B15 - a right-click over the sidebar container still cancels; the container passes the second button through to the wall's routing.
  files_touched: [solatro/UI/hud_container.gd, solatro/Tests/Wall/test_sidebar.gd]
  verification_command: 'run_tests.py --filter Sidebar'
  verification_kind: suite
  status: in_progress
  evidence: ''
  notes: ''
- id: P3
  description: R2 - ui_cancel zooms out to wall view after the focused screen's first refusal; wall_back stays Back; PICTURE_WALL.md and picture-wall Q100 annotated.
  files_touched: [solatro/UI/Wall/wall.gd, solatro/Tests/Wall/test_wall_input.gd, solatro/PICTURE_WALL.md, solatro/design/picture-wall/DESIGN.md]
  verification_command: 'run_tests.py --filter WallInput'
  verification_kind: suite
  status: in_progress
  evidence: ''
  notes: ''
- id: P4
  description: R3 - after the wall reveal, Main focuses the map picture through the existing focus route; Continue with nothing pending does the same.
  files_touched: [solatro/Levels/main.gd, solatro/Tests/Wall/test_wall_transition.gd]
  verification_command: 'run_tests.py --filter WallTransition'
  verification_kind: suite
  status: in_progress
  evidence: ''
  notes: ''
- id: P5
  description: B11 - the face-down stock card no longer displaces the Entrance cards one depth pitch up; only a held card is lifted (CardVisual.held_lift_px), and it must read against a flat row.
  files_touched: [solatro/UI/play_area.gd, solatro/Cards/card_visual.gd]
  verification_command: 'run_tests.py --filter Sidebar EntranceStocks DragPlace; by eye'
  verification_kind: snapshot
  status: pending
  evidence: ''
  notes: 'B14 is already built (held_lift_px); it does not read because of this. Verify by eye after.'
- id: P6
  description: R6 - the legal-cell highlight brightens the zone card back toward white with the mark pips excluded; legal_cell_tint becomes that brightening, no green.
  files_touched: [solatro/Cards/card_visual.gd, solatro/Shaders/outline.gdshader, solatro/Scripts/player_settings.gd, solatro/Tests/UI/test_plan_visuals.gd]
  verification_command: 'run_tests.py --filter PlanVisuals Sidebar Pixels; by eye'
  verification_kind: snapshot
  status: pending
  evidence: ''
  notes: 'TP-64 pins that the match tints nothing; keep it discriminating.'
- id: P7
  description: R10 - describe_card/card_info produce a title and per-effect blocks; DescriptionPanel draws names large and bodies small; PipRankNumeral.get_str retired in favour of a display name.
  files_touched: [solatro/UI/control_card.gd, solatro/UI/play_area.gd, solatro/UI/description_panel.gd, solatro/UI/description_panel.tscn, solatro/Cards/Pips/pip_rank_numeral.gd]
  verification_command: 'run_tests.py --filter Sidebar UiViewers; by eye'
  verification_kind: snapshot
  status: pending
  evidence: ''
  notes: 'todo.md records the wart (NumeralRank5.0) and its wrapping fallout; both close with this.'
- id: P8
  description: R9 - every description preview draws at the deck viewer's card size.
  files_touched: [solatro/Levels/game_view.gd, solatro/UI/hud_container.gd, solatro/design/sidebar/gaps/GAP-004.md]
  verification_command: 'run_tests.py --filter Sidebar; by eye'
  verification_kind: snapshot
  status: pending
  evidence: ''
  notes: ''
- id: P9
  description: R5 - the pickup model. Auto-arm removed; click lifts; drag follows while held; release places or returns; click on a legal cell places a lifted card.
  files_touched: [solatro/UI/play_area.gd, solatro/Levels/game_view.gd, solatro/Tests/Interaction/test_drag_place.gd, solatro/Tests/Wall/test_sidebar.gd, solatro/Tests/UI/test_plan_visuals.gd]
  verification_command: 'run_tests.py --logic; --filter DragPlace Sidebar Interaction PlanVisuals'
  verification_kind: suite
  status: pending
  evidence: ''
  notes: 'Large. Every row asserting the auto-arm (sidebar section 10) is re-pointed, not deleted.'
- id: P10
  description: R8 - a small fixed overview gap; the isolating buffer applies only while focused.
  files_touched: [solatro/UI/play_area.gd, solatro/Scripts/player_settings.gd, solatro/Tests/UI/test_grid_view.gd]
  verification_command: 'run_tests.py --filter GridView GridLayout; by eye'
  verification_kind: snapshot
  status: pending
  evidence: ''
  notes: ''
- id: P11
  description: R7 - the uncommitted Entrance is centred and grid-free; a pickup focuses the nearest grid and the Entrance slides under it; a committed Entrance stays with its grid.
  files_touched: [solatro/UI/play_area.gd, solatro/Levels/game_view.gd, solatro/Tests/UI/test_grid_view.gd, solatro/Tests/Interaction/test_drag_place.gd]
  verification_command: 'run_tests.py --filter GridView DragPlace EntranceStocks; by eye'
  verification_kind: snapshot
  status: pending
  evidence: ''
  notes: 'Depends on P9 for what a pickup is. _sync_entrance_x follows pan_grid today and never reads committed_grid.'
- id: P12
  description: R1 - the sidebar overlays and slides in after a picture lands and out before it leaves; no picture inset; hidden on the menu and in wall view; the half-width all-edge inset decided on the investigation's numbers.
  files_touched: [solatro/UI/hud_container.gd, solatro/Levels/game_view.gd, solatro/Levels/map.gd, solatro/Levels/menu.gd, solatro/Levels/main.gd, solatro/Scripts/Wall/wall_picture.gd]
  verification_command: 'run_tests.py --filter Sidebar WallTransition WallRender; by eye'
  verification_kind: snapshot
  status: pending
  evidence: ''
  notes: 'Investigation A1-A5 pending.'
- id: P13
  description: R4 - a second, lockable sidebar for pack previews with a Take button; map travel through a sidebar button after previewing; a Deck button on the map sidebar at rest.
  files_touched: [solatro/UI/hud_container.gd, solatro/UI/hud_container.tscn, solatro/UI/description_panel.gd, solatro/UI/choice_viewer.gd, solatro/Levels/map.gd, solatro/Locale/localization.csv]
  verification_command: 'run_tests.py --filter Sidebar MapTraversal WallInput; by eye'
  verification_kind: snapshot
  status: pending
  evidence: ''
  notes: 'Investigation B1-B5 pending. Feature-sized; the owner asked for direct fixes, not a design round.'
```

## Verified vs assumed
- The research behind every ruling's "overturns" line: two read-only Explore agents on `opus`,
  file:line cited in their reports; not re-read by the overseer.

## Open bugs
- none beyond the tasks.

## Next up
1. Land P1–P4 (in flight), full gate, one commit each.
2. P5, P6, P7, P8 — the small visual fixes, each by eye.
3. P9, then P11 (depends on it), P10, then P12/P13 on the investigation's numbers.

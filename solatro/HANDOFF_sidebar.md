# HANDOFF — sidebar (PLAN.md Phases 1–5, S1–S18)

**Goal:** land ALL of `solatro/design/sidebar/PLAN.md` — S1 through S23 and the closing phase S24 —
on branch `sidebar`, one verified step per commit (owner ruling: the original S1–S18 scope was
widened to every phase; do not stop at S18).
**State:** Phase 2 (S5–S8) done, awaiting its boundary review. `test-speed` (one test pacing for every suite, a suite filter, a headless logic tier —
`py solatro/Tools/run_tests.py --filter <Node> | --logic`) is merged at 587f2d60; the full run is
~200 s and a single suite ~30 s. Open: GRID LAYOUT fails 2 of 4 runs on the merged branch
(rotating check; 0 of ~15 before the merge) — being diagnosed before S5. Phase 1 (S1–S4) done and reviewed: the adversarial pass at the phase boundary found 8
confirmed defects, fixed in four commits (3d858441, 1f34cf5e, ce0f918b, 784f173e). S5 next. An
owner report that the game board sits too far right with a gap beside the sidebar is OPEN — not
reproduced at ten window sizes (grid centre within 7 logical px of the remaining-space centre);
awaiting the owner's screenshot and window size. Implementers now append evidence to a scratch file as they go,
because a turn-cap stop loses the final report (it happened on most S2/S3 dispatches). A throwaway
detached worktree of unmodified main (`../gamedev-baseline`, a28c79aa) exists for by-eye
before/after captures — local only; `git worktree remove` it at the close. Single-suite runs: launch the NON-console exe, wait for the
suite banner in test_output_all.log, end `$p.Id` (the console exe is a wrapper; ending it orphans
the game window).
**Entry docs:** solatro/design/sidebar/PLAN.md (self-contained), DESIGN.md (authority on behaviour),
TEST_PLAN.md (every test that must exist), NAMES.md (every identifier), solatro/START_HERE.md
**IMPLEMENTED-BY:** `plan-implementer` subagent. S1–S4 (through commit 5b8f84b9 and S4's
uncommitted first pass): `sonnet` at `effort: low`. From S4's finish onward: `opus` (Opus 5) at
default effort. Overseer: Opus 5 through S4, then Fable 5.1 at high effort; it writes no source.

## Provenance
- Code: `plan-implementer` — sonnet (effort low) for S1–S4's first pass; Opus 5 (default effort)
  for everything after. Both models wrote code on this branch.
- Reviewer floor: the highest tier present — Opus 5 at default effort or higher (`opus` or
  `fable`), same generation or newer.

## Run rules in force
- Worktree `../gamedev-sidebar`, branch `sidebar`. Overseer commits one verified step per commit.
- ONE subagent at a time (hook-enforced). Implementer never stages or commits.
- Every `--import` rewrites `solatro/design/effect-review/EFFECTS.*.translation` and `.csv.import`.
  Revert them before each commit: `git checkout -- solatro/design/effect-review` then
  `git clean -fq -- solatro/design/effect-review/*.translation`.
- The main checkout shares `app_userdata/Solatro` with this worktree — never run the suite from both.
- Dispatch every implementer FOREGROUND (`run_in_background: false`): the lock's PostToolUse
  release only fires for foreground calls. `plan-implementer` maxTurns is 150; a step bigger than
  that is split into parts that each leave the suite green.
- An implementer cut off mid-step: reset to the last commit, unless its last act was a completed
  full-suite run, in which case the tree is coherent and a fix-forward dispatch is cheaper.

## Baseline (main @ a28c79aa, unmodified, this box)
- `py solatro/Tools/run_tests.py` (GODOT_BIN = the box's console exe), windowed, ~400 s.
- Banner: `ALL 45 SUITES: 4002 CHECKS PASSED [23 placeholder warnings]`
- Exit-time (wrapper, pre-existing): `Pages in use exist at exit in PagedAllocator:
  N16WorkerThreadPool5GroupE`, `15 resources still in use at exit`. Wrapper exit code 2.
- ⚠ An owner editor open on the MAIN checkout (shared `app_userdata`) made GRID VIEW's three
  `grid_pan_right` real-key-press checks fail. Check for editor processes before every run.
- Suite count derivation: `grep -c 'ext_resource type="PackedScene"' solatro/Tests/all_tests.tscn` = 45.
- **Gate for every step:** suite count ≥ 45 (rising as suites are added), zero failures, no
  exit-time error lines beyond the two above.

## Owner rulings made during this run
- `plan-implementer` maxTurns 50 → 150 (edited on main and on this branch).
- Legacy comment debt is DEFERRED to its own pass: a step keeps every comment it writes or edits
  compliant and leaves old comments in touched files alone. `doc_check --changed` findings on those
  lines are expected. Counts when this run started touching them: play_area.gd 638, game.gd 352,
  test_visual_layers.gd 293, test_grid_view.gd 252, test_ui_props.gd 241, card_visual.gd 205,
  test_grid_layout.gd 197, main.gd 181, wall_editor.gd 115, wall_picture.gd 97,
  wall_editor_soak.gd 67, wall_transition.gd 53, test_interaction.gd 51, player_settings.gd 47,
  wall_input.gd 31, map.gd 12, wall_overlay.gd 11, choice_viewer.gd 11, deck_builder.gd 10,
  card_effect_api.gd 9, deck_viewer.gd 4, cards_viewer.gd 3, type_input.gd 3.

## Phase 1 review (adversarial, Fable 5.1) — what it found and where it went
- Top-case board zoom ignored `board_inset_top` (fixed, 3d858441); menu laid out in window px
  inside a picture (fixed, `WallPicture.local_rect_beside`, 1f34cf5e); map camera shift in window
  px vs world units × zoom (fixed, ce0f918b, GAP-003 filed); S4 fixtures that removed the unit
  mismatch (rewritten); connection bookkeeping and the private-container fallback in three homes
  (now `HudContainer.connect_for_screen/disconnect_for_screen/ensure`, 784f173e); a check that
  could not fail (deleted). Open from it: GAP-001 note — on a clamped ultrawide the flush-inner
  container overlaps the board region by the outboard gap (finding 10); the inset uses the
  design's unmargined scale, ~6 window px narrower than the picture's real overfilled scale
  (recorded in ASSUMPTIONS).
- ⚠ The whole geometry runs in the project's LOGICAL canvas (`canvas_items` + `expand`, base
  1152×648): every 16:9 window is the same layout scaled; only non-16:9 windows change it.

## Phase 2–5 audits (plan-auditor, read-only) — defects the briefs must carry
- §3a line numbers: play_area.gd −4 everywhere; game_view.gd rewritten in S2/S3 — the relay is
  `:86`, `_on_processing_changed` `:208`, `_on_data_selected` `:323` (S15's `:462-498` is past EOF).
- S5: `info_requested` fires only on CLICK and only in Info mode (`play_area.gd:1440-1450`,
  `:1476-1481`, gate `_info_mode()`); hover goes `mouse_entered → grab_focus →
  on_control_focus_entered` (`:2782-2813`) into the in-board popup. S5 must emit on focus and
  keep click semantics; no hover-EXIT publication exists (S6 needs one — an invisible mechanism
  choice, log it); `Main._on_screen_info_hovered` (`main.gd:685`) is gated on `wall_info_mode`
  and also receives the map's `info_hovered`. `DescriptionPanel` is a 4-line shell;
  `show_description(entry)` discards its argument. `InfoCard._resize_to_content` measures
  against knobs S9 deletes — size off `container_rect()`. Per-screen memory (1.14) lives only in
  Info-mode code S9 deletes — the container must own it.
- S6: exit X sized by `WallInput.touch_target_px(DisplayServer.screen_get_dpi(),
  PlayArea.settings())` today (S13 repoints; four call sites, not three). TEST_PLAN 1.7's fourth
  dismissal and 1.8 need `following` → moved to S14 (plan defect, not dropped). Bare-board click
  has no branch in `_on_gui_input`; per-cell geometry is `_grid_slot_center_global` /
  `_card_control_at`, not `_publish_cell_rects`.
- S7: `game.gd` needs no edit (`processing_changed` exists, `game_view.gd:55` listens).
- S9: `wall.gd:290-293` holds the only `wall_info` reader (missing from the map);
  `player_settings.gd:522-566` interleaves two SURVIVING knobs; `main.gd` Info surface is ~20
  sites incl. `_info_card_height()` (6 callers) and `_on_picture_hovered`; `WallTransition`'s
  Info removal is a signature change (`card_height_px`); `test_wall_input.gd:60,1029,1111` and
  `test_wall_focus.gd` assert Info mode and go red loudly.
- S10: `hide_focus_info()` (`play_area.gd:3042`) is the only caller that stops `_process()`,
  guarded by `_row_open`/`_layer_grown` (measured regression at `:3044-3049`); `card_info()`
  SURVIVES inside the cited range.
- S11: `sidebar_snapshot` exists (six PNGs; no description capture yet — 9.2 needs one); the
  wall editor has NO Info panel node — its Inspector `preview_info_mode` + borrowed InfoCard go;
  suite count lands at 45 after deleting test_wall_info (46 today) — TEST_PLAN says ≥ 45.
- S12: only ChoiceViewer has a panel (`%CardInfo`); DeckViewer has none and Rules is DeckViewer
  on `rules_deck`; viewers live inside a picture's SubViewport → the inset goes through
  `WallPicture.local_rect_beside()`; `deck_builder.tscn` is broken too (missing ext_resource).
- S13: `test_wall_input.gd:947-964,1246-1285` and `test_grid_view.gd:1538-1562` assert the
  clamp/mm knobs and must change in the same commit.
- S14: no LIFT quantity exists (held offset is cursor-relative, `card_visual.gd:700-704`) →
  GAP candidate; `prop_layer.gd:277` reads `held`; emulated mouse motion from touch (device −1).
- S15: no auto-arm exists; `grab_cards` has one production caller (`game_view.gd:336`).
  TEST_PLAN 6.3's spy has no seam — assert effects instead.
- S16: `game_view.gd:327-329` ungrabs on a click on the held card (contradicts 5.5); a release
  over the container cannot reach PlayArea (root-viewport STOP control vs SubViewport) → GAP
  candidate; 5.6 needs a test rules card (no shipped rule grabs a grid card).
- S17: `card_effect_api.gd` has no subscription surface; the tap reaches effects via
  `Game.run_all_mods(&"on_card_tapped")` with a test-local CardModifierType (precedent
  `test_board.gd:313`).
- S18: Escape is read in `wall.gd:270-273` → `Main._on_back_pressed` (`main.gd:716`): one step
  back on the FocusStack, wall view when empty — there is no 'menu' destination;
  `ungrab_cards()` also hides the description (`play_area.gd:1530`), collapsing the two steps.
- Wall-view picture hover (`Wall.picture_hovered` → `WallPicture.get_info()`) has no destination
  after S9 — Q21=(b) says no sidebar in the overview → it is deleted with Info mode (assumption).
- S19–S23 (plan-auditor): S19's blast radius is ~3x §3a — add `card_effect_api.gd:57,154,177`
  (`draw_deck()/draw_card()/return_to_draw_deck()`), `game.gd:924-941` `return_to_map()` (the run
  deck is rebuilt there — miss it and stock cards leave the run), `skill_grid_allotment.gd:35`
  (grid count from deck size), `skill_hungry_hippo.gd:40`, and eleven test files (notably
  `test_iterator.gd:194-210` asserting collection ORDER and `test_persistence_fuzz.gd:196`).
  §2's `Array[Array[CardData]]` is not an expressible GDScript type (`scoring.gd:919` writes it as
  a comment; `card_data_array.gd` is the wrapper) and a top-level per-slot array drifts from
  `entrance_zone().cells`, which `Board.add_column/remove_column` (`board.gd:235,243`, driven by
  `zone_adder.gd`) mutate — the stock rides the entrance zone's per-cell data (assumption, invisible).
  `on_append` is a shuffle-time hook (`game.gd:429-433`), not a board walk; the walk is
  `get_card_collections()`/`all_card_datas()` (`game_data.gd:412/428`); the stage verifier is
  `validate()` I1/I3/I5 (`:483/:531/:575`). No RunState version exists: 'discarded, not migrated'
  needs a load-time check (assumption). `draw_card()` pops the BACK — today's 'top'. S20 has no
  call site in its two files. S21: `CardVisual` spawns Stage.DRAW cards at `deck_ui`'s centre — now
  a ROOT-viewport control (latent bug since S2: wrong space); flip = `data.flipped` slerped at a
  hard-coded 6.5/s only while `floating`; `deck_viewer.gd`'s sort enums are dead — sort at the
  caller. S22: 'fully resolved' is a code position after `refill_entrance_if_due()` and AFTER
  `save_state()` (`game.gd:774-782`), guarded on `not processing` (re-entrancy `:733-739`);
  `submit_button.visible` is never written — Q107=(c) owner note 'end button becomes revealed
  when either deck empty, or no more possible action on board (no empty tiles)' means End starts
  HIDDEN; `test_game_headless.gd:772-802` asserts a scored line does not resolve (pin its goal).
  S23: hover→container already routed (S5); `map_hover_panel.tscn` EXISTS (leak canary preloads
  it) — 'do not re-instantiate on the map'; `_on_node_hovered` is `map.gd:162`. 4.3's
  `_replay_pending_placement()` dereferences `RunManager.run` unguarded — populate it.

## Phase 2 review (adversarial, Fable 5.1) — open until fixed
1. CONFIRMED `hud_container.gd` per-screen state (`_entry_by_screen`, `_lock_by_screen`,
   `_locked_entry_by_screen`, `_processing_screen`) outlives a show: a WON show leaves
   `processing` true so the next show's whole first pick has no description; a mid-show Back then
   New Run re-shows the previous show's entry/lock. Nothing resets on `detach_screen`/new run.
2. CONFIRMED leaving the game while locked: `set_active_screen` sets the new screen BEFORE
   `show_hud()`, so `clear_lock` erases the wrong screen's lock while `description_dismissed`
   still drops the board's marking — on return the lock is half-alive (X focusable, marking gone).
3. CONFIRMED (by reading) a remembered entry detached on a mid-cascade screen change and never
   re-mounted is orphaned by the next publication (`_entry_by_screen` overwrite at `:178`).
4. CONFIRMED Q68=b met in flag only: `%ExitX` is FOCUS_ALL when locked but arrows are consumed
   for scrolling and nothing in the root viewport can navigate to it; the test asserts the flag.
5. CONFIRMED preview size baked at publish — a resize/board zoom with a description up leaves it
   stale (Q34=b, Q48=a).
6. SUSPECTED stick scroll rounds to 0 px/frame at low deflection on a short panel — use a
   fractional accumulator.
7. Test shape: the cancel test calls `wall._unhandled_input` directly (item 13); the rebuild test
   compares `locked_data` to a value it set itself.

## Gaps
- GAP-001 (open, non-blocking) — a 16:9 window wider than 2560 px clamps, so "394 at any 16:9" fails
  there. S3 builds §1.1 as written; gate checked at TEST_PLAN 3.1's fixtures.
- GAP-002 (open, CONTRADICTION, parked thread) — §1.1's inset ignores the covering picture's crop, so
  on windows narrower than 1576:887 (16:10, 4:3) the board's region starts under the container
  (measured −70 px at 1920×1200). The portrait spill was a bug, fixed (3d858441).
- GAP-003 (open, CONTRADICTION, not parked) — D11's 'the map has no picture' is false; the code
  converts through the picture scale and camera zoom (ruling a). Needs D11's text corrected.

## Tasks
```yaml
- id: S1
  description: HudContainer + DescriptionPanel empty shells, show_hud/show_description swap
  status: done
  evidence: 'full suite ALL 46 SUITES: 3997 CHECKS PASSED (log mtime 17:48, overseer-read); SIDEBAR: ALL 9 CHECKS PASSED == 9 check( calls; no lock_to/GameHud/MapHud yet; extends PanelContainer + StyleBoxFlat'
  notes: 'container bg is a hardcoded colour (+1 PALETTE placeholder, 23->24) - S2 routes it through the palette'
- id: S2
  description: move the HUD controls into HudContainer; delete %MultScore (+3 children) and %Preview
  status: done
  evidence: 'S2d d53f8261: ALL 46 SUITES 4069 PASSED [22], SIDEBAR 80; overseer LOOKED at user://sidebar_snapshot/game_hud.png - Goal/Total legible below the overlay buttons, piles row, Undo/End, board centred beside the container. S2c 3123530c: ALL 46 SUITES 4034 PASSED, TestSidebar 57 checks, red-then-green per test. S2a 2b88ea90: ALL 46 SUITES 3981 PASSED [23 placeholders]; pre-change board_inset_left 394.0, _hud_authored_width 402.0, board centre (scroll_container.position.x + size.x/2) 733.808. S2b 07aa305f: ALL 46 SUITES 3979 PASSED [22 placeholders], godot.log 0 SCRIPT ERROR'
  notes: 'Tests/Visual/sidebar_snapshot built here (ahead of S11) - boots Main, enters the game, writes user://sidebar_snapshot/game_hud.png; run with the NON-console exe and wait for exit'
- id: S3
  description: geometry per PLAN 1.1; add board_inset_top; delete pan_window_left_x
  status: done
  evidence: '03e85767: ALL 46 SUITES 4076 PASSED [22]; SIDEBAR 109. 3.1 394+-0.5 at 1280/1920/2560 wide, 3.2 262.7 at 3840x1080 flush inner, 3.3 top case; red-then-green logged per check (clamp, max->min [only 3.2 catches it - min==max at 16:9], top branch, resize hook, HUD overflow). grep of removed names: nothing. By eye 1280x720: 320 px container, HUD inside, board beside it'
  notes: 'Top case (600x1000) board spills under the band - GAP-002, parked. The Entrance/grid offset check cannot fail for the neutralisations tried (test-surface review at close). The Entrance x in any still is MID-DEAL-ANIMATION (measured -165..-30 px vs grid across captures; layout rule is identical to main) - sidebar_snapshot must wait for the deal to settle; fold into S5 which extends it'
- id: S4
  description: the map gets the same container (Fame, Lap, Luck, Deck)
  status: done
  evidence: 'commit after 5b8f84b9: ALL 46 SUITES 4151 PASSED [22]; SIDEBAR 148; tests a-e + menu aspect/centring red-then-green (s4 evidence); by eye at 1280x720 menu centred beside the container, map start node x~800, game screen unchanged'
  notes: 'menu and wall-overview rules landed here too (Q22=b, Q21=b). GAP-002 also applies to the map on windows narrower than 16:9 only if map content sits under the band - unmeasured'
- id: S5
  description: route PlayArea.info_requested into HudContainer; description content
  status: done
  evidence: '16f107a5 + 7904d1c7: ALL 46 SUITES 4180 PASSED; 1.2/1.3/1.14 red 17 -> green; by eye description.png: name beside a board-sized preview, body below'
- id: S6
  description: lock, follow, the four dismissals, exit X
  status: done
  evidence: 'S6a e9e1754f + S6b: ALL 46 SUITES 4282 PASSED [22], SIDEBAR 303, exit profile = the two standing lines + 135 ObjectDB; red-then-green per test logged; by eye description_locked.png (X, lifted locked card) and description_follow.png (hovered card shown, locked card marked)'
  notes: 'the fourth dismissal (card leaves its cell while following) and TEST_PLAN 1.8 are owed by S14 (need following). S6b shipped a production leak (a displaced lock orphaned its visual) caught by the leak probe and fixed with a regression check'
- id: S7
  description: the processing rule
  status: done
  evidence: '6d4d9b8c: ALL 46 SUITES 4336 PASSED; 1.9-1.12 red 10 -> green; SIDEBAR 342; by eye description_processing.png: HUD only mid-cascade'
- id: S8
  description: scroll and multi-modal reach, sidebar_scroll action
  status: done
  evidence: 'ALL 46 SUITES 4337 PASSED (overseer run, alone); 7 new tests red -> green; SIDEBAR 372; by eye description_scroll.png'
  notes: 'at the shipped container width no card text overflows at any window - the scrollbar is real but idle until descriptions grow (Q36=c later design)'
- id: S9
  description: delete Info mode
  status: pending
  evidence: ''
- id: S10
  description: delete the in-board popup
  status: pending
  evidence: ''
- id: S11
  description: replace test_wall_info / wall_info_snapshot / the wall editor Info panel
  status: pending
  evidence: ''
- id: S12
  description: migrate the deck/discard/rules/choice viewers to the sidebar
  status: pending
  evidence: ''
- id: S13
  description: GestureMetrics, delete DPI and the six mm/px knobs
  status: pending
  evidence: ''
- id: S14
  description: split held from following on CardVisual
  status: pending
  evidence: ''
- id: S15
  description: arming through the pickup path
  status: pending
  evidence: ''
- id: S16
  description: click versus drag, release-to-place
  status: pending
  evidence: ''
- id: S17
  description: tap — double-click, card_tap action, card_tapped signal, one dummy effect
  status: pending
  evidence: ''
- id: S18
  description: cancel — held card first, description second, Escape shows menu/wall
  status: pending
  evidence: ''
```

## Open bugs
- GRID VIEW `one more pan-right at the board's end does not move the camera past it` failed once
  by 0.018 px (edge 545.640 vs 545.658) in ~14 branch runs; green on the rerun. Pre-existing
  camera-settle timing, not touched by this run. Quote the denominator if it recurs.

## Next up
1. Phase 2 boundary review. 2. S9. 3. S10.

Resume prompt: *"Resume /plan-run on solatro/design/sidebar/PLAN.md in worktree ../gamedev-sidebar,
branch sidebar, Phases 1–5 only (stop at S18). Read solatro/HANDOFF_sidebar.md first, then
`git log --oneline`, `git status --porcelain`, and a full suite run before continuing."*

## References
- solatro/design/sidebar/PLAN.md, DESIGN.md, TEST_PLAN.md, NAMES.md, answers.json
- .claude/skills/plan-run/SKILL.md, .claude/skills/handoff/SKILL.md
- .claude/memory/running-godot-scenes.md, .claude/memory/tests-that-prove-nothing.md

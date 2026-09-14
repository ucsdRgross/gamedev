# HANDOFF — sidebar (PLAN.md Phases 1–5, S1–S18)

**Goal:** land ALL of `solatro/design/sidebar/PLAN.md` — S1 through S23 and the closing phase S24 —
on branch `sidebar`, one verified step per commit (owner ruling: the original S1–S18 scope was
widened to every phase; do not stop at S18).
**State:** Phases 1–4 done (S1–S13 committed; the Phase 3 adversarial review and its re-review
are fixed in four commits, 54317308 → 17e9cc1c — see the two Phase 3 sections). Phase 5 is next:
S14 (`following`), S15, S16, S17, S18; then Phase 6 (S19–S21),
Phase 5 (S14–S18), Phase 6 (S19–S21), Phase 7 (S22), Phase 8 (S23), the closing phase S24 — all in
this run (owner ruling). GAP-004 (Q34's reading inside a viewer) is open, non-blocking.
⚠ The owner's other worktree (`../gamedev-boardplan`) runs the suite unannounced; check
`tasklist | findstr Godot_v4.7` before every run and wait it out — a concurrent run rotates
`godot.log` and fabricated one GRID VIEW failure this session. PID 3020 is a stale Godot 4.1.2
window of `sidebar_snapshot.tscn` from 01:52 that the permission classifier refused to stop —
harmless so far; the owner should close it. `test-speed` (one test pacing for every suite, a suite filter, a headless logic tier —
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
- S10: landed. `_process()` is stopped by `_ease_row_openings()`'s own return, which reports the
  row openings and the depth-layer growth together; `PlayArea.card_info()` survives as the
  sidebar's publish shape.
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

## Phase 2 review (adversarial, Fable 5.1) — all seven fixed in 7fafbfb3
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

## Phase 3 review (adversarial, Fable 5.1, at S12) — 5 confirmed, 6 suspected; where each went
1. CONFIRMED a viewer opened from a pile button never returned focus on close (`show_deck` read the
   picture SubViewport's focus owner, always null once an overlay button holds focus) — fixed,
   `show_deck(parent, deck, opener)`, 54317308.
2. CONFIRMED `ChoiceViewer.fit_beside` moved only the near edges: the pack centred half off-screen
   in the top band — fixed, four-edge fit on BOTH viewers (the deck viewer's rows overran too),
   74897f3a.
3. CONFIRMED opening a viewer by pad published nothing (first focus landed before the opener
   wired the relay; ASSUMPTIONS had rationalised it as B4) — fixed, deferred first `grab_focus`,
   54317308.
4. CONFIRMED the start menu's Inspect viewer was neither inset nor publishing — fixed, same rule
   as every viewer through `Menu`, fix dispatch 3.
5. CONFIRMED a viewer was fitted once and never on resize — fixed, re-fit on
   `container_rect_changed` after the board/map inset publish, 74897f3a.
- SUSPECTED: preview re-drawn at the board's size on a rect change (fixed: the viewer re-publishes
  its remembered highlight, 74897f3a); `fit_beside` adding margins (fixed: set from the authored
  margins); the reroll's stale description (reproduced and fixed: `CardsViewer.rehighlight`, fix 3);
  a viewer swap announcing nothing (NOT reproduced — the incoming viewer's opening publish covers
  it; pin test kept); the S9 `card_environment` guard (caller found, guard kept — see State);
  `settings.tres` carrying deleted keys (engine drops them silently; nothing to do).
- Residue: `_key_scroll_pages`, `PlayArea._grid_panel_height`, `PlayArea.get_data_from_control`
  deleted (fix 3); deck_builder's `TypeOption` and skill-Random path deleted (fix 3).
- Observed by the overseer at fix 3: the choice viewer's "Take all"/"Rerolls" chrome was still
  anchored to the picture — fixed in the same dispatch (one `Layout` control insets pack + chrome).
- Plan drift it named: Q34=b's reading inside a viewer → GAP-004; L5's "opacity" exposed as
  nothing (ASSUMPTIONS S11, defensible, for the owner to see); the deck picker's viewer → wired
  (Q140=a + Q143=a make it the consistent reading; ASSUMPTIONS records it).

## Phase 3 re-review of the fix commits (Fable 5.1, at S13) — 3 confirmed, 4 suspected
1. CONFIRMED `HudContainer.disconnect_for_screen()` is one flat list: a GameView teardown (show
   ends, New Run) drops the Map's and Menu's connections too — the map's Deck button dies and no
   resize re-insets map or menu after the first show. Predates the fix range (784f173e). Fix
   dispatch 4: key the list by owner.
2. CONFIRMED the viewer re-fit re-publishes unconditionally, so a resize re-opens a description
   the player dismissed with the X. Fix dispatch 4: republish only while a description is showing.
3. CONFIRMED S12.9 asserts focus on a HIDDEN pile button (a pad close of a viewer while its
   description is up strands the player). Overseer decision (reversible, ASSUMPTIONS): the exit X
   is focusable whenever a description shows; a viewer's close focuses its opener if visible, else
   the X. Fix dispatch 4.
- SUSPECTED: the menu picker's `Dim` (layer 64, STOP) swallows hover/click over the Inspect viewer,
  so the menu's viewer publishes by keyboard only (pre-existing layering) — fix dispatch 4
  reproduces and fixes; two viewers up on the map republish in an order that lets a stale pack
  highlight win (unrun); every viewer open now hides the HUD stack even for a mouse open, so a
  mouse user cannot swap Deck→Discard without closing first — §1.2's exclusive HUD/description
  makes this by design, but the OWNER should look; S12.14's label cites Q34=b for the built
  viewer-size reading (GAP-004) — reworded in dispatch 4.
- Answered: the picker panel drawing over the inspected cards in `menu_inspect.png` is
  PRE-EXISTING on main (picker layer 64 over the viewer's layer 1; the cards measure exactly 0.4x
  under the picker's dim).

## Gaps
- GAP-005 (open, OWNER CALL + plan hole, not blocking) — the legal-cell highlight (Q24=a, Q124=a,
  G12, "the drop map" of Q280=a) does not exist in the code and has no visual design; TEST_PLAN §11
  claims G12 covered and it is not. Options a/b/c in the file; S16 builds release-to-place on
  `try_place` legality with no visual.
- GAP-004 (open, OWNER CALL, not parked) — inside a viewer, is the description's preview drawn at
  the board's card size (Q34=b literally) or the viewer's own (built)? One line per viewer either way.
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
  status: done
  evidence: '0d323d8c: ALL 45 SUITES 4249 PASSED; wall_info grep empty; suite count 46->45 (TEST_PLAN 8.4 >= 45)'
- id: S10
  description: delete the in-board popup
  status: done
  evidence: '5ca37f5f: ALL 45 SUITES 4257 PASSED; _focus_info/wall_screen_popups grep empty; by eye no popup in description.png'
- id: S11
  description: replace test_wall_info / wall_info_snapshot / the wall editor Info panel
  status: done
  evidence: 'S9 (tests) + S11 commit: ALL 45 SUITES 4264 PASSED; WALL EDITOR SOAK 83 checks 0 problems; by eye wall_editor_sidebar_locked.png'
- id: S12
  description: migrate the deck/discard/rules/choice viewers to the sidebar
  status: done
  evidence: '7f6a2219: ALL 45 SUITES 4287 PASSED [21]; SIDEBAR 404 -> 432 (S12.1-S12.7, 28 checks); red: relays removed 9 FAILED, insets/close/panel/deck_builder neutralised 6 FAILED; CardInfo grep in choice_viewer.* empty; doc_check 0 of 221 on added lines; by eye viewer_description.png (deck viewer grid from ~x396 beside the 320 px sidebar, the hovered viewer card described) and choice_viewer_description.png (pack row beside the sidebar); map_hud.png start node still ~x800 after the inset refactor'
  notes: 'ASSUMPTIONS records: preview at the VIEWER''s card size (Q34=b read as the object pointed at); viewers publish highlights only, no lock; close announces highlight_cleared; OPENING a viewer publishes nothing (first focus lands before the relay is wired) - flagged to the Phase 3 review; the deck picker''s Inspect viewer on the start menu is NOT wired (Q143=a, 3a names neither menu.gd nor deck_picker.gd); new names InfoEntry.relay_to, HudContainer.rect_beside/window_scale, WallPicture.window_scale, CardsViewer.card_window_px, DeckViewer/ChoiceViewer.fit_beside, GameView.wall_picture/_open_deck_viewer. main.gd touched beyond 3a (enter_game hands the picture to the view). A second todo.md item (deck_builder broken preloads) closed with Q166=c. Phase 3 review fixes (three dispatches, one commit each) followed - see the State line and the Phase 3 review section'
- id: S13
  description: GestureMetrics, delete DPI and the six mm/px knobs
  status: done
  evidence: 'bb2484db: ALL 46 SUITES 4356 PASSED [21]; suite count 45 -> 46 (TestGestureMetrics rows 2.1-2.6 + 8.3, 14 checks); hard gate grep dpi|DPI|mm_to_px empty outside archive/addons; six knob names resolve nowhere outside design docs; red: model neutralised 5 FAILED, clamp/density put back 2 FAILED, WallInput stops delegating 7 FAILED, swipe stops asking the model 3 FAILED, a knob put back 1 FAILED; doc_check 0 of 1014 on added lines'
  notes: 'new name PlayArea.board_card_picture_px() (the swipe travel is in picture space, so board_card_window_px was the wrong space; the window helper now derives from it) - ASSUMPTIONS. Four production touch_target_px call sites, not three (the exit X). PICTURE_WALL.md wiring row kept with its new reason (Q306=a)'
- id: S14
  description: split held from following on CardVisual
  status: done
  evidence: '4a008669: ALL 46 SUITES 4410 PASSED [21]; SIDEBAR 89 -> 97 tests (6.4-6.9, 1.7 fourth dismissal, 1.8); red per neutralisation 8/2/3/8/3 FAILED; lift 18.3 held vs 18.2 following (non-zero, equal); doc_check 0 of 775 on added lines; by eye card_lifted.png (raised in its slot) and card_following.png (riding over the grid, same lift)'
  notes: 'no lift quantity existed for a HELD card (a grab never called anim_jump) - the jump rise card_jump_rise_play is applied in both states, no new knob (ASSUMPTIONS). Q267=a lands behind try_grab''s await, so the click sets PlayArea._next_grab_follows and grab_cards consumes it. OWNER SHOULD SEE: Q56=a + Q62=b + Q267=a together mean a click-lock on a grabbable card is dismissed the moment the pointer leaves that card''s cell (the click also grabs, and a clicked card follows at once); four S6 tests now lock through _lock_without_holding(). New names: CardVisual.held_lift_px/cursor_ride_offset, PlayArea.follow_cards/_on_pointer_moved/_origin_cell_rect/_next_grab_follows'
- id: S15
  description: arming through the pickup path
  status: done
  evidence: 'a5449e77: ALL 46 SUITES 4452 PASSED [21]; SIDEBAR 97 -> 109 tests (6.1, 6.2, 6.3 effects + source pin, 6.10, Q251/Q116/Q118/Q114/Q115/Q119/G1); red per neutralisation 9/6/12/9 FAILED; no armed field; arm_leftmost has one production caller (GameView); doc_check 0 of 817 on added; by eye game_hud.png (leftmost card lifted+brightened at the deal, HUD up), armed_focus_elsewhere.png'
  notes: 'GAP-005 filed (legal-cell highlight never built, no visual design - owner look call; parked = the visual only). Q123=b board-card test NOT written: nothing outside the Entrance can be picked up today (only TypeInput has on_can_grab_stack) - S16 5.6/5.7 need a test-local grabber. S14 cell-leave became a CROSSING of the origin cell (a position test dismissed on every move once a card is always armed). Undo held-cards guard deleted (always true now). _publish_focus_left_cards assert -> guard naming the teardown case. OWNER SHOULD SEE: (1) TEST_PLAN 9.4 "lifted, glowing, focus elsewhere" is unreachable after any input - a key focus or any mouse motion latches following (Q262=a), so the armed card rides the MOUSE position even when the player is on keyboard (section 1.4 targets get_global_mouse_position); (2) armed_focus_elsewhere.png shows two horizontal lines across the board area of unknown origin - handed to the Phase 5 review'
- id: S16
  description: click versus drag, release-to-place
  status: done
  evidence: '99644d39: ALL 47 SUITES 4470 PASSED [21]; suite 46 -> 47 (TestDragPlace 5.1-5.7, 31 checks); red per neutralisation 1/7/1/1/3/4 FAILED (the 1 for wall routing removed is exactly 5.4 - the container release measurement); doc_check 0 of 1614 on added; LF verified at byte level after a CRLF scare; by eye drag_release_returned.png (card back in its slot, lifted, not following)'
  notes: 'Q288=a needed NO new forwarding: a press on the board sets no gui.mouse_focus in the root viewport, so the release over the container reaches Wall._unhandled_input and rides WallInput.route into the picture (the earlier "gap candidate" was a misunderstanding of the engine, not a gap). The click is decided at the RELEASE. 5.1''s discriminator is the description LOCK (only the click route locks). A held card''s control is MOUSE_FILTER_IGNORE so no tap reaches the card in hand - 5.5''s toggle half is driven by key accept. 5.6/5.7 ride a test-local STAMP. New: Tests/Support/test_main_host.gd (TestSidebar''s _boot_main_at moved there). ⚠ Path.write_text on Windows rewrites sources to CRLF - the implementer''s neutralise driver now writes bytes; two source-reading test gates (registration, 6.3''s source pin) break on CRLF'
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
1. S12. 2. S13. 3. S14 (then S15–S18, S19–S23, S24 close).

Resume prompt: *"Resume /plan-run on solatro/design/sidebar/PLAN.md in worktree ../gamedev-sidebar,
branch sidebar, Phases 1–5 only (stop at S18). Read solatro/HANDOFF_sidebar.md first, then
`git log --oneline`, `git status --porcelain`, and a full suite run before continuing."*

## References
- solatro/design/sidebar/PLAN.md, DESIGN.md, TEST_PLAN.md, NAMES.md, answers.json
- .claude/skills/plan-run/SKILL.md, .claude/skills/handoff/SKILL.md
- .claude/memory/running-godot-scenes.md, .claude/memory/tests-that-prove-nothing.md

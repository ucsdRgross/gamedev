# HANDOFF — sidebar (PLAN.md Phases 1–5, S1–S18)

**Goal:** land `solatro/design/sidebar/PLAN.md` steps S1–S18 on branch `sidebar`, one verified step
per commit, stopping at S18. Phases 6–9 (S19–S24) are NOT in this run.
**State:** S1–S3 done. S4 next. Implementers now append evidence to a scratch file as they go,
because a turn-cap stop loses the final report (it happened on most S2/S3 dispatches). A throwaway
detached worktree of unmodified main (`../gamedev-baseline`, a28c79aa) exists for by-eye
before/after captures — local only; `git worktree remove` it at the close. Single-suite runs: `run_suite_scene.ps1` pattern — launch the NON-console exe, wait for the
suite banner in test_output_all.log, end `$p.Id` (the console exe is a wrapper; ending it orphans
the game window).
**Entry docs:** solatro/design/sidebar/PLAN.md (self-contained), DESIGN.md (authority on behaviour),
TEST_PLAN.md (every test that must exist), NAMES.md (every identifier), solatro/START_HERE.md
**IMPLEMENTED-BY:** `plan-implementer` subagent — `sonnet` at `effort: low` (its frontmatter), all
code. Overseer (opus) writes no source.

## Provenance
- Code: `plan-implementer` (sonnet, effort low), every step so far.
- Reviewer floor: sonnet at normal effort or higher, same generation or newer.

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

## Gaps
- GAP-001 (open, non-blocking) — a 16:9 window wider than 2560 px clamps, so "394 at any 16:9" fails
  there. S3 builds §1.1 as written; gate checked at TEST_PLAN 3.1's fixtures.
- GAP-002 (open, CONTRADICTION, parked thread) — §1.1's inset ignores the covering picture's crop, so
  on windows narrower than 1576:887 (portrait top case, 16:10, 4:3) the board's region reaches under
  the container. Main already cropped the board off-screen on portrait windows.

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
  status: pending
  evidence: ''
  notes: 'ALSO OWED HERE (seen by eye in main_boot_snapshot boot.png after S2c): the start menu shows the GAME HUD in the container and the container covers the menu Options button. Q22=(b) "the surface exists everywhere and is simply empty there"; Q21=(b) no sidebar in the wall overview; owner Q27 note "center of screen for picture is center of remaining space not taken by sidebar" - the menu picture must centre beside the container. Main picks the HudStack child per focused screen'
- id: S5
  description: route PlayArea.info_requested into HudContainer; description content
  status: pending
  evidence: ''
- id: S6
  description: lock, follow, the four dismissals, exit X
  status: pending
  evidence: ''
- id: S7
  description: the processing rule
  status: pending
  evidence: ''
- id: S8
  description: scroll and multi-modal reach, sidebar_scroll action
  status: pending
  evidence: ''
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
None yet beyond the baseline failure set above.

## Next up
1. S4. 2. S5. 3. S6.

Resume prompt: *"Resume /plan-run on solatro/design/sidebar/PLAN.md in worktree ../gamedev-sidebar,
branch sidebar, Phases 1–5 only (stop at S18). Read solatro/HANDOFF_sidebar.md first, then
`git log --oneline`, `git status --porcelain`, and a full suite run before continuing."*

## References
- solatro/design/sidebar/PLAN.md, DESIGN.md, TEST_PLAN.md, NAMES.md, answers.json
- .claude/skills/plan-run/SKILL.md, .claude/skills/handoff/SKILL.md
- .claude/memory/running-godot-scenes.md, .claude/memory/tests-that-prove-nothing.md

# HANDOFF — sidebar (PLAN.md Phases 1–5, S1–S18)

**Goal:** land `solatro/design/sidebar/PLAN.md` steps S1–S18 on branch `sidebar`, one verified step
per commit, stopping at S18. Phases 6–9 (S19–S24) are NOT in this run.
**State:** Phase 1 (S1–S4) done and reviewed: the adversarial pass at the phase boundary found 8
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
- GRID VIEW `one more pan-right at the board's end does not move the camera past it` failed once
  by 0.018 px (edge 545.640 vs 545.658) in ~14 branch runs; green on the rerun. Pre-existing
  camera-settle timing, not touched by this run. Quote the denominator if it recurs.

## Next up
1. Owner's centring report (screenshot pending). 2. S5. 3. S6.

Resume prompt: *"Resume /plan-run on solatro/design/sidebar/PLAN.md in worktree ../gamedev-sidebar,
branch sidebar, Phases 1–5 only (stop at S18). Read solatro/HANDOFF_sidebar.md first, then
`git log --oneline`, `git status --porcelain`, and a full suite run before continuing."*

## References
- solatro/design/sidebar/PLAN.md, DESIGN.md, TEST_PLAN.md, NAMES.md, answers.json
- .claude/skills/plan-run/SKILL.md, .claude/skills/handoff/SKILL.md
- .claude/memory/running-godot-scenes.md, .claude/memory/tests-that-prove-nothing.md

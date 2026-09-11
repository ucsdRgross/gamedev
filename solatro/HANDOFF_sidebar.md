# HANDOFF — sidebar (PLAN.md Phases 1–5, S1–S18)

**Goal:** land `solatro/design/sidebar/PLAN.md` steps S1–S18 on branch `sidebar`, one verified step
per commit, stopping at S18. Phases 6–9 (S19–S24) are NOT in this run.
**State:** worktree created, import cache built, baseline measured. No step started.
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

## Baseline (main @ a28c79aa, unmodified, this box)
- `py solatro/Tools/run_tests.py` (GODOT_BIN = the box's console exe), windowed, ~409 s.
- Banner: `ALL 45 SUITES: 3980 passed, 3 FAILED (3 behavior, 0 implementation) [23 placeholder warnings]`
- Failure SET (pre-existing, not this run's): GRID VIEW ×3, all `grid_pan_right` real key press
  (`pan_grid 1`, `moved 0.000 vs pitch 448.000`, `pan_grid 1 of 3`).
- Exit-time (wrapper): `Pages in use exist at exit in PagedAllocator: N16WorkerThreadPool5GroupE`,
  `15 resources still in use at exit`. Wrapper exit code 5.
- Suite count derivation: `grep -c 'ext_resource type="PackedScene"' solatro/Tests/all_tests.tscn` = 45.
- **Gate for every step:** suite count ≥ 45 (rising as suites are added), failure set ⊆ baseline set,
  no new exit-time error lines.

## Gaps
- GAP-001 (open, non-blocking) — a 16:9 window wider than 2560 px clamps, so "394 at any 16:9" fails
  there. S3 builds §1.1 as written; gate checked at TEST_PLAN 3.1's fixtures.

## Tasks
```yaml
- id: S1
  description: HudContainer + DescriptionPanel empty shells, show_hud/show_description swap
  status: pending
  evidence: ''
- id: S2
  description: move the HUD controls into HudContainer; delete %MultScore (+3 children) and %Preview
  status: pending
  evidence: ''
- id: S3
  description: geometry per PLAN 1.1; delete hud_scale, furniture caches, _process slide, pan_window_left_x
  status: pending
  evidence: ''
- id: S4
  description: the map gets the same container (Fame, Lap, Luck, Deck)
  status: pending
  evidence: ''
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
1. S1. 2. S2. 3. S3.

Resume prompt: *"Resume /plan-run on solatro/design/sidebar/PLAN.md in worktree ../gamedev-sidebar,
branch sidebar, Phases 1–5 only (stop at S18). Read solatro/HANDOFF_sidebar.md first, then
`git log --oneline`, `git status --porcelain`, and a full suite run before continuing."*

## References
- solatro/design/sidebar/PLAN.md, DESIGN.md, TEST_PLAN.md, NAMES.md, answers.json
- .claude/skills/plan-run/SKILL.md, .claude/skills/handoff/SKILL.md
- .claude/memory/running-godot-scenes.md, .claude/memory/tests-that-prove-nothing.md

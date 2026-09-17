# HANDOFF — sidebar gaps: the ten answered rulings

**Goal:** build the ten gap rulings the owner accepted, on branch `sidebar`, one verified item per
commit, then hand the branch to the closing phase of `/plan-run`.
**State:** THE CLOSE IS IN PROGRESS (Opus 5 reviewer session, fable reviewers). Items 1–6 of
"Closing the run" have run over the ten gap commits `dec20d42..a37900b2`; their outputs are in
"## Close ledger" below and item 7 (fixes) is under way. Every gap in
`solatro/design/sidebar/gaps/` is `status: built` except `GAP-011`, which is `open` and waits on
the owner. The branch is unmerged. The main checkout is on `sidebar`; there is no worktree.

## Close ledger
1. `doc_check.py` full: 0 errors, 9 warnings (the standing style backlog CLAUDE.md names).
   Baseline suite on Box B: `ALL 48 SUITES: 5279 passed, 1 FAILED` — the PIXELS `fire brightens`
   check; 0 `SCRIPT ERROR`; 22 placeholder warnings; expected exit profile. **Discriminated:**
   `--filter WallRender Pixels` → red (162 passed, 1 FAILED, same numbers); `--filter Pixels` → 43
   green. WALL RENDER leaves state PIXELS reads. (The suite node is `TestWallRender`; the pattern
   `"Wall Render"` matches nothing.)
2. `adversarial-review` (fable): CONFIRMED `hud_container.gd:_show_preview_card` — a pick by pad
   detaches the focused grid, the root viewport has no focus owner, `%Back` is never focused.
   SUSPECTED: outcome Undo by pad leaves the board viewport unfocused; sweep interleaving under an
   awaiting placement rule; NAMES.md lacks `_build_outcome_buttons`/`_add_outcome_button`.
   PLAN DRIFT: GAP-010=c's pad half; GAP-009 row 7.6 never asserts the focus owner.
3. `/code-review` (fable, angles serial): CONFIRMED the two pad-focus defects above (game_view.gd
   `_on_show_unresolved` → `undo_button.grab_focus()` in the ROOT viewport; `_arm_the_entrance`
   skips `rest_focus_on_armed` once `_rested_the_focus` is set); `_motion_may_start_following`
   cleared by EVERY `stop_following`, so a click on a locked card parks the armed card (beyond
   GAP-007's text); `_show_preview_card` lays out before `_show_back(true)` so the top row is
   measured without Back; the legal-cell sweep runs on every `queue_rebuild` (each cascade step).
   Resolved: the "grid re-picked under a stationary cursor" hazard does not exist (godot#112513).
4. Test-surface (fable): 7.6 asserts `_armed_card() != null`, never the focus owner; 7.6's
   `check(stepped_right == undo)` is null==null when Undo is absent, and its gate SKIPS five checks
   rather than failing them (the a37900b2 message's "stayed green" conflated skipped with green —
   compare per-suite counts); 6.11 asserts `CardVisual.tint` (never shown) not `modulate`, and its
   "refused target" is an Entrance card, never a cell, so a sweep marking every cell passes; 6.6
   measures y only; 1.17/1.18's pad half is `grab_focus()` + a real click on Back, so no row
   proves a pad reaches Back. Test-only production callers: none (grepped the full list).
   Red-then-green audit: cd9b81bd claims +12, the test yields +10; the rest consistent.
5. `/simplify` (fable, angles serial): `_sweep_legal_cells` is the THIRD copy of the legality walk
   (`game.gd` `_no_held_card_has_a_legal_placement`, `_no_legal_placement_remains_in_grid`) and
   asks a Game question from the view; the sweep runs with an EMPTY hand on every cascade step and
   never on the direct `set_card_zones` path; `if _outcome_buttons:` has no null producer (rule 7);
   `_build_outcome_buttons` and `_band_axis_outruns_reference` have one call site (rule 8);
   `_show_back` restates `_refresh_exit_focus`; three test copies of the legal-target dispatch;
   `FOCUS_GLOW` and `reference_window_size()` restated in tests. Backlog (not applied): one
   `board_region` Rect2 in place of three setters that each re-fit; the panel owning its Back;
   `scroll_position` via `set_deferred`.
6. `/fx-verify` (fable, 27 shots rendered, key ones re-read by the overseer): PASS on all six
   numbered items. Looked at: outcome row (Continue outlined, Undo beside, one row, legible, dim
   under the spotlight layer); preview Back beside a frameless sprite with the title wrapping in a
   ~100 px column when the body is empty; viewer previews within 1 px of the viewer's cards;
   geometry — container edge and visible crop agree; the GAP-005 tint confirmed NOT drawn
   (`legal_cells=25 of=25`, interiors (76,76,76)); `armed_focus_elsewhere.png` shows two
   full-width grey rules at y≈66/537 — the board ScrollContainer's focus border
   (`draw_focus_border = true` in `play_area.tscn`, unchanged on this branch; the docs say it
   draws when any descendant is focused) with its sides off-picture. Harness note: the scene
   honours `OUT_PATH` for `game_hud.png` only, not `OUT_DIR`.
**Entry docs:** `solatro/design/sidebar/` DESIGN.md, PLAN.md, TEST_PLAN.md, NAMES.md,
ASSUMPTIONS.md, `gaps/GAP-001.md`..`gaps/GAP-011.md`; `solatro/ARCHITECTURE_REVIEW.md` §1.6;
`solatro/PICTURE_WALL.md`; `solatro/todo.md` ("Sidebar: owner should see", "PIXELS `fire
brightens`"); `.claude/skills/plan-run/SKILL.md`.
**IMPLEMENTED-BY:** `plan-implementer` (Opus 5, default effort) wrote every gap's code and tests.
Sonnet wrote S1–S4's first pass of the original plan run only. Overseers: Fable 5.1 at high effort
for the plan run and G6–G8; Opus 5 for G5, the geometry pass, G4, G10 and G9.

## ⚠ Waiting on the owner
- **`GAP-011` (open).** `Shaders/outline.gdshader` ends `COLOR = out_col;` and never multiplies the
  vertex COLOR, so nothing `modulate` marks can draw: the `G5` legal-cell tint, and
  `CardVisual.focused`'s "selected" glow, which has therefore never been on screen. The one-token
  fix switches `modulate` on for EVERY card at once — a board-wide look change nobody has seen. The
  blanket *"i will take recommendation for all gaps"* does not reach a gap raised after it was
  said. Do not build it without a fresh ruling.
- **The reviewer floor for the close:** Opus 5 at default effort or higher, same generation or
  newer. Never weaker.

## Tasks
```yaml
- id: G6..G8, G5
  status: done
  evidence: 'e2d9a4e0, d11aa4ed, 37f48cb6, cd9b81bd — each message carries its red/green and banner'
- id: G1+G2+G3 (geometry pass)
  status: done
  evidence: '5e2d7438 — ALL 48 SUITES: 5257 CHECKS PASSED; 3.1 read 262.667 red at HEAD, green after'
- id: G4
  status: done
  evidence: 'd9a6cedf — docs only; the distinguishing row already existed (TEST_PLAN 1.15)'
- id: G10
  status: done
  evidence: '282278c3 — ALL 48 SUITES: 5304 CHECKS PASSED; seven assertions red first; map_preview_card.png'
- id: G9
  description: GAP-009=b, the outcome screen's own Undo beside Continue. 19046951 built it unverified
    ("ran out of limit"); the verification commit that follows it carries the proof.
  files_touched: [solatro/Levels/game_view.gd, solatro/Tests/Wall/test_sidebar.gd, solatro/Tests/Visual/sidebar_snapshot.gd]
  verification_command: 'py solatro/Tools/run_tests.py'
  verification_kind: suite
  status: done
  evidence: |
    Red-then-green, row 7.6: Undo not added to the row -> RED "the outcome screen shows an Undo
    beside Continue" and "one d-pad step off Continue lands on the outcome's Undo", the other
    checks green, no null crash; restored -> SIDEBAR 1166 CHECKS PASSED.
    Explicit focus_neighbor lines removed -> both walk checks STAY GREEN, so the lines were dead
    and are deleted; Godot's own neighbour search walks the HBox.
    Field lifetime: new 7.6 check "the outcome's button row is freed with the screen, its field
    cleared"; free skipped -> RED (field=<null> row_valid=true), the only red of 1167; restored
    -> 1167 CHECKS PASSED.
    By eye, outcome_buttons.png (1280x720): sidebar to x~320 with the HUD's own Undo up, "Fame +1"
    centred, Continue wearing the focus outline at ~515..670, Undo beside it at ~672..762. Print
    after the harness fix: drawn_x=[Continue=518.2..667.6, Undo=670.9..761.8] container_right=320.0.
    Full suite: ALL 48 SUITES: 5277 passed, 1 FAILED — the one red is the PIXELS fire-luminance
    check below, in no file this item touched. 0 SCRIPT ERROR; exit profile PagedAllocator
    WorkerThreadPool + 15 resources + 135 ObjectDB. doc_check --changed: exit 0.
  notes: 'The snapshot print had been in stretch canvas units (1152 base) against a 1280-px capture; it now goes through the root viewport get_final_transform(). _report_the_board_geometry still prints canvas units, labelled as the image''s own space — untouched.'
```

## Verified vs assumed
- Every banner above was read by the overseer from the wrapper's output or the preserved
  `logs-failed-*` log, never from an implementer's word alone.
- **Assumed, not checked:** that Box A's green full runs on the same commits mean the PIXELS
  failure is Box-B-only. Nobody has run PIXELS on Box A since the geometry pass.

## Open bugs
- `PIXELS: fire brightens when its host is highlighted -- mean luminance 0.294 plain vs 0.296
  highlighted` fails in the full run on Box B: 3 of 4 full runs, the same numbers each time,
  43/43 alone. The one full run that passed it was the run in which `Tools/wall_editor.tscn`
  failed to load, and WALL RENDER (which mounts that scene) finishes right before PIXELS. Surfaces
  at `Tests/Visual/test_pixels.gd`, `test_effects_take_their_host_modulate`. Recorded in `todo.md`.

## Run rules (still in force)
- The overseer writes no source. Every item is a `plan-implementer` dispatched FOREGROUND with a
  brief that quotes the ruling verbatim, names the call site, and states the comment and complexity
  rules. The implementer never stages or commits.
- At most two subagents at once, only one runs Godot. The suite is one process: `tasklist |
  findstr Godot` before and after every run.
- Full windowed suite gate: `py solatro/Tools/run_tests.py` with GODOT_BIN set from
  `.claude/memory/machine-profiles.md`. `ALL 48 SUITES ... CHECKS PASSED`, at most 22 placeholder
  warnings, 0 `SCRIPT ERROR` in the Solatro user data's `logs/godot.log`, exit profile exactly
  `PagedAllocator ... WorkerThreadPool` + `15 resources still in use` + the `135 ObjectDB` note.
  The check TOTAL drifts between green runs; judge on the suite count and the failure set.
- `py .claude/tools/doc_check.py --changed`: zero findings on added lines. The legacy comment
  backlog in touched files stays, by owner ruling.
- Red-then-green for every new row. Anything visual: render `Tests/Visual/sidebar_snapshot.tscn`
  with the NON-console exe and LOOK at the PNGs under the user data's `sidebar_snapshot/`.
- ⚠ A first run on a box that has not built this branch fails on the `.godot/` class cache
  (`Could not find type "HudContainer"` cascades) — `HEADLESS_TESTING.md` §2. On Box B the
  checkout also had `solatro/tools` in lowercase, which registers `WallEditor` at
  `res://tools/...` against the test's `res://Tools/...` and fails WALL RENDER with `hides a global
  script class`; rename the directory through a temporary name, then rebuild the cache.
- Known flakes: an intermittent TEARDOWN crash after a passing banner (wrapper exit 3); an
  intermittent map Deck-button click failure right after a viewport resize. Rerun once.
- The placeholder-warning gate is AT its cap of 22. The next off-palette colour breaches it.

## Files touched
Committed per item; see `git log --oneline main..sidebar`.

## Next up
1. **The closing phase of `/plan-run`** for the whole branch — the ten gaps have had no
   adversarial review, `/code-review`, test-surface review or `/simplify` pass as a set. Open a NEW
   session at or above the floor and paste the block from "Declaring the run ready to close".
2. Discriminate the PIXELS failure on Box B: `py solatro/Tools/run_tests.py --filter "Wall Render"
   Pixels`. If it reproduces, WALL RENDER leaves state PIXELS reads; if not, halve the suites
   ahead of it.
3. `GAP-011` — needs the owner's ruling, then one item.

Resume prompt: *"Read `solatro/HANDOFF_sidebar_gaps.md` FIRST, then `git log --oneline -5`,
`git status --porcelain` and a full suite run, before dispatching anything. The ten gaps are built;
the next step is the close."*

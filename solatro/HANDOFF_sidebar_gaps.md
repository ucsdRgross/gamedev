# HANDOFF — sidebar gaps: the ten answered rulings

**Goal:** build the ten gap rulings the owner accepted, on branch `sidebar` in the worktree
`../gamedev-sidebar`, one verified item per commit.
**State:** the sidebar plan run (PLAN.md S1–S24, every phase and the closing sequence) is COMPLETE
and committed; the branch is ~139 commits ahead of `main` and unmerged. The tree is clean and the
suite is green. Every gap in `solatro/design/sidebar/gaps/` is `status: answered`: the owner said
*"i will take recommendation for all gaps"*, so each gap's own recommendation is the ruling.
Nothing is in flight.

**Done, one commit each:** `G6` `e2d9a4e0`, `G7` `d11aa4ed`, `G8` `37f48cb6`, `G5` `cd9b81bd`.
**Left:** `G1`, `G2`, `G3` as one geometry pass, then `G4` and `G10`, then `G9`.

⚠ **`GAP-011` is OPEN and needs the OWNER, not an implementer.** Building `G5` proved that
`Shaders/outline.gdshader` ends `COLOR = out_col;` and never multiplies the incoming vertex COLOR,
so **nothing `modulate` marks can draw**: the new legal-cell tint, and also `CardVisual.focused` —
the glow `Q249` calls "selected", which has therefore never been on screen. Both standing "no focus
highlight" look calls in `todo.md` are this one fact. The recommended fix is one token and switches
`modulate` on for EVERY card at once, which is a board-wide look change nobody has seen. The
blanket *"i will take recommendation for all gaps"* covered the ten gaps below; it does not reach a
gap raised after it was said. Do not build `GAP-011` without a fresh ruling.

**Entry docs:** `solatro/design/sidebar/` DESIGN.md (behaviour and the answer record), PLAN.md
(contracts), TEST_PLAN.md (rows), NAMES.md (identifiers), ASSUMPTIONS.md (every reading the run
invented), `gaps/GAP-001.md`..`gaps/GAP-010.md`; `solatro/ARCHITECTURE_REVIEW.md` §1.6 (the sidebar
and board input, the knob table, the measured gotchas), `solatro/PICTURE_WALL.md` (container
geometry, wiring, the pause rule), `solatro/todo.md` ("Sidebar: ten gaps" and "Sidebar: owner
should see"), `.claude/skills/plan-run/SKILL.md`.

## Provenance and the reviewer floor
- Code on this branch: `plan-implementer` subagent, Opus 5 at default effort. Sonnet wrote S1–S4's
  first pass only. Overseer: Fable 5.1 at high effort, then Opus 5 after a usage limit.
- Reviewer floor: Opus 5 at default effort or higher, same generation or newer. Never weaker.

## Run rules
- Worktree `../gamedev-sidebar`, branch `sidebar`. NEVER work in the main checkout: it shares
  `app_userdata/Solatro` with this worktree.
- The overseer writes no source. Every item is a `plan-implementer` dispatched FOREGROUND with a
  brief that quotes the ruling verbatim, names the call site, and states the comment and complexity
  rules. The implementer never stages or commits.
- At most two subagents at once, and only one runs Godot. The suite is one process: check
  `tasklist | findstr Godot_v4.7` before and after every run.
- Commit one verified item per commit, with the evidence in the message.
- Implementers append evidence to a scratch file as they go: a turn-cap stop fires no final reply.
  Resume a cut-off agent with SendMessage to the same agent id before considering a reset.
- Never `git checkout`, `git restore` or `git stash` a tracked file; park it with `Copy-Item`.
- Never write a source file with Python's `write_text`, which writes CRLF on Windows. Use the Edit
  tool or binary writes, and verify with `git ls-files --eol` or a Python bytes count. Git Bash
  `grep -c` for a carriage return counted CR on every line of an LF file.
- In the Bash tool a doubled backslash inside a quoted heredoc reaches Python as one; build it with
  `chr(92)`. A long quoted heredoc is fragile; prefer the Write and Edit tools for file content.

## The gate for every item
- Full windowed suite: `py solatro/Tools/run_tests.py`, with GODOT_BIN set to the box's
  `Godot_v4.7.2-stable_win64_console.exe`. Gate: `ALL 48 SUITES ... CHECKS PASSED`, at most 22
  placeholder warnings, 0 `SCRIPT ERROR` in the Solatro user data's `logs/godot.log`, and an exit
  profile of exactly `PagedAllocator ... WorkerThreadPool` plus `15 resources still in use` plus
  the `135 ObjectDB` note. The check TOTAL drifts between green runs; judge on the suite count and
  the failure set.
- `py .claude/tools/doc_check.py --changed`: zero findings on lines the item ADDED, intersected
  with `git diff HEAD -U0`. The legacy comment backlog in touched files stays, by owner ruling.
- Red-then-green for every new row: neutralise the behaviour, watch the expected checks fail,
  restore, watch them pass.
- Anything visual: render `Tests/Visual/sidebar_snapshot.tscn` with the NON-console exe, wait for
  the process to exit, and LOOK at the PNGs under the Solatro user data's `sidebar_snapshot/`.
- Known flakes, neither attributable to a change: an intermittent engine crash in TEARDOWN after a
  passing banner makes the wrapper exit 3; and an intermittent map Deck-button click failure right
  after a viewport resize (`a real click on the map's Deck button pressed it`), which passed in both
  neighbouring runs. Rerun once; a passing banner's verdict stands.
- ⚠ The placeholder-warning gate is AT its cap of 22 since `G5`. The next off-palette colour
  breaches it — see `todo.md`'s "two measured costs" item.

## Tasks: one per gap, each ending in its own commit
Each item: build the ruling, add the rows, then set the gap file to `status: built`, correct every
design doc the gap names, and delete that gap's bullet from `todo.md`.

```yaml
- id: G6
  gap: GAP-006, option (b)
  ruling: a key or pad focus does not start following; the armed card stays lifted in its slot, and
    only a mouse motion or a touch starts it. The pad places by accept on a cell.
  build: UI/play_area.gd, on_control_focus_entered stops calling follow_cards; the pointer stays the
    follow target for mouse and touch.
  tests: TEST_PLAN 9.4 becomes reachable, so capture it; a row that a key focus leaves the armed
    card resting in its slot, and that a later mouse motion starts the follow.
  docs: PLAN 1.4, DESIGN nodes G5-G9, TEST_PLAN 9.4.
- id: G7
  gap: GAP-007, option (a)
  ruling: after a failed drag, following restarts only on a NEW press, not on motion.
  build: UI/play_area.gd, _on_pointer_moved and _release_places.
  tests: extend TestDragPlace 5.3 with "then move the mouse"; the card stays in its slot.
  docs: DESIGN 1.6.
- id: G8
  gap: GAP-008, option (a)
  ruling: the cell-leave dismissal applies only to a card the player did NOT click to lock. A
    click-locked card keeps its description through the drag, and the placement closes it.
  build: UI/play_area.gd, the dismissal branch of _on_pointer_moved.
  tests: TestSidebar 1.7's fourth dismissal row splits into locked and unlocked cases.
  docs: DESIGN 1.2 B9.
- id: G5
  gap: GAP-005, option (a)
  ruling: the legal-cell highlight is a tint on each legal cell slot's own zone card, its colour
    from player_settings.gd, owned by the release-to-place path.
  build: UI/play_area.gd cell slots, one colour knob in Scripts/player_settings.gd.
  tests: a TEST_PLAN section 6 row; chart node G12 has none today. The tint follows what try_place
    accepts.
  docs: TEST_PLAN sections 6 and 11, DESIGN G12, E6, E16, NAMES for the knob.
- id: G1
  gap: GAP-001, option (b)
  ruling: the container cap applies only when the window is WIDER than the picture's aspect, so
    every 16:9 window keeps a 394 px inset and only ultrawides clamp.
  build: the container geometry in UI/hud_container.gd, PLAN 1.1.
  tests: TEST_PLAN 3.1 and 3.2 gain a 3840x2160 fixture.
  docs: PLAN 1.1, DESIGN D6, D7, D8, D10.
- id: G2
  gap: GAP-002, option (a)
  ruling: measure the board's region in the VISIBLE picture; every inset gains the crop on its axis,
    so the board fits and centres in what the player can see beside the container.
  build: the inset publication, GameView._publish_board_inset, through WallPicture.inset_beside.
  tests: TEST_PLAN 3.x fixtures at 16:10, 4:3 and portrait; nothing of the board sits under the
    container. This also answers the top-case grid offset listed in todo.md.
  docs: PLAN 1.1 and GAP-002's own note.
- id: G3
  gap: GAP-003, option (a)
  ruling: D11 is corrected. The map converts exactly as the board does, window px through the map
    picture's live scale and its own camera zoom. The code already does this.
  build: nothing; docs only.
  docs: DESIGN D11 and C13, PLAN 1.1's last line and 1.9's map note.
- id: G4
  gap: GAP-004, option (b)
  ruling: a viewer's description preview uses the viewer's own drawn card size. Already built.
  build: nothing; docs only.
  docs: DESIGN's Q34 note, and TEST_PLAN wherever it states the board's size.
- id: G9
  gap: GAP-009, option (b)
  ruling: an Undo button inside the win or lose screen beside Continue, in the same SubViewport, so
    a pad walks from Continue to Undo. The HUD's Undo stays for the mouse.
  build: the outcome screen in Levels/game_view.tscn and game_view.gd, reusing
    GameView._on_undo_pressed.
  tests: a pad reaches Undo from the outcome and rewinds to a live board. Close fix 8 measured that
    it cannot today.
  docs: DESIGN J11, NAMES for the button.
- id: G10
  gap: GAP-010, option (c)
  ruling: an explicit Back control in the description panel while a preview card is shown.
    WARNING, Q135 = (b) itself is NOT built: the S23 brief misquoted it as (a), so hovering a
    preview card currently changes nothing. This item builds the switch AND the Back control.
  build: UI/description_panel.gd (_make_still, slot ownership, scroll memory), UI/hud_container.gd,
    UI/map_hover_panel.gd (get_info passes an inspect callback), Levels/map.gd. Mouse, pad and touch
    must all reach the preview cards, per Q137=a.
  tests: TestSidebar S23.5 is re-aimed from (a) to (b); a row for the Back control returning the
    pack with its grid.
  docs: DESIGN K9 is already correct; TEST_PLAN gains a K9 row; NAMES for the control.
```

## Suggested order
G6, G7 and G8 first: they share `UI/play_area.gd`'s follow and dismissal rules. Then G5 on the same
file. Then G1, G2 and G3 as one geometry pass. Then G4 and G10 on the panel and the viewers, and G9
last, since it touches the outcome screen alone.

## Also waiting on the owner, from `solatro/todo.md`
"Sidebar: owner should see" lists what the close left as look calls: a card name breaking at its
period, the top-band HUD overflowing its band, the exit X over the scrollbar, overlay buttons that
grow but never shrink, the scroll container's focus border drawing two lines across the board, the
top-case grid offset (G2 above), cards drawn above the picture mid-cascade, no focus highlight in a
viewer, and the intermittent teardown crash. None of them blocks this work.

Three tooling questions are open too: whether the deferred legacy-comment ruling is permanent,
whether `doc_check` should gain an added-lines mode, and whether the hook file
`one-subagent-at-a-time.ps1` should be renamed now that the cap is two.

Resume prompt: *"Build the ten answered sidebar gaps. Worktree `../gamedev-sidebar`, branch
`sidebar`. Read `solatro/HANDOFF_sidebar_gaps.md` FIRST, then `git log --oneline -5`, `git status
--porcelain` and a full suite run, before dispatching anything."*

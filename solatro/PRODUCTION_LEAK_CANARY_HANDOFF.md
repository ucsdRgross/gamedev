# Handoff: comprehensive PRODUCTION leak canary (owner-endorsed 2026-07-17)

Written 2026-07-18 for an agent with NO prior context. Repo:
`C:\richard\gamedev\solatro` (Godot 4.7 GDScript). Read this whole file, then
`solatro/todo.md` §Memory (the owner's spec — authoritative) before writing code.

## Mission

Build a canary test suite that simulates a REAL play session end-to-end, N cycles,
and asserts `Performance.OBJECT_COUNT` returns to a post-warm-up baseline. The
existing canary (`Tests/Engine/test_leak_canary.gd`, 23rd suite) only covers bare
headless `Game` build/teardown cycles; what matters now is leaks a PLAYER can
accumulate through the actual UI/flow. Owner ruling: test-only leaks do NOT matter
(the ~700-instance suite-exit floor is accepted — do not chase it); PRODUCTION
leaks are the target.

## Background you need

- CardData<->modifier backrefs are RefCounted CYCLES Godot never collects. Any
  card graph built and dropped without `unlink_card_backrefs` leaks until exit.
  The 2026-07 sweep proved production autoloads leak 0 in the covered paths and
  landed ONE production fix: `Game.undo()` unlinks the outgoing live state
  (quiescent point). `_restore_pre_act_board` deliberately does NOT unlink — mods
  still run against the doomed state there (see its comment). NEVER "fix" that.
- Attribution tooling exists: `Tests/Support/leak_probe.tscn` runs ONE suite scene
  then quits, so the engine's exit-leak count attributes per suite. Keep and reuse.
- History/details: `solatro/todo.md` §Memory, `EFFICIENCY_AUDIT_TRACKER.md`
  (dated 2026-07-17 entries), `Tests/Support/test_base.gd` comments.

## What each cycle must exercise (owner spec, todo.md §Memory)

Everything that creates Nodes or RefCounted card graphs:

1. Menus / DeckPicker open+close (builds decks); viewers open+close: DeckViewer,
   ChoiceViewer, map hover panel.
2. Map: enter, traverse a node or two, open a booster choice.
3. A real show WITH a GameView attached (not `view == null`): a few Nexts,
   grab/place moves on the board, draw + discard, a Submit with real scoring so
   props spawn and finish, then UNDO across the Submit (undo swaps whole GameData
   snapshots — the Game.undo() unlink covers the quiescent path; the canary should
   PROVE it).
4. Quit-mid-show -> resume (RunManager save/load relink), `exit_show` on BOTH the
   win and loss paths, `clear_save`.

## Structure & rules

- Extend `test_leak_canary.gd` or add a sibling suite in `Tests/Engine/` — either
  way it must run LAST and ALONE: `OBJECT_COUNT` is engine-global. Mind ⚠️ THE
  DEADLOCK RULE in `Tests/Support/test_base.gd` (~line 44): waiting is a directed
  dependency; the `await_siblings_except` excludes must stay consistent across
  suites or the whole run hangs. Every earlier waiter already excludes
  "LEAK CANARY" — a new suite name needs the same treatment everywhere.
- Copy the existing canary's discipline: (a) a warm-up cycle FIRST (lazy deck
  caches, static registries must not count), (b) `_settle()` two frames before
  every count, (c) `print_orphan_nodes()` on failure, (d) a "prove it can detect"
  step — deliberately leak once BEFORE the baseline snapshot and assert growth.
- Known accepted sources to tolerate/pin (not leaks): `RunManager._saveable_deck`
  cache (rebuilt per deck change), TestLog file handles.
- Any board/state mutation in tests MUST bump `state.revision` after consistency
  (the position index is a lazy revision-keyed cache in `GameData.position_of`;
  a raw mutation without a bump reads stale positions).
- UI parts likely need the real scene tree, not headless-with-no-view. Note
  Solatro's suite runs `--headless` fine (it never awaits `frame_post_draw`), but
  if you must render frames for GameView/props, verify prop timers/tweens finish
  before counting (await their completion signals, not fixed frame counts).

## Validation

- Full suite: `C:\richard\Godot_v4.7-stable_win64_console.exe --headless --path
  C:\richard\gamedev\solatro res://Tests/all_tests.tscn` — exit code = failure
  count; bar is ALL suites green (24 if you add a suite — update the expected
  count in any banner/docs). Check TOTALS vary run-to-run (data-dependent
  suites); compare failure sets, not totals.
- If "Could not find type X" cascades appear: stale global class cache — run once
  with `--import` first.
- Isolate your suite via `Tests/Support/leak_probe.tscn` to attribute its own
  exit-leak contribution; keep it near zero (unlink everything you build in
  teardown — `test_base.gd` has the `unlink_cards` helper).

## On completion, update

- `solatro/todo.md` §Memory (mark the owner item DONE, note suite count).
- `EFFICIENCY_AUDIT_TRACKER.md` — dated entry (what landed, numbers, run log).
- If you touched any production file, call it out explicitly in both.

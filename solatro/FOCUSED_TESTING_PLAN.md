# PLAN — focused suite testing

Temporary plan doc. When it lands, fold the rules into `HEADLESS_TESTING.md` (§0 runbook, §0a
bounding), add the residue to `ARCHITECTURE_REVIEW.md` §7, update the memories listed in §5, and
**delete this file.**

## 1. The problem, in measured terms

- `Tests/all_tests.tscn` has **43 suite children**, all-or-nothing. There is no way to run a subset
  without hand-editing the scene.
- A full attempt costs ~7 minutes (`todo.md`, hang item), windowed, GPU-bound, one run at a time
  ([[running-godot-scenes]]). That is the unit of feedback for a one-line change.
- **No timing instrumentation exists.** `Time.get_ticks_msec()` appears nowhere in
  `Tests/Support/test_base.gd` or `Tests/all_tests.gd`, so "the tests are slow" currently has no
  breakdown behind it. Nothing here should be optimised before §3 Phase 0 measures it.
- `speed_base_delay` is already 0.01. The animation knob is spent; the cost is elsewhere.

Two facts already in the repo say focused runs are viable and wanted:

- Every suite is its own PackedScene with a single Node (`Tests/Engine/test_board.tscn` →
  `TestBoard`), and `TestLog.line()` self-starts for a suite run straight from its own scene.
- `todo.md`'s hang item records that every suite in the stalled tail **"completes cleanly when run
  ALONE."** Solo runs are already the diagnostic instrument; they are just undocumented and unsafe
  to launch.

## 2. The invariants this must not break

Each one is currently load-bearing. Any task below that weakens one is wrong.

1. **A focused run is a debugging aid, never a verification** ([[one-fix-at-a-time]]). Nothing here
   changes what counts as green: the full windowed run through `Tools/run_tests.py`.
2. **The SUITE count is the only detector for a suite that failed to parse and load**
   (`HEADLESS_TESTING.md` §0a — the check total drifts run to run, the suite count does not). A
   filter deliberately changes that count and therefore destroys the detector for that run. A
   filtered run must be unable to *look* green.
3. **The engine-error gate is the verdict, not `check()` alone.** `all_tests.gd::_scan_engine_errors`
   plus the stream gate in `Tools/run_tests.py` caught both known false greens. Any focused path that
   bypasses `all_tests.tscn` also bypasses both.
4. **Suite ordering is a directed dependency graph** (`Tests/Support/test_base.gd`, DEADLOCK RULE).
   Filtering may only ever REMOVE nodes; it may never reorder them.
5. **Disk isolation stays per-suite.** `run_bak_path(tag)` / `_settings_bak_path()` derive from the
   suite name. A filter changes which suites run, not how they park files.

## 3. Phases and task list

### Phase 0 — measure first

- ⬜ Add elapsed-time capture to `TestSuite`: stamp in a base-class `_enter_tree()`, diff in
  `finish()`, print in the suite banner.
- ⬜ Print a sorted tail in `Tests/all_tests.gd` after the grand total: slowest N suites by **finish
  timestamp relative to run start**, not by duration. Suites run CONCURRENTLY, so durations overlap
  and do not sum to the run length — the last finisher is what you actually wait on.
- ⬜ Record the measured tail in this doc before doing Phase 1. The expectation to falsify: the cost
  is the serialized `INTERACTION -> UI PROPS -> VISUAL LAYERS -> E2E RUN -> LEAK CANARY -> WALL
  PAUSE` chain plus the GPU-bound `PIXELS`, not an even spread.

### Phase 1 — a suite filter on the real runner

Keeps the quit, the exit code, the error gate and the log discipline. Prune in `_enter_tree`.

```gdscript
func _enter_tree() -> void:
	var filter := _suite_filter()                   # OS.get_cmdline_user_args(), after `--`
	if not filter.is_empty():
		for child in get_children().duplicate():    # copy: we mutate during ENTER_TREE propagation
			var keep := false
			for pat in filter:
				if child.name.to_lower().contains(pat.to_lower()): keep = true
			if not keep:
				remove_child(child)
				child.free()
	TestLog.begin(terminal_output == TerminalOutput.ERRORS_ONLY)
```

- ⬜ Implement `_suite_filter()` reading `OS.get_cmdline_user_args()`.
- ⬜ Prune in **`_enter_tree`, not `_ready`.** Parent `_enter_tree` fires before any child enters the
  tree (already stated in `Tests/all_tests.gd`'s own `_enter_tree` comment); by parent `_ready` every
  child has already run.
- ⬜ Use **`remove_child()` + `free()`, never `queue_free()` alone.** `queue_free` defers to end of
  frame, so the suite's `_ready` fires and the suite runs anyway.
- ⬜ Iterate a `duplicate()` of `get_children()` — the list is mutated mid-propagation.
- ⬜ Match case-insensitively on the NODE name (`TestWallInput`), so one pattern selects the whole
  Wall group and two patterns select two suites. Node name, not `suite_name()`: the scene is the
  registry, and scene filename is not script name in places (`test_scoring.gd` lives in
  `Tests/Engine/test_score.tscn`).
- ⬜ **The filtered banner must be unmistakable** (invariant 2): it names the filter, prints
  *selected of total*, and says in words that it is NOT a green signal for the project.
- ⬜ Verify `await_siblings_except` still terminates for every surviving subset, including a filter
  that keeps a waiter and drops everything it waits for, and one that keeps `WALL PAUSE` alone.

Invocation: pass the filter as a user arg after `--` to `res://Tests/all_tests.tscn`.

### Phase 2 — teach the wrapper about filtered runs

- ⬜ `Tools/run_tests.py` accepts and forwards the filter argument.
- ⬜ It **refuses to print a clean verdict** when a filter was passed — the exit code stays the
  failure count, but the human-facing banner says FILTERED. Otherwise this becomes a machine for
  producing the exact false green the error gate exists to stop.
- ⬜ Keep the stream gate active on filtered runs. It is the only part of the verdict a filter does
  not invalidate.
- ⬜ While in this file: `run_tests.py` discards the suite's stdout by design, which `todo.md` records
  as why intermittent-failure evidence is always already gone. Consider a keep-the-log option here,
  since a focused loop makes per-run logs cheap to keep.

### Phase 3 — the two-tier loop

The real win is not filtering, it is that the logic tier does not need a GPU.

- ⬜ Define a LOGIC tier: the suites that are renderer-independent (`Tests/Engine`, `Tests/Map`, the
  Wall logic suites). `HEADLESS_TESTING.md` §0 already sanctions headless for these.
- ⬜ Add a tier shorthand rather than making every caller spell out the suite list.
- ⬜ Confirm headless exit codes are usable for the tier: `PIXELS` must not be in it (it FAILS rather
  than skips under headless, by design and by owner ruling — do not "fix" that).
- ⬜ Inner loop = headless logic tier, seconds. Gate = full windowed run. Document both in
  `HEADLESS_TESTING.md` §0 as a two-line runbook.

### Phase 4 — solo-scene runs, documented rather than discovered

Running a single suite scene directly already works. Three traps make it unsafe as written, and all
three are silent:

- ⬜ **It never exits.** `finish()` only emits `suite_finished`; `get_tree().quit()` lives in
  `Tests/all_tests.gd`. A hard-kill timeout is mandatory, not advisory (`HEADLESS_TESTING.md` §0a).
- ⬜ **It truncates the full-run log.** `TestLog.begin()` opens `test_output_all.log` for WRITE.
  Decide: either a solo run writes to a distinct filename, or the runbook says copy the log first.
- ⬜ **No engine-error gate at all** — `_scan_engine_errors` is in `Tests/all_tests.gd`.

Given Phase 1 exists, prefer the filter over a solo scene; it fixes all three for free. Keep the solo
path documented only as the editor-side convenience it is.

## 4. Explicitly out of scope

- **Migrating to GUT or gdUnit4.** Assessed and declined: ~33.5k lines and 2,147 checks, and neither
  framework has the engine-stderr gate, the BEHAVIOR/IMPLEMENTATION split, or the disk-parking. If it
  is ever revisited, the answer is GUT — this is a pure-GDScript project, GUT tracks Godot 4.7 while
  gdUnit4's latest builds on 4.5, and gdUnit4's differentiators are C# and .NET tooling that do not
  apply here. The single feature worth taking from either — selective runs — is Phase 1, at a
  fraction of the cost.
- **Mocking / auto-generated doubles.** An auto-double returns a type default from every method you
  forgot to stub, which is the `FakeEnvironment` empty-revision-key failure generalised to every
  method at once ([[no-mocks-in-tools]]). Hand-written fakes stay; `EventLog` already covers the one
  real gap (call-order assertions) on real objects in a real run.

## 5. Docs, memory, skills and hooks to update

**Do these in the same change as the code.** Two of them currently state the opposite of what this
plan lands, so a half-done migration leaves the repo contradicting itself.

### Memory (`.claude/memory/` — the repo copy, never the machine-local one)

- ⬜ `running-godot-scenes.md` — **currently says individual suite scenes do not self-quit, so run
  `all_tests.tscn` and not a lone suite.** Replace with the filtered invocation, keep the
  no-self-quit fact as the reason, and keep the never-force-quit-after rule intact.
- ⬜ `running-godot-scenes.md` — add the two-tier loop under "Launching it": headless logic tier for
  the inner loop, full windowed run as the gate.
- ⬜ `one-fix-at-a-time.md` — its "a single-suite run is a debugging aid, never a verification" line
  is CORRECT and gets stronger, not weaker. Add only that a filtered run's banner now says so itself.
- ⬜ `tests-that-prove-nothing.md` — add the new entry this plan creates: **a filtered run read as a
  full one.** It is the same shape as the others — a green banner over checks that never ran.
- ⬜ `MEMORY.md` — no new memory files expected; if one is added, one line, hook only.
- ⬜ Run `py .claude/tools/doc_check.py` after: it proves the memory links and file references above
  still resolve.

### Project docs

- ⬜ `HEADLESS_TESTING.md` §0 — the runbook gains the filtered and tiered invocations. §0a's
  "bound the run" rule extends verbatim to solo scenes, which never self-quit.
- ⬜ `HEADLESS_TESTING.md` §0a — restate that the suite-count detector is void under a filter.
- ⬜ `ARCHITECTURE_REVIEW.md` §7 — the filter is a testing convention and belongs with the rest.
- ⬜ `START_HERE.md` — one row in the doc table while this plan is live; delete the row with the file.
- ⬜ `todo.md` — one line pointing here; delete it when this lands.
- ⬜ **Reconcile the suite count across docs.** The scene has 43 suite children; `todo.md`'s hang item
  says 39 and `HEADLESS_TESTING.md`'s sample banner says 30. Since invariant 2 makes that number the
  load-bearing detector, a stale count in a doc is a real defect. Prefer wording that does not
  hardcode it.

### Skills

- ⬜ `.claude/skills/plan-run/SKILL.md` — says a full suite run is the only ground truth. Keep that
  sentence. Add the inner loop as what happens BETWEEN gates, so an implementer subagent stops paying
  ~7 minutes per iteration without ever being told it may skip the gate.
- ⬜ `.claude/skills/fx-verify/SKILL.md` — check whether it names `all_tests.tscn` directly; visual
  work must NOT move to the logic tier.
- ⬜ `.claude/skills/docs/SKILL.md` — no change expected; confirm.

### Hooks

- ⬜ **No new hook is required.** Record why, so it is not re-proposed: `CLAUDE.md` deliberately does
  NOT install a PostToolUse suite run, because the suite is windowed and would fight the owner's
  editor.
- ⬜ **Open for the owner:** Phase 3 removes the window from that objection — a headless logic tier
  could run on PostToolUse without touching the GPU or the editor. It is still the owner's call, and
  the remaining objection is unchanged: one run at a time, and a background run colliding with a
  manual one fabricates failures in unrelated suites. Do not install it unasked.
- ⬜ The two `PreToolUse` guards and the `Stop` doc check are unaffected.

## 6. Open questions

- ⬜ Does the filtered inner loop change the intermittent-hang picture? `todo.md` records the tail
  suites passing alone and hanging together. If Phase 1 makes subsets cheap to run, the hang becomes
  bisectable by SUBSET for the first time — that may be worth more than the speed.
- ⬜ Should the logic tier be a name in the scene (a group, a node prefix) rather than a list in the
  runner? A list drifts the moment a suite is added; the scene is the registry everywhere else.

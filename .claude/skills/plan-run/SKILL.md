---
name: plan-run
description: Execute an already-written implementation plan using an overseer session plus implementer subagents — the step that follows /flowchart-design. Sets up the worktree and reversed commit policy, shapes each step brief so components cannot ship unwired, and carries the verification hierarchy plus the ten ways a test passes while proving nothing. Use when DESIGN/PLAN/TEST_PLAN/NAMES exist and the work is execution, or when asked to run a plan with subagents.
---

# Running a plan with an overseer and implementer subagents

`/flowchart-design` produces `DESIGN.md`, `PLAN.md`, `TEST_PLAN.md` and `NAMES.md`. This skill
executes them. The split: **one session holds the plan and never reads code; subagents hold the code
and never hold the plan.** That keeps the overseer's context plan-shaped across dozens of commits,
which is what lets a long run survive.

⚠ **The pattern's known blind spot, and the reason half this document exists:** the overseer verifies
what it can *observe*, and the implementer optimises to the *done-when it is handed*. Neither owns
"does this actually do anything in the running game." A run using this pattern shipped a gesture
tracker with no caller, an info card mounted nowhere, four dead input actions, and a layout tool
editing a file the game never loaded — **every one with passing tests.** Everything below aims at
that failure.

## Setup

- A **git worktree on its own branch**, never the main working tree. The owner merges when done.
- **The repo's no-commit rule is REVERSED for the overseer on that branch**: commit after every step
  you verified yourself, one step per commit. Commits are the only rollback points, and a long run
  will lose sessions to API limits — assume it.
- The implementer still never commits, never stages, never stashes.
- Use `/handoff` for `<project>/HANDOFF_<topic>.md`. Record the EVIDENCE that proved each done-when
  (the grep output, the banner line), not prose. A cold overseer must be able to resume from it.

## The overseer's rules

**Never** read, edit or write source files; never print file contents; never `git diff` without
`--stat`. **May** read the plan documents, the handoff, cited design sections, gap files and agent
reports; may run `grep -c`/`-l`, `git status --porcelain`, `ls`, and the suite.

**Verify every done-when yourself with a bounded command.** Never accept a self-reported green.

## Writing a step brief

The implementer's definition already carries the report schema and repo rules, so a brief is short —
but it MUST carry:

1. The step id and its **exact done-when, quoted** from the plan.
2. The **test-plan row ids** that step owes. A dropped planned row is a gap, not a judgement call.
3. ⚠ **The CALL SITE.** "Where is this called from, and what breaks if it is deleted?" A step whose
   done-when is only "TestX is green" will ship a component nothing calls. Require a test that fails
   when the wiring is removed.
4. Any trap below that applies, named specifically.

**Never accept `STATUS: done` on a component whose consumer does not exist.**

## The verification hierarchy — weakest to strongest

Each layer caught things the one above it missed.

1. **A green suite** — proves almost nothing. Eight tests in one run passed while asserting nothing.
2. **Greps and counts** — catch contract drift (field lists, registries, knob sets), never behaviour.
3. **Reading the diff** — catches structure and dead code, but not user journeys.
4. **Red-then-green proof** — caught a real defect *every single time*.
5. **An adversarial reviewer tracing what a player actually does** — highest yield of the whole run.

**Do 3 and 5 at every phase boundary.** Doing them only at the end means finding six critical defects
after the work is already "complete".

## Red-then-green is mandatory

For **every new test**, not only for bug fixes: neutralise the behaviour, watch the test fail,
restore it, watch it pass, report both observations.

⚠ **Check the red run failed the checks you EXPECTED.** A neutralisation that breaks the TEST rather
than the behaviour aborts the test function, and the banner then reads all-passed with those
assertions silently missing — the same shape as the defect you are hunting.

⚠ When a fix makes an existing test fail, **investigate before adjusting it** — one run found a
tolerance that had been calibrated to the bug, so it passed *because* the defect existed.

## The ten ways a test passes while proving nothing

1. `await some_timer` instead of `await some_timer.timeout` — awaiting a non-signal resolves instantly.
2. **Lambdas capture outer locals by value.** `var fired = false` then `func(): fired = true` writes
   to a copy. Box it in a one-element `Array`.
3. **A fixture chosen so the implementation passes** — a symmetric pair hiding an asymmetric defect,
   or "settle every item" so the interesting one is never in the interesting state.
4. **A leak that is not a check failure** — a class extending `Node` needs an explicit `.free()`.
5. **A loop or sampler whose body never runs.** Assert the sample count is non-zero *before*
   asserting anything about its contents.
6. **An assertion on a local the production path never touches** — it re-proves a data structure's
   own arithmetic while being unable to fail for the wiring bug it exists to catch.
7. **A tolerance calibrated to a bug.**
8. **A new test that breaks a DIFFERENT suite** — global state left behind (pause flags, a live node,
   a running tween). If the banner reports a failure you cannot find in your own suite, suspect your
   fixture's side effects.
9. **A fixture that clears the very global state the feature runs under.** Every `Main`-based test
   in solatro wrote `get_tree().paused = false` right after `add_child()`; the shipped game holds
   the tree paused for the whole session. That one habit hid a total soft-lock, a timer that never
   fires, and a camera resting at the wrong zoom — all three green, for a whole run. Ask what
   ambient state the real product runs under, and whether the fixture just turned it off.

10. **Two competing mechanisms with the SAME observable.** A test can pass because the WRONG
   mechanism happens to produce the right answer. Measured: a re-pack test passed with its fix
   removed, because the stale tween and the correct one wrote the same property every frame and the
   later one landed last — the defect was real and invisible. Separate the two before asserting
   (there, by making the stale animation outlive the correct one) or the test is measuring which
   writer ran second.

## Traps that are not about tests

- **Know exactly which log is the gate, and check its mtime.** One run read a stale 0-byte error log
  for its entire length. Engine logs are overwritten by whichever process wrote last — including the
  overseer's own runs.
- **A banner can report a failure that is not a check** ("0 behavior, 0 implementation") — that is an
  unexpected engine error. Read the newest engine log's backtrace.
- **A single-suite run is a debugging aid, never a verification.** Only the full suite with a real
  banner counts; "no banner" is a crash, and a crash is a failure of the change that produced it.
- **One critical fix at a time**, full suite between each. Six independent fixes landing together
  became one unfixable state that crashed the engine, with no way to tell which caused it.
- **A tunable literal in a source file is a defect**, even when it looks like an epsilon. Sweep
  touched files for numeric and colour literals at the end of every step.
- **Diff your identifiers against the registry before reporting.** Invented names and signals stop
  the registry being authoritative.
- **Comments deferring to "a later step"** become lies when that step lands. Grep the deferral
  language when closing one.

## Gaps

Follow the plan's own gap protocol. As overseer: **a bug is not a gap.** A gap is a decision the
design does not cover. If exactly one choice is defensible, it is a defect — fix it and record it.
File a gap only when two defensible options differ in observable behaviour, when reversal is
expensive, or when it is an owner call.

**Quote a gap's own option text when asking the owner to decide.** Paraphrasing one caused an answer
to be given against a mislabelled list.

## Interruptions

Sessions die to API limits — plan for it. On resume: read the handoff, then `git log --oneline`,
`git status --porcelain`, and **a full suite run**, which is the only ground truth. If the suite is
green and the last claimed step's done-when still passes, continue; otherwise that step is suspect —
reset to the last commit and redo it. Never resume mid-step.

⚠ **Never reset the tree while a subagent is working in it.** One run did, and the agent correctly
reported the worktree as corrupted — it had no way to know the overseer had rolled it back. Tell it
first, and confirm it has stopped.

## Closing the run

Before calling it done: read the full diff yourself, run an adversarial review against the design,
charts, plan and tests, and fix what they find. Then fold the run's residue into the living docs with
`/docs` and delete the temporary plan documents the run produced.

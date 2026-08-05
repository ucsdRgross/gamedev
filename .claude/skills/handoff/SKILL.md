---
name: handoff
description: The session-continuity loop for this repo — read a handoff doc to resume work with zero prior context, and keep it updated as durable state while executing. Use when picking work back up, when asked for a handoff or checkpoint, when turning a plan into a resumable run, or partway through long multi-phase work before the session runs out.
---

# Handoff

One file per work stream: `<project>/HANDOFF_<topic>.md` (e.g. `solatro/HANDOFF_fx.md`). It is
both the resume point and the live journal — **never split state across two files**, and never
create a parallel copy of an existing handoff. Update it in place.

## Resuming (the file exists)

1. Read it, plus the `entry_docs` it names. Do not rely on conversation history — the file is the
   source of truth.
2. Confirm the tree is actually green before trusting any `done` status: run the suite,
   `<binary> --path solatro res://Tests/all_tests.tscn`, **windowed, no `--headless`** (~60 s,
   self-quits with the failure count). Check the owner's Godot editor is closed first.
3. Summarize goal, what is done (with its evidence), what is in progress or blocked, what is
   next. That summary must stand on its own with zero prior context.
4. Continue from the first `pending` task.

## Starting fresh (no file yet)

Read the project's entry doc first — `solatro/START_HERE.md`, `solatro/VFX.md` for effects work,
`palette/ARCHITECTURE.md` then `PROGRESS.md`, `worldgen/START_HERE.md` — then decompose the work
into the structure below and start executing.

## Structure

````markdown
# HANDOFF — <topic>

**Goal:** one sentence; what "done" means for the whole stream.
**State:** one paragraph; where this actually stands right now.
**Entry docs:** solatro/START_HERE.md, solatro/VFX.md

## Tasks
```yaml
- id: fx-01
  description: Concrete enough to start cold.
  files_touched: [solatro/Effects/fire.gdshader]
  verification_command: '<godot> --path solatro res://Tests/all_tests.tscn'
  verification_kind: suite      # suite | snapshot | perf | manual
  status: pending               # pending | in_progress | done | blocked
  evidence: ''                  # paste of the real output / measured numbers
  notes: ''                     # blockers, decisions, what was tried
```

## Verified vs assumed
Per claim: the exact command plus measured numbers that prove it, or an explicit
"assumed, not checked". Visual claims count as verified only with a rendered snapshot
someone looked at.

## Open bugs
Each with repro steps and the file:line where it surfaces.

## Files touched
From `git status` / `git diff --stat`.

## Next up
The next 3 tasks in priority order, then a copy-paste opening prompt for the next agent.
````

## Per-task loop — never batch

1. Set `status: in_progress`.
2. **Before writing code: name the competing READINGS of whatever the step specifies, and test the
   input that separates them.** Two sentences is enough. ⚠ Measured on the spotlight stream: a rule
   that arrives with a worked example has two representations — the example and the general rule —
   and they can differ. Both readings reproduce the example, so **the case that matters is the one the
   example does not cover**, and that is exactly the case with no test.
3. **If the design has a plan beside it, run its checks before starting** — for a `/flowchart-design`
   stream that is `npm --prefix designloop run check -- <project>/<slug>`, and **read `unclaimed`**:
   answered questions no plan step implements. First run on spotlight: 190 of 255, including the one
   that had already shipped wrong through three phases.
4. Do the work.
5. Run its `verification_command`. For `verification_kind: snapshot` that means the `/fx-verify`
   gate — render and actually look at the PNG. ⚠ **If the change has a DURATION, a still frame is the
   wrong instrument**: run it and report what MOVED. See `/fx-verify`.
6. Paste the real output or measured numbers into `evidence`. Never write evidence you did not
   observe; never paste a green banner from a different run.
7. Set `status: done`, or `blocked` with the reason in `notes`.

Update the file after **every** task and **at the 60% mark of the session at the latest** — not
as an end-of-session artifact. Sessions here have died mid-handoff; the file existing early is
the entire point.

## Rules

- **Repo-relative paths only** — no machine-local absolute paths, no references to memory files.
  The next agent may be on a different machine.
- **Do not `git add` or commit on your own.** The owner drives this repo through GitHub Desktop.
  Evidence lives in this file rather than in commit messages. If they have authorized commits for
  the session, commit after a green verification with a message naming the task id.
- **No dated history logs in living docs** (owner policy). When the stream lands, fold the residue
  into `ARCHITECTURE_REVIEW.md` / `todo.md` and delete the handoff — but run `git ls-files <path>`
  first, since deleting an untracked file destroys it.
- ⚠ **KEEP IT UNDER ~300 LINES, AND PRUNE WHEN IT DRIFTS OVER.** Measured 2026-08-04: the spotlight
  handoff reached **1097 lines** by appending `⚠ HISTORICAL` and `✅ FIXED` blocks instead of removing
  them — every session then paid that cost to start, for content that was already in the gap files.
  **A fixed bug's forensics belong in its `GAP-NNN.md`; a resolved decision's belong in the design's
  changelog; an instrument's how-to belongs in the doc that owns it.** This file holds what is TRUE
  NOW: goal, state, the ledger, current evidence, OPEN bugs, next up. When you find yourself writing
  "historical, kept because", that content has a home and it is not here.
- **Write the ledger so the tooling can still read it.** `designloop/src/gaps.mjs::planSteps()` reads
  `id: Sn` out of the YAML, which is what keeps the stale-step report working from this file as well
  as from the plan. Verify after any restructure:
  `node --input-type=module -e "import {planSteps} from './designloop/src/gaps.mjs'; …"`.
- Include a references/sources section; the owner expects plans and handoffs to carry them.
- Keep going through mechanical work. Surface to the owner for subjective visual judgment, an
  architectural decision the plan does not cover, a failure suggesting the plan itself is wrong,
  or a task blocked on their editor being open. Report failures with the actual output.

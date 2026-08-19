---
name: one-fix-at-a-time
description: "Land one fix per full-suite run; a batch that goes red or crashes cannot be diagnosed"
metadata:
  type: feedback
---

Six independent critical fixes were briefed as one batch. The result was a tree that failed four
checks on one run and **crashed the engine outright** on the next two, with no way to tell which
change caused what — a crashing engine masks every other failure behind it. It was rolled back
whole, and redone one at a time, each with its own full-suite run and its own commit. Every one
passed.

**Rules:**
- One fix, then the FULL suite, then the next. Each green fix is its own commit and its own rollback
  point.
- **A single-suite run is a debugging aid, never a verification** — it says nothing about the other
  suites, and cannot see a crash that only appears in the full run.
- **"No banner" is a crash — but it is not always YOUR crash.** Treat it as a failure of the change
  that produced it *only after re-running once*. Measured on solatro: 3 consecutive hangs at 30 of
  39 suites, then a clean HEAD twice, then the SAME working tree twice — 3 hangs and 4 passes with
  no code difference between them. Following this rule literally bought a bisect that proved
  nothing. If a suite hangs, re-run before you bisect; if the hang follows the change across
  several runs, then it is yours. ⚠ The converse still holds: never re-run until it passes and call
  that a result.
- A banner reporting a failure with "0 behavior, 0 implementation" is an **unexpected engine error**;
  read the newest engine log's backtrace.

⚠ **Never reset or roll back a worktree while a subagent is working in it.** One run did, and the
agent correctly reported the tree as corrupted — it had no way to know. Tell it first and confirm it
has stopped. See [[running-godot-scenes]].

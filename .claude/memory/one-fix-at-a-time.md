---
name: one-fix-at-a-time
description: "Land one fix per full-suite run; a batch that goes red or crashes cannot be diagnosed"
metadata:
  type: feedback
---

Six independent critical fixes were briefed as one batch. The result was a tree that failed four
checks on one run and **crashed the engine outright** on the next two, with no way to tell which
change caused what — a crashing engine masks every other failure behind it. Redone one at a time,
each with its own full-suite run and its own commit, every one passed.

**Rules:**
- One fix, then the FULL suite, then the next. Each green fix is its own commit and its own rollback
  point.
- **A single-suite or tiered run is a debugging aid, never a verification** — it says nothing about
  the other suites and cannot see a crash that only the full run shows.
- **A hang or a missing banner after a fix is not yet that fix's crash.** Re-run once before you
  bisect; [[running-godot-scenes]] "Diagnosing a red, hung or flaky run" has the measurements and
  the rest of the procedure.

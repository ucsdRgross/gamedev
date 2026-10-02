# Deliberately not installed

Each for a measured reason. Installing any of them is the owner's call.

- **A PostToolUse hook running the test suite after every Edit.** The full Solatro suite is minutes
  long and must run WINDOWED, so per-edit runs would fight the owner's editor. ⚠ The headless logic
  tier (`solatro/Tools/run_tests.py --logic`, no window) removes that objection and is STILL not
  installed — one run at a time, and a background run colliding with a manual one fabricates
  failures in unrelated suites. Run either at a task boundary.
- **A pre-commit AI review.** A per-commit reviewer cannot see the duplicate it should catch — the
  other copy is in a commit that is not in front of it — so it returns nits. The gate at commit time
  is deterministic (`.claude/hooks/commit-gate.ps1`); the model-driven passes belong at the
  work-stream boundary where the whole diff exists.
- **A weaker model as reviewer, ever.** See `/plan-run`'s "The reviewer's model floor".
- **A parallel implementer swarm in worktrees.** The owner kept `CLAUDE.md` hard rule 2: every
  worktree shares `user://settings.tres`, `godot.log` and the window.
- **A scripted headless `claude -p` loop, one plan step per call.** It bypasses the overseer, the
  reviews and the owner's questions.

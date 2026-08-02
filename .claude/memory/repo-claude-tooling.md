---
name: repo-claude-tooling
description: "gamedev/.claude/ holds project skills (/handoff, /fx-verify, /flowchart-design), the plan-auditor subagent, and a hook that blocks name-based process kills — set up 2026-07-30"
metadata: 
  node_type: memory
  type: reference
  originSessionId: 75157de2-6326-43ea-b7df-1a25b81a7de6
  modified: 2026-08-01T11:55:32.282Z
---

`<repo>/.claude/` carries this repo's agent tooling, added 2026-07-30 from the /insights
suggestions. **All of it is tracked in git and therefore portable across the owner's computers** —
skills, agents, hooks, settings, launch configs, and (since 2026-08-02) `.claude/memory/`, which is
the source of truth for memory; the per-user memory directory is a cache a second machine will not
have. `/CLAUDE.md` at the repo root states the rule and loads automatically everywhere.
Prefer these over improvising the same workflow:

- **`/handoff`** (`skills/handoff/`) — the whole session-continuity loop in ONE skill and ONE file
  per work stream, `<project>/HANDOFF_<topic>.md`. Resuming = read it (+ its entry_docs), run the
  suite to confirm green, summarize with zero prior context, continue from the first `pending`
  task. Executing = update it after EVERY task and by the 60% mark of the session. The doc holds
  prose state (goal, verified-vs-assumed, open bugs, next 3 tasks, opening prompt) around a
  machine-readable ```yaml tasks block (id, verification_command, verification_kind, status,
  pasted evidence). Owner's call 2026-07-30: write and resume are two halves of one loop, so a
  separate /resume skill with its own PLAN.yaml was merged in — never split this state across two
  files, they drift and disagree. Evidence lives in the doc rather than in commits, because the
  owner drives git through GitHub Desktop ([[no-git-staging]]).
- **`/fx-verify`** (`skills/fx-verify/`) — the visual gate: render the snapshot scene WINDOWED,
  read the PNG, describe what it shows. See [[verify-visuals-by-eye]].
- **`/flowchart-design`** (`skills/flowchart-design/`) — added 2026-08-01 at the owner's request:
  braindump → research the real call chain → numbered mermaid flowcharts (every node has an ID,
  NEW nodes marked, existing nodes named with their real function) → usage-enumeration table →
  100+ numbered questions each carrying a recommended default so *default* is a complete answer.
  DESIGN ONLY — no code, no file lists, no test plan; the implementation plan is a separate doc
  written after every node is approved. Ask about behaviour/appearance, never about code: the
  agent fills in the architecture. Skill self-improves — fix it in-session when a review turns up
  a question category it should have caught. First use: `solatro/SPOTLIGHT_DESIGN.md`.
- **`plan-auditor`** subagent (`agents/plan-auditor.md`) — read-only; audits a plan/handoff/design
  doc against live code and reports STALE / MOVED / UNVERIFIABLE / SOUND with file:line. Good for
  the read-heavy phases that otherwise eat the main context.
- **Hook** (`settings.json` → `hooks/block-process-kill.ps1`) — PreToolUse on Bash/PowerShell,
  blocks kills by image name, wildcard, or `Get-Process` pipeline; an explicit verified
  `-Id <pid>` still passes. Exists because a broad filter twice closed the owner's editor with
  unsaved changes. Verified working when installed.

Deliberately NOT installed: a PostToolUse hook running the test suite after every Edit — the
Solatro suite is ~60 s and must run WINDOWED, so per-edit runs would be disruptive and would
fight the owner's editor. Run the suite at task boundaries instead ([[running-godot-scenes]]).

# CLAUDE.md — repo entry point

**Read this first. It is loaded automatically in every session in this directory, on every
machine.** Everything an agent needs to work here is inside this git repository — nothing depends
on machine-local state.

## Portable by design

The owner works across more than one computer. **The git directory is the only shared state.**

| What | Where | Portable |
|---|---|---|
| Skills (`/handoff`, `/fx-verify`, `/flowchart-design`) | `.claude/skills/` | ✅ tracked |
| Subagent (`plan-auditor`) | `.claude/agents/` | ✅ tracked |
| Hooks + settings | `.claude/hooks/`, `.claude/settings.json` | ✅ tracked |
| Dev-server launch configs | `.claude/launch.json` | ✅ tracked |
| **Project memory** | **`.claude/memory/`** | ✅ tracked — **this is the source of truth** |
| Handoff / resume state | `<project>/HANDOFF_*.md` | ✅ tracked |
| Design + execution plans | `<project>/design/<slug>/` | ✅ tracked |
| `settings.local.json` | machine-local | ❌ deliberately not tracked |

**⚠ MEMORY RULE.** Claude Code's per-user memory directory is **a cache, not the record**. A second
computer has none of it. Therefore:

- **Read `.claude/memory/MEMORY.md`** at the start of substantive work — it is the index, one line
  per memory.
- **Write new or updated memories into `.claude/memory/`**, not into the machine-local directory.
  Same format (frontmatter with `name` / `description` / `metadata.type`), same one-line index entry
  in `.claude/memory/MEMORY.md`.
- If a machine-local memory disagrees with the repo copy, **the repo copy wins** — the local one is
  from another machine or another day.

Anything a future session needs and cannot re-derive from the code belongs in `.claude/memory/`.
Machine-specific facts (absolute paths, installed binary locations) belong in the memory file that
already covers that topic, labelled as machine-specific, never assumed.

## Hard rules (they override defaults)

1. **No `git add`, no commits, no staging.** The owner commits through GitHub Desktop. Just edit
   files. Ask before committing anything, ever.
2. **Never kill a process by image name or wildcard.** A hook blocks it
   (`.claude/hooks/block-process-kill.ps1`) because a blanket filter twice closed the owner's editor
   with unsaved work. An explicit verified `-Id <pid>` passes.
3. **PowerShell mangles UTF-8** — never `Get-Content | Set-Content` a source file; use the Edit tool.
4. **Verify visuals by eye.** Green tests and metrics are not evidence about pixels. Render, look at
   the image, describe what it actually shows — or say UNVERIFIED.
5. **No mocks in tools.** A harness hosts the real scene and the real data; a stand-in cannot
   disagree with what it models.

## The projects

| Directory | What | Read first |
|---|---|---|
| `solatro/` | Godot 4.7 card game — the main project | `solatro/START_HERE.md`, then `VFX.md` for effects work |
| `palette/` | Node/npm procedural palette generator (zero dependencies) | `palette/ARCHITECTURE.md` |
| `worldgen/` | Godot map generation addon, vendored into solatro | `worldgen/START_HERE.md` |
| `designloop/` | Node tool: the branching-questionnaire design front end — built and working | `designloop/README.md` |
| others | smaller game-jam and study projects | — |

## The design workflow

Feature design in this repo runs through **`/flowchart-design`** (`.claude/skills/flowchart-design/`):
braindump → research → numbered mermaid flowcharts + a branching question DAG → the owner answers →
flowcharts reviewed and **confirmed** → implementation plan + a copy-paste handoff prompt.

The owner answers in **`designloop/`** — `npm --prefix designloop start`, then hand over
`http://localhost:5273/web/question.html?key=<project>/<slug>`. It parses the markdown you wrote;
there is never a second authored copy. **It is optional**: with the server down, the document is
still answerable by ID in chat exactly as before.

Two rules from that skill that reach beyond it:

- **Design docs carry no code; implementation plans carry everything** — schemas, formal grammars,
  module APIs, per-step done-when, hard self-checking acceptance gates. A plan that names a file
  without specifying it guarantees two incompatible inventions of the same thing.
- **The gap protocol.** An agent executing a plan that meets a decision the design does not cover
  does not invent it: reversible and clearly within intent → do it and log one line in that design's
  `ASSUMPTIONS.md`; otherwise → park that thread only, file `gaps/GAP-NNN.md` in the questionnaire
  grammar, keep working everything else, and tell the owner. The full protocol travels in a block at
  the head of every plan.

## Resuming work

Look for `<project>/HANDOFF_*.md` — that is the live state of any multi-session work stream, written
to stand alone with zero prior context. `/handoff` is the skill that reads and maintains it.

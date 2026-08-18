# CLAUDE.md — repo entry point

**Loaded automatically in every session in this directory, on every machine.** Everything an agent
needs is inside this git repository; nothing depends on machine-local state. The owner works across
more than one computer — **the git directory is the only shared state.** Absolute paths and hardware
quirks live in exactly one file: `.claude/memory/machine-profiles.md`.

## ⚠ Memory rule

Claude Code's per-user memory directory is **a cache, not the record** — a second computer has none
of it.

- **Read `.claude/memory/MEMORY.md`** at the start of substantive work. It is the index: one line
  per memory, a hook only.
- **Write new and updated memories into `.claude/memory/`**, never the machine-local directory.
  Same frontmatter (`name` / `description` / `metadata.type`), plus a one-line index entry.
- If a machine-local memory disagrees with the repo copy, **the repo copy wins.**

**Memory holds only what applies ACROSS projects** — working agreements, Godot practice, the
machine profiles, and `architecture-map.md` (what each project is and where they collide).
Anything specific to one project — its contracts, conventions, design decisions, status,
backlog — belongs in **that project's own docs**, and memory just points at them. Start from
`architecture-map.md` to know what a change can break, then read the doc it names.

## Doc hygiene

Docs describe the system as it is now, for someone about to change it.

- **No history.** No dated session logs, no "landed on <date>", no changelog of what was fixed
  when, no lists of retired files. Git has that.
- **No dead references.** If a doc names a file, section or tool, it must exist.
- Keep: contracts, gotchas, non-default conventions, owner rulings, levers and their defaults,
  measured dead ends, and what is still open.
- **Say it in as few words as carry the rule.** This applies to code comments too. Keep the rule and
  the measured number; drop the story of how it was found, who reported it, and what it used to do.
  State a fact once, at the site that enforces it, and point at that name from anywhere else.
- A date earns its place only when the fact is *about* a moment (a measurement's conditions, a
  version boundary). "The suite runs windowed" needs no date; "measured on Box A" does.
- Plan and handoff docs are temporary: once landed, fold the residue into the living doc and
  delete them.

`py .claude/tools/doc_check.py` enforces the mechanical half — dangling `[[memory links]]`, an
index out of sync with disk, references to files that do not exist, hard-coded absolute paths,
and dated lines. It covers **code comments as well as `.md` files**: a comment is a doc that lives
in a source file, and a comment deferring to a doc is only useful if the doc resolves. Run it after
any docs change. The judgement half is the `/docs` skill.

A **`Stop` hook runs `--changed --warn-only` at every task boundary** — only the files you touched,
only the findings that are always bugs, and it never blocks. ⚠ **A silent hook is not a clean
repo:** it says nothing about the standing style backlog (hundreds of dated and over-long comments,
`solatro/todo.md`). Run the full check by hand for that.

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
   disagree with what it models. ⚠ One sanctioned exception: `Tools/wall_editor.tscn` carries a
   `use_placeholder_content` toggle, **default off**, so the default path still hosts real
   scenes — `solatro/design/picture-wall/gaps/GAP-017.md` records why.

## Where to start

| Project | Read first |
|---|---|
| `solatro/` | `START_HERE.md`, then `VFX.md` for effects work — the main project |
| `palette/` | `ARCHITECTURE.md` |
| `worldgen/` | `START_HERE.md` — vendored into solatro |
| `designloop/` | `README.md` |

Everything else is a smaller game-jam or study project.

## Workflows (skills — invoke, don't reimplement)

- **`/flowchart-design`** — feature design: braindump → flowcharts + question DAG → confirm → plan
  and handoff prompt. It also carries the two rules that reach beyond it: design docs carry no code
  while implementation plans carry everything, and the **gap protocol** for decisions a design does
  not cover.
- **`/handoff`** — session continuity. `<project>/HANDOFF_*.md` is the live state of any
  multi-session work stream; start there when resuming.
- **`/fx-verify`** — the verification gate for any visual, shader or prop-art change.
- **`/docs`** — audit and consolidate the docs and memory. Run it when a work stream lands, when
  the docs feel scattered, and **before writing any new memory file**. Its mechanical half is
  `py .claude/tools/doc_check.py`, which proves every reference still resolves.
- **`plan-auditor`** subagent — audits a plan or doc against the live code before you execute it.

Deliberately NOT installed: a PostToolUse hook that runs the test suite after every Edit. The
Solatro suite takes ~60 s and must run WINDOWED, so per-edit runs would fight the owner's editor.
Run the suite at task boundaries instead.

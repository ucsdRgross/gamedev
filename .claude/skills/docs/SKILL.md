---
name: docs
description: Audit and consolidate this repo's documentation and memory — find guidance that drifted into the wrong place, strip history and dead references from living docs, and prove every claim still resolves. Use when asked to update, clean up, consolidate or audit the docs or memory, when a work stream lands and its plan doc needs folding away, and before writing any new memory file.
---

# Docs — keep the primary sources clean

The docs are the primary source of information in this repo. Memory is a thin index over them,
not a second copy. This skill keeps that true.

**Run `py .claude/tools/doc_check.py` first, always.** It is the mechanical half; everything
below is the judgement half. Never do the judgement work without the check output in hand —
that is how the last cleanup found a doc listing a class that had been deleted.

## The two rules this enforces

**1. Scope — where does this belong?**

| It is… | It goes in |
|---|---|
| A working agreement, a Godot-practice note, an engine gotcha that applies across projects | `.claude/memory/<name>.md` |
| A repo-root path, a binary location, a GPU quirk | `.claude/memory/machine-profiles.md` — the ONLY place absolute paths live |
| What each project is and where two projects collide | `.claude/memory/architecture-map.md` |
| **Anything specific to one project** — its contracts, conventions, design decisions, status, backlog | **that project's own docs** |

A memory naming exactly one project is a scope violation unless it is `architecture-map` or
`machine-profiles`. `doc_check.py` flags these; each one is a question, not an automatic delete.

**2. Hygiene — a living doc describes the system as it is now, for someone about to change it.**

Cut: dated session logs, "landed on <date>", changelogs of what was fixed when, lists of retired
files, superseded-rule trails ("CHANGED <date>… CORRECTED <date>… the rule at the top overrides
this"), and narration of how a bug was found.

Keep: contracts, gotchas, non-default conventions, owner rulings, levers and their defaults,
measured numbers, dead ends already tried, and what is still open.

A date earns its place only when the fact is *about* a moment — a measurement's conditions, a
version boundary. "The suite runs windowed" needs no date. "Measured on Box A" does.

## Procedure

### 1. Check

```bash
py .claude/tools/doc_check.py            # audit, exits 1 if anything is broken
py .claude/tools/doc_check.py --verbose  # also lists every date-stamped line
```

Broken references and dangling links are always bugs — fix them. Scope violations and date
density are prompts to look, not verdicts.

### 2. Before deleting ANY memory, prove the content survives

This is the step that makes deletion safe, and skipping it is how real design records get lost.

For each memory under review, pick its 3–5 distinctive terms — a function name, a constant, a
ruling — and grep the destination doc for them:

```bash
grep -rniE 'ResourceSaver|pending_action|has_save' solatro/ARCHITECTURE_REVIEW.md
```

- **Covered** (the doc says the same thing, or better) → delete the memory.
- **Not covered** → the memory *is* the only record. **Move it into the project's doc first**,
  then delete. Never delete on the assumption a big doc "probably" covers it.
- **Covered but the doc is thinner** → fold the missing detail into the doc, then delete.

### 3. Fold landed plan docs

Once a work stream is landed and verified: fold its regression-critical residue into the living
doc (rules, landmines, contracts — not the story of how it was built), move open items to the
project's `todo.md`, then delete the plan doc. **Run `git ls-files <path>` first** — the policy
assumes the file is tracked, and an untracked file deleted this way is gone for good.

Plan artifacts under `design/<slug>/` are cited by question ID (`Q85`) from plan steps and
sometimes from code comments. Do not delete one while any citation to it is live — check first.

### 4. Clean the living docs

Work one file at a time so each is reviewable in `git diff`. For each: strip per rule 2, verify
every file, section and tool it names still exists, and replace absolute paths with a pointer to
`machine-profiles.md`.

### 5. Re-check and report

Re-run `doc_check.py`, then report per file: before/after size, what categories came out, and
anything you moved rather than deleted.

## Writing a NEW memory

Before creating one, ask in order:

1. Is this specific to one project? → it belongs in that project's docs. Stop.
2. Is it a path or hardware fact? → `machine-profiles.md`. Stop.
3. Does an existing memory already cover the topic? → update that file, do not add another.
4. Otherwise: create it, add a **one-line hook** to `MEMORY.md` — no status, dates, counts or
   gap IDs — and link related memories with `[[name]]`.

## Never

- Never write a gamedev memory into the machine-local per-user memory directory. It is a cache;
  a second computer does not have it. The repo copy wins in any disagreement.
- Never copy a project's status into a memory. Status lives in `HANDOFF_*.md` / `todo.md`, which
  are already the thing that gets updated.
- Never leave a reference to a file, section or tool that does not exist.

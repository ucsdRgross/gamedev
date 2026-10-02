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
dated lines, and **design-process ids that have escaped into the code** (`Q183=a`, `GAP-017=c`,
`PLAN.md §1.8` — see [[design-ids-stay-out-of-code]]). It covers **code comments as well as `.md` files**: a comment is a doc that lives
in a source file, and a comment deferring to a doc is only useful if the doc resolves. Run it after
any docs change. The judgement half is the `/docs` skill.

A **`Stop` hook runs `--changed --warn-only` at every task boundary** — only the files you touched,
only the findings that are always bugs, and it never blocks. ⚠ **A silent hook is not a clean
repo:** it says nothing about the standing style backlog (`solatro/todo.md`). Run the full check by
hand for that.

## Code hygiene

More mechanical checks, same shape as `doc_check.py`; the first two share its `Stop` hook:

- **`py .claude/tools/dup_check.py`** — the same logic in two homes. A green suite never fails on a
  duplicate and `doc_check` stays silent because every NAME in it resolves, so nothing else here
  sees it. Pairs are reported only WITHIN a top-level project: this is a monorepo of separate
  games, and a shader one jam copied from another has no next edit that touches both.
- **`py .claude/tools/diff_shape.py`** — a change that only ADDS lines to an existing file, which is
  what bolting a new path alongside the old one looks like. `--history N` re-derives the baseline.
- **`py .claude/tools/sweep_check.py <file>`** — proves a comment sweep changed no code: the
  comment-stripped code of HEAD and of the working copy must be byte-identical. A trailing
  comment's removal edits its code line, which a diff cannot tell from a code change; this can.

**`.claude/hooks/commit-gate.ps1` blocks an agent commit whose staged diff creates a
duplicate pair** (a pair already on HEAD does not block), with `[dup-ok]` in the commit message
(`-m` or `-F`) as the deliberate-duplication escape. It fires only
on commits an agent makes, never on the owner's GitHub Desktop flow.

⚠ **Duplication blocks; add-only shape only warns.** The gate's header carries the measured reason;
re-derive before changing either threshold. The standing backlog: run `dup_check.py` bare.

## Hard rules (they override defaults)

1. **Never commit to `main`.** On `main` the owner commits through GitHub Desktop — just edit files,
   and ask first. **On any other branch, committing is fine and needs no permission**: one verified
   step per commit, evidence in the message.
2. **AT MOST TWO SUBAGENTS AT A TIME, AND ONLY ONE OF THEM RUNS GODOT.** A hook enforces the
   count (`.claude/hooks/one-subagent-at-a-time.ps1`, released on `SubagentStop` and on
   `PostToolUse` for a foreground `Agent` call); the overseer enforces the Godot half. The suite
   is a one-process rule: two runs race for the same `user://settings.tres`, the same `godot.log`
   and the same window — every worktree shares them — and a failure stops being attributable to
   either. The second slot is for an agent that runs no Godot (a reviewer, an auditor, docs work).
   A lock older than 90 minutes is ignored, so a killed session cannot wedge the repo shut.
3. **Never kill a process by image name or wildcard.** A hook blocks it
   (`.claude/hooks/block-process-kill.ps1`): the owner's editor matches the same filter. An
   explicit verified `-Id <pid>` passes.
4. **PowerShell mangles UTF-8** — never `Get-Content | Set-Content` a source file; use the Edit
   tool, or a python heredoc writing `encoding='utf-8'`. A hook blocks it
   (`.claude/hooks/block-source-rewrite.ps1`): `Set-Content`/`Out-File`/`Add-Content` aimed at a
   source extension is refused. `Copy-Item`/`Move-Item` are byte copies and pass — that is how you
   park and restore a file around a deliberate red-then-green run.
5. **Verify visuals by eye.** Green tests and metrics are not evidence about pixels. Render, look at
   the image, describe what it actually shows — or say UNVERIFIED.
6. **Online research is allowed, and is expected when a blocker might be a MISUNDERSTANDING rather
   than a design gap.** Engine semantics, an API's actual contract, a container's sizing rules, a
   platform quirk — look them up rather than inferring from behaviour. ⚠ **Say which it was:** cite
   the source, and keep "the docs say X" separate from "I measured X here". A gap is for a decision
   the design does not cover; if the real problem is that nobody knew how the engine behaves, that
   is research, not a gap, and filing one wastes an owner ruling. Measurement still outranks
   documentation when the two disagree — the engine in front of you is the authority.
7. **No speculative defense.** No guard clause, `try`/`except`, null check or fallback branch
   unless you can NAME the caller that produces that case, or you observed the failure. A
   precondition gets `assert` — it compiles out in release, and a crash at the real cause beats a
   fallback that hides it. ⚠ This is the repo's most likely source of bloat.
8. **No unrequested generality.** No parameter, flag, `@export` or extension point without a caller
   TODAY. A new function needs two call sites or a test that needs the seam; otherwise inline it.
   The `bloat-reviewer` subagent checks exactly rules 7 and 8 against one diff.
9. **No mocks in tools.** A harness hosts the real scene and the real data; a stand-in cannot
   disagree with what it models. ⚠ One sanctioned exception: `Tools/wall_editor.tscn` carries a
   `use_placeholder_content` toggle, **default off**, so the default path still hosts real
   scenes — `solatro/design/picture-wall/gaps/GAP-017.md` records why.

## Working rules

- **The player's save and settings are not yours.** Every probe, harness and suite run gets a
  private `APPDATA`, so `user://` is isolated — `.claude/hooks/godot-needs-private-appdata.ps1`
  blocks a launch without one. Back up before any touch you cannot avoid. The editor: hard rule 3.
- **Track every PID you start.** Before reporting done, no Godot console process you started is
  left (kill your own, by `-Id`). A suite with no banner inside its timeout is a hang — look for a parse error first.
- **Solatro's full gate is one call:** `py .claude/tools/gate.py --out <scratchpad> --handoff
  <project>/HANDOFF_*.md` — private APPDATA, refused while any Godot runs, a short verdict (its
  docstring says what it checks).
- **A claim about state is measured or it says "probably".** Before every claim, not only when in
  doubt: did you touch the thing itself — the file, the run, this command's output? A log line, an
  earlier note or another agent's report is inferred. A check passed only if it ran as its own
  command and you read its exit code — never through a pipe, which reports the last command's.
  Send long output to a file and search the file.
- **Plans and design records.** Fold new work and rulings into the EXISTING plan steps and tests
  unless told otherwise. Record the owner's ACTUAL answer verbatim, never your recommendation
  ([[charts-from-resolved-answers]]). Answer a question from `PLAN.md`, the handoff and the design
  docs before asking the owner. A handoff is stateless and portable: no absolute paths, the exact
  next step and its verification commands. Never delete a plan that has not landed (a landed one is
  folded and deleted, as above). A magic value is not a design answer — derive it.
- **Any fix.** State the diagnosis in one sentence and confirm the cause with evidence (a repro, a
  log, a measured value) before editing. Skip it only when the cause is the line you are reading.
- **Visual bugs.** Reproduce and measure first; list at least two hypotheses, each with the
  measurement that confirms or refutes it; fix only the confirmed one. Verify on a real render of
  real art (hard rule 5, `/fx-verify`). In-game behaviour is never "untestable" — build a harness.
  Engine capability: the engine docs before a repo grep (hard rule 6).
- **Execution.** Never stop early citing context — compaction exists. One blocked scenario: finish
  the rest and report the blocker. Commit only the current step's files, staged by path. Never
  batch an edit with the run that tests it. Subagent presets: model aliases and explicit effort in
  frontmatter ([[implementer-routing]]).
- **Reflect at every gate, unprompted.** Every session end, plan finish and `/plan-run` close runs
  `/handoff`'s "Reflect and record": what cost time, whether it will recur, the rule written where
  it is read next time, and the last message says what was recorded. Do not wait to be asked.

## Where to start

| Project | Read first |
|---|---|
| `solatro/` | `START_HERE.md`, then `VFX.md` for effects work — the main project |
| `palette/` | `ARCHITECTURE.md` |
| `worldgen/` | `START_HERE.md` — vendored into solatro |
| `designloop/` | `README.md` |

Everything else is a smaller game-jam or study project.

## Workflows (skills — invoke, don't reimplement)

- **`/flowchart-design`** — before any feature large enough that a vague plan would leak decisions
  into implementation. Also the home of two rules that reach beyond it: design docs carry no code
  while implementation plans carry everything, and the **gap protocol** for decisions a design does
  not cover.
- **`/plan-run`** — AFTER `/flowchart-design` has produced the documents.
- **`/handoff`** — when resuming or checkpointing. `<project>/HANDOFF_*.md` is the live state of
  any multi-session work stream; start there.
- **`/fx-verify`** — before claiming any visual, shader or prop-art change works.
- **The owner's visual review** — before/after pairs the owner approves, rejects or comments on,
  served by Design Loop (`#visual` tab); `solatro/visual-review/README.md`. `/fx-verify` and
  `/plan-run` say when to shoot it and how a reject becomes the next step.
- **`/merge-branches`** — before anything goes to `main`, a single branch included.
- **`/docs`** — when a work stream lands, when the docs feel scattered, and **before writing any
  new memory file**.
- **Subagents** — `pair-reviewer` before design work reaches the owner (`/flowchart-design` § Pair
  review); `plan-auditor` before executing a plan; `bloat-reviewer` on ONE diff, dispatched by hand
  per `/plan-run` § "Spending the reviewer".

**Do not install** a per-edit test-suite hook, a pre-commit AI review, a weaker model as reviewer,
a parallel implementer swarm in worktrees, or a headless `claude -p` plan loop. Reasons:
`.claude/NOT_INSTALLED.md`.

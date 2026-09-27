---
name: handoff
description: The session-continuity loop for this repo — read a handoff doc to resume work with zero prior context, and keep it updated as durable state while executing. Use when picking work back up, when asked for a handoff or checkpoint, when turning a plan into a resumable run, or partway through long multi-phase work before the session runs out.
---

# Handoff

One file per work stream: `<project>/HANDOFF_<topic>.md` (e.g. `solatro/HANDOFF_spotlight.md`). It is
both the resume point and the live journal — **never split state across two files**, and never
create a parallel copy of an existing handoff. Update it in place.

## Resuming (the file exists)

1. Read it, plus the `entry_docs` it names. Do not rely on conversation history — the file is the
   source of truth.
2. Confirm the tree is actually green before trusting any `done` status: the full suite,
   **windowed, no `--headless`** — on solatro, the gate (`CLAUDE.md` Working rules).
   `running-godot-scenes.md` in `.claude/memory/` carries the launch rules. Check the owner's Godot
   editor is closed first.
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
**IMPLEMENTED-BY:** the model(s) that did the work, THE EFFORT each ran at, and which parts each did.

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

## ⚠ IMPLEMENTED-BY is not bookkeeping

`/plan-run`'s reviewer floor picks the reviewer's tier AGAINST THE AUTHOR'S, so a stream that does
not record which model wrote it leaves the next session guessing — and guessing low is the harmful
direction, the one measured at 13 regressions against 3 fixes. Name each model and what it wrote;
"a mix" with no detail forces the reviewer to the highest tier present, which is the safe reading
but an expensive one.

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
   input that separates them** — the case its worked example does not cover. Two sentences is
   enough (`seam-checks-not-rereading.md`, "A rule stated with an EXAMPLE").
3. **If the design has a plan beside it, run its checks before starting** — for a `/flowchart-design`
   stream that is `npm --prefix designloop run check -- <project>/<slug>`, and **read `unclaimed`**:
   answered questions no plan step implements (`design-answers-need-a-claimant.md`).
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

## Reflect and record — at every session end, unprompted

Owner, verbatim: "make sure to do these type of cleanup and reflections steps every time for
self-learning at planned gates such as at end of sessions or when finishing a plan, not just when i
ask you to reflect. Having issues repeat is a waste of time." It runs before the session's last message, at
every `/plan-run` close (item 10, over the whole run), and when a plan finishes.

1. **List what cost time this session**, from the transcript, not memory: a brief whose premise
   measurement overturned; an owner question a ruling already answered (or one asked so the owner
   rejected the options); a rerun, a leak, a hang, a turn-cap stop; a review shot that misled the
   owner; tool or hook friction; a schedule change the owner learned about by asking; **repeated
   scaffolding** - a command, a grep chain or a snippet typed three or more times, or boilerplate
   pasted into every brief.
2. **For each, ask "will this happen again?"** If yes, write the rule WHERE IT IS READ AT THAT
   MOMENT — a rule in a document nobody reads then is indistinguishable from no rule (the reuse rule
   lived in memory and `/simplify`, never in the brief template, and code came back duplicated):
   an implementer trap → `.claude/agents/plan-implementer*.md`; a test trap →
   `tests-that-prove-nothing`; a brief trap → `brief-premise-is-a-hypothesis` or `/plan-run`'s
   brief section; a project fact → that project's doc; a cross-project agreement → a memory
   (`.claude/memory/`, run `/docs` first); repeated scaffolding → a script in `.claude/tools/`
   (the `gate.py` shape: it runs the work and prints a short verdict), or a line in the brief
   template or the agent definition - proposed here and built as its own small reviewed step,
   never improvised mid-run. A one-off goes nowhere.
3. **Audit the rules themselves - adding is only half the loop.** Owner, verbatim: "add ways to
   figure out if something in workflow has become harmful so that it can be updated, fixed, or cut.
   we dont want workflow to become too strict and unflexible." For each rule, hook or tool that
   fired WITH AN EFFECT this session (blocked, flagged, cost a workaround, or caught) - silent
   passes are only a count - one line: **caught** (a real defect it stopped), **false alarm** (it
   blocked or flagged legitimate work), **cost** (time, tokens, a workaround someone had to
   invent), or **ceremony** (satisfied on paper while the defect it targets got through anyway).
   Then propose
   to the owner, never apply silently:
   - **fix** a guard with a false alarm - narrow its matcher; never pile on exceptions;
   - **cut or narrow** a rule with no catch across ~five sessions and a real cost - unless it
     guards a rare disaster (lost unsaved work, a leaked save), where low hits are the point;
   - **re-measure** a rule whose cited number no longer holds (a timing, a rate, a count);
   - **merge** two rules that say nearly the same thing, and fix copies that have drifted;
   - **loosen** a rule people keep routing around - the workaround is the evidence.
   Count the REVIEWERS the same way: each latent finding later reproduced (caught) or refuted (false
   alarm), so the value of chasing "traced, not measured" findings becomes a number; and re-measure
   any routing figure in `implementer-routing` whose sample is still a handful of steps.
   Record the tally in the handoff's Open bugs as a TOOLING line so the next audit can add to it.
   **If this session edited the workflow** (skills, agent definitions, memory, `CLAUDE.md`, hooks),
   one Fable pass over that whole diff, batched here rather than per edit: contradictions with the
   rest of the workflow, duplicates, a rule that inverts another. A wrong rule costs every later
   session - one `/docs` pass found an inverted reviewer rule and three docs contradicting hard
   rule 1, all left by earlier edits nobody re-read.
4. **Prune this file** (the ~300-line rule below): a finished row shrinks to id, description,
   status and its commits - the commit message holds the evidence; an open item it carried moves
   to Open bugs; a resolved Open bug goes.
5. **Say in the session's last message what was recorded and where**, one line each, and what was
   judged a one-off.

## Rules

- **Repo-relative paths only** — no machine-local absolute paths, no references to memory files.
  The next agent may be on a different machine.
- **A parked branch is local until pushed.** Work parked on a side branch (the temp-index commit
  shape) does not exist on the owner's other machine: name it in the handoff as LOCAL ONLY and ask
  the owner to push it (never push unasked) - or park it as an UNFINISHED commit on the work branch
  when it does not break the gate.
- **Commits follow CLAUDE.md hard rule 1:** never on `main` (the owner commits through GitHub
  Desktop); on any other branch, one verified task per commit, its id and evidence in the message.
- **No dated history logs in living docs** (owner policy). When the stream lands, fold the residue
  into `ARCHITECTURE_REVIEW.md` / `todo.md` and delete the handoff — but run `git ls-files <path>`
  first, since deleting an untracked file destroys it.
- ⚠ **KEEP IT UNDER ~300 LINES, AND PRUNE WHEN IT DRIFTS OVER.** Measured: the spotlight
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

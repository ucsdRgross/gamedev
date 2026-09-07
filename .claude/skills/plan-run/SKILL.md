---
name: plan-run
description: Execute an already-written implementation plan using an overseer session plus implementer subagents — the step that follows /flowchart-design. Sets up the worktree and reversed commit policy, shapes each step brief so components cannot ship unwired, and carries the verification hierarchy plus the ways a test passes while proving nothing. Use when DESIGN/PLAN/TEST_PLAN/NAMES exist and the work is execution, or when asked to run a plan with subagents.
---

# Running a plan with an overseer and implementer subagents

`/flowchart-design` produces `DESIGN.md`, `PLAN.md`, `TEST_PLAN.md` and `NAMES.md`. This skill
executes them. The split: **one session holds the plan and never reads code; subagents hold the code
and never hold the plan.** That keeps the overseer's context plan-shaped across dozens of commits,
which is what lets a long run survive.

⚠ **The pattern's known blind spot, and the reason half this document exists:** the overseer
verifies what it can *observe*, and the implementer optimises to the *done-when it is handed*.
Neither owns "does this actually do anything in the running game." See [[built-but-not-wired]] for
what that shipped. Everything below aims at that failure.

## Setup

- A **git worktree on its own branch**, never the main working tree. The owner merges when done.
- **The repo's no-commit rule is REVERSED for the overseer on that branch**: commit after every step
  you verified yourself, one step per commit. Commits are the only rollback points, and a long run
  will lose sessions to API limits — assume it.
- The implementer still never commits, never stages, never stashes.
- Use `/handoff` for `<project>/HANDOFF_<topic>.md`. Record the EVIDENCE that proved each done-when
  (the grep output, the banner line), not prose. A cold overseer must be able to resume from it.
- ⚠ **RECORD THE IMPLEMENTING MODEL IN THE HANDOFF, on the first line, as
  `IMPLEMENTED-BY: <model>`.** Update it if the run changes models partway; list every model that
  wrote code. The close reads this line and nothing else to pick a reviewer, so a run that does not
  write it cannot be reviewed correctly.

## The overseer's rules

**Never** read, edit or write source files; never print file contents; never `git diff` without
`--stat`. **May** read the plan documents, the handoff, cited design sections, gap files and agent
reports; may run `grep -c`/`-l`, `git status --porcelain`, `ls`, and the suite.

**Verify every done-when yourself with a bounded command.** Never accept a self-reported green.

## Writing a step brief

The implementer's definition already carries the report schema and repo rules, so a brief is short —
but it MUST carry:

1. The step id and its **exact done-when, quoted** from the plan.
2. The **test-plan row ids** that step owes. A dropped planned row is a gap, not a judgement call.
3. ⚠ **The CALL SITE.** "Where is this called from, and what breaks if it is deleted?" A step whose
   done-when is only "TestX is green" will ship a component nothing calls. Require a test that fails
   when the wiring is removed.
4. Any trap below that applies, named specifically.
5. ⚠ **The comment rule, stated.** A comment sits at column 0, above the method, at most 3 lines,
   and says WHY the method exists. No comment may have whitespace before it and none may trail
   code. An implementer that is not told this ships indented prose every time.
6. ⚠ **The complexity rule, stated** — engine method before hand-rolled, existing helper before new
   one, each thing at its proper altitude. See the section below.

**Never accept `STATUS: done` on a component whose consumer does not exist.**

⚠ **5 and 6 are here because they were reaching nobody.** They lived in memory and in `/simplify`
while this template carried lines about tunable literals, design ids and registry names and not
these — so briefs never said them, and the code came back with both violated. Where a rule matters,
put it in the brief and gate it; restating it somewhere else is how it gets ignored.

⚠ **The brief hands the implementer design ids, and they come back out in the code unless you say
so** — including into `@export_group` labels Godot renders as Inspector headings. **The citation
belongs in the `STEP:` report and in `PLAN.md`; the code gets the rule.**
[[design-ids-stay-out-of-code]].

## The verification hierarchy — weakest to strongest

Each layer caught things the one above it missed.

1. **A green suite** — proves almost nothing. Eight tests in one run passed while asserting nothing.
2. **Greps and counts** — catch contract drift (field lists, registries, knob sets), never behaviour.
3. **Reading the diff** — catches structure and dead code, but not user journeys.
4. **Red-then-green proof** — caught a real defect *every single time*.
5. **An adversarial reviewer tracing what a player actually does** — highest yield of the whole run.

**Do 3 and 5 at every phase boundary.** Doing them only at the end means finding six critical defects
after the work is already "complete".

⚠ **AN `assert` IS A CHEAPER REACHABILITY ORACLE THAN ANY AMOUNT OF STATIC ANALYSIS, AND IT OUTRANKS
LAYER 5 ON THAT ONE QUESTION.** Asked whether a guard's case has a caller, two independent reviewers
at the floor each answered "no caller reaches it" with call-graph evidence. Replacing the guard with
an `assert` fired **12 times on the next run**, naming three fixtures that had been silently banking
score into a board that did not exist. If you want to know whether a branch is dead, assert it and
run the suite — do not reason about it.

⚠ **AND BE READY TO BACK THE ASSERT OUT.** It is a change with blast radius across every fixture, and
one of those three could not be fixed without altering the board a geometry test exists to measure.
The assert's value is the reachability answer and the bugs it exposes; landing it is optional. Keep
the finding at the guard, in a comment, and move on — leaving a suite red to keep an assert is the
wrong trade.

**Also run `py .claude/tools/doc_check.py --changed` at every phase boundary.** A design id leaked
into a comment or a string survives every other layer here — it never fails a test and never breaks
a journey — and it is the one thing an overseer can check without reading code.

## The reviewer's model floor

**A reviewer is never a weaker model than the author it reviews** — same generation or newer, same
effort or higher, no exceptions. This binds layer 5, the run's highest-yield check.

A weaker reviewer on stronger code is NET NEGATIVE, not merely useless: reviewing a strong draft, the
weaker model rewrote whole solutions instead of patching, scoring 13 regressions against 3 fixes and
dropping the pass rate 8.6 points (arXiv 2607.21656). In the same experiment a stronger reviewer on
the weaker author's code gained 18.1 points. **Capability is the lever; a different model is not.**
Cross-vendor review buys decorrelated blind spots and is worth having *at or above* the floor —
never below it.

`plan-implementer` runs `sonnet` at `effort: low`, so its reviewer starts at `sonnet` normal effort.
`plan-auditor` runs `opus` and clears the floor. Raising an implementer's tier raises the floor with
it.

⚠ **THE FLOOR IS A RULE THE OVERSEER FOLLOWS, NOT ONE IT CAN CHECK.** `effort` is declared in agent
frontmatter or a model override and is not visible at dispatch time, so nothing validates it. If it
needs enforcing rather than instructing, that is a `PreToolUse` hook on `Agent`.

⚠ **`model:` SELECTS A FAMILY, NOT A VERSION** — `opus`, `sonnet`, `haiku`, `fable`. It cannot pin a
point release. When the distinction you need is between two versions of one family, the only
reliable mechanism is a SEPARATE SESSION with that model chosen at startup, which is why the close
hands over rather than dispatching.

⚠ **RECORD WHO WROTE IT, OR THE FLOOR CANNOT BE APPLIED.** The reviewer's tier is chosen against the
AUTHOR's, so a run that does not record `IMPLEMENTED-BY` leaves the next session guessing — and
guessing low is the harmful direction. `/handoff` carries the convention.

## Red-then-green is mandatory

For **every new test**, not only for bug fixes: neutralise the behaviour, watch the test fail,
restore it, watch it pass, report both observations.

⚠ **Check the red run failed the checks you EXPECTED.** A neutralisation that breaks the TEST rather
than the behaviour aborts the test function, and the banner then reads all-passed with those
assertions silently missing — the same shape as the defect you are hunting.

⚠ When a fix makes an existing test fail, **investigate before adjusting it** — one run found a
tolerance that had been calibrated to the bug, so it passed *because* the defect existed.

## The ways a test passes while proving nothing

**[[tests-that-prove-nothing]] carries the list.** Read it before writing a step brief and before
accepting one. The two that bite hardest in this pattern: a fixture that clears the ambient global
state the real product runs under (a pause flag, an autoload), and two competing mechanisms with the
SAME observable, where the test measures which writer ran second.

## Traps that are not about tests

- **Know exactly which log is the gate, and check its mtime.** One run read a stale 0-byte error log
  for its entire length. Engine logs are overwritten by whichever process wrote last — including the
  overseer's own runs.
- **A banner can report a failure that is not a check** ("0 behavior, 0 implementation") — that is an
  unexpected engine error. Read the newest engine log's backtrace.
- **One critical fix at a time**, full suite between each — [[one-fix-at-a-time]].
- **A tunable literal in a source file is a defect**, even when it looks like an epsilon. Sweep
  touched files for numeric and colour literals at the end of every step.
- **Diff your identifiers against the registry before reporting.** Invented names and signals stop
  the registry being authoritative.
- **Comments deferring to "a later step"** become lies when that step lands. Grep the deferral
  language when closing one.
- ⚠ **WHEN YOU CHANGE A RULE IN A SKILL, GREP THE AGENT DEFINITIONS THAT ENFORCE IT.** A run
  corrected the reviewer rule here and left `.claude/agents/adversarial-review.md` carrying the
  inverted one — *"if you are the implementing model, review nothing"*. Dispatched at the floor it
  would have refused and returned an empty report, and the close would have recorded a review that
  never happened. A skill and the agent that implements it are one change, not two.
- ⚠ **AGENT DEFINITIONS RESOLVE FROM THE SESSION'S PROJECT ROOT, NOT THE WORKTREE.** An agent that
  exists only on the branch cannot be dispatched by name from a session rooted in the main checkout.
  Inline its definition into a general-purpose agent and tell that agent to read the file.
- ⚠ **A TEST THAT ASSERTS A FIELD THE PRODUCT DOES NOT READ PASSES BECAUSE THE DEFECT EXISTS.** Not
  a tolerance calibrated to a bug — a whole check pointed at a retired accumulator that still moved.
  Ask of every green check: *is this the value the player is shown, or merely one that changes?*

## Gaps

Follow the plan's own gap protocol. As overseer: **a bug is not a gap.** A gap is a decision the
design does not cover. If exactly one choice is defensible, it is a defect — fix it and record it.
File a gap only when two defensible options differ in observable behaviour, when reversal is
expensive, or when it is an owner call.

**Quote a gap's own option text when asking the owner to decide.** Paraphrasing one caused an answer
to be given against a mislabelled list.

## Interruptions

Sessions die to API limits — plan for it. On resume: read the handoff, then `git log --oneline`,
`git status --porcelain`, and **a full suite run**, which is the only ground truth. If the suite is
green and the last claimed step's done-when still passes, continue; otherwise that step is suspect —
reset to the last commit and redo it. Never resume mid-step.

⚠ **Never reset the tree while a subagent is working in it.** One run did, and the agent correctly
reported the worktree as corrupted — it had no way to know the overseer had rolled it back. Tell it
first, and confirm it has stopped.

## Declaring the run ready to close

**The last step's commit is not the end of the run.** The moment every step in `PLAN.md` is verified,
say so explicitly and hand the owner the block below — do not start closing silently, and do not let
the run just stop.

Print exactly this, filled in:

```
READY FOR CLOSING — <project> / <branch>
  steps verified : <n> of <n>          suite: <the banner line>
  IMPLEMENTED-BY : <model that wrote the code, at <effort>>
  REVIEWER FLOOR : <same generation or newer, same effort or higher — never weaker>

Open a NEW session, select a model AT OR ABOVE that floor, and paste:

  Run the closing phase of /plan-run for the branch <branch> in <worktree path>.
  The code was implemented by <model> at <effort>. You are the reviewer, and you
  must be at or above that: same generation or newer, same effort or higher. A
  weaker reviewer on stronger code is net negative, not merely useless. Start by
  reading .claude/skills/plan-run/SKILL.md "The reviewer's model floor" and then
  "Closing the run", and work its numbered list in order.
```

⚠ **THE SAME MODEL IS FINE; A WEAKER ONE IS NOT.** The floor is about capability, not variety — a
same-model review at equal effort clears it. Reaching for a different vendor is a bonus worth having
*at or above* the floor and never a reason to drop below it.

⚠ **A NEW SESSION, NOT THIS ONE.** The overseer has held the plan for dozens of commits and has
every reason to believe the work is done — that is exactly the bias the close exists to defeat. It
is also the only way to choose the reviewer's model, since a session's model is chosen when it
starts and `model:` on a subagent selects only a family.

## Closing the run — a phase, not a gesture

⚠ **THIS IS A NUMBERED PHASE AND EVERY ITEM EITHER RAN OR DID NOT.** It replaces an earlier prose
close that said "run an adversarial review" and named no tool — a run could satisfy that by
claiming it had thought hard. Every other gate here is written to be un-talk-past-able; so is this
one. Record each result in the handoff the way a done-when is recorded: the output, not a claim.

⚠ **DISPATCH THE READING WORK TO SUBAGENTS, ONE AT A TIME.** The overseer never reads source, so
every item that reads code is a subagent. **A hook enforces one at a time** — they run the suite,
which is a one-process rule, and a parallel fan-out makes a failure unattributable. Dispatch, wait
for the report, dispatch the next.

Run in this order. Earlier items change the diff the later ones read.

1. **`py .claude/tools/doc_check.py`** — the FULL run, not `--changed`. Overseer runs this itself;
   it reads no source. Phase boundaries use `--changed`; the close needs the whole repo, because a
   doc this run invalidated may live in a file the run never touched.
2. **`adversarial-review` subagent** over `main...HEAD`. Reads the design, plan, test plan and names
   registry, then judges the entire branch. Its `PLAN DRIFT:` section is the half a code review
   cannot produce.
   ⚠ **GIVE IT A PRIORITY ORDER AND TELL IT TO REPORT EARLY.** A reviewer handed "review 275
   commits" spends its whole budget investigating and dies with nothing written down — measured:
   one died to a session limit mid-investigation and returned zero findings, and the rerun found a
   real defect inside its first third. Number the areas most likely to hurt a player, say "work in
   this order, keep a running list, and if you sense you are running long STOP INVESTIGATING AND
   REPORT WHAT YOU HAVE", and say that a partial report with three solid findings beats a thorough
   investigation that never lands.
3. **`/code-review`** on the branch diff, at high effort — correctness.
4. **`/simplify`** — the complexity section below is what it enforces.
   ⚠ **IT ASKS FOR FOUR PARALLEL AGENTS AND THIS REPO FORBIDS THAT.** `/simplify` is a built-in
   skill and cannot be edited here; its Phase 1 says to launch four review agents "in a single
   message so they run concurrently", which the one-subagent hook blocks. Run its four angles
   (reuse, simplification, efficiency, altitude) inline yourself, or serially. On a small diff
   inline is strictly better anyway — four cold agents re-deriving context to read ten lines is
   the expensive path.
5. **`/fx-verify`** — mandatory if ANY step touched a visual, a shader or prop art. Green tests are
   not evidence about pixels. Dispatch as a subagent; it renders and LOOKS.
6. **Fix everything 1–5 found** — one fix at a time, full suite between them ([[one-fix-at-a-time]])
   — then re-run whichever of 1–5 your fixes could have invalidated.
7. **`/docs`** — fold the run's residue into the living docs.
8. **`consolidate-memory`** — merge duplicates, fix facts the run made stale, prune the index.
9. **Feed the run's findings back into the skills and agents.** Every trap this run hit that a
   skill, an agent definition or a memory did not warn about is a gap in the tooling, not bad luck.
   Add it where it will be READ next time — the step-brief template, the agent's rules, the trap
   list — and delete anything the run proved wrong.
10. **Delete the temporary plan documents** the run produced.

⚠ **8 AND 9 ARE THE ANTI-DEBT STEPS, AND THEY ARE THE FIRST TO BE SKIPPED.** A run that lands its
code and skips these leaves every later session paying for it twice: re-reading memory that
duplicates itself, and re-discovering a trap that was already paid for once. Both shrink what the
next session must load — the cost of skipping them is measured in tokens on every run after this
one, which is exactly why nobody notices it happening.

⚠ **A finding is only fed back if it lands where the reader already looks.** Memory records the
shape of this failure: the reuse rule lived in memory and in `/simplify` while the step-brief
template did not carry it, so implementer briefs never said it and the code came back duplicated.
Adding a rule to a document nobody reads at that moment is indistinguishable from not adding it.

⚠ **A REVIEWER'S FINDING IS A CLAIM, NOT A VERDICT.** Reproduce it before you act: the reviewer is
told to hunt aggressively and is explicitly allowed to file "suspected". Fixing an unreproduced
finding is how a run acquires a defect it did not have.

⚠ **2 through 5 do not substitute for each other.** The reviewer hunts defects and plan drift,
`/code-review` reads the diff for correctness, `/simplify` reads it for duplication and altitude,
`/fx-verify` looks at rendered pixels. Skipping one because another was green is how a run ships a
component that passes its tests, contradicts its design, and renders wrong.

## Reduce complexity — a review axis, not a preference

Every step brief carries this, and `/simplify` and the close enforce it. Three rules, in the order
they are usually violated:

1. **Use the engine before writing your own.** Godot already has the tween, the timer, the easing
   curve, the rect intersection, the string helper, the sort. A hand-rolled version is more code,
   handles fewer edge cases, and drifts from engine behaviour the first time the engine changes.
   Search the class reference before adding a helper — [[read-the-engine-docs]].
2. **Reuse before you write.** Search for an existing helper in this project first. Measured cost of
   skipping it: a bucket-growing helper was added that duplicated an existing one, and the same
   constant ended up stated in two files — where the existing version was also the stricter of the
   two. **All stacking uses the same code** is the owner's standing example.
3. **Put each thing at its proper altitude.** A geometry question belongs in the geometry type, not
   in the view that asked it; a rule belongs at the seam that enforces it, not restated at every
   call site. If a method reaches through two objects to get what it needs, the thing it needs is at
   the wrong level.

⚠ **Wanting an inline comment is this section's loudest signal.** Code that needs prose to explain
itself needs a NAME instead — extract a well-named helper. The comment rule and this section are the
same rule wearing two hats.

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
- **Models:** the overseer runs Opus 5.5 at high effort with Fable 5.1 as its read-only reviewer;
  each step's implementer is picked by [[implementer-routing]]. Effort lives in agent frontmatter
  only - the dispatch cannot override it - and a session's model is fixed at startup, so check
  yours before the first dispatch.
- **The overseer COMMITS every step it verified itself, one step per commit** (hard rule 1).
  Commits are the only rollback points, and a long run will lose sessions to API limits — assume it.
  The implementer never commits, stages or stashes.
- Use `/handoff` for `<project>/HANDOFF_<topic>.md`. Record the EVIDENCE that proved each done-when
  (the grep output, the banner line), not prose. A cold overseer must be able to resume from it.
- ⚠ **Keep the handoff's `IMPLEMENTED-BY` line current** — every model that wrote code, with its
  effort, updated the moment the run changes models. The close reads that line and nothing else
  to pick a reviewer; `/handoff` says why.

## The overseer's rules

**Never** read, edit or write source files; never print file contents; never `git diff` without
`--stat`. **May** read the plan documents, the handoff, cited design sections, gap files and agent
reports; may run `grep -c`/`-l`, `git status --porcelain`, `ls`, and the suite. Line endings:
`git ls-files --eol`, never Git Bash's `grep -c $'\r'`, which counted CR on every line of an LF file.

**Verify every done-when yourself with a bounded command.** Never accept a self-reported green.

**The gate (`CLAUDE.md` Working rules) is one command, run in the background.** Only its GREEN
clears a commit; a failure it marks NEW is never called a flake.

⚠ **A listed intermittent has a budget: three failures, then it is a fix step.** Keep its count on
its Open-bugs line (each gate that trips it adds one); at the third it becomes the next step AFTER
the current group's review round - it now undermines every gate's verdict, so it takes the front
under the queue rule's exception (say so, with what it delays).
Measured: a dozen listed rows, TP-92 alone ~1 gate in 3, all counted and none ever fixed, until
"red, but only listed rows" read as green - and a real regression landing on a listed row would pass.

**Verify the recon premise before dispatch** — the site and cause a brief names are a hypothesis
until a bounded command confirms them ([[brief-premise-is-a-hypothesis]]).

⚠ **A new task goes to the END of the queue.** Owner, verbatim: "from now on new tasks should go to
end of queue unless it would make much more sense to put in the end" (read as: in front). Put one
in front only when it clearly blocks or invalidates the next item, and **say so the moment you
insert it**, with what it delays ("this puts the square cards a session later"). Measured: twelve
found-along-the-way rows pushed the owner-ordered square cards a session back; seven review-comment
steps went ahead of an owner-ordered merge and the owner learned it by asking. Bugs surfaced by a
step that MOVES structure (a node to another layer or viewport, a scene restructured - five on one
run) queue at the end too.

**Split a brief that moves more than one mechanism.** A layout rebuild plus a retired lock-out plus
six re-pointed rows hit the implementer's 150-turn cap mid-edit.

## Writing a step brief

The implementer's definition already carries the report schema and repo rules, so a brief is short —
but it MUST carry:

1. The step id and its **exact done-when, quoted** from the plan.
2. The **test-plan row ids** that step owes. A dropped planned row is a gap, not a judgement call.
3. ⚠ **THE OWNER RULING THIS STEP IMPLEMENTS, QUOTED VERBATIM** from `PLAN.md` §1 (which quotes
   `answers.json` for exactly this purpose). Not the id — the WORDS. **This is the only moment
   drift against an answer is cheap to prevent**: the implementer has the ruling in front of them
   while writing the code. At the close it is already built, and unbuilding it costs a run.
   ⚠ **A done-when can be met while the ruling it came from is not.** Measured: `D11` — *"melds and
   effects both feed combo on the same terms"* — has a step whose done-when was satisfied by tests
   that assert the arithmetic directly, so the step went green while the ruling was never
   implemented on the only path that scores. Nobody noticed until a close two phases later, and by
   then the fix had grown a second open question. **State the ruling and make the done-when answer
   to it**, not only to a test id.
   ⚠ **Quote it; never paraphrase — and script-check every quoted ruling letter against
   `answers.json` before dispatching.** A brief misquoted one letter and a whole step built the
   rejected option.
4. ⚠ **The CALL SITE.** "Where is this called from, and what breaks if it is deleted?" A step whose
   done-when is only "TestX is green" will ship a component nothing calls. Require a test that fails
   when the wiring is removed. **Name the coordinate space of every position the step reads or
   writes** (root viewport or inside the picture) — 4 wrong-space defects on one branch. **For a
   pad or keyboard route, name the VIEWPORT the focus must END in and require the row to assert
   its focus owner** — two pad features on one branch were green on their state change while the
   pad was stranded in the other viewport ([[godot-key-events-no-bubble]]).
5. Any trap that applies — from [[tests-that-prove-nothing]] or [[running-godot-scenes]] — named
   specifically.
6. ⚠ **The comment rule, named** in one line — an implementer not told ships indented prose.
7. ⚠ **The complexity rule, named** in one line — engine method, existing helper, proper altitude.
8. ⚠ **Every field the step adds: what it belongs to, and which event ends it** (show end, New Run,
   screen leave, a refused action). A test drives that event and asserts the field is gone.
   Measured: 6 defects of state outliving its owner on one branch, each found only by a reviewer.
9. ⚠ **Every identifier the step ADDS goes into `NAMES.md` in the same step**, in one line — a
   run's close found fourteen public names in the code and none in the registry. Check it.

⚠ **Do not paste what the implementer's definition already carries** - the report schema, parking by
copy, the exit-profile rule, the comment and complexity rules, design ids, red-then-green, leftover
processes, `NAMES.md`, the shots folder (`.claude/agents/plan-implementer*.md`). Measured: one
session's briefs restated ~25 lines of the definition per dispatch. A brief's words go to what only
this step knows: the ruling verbatim, the suspected writer with `file:line`, the done-when, the
traps that apply, the verification filter.

**Never accept `STATUS: done` on a component whose consumer does not exist.**

⚠ **The expected behaviour a brief states is derived from the rulings block, not recalled.** Before
writing "on return X shows" or "one cancel does Y", find the ruling or the existing row that says so
and quote it. Measured: two expectations written from memory contradicted a ruled row, and only the
implementer's run caught them.

⚠ **STATE THE PROPERTY, NOT THE PROCEDURE.** When a fix is an algorithm, the implementer is the
one who can measure it; an overseer who dictates the steps dictates them blind. Measured at a
close: the reroll brief specified "exclude every face the batch gives up, re-ask the unchanged
board when the offer is spent" — the implementer proved the re-ask a no-op and the exclusion
unsatisfiable on the shipped deck, and the second brief (the deal's own rule over the batch, each
cell barred from its own face) was right only after its measurement too. Write the observable the
test must pin and the ruling it comes from; let the implementer propose the mechanism and report
what it measured, and expect `blocked` with a measurement to be the good outcome.

## The verification hierarchy — weakest to strongest

Each layer caught things the one above it missed.

1. **A green suite** — proves almost nothing. Eight tests in one run passed while asserting nothing.
2. **Greps and counts** — catch contract drift (field lists, registries, knob sets), never behaviour.
3. **Reading the diff** — catches structure and dead code, but not user journeys.
4. **Red-then-green proof** — caught a real defect *every single time*.
5. **An adversarial reviewer tracing what a player actually does** — highest yield of the whole run.

**Between gates, run the inner loop, not the gate:** on solatro `py solatro/tools/run_tests.py
--logic` (headless, several times faster; `--filter <NodeName>` narrows to one suite). It is a
debugging aid with no verdict; a step is done only on a FULL windowed run ([[running-godot-scenes]]).

**Do 3 and 5 when a group lands (§ Spending the reviewer, item 2).** Doing them only at the end means
finding six critical defects after the work is already "complete".

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
effort or higher, no exceptions; the same model clears it. This binds layer 5, the run's
highest-yield check.

A weaker reviewer on stronger code is NET NEGATIVE, not merely useless: reviewing a strong draft, the
weaker model rewrote whole solutions instead of patching, scoring 13 regressions against 3 fixes and
dropping the pass rate 8.6 points (arXiv 2607.21656). In the same experiment a stronger reviewer on
the weaker author's code gained 18.1 points. **Capability is the lever; a different model is not.**
Cross-vendor review buys decorrelated blind spots and is worth having *at or above* the floor —
never below it.

Owner ruling (verbatim): "reviewer ideally fable always, but it never touches the code itself,
just finds issues." Every reviewer runs `fable`, read-only, so the floor is cleared whatever the
author; raising an implementer's tier raises the floor with it. **A review pass REPORTS, never
applies:** `/simplify`'s apply phase and `/code-review --fix` are not used; a finding goes to an
implementer as a step, red-then-green and gated like any other.

## Spending the reviewer - Fable is the expensive senior

Its job is the issue that would cost time LATER, which the junior cannot check cheaply. Never hand
it proofreading, grep work, log triage (`gate.py`) or recon (Explore). Four uses in a run, and no
others (the once-per-session workflow-diff pass is `/handoff` Reflect step 3):

1. **Per step - targeted, and only for a step with judgement in it.** Skip it for a comment sweep, a
   doc-only commit, a data edit at a named site. Hand it the diff plus 2-4 questions about THIS
   diff's riskiest interactions (which inputs reach the new path, what state it inherits, which
   docs it contradicts), never "review everything". Measured: about two in three such reviews
   returned an actionable finding the green run had missed. Add, only when they apply:
   - **the tests** - when the step adds or re-points rows: can each fail, did a re-point get looser,
     does an expected value come from the code under test ([[tests-that-prove-nothing]]);
   - **the shots** - when the step changes what is drawn: the `shots/<step>/<W>x<H>/` folder and the
     ruling; it describes each image and says whether it shows the ruling, before you read yours.
2. **Per group of related steps - broad, sparingly.** When a group lands (§ The owner's visual
   review), one broad pass
   over the group's whole diff, for the problem nobody thought to ask about. Give it a PRIORITY
   ORDER and "report early": an unordered "review 275 commits" spent its budget and returned
   nothing; ordered, the rerun found a defect in its first third. In the review round, it also
   drafts each shot's `seen` from the pixels alone - resolve every disagreement with yours by
   re-reading the image.
3. **An owner question that shapes a mechanism** - one whose answer spreads across several steps
   (a principle, a size that sets a scale): before it reaches the owner, it checks no ruling already
   answers it, the options are complete and neutral, and each look has a shot. Everyday questions
   go straight to the owner.
4. **The close** - the numbered list below; its adversarial and test-surface passes are the broad
   reviews of the whole branch.

⚠ **THE FLOOR IS A RULE THE OVERSEER FOLLOWS, NOT ONE IT CAN CHECK.** `effort` is declared in agent
frontmatter or a model override and is not visible at dispatch time, so nothing validates it. If it
needs enforcing rather than instructing, that is a `PreToolUse` hook on `Agent`.

⚠ **An alias `model:` follows each release; a full ID pins one.** `model:` takes `opus`, `sonnet`,
`haiku`, `fable` or a full model ID such as `claude-sonnet-5-5` (code.claude.com/docs/en/sub-agents).
An alias in the SESSION's own family resolves to the session's exact model, so dispatching `opus` from
an Opus session cannot pick another Opus version - pin a full ID for that. The close still hands
over to a new session: the bias it defeats is the overseer's, not its model's.

⚠ **A usage limit on the higher tier mid-close:** continue on the next tier only if it still clears
the floor, and write the switch into `IMPLEMENTED-BY` before the next dispatch.

## Red-then-green is mandatory

For **every new test**, not only for bug fixes. The implementer's definition binds it and
[[tests-that-prove-nothing]] (its end) carries the procedure. Refuse a report without the red and
the green observation and their per-suite counts, with a red that failed checks other than the
expected ones (a mutant's, when HEAD cannot run the test), or with an existing test adjusted to
green after a fix turned it red. A rewrite that claims to change nothing has no red: refuse it
without the shadow comparison's count and zero-difference line ([[brief-premise-is-a-hypothesis]]).

## The ways a test passes while proving nothing

**[[tests-that-prove-nothing]] carries the list.** Read it before writing a step brief and before
accepting one. The two that bite hardest in this pattern: a fixture that clears the ambient global
state the real product runs under (a pause flag, an autoload), and two competing mechanisms with the
SAME observable, where the test measures which writer ran second.

## Traps that are not about tests

- **One critical fix at a time**, full suite between each — [[one-fix-at-a-time]].
- **Comments deferring to "a later step"** become lies when that step lands. Grep the deferral
  language when closing one.
- ⚠ **WHEN YOU CHANGE A RULE IN A SKILL, GREP THE AGENT DEFINITIONS AND SKILLS THAT RESTATE IT.** A
  run corrected the reviewer rule here and left `.claude/agents/adversarial-review.md` carrying the
  inverted one — *"if you are the implementing model, review nothing"*: dispatched at the floor it
  would have returned an empty report recorded as a review. A skill and the agent that implements
  it are one change, not two.
- ⚠ **AGENT DEFINITIONS RESOLVE FROM THE SESSION'S PROJECT ROOT, NOT THE WORKTREE.** An agent that
  exists only on the branch cannot be dispatched by name from a session rooted in the main checkout.
  Inline its definition into a general-purpose agent and tell that agent to read the file.

## Gaps

Follow the plan's own gap protocol (its propagation block). As overseer: **a bug is not a gap** —
if exactly one choice is defensible, it is a defect; fix it and record it.

⚠ **SIZE A GENERAL RULING BEFORE BUILDING IT.** An owner answer phrased as a principle ("UI never
zooms with the picture") applies to every instance of it, not the one asked about. The moment it
arrives, list the instances it covers and the steps they make, and say so with the queue impact.
Measured: one such answer became six steps nobody had estimated.

**Quote a gap's own option text when asking the owner to decide.** Paraphrasing one caused an answer
to be given against a mislabelled list.

⚠ **A ruling the owner gives mid-run is quoted verbatim in the handoff (or its RULINGS file) AND marked on every design
node, answer, `TEST_PLAN` row and `NAMES` entry it supersedes, in the same commit.** An unmarked
superseded node reads as the live rule to the next brief and the close's reviewer.

## Interruptions

Sessions die to API limits — plan for it. On resume: read the handoff, then `git log --oneline`,
`git status --porcelain`, and **a full suite run**, which is the only ground truth. If the suite is
green and the last claimed step's done-when still passes, continue; otherwise that step is suspect —
reset to the last commit and redo it.

⚠ **A CUT-OFF IMPLEMENTER (turn cap, API limit, app restart) LEAVES ITS EDITS IN THE TREE, ITS RUNS
IN THE LOGS AND `.claude/.subagent.lock` HELD.** The suite script keeps `all_<label>.log` /
`errors_<label>.log` per run, so the banners, per-suite counts and failure set are readable without
the agent, beside its scratch evidence file. Verify from those and the diff first; resume with
`SendMessage` to the same agent id (never a fresh dispatch — its context holds the code) only when
something is missing, and reset only if that fails — never when its last act was a completed full
run. Clear the lock by hand when nothing runs. A background agent is alive only while the report file
its brief told it to append to grows: an owner's interrupt stops background subagents with the
turn and sends no notification, and the lock is released only where the hooks run (Windows). Check
that file's mtime before saying "still running" - measured: a reviewer that died with an interrupt
was reported running for 12 hours.

⚠ **A STOPPED OR FINISHED SUBAGENT CAN LEAVE PROCESSES RUNNING.** After `TaskStop`, or a notice that an
agent stopped with background work, list Godot / python / bash / node by start time and end the
orphans by explicit PID (hard rule 3). Measured: a reviewer's hung command ran 9 hours; a stopped
implementer's mutant script kept swapping files in the tree.

⚠ **Never reset the tree while a subagent is working in it.** One run did, and the agent correctly
reported the worktree as corrupted — it had no way to know the overseer had rolled it back. Tell it
first, and confirm it has stopped.

## The owner's visual review

⚠ **One round per GROUP of related steps, not one per stream.** When a group lands (one mechanism
moved, one ruling built across its instances), shoot a round for it before the next group starts.
Measured: a round that waited for ~15 steps meant the owner saw none of a four-part viewer move, a
picture crop and a menu rebuild - all built on the overseer's reading of rulings - until the end.

Fable's share of a round (the per-group review and its independent `seen` drafts): § "Spending the
reviewer" item 2.

At the end of a run with visual work — or at the start of the next session doing visual work — run
`py solatro/visual-review/review.py refresh` (it reshoots both sides, so it takes the one Godot
slot), then park on `npm --prefix designloop run watch -- visual-review/solatro`. Park only after a
shoot: a Done older than the last shoot is ignored. Every reject or comment becomes an implementer
step, queued under the queue rule (§ the overseer's rules), the owner's comment verbatim as its
brief; then refresh and park again.

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

⚠ **A NEW SESSION, NOT THIS ONE.** The overseer has held the plan for dozens of commits and has
every reason to believe the work is done — that is exactly the bias the close exists to defeat —
and a new session is the only way to choose the reviewer's model (§ floor, `model:`).

## Closing the run — a phase, not a gesture

⚠ **THIS IS A NUMBERED PHASE AND EVERY ITEM EITHER RAN OR DID NOT.** Record each result in the
handoff the way a done-when is recorded: the output, not a claim.

⚠ **The overseer never reads source, so every item that reads code is a subagent**, within hard
rule 2: a parallel second agent is a read-only reviewer or docs work, never a second suite run.

Run in this order. Earlier items change the diff the later ones read.

1. **`py .claude/tools/doc_check.py`** — the FULL run, not `--changed`. Overseer runs this itself;
   it reads no source. Phase boundaries use `--changed`; the close needs the whole repo, because a
   doc this run invalidated may live in a file the run never touched.
1a. **`plan-auditor` subagent writes `AUDIT.md` beside the handoff** — PASS/FAIL per plan item;
   the run closes only at zero unwaived FAILs. `close-needs-audit-warn.ps1` warns until it exists.
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
3. **`/code-review`** on the branch diff, at high effort — correctness. ⚠ It wants eight parallel
   finder agents and a verifier per candidate, which the cap forbids: one Fable finder for the
   three correctness angles (background, beside a read-only reviewer), the cleanup angles inline
   from your own read of the diff, and ONE verifier over the whole deduped candidate list.
   Measured: 14 candidates verified in one pass, 10 findings reported.
4. **A TEST-SURFACE review subagent — the tests, as their own pass.** Items 2 and 3 read
   production; a test that passes while proving nothing is invisible to them by construction and
   invisible to the suite by definition. Hand it [[tests-that-prove-nothing]] as a CHECKLIST, engine
   tests first; items 5, 9, 11, 13, 14 and 20 had the highest yield on one branch.
   ⚠ **DO NOT FOLD THIS INTO `/code-review` OR `bloat-reviewer`.** Both are pointed at production,
   and `bloat-reviewer` reads a step's rows only when asked, one diff at a time — so "the diff was
   reviewed" is routinely true while 12,000 lines of tests in that same diff were read by nobody.
5. **`/simplify`** — the complexity section below is what it enforces. ⚠ It is a built-in skill
   whose Phase 1 launches four agents concurrently, which the cap blocks: run its four angles
   (reuse, simplification, efficiency, altitude) inline yourself, or serially. On a small diff
   inline is strictly better — four cold agents re-deriving context to read ten lines is the
   expensive path.
6. **`/fx-verify`** — mandatory if ANY step touched a visual, a shader or prop art. Green tests are
   not evidence about pixels. Dispatch as a subagent; it renders and LOOKS.
7. **Fix everything 1–6 found** — one fix at a time, full suite between them ([[one-fix-at-a-time]])
   — then re-run whichever of 1–6 your fixes could have invalidated. ⚠ **The fix commits are a
   diff and get their own item-2 pass.** Measured: of nine fixes on one close, one asserted on a
   producer the row's fixture never reached (End with an empty Entrance) and one over-reached
   (a grab meant for the pad fired on every pointer pick); the re-review caught both, the suite
   neither.
   ⚠ **THE OWNER'S WHOLE-FILE COMMENT SWEEP IS ITS OWN STEP, AFTER THE FIXES, NOT PART OF EACH** —
   an exception to the definition's whole-file-on-touch rule. The files a close fixes are the big
   ones (`game.gd` ~350 legacy findings, `play_area.gd` ~640); folding the sweep into a defect fix
   multiplies the blast radius of both, and a sweep once deleted a load-bearing note. Brief every
   fix with "touch only the comments this fix changes; the sweep is a separate final step", then
   dispatch the sweep once: no behaviour change, `sweep_check.py`, its own full gate.
   Test-only repairs in different suites may share one gate: a red there names its suite.
8. **`/docs`** — fold the run's residue into the living docs.
9. **`consolidate-memory`** — merge duplicates, fix facts the run made stale, prune the index.
10. **`/handoff`'s "Reflect and record", over the WHOLE run.** Every trap the run hit that no skill,
   agent definition or memory warned about is a tooling gap, not bad luck; also delete anything
   the run proved wrong.
11. **Delete the temporary plan documents** the run produced.

⚠ **9 AND 10 ARE THE ANTI-DEBT STEPS, AND THEY ARE THE FIRST TO BE SKIPPED.** Skipping them makes
every later session re-read memory that duplicates itself and re-discover a trap already paid for
once — a cost in tokens on every later run, which is why nobody notices it.

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

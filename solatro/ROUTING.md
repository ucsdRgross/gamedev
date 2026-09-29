# Routing Solatro's plan steps to an implementer tier

The general rule, the tiers and the cost arithmetic live in `.claude/memory/implementer-routing.md`.
This file is the Solatro catalogue: every kind of step the playtest-fix stream has actually run, the
tier it belongs to, and the evidence. Route a new step by the row it matches; when none matches, ask
the one question - **can this step end with "the premise was wrong, stop and ask"?**

## Sonnet 5.5 high (`plan-implementer-sonnet`) - fully specified, a tool checks the result

| Task kind | Example | Why no judgement is needed |
|---|---|---|
| Comment sweep of named files, code unchanged | the whole-file sweeps owed after a fix | `.claude/tools/sweep_check.py` proves the code byte-identical; every such sweep landed first round |
| Doc correction at named lines, replacement given | the design records `/docs` owes at a close; a stale "another viewport" line | `.claude/tools/doc_check.py` verifies |
| A knob or data edit whose value the brief states | tripling the base prop speed; placeholder colours with the palette entries named | one value, one home |
| Mechanical test hygiene at named lines | bare `frame_post_draw` awaits moved onto `TestSuite.await_drawn_frames`; deleting a duplicated pin; splitting collapsed `\` continuations | a pattern applied as written; the filtered run confirms |
| Bookkeeping | shot entries in `solatro/visual-review/manifest.json`; `NAMES.md` rows for a landed step | copied from the step's evidence |
| Re-shooting a named shot scene | a shot rerun after a fix | run and save; the overseer and Fable do the looking |

## Opus 5.5 low (`plan-implementer-low`) - the writer is named, measuring may overturn it

| Task kind | Example | Evidence |
|---|---|---|
| One-site fix with its `file:line` | making disabled buttons unfocusable; refreshing the menu's Continue on every show; the review page's Done not reaching `status.owner.json` | the disabled-button step stopped on a navigation question its brief never foresaw |
| Reproduce a review finding, then fix or refute it | a Fable claim of "no writer rests the focus" refuted by a probe and a mutant | verifying is the judgement |
| Measure a visual or layout complaint, then fix | the owner's review comments: text centring, a sea buffer, a viewer's inner margin, the win overlay's centre, hoop alignment | every one is "measure first" |
| Re-check a stale report before building | a hang last seen before the minimized-window fix | may close with a measurement alone |
| Tooling fix at a named script | `.claude/tools/gate.py` diffing against a stale gate; `.claude/hooks/commit-gate.ps1` blaming pairs already on HEAD | named site, known symptom |
| Add a check a test helper promises and lacks | a slide helper whose docstring says it fails and never does, nine callers | any caller going red needs a diagnosis |
| Build a mechanism already chosen and measured | emptying `ui_focus_next` so Tab reaches the wall | nothing left to decide - run at medium only because that implementer was warm |

## Opus 5.5 medium (`plan-implementer`) - the cause is open, or a state machine or focus model moves

| Task kind | Example | Evidence |
|---|---|---|
| A listed intermittent past its budget | a freed-instance race between two suites' boards; a frame-rate-dependent timing row; a focus stolen by another suite's window | each found a global-state or timing cause and several stopped for an owner pick; the one open-cause bug given to Sonnet 5 failed after 288k tokens |
| A focus, input or modal route across viewports | cancel and Tab out of the pack chooser; the start menu by keys and pad; the sidebar reachable under an open viewer | three rounds each, and every round's review found a real hole the green suite missed |
| Restoring parked work across a merge and re-proving it | a start-menu rebuild parked on a pre-merge branch | a hypothesis measured false; four mutant rows re-proved |
| A new UI behaviour inside a ruling | the possible-cards list as icons; the chooser's size against an earlier ruling | layout choices that may raise an owner question |
| Deciding what a test must assert | root-window rows at the real content scale | choosing the claims is the work |

## Outside the ladder

- Read-only recon before a step: `Explore` on `sonnet`. Its runtime claims go into the brief as "traced, not measured".
- Every review: Fable, read-only (`.claude/memory/implementer-routing.md`).
- Reading a PNG and writing its `seen`: the overseer and Fable only - a judgement about pixels.
- The full gate, commits, counting intermittents: the overseer.

## Two patterns

- **A step's later rounds sit higher than its first.** Review findings on a focus or input step are
  usually open-cause; a follow-up that only deletes or rewords drops back to Sonnet.
- **Route by the question, not by who is warm.** Continuing a finished implementer with
  `SendMessage` saves cache reads only while the step still needs that tier.

# HANDOFF — the Design Loop tool

**Goal:** build the tool described by `designloop/design/designloop/PLAN.md` — the owner answers a
branching design questionnaire one question at a time in a local browser UI, every answer is on
disk before the next question appears, and the agent is woken when the round ends. Done for the
whole stream = all 17 steps (S1–S17); done for **this** run = S1–S10, Phases 0 through 2.

**State:** S1–S10 are complete and verified — Phase 2 is finished, so the questionnaire half of the
tool works end to end today. `npm --prefix designloop test` is green at 60/60, and the whole
answering loop has been driven in the browser against the real 196-question
`solatro/SPOTLIGHT_DESIGN.md`, which was **not edited** (`git diff HEAD` on it is empty). The next
work is **Phase 3, the canvas (S11–S14)**, starting with mermaid ingestion. One gap is open —
`gaps/GAP-001.md` — and it is not blocking: both behaviours are implemented behind a `strict` flag
and the owner picks the default.

**Entry docs:** `designloop/design/designloop/PLAN.md` (the build document; §4–§7 are normative),
`designloop/design/designloop/DESIGN.md` (the authority on behaviour — where they disagree, the
design wins), `designloop/design/designloop/ASSUMPTIONS.md`, `designloop/design/designloop/gaps/`.

---

## Design provenance and gap protocol — COPY THIS BLOCK INTO ANYTHING DERIVED FROM THIS DOCUMENT

Derived from: `designloop/design/designloop/DESIGN.md`, rounds 1–2 answered 2026-08-01. Every step
below cites the design node IDs it implements.

If you are executing this and you reach a decision the design does not cover:

1. Reversible and clearly within intent → do it, and append one line to
   `designloop/design/designloop/ASSUMPTIONS.md` citing the node you were working on. Never
   silently.
2. Otherwise — two defensible choices differ in what the user sees, or the choice is expensive to
   reverse (file format, a public seam, the question grammar), or it is an owner call (scope, look)
   → **park that thread, file a gap, keep working on unaffected threads, and tell the owner.**
3. The design contradicts itself or the code → always a gap, highest priority.

File gaps at `designloop/design/designloop/gaps/GAP-NNN.md` using the template in
the gap template in `.claude/skills/flowchart-design/SKILL.md`.
Write the options in the questionnaire grammar; they become the next round's questions unchanged.

Do not resolve a gap by picking an answer. Do not proceed on the parked thread. Do not delete a gap
— it is closed by a new design version.

This block, unchanged, goes into every document derived from this one.

---

## How to run it

```
npm --prefix designloop test                          the whole suite, ~2 s
npm --prefix designloop start                         the server, http://localhost:5273
npm --prefix designloop run check -- solatro/spotlight  does a design document parse?
npm --prefix designloop run watch -- solatro/spotlight  park until the owner finishes a round
```

The Browser pane drives it through the `designloop` entry in `.claude/launch.json`.
**The pane in this environment is not displayed**, which has two consequences for the next agent:
`computer {action:"screenshot"}` fails and OS-level key events do not reach the page. Verify the UI
with `read_page` / `get_page_text`, and exercise keyboard paths by dispatching real
`KeyboardEvent`s through `javascript_tool` — that runs the actual handler in the actual page.
**The Node server has no hot reload**: after editing anything in `designloop/src/`, `preview_stop`
then `preview_start`, or the browser will be talking to the old routes.

## Tasks

```yaml
- id: S1
  description: >
    Project skeleton and server (implements A4, I2, I3). package.json (type module, zero deps),
    src/server.mjs static hosting + JSON API + /api/ping + /api/shutdown + port reclaim,
    start.cmd, and a designloop entry in .claude/launch.json.
  files_touched: [designloop/package.json, designloop/start.cmd, designloop/src/server.mjs,
                  designloop/web/index.html, designloop/web/app.css, designloop/test/server.test.mjs,
                  .claude/launch.json]
  verification_command: 'npm --prefix designloop test'
  verification_kind: suite
  status: done
  evidence: |
    6 server tests pass: ping returns {app:"designloop"}, / redirects to /web/index.html,
    /src/grammar.mjs is served to the browser, package.json + traversal are 404, shutdown is
    POST-only and only exists with a stop hook. Server observed live on port 5273 via preview_start.
  notes: >
    Static root is designloop/ but only web/ and src/ are reachable, so the browser's
    ../src/grammar.mjs import resolves without exposing the tool directory. One real bug found and
    fixed: listenFrom resolved with the requested port, so port 0 (the test harness) produced an
    unconnectable URL — it now asks the socket.

- id: S2
  description: >
    The grammar module (implements C1–C11, PLAN §5). parseDocument / parseQuestionLine / parseGate /
    evaluateGate / reachability / nextQuestion / blastRadius / validate, pure and importable by both
    the server and the browser.
  files_touched: [designloop/src/grammar.mjs, designloop/test/grammar.test.mjs]
  verification_command: 'npm --prefix designloop test'
  verification_kind: suite
  status: done
  evidence: |
    THE ACCEPTANCE GATE, against an UNEDITED solatro/SPOTLIGHT_DESIGN.md:
      questions   195 live, 1 retired   (188 Q-numbered + 8 QR, Q140 retired in place)
      gates       8 ⚑gate, 39 marked notes
      opens at    QR1
      errors      0
      warnings    1   (QR8 — see gaps/GAP-001.md)
      skipped     4 bullets that name a question ID but are not questions
    validate() reports no cycle, no gate naming an undefined ID or letter, nothing unsatisfiable.
    QR1=(b) prunes 22 questions of §17.2. 27 grammar tests pass, one per §5.6 construct.
    git diff HEAD -- solatro/SPOTLIGHT_DESIGN.md is empty.
  notes: >
    Two counts in PLAN.md do not survive contact with the document, both recorded in ASSUMPTIONS.md
    and neither a behaviour change. (1) §5.6 says "188 questions, 8 of them QR*"; the document has
    188 Q-numbered questions PLUS 8 QR, so the assertion is 188 + 8 = 196 lines. (2) S2 asks the
    reachability run to reproduce "longest path ~150"; the measured longest path is 194 of 195,
    because exactly one pair in the whole DAG is mutually exclusive (Q118 [Q113=a] against
    Q114 [Q113=b|c]). The ~150 is a hand estimate, not a property of the gates. Test pins 194.

- id: S3
  description: >
    Registry and index (implements H1–H4, Q102, Q103, Q106, Q107). registry.mjs scans
    */design/*/meta.json; the index page lists every design by project, title, status, last touched,
    with a gap badge.
  files_touched: [designloop/src/registry.mjs, designloop/web/index.mjs, designloop/web/index.html,
                  solatro/design/spotlight/meta.json, designloop/test/api.test.mjs]
  verification_command: 'npm --prefix designloop test'
  verification_kind: manual
  status: done
  evidence: |
    Index page read in the Browser pane:
      designloop
        Design Loop — the branching-questionnaire design tool
        your turn — answering · 0 answered · last touched 8/1/2026   [1 open gap]
      solatro
        The Spotlight mechanic and its visual effects
        your turn — answering · 0 answered · last touched 8/1/2026
    Plus an API test asserting key/title/owner/agent/answered/touched for a fixture design.
  notes: >
    Spotlight is registered IN PLACE — solatro/design/spotlight/meta.json with
    "doc": "../../SPOTLIGHT_DESIGN.md" — so the UI could be verified against the real 196-question
    document without moving or editing the owner's paused file. Q104=(a) still stands: S16 does the
    real move and changes that one string to "DESIGN.md".

- id: S4
  description: >
    The durable store (implements B12, Q80–Q82, Q108, Q35). Append to answers.log, fsync, rewrite
    answers.json via temp+rename, fsync, THEN respond.
  files_touched: [designloop/src/store.mjs, designloop/test/store.test.mjs]
  verification_command: 'npm --prefix designloop test'
  verification_kind: suite
  status: done
  evidence: |
    THE S4 GATE — "a crash between the log append and the materialise is recovered by replay":
    the test appends a third answer with its fsync, asserts answers.json is byte-identical to what
    it was one answer earlier (the precondition — the crash window), then loads: the replay
    recovers all three answers, reports recovered:true, and seq is 3 so the next answer does not
    reuse a sequence number. A second test corrupts answers.json outright and the log still rebuilds
    it. 11 store tests pass, covering the three answer states, strand/restore keeping notes intact,
    a torn final log line, and a hand-edited answers.json with no log.
  notes: >
    Real Windows bug found and fixed here: a replacing rename fails with EPERM while anything else
    holds the directory open, which the S9 watch guarantees. writeJsonAtomic now retries
    EPERM/EACCES/EBUSY with a short backoff. It fired on the first run of the watch test.

- id: S5
  description: >
    The question screen (implements B6, B7, B7a, B7b, Q11, Q12, Q14, Q17, Q17b–d, Q26). One
    question, options prefilled with consequences, recommendation marked but not pre-selected, free
    text, NOT RELEVANT, expandable "asked because…", → next previews on gates only, no progress.
  files_touched: [designloop/web/question.html, designloop/web/question.mjs, designloop/web/app.css,
                  designloop/src/server.mjs]
  verification_command: 'npm --prefix designloop test'
  verification_kind: manual
  status: done
  evidence: |
    Browser pane, key=solatro/spotlight, opens at QR1 with both options, both consequences, both
    "→ next:" previews, (a) marked "recommended" and NOT selected, a free-text box, Not relevant,
    Back, History — and nothing on screen that indicates progress. Clicking (b) advanced to QR2 and
    left reachable 47 / pending 121 / pruned 26, with all 22 §17.2 questions pruned.
    "asked because… QR1 = yes" rendered on a gated question in the dry run.
  notes: >
    Ordering is §5.5 as written: document order within a section, sections by gate weight. The
    visible consequence is that answering QR1=(a) pulls §17.2 (weight > 0) ahead of the rest of the
    ungated §17.1 — deliberate, "the tree collapses fastest".

- id: S6
  description: >
    Input parity and Enter-to-default (implements Q13, Q108–Q113). Arrow keys move a visible focus
    ring, Enter picks the focused option, letter keys jump, everything is a click target; Enter with
    nothing focused accepts the default as `defaulted` but stops at ⚑gate and `notes` questions.
  files_touched: [designloop/web/question.mjs, designloop/web/app.css]
  verification_command: 'npm --prefix designloop test'
  verification_kind: manual
  status: done
  evidence: |
    Driven in the page: letter 'b' then 'a' moved the ring to those options; Enter on the focused
    option answered QR1 and advanced; Enter with nothing focused defaulted Q9 and advanced; the next
    Enter STOPPED at Q10 (a `notes` question) with the banner "You accepted 1 recommended answer
    without reading it…" naming Q10 exactly and a click-back list, focus ring on option (a).
    On a ⚑gate (QR1, revisited) Enter with nothing focused refused, explained why, and left the
    answers byte-identical (checked against /history before and after).
  notes: >
    One real bug found and fixed: the focus-ring modulo kept returning -1, so arrow keys did
    nothing. The ring has one slot more than there are controls — slot 0 is "nothing focused", which
    is the state Enter reads as "accept the recommendation".

- id: S7
  description: >
    Back, history and re-answering (implements D1–D9, Q33–Q36b). BACK plus a clickable history list;
    a re-answer previews its blast radius before applying; stranded answers go inactive, never
    deleted, and restore intact.
  files_touched: [designloop/web/question.mjs, designloop/src/server.mjs, designloop/src/grammar.mjs]
  verification_command: 'npm --prefix designloop test'
  verification_kind: manual
  status: done
  evidence: |
    The S7 scenario, run in the page against Spotlight: answered the roots with QR3=(a), then 15
    §17.8 beam questions; re-answering QR3=(b) showed "This makes 15 of your answers irrelevant"
    listing exactly Q88, Q93–Q98, Q100–Q107 BEFORE applying, and a preview writes nothing
    (asserted in the API test). Continuing marked all 15 inactive with their notes intact;
    re-answering (a) restored all 15 ("15 earlier answers came back"), Q97 back as chosen/(a).
  notes: >
    The Q34 warning is an in-page screen with Continue / Leave it as it was, not a browser
    confirm() — Q113 says every control is keyboard-reachable, and a native dialog is not.

- id: S8
  description: >
    Round handshake and gate override (implements B15, B17, P1–P8, E2, E9, E10, Q28, Q29). Two
    status files, one writer each; last reachable question answered → done/complete; free text at a
    ⚑gate → done/new_branch_needed immediately; the DONE screen switches itself over.
  files_touched: [designloop/src/server.mjs, designloop/src/registry.mjs, designloop/web/question.mjs]
  verification_command: 'npm --prefix designloop test'
  verification_kind: manual
  status: done
  evidence: |
    Free text at QR3 in the page wrote {"state":"done","reason":"new_branch_needed"} and the screen
    became "Your answer needs a branch that does not exist yet", surviving a reload. Writing
    status.agent.json {state:ready, round:2, summary:"Your answer to QR3 opened these…"} as an agent
    would: the DONE screen switched ITSELF over within ~2 s, showed the summary banner with its
    markdown rendered, and resumed at QR4 — no reload, no instruction to the owner.
    The complete ending was driven end to end on the S10 dry-run design: two questions answered,
    "That is everything for now", owner {state:done, reason:complete}.
  notes: >
    Two additions ASSUMPTIONS.md records, both because §4.2 requires a transition §4.8 gives no
    route for: POST /api/designs/:key/resume (the UI taking its turn back), and an optional
    `summary` string in the agent-owned status file (Q29 needs it; §4.2 has nowhere to put it).

- id: S9
  description: >
    The watch (implements E4, E5, E7, E9, Q20, Q21, Q23). `npm run watch -- <design>` blocks until
    owner_state changes and prints what happened; the chat fallback stays documented as always valid.
  files_touched: [designloop/src/watch.mjs, designloop/test/watch.test.mjs, designloop/package.json]
  verification_command: 'npm --prefix designloop test'
  verification_kind: manual
  status: done
  evidence: |
    6 tests pass, including "the watch wakes within a second of the owner finishing" (asserts
    elapsed < 1000 ms). Hand-run against the real design: parked with "watching solatro/spotlight —
    waiting for the owner. Ctrl-C, or just tell me in chat.", and on the status flip printed
      solatro/spotlight — the owner's turn ended
        state       done (complete)
        round       1
        answered    3 active
        own answers 1 — QR3
    then wrote status.agent.json {state:"working"} and left status.owner.json untouched.
  notes: >
    fs.watch is the fast path and a 250 ms poll is the backstop, because a watch that silently stops
    firing would strand an agent for as long as the owner is willing to wait. A missing directory
    rejects rather than waiting forever. No timeout by default (Q23=a).

- id: S10
  description: >
    Skill wiring (implements A2–A4, Q91). The flowchart-design skill gains the concrete handover:
    where to write the design, how to check it parses, how to start the server, what URL to hand
    over, how to park on the watch, and how to hand the turn back.
  files_touched: [.claude/skills/flowchart-design/SKILL.md, designloop/src/check.mjs,
                  designloop/package.json]
  verification_command: 'npm --prefix designloop run check -- solatro/spotlight'
  verification_kind: manual
  status: done
  evidence: |
    Dry run: created designloop/design/dryrun/ with meta.json + a two-question DESIGN.md exactly as
    the skill now instructs. `run check` reported 2 live questions, 1 ⚑gate, opens at QR1, 0 errors.
    The index picked it up under "designloop" with no restart, both questions were answered in the
    UI, "asked because… QR1 = yes" appeared on the gated one, and it ended at the DONE screen with
    owner {state:done, reason:complete}. Dry-run directory then deleted.
  notes: >
    The skill's section says in its own words that the tool is optional and the markdown document is
    still answerable by ID in chat if it is absent — that requirement is stated, not just satisfied.

- id: S11
  description: >
    Graph ingestion (implements G2, Q64). src/graph.mjs reads ```mermaid blocks into
    {nodes, edges, chart} with IDs preserved, restricted to the PLAN §6 subset, failing loudly
    (naming file and line) on anything outside it.
  files_touched: [designloop/src/graph.mjs, designloop/test/graph.test.mjs]
  verification_command: 'npm --prefix designloop test'
  verification_kind: suite
  status: pending
  evidence: ''
  notes: >
    PLAN §9 calls this the riskiest step. The gate is all 14 charts in SPOTLIGHT_DESIGN.md AND all
    10 in designloop's DESIGN.md ingesting with zero unknown constructs — 24 real charts. Note
    before starting: both documents wrap long labels across source lines inside quotes (§6 says join
    with a single space), and DESIGN.md chart A uses that form heavily.

- id: S12
  description: Canvas render (implements F2, Q52, Q53, Q63, Q66) — whole graph, collapsible subgraphs, deterministic layout, pan/zoom.
  files_touched: []
  verification_command: 'npm --prefix designloop test'
  verification_kind: manual
  status: pending
  evidence: ''
  notes: 'Hand-rolled layered layout FIRST and record the measurement; adding a dependency is a GAP, not a free choice (PLAN §9).'

- id: S13
  description: Annotations and side panel (implements F5, F6, F7, Q55–Q58, Q116).
  files_touched: []
  verification_command: 'npm --prefix designloop test'
  verification_kind: manual
  status: pending
  evidence: ''
  notes: 'store.annotate() already exists and is tested — annotations.json round-trips per §4.5.'

- id: S14
  description: Approval, Confirm, versions (implements F10, F11, G1–G3, Q59–Q62, Q65, Q71, Q72, Q115).
  files_touched: []
  verification_command: 'npm --prefix designloop test'
  verification_kind: manual
  status: pending
  evidence: ''
  notes: 'Confirm freezes layout AND collapse state (Q115=b). Note the owner''s Q59 answer in DESIGN.md §9.5 asks for DISapproval flagging, not per-node approval — read it before building the panel.'
```

## Verified vs assumed

| Claim | How it is known |
|---|---|
| The whole suite is green | `npm --prefix designloop test` → `tests 60 / pass 60 / fail 0`, 1.65 s, run after the last edit |
| `SPOTLIGHT_DESIGN.md` parses unchanged | `npm --prefix designloop run check -- solatro/spotlight` → 195 live + 1 retired, 0 errors, 1 warning; `git diff HEAD -- solatro/SPOTLIGHT_DESIGN.md` empty; file still 1221 lines |
| A crash between log and materialise is survivable | The S4 test simulates the exact window (append + fsync, no materialise) and asserts the stale file first, then the recovery — not an inferred property |
| The watch wakes in under a second | Asserted numerically in the test, and observed by hand against the real design |
| The UI behaves as S5–S8 require | Driven in the Browser pane and read back with `get_page_text` / DOM queries; every claim above quotes what the page actually said |
| **Not verified: how any of it LOOKS** | The Browser pane is not displayed in this environment, so `screenshot` fails. Structure and text are verified; nobody has looked at the pixels. PLAN §10 leaves appearance deliberately unspecified — "plain and legible" is the standard applied, and it is unconfirmed by eye |
| **Not verified: OS-level keyboard input** | Real key events do not reach a non-displayed pane. The handlers were exercised with dispatched `KeyboardEvent`s in the real page, which runs the same code, but a physical keypress has not been tried |

## Open bugs

None known. Three real defects were found and fixed during this run, each noted in its task:
`listenFrom` returning the requested rather than the bound port (`src/server.mjs`), the focus-ring
modulo never leaving -1 (`web/question.mjs`), and the Windows replacing-rename EPERM under the
watch (`src/store.mjs`).

## Open gaps

- `designloop/design/designloop/gaps/GAP-001.md` — **CONTRADICTION, open.** PLAN §5.1 says a ⚑gate
  option with no `→ next:` is a hard parse error; PLAN S2 says `SPOTLIGHT_DESIGN.md` must parse
  unchanged with zero errors; QR8's option (a) has no preview. Not blocking: `parseQuestionLine`
  takes a `strict` flag, strict throws (so §5.6's test exists), the default warns (so the acceptance
  gate passes and names QR8). Whichever way the owner answers, the change is one default.

## Files touched

```
 M .claude/launch.json                                 designloop entry, port 5273
 M .claude/skills/flowchart-design/SKILL.md            S10 — the concrete handover
 M designloop/design/designloop/ASSUMPTIONS.md         9 assumptions, each with why it is reversible
?? designloop/design/designloop/gaps/GAP-001.md
?? designloop/package.json  designloop/start.cmd
?? designloop/src/          grammar.mjs graph? (no) server.mjs store.mjs registry.mjs watch.mjs check.mjs
?? designloop/test/         grammar server store api watch
?? designloop/web/          index.html index.mjs question.html question.mjs app.css
?? solatro/design/spotlight/meta.json                  registers Spotlight in place (see S3 notes)
```

`solatro/SPOTLIGHT_DESIGN.md` is **not** in that list, and that is a requirement, not an accident.

## Next up

1. **S11 — graph ingestion.** The riskiest step in the plan. Write `src/graph.mjs` to PLAN §6
   exactly, and treat all 24 existing charts as the acceptance corpus before calling it done.
2. **S12 — canvas render.** Hand-rolled layered layout first, measured; a layout dependency is a
   gap to file, not a choice to make.
3. **S13 — annotations and side panel.** Read DESIGN.md §9.5 Q59's written answer first — the owner
   asked for disapproval flagging with soft-approval defaults, which is not what the plan's summary
   line says.

### Copy-paste opening prompt for the next agent

```
Continue the Design Loop tool. Read designloop/HANDOFF_designloop.md first — it is the source of
truth and stands alone. S1–S10 (Phases 0–2) are done and verified; you are starting Phase 3, the
canvas, at S11.

The build document is designloop/design/designloop/PLAN.md and its §4–§7 are NORMATIVE — the file
formats, the question grammar, the mermaid subset and the module APIs are specified, not suggested.
DESIGN.md beside it is the authority on behaviour; where the two disagree the design wins and the
plan is wrong. Follow the gap protocol at the head of the plan: if you hit a decision the plan does
not cover, do not invent it — file a gap under designloop/design/designloop/gaps/ and keep working
the steps it does not block. GAP-001 is already open and is not blocking.

S11's gate is self-checking and is the risky one: all 14 mermaid charts in
solatro/SPOTLIGHT_DESIGN.md and all 10 in designloop/design/designloop/DESIGN.md must ingest with
zero unknown constructs — 24 real charts. Do not edit either document to make it parse; if it does
not parse, the subset or the parser is wrong.

Verify with `npm --prefix designloop test` after every step (60 tests pass today), and drive the UI
through the Browser pane via the `designloop` launch config. Two environment facts that cost time
last session: the pane is not displayed, so screenshots fail and OS key events do not reach the
page — verify with read_page/get_page_text and dispatch KeyboardEvents through javascript_tool; and
the Node server has no hot reload, so preview_stop + preview_start after any src/ edit.

Keep this handoff updated after every task. Do not git add or commit.
```

## References

- `designloop/design/designloop/PLAN.md` — the build document; §3 the steps, §4 the interchange
  contracts, §5 the grammar, §6 the mermaid subset, §7 the module APIs.
- `designloop/design/designloop/DESIGN.md` — the authority on behaviour; charts A–J, §9/§12 the
  questionnaire and its answers of record.
- `designloop/design/designloop/ASSUMPTIONS.md` — every decision taken that the design did not
  cover, with why each is reversible.
- `.claude/skills/flowchart-design/SKILL.md` — the authoring rules, the gap protocol and its
  template, and (as of S10) the handover procedure.
- `solatro/SPOTLIGHT_DESIGN.md` — the acceptance corpus, and the first real client. Read-only.
- `palette/tools/serve.mjs` — the dependency-free local server this one is modelled on.

# HANDOFF — the Design Loop tool

**Goal:** build the tool described by `designloop/design/designloop/PLAN.md` — the owner answers a
branching design questionnaire one question at a time in a local browser UI, every answer is on
disk before the next question appears, and the agent is woken when the round ends. Done for the
whole stream = all 19 steps (S1–S19; S18 and S19 are the owner's own reviews of what was built).
**All 19 are done.**

**State: THE TOOL IS FINISHED.** Every step S1–S17 is complete and verified, and
`npm --prefix designloop test` is green at **119/119**. All three halves work end to end: the
questionnaire (Phases 0–2), the review canvas (Phase 3), and the gap surface (S15) — gap files read
as draft questions, a badge per design, a **scoped round** built from a gap's own options, stale
plan steps computed from the plan's own citations, closed gaps kept with their resolutions, and
"I want a say in this" promoting an assumption to a gap from the canvas. **S16 moved the owner's
document**: `solatro/SPOTLIGHT_DESIGN.md` is now `solatro/design/spotlight/DESIGN.md` and its
`meta.json` says `"doc": "DESIGN.md"` — **not one byte of the document changed** (sha1
`68c348dbe38262be6c2af49042321a9085eb3471` before and after), and it still parses (195 live
questions) and ingests (14 charts / 176 nodes / 182 edges) unedited from its new home.
`designloop/README.md` is the tool's entry point; new work on it starts there.

**The owner has now reviewed both halves by using them, and each review became a design version.**
The canvas on 2026-08-02 (S18 → version 3, GAP-002). **The answering screen on 2026-08-03 (S19 →
version 4)**: history is a scrollable sidebar carrying question *and* answer; BACK is a real visit
stack that is never a silent no-op; every control shows the key that presses it; the control Enter
will press is **marked before you press it**; a typed answer can no longer be destroyed by Enter;
and the screen says whether **an agent is actually watching**, with a prompt to paste when none is.
`DESIGN.md` §15 is the changelog. **Both gaps are closed and there is nothing parked.** GAP-002 was answered in the tool's own scoped gap round on
2026-08-02 — the owner chose **(b)**, derive the cross-chart links — which produced **design
version 3** (`DESIGN.md` §14) and re-derived S11, S12 and S14. The links ship: `graph.json` has a
`links` list beside `edges`, and the whole-graph view draws them dashed. 125/125 green.

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
npm --prefix designloop test                                  the whole suite, ~1.5 s
npm --prefix designloop start                                 the server, http://localhost:5273
npm --prefix designloop run check -- solatro/spotlight        does a design document parse?
npm --prefix designloop run check -- solatro/spotlight charts …and do its charts ingest?
npm --prefix designloop run watch -- solatro/spotlight        park until the owner finishes a round
```

Four screens, all keyed `<project>/<slug>`: `/web/index.html` lists every design,
`/web/question.html?key=…` answers the questions (`&scope=gaps` makes it a scoped gap round),
`/web/canvas.html?key=…` reviews the graph (`&version=1` opens a frozen one), and
`/web/gaps.html?key=…` is the gap surface — open, closed, and what is stale.
Never pass a `--flag` through `npm run` — npm eats it and exits 255 on a run that succeeded; that
is why the chart listing is the bare word `charts`.

The Browser pane drives it through the `designloop` entry in `.claude/launch.json`.
**The pane in this environment is not displayed**, which has two consequences for the next agent:
`computer {action:"screenshot"}` fails and OS-level key events do not reach the page. Verify the UI
with `read_page` / `get_page_text`, and exercise keyboard paths by dispatching real
`KeyboardEvent`s through `javascript_tool` — that runs the actual handler in the actual page.
**The Node server has no hot reload**: after editing anything in `designloop/src/`, `preview_stop`
then `preview_start`, or the browser will be talking to the old routes. Editing `web/` only needs a
page reload.

⚠ **Verify against a throwaway design, never against `solatro/spotlight`.** Answering anything in
the UI writes `answers.json`, `answers.log` and `status.owner.json` into that design's directory,
and on the owner's paused document those are answers they did not give. It happened twice on
2026-08-02 — once deliberately for the S16 gate and once because a `javascript_tool` click landed
on a tab still showing Spotlight — and both times the files had to be deleted afterwards. Make a
design directory with a two-question `DESIGN.md`, exercise that, delete it. Check
`git status solatro/design/spotlight` before you finish.

**To actually LOOK at the canvas** (project rule 4 — visuals are verified by eye or not at all):
the `claude-in-chrome` tools drive the owner's real Chrome, which composites, so `screenshot` works
there. Two traps met on 2026-08-01: that window opens at 200 % page zoom, so send `ctrl+-` a few
times (click the page first, or the key goes nowhere) and confirm with
`javascript_tool → ({dpr, inner:[innerWidth,innerHeight]})` before believing a screenshot; and
Chrome blocks a *second* automatic download, so only the first export lands in `Downloads/`.

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
  files_touched: [designloop/src/graph.mjs, designloop/test/graph.test.mjs, designloop/src/check.mjs]
  verification_command: 'npm --prefix designloop test'
  verification_kind: suite
  status: done
  evidence: |
    THE S11 GATE, against both UNEDITED documents:
      solatro/SPOTLIGHT_DESIGN.md   14 charts  176 nodes  182 edges  0 validate errors
      design/designloop/DESIGN.md   11 charts  128 nodes  133 edges  0 validate errors
    25 charts, zero unknown constructs, zero edits to either document. Chart IDs A–N and
    A,B,P,C,D,E,F,G,H,J,I. Round-trip asserted: re-ingesting the generated DESIGN.md reproduces the
    same charts, nodes and edges. 22 subset tests, one per construct and one per refusal — every
    refusal names the file and the line (`T.md:4 A1 is declared twice with different labels…`).
  notes: >
    PLAN §6 says the corpus is 24 (14 + 10). DESIGN.md actually holds 11 charts — B2, the `P*`
    nodes, is a chart of its own — so the gate met is 25 (ASSUMPTIONS.md). One design decision worth
    knowing: the parser is a left-to-right cursor, never a split on `-->`, because labels legitimately
    contain `->`, `--` and `·`. Two charts sharing a prefix is an error rather than a merge.

- id: S12
  description: >
    Canvas render (implements F2, Q52, Q53, Q63, Q66). src/layout.mjs (hand-rolled layered layout,
    pure and deterministic) + web/canvas.html/.mjs: whole graph, per-chart collapse, a chart picker
    that solos one chart, pan/zoom, colour by chart or by status, full keyboard parity.
  files_touched: [designloop/src/layout.mjs, designloop/web/canvas.html, designloop/web/canvas.mjs,
                  designloop/web/app.css, designloop/src/server.mjs, designloop/test/layout.test.mjs]
  verification_command: 'npm --prefix designloop test'
  verification_kind: manual
  status: done
  evidence: |
    THE MEASUREMENT PLAN §9 ASKED FOR — hand-rolled layered layout at Spotlight's size:
      176 nodes, 182 edges   1.8 ms best of 10, 2.3 ms median   deterministic (byte-identical runs)
      9 straight-line edge crossings in the whole 14-chart graph; 5 back edges found and bowed out
    No layout dependency is needed, so no gap was filed. Asserted in tests: no two nodes overlap,
    every node sits inside its chart's frame, every edge points down a layer except the recorded
    back edges, collapse removes a chart and shrinks the page, `only` restricts to one chart.
    LOOKED AT, in real Chrome (project rule 4): the whole 14-chart graph fits at 17 %, each chart a
    framed block titled in its own colour; chart A at 88 % reads cleanly — rounded boxes, chamfered
    decision slabs, `no`/`yes` edge chips, node IDs in the corner, a green NEW badge on A6. Colour
    by status repaints NEW green and leaves the rest neutral; collapsing D folds it to a dashed box
    and reflows the page.
  notes: >
    One real bug the screenshot caught: the status-colour CSS rules beat the per-chart presentation
    attributes, so every NEW node was green in "colour: by chart". Fixed by putting the mode on the
    `.nodes` group. Two more found by eye: the canvas swallowed Ctrl+− and Ctrl+F (modified keys now
    return early), and disabled buttons looked enabled (`button:disabled` styling).

- id: S13
  description: >
    Annotations and side panel (implements F5, F6, F7, Q55–Q58, Q116). Click a node or an edge for
    its detail, the questions that decided it and your answers, and an annotation box; the panel
    lists assumptions (all three sources), out-of-scope, and open notes.
  files_touched: [designloop/web/canvas.mjs, designloop/web/app.css, designloop/src/server.mjs,
                  designloop/src/registry.mjs, designloop/src/store.mjs]
  verification_command: 'npm --prefix designloop test'
  verification_kind: manual
  status: done
  evidence: |
    Driven in real Chrome against a throwaway design (created, exercised, deleted):
    clicking A3 showed "NEW: the agent re-reads the flagged nodes · box in chart A", then
    "decided by Q1 … answered (a) the agent re-reads it next round" (Q55=a — the question AND the
    answer). A node note and an edge note saved through POST /annotate and came back on reload; the
    annotated node grew an orange dot, the annotated edge turned orange. The panel read
    Assumptions 3 — tagged `agent` (from ASSUMPTIONS.md), `defaulted` (Q2, Enter), `not relevant`
    (Q4), visually distinguished exactly as Q116=a asks — Out of scope 1 (Q4, derived from its
    section heading), Open notes 3 (node, edge, and the note left on an answer).
  notes: >
    Out-of-scope and open-notes have no authored source anywhere in the design, so both are derived
    best-effort and recorded in ASSUMPTIONS.md. `GET /review` is a new route: §4.8 can write an
    annotation but has no way to read one back.

- id: S14
  description: >
    Approval, Confirm, versions (implements F10, F11, G1–G3, Q59–Q62, Q65, Q71, Q72, Q115).
    Disapproval flagging, Confirm freezing versions/NNN/ including layout AND collapse state,
    node-level diff, generated DESIGN.md + transcript + changelog, SVG/PNG export, Review again.
  files_touched: [designloop/src/versions.mjs, designloop/src/server.mjs, designloop/src/store.mjs,
                  designloop/web/canvas.mjs, designloop/test/versions.test.mjs, designloop/test/api.test.mjs]
  verification_command: 'npm --prefix designloop test'
  verification_kind: manual
  status: done
  evidence: |
    THE S14 GATE — two Confirms, a diff that names exactly what changed, and version 1 reopening
    with its collapse state. Driven in real Chrome on the throwaway design:
      Confirm → versions/001/ holding DESIGN.md annotations.json answers.json changelog.md
                graph.json layout.json transcript.md; layout.json carried
                {"engine":"layered-v1", positions…, "collapsed":["B"], "viewport":{x,y,zoom:1.0618}}
      edited the document (A4 relabelled, A6 added), Confirm → versions/002/, 001 byte-identical
      Diff v1→v2  "1 added · 2 changed · 0 removed · +A6 · ~A4 (label, edges) · ~A5 (edges)"
      reopened v1 → A6 absent, A4's OLD label, chart B collapsed, A1 back at exactly (161,68),
                    zoom 106 %, actions disabled, "Version 1, frozen" banner
    Export SVG wrote a 21 KB file with the stylesheet embedded, the viewBox at content bounds and
    all 11 nodes; the PNG pipeline was run in-page and produced a 69 KB data URL (Chrome refuses the
    second automatic download, which is browser policy, not a defect).
  notes: >
    Q59's written answer is DISapproval flagging, not per-node approval, so `annotations.json` gains
    a `flagged` map beside §4.5's `approved`; unflagged means "not objected to", deliberately weaker
    than approved, and nothing gates Confirm (Q60=a). Q72=a needed `transcript.md`, which §4.7 does
    not list. Both in ASSUMPTIONS.md.

- id: S15
  description: >
    The gap surface (implements J8–J17, Q86–Q97b). src/gaps.mjs reads gaps/*.md as draft questions
    through the SAME grammar; the index badges open and closed; a SCOPED round asks only the open
    gaps; plan steps citing what an open gap puts in question are reported stale; closed gaps are
    kept with their resolutions; an assumption can be promoted to a gap from the canvas.
  files_touched: [designloop/src/gaps.mjs, designloop/src/grammar.mjs, designloop/src/registry.mjs,
                  designloop/src/server.mjs, designloop/web/gaps.html, designloop/web/gaps.mjs,
                  designloop/web/index.mjs, designloop/web/question.mjs, designloop/web/canvas.mjs,
                  designloop/web/app.css, designloop/test/gaps.test.mjs, designloop/test/api.test.mjs]
  verification_command: 'npm --prefix designloop test'
  verification_kind: manual
  status: done
  evidence: |
    THE S15 GATE — "a hand-written gap file appears as a badge and generates a one-question scoped
    round." Driven in the Browser pane against a throwaway design (created, exercised, deleted):
      index card    "1 open gap  1 closed"  + a link reading "answer 1 open gap"
      gaps.html     the open gap with all four report paragraphs, both options with their
                    consequences and (b) marked recommended, its blast radius; the CLOSED one with
                    its resolution quoted; "2 plan steps are stale … S1 — GAP-001, nodes A2 ·
                    S2 — GAP-001, nodes A3 · named in the blast radius"
      scoped round  question.html?…&scope=gaps opened at GAP-001 with the report on the screen
                    beside it, and answering (b) wrote {"state":"done","reason":"gaps_answered"}
                    with the answer in answers.json/answers.log under the key GAP-001
      the gap file  byte-identical afterwards — an answer does not close a gap
      promotion     "I want a say in this" on a `not relevant` assumption filed GAP-003, open, with
                    NO options, and S2 (which cites Q1) went stale on the spot
    14 new tests (12 in gaps.test.mjs, 2 over HTTP), suite 104 → 118, then 119 with the review fix.
  notes: >
    One real defect found by driving it: ending a scoped round made the MAIN question screen show
    "that is everything for now", because it reads owner.state. `gaps_answered` is now excluded
    there — Q88b=a parks only the affected thread, and the questionnaire carries on where it was.
    Five assumptions recorded, the load-bearing one being that a gap's answer lands in the ordinary
    answers.json under the gap's own ID rather than in a second file with a second recovery
    contract. Stale steps are computed and REPORTED, never written into PLAN.md.

- id: S16
  description: >
    Migrate Spotlight for real (implements Q104). Move solatro/SPOTLIGHT_DESIGN.md to
    solatro/design/spotlight/DESIGN.md, change meta.json's "doc" to "DESIGN.md", and answer it.
  files_touched: [solatro/design/spotlight/DESIGN.md, solatro/design/spotlight/meta.json,
                  designloop/test/grammar.test.mjs, designloop/test/graph.test.mjs,
                  designloop/test/layout.test.mjs, designloop/test/versions.test.mjs,
                  designloop/src/grammar.mjs]
  verification_command: 'npm --prefix designloop run check -- solatro/spotlight charts'
  verification_kind: manual
  status: done
  evidence: |
    THE S16 GATE — answerable end to end from the new path, with the document untouched.
    sha1 68c348dbe38262be6c2af49042321a9085eb3471 before the move and after it.
      run check   195 live, 1 retired · 8 ⚑gate, 39 notes · opens at QR1 · longest 194
                  14 charts, 176 nodes, 182 edges · 0 errors · 1 warning (QR8, GAP-001)
      in the page opened at QR1, answered it (a), then Q9 Q10 Q11 Q13 Q14 Q15 — all `[QR1=a]`
                  History listed all seven; clicking QR1 reopened it with (a) selected and the
                  "you are looking at an answer you already gave" banner
                  changing it to (b) → "This makes 6 of your answers irrelevant", naming
                  Q9 Q10 Q11 Q13 Q14 Q15 BEFORE applying
                  Continue → all six inactive, kept · re-answering (a) → "6 earlier answers came
                  back", Q11 intact as chosen/(a) "`on_active`, the existing one"
  notes: >
    The acceptance run's own answers were DELETED afterwards (answers.json, answers.log,
    status.owner.json) — they were the agent's, not the owner's, and the design had none before.
    The document is paused and unapproved; it is left exactly as the owner left it.
    Everything in the repo that pointed at the old top-level path was repointed (tests, the
    grammar module's header, CLAUDE.md, .claude/memory/) EXCEPT the design records that describe
    the move as a decision — DESIGN.md, PLAN.md and gaps/GAP-001.md say "moved from
    SPOTLIGHT_DESIGN.md" and are still true; a gap is never edited.

- id: S17
  description: >
    Docs pass (project rule). designloop/README.md, the flowchart-design skill's handover updated
    with the gap surface and the scoped round, and .claude/memory/ brought up to date.
  files_touched: [designloop/README.md, .claude/skills/flowchart-design/SKILL.md, CLAUDE.md,
                  .claude/memory/MEMORY.md, .claude/memory/designloop-tool.md,
                  .claude/memory/solatro-spotlight-design.md, .claude/memory/repo-claude-tooling.md,
                  designloop/HANDOFF_designloop.md]
  verification_command: 'npm --prefix designloop test'
  verification_kind: manual
  status: done
  evidence: |
    README.md covers: how to start it, all five screens with their URLs, the directory shape with
    who writes each file, the two rules (markdown IS the questionnaire; an answer is on disk before
    the next question appears), the gap loop, and that the tool is OPTIONAL — the markdown is still
    answerable by ID in chat with the server down. SKILL.md's "closing the loop" now names the
    concrete surface (badge, scoped-round URL, stale steps, `gaps_answered`, the promote button)
    and the three things a gap file must get right for them to work; its step 3 lists gaps.html and
    step 5 covers both special endings. CLAUDE.md points designloop/ at README.md and tells the
    design workflow how to hand over. Memory updated in the REPO copy (.claude/memory/), per the
    memory rule at the head of CLAUDE.md.
  notes: >
    No ARCHITECTURE.md was written: PLAN.md §4–§7 already hold the file formats, the grammar, the
    mermaid subset and the module APIs, and a second copy of a contract is the drift this project
    keeps warning about. The README points at them instead.

- id: S18
  description: >
    The owner's review of the built canvas and question screen (2026-08-02), from screenshots.
    Seven defects reported: a duplicated "asked because" reason, markdown printed raw in the side
    panel, truncated chart names, chrome that cannot be folded away, no way to tell which nodes
    trace back to a question or what the unanswered default is, colliding edge labels, and a
    whole-graph view with no connections in it.
  files_touched: [designloop/src/grammar.mjs, designloop/web/md.mjs, designloop/web/canvas.mjs,
                  designloop/web/canvas.html, designloop/web/question.mjs, designloop/web/gaps.mjs,
                  designloop/web/app.css, designloop/test/grammar.test.mjs,
                  designloop/design/designloop/gaps/GAP-002.md]
  verification_command: 'npm --prefix designloop test'
  verification_kind: manual
  status: done
  evidence: |
    SIX FIXED, ONE FILED AS A GAP. Driven in the Browser pane on a throwaway design, then LOOKED AT
    in real Chrome (project rule 4) on designloop's own chart B — the chart the owner screenshotted:
      asked because   ONE row for QR1, not two. `andGates` collapses an atom repeated by a section
                      gate; a grammar test pins it, and the gate still prunes.
      markdown        `web/md.mjs` is now the ONE renderer, imported by all three screens. The
                      panel reads "A `- **Qn**` bullet with no backticked gate" with the code span
                      monospaced and the phrase bold, not as asterisks. Swept the project: node
                      labels and chart titles carry no markdown in either real document (0 and 0),
                      so the SVG needs none — the panel was the only raw site.
      chart names     wrap in full: "C reachability (what makes a question disappear)",
                      "J execution hits design space the plan does not cover", + a tooltip.
      chrome          1 / 2 / 3 fold the picker, panel and toolbar; f folds all three. Measured:
                      the stage went 295 → 412 → 589 px as they folded, the handles stayed on
                      screen, and `f` brought everything back.
      traceability    a chip under each node names its questions (B5 Q28, B6 Q11, B7 Q26), blue
                      while any is unanswered, with a tooltip naming each one's state; the detail
                      panel adds "not answered yet — recommended (a) ship the seam now" and an
                      "answer it" link that opens that question (`question.html?key=…#Q1`); a node
                      no question names says so rather than showing nothing.
      edge labels     chart B's five-way fan-out: 11 labels, 0 overlapping pairs, 2 ties drawn back
                      to their own edge. Read every label in the screenshot.
  notes: >
    The seventh is GAP-002, open: the whole-graph view has nothing to connect. Measured — 0
    cross-chart edges in either document (133 and 182 edges), against 12 node labels that name
    another chart in prose ("— chart B"). Whether a prose reference becomes a drawn link changes
    graph.json, which §4.6 specifies and an implementation agent consumes, so it is an owner call
    and is parked. Nothing else in the review depended on it.
```

## Verified vs assumed

| Claim | How it is known |
|---|---|
| The whole suite is green | `npm --prefix designloop test` → `tests 151 / pass 151 / fail 0`, run after the last edit (2026-08-04) |
| **The provenance audits find the defect that motivated them** | `test/provenance.test.mjs` reduces the solatro/spotlight incident to its smallest form and asserts each report on it, and the last test runs all three against the real Spotlight documents. `npm run check -- solatro/spotlight` reports 22 answers given in prose, 16 documents paraphrasing one, and 0 unauthorised contracts (7 blocks, all cited) |
| **The S19 screen changes work, and I LOOKED** | Driven in headless Edge over CDP against a throwaway copy of the design (never the owner's live round): the Enter mark reads `option c`, moves to `Use what I wrote` the moment the note box has text, and Enter then submits the written answer instead of discarding it. BACK walked four questions in reverse and then disabled itself with its reason. `h`, `i`, `w`, `n` all fire. The session chip was screenshotted **live**, **stopped** and **none** |
| **Not verified: physical keypresses** | Still dispatched `KeyboardEvent`s in the real page rather than OS input, same as before. The handlers are the real ones |
| **The derived cross-chart links are right, and I LOOKED** | Counts measured on both real documents (10 and 5, 0 unresolved) and pinned as a fixture. The canvas was screenshotted in headless Edge over CDP and described: expanded, collapsed, and the picker. **The first bow was wrong and only the picture said so** — collapsed charts shelf-pack into one row, so a bow proportional to the vertical drop was flat and the links lay along the row through the boxes. Fixed to a perpendicular bow, re-shot, and the arcs now pass clear |
| **How to screenshot without the Browser pane** | **`designloop/tools/shot.mjs`** — headless Edge with `--remote-debugging-port`, driven over CDP with Node's built-in `WebSocket`, runs a JS snippet first (so the shot can be of the *collapsed* canvas, or of the picker) and writes a real PNG. No dependencies. `msedge --screenshot` on its own only ever captures the initial state, which is useless for a canvas whose interesting states are behind a click |
| The Spotlight document parses AND ingests unchanged, from its NEW path | `npm --prefix designloop run check -- solatro/spotlight charts` → 195 live + 1 retired, 14 charts / 176 nodes / 182 edges, 0 errors, 1 warning (QR8); `sha1sum` is `68c348db…` both before the move and after it |
| The gap surface does what S15 asks | Driven in the Browser pane against a throwaway design: badge → gaps page → scoped round → `gaps_answered` → promotion. Quoted in S15's evidence, and the gap file was byte-identical afterwards |
| A crash between log and materialise is survivable | The S4 test simulates the exact window (append + fsync, no materialise) and asserts the stale file first, then the recovery — not an inferred property |
| The watch wakes in under a second | Asserted numerically in the test, and observed by hand against the real design |
| The UI behaves as S5–S8 require | Driven in the Browser pane and read back with `get_page_text` / DOM queries; every claim above quotes what the page actually said |
| The layout is fast and deterministic at 176 nodes | Measured, 1.8 ms best of 10, and asserted byte-identical across runs — not "should be fine" |
| **How the canvas LOOKS — verified** | Screenshotted in real Chrome and described in S12/S13's evidence. Three defects were found that way and fixed. The question screens (S5–S8), the gaps page and the scoped round are still text-verified only; nobody has looked at their pixels |
| **Not verified: OS-level keyboard input** | Real key events do not reach a non-displayed pane. The handlers were exercised with dispatched `KeyboardEvent`s in the real page, which runs the same code (arrows moved the selection A1→A2→A3→A4, `s` switched colour mode, `c` collapsed, `/` focused search, Enter jumped to B4 and expanded the chart it was in), but a physical keypress has not been tried |
| **Not verified: a second design's charts** | Only the two real documents were ingested. Both are written by the same hand, so the subset is proven against this repo's dialect of mermaid, not against mermaid |

## Open bugs

None known. Seven real defects were found and fixed across the three runs, each noted in its task:
`listenFrom` returning the requested rather than the bound port (`src/server.mjs`), the focus-ring
modulo never leaving -1 (`web/question.mjs`), the Windows replacing-rename EPERM under the watch
(`src/store.mjs`), status colours overpainting chart colours, the canvas swallowing Ctrl-modified
keys, disabled buttons that looked enabled (all `web/canvas.mjs` / `web/app.css`), and the end of a
scoped gap round making the MAIN question screen claim the questionnaire was over
(`web/question.mjs`).

## Open gaps

**None.** Both filed gaps are closed, in place, with their resolutions.

**GAP-002 — resolved 2026-08-02, the owner chose (b): derive the cross-chart links.** It was
answered in the tool's own scoped gap round (`question.html?key=designloop/designloop&scope=gaps`),
which is the first time the gap loop ran on real work rather than on a throwaway design. What it
turned into, so nobody re-derives it:

- **`src/graph.mjs` derives them at ingestion.** A node label naming another chart becomes a link
  from that node to that **chart** — not to a node inside it, because the label named a chart and
  picking an endpoint would invent structure the document does not have.
- **`graph.json` grows a `links` list beside `edges`** (PLAN §4.6), deliberately separate: an edge
  was drawn by the author, a link was inferred from a label, and a consumer that cannot tell them
  apart asserts a connection the document never made. Key is `FROM~>TOCHART`, so it can never
  collide with an edge key.
- **The rule is PLAN §6.1**, and it resolves a name **the way a reader does — by the name the
  document uses, before the chart ID.** This is the one that bites: Spotlight's §7 holds two
  charts, so from there on every chart ID is one letter ahead of the heading naming it, and
  `K14 "see chart H"` means the chart with `I`-prefixed nodes. ID-first gives a wrong link.
- **Nothing is guessed.** Unresolved → a warning naming the line (GAP-001's rule, same class of
  defect); same-chart → dropped silently (chart E says "chart E2" about its own node, which is
  correct authoring); repeated in one label → deduped.
- **The canvas draws them dashed, purple, node-to-chart**, under the nodes, hidden in the
  single-chart picker view, with a `links: shown (N)` toggle (`l`). A collapsed chart keeps its
  links (F8).
- **Measured, and pinned as a fixture** in PLAN §6.1 and `test/graph.test.mjs`: **10** links here,
  **5** in Spotlight, 0 unresolved in either, and neither document was edited to make it so.

Design version 3 (`DESIGN.md` §14) records the round; S11, S12 and S14 in `PLAN.md` are re-derived
and marked as such.

`designloop/design/designloop/gaps/GAP-001.md` is `status: resolved` — the owner
chose **(b)**: a ⚑gate option with no `→ next:` is a **warning**, not a parse error. What that
turned into, so nobody re-derives it:

- `parseQuestionLine` warns by default; `strict: true` still throws, which is what PLAN §5.6's
  must-throw case exercises.
- The warning reaches the authoring agent through `run check` **and** through a badge on the
  design's card in the index (`registry.docHealth` → `GET /api/designs` → `web/index.mjs`).
- The question screen renders **`→ next: not described`** on an option with no preview. Rendering
  nothing would have been indistinguishable from "no questions follow this branch".
- `.claude/skills/flowchart-design/SKILL.md` states the rule for future authoring.
- The Spotlight document was **not** edited. QR8 is the one live warning in the repo.

The gap file is kept with its resolution (Q96b=a) — it is not deleted. As of S15 it is also
**visible**: `web/gaps.html?key=designloop/designloop` shows it closed, with its resolution and the
options it offered, which is what "kept" was supposed to mean.

## Files touched

```
 M CLAUDE.md                                           designloop/ → README.md; how to hand over
 M .claude/skills/flowchart-design/SKILL.md            S10 handover, the GAP-001 authoring rule,
                                                       the §6 subset, and S15's gap surface
 M .claude/memory/  MEMORY.md designloop-tool.md solatro-spotlight-design.md repo-claude-tooling.md
 M designloop/design/designloop/ASSUMPTIONS.md         25 assumptions, each with why it is reversible
 M designloop/design/designloop/gaps/GAP-001.md        resolved (b), with what it became
 D solatro/SPOTLIGHT_DESIGN.md                         ─┐ S16: one move, zero content change.
?? solatro/design/spotlight/DESIGN.md                   ─┘ GitHub Desktop shows it as a rename.
 M solatro/design/spotlight/meta.json                  "doc": "DESIGN.md"
?? designloop/README.md
?? designloop/package.json  designloop/start.cmd
?? designloop/src/          grammar graph gaps layout store registry versions server watch check
?? designloop/test/         grammar graph gaps layout store versions api server watch
?? designloop/web/          index question canvas gaps (.html/.mjs) + app.css
?? solatro/design/spotlight/graph.json  ui_meta.json
```

`solatro/design/spotlight/DESIGN.md` is byte-identical to the `SPOTLIGHT_DESIGN.md` it came from,
and that is a requirement, not an accident. `graph.json` is generated from it and is rewritten
whenever its hash moves.

## Next up

**Nothing in this stream.** All 19 steps are done plus S20 below, and the owner is already *using*
it — Spotlight's phase 1 shipped against it, so the next job is that design, not this tool.

⚠ **S20 — PROVENANCE (added 2026-08-04, after Spotlight phase 1 cost a round to a misreading).**
`src/provenance.mjs` + `⚑contract` in the grammar + `GET /provenance` + two new `check`
subcommands. The incident is written at the head of the module and it is worth reading before
touching any of it: **one free-text answer, two documents paraphrasing it, both dropping the clause
that settled it, and an executing agent filing a gap on the difference between the paraphrases.**
The reports are `in prose`, `unquoted` and `contracts`; like every other audit here, none of them
blocks. **2026-08-06 (review pass):** the ID scanner now matches GAP ids too — gap answers are
free-text by construction and were invisible to every report, silently — and `quoteAudit` hoists
its per-document work (was O(answers × doc bytes), ~700 ms on Spotlight per request; report counts
may shift as gap citations now register. ⚠ **What is NOT built: the canvas has no contracts panel.** The owner reviews flowcharts;
`PLAN.md` §1 — which is what an executor actually obeys — is still reviewed only by being read in
chat. `GET /provenance` serves the data a panel would need. `.claude/skills/flowchart-design/`
§8b item 9 carries the process half in the meantime.

1. **`solatro/design/spotlight/` is IN PROGRESS.** The owner began answering it on 2026-08-03 and
   was ~47 answers in. Do not reset it, do not answer it, and do not delete its `answers.*`. Park
   on `npm --prefix designloop run watch -- solatro/spotlight` — and note that parking is now
   *visible to them*: the screen's chip goes green while a watch is beating.
2. **Fix QR8** while doing that: it is the one live authoring warning in the repo (its option (a)
   carries no `→ next:`), and it shows on the index card until it is gone.
3. **The gaps page and the scoped round have still never been looked at.** S18 reviewed the canvas
   and S19 the question screen, and both found things no test would have. These two are the
   remaining screens that have only ever been read as text —
   `node designloop/tools/shot.mjs` makes that cheap now.
4. ⚠ **When editing `src/`, the owner's own server does not reload.** They run one from
   `start.cmd`; it keeps the code it started with. `web/` changes reach them on a page reload.
   Never restart or kill their server to make a change land — say so and let them.

### Copy-paste opening prompt for the next agent

```
The Design Loop tool (designloop/) is FINISHED — all 17 steps of
designloop/design/designloop/PLAN.md, npm --prefix designloop test green at 119/119, GAP-002 open (the whole-graph view has no cross-chart connections).
Read designloop/README.md first; designloop/HANDOFF_designloop.md is the build's live state and
stands alone if you need the history.

If you are here to WORK ON THE TOOL: PLAN.md §4–§7 are NORMATIVE — the file formats, the question
grammar, the mermaid subset and the module APIs are specified, not suggested. DESIGN.md beside it
is the authority on behaviour; where the two disagree the design wins and the plan is wrong (that
decided Q52 and Q59 in Phase 3 — read the owner's written answers in DESIGN.md §9, not the plan's
summary of them). Follow the gap protocol at the head of the plan: a decision the plan does not
cover is a gap file, not an invention. The tool now shows those gaps itself.

If you are here to USE it, that is the more likely job: solatro/design/spotlight/ is the owner's
paused Spotlight design, moved into place by S16 and never edited. Start the server, hand over
http://localhost:5273/web/question.html?key=solatro/spotlight, and park on
npm --prefix designloop run watch -- solatro/spotlight. .claude/skills/flowchart-design/SKILL.md
is the procedure end to end.

Environment facts that cost time twice: the Browser pane is not displayed, so screenshots fail
there and OS key events do not reach the page — verify with read_page/get_page_text and dispatch
KeyboardEvents through javascript_tool. To actually LOOK at something, run
`node designloop/tools/shot.mjs <url> <out.png> [w] [h] ["js first"]` and Read the PNG: headless
Edge over CDP, a JS snippet run before the shot, no dependencies. The Node server has no hot
reload, so preview_stop + preview_start after any src/ edit; editing web/ only needs a page reload.

Keep this handoff updated after every task. Do not git add or commit.
```

## References

- `designloop/README.md` — what the tool is, how to start it, every screen and every file, and the
  gap loop. The entry point for anyone who is not resuming this build.
- `designloop/design/designloop/PLAN.md` — the build document; §3 the steps, §4 the interchange
  contracts, §5 the grammar, §6 the mermaid subset, §7 the module APIs.
- `designloop/src/graph.mjs` — the mermaid subset, with the reason for every refusal in the header.
- `designloop/src/gaps.mjs` — the gap file format, read as a draft question, and the stale-step
  computation, with why nothing is ever written back to a gap or to a plan.
- `designloop/src/layout.mjs` — the layout engine and its metrics; `ENGINE` is what a frozen
  version records so a later change cannot silently re-flow it.
- `designloop/src/versions.mjs` — Confirm, the freeze, the diff, and the generated renders.
- `designloop/design/designloop/DESIGN.md` — the authority on behaviour; charts A–J, §9/§12 the
  questionnaire and its answers of record.
- `designloop/design/designloop/ASSUMPTIONS.md` — every decision taken that the design did not
  cover, with why each is reversible.
- `.claude/skills/flowchart-design/SKILL.md` — the authoring rules, the gap protocol and its
  template, the handover procedure (S10) and the gap surface it drives (S15).
- `solatro/design/spotlight/DESIGN.md` — the acceptance corpus, and the first real client. Paused,
  unapproved, and never edited by this build. Was `solatro/SPOTLIGHT_DESIGN.md` until S16.
- `palette/tools/serve.mjs` — the dependency-free local server this one is modelled on.

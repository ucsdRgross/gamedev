Session 1 is running. Here are the rest.

| # | Session | Effort | Blocked by |
|---|---|---|---|
| 1 | Phases 0–2 — server, grammar, store, question UI, watch | medium | *(running)* |
| 2 | Phase 3 — the canvas + close GAP-001 | **high** | 1 |
| 3 | Phase 4 — gap surface, Spotlight migration, docs | medium | 2 |
| 4 | Spotlight design review → plan + its own handoff prompt | **high** | 3 |
| 5 | Spotlight implementation | TBD | 4 generates this prompt |

## Session 2 — Phase 3, the canvas — **high effort**

```
Read CLAUDE.md at the repo root first - it carries the hard rules and points at .claude/memory/,
which is where this repo's memory lives (the per-user memory directory may be empty on this
machine; the repo copy is authoritative).

Implement designloop/design/designloop/PLAN.md, Phase 3 only (steps S11-S14). Stop at S14.
Resume state is designloop/HANDOFF_designloop.md - read it; S1-S10 are already built and green.

First, close GAP-001 (design/designloop/gaps/GAP-001.md): the owner chose option (b) - a gate
option missing its "next:" preview is a WARNING, not an error. Make that the default in
parseQuestionLine, keep the strict flag so the 5.6 throw-test still passes, surface warnings to
the authoring agent and on the design's index card, and decide what the question screen renders
for a gate option with no preview (blast radius names S5). Set the gap to status: resolved with
the chosen option and the date. Do not delete it.

Then Phase 3. PLAN.md is self-contained; DESIGN.md beside it is the authority on behaviour.
Sections 4-7 are normative - graph.json's shape (4.6), versions/NNN/ and layout.json (4.7), the
API (4.8), the mermaid subset (6) and the graph.mjs API (7) are specified, not suggestions.

Hard gate: S11 is not done until all 14 mermaid charts in solatro/SPOTLIGHT_DESIGN.md and all 10
in design/designloop/DESIGN.md ingest with zero unknown constructs - 24 real charts. Anything
outside the subset in section 6 must throw naming the file and line, never guess.

Layout: try a hand-rolled layered layout first and measure it at Spotlight's ~200 nodes. Adding
an npm dependency to a zero-dependency project is a GAP, not a free choice - file it rather than
deciding it.

Confirm must freeze layout AND collapse state (Q115=b), so reopening a version restores exactly
what was on screen.

Verify with `npm --prefix designloop test` and by driving the canvas through the Browser pane
(launch config "designloop"). Screenshot the Spotlight graph and describe what it actually shows
before calling S12 done - never claim a visual works without looking at it.

Follow the gap protocol at the head of PLAN.md. Use /handoff to keep resumable state.
```

## Session 3 — Phase 4, completes the tool — **medium effort**

```
Read CLAUDE.md at the repo root first - hard rules, and .claude/memory/ is where this repo's
memory lives (authoritative over any machine-local copy).

Implement designloop/design/designloop/PLAN.md, Phase 4 (steps S15-S17). This completes the tool.
Read designloop/HANDOFF_designloop.md for current state.

PLAN.md is self-contained; DESIGN.md beside it is the authority on behaviour. Sections 4-7 are
normative.

S15 - the gap surface: read gaps/*.md, badge the index (Q89b=c), build a SCOPED round from a
gap's own options, mark plan steps citing changed nodes as stale, keep closed gaps with their
resolutions.

S16 - migrate Spotlight for real: move solatro/SPOTLIGHT_DESIGN.md to
solatro/design/spotlight/DESIGN.md and change meta.json's "doc" to "DESIGN.md". A meta.json
already exists pointing at the old path (see ASSUMPTIONS.md, S3/Q104). Do NOT edit the document's
content to make anything parse - if it does not parse, the grammar is wrong. Preserve the
existing answers.json / answers.log / status.owner.json / ui_meta.json.

Hard gate: after the move, Spotlight's questionnaire is answerable end to end - open it in the
Browser pane, answer several questions including a gate, go back, change the gate answer, and
confirm the stranding warning and the restore both work.

S17 - docs: designloop/README.md, update .claude/skills/flowchart-design/SKILL.md with the
concrete handover (where to write a design, how to start the server, what URL to hand over), and
note that the markdown workflow still works with the tool absent. Update .claude/memory/ (the
in-repo copy) with anything a future session cannot re-derive.

Follow the gap protocol at the head of PLAN.md. Use /handoff to keep resumable state.
```

## Session 4 — Spotlight design review → its own handoff — **high effort**

```
Read CLAUDE.md at the repo root first - hard rules, and .claude/memory/ is where this repo's
memory lives (authoritative over any machine-local copy).

Resume the Solatro Spotlight design review using the Design Loop tool.

Read solatro/design/spotlight/DESIGN.md (the design, paused since 2026-08-01) and
.claude/skills/flowchart-design/SKILL.md (the workflow you are running).

Start the designloop server and give me the URL for the spotlight design. Then park on
`npm --prefix designloop run watch -- solatro/spotlight` until I finish a round.

When a round ends: read the answers, and either author follow-up questions in the strict grammar
(SKILL.md) or finalise. Free text at a gate ends a round early and means I want a branch that
does not exist - author it and put me back on that same question.

When no reachable questions remain, do NOT jump to an implementation plan. Follow Step 8 of the
skill: finalise the flowcharts, present them, tell me what my answers changed, and ASK me to
confirm. Only after I confirm do you write the implementation plan.

The plan must be the last document needed to build it - schemas, formal specs, module APIs,
per-step done-when, and hard self-checking acceptance gates. Run the Step 8b readiness checklist,
including grepping that every path it references exists. End with a copy-paste handoff prompt and
a recommended effort level.

Spotlight touches the FX layer: read solatro/VFX.md and ARCHITECTURE_REVIEW.md 4g before writing
the plan.
```

**Session 5** (Spotlight implementation) is written *by* session 4 — its scope depends on which of the 188 answers you give.
---
name: built-but-not-wired
description: "Components ship with passing tests and no caller; a done-when must name the call site"
metadata:
  type: feedback
---

The most common way finished work does nothing: a class, signal, knob or method is built, unit
tested, and **never called**. One run shipped a gesture tracker with no caller, an info card mounted
nowhere, four input actions no code read, five settings knobs nothing consumed, and a layout tool
editing a resource the game never loaded — every one with green tests.

**Cause:** a step's done-when is usually unit-shaped ("TestX is green"), and an implementer optimises
to the done-when it is handed. Nothing says "and something calls it".

**Fixes:**
- Every step brief names the **CALL SITE**: where is this invoked from, and what breaks if it is
  deleted? Require a test that fails when the wiring is removed.
- Never accept `done` on a component whose consumer does not exist.
- Audit registries (identifier lists, signal tables, settings keys) **directly against the
  implementation**, not against the test plan — a test plan only covers what someone thought to row.
  See [[design-answers-need-a-claimant]] for the design-side version of the same check.
- **A knob nothing reads is a defect**, not a placeholder.

Reading code for contract conformance does not catch this either. Tracing what a user actually does —
alt-tab, resize, press Escape, click twice — does.

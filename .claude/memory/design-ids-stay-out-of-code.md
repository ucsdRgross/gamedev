---
name: design-ids-stay-out-of-code
description: "A design-process id (Q183=a, GAP-017=c, S34, PLAN.md §1.8) never appears in code — least of all in a user-facing string; state the RULE the answer produced and let the design docs keep the provenance"
metadata:
  node_type: memory
  type: feedback
---

**The design conversation and the code are different layers. Ids do not cross.**

`Q183=a`, `GAP-017=c`, `S34`, `J2/Q128`, `PLAN.md §1.10`, `ASSUMPTIONS.md` — each names a document
the code's reader cannot see and which the code outlives. A comment citing one carries **no rule at
all**: the reader must go find the answer to learn what the code must do.

```gdscript
# NO
@export_group("Transition preview (Q183=a)")
## Q48=b: the "fit" zoom — MIN of the two axis ratios (see ASSUMPTIONS.md, PLAN.md §1.10).

# YES
@export_group("Transition preview")
## The "fit" zoom — MIN of the two axis ratios — at which a window centred on the midpoint
## contains both frames plus a margin.
```

⚠ **In a `##` doc comment on an `@export`, or in any string literal, this is a LAYERING BREACH, not
a style nit.** Godot renders `##` as the Inspector tooltip and `@export_group("…")` as the heading,
so `Content mode (GAP-017=c)` is a *heading on screen* for someone with no way to look it up.
Measured on the picture-wall run: three group labels and every "Picture wall" tooltip shipped
carrying question ids.

**One exemption: TEST ASSERTION MESSAGES.** A failing check naming the answer it defends says which
decision just broke, and nobody outside the suite reads one.

**Why it happened, which matters more than the rule:** [[design-answers-need-a-claimant]] presses
hard on binding every answer to something mechanical. Citing the id *in the code* looks like
compliance and is not — the claim belongs in `PLAN.md`'s `(implements …)` line and the step report,
where the checker reads it. **Traceability lives in the plan; the code carries behaviour.**

**Same instinct, same pass:** those comments also narrate how the code got here. Keep the ⚠ and the
measured number when they stop the next reader repeating the mistake; drop the plot, the step id and
who found it. See [[code-style-lean-documented]].

**How to apply:**

1. `py .claude/tools/doc_check.py --changed` ERRORS on a design id in a comment or a string literal
   (tests exempt for strings; `designloop/` exempt entirely — ids are its subject matter). The full
   run summarises the standing backlog. The `Stop` hook runs `--changed --warn-only`, so it reports
   without blocking.
2. Reaching for an id while writing a comment? That is the moment to ask **what the answer decided**
   and write that sentence instead.
3. Reviewing a plan run: grep the diff for `Q\d`/`GAP-\d{3}` before accepting a step.

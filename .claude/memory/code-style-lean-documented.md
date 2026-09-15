---
name: code-style-lean-documented
description: "Delete unused code, reuse before writing, and a comment says only WHY a method exists — at column 0, never trailing, capped short; plans end with a references section"
metadata:
  node_type: memory
  type: feedback
---

Keep lines of code low by REMOVING old unused code outright — no dormant paths. Plans end with a
references/sources section for easy handoff.

⚠⚠ **COMMENTS ARE A CODE SMELL.** Owner rule, verbatim: *"comments dont exist inline of methods,
and only explains why the methods exists and nothing else. no historical stuff or what method does
since that can be read through the code."* Three rules follow, and `doc_check --changed` errors on
all three:

1. **No comment may have whitespace before it** — a plain `#` sits at column 0, above the method.
2. **No comment may share a line with code.**
3. **A `#` block is at most 3 lines; a `##` doc comment is at most 1.** `##` is the label Godot
   renders beside an exported knob in the Inspector, so it lives wherever its knob does — indented
   or not — and pays for that freedom with the tighter cap.

If an inline comment feels necessary, the code needs a NAME (extract a well-named helper), not prose.

⚠ **A FILE YOU EDIT MUST LEAVE COMPLIANT, including comments you did not write** — whole-file on
touch is how the legacy backlog drains; never a repo-wide sweep.

A kept comment states the rule and its measured number, once, at the site that enforces it — the
wording rules are CLAUDE.md "Doc hygiene", and design ids are [[design-ids-stay-out-of-code]].

⚠ **REUSE BEFORE YOU WRITE. Owner, verbatim:** *"reducing duplicate code as much as possible
and no reinventing existing setups, or using existing engine methods when available."* The three
rules and their measured cost: `/plan-run` "Reduce complexity". `dup_check.py` and the commit gate
enforce the duplication half.

Commented-out code (owner ruling, `solatro/START_HERE.md`): replace it with a TODO if it describes
unimplemented logic, delete it outright if the implementation exists elsewhere. Handoff docs use
`/handoff`; deleting a doc follows `/docs` step 3.

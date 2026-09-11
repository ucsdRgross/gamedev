# The effect-review build — how to change it without breaking recorded answers

`../DESIGN.md` is GENERATED. `render.py` joins `corpus.tsv`, `batches/tagged*.tsv` (the
`mechanic_grid` blurbs, which win over corpus), `decisions/`, `variants/` and `generated/` into it.
Edit the sources, then re-render. Never edit `DESIGN.md` by hand.

## ⚠ The question id is positional

`render.py` numbers questions by walking rows sorted on (family, class, name). So:

- **Never rename an effect** — the name is the sort key, and a rename moves it.
- **Never delete a row** — retire it in place in `retired_questions.py`; it still renders.
- **New effects go in a family that sorts last**, so nothing before them moves.

`order_check.py` dumps `Qnnnn -> eid`; `fixkit.verify()` re-renders and diffs it against
`_order.baseline.tsv`, and fails if any pre-existing id moved.

## The tools

| file | what |
|---|---|
| `GAME_BRIEF.md` | the yardstick every effect is judged against — the live rules and the confirmed designs |
| `fixkit.py` | `patch()` prose across every source, `set_options()` for one question, `retire()` in place, `verify()` |
| `retire.py` | the vocabulary table that re-expressed retired architecture (act, Submit, round, blind, ante, tableau) |
| `retired_questions.py` | every retired question and why, keyed by eid |
| `review_batch.py` | lists unjudged questions by family and holds the verdicts |
| `_verdicts.tsv` | one verdict per question, with the reason and what was done |
| `AUDIT_PROMPT.md` | the instructions an auditor follows, including every false positive earlier auditors made |
| `spot.py` | prints every question in a family matching a known damage shape, for the overseer's own pass |
| `record.py` | records a family's verdicts, OK unless adjudicated otherwise |

## House translations

- a multi-card **act** -> an **Entrance refill** (five cards); a per-act trigger -> a placement
- a **scoreless act** -> a scoreless refill, never a scoreless placement (that is the normal case)
- a **discard budget** -> **discard events**: effects discard cards from the board into a pile that
  persists to the next show. There is no player discard action or budget, but discards are real
- **"mark"** means the board plan's cell mark; other senses are "tag", "flag" or "claim"

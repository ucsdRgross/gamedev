# Architecture audit — instructions for one auditor

You are auditing a game-design questionnaire against the game's ACTUAL current rules.
**Read-only: do not edit any file.**

## Step 1 — read the yardstick, in full

`GAME_BRIEF.md`, in this same directory. Read its ⚠ warnings carefully; several exist
specifically to stop false positives that earlier auditors produced.

## Step 2 — list your families

From this directory run `py review_batch.py fam <F>` for each family you were given, and audit
every line each prints. A garbled character is only console encoding; ignore it.

## Step 3 — judge EVERY question printed. Do not sample. One verdict each

| verdict | when |
|---|---|
| `OK` | still fits the architecture |
| `STALE` | premise is a mechanic that no longer exists, or a wrong constant. Say WHICH phrase |
| `ALREADY` | proposes something the game already does BY DEFAULT. Say which shipped rule |
| `CONTRADICTS` | says something the live rules make IMPOSSIBLE — not merely overriding a default. Say which rule |
| `DUPLICATE` | same design space as another question. Name the other ID |
| `RESCOPE` | the idea survives but its options describe the wrong board. Say what needs re-expressing |
| `MISMATCH` | the options describe a genuinely UNRELATED effect from the question's own name and description (options copied from another card). NOT for variants or reinterpretations of the same idea |
| `UNSURE` | you genuinely cannot tell. Say the doubt |

### ⚠⚠ DO NOT FLAG — legal, and previous auditors wasted time on every one of these

- Any effect or rule card that **overrides a default**. "Lines never wrap", "a placed card cannot
  move", "lines are 5 cells", "the grid is never cleared" are DEFAULTS an effect may change.
  Deliberately destroying, discarding, moving or shifting cards is fine.
- Deck-order language ("top of the deck"). The five stocks are one shuffle dealt round-robin; the
  deck still has an order.
- Changing the Entrance's width.
- Fire and Knife are suits.
- A skill keeping its own once-per-show flag.
- "A new hand" / "a new meld" — a meld type recognised when a line completes.
- Face-down cards on the grid (`CardData.flipped` exists; effects place them).
- Three options that are different MECHANISMS or strengths of the same idea.
- Points paid per distinct effect — the combo is a separate multiplier.
- Gold, shops, boosters, the map, towns, bosses and levels all exist.
- "per Entrance refill" / "each Entrance refill" — the house translation of a multi-card act (a
  refill delivers five cards). It is correct, not stale.
- Discards. Effects discard cards from the board into the discard pile, as a target or a side
  effect, and the pile persists to the next show. An effect about discard events or the pile is
  live; only a per-round discard BUDGET the player spends is stale.
- An effect that GRANTS a new player action (a discard, a swap, a peek) — granting is legal; only
  ASSUMING the action already exists is stale.

### ⚠ DO flag — the point of this audit

- **"act" was bulk-rewritten to "placement".** That is WRONG wherever an act held MANY cards. A
  placement places exactly ONE card, in ONE cell, ONE row, ONE column. Flag `STALE` any option now
  vacuous or impossible: "the first card you placed this placement", "if the first placement is a
  single card", "every row / every column / all five scored this placement", "N cards per
  placement", "cards played this placement", "after the first card each placement".
- **Timing clauses keyed to a placement are the easiest damage to miss.** Every line a placement
  completes scores INSIDE that placement, so "holds and pays when a placement finishes resolving" is
  a no-op, and "at each placement's start, name X" asks the player something before every single
  card. Those were per-ACT and now want "each Entrance refill". Read every "placement" twice.
- **"mark" now means the board plan's cell mark.** An option using "mark" for something else — a
  targeting tag, a flagged line — is RESCOPE so the word can be changed.
- There is no Next button and no Submit button; the buttons are End and Undo.
- **Standing owner rulings** in GAME_BRIEF.md: an effect that contradicts one is `CONTRADICTS`,
  naming the ruling. Overscore - raising future goals BECAUSE you scored well - is the main one.
- **The combo is per SHOW and never resets.** "this placement's combo", "the combo resets each
  placement" are stale.
- **Wrong constants:** grid 5x5, line 5 cells, stack scores at multiples of 5, grids unlock per 52
  deck cards, `grid_max_count` 3, five Entrance slots.
- A board deeper than five rows, a Submit, a held hand of cards, hand SELECTION ("select cards to
  play"), discards per round, an ante ladder, a show-end scoring pass or payout, or a premise that
  the board clears by itself.
- **ALREADY** — these are the shipped defaults: scoring is continuous and immediate; a placed card
  cannot normally be moved or stacked on; removing a card compacts its own stack vertically; the
  Entrance refills only when every slot is empty; the first placement commits the grid; diagonals
  already score; a complete line re-scores every time it is disturbed; the combo already rises with
  distinct triggers for the whole show. And the confirmed board plan: every cell is dealt a MARK at
  show start and a card agreeing with its mark on rank, suit, talent or hat pays — so an effect
  that assigns every cell a target card at show start is ALREADY the plan.

## Step 4 — output

ONLY tab-separated rows, one per question, no preamble, no markdown, no summary:

```
Q0123<TAB>K4<TAB>OK<TAB>
Q0124<TAB>K4<TAB>STALE<TAB>"rows 6 to 10" - a grid has five rows
```

Columns: question id, class code, verdict, note (empty for OK, short and specific otherwise).
Every question printed must appear exactly once.

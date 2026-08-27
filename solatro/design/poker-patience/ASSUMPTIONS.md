# Poker Patience — assumptions log

One line per reversible, clearly-within-intent decision the design did not spell out.
See the gap protocol in `PLAN.md` §0 — this is for (1), not (2)/(3).

- **BoardCoord.step** — beyond the last real grid, or before grid 0, the virtual continuation
  steps at the width of the nearest REAL edge grid (grid 0's width to the left, the last
  grid's width to the right), mirroring that one edge grid rather than, say, some fixed or
  averaged width. Reversible: nothing currently depends on a virtual block's width past
  "some grid-shaped continuation exists."

- **S4** — `Board.place_in_cell` / `move_to_cell` always land at the TOP of the destination
  cell (current stack size, i.e. `h+1` of whatever card is already there) and ignore
  `coord.h` on the way in, mirroring `Anchor.ON_TOP`'s "insert above whatever is there"
  rule from the legacy engine rather than trusting a caller-supplied height that could
  disagree with the stack's actual size. PLAN.md §1: "Reuses `Anchor.ON_TOP` for stacking."

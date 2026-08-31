---

## What this document deliberately does not contain

- **No flowcharts.** Charts redraw questions, and a chart of a thousand independent content
  rulings tells nobody anything. There is no review-canvas stage for this round.
- **No history and no reasoning.** Every effect is stated as trigger, action, number. Where an
  idea arrived with circus history, a Balatro joker name or a paragraph of why it would be fun,
  all of that was stripped. Provenance is kept as a source citation and nothing more.
- **No balance numbers you should trust.** The numbers in the options exist to make the three
  versions distinguishable from each other. Rarity, cost and tuning are a later pass, run against
  `Tools/scoring_sim.py`, not decided here.
- **No implementation.** No pseudocode, no class names, no file paths, no hooks named as
  contracts. An approved effect is a decision that it belongs in the game, not a spec.
- **No engine-capability audit.** The gate that normally precedes a first question round asks
  whether the engine already ships what a design proposes. It does not apply to a content
  selection round — nothing here is being built yet. **Each approved effect still needs that gate
  run against it before it is implemented**, and a cluster of approved effects sharing a mechanism
  should get one design pass between them rather than one each.
- **No family N.** View, camera and UI effects were excluded by your ruling. The taxonomy still
  carries the ten classes so the hole stays visible, and they can be a later round on their own.

## What happens when the round ends

Every answer becomes one row of a single CSV: the effect, the approved variant in full, its slot,
its class, its rarity band, its provenance, and its status. Rejections are recorded as rejections
so the same idea does not get re-mined out of the same documents next time. Free-text answers are
carried verbatim.

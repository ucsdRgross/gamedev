---
name: general-not-shape-specific
description: Owner rejects shape-specific hacks and coupled designs — propose the general form (or 2-3 options with tradeoffs) before implementing
metadata: 
  node_type: memory
  type: feedback
  originSessionId: 75157de2-6326-43ea-b7df-1a25b81a7de6
  modified: 2026-07-30T22:11:31.063Z
---

The owner reviews on **architectural** grounds, not on whether it passes. A solution that only
works for one prop, one silhouette, or one call site gets rejected outright even when it renders
correctly — and so does structural coupling (VFX nodes as siblings in the card layer, pair
coupling between effects, magic z-index numbers where structural ordering belongs).

**Why:** each rejection cost a full implement-then-redesign cycle. The normal-based tendril/skirt
work and its written spec were both thrown out as shape-specific; the FX plan went through v2 /
v3 / v3.2 rewrites over sibling coupling and a rotation model that produced diagonal pixels. The
constraint is always the same one: **it must generalize to any silhouette, and the data/visual
boundary must stay clean.**

**How to apply:** before implementing anything with a shape, layering, or coupling dimension,
state how it generalizes — and if a fix only works for the current prop, say so and propose the
general form instead of shipping it. For anything load-bearing, offer 2-3 architectures with
their tradeoffs (generalization, where the data/visual boundary sits, GPU cost, failure mode),
recommend one, and say what would falsify the recommendation — cheaper than a rewrite chain.
Layering uses structural ordering, never hardcoded z-index ([[solatro-structural-layering]]);
game logic stays headless-safe with no node/render dependencies ([[solatro-game-view-split]]);
shared tunables go in player_settings.gd ([[solatro-tuning-knobs-in-settings]]).

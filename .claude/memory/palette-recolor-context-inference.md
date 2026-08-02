---
name: palette-recolor-context-inference
description: Measured 2026-07-23 — automatic source-context inference for palette recolouring is infeasible; the target-side pool restriction works but only with DISJOINT pools
metadata: 
  node_type: memory
  type: project
  originSessionId: 7d94d192-014a-4f9c-87c9-f2e9c9acb8b4
  modified: 2026-07-24T00:52:13.172Z
---

Investigated 2026-07-23 whether `palette/` recolouring can be made context-aware
(source background colour → target BACKGROUND colour). Measured, not guessed:

**Source-context inference is NOT reliable enough to ship automatically.** Over the 264
decodable pixel-art PNGs in `palette/reference/`, only **23%** have an identifiable flat
backdrop (borderShare ≥ 0.5, coverage ≥ 0.12, edginess < 0.35); **33% have none at all**
(median borderShare 0.32). A finished illustration often has no fg/bg distinction to infer —
the whole frame is depicted scenery. Signal AUCs (bg vs fg): borderShare 0.77, ownBorder 0.73,
edginess 0.27, coverage 0.68 — all individually weak. Chroma looks perfect (AUC 0.000) but that
is **circular**: the ground truth came from our own generator, which defines bg as desaturated.
Outline detection ("darkest abuts the most colours") is only 33% top-1. The animation signal is
degenerate — 84–97% of pixels in real GIFs are static, so it finds "the moving element", not
the background.

**The target-side restriction works, but MAP_CONTEXTS pools are the wrong tool.** With oracle
(perfect) source labels, restricting each source colour to a target pool:
- using `MAP_CONTEXTS` sprites/scenery as-is → separation barely moves (3.21 → 3.54 ΔE), because
  those pools deliberately **overlap on 11 of 48 entries** (both keep the anchors).
- using strictly **disjoint** pools (fg/accent vs bg/neutral) → separation 3.21 → **10.29 ΔE**,
  cases collapsing below 2 ΔE go **12/16 → 0/16**, cross-assignments 19% → 0%, at a fidelity
  cost of +18% (5.16 → 6.07 ΔE mean).

**SHIPPED 2026-07-23** as `recolor_context` (off | suggest | manual), off by default. Owner
overrode the abstention recommendation: apply the guess to every image and accept that some
look bad. Live spec is ARCHITECTURE §12.8 — read that, not this.

**How to apply:** the inference is a starting point a human corrects, never an authority; do
not "improve" it into a confident classifier, the ceiling was measured and it is low. Two traps
worth keeping: context is applied as a **surcharge on the ΔE cost matrix** (so all three match
strategies and the monotone DP honour it unchanged), and the soft-bias scale must be on the ΔE
scale — interpolating to the hard penalty made every bias from 0.2 to 1.0 identical, a placebo
that every unit test passed and only a knob sweep plus reading the images caught. At bias 1 the
pools visibly flatten dithered tile texture; ~0.2–0.4 keeps it. See [[palette-project-facts]].

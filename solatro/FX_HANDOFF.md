# FX_HANDOFF.md — retired 2026-07-27, kept only as a signpost

This was the mid-flight handoff for the shader-FX feature. **The work it was handing off is done**
(T1–T14, T17–T20: landed, GPU-verified, suite green), so everything that used to live here has been
folded into its permanent home and deleted from this file rather than kept in two places.

**This file can be deleted.** Nothing links to it; git has the full text (committed in
`22f2aac "VFX plan"`, then emptied here). It is left in place only so that an old link or an open tab
lands on this map instead of on stale instructions.

| What you came here for | Where it lives now |
|---|---|
| The FX rules, contracts and every trap already paid for | **ARCHITECTURE_REVIEW.md §4g** |
| Prop/pip art: one pixel size, mirror-not-rotate, the hoop's split, what gets recoloured | **ARCHITECTURE_REVIEW.md §4h** |
| How to run the snapshot harnesses, and the shot lists | ARCHITECTURE_REVIEW.md §4g (shader) and §4h (prop art) |
| Why anything is the way it is; the 25 owner rulings; the task board | FX_SHADER_PLAN.md (§0b, §7) |
| The ball-position bug | Resolved — it was the harness re-enabling its own parked clock. The trap is in ARCHITECTURE_REVIEW §4g; the story is in git. |
| The universal palette (the one open feature) | **[PALETTE_PLAN_BRIEF.md](PALETTE_PLAN_BRIEF.md)** |
| What is left to do | [todo.md](todo.md) |

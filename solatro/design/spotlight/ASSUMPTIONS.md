# SPOTLIGHT — ASSUMPTIONS

Decisions taken while executing `PLAN.md` that the design did not cover, and that were
**reversible and clearly within intent** (gap protocol rule 1). Anything that was not is a file
in `gaps/`, not a line here.

One line each, citing the node it was taken under.

- **2026-08-04, S5 (D3).** `Game.score_line` builds a `ScoringSection` from the live board; a
  section that comes back **empty** skips the spotlight phase AND the re-evaluation, so the
  `Result` the caller handed in is banked unchanged. A real line always has cards (the scorer
  only calls `score_line` when it found a meld), so this only catches a caller that is not
  scoring a board line at all — the unit fixtures do exactly that. A section that HAD cards and
  lost them all is the design's own case and scores nothing (`Q244`=a).
- **2026-08-04, S6/S7 (D12b, `Q201`=b).** Every iteration of `_spotlight_section`'s unbounded
  loop calls `note_processing()`. `Q201` leaves the act-level runaway guard as the only bound,
  and without this the guard cannot see the loop: a chain whose handlers invoke no other mod
  never advances `act_calls`, so it would spin forever instead of tripping `act_event_cap`.
  Counting an activation sweep as one unit of processing is the same accounting the guard
  already applies per mod invoked and per prop slot entry.
- ~~**2026-08-04, S5 (D10, D19/D20, `Q16`).** `forced_spotlight` accumulates across the act's
  sections.~~ **WITHDRAWN the same day, and so was the gap that replaced it.** There was no
  decision here at all: `Q16` says the forced spotlight stays up for the whole act *and* that it
  *"increases or **decreases** based on cards being scored"* — one travelling light, which is
  what shipped. The apparent conflict existed only between two lossy RESTATEMENTS of that answer,
  not in the answer. See **GAP-002 (withdrawn)** for what that cost and what `DESIGN.md` v7
  changed so it cannot recur.
- **2026-08-04, S11 (O3, `Q213`=d).** `FxGlowStyle.grid` REPLACES the inherited `FxStyle.pixel`
  rather than sitting beside it: it writes the same `u_pixel` uniform, after `super(mat)`, and the
  inherited row is hidden from the inspector by `_validate_property` (still stored, so no `.tres`
  breaks). `Q213`=(d) asks for one knob running from the art's grid down to screen resolution, and
  `pixel`'s range stops at 0.25 — but two inspector rows quantizing the same coordinate is exactly
  the confusion the subclass split exists to prevent. Reversible: deleting `grid` and widening the
  base's range gives the other shape with no data migration. Pinned by
  `test_glow_grid_replaces_pixel()`.
- **2026-08-04, S11 (GAP-003).** The off-palette ramp the owner chose is Godot's built-in
  `Gradient`, not a new resource class. GAP-003's option (b) offered either; `Gradient` is a type
  the engine already edits well and carries no maintenance, and swapping it later is one export
  and one bake function. `PaletteRamp` stays the only ramp everywhere else in the game.
- **2026-08-04, S12 (O7, O9, `Q209`=a, `Q122`=c).** The field **peaks on the silhouette** and falls
  away in both directions: outward over each layer's radius, inward over `sink`. The plan's shorthand
  reads as fire's erosion (`d + sink`), which spends part of the reach before the edge — measured,
  that left NO visible halo in any panel of `09_glow_falloff` while every headless check passed.
  `Q209`'s stated purpose is that the light is *already at full strength where it crosses the
  silhouette*, and only this shape delivers it; the inward half is then `Q122`=(c)'s inner lift, a
  rim rather than a wash.
- **2026-08-04, S12 (O19-O21, `Q218`).** `render_mode blend_premul_alpha`, whose equation is
  `src.rgb + dst*(1-src.a)`, so a fragment picks its own blend by picking its alpha: 0 outside the
  silhouette is pure addition, `inner_alpha` over the art is a true lerp that cannot blow out.
  That is `Q218`=(c)'s two blends in ONE pass, with no second material and no screen read. The
  over-art alpha is scaled by the light's own coverage, because a constant one dims every card in
  reach by `1 - inner_alpha` where the light has faded to nothing.
- **2026-08-04, S13 (H4, H5, H8, `QR9`=c, `Q218`).** The light layer's CIRCLE contributes
  **coverage only** — it punches the dim over its card and adds no light of its own; the beam still
  adds, because a beam is light in the air with no art under it to wash out. Chart H8 has the layer
  adding `coverage * light colour` while `QR9`=(c) has the GLOW shader drawing the same circle as
  `MASK_DISC` with `circle_inner_alpha` holding it down over art, and both lighting one circle is
  twice the light for the one client with no room for it. Measured on `10_light_layer` over a real
  board: a card under a beam kept its rank and pips, a card under a circle lost them entirely.
  `Q218`'s note is *"dont want blowout to white"*. Reversible in one line — put `circle` back into
  `add_cover` — and it is the owner's eye that confirms it at G2.2.
- **2026-08-04, S13 (owner, beam shape).** The beam's half-width at its target is DERIVED from the
  circle's radius rather than passed in, and the cone ends **on the circle's far arc**: past the
  centre plane its cross-section is measured from the CENTRE instead of across the axis, so the
  circle's own far half finishes the shape and the two agree exactly at `t = 1`.
  ⚠ **THE FIRST TWO ATTEMPTS BOTH ENDED IT AT `t = 1`, WHICH IS THE CIRCLE'S CENTRE** — a straight
  chord through the middle of the pool, reported twice (*"Beam hard cuts into a straight line when
  it reaches halfway into circle instead of covering entire circle"*). The target point is a centre,
  not an edge; clamping to it can only ever cut the pool in half. Owner: *"shouldnt
  beams cut off at the circle? They reach max width at the circle then keep going for some reason.
  beam edges should match circle"*. §16's `beam_width_at_target` specified the requirement
  *"must cover the circle"* — a number whose only correct value is another number is a derived
  quantity, not a knob. What survives of it is `flare`, extra half-width beyond the circle, shipped
  at **0**.
- **2026-08-04, S13 (H4, H6, owner).** The beam's contribution to COVERAGE ramps from
  `u_beam_intensity` at the origin to **1.0 at the target**, matching the circle exactly; its
  contribution to ADDED LIGHT does not ramp. Owner: *"there is clear semicircle where beam and
  circle overlap"* — the arc was a step between two VALUES meeting at one boundary (the disc punched
  the dim to zero, one pixel outside it the beam only to 0.45), not a defect in the geometry, so
  softening the circle's edge alone would have blurred the arc rather than removed it. Ramping the
  coverage is the cone converging on the pool it makes; leaving the additive term flat is what keeps
  the card from washing out again.
- **2026-08-04, S13 (H5, owner).** `u_circle_softness` ships at **0.75**, a wide penumbra rather
  than a crisp disc. Because the circle punches the dim without adding light of its own, wherever it
  falls on the BACKGROUND it is "less dark" with nothing in it — fog, and with a hard edge, a drawn
  disc. A real pool of light has a penumbra; this is the number that makes the boundary stop being a
  line. Judged by eye on `10_light_layer`, not derived.
- **2026-08-04, S13 (H5, §16, owner).** `u_circle_intensity` ships at **0.3**, well under §16's
  suggested 1.0. The circle must READ as a pool inside the beam (owner: *"we can move on to next
  phase once circle shows up inside beam"*), and with the beam's coverage now converging on the
  circle's, a coverage-only circle is invisible by construction. 1.0 is what washed the rank glyph
  off the card. ⚠ **It is a FLOOR, not the whole answer**: once the glow draws the disc (`QR9`=c,
  `MASK_DISC`) most of the circle's brightness comes from there, where `circle_inner_alpha` holds it
  off the art — so expect this number to come DOWN, not up, when S13's node is wired.
- **2026-08-04, S13 (H5, owner).** `u_circle_softness` settled at **0.4**, after 0.25 (a visible
  arc) and 0.75 (*"circle edges are way too soft now, earlier it was better"*). ⚠ The 0.75 was an
  OVER-CORRECTION treating a symptom: the arc was a step between two coverage VALUES, and once the
  beam's coverage was made to converge on the circle's, the edge could be sharp again without it
  returning. **Blurring a boundary is not how you remove a discontinuity across it.**
- **2026-08-04, S13 (`Q98`=b, owner).** The beam's volumetric noise was mistuned, reported as
  *"pixelated hard edge noise ... at wrong resolution"*. Isolated by rendering with
  `u_beam_noise = 0` — the patches vanished, so it was this and not the dim's Bayer dither.
  `u_beam_noise_scale` was **0.02**, putting `fx_fbm`'s base cell at ~50 SCREEN PIXELS and its
  finest octave at ~12, so the haze read as flat blocks the size of a card's art square. Now 0.06
  (~17 px base, ~4 px finest), amplitude down to 0.25, and the multiplier centred on 1 —
  `0.55 + n * 0.9` rather than `n * 1.6`, which darkened more than it brightened and drove the low
  end into a hard cutoff. All three are uniforms and remain tunable.
- **2026-08-04, S8 (D13b).** The re-evaluated `Scoring.Result` REPLACES the one passed into
  `score_line`, so the δ duplicate-class decision, `register_combo`, `animate_meld`,
  `show_meld_score` and `_run_score_effects` all read the new hand. `Q243`=(a) asks for the
  lights and jumps to re-cue when the meld changed; feeding every consumer the re-derived
  result is that, with no second code path.
- **2026-08-05, S15 (chart T, `T10` / GAP-006).** The momentary cue's lights are **exempt from the
  per-section reveal gate** — `LightLayer.Light.gated = false`, and `_dim_target()` takes
  `max(_show, strongest ungated intensity)`. The design does not say how chart T's cue interacts with
  GAP-006's `_show`, and the two readings are not close: a GATED cue is multiplied by `_show = 0`
  outside a submit — nothing raises the gate in ordinary play — so it would be **perfectly invisible
  while every headless assertion about the light set still passed**, which is GAP-005's failure shape
  exactly. Raising `_revealed` for a cue instead would drag the previous section's faded beams back up
  with it. `T10` settles it in the design's own words: the cue's dim *"rises with this spotlight's
  BEAM and falls when it retires"* — its own life, not scoring's beat. `max` rather than a sum keeps
  `Q247`=(a)'s *one* dim covering all of them. Reversible: one bool on `Light`.
- **2026-08-05, S15 (chart T, `T6`).** The cue's hold reuses **`spotlight_hold_fraction`**. §16 lists
  no cue-specific hold and `T6` only says *"spawn on it, hold, and retire"*. That knob is already
  defined as *"the beat after `on_active`"*, and chart T's cue fires precisely when a card gains
  `on_active` — so this is the same beat, not a second one invented for it. If the owner wants the
  casual cue to hold longer or shorter than the scoring beat, it needs its own §16 row.
- **2026-08-05, S15 (chart T, `T15`/`T16`).** A cue is **invisible to `_on_section_changed`**: never
  taken as a leftover to travel, and it does not `claim` its card either. So a card both cued and
  scored briefly carries **two lights**. The alternative — letting the cue claim the card — was
  rejected because the cue then retires and leaves that card dark for the rest of its section, which
  is a visible hole rather than a brief double brightness. `Q249`=(a)'s *"a second cue may start while
  the first is still retiring"* is what forbids the cue from sharing the section's replace-the-set
  semantics at all.
- **2026-08-06, review pass (G2.4, `Q83`).** `glow.gdshader`'s over-art ALPHA now rides
  `clamp(u_brightness, 0, 1)` and the host's `COLOR.a`. At `fx_intensity = 0` the glow emitted
  `rgb = 0` with alpha standing, and `blend_premul_alpha`'s `dst * (1 - a)` drew a DARK DISC over
  every spotlit card — the inverse of G2.4's "scales the lights toward nothing". At the shipped
  brightness (1.0) the output is bit-identical, so no look changed. Reversible: one factor.
- **2026-08-06, review pass (D22/D23, `QR2`=d).** A CANCELLED submit now emits the empty
  `spotlight_section_changed` before `_restore_pre_act_board` — view-only teardown, no sweep (the
  doomed state's hooks must not fire). Without it the revealed rows stayed open forever and the
  next act inherited the cancelled act's beams and origin band; nothing else closes the view
  (`clear_reveal`/`retire()` had no callers, and the model restore does not reach the view).
- **2026-08-06, review pass (A8, GAP-001).** `CardModifier._blocked_from_above()`'s three
  degenerate-lookup branches return **blocked** (dark), restoring `is_data_topmost`'s fail-closed
  default — the port had inverted them to fail-open, so a card the (revision-cached) index could
  not locate read as spotlit mid-mutation.
- **2026-08-06, review pass (`Q245`=c).** `u_dim_scale` DELETED from `light.gdshader` and the
  layer: the casual scale is applied CPU-side in `_dim_target()` and the uniform was pushed as a
  literal 1.0 forever — a dead multiply whose comment claimed the opposite.
- **2026-08-06, review pass (K12).** `PlayArea.update_score_controls()` re-applies row openings
  after `set_score_zone` — banking a line score reaches it while the scored row is still open and
  the reset collapsed the gutters (the K12 silent desync its own header warns about).
- **2026-08-06, review pass (`Q252`=b).** `set_reveal_cards` and the director's two signal
  handlers `flush_rebuild()` before reading slot bindings; `_row_covers_anything` reads
  `game.state` instead of control child counts. Both closed the same seam: a hook's compaction
  queues a DEFERRED rebuild, so tree reads between mutation and flush described the previous board.
- **2026-08-06, review pass (I10–I12, `Q251`=b).** `SpotlightOrigins.advance()` re-spreads in
  x ORDER (sorted view), not index order — after `_subdivide()` appends midpoints the two diverge,
  and the index-order walk permuted the band, teleporting taken lamps under live beams.
- **2026-08-06, review pass (chart E).** `SpotlightDirector._Beam.last_pos`: a beam whose card
  lost its visual holds its last drawn position instead of collapsing to `(0,0)` — the tool had
  this guard, the shipped director did not (the owner's "flying in from outside the board").
- **2026-08-06, review pass (`Q260`/`Q266`).** `ScoringSection.refresh()` re-collects through a
  `Callable` captured by `of_line` instead of branching on `origin` — the field's own doc says
  "NEVER branched on for behaviour", and a future non-line shape would have been silently re-read
  as a column.

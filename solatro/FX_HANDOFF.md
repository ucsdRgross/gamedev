# FX_HANDOFF.md — live handoff, updated 2026-07-29 (late: BOTH remaining tasks landed)

**Read [VFX.md](VFX.md) and ARCHITECTURE_REVIEW **§4g** first** (the map and the contract).

✅ **START AT §0. THE NOISE FIRE HAS SHIPPED; SO HAVE BOTH OF THE TASKS THAT WERE LEFT.** The tendril /
comb / ogee / onion build is gone and `fire.gdshader` is now a cover field carved by scrolling noise,
with a stack ratio on every knob. §0 is the record of what was built and what it measured.

✅ **THE TWO TASKS OF §0c/§0d ARE DONE** (owner 2026-07-29: *"our last tasks will be making fire vfx
show behind the art and saving juggling performance"*). Both are code; both are measured; **neither
has been seen by the owner yet, and §0c is a LOOK claim, so his eye is the last word.**

| ✅ | landed | measured |
|---|---|---|
| **§0c** | fire behind the art — **route 1**, the unquantized alpha cut. Cards AND sprite props (the props were a second pass, after the owner caught them) | the seam follows the art's own edge at every angle; the staircase and its backdrop gaps are gone (`fx_behind.tscn`, new) |
| **§0d** | juggling perf — **lever 1**, `FxRequest.min_half`, the quad sized to the pattern | the juggling layer **1.44x cheaper** (full screen 2.258 → 1.825 ms), all 18 snapshot panels **byte-identical** |

⚠ **AND THE REVERT THAT BLOCKED §0d FOR TWO SESSIONS WAS CHASING A HARNESS FLAKE** — measured, not
argued. §0d.1 has it, and the claim now lives in an asserting check instead of a picture.

⬜ **TWO THINGS THE OWNER FOUND WHILE REVIEWING THIS, AND ONE OF THEM IS BIGGER THAN EITHER TASK:**
**§0c.1** the warped card's spikes still take fire over the art (the 32-ray mask cannot hold a vertex,
and the cut follows the mask), and **§0c.2 NO HARNESS ANYWHERE RENDERS A REAL `CardVisual`** — every
card panel in this project is `star_outline`, a hand model of the rig, and the FX editor draws that same
array as the card's face. **§0d.2 is the priced menu of juggling compromises he asked for.**

§0e explains `cover_taps`, the one knob that trades look against the only cost this shader has.

**§1 to §7 describe the RETIRED build: read them as the record of what was learned and what must not
be broken, not as a description of what is there.** **§8 is the live list**; §9 is the cost
attribution that justified the rewrite and is now the baseline it beat; §11 is the runbook.

Sections are numbered in reading order. If you add one, keep it that way — an earlier edition had
§6.-1 and put §7b before §7a, and it cost a reader real time.

⚠ **The owner will run the `simplify` skill over the unpushed commits.** Land behaviour first; do not
pre-emptively restructure for tidiness.

⚠ **NUMBERS: §0's and §1's are a GTX 1070; everything in §6 and §9 is the owner's Intel UHD** (driver
31.0.101.2135, gl_compatibility), which is the real target. The two are ~2x apart on these rows, NOT
the ~12x an earlier edition of this file assumed. Ratios transfer; absolutes do not — **so read §0's
RATIOS and re-run `fx_cost.tscn` on the Intel box before making any decision from them.**

---

## 0. THE NOISE FIRE — shipped, plus the TWO TASKS LEFT

Owner, 2026-07-29: *"Fire effect no longer has tendrils at all, just average fire shader effects like
moving noise instead... make sure all params have scaling ratios as stacks increase"* — and *"should
still be form fitting to any shape and rotation. Do this for all current fire effects card prop ball."*

Built, measured, green (28 suites, exit 0). ✅ **§0c and §0d have since landed on top of it — read
them for what changed and what is still owner-only.**

### 0a. The model, and what it measured

```
cover(p) = 1 - (first of u_taps taps below p to land inside the mask - 1) / u_taps
n        = two scrolling noise layers, in the SAME world-aligned, already-quantized p
heat     = clamp(cover * (((cover + aperture*(1-cover)) * n - aperture*(1-cover)) * gain) * intensity, 0, 1)
COLOR    = texture(u_ramp, vec2(heat, u_level))
```

`cover` is 1 at the surface and steps to 0 at exactly `u_height` above it — the role `UV.y` plays in
the owner's Kinomoto reference, so substituting the MASK-derived cover for the QUAD's `UV.y` is the
whole port: the same arithmetic that burns a rectangle burns the host's own shape.

GTX 1070, GPU timer, `fx_cost.tscn`, before/after in one session. ⚠ **NOT the Intel UHD of §6 — ratios
transfer, absolutes do not, and nobody has run this build on the slow box.**

| GPU timer, ms/frame | retired build | noise fire | |
|---|---|---|---|
| **78 burning cards, edge to edge** | 1.148 | **0.639** | **1.80x** |
| **78 burning AND juggling, 5 lit balls each** | 3.358 | **2.580** | **1.30x** |
| the juggling half of that row alone | 2.210 | 1.941 | 1.14x |
| the same 78 plus 3x more OFF-SCREEN | 3.358 | 2.407 | still exactly free ✅ |
| card fire x20 (DEFORMED — what a real card is) | 0.373 | 0.207 | 1.80x |
| prop fire (hoop) x20 | 0.288 | 0.126 | 2.29x |

**The tap cost curve — the whole cost model, drawn directly** (full screen, burning): 2 taps 0.450,
**4 taps 0.598 (ships)**, 6 taps 0.754, 8 taps 0.900. Dead linear at **+0.081 ms per tap** over a
fixed ~0.29 ms of fill, noise and ramp. §9's claim — *the cost is `mask_level` call count times cost
per call and nothing else* — is now measured on the shipped build rather than inferred.

⚠ **THE GPU CLOCK STATE WILL LIE TO YOU ON THIS BOX.** The 1070 sits in two power states and the timer
is bimodal by ~1.3–1.7x between them, with **every row of a run scaled by the same factor** — five
consecutive runs of ONE unchanged build read 0.594, 0.597, 0.753, 0.874, 0.924 on the same row. **Run
the bench three times and take the MINIMUM.** A single run is not evidence.

### 0b. The stack ratios — the owner's actual request

`FxFire.stacks_live()` is the ONE mapping from stacks to uniforms. Every knob carries a ratio, and the
ratios are EXPORTED on `FxFireStyle` ("Stack scaling") so tuning how fast each ramps is art, not code:

```
growth = log(stacks)              # 0 at 1 stack, 2.5 at 12, 3.7 at 40, 5.3 at 200
value  = base * max(1 + growth * ratio, 0)
```

| uniform | ratio | default | why |
|---|---|---|---|
| `u_intensity` | `intensity_ratio` | 0.25 | matches the retired build at 200 stacks |
| `u_height` | `height_ratio` | 0.16 | ditto for reach |
| `u_aperture` | `aperture_ratio` | **-0.08** | a bigger fire is more SOLID, and the aperture is a CUT — so it must FALL |
| `u_fire_gain` | `gain_ratio` | 0.05 | more contrast |
| `u_noise_scale` | `noise_scale_ratio` | **-0.06** | a bigger fire has COARSER grain |
| `u_noise_scroll` | `noise_scroll_ratio` | 0.12 | and moves faster |

- ⚠ **AT ONE STACK EVERY RATIO IS INERT** (`log(1) = 0`), so the base values ARE the 1-stack look.
  Tune the base at 1 stack, then the ramp at 40 and 200.
- ⚠ **THE OLD `overflow` CAP IS GONE** — the retired build was flat below 12 stacks, so nothing but
  the colour changed from 1 to 12. Everything ramps from stack one now, which is the request, and it
  is the thing most likely to need retuning by eye.
- ⚠ `u_count` survives ONLY in `FxRequest.live`, where `_emit_embers` reads it as the ember RATE. It
  is not a uniform: the shader never read it and Godot ignores an undeclared parameter.
- `test_every_fire_knob_ramps_with_stacks` walks all 200 counts and **fails when a new knob is added
  without a ratio** — which is the failure this pass existed to prevent.

### 0c. ✅ TASK 1 — FIRE RENDERS BEHIND THE ART (route 1, shipped 2026-07-29)

**What shipped is ONE LINE, and it is route 1 of the three weighed below.** The occlusion cut is now
tested at the **unquantized** position:

```glsl
if (u_inner_alpha < 1.0) {
    vec2 cut = (u_shape == SHAPE_BOX || u_shape == SHAPE_RADII)
            ? fx_local_raw(UV, u_extent) : p;      // fx_local_raw = the same point, NOT quantized
    if (mask_solid(mask_level(cut, ball, ball_level))) alpha_mul = u_inner_alpha;
}
```

- The flame's own pixels stay on the FX grid — it is pixel art. **Only the boundary moved**, onto the
  resolution the art actually has, which is what real occlusion looks like.
- ⚠ **SPRITE AND BALLS DELIBERATELY KEEP THE QUANTIZED POINT.** Their art IS drawn on the FX grid (a
  prop's sheet at `pixel` 2.5, a ball by `juggle.gdshader` on the shared lattice), so there the
  quantized test is the one that AGREES with the drawing — an exact cut would slice a smooth curve out
  of chunky pixels and open the same class of seam from the other side. Uniform branch either way.
- ⚠ **Cost: none beyond what the cut already paid** — the same single `mask_level`, at a different
  point. `burning, FULL SCREEN` is 0.615 ms before and after, inside the clock noise.

**THE INSTRUMENT IS NEW AND IT IS THE POINT: `Tests/Visual/fx_behind.tscn`.** §0g's standing lesson is
that every FX bug that reached the owner was invisible in `fx_snapshot`, and the reason is structural
— that harness draws its hosts as an **outline**, and an outline cannot show a seam. `fx_behind` draws
the host **filled and opaque**, the way the game draws it, at up to 6 screen px per art unit, in three
shots: `behind_card_rot` (0 / 15 / 45 deg), `behind_card_warp` (corners +0 / 25 / 45 %) and
`behind_prop` (ring, ring rotated, blade rotated). Reviewed with
`py <scratch>/crop.py <png> <out> x y w h 5`.

**What it showed, before and after** (45-degree card, the worst case):

| | the seam along a diagonal art edge |
|---|---|
| **before** | a staircase of 1-art-unit treads against a straight line, with **backdrop showing through every tread** — exactly *"rotating still shows jaggedness"* |
| **after** | the art's edge slices the chunky flame pixels diagonally; no treads, no gaps |
| **0 deg, before AND after** | identical, and it always looked right — an axis-aligned edge happens to fall ON the FX grid, which is why this bug only ever showed when a card turned |
| **warped card** | the flame's foot rides the concave dip and the stretched corners; ⚠ a **~0.17 art unit** grey sliver survives in places, and it is the RADII table's own fidelity (32 rays interpolated as a radial scale) rather than the cut — see §10 E |

**THE SPRITE PROPS NEEDED IT TOO, AND THE FIRST DRAFT EXCLUDED THEM** (owner, 2026-07-29: *"props did
not get same treatment as card and dont have nice seams"* — with a screenshot of a knife at ~25 deg
carrying whole 2.5-unit flame blocks straight across the blade). The excluding argument was *"a prop's
art is pixel art at `pixel` 2.5, so the quantized test agrees with the drawing"*, and **it holds only
at zero rotation**: the art turns with its host and the FX grid never turns (the universal rule), so
the art's texels run diagonally while the cut's staircase stays axis-aligned. Fixed by testing the raw
point for SPRITE as well — the mask IS the art's alpha, so it returns the drawing's own pixel edges,
diagonal staircase included.

**SHAPE_BALLS is now the only shape that keeps the quantized point**, and that one is not an oversight:
a ball is drawn by `juggle.gdshader` on the SAME origin-anchored lattice and never rotates, so there
the drawn silhouette really is the quantized disc. ⚠ It holds while the juggle and `fire_ball` styles
share a `pixel` (both 1.0 today); if they diverge, that cut is on the wrong lattice.

⚠ **AND `fx_snapshot` COULD NOT HAVE CAUGHT THE PROP BUG — `snapshot_diff` came back 18/18 IDENTICAL
across the fix.** Every prop panel in that harness is at rotation ZERO, which is the one angle where
the two cuts agree. The FX editor rotates every host, which is why the owner saw it and no test did.
`fx_behind`'s `behind_prop_turned` exists for exactly this, and §0c.2 is the wider version of the same
gap.

⚠ **IT IS STILL A CUT, NOT A LAYER, AND THE OWNER SHOULD BE TOLD THAT PLAINLY.** For an opaque host —
every host is opaque over its own mask — it is now indistinguishable from drawing the fire underneath.
If his eye still says otherwise, **route 3 below is the structural answer and its plan is unchanged**;
set `inner_alpha` back to 1.0 if you take it.

#### 0c.1. ⚠ THE CARD'S WARP CORNERS ARE STILL WRONG, AND IT IS THE MASK, NOT THE CUT

Owner, 2026-07-29: *"curious why fire effect goes in front of card at extreme warp, chamfering at
edges."* **Measured on `behind_card_warp`, and the answer is the chamfer §0g already documents:**

- `u_radii` is a **32-ray table of radial SCALE, linearly interpolated**, and no scheme that blends two
  rays can reproduce a VERTEX. A warped card's corner is a vertex — `star_outline` pulls 4 corners out
  and leaves 12 interior points on the rest edges, so the shape is a star with four spikes.
- So the MASK's boundary near a spike is a straight line across its shoulder. **The cut follows the
  mask**, which produces both halves of what the owner sees: flame drawn OVER the art where the mask's
  chamfer line falls inside the spike, and a BARE spike above it where the mask says "no art, nothing
  to stand on".
- ⚠ **It is not a regression and the unquantized cut did not cause it** — it made it VISIBLE by making
  every other part of the seam exact. §0g's chamfer row fixed the REST case (the radial scale reduces to
  the exact box at warp 0); the deformed case was never exact.
- **Scale:** at **+45 %** it is obvious (a whole spike bare, ~2 units of overhang). At **+25 %** — which
  is where `card_visual.tscn`'s autoplay animation actually peaks — it is roughly one art unit at the
  shoulder and easy to miss. The +45 % panel is deliberately past what the rig can reach (§7).
- **The three ways out, none of them free** (and §10 E is already taken, which is why this is what is
  left): **(a) `RADII` 32 → 64** halves the error (§7's numbers: 2.32 → 1.41 → 0.56 art units) for 64
  floats per material per quad per host — two lines, and the only one that is a one-run experiment;
  **(b) an analytic STAR branch** in `mask_level` (the shape is exactly the rest rectangle plus four
  corner triangles), which is exact and cheap per tap but is a PER-SHAPE path, brushing the owner's
  *"fire should be unified and identical in how it treats everything"*; **(c) accept it**, on the
  grounds that the rig peaks at 0.25. ⚠ **Owner call — (b) is the only correct one.**

#### 0c.2. ⚠ NO HARNESS RENDERS A REAL `CardVisual`, AND THAT IS THE ROOT OF THE CARD-VS-PROP DIVERGENCE

Owner, 2026-07-29: *"has this issue this whole time been that fx editor doesnt use real card visual,
causing broken assumptions and constant mismatch between card vs prop visuals despite requirement they
use same code, because the card outline was never accurate to real cards and therefore tests nothing?"*
**Substantially yes, and here is the precise version.**

**Every FX harness stands up a bare `Node2D` + `FxAttachment` and feeds it
`CardVisual.star_outline(body, warp)`** — `fx_editor.gd:351`, `fx_snapshot.gd:188`, `fx_cost.gd:206`,
`fx_behind.gd:100`. That static is a **hand model of the rig**, not the rig: the real card hands
`_rig_outline()`, composed from 16 `Bone2D` local transforms every frame, and its FACE is a baked
polygon grid SKINNED to those bones. Two things follow, and the second is the owner's point:

1. ⚠ **THE FX EDITOR DRAWS THE MASK'S OWN SOURCE AS THE CARD FACE** (`_draw` fills `_card_outline()`,
   the same polygon it hands the attachment). **A tool built that way cannot show a face-versus-mask
   disagreement at all** — the two are the same array. It is the same class of tool-lie the §0g
   instruments were built to avoid, in the one place that gets used for tuning every day.
2. ⚠ **THE PROPS WERE ALWAYS TESTED WITH THEIR REAL ART** (`Shape.SPRITE`, the mask IS the sheet's
   alpha, and the harnesses draw that same sheet), **while the card was tested against an idealisation
   of itself.** That asymmetry IS the "card and prop keep diverging despite sharing code": the shared
   code is fine, but only one of the two was ever checked against what the game draws.

**What is genuinely NOT invalidated**, so the next reader does not over-correct: the mask maths, the
cover field, the cut, `min_half`, the balls, and every prop claim. Those either use real art or are
statements about the shader that hold for any outline. **What IS unverified is the card's silhouette
itself** — nothing anywhere checks that the arm-tip polygon the attachment is handed matches the
boundary of the skinned polygons the player sees, and it is not obvious that it should: the face's
outer vertices are *skinned by* those bones, not equal to them.

⬜ **THE TEST THAT WOULD CLOSE IT, and it is the next thing to build:** instantiate a REAL `CardVisual`
in the PIXELS suite (a test scene has the autoloads the `@tool` editor deliberately lacks — which is
*why* the editor fakes the card), let its autoplay animation run to a fixed time, and compare the drawn
face's silhouette against `att._radii` column by column. ⚠ Do it in `test_pixels.gd`, not in a snapshot:
the claim is numeric agreement, and §0g's lesson is that a picture of a card at 2x zoom hides exactly
this. Until that exists, **every warp claim in this file is a claim about `star_outline`, not about a
card**, and `fx_editor`'s warp slider should be read the same way.

#### 0c.3. The three routes, as they were weighed — kept for route 3

Owner: *"I would prefer that fire effect always be behind main card art visually, so it never covers
art and hides jaggedness of fire bottom vs object tops when rotating or warping"* — then, after the
first attempt: *"vfx is still not behind card or hoop or knife. rotating still shows jaggedness. My
guess is that you are turning pixels that are supposed to be behind transparent instead of rendering
it, which looks nothing like if it was actually behind."*

**The diagnosis is the owner's and it is correct.** `inner_alpha = 0` (shipped, and the DEFAULT on
`FxFireStyle`) makes the flame TRANSPARENT where the mask is solid rather than drawing it and letting
the art cover it. It measures **0 fire pixels over the art** on card, hoop and knife — so the metric
passed while the look did not. ⚠ *"No fire pixels over the art"* is not the same claim as *"the fire is
behind the art"*, and only the second was asked for.

⚠ **WHY IT LOOKS WRONG, AND IT IS NOT WHAT AN EARLIER EDITION OF THIS SECTION SAID.** That edition
blamed the mask's accuracy and declared `inner_alpha` and `z_index` both dead. **Both of those
rulings were premature — here is the actual state of each.**

**The real cause is one word: QUANTIZATION.** The cut is
`if (u_inner_alpha < 1.0 && mask_solid(mask_level(p, ...)))`, and **`p` is the FX-grid-quantized
position** (`fx_local`). So the boundary is a staircase with a 1-art-unit tread — ~2.5 screen pixels
on a card — while a card's face is a `Polygon2D` whose edge is a hard line at SCREEN-pixel resolution.
A 2.5-px staircase against a 1-px line is the jaggedness in the screenshots, and it appears at every
angle and warp.

**Three routes. Try them in this order; only the third is definitely correct and it is also the most
work.**

1. ✅ **`inner_alpha` WITH AN UNQUANTIZED CUT — TAKEN, and it worked exactly as predicted.** Keep the
   flame's own pixels on the FX grid (it is pixel art) but test the mask for the ALPHA CUT at the raw,
   un-quantized local position. The cut then follows the art's true edge at screen resolution, which
   is **exactly what occlusion does**: the art's smooth edge slices chunky fire pixels diagonally.
   For an opaque host — and every host is opaque over its own mask — that should be visually identical
   to real occlusion.
   - `fx_local` currently returns only the quantized point, so this needs the unquantized one
     alongside it (`(UV - 0.5) * extent` with the y flip, ~2 lines).
   - ⚠ It costs the mask lookup `inner_alpha < 1.0` already costs, and no more.
   - ⚠ For a SPRITE host the mask IS the art's alpha, so an unquantized sample lands on the art's own
     texel boundaries — the prop and knife cases come out right for free.
   - **It was the cheapest thing that could work, and it did. Shipped — see the top of §0c.**
2. ⬜ **`z_index`, which the owner explicitly offered** — NOT NEEDED NOW, and the experiment below was
   never run, so it stays unsettled rather than dead. (*"Changing z index is fine here just to save
   us from having back and front vfx layers"*). ⚠ **A bare `z_index = -1` on the fire quad does NOT
   work, but the reason is a claim that was DERIVED AND NEVER MEASURED, and it should be measured
   before this route is dropped.** Godot resolves effective z through the `z_as_relative` chain and
   sorts by that ONE number across the whole canvas (LAYERING.md), so a fire quad at relative -1 goes
   under EVERY z-0 item, not just its own card's art — and since `CARD_SEPARATION` is 14 while card
   fire reaches 7, the band a card's flames occupy sits inside the body of the card ABOVE it in the
   column, which would then cover them.
   - ⚠ **THAT LAST STEP IS GEOMETRY ON PAPER, NOT AN OBSERVATION.** One experiment settles it: two
     overlapped cards, both burning, fire quad at `z_index = -1`. If the flames survive, this is by
     far the cheapest fix. **Run it before believing the paragraph above.**
   - If it does hide them, the working variant is a **per-card z band**: card root `z_index = index*2`,
     fire quad at -1 relative, so card N's fire (2N-1) sits above card N-1's art (2N-2) and below its
     own (2N). ⚠ Its real cost is not the arithmetic — it is that **mixing numeric z with a structural
     scheme is exactly what LAYERING.md forbids**, so props and overlays at z 0 would then sort under
     every card and the whole board would have to go numeric with it. Bounded, but wide.
3. ⬜ **A SECOND `FxAttachment`, placed BEFORE `visual`** — structural, no z, and definitely correct:

```
CardVisual
└── offset
    ├── FxBack   <- child index 0: drawn BEFORE the face, so the ART COVERS the fire
    ├── visual   <- the card's Polygon2D face, the rig, status_layer
    └── Fx       <- the existing node: balls, ball fire, anything in front
```

   Correct on both axes for the reason z is not: within a card the art covers the fire; across cards
   the whole `CardVisual` subtree is ONE unit in `CardLayer`'s order, so card N's `FxBack` still draws
   after all of card N-1. The work, and its traps:
   - `FxRequest.behind`; `FxFire.request` sets it, **`FxJuggle` must not** — balls stay in front
     (ruling 11), and ball fire stays in the FRONT node because a plume over the card must stay
     visible and it is already behind the balls by declaration order (§0g).
   - `CardVisual._ready`: `offset.add_child(fx_back)` then `offset.move_child(fx_back, 0)`.
     ⚠ A prop has no balls, so `PropVisual` can just move its single attachment to index 0.
   - **Every call site doubles** — `measure_silhouette` / `measure_outline` / `track_outline`,
     `visible`, `sync`, `_restyle`. Route by `req.behind` in one helper, not at each site.
   - ⚠ **COPY `_seed` ACROSS**, or the fire and the balls on one host stop looking like one effect.
   - ⚠ **SET `inner_alpha` BACK TO 1.0** or you get the cut AND the occlusion and the seam is still
     the mask. `sink` then means what it says: flame drawn under the art and hidden, burying the
     ragged foot.
   - LAYERING.md documents the board order node by node and needs updating.

### 0d. ✅ TASK 2 — JUGGLING PERFORMANCE (lever 1, shipped 2026-07-29)

The juggling layer was the dominant half. **Lever 1 landed and took ~30 % off it.** Measured on the
GTX 1070, `fx_cost.tscn`, **three runs each way, minimum taken**, with the ONLY difference the two
`min_half` assignments:

| GPU timer, ms/frame | before | after | |
|---|---|---|---|
| `juggle balls x20` | 0.224 | **0.160** | 1.40x |
| `ball fire x20` | 0.360 | **0.246** | 1.46x |
| **`juggle both x20`** | **0.567** | **0.386** | **1.47x** |
| `burning + juggling, FULL SCREEN` | 2.258 | **1.825** | 1.24x |
| **the JUGGLING HALF of that row** | **1.643** | **1.144** | **1.44x** |
| `burning, FULL SCREEN` (the control — no juggle quad in it) | 0.615 | 0.681 | ⚠ 0.90x |

⚠ **READ THE CONTROL ROW BEFORE THE OTHERS.** The burning-only rows came out ~10 % *slower* in the
"after" set, which is the bimodal clock of §0a scaling a whole run — so the juggling gains above are
if anything **understated**, and the honest claim is "the juggling layer costs ~30 % less", not a
specific millisecond.

**What it is: the quad is sized to the PATTERN instead of to the card.** `FxRequest.min_half` lets a
request declare its own content half-extent, and `FxAttachment._size_quad` uses it INSTEAD of
body-plus-reach. The two values are `fx_balls_near`'s own box — half a span plus a ball, one tall arc
plus a ball, plus one flame for the plumes — so nothing the shader is willing to draw can fall outside.
A 38x50 card's ball quads went from **112x125** to ~**54x80**.

**Proof it changed nothing visible: `py solatro/tools/snapshot_diff.py` — ALL 18 PANELS BYTE-IDENTICAL**
with the lever on versus off. That is the honest instrument for an optimisation (§11), and it is a
stronger statement than "no clipping was visible": the lattice is origin-anchored, so a correctly
sized quad renders the same pixels as an oversized one.

#### 0d.1. ⚠ THE REVERT THAT BLOCKED THIS WAS A HARNESS FLAKE — measured, and it is a lesson

This lever was written, measured and **reverted** on 2026-07-31 because `05f_ball_rotation` showed the
balls displaced along +x by up to **6.1 art units at 90 degrees**, growing with the angle, with no
mechanism ever found. §1b called that "exactly the class of thing that produced two rejected builds".

**On 2026-07-29 the same displacement was reproduced on an UNCHANGED build**: five consecutive runs of
`fx_snapshot`, and run one printed probe offsets of **1.0 / 2.0 / 5.8** art units at 30 / 45 / 90 while
the other four printed 0.1 at every angle. The shot has carried a standing *"rotated panels are not
reproducible"* warning the whole time; nobody had run it twice.

- The counter-rotation was **printed** and it was correct in every run (`host.global_rotation` and
  `att.rotation` exact negatives at all four angles) — that print is now permanent in `_shot`, along
  with a POST-CAPTURE re-read, so a future flake is diagnosable rather than mysterious.
- A first-run **shader-recompile** theory was tested (touch `fire.gdshader`, run once) and is **wrong**:
  that run came out clean.
- **So the mechanism is still unknown, and that is now acceptable, because the claim moved.**
  `test_balls_ignore_their_hosts_rotation` in the PIXELS suite asserts it: 5 balls on a host at 30 / 45
  / 90 degrees must sit within 2 art units of the WORLD-UPRIGHT oracle. Deterministic (`_seed` pinned),
  runs in the suite, passes with the lever on. **A decision this size needed an assertion, not a
  picture** — and `_host_balls` takes a `deg` now, which is what made it three lines.

⚠ **THE STANDING LESSON, and it is the twin of §0g's:** a green metric is not a green look — and a red
picture from a flaky harness is not a red build. **Run a rendering harness twice before believing
either half of what it tells you.**

#### 0d.2. ⬜ THE COMPROMISES AVAILABLE FOR JUGGLING, priced — owner asked for the menu, 2026-07-29

⚠ **READ THE BUDGET FIRST.** After lever 1 the worst window this box can build — 78 cards, every one
burning AND juggling five lit balls — is **1.825 ms**, of which the juggling layer is **1.144**. The
owner's target is ~2 ms for ALL FX. **On the GTX 1070 there is nothing left to buy**; this list matters
only if the Intel UHD (~2–2.5x, §6) or a real playtest says otherwise. **Do not spend a LOOK change on
a budget that is already met.**

**Free — no visual change, nothing given up:**

| | lever | worth | risk |
|---|---|---|---|
| **1** | ⬜ **AN OFF-CENTRE QUAD.** The pattern hangs ABOVE y = 0 (`fx_balls_near`: y from `-(arc+ball)` to `+ball`), but a quad is centred on the host's origin — so **~40 % of both juggling quads is empty space below the loop**, and `min_half` cannot express it because it is a half-extent. Give a request an OFFSET, fold it into `fx_local`'s `s` BEFORE the quantize, and move the mesh by the same amount. ⚠ **Safe with the current lattice and only because of it** — the grid is anchored on the host's ORIGIN, so a constant offset added before `floor` leaves it exactly where it was (this is the same reason `min_half` was safe: §0g's `height`-jitter row). | **~1.4x on the layer**, the largest thing left | medium — it is quad geometry, so §0d.1's flake will look like a bug again. `test_balls_ignore_their_hosts_rotation` plus `snapshot_diff` 18/18 are the gates, and both exist now. |
| **2** | ⬜ **SHRINK THE BALL-FIRE QUAD TO THE LIT BALLS.** `req.lit` is known on the CPU, so the plume quad only needs to cover the balls actually alight — usually 1–2 of many. It changes every frame as they travel, which used to be unthinkable (a live resize moved the lattice) and is now free for the same reason as above. | large in PLAY, zero in the saturated bench (where every ball is lit) | medium, plus per-frame CPU to recompute — and the bench cannot show the win, so it needs a play measurement |
| **3** | ⬜ **§6a's lever B / §10 B** — the diagonal bound only while a card is really turned. | ⚠ **1.09x, measured** (`BOX-BOUND quads` row: 1.825 → 1.672). Lever 1 already removed most of what it was measuring. | low, and now nearly pointless |

**Cheap, and they cost a LOOK the owner owns:**

| | lever | worth | what is given up |
|---|---|---|---|
| **4** | ⬜ **`fire_ball.height` down (7 → 5).** It is now a FILL knob as well as an art knob: `min_half` grows the plume quad by `height + sink` on all four sides. | ~1.15x on the ball-fire quad | shorter plumes |
| **5** | ⬜ **`ball_arc_max` / `ball_arc_height` down.** These set `min_half.y` for BOTH quads directly, and a lower cap shrinks the loop as well as the fill. | similar to 4, on both quads | a flatter pattern; ties into ruling 13 |
| **6** | ⬜ **`noise_ratio = 0` on `fire_ball.tres` ALONE** — drops the second noise layer for plumes and leaves cards untouched. Uniform branch, ~a third of that quad's noise cost. | ~1.1x on ball fire | plumes read coarser and flicker less |
| **7** | ⬜ **Fewer arcs** (`ball_arcs_max` 8 → 6 → 4): the nearest-ball lookup does fixed work PER ARC, so it is near-linear in the lookup. | up to ~1.3x on `juggle balls` | the ladder is a look decision the owner made (owner 2026-07-28) |
| **8** | ⬜ **Cap simultaneously lit balls, or juggling cards.** Feature scope. | unbounded | gameplay |

**Structural, and worth more than any knob above — but they fight a ruling:**

| | lever | worth | what it fights |
|---|---|---|---|
| **9** | ⬜ **MERGE THE TWO JUGGLING QUADS** into one shader: one `fx_nearest_ball`, one fill, instead of two of each. | large — the two quads are ~equal halves of the layer | plumes must draw BEHIND balls (§0g's tree-order fix, which handed back occlusion for free) and one-shader-per-effect (§5b) |

⚠ **THREE THINGS THAT LOOK LIKE LEVERS AND ARE MEASURED NOT TO BE.** Do not spend time here:
`FxStyle.pixel` (quantizes a coordinate — the quad still runs once per SCREEN pixel: §6f); `cover_taps`
on `fire_ball` (the ball branch SOLVES for the tap index with one `sqrt`, so that quad pays no mask
lookups at all: §0e); and deleting anything from the ARC maths (hoisted to 8 evaluations per fragment
in §1a.1 — it is not the cost any more).

### 0e. `cover_taps` — why you do NOT want it as low as possible

**What it is.** The ladder takes `cover_taps` mask samples straight down from each fragment, spread
across `height`, and `cover` is read off the first one inside the art. It is **the only thing that
costs** — +0.081 ms per tap per full burning screen — so the instinct to minimise is right.

**Why 2 is not always the answer: taps are not a quality dial, they are the RESOLUTION OF THE
SHAPE-FOLLOWING.** One tap step is `height / cover_taps` art units, i.e.

```
FX pixels per tap = height / (cover_taps * pixel)
```

Three things break as that grows, and the first is the one that matters:

1. **The fire stops hugging the art.** `cover` is how the flame knows where the surface is, to one tap
   step. At 4 FX pixels per tap the inner boundary follows a curve or a diagonal in 4-pixel jumps —
   which is the form-fitting the whole model exists for. The hoop's arcs and a warped card's corners
   show it first.
2. **Thin art gets missed entirely.** A feature thinner than one tap step can be straddled and light
   NOTHING — `cover_below`'s ball branch says it outright (*"a ball smaller than one tap spacing can
   sit entirely between two taps"*), and a hoop's wall or a blade's thickness is the same case. Bald
   patches, not softness.
3. **The flame loses its vertical gradient.** `cover` has only `taps + 1` values, so 2 taps is a hot
   base and one cooler band. `cover_dither` hides the BANDING; it cannot invent unsampled detail.

**And the floor: below ~1 FX pixel per tap you are paying for detail the grid cannot show**, because
`p` is quantized to `pixel` before anything samples it.

**Target 2–4 FX pixels per tap**, plus: a tap step must not exceed the thinnest art the fire should
hug. At the intended style values:

| style | height | pixel | flame is | 2 taps | 4 taps |
|---|---|---|---|---|---|
| `fire_card` | 7 | 1.0 | 7 FX px | 3.5 px/tap | **1.75** ✅ |
| `fire_prop` | 20 | 2.5 | 8 FX px | **4 px/tap** ✅ | 2 |
| `fire_ball` | 6 | 1.0 | 6 FX px | 3 px/tap | **1.5** ✅ |

⚠ So the owner's `cover_taps = 2` on `fire_prop` is a **reasonable trade, not a mistake** — a prop
flame is only ~8 FX pixels tall. The card and the ball want 4: short in ART units, fine in PIXELS.

⚠ **Judge it on `00_cover_field` (the raw ladder, the only place `cover_dither = 0`) and then on
`01_fire_ladder` DRESSED** — the bet the whole model makes is that 4 taps' banding is invisible under
the noise. Re-run `fx_cost.tscn` after: three runs, take the minimum.

### 0f. ⬜ Art calls only the owner can make

1. **THE RETUNE.** The `.tres` were MIGRATED, not tuned. Four numbers were DERIVED and are not taste:
   the three `pixel` values (the game's one pixel size — 1.0 card and ball, `ART_PIXEL_SCALE` = 2.5 on
   a prop) and the prop's `height`/`sink`. Everything else is yours.
2. ⚠ **`fire_prop.tres` HAS BEEN CLOBBERED THREE TIMES** by the §11 editor collision, every time this
   pass edited `fx_fire_style.gd` with the FX editor open. It currently carries `cover_taps = 2`,
   `level_ref = 60`, `pixel = 2.5` and nothing else — `dither`, `height`, `sink`, `aperture`,
   `fire_gain`, `noise_scale`, `noise_scroll`, `flicker_speed` are all at card-shaped defaults, which
   makes a prop flame ~3 art pixels tall. **DO NOT RESTORE IT BLIND**: some of that state is the
   owner's tuning. §0g has the test for telling clobbering from tuning. Ask.
3. The fire ramp's ENDS (entry 0 makes a 1-stack flame near-black; entry 19 puts neutral grey at the
   white-hot end — one-line edits to `Assets/Palette/ramp_fire.tres`); prop art SIZES; `level_ref`;
   `aperture` / `fire_gain` per style.
4. **Owner playtest (T15)** still blocks "done" — FX_SHADER_PLAN §10, 17 steps. It is also the only
   way to learn whether §6b's saturated window is reachable in play at all.

### 0g. The findings worth keeping — five rounds of owner reports, compressed

⚠ **Every one was reproduced with an INSTRUMENT before anything changed, and the snapshot harness
caught NONE of them** — it renders at ~2x zoom with no reference grid, and most of these are invisible
unless the fire is beside the game's real pixels. The instruments that worked: a card rendered at real
board scale over a **one-art-unit checkerboard**, a `SHAPE_BOX`-vs-`SHAPE_RADII` A/B, a **row dump** of
lit-pixel counts and colours per FX row, and a **400k-sample distribution** of the noise expression.

| symptom | root cause, measured | fix |
|---|---|---|
| **not pixelated** | `FxStyle.pixel` was never the game's pixel. A card draws art one texel per unscaled unit (so 1.0); a prop's art is `frame_px * ART_PIXEL_SCALE` in its own local space (so 2.5). Shipped were 0.4 and 0.45 — **2.5x finer than a card's pixels and 5.5x finer than a prop's.** | the three styles carry 1.0 / 1.0 / 2.5; `test_fx_pixel_is_the_games_pixel` pins it |
| **nothing animates in the FX editor** | `_on_screen()` reads spaces that belong to the running game: `get_viewport_rect()` is the editor WINDOW, and `get_global_transform_with_canvas()` carries the editor's pan/zoom. **Measured on the real `fx_editor.tscn`: 2 of 6 hosts off-screen at 1152x648 before any panning.** The CLOCKS keep running, which is why it reads as frozen, not stopped. | `_on_screen()` returns true under `Engine.is_editor_hint()` |
| **corner chamfer / curvature**, twice | `u_radii` held a RADIUS, and interpolating a function with a VERTEX in it cut 2.32 art units. ⚠ **The table was EXACT at every ray (worst error 0.000)** — so the fault was never `measure_outline`. Two dead ends: more rays only shrinks it (32→-2.32, 64→-1.41, 128→-0.56), and interpolating `1/r` fixes the scalloped side bulge and nothing at the vertex. | `u_radii` holds a RADIAL SCALE against the rest rectangle, so the RADII branch reduces to the EXACT box at rest (§10 E, taken). ⚠ Three places share that contract: `radii_scale`, `_fill_radii_from_outline`, `measure_silhouette` |
| **"stacked masks, hard edges, big gaps"** | (a) `cover` has only `taps+1` values and the ramp is `filter_nearest`, so each was a flat hard band ringing the silhouette; (b) my own tip-weighted aperture made the base `n*gain`, which SATURATES above gain ~1.4 — a flat slab with a hard edge | (a) the ladder's PHASE is dithered per FX pixel (`cover_dither`) — one hash, **no extra taps**; (b) gains down to 1.6–1.8 |
| **flame bottoms look off** | The row dump showed the foot was **ONE flat colour edge to edge**. The noise could not break it: measured, `fx_fbm` alone spans 0.185..0.815, AVERAGING the two layers narrows it to 0.215..0.786, and `mix(0.5, n, amp)` at the shipped `amp = 0.5` left a swing of just **0.358..0.643**. ⚠ **So every ragged edge in the build up to then was the cover ladder showing through, not the noise.** | `fire_noise` expands about flat with a contrast gain so `amp = 1` reaches the full range with ~5 % clipping (clipping is WANTED — solid cores, clean cutoffs); default `noise_amp` 0.8 |
| **`height` jitters the effect sideways, sub-pixel gaps at the seam** | `fx_local` anchored the lattice on the QUAD: cell centres at `(k+0.5)*pixel - extent/2`, so the grid's phase was `-extent/2 mod pixel` and `reach = height + sink` swept it. A/B'd — leftmost fire pixel 168→167→166→165→164 over `height` 7.0→7.4, then **228 fire pixels spilling over the art**. ⚠ And the second face is worse: **the grid was never aligned to the art's pixels at all, except by luck.** | the lattice is anchored on the HOST'S ORIGIN. `u_partner_extent` deleted with it, and ⚠ **§6a's objection to lever B is void** |
| **fire not behind props / balls** | props: `inner_alpha` had to be a NON-DEFAULT to work, and Godot omits any property equal to its default when saving — so the editor ate it twice. balls: the mask resolves the nearest **LIT** ball, so a plume passing an UNLIT one painted over it | `inner_alpha` default is 0.0 (no clobbered `.tres` can undo a default); `FxJuggle.requests` returns `[ball_fire, balls]` so tree order puts every ball over every plume — which hands back the occlusion §2 traded away, free |

⚠ **HOW TO TELL AN EDITOR CLOBBER FROM REAL TUNING**, because it decides whether you restore: Godot
omits any property equal to its script default, so an absent line is ambiguous alone. When
`fire_prop` was clobbered, `fire_card` and `fire_ball` were re-saved in the same pass and **every
property they dropped equalled a current default** — nothing lost. `fire_prop` dropped ten that did
not. **That asymmetry is the tell.** A real non-default that appears (e.g. `cover_taps = 2`) is
something the owner typed; keep it.

⚠ **AND THE STANDING LESSON: a green metric is not a green look.** "0 fire pixels over the art" passed
while the fire plainly was not behind it (§0c). Every claim in this section that survived was one an
instrument could fail.

### 0h. The files that moved

| file | what happened |
|---|---|
| `Shaders/fire.gdshader` | the rewrite: `cover_below` + `fire_noise` replace the march, the comb, `tendril`, the ogee and the onion shells; `radii_scale`; the FX-grid dither |
| `Shaders/fx_common.gdshaderinc` | origin-anchored `fx_local` / `fx_pixel_snap`; `fx_nearest_ball` returns the winner's position; `fx_ball_pos` and `fx_quantize` deleted |
| `Shaders/juggle.gdshader` | reads that position instead of re-deriving it |
| `UI/Fx/fx_fire_style.gd` | 13 exports retired; aperture/gain/taps/`cover_dither`/noise knobs and the whole "Stack scaling" group added |
| `UI/Fx/fx_fire.gd` | `stacks_live` drives every knob from `log(stacks)`; `FX_MAX_TENDRILS`, `overflow`, `merged` deleted |
| `UI/Fx/fx_attachment.gd` | no cull in the editor; `_rect_radius`; reach + sink; `u_partner_extent` push gone |
| `UI/Fx/fx_juggle.gd` | `u_emit_width` gone; `[ball_fire, balls]` order |
| `Shaders/Styles/fire_*.tres` | migrated — ⚠ **not tuned**, and see §0f.2 |
| `Assets/Fx/noise_fire.png`, `tools/make_fx_noise.py` | new — the baked tile and its generator |
| `Tests/` | `00_cover_field` / `00b_aperture` replace the tendril shots; the ONION section died whole; the stack-ratio walk; tap-sweep and noise-source cost rows; two new pins |

**And then §0c/§0d, on top of all of that:**

| file | what happened |
|---|---|
| `Shaders/fx_common.gdshaderinc` | `fx_local_raw` — the same point, NOT quantized, for occlusion tests only (§0c) |
| `Shaders/fire.gdshader` | the inner-alpha cut tests that point for BOX/RADII, `p` for SPRITE/BALLS |
| `UI/Fx/fx_request.gd` | `min_half` — an effect's own content extent, replacing body-plus-reach (§0d) |
| `UI/Fx/fx_attachment.gd` | `_size_quad` honours it |
| `UI/Fx/fx_juggle.gd` | both juggling quads declare it, from `fx_balls_near`'s own box |
| **`Tests/Visual/fx_behind.gd` / `.tscn`** | **NEW — the seam instrument: hosts drawn FILLED, at up to 6 px per art unit. `fx_snapshot` cannot answer a seam question and never could (§0c)** |
| `Tests/Visual/test_pixels.gd` | `test_balls_ignore_their_hosts_rotation` — the rotated-ball claim as an ASSERTION (§0d.1); `_host_balls` takes a `deg` |
| `Tests/Visual/fx_snapshot.gd` | prints the counter-rotation per case and re-reads it POST-CAPTURE, so the flake in §0d.1 is diagnosable next time |

---

---



---



---


---


---

## 1. ✅ JUGGLING WAS TOO EXPENSIVE — ~2.4x cheaper on the GPU

**Measured** (`Tests/Visual/fx_cost.tscn`, 20 juggling cards, 5 balls each, all lit). The bench now
prices the two juggling quads SEPARATELY — one row for both hid which of them was expensive:

| 20 hosts, GTX 1070 | before | after | GPU timer, before → after |
|---|---|---|---|
| juggle balls | 1.28 ms | 0.52 ms | 1.458 → 0.446 |
| ball fire | 1.68 ms | 0.69 ms | 1.863 → 0.670 |
| **juggle both** | **2.37 ms** | **1.20 ms** | **2.539 → 1.062** |

Card fire and the props were untouched by design and are unchanged (0.45–0.51 ms for 20).

⚠ The wall-clock column includes ~0.4 ms of CPU that does NOT shrink with fragment work: 20
attachments pushing per-frame uniforms for 2 quads each. The GPU timer is the honest read of a
shader change on this machine, and it is implemented here (it returns a flat 0.0 on the Intel UHD's
driver, which is why the original measurement had to use wall-clock).

### 1a. The three levers, all taken

1. **THE LADDER IS HOISTED.** `fx_arc_ladder()` resolves every arc's start and share ONCE per
   fragment into two local arrays; `fx_nearest_ball` and the ball-position lookup read that table.
   Before, `fx_arc_span` summed the whole ladder and then walked it, `fx_ball_at` did the same, and
   the nearest-ball loop called the first once per arc and the second twice per arc — ~384
   `fx_arc_weight` evaluations per fragment at the 8-arc ceiling, each carrying a `sqrt`, none of
   them varying across the quad. It is 8 now. Zero visual change; the probes in every ball shot moved
   by less than a pixel.
2. **`fx_balls_near()` REJECTS THE EMPTY MAJORITY.** One box test — the loop is `span` wide and one
   tall arc high, and every arc starts and ends at y = 0 — before any fragment pays for the lookup.
   The fire quad passes a margin of one flame height plus `sink`. On the fire quad this also skips
   the down-march, which is ~20 mask lookups.
3. **THE QUADS TOOK THE BOX BOUND.** `FxRequest.rotates_with_host` is a per-REQUEST property now: the
   juggling quads set it false (the pattern does not turn with its host — §4 proves it), so they keep
   the 38x50 box instead of the 62.4 diagonal, ~22 % of their fill. Fire on a card still needs the
   diagonal, and still gets it.

### 1b. ✅ SUPERSEDED — THIS LEVER HAS SINCE SHIPPED, AND ITS "TRAP" WAS A HARNESS FLAKE (§0d)

⚠ **Read §0d and §0d.1 for what actually happened. Everything below is the state of the argument
before that, kept because the displacement it describes is real — as an artefact of
`05f_ball_rotation`, which reproduces it on an UNCHANGED build about one run in five.**

The quads are STILL sized as body-plus-reach on **every** side, because `FxRequest.reach` is a
decorator's rule. A juggling pattern is 33 art units wide and 32 tall on a 38x50 card and gets a
**112x125** quad for it. Letting the request declare its own half-extent and shrinking the quad to
the larger of that and the host's bound gives 46x72 — and it is worth **~25 % of the juggling layer's
GPU time** (`juggle both` GPU 1.062 → 0.724).

**It was implemented, measured, and REVERTED, because it moved the rendered balls on a ROTATED host.**
`05f_ball_rotation` went from sub-unit probe offsets at every angle to **+6.1 art units at 90
degrees** and +2.3 at 45, the whole pattern displaced along +x, growing with the angle. Shrinking
only the X axis reproduced it; not shrinking reproduced nothing; the fire quad's own shrink did not.
The quad's uniforms and its transform are byte-for-byte identical at every angle — `u_extent` is
printed per case and does not change with rotation, the attachment counter-rotates the quad, and the
pixel lattice works out to the same half-integer set at either size — so no mechanism was found, and
an unexplained displacement is exactly the class of thing that produced two rejected builds. It is
not shipped. If you pick it up: the experiment is three lines (`FxRequest.min_half` plus two lines in
`FxAttachment._size_quad`), and `05f_ball_rotation`'s probe output is the instrument.

⚠ Note that the rotated panels of this harness carry a standing "not reproducible" warning for
`02_fire_rotation`. Rule that in or out FIRST — run the same build twice — before believing either
result. That was not done.

---

## 2. ✅ FIXED — a lit ball's plume disappeared and came back

Owner: *"fire on balls sometimes disappear, then reappear later."*

**The cause was NOT the one the last edition of this file predicted.** It guessed the unlit-ball
suppression below; that is real and is also fixed, but the disappearing plumes were a comb bug:

- **A BALL WAS TREATED AS A CELL OF A COMB ANCHORED TO THE QUAD.** `u_emit_width` made the comb TILE
  at ball pitch so each ball would catch roughly one cell. But a comb does not move and a ball does.
  Two consequences, and the second is the bug: a ball crossing a cell boundary lost its flame (the
  arch's own outline is zero there) and changed its flame's identity, phase and flicker; and
  `tendril`'s grow-in ramp — `(id >= floor(cells)) ? fract(cells) : 1.0`, which is a SPANNING comb's
  rule and only a spanning comb's — read `cells = 1` on the tiled comb and multiplied the flame
  height by **ZERO for every cell past the first**. A ball's plume therefore died the moment it
  travelled right of the quad's centre and reappeared when it crossed back to the left. Measured on
  the new `06b_ball_fire_cycle`: at phases 0.00 and 0.50 the two lit balls of six sat exactly at the
  x > 0 positions and BOTH plumes were gone.
  - **Fixed by anchoring the arch to the ball**: one flame per ball, centred on the ball's own snapped
    centre, `grow = 1`, `fan` measured across the pattern (it was `xc / (emit_width * 0.5)`, which for
    a ball is one DIAMETER — a ball 15 units out was fanned as if it stood 11 cell-widths off centre,
    and its tip was flung outside its own arch). `grow` and `fan` are now caller-supplied.
- **AND the nearest-ball lookup now resolves the nearest LIT ball** (`lit_only` in `fx_nearest_ball`).
  High above ball A the nearest ball is often a different ball B, and an unlit B returned
  "solid, emits nothing" — an unlit ball actively suppressing a lit one's plume. `MASK_DARK` has no
  producer left and is deleted. What that gives up is occlusion of a plume passing behind an unlit
  ball, which the owner pre-ruled as the cheaper of the two.

**The regression guard is `06b_ball_fire_cycle`**: six balls, two lit, stepped around the whole cycle.
**Two plumes in every panel** — verified at all six phases. A single-phase shot could never have
caught this, which is exactly how it got past `06_ball_fire`.

⚠ `fire_ball.tres`'s `merge = true` and `base_width = 2.0` were WORKAROUNDS for the straddle. Merge is
now skipped for balls (a ball has no neighbouring cell to fuse with) and a `base_width` of 2.0 makes a
flame twice its ball's width. Both are ART numbers, so they are left for the owner rather than
retuned by an agent — but they are the first things to try if ball flames now read too fat.

---

## 3. ⬜ ACCEPTED — the hoop's tendrils look sliced

⚠ **THE MECHANISM IS GONE WITH THE ARCH (§0), SO THIS IS PROBABLY MOOT — BUT IT IS NOT VERIFIED.**
A per-column `cover` has the same shape of hazard, so look at the ring before crossing it off.
The reasoning below is kept because the 22.52 ms it prices is still the price of the only correct fix.

Unchanged, and unchanged on purpose. Each column's flame is anchored to that column's own surface, so
where the ring falls away steeply a flame's top can sit below its own base on the high side. The only
correct fix is cross-column anchoring, measured at **22.52 ms for 20 hoops** against 1.21 without —
the design the owner pre-ruled out. Letting a column stand on a NEIGHBOUR's floor is the trap he
spotted (the base then floats over void). **The owner's standing rule: an anchor ships measured or not
at all.** Two rejected builds came from approximating it. He has said it does not look too bad.

---

## 4. ✅ DONE — the FX editor turns, and juggling is proven not to

`fx_editor.gd` has a `Host rotation` slider in its **Stage** group (`-180..180`, degrees), applied to
every host, with the body outlines and card faces turning with them so the tool cannot lie about what
is tilted. A rotated host takes the diagonal quad bound, exactly as a spinning card does.

The gap that let this go unverified is closed: **`fx_snapshot`'s new `05f_ball_rotation`** puts a
juggling card at 0 / 30 / 45 / 90 degrees. The oracle crosses are drawn WORLD-UPRIGHT there
(`_Ghost.ball_rot` cancels the slot's rotation), which makes the shot self-verifying — the balls must
sit on their crosses on a visibly tilted card. **They do, to under one art unit at every angle.** So
the requirement was already satisfied structurally, as predicted: `juggle.gdshader` never reads
`u_shape_rot` and `FxAttachment._push_live` counter-rotates the quad.

---

## 5. ✅ DONE — the ember tunables are in the editor, and the preview updates while you type

**The tool now re-reads its resources four times a second** (`FxEditor.WATCH_SECS`) and rebuilds when
anything the owner can edit has moved (owner 2026-07-31: *"changing vfx parameters in editor does not
update in real time, requiring closing scene and reopening each time"*).

**Why it did not before, and why polling rather than signals.** `Resource.changed` is emitted by
`emit_changed()`, which built-in resources call from their setters and a script's plain `@export var`
does not — so editing `height` on `fire_card.tres` told nobody. The tool's own `_touch()` setters only
fire when an export is ASSIGNED a different resource, which is not what tuning looks like. The
alternative was hand-written `emit_changed()` in ~35 FxStyle setters plus ParticleSpec and PaletteRamp,
which goes stale the first time a knob is added. The poll is one function and cannot.

Two things the poll needed, both of which had already silently broken live tuning:

- ⚠ **`Array` and `Dictionary` are REFERENCES in GDScript.** Storing one stores a window onto the live
  value, so a `PaletteRamp.indices` entry edited IN PLACE — which is what retuning a colour does —
  compared equal to itself for ever. The snapshot duplicates them. This was caught by a check, not by
  reading: the fire ramp was the one thing the watch could not see.
- ⚠ **`FxStyle` caches its ramp texture and drops that cache only from its OWN setters**, so editing
  an entry inside the `PaletteRamp` left the stale texture in place for the rest of the session.
  `_drop_ramp_caches()` re-assigns each ramp property to itself, which is the only invalidation these
  resources have. Same story for `ParticleSpec._gradient`.

The clocks and the per-slot seeds now SURVIVE a rebuild, because a fresh `FxAttachment` rolls a random
seed and a random phase — un-preserved, a rebuild four times a second teleported every ball and
re-scattered every tendril, so a drag read as the effect flickering rather than as the parameter
changing.

### 5a. Where the ember knobs are

`fx_editor.gd` exports `card_ember_spec` and `prop_ember_spec` (`ember.tres` / `ember_prop.tres`)
beside `show_embers`, so every ember knob — lifetime, speed, spread, gravity, drag, sizes,
`ramp_source`, `ramp_alphas` — is one click away while the preview is on screen. They MIRROR
`FxStyle.ember` rather than overriding it (`_mirror_ember_specs`): a window onto the spec each fire is
really throwing. **To point a fire at a DIFFERENT ember, set it on the fire style** — assigning here
is snapped back on the next rebuild. (It used to write through, which was harmless only while nothing
else moved; at four rebuilds a second it would stamp the tool's value over an edit made to the `.tres`
itself, and the editor might then save that.)

**How many** embers per second is still `FxStyle.ember_rate_max` on `fire_card` / `fire_prop` /
`fire_ball`, because a rate belongs to the fire that throws them, not to the particle. That split is
documented on the export.

⚠ `ember_prop.tres` deliberately carries no comments — the editor strips them on save. Its rationale
lives on `FxStyle.ember`'s doc comment. Keep it that way.

### 5b. ✅ ONE STYLE CLASS PER EFFECT

Owner: *"both fire and ball effects existing in same location for editing is confusing. Why does fire
effects allow tuning ball and ball effects allow tuning fire? it should be separate"* — and then,
having seen a `kind` flag do it: *"its worth doing now before ive decided on final params so no
refactoring in the future since there are migration hazards. waiting will become more expensive."*

So it is inheritance, and the flag is gone:

| | knobs in the inspector |
|---|---|
| `FxStyle` (base) | `pixel`, `brightness`, `opacity`, `ember_rate_max`, `ember`, and a virtual `apply()` |
| `FxFireStyle` — `fire_card` / `fire_prop` / `fire_ball` | 37 (the 32 fire levers + the 5 shared) |
| `FxJuggleStyle` — `juggle_default` | 23 (the 18 ball levers + the 5 shared) |

`FxRequest.style` is still the base and `FxAttachment` still only touches base members, so nothing in
the attachment layer learned which effect it carries.

**Why not the flag, in one line each** (the long version is on `FxStyle` itself): the inspector filter
needs a per-kind name table as soon as there is a third effect; one shared `apply()` writes every
kind's parameters at every material, and an unused parameter costs ~140 bytes **per material** —
per quad per host — so the waste scales with the board, not with the number of styles; and "New
Resource" now cannot produce a fire style with ball knobs. Verified after the split: a fire material
carries no `u_ball_*` parameters at all.

**The split found two more copies of one bug.** The ball PATH was being read from three places:
- `FxStyle.apply()` pushed `u_top_fraction` / `u_ball_gravity`, so the ball-fire quad read the path
  off the FIRE style while its balls read it off the JUGGLE style. They agreed only because both sat
  at their script defaults — `05d_ball_gravity` was drawing plumes at gravity 1.6 while its balls
  flew at 1.0 and 2.4.
- `FxAttachment._ember_origin` read `style.ball_top_fraction` / `style.ball_gravity` off the ball-fire
  request's style — a FIRE style — to place embers on a ball.

Both now read the eased values out of `FxJuggle.geometry()`, which is the one place the path lives and
which hands the same numbers to both quads. This is the same class of bug the shared
`fx_common.gdshaderinc` exists to prevent, and it had quietly reappeared twice on the script side.

⚠ **Migration notes, if another kind is added later.** Do it with the editor CLOSED. A `.tres` needs
its `script_class=`, its script `ext_resource` (drop the stale `uid=`) and any properties the new
class does not have. Then run `Godot --headless --path solatro --import` — a new `class_name` is
invisible until the global class cache is rebuilt, and the failure looks like *"Could not find type
FxFireStyle in the current scope"* on every file at once.

---

## 6. ✅ MEASURED ON THE SLOW MACHINE — and it found the number nobody was looking for

⚠ **EVERY NUMBER BELOW IS THE RETIRED BUILD.** It is kept because it is the only Intel UHD data that
exists and because §6b's reframing — *host count is the wrong axis, the bound is the WINDOW* — still
governs. **§0b is the shipped build, on a GTX 1070.** Nobody has run the noise fire on the Intel box;
that is an item in §8.

**Taken 2026-07-29 on the owner's box: Intel UHD Graphics, driver 31.0.101.2135, Godot 4.7.1,
gl_compatibility.** Suite green first (28 suites, exit 0). **Read the GPU-TIMER column below** — the
old note that `viewport_get_measured_render_time_gpu` returns a flat 0.0 on this driver is WRONG and
has been corrected in `fx_cost.gd`; it works, and the wall-clock column swings ~50 % run to run on
this box while the timer holds to ~3 %.

| GPU timer, ms/frame | 20 hosts | 50 hosts (deck viewer) |
|---|---|---|
| empty scene | 0.003 | 0.004 |
| card fire (BOX) | 2.05–2.16 | 3.90 |
| **card fire (DEFORMED — what a real card is)** | **4.11 at rest, 4.90 warped** | **12.08** |
| prop fire (hoop) | 2.07 | 4.86 |
| prop fire (knife) | 0.29–0.33 | 0.61 |
| juggle balls | 0.93 | 1.96 |
| ball fire | 1.84 | 4.27 |
| **juggle both** | **2.68–2.79** | **6.42** |

### 6a. ✅ THE PERF WORK LANDED — 2.1x on a burning screen, and off-screen is now genuinely free

| Full window, 78 cards, GPU timer | before | **after** |
|---|---|---|
| 78 burning cards, edge to edge | 16.13 | **7.61** (2.1x) |
| 78 burning AND juggling, 5 lit balls each | 26.15 | **16.84** (1.55x) |
| the same 78 plus **3x more OFF-SCREEN** (312 hosts), WALL clock | 24.70 | **18.33 — the same as 78** |

**Two changes, and BOTH are provably pixel-identical** (`py solatro/tools/snapshot_diff.py`: all 18
snapshot panels byte-for-byte unchanged, suite green at 28 suites / exit 0):

1. **`body_near()` in `fire.gdshader` — the empty majority, rejected first.** `fx_balls_near`'s lever
   (§1b.2) generalised to every other shape. One box test against the body's world-aligned bound at
   the live rotation, before the ~20-lookup march. **It cannot change a pixel**: every fragment it
   rejects is one where `surface_below` could not have found a surface within reach. Worth the whole
   2.1x on burning cards, because an 84.8² quad around a 38x50 card is mostly empty and every empty
   fragment used to walk the full march to find nothing.
2. **`FxAttachment._on_screen()` — an off-screen host stops UPLOADING.** Godot culls the quads, so the
   GPU never cared; nothing culled `_push_live`, which is ~15 `set_shader_parameter` calls per quad
   per frame. 234 invisible hosts were costing **~6.4 ms of pure CPU** — more than the whole visible
   board's GPU time. ⚠ The CLOCKS still advance unconditionally; only the upload is skipped, or a
   scroll would teleport every ball as its card came back into view.

⚠ **NEITHER CHANGE HELPED THE JUGGLING LAYER'S GPU COST, AND THAT IS NOW THE DOMINANT HALF.** Asked
directly (owner, 2026-07-29: *"did we find any ways to save ball juggling time?"*) — **no.** Measured
before and after, 20 hosts, GPU timer: `juggle balls` 0.93 → 0.90, `ball fire` 1.84 → 1.82,
`juggle both` 2.7 → 2.7. All inside run-to-run noise, and it is structural, not an accident:

- `body_near()` sits in the **`else` of `if (u_shape == SHAPE_BALLS)`**. The ball-fire quad IS
  `SHAPE_BALLS`, so it kept `fx_balls_near` — which already did exactly this job (§1b.2). There was
  nothing left to reject.
- `juggle.gdshader` is a **separate shader with no march at all**, so none of §9's analysis touches it.

Only the off-screen skip helped juggling, and only on the CPU — where it helps MOST, since a juggling
host carries two quads to a burning card's one.

⚠ **And yes, this box is much slower than the machine §1 was measured on: `juggle both x20` is 1.06 ms
on the GTX 1070 against 2.71 here — ~2.5x.** That ratio holds across the rows and is the reason §1's
absolutes cannot be used for a ship decision.

**What is actually left for juggling**, in order:
1. **§0 covers two thirds of it already.** `ball fire` is 1.82 of the 2.71 and it is the FIRE shader
   wearing `SHAPE_BALLS` — so the noise rewrite lands on `fire_ball.tres` like any other fire style.
   Do not plan separate ball work before §0.
2. **§6f.1's quad extent** (`FxRequest.min_half`) — ~25 % of the juggling layer, written once and
   REVERTED for displacing balls on a rotated host. Its trap, and the reproducibility question that
   was never settled, are in §1b.
3. The balls quad itself (0.90) is already cheap after §1's three levers. Leave it.

**The remaining worst case is 16.8 ms — one frame at 60 fps** for a window packed edge to edge where
EVERY one of 78 cards is both burning and juggling five lit balls. Burning-only is 7.6 ms (43 %).
⚠ **Ask whether that saturated case is reachable in play at all** before spending anything more.

⚠ **Lever B was MEASURED AND NOT SHIPPED.** `fx_cost`'s `BOX-BOUND quads` row prices its ceiling:
16.84 → 15.46, i.e. **1.16x, not the 1.6x predicted before lever A landed** — A had already taken the
march cost out of exactly the fragments B would remove. Against that, B resizes a live quad, which
moves the FX pixel lattice, and a card's tilt juice turns it by up to 10 degrees on every move — so
it risks shimmer on every card that moves, for 14 %. **Not worth it as designed.** If it is revisited,
quantize the bound (box up to ~15 degrees, diagonal beyond) so the tilt juice never triggers a switch.

⚠ **The juggling layer is now the dominant half**: 16.84 total against 7.61 for burning alone. The
next real lever is §1b.1's quad extent on the ball quads, with its trap.

### 6b. ⚠ HOST COUNT IS THE WRONG AXIS — the bound is the WINDOW

Owner 2026-07-29: *"cards off screen don't affect performance right? if true we only need to limit
performance to worst case in one window."* **Correct, and now proven** — `fx_cost` has the rows:

| Full window, board scale, GPU timer | ms | verdict |
|---|---|---|
| **78 burning cards, edge to edge** | **16.13** | 96 % of a 60 fps frame |
| **78 burning AND juggling cards** | **26.15** | **150 % — 37 fps** |
| the same 78, plus **3x as many parked OFF-SCREEN** (312 hosts) | **25.60** | **identical: off-screen is FREE** |

4x the hosts for the same cost. The fire shader is FRAGMENT-BOUND and Godot culls canvas items
outside the viewport, so a 200-card deck with 78 on screen costs what those 78 cost. **Every "x20 /
x50" row below is therefore a proxy, not a budget.** The budget is the row above, and the worst
window the game can build misses it by 1.5x.

⚠ **And that reframes what is worth fixing.** Fragment count, not lookup cost, is the multiplier:

- **FILL.** A 38x50 card gets an **84.8 x 84.8** quad — `body.length()` (the 62.4 diagonal, because a
  card CAN spin) plus reach on all four sides. That is **3.8x the card's own area**, so a packed
  window draws the fire shader ~3.8 times over. Most of those fragments are empty quad corners that
  still run the whole march.
- **MARCH LENGTH.** Every surviving fragment walks up to `u_height / u_pixel` ~ 20 mask lookups.
- **LOOKUP COST.** RADII vs BOX is 1.9x — real, but the SMALLEST of the three, and the only one §10
  was about.

### 6c. The per-host verdict, in three lines

1. **JUGGLING IS FINE.** 20 juggling cards with every ball alight is ~2.7 ms — the worst case in the
   game, at the owner's ~2 ms target and 0.13 ms per card against a 0.2 ms budget. §1's work landed.
2. **THE PROPS ARE FINE.** Hoops are the dearest at 2.07 ms for 20, and nothing regressed.
3. ⚠ **BURNING CARDS ARE NOT, AND THE OLD TABLE WAS MEASURING THE WRONG SHAPE.** `fx_cost` built its
   card row as a `Shape.BOX`. A real board card is not one — `CardVisual` hands its attachment the
   star rig's outline, so it takes the **RADII** branch of `mask_level`, which costs an `atan`, a
   table index and a lerp on **every step of the down-march** where the box is one ray/rect exit.
   Priced apart on the new row: **the branch alone is ~1.9x the box (2.13 → 4.11)** and the corner
   warp adds fill on top (→ 4.90). At deck-viewer density it is **12.1 ms, 80 % of a 60 fps frame,
   for the fire alone.** This cost has been there the whole time; only the row is new.

### 6d. ⚠ SUPERSEDED BY §0 — kept only because the reasoning still applies to the mask

1. **`radii_reach` OUT OF THE MARCH.** The march never leaves its column but does move in y, so the
   angle changes at every step and the `atan` cannot simply be hoisted. What CAN be: the RADII mask
   is a star, and a star's boundary in a column is one y per x — the same closed form the box branch
   gets. Worth measuring before designing.
2. §6e below, unchanged, for the juggling layer — which no longer needs it.

⚠ **Judge any of these by EYE on `fx_snapshot` before believing the number.** Two rejected builds
came from approximating the mask.

### 6e. How the numbers above were taken

```bash
# 1. Sanity: the suite must be green BEFORE you trust any number. Windowed, ~60-85 s.
Godot --path solatro res://Tests/all_tests.tscn            # exit code = failure count; expect 28 suites, 0

# 2. The numbers. NOT a test — it prints a table and quits. Takes ~1 min.
Godot --path solatro res://Tests/Visual/fx_cost.tscn

# 3. The pictures, if anything looks wrong in play. Writes PNGs and quits.
Godot --path solatro res://Tests/Visual/fx_snapshot.tscn
```

⚠ **Before the first run on a fresh checkout**, if scripts fail to load with cascades of
*"Identifier FxAttachment not declared"* / *"not present on the inferred type Variant"*, the import
cache is stale, not the code:

```bash
Godot --headless --path solatro --import
```

That run also rewrites `Locale/localization.en.translation` and deletes two `~`-prefixed
GDExtension DLLs, **all tracked** — `git status` afterwards and revert what you did not mean to
change.

⚠ **A Godot run that prints nothing and never exits has failed to parse its main script.** Redirect
to a file and read the FIRST lines; piping to `tail` shows you nothing until exit, which never comes.

Raise `HOSTS` in `Tests/Visual/fx_cost.gd` from 20 to 50 for the deck-viewer column and re-run.

- **The owner's target is ALL FX on screen ≤ ~2 ms, i.e. ~0.2 ms per juggling card.**
- ⚠ 20 juggling cards with every ball lit may never happen in play. If 3–5 cards are comfortable
  that is a legitimate answer, and it changes what is worth doing.
- ⚠ **The GTX 1070 and this Intel UHD are ~2x apart on these rows, not the ~12x the old note in this
  file assumed.** `juggle both x20` is 1.06 on the 1070 and 2.68–2.79 here. Ratios still transfer
  better than absolutes, but the gap is much smaller than anyone had written down.

### 6f. If the juggling layer ever needs it again — the older levers, in order

1. ✅ **THE QUAD EXTENT — TAKEN, 2026-07-29. §0d has the shipped numbers; the paragraph below is the
   pre-ship argument and its reproducibility question, which §0d.1 answers.** The quads are sized as
   body-plus-reach on EVERY side, so a 33-unit-wide juggling pattern gets a 112x125 quad. §1b has the
   whole story: it is three lines (`FxRequest.min_half` plus two in `FxAttachment._size_quad`), it
   measured `juggle both` GPU 1.062 → 0.724 here, and it was **reverted because it displaced the balls
   on a rotated host** by up to +6.1 art units. **Run `fx_snapshot.tscn` twice on an unchanged build
   first** and diff the `PROBE` lines of `05f_ball_rotation`: this harness carries a standing
   "rotated panels are not reproducible" warning, and nobody has ruled that in or out. If the offsets
   are stable across two runs, the displacement is real and needs a mechanism; if they are not, the
   revert was over-cautious and the lever is free.
2. **`fx_fbm` at one octave** (`fx_common.gdshaderinc`). Three octaves is seven hash+lerp taps per lit
   fragment. Dropping to one is a visible texture change — show the owner `01_fire_ladder` before and
   after — but it is the largest remaining per-fragment cost in the fire shader.
3. **Fewer arcs**: `FxStyle.ball_arcs_max` (8 today, on `juggle_default.tres`). The nearest-ball
   lookup does fixed work PER ARC, so 8 → 6 → 4 is a near-linear cut in the lookup, and the ladder is
   a LOOK decision the owner made — do not change it without asking him.
4. **Fewer lit balls at once**, or a cap on simultaneously juggling cards. Feature scope, owner only.

⚠ **DO NOT start by raising `FxStyle.pixel`.** It quantizes a COORDINATE inside the fragment shader;
the quad's screen footprint is unchanged and the shader still runs once per screen pixel. That advice
was in this file for weeks and it is wrong.

⚠ **Re-run the suite AND `fx_snapshot.tscn` after every one of these, and LOOK at the PNGs.** Judge
fire by eye, never by counting columns — that instrument reported two rejected builds as successes.

---

## 7. ✅ DONE — the fire WARPS with the card now

Owner 2026-07-29: *"card visual has bones and a default running animation which can heavily distort
the edges of the card... I don't see the fire effect warping with the card during playtesting."*

**The cause was that the silhouette was measured ONCE, at rest.** `CardVisual._ready` called
`fx.measure_silhouette(type.polygon)` — the REST vertices of the baked grid — and nothing ever
re-read it. The card's face polygons are skinned to a 16-arm star rig whose animation is on
**autoplay**, so the drawing moved every frame while the mask stayed a 38x50 rectangle. Rotation- and
mask-proofing could not have helped: neither one is a *deformation*.

- **THE RIG IS NOW THE SOURCE.** `_bind_rig` caches `Bone_Center` and its 16 arms; `_rig_outline`
  composes their tips from the bones' OWN local transforms every frame and `FxAttachment
  .track_outline` re-resolves the radius table the RADII mask already reads. No shader change: the
  32-entry table was always the right carrier, it was simply never refreshed.
  - ⚠ **Local transforms, NEVER `global_position`.** The rig hangs under `visual`, which carries the
    basis3d flip — a basis that goes SINGULAR edge-on — and the bob. Ruling 1 keeps both off the
    effects, and going through globals would collapse a flipping card's silhouette to a line and take
    its flames with it.
- **THE RAYS ARE RESOLVED, NOT BUCKETED.** `measure_silhouette`'s angular histogram + neighbour-max
  gap fill inflates a 16-point star by up to ~5 art units between a corner and the edge sample beside
  it — a lump of flame standing off the card. `measure_outline` intersects each of the 32 rays with
  the ONE outline segment spanning its angle, in a single merged walk (32 + n steps, not 32 * n),
  which is what makes it cheap enough to run on every card every frame. It takes an ORDERED outline;
  unordered points still belong in `measure_silhouette`.
- **THE QUAD GROWS WITH THE WARP** (`_radii_max`), or a stretched corner's flames clip on the quad
  edge they were built inside; and **`u_body` is now the DEFORMED width**, because that is what the
  comb divides — at the authored width the outermost tendril stops short of the corner that moved.
- **Early-out on an unmoved outline**, so a settled card pays the walk and no upload.

**The regression guard is `fx_snapshot`'s new `02b_card_warp`**: corners at +0 / 10 / 25 / 45 %, with
the outline the attachment was handed drawn underneath. One glance — every flame base must sit on the
drawn outline, corners included. Verified: the top edge's flames follow the concave dip, and the
stretched corners carry their own flames.

**The FX editor has the knob**: `corner_warp` in the **Stage** group, beside `Host rotation`, driving
`CardVisual.star_outline` — the cards' own shape, not a copy. The face and the outline warp with it,
so the tool cannot lie about what is bent.

⚠ **IT DOES NOT REACH THE PROPS, and that is deliberate.** A prop's mask IS its drawing's alpha
(`Shape.SPRITE`); there is no outline to stretch, and no prop deforms in the game. Warping one would
need a warp term in `fire.gdshader`'s SPRITE branch — a shader change and an owner call, not a tool
one. Said plainly on the export.

---

## 8. What is LEFT — the index; §0 is the text

⚠ **This section is deliberately a POINTER LIST.** It used to restate §0 and the two drifted; if a row
here and §0 disagree, §0 wins.

| | Item |
|---|---|
| ✅ **TASK 1 OF 2** | **§0c — fire renders behind the art.** Route 1, the unquantized cut, one line. ⚠ **A LOOK claim: the owner has not seen it.** Route 3 (the `FxBack` node) is still the answer if his eye disagrees. |
| ✅ **TASK 2 OF 2** | **§0d — juggling performance.** `min_half`: the layer is 1.44x cheaper, 18/18 panels byte-identical. ⚠ Its old blocker was a harness flake (§0d.1) and the claim now has an asserting check. |
| ⬜ **THE BIGGEST OPEN GAP** | **§0c.2 — no harness renders a real `CardVisual`.** Every card panel everywhere is `star_outline`, a hand model of the rig, and the FX EDITOR DRAWS THAT SAME ARRAY AS THE CARD'S FACE — so it cannot show a face-versus-mask disagreement at all. The props were always tested with real art; the card never was, which is the card-vs-prop divergence in one sentence. **The test that closes it is specified in §0c.2 and it is the next thing to build.** |
| ⬜ **The warped card's spikes** | **§0c.1 — fire over the art at a warped corner.** The 32-ray mask cannot represent a vertex; the cut follows the mask. ~1 art unit at the warp the rig actually reaches, obvious past it. A one-run experiment (`RADII` 64) or an analytic star branch — owner call. |
| ⬜ **Juggling, if it is needed again** | **§0d.2 — the priced menu.** The free levers come first, and the off-centre quad is worth ~1.4x for no visual change. ⚠ The budget is already met on this box; do not spend a look change on it. |
| ⬜ **Blocking "done"** | **Owner playtest (T15)**, FX_SHADER_PLAN §10, 17 steps — **the last gate, with the art calls in §0f and the real-card test above.** Also the only way to learn whether §6b's saturated window is reachable in play at all. |
| ⬜ **Owner art calls**, incl. the retune and the clobbered `fire_prop.tres` | §0f. |
| ⬜ **RE-MEASURE ON THE INTEL UHD** | Every number in §0 is a GTX 1070; §6 and §9 are the owner's Intel UHD, ~2x apart. Ratios transfer, absolutes do not. Two rows are genuinely likely to FLIP on the slow box: the noise-source A/B (ALU vs shared memory bandwidth) and whether 6 cover taps are affordable. Three runs, take the minimum (§0a). |
| ⬜ **RE-MEASURE `min_half` ON THE INTEL UHD TOO** | The 1.44x of §0d is a GTX 1070. It is a pure FILL cut, which is the multiplier §6b says dominates on the slow box, so it should transfer or do better — but it has not been run there. |
| ✅ **Closed this pass** | The noise fire and its stack ratios (§0a/§0b); the corner chamfer (§10 E, taken); §3's sliced tendrils (gone with the arch, confirmed on `04_shapes`); the pixel size, the editor freeze, the tap banding, the flame's foot, the `height` jitter, and fire-behind on balls. All in §0g with the measurement that found each. |
| ⬜ Known limitation | Ball highlight is a quantized ellipse at small radii — pixel-art resolution, not a defect. Levers: `ball_spec`, or a smaller `pixel` on the juggle style. |
| ⬜ Deferred by the owner | Map screen + in-game UI chrome still hardcoded (they warn `[WARN][PLACEHOLDER]` every run); `FireworkVisual` has no art; `suit_pips.png` has a few off-palette pixels. |

---

## 9. WHERE THE COST ACTUALLY IS — four attribution runs, and they settled the design

⚠ **THIS IS THE ARGUMENT THAT PRODUCED §0, AND IT IS NOW THE BASELINE §0 BEAT.** Read it for the
reasoning, not for the shipped numbers: the two conclusions at the bottom were both correct, and §0b
re-measures the same claims on the build that replaced this one (where the tap cost came out dead
linear at +0.076 ms per tap, exactly as this section predicts).

All on the same 78-card full-screen burning row, GPU timer, everything else held constant:

| what was changed | ms | vs shipped |
|---|---|---|
| **shipped today** (march, up to 35 steps at `pixel` 0.4) | **7.61** | — |
| every TENDRIL computation deleted (ogee, onion, sway, wave, fan, drift, merge, 4 `pow`s) | 7.29 | **-4 %** |
| the march replaced by **8 shifted mask taps** | 6.36 | -16 % |
| the march replaced by **4 shifted mask taps** | 4.46 | **-41 %** |
| the march replaced by a CONSTANT (zero mask lookups) | 2.17 | -71 % |

**The cost is `mask_level` CALL COUNT x cost per call. Nothing else in this shader matters.** It is
linear at ~0.48 ms per tap per full screen, and the shipped march behaves like ~11 effective taps —
its early `return` helps less than it looks, because a GPU warp runs until EVERY lane exits and in
the empty band above the flames no lane ever hits.

Two conclusions, and they are the opposite of what each change looks like on its own:

1. ⚠ **DROPPING TENDRILS SAVES NOTHING BY ITSELF — 4 %.** And it would likely cost more than it saves:
   `fx_fbm` is guarded behind `heat > 0` (the single biggest saving in the file), and a fire whose look
   IS moving noise evaluates noise across the whole band rather than only where a tendril put heat.
2. ✅ **BUT IT IS WHAT MAKES THE MARCH REPLACEABLE, AND THAT IS WORTH 1.7x.** A shifted-mask
   accumulation — *"how much body is below me within reach"*, fixed tap count, no early-out, no
   divergence — needs FEW taps to look right only if nothing downstream needs a precise surface
   height. Tendrils do: at `pixel` 0.4 the arch springs from a surface located to 0.4 art units, which
   is ~11 taps. Noise does not: 4 taps over a 14-unit reach is 3.5-unit resolution, and noise shaping
   hides the banding. **The two decisions are worthless apart and compound together.**

⚠ **THE COMB IS NOT THE COST, AND DELETING IT BUYS NOTHING** (owner asked, 2026-07-29; verified in the
source). `w` / `cells` / `pitch` / `id` are built at `fire.gdshader:479-484` and read at exactly three
places — the `tendril_at` calls — so the comb does go when tendrils do. But it is a floor, a clamp and
two divides, and **not one of the shader's `mask_level` calls is in it**: they are all inside
`surface_below` (296, 301, 312) plus the single inner-alpha test (523). Lanes never caused a lookup.
What costs is the PRECISION the tendril needs from the march — at `pixel` 0.4 over a 14-unit reach,
locating the surface is ~35 steps worst case and ~11 effective.

⚠ **Keep `u_count` when the comb goes.** `FxAttachment._emit_embers` reads it as the ember rate, so it
has to survive as an INTENSITY value even with nothing left to partition.

It also fixes three things for free: multiple surfaces per column stop being a special case (§1's
whole requirement falls out of the accumulation), nothing can leap a hole (no tap reaches further than
`reach`), and there is no angular surface-finding left to chamfer a corner (§7).

⚠ **And the SECOND factor is still open**: each tap on the RADII branch carries an `atan`, which is
why a card's mask is 1.9x a box's. Cutting taps AND making each tap cheaper (§10 E, or a column-height
table) multiply — 4 cheap taps would approach the 2.17 floor.

## 10. The levers, ordered by win x safety — and the correction that produced this order

⚠ **A AND THE TAP WORK HAVE SHIPPED; the rest of this table is still live.** A is `body_near`, in
the shader since §6a and carried through the rewrite intact. B and C are unchanged and untaken. D
and F are moot — there is no march left to shorten or unwarp. **E is the one to keep**: it is the
only remaining answer to §8's corner chamfer if the mask is ever revisited, and it makes every tap
cheaper, which multiplies with the tap count rather than adding to it.

⚠ **An earlier edition of this section offered TWO options and implied that was the space.** It was
not, and the framing was wrong: it only considered the MASK REPRESENTATION, which §6b shows is the
smallest of the three multipliers. The list below is the actual space. **A, B and C need no mask
change at all**, and between them they are worth more than any redesign.

| | Lever | Worth | Visual risk |
|---|---|---|---|
| **A** | **REJECT THE EMPTY QUAD FIRST.** One box test — is this fragment within `height + sink` above the body's bound? — before the march, exactly what `fx_balls_near` does for the juggling quads (§1b.2). The empty corners of an 84.8² quad currently run ~20 mask lookups to find nothing. | large | **NONE** — a pure early-out; the rejected fragments already draw nothing |
| **B** | **THE DIAGONAL BOUND ONLY WHILE THE CARD IS ACTUALLY TURNED.** `_size_quad` takes `body.length()` because a card *can* spin — but `anim_spin` is rare and `u_shape_rot` is ~0 the rest of the time. A live bound is 60.2x72.4 against 84.8², i.e. **0.61x the fill on every burning card.** | ~1.6x | low — the lattice changes when the bound does, so check for jitter as a spin starts |
| **C** | **THE QUAD IS BODY-PLUS-REACH ON EVERY SIDE**, including below, where a card's fire never goes. §1b's `min_half`, and its trap was the JUGGLE quads on a rotated host, not this one. | ~1.3x | low, but re-read §1b first |
| **D** | **COLUMN HEIGHT FIELD.** The march exists to find the top surface in a column; for a card that is a 1-D function of x, so ~20 lookups collapse to 1–2. ⚠ It does NOT generalise — the hoop has two surfaces in one column and §1 exists for that — so it is a per-shape path, which brushes the owner's *"fire should be unified and identical in how it treats everything"*. And a WARPED card has two surfaces per column near the spikes, so it needs two entries. | very large | medium |
| **E** | **BOX TEST + RADIAL SCALE.** Divide `q` by a smooth per-angle scale, then test `abs(q) <= h`. Fixes §7's corner chamfer EXACTLY (a scale field has no vertex to miss, and the rig's deformation IS a radial stretch). Costs about what RADII costs today. | fixes correctness, not speed | low |
| **F** | **UNWARP ONCE, MARCH IN REST SPACE.** Every mask test becomes the two-comparison box: the whole 1.9x. ⚠ APPROXIMATION — world-down is not exactly down in rest space, so the march drifts across columns on a strongly warped card, and approximating the mask is what produced the two rejected builds. | 1.9x | **high** |

**Recommended order: A, then B, re-measure §6b after each, and only then decide between D and E+C.**
A and B are non-visual and together should be worth ~2.5x on the number that is 1.5x over budget.

⚠ **Do NOT just raise `RADII`.** The numbers are in §7: it converges far too slowly on a sharp vertex
to be worth the uniform bytes (32 → -2.32, 64 → -1.41, 128 → -0.56 art units).

---

## 11. Runbook

`Godot` below is the console build — on this box
`C:\richard\Godot_v4.7.1-stable_win64_console.exe`, run from `C:\richard\gamedev`.

```bash
Godot --path solatro res://Tests/all_tests.tscn            # windowed, ~60-85 s, exit = failure count
Godot --path solatro res://Tests/Visual/fx_snapshot.tscn   # after ANY shader edit
Godot --path solatro res://Tests/Visual/fx_behind.tscn     # the SEAM: hosts drawn FILLED (§0c)
Godot --path solatro res://Tests/Visual/prop_art_snapshot.tscn
Godot --path solatro res://Tests/Visual/fx_cost.tscn       # ms/frame per host kind — not a test
py solatro/tools/palette_conformance.py
py solatro/tools/snapshot_diff.py save                     # stash the PNGs you trust as a baseline
py solatro/tools/snapshot_diff.py diff                     # re-run fx_snapshot, then prove nothing moved
py solatro/tools/make_fx_noise.py                          # re-roll Assets/Fx/noise_fire.png
```

⚠ **`fx_cost.tscn` NEEDS THREE RUNS ON THIS BOX, AND YOU TAKE THE MINIMUM.** The GTX 1070 sits in two
power states and the GPU timer is bimodal by ~1.3–1.5x between them, with every row of a run scaled
by the same factor — five consecutive runs of ONE unchanged build read 0.594, 0.597, 0.753, 0.874 and
0.924 on the same row. A single run is not evidence; consecutive runs agreeing to ~1 % are. (§0b.)

**For a change that must not alter the picture, `snapshot_diff.py` is the instrument, not your eye.**
"Judge fire by EYE" is right for a change that is SUPPOSED to look different; an optimisation's only
honest claim is byte-identical, and an eye is far too generous for that. Both §6a changes were
landed on it.

Last full run (2026-07-29 late, GTX 1070 box, with §0c and §0d in): **28 suites, exit 0** — two runs
read 1571 and 1555 checks, and **PIXELS: ALL 37** in both (34 before this pass, plus §0d.1's three
rotated-ball checks). The total COUNT varies run to run because BOARD FUZZ is randomised; what must
hold is 28 suites and exit 0.

⚠ **TWO RENDERING HARNESSES HANG AT RANDOM ON THIS BOX, AND NEITHER IS A FAILURE.** Measured
2026-07-29 while A/B-ing §0d: `test_pixels.tscn` run STANDALONE printed all 37 checks and then never
exited, in four consecutive runs, with the change both ON and OFF — so that one is an exit hang, and
the checks are what matter. `all_tests.tscn` hung MID-SUITE once (inside the PIXELS modulate shot,
awaiting `frame_post_draw`) and completed cleanly on the next run of the identical build. **Both were
briefly mistaken for a bug in the change under test. Re-run before believing a hang**, and time the
runs out rather than waiting (a hung run holds a window at ~10 % CPU forever).

⚠ **LEAK CANARY is mildly FLAKY** — it failed once in four consecutive runs of an unchanged build
with `growth 2` and two stray `/Fx` Node2Ds, and passed the other three. Zero tolerance and a
deferred-free path; re-run before believing it.

⚠ **`Godot_*_console.exe` must sit NEXT TO the real `Godot_*.exe`** or it exits 255 with *"Main
executable ... not found"* and no other clue. On this box the real one is on the Desktop.

⚠ **DO NOT round-trip a source file through PowerShell `Get-Content | Set-Content`.** PS 5.1 reads as
ANSI and every `⚠`, `§` and `—` in these heavily-commented files comes back mangled. `git checkout --`
the file and re-edit.

**Judge fire by EYE, never by counting columns** — that instrument reported two rejected builds as
successes. `py <scratch>/crop.py <png> <out> x y w h scale` (PIL, nearest-neighbour) is how these were
reviewed; a snapshot panel is too small at 1x. **Read `fx_snapshot`'s PROBE lines**: they print, per
expected ball, how far the nearest rendered ball actually is, in art units. Everything under ~2 is
agreement (the search finds an EDGE pixel, so it reads a radius pessimistically).

### Traps, each of which cost real time

- ⚠ **A GODOT RUN THAT PRINTS NOTHING AND NEVER EXITS HAS FAILED TO PARSE ITS MAIN SCRIPT.** The
  scene loads without the script, so nothing quits and the window sits idle at ~10 % CPU. Redirect to
  a file and read the FIRST lines rather than piping to `tail`, which shows you nothing until exit.
- ⚠ **`res://.godot` can be missing imports, and every symptom points somewhere else.** A stale or
  partial import cache made every `class_name` in the project unresolvable ("Identifier FxAttachment
  not declared", "the method sync() is not present on the inferred type Variant") — hundreds of
  cascading parse errors that look like a broken edit. Fix:
  `Godot --headless --path solatro --import`. ⚠ That run also rewrote `Locale/localization.en.translation`
  and deleted two `~`-prefixed GDExtension DLLs, all of them TRACKED — `git status` afterwards and
  revert what you did not mean to change.
- ⚠ **`Callable.bind` puts the OUTERMOST bind's arguments FIRST.** `f.bind(a)` passed into something
  that then calls `.bind(b)` arrives as `f(x, b, a)`, not `f(x, a, b)`. It fails at runtime, not at
  parse time, and the row still prints — as a negative millisecond delta.
- ⚠ **`return` is not allowed in a Godot fragment processor.** An early-out has to be a flag or a
  wrapping branch. Arrays as function parameters and `out float a[N]` DO work (Godot 4.7,
  gl_compatibility) — `fx_arc_ladder` depends on it.
- ⚠ **AN OPEN EDITOR AND AN AGENT EDITING SCRIPTS WILL COLLIDE, AND THE `.tres` LOSES.** Measured
  2026-07-31, live: while `FxStyle` was being edited from a session, the owner's editor saved five
  style resources — writing `kind = null` into three of them (a property whose script it had only
  half-loaded) and dropping `dither` from `fire_card.tres`, `spread` from `ember_prop.tres` and
  `gravity` / `size_start` / `size_end` from `ember.tres`. **A `.tres` written while its script is
  mid-edit keeps only the properties the editor could see.** Every `null`-tolerant setter in
  `fx_style.gd` exists because of this. If both are working at once: `git diff Shaders/Styles/`
  before believing any test result, and re-check the dropped values by hand.
- ⚠ **Running the project DELETES two tracked `~`-prefixed GDExtension DLLs**
  (`addons/big_number/...`, `addons/worldgen/...`) — Godot's Windows unload artefact, not anything a
  session did. They come back with `git checkout --`; they probably should not be tracked at all.
- ⚠ **The owner's editor REWRITES scenes and `.tres` on disk.** It dropped `speed_base_delay = 0.1`
  from `Tests/all_tests.tscn` mid-session (the script default is 0.01), which shrinks a jump tween
  from 30 ms to 3 ms against a once-per-frame poll and made `test_ui_props` fail deterministically
  with nothing about the game changed. **Re-read anything you edited, and `git diff` before blaming
  your own change.** Comments do not survive an editor save.
- ⚠ **A `git stash` A/B LIES when the editor has touched a tracked file** — the baseline half gets
  the committed value and the "after" half gets the editor's, so an unrelated change looks causal.
  Check `git status` first. This cost five bisects, a wall-clock A/B and an `--max-fps 60` run.
- ⚠ **A check that polls for a transient must be slower than a frame**, or it measures the frame
  budget rather than the behaviour. Grep the UI suites for `WATCHDOG_SECS` before trusting a failure.
- ⚠ **A rendering test with a random input is not a test.** `FxAttachment._seed` is `randf()` per
  host and drives ball spin, which moves the highlight — the PIXELS suite now pins `att._seed = SEED`
  before `sync()` at every construction site. Per-host randomness is read when the quads are BUILT.
- **`Texture2D.get_image()` + `Image.get_pixel` is a real hitch** (2304 calls for one hoop frame,
  once per attachment, three per split prop). `FxAttachment._sprite_cache` exists for that reason.
- **The GLSL shading language has `PI`, `TAU`, `E` — but NOT `HALF_PI`.** Using it compiles to
  nothing and every effect renders SOLID WHITE, which looks exactly like the `@tool`/placeholder
  failure. `smoothstep` also wants its edges in increasing order; reversing them is undefined.
- **Every script in `UI/Fx/` and every FX host must stay `@tool`.** A non-tool script loads as a
  PLACEHOLDER: `FxStyle.apply()` never runs (white effects) and saving a `.tres` DROPS the properties
  the editor could not see.
- ⚠ **Never kill a Godot process without reading `MainWindowTitle` first.** The owner's editor was
  killed on 2026-07-29 by a blanket `Get-Process *odot* | Kill()`.
- `PropVisual._ready()` early-returns in the editor, so a snapshot scene and the editor can disagree.

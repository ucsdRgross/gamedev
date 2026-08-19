# FX_HANDOFF.md — live handoff (FX PERFORMANCE IS **PAUSED**, not finished)

> ⚠ **STALE — the card is 40x54, not 38x50** (the outline change). Every measured FX number in this file was taken on a 38x50 card and is stale by **~12 % of fill** — the quad went 84.8² -> ~89.2², the diagonal 62.80 -> 67.20, the card area 1900 -> 2160 art². The ARGUMENTS all still hold; the NUMBERS want re-running with `fx_cost.gd` before any of that budget is spent again. They are deliberately left as measured rather than rescaled by hand.


🟢 **THERE IS NO OPEN ENGINEERING TASK IN THIS FILE.** The fire effect's LOOK is closed (§0, §0c), and
the performance pass took the worst window the game can build from **12.07 to 5.82 ms of
GPU**. Owner, after the last measurement: *"sure lets stop here then."*

➡ **IF YOU ARE HERE TO SPEND MORE BUDGET, START AT [§0d.10](#0d10--restarting-the-performance-work--the-one-page-version).**
It is the one page that matters: today's numbers, every lever still on the table with an honest price and
risk, and — the part that will save you the most time — **the list of things that look like levers and are
measured or reasoned NOT to be**, so you do not re-tread a day of this pass.

➡ **IF YOU ARE HERE TO CHANGE HOW THE FIRE LOOKS**, read §0a–§0c for the model and §0f for the art calls
that are the owner's. **Then read [VFX.md](VFX.md) and ARCHITECTURE_REVIEW §4g** (the map and the contract).

**WHERE THE PERFORMANCE PASS WENT, so you do not re-take any of it:**

| | what | worth |
|---|---|---|
| ✅ | **[§0d.6](#0d6--one-instance-per-ball--the-juggling-layer-is-32x-cheaper-and-the-search-is-deleted) — ONE INSTANCE PER BALL.** The closed-form nearest-ball search is DELETED. ⚠ Read the three things that went wrong doing it; one made a broken build look 10x faster | juggling half of the window **5.46 → ~1.7 ms**; `juggle both x20` **1.822 → 0.220** |
| ✅ | **[§0d.7](#0d7--the-cpu-half--_push_live-was-42-msframe-and-nobody-had-ever-measured-it) — THE CPU HALF.** `_push_live` sends 2 uniforms per frame instead of ~15 | **4.21 → ~1.3 ms/frame**, and it was invisible to the GPU timer |
| ✅ | **[§0d.9](#0d9--two-levers-taken--650--466-ms-and-the-first-one-is-two-lines) — CARD FIRE.** Buried fragments no longer pay the tap ladder (TWO LINES, 1.27x), plus §10's lever B | `burning, FULL SCREEN` **6.496 → 4.657 ms** |
| ⬜ | **`cover_taps` 4 → 2 on `fire_card`** — the one lever left that is worth a whole millisecond | **0.98 ms**, and it is a LOOK call the owner has NOT made (§0e argues against it) |
| ⚪ | **[§0d.5](#0d5--closed-by-0d6--the-brief-kept-for-its-budget-and-its-history)** (the old juggling brief) and **[§0d.2](#0d2--void--the-priced-menu-and-none-of-it-was-spent)** (its nine priced levers) | **VOID as guidance**, kept as history — not one of those nine levers was what worked |

### What the fire is, in five lines

`fire.gdshader` is a **cover field carved by scrolling noise**: `cover` is how far above the nearest
surface below a fragment sits, measured in `u_taps` mask lookups, and everything above it is the
Kinomoto aperture/gain form over two noise layers. The tendril / comb / ogee / onion build is gone.
Every knob carries a stack ratio (§0b). **The cost of this shader is `mask_level` call count times cost
per call and nothing else** (§9) — which is why `cover_taps` is the only knob that matters and why the
mask's representation was worth getting exactly right.

### Everything the owner asked for on fire, and where it landed

| | asked | landed |
|---|---|---|
| ✅ | *"average fire shader effects like moving noise"*, params scaling with stacks | §0a / §0b — the noise fire and its exported stack ratios |
| ✅ | *"fire effect always be behind main card art"* | §0c — the unquantized alpha cut, cards and props. **Owner has now seen it: *"fire looks good on rotations, no longer jagged"*** |
| ✅ | *"still clipping at edges when warping"* | §0c.1 — the mask carries the outline's OWN VERTICES (`u_poly`/`u_wedge`) instead of 32 interpolated rays. **26.9 art units of unlit column → 1.0**, at +6 % on a burning screen |
| ✅ | *"has this issue... been that fx editor doesnt use real card visual"* | §0c.2 — a real `CardVisual` is under test at last, and it proved the stand-in was **2.3–3.3 art units** from any pose the rig makes |
| ✅ | *"use actual TypePaper visual for fx editor... no useless mocks"* | §0c.4 — the tool hosts real cards, `rig_pose` seeks the card's own animation, and the whole card data chain is `@tool` so it survives the editor |
| ✅ | *"fx editor shows corner texel not being accounted for"* — and *"do card and prop use same mask code or not?"* | §0c.5 — the type frame's clipped corners are in the outline, measured off its own alpha and exact under deformation; **zero** disagreeing cells against a real card. Costs 16 % of a burning screen. §0c.5 also answers the second question: one shader, ONE branch apart, and why a card cannot use the prop's. |
| ✅ | *"another performance test... on slower comp"* | §0d.3 — the Intel UHD table. ⚠ **The two boxes are 5x–8x apart, not the ~2x this file claimed for weeks** |
| 🟡 | *"new task is solving card fire time"* | **§0d.9 — two levers taken, 6.50 → 4.657 ms (1.39x).** The buried-fragment early-out (two lines, 1.27x) and lever B. ⬜ **Open: `cover_taps` 4 → 2, worth 0.98 ms, a LOOK call** |
| ✅ | *"saving juggling performance"* | §0d.6 — **ONE INSTANCE PER BALL.** The juggling half of the worst window is **5.46 → 1.71 ms** and `fx_nearest_ball` is deleted. ⚠ The layer is **CPU-bound now** (wall 10.97 vs GPU 8.23 on that window), so the next millisecond is in `_push_live`, not in a shader |

### Three things that will bite you if you skip them

1. 🔴 **`snapshot_diff.py` WAS BLIND UNTIL TODAY** (§0d.4) — it compared ALPHA only, so it called every
   colour change "identical". **Every "18/18 panels identical" claim written before that fix is
   vacuous**, `min_half` and `body_near` included. The tool is fixed; the claims were never re-earned.
2. ⚠ **RATIOS FROM THE GTX 1070 DO NOT TRANSFER** (§0d.3). Re-run `fx_cost.tscn` on the Intel box —
   three runs, take the minimum — before you believe any number in this file that is not labelled
   Intel UHD.
3. ⚠ **A RENDERING HARNESS CAN LIE TWICE OVER**: run it twice before believing a red picture (§0d.1's
   flake), and remember that `09_embers` differs run to run by design.

Sections are numbered in reading order. If you add one, keep it that way — an earlier edition had
§6.-1 and put §7b before §7a, and it cost a reader real time. **§1 to §7 are mostly the RETIRED
build**: read them for what was learned and what must not be broken, not as a description of what is
there — each one now says at its head whether it is live. **§8 is the live list**; §9 is the cost
attribution that justified the rewrite; §11 is the runbook.

⚠ **The owner will run the `simplify` skill over the unpushed commits.** Land behaviour first; do not
pre-emptively restructure for tidiness.

---

## 0. THE NOISE FIRE — the shipped build, and the one task left

🟢 **LIVE — this is what is in the game.** §0d.5 is the open task; everything else here is the record of what was built and what it measured.

Owner: *"Fire effect no longer has tendrils at all, just average fire shader effects like
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

### 0c. ✅ FIRE RENDERS BEHIND THE ART — shipped, and ACCEPTED BY THE OWNER

**What shipped is ONE LINE, and it is route 1 of the three weighed below.** The occlusion cut is now
tested at the **unquantized** position:

```glsl
if (u_inner_alpha < 1.0) {
    // BALLS keep the quantized point; every other shape tests the raw one
    vec2 cut = (u_shape == SHAPE_BALLS) ? p : fx_local_raw(UV, u_extent);
    if (mask_solid(mask_level(cut, ball, ball_level))) alpha_mul = u_inner_alpha;
}
```

- The flame's own pixels stay on the FX grid — it is pixel art. **Only the boundary moved**, onto the
  resolution the art actually has, which is what real occlusion looks like.
- ⚠ **THE SNIPPET ABOVE IS THE SECOND DRAFT.** The first excluded SPRITE, on the reasoning in the next
  paragraph, and the owner caught it. ⚠ **BALLS DELIBERATELY KEEP THE QUANTIZED POINT.** Their art IS
  drawn on the FX grid (a ball by `juggle.gdshader` on the shared lattice), so there the
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

**THE SPRITE PROPS NEEDED IT TOO, AND THE FIRST DRAFT EXCLUDED THEM** (owner: *"props did
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

#### 0c.1. ✅ THE WARPED CORNERS ARE FIXED — THE MASK CARRIES THE OUTLINE'S OWN VERTICES

Owner: *"curious why fire effect goes in front of card at extreme warp, chamfering at
edges"*, then *"still clipping at edges when warping"*. **The diagnosis below was right and the menu of
fixes under it was wrong — including its own recommendation. Read §0c.2 for why: (b) was "the rest
rectangle plus four corner triangles", and the REAL rig is not that shape.**

**The diagnosis, unchanged:** `u_radii` was a 32-ray table of radial SCALE, linearly interpolated, and
no scheme that blends two rays can reproduce a VERTEX. The cut follows the mask, so a stretched corner
gave both halves of what the owner saw — flame OVER the art where the mask's chamfer line fell inside
the spike, and a BARE spike above it where the mask said "no art, nothing to stand on".

**What shipped is neither (a) nor (b): `mask_level`'s RADII branch now holds the SILHOUETTE ITSELF.**

```glsl
uniform vec2  u_poly[POLY];      // the outline's own 16 vertices, in the art's frame
uniform float u_wedge[WEDGES];   // per 1/32 turn: the vertex whose wedge spans that slot's START
uniform vec2  u_inner;           // the largest origin-centred box that fits INSIDE the outline
// inside == inside ONE wedge triangle (origin, V[i], V[i+1]), and the index finds it with no search
```

- **A shape is the union of its wedges**, so "inside" is "inside one wedge" and the only question is
  which. `u_wedge` answers it in O(1); a slot is 11.25 deg and the rig's vertices are ~20 deg apart at
  their closest, so **testing that wedge and the next one covers the slot** — which is why two, not a
  loop. `test_fx_attachment` asserts the vertex spacing, because a third vertex in one slot would leave
  a HOLE in the mask with no other symptom.
- **It is exact for a non-convex shape too**, which matters: a star's rest edge between two stretched
  corners is a reflex vertex, and the union handles a spike and a dent with the same code. A half-plane
  per slot would have been one dot product and cannot — a slot holding a vertex has no single line.
- ⚠ **IT COSTS SOMETHING, AND THE TWO BOX TESTS PAY MOST OF IT BACK.** Outside the outline's own bound
  nothing is solid; inside `u_inner` everything is; the polygon runs only in the band between. **A card
  at rest IS its authored rectangle, so the two boxes coincide and no fragment on a resting board ever
  builds a wedge** — four comparisons, against the old branch's `atan` + two fetches + a lerp + a
  divide. Measured on the owner's **Intel UHD**, three runs each, minimum taken:

| GPU timer, ms/frame | 32-ray table | bare polygon | **polygon + box tests** | net |
|---|---|---|---|---|
| **burning, FULL SCREEN** (78 cards) | 5.163 | 6.529 | **5.459** | **+6 %** |
| **burning + juggling, FULL SCREEN** | 10.435 | 11.960 | **10.775** | **+3 %** |
| card fire (DEFORMED) x20 | 1.817 | 2.238 | 2.081 | +15 % |
| card fire x20 (a BOX host!) | 0.975 | 1.073 | 1.214 | +25 % |
| prop fire (hoop) x20 — the control | 0.577 | 0.565 | 0.577 | 0 % |

  ⚠ **READ THE LAST TWO ROWS TOGETHER.** The hoop is a SPRITE and did not move at all, which is what
  makes the rest of the column trustworthy — but `card fire x20` is a **BOX** host that never enters the
  RADII branch and still got 25 % dearer, so part of the cost is the PROGRAM (two more uniform arrays,
  one more branch: register pressure and instruction cache), not the work. That part cannot be bought
  back by making the branch cheaper.
  ⚠ **The bare-polygon column is the one to reason from if the boxes are ever touched**: without them
  an exact mask costs 26 % of a burning screen, and the whole of that is `atan` + four `vec2` fetches
  per tap on hardware where a dynamically indexed uniform array is not free.
  **If 6 % matters more than the corner does, `cover_taps` is where the money is** — 4 → 2 on
  `fire_card` is measured at 5.418 → 4.174 on the same row, four times the cost of this whole fix
  (§0e has what it gives up).

- **What it measures on a REAL card** (§0c.2's new check, four points of the rig's own animation):
  worst mask-vs-drawn-face disagreement **26.9 art units → 1.0**, and 1.0 is the FX grid's own cell, so
  it is quantization and nothing else can be bought. Width agreement went to exact.
- **What it looks like** (`fx_behind`'s `behind_card_warp`, +25 / +45 %): the corner spikes carry flame
  up their edges instead of stopping at a chamfer line across the shoulder. `fx_snapshot` moves 3 of 20
  panels — `02_fire_rotation`, `02b_card_warp` and `09_embers` (embers are thrown from the mask's
  surface) — and NOTHING else, which is exactly the blast radius a mask-only change should have.
- ⚠ **The radial-scale contract is GONE, and with it `radii_scale`, `_rect_radius` and the "three places
  must agree" hazard.** What replaces it: `poly_solid` in the shader, `_fill_poly_from_outline` on the
  script side, and `PixelProbe.mask_contains` as the tests' mirror of the first.
- ⚠ **The winding is normalized on the CPU** (`_fill_poly_from_outline`). The wedge index and
  `wedge_has` both read the walk as angle-INCREASING, so an outline handed over backwards would index
  the wrong edge and mask as empty everywhere — a card with no fire at all, from a caller that did
  nothing wrong.

#### 0c.2. ✅ A REAL `CardVisual` IS UNDER TEST — and it answered the card-vs-prop divergence

Owner: *"has this issue this whole time been that fx editor doesnt use real card visual,
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
statements about the shader that hold for any outline.

✅ **THE TEST NOW EXISTS AND IT ANSWERED THE OWNER'S QUESTION BOTH WAYS.**
`test_pixels.gd`'s **`test_the_card_mask_is_the_card_the_player_sees`** instantiates a REAL `CardVisual`
(the PIXELS suite has the autoloads the `@tool` editor lacks — which is *why* the editor fakes one),
seeks its autoplay animation to four fixed times, renders the skinned face with its TEXTURE OFF so the
silhouette is the drawn geometry, and compares it to the mask **on the FX grid the fire actually samples**,
column by column. Three findings, and they split the owner's question in two:

1. ✅ **THE MASK'S SOURCE WAS NEVER THE PROBLEM.** The face's 16 perimeter vertices are each weighted
   **0.99997 to their own arm bone** (`card_visual.tscn`'s `Type` polygon), and each arm's rest position
   IS that vertex — so the drawn silhouette and `_rig_outline()` are the same 16 points. Measured: at
   rest they agree to **0.1 art units**. The "hand model vs rig" worry about the SILHOUETTE is answered:
   for a card, the outline handed over is what gets drawn.
2. ⚠ **BUT `star_outline(warp)` IS A SHAPE THE RIG NEVER MAKES**, and this is the real content of the
   owner's *"the card outline was never accurate to real cards"*. The closest `warp` to a real pose is
   **off by 2.3 to 3.3 art units** at every one of the four times, for two structural reasons: the
   shipped animation also swings the four MID-EDGE arms (`Arm_Right_2` runs 19 → 21.3 → 16, `Arm_Left_2`
   the other way), so a real card BULGES and PINCHES its long edges, and its corners do not move
   together (at t=0.15 the top-left arm is 2.9 units out while the top-right is 0.5). One radial `warp`
   cannot express either. **So every warp panel is a claim about that stand-in** — ✅ except in the FX
   EDITOR, which hosts real cards as of §0c.4 and whose slider now seeks the rig's own animation.
3. ⚠ **AND THAT ASYMMETRY HID A REAL BUG FOR THE WHOLE PASS.** §0c.1's chamfer was ~2 units on
   `star_outline` at the warp the harnesses use and **26.9 art units of unlit column on the real rig** —
   an order of magnitude apart, because the rig's corner spike is narrow and steep where the stand-in's
   is broad. That is why the panels only ever showed "a 0.17 unit sliver" while the owner kept seeing
   the corner. The stand-in did not test nothing; it tested a shape whose worst case is ten times milder.

#### 0c.3. ✅ CLOSED — the three routes, as they were weighed

✅ **ROUTE 1 SHIPPED AND THE OWNER HAS ACCEPTED IT** (*"fire looks good on rotations, no
longer jagged"*), so routes 2 and 3 are not needed. **Kept for one reason only: if a future change ever
makes the CUT wrong again, route 3 (a second `FxAttachment` before `visual`) is the structural answer and
its full plan is still written out below.** Route 2's `z_index` experiment was never run and stays
unsettled rather than dead.

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

#### 0c.4. ✅ THE FX EDITOR HOSTS REAL CARDS NOW — the tool's last mock is gone

Owner: *"please use actual TypePaper visual for fx editor since its not perfect rectangle. no placeholder
art that isnt ever seen in game, and no useless mocks when you can just use actual original scene, just
like how hoop knife use actual art."*

**Both card slots are `CardVisual.CARD_VISUAL.instantiate()` now** — the shipped scene, its TypePaper
face, its star rig, its pips, with real `CardData` built exactly the way `Deck._card` builds every card
in the game. The props already worked this way; the cards are the same door now (`_spawn_host` takes the
host's own visual and adds it BEFORE the attachment, so art draws under the effects by tree order).

- ⚠ **AND THE FACE IS NOT A RECTANGLE, WHICH IS WHY IT MATTERED.** `card_types.png` frame 2 is 38x50
  with **one texel clipped off each corner** — measured off the sheet's alpha. The flat palette-coloured
  polygon this replaced could never have shown that, and it was drawn from **the same array the mask was
  built from**, so the tool could not show a face-versus-mask disagreement at all. ✅ **And it showed one
  the same day** (owner: *"oops yeah fx editor shows corner texel not being accounted for"*): the mask was
  the RIG, the full rectangle, so the fire stood one flame pixel on nothing at each corner. **Fixed in
  §0c.5** — which is the tool paying for itself within hours of no longer being a mock.
- **`corner_warp` became `rig_pose`** — 0 to 1 across the card's own `new_animation_2`. The animation
  does not autoplay in the editor, so every pose the slider seeks is one the shipped card really passes
  through, instead of a symmetric star the rig never makes.
- **Two things a real card needed, and both are the same class of guard the props already had:**
  `CardVisual.settings()` (the `FxAttachment.settings()` pattern — the editor has no `SettingsManager`,
  and the shipped defaults are what a tuning tool should show anyway), and `_bind_rig()` moved out of the
  runtime-only block so the tool can read the same outline the board reads. `CardEnvironment` needed
  nothing: it is statics, and they answer null.
- ⚠ **THE TOOL SCENE CAN BE *RUN*, NOT JUST EDITED, AND THAT IS HOW THIS WAS VERIFIED** — a throwaway
  harness instantiated `fx_editor.tscn` in a real scene and saved a PNG, which is far cheaper than
  opening the editor. Two traps it caught, both worth knowing: a card **frees itself on its first frame**
  when run rather than edited (`delta_self_moving_logic` drops any non-play-area card with no
  `control_anchor`), and at runtime a card **builds its own `FxAttachment`**, so the preview would carry
  two. `_pose_card` parks the process and frees the card's own attachment for exactly those two reasons.
- 🔴 **AND THE FIRST DRAFT SHIPPED BROKEN IN THE EDITOR, FOR A REASON WORTH KNOWING: A NON-`@tool` BASE
  CLASS MAKES ITS SUBCLASSES PLACEHOLDERS.** Owner, minutes later: *"Invalid access to property or key
  'data_changed' on a base object of type 'Resource (CardData)'"*, *"Nonexistent function 'set_texture'
  in base 'Resource'"*, and *"dont see type art and other card art, only rank pip art"*.
  - **`PipSuitHoop` IS `@tool` and still came back as a bare `Resource`** — because `PipSuit` and
    `CardModifier` above it were not. The type name survives a placeholder; every member does not.
  - **The visible half follows from the invisible half**: the error was thrown at
    `data.suit.set_texture(suit)`, which ABORTS `update_visual` — so the rank pip (set on the line
    before) drew and the type, stamp and art (lines after) never ran. One failing call, three missing
    polygons, and `show_card_face` could not touch it because nothing was hidden; it was never set.
  - **Fixed by carrying `@tool` down the whole chain**: `CardData`, `CardModifier`, `CardModifierType`,
    `PipSuit`, `CardModifierStamp`, `CardModifierSkill` (`PipRank` and every concrete pip already had
    it). None of them needs a running game — the `CardEnvironment` reads are statics that answer null.
  - ✅ **A/B'd IN THE EDITOR, not argued**: `Godot --path solatro --editor --quit-after 400
    res://Tools/fx_editor.tscn` reproduces all six of the owner's errors with the flags reverted
    and prints **zero** with them in, and a probe confirmed `type/rank/suit/art` all visible in editor
    mode. ⚠ **That command is the cheapest way to test an editor-only claim** — it needs the owner's
    editor CLOSED, and it is how any future `@tool` question should be settled.
  - ⚠ **The pin is `test_card_preview_chain_is_tool`** in the FX ATTACHMENT suite, and it reads the
    SOURCE, because nothing that runs can catch this: at runtime every one of these classes works
    perfectly whether it is `@tool` or not.
  - ⚠ **ONE THING TO WATCH:** the editor can now see every member of these resources, so the next time it
    saves anything holding a `CardData` (`card_visual.tscn`'s own embedded default, say) the written
    property set may differ from before. `git diff` it rather than assuming a scene was untouched.
- ✅ **THE BALLS ARE FINE IN THE EDITOR** (owner: *"i can see the balls in editor, so no
  issue there"*). ⚠ Kept because it is a standing caveat about the instrument, not a bug: the juggler
  slot renders **no balls when the tool scene is RUN** rather than edited — identically on the build
  before the real-card swap, so it is a runtime-only artefact of running an `@tool` scene. **A runtime
  capture of `fx_editor.tscn` is a fair test of the CARDS and the FIRE and not of the balls.**

⬜ **THE SAME RULE STILL APPLIES TO THREE HARNESSES, and they are the follow-up:** `fx_snapshot`,
`fx_behind` and `fx_cost` all still stand up a bare `Node2D` and feed it `star_outline`. They run in a
real scene tree, where a `CardVisual` needs none of the guards above — `test_pixels` already does it in
about ten lines — so the swap is mechanical; what makes it work is pinning the card's seed and clock the
way `_park` does. Doing it would make `fx_behind`'s seam shots the real thing (its "hosts drawn FILLED"
is a filled POLYGON today, not a card) and would delete the last of `star_outline`'s users.

#### 0c.5. ✅ THE ART'S CLIPPED CORNERS ARE IN THE MASK NOW — and why a card needed this at all

Owner: *"fx editor shows corner texel not being accounted for, fix it then we are done"* —
and, fairly: *"do card and prop use same mask code or not? I thought this was already a solved issue
since hoops, knife, suit pip arts are non trivial shapes... what took so much work to make fire treat
card as non rect?"*

**THE ANSWER IS THE WHOLE REASON THIS TOOK WORK, so put it at the top of any future mask discussion:**

| host | `Shape` | how the mask answers "is there art here" |
|---|---|---|
| hoop, knife, pips, ball pip | `SPRITE` | **samples the sheet's ALPHA, live** — non-trivial shapes and the hoop's HOLE come free |
| card | `RADII` | an **OUTLINE POLYGON**, because a card DEFORMS |

Everything above the mask — the cover field, the taps, the noise, the ramp, the cut — is one code path
for every host. **The branch differs for exactly one reason: a prop's art never changes shape, and a
card's is skinned to a 16-arm rig** (posed by jumps, spins and warps; the idle does not autoplay —
`CardVisual.RIG_ANIM`). The SPRITE branch samples a static sheet through a fixed
transform, so a card on it would burn its UNDEFORMED shape — which is precisely the report §7 exists for
(*"I don't see the fire effect warping with the card during playtesting"*). Putting a card on that branch
means inverting a 16-bone skin per fragment.

So a card gets NONE of what a prop's alpha gives for free, and every bit of it has to be rebuilt
geometrically. Three separate defects came out of that, and none was polish:

1. the outline was **32 interpolated rays**, which cannot hold a vertex — up to **27 art units** of a
   stretched corner outside its own mask (§0c.1);
2. **no harness rendered a real card**, so the stand-in under-reported that by ~10x (§0c.2);
3. **the corner bite is in the ART, not the rig** — a prop never had to be told, and an outline does.

**WHAT SHIPPED FOR (3).** `CardModifierType.corner_notch()` measures the bite off the type frame's own
alpha (cached per frame, never typed in) and `CardVisual._rig_outline` emits it as the three points it
really is: in along one edge, across the bite, out along the other. ⚠ **The middle point is the corner
cell's BILINEAR corner**, so the bite stretches and shears with the rig instead of only being right at
rest. Measured across the shipped frames: `TypePaper` and most types bite one texel, `TypeInput` three by
one, the boosters none — and a frame with a STAIRCASE corner is read conservatively (it under-cuts by a
texel rather than eating art the frame draws).

- **`POLY` 16 → 24** and `WEDGE_CANDIDATES` 2 → 4: a corner's three points sit within ~1.5 degrees, so
  one wedge slot can hold three of them and covering it takes four wedges.
- ✅ **The claim is now EXACT, and the check asserts zero rather than a tolerance.**
  `test_the_card_mask_is_the_card_the_player_sees` compares **cell by cell, both sides sampled at the FX
  cell's own centre** — the point a flame pixel is actually decided at — and gets **0 disagreements in
  ~6300 decidable cells at all four poses**, where the previous draft had 4 (one per corner).
- ⚠ **IT COSTS 16 % OF A BURNING SCREEN** (Intel UHD, three runs, minimum: 5.459 → 6.344 ms; the worst
  window 10.775 → 11.649). **And the cost is the ARRAY, not the loop** — isolated with a probe: 24
  vertices with only 2 candidates already cost 6.142, so the extra candidates are 0.2 of the 0.9. Two
  micro-optimisations were tried and are recorded because the reasoning for both was sound and both
  measured WORSE: an early `break` out of the candidate loop, and packing two vertices per `vec4` (6.808
  — the shift/mask/select per fetch costs more than the padding saves).
- ⚠ **SO IF THIS 16 % EVER MATTERS, THE LEVER IS NOT THE MASK.** `cover_taps` 4 → 2 on the card style is
  worth **1.24 ms** on the same row (§0d.3), four times what the whole bite costs, and it is a look call
  the owner already has priced. The cheaper mask alternative, if it is ever wanted, is a 20-point
  DIAGONAL chamfer at 1.5x the bite depth: same pixels on the FX grid, ~half the cost, and approximate
  off it — write it down as a compromise, not as the shape.

### 0d. 🟢 FX PERFORMANCE — the whole pass, and how to restart it (§0d.10)

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

**Proof it changed nothing visible: `py solatro/Tools/snapshot_diff.py` — ALL 18 PANELS BYTE-IDENTICAL**
with the lever on versus off. That is the honest instrument for an optimisation (§11), and it is a
stronger statement than "no clipping was visible": the lattice is origin-anchored, so a correctly
sized quad renders the same pixels as an oversized one.

#### 0d.1. ⚠ THE REVERT THAT BLOCKED THIS WAS A HARNESS FLAKE — measured, and it is a lesson

This lever was written, measured and **reverted** because `05f_ball_rotation` showed the
balls displaced along +x by up to **6.1 art units at 90 degrees**, growing with the angle, with no
mechanism ever found. §1b called that "exactly the class of thing that produced two rejected builds".

**the same displacement was reproduced on an UNCHANGED build**: five consecutive runs of
`fx_snapshot`, and run one printed probe offsets of **1.0 / 2.0 / 5.8** art units at 30 / 45 / 90 while
the other four printed 0.1 at every angle. The shot has carried a standing *"rotated panels are not
reproducible"* warning the whole time; nobody had run it twice.

- The counter-rotation was **printed** and it was correct in every run (`host.global_rotation` and
  `att.rotation` exact negatives at all four angles) — that print is now permanent in `_shot`, along
  with a POST-CAPTURE re-read, so a future flake is diagnosable rather than mysterious.
- A first-run **shader-recompile** theory was tested (touch `fire.gdshader`, run once) and is **wrong**:
  that run came out clean.
- **So the mechanism is still unknown, and the assertion that was supposed to settle it is GONE.**
  A `test_balls_ignore_their_hosts_rotation` row was added to the PIXELS suite (5 balls on a host at
  30 / 45 / 90 degrees, within 2 art units of the WORLD-UPRIGHT oracle) on the theory that pinning
  `_seed` made it deterministic. It is not: measured over 8 consecutive serialised full runs of one
  unchanged build it failed 7 times, with the angle and the miss count both varying run to run, and
  sometimes failing on MISSING balls while the worst offset was under tolerance. **It was asserting
  the very non-determinism it was written to rule out**, so it gated every suite run on a coin flip
  and has been deleted. `_host_balls` still takes a `deg`, so the measurement is one call away when
  someone has an instrument that can survive it. **The rotated-ball claim has no automated gate.**

⚠ **THE STANDING LESSON, and it is the twin of §0g's:** a green metric is not a green look — and a red
picture from a flaky harness is not a red build. **Run a rendering harness twice before believing
either half of what it tells you.**

#### 0d.2. ⚪ VOID — the priced menu, and none of it was spent

⚠ **EVERY LEVER BELOW IS EITHER SUBSUMED OR UNNECESSARY AFTER §0d.6, and the reason is the interesting
part: they all shave ONE factor of a product with two wrong factors.** Levers 1, 2 and 9 are subsumed
whole (an off-centre quad, a lit-ball shrink and merging the two quads are all what per-ball instancing
already does); 3 was measured near-pointless; and 4–8 are LOOK compromises that no longer have to be
asked for. Kept as the record of how the layer was priced before the model was fitted.

⚠ **READ THE BUDGET FIRST, AND READ IT FROM THE INTEL BOX** (§0d.3). The worst window is **10.8 ms, of
which juggling is ~5.3** (`juggle both x20` scaled by the same ratio the burning rows hold, and the
`burning + juggling` minus `burning` difference agrees: 10.775 − 5.459). The owner's target is ~2 ms for
ALL FX. **On the GTX 1070 there was nothing left to buy and this list looked academic; on the box that
ships, juggling alone is 2.7x the whole budget.** That is the reframing §0d.3 forced, and it is why the
menu below is now the live task rather than a footnote.

⚠ **THE `worth` COLUMN IS GTX-1070-DERIVED unless it says otherwise.** Ratios were assumed to transfer
and they demonstrably do not (§0d.3). **Re-price the lever you pick, on the Intel box, before you build
it** — three runs, minimum, `fx_cost.tscn`.

**Free — no visual change, nothing given up:**

| | lever | worth | risk |
|---|---|---|---|
| **1** | ⬜ **AN OFF-CENTRE QUAD.** The pattern hangs ABOVE y = 0 (`fx_balls_near`: y from `-(arc+ball)` to `+ball`), but a quad is centred on the host's origin — so **~40 % of both juggling quads is empty space below the loop**, and `min_half` cannot express it because it is a half-extent. Give a request an OFFSET, fold it into `fx_local`'s `s` BEFORE the quantize, and move the mesh by the same amount. ⚠ **Safe with the current lattice and only because of it** — the grid is anchored on the host's ORIGIN, so a constant offset added before `floor` leaves it exactly where it was (this is the same reason `min_half` was safe: §0g's `height`-jitter row). | **~1.4x on the layer**, the largest thing left | medium — it is quad geometry, so §0d.1's flake will look like a bug again. `snapshot_diff` 18/18 is the gate. ⚠ The rotated-ball assertion that was the other half of this pair was deleted as non-deterministic (§0d.1). |
| **2** | ⬜ **SHRINK THE BALL-FIRE QUAD TO THE LIT BALLS.** `req.lit` is known on the CPU, so the plume quad only needs to cover the balls actually alight — usually 1–2 of many. It changes every frame as they travel, which used to be unthinkable (a live resize moved the lattice) and is now free for the same reason as above. | large in PLAY, zero in the saturated bench (where every ball is lit) | medium, plus per-frame CPU to recompute — and the bench cannot show the win, so it needs a play measurement |
| **3** | ⬜ **§6a's lever B / §10 B** — the diagonal bound only while a card is really turned. | ⚠ **1.09x, measured** (`BOX-BOUND quads` row: 1.825 → 1.672). Lever 1 already removed most of what it was measuring. | low, and now nearly pointless |

**Cheap, and they cost a LOOK the owner owns:**

| | lever | worth | what is given up |
|---|---|---|---|
| **4** | ⬜ **`fire_ball.height` down (7 → 5).** It is now a FILL knob as well as an art knob: `min_half` grows the plume quad by `height + sink` on all four sides. | ~1.15x on the ball-fire quad | shorter plumes |
| **5** | ⬜ **`ball_arc_max` / `ball_arc_height` down.** These set `min_half.y` for BOTH quads directly, and a lower cap shrinks the loop as well as the fill. | similar to 4, on both quads | a flatter pattern; ties into ruling 13 |
| **6** | ⬜ **`noise_ratio = 0` on `fire_ball.tres` ALONE** — drops the second noise layer for plumes and leaves cards untouched. Uniform branch, ~a third of that quad's noise cost. | ~1.1x on ball fire | plumes read coarser and flicker less |
| **7** | ⬜ **Fewer arcs** (`ball_arcs_max` 8 → 6 → 4): the nearest-ball lookup does fixed work PER ARC, so it is near-linear in the lookup. | up to ~1.3x on `juggle balls` | the ladder is a look decision the owner made (owner) |
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

#### 0d.3. ✅ THE INTEL UHD NUMBERS — the slow box, at last

⚠ **EVERY ABSOLUTE IN THIS SECTION IS SUPERSEDED — the worst window is 5.82 ms now, not 10.775, and
§0d.10 has the current table.** Read this section for its METHOD (three runs, minimum, editor closed) and
for the two findings that still hold: the noise-source A/B is a wash, and the two boxes are 5x–8x apart so
no GTX absolute ever transfers.

Owner: *"Do another performance test to verify current performance on slower comp."* **Taken on the
owner's own box** — Intel UHD Graphics, driver 31.0.101.2135, Godot 4.7.1, gl_compatibility, editor
CLOSED, suite green first (28 suites, exit 0), `fx_cost.tscn` three times, minimum taken. ⚠ **This box
is STEADY, unlike the 1070**: run to run it holds to ~2–3 % on most rows, so a 6 % delta is real here
and a 6 % delta on the GTX box is not.

| GPU timer, ms/frame | 32-ray build | with the exact mask | verdict |
|---|---|---|---|
| **78 burning cards, edge to edge** | 5.163 | **5.459** | 33 % of a 60 fps frame |
| **78 burning AND juggling, 5 lit balls each** | 10.435 | **10.775** | **65 % — the worst window this game can build** |
| the same 78 plus 3x more OFF-SCREEN | 10.712 | 11.495 | still free ✅ |
| card fire x20 | 0.975 | 1.214 | |
| card fire (DEFORMED) x20 | 1.817 | 2.081 | |
| prop fire (hoop) x20 | 0.577 | 0.577 | |
| prop fire (knife) x20 | 0.153 | 0.146 | |
| juggle balls x20 | 0.564 | 0.576 | |
| ball fire x20 | 1.190 | 1.311 | |
| **juggle both x20** | **1.647** | **1.912** | |

**THREE THINGS THIS SETTLES, AND THE FIRST ONE CONTRADICTS THIS FILE:**

1. ⚠ **THE TWO BOXES ARE NOT "~2x APART" — THEY ARE 5x TO 8x APART ON THE ROWS THAT MATTER.** §6's
   note (written from the retired build) said 2–2.5x, and §0/§0d's ratios were transferred on that
   basis. Against the last GTX numbers in this file: `burning FULL SCREEN` 0.681 (GTX) vs **5.459** here
   = **8x**; `burning + juggling` 1.825 vs **10.775** = **5.9x**; `juggle both x20` 0.386 vs **1.912** =
   **5.0x**. ⚠ Those GTX rows are the 32-ray build, so the gap is **at least** this wide rather than
   exactly it — nobody has run the exact-mask build on the 1070, and nobody needs to. The noise fire
   gained far more on the 1070 than on the Intel, so the gap WIDENED. **Do not
   transfer an absolute or a budget from a GTX row again; re-run here.**
2. ✅ **THE NOISE-SOURCE A/B IS A WASH, and §8 expected it to flip.** `fx_fbm` 5.438 vs the baked
   TEXTURE 5.310 on a full burning screen — 2 %, inside this box's own spread. The theory was that
   trading seven ALU taps for one memory fetch would pay off on shared-memory hardware; it does not.
   **`noise_procedural` is a look knob, not a performance one, on either box.** Item closed.
3. ⚠ **SIX COVER TAPS ARE NOT AFFORDABLE HERE, and two would buy a lot.** Full burning screen: **2 taps
   4.174, 4 taps 5.418 (ships), 6 taps 6.647, 8 taps 8.083** — dead linear at ~+0.65 ms per tap, which
   is **8x the per-tap cost on the 1070** (+0.081). So the tap knob is the single biggest lever on the
   box that matters: dropping the card style to 2 taps is worth 1.24 ms, four times the entire cost of
   §0c.1's exact mask. ⚠ It is a LOOK change and §0e is the argument against it (a card flame is 7 FX
   pixels tall, so 2 taps is 3.5 px per tap and the fire stops hugging the art) — **owner call, and now
   a priced one.**

**Against the owner's ~2 ms target for ALL FX**: burning-only is 5.5 ms and the saturated window is
10.8. ⚠ **The target is missed by 5x in the saturated case and by 2.7x for burning alone** — so the
question §6b asked is still the one that decides whether any of this matters: **is a window where every
one of 78 cards is burning AND juggling reachable in play at all?** That is a playtest question (T15),
not a shader one, and nothing above should be spent until it is answered.

#### 0d.4. ⚠ `snapshot_diff.py` WAS BLIND, AND IT INVALIDATES EVERY "PANELS IDENTICAL" CLAIM BEFORE TODAY

**Measured, not argued.** `diff` compared two RGBA images with `ImageChops.difference(a, b).getbbox()`,
and **Pillow trims an RGBA image by its ALPHA channel alone** — verified on Pillow 9.5: two opaque
images differing only in RED return `getbbox() is None`. Every panel these harnesses write is opaque
edge to edge, so **the tool reported "identical" for any change that did not move alpha, which is every
colour change there is.**

How it was caught: the exact mask should have moved the warp panel and the tool said 20 of 20 identical.
Blanking the card mask deliberately — fire gone from four panels — **also** read as 20 of 20 identical.
Fixed by splitting the bands and taking each one's own bbox (a single-band image has no alpha to trim
by), and the fix immediately reported the three panels the mask change actually touches.

- ⚠ **SO §0d's "ALL 18 PANELS BYTE-IDENTICAL" FOR `min_half`, AND §6a's SAME CLAIM FOR `body_near` AND
  THE OFF-SCREEN SKIP, ARE VACUOUS.** They are not disproved — all three are still very likely
  pixel-neutral, and `min_half` additionally has an asserting check (§0d.1) — but **the evidence that
  was offered for them does not exist.** Re-running `save` on `git stash`ed builds and `diff` on those
  three is a ~10-minute job and it is the next thing to do if any of them is ever doubted.
- ⚠ **AND `09_embers` DIFFERS RUN TO RUN ON AN UNCHANGED BUILD** (measured: same bbox twice) — the
  embers are randomised, so that panel is not a regression signal and never was. Expect it in every
  diff. The 18 others are deterministic.
- ⚠ Two stale panels (`00_tendril_count`, `00b_ogee_profile`) are still sitting in the shots directory
  from the retired build. They are not written any more, so they compare identical for ever and pad the
  count from 18 to 20. Delete them from `%APPDATA%\Godot\app_userdata\Solatro\fx_snapshots`.

#### 0d.5. ✅ CLOSED BY §0d.6 — the brief, kept for its budget and its history

⚠ **READ §0d.6 FIRST. The task below is done and its priced menu was NOT what did it** — none of the
nine levers was taken, because the cost model they were all derived from turned out to have two factors
and every one of them moved only one. Kept because the BUDGET here is still the target, and because the
list of "what is already taken" is still true history.

Owner: *"Last task for next agent will be back and forth with user to make juggling effect
as performant as possible."*

**THE NUMBER TO BEAT** (Intel UHD, §0d.3, three runs, minimum): the juggling layer is **~5.3 ms** of the
**10.775 ms** worst window, against a **~2 ms target for all FX**. `juggle both x20` is **1.912**, split
`juggle balls` **0.576** and `ball fire` **1.311** — ⚠ **the plumes are 2.3x the balls**, so the fire
shader wearing `SHAPE_BALLS` is the expensive half and `juggle.gdshader` is not the problem.

**WHAT IS ALREADY TAKEN, so you do not re-take it:** the arc-ladder hoist (§1a.1, ~384 → 8 evaluations
per fragment), `fx_balls_near`'s empty-majority rejection (§1b.2), the box bound on the juggling quads
(§1a.3), the off-screen upload skip (§6a.2), the ball column SOLVED rather than sampled (§0a — that quad
pays zero mask lookups), and `min_half` (§0d, ~30 % of the layer). ⚠ **And three things that look like
levers and are measured not to be** — the last paragraph of §0d.2.

**HOW TO RUN IT AS A CONVERSATION.** The free levers need no permission; everything else is a look or a
feature decision that is his, and the whole point of the back-and-forth is to spend the smallest one
that reaches the budget. Bring him numbers, not options:

1. **Take the two FREE levers first and measure each on the Intel box** — the off-centre quad (§0d.2
   lever 1, ~40 % of both juggling quads is empty space below the loop) and the lit-ball shrink (lever
   2). Neither changes a pixel, so `snapshot_diff` (now honest — §0d.4) is the gate. ⚠ The rotated-ball
   assertion that used to stand beside it was deleted as non-deterministic (§0d.1) — there is one gate
   here now, not two.
2. **Then ask the FIRST question, because it can end the task**: *is a window where every one of 78 cards
   is juggling five lit balls reachable in play at all?* §6b proved host count is the wrong axis — the
   bound is the WINDOW — and if the real worst case is 3–5 juggling cards, the budget is already met and
   every look compromise below is unnecessary. **That is a playtest answer (T15), and it is the cheapest
   thing in this list.**
3. **Only then price the LOOK compromises for him** (§0d.2 levers 4–8: plume height, arc height, the
   second noise layer on plumes alone, fewer arcs, a cap on lit balls). Give each one a measured
   millisecond and a one-line description of what it costs visually, and let him choose. ⚠ **Ruling 13
   and the arc ladder are his decisions already** — do not quietly retune them.
4. **The structural lever (§0d.2 lever 9, merging the two juggling quads) is worth more than any knob and
   fights two rulings** — plumes must draw behind balls, and one shader per effect (§5b). Raise it only
   if 1–3 miss, and raise it as a question.

⚠ **ONE DEBT TO SETTLE EARLY, BECAUSE IT IS ABOUT JUGGLING**: `min_half`'s "18 panels byte-identical"
evidence was produced by the broken `snapshot_diff` (§0d.4) and does not exist. It is very likely still
pixel-neutral and it has an asserting check for the displacement that got it reverted once (§0d.1) — but
**re-earning it is ~10 minutes** (`save` on a build with the two `min_half` assignments commented out,
`diff` with them in) and it is the foundation the next lever sits on.

#### 0d.6. ✅ ONE INSTANCE PER BALL — the juggling layer is 3.2x cheaper and the search is DELETED

Owner: *"1. yes reachable. 2. if overlapping, ball with highest stacks win"* — answering §0d.5's two
questions, which closed off the cheap escape (the saturated window IS reachable in play) and pre-ruled
the one visual change this needed.

**THE COST MODEL THAT PICKED THIS, and it is the reason none of §0d.2's nine levers was taken.** Fit
§0d.3's own numbers to `cost = guard-box area x cost of one fx_nearest_ball call`:

| | quad extent | `fx_balls_near` box | actual drawn pixels |
|---|---|---|---|
| balls | 33.1 x 64.0 = 2118 art² | **1104 art²** | ~28 art² |
| ball fire | 49.1 x 80.0 = 3928 art² | **2422 art²** | ~150 art² |

Guard-box ratio **2422/1104 = 2.19**; measured cost ratio **1.311/0.576 = 2.28**. A 4 % fit. And
solving `min_half`'s measured 1.40x with the same model says an ACCEPTED fragment costs **~26x** a
box-rejected one. So the layer was one product — *area x search* — with the search running over **39x
more area than there was ball**. Every lever on §0d.2's menu shaves one factor by 10–40 %; both
factors were wrong by more than an order of magnitude.

**WHAT SHIPPED.** One `MultiMeshInstance2D` per juggling quad, **one instance per ball** (per LIT ball
for the plumes). The ball's INDEX and its own level ride in `INSTANCE_CUSTOM`; `vertex()` calls
`fx_ball_of` to place that one ball; the fragment does a disc test against a centre it already has.
`fx_nearest_ball`, `fx_balls_near`, `lit_only`, the `u_ball_fire` levels texture and
`FxJuggle.fire_texture` are **all deleted** — not replaced.

| GPU timer, ms/frame, Intel UHD, 3 runs, min | before | after | |
|---|---|---|---|
| `juggle balls x20` | 0.540 | **0.091** | **5.9x** |
| `ball fire x20` | 1.256 | **0.168** | **7.5x** |
| **`juggle both x20`** | **1.822** | **0.248** | **7.3x** |
| `burning, FULL SCREEN` (the CONTROL — no juggling in it) | 6.606 | 6.513 | 1.0x ✅ |
| **`burning + juggling, FULL SCREEN`** | **12.066** | **8.225** | |
| **the JUGGLING HALF of that window** | **5.46** | **1.71** | **3.2x** |

⚠ **THE x20 ROWS GAIN 7x AND THE 78-HOST WINDOW ONLY 3.2x, AND THE GAP WAS THE CPU — see §0d.7, which
took it.** At 78 hosts
the layer is 156 MultiMesh draws carrying 780 instances, so per-draw and per-instance overhead now
dominates what used to be fill. **The wall clock proves it: the worst window was 11.96 ms wall against
12.34 GPU (GPU-bound) and is now 10.97 wall against 8.23 GPU — CPU-bound.** So `_push_live`'s ~15
`set_shader_parameter` calls per quad per frame, which §6a measured at ~0.03 ms per host and which was
always hidden underneath the GPU, is now the binding constraint. That is where the next millisecond is,
and it is not a shader change.

**THREE THINGS THAT WENT WRONG, EACH WORTH KNOWING:**

1. 🔴 **THE FIRST BUILD LOOKED 10x FASTER AND WAS DRAWING ALMOST NOTHING.** Godot derives a
   `MultiMeshInstance2D`'s cull rect from the instance TRANSFORMS, and an effect that places its
   instances in `vertex()` leaves every transform at identity — so the engine believed the whole effect
   was one mesh-sized box at the host's origin. Of 8 balls the 2 passing near the card's centre drew and
   6 vanished; of 50, four. **`fx_cost` cannot tell "cheap" from "not drawn"**, and only the PIXELS
   suite's ball checks caught it. Fixed with `MultiMesh.custom_aabb` from a new
   `FxRequest.instance_bound` — the pattern's box, which is exactly what the old quad was SIZED to and
   now costs no fill at all because it only decides whether the item is submitted.
2. 🔴 **THE Y FLIP IS NOT WHERE IT LOOKS.** `VERTEX += vec2(origin.x, -origin.y)` drew the entire
   pattern mirrored below the card. `fx_local`'s flip is between UV and MESH space, not between mesh
   space and ART space: the 2-D renderer uses a canvas mesh's vertex x/y directly and canvas +y is down,
   which is the way art +y already points. **A vertex offset IS an art-space offset.** `05_balls` showed
   it in one glance — oracle crosses above centre, rendered balls below.
3. ⚠ **AND THE INSTRUMENT I REACHED FOR SECOND WAS A MOCK.** A throwaway probe scene that re-implemented
   the PIXELS harness rendered NOTHING and told me nothing; `fx_snapshot`'s own PROBE lines answered the
   same question in seconds (every ball within **0.1–0.3 art units** of its oracle). The rule in §0c.2
   applies to debugging too: use the harness that already works.

**WHAT IT COSTS VISUALLY, AND IT IS THE OWNER'S OWN RULING.** Overlap is resolved by DRAW ORDER now
instead of by nearest centre, so `FxJuggle._ball_instances` sorts by level and the highest-level ball
draws last and wins. `snapshot_diff` against the pre-change build: **the panels with no overlap are
BYTE-IDENTICAL — `05c_ball_sphere`, `05f_ball_rotation` and `06_ball_fire`** (so the plume path is
pixel-perfect), and the five that differ are the crowded ones (`05e_ball_arcs` 1477 px at 8 arcs,
`05_balls` 58 px, `05d_ball_gravity` 27, `06b_ball_fire_cycle` 8, `05b_ball_path` 2). ⚠ Two causes, both
expected: the overlap order above, and rare single-cell disagreements at a ball's edge where the new
arithmetic path (`snap(inst_raw + origin)`) rounds differently from the old (`snap` over a host-sized
quad) at an exact cell boundary. ⚠ `09_embers` differs by design, as always.

**THE CONTRACTS THIS ADDED, and all three are load-bearing:**

- **`fx_cell_round`** — an instance is placed at a WHOLE number of FX cells, which is what keeps its
  content on the host's own lattice (the identity `fx_pixel_snap(fx_local_raw(uv, e), c) ==
  fx_local(uv, e, c)`, which holds because `fx_local` quantizes before its flip) AND what puts the
  quad's edges on cell boundaries so no chunky pixel is ever sliced in half.
- **`FxRequest.instance_half` must be a whole number of cells**, for that second reason. `_cell_box`
  rounds up and adds a DERIVED 1.5 cells of slack (0.5 placement + 0.5 snap + 0.5 the cell's own body);
  `test_fx_attachment` asserts the whole-cell part.
- **A plume's box is NOT symmetric about its ball** — the cover ladder only steps DOWN, so the box runs
  `r + height` above the centre and `r + sink` below it and the instance is centred `(sink - height)/2`
  off the ball. Worth about half that quad's fill. ⚠ `u_height` and `u_sink` were therefore taken OUT of
  the plume's `live` dictionary: everything in `live` is EASED, and an easing height would move the box's
  centre while the box was sized for one end of it.

✅ **AND TWO CONSTRAINTS ARE LIFTED, which is worth as much as the milliseconds.** The path no longer has
to be **invertible** — `fx_arc_ease_inv` is deleted, and "do not add a timing ease inside a half without
checking it stays invertible" is no longer a rule on anyone tuning the loop. And **§0d.2's menu is void**:
levers 1 (off-centre quad), 2 (lit-ball shrink) and 9 (merge the two quads) are all subsumed, and 9's
fight with the plumes-behind-balls ruling never has to be had — two MultiMesh nodes in the same tree
order keep it.

#### 0d.7. ✅ THE CPU HALF — `_push_live` was 4.2 ms/frame and nobody had ever measured it

§0d.6 ended GPU-bound-no-more: the worst window read **wall 10.97 ms against 8.23 ms of GPU**. So the
next millisecond was never going to be in a shader.

**IT IS NOW MEASURED DIRECTLY, by a new permanent bench row** (`fx_cost`'s `_push_live, FULL SCREEN`,
which times the real function on a real board's quads — the GPU timer structurally cannot see any of
this, and §6a's only previous figure was the indirect "234 OFF-SCREEN hosts cost ~7 ms", for hosts that
skip the upload entirely):

| Intel UHD, 3 runs, min | before | after | |
|---|---|---|---|
| **`_push_live`, 78 hosts / 234 quads** | **4.206 ms** | **1.135 ms** | **3.7x** (18.0 → 4.9 µs per quad) |
| `burning + juggling, FULL SCREEN` — **WALL clock** | 12.760 | **8.460** | the number a player feels |
| the same row, GPU timer | 8.225 | 7.310 | |

**WHAT IT WAS.** ~15 `set_shader_parameter` per quad per frame plus a freshly allocated eased Dictionary
per effect. **Only TWO of those are genuinely per-frame** — `u_time` and `u_phase`. The rest describe
either the HOST'S POSE (`u_shape_rot`, `u_lag`) or an EASED TRANSITION, and on a settled board neither
changes at all, so both are now sent on CHANGE: `_sent_rot` / `_sent_lag` for the pose, `Effect.pushed`
for the eased set. `_on_screen`'s per-frame loop over every effect became the `_cull_reach` cache, since
only `_size_quad` can move that number.

⚠ **THE VALUES ARE STILL COMPUTED, ONLY THE UPLOAD STOPS.** `Effect.vals` caches the eased set because
the EMBER emitter needs this frame's geometry every frame even when the shader does not.

⚠ **AND `_apply_static` MUST CLEAR `pushed`, WHICH IS THE ONE TRAP HERE.** `style.apply()` writes the
style's BASE value for names the live set also owns — `u_height` is both a style lever and a stack-scaled
live value on a card's fire — so a restyle (it is wired to `settings_changed`) stamps the base over the
eased value, and nothing would ever put it back.

⚠ **ONE REGRESSION FROM §0d.6 WAS FOUND HERE, and no test could have caught it.** Taking `u_height` out
of the plume's `live` left `_ember_origin` reading it from `vals` as **zero**, so every ball ember was
born ON its ball instead of scattered up its flame. Embers are randomised — `09_embers` differs run to
run by design — so the fix is a fallback to the style's own height, and the comment says why the fallback
is where a plume's height actually lives.

⚠ **AND A REAL NON-DETERMINISM IN §0d.6's OVERLAP RULE, caught by re-running the diff.** `05e_ball_arcs`
reported 1477 differing pixels one run and 2228 the next with nothing changed between them:
`Array.sort_custom` is **NOT STABLE**, so balls of EQUAL level — which is every ball in most panels and
the common case on a real board — came out in an arbitrary permutation, and draw order decides every
overlap. Ties break on the INDEX now, and that panel dropped to **24 px and holds it across runs**.

⚠ **THE OTHER PANELS STILL FLAKE RUN TO RUN AND IT IS NOT THIS CHANGE.** Two consecutive runs of the same
build put `05f_ball_rotation` / `06_ball_fire` / `08_focus_highlight` in one diff and `05d_ball_gravity`
at 1668 px in the other. That is §0d.1's standing warning, unchanged: **run this harness twice before
believing either half of what it says.** The panels that are stable across runs are `05_balls` 58 px,
`05b_ball_path` 2, `05e_ball_arcs` 24 and `06b_ball_fire_cycle` 8 — the overlap-order and edge-rounding
differences §0d.6 predicted, and nothing else.

**WHERE THE BOARD STOOD AT THE END OF THIS STEP** — ⚠ superseded by §0d.9, which took card fire down
another 1.84 ms; **§0d.10 has the current table.** The worst window was **8.46 ms of wall clock**, of which
**~6.5 ms is CARD FIRE's GPU time** and juggling is ~1.7. Against the owner's ~2 ms target for all FX, the
remaining lever is `cover_taps` on `fire_card` (4 → 2 is worth ~1.24 ms — §0d.3), and that is a LOOK call
only the owner can make (§0e is the argument against it).

#### 0d.8. 🟡 CARD FIRE TIME — the brief, and what it produced

Owner: *"new task is solving card fire time."* ✅ **Two levers were taken (§0d.9) and the owner
then stopped the pass.** ⚠ **For the CURRENT numbers and what is still available, go to §0d.10** — this
section is the diagnosis as it stood BEFORE those levers, kept because the decomposition and the area
arithmetic are what pointed at them.

**THE NUMBER IT STARTED FROM** (Intel UHD, `fx_cost`, 3 runs, minimum): a window packed edge to edge with
78 burning cards cost **6.50 ms of GPU** against the owner's **~2 ms target for all FX**. It is **4.66 ms**
now.

**THE COST SPLITS ALMOST EXACTLY IN HALF, and this is fresh evidence on the shipped build** — the tap
sweep, which is the shader's cost curve drawn directly:

| full burning screen, GPU ms | 2 taps | 4 taps (ships) | 6 taps | 8 taps |
|---|---|---|---|---|
| | 4.841 | **6.496** | 8.155 | 9.899 |

Dead linear at **0.843 ms per tap**, intercept **3.16 ms**. So at the shipped 4 taps:

- **~3.37 ms IS THE COVER LADDER** — `u_taps` mask lookups per accepted fragment. §9's model holds.
- **~3.16 ms IS EVERYTHING ELSE** — the fill itself, `body_near`, the erosion test, the noise, the ramp.
  ⚠ **Do not read that as "the noise"**: the source A/B is still a wash (`fx_fbm` 6.573 vs the baked
  TEXTURE 6.435 — 2 %, inside this box's spread), which is the third time that has measured flat.

⚠ **BOTH HALVES SCALE WITH ACCEPTED AREA**, which is what makes the leading candidate below worth more
than any tap knob: taps run only where `body_near` passes, and the noise only where `cover > 0`.

**THE AREA ARITHMETIC, for a 38x50 card** (art units², and the reason to look here first):

| | |
|---|---|
| the quad — circumscribed bound plus reach on all four sides | 84.8 x 84.8 = **7191** |
| what `body_near` ACCEPTS (body bound + `height + sink` each way) | ~54 x 66 = **3564** |
| the band the flame can actually occupy — the outline extruded by `height + sink` | ~176 perimeter x 8 = **~1408** |

#### 0d.9. ✅ TWO LEVERS TAKEN — 6.50 → 4.66 ms, and the first one is TWO LINES

Owner: *"yes assume reachable. reduce ms as much as possible."*

| Intel UHD, 3 runs, min | before | after | |
|---|---|---|---|
| **`burning, FULL SCREEN`** | **6.496** | **4.657** | **1.39x, −1.84 ms** |
| `card fire (DEFORMED) x20` | 2.222 | 1.684 | 1.32x |
| `burning + juggling, FULL SCREEN` | 7.310 | **5.820** | |
| the tap slope, ms per tap | 0.843 | **0.541** | −36 % |

**LEVER 1 — BURIED FRAGMENTS NO LONGER PAY THE LADDER (`cover_below`, two lines, worth 1.27x alone).**
`deep` means the fragment is more than `sink` inside the art, and `fragment()` discards it on exactly
that flag — but the tap loop ran first, all four lookups of it. **A card's interior is the largest
contiguous region in its quad — ~41 % of everything `body_near` accepts (1564 art² of 3808)** — and it
was paying full price to draw nothing. ✅ **Pixel-exact by construction** (the caller already threw the
fragment away whatever cover said) and it divides well, because the interior is one block rather than
scattered fragments. The tap slope falling 0.843 → 0.541 is the same 41 %, measured from the other side.

**LEVER 2 — §10's LEVER B, AT LAST: the circumscribed bound only while the host is actually turned**
(`_size_quad`, `_rot_tight`). A resting card was paying 84.8² of quad for a 56x68 bound. ⚠ **The
objection that blocked this for months is VOID** — §6a rejected it because "resizing a live quad moves
the FX pixel lattice", which stopped being true when the lattice moved to the host's ORIGIN. It falls
back to the diagonal the instant the host turns, so it is exact rather than approximate, and only the
CROSSING re-sizes anything (a spinning card pays two resizes for the whole spin).

⚠ **AND LEVER 2 CAME WITH A REGRESSION THIS BENCH CANNOT SEE, which is the lesson worth keeping.**
Making the extent depend on the LIVE silhouette meant `track_outline` — which runs every frame for any
card whose rig is moving — rebuilt the QuadMesh and re-pushed `u_extent` every frame, handing back
exactly the per-frame CPU §0d.7 had just removed. `fx_cost`'s hosts call `measure_outline` once and never
deform, so **the row stayed green while the game got slower**; it showed up only as `_push_live` drifting
1.14 → 1.40 ms and the wall clock going the wrong way against a falling GPU timer. Fixed by rounding the
extent to whole art units and writing it only when it changes.

**WHAT THE PIXEL GATE SAYS.** The card panels move by **tens of pixels, and the panel they move in
changes as the extent's float path changes** (`06_ball_fire` 5 px in one build, `04_shapes` 67 px in the
next) — the signature of single-cell boundary rounding in `floor(s / cell)`, not of geometry: `04_shapes`
inspected by eye shows the rings whole, with scattered single flame pixels at their edges and no cut
line anywhere. ⚠ Two consecutive runs agreed exactly, so this is deterministic within a build.

**WHAT IS LEFT, and the ring mesh is NO LONGER WORTH IT.** At 4 taps the cost is now ~2.16 ms of ladder
and ~3.00 ms of everything else. ⚠ **My own ~2.5x estimate for the ring mesh below was wrong twice over**:
the honest area arithmetic is 3808 → ~2174 art² (**1.75x**, not 2.5x — the first estimate forgot the
corner wedges and the inner erosion band), and **lever 1 has already taken the whole interior out of the
expensive path**, so a ring would now only save those fragments' RASTERIZATION and their one erosion
test — about **0.3 ms** for a triangle strip, a reflex-corner problem and a per-frame vertex budget. The
remaining levers are the tap knob (below) and the mask's own cost (§0c.5's 20-point chamfer compromise).

**THE LEADING CANDIDATE (SUPERSEDED — read §0d.9 first): A RING MESH INSTEAD OF A QUAD.** It is the direct analogue of what just won
3–8x on juggling (§0d.6), and the machinery it needs already exists:

- The mesh becomes a fixed-topology triangle STRIP around the silhouette — `u_poly` is already a
  uniform, so `vertex()` can place each strip vertex by reading its own outline vertex and extruding it
  outward by `height + sink`. **Zero per-frame CPU**, which matters now that §0d.7 has made CPU the thing
  to protect: no mesh rebuild even though the rig deforms every frame.
- The fragment recovers its host-space point from a varying and snaps it, exactly as the instanced ball
  path does — so the FX lattice is untouched and the flame's own pixels do not move.
- ⚠ **ESTIMATE, NOT A MEASUREMENT: ~2.5x on both halves**, i.e. 6.50 → ~2.6 ms, from accepted area
  3564 → ~1408. Derived with the 26:1 accepted-to-rejected fragment ratio fitted in §0d.6. **Re-price it
  on this box before building it** — and remember §0d.6's trap: a build that draws less than it should
  reads as a triumph, so gate on `all_tests` and `fx_snapshot`, never on `fx_cost` alone.
- ⚠ **THE RISK IS REFLEX CORNERS.** A deformed card's outline is not convex (§0c.1), so an outward
  extrusion self-overlaps at a dent — and two ribbons over one fragment blend twice. Convex corners need
  a fan or a mitre; concave ones need the overlap resolved or accepted.

**AND THE PRIZE BEHIND IT: THE TAP LADDER COULD GO ENTIRELY.** On a ring mesh a fragment knows WHICH
EDGE it belongs to, so "how far above the surface am I" is a dot product against that edge instead of
`u_taps` mask lookups — the ~3.37 ms above, gone, and with it the `u_poly` array cost §0c.5 measured at
16 % of a burning screen (the array would be read once per VERTEX, not once per tap). ⚠ It must quantize
to the same `taps + 1` levels or the look changes; ⚠ it is CARD-ONLY (props are SPRITE and keep the
ladder, which is correct — a hoop has two surfaces in a column and §1 exists for that); and ⚠ it is
§10's lever D wearing different clothes, so read D's warning about per-shape paths first.

**THE CHEAP LEVERS, for completeness:**

| | lever | worth | what it costs |
|---|---|---|---|
| 1 | ⬜ **`cover_taps` 4 → 2 on `fire_card`** | **0.98 ms, re-measured after §0d.9** (5.062 → 4.085 on the sweep; it was 1.66 before lever 1 made each tap cheaper) | a LOOK the owner owns — §0e is the argument against it (a card flame is 7 FX pixels tall, so 2 taps is 3.5 px per tap and the fire stops hugging the art) |
| 2 | ✅ **§10's lever B — TAKEN (§0d.9)** | part of the 1.39x | — |
| 3 | ⚪ **the noise source** | **nothing — measured flat three times** | — |

**THE THREE QUESTIONS THIS SECTION PUT TO THE OWNER, AND WHAT HE SAID:**

1. **Is a screen of 78 cards where EVERY ONE is burning actually reachable in play?** ✅ **"yes assume
   reachable"** — so the saturated window is the right number to optimise, and nobody needs to ask again.
2. **Spend the LOOK (`cover_taps` 2) or the ENGINEERING?** ✅ **"reduce ms as much as possible"** — taken as
   "do the non-visual work", which is what §0d.9 did. ⬜ **The look call itself is still UNMADE**; it is
   worth 0.98 ms and it is lever 1 of §0d.10.
3. Is `height` = 7 on `fire_card` firm? ⬜ **Never answered** — still lever 3 of §0d.10.

#### 0d.10. ⬜ RESTARTING THE PERFORMANCE WORK — the one-page version

**Owner stopped the pass here, with the numbers below. Nothing is broken and nothing is
half-built; this section exists so picking it back up costs an hour instead of a day.**

#### Where the budget stands — Intel UHD, `fx_cost.tscn`, 3 runs, MINIMUM taken

| row | ms | what it is |
|---|---|---|
| **`burning + juggling, FULL SCREEN`** | **5.82 GPU** | **the worst window the game can build** — 78 cards at board scale, every one burning AND juggling 5 lit balls. Was 12.07 before this pass |
| `burning, FULL SCREEN` | 4.66 GPU | the same 78 cards burning only — **this is where ~80 % of the remaining FX cost is** |
| the juggling layer within that window | ~1.2 GPU | §0d.6 |
| `_push_live`, 78 hosts / 234 quads | ~1.3 CPU | §0d.7. ⚠ **The GPU timer cannot see this row; only `_cpu_row` can** |
| the tap slope on `fire_card` | 0.541 ms per tap | was 0.843 before §0d.9 |

**The owner's target is ~2 ms for ALL FX.** The window is 5.82 and burning-only is 4.66, so the target is
still missed by ~3x in the saturated case. ⚠ **The owner has confirmed that window IS reachable in play**
(owner: *"yes assume reachable"*), so it is the right number to optimise — do not re-open that.

#### Card fire, decomposed — this is the whole map of what is left

At the shipped 4 taps, `burning, FULL SCREEN` = **4.66 ms**, and the tap sweep splits it:

- **~2.16 ms is the COVER LADDER** (4 taps x 0.541). The only cheap way at it is the tap count.
- **~2.50 ms is EVERYTHING ELSE** — rasterizing the quads, `body_near`, the erosion test (one mask call
  per accepted fragment), the noise on the lit band, the ramp. ⚠ **No single item in here is large**,
  which is why the pass stopped: the next win needs a structural change, not a knob.

#### Every lever still on the table, honestly priced

| | lever | worth | risk / cost |
|---|---|---|---|
| **1** | ⬜ **`cover_taps` 4 → 2 on `fire_card`.** Measured directly on the sweep (5.062 → 4.085) | **0.98 ms** | **a LOOK the owner owns.** §0e is the argument against it: a card flame is 7 FX pixels tall, so 2 taps is 3.5 px per tap and the fire stops hugging the art. **Show `00_cover_field` and `01_fire_ladder` side by side before asking** |
| **2** | ⬜ **§0c.5's 20-POINT DIAGONAL CHAMFER** instead of the exact 24-vertex corner bite. §0c.5 measured the exact mask at **16 %** of a burning screen and the cost is the ARRAY's size, not the loop | ~half of that 16 %, so **~0.3–0.4 ms** at today's numbers (UNMEASURED since §0d.9) | an ACCURACY trade the owner should see: same pixels on the FX grid, approximate off it. `POLY` 24 → 20 and `WEDGE_CANDIDATES` back to 2 |
| **3** | ⬜ **`fire_card.height` down from 7.** It is a FILL knob as well as an art one — the lit band is `height + sink` thick around the whole silhouette, so every unit off it is ~1/8 of the band | ~0.2 ms per unit (ESTIMATE) | a LOOK the owner owns |
| **4** | ⬜ **A SPECIALISED CARD-FIRE SHADER** — one program per shape instead of one carrying all four. §0c.1 measured a BOX host getting **25 % dearer purely from carrying two uniform arrays it never enters**, so program size demonstrably costs real time on this GPU | UNMEASURED. That 25 % datum is the only reason to believe in it | it fights §5b (one shader per effect) and duplicates the cover/noise/ramp tail unless that tail is extracted into a shared `.gdshaderinc` first |
| **5** | ⬜ **BOARD-WIDE BATCHING** — one MultiMesh per LAYER instead of per host, collapsing 234 draws and 234 uniform sets into a handful | attacks the ~1.3 ms CPU row, not the GPU | wide: it fights the attachment-per-host architecture that makes "fx shared across all views" free (rulings 7, 18). **Do not start this without re-measuring the CPU row first** |

#### ⛔ Things that look like levers and are NOT — do not spend time here

Each of these cost real time in this pass or an earlier one, and the reason is recorded:

- **A RING / STRIP MESH around the silhouette** (§0d.9's last paragraph). Honest area arithmetic is 3808
  → ~2174 art² (**1.75x, not the 2.5x an earlier draft of this file claimed**) — and the two-line
  buried-fragment early-out **already removed the whole interior from the expensive path**, so a ring now
  saves only those fragments' rasterization and one erosion test each: **~0.3 ms** for a triangle strip, a
  reflex-corner problem on a deformed outline, and a per-frame vertex budget.
- **THE NOISE SOURCE** (`noise_procedural`). Procedural `fx_fbm` vs the baked tile has measured FLAT
  **three separate times** on this box (latest: 6.573 vs 6.435 on a burning screen). It is a look knob.
- **`FxStyle.pixel`.** Quantizes a coordinate; the quad still runs once per SCREEN pixel (§6f).
- **`cover_taps` on `fire_ball`.** The ball branch SOLVES for the tap index with one `sqrt`, so that quad
  pays no mask lookups at all (§0e).
- **The ARC MATHS.** Hoisted to 8 evaluations per fragment in §1a.1 and then out of the fragment stage
  entirely in §0d.6. It is 4 evaluations per ball per FRAME now.
- **Shrinking a quad to `body_near`'s box.** Rejected fragments are ~1/26 the cost of an accepted one, so
  removing 3383 art² of them is worth ~3 %. The win is always in the ACCEPTED area.

#### ⚠ The four traps that will cost you a day if you skip them

1. **`fx_cost` CANNOT TELL "CHEAP" FROM "NOT DRAWN".** §0d.6's first build read **10x faster** and was
   culling most of its balls. **Gate on `all_tests.tscn` (the PIXELS ball checks) or `fx_snapshot`, never on
   `fx_cost` alone.** A number that beats your own prediction is a bug report.
2. **`fx_cost` CANNOT SEE CPU YOU ADD ELSEWHERE.** §0d.9's lever B made a deforming card rebuild its mesh
   every frame; the bench's hosts never deform, so the row stayed green while the GAME got slower. **Watch
   `_push_live, FULL SCREEN` and watch wall clock against the GPU timer** — wall rising while GPU falls is
   the signature.
3. **RUN A RENDERING HARNESS TWICE.** `fx_snapshot` disagrees with itself run to run on the rotated and
   fire panels (§0d.1, re-confirmed). A red picture from one run is not a red build.
4. **`snapshot_diff` IS THE INSTRUMENT FOR "NOTHING MOVED", NOT YOUR EYE** — and expect the juggling
   overlap panels (58 / 2 / 24 / 8 px) plus `09_embers` to differ against the pre-pass baseline for the
   reasons §0d.6 and §0d.7 give. ⚠ Single-cell differences MIGRATE between panels whenever a quad's extent
   changes, because `floor(s / cell)` takes a different float path to the same point; tens of pixels with
   no cut line is that, not geometry.

#### The cost model that has held up, and the one that replaced it

- **For the CARD/PROP path: cost = `mask_level` call count x cost per call** (§9). Still true — the tap
  sweep is dead linear, and it is why the tap knob is the only cheap lever left.
- **For the JUGGLING path it was: cost = guard-box area x cost of one nearest-ball search** — fitted to
  within 4 % (§0d.6), and the reason instancing beat all nine of §0d.2's levers. ⚠ **The lesson generalises:
  when a menu of knobs each buys 10–40 %, fit a model and check whether it has TWO wrong factors.**

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
4. **Owner playtest (T15)** still blocks "done" — FX_SHADER_PLAN §10, 17 steps. ⚠ Its old second purpose
   is spent: the owner has ruled that the saturated window IS reachable, so §6b's question
   does not need the playtest to answer it.
5. ⬜ **TWO PERFORMANCE CALLS ARE WAITING ON YOU, and they are the only budget left worth a millisecond**
   (§0d.10 prices them):
   - **`cover_taps` 4 → 2 on `fire_card` — worth 0.98 ms.** §0e is the argument against it: a card flame is
     7 FX pixels tall, so 2 taps is 3.5 px per tap and the fire stops hugging the art. **Judge it on
     `00_cover_field` (the raw ladder) and then `01_fire_ladder` DRESSED, side by side, before deciding.**
   - **`fire_card.height` (7 today).** It is a FILL knob as well as an art one — the lit band is
     `height + sink` thick around the whole silhouette — so roughly 0.2 ms per art unit removed.
   ⚠ **Neither was taken.** The performance pass deliberately spent only non-visual levers, and the owner
   stopped it there rather than spend a look (*"sure lets stop here then"*).
6. ⚠ **AND ONE LOOK QUESTION THE PASS CREATED, which the owner has not yet seen in motion:** where two
   juggled balls OVERLAP, the winner is now the one with the higher level rather than the nearer centre
   (§0d.6, his own ruling), and two overlapping PLUMES now blend twice where they cross. It is measured as
   tens of pixels on the crowded snapshot panels and has never been judged by eye on a real board.

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
| `Tests/Visual/test_pixels.gd` | `_host_balls` takes a `deg`. ⚠ The rotated-ball ASSERTION built on it was deleted as non-deterministic — see §0d.1 |
| `Tests/Visual/fx_snapshot.gd` | prints the counter-rotation per case and re-reads it POST-CAPTURE, so the flake in §0d.1 is diagnosable next time |

**And then this pass (the exact mask, the real card, the slow box):**

| file | what happened |
|---|---|
| `Shaders/fire.gdshader` | `u_poly` / `u_wedge` / `u_poly_count` / `u_inner` replace `u_radii`; `poly_solid` + `wedge_has` replace `radii_scale`; the RADII branch is two box tests around an exact polygon (§0c.1) |
| `UI/Fx/fx_attachment.gd` | `_poly` / `_wedge` / `_poly_half` / `_poly_max` / `_poly_inner`; `_fill_poly_from_outline` and `_inner_box` replace `_fill_radii_from_outline`; `_push_poly` pushes the silhouette as ONE fact; winding normalized; `_rect_radius` deleted |
| `Cards/card_visual.gd` | `star_outline`'s docstring carries the MEASURED gap to the real rig (2.3–3.3 art units) and names the check that uses a real card |
| `Tools/fx_editor.gd` | same warning on the `corner_warp` export — the tool cannot host a real `CardVisual` and now says why |
| **`Tests/Visual/test_pixels.gd`** | **`test_the_card_mask_is_the_card_the_player_sees` — the first real `CardVisual` in any harness (§0c.2)** |
| `Tests/Visual/pixel_probe.gd` | `mask_contains` — the shader's mask, transcribed, shared by the two suites that need it |
| `Tests/UI/test_fx_attachment.gd` | `test_the_mask_is_the_outline` — the mask against `Geometry2D.is_point_in_polygon`, plus the vertex-spacing invariant the two-candidate wedge test depends on; the enum-mirror pin follows POLY/WEDGES |
| **`tools/snapshot_diff.py`** | **`_bbox` — compares EVERY channel. It compared alpha only, and said "identical" to anything that did not move alpha (§0d.4)** |
| **`Tools/fx_editor.gd`** | **real `CardVisual` hosts; `rig_pose` replaces `corner_warp`; the flat mock face and its palette index deleted; `_spawn_host` takes the host's own visual (§0c.4)** |
| `Cards/card_visual.gd` | `settings()` for the editor's missing autoload; `_bind_rig()` in either mode — both so the tool can stand up a REAL card |
| `Cards/card_data.gd`, `card_modifier.gd`, `card_modifier_type.gd`, `card_modifier_stamp.gd`, `card_modifier_skill.gd`, `Pips/pip_suit.gd` | **`@tool` down the whole data chain** — without it a previewed card's suit/type/stamp are PLACEHOLDERS in the editor and its face stops drawing mid-`update_visual` (§0c.4) |
| `Cards/card_modifier_type.gd` | **`corner_notch()`** — the bite each type's frame takes out of its corners, measured off the sheet's own alpha and cached per frame (§0c.5) |
| `Cards/card_visual.gd` | `star_outline` and `_rig_outline` carry that bite as three points per corner (`corner_points`, the middle one the cell's bilinear corner so it shears with the rig) |
| `Shaders/fire.gdshader` | `POLY` 16 → 24, `WEDGE_CANDIDATES` 4, and `wrap()` instead of an integer `%` per fetch |
| `Tests/Visual/test_pixels.gd` | the real-card check compares CELL BY CELL at the FX cell's own centre and asserts ZERO disagreements; the two column readers it replaced are gone |

**And then the JUGGLING REWORK (§0d.6 — one instance per ball):**

| file | what happened |
|---|---|
| `Shaders/fx_common.gdshaderinc` | **`fx_nearest_ball`, `fx_balls_near` and `fx_arc_ease_inv` DELETED** — the fragment-stage search, its guard box and the inverse the search needed. `fx_ball_of` (one ball, vertex stage) and `fx_cell_round` (whole-cell placement, and the lattice identity it rests on) added |
| `Shaders/juggle.gdshader` | a `vertex()` that places this instance's ball; the fragment is a disc test plus the sphere shading and nothing else. `u_ball_fire` gone |
| `Shaders/fire.gdshader` | a `vertex()` for `SHAPE_BALLS` only, with the plume's asymmetric box bias; the ball comes from the instance, so the search and the levels texture are gone. Every other shape is untouched — the `burning, FULL SCREEN` control moved 6.606 → 6.513 |
| `UI/Fx/fx_request.gd` | `instances` / `instance_half` / `instance_bound` replace `min_half`. ⚠ `instance_bound` is the CULL bound, and forgetting it deletes most of the balls while looking 10x faster |
| `UI/Fx/fx_attachment.gd` | `Effect` carries its `mesh` / `mat` / `multi` (a MultiMeshInstance2D has neither of the first two in the shape the call sites want) and `box_from` for the eased transition; `_make_quad` builds either node kind; `_size_quad` sizes ONE subject and writes `custom_aabb`; `_apply_static` writes the instance set |
| `UI/Fx/fx_juggle.gd` | both quads declare instances, boxes and bounds; `_ball_instances` (sorted by level — the owner's overlap rule) and `_cell_box` added; **`fire_texture` deleted**; `u_height` / `u_sink` taken out of the plume's eased `live` |
| `Tests/UI/test_fx_attachment.gd` | `test_per_ball_levels` reads the INSTANCE BUFFER instead of a texture, and pins two new contracts: the level ORDERING and the whole-cell instance box |
| `Tests/Visual/fx_snapshot.gd` | reads `Effect.mat` rather than casting the node to `MeshInstance2D` |

**And the CPU pass (§0d.7):**

| file | what happened |
|---|---|
| `UI/Fx/fx_attachment.gd` | `_push_live` sends only `u_time` and `u_phase` every frame; `_sent_rot` / `_sent_lag` gate the host pose and `Effect.pushed` / `Effect.vals` gate the eased set; `_apply_static` clears `pushed` (it can overwrite what the ease owns); `_cull_reach` replaces `_on_screen`'s per-frame loop; `_ember_origin` falls back to the style's height, which §0d.6 had quietly zeroed for balls |
| `UI/Fx/fx_juggle.gd` | the instance sort breaks TIES ON THE INDEX — `sort_custom` is not stable, and equal-level balls were getting an arbitrary overlap order |
| `Tests/Visual/fx_cost.gd` | **`_cpu_row` — the first direct measurement of `_push_live`, and the only row in this bench that prices CPU.** Read it as "what one frame's pushes cost", not as a frame time |

**And the CARD FIRE levers (§0d.9) — the last change of the pass:**

| file | what happened |
|---|---|
| `Shaders/fire.gdshader` | **`cover_below` returns early when `deep`** — two lines, 1.27x, pixel-exact. A card's interior was paying the whole tap ladder to draw nothing |
| `UI/Fx/fx_attachment.gd` | `_rot_tight` + `_size_quad` take the AABB instead of the circumscribed diagonal while the host is upright (§10's lever B, at last); `Effect.extent` makes a re-size a NO-OP when nothing moved, which a deforming card needs because `track_outline` calls `_size_quad` every frame; `physics_interpolation_mode = OFF` on the MultiMesh nodes (their transforms are identity for life — the shader places the instances) |

---

---



---



---


---


---

## 1. ✅ JUGGLING WAS TOO EXPENSIVE — ~2.4x cheaper on the GPU

🟡 **HALF LIVE.** The three levers of §1a are all still in the shader and must not be lost; the NUMBERS are the retired build's, on a GTX 1070, and §0d.3 supersedes them. §1b is history — that lever shipped (§0d).

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
   the 38x50 box instead of the 62.80 diagonal (38x50; 67.20 at 40x54), ~22 % of their fill. Fire on a card still needs the
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

⚠ Note that the rotated panels of this harness carry a standing "not reproducible" warning. Rule that
in or out FIRST — run the same build twice — before believing either result. That was not done.

⚠ **AND IT IS NOT ONE PANEL — IT IS EVERY ROTATED HOST, IN EVERY HARNESS** (re-measured,
§12). Two consecutive runs of an unchanged build with the per-host seed pinned: `02_fire_rotation`
12392 px, `05f_ball_rotation` 1035 px, and `fx_behind`'s `behind_prop_turned` 15506 px — while **every
upright panel in all three sets came back byte-identical.** So the warning generalizes, and a pixel
diff of any rotated panel is worth nothing whichever way it comes out.

✅ **ROOT-CAUSED AND FIXED — AND THE REVERT IN §1b WAS UNNECESSARY.**
Both harnesses are deterministic now: 20 of 21 `fx_snapshots` panels identical over 3 runs (only
`09_embers`, randomised by design), 5 of 5 `fx_behind` panels over 4 runs.

**The cause.** `FxAttachment._rot_tight` defaults TRUE and is re-evaluated in exactly one place,
guarded by `if moved and on_screen:` — and `_push_live` skips its uploads ENTIRELY when
`_on_screen()` is false. Both harnesses pushed the pose in the same frame the node was added, before
the canvas transform had settled, then PARKED the attachment (`set_process(false)`), so that single
call was the only chance the flag ever got. A rotated host therefore kept the UPRIGHT quad bound
(lever B in `_size_quad` only widens to the diagonal `if ... and not _rot_tight`) and rendered
CLIPPED flames — at random. Fix: settle two frames, then re-push and re-park
(`fx_snapshot.gd::_settle_poses`, mirrored in `fx_behind.gd`).

**Why it resisted diagnosis for six weeks.** It is BISTABLE, not drifting: two runs differed by the
SAME count every time (8248 px on `02_fire_rotation`), which is one boolean rather than a continuum.
Only rotated hosts were ever affected because an upright host is legitimately `_rot_tight`, so the
branch is a no-op — which made "rotated hosts are cursed" look like the phenomenon instead of a
symptom. Ruled out along the way: screen-space `fx_bayer` (retired), pinning `_seed`, and
`_push_live`'s counter-rotation (every CPU-side value the harness prints was identical across runs).

⚠ **A GAME BUG WAS NOT INVOLVED.** In play nothing parks the attachment, so the flag re-evaluates
on the frame the host is next on screen. **Do not "fix" `fx_attachment.gd` for this.**
⚠ **§1b's quad-extent lever can be re-tried.** It was reverted because it "moved the rendered balls
on a ROTATED host" — measured on the instrument that was itself unreliable for exactly those panels.
That evidence no longer stands; re-measure before accepting the revert as final.

Full evidence: the `NOISY` comment in `Tools/snapshot_diff.py`.


---

## 2. ✅ FIXED — a lit ball's plume disappeared and came back

⚪ **HISTORY.** The mechanism (a comb tiled at ball pitch) no longer exists, so the bug class is deleted by construction. Kept for `lit_only` in `fx_nearest_ball`, which IS live, and for `06b_ball_fire_cycle`, which is still the guard.

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

## 3. ✅ CLOSED — the hoop's tendrils looked sliced

⚪ **HISTORY, and confirmed gone**: there is no arch left to slice, verified on `04_shapes`. Kept for one live number — 22.52 ms for 20 hoops is still the price of the only correct cross-column anchoring, and *"an anchor ships measured or not at all"* is a standing rule.

The reasoning below is kept because the 22.52 ms it prices is still the price of the only correct fix.

Unchanged, and unchanged on purpose. Each column's flame is anchored to that column's own surface, so
where the ring falls away steeply a flame's top can sit below its own base on the high side. The only
correct fix is cross-column anchoring, measured at **22.52 ms for 20 hoops** against 1.21 without —
the design the owner pre-ruled out. Letting a column stand on a NEIGHBOUR's floor is the trap he
spotted (the base then floats over void). **The owner's standing rule: an anchor ships measured or not
at all.** Two rejected builds came from approximating it. He has said it does not look too bad.

---

## 4. ✅ DONE — the FX editor turns, and juggling is proven not to

🟢 **LIVE.** The rotation knob and the claim it proves are both current; the claim now also has an assertion (§0d.1).

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

🟢 **LIVE, and §5b is a standing contract**: one style class per effect, and `FxAttachment` still touches only base members.

**The tool now re-reads its resources four times a second** (`FxEditor.WATCH_SECS`) and rebuilds when
anything the owner can edit has moved (owner: *"changing vfx parameters in editor does not
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

🟡 **THE NUMBERS ARE THE RETIRED BUILD'S — §0d.3 is the live table.** What is still live and still governs: §6b (host count is the wrong axis, the bound is the WINDOW) and §6a's two shipped changes.

⚠ **EVERY NUMBER BELOW IS THE RETIRED BUILD.** It is kept because it is the only Intel UHD data that
exists and because §6b's reframing — *host count is the wrong axis, the bound is the WINDOW* — still
governs. **§0b is the shipped build, on a GTX 1070.** Nobody has run the noise fire on the Intel box;
that is an item in §8.

**Taken on the owner's box: Intel UHD Graphics, driver 31.0.101.2135, Godot 4.7.1,
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

**Two changes, and BOTH are provably pixel-identical** (`py solatro/Tools/snapshot_diff.py`: all 18
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
directly (owner: *"did we find any ways to save ball juggling time?"*) — **no.** Measured
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

Owner: *"cards off screen don't affect performance right? if true we only need to limit
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

- **FILL.** A 38x50 card gets an **84.8 x 84.8** quad — `body.length()` (the 62.80 diagonal (38x50; 67.20 at 40x54), because a
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
- 🔴 **THIS ROW'S "~2x APART" CLAIM IS WRONG AND IT MISLED SEVERAL PASSES.** It was measured on the
  RETIRED build (`juggle both x20`: 1.06 on the 1070, 2.68–2.79 here). On the SHIPPED build the same
  comparison is **5x–8x** (§0d.3), because the noise fire gained far more on the 1070 than on the Intel.
  **Neither absolutes nor ratios transfer. Re-run `fx_cost.tscn` here.**

### 6f. If the juggling layer ever needs it again — the older levers, in order

1. ✅ **THE QUAD EXTENT — TAKEN,. §0d has the shipped numbers; the paragraph below is the
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

🟡 **LIVE except for the mask's representation**: the rig is still the source and `track_outline` still re-reads it every frame, but the 32-ray radius table this section describes is gone — the mask carries the outline's own vertices now (§0c.1).

Owner: *"card visual has bones and a default running animation which can heavily distort
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
here and §0 disagree, §0 wins. **Four groups: what a restart would pick up, the calls that are the
owner's, safe housekeeping, and what is closed.**

### 8a. NO OPEN ENGINEERING TASK — what a restart would pick up

| | Item |
|---|---|
| 🟢 **NOTHING IS OPEN** | FX performance is **PAUSED at the owner's call**, not finished. The worst window went **12.07 → 5.82 ms of GPU** across §0d.6, §0d.7 and §0d.9. |
| ⬜ **IF MORE BUDGET IS WANTED** | **§0d.10 is the one page**: today's numbers, five remaining levers priced with their risks, the ⛔ list of things that look like levers and are measured NOT to be, and the four traps in `fx_cost` itself. Read the ⛔ list first — it is the part that saves a day. |
| ⚪ **A debt that DIED with its lever** | `min_half`'s missing A/B no longer matters: per-instance sizing replaced `min_half` outright in §0d.6. ⚠ The claim it lacked evidence for is now carried by `snapshot_diff` ALONE — the rotated-ball assertion that was the other half was deleted as non-deterministic (§0d.1). |

### 8b. OWNER CALLS — nothing an agent should decide

| | Item |
|---|---|
| ⬜ **`cover_taps` 4 → 2 on the card style** | Worth **0.98 ms**, re-measured after §0d.9 made every tap cheaper (it was 1.24 before). §0e is the argument against: a card flame is 7 FX pixels tall, so 2 taps is 3.5 px per tap and the fire stops hugging the art. **Still the biggest single number left, and it is a look decision.** Judge it on `00_cover_field` then `01_fire_ladder` DRESSED. |
| ⬜ **`fire_card.height` (7 today)** | A FILL knob as well as an art one — the lit band is `height + sink` thick around the whole silhouette, so ~0.2 ms per art unit removed (§0f.5). |
| ⬜ **The juggling OVERLAP look, never judged by eye** | §0d.6 changed overlap from nearest-centre to highest-level (his ruling), and two crossing PLUMES now blend twice. Measured as tens of pixels on the crowded panels; nobody has watched it on a real board (§0f.6). |
| ⬜ **The retune, and the clobbered `fire_prop.tres`** | §0f. The `.tres` were MIGRATED, not tuned; `fire_prop` has been clobbered three times by the editor collision and §0g has the test for telling clobbering from tuning. **Ask before restoring anything.** |
| ⬜ **Playtest (T15)** | FX_SHADER_PLAN §10, 17 steps — the last gate. ⚠ Its old second purpose is spent: the owner has RULED that the saturated window is reachable, so no playtest is needed to settle that. |

### 8c. HOUSEKEEPING — small, safe, nobody's decision

| | Item |
|---|---|
| ⬜ **Three harnesses still use the stand-in** | `fx_snapshot`, `fx_behind` and `fx_cost` feed `star_outline` to a bare `Node2D`. They run in a real scene tree where a `CardVisual` needs none of the editor guards (`test_pixels` does it in ~10 lines), so the swap is mechanical — pin the card's seed and clock the way `_park` does. It would make `fx_behind`'s seam shots the real thing (its "filled host" is a filled polygon today) and delete `star_outline`'s last users. |
| ⬜ **Two stale snapshot panels** | `00_tendril_count` and `00b_ogee_profile` are still in `%APPDATA%\Godot\app_userdata\Solatro\fx_snapshots` from the retired build. They are never rewritten, so they compare identical for ever and pad the count from 18 to 20. Delete them. |
| ✅ **SNAPSHOT NONDETERMINISM — ROOT-CAUSED AND FIXED** | §1b/§12. `FxAttachment._rot_tight` defaults TRUE and is only re-evaluated under `if moved and on_screen:`, while `_push_live` skips its uploads entirely when `_on_screen()` is false. Both snapshot harnesses pushed the pose in the frame the node was added — before the canvas transform settled — then PARKED the attachment, so that call was the flag's only chance; a ROTATED host kept the upright quad bound and rendered clipped flames at random. Fix: settle TWO frames, then re-push and re-park (`fx_snapshot.gd::_settle_poses`, mirrored in `fx_behind.gd`). Verified 20/21 fx_snapshots panels identical over 3 runs and 5/5 fx_behind over 4. NOISY is down to `09_embers` alone. ⚠ **Not a game bug** — in play nothing parks the attachment. |
| ⬜ **Known limitation** | Ball highlight is a quantized ellipse at small radii — pixel-art resolution, not a defect. Levers: `ball_spec`, or a smaller `pixel` on the juggle style. |
| ⬜ **Deferred by the owner** | Map screen + in-game UI chrome still hardcoded (they warn `[WARN][PLACEHOLDER]` every run); `FireworkVisual` has no art; `suit_pips.png` has a few off-palette pixels. |

### 8d. CLOSED — do not reopen these without new evidence

| | Item |
|---|---|
| ✅ **Fire, whole** | Owner: *"with this we are done with fire effect changes."* The noise fire and its stack ratios (§0a/§0b), fire behind the art (§0c, accepted by eye), the warped corner (§0c.1, exact mask), the real-card test (§0c.2), the FX editor's real cards (§0c.4). |
| ✅ **The mask IS the art, corners included** | §0c.5 — measured off the type frame's own alpha, exact under deformation, asserted at ZERO disagreeing cells. ⚠ Costs 16 % of a burning screen, and the cost is the uniform ARRAY rather than the wedge loop — both micro-optimisations tried measured worse, and `cover_taps` is where it would be bought back. |
| ✅ **The Intel UHD measurement** | §0d.3 for the method; ⚠ **its ABSOLUTES are superseded — the worst window is 5.82 ms, not 10.8. §0d.10 has the current table.** Still true from it: the noise-source A/B is a WASH (three times now), and **the two boxes are 5x–8x apart, so no GTX absolute transfers.** |
| ✅ **`snapshot_diff.py`** | §0d.4 — it compared ALPHA only, and (§12) it scanned one of the three panel sets. Both fixed; it now walks 31 panels and separates the four known-noisy ones from real differences. ⚠ Any "panels identical" claim dated before that fix was measured with one or both defects in place. |
| ✅ **The juggling layer, and the CPU push** | §0d.6 and §0d.7. `fx_nearest_ball`, `fx_balls_near`, `fx_arc_ease_inv`, `u_ball_fire` and `FxJuggle.fire_texture` are all DELETED; the path no longer has to be invertible. ⚠ Do not reintroduce a per-fragment "which ball am I" search. |
| ✅ **A ring/strip mesh for card fire** | Priced and REJECTED in §0d.10's ⛔ list — ~0.3 ms for a reflex-corner problem and a vertex budget, because §0d.9's two-line early-out already took the interior out of the expensive path. |
| ✅ **`05f_ball_rotation`'s displacement** | A harness flake, reproduced on an unchanged build, and the claim now lives in an asserting check (§0d.1). |
| ✅ **The hoop's sliced tendrils** | Gone with the arch, confirmed on `04_shapes` (§3). |
| ✅ **The five rounds of owner reports** | The pixel size, the editor freeze, the tap banding, the flame's foot, the `height` jitter, fire-behind on balls, the corner chamfer — all in §0g with the measurement that found each. |

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

⚠ **THE COMB IS NOT THE COST, AND DELETING IT BUYS NOTHING** (owner asked; verified in the
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

⚠ **A, B, C AND THE TAP WORK HAVE ALL SHIPPED; almost nothing in this table is live any more — §0d.10 is
the current list.** A is `body_near`, in the shader since §6a and carried through the rewrite intact.
**B shipped in §0d.9** (the circumscribed bound only while the host is really turned — and read there why
the "resizing moves the lattice" objection against it was void). **C shipped as `min_half` in §0d and was
then superseded by per-instance sizing in §0d.6.** D and F are moot — there is no march left to shorten or
unwarp, and D's descendant (distance-to-edge on a ring mesh) is priced and rejected in §0d.10. **E is the one
thing here still worth keeping**: it is the remaining answer to §8's corner chamfer if the mask is ever
revisited, and it makes every tap cheaper, which multiplies with the tap count rather than adding to it.
⚠ **E's cheaper cousin — the 20-point diagonal chamfer — is lever 2 of §0d.10.**

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

⚪ **The "recommended order: A, then B" this section used to end on is spent — A, B and C are all in.**
What replaced it is §0d.10's priced list, and the honest summary of how this table aged is that its three
non-visual levers together were worth less than the two lines of §0d.9's buried-fragment early-out, which
nobody on this list thought to look for.

⚠ **Do NOT just raise `RADII`.** The numbers are in §7: it converges far too slowly on a sharp vertex
to be worth the uniform bytes (32 → -2.32, 64 → -1.41, 128 → -0.56 art units).

---

## 11. Runbook

`Godot` below is the console build, run from the repo root. Its path differs per computer —
see `../.claude/memory/machine-profiles.md`.

```bash
Godot --path solatro res://Tests/all_tests.tscn            # windowed, ~60-85 s, exit = failure count
Godot --path solatro res://Tests/Visual/fx_snapshot.tscn   # after ANY shader edit
Godot --path solatro res://Tests/Visual/fx_behind.tscn     # the SEAM: hosts drawn FILLED (§0c)
Godot --path solatro res://Tests/Visual/prop_art_snapshot.tscn
Godot --path solatro res://Tests/Visual/fx_cost.tscn       # ms/frame per host kind — not a test
py solatro/Tools/palette_conformance.py
py solatro/Tools/snapshot_diff.py save                     # stash the PNGs you trust as a baseline
py solatro/Tools/snapshot_diff.py diff                     # re-run fx_snapshot, then prove nothing moved
py solatro/Tools/make_fx_noise.py                          # re-roll Assets/Fx/noise_fire.png
```

⚠ **`fx_cost.tscn` NEEDS THREE RUNS ON THIS BOX, AND YOU TAKE THE MINIMUM.** The GTX 1070 sits in two
power states and the GPU timer is bimodal by ~1.3–1.5x between them, with every row of a run scaled
by the same factor — five consecutive runs of ONE unchanged build read 0.594, 0.597, 0.753, 0.874 and
0.924 on the same row. A single run is not evidence; consecutive runs agreeing to ~1 % are. (§0b.)

⚠ **AND ON THE OWNER'S INTEL UHD IT IS STEADY** — three runs hold to ~2–3 % on most rows, so a 6 %
delta is real evidence there and the same delta on the GTX box is not. Take three runs on either.
⚠ **`snapshot_diff.py` HAS BEEN BLIND TWICE, AND ONLY THE SECOND FIX MAKES ITS COUNT MEAN ANYTHING.**
It compared ALPHA only (§0d.4), and it scanned **`fx_snapshots` alone** while its own docstring
claimed the prop harness too — so `prop_art_snapshots` and, worse, `fx_behind` were never diffed at
all (§12). Any "N of N panels identical" claim predating both fixes means nothing. It now walks all three sets (18 → **31 panels**) and names a missing one instead
of dropping it.

⚠ **FOUR PANELS DIFFER ON UNCHANGED CODE and the tool lists them as `noisy` rather than counting
them**: the three ROTATED ones (§1b) plus `09_embers` (randomised particles, by design).
⚠ **`10_light_layer` was a FIFTH and nobody had noticed** — upright, and the worst of the set at 8.1%
of the frame. It is now FIXED (§1b) and back in the diff. Its late discovery still matters:
HANDOFF_spotlight's G3.3 pass had explained that exact panel's difference as the 38x52 art refactor,
"verified by eye", which a panel moving 78k px between two runs of ONE unchanged build could not
support — that claim is now re-testable. Two stale retired-build panels still pad `fx_snapshots`
(§8c).

**For a change that must not alter the picture, `snapshot_diff.py` is the instrument, not your eye.**
"Judge fire by EYE" is right for a change that is SUPPOSED to look different; an optimisation's only
honest claim is byte-identical, and an eye is far too generous for that.

⚠ **AND FOR AN EDITOR-ONLY CLAIM, THE EDITOR IS THE ONLY INSTRUMENT** — nothing that RUNS can see a
`@tool` or placeholder problem (§0c.4). This is how to test one without opening the GUI by hand, and it
needs the owner's editor CLOSED:

```bash
Godot --path solatro --editor --quit-after 400 res://Tools/fx_editor.tscn
```

It opens the project, builds the scene, prints every script error to stdout and quits. A/B it by
reverting the change and running it again — that is how the `@tool` chain was settled.

**Last full run (Box A, with everything through §0d.9 in): 28 suites, 1628 CHECKS PASSED.** The total
COUNT varies run to run because BOARD FUZZ is randomised; what must hold is **28 suites and exit 0**.

⚠ **`fx_cost.tscn` CANNOT TELL "CHEAP" FROM "NOT DRAWN", and §0d.6 lost half a day to exactly that** —
an instanced build whose balls were being culled read 10x faster than the real thing and every row
looked like a triumph. **Run `all_tests.tscn` (the PIXELS ball checks) or `fx_snapshot` BEFORE believing
any speedup.** A number that improves more than the model predicts is a bug report, not a win.

⚠ **TWO RENDERING HARNESSES HANG AT RANDOM ON THIS BOX, AND NEITHER IS A FAILURE.** Measured
while A/B-ing §0d: `test_pixels.tscn` run STANDALONE printed all 37 checks and then never
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
 , live: while `FxStyle` was being edited from a session, the owner's editor saved five
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
  ⚠ **BEFORE `sync()` IS THE WHOLE OF IT, AND BOTH REVIEW HARNESSES GOT IT WRONG** (§12b): `u_seed`
  is written to the material inside `_make_quad`, so `fx_behind`'s assignment BELOW its `sync` set a
  field the shader had already read, and `fx_snapshot` pinned `_ball_dir` — with a comment stating
  this very rule — while never pinning `_seed` at all. An assignment that is a no-op looks exactly
  like one that works.
- **`Texture2D.get_image()` + `Image.get_pixel` is a real hitch** (2304 calls for one hoop frame,
  once per attachment, three per split prop). `FxAttachment._sprite_cache` exists for that reason.
- **The GLSL shading language has `PI`, `TAU`, `E` — but NOT `HALF_PI`.** Using it compiles to
  nothing and every effect renders SOLID WHITE, which looks exactly like the `@tool`/placeholder
  failure. `smoothstep` also wants its edges in increasing order; reversing them is undefined.
- **Every script in `UI/Fx/` and every FX host must stay `@tool`.** A non-tool script loads as a
  PLACEHOLDER: `FxStyle.apply()` never runs (white effects) and saving a `.tres` DROPS the properties
  the editor could not see.
- ⚠ **Never kill a Godot process without reading `MainWindowTitle` first.** The owner's editor was
  killed by a blanket `Get-Process *odot* | Kill()`.
- `PropVisual._ready()` early-returns in the editor, so a snapshot scene and the editor can disagree.

---

## 12. CODE-REVIEW AUDIT
A review pass over everything since `22f2aac` (the VFX plan) through `b566324` (the simplify pass):
~11.3k added lines. **The shipped FX layer held up** — nothing in the simplify commit was a
regression, and the nine defects below are all in seams the suites do not reach. Recorded here
because most of them are in the INSTRUMENTS, and an instrument that lies is worse than no instrument.

Verified: **ALL 28 SUITES green, windowed, twice** (`1591` / `1614` / `1621` checks — the total
drifts run to run on the data-dependent suites), all 235 `fx_snapshot` ball probes agreeing to under
one art unit, and `snapshot_diff` clean across all 31 panels.

### 12a. The game

| Fix | What it was |
|---|---|
| **`PropVisual.flipped` is a SETTER now** | `PropLayer.begin_prop_tick`'s staged pose set `vis.flipped` without mirroring the attachments, unlike `retarget`. `u_art_flip` stayed `+1`, so a burning knife staged heading right drew its blade mirrored while the fire mask read the un-mirrored frame — flames off the drawing until its first horizontal leg. The setter owns the propagation, so every site gets it; `_make_fx` seeds a late-built attachment. |
| **`_push_live`'s off-screen guard skips UPLOADS ONLY** | It was an early `return` above the loop, so it also froze `Effect.t` and `Effect.fade` and never reached the release. A card that lost its Burning while scrolled out of the play area kept its quad, kept `set_process` on, and came back at FULL opacity to start fading only then. ⚠ **The follow-up matters as much as the fix:** gating the upload alone leaves `Effect.pushed` false for ever on an invisible host and rebuilds the eased Dictionary every frame — so the eased EVALUATION is gated with the upload, and only two float advances plus the release still run. §6b's "off-screen is FREE" row is what would have reported getting that wrong. |
| **`extent.ceil()` moved into the non-instanced branch** | It was rounding INSTANCED extents to whole ART UNITS, over the whole-number-of-`pixel`-CELLS contract `FxJuggle._cell_box` exists to satisfy (`FxRequest.instance_half`). Dormant at today's `pixel = 1.0`; at 0.3 it slices the outer ring of every ball and plume. `test_fx_attachment` asserts the contract on `instance_half` and so could never have caught it on the quad. |
| **`track_outline` skips INSTANCED quads** | The balls quad leaves `shape` at -1, so it inherited the card's RADII and slipped past the shape test — uploading a 24-vertex polygon plus four more uniforms into `juggle.gdshader`, which declares none of them, every frame the rig moved (which is every frame). Five wasted `set_shader_parameter` calls per juggling host per frame, inside the function §0d.7 emptied. |
| **`_apply_static` seeds `u_shape_rot` / `u_lag`** | `_push_live` sends the pose only when it CHANGES, and a material born mid-life starts at the shader defaults — so an effect added to a host already turned, and not turning further that frame, masked against an angle the host did not have. |
| **`fire.gdshader`'s sprite frame test is half-open** | `repeat_disable` clamps to the TEXTURE edge, never the FRAME's, so `t == 1.0` sampled the first texel of the NEXT frame on the sheet — the hoop's back arc bleeding into the full ring's mask. `>=` costs nothing and a frame's footprint really is `[0, 1)`. A/B'd across all 31 panels: **no rendered pixel moved**, which is what "the boundary was never inside the frame" predicts. |
| **`fx_editor` owns its clock** | It let the attachments self-drive and then added `delta * (time_scale - 1.0)` — the DIFFERENCE, which is NEGATIVE below 1.0, and the scene ships at 0.5. A negative delta reaches `_push_live` as a negative `step`: `Effect.t` walks backwards out of its ease and `Effect.fade` can never reach 1, so a released effect never goes away in the preview. `_time` netted out correctly, which is why it looked fine. |

Not a defect, checked and dropped: `StringName.begins_with` **is** supported in Godot 4.7 (verified
directly), so `PaletteRoles._get` is fine. `_poly_padded` is safe but does NOT avoid an allocation —
CoW forks it once the material holds the Variant — and its comment now says so, because an
overclaiming perf note is what invites the next round of "optimization".

### 12b. The instruments — and this is the half worth reading

| Fix | What it was |
|---|---|
| **`snapshot_diff.py` scanned 1 of 3 sets** | Its docstring claimed the prop harness; it read `fx_snapshots` only. `prop_art_snapshots` and — worse — `fx_behind`, the ONLY harness that shows where flame meets art, were never diffed. This is the second time this tool has been silently blind (§0d.4 was the first). Now 31 panels across three sets, with a missing set NAMED. |
| **Known-noisy panels are listed, not counted** | Four panels differ on unchanged code (§1b). Burying one real regression under four expected ones is how a diff stops being read; DROPPING them silently is the `_bbox` mistake in the other direction. They print as `noisy` with their pixel counts and sit outside the verdict. |
| **Both review harnesses mis-pinned the seed** | `u_seed` is written to the material in `_make_quad`, i.e. while `sync` BUILDS the quad. `fx_behind` set `att._seed` AFTER `sync` — a no-op on a field the shader had already read — and `fx_snapshot` pinned `_ball_dir` with a comment stating exactly that rule while never pinning `_seed` at all. Both fixed. ⚠ **This did NOT fix the rotated-panel flakiness** — tested directly; that is a separate, still-unknown cause. |
| **`test_pixels._check_directions_split` skipped SILENTLY** | `if arcs != count: continue` guarded the one condition that makes the guard mean anything (the cancellation was total only where ball count == arc count). Retune `ball_arcs_per_count` and the regression check would test nothing with the suite still green — the exact failure that file's own header refuses to allow. Now a check that fails loudly, plus 3 new PASSes. |
| **`test_balls_alternate_directions` read a stale `_zoom`** | Its search radius came off the PREVIOUS shot's zoom, since `_host_balls` is what sets `_zoom`. Right by luck today (both clamp to `ZOOM`); a `ball_span` or `ball_arc_max` retune silently makes the window too tight (ball reported missing) or too loose (the mirrored spot found). |
| **`PixelProbe.ball_positions`' docstring had drifted** | Three stale claims — a per-ball mirror, `f * 2 / arcs` equal shares, the lowest arc exempt from the ease — each describing a model retired and each contradicted by the inline comments a few lines below. ⚠ **That paragraph is the SPEC the oracle is transcribed FROM**, so it drifting is worse here than anywhere else in the project: a reader "fixing" the oracle to match it would make it agree with nothing. |

### 12c. An ART RETUNE turned the suite red, and the instrument was at fault

⚠ **THE ONE FINDING HERE THAT WAS FOUND BY A FAILING TEST RATHER THAN BY READING**, and the honest
answer was to change the test, not the art.

`ramp_ball.tres` was retuned in the editor from palette entries **16/30/6 to 7/8/9** — three oranges
to three GREENS. `PixelProbe.is_warm`, the predicate both harnesses used to find a ball in a rendered
frame, was `r > 0.45 and r > b * 1.6 and g > b`: *"a ball is orange"*. Of the new tones only the
lightest still reads as warm, and the cream gloss never did — so a ball registered on its lit sliver
alone. At 50 balls the radius is pinned to its 1.0 floor (~4 px on the stage), which took **5 of 50
balls to "missing" in one direction and 7 in the other**, and pushed the worst measured offset to
2.73 against a 2.0 tolerance. Both `50 balls all render within 2.0 art units` checks failed,
deterministically and identically across runs.

**Fixed by deriving the ball's colours from the STYLE** (`PixelProbe.ball_colours` / `ball_pixel`):
its tones ramp plus the gloss role, matched exactly, because that is precisely what the shader emits
— `u_ball_tones` is `filter_nearest`, one texel per band, never a mix. It cannot go stale against a
retune, which is the same reason nothing else in the project stores a colour value (T21).

Two things this dragged out with it:

- **`fx_snapshot`'s ball PROBE was blind in the same way and said nothing about it**, because it only
  prints. Worse, its oracle CROSSES are green — so a hue test could no longer tell a ball from the
  mark showing where the ball should be. 5 of 235 probes still failed after the first fix: the
  FOCUSED panel multiplies the ball by the host's `1.825` modulate (ruling 10), so the predicate now
  takes the tint and clamps it the way the 8-bit target does. **235 of 235 agree to under one art
  unit.**
- ⚠ **`ramp_ball.tres` and `juggle_default.tres` are UNCOMMITTED**, and were not touched by this
  audit — the editor-collision trap in §11 is exactly this, and its advice (`git diff` before
  believing a test result) is what found it in one step.

### 12d. What this says about the test layer

The suites are strong where they assert and blind where they SKIP — every instrument defect in §12b
is a silent skip, a stale spec, or a tool measuring less than it claims, and none of them could ever
turn a run red. Three are worth generalizing:

- **A guard that `continue`s past its own precondition tests nothing and reports success.** Both
  cases here were written as `continue` and should have been `check(); if fail: continue`.
- **A tool's claimed SCOPE is part of its contract.** `snapshot_diff.py` was correct about every
  panel it looked at, both times it was blind. What was wrong was which panels it looked at.
- **A check that infers a fact instead of asking for it dies at the next art change.** `is_warm`
  guessed at hue where the style could simply be asked. When a test fails right after a `.tres`
  edit, `git diff` the resources FIRST — the art is usually right and the instrument usually is not.

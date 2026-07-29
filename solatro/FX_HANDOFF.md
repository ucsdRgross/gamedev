# FX_HANDOFF.md — live handoff, updated 2026-07-30

**Read [VFX.md](VFX.md) and ARCHITECTURE_REVIEW **§4g** first** (the map and the contract).

The fire emitter was replaced by the MASK model on 2026-07-30 and the suite is green. This file is
the OWNER'S REVIEW of that build: five things he found or asked for, in the order they should be
picked up. **Delete this file once §1–§5 are settled.**

⚠ **The owner will run the `simplify` skill over the unpushed commits.** Land behaviour first; do not
pre-emptively restructure for tidiness.

---

## 1. ⬜ THE BIG ONE — JUGGLING IS TOO EXPENSIVE, and it scales per host

**Measured** (`Tests/Visual/fx_cost.tscn`, 20 juggling cards with 5 balls each, all lit, Intel UHD):
**28.5 ms per frame** — nearly two whole 60 fps frames. It is **not** a regression (the shipped
contour build measured 26.6 ms on the same bench; the mask model added ~2 ms) but it is now the
worst number in the layer, and the cost is **per host**: ~1.4 ms each, so even FIVE juggling cards
is ~7 ms — half a frame — before anything else in the game draws. Owner: *"we need to make as cheap
as possible."*

**THE TARGET, and the reasoning behind it (owner 2026-07-30).** 60 fps is a 16.67 ms budget for
EVERYTHING — game logic, render submission and GPU work. CPU and GPU are pipelined, so each gets the
full 16.67 ms rather than half each, but one effect layer at 28.5 ms means the frame cannot hit 60 at
all. For scale: AAA 3D at 30 fps budgets ~2–5 ms for particles/VFX out of 33 ms, i.e. VFX is ~10–15 %
of frame even where it is the main event. **A 2D pixel-art card game should be far under that.**

> **Target: ALL FX on screen ≤ ~2 ms on the Intel UHD this was measured on — about 0.2 ms per
> juggling card, a ~7× reduction.** Demanding, but the `O(arcs²)` waste below is pure overhead with
> no visual contribution, so most of it should come for free.

⚠ Two honesty notes on the measurement. 20 juggling cards with EVERY ball lit is a worst case that
may never occur in play; 3–5 cards is ~4–7 ms, which is bad but not catastrophic. And Intel UHD is
the low end — a discrete GPU would be several times faster. **If the game targets laptops, the Intel
number is the number.** Re-measure on the owner's real target before declaring victory.

### ⚠ 1a. FIRST, UNLEARN THE ADVICE THIS FILE AND VFX.md USED TO GIVE

**"Raise `FxStyle.pixel`" DOES NOT REDUCE THE FRAGMENT COUNT.** `fx_local()` quantizes a
*coordinate* inside the fragment shader; the quad's screen footprint is unchanged, so the shader
still executes once per screen pixel. Chunkier FX pixels help warp coherence and texture-cache hits
a little, and that is all. That claim predates this work, and I repeated it — it is corrected in
VFX.md §6.3 now. **Do not spend a round on it.**

### 1b. The three real levers, cheapest and safest first

1. **HOIST THE LOOP-INVARIANT ARC MATHS — biggest win, zero visual change.** In
   `fx_common.gdshaderinc`, `fx_nearest_ball` is `O(arcs²)`:
   - `fx_arc_span()` calls `fx_arc_total()` (a loop over `FX_MAX_ARCS`) and *then* loops again;
   - `fx_ball_at()` calls `fx_arc_total()` again, then walks the ladder again;
   - `fx_nearest_ball()` calls `fx_arc_span()` **per arc**, and `fx_ball_pos()` twice per arc.

   At the 8-arc ceiling that is roughly **384 `fx_arc_weight` evaluations per fragment**, each with a
   `sqrt`, plus `pow()` in the ease. Every one of those depends **only on uniforms** (`u_ball_arcs`,
   `u_arc_height`, `u_return_height`, `u_top_fraction`) — nothing per-fragment. Compute the arc
   starts/shares ONCE and reuse them. Best form: push them from `FxJuggle`, which already computes
   the identical weights on the script side (`_arc_weight`), as a `u_arc_start[8]` / `u_arc_share[8]`
   pair — that also removes a whole class of script/shader drift. Expect ~384 → ~48 inner iterations.
   ⚠ Both `juggle.gdshader` and `fire.gdshader` include this file, so both quads get the win.
2. **A CHEAP EARLY-OUT BEFORE `fx_nearest_ball`.** Most of a ball quad is empty space between arcs.
   Each arc is `y = -h_j · sin(a·PI)` with x monotone, so the vertical distance from a fragment to
   each arc curve is a handful of ops — reject when it exceeds `radius + plume height` for every arc,
   before paying for the ball lookup at all. Same shape of saving as the existing "guard the noise"
   branch, which §4g calls the single biggest one in the fire shader.
3. **SHRINK THE QUADS.** `FxAttachment._size_quad` uses the CIRCUMSCRIBED (diagonal) bound whenever
   `rotates` is true, and a card rotates — so a juggling card pays `body.length()` = 62.4 instead of
   38×50. **But the juggling pattern provably does not rotate with its host** (§4 below):
   `juggle.gdshader` never reads `u_shape_rot`, and the attachment counter-rotates the quad. So the
   diagonal bound buys the BALL quads nothing — roughly 22 % of their fill.
   ⚠ Fire on a card DOES need the diagonal bound: its mask rotates. So this is a per-REQUEST
   property, not a per-host one.

**Only after those three** should anyone touch `ball_arcs_max`, the arc ladder, or feature scope.
Re-measure with `fx_cost.tscn` after each step.

⚠ **The bench lumps the two ball quads together.** `_balls_case` builds `FxJuggle.requests(...)`,
which is the balls quad AND the ball-fire quad. Split it before optimising so you know which one you
are paying for.

---

## 2. ⬜ BUG — a lit ball's plume disappears and comes back

Owner: *"fire on balls sometimes disappear, then reappear later."*

**Prime suspect, and it is mine.** `fire.gdshader::fragment()` resolves the nearest ball **once per
fragment** and hands that one ball down to every `mask_level()` call (a deliberate hoist — re-running
the closed-form lookup at every march step would cost more than the rest of the shader). Two
consequences:

- The ball nearest to a fragment **high above ball A** may be a different ball B. The march can then
  only ever hit B, so A's plume is simply absent in that column.
- Worse: if B is **unlit**, `mask_level` returns `MASK_DARK`, the march reports "solid but emits
  nothing", and `mask_lit(floor_level)` fails — so the fragment is forced dark. **An unlit ball
  actively suppresses a lit ball's plume wherever it wins the lookup.** With `lit_balls` well below
  `ball_count` that happens constantly, and it changes as the balls travel — which is exactly
  "disappears, then reappears later".

**Cheapest fix to try first:** in the ball branch, return `MASK_EMPTY` for an unlit ball instead of
`MASK_DARK`. The "solid but dark" rule exists so an unlit ball stays dark (ruling 3) — but it is
already dark by emitting nothing, and the occlusion it buys is a nicety that is costing real plumes.
Failing that, resolve the nearest **lit** ball rather than the nearest ball.

**Repro:** `UI/Fx/Tools/fx_editor.tscn` with `ball_count = 6`, `lit_balls = 2`, `time_scale`
non-zero — watch the plumes over a few cycles. `fx_snapshot`'s `06_ball_fire` captures one phase
only, which is why this got past it.

---

## 3. ⬜ THE HOOP'S TENDRILS LOOK SLICED — the cost of the dropped anchor

Owner: *"lots of tendrils look like they are cut halfway through. It doesn't look too bad, but is it
fixable or would it cause base of tendrils to illegally spread over edge of art?"*

**The instinct is right, and the answer is: not cheaply, and the risk he named is the real one.**

Each column's flame outline is `floor(x) - height · dome(u)` — anchored to **that column's own**
surface. Where the ring's surface falls away steeply the outline plunges with it, so a flame's top on
the low side of a cell can sit below its own base on the high side. That reads as a slice. It is not
clipping and not a quad bound: it is the arch riding the surface, which is precisely what dropping
the per-cell anchor bought (§4g, and the 21 ms measurement behind it).

- **The only correct fix is cross-column anchoring** — one anchor per cell, every column draping to
  its own floor. Measured at **22.52 ms for 20 hoops** against 1.21 ms without. That is the design
  the owner pre-ruled out for exactly this reason.
- **Letting a column stand on a NEIGHBOUR's floor is the trap the owner spotted:** the base then sits
  where there is no art beneath it, i.e. floating over void. Do not do it.
- **A cheaper anchor may exist and would need measuring, not assuming.** The `merge` path already
  evaluates the two neighbouring cells for the same fragment using the SAME `floor_y`, so it costs no
  extra marches — whether anything usable can be derived from that is the open question. ⚠ **The
  owner's standing rule: an anchor ships measured or not at all. Two rejected builds came from
  approximating it.**

**Verdict for now:** accept it (the owner says it does not look too bad), and treat a cheaper anchor
as a scoped experiment with a bench number attached, not a tuning pass.

---

## 4. ⬜ FX EDITOR — add a rotation slider (it should CONFIRM juggling is already correct)

Owner: *"add slider in fx editor to rotate objects in scene to see how fx handles it. Juggling effect
should remain upright around center of card even if card rotates. Only requirement is that juggle
effect doesn't rotate with card."*

**That requirement is already satisfied structurally — the slider is to PROVE it, not to fix it.**

- `FxAttachment._push_live()` sets `rotation = -parent.global_rotation`, so every quad holds still in
  world space while the host turns (the universal no-rotating-grid rule).
- `juggle.gdshader` **never reads `u_shape_rot`** — the pattern's geometry is defined in quad space,
  so it cannot tilt. The only thing the spin rotates is a ball's SHADING FRAME, after quantization.
- The attachment sits at the host Offset's origin, i.e. the card's centre, so the pattern stays
  centred on the card exactly as asked.

**What to build:** an `@export_range(-180, 180, 1)` degrees knob in the `Stage` group of
`UI/Fx/Tools/fx_editor.gd`, applied to each host node — its `_touch()` setter is the existing idiom,
every knob there already rebuilds on change. Fire on a rotated host is covered by `fx_snapshot`'s
`02_fire_rotation`; **there is no rotated JUGGLING shot anywhere**, so add one while you are here —
that gap is why this went unverified.

---

## 5. ⬜ EMBER TUNING — the knobs exist, the editor just does not surface them

Owner: *"embers look fine on props, I assume I can tune to look better. Where should I tune it? Only
see show embers in editor and not the tunables."*

**Where they live today:**

| Knob | Where |
|---|---|
| Everything about how an ember LOOKS and MOVES | `Shaders/Styles/ember_prop.tres` (props **and** balls) and `ember.tres` (card) — `ParticleSpec` resources |
| `lifetime`, `lifetime_var`, `speed`, `speed_var`, `spread`, `gravity`, `drag`, `size_start`, `size_end` | the same two `.tres` |
| Colour | `ramp_source` (a `PaletteRamp` — palette entries only, T21) + `ramp_alphas` |
| How MANY per second, per host | `FxStyle.ember_rate_max` on `fire_prop.tres` / `fire_ball.tres` / `fire_card.tres` (12/s prop and ball, 24/s card) |
| Whether a fire throws embers at all | `FxStyle.ember` (null disables — that is what viewer styles use) |

To tune right now: select the `.tres` in the FileSystem dock and edit it in the inspector; the
fx_editor preview picks it up live, because `FxStyle.ember` points at that same resource.

**The friction is real and worth fixing:** `fx_editor.gd` exposes only `show_embers : bool`, so you
must leave the tool's inspector to reach the numbers. **Add `@export var ember_spec : ParticleSpec`
(and the card one) beside `show_embers`**, with the same `_touch()` setter — one line each, the same
pattern as `fire_style` / `prop_fire_style` above it, and every ember knob is then one click away
while the preview is on screen.

⚠ `ember_prop.tres` deliberately carries **no comments** — the editor strips them on save. Its
rationale lives on `FxStyle.ember`'s doc comment instead. Keep it that way.

---

## 6. What is LEFT after the above — the honest state of the VFX layer

Nothing here is secretly broken; each is understood. Full backlog in **VFX.md §6/§7**.

| | Item |
|---|---|
| ⬜ **Blocking "done"** | **Owner playtest (T15)** — nobody has PLAYED any of this. The 17-step walk is FX_SHADER_PLAN §10. No agent can do it. |
| ⬜ Perf | §1 above. Also still unmeasured: **50 burning cards in the DECK VIEWER**, the densest screen in the game (`fx_cost.gd` takes a `HOSTS` constant — raise it and re-run). |
| ⬜ Bug | §2 above. |
| ⬜ Accepted | §3 above (sliced tendrils on curves). |
| ⬜ Art calls only the owner can make | The fire ramp's ENDS (entry 0 makes a 1-stack flame near-black, entry 19 puts neutral grey at the white-hot end — one-line edits to `Assets/Palette/ramp_fire.tres`); prop art SIZES; flame `height` per style; `level_ref`; `base_width`. |
| ⬜ Known limitation | Ball highlight is a quantized ellipse at small radii — pixel-art resolution, not a defect. Levers: `ball_spec`, or a smaller `pixel` on the juggle style. |
| ⬜ Deferred by the owner | Map screen + in-game UI chrome still hardcoded (they warn `[WARN][PLACEHOLDER]` every run); `FireworkVisual` has no art; `suit_pips.png` has a few off-palette pixels. |

**Do we need more cycles?** Yes — §1 is a real performance problem and §2 is a real bug. §3, §4 and
§5 are each a small, well-scoped session. After those the layer is waiting on the owner's eyes and
his art calls, not on more engineering.

---

## 7. Runbook

```bash
Godot --path solatro res://Tests/all_tests.tscn            # windowed, ~60-85 s, exit = failure count
Godot --path solatro res://Tests/Visual/fx_snapshot.tscn   # after ANY shader edit
Godot --path solatro res://Tests/Visual/prop_art_snapshot.tscn
Godot --path solatro res://Tests/Visual/fx_cost.tscn       # ms/frame per host kind — not a test
py solatro/tools/palette_conformance.py
```

Last full run (2026-07-30): **28 suites, exit 0** (the check COUNT varies run to run — BOARD FUZZ is
randomised; what must hold is 28 suites and exit 0). Palette conformance 0.2–0.7 % per FX shot, all
edge blends.

**Judge fire by EYE, never by counting columns** — that instrument reported two rejected builds as
successes. `py <scratch>/crop.py <png> <out> x y w h scale` (PIL, nearest-neighbour) is how these
were reviewed; a snapshot panel is too small at 1x.

### Traps, each of which cost real time

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

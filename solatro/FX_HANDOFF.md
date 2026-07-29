# FX_HANDOFF.md — live handoff, updated 2026-07-29

**Read [VFX.md](VFX.md) and ARCHITECTURE_REVIEW **§4g** first** (the map and the contract).

⚠ **START AT §0. THE FIRE MODEL IS BEING REPLACED.** The owner has chosen a cheaper, generic,
noise-based fire — no lanes, no tendrils, no ogee, no onion shells — and §0 is the spec for it.
Everything from §1 to §7 describes the build being retired: **read it as the record of what was
learned and what must not be broken, not as a description of what to keep.** **§8 is the live list**;
§9 is the cost attribution that justifies §0, and §11 is the runbook.

Sections are numbered in reading order. If you add one, keep it that way — an earlier edition had
§6.-1 and put §7b before §7a, and it cost a reader real time.

⚠ **The owner will run the `simplify` skill over the unpushed commits.** Land behaviour first; do not
pre-emptively restructure for tidiness.

⚠ **NUMBERS: §1's are a GTX 1070; everything in §6 and §9 is the owner's Intel UHD** (driver
31.0.101.2135, gl_compatibility), which is the real target. The two are ~2x apart on these rows, NOT
the ~12x an earlier edition of this file assumed. Ratios transfer; absolutes do not.

---

## 0. ⬜ THE NEXT BUILD — THE FIRE MODEL THE OWNER HAS CHOSEN

Owner, 2026-07-29: *"Fire effect no longer has tendrils at all, just average fire shader effects like
moving noise instead... just increasing shader params as intensity/stacks increase, no more individual
tendrils, make sure all params have scaling ratios as stacks increase"* — and *"should still be form
fitting to any shape and rotation. Do this for all current fire effects card prop ball."*

**The rationale is the owner's and it is an ART call**: tendril count only reads at single-digit
stacks, after which the ladder stops adding tendrils and the other parameters carry the intensity — so
the tendrils were never doing much work. ⚠ **Do not sell this as a performance win on its own: §9
measures the tendril math at 4 %.** What it buys is the RIGHT to stop marching, and that is 1.7x. The
two changes are worthless apart and compound together — §9 is the whole argument, read it first.

### 0a. What goes, what stays

| GOES | STAYS, and why |
|---|---|
| the COMB / lanes (`w`, `cells`, `pitch`, `id`) | the MASK (`mask_level`) — it is what makes fire form-fitting |
| `tendril()` / `tendril_at()` | `u_pixel` quantization + the world-aligned grid |
| the OGEE arch (`ogee_point`, `ogee_flare`, `base_width`) | the PaletteRamp (`u_ramp`) — see 0e |
| the ONION shells (`onion_power`, `onion_rise`) | `u_sink` (erosion into the art) and `u_inner_alpha` |
| `merge`, `desync`, `sway_*`, `wave_*`, `height_var` | `u_time` (paced, pausable — NEVER built-in `TIME`) |
| the DOWN-MARCH (`surface_below`) | `u_lag` (the cape), `u_level`, `u_intensity`, `u_brightness` |

### 0b. The model, in four lines

```
cover(p) = fraction of N fixed taps BELOW p, within reach, that land inside the mask   // §9
rise     = (1.0 - cover) * reach                     // height above the surface, no search
n        = noise(p * scale + vec2(0, u_time * scroll) + u_seed)     // RISING, world-aligned
heat     = clamp(aperture(cover, rise) * n, 0, 1)  ->  COLOR = texture(u_ramp, vec2(heat, u_level))
```

`cover` replaces the march AND the tendril in one move: it is both "where is the surface" and "how far
above it am I", to the resolution the noise actually needs. **§9 measured 4 taps at 1.7x and 8 at
1.16x — start at 4 and let the owner look.**

### 0c. Why it is still form-fitting and rotation-proof — the two properties that must not regress

- **FORM-FITTING IS FREE, AND STRICTLY BETTER THAN TODAY.** `cover` is sampled from the mask itself, so
  fire hugs whatever `mask_level` answers — card, deformed card, blade, ring, ball. Three §1 properties
  that currently need argument fall out by construction: **every upward-facing surface burns** (the
  hoop's inner-bottom arc is just more body below a fragment), **no flame leaps the hole** (no tap
  reaches further than `reach`), and **the corner chamfer disappears** (§7's bug — there is no angular
  surface-finding left to miss a vertex).
- **ROTATION-PROOF IS NOT AUTOMATIC — KEEP THE RULE.** Owner ruling 1: flames point WORLD-UP on a
  spinning host. The taps must step WORLD-DOWN and only the mask LOOKUP may rotate (`u_shape_rot`),
  exactly as `surface_below` does today. The noise must be sampled in the same world-aligned, already
  quantized `p` — **never rotate a coordinate before quantizing it** (fx_common §0b) or the pixels go
  diagonal, which is the universal rule this whole layer is built on.

### 0d. Scaling with stacks — one place, and every knob needs a ratio

`FxFire.stacks_live()` is the ONE mapping from stack count to uniforms, and it stays that. Today:

```
u_count     = min(count, FX_MAX_TENDRILS)        # RETIRE the cap; see the warning below
u_intensity = intensity * (1 + log(over) * 0.45)
u_height    = height    * (1 + log(over) * 0.30)
u_level     = level(count, style)
```

**Every new noise knob needs its own ratio here** — aperture, noise scale, scroll speed, and whatever
else the look ends up needing. Two hard constraints:

- ⚠ **KEEP `u_count`, AS AN INTENSITY.** It stops meaning "how many tendrils" but `FxAttachment
  ._emit_embers` reads it as the ember RATE (`sources = vals.get(&"u_count")`). Retire
  `FX_MAX_TENDRILS` as a tendril cap, not the uniform.
- ⚠ **EVERY SCALED VALUE MUST BE CONTINUOUS IN THE STACK COUNT** (owner ruling 16: a stack change eases,
  it never jumps). That is why `u_count` is a float today. A knob that steps at integer stacks will
  make the whole effect pop, and `FxAttachment._eased` can only tween what is continuous.

### 0e. The owner's references — what transfers, and what will break this project

| reference | take | ⚠ do NOT take |
|---|---|---|
| **Yui Kinomoto** — `noise = UV.y * (((UV.y + aperture) * fire_noise - aperture) * 75.0)` | **THE CORE IDEA, and the single most useful line the owner sent.** A vertical ramp times noise, thresholded to alpha, with `aperture` opening the flame out. **The adaptation IS the design: replace `UV.y` with `cover` from 0b** and a quad-shaped fire becomes a shape-fitting one. | `UV.y` itself — UV is the QUAD, so it would burn a rectangle, not the host |
| **the tri-colour layered version** — two noise layers at different speeds, `tri_color_mix` | **two noise layers at different speeds** is cheap and is what makes noise read as fire rather than as static | `tri_color_mix` and the hardcoded `source_color` uniforms — `u_ramp` already does layered colour, per stack level, and ON PALETTE. Hardcoded colours FAIL `tools/palette_conformance.py` and the PALETTE suite |
| **the Balatro-style fractal one** — 5 iterations of `sin`/`cos`/`length` per fragment | the LOOK is worth studying | ⚠ **THE COST MODEL IS THE OPPOSITE OF WHAT §9 SAYS WE NEED.** That is dozens of transcendentals per fragment, on a shader whose whole budget is per-fragment work times a 3.8x-overdraw fill, on an Intel UHD. It would undo every gain in §6a several times over. Look at it; do not port it |

⚠ **All three references use `TIME`.** It is forbidden here — it ignores the act compression ramp and
keeps running through a paused tree. `u_time` exists for exactly that.

#### The reference code worth keeping

**The one line the whole design turns on** (Fire Shader by Yui Kinomoto @arlez80, MIT):

```glsl
// original — UV.y is the QUAD, so this burns a rectangle
float fire_noise = texture( noise_tex, UV + TIME * fire_speed ).r;
float noise = UV.y * ( ( ( UV.y + fire_aperture ) * fire_noise - fire_aperture ) * 75.0 );
ALPHA = clamp( noise, 0.0, 1.0 ) * fire_alpha;
```

**The adaptation, and it is the entire port:**

```glsl
// ours — `cover` comes from the MASK (0b), so the same maths burns the HOST's shape
float n     = fx_fbm(p * u_noise_scale + vec2(0.0, u_time * u_noise_scroll) + u_seed);
float shape = cover * (((cover + u_aperture) * n - u_aperture) * u_fire_gain);
heat        = clamp(shape, 0.0, 1.0);
```

`cover` is 1 at the surface and falls to 0 at full reach, which is exactly the role `UV.y` plays after
flipping — so the aperture term, the gain and the feel of the original all carry over unchanged. That
substitution is the whole reason this reference is the right one to start from.

**The second idea worth keeping** — two noise layers at different speeds (from the tri-colour
reference). Cheap, and it is what stops noise reading as static:

```glsl
float n = 0.5 * (noise(uv + t * speed) + noise(uv + t * speed * 1.5));
```

**From the Balatro-style one, keep NOTHING as code** — see the table above. Its 5-iteration
trig loop per fragment is the exact cost profile §9 says this project cannot afford.

#### 0e.1 The noise source — there IS a sensible default, and one thing to measure

**Default: ONE seamless tiling FBM texture.** Value or Perlin FBM, ~3 octaves baked in, **R8**
(single channel — nothing here reads colour from noise), 128² or 256², `filter_nearest`,
`repeat_enable`. Godot's `NoiseTexture2D` + `FastNoiseLite` with `seamless = true` generates it at
import; no hand-authored asset needed.

**Do NOT build a noise-TYPE system.** A `noise_kind` enum means a per-fragment branch and a parameter
explosion, for a choice that gets made once. Instead **`@export var noise_tex : Texture2D` on
`FxFireStyle`**, so the owner can swap the resource in the FX editor and A/B it live (the editor's
resource watch already re-reads styles four times a second, §5) — the texture is tunable, the code
is not.

Why baked octaves are the right call here: `fx_fbm` pays for its 3 octaves **per fragment, every
frame**, while a baked texture pays once at import. And there is a hard ceiling on useful detail —
`p` is quantized to `u_pixel` before anything samples it, so **octaves finer than one FX pixel cannot
be seen and are pure waste.** Size the texture so its finest octave lands near `u_pixel`, and stop.

⚠ **MEASURE texture-vs-`fx_fbm` before committing, and do not assume the texture wins.** It trades 7
hash+lerp ALU taps for one memory fetch, and this is an Intel UHD with shared memory bandwidth — the
result is genuinely not obvious. `fx_cost.tscn` answers it in one run. ⚠ Also check the TILING PERIOD
by eye at the shipped `noise_scale`: a nearest-filtered scrolling texture repeats visibly if the
period lands near the flame height, which is a look bug no number will catch.

### 0f. Cascading consequences — every file that has to move

Enumerated from the source, not guessed (`grep -rlniE "tendril|ogee|onion|\bcomb\b"`):

| file | what happens |
|---|---|
| `Shaders/fire.gdshader` | the rewrite |
| `UI/Fx/fx_fire_style.gd` | **13 of 38 exports retire** (`height_var`, `base_width`, `ogee_point`, `ogee_flare`, `onion_power`, `onion_rise`, `merge`, `sway_amp/speed`, `wave_amp/freq/speed`, `desync`); noise knobs replace them |
| `UI/Fx/fx_fire.gd` | `stacks_live` (0d), and `FX_MAX_TENDRILS` retires as a cap |
| `Shaders/Styles/fire_card.tres`, `fire_prop.tres`, `fire_ball.tres` | migrate + **RETUNE — this is the owner's art pass and an agent cannot do it**. ⚠ Migration recipe and its traps are in §5b |
| `UI/Fx/fx_juggle.gd` | the ball-fire request's `u_emit_width` / `partner_pixel` were a COMB fix (§2). With no comb, **the entire §2 bug class is deleted by construction** — one flame per ball becomes "noise over the ball mask". Re-derive rather than port |
| `UI/Fx/fx_attachment.gd` | `_emit_embers` reads `u_count`, `_ember_origin` reads `u_height` — both must still resolve |
| `Tests/Visual/test_pixels.gd` | ⚠ **the ONION section dies whole** — both base-row checks and the narrow-CORE check are claims about a model that will not exist. §0c's list is what replaces them: form-fitting, every upward surface, no leaping the hole, tips up under rotation |
| `Tests/Visual/fx_snapshot.gd` | `00_tendril_count` and `00b_ogee_profile` become meaningless; `01_fire_ladder` should become the STACK-SCALING ladder that proves 0d |
| `Tests/UI/test_fx_attachment.gd` | references the comb |
| `Tests/Visual/fx_cost.gd` | re-measure every row; §6a and §9 are the baselines to beat |
| `UI/Fx/Tools/fx_editor.gd` | `fire_stacks` stays and is the knob that proves 0d; its doc comments name tendrils |
| `VFX.md`, `ARCHITECTURE_REVIEW.md` §4g, `FX_SHADER_PLAN.md`, `todo.md` | all describe the retired model |

### 0g. What must NOT break — the rulings this rewrite still owes

Every one of these was paid for once already; none of them is negotiable without the owner.

1. **Flames point world-up on a rotated host** (ruling 1) — §0c.
2. **Every upward-facing surface burns, and no flame leaps a hole** (§1) — free from `cover`, but the
   `PIXELS` suite must still assert it on the RING.
3. **A stack change eases, never jumps** (ruling 16) — §0d.
4. **Per-ball lit state** (rulings 3 / 21): each ball burns or does not, independently.
5. **The host's modulate reaches the fire** (ruling 10) — the `tint` capture at the top of `fragment()`,
   or a focus-highlighted card lights up while its fire does not.
6. **`fx_intensity` still scales everything to zero** — a photosensitivity control, not a taste one.
7. **On-palette colour** — `u_ramp` only; `palette_conformance.py` and the PALETTE suite enforce it.
8. **The pixel grid stays world-aligned and square at every angle** (fx_common §0b).
9. **`body_near()`'s early-out survives the rewrite** — it is 2.1x (§6a) and it is easy to lose in a
   rewrite. Its `tall` margin is derived from `height`/`height_var`; re-derive it from whatever the new
   reach is.

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

### 1b. ⚠ THE NEXT LEVER, AND THE TRAP THAT STOPPED IT — read this before trying it

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

1. **THE QUAD EXTENT — worth ~25 %, and the work is already written.** The quads are sized as
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

## 8. What is LEFT

| | Item |
|---|---|
| ⬜ **THE NEXT BUILD** | **§0 — the noise fire.** Spec, references, stack scaling, the 13-file consequence list and the 9 rulings it still owes. Two open questions before anyone starts: **tap count (4 or 6)** and **whether the cheap-mask work rides along** (it roughly doubles the win but is the half that changes the silhouette). |
| ⬜ **Blocking "done"** | **Owner playtest (T15)** — nobody has PLAYED any of this. The 17-step walk is FX_SHADER_PLAN §10. No agent can do it. ⚠ Worth doing on the CURRENT build anyway: it is the only way to learn whether the saturated window in §6b is reachable in play, which decides how much of §0's perf argument matters. |
| ✅ **Perf** | **2.1x on a burning screen, and off-screen hosts are now free on CPU as well as GPU** — §6a, both changes pixel-identical. The worst window the game can build is 16.8 ms, exactly one 60 fps frame; burning-only is 7.6 ms. |
| ⬜ Perf, what is left | ⚠ **First ask whether a window where all 78 cards burn AND juggle is reachable in play.** If it is: **the juggling layer is the dominant half (9.1 of 16.8 ms) and NOTHING this pass did touched it** — §6a explains why, and lists its three remaining levers (most of which §0 absorbs). Lever B measured at 1.16x and rejected. |
| ⬜ **A DIAGNOSED BUG — but §0 DELETES IT** | ⚠ Do not fix this separately; §0c retires the mechanism. Kept for the diagnosis only. **Fire licks DOWN the side of a card from each top corner** (owner report, 2026-07-29 screenshot). Not the fire model — the SILHOUETTE. A uniform-angle radius table cannot represent a sharp vertex: a 38x50 card's corner sits at 37.23 deg, the 32 rays sample at multiples of 11.25, so the corner falls BETWEEN two samples and the lerp cuts straight across it. **Measured: the corner is chamfered IN by 2.32 art units** (the mask reaches \|x\| 16.70 at the top row instead of 19.00), and that chamfer is a genuine upward-facing slope — so the march finds it and stands flames on it, correctly. There is also a +0.28 outward bulge along the edges below it. Reproduced against the BOX card, which has a clean corner. **This is PRE-EXISTING**: cards have taken the RADII branch since `measure_silhouette` was first wired up; the warp work only made it visible. ⚠ **More rays barely helps** — the chamfer converges slowly on a sharp vertex: 32 rays -2.32, 64 rays -1.41, 128 rays -0.56, at 128 floats per material per quad per host. The fix is a different REPRESENTATION, and the two candidates are in §10. |
| ⬜ Accepted — **and §0 likely deletes it too** | §3 (sliced tendrils on curves): a flame's top could sit below its own base where the ring falls away steeply, because each column's arch was anchored to its own surface. With no arch there is nothing to slice — but VERIFY it on the ring rather than assuming, because a `cover` that is per-column has the same shape of hazard. |
| ✅ The onion check | WAS failing against the 2026-07-31 card-fire tuning. **The CHECK was wrong, not the tuning** (owner: *"if it's caused by me adjusting parameters then it wasn't a good test in the first place"*). "Core-near-tip beats shoulder-near-base" is not a structural claim: heat is `(1 - across)^power * (1 - rise * k)`, so `onion_rise = 1.0` cools the tip to zero BY CONSTRUCTION — a legitimate art setting no correct onion can win against. Replaced with two claims read off the flame's BASE row, where `k ~ 0` and the rise term drops out of both models: it must cross several shells rather than sit in one flat band, and the heat must fall halfway before the rim rather than holding peak out to the corner (rows pinch every contour into the two base corners). **Mutation-tested**: with `heat = 1 - rise/(h*dome)` restored, the base row comes back a single flat band (0.286 across all 152 px) and the section goes red. Suite green, 28 suites, exit 0. |
| ⬜ Art calls only the owner can make | ⚠ **The `.tres` RETUNE in §0f is the big one and only the owner can do it.** Also: the fire ramp's ENDS (entry 0 makes a 1-stack flame near-black, entry 19 puts neutral grey at the white-hot end — one-line edits to `Assets/Palette/ramp_fire.tres`); prop art SIZES; flame `height` per style; `level_ref`. |
| ⬜ Known limitation | Ball highlight is a quantized ellipse at small radii — pixel-art resolution, not a defect. Levers: `ball_spec`, or a smaller `pixel` on the juggle style. |
| ⬜ Deferred by the owner | Map screen + in-game UI chrome still hardcoded (they warn `[WARN][PLACEHOLDER]` every run); `FireworkVisual` has no art; `suit_pips.png` has a few off-palette pixels. |

---

## 9. WHERE THE COST ACTUALLY IS — four attribution runs, and they settle two design questions

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
Godot --path solatro res://Tests/Visual/prop_art_snapshot.tscn
Godot --path solatro res://Tests/Visual/fx_cost.tscn       # ms/frame per host kind — not a test
py solatro/tools/palette_conformance.py
py solatro/tools/snapshot_diff.py save                     # stash the PNGs you trust as a baseline
py solatro/tools/snapshot_diff.py diff                     # re-run fx_snapshot, then prove nothing moved
```

**For a change that must not alter the picture, `snapshot_diff.py` is the instrument, not your eye.**
"Judge fire by EYE" is right for a change that is SUPPOSED to look different; an optimisation's only
honest claim is byte-identical, and an eye is far too generous for that. Both §6a changes were
landed on it.

Last full run (2026-07-29, Intel UHD box): **28 suites, exit 0**, all checks passed (the check COUNT
varies run to run — BOARD FUZZ is randomised; what must hold is 28 suites and exit 0).

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

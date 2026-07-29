# FX_HANDOFF.md — live handoff, updated 2026-07-31

**Read [VFX.md](VFX.md) and ARCHITECTURE_REVIEW **§4g** first** (the map and the contract).

The previous edition of this file was the owner's review of the MASK build: five items, §1–§5.
**Four of them are done and one was accepted as-is.** This edition records what was done, what it
measured, and the two things still open — the owner's playtest, and a re-measure on the slow machine.
**§6 is written to be handed to whoever has that machine: run steps, the numbers to collect, and the
fixes to apply in order if they fail.** Delete this file once §7 is empty.

⚠ **The owner will run the `simplify` skill over the unpushed commits.** Land behaviour first; do not
pre-emptively restructure for tidiness.

⚠ **All numbers below were measured on a GTX 1070.** The 28.5 ms that started §1 came from an Intel
UHD, and the two machines are ~12x apart. **Ratios transfer; absolutes do not.** If the game targets
laptops, the Intel number is still the number, and nobody has taken it since the fix.

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

## 6. ⬜ HANDOFF TO THE SLOW MACHINE — the one job an agent cannot do from here

Everything in §1 was measured on a **GTX 1070**. The number that decides whether this ships is the
one from the **Intel UHD laptop** (or whatever the real target is), and it has not been taken since
the fix. This section is written to be handed over whole: run §6a, read §6b, and if — and only if —
the numbers fail, work §6c **in order**, re-measuring after each step.

### 6a. What to run there, in this order

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

### 6b. What the numbers have to say

`fx_cost.tscn` prints one row per host kind, as a delta against an empty scene, for **20 hosts**.
Copy the whole table into this file when you have it. The rows that matter:

| Row | GTX 1070 today | What it means |
|---|---|---|
| `juggle both x20` | 1.20 ms | 20 juggling cards, 5 balls each, ALL lit — the worst case in the game |
| `juggle balls` / `ball fire` | 0.52 / 0.69 ms | which of the two quads is expensive, if it is |
| `card fire` / `prop fire` | 0.45–0.51 ms | untouched by this work; a regression here means something else broke |

- **The owner's target is ALL FX on screen ≤ ~2 ms, i.e. ~0.2 ms per juggling card.**
- **Read the GPU-timer column if it is non-zero.** `viewport_get_measured_render_time_gpu` is
  unimplemented on the Intel driver and prints a flat `0.000` there — if so, the wall-clock delta is
  all you have, and it includes ~0.4 ms of CPU (20 attachments pushing uniforms for 2 quads each)
  that no shader change can remove. Say which column you used when you report.
- **Also raise `HOSTS` in `Tests/Visual/fx_cost.gd` to 50 and re-run.** That is the DECK VIEWER, the
  densest screen in the game, and nobody has ever measured it.
- ⚠ 20 juggling cards with every ball lit may never happen in play. If 3–5 cards are comfortable,
  say so — that is a legitimate answer and it changes what is worth doing below.

### 6c. If it is still too slow — the fixes, in order, cheapest and safest first

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

## 7. What is LEFT

| | Item |
|---|---|
| ⬜ **Blocking "done"** | **Owner playtest (T15)** — nobody has PLAYED any of this. The 17-step walk is FX_SHADER_PLAN §10. No agent can do it. |
| ⬜ **Owner's hardware** | **§6 — re-run `fx_cost.tscn` on the slow machine.** Every number above is a GTX 1070; §6 is written to be handed over whole. |
| ⬜ Perf | §6c, in order: the quad extent (~25 %, with its trap in §1b), then `fx_fbm`, then the arc count. Also the still-unmeasured **50 burning cards in the DECK VIEWER** (`fx_cost.gd` takes a `HOSTS` constant — raise it and re-run). |
| ⬜ Accepted | §3 (sliced tendrils on curves). |
| ⬜ **One FAILING check, and it is an ART CALL** | `PIXELS: the flame is hottest along its CORE toward the tip` fails against the card-fire tuning saved on 2026-07-31 (tip 0.066 vs shoulder 0.107). Not a code regression — reverting the `.tres` files alone turns it green with every code change in place. `onion_rise = 1.0` is the biggest cause (heat goes to zero at the tip by construction), but at 0.35 the two sample points TIE, so `onion_power 0.7` + `base_width 2.0` + `ogee_point 0.2` have flattened the discriminator too. Either the tuning moves or that check does — the owner's call, and the check took three tries to make discriminating, so do not weaken it casually. |
| ⬜ Art calls only the owner can make | `fire_ball.tres`'s `merge` / `base_width` (§2); the fire ramp's ENDS (entry 0 makes a 1-stack flame near-black, entry 19 puts neutral grey at the white-hot end — one-line edits to `Assets/Palette/ramp_fire.tres`); prop art SIZES; flame `height` per style; `level_ref`. |
| ⬜ Known limitation | Ball highlight is a quantized ellipse at small radii — pixel-art resolution, not a defect. Levers: `ball_spec`, or a smaller `pixel` on the juggle style. |
| ⬜ Deferred by the owner | Map screen + in-game UI chrome still hardcoded (they warn `[WARN][PLACEHOLDER]` every run); `FireworkVisual` has no art; `suit_pips.png` has a few off-palette pixels. |

---

## 8. Runbook

`Godot` below is the console build — on this box
`C:\richard\Godot_v4.7.1-stable_win64_console.exe`, run from `C:\richard\gamedev`.

```bash
Godot --path solatro res://Tests/all_tests.tscn            # windowed, ~60-85 s, exit = failure count
Godot --path solatro res://Tests/Visual/fx_snapshot.tscn   # after ANY shader edit
Godot --path solatro res://Tests/Visual/prop_art_snapshot.tscn
Godot --path solatro res://Tests/Visual/fx_cost.tscn       # ms/frame per host kind — not a test
py solatro/tools/palette_conformance.py
```

Last full run (2026-07-31): **28 suites, exit 0** (the check COUNT varies run to run — BOARD FUZZ is
randomised; what must hold is 28 suites and exit 0).

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

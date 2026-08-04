# VFX.md — the visual-effects entry point

**Link this file when you want VFX work done, then say what you want changed.** Everything an agent
needs to pick up fire, juggling balls, prop art, particles or the FX shaders cold is either here or
linked from here, including the open backlog (§6) and the known bugs (§7).

Scope: the shader-FX layer (`Shaders/`, `UI/Fx/`), prop and pip ART (`Cards/Props/Visuals/`, the
suit pips), and the palette work that is still open. NOT board layout or card animation — those are
[LAYERING.md](LAYERING.md) and ARCHITECTURE_REVIEW §1.6.

---

## 1. Read this in this order

1. **[START_HERE.md](START_HERE.md)** — the project rules that override everything (no `git add`,
   warnings-are-errors, never run Godot while the owner's editor is open, docs pass at the end).
2. **This file**, §2–§5: where things are, how to run them, what you may not break.
3. **ARCHITECTURE_REVIEW.md §4g** — THE contract for the FX layer (every rule, every trap already
   paid for). **§4h** — pixel art: one pixel size, mirror-not-rotate, the hoop's split, what gets
   recoloured. These are the authoritative text; this file deliberately does not restate them.
4. Only then the section of §6/§7 your task touches.

Why the split: contracts live in ARCHITECTURE_REVIEW because that is where every other subsystem's
rules live and the project's doc-hygiene rule forbids keeping the same text in two places. This file
is the map, the runbook and the backlog.

Background reading, only if you need the *why*: **FX_SHADER_PLAN.md** §0b (the 25 owner rulings —
they are the spec) and §7 (the task board, T1–T21). The palette contract is
**ARCHITECTURE_REVIEW §4i**. FX_SHADER_PLAN is historical; if it disagrees with
ARCHITECTURE_REVIEW, the latter wins.

---

## 2. Where the code is

| Path | What |
|---|---|
| `Shaders/fx_common.gdshaderinc` | The pixel grid, noise, dither, and **the one definition of the ball path** (`fx_ball_at_ladder` / `fx_ball_pos_ladder` / `fx_ball_of` / the arc ladder), plus `fx_cell_round` — the whole-cell placement an INSTANCED effect needs to stay on its host's lattice. Included by both shaders so the maths cannot exist twice. ⚠ **`fx_nearest_ball` and `fx_balls_near` are GONE (2026-07-29): the juggling layer is ONE INSTANCE PER BALL and a fragment's ball arrives in `INSTANCE_CUSTOM`, so nothing searches for it. FX_HANDOFF §0d.6 is the live description.** |
| `Shaders/fire.gdshader` | Fire. ONE path for every host: a COVER FIELD sampled from the art's MASK, carved by two layers of scrolling noise (2026-07-29 — the tendril/comb/ogee/onion build is retired). `mask_level()` is the only extension point — one branch per shape, and a juggled ball is one of those shapes, not a mode. |
| `Shaders/juggle.gdshader` | The juggled balls — ONE INSTANCE PER BALL on a `MultiMeshInstance2D`, placed by `vertex()`. The fragment is a disc test and the sphere shading, nothing more. |
| `Shaders/Styles/*.tres` | Every art lever, per effect (`FxStyle`), plus `ember.tres` (a `ParticleSpec`). Colours point at `Assets/Palette/` ramps (§4i). **The single place FX tuning lives** (owner ruling 8). |
| `UI/Fx/fx_attachment.gd` | One host's effects: builds the quads (a `MeshInstance2D`, or a `MultiMeshInstance2D` for an instanced effect), owns the clock, the per-host randomness, the lag spring. ⚠ `_push_live` sends only the two genuinely per-frame uniforms; everything else goes on CHANGE (FX_HANDOFF §0d.7 — it was 4.2 ms per frame on a full board). |
| `UI/Fx/fx_fire.gd`, `fx_juggle.gd` | Stacks → uniforms. `FxJuggle.geometry()` is the ONE computation both ball quads read. |
| `UI/Fx/fx_style.gd`, `fx_request.gd` | The lever resource, and the request a status hands to an attachment. |
| `UI/Fx/particle_engine.gd`, `particle_spec.gd` | The game's ONLY particle path (embers are its first client). |
| `Cards/Props/prop_visual.gd` + `Cards/Props/Visuals/*.gd` | Prop art: sheets, sizes, mirroring, the split halves. |
| `Cards/Pips/pip_suit.gd`, `Assets/color_picker.gdshader` | Suit pips and the palette recolour shader. |
| `Tools/fx_editor.tscn` | **Live FX tuning in the editor** — open it, edit an `FxStyle`, watch the real shaders react. Start here for any art tuning (§4g). |
| `Scripts/visual_log.gd` + `Tools/spotlight_trace.tscn` | **The visual log — behaviour over TIME, which no snapshot can show.** Timestamped, frame-numbered events for everything the presentation layer does. Use it for any "did these happen together or in sequence", "did the board move under this", or "why did that draw nothing" question. Logs land in `user://logs/`; read `EventLog.summary()` first. See `HEADLESS_TESTING.md` §0c. |
| `Tests/Visual/` | `test_pixels.gd` (asserting), `fx_snapshot.gd` + `prop_art_snapshot.gd` + `fx_behind.gd` (reviewable — the last one draws hosts FILLED, for the seam), `fx_cost.gd` (the GPU bench, asserts nothing), `pixel_probe.gd` (the shared oracle + image readers), `snapshot_scene.gd` (the harness base). |

---

## 3. How to run and verify — all three matter

**⚠ Never run any of these while the owner's editor has the project open** (`Get-Process *odot*`,
check `MainWindowTitle`). Wait, or hand the commands over.

**The suite — WINDOWED, after every change.** Not `--headless`: the PIXELS suite needs a real
renderer and FAILS rather than skips without one (a skipped pixel check reads exactly like a passing
one, which is how four render bugs once shipped past a green run).

```bash
timeout 400 "/c/Users/khanr/Desktop/Godot_v4.7.1-stable_win64_console.exe" --path solatro res://Tests/all_tests.tscn > /tmp/run.log 2>&1; echo "exit: $?"; grep -c "Parse Error" /tmp/run.log; grep "SUITES" /tmp/run.log | tail -1
```

Exit code = failure count. Read only `%APPDATA%\Godot\app_userdata\Solatro\test_output_errors.log`
(empty = green) plus the final banner. **A dropped suite count is a silent failure**: a parse error
in a suite script means it never loads, the banner still says "ALL n SUITES PASSED", and n is simply
one smaller. Check the number.

⚠ **`push_error` LINES IN THE CONSOLE ARE NOT THE VERDICT**, and two suites print some on purpose:
LEAK CANARY's sentinel report, and PALETTE's `Palette index -5 out of range 0..31 — clamped` (that
call IS the clamp contract — `Palette.color` reports rather than returning a silent wrong colour).
Both label themselves in their check text. The errors LOG is the suite's own channel, so neither
reaches it; a green run still leaves it empty.

**FX snapshots — after every shader edit.** Writes PNGs to
`%APPDATA%\Godot\app_userdata\Solatro\fx_snapshots\`; the shot list is in ARCHITECTURE_REVIEW §4g.

```bash
timeout 250 "/c/Users/khanr/Desktop/Godot_v4.7.1-stable_win64_console.exe" --path solatro res://Tests/Visual/fx_snapshot.tscn > /tmp/snap.log 2>&1; echo "exit: $?"; grep "PROBE" /tmp/snap.log | grep -vE "offset by art \(-?[01]\.[0-9], -?[01]\.[0-9]\)"
```

That second grep is the ball check: the harness measures its own capture and prints, per ball, how
far the nearest rendered ball is from where the independent oracle says it should be, **in art
units**. Empty output = every ball agrees to under 2 units. **Read the numbers — do not measure the
PNGs by hand.** Two separate debugging passes did and both reached wrong conclusions.

**The GPU cost bench — after anything that changes how much work a fragment does.** It prints
milliseconds per frame for 20 burning hosts of each kind, against an empty scene. Not a test; it
asserts nothing. This is what answered "does the per-cell anchor fit" with a number (§4g) and what
turned up the ball-fire figure in §7.

```bash
timeout 600 "/c/Users/khanr/Desktop/Godot_v4.7.1-stable_win64_console.exe" --path solatro res://Tests/Visual/fx_cost.tscn 2>&1 | grep -E "ms/frame|->"
```

**Prop-art snapshots — after any change to prop art, `art_size`, or the facing rule.**

```bash
timeout 250 "/c/Users/khanr/Desktop/Godot_v4.7.1-stable_win64_console.exe" --path solatro res://Tests/Visual/prop_art_snapshot.tscn > /tmp/snap.log 2>&1; echo "exit: $?"
```

**The SEAM harness — after any change to the mask, `sink` or `inner_alpha`.** `fx_behind.tscn` is the
only one that draws its hosts FILLED, which is the thing an outline harness cannot show: whether the
boundary between flame and art reads as occlusion or as a staircase of its own.

```bash
timeout 250 "/c/Users/khanr/Desktop/Godot_v4.7.1-stable_win64_console.exe" --path solatro res://Tests/Visual/fx_behind.tscn > /tmp/snap.log 2>&1; echo "exit: $?"
```

**And for a change that must alter NOTHING, diff the panels rather than looking at them.** `save` on
the build you trust, make the change, re-run the three snapshot scenes, `diff` — 31 panels across the
three sets.

```bash
py solatro/Tools/snapshot_diff.py save     # then make the change and re-run the scenes
py solatro/Tools/snapshot_diff.py diff     # -> "0 of 27 comparable panels differ (4 known-noisy skipped)"
```

⚠ **It has been blind twice** — alpha-only until 2026-07-29, and scanning `fx_snapshots` alone until
2026-07-30 — so any "panels identical" claim older than that measured less than it claimed
(FX_HANDOFF §12). ⚠ **Four panels differ on unchanged code** and print as `noisy` instead of counting:
the three ROTATED ones (cause unknown — todo.md) and `09_embers` (randomised by design).

**After adding a `class_name` or a new PNG:** `--headless --path solatro --import` first, or you
will chase a phantom parse error (and a brand-new image has no `.import` yet).

---

## 4. The five things that will bite you

Full text and the rest of the list: ARCHITECTURE_REVIEW §4g/§4h. These are the ones that have
actually cost time.

1. **`--headless` never compiles a shader, and Godot logs nothing for a semantically wrong one.** A
   clean log and a green headless run say nothing about pixels. Only the PIXELS suite and the
   snapshots do.
2. **A shader that writes `COLOR` must multiply the host's modulate back in.** The renderer folds it
   into `COLOR` before `fragment()`, so overwriting discards it — that is how the focus highlight
   silently stopped reaching the effects.
3. **`FxAttachment._push_live()` ends with `set_process(...)`.** Park a clock by disabling the
   process LAST, or the frames before your capture advance it and you will "discover" a shader bug
   that is not there.
4. **Per-host randomness is read when the QUADS ARE BUILT** (`_seed`, `_ball_dir`), unlike the clock
   which is pushed after. A test pinning them must do it before `sync()`.
5. **GLSL is not GDScript.** `##` is a preprocessor error, `return` is illegal in `fragment()`, and
   dynamically indexed local arrays return garbage on GLES3 without any error. On the GDScript side,
   `floor()`/`ceil()` return Variant — use `floorf()`/`ceilf()`.

---

## 5. Adding an effect, a prop kind, or a lever

- **A new effect** = one `.gdshader` + one **`FxStyle` SUBCLASS** carrying that effect's levers + a
  `.tres` of it + a status that returns an `FxRequest` from `fx_request()`. `FxAttachment` never
  learns effect names — it only ever touches the base (`apply()`, `opacity`, `brightness`, `ember`).
  - ⚠ **Do not add your knobs to `FxStyle` itself.** The base is the shared half only. A knob on the
    base is a knob every other effect's inspector shows and every other effect's material is handed —
    which is exactly the confusion, and the per-material waste, the subclasses exist to end
    (2026-07-31; `FxStyle`'s own doc comment has the measurements).
- **A new lever on an existing effect** = an `@export` on `FxFireStyle` / `FxJuggleStyle`, one
  `set_shader_parameter` in that class's `apply()`, one uniform. Never a literal in the shader.
- **A new prop shape** = usually NOTHING. A textured kind overrides `measure_fx_silhouette()` to
  hand `FxAttachment` its sheet, and the fire shader reads that art's own alpha as its mask. Only a
  kind with no texture at all (a deformed card) needs a `mask()` branch and an `fx_shape()` override.
- **A new prop kind's art** = a sheet, `art_size = art_size_for(SHEET, …)` in `_init` (never a raw
  pixel number), and a `_draw_frame` call. §4h explains why.
  `Shaders/Styles/*.tres` is the single tuning home.
- **A new motion term** must fold in the host's seed, or every card on the board runs it in lockstep.

---

## 6. Open work

🟢 **THE FIRE EFFECT IS CLOSED (owner, 2026-07-29: *"with this we are done with fire effect changes"*)
AND FX PERFORMANCE IS PAUSED, NOT FINISHED (owner, 2026-07-30: *"sure lets stop here then"*). THERE IS NO
OPEN ENGINEERING TASK.** The 2026-07-29/30 pass took the worst window the game can build from **12.07 to
5.82 ms of GPU** — one instance per ball, the CPU uniform push, and two card fire levers.

⬜ **TO SPEND MORE BUDGET, GO STRAIGHT TO FX_HANDOFF §0d.10.** It is one page: today's measured numbers,
every remaining lever with an honest price and risk, **the list of things that look like levers and are
measured NOT to be** (do not re-tread those — this pass did), and the four traps in the bench itself.

Everything below is either an owner call, art tuning, or a closed record kept for its measurement.

Ordered roughly by what a session should pick up first.

### 6.1 Owner decisions outstanding (cheap, unblock the rest)

- **⬜ Owner verification in-game (T15) — the one thing blocking "done".** Agent-side checks are all
  green, but nobody has PLAYED it. The 17-step walk is **FX_SHADER_PLAN.md §10** (one copy,
  deliberately not restated). Steps 13–17 cover the newest work, including the two calls that are the
  owner's: the hoop's on-screen size, and whether banded ball shading beats the old two-tone.
- **Juggling speed and hang-time** are the first two numbers to try: `FxStyle.ball_period_secs`
  (1.2 s per loop at one ball, REAL seconds — it no longer follows `base_delay`) and
  `ball_gravity` (1.6; 1.0 = constant speed, 2.4 hangs visibly). `05d_ball_gravity.png` shows three
  values side by side.
- **The arc ladder's two knobs:** `ball_arcs_per_count` (1.2 — how fast lanes appear) and
  `ball_arcs_max` (8). `05e_ball_arcs.png` shows 2/4/6/8 at one ball count.
- **Effect heights** are budgeted at half a card separation so the card behind stays visible: card
  fire `height` 7, juggling `ball_arc_max` 32 (to the topmost ball's edge). If that reads timid,
  those two numbers are the levers — raising them is exactly what starts covering the card behind.
- **Prop art SIZES.** The hoop draws 80×180 screen px at default `card_scale` (a card is 95×125),
  which is what the 32×72 art implies at one pixel size for all art. The lever is that kind's
  `art_size` in `_init` — keep it a multiple of `PropVisual.ART_PIXEL_SCALE` or its pixels stop
  matching the cards'.
- **The rest of the numbers to settle by eye**, all single tunables: `FxFireStyle.cover_taps` (4 —
  ⚠ and it is the shader's whole cost curve: **+0.65 ms per tap on the owner's Intel UHD**, +0.081 on a
  GTX 1070. Dropping the card style to 2 is worth **1.24 ms**, the biggest single number on the table and
  a LOOK call — FX_HANDOFF §0d.3 prices it, §0e argues against it),
  `aperture` / `fire_gain` (the flame's shape), the six **stack ratios** (how fast each knob ramps
  with the count — FX_HANDOFF §0d), `FxStyle.level_ref` (120 card / 60 prop / 40 ball),
  `settings.fx_transition_fraction` (0.6), `ParticleEngine.MAX_PARTICLES` (1024),
  `FxStyle.ember_rate_max` (24/s), ball spin base and its per-count coefficient,
  `ball_bands` / `ball_light` / `ball_light_z` / `ball_spec` (the sphere's tones, light, highlight).

### 6.2 The one open feature

- **✅ T21 — the universal palette. LANDED 2026-07-28.** Every FX colour now comes from a
  `PaletteRamp` of exact palette entries; the contract is **ARCHITECTURE_REVIEW §4i**. What is still
  hardcoded, deliberately: the map screen and the in-game UI chrome, deferred until the owner's custom
  art for them exists — the PALETTE suite reports each one as a `[WARN][PLACEHOLDER]` every run.

### 6.2b Open after the 2026-07-28/29 tuning review

**✅ THE FIRE EMITTER WAS REPLACED — "RAISE THE MASK" LANDED 2026-07-30.** The contour model was
wrong at the root: it knew one top contour per column, so a shape with two upward-facing surfaces in
one column — the hoop's inner-bottom arc — could only ever light the upper one. Fire is now the art's
MASK raised by the ogee and minus the mask, which lights every upward-facing surface anywhere in the
art, makes the tendril count per SURFACE, and moves shape-following into the shader so nothing is
baked at `_ready`. **The contract is ARCHITECTURE_REVIEW §4g**; the rejected techniques and why are
in git history (FX_HANDOFF.md §1.5, deleted with the file).

Deleted with it: the skirt (`u_skirt` / `skirt_var` / `skirt_freq`), `u_wrap`, `u_mode` /
`MODE_BALLS` and the whole ball branch, `Shape.PROFILE` / `u_profile`, `Shape.RING`, `contour_y` /
`box_contour` / `emit_half_width`. The hoop is a SPRITE now — an analytic ellipse cannot represent a
hole.

⚠ **Two things the owner asked for that are NOT in it, both deliberate and both stated:**

1. **ENGULF is gone.** It was to come from a per-cell ANCHOR (the arch anchored once at the cell's
   highest surface, every column draping down to its own floor). Measured at **21 ms extra for 20
   burning hoops** on integrated graphics — more than a whole 60 fps frame. The owner pre-ruled the
   fallback for exactly this outcome, so the plain mask shift ships and the anchor is dropped whole.
   Numbers and the ruling: §4g.
2. Consequently the arch **rides** the surface it stands on, so flames on a steep flank are shorter
   than flames on the apex. Tips still point straight up everywhere.

**✅ AND THEN THE EMITTER ITSELF WAS REPLACED — THE NOISE FIRE LANDED 2026-07-29.** Owner: *"Fire
effect no longer has tendrils at all, just average fire shader effects like moving noise instead...
make sure all params have scaling ratios as stacks increase"*. The mask stayed; what sits on it is
now a COVER FIELD (how far above the nearest surface below me am I, in `cover_taps` fixed lookups)
carved by two layers of scrolling noise, with every knob ramping continuously from one stack.
**Measured 1.93x on a burning screen and 1.40x on the worst window the game can build** (GTX 1070);
the whole record, including what only the owner can decide, is **FX_HANDOFF §0**. Deleted with it:
the comb, `tendril()`, the ogee arch, the onion shells, `merge`, `desync`, the sway/wave motion,
`height_var`, `base_width` and `FX_MAX_TENDRILS`.

**What to look at, by EYE:** `fx_snapshot`'s `00_cover_field` (the tap ladder naked), `00b_aperture`,
`01_fire_ladder` (the STACK RATIOS — nothing may jump), `03_surfaces` (1/4/40/200 stacks over the
ring — both arcs alight, the hole's middle always empty at every count), `04_shapes`,
`02_fire_rotation`, and `prop_art_snapshot`'s `17_prop_fire` at real size. **Never count columns** —
that instrument reported two rejected builds as successes.

- **✅ FIXED — hoop fire left the ring's flanks bare.** Superseded twice: first by a SKIRT (2026-07-30,
  now deleted), then properly by the mask model above. The skirt covered the outer arc by ANGLE and
  could never reach an upward surface elsewhere in the art; the mask reaches all of them.
- **✅ FIXED — embers only came off the card (2026-07-30).** Props and balls now carry
  `ember_prop.tres` (the card's spec is in screen units and ~2.5x too big beside a knife), and ball
  embers spawn on the LIT BALLS via `FxJuggle.ball_pos` — the one script-side copy of the path, pinned
  to the independent oracle by `test_ball_pos_matches_the_oracle`. New shot: `fx_snapshot` `09_embers`,
  the only one that runs live. See ARCHITECTURE_REVIEW §4g.


- **✅ FIXED — balls all travelled the same way below ~10.** The per-ball direction mirror cancelled
  the arc ladder's own alternation whenever the ball count was near the arc count; at 2, 4 and 6 every
  ball ran one way and half the pattern sat empty. The mirror is gone; crossing comes from the ladder
  (ARCHITECTURE_REVIEW §4g, guarded by name in `test_pixels.gd`).
- **✅ FIXED — everything white in the editor, and `fire_card.tres` silently losing properties.** Every
  FX script is `@tool` now; a non-tool script is a PLACEHOLDER in the editor, which both breaks
  `FxStyle.apply()` and makes the editor drop unknown properties when it re-saves a `.tres`. This one
  destroys data — see the loud block in §4g before removing `@tool` from anything.


- **✅ `fx_editor.tscn` IS verified inside the editor, and it hosts the REAL SCENES (2026-07-29).** Both
  card slots instantiate `card_visual.tscn` with real `CardData` — the TypePaper face skinned to the star
  rig, which is **not a rectangle** (the frame clips one texel off each corner) — and `rig_pose` seeks the
  card's own animation instead of warping a hand-built star (owner: *"no useless mocks when you can just
  use actual original scene, just like how hoop knife use actual art"*). ⚠ It needed **`@tool` down the
  whole card DATA chain**: without it a previewed card's suit is a placeholder and the face silently stops
  drawing mid-`update_visual`. FX_HANDOFF §0c.4, pinned by `test_card_preview_chain_is_tool`.
  ⚠ **How to test an editor-only claim without opening the GUI** (owner's editor must be CLOSED):
  `Godot --path solatro --editor --quit-after 400 res://Tools/fx_editor.tscn` prints every script
  error and quits. ⚠ Running that scene as a GAME is fair for the cards and the fire but **not for the
  balls** — they do not render in a runtime run, and that is an artefact of the harness, not a bug.
- **⬜ THE THREE FIRE `.tres` WERE MIGRATED, NOT TUNED (2026-07-29).** The retired knobs were dropped
  and the new ones given plausible starting values; only `noise_scale` was actually re-derived, and
  only because the retired build's value was ~6x too fine for a model where the noise IS the shape
  (it read as one-pixel static). **This is the biggest thing waiting on the owner** — FX_HANDOFF §0f.
- **✅ FIXED, TWICE — fire no longer licks down a card's top corners, and no longer misses a warped
  one.** The chamfer was always in the MASK, not the fire: no scheme that interpolates between two
  angular rays can represent a vertex, and a chamfer is a real upward-facing slope. ⚠ **The ray table was
  exact AT every ray all along (worst error 0.000 art units), so the whole fault was interpolating a
  function with a CORNER in it.** A radial-SCALE table fixed the REST case; the DEFORMED case needed the
  mask to carry the silhouette's **own vertices** (`u_poly` + `u_wedge` + two box tests), which is exact at
  every pose and, measured on a REAL card, took **26.9 art units of unlit column down to 1.0** — one FX
  pixel, i.e. quantization. FX_HANDOFF §0c.1.
- **✅ FIXED — the fire stood one pixel of flame on nothing at each card corner (2026-07-29).** Every card
  type's frame clips its corners and the mask was the RIG, which is the full rectangle. ⚠ **A card and a
  prop do not share the mask BRANCH** — a prop SAMPLES its sheet's alpha (`Shape.SPRITE`, which is why
  hoops and blades were never a problem), a card carries an OUTLINE because its face is skinned to a rig
  that animates. So the bite had to be measured off the type frame and rebuilt geometrically:
  FX_HANDOFF §0c.5, which also has why a card cannot simply use the prop's branch.
- **✅ FIRE RENDERS BEHIND THE ART, and the owner has accepted it by eye** (*"fire looks good on
  rotations, no longer jagged"*). `inner_alpha = 0` cuts the flame at the host's mask, and the cut is
  tested at the **UNQUANTIZED** position — which is what stopped the seam being a 2.5-screen-pixel
  staircase against a `Polygon2D`'s screen-pixel edge. Cards AND sprite props. FX_HANDOFF §0c.
- **✅ JUGGLING PERFORMANCE IS DONE, AND SO IS THE FIRST HALF OF CARD FIRE.** It was *"~5.3 ms of a 10.8 ms
  worst window"* against a ~2 ms target; the whole window is **5.82 ms of GPU** now and juggling is ~1.2 of
  it. What did it: **one instance per ball** (FX_HANDOFF §0d.6 — the closed-form nearest-ball search is
  deleted), **the CPU uniform push** (§0d.7 — 4.21 → ~1.3 ms/frame, and nothing had ever measured it), and
  **two card fire levers** (§0d.9 — the first is two lines). ⚠ **Not one of the nine levers the old priced
  menu offered was what worked**; the cost model had two wrong factors and the menu only ever moved one.
  ⬜ **Still open, and both are the owner's LOOK calls, not engineering: `cover_taps` 4 → 2 on `fire_card`
  (0.98 ms) and `fire_card.height` (§0f.5).**
- **⚠ `fire_prop.tres` KEEPS GETTING CLOBBERED** by the editor whenever an agent edits
  `fx_fire_style.gd` with the FX editor open — three times in one pass. `git diff Shaders/Styles/`
  before believing anything, and see FX_HANDOFF §0g for how to tell clobbering from real tuning.
- **✅ FIXED, and worth knowing about because they hid in the same place (FX_HANDOFF §0g)**: the FX
  styles' `pixel` was never the game's one pixel size (fire was 2.5x finer than a card's art and
  5.5x finer than a prop's); the dither was indexed per SCREEN pixel, printing a checkerboard inside
  every FX block; the fire quad budgeted `height` while the cover ladder reaches `height + sink`, so
  flames clipped; the flame's base could never be opaque, at any setting; and `FxAttachment
  ._on_screen()` froze every effect in the FX EDITOR, because both spaces it reads belong to the
  running game.
- **⬜ The ball highlight is a quantized ellipse** at small radii: ~5x7 FX pixels at r=14, so its
  flanks show dead-straight runs. That is pixel-art resolution, not a defect — the levers if it
  should read rounder are `ball_spec` (a tighter dot) or a smaller `pixel` on the juggle style.

### 6.3 Measurements nobody has taken

- **✅ MEASURED 2026-07-30 — `Tests/Visual/fx_cost.tscn`, 20 burning hosts each, Intel UHD.** Card
  fire 1.53 ms, hoop 1.21 ms, knife 0.36 ms — all comfortable against a 16.7 ms frame. **Ball fire is
  28.5 ms and always was** (26.6 ms before the mask model): the biggest number in the layer.
- **✅ THE THREE LEVERS WERE TAKEN, 2026-07-31 — the juggling layer is ~2.4x cheaper on the GPU.**
  Re-measured on a **GTX 1070**, NOT the Intel UHD above, so read the ratios rather than the
  absolutes. The bench now prices the two juggling quads separately, and this machine's driver does
  implement `viewport_get_measured_render_time_gpu`, so the GPU column means something here.

  | 20 hosts, GTX 1070 | before | after | GPU timer, before → after |
  |---|---|---|---|
  | juggle balls | 1.28 ms | 0.52 ms | 1.458 → 0.446 |
  | ball fire | 1.68 ms | 0.69 ms | 1.863 → 0.670 |
  | juggle both | 2.37 ms | 1.20 ms | 2.539 → 1.062 |

  What did it: (1) **hoisting the ladder** — `fx_arc_ladder` resolves every arc's start and share
  ONCE per fragment, where `fx_nearest_ball` re-derived them ~384 times, each carrying a `sqrt`;
  (2) **`fx_balls_near`**, one box test that rejects the empty majority of a ball quad before the
  lookup is paid for; (3) **the box quad bound** — `FxRequest.rotates_with_host = false` on both
  juggling quads, since the pattern provably does not turn with its host (`05f_ball_rotation` is the
  proof), which is ~22 % of their fill. ⚠ **The Intel UHD figure has NOT been re-measured, and it is
  the number that matters if the game targets laptops.**
  - ⚠ **THE OLD LEVER ORDER WAS WRONG AND IS WITHDRAWN.** It began "raise `FxStyle.pixel`, chunkier
    FX pixels is a LOOK change not a capability loss" — but `fx_local()` quantizes a COORDINATE
    inside the fragment shader, so the quad's screen footprint is unchanged and **the shader still
    runs once per screen pixel**. Chunkier pixels help warp coherence and texture-cache hits a
    little; they do not cut the fragment count at all. **Do not start by cutting features.**
  - **What is left, in order:** the quads are still sized as body-plus-reach on EVERY side, so a
    33-unit-wide pattern gets a 112x125 quad — shrinking that to the effect's own box is worth
    another ~25 %, and the attempt, with the trap that stopped it, is written up on
    `FxRequest.reach` and in FX_HANDOFF §1. Then `fx_fbm` at one octave. Only then features.
- **⬜ Still unmeasured: 50 burning cards in the DECK VIEWER**, the densest screen in the game. The
  bench takes a `HOSTS` constant; raise it and re-run.

### 6.4 Deferred by design

- **Motion lag is tier 1** (one spring). The 8-sample position history that gives a real S-curve is
  only worth building if a single arc reads flat — show the owner tier 1 first.
- **`Shaders/Styles/` is now a wrong name** (it holds a `ParticleSpec` too). Everything is in ONE
  place, which is what the ruling asked for; renaming the tree to `res://Fx/` is a separate
  mechanical change.
- **`FxAttachment.measure_silhouette` samples a card's outline ONCE.** Live per-frame bone
  deformation from the star rig is not tracked — re-call it if anything ever re-bakes a card shape
  at runtime.

### 6.5 Cleanups left on the table by the 2026-07-30 `/simplify` pass

Reviewed and deliberately NOT applied. Each was judged, not missed — the reason is the useful part.

- **⚠ DO NOT ADD `if _fx.is_empty(): return` TO `FxAttachment.track_outline`.** It looks like the single
  biggest per-frame win in the layer (an unlit card walks its whole rig, ~24 `atan2` plus the wedge index,
  and pushes the result nowhere — across a 78-card board and a 50-card deck viewer). **It was applied and
  it broke `PIXELS / the mask and the drawn face agree in EVERY FX cell` at 3 of 4 phases.** `_poly` is a
  PUBLISHED property, not a cache for the quads: that check reads it off an UNLIT card, and it has to be
  unlit because it samples the card's own face pixels — flames drawn over them would decide the
  comparison. A guard at the call site has the same problem. To actually collect this, make the resolve
  cheaper or have the HOST stop calling it; the reasoning is repeated at the guard site in the code.
- **The outline RESAMPLE path in `_fill_poly_from_outline` is reachable, despite looking dead.** Every
  shipped caller hands over exactly `POLY = 24` points, so it never runs today — but `CardVisual`'s rig
  generator has an `edge_subdivisions` `@export`, and raising it to 4 bakes 28 points and drops straight
  into it. Deleting it would turn a tool knob into the chamfer bug the vertex mask was built to remove.
- **`FxAttachment.measure_silhouette` is all but dead** (one caller, `card_visual.gd`'s `_rig_arms
  .is_empty()` branch, which the shipped `card_visual.tscn` never takes). Left in place because it is the
  fallback for a card scene with no skeleton, and deleting it silently changes that case to a plain box.
- **`PaletteRoles.ROLE_NAMES` is a hand-maintained mirror of the `@export` list.** Derivable by walking
  `get_property_list()` for `TYPE_INT` script variables — which is exactly what the test that polices it
  already does. Not applied: `_get_property_list`/`_get`/`_validate_property` all read `ROLE_NAMES`, so
  deriving it inside the same reflection surface risks recursion for a two-line saving.
- **The 18 `fx_editor` export setters are `set(v): x = v; _touch()` boilerplate**, and the tool already
  polls for changes it cannot get setters for. Not applied on purpose: polling costs a quarter-second of
  latency, and the owner keeps this editor open while tuning — trading instant feedback for tidiness in
  the one tool that exists for feel is the wrong trade.
- **`tools/palette_conformance.py` hand-rolls a PNG decoder (Paeth reconstruction included)** and claims
  *"stdlib only — no PIL, no numpy, same rule the rest of tools/ follows"*. **That claim is now false:**
  `snapshot_diff.py` imports PIL and `make_fx_noise.py` imports both, in this same changeset. ~75 lines
  would collapse into `Image.open(...).convert("RGB")` + `getcolors()`. Not applied because it adds a
  dependency to a script that works — but fix the docstring or fix the code, not neither. Its
  `PALETTE_PNG` also hardcodes the palette path, bypassing the one-place rule `PaletteDB` holds.
- **Test-harness duplication that `snapshot_scene.gd` was created to stop.** Its own header says the two
  harnesses "had drifted into two copies of this… not the kind of thing that should live in two files" —
  and `fx_behind.gd` still re-implements `fx_snapshot.gd`'s panel harness: `_zoom_for` is body-identical,
  `_Panel` duplicates `Case` field for field, `_Face` duplicates `_Ghost`'s sprite branch, and the
  attachment build repeats `_attach_for` **including its documented "disable the process LAST" ordering
  trap**. ~90 lines. If that trap is ever fixed in one copy only, the two harnesses shoot different
  frames of the same noise and neither is comparable to the other.
  **⚠ THAT PREDICTION CAME TRUE ON 2026-07-30, AND IT HAD ALREADY HAPPENED WHEN THIS WAS WRITTEN**
  (FX_HANDOFF §12b). The two copies had diverged on the OTHER per-host random: `fx_behind` set
  `att._seed` BELOW its `sync` — a no-op, since `u_seed` is written to the material inside
  `_make_quad` — while `fx_snapshot` pinned `_ball_dir` with a comment stating that exact rule and
  never pinned `_seed` at all. Two copies, two different wrong answers, neither visible until
  `snapshot_diff` was pointed at both sets for the first time. This bullet is no longer speculative
  and should be promoted above the tidiness items.
- **Nine ball-path uniforms are declared in BOTH `fire.gdshader` and `juggle.gdshader` with
  independently written defaults** (`u_span = 30.0`, `u_arc_height = 37.5`, `u_ball_radius = 3.0`, …),
  while `fx_common.gdshaderinc` — the file that exists so "the maths cannot exist twice" — holds only
  functions. A default that drifts is invisible on any host that pushes the uniform and wrong on any that
  does not. Same shape: `COVER_TAPS_MAX = 8` against `FxFireStyle.cover_taps`' `@export_range(2, 8)`,
  unpinned, where exceeding it makes the tap loop silently stop.
- **A split prop's dividing line is declared twice** — `HoopVisual._draw_half` cuts the source frame at
  0.5 of its width, and `fire.gdshader` carves the same cut with `if (u_half == 1 && p.x > 0.0)`, which
  also hardcodes "back = left, front = right" for every future split kind. Handing each half attachment
  its own half rect would make the SPRITE branch return `MASK_EMPTY` outside it for free and delete
  `u_half` and both branch lines.
- **`FxAttachment.transition_secs` re-derives `PropLayer.current_tick_seconds`'s formula.** Blocked, not
  skipped: `PropLayer` is not `@tool` and reads `SettingsManager.settings` directly, so it must route
  through the shared editor-safe accessor first. When `PropLayer` grew `MIN_FLOURISH_SECS` nothing
  propagated to FX transitions.

---

## 7. Known bugs and limitations

Nothing here is secretly broken — each is understood, and each is either accepted or scoped.

1. **✅ FIXED 2026-07-28 — FX colours were OFF-PALETTE.** `fire_ramp.png` held 64 colours, none of
   them a CircusCrayon entry, and the ball tones were hand-picked (40–80 from the nearest entry). Both
   generated their in-between colours (the ramp baker's COLD→HOT interpolation, `juggle.gdshader`'s
   `mix(shade, lit, …)`), which is why on-palette endpoints were never going to be enough. Fire and
   balls now SAMPLE ordered `PaletteRamp`s and the baked PNG is gone (ARCHITECTURE_REVIEW §4i).
   The fire and ball tones CHANGED as a result — that was the approved look change, not a regression.
2. **⚠ Adding an arc lane is a visible POP.** The arc count is an integer; when a stack crosses a
   lane boundary the path re-shapes. This is the one place owner ruling 16 ("no visual jumps") does
   not hold — the alternative is interpolating between two different path topologies. Accepted, not
   fixed.
3. **⚠ `02_fire_rotation` is not reproducible.** Two runs of identical code differ by ~11k pixels,
   all inside the ROTATED panels (the 0° panel is stable). Every other shot is byte-identical. So
   that shot is for EYE review only and a pixel diff of it means nothing. If it ever needs to be
   diffable, start at `fx_bayer(FRAGCOORD.xy)` — it is screen-space, so a sub-pixel placement
   difference moves every band edge.
4. **⬜ `FireworkVisual` has no art** — still the placeholder polygon (`color`), because none was
   authored. Every other prop kind draws a real sheet.
5. **A prop that TELEPORTS and immediately exits can fight its own fade.** `_flash()` tweens the
   whole `modulate` while `_drive_exiting` writes `modulate.a` per frame; whichever runs later that
   frame wins. Rare (relocate-then-despawn inside one flash), cosmetic, and the prop still frees
   correctly.
6. **The height budget is in the HOST's art units.** A card's are unscaled card units; a prop's are
   screen pixels at the default `card_scale` (≈2.5× smaller). "Half a card separation" is therefore a
   different NUMBER in `fire_prop.tres` than in `fire_card.tres`. Ball-fire plumes are deliberately
   outside the budget entirely (owner).
7. **A GDScript↔GLSL enum mirror can drift silently** (`FxAttachment.Shape` against the constants in
   `fire.gdshader`). The FX ATTACHMENT suite reads the constants out of the shader source and asserts
   the mapping — keep that test alive if you add a shape. It also asserts that `u_mode` never comes
   BACK: one code path for every host is the point of the mask model.
8. **✅ CLOSED 2026-07-29/30 — the juggling layer is now ~1.7 ms of the worst window and the search is
   DELETED.** ⚠ **Everything below this line is the history of an intermediate build; the live account is
   FX_HANDOFF §0d.6 (one instance per ball) and §0d.7 (the CPU push).** What finally did it was neither
   of the two levers described below: the layer's cost was *guard-box area x one nearest-ball search*,
   and instancing removed both factors at once. Measured on the Intel UHD: `juggle both x20`
   1.822 → 0.220, the juggling half of a full window 5.46 → ~1.7, and `_push_live` 4.21 → 1.14.
   Original report — **ball fire cost 28.5 ms per frame for 20 juggling cards** (measured
   2026-07-30, integrated graphics). It was **pre-existing**: the shipped contour build measured
   26.6 ms on the same bench, so the mask model added ~2 ms to an already-broken number rather than
   causing it. The cost was `fx_nearest_ball` — `O(arcs²)` in `sqrt`-carrying arc weights, none of
   which varied across a fragment — run over a quad sized by the ARC HEIGHT on every side, nine
   tenths of which no ball could ever occupy. §6.3 has the three levers that took it, the new table,
   and what is left. ⚠ **Re-measured on a GTX 1070, not on the Intel UHD the 28.5 came from.**
9. **⚠ `all_tests.tscn`'s `speed_base_delay` DECIDES WHETHER SOME UI CHECKS CAN PASS AT ALL, and the
   editor drops it (2026-07-30).** The committed scene sets `speed_base_delay = 0.1`; the script's
   own default is 0.01, and re-saving the scene in the editor wrote the property out entirely, so the
   suite silently dropped to 0.01. **PROVEN, not inferred:** restoring only that one property — with
   every other change in place and the test edit below reverted — turned a reproducible failure into
   a green run. `test_ui_props`'s per-arrival pulse check polls once per frame for
   a tween phase `delay * card_jump_pulse_fraction` long — **30 ms at 0.1 (two frames, observable),
   3 ms at 0.01 (unobservable)** — so it began failing deterministically with nothing about the game
   changed. It cost five bisects, a wall-clock A/B and an `--max-fps 60` run to find, because a
   `git stash` A/B restores the committed 0.1 for the baseline half and hands the "before" build a
   different speed knob than the "after" one. ⚠ **Check `git diff Tests/all_tests.tscn` before
   trusting any A/B of an animated suite.**
   - `test_reactions_drive_card_pose` now raises `base_delay` to 0.4 for its own duration (the idiom
     `test_slow_props_move_continuously` beside it already used), so it no longer depends on the
     global knob either way.
   - The general rule: **a check that polls for a transient must be slower than a frame, or it is
     measuring the frame budget rather than the behaviour.** Grep the UI suites for `WATCHDOG_SECS`
     polls before trusting a similar failure.
10. **✅ FIXED 2026-07-30 — `PIXELS / the highlight sits OFF-CENTRE` had a RANDOM INPUT.** It failed
   intermittently (4.5 px against an 8 px bound) because `FxAttachment._seed` is rolled with `randf()`
   per host, the seed drives the ball's SPIN, and the spin rotates the shading frame the highlight
   sits in — so some runs put the highlight near the ball's centre through no fault of the shader.
   The suite pinned `_ball_dir` for exactly this reason and not `_seed`. Every attachment the PIXELS
   suite builds now sets `att._seed = SEED` BEFORE `sync()` (the per-host randomness is read when the
   quads are BUILT — §4.4). **A rendering test with a random input is not a test**; if you add a shot
   to that suite, pin the seed.
11. **⬜ `fx_intensity` DOES NOT REACH THE JUGGLED BALLS.** `FxStyle`'s own doc calls `brightness` a lever
   the attachment re-pushes with the player's `fx_intensity` folded in, "which is what lets a *reduce
   effects* setting reach every effect without editing a single `.tres`" — and `FxAttachment._apply_static`
   does push `u_brightness = brightness * fx_intensity`. But **`juggle.gdshader` declares no
   `u_brightness`**, so that write lands nowhere and the balls ignore the setting. Reaching 0 is
   documented as "a genuine photosensitivity control, not a taste one", so this is the one effect where
   that claim is false. Fix is either `uniform float u_brightness = 1.0;` folded into `col.rgb` beside
   `u_opacity` (juggle.gdshader:148), or a decision that brightness is fire-only — in which case move it
   off `FxStyle` onto `FxFireStyle`, where a shader-less uniform cannot be written by accident.
   Found by the 2026-07-30 `/simplify` pass; deliberately NOT fixed there because it changes what renders.
12. **⬜ `FxAttachment` KNOWS ABOUT JUGGLING, in the ember emitter only.** The class's headline contract is
   "it does not know which effects exist", and `sync`/`_apply_static`/`_push_live` all honour it. Then
   `_emit_embers` branches on `fx.req.shape == Shape.BALLS`, `_ember_origin` casts `fx.req.style as
   FxFireStyle`, reads eight juggling uniform names out of `vals` (`u_ball_radius`, `u_span`,
   `u_arc_height`, `u_return_height`, `u_ball_arcs`, `u_top_fraction`, `u_ball_gravity`, `u_ball_count`)
   and calls `FxJuggle.ball_pos` directly. So a juggle-uniform rename silently degrades embers to height
   0 — the failure already recorded in the comment there, which was found by eye because `09_embers` is
   randomised. The deep fix is a spawn-point seam ON the request (a small emitter object, not a
   `Callable` — a stored closure on a long-lived request keeps its whole enclosing scope alive), set by
   `FxFire.request` / `FxJuggle.requests`. That also deletes `FxRequest.lit`, which exists only so the
   generic request class can carry a juggling fact. Third visual status = a third `if` until then.
13. **⬜ A PROP CATCHING FIRE MID-FLIGHT SHOWS NOTHING.** `PropVisual.fire_stacks`' setter documents that
   it exists so "a prop catching fire mid-flight lights up without waiting for a respawn", but the only
   write is `PropLayer._make_visual` (capture at spawn). `PropLayer._process` already re-derives every
   other data→visual fact live — scale, pin, lane offset, split state, position — precisely because
   capture-at-spawn caused two owner reports. So `PropBurning` raising `PropData.fire_stacks` is a live
   gameplay state with no visual. Fix is one line in that existing `_process` loop (or `begin_prop_tick`).

---

## 8. When you stop

1. Full suite green, WINDOWED, with the suite count checked (§3).
2. Re-run whichever snapshot harness your change touches, and **look at the PNGs**.
3. Update **ARCHITECTURE_REVIEW §4g/§4h** if you changed a rule or added a trap, and **this file's
   §6/§7** so the next agent inherits an accurate backlog.
4. Add a row to FX_SHADER_PLAN.md's handoff log if the work maps to its task board.
5. No `git add`, no commits — the owner commits via GitHub Desktop.

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
| `Shaders/fx_common.gdshaderinc` | The pixel grid, noise, dither, and **the one definition of the ball path** (`fx_ball_at` / `fx_ball_pos` / `fx_nearest_ball` / the arc ladder). Included by both shaders so the maths cannot exist twice. |
| `Shaders/fire.gdshader` | Fire. ONE path for every host: it raises the art's MASK by an ogee arch and subtracts the mask. `mask()` is the only extension point — one branch per shape, and a juggled ball is one of those shapes, not a mode. |
| `Shaders/juggle.gdshader` | The juggled balls. |
| `Shaders/Styles/*.tres` | Every art lever, per effect (`FxStyle`), plus `ember.tres` (a `ParticleSpec`). Colours point at `Assets/Palette/` ramps (§4i). **The single place FX tuning lives** (owner ruling 8). |
| `UI/Fx/fx_attachment.gd` | One host's effects: builds the quads, owns the clock, the per-host randomness, the lag spring. |
| `UI/Fx/fx_fire.gd`, `fx_juggle.gd` | Stacks → uniforms. `FxJuggle.geometry()` is the ONE computation both ball quads read. |
| `UI/Fx/fx_style.gd`, `fx_request.gd` | The lever resource, and the request a status hands to an attachment. |
| `UI/Fx/particle_engine.gd`, `particle_spec.gd` | The game's ONLY particle path (embers are its first client). |
| `Cards/Props/prop_visual.gd` + `Cards/Props/Visuals/*.gd` | Prop art: sheets, sizes, mirroring, the split halves. |
| `Cards/Pips/pip_suit.gd`, `Assets/color_picker.gdshader` | Suit pips and the palette recolour shader. |
| `UI/Fx/Tools/fx_editor.tscn` | **Live FX tuning in the editor** — open it, edit an `FxStyle`, watch the real shaders react. Start here for any art tuning (§4g). |
| `Tests/Visual/` | `test_pixels.gd` (asserting), `fx_snapshot.gd` + `prop_art_snapshot.gd` (reviewable), `pixel_probe.gd` (the shared oracle + image readers), `snapshot_scene.gd` (the harness base). |

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
- **The rest of the numbers to settle by eye**, all single tunables: `FxFire.FX_MAX_TENDRILS` (12),
  `FxStyle.level_ref` (120 card / 60 prop / 40 ball), `settings.fx_transition_fraction` (0.6),
  `ParticleEngine.MAX_PARTICLES` (1024), `FxStyle.ember_rate_max` (24/s), ball spin base and its
  per-count coefficient, `onion_power` / `onion_rise` (shell thickness, how much the tip cools),
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

**What to look at, by EYE:** `fx_snapshot`'s new `03_surfaces` (1/2/4/12 tendrils over the ring —
both arcs alight, the hole's middle always empty), `04_shapes`, `07_transition`'s RING panels (the
comb easing over a curved host), and `prop_art_snapshot`'s `17_prop_fire` at real size. **Never count
columns** — that instrument reported two rejected builds as successes.

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


- **⬜ `fx_editor.tscn` unverified inside the editor.** Its non-editor paths were smoke-run with a
  GPU; the `Engine.is_editor_hint()` branches (no autoloads, ownerless rebuild) are unproven until
  the owner opens the scene. First thing to report if it misbehaves.
- **⬜ `base_width` is now 1.3** on all three fire styles — that is what closed the per-tendril seams
  and the edge coverage (§4g). If the crown now reads too solid, that number is the lever.
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
8. **✅ MOSTLY FIXED 2026-07-31 — ball fire cost 28.5 ms per frame for 20 juggling cards** (measured
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

---

## 8. When you stop

1. Full suite green, WINDOWED, with the suite count checked (§3).
2. Re-run whichever snapshot harness your change touches, and **look at the PNGs**.
3. Update **ARCHITECTURE_REVIEW §4g/§4h** if you changed a rule or added a trap, and **this file's
   §6/§7** so the next agent inherits an accurate backlog.
4. Add a row to FX_SHADER_PLAN.md's handoff log if the work maps to its task board.
5. No `git add`, no commits — the owner commits via GitHub Desktop.

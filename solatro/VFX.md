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
they are the spec) and §7 (the task board, T1–T21). **PALETTE_PLAN_BRIEF.md** for the one open
feature. Both are historical; if they disagree with ARCHITECTURE_REVIEW, the latter wins.

---

## 2. Where the code is

| Path | What |
|---|---|
| `Shaders/fx_common.gdshaderinc` | The pixel grid, noise, dither, and **the one definition of the ball path** (`fx_ball_at` / `fx_ball_pos` / `fx_nearest_ball` / the arc ladder). Included by both shaders so the maths cannot exist twice. |
| `Shaders/fire.gdshader` | Fire, in two modes: SILHOUETTE (a host's outline) and BALLS (a plume per lit ball). |
| `Shaders/juggle.gdshader` | The juggled balls. |
| `Shaders/Styles/*.tres` | Every art lever, per effect (`FxStyle`), plus `ember.tres` (a `ParticleSpec`) and the baked `fire_ramp.png`. **The single place FX tuning lives** (owner ruling 8). |
| `UI/Fx/fx_attachment.gd` | One host's effects: builds the quads, owns the clock, the per-host randomness, the lag spring. |
| `UI/Fx/fx_fire.gd`, `fx_juggle.gd` | Stacks → uniforms. `FxJuggle.geometry()` is the ONE computation both ball quads read. |
| `UI/Fx/fx_style.gd`, `fx_request.gd` | The lever resource, and the request a status hands to an attachment. |
| `UI/Fx/particle_engine.gd`, `particle_spec.gd` | The game's ONLY particle path (embers are its first client). |
| `Cards/Props/prop_visual.gd` + `Cards/Props/Visuals/*.gd` | Prop art: sheets, sizes, mirroring, the split halves. |
| `Cards/Pips/pip_suit.gd`, `Assets/color_picker.tres` | Suit pips and the palette recolour shader. |
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

- **A new effect** = one `.gdshader` + one `FxStyle` preset + a status that returns an `FxRequest`
  from `fx_request()`. `FxAttachment` never learns effect names.
- **A new prop shape** = one branch in `shape_radius()` + one `fx_shape()` override.
- **A new prop kind's art** = a sheet, `art_size = art_size_for(SHEET, …)` in `_init` (never a raw
  pixel number), and a `_draw_frame` call. §4h explains why.
- **A new lever** = an `@export` on `FxStyle`, one `set_shader_parameter` in `apply()`, one uniform.
  Never a literal in the shader: `Shaders/Styles/*.tres` is the single tuning home.
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

- **⬜ T21 — the universal palette.** Audit done, decisions listed:
  **[PALETTE_PLAN_BRIEF.md](PALETTE_PLAN_BRIEF.md)**. Write the plan from it, get the approval lines
  ruled on, then build. FX is the LAST consumer to migrate (see §7.3).

### 6.3 Measurements nobody has taken

- **⬜ Fill rate — the one unmeasured risk**, and it needs a real GPU: 20 burning cards on the board,
  then 50 in the deck viewer; read the frame time. Then again at 8 arcs with many juggling cards,
  which is where this feature's cost now lives (§7.2). If it measures badly, spend the levers in this
  order — raise `FxStyle.pixel` (chunkier FX pixels is a LOOK change, not a capability loss) → drop
  `fx_fbm` to one octave → cap `FxStyle.height` to shrink the quads → and only then reconsider
  one-quad-per-effect. **Do not start by cutting features.**

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

1. **⬜ FX colours are OFF-PALETTE.** Measured 2026-07-27: `Shaders/Styles/fire_ramp.png` holds **64
   distinct colours, none of them a CircusCrayon entry**, and the ball colours are hand-picked
   (nearest-entry distance 40–80). They were tuned to look like fire, so nothing looks wrong — but a
   palette swap will not move them. Card/prop/pip ART is already on-palette; only the shader FX and
   ~20 scattered `Color(...)` literals are not. Two mechanisms also GENERATE in-between colours (the
   ramp generator's COLD→HOT interpolation, and `juggle.gdshader`'s `mix(shade, lit, …)` sphere
   banding), so on-palette endpoints are not enough — band colours must be SAMPLED from an ordered
   role list. This is T21's job, not a bug to chase. Numbers: PALETTE_PLAN_BRIEF §2.3 / §4.4.
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
7. **Two GDScript↔GLSL enum mirrors can drift silently** (`FxAttachment.Mode` / `.Shape` against the
   constants in `fire.gdshader`). The FX ATTACHMENT suite reads the constants out of the shader
   source and asserts the mapping — keep that test alive if you add a mode or a shape.

---

## 8. When you stop

1. Full suite green, WINDOWED, with the suite count checked (§3).
2. Re-run whichever snapshot harness your change touches, and **look at the PNGs**.
3. Update **ARCHITECTURE_REVIEW §4g/§4h** if you changed a rule or added a trap, and **this file's
   §6/§7** so the next agent inherits an accurate backlog.
4. Add a row to FX_SHADER_PLAN.md's handoff log if the work maps to its task board.
5. No `git add`, no commits — the owner commits via GitHub Desktop.

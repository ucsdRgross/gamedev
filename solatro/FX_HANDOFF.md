# FX_HANDOFF.md — pick this up cold

You are continuing the shader-FX feature. The previous session ran long and meandered; this file
exists so you do **not** repeat its dead ends. Read this whole file before touching anything, then
read [FX_SHADER_PLAN.md](FX_SHADER_PLAN.md) §0b (the 25 owner rulings — they are the spec) and its
§7 task board.

**Read order:** this file → FX_SHADER_PLAN.md §0b → FX_SHADER_PLAN.md §7 → the section your task
points at. Project rules that override everything: [START_HERE.md](START_HERE.md).

---

## 1. Where things stand

**Landed and green:** T1–T14 of the plan's task board. The full headless suite is 26 suites / 0
failures. Architecture is documented in [ARCHITECTURE_REVIEW.md](ARCHITECTURE_REVIEW.md) §4g and
[LAYERING.md](LAYERING.md); do not re-derive it, and do not redesign around the rulings.

**Not done:** T15 (owner plays the §10 script) and T16's final step (deleting the plan file —
**blocked on owner review, and the file is UNTRACKED, so `rm` is unrecoverable; do not delete it**).

**What actually works, verified on a GPU:** fire renders upright and pointed at every host
rotation with a square pixel grid; the tendril comb is exact (1/2/4/8/12 counted); the ogee
profile, the ramp colouring, the prop shapes and the split-prop halves all render.

**What is broken:** ball positions (§3.1). Three new owner requirements are unimplemented (§4).

---

## 2. How to run things (exact commands, both matter)

**Headless suite — after every change.** Never while the owner's editor is open
(`Get-Process *odot*`). Bound it and grep in the same command; a parse error HANGS the run forever
(HEADLESS_TESTING.md §0a):

```bash
timeout 400 "/c/Users/khanr/Desktop/Godot_v4.7.1-stable_win64_console.exe" --headless --path solatro res://Tests/all_tests.tscn > /tmp/run.log 2>&1; echo "exit: $?"; grep -n "Parse Error" /tmp/run.log | head; tail -4 /tmp/run.log
```

**Visual snapshots — after EVERY shader edit.** Windowed, needs a GPU. This is the only thing that
can see a pixel:

```bash
timeout 200 "/c/Users/khanr/Desktop/Godot_v4.7.1-stable_win64_console.exe" --path solatro res://Tests/Visual/fx_snapshot.tscn > /tmp/snap.log 2>&1; echo "exit: $?"
```

PNGs land in `%APPDATA%\Godot\app_userdata\Solatro\fx_snapshots\`. **Read them** — they are the
test. Shots: `00_tendril_count` (geometry only, countable), `00b_ogee_profile` (the arch outline),
`01_fire_ladder`, `02_fire_rotation`, `03_fire_wrap`, `04_shapes`, `05_balls`, `05b_ball_path`
(one ball traced phase by phase), `06_ball_fire`, `07_transition`.

**After adding any `class_name`,** run `--headless --path solatro --import` first or the class
cache is stale and you will chase phantom parse errors.

---

## 3. The open bug — read before touching juggle.gdshader

### 3.1 Ball positions disagree with the spec at LOW ball counts ⚠

`05_balls.png` draws green crosses from an **independent GDScript oracle** (`_oracle()` in the
snapshot harness, transcribed from the spec, deliberately NOT from the shader). At 50 balls the
balls sit on their crosses. **At 1 ball the rendered ball is nowhere near its cross.**

Already ruled out — do not redo this work:

- The uniforms reaching the material are correct. The harness prints them: `u_phase=0.13`,
  `u_count=1.0`, `u_span=30.4`, `u_arc_height=37.5`, `u_return_height=6.0`, `u_top_fraction=0.6`,
  `u_extent=(151.8, 151.8)`.
- Both `fx_ball_at` call sites pass arguments in the declared order `(s, span, h_top, h_bot, f)`.
- It is not panel overlap in the harness (that was a red herring; `_zoom_for` now sizes every shot
  so slots cannot overlap).
- It is not a constant phase offset and not a pure mirror — both were tried against the traced
  path and neither fits.

**Where to look:** `fx_nearest_ball` in `Shaders/fx_common.gdshaderinc`, specifically the index
recovery when `count == 1`. Every candidate wraps to the same index there, so a wrong arc branch
cannot be caught by disagreement between candidates — which is consistent with the bug appearing
at low counts and vanishing at high ones.

**Start from `05b_ball_path.png`**, which traces ONE ball around the whole cycle at eight phases.
Compare each ball against its cross. Fire is unaffected — this is balls only.

**Do not measure pixel positions out of the PNGs.** The previous session burned a large amount of
context doing that and drew two wrong conclusions. The crosses exist so you can judge by eye.

Once fixed, re-check `06_ball_fire.png`: whether plumes are welded to their balls cannot be judged
while the balls themselves are misplaced.

---

## 4. New owner requirements (2026-07-27, unimplemented)

### 4.1 Balls must look SPHERICAL

> *"balls need to be spherical"*

Today `juggle.gdshader` shades a ball with two flat regions plus a gloss dot — it reads as a disc.
It needs to read as a sphere: a proper terminator, banded shading that follows the curvature
(concentric, not a straight split), and a highlight that sits ON the surface. Keep it pixel-art —
hard bands, no antialiasing, and the spin still rotates only the SHADING frame, after quantization
(the pixel grid never rotates).

Band count and light direction should be `FxStyle` levers, not literals.

### 4.2 Fire must be ONION-LAYERED, not row-layered

> *"fire should be less layered where colors are stacked like rows, and more like onion layers
> where each layer wraps around the other, like actual candle lights"*

This is the important one, and it is a change to how `heat` is computed — not to the palette.

Today `heat` is essentially `1 - rise/top`, which varies almost purely with HEIGHT, so the ramp's
bands come out as horizontal stripes stacked up the flame. A candle flame is the opposite: nested
shells, each colour wrapping the one inside it, hottest at the core and coolest at the rim, with
the bands following the flame's OUTLINE at every height.

The fix is to make heat a function of *distance from the flame's core*, normalized by the local
half-width, rather than of height alone — so an iso-heat contour is a scaled copy of the outline.
Roughly: heat should fall off with `|u| / dome` (how far across the flame you are, relative to how
wide the flame is at this height) combined with a much weaker height term. Verify with
`00_tendril_count` (noise off): the bands must appear as nested arch-shaped shells, not as
horizontal rows.

### 4.3 Height must be adjustable per effect

> *"make sure height of each is adjustable"*

Already partly true and must stay true through 4.1 and 4.2: fire length is `FxStyle.height`, ball
size is `ball_radius`, the throw arc is `ball_arc_height`, the return is `ball_return_height`.
Whatever you add for spheres and onion layers must not bake a height in — every one of them stays
a `.tres` lever, and `Shaders/Styles/*.tres` stays the single place all FX tuning lives (ruling 8).

---

## 5. New system: ONE palette for the whole game

> *"colors should come from universal palette ... given a palette (1xN pixel image), we can assign
> to every color using system in the project a color from the palette via some resource of
> pointers, and make it easy to reassign to different colors especially if the palette changes."*

This is a **project-wide system, not an FX feature**, and it outlives this plan. Treat it like
`ParticleEngine`: its own files, its own section in ARCHITECTURE_REVIEW, its own tests.

### What exists today (audited 2026-07-27, from code)

| Fact | Where |
|---|---|
| The palette is a **24x1** PNG | `Assets/CircusCamping.png` |
| An older **20x1** palette also exists | `Assets/palette.png` |
| Recolouring is a VisualShader with `color_x` (index) + `num_colors` uniforms | `Assets/color_picker.tres` |
| Suit colours are **raw magic indices** | `Cards/Pips/pip_suit.gd:21` — `const PALETTE : Array[int] = [6, 11, 8, 2, 14]` |
| Three card polygons have the index and count **stamped into the scene** | `Cards/card_visual.tscn:464-475` — `color_x = 8`, `num_colors = 20` |
| **Existing bug:** `num_colors` is 20 in the scene and 24 in the shader default, but `CircusCamping.png` is 24 wide | the two above |
| FX colour is currently a **baked PNG ramp**, outside the palette entirely | `Shaders/Styles/fire_ramp.png`, `tools/make_fx_ramp.py` |

So the same palette index is spelled three different ways (a GDScript const array, a scene
property, a shader default), and `num_colors` is already inconsistent with the actual image. That
is exactly the drift the owner wants removed.

### Shape of the system (design, not yet built)

- **`Palette` (`Resource`)** — the `Nx1` texture, plus `width` derived FROM the texture, never
  hand-entered. Swapping palettes is swapping this resource.
- **`PaletteRoles` (`Resource`)** — the "resource of pointers": a
  `Dictionary[StringName, int]` mapping a semantic ROLE (`&"suit_hearts"`, `&"fire_core"`,
  `&"ball_lit"`, `&"ui_focus"`) to an index in the palette. Reassigning a colour is editing ONE
  entry in ONE `.tres` in the inspector. Roles are named for MEANING, never for the colour
  ("fire_core", not "orange") — that is what survives a palette change.
- **`PaletteManager` (autoload)** — holds the current `Palette` + `PaletteRoles`; exposes
  `color(role) -> Color` (for GDScript-side drawing) and `index(role) -> int` (for `color_x`).
  Emits `palette_changed` so live materials can be re-pushed, exactly as `SettingsManager` does.
- **`num_colors` comes from the texture width**, pushed by the manager. Never stamped into a scene
  or a material by hand again.

### Migration, in order

1. Build the resources + autoload, with a test asserting every role resolves inside `0..width-1`.
2. Repoint `PipSuit.PALETTE` at roles.
3. Strip `color_x`/`num_colors` out of `card_visual.tscn` and set them from the manager.
4. FX last: replace the baked `fire_ramp.png` with a ramp GENERATED from palette roles (a heat
   ramp is an ordered list of roles — `fire_core`, `fire_mid`, `fire_edge`, `fire_smoke`), so a
   palette swap recolours the fire too. `tools/make_fx_ramp.py` becomes a role-driven generator,
   or the ramp is built at load into an `ImageTexture`.
5. Only then delete `Assets/palette.png` if nothing references it.

**Do not start this inside the FX plan.** It needs its own plan doc, written to START_HERE's
workflow (audit → owner APPROVAL lines → steps that each leave the game runnable), because it
touches scenes, save-independent art, and every colour in the game.

---

## 6. Traps already paid for — do not rediscover these

- **`QuadMesh` UV.y is inverted** against Godot 2-D. `fx_local()` in `fx_common.gdshaderinc` owns
  that flip; go through it, never quantize `UV` yourself. Getting this wrong renders every effect
  upside down.
- **Dynamically indexed local arrays in GLSL are unreliable on GLES3** — one compiled with no
  error and returned garbage. Unroll them (see `box_contour`).
- **Godot logs no shader error for a semantically wrong shader.** A clean log means nothing; only
  the snapshots do.
- **`--headless` never compiles a shader.** A green suite says nothing about pixels.
- **Warnings are errors.** Type every array and loop variable; `floor()`/`ceil()` return Variant,
  use `floorf()`/`ceilf()`; `Dictionary.get()` returns Variant — assign through a typed local.
- **Both FX hosts are `@tool`.** Guard construction with `Engine.is_editor_hint()` and never set
  `owner`, or the editor writes FX nodes into `card_visual.tscn` on disk.
- **No `git add`, no commits.** The owner commits via GitHub Desktop.

---

## 7. Suggested order

1. **§3.1 ball positions** — a real bug, already instrumented, blocks judging ball fire.
2. **§4.1 spherical balls** and **§4.2 onion-layered fire** — both are shader-local and verified
   entirely by snapshots.
3. **§4.3** is a constraint on 1–2, not separate work.
4. **§5 palette system** — its own plan doc first, owner approval, then build.
5. T15 (owner plays §10), then T16's last step.

Append a row to FX_SHADER_PLAN.md's handoff log when you stop.

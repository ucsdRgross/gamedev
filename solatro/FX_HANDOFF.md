# FX_HANDOFF.md — live handoff, reopened 2026-07-29

**Read [VFX.md](VFX.md) and ARCHITECTURE_REVIEW **§4g** first** (the map and the contract). This file
is the *current* handoff: what changed in the 2026-07-28/29 sessions, what the owner has REJECTED,
and the one problem that is still open. Fold it back into §4g and delete it once the open issue is
settled.

---

## 1. THE OPEN ISSUE — fire on the hoop (curved surfaces)

**Status: two attempts, both rejected by the owner. This is why you are reading this file.**

The hoop is the only curved host (`Shape.RING`, an analytic ellipse from `u_body`). Flat hosts — the
card, the knife, the ball and fire pips — all look right; do not "fix" them while chasing this.

### What the owner said, in order

1. *"tendrils become flatter as they curve around hoop top, which definitely shouldn't happen,
   tendrils should be equally long no matter where base location is"* — about the ORIGINAL build,
   where the base was sampled per FRAGMENT (`contour_y(p.x)`), which shears each tendril along the
   surface and squashes its arch as the contour steepens.
2. Asked to choose between tilting flames along the surface normal, keeping them upright and merging
   by overlap, or reverting to the continuous sheared base: chose **"keep upright, merge by
   overlapping"**.
3. After seeing that build: *"hoop fire still looks wrong … previous sheared version looks better
   than whatever latest is."*

So the ranking so far is **sheared (original) > current**, and neither is acceptable.

### What is in the code right now

`fire.gdshader::tendril_on_contour()` gives every tendril ONE base, taken from the contour at its own
cell centre, so its arch is never sheared. `Shaders/Styles/fire_prop.tres` has `merge = true` and
`base_width = 1.3` so neighbours fuse.

**Reverting to the sheared look is small and local**: compute `base` from `contour_y(p.x, …)` inside
the caller again and pass one `rise` to `tendril()`, as it was before 2026-07-29. Git has it. If the
owner wants the old look back while a better model is designed, that is the one-line direction.

### Why neither version is right — the diagnosis to start from

**The comb is uniform in X, but the ring is not.** `emit_half_width()` returns the ellipse's half
WIDTH and the tendrils are spread evenly across it, so equal x-steps map to wildly unequal ARC
LENGTHS: dense, well-spaced flames at the apex, and a handful of stretched ones along the flanks
where the surface is nearly vertical. On top of that, a strictly vertical flame planted on a
near-vertical surface only grazes it, so at the flanks the flames read as lying along the ring rather
than standing on it. The per-tendril base did not cause this — it just stopped hiding it behind a
continuous skirt.

**Suggested direction (untried, and it needs an owner ruling):** comb by ARC LENGTH along the top
arc, and emit along the local NORMAL rather than straight up. That gives evenly spaced flames all the
way round, every one the same length, adjacent bases overlapping (so they merge), and no shearing —
all four things the owner has asked for, at once. The cost is that flames on a curved host would no
longer point strictly up, which contradicts **owner ruling 1** as written. Get that ruled on before
building it. The ellipse makes both pieces cheap: arc length and normal are closed-form.

### ⚠ Do not trust the metric I used

I measured "columns of ring with a flame above them" (88 columns, 12 gaps, largest 4 px) and reported
success twice while the owner was telling me it looked wrong. **Coverage is not the same as reading
correctly.** Judge this shot by eye, or find a metric that captures spacing evenness along the arc
and flame direction relative to the surface.

Fastest loop: open `UI/Fx/Tools/fx_editor.tscn` in the editor (see §5) — the hoop is on screen with
live knobs. `Tests/Visual/prop_art_snapshot.tscn` shot `17_prop_fire` is the reviewable capture.

---

## 2. EMBERS ON EVERY FIRE, not just the card

**Owner 2026-07-29: *"all fire effects should leave embers like card is currently. dont see embers on
props or balls."*** Wanted: a burning hoop, knife, ball or fire prop, and a lit juggling ball, all
throw embers the way a burning card does.

**Why none appear today.** `FxAttachment._emit_embers()` early-outs on `not style.ember`, and only
`fire_card.tres` carries an ember spec — `fire_prop.tres` and `fire_ball.tres` leave it null, which
is what disables them. Props ARE `ambient` (`PropVisual._make_fx` never passes `host_ambient`, so it
defaults true), so nothing else is in the way for them.

Two real obstacles, in order:

1. **Ball embers would spawn in the wrong place.** The spawn point is derived from the HOST's body —
   `randf_range(-body.x, body.x) * 0.5` across the top edge, lifted by `u_height`. For a prop the
   host IS the burning thing, so that is right. For ball fire the host is the CARD, so embers would
   pour off the card's top edge while the flames are out on the balls. Ball embers need the ball
   positions — the same closed form `fx_nearest_ball` inverts, or `FxJuggle.geometry()` plus a
   GDScript copy of `fx_ball_at`. ⚠ A second copy of the arc maths is exactly the bug that made
   flames trail their balls (§4g); prefer sampling only LIT ball indices from
   `StatusJuggling.fire_levels()` and reusing one shared implementation.
2. **The ember spec is tuned in CARD art units.** `ember.tres` is `size_start 2.0`, `speed 16`,
   `gravity (0, -14)`. Prop art units are ~2.5× smaller (§4h), so a card-sized ember on a knife will
   look enormous. Expect a second spec (`ember_prop.tres`) rather than reusing one, exactly as the
   fire styles are split per host scale. Both are `ParticleSpec` `.tres` files — data, not code.

`ember_rate_max` is a per-source ceiling (24/s on the card), so adding sources multiplies the load on
`ParticleEngine`'s single 1024 cap — worth a glance at `live_count()` with a board full of burning
props before settling the rates.

---

## 3. Also open (none of these blocks the above)

| Item | Where |
|---|---|
| Fire ramp's ENDS are an art call: entry 0 makes a 1-stack flame near-black, entry 19 puts neutral grey at the white-hot end. One-line edits to `Assets/Palette/ramp_fire.tres` | todo.md |
| Ball highlight is a quantized ellipse at small radii (~5×7 FX pixels at r=14), so its flanks show straight runs. Levers: `ball_spec`, or a smaller `pixel` on the juggle style | VFX.md §6.2b |
| Map screen + in-game UI chrome still hardcoded, deferred pending the owner's custom art. They warn every test run as `[WARN][PLACEHOLDER]` | todo.md, §4i |
| `FireworkVisual` has no art — placeholder magenta polygon | todo.md |
| `suit_pips.png` has a few off-palette pixels (e.g. `#ec0037`) — authored art, not plumbing | `tools/palette_conformance.py` |

---

## 4. What landed in these sessions (context for the diff you are reading)

**Universal palette (T21).** Contract: **ARCHITECTURE_REVIEW §4i**. `Palette` / `PaletteRoles` /
`PaletteRamp` / static `PaletteDB`; fire, ball tones and embers all SAMPLE ordered palette ramps
instead of lerping; `color_picker.gdshader` replaced the VisualShader; `make_fx_ramp.py` and
`fire_ramp.png` deleted.

**FX fixes, all in §4g:**

- **Ball direction.** The per-ball mirror cancelled the arc ladder's own alternation whenever the
  ball count was near the arc count — at 2, 4 and 6 balls every ball travelled the same way and half
  the pattern sat empty. Mirror removed; crossing comes from the ladder. Guarded by name in
  `test_pixels.gd`.
- **One gravity for the ladder.** Arc time shares are now ∝ sqrt(arc height); the ease applies to
  every arc including the carry. Measured speed spread 1.92× → 1.26×.
- **Ball plume** sits on TOP of the ball (`rise` from `- radius + sink`), not wrapped around it.
- **Ball centre snapped** to the pixel lattice (`fx_pixel_snap`), with the y flip undone — the two
  axes only share a lattice when `extent/pixel` is a whole number. The ball-fire quad snaps on the
  BALL quad's lattice via `FxRequest.partner_reach` / `partner_pixel`.
- **`base_width` 1.3** on the fire styles: at 1.0 each dome hits exactly zero at its cell boundary and
  so does its neighbour's, so `merge` could never close the seam (`max(0,0)` is 0).
- **Sprite silhouettes** are a per-column `Shape.PROFILE` measured from alpha, and `body` is tightened
  to the art. Fixed flames over blank padding and bases jittering along flat tops (a polar table has
  no resolution across a flat edge). 0 px overhang measured on all three sprite props.
- **Fire is opaque** (`inner_alpha = 1.0` everywhere); `FxStyle.sink` is the knob for how far flames
  come down over the art (negative lifts them clear).
- **Everything FX is `@tool`.** See the loud block in §4g — a placeholder script both breaks
  `FxStyle.apply()` (white effects) and makes the editor DROP properties when it re-saves a `.tres`.
- **`UI/Fx/Tools/fx_editor.tscn`** — live tuning in the editor, rendering through the shipping path.

---

## 5. Runbook (corrected 2026-07-29)

```bash
Godot --path solatro res://Tests/all_tests.tscn            # windowed, ~85 s, exit = failure count
Godot --path solatro res://Tests/Visual/fx_snapshot.tscn   # after ANY shader edit
Godot --path solatro res://Tests/Visual/prop_art_snapshot.tscn
py solatro/tools/palette_conformance.py
```

- **The owner's editor being open is fine for running these** — measured with it open: import 26 s,
  suite 84 s, exit 0, 28 suites green. The old "the two instances starve each other" claim did not
  reproduce; it was the Bash tool's own 120 s default timeout being misread. Bound long runs with an
  explicit timeout.
- **But the open editor REWRITES `.tres` on disk**, and a non-`@tool` script loads as a placeholder
  whose save DROPS unknown properties (`fire_card.tres` lost `pixel` and `dither` that way).
- ⚠ **Never kill a Godot process without reading `MainWindowTitle` first.** The owner's editor was
  killed on 2026-07-29 by a blanket `Get-Process *odot* | Kill()`.
- `PropVisual._ready()` early-returns in the editor, so anything it does at runtime (including
  `measure_fx_silhouette()`) must be done explicitly by an editor tool. **A snapshot scene and the
  editor can therefore disagree** — that gap hid the prop-silhouette bug for a whole round.

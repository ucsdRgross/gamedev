# IMPACT MAP — card 38×50 → 40×54, and the shader-drawn art outline

**Status:** inventory only. This is *not* a design decision record and *not* an implementation
plan — it is the complete list of what the two changes touch, with the measured current values and
the file:line where each one lives, so a `/flowchart-design` run or a plan can be written against
facts instead of guesses. Every number below was read out of the code or the PNG headers on
2026-08-04; nothing here is quoted from another doc.

Open questions that need the owner are collected in **§9**. Nothing in §1–§8 assumes an answer.

---

## 0. The two changes, stated precisely

**Change A — the card grows.** `CARD_SIZE` goes from `Vector2(38, 50)` to `Vector2(40, 54)`.
At the shipped `card_scale = 2.5` the drawn card goes **95×125 → 100×135 screen px**.

**Change B — every sprite-sheet element on the card, INCLUDING THE CARD FACE ITSELF, gains a solid
1-px, 8-directional outline in a palette colour, drawn by a shader.** The pip and art sheets stay
authored at 8×8 and 32×32; the outline is generated at draw time, so the *occupied* footprint
becomes **10×10 and 34×34** while the *source art* is untouched.

**Change B′ (owner, 2026-08-04) — the card TYPE art is an outline client too.** Its frames shrink
to **38×52** in the sheet and are *treated as* 40×54: the shader's outline supplies the missing
ring. This is the one client whose source art shrinks rather than staying put, because the type
frame is the only one whose frame size *is* the host's footprint.

⚠ **This replaces a border that is already painted into the art, and that is measurable.** Sampled
2026-08-04: the perimeter ring of `card_types.png` frames 2, 3 and 4 is a **single flat colour,
`#290d2c`, at exactly 168 opaque texels** — the full 38×50 perimeter is 172, minus the 4 corner
texels each frame bites out. Frames 1, 5 and 6 carry the same 172-ish `#290d2c` count. So the
change is not "add an outline to art that has none"; it is **lift the hand-painted ring out of the
art and hand it to the shader**, which is exactly what makes it dynamic. The interior face grows
36×48 → 38×52 as the card grows 38×50 → 40×54 — the same +2/+4, so the design is self-consistent.

**Why B forces A (and why A is exactly +2/+4):** the outline needs somewhere to be drawn. A
canvas fragment shader can only write inside its own polygon, so each pip polygon must grow
8×8 → 10×10 and the art polygon 32×32 → 34×34. The card grows by exactly the margin those
outlines eat: +1 per side horizontally (the art square is the widest element, +2 total) and +2 top
+2 bottom vertically (the pip row and the art row each gain an outline, +4 total). §7 shows the
arithmetic landing on the same 3-unit margins the card has today.

**Why B is wanted:** a card's *type* frame is the card's whole face and its colour is authored
art — today's shipped types happen to be readable behind the pips, but nothing constrains a future
type to a colour that a pip or the card art already uses. When they match, the element vanishes
into the face. An outline in a *different* palette entry keeps every element readable against any
face colour. ⚠ That argument has a hole the outline colour itself must answer — see **Q1** in §9.

---

## 1. Ground truth: the geometry as it stands today

### 1a. The constants

| Constant | Value | Where |
|---|---|---|
| `CARD_SIZE` | `Vector2(38, 50)` | [card_visual.gd:7](Cards/card_visual.gd:7) |
| `CARD_SEPARATION` | `14` (stack overlap, in art units) | [card_visual.gd:8](Cards/card_visual.gd:8) |
| `CARD_JUMP_RISE` | `CARD_SIZE.y / 5.0` = **10.0** — *derived* | [card_visual.gd:13](Cards/card_visual.gd:13) |
| `SHIPPED_CORNER_NOTCH` | `Vector2.ONE` (1 texel bite per corner) | [card_visual.gd:262](Cards/card_visual.gd:262) |
| `PlayArea.separation` | `4` (column gutter) | [play_area.gd:21](UI/play_area.gd:21) |
| `card_scale` | `2.5` default | [player_settings.gd:21](Scripts/player_settings.gd:21) |
| `PropVisual.AUTHORED_CARD_SCALE` | `2.5` | [prop_visual.gd:94](Cards/Props/prop_visual.gd:94) |
| `StatusLayer.ICON_SIZE` | `10.0` (drawn primitive, not sheet art) | [status_layer.gd:7](Cards/Statuses/status_layer.gd:7) |

The four `card_*_play` statics ([card_visual.gd:39-52](Cards/card_visual.gd:39)) and
`recalculate_size` ([:431](Cards/card_visual.gd:431)) all multiply `CARD_SIZE` / `CARD_SEPARATION`
by `card_scale`. **They need no edit** — that is the point of them.

### 1b. The polygons in `card_visual.tscn`

All coordinates are unscaled art units, card centre = origin. One texel of source art = one art
unit (pinned by `test_fx_pixel_is_the_games_pixel`).

| Node | Polygon | Position | Occupied box | Margin to card edge |
|---|---|---|---|---|
| `Type` | 38×50, 4×4 grid + diamond cuts, 41 verts | `(0, 0)` | x −19..19, y −25..25 | — (it *is* the face) |
| `Rank` | 8×8, 5 verts | `(-12, -17)` | x −16..−8, y −21..−13 | left 3, top 4 |
| `Stamp` | 8×8, 5 verts | `(0, -17)` | x −4..4, y −21..−13 | top 4 |
| `Suit` | 8×8, 5 verts | `(12, -17)` | x 8..16, y −21..−13 | right 3, top 4 |
| `Art` | 32×32, 2×2 grid, 13 verts | `(0, 5)` | x −16..16, y −11..21 | side 3, bottom 4 |

Inter-element gaps: rank→stamp **4**, stamp→suit **4**, pip row→art **2**.

Scene lines: [Type 485-489](Cards/card_visual.tscn:485), [Rank 491-499](Cards/card_visual.tscn:491),
[Suit 501-509](Cards/card_visual.tscn:501), [Stamp 511-519](Cards/card_visual.tscn:511),
[Art 521-530](Cards/card_visual.tscn:521).

### 1c. The star rig (16 arms + centre)

Bone positions, in bake order — one walk around the card, top-left first. **This order is
`FxAttachment.measure_outline`'s contract** ([card_visual.gd:201-206](Cards/card_visual.gd:201)).

| Bone | Position | `length` | New position (§7) | New `length` |
|---|---|---|---|---|
| `Bone_Center` | `(0, 0)` | 10 | `(0, 0)` | 10 |
| `Arm_TopLeft` / `TopRight` / `BottomRight` / `BottomLeft` | `(±19, ±25)` | 31.400637 | `(±20, ±27)` | 33.60060 |
| `Arm_Top_1` / `Top_3` / `Bottom_1` / `Bottom_3` | `(±9.5, ±25)` | 26.744158 | `(±10, ±27)` | 28.79236 |
| `Arm_Top_2` / `Bottom_2` | `(0, ±25)` | 25.0 | `(0, ±27)` | 27.0 |
| `Arm_Right_1` / `Right_3` / `Left_1` / `Left_3` | `(±19, ±12.5)` | 22.743132 | `(±20, ±13.5)` | 24.12986 |
| `Arm_Right_2` / `Left_2` | `(±19, 0)` | 19.0 | `(±20, 0)` | 20.0 |

Every bone carries `position` **and** `rest` (identical) — both need editing. Scene lines
[534-663](Cards/card_visual.tscn:534).

### 1d. The two animations

`RESET` ([37-243](Cards/card_visual.tscn:37)) keys every arm at its rest position — a pure mirror
of §1c.

`new_animation_2` (autoplay, looping, [244-451](Cards/card_visual.tscn:244)) is the idle
deformation. Its non-rest keys are what makes a real card "never the 38×50 rectangle":

| Track | Keys | Ratio to rest |
|---|---|---|
| `Arm_TopLeft` | `(-19,-25)` → `(-24.000002,-29.333336)` → `(-19,-25)` | ×1.2632, ×1.1733 |
| `Arm_TopRight` | `(19,-25)` → `(24,-29.333334)` | ×1.2632, ×1.1733 |
| `Arm_BottomRight` | `(19,25)` → `(21.333334,26.66667)` → `(19,25)` | ×1.1228, ×1.0667 |
| `Arm_BottomLeft` | `(-19,25)` → `(-21.333334,26.666666)` | ×1.1228, ×1.0667 |
| `Arm_Right_2` | `(19,0)` → `(21.333334,~0)` → `(16,0)` | ×1.1228, ×0.8421 |
| `Arm_Left_2` | `(-19,0)` → `(-16.000002,~0)` → `(-21.333334,0)` | ×0.8421, ×1.1228 |

**Keep the ratios, not the absolute values** — rescaling by `20/19` and `27/25` preserves the
motion. Getting this wrong is invisible in a still and obvious in motion.

### 1e. The sprite sheets

| Asset | Pixels | Grid | Frame | Change A? | Change B? |
|---|---|---|---|---|---|
| `card_types.png` | 304×400 | 8×8 | **38×50** | ⚠ **RE-AUTHOR → 304×416** (8×8 of **38×52**) | **yes — B′, the outline is what makes it 40×54** |
| `rank_pips.png` | 104×40 | 13×5 | 8×8 | no | outlined by shader |
| `suit_pips.png` | 64×64 | 8×8 | 8×8 | no | outlined by shader |
| `stamp_pips.png` | 64×64 | 8×8 | 8×8 | no | outlined by shader |
| `suit_art.png` | 416×416 | 13×13 | 32×32 | no | outlined by shader |
| `skill_art.png` | 512×512 | 16×16 | 32×32 | no | outlined by shader |

**`card_types.png` is still the only art file that must be redrawn**, and under B′ the job is much
smaller than "redraw at a new size": **the frame width does not change at all** (38 → 38), the
height gains 2 rows (50 → 52), and the hand-painted `#290d2c` perimeter ring comes *out* because
the shader now draws it. What is left is the interior face, which grows 36×48 → 38×52 — i.e. the
old art keeps its proportions and simply reclaims the ring's row plus two new ones.

⚠ **The corner bite is a decision the new art now makes.** Every current frame bites 1 texel per
corner (168 of 172 perimeter texels opaque). Square-cornered art would make the card a true
rectangle, drop the rig outline from 24 points back to 16, and make `SHIPPED_CORNER_NOTCH` zero —
see §2f for why a bite in the art survives the outline intact, and **Q8**.

Grid constants that stay correct (8×8, 13×5, …) but whose *frame size* is re-derived from the
image by `CardModifier.frame_size` ([card_modifier.gd:136](Cards/card_modifier.gd:136)) — so
re-exporting `card_types.png` needs **no code edit**, only a Godot re-import.

Unused-and-unreferenced (verified by grep across `.gd`/`.tscn`/`.tres`): `card_template.png`
(190×50 — five 38×50 frames, a fossil of the old card size), `card_art.png`, `suits.png`,
`deck_thing.png`. They will *look* like they need updating and do not.

---

## 2. The outline shader — what it has to be

### 2a. Why a shader, and why the polygon must still grow

**Every polygon holds 1 art unit of margin past its art, and this part is not a choice.** A
fragment shader can only write inside its own polygon, so the outline needs somewhere to go —
hence **10×10, 34×34 and (under B′) 40×54**, whatever the sheets do.

The two changes reach that margin from opposite directions, which is the whole difference between
them: the **pips and card art keep their frame size and their polygon grows around it**; the
**card face keeps its polygon (it is `CARD_SIZE`) and its frame shrinks inside it**. Same rule
either way — *the frame maps to the polygon's inner rect* — and one shader serves all five.

### 2b. The sampling trap, which is the whole difficulty

`update_polygon_uv_frame` ([card_modifier.gd:147](Cards/card_modifier.gd:147)) maps the polygon's
bounding box *exactly* onto the frame's pixel window. Grow the polygon to 10×10 and the same
mapping stretches an 8×8 frame across 10 units — the art gets 1.25× bigger, not outlined.

The mapping therefore has to be **padded**: a 10×10 polygon maps to a 10×10 *texel* window centred
on the 8×8 frame. But frames are packed edge-to-edge in these sheets, so that window overlaps the
four neighbouring frames — sample it naively and every pip is ringed with slices of its neighbours.
There are two ways to stop that, and they are a real choice.

**DECIDED (owner, 2026-08-04): clamp in the shader. Sheets are NOT padded.** The shader is told
where the real frame ends — a `u_frame_uv` (vec4: min-uv, max-uv) uniform — and every tap outside
it is treated as alpha 0. Both the frame rect and the sheet size are already available from
`CardModifier.frame_rect`; nothing new needs measuring.

Two consequences to carry forward:

- **`update_polygon_uv_frame` needs a padded VARIANT, not an edit.** The existing function is
  shared with prop art (`PropVisual._draw_frame`) and is the project's one definition of sheet
  geometry ([card_modifier.gd:132-137](Cards/card_modifier.gd:132)). Add a second entry point;
  changing this one moves every prop.
- **Neighbour bleed is now prevented by a uniform rather than by construction**, so it is a bug
  that can be introduced and must be *tested* — see §6c. On a padded sheet it would have been
  impossible; that guarantee was the thing traded away.

*Rejected alternative, recorded so it is not re-proposed:* padding every frame with a 1-texel
transparent border (sheets would have become `rank_pips` 130×50, `suit_pips`/`stamp_pips` 80×80,
`suit_art` 442×442, `skill_art` 544×544). It needs no shader clamp and no UV variant, but it fixes
the outline at 1 px forever — a wider outline, a double edge, or any outward-bleeding alert (§2e)
would mean re-packing all five sheets again. The clamp runs unchanged on padded sheets if that ever
changes; the reverse is not true.

### 2c. It must absorb `color_picker.gdshader`

`Assets/color_picker.gdshader` recolours a polygon to one flat palette entry (alpha from the
texture). It is applied by `PipSuit.set_material` ([pip_suit.gd:53](Cards/Pips/pip_suit.gd:53)) to
the **rank pip** and the **card art**. A Polygon2D has one material, so the outline shader has to
do the recolour too, or the two cannot coexist.

That gives the new shader three modes on one uniform:

| Element | Body | Outline |
|---|---|---|
| Rank pip | flat recolour to the suit's palette role | outline colour |
| Card art (suit or skill) | flat recolour to the suit's palette role | outline colour |
| Suit pip | **texture's own colours** (authored in-palette — recolouring flattens its shading, [pip_suit.gd:41-49](Cards/Pips/pip_suit.gd:41)) | outline colour |
| Stamp pip | texture's own colours | outline colour |
| **Card face (Type)** | texture's own colours — **B′, and it has no material at all today** | face rim colour (**Q7**) |

⚠ The `Type` polygon currently carries **no material whatsoever** (`CardModifierType.set_texture`
only reframes UVs — [card_modifier_type.gd:11](Cards/card_modifier_type.gd:11)). B′ makes it a
shader client for the first time, so it needs a material assigned on the same pooled-rebind path as
the rest.

⚠ **The consequence that will bite:** `PipSuit.set_texture` and `CardModifier.set_material`
currently *clear* the material (`polygon2d.material = null` —
[pip_suit.gd:49](Cards/Pips/pip_suit.gd:49), [card_modifier.gd:43](Cards/card_modifier.gd:43)),
deliberately, because these polygons are **pooled and reused across cards** so a stale material
would survive a rebind. After this change *no polygon may be left material-less* — every
`= null` site becomes "assign the outline-only material". Missing one is a pip that silently
loses its outline on some cards and not others, depending on what was bound there before.

### 2d. Cost

Eight neighbour taps per fragment on a 10×10 or 34×34 quad. On a full board that is far below the
fire/glow shaders already shipping (FX_HANDOFF's worst window is 5.82 ms of GPU), but it is *new*
per-card fill in a budget the owner has explicitly paused rather than finished. Worth a number
from `fx_cost.gd` rather than an assumption.

### 2e. Dynamic outlines — the colour is a CARD-level fact, and that inverts today's flow

Owner direction (2026-08-04): **the card's TYPE decides the outline colour, chosen for contrast
against the card's back rather than against the art.** That is the right rule, and it is worth
recording *why*, because the reasoning is not obvious:

The failure being fixed is *element fill = face colour → element vanishes*. An outline that
contrasts with the FACE keeps the element's **silhouette** legible even when its fill matches the
face exactly. Outline = fill is harmless — the art simply reads one pixel bolder. So contrast
against the face is the only contrast that has to be guaranteed, and guaranteeing it once per card
gives one outline colour for every element on that card. **This closes Q1 as originally posed.**

#### The face colour is measurable, not something to author

Measured off `card_types.png`, 2026-08-04, all eight frames:

| Frame | Distinct opaque colours | Dominant | Runner-up |
|---|---|---|---|
| 0 | 3 | `#eddcc0` (1392 px) | `#e71b40` 248 |
| 1 | 3 | `#eddcc0` (1544) | `#9d7900` 180 |
| 2 (TypePaper) | 3 | `#eddcc0` (1560) | `#290d2c` 172 |
| 3 | 3 | **`#e71b40`** (1096) | `#f8c300` **628** |
| 4 | 4 | `#eddcc0` (1056) | `#6e5f62` **536** |
| 5 | 6 | `#eddcc0` (922) | `#290d2c` 303 |
| 6 | 3 | `#eddcc0` (1497) | `#9d7900` 193 |
| 7 | — | empty | — |

Every frame has one clearly dominant fill. So the outline colour can be **derived from the art**
rather than authored per type — and there is an exact precedent for doing exactly that:
`CardModifierType.corner_notch()` ([card_modifier_type.gd:35](Cards/card_modifier_type.gd:35))
reads the sheet's own alpha, caches per frame index in `_notch_cache`, and carries the comment
*"measured off the sheet's own alpha, never typed in (owner 2026-07-29)"*. Same shape: read the
frame's colour histogram, pick the highest-contrast palette entry, cache by frame. **Repainting a
type frame then moves its outline with zero code edits**, which is the whole point when a type may
be any colour.

⚠ **Do not pick against the dominant colour alone.** Frame 3 is 1096 red / 628 yellow and frame 4
is 1056 cream / 536 grey — in both, the runner-up covers a third of the card. Maximise the
*minimum* contrast across every colour above an area threshold, not the contrast against the single
most common one. This is a small pure function and it is testable without rendering anything.

#### Where it gets resolved — this is the structural change

Today every modifier sets **its own polygon's** material
([pip_suit.gd:53](Cards/Pips/pip_suit.gd:53)), and `set_material` builds a fresh
`ShaderMaterial.new()` on every bind. A card-level outline inverts that:

- **`CardVisual.update_visual()` resolves ONE outline spec per card and pushes it to all four
  polygons.** Resolving it inside each modifier means deriving the same fact four times and leaves
  no single place for an override to land.
- **Anything that changes mid-act must go through `set_shader_parameter` on the live material, not
  a rebuild.** The deck viewer is the densest screen in the game (50+ cards × 4 polygons);
  reconstructing materials there mid-frame is a hitch, and the pooled-control rule
  (`_bind_slot` re-derives per-card state) means rebinds are frequent.

#### THE ALERT — the status override, and it is a MODE, not a colour

**Owner direction, 2026-08-04:** statuses *do* override the outline, but not by naming a colour.
The purpose is **UI notification** — "this card's ability is about to fire", a popup-like nudge —
so it must read as an **alert**: dynamic, moving, unmistakably not the resting state. *"Naming a
colour or hue makes no sense. Instead the shader should have an alert switch that can be turned on
by effects then turned back off when the effect is over."*

That resolves **Q6**, and it is a better answer than either option previously listed, because it
sidesteps the objection to both: an alert that is *animated* is distinguishable from the resting
outline **regardless of what colour it lands on**, so the readability guarantee (§2e's contrast
rule) is never traded away to get attention. The two concerns stop competing for one knob.

Design consequences, in order of how likely they are to be got wrong:

1. ⚠ **NO `TIME`.** The built-in is banned project-wide because it ignores the game's own pacing
   ([glow.gdshader:51-52](Shaders/glow.gdshader:51), and `fire.gdshader:125` /
   `juggle.gdshader:24` both declare `uniform float u_time` with the comment *"pacing-aware,
   script-driven — NEVER the built-in TIME"*). The alert needs the same treatment.
2. ⚠ **There is no clock writer on these polygons yet.** `FxAttachment._process` advances `_time`
   as `delta * pacing()` and pushes it ([fx_attachment.gd:936-938, 1066](UI/Fx/fx_attachment.gd:936))
   — but that is the FX *quad*'s material, and the outline lives on the **card's own four
   polygons**. `CardVisual._process` already runs every frame (`_track_fx_outline`), so it is the
   natural writer; **gate it on "any alert active" so a resting board pays nothing**, which is the
   same shape as `set_process(false)` when idle.
3. ⚠ **The alert's period is a fraction of `get_delay()`, never a wall-clock literal.** START_HERE
   rule 4. An "about to activate" cue that does not scale with the pacing/compression settings will
   desync from the cascade it is announcing — which is the one job it has.
4. **On/off must be a SET or a refcount, not a bool.** Two statuses can alert at once, and the
   second one clearing must not switch off the first. `CardVisual` has the exact precedent for the
   hazard in `_spin_holding` / `anim_spin_start` / `anim_spin_stop`
   ([card_visual.gd:608-632](Cards/card_visual.gd:608)) — a hold flag that self-guards.
5. **Statuses should DECLARE it, not push it.** `CardVisual._fx_requests()`
   ([card_visual.gd:173](Cards/card_visual.gd:173)) already collects `status.fx_request()` from
   every status and hands the list to `fx.sync()`, with the standing note that *"CardVisual never
   names an effect — statuses declare their own"*. An imperative `turn_alert_on()` breaks that and
   creates exactly the leak case in 4 (a status freed mid-alert never turns it off). A declared
   alert is re-derived from the live status list every refresh and cannot leak.
6. **Cost is bounded by alert count, not board size.** An alerting card writes uniforms on its
   **five** materials per frame (the Type polygon joined as a client under B′); a resting card
   writes none. Five rather than one because `u_frame_uv` and the fill mode differ per element —
   see **§2e′** for why they cannot share a ShaderMaterial, and for the card-space coordinate that
   makes the five behave as one effect anyway.

**Still open (Q6a):** what the alert *looks like* is not specified and cannot be settled from a
description — it is an eye call under `/fx-verify`. Candidates that fit "no static colour": a
pulse between the resting outline and a second entry, a marching-ants offset around the silhouette,
or a thickness throb. Only the last needs outline width > 1, which §2b's clamp already allows.

#### The "tres resource determining colours per settings"

If the colour is derived (above), the resource needed is **not** a per-type colour map — it is a
small one holding the **candidate palette entries the outline may pick from** plus the minimum
acceptable contrast. That is much smaller than a per-type table and cannot go stale when a type is
repainted.

⚠ Follow the `PaletteRoles` ruling if this becomes a resource: **named `@export` fields, not a
Dictionary** — owner's reason ([palette_roles.gd:12](Scripts/palette_roles.gd:12)) is
autocomplete-visible, compile-checked, inspector-editable. A candidate *set* is naturally an array
of ints, which does not fit that shape; if it ships as an array, say why in the file rather than
letting it read as a lapse.

### 2e′. THE ALERT IS ONE EFFECT ACROSS FIVE POLYGONS — the card-space coordinate

Owner, 2026-08-04: *"ideally glare band matches between all outlines in one card, so that position
of glare band makes it look like 1 single glare."* Without this, each polygon sweeps its own local
extent and a card shows **five independent glares** — a pip's band crossing 10 units in the time
the card's crosses 40.

#### Why the materials cannot simply be shared

The owner's first proposal — *"make all outlines on a card use the exact same shader outline"* — is
already true at the level that matters: **one `.gdshader`, five clients** (§2c). Sharing one
`ShaderMaterial` *instance* is what does not work, and the reason is exactly two uniforms:

- `u_frame_uv` — a different frame of a different sheet per element;
- the fill mode — rank and card art are recoloured to the suit's role, suit pip / stamp / type draw
  their own colours ([pip_suit.gd:41-49](Cards/Pips/pip_suit.gd:41)).

Godot exposes no per-instance uniform for `Polygon2D` (`INSTANCE_CUSTOM` is MultiMesh/particles
only). ⚠ Note the *sheet* difference alone would NOT have blocked sharing — `TEXTURE` is a property
of the CanvasItem, not the material — so it is the uniforms and only the uniforms.

#### The fix, and why it is one `vec2`

The owner's second proposal is the right one: *"have outline shaders know their own position in
card space, so all shaders simulate their positional data as if on full type art, but outline only
reveals the portion around where art is."*

**It costs one static `vec2` per polygon, because 1 texel = 1 art unit makes local→card a PURE
TRANSLATION with no scale** (`test_fx_pixel_is_the_games_pixel`). The values are already in the
scene — they are the node positions: Rank `(-12,-18)`, Stamp `(0,-18)`, Suit `(12,-18)`, Art
`(0,6)`, Type `(0,0)`.

```glsl
vec2 card_pos = (UV - 0.5) * u_extent + u_card_offset;
float glare   = band(card_pos.x, clock);   // one function, one coordinate, all five polygons
```

✅ **"Reveals only the portion around where art is" is then automatic** — the glare modulates the
OUTLINE's colour, and the outline exists only where that element's art has an edge. Each element
shows exactly the slice of the card-wide band that crosses its own rim. The bounce endpoints become
the card's own edges (±20) for free, instead of five different pairs of endpoints.

#### Card space, NOT world space

The owner said "world space", but described coherence — and card space delivers that while world
space adds noise. A card deforms continuously (the idle rig), bobs (`visual.position.y`), tilts
from its own motion (`rotation_degrees`), and can spin a full revolution (`anim_spin_start`). A
world-aligned band lets all of that slide the glare around independently of the card, and on a spin
it strobes. Card space paints the glare **on** the card and lets the skinning carry it — consistent
with the outline itself being texture-space (§2f(3)).

⚠ It also means `card_pos` is the **rest** card space (UV plus a static offset), not the deformed
one. That is correct AND it is the only option: reading true deformed position needs a varying from
the vertex stage, and §2f(3) forbids writing a `vertex()` at all. The two constraints agree.

**Three spaces now live in this stack, and each is deliberate:**

| What | Space | Why |
|---|---|---|
| Outline neighbourhood | **texture** | the rim rides the art through deformation (§2f(3)) |
| Alert glare | **card** | one band across five polygons (here) |
| Fire / glow FX | **world** | pixels must not crawl under a moving card (`fx_common`) |

#### Two consequences to know before tuning

- **A pip is 10 units of a 40-unit sweep, so pips FLASH for ~25 % of the pass** rather than glowing
  steadily. That *is* "one single glare" — but it is a different read from a per-element glare, and
  it is the thing to look at first on the §11 tool.
- **Band thickness is now a card-space quantity.** A band thin enough to look right on the card's
  40-unit rim may barely register on a 10-unit pip. If it cannot be made to serve both, the escape
  hatch is a per-host thickness scale — one more uniform, and §11 is where that gets decided.

#### Cost

The alert's per-frame writes are the clock (and phase) on five materials per alerting card. Alerts
are brief and rarely simultaneous, so this is negligible and needs no cleverness. ⚠ If many cards
ever alert at once, the escape hatch is a **global shader uniform** for the clock
(`RenderingServer.global_shader_parameter_set`), leaving only per-card *state* on the materials —
but the project uses no global shader parameters today (verified 2026-08-04), so that would be a
new mechanism and should not be introduced speculatively.

### 2f. The card face as an outline client (B′) — three findings

#### (1) The mapping generalises; ONE line of existing code stops being true

Every outline client now shares one rule: **the source frame maps to the polygon's INNER rect, and
the polygon extends 1 art unit past it on all four sides.** 8×8 art in a 10×10 polygon, 32×32 in
34×34, and now 38×52 in 40×54. Same padded mapping, same frame-rect clamp, one shader.

⚠ **But `_bind_rig`'s texel conversion breaks, and it breaks quietly.**
[card_visual.gd:301-306](Cards/card_visual.gd:301) computes

```gdscript
var per_texel := CARD_SIZE / Vector2(maxf(frame_px.x, 1.0), maxf(frame_px.y, 1.0))
```

which was exactly `1.0` only because the type frame *was* `CARD_SIZE`. Under B′ it becomes
`(40,54) / (38,52)` = **(1.0526, 1.0385)** and silently inflates the corner notch by ~4–5 %, with
a comment above it still asserting the value is 1.0 on a card. It must divide by the **inner** rect
(`CARD_SIZE - 2 × outline`), not by `CARD_SIZE`. This entry was listed as safely *derived* in an
earlier pass of this document; B′ makes it a must-change, and it is the single most likely thing to
be missed because nothing about it looks size-dependent.

#### (2) A 1-px dilation preserves a corner bite EXACTLY — so the FX mask survives

The worry: the FX mask is built from the type frame's alpha via `corner_notch()`
([card_modifier_type.gd:35](Cards/card_modifier_type.gd:35)), which now measures the *un-outlined*
38×52 art while the drawn silhouette is that art dilated by 1. Do they still agree?

They do, and it is exact rather than approximate. Put the art at offset (1,1) in the 40×54 card
frame and let the art bite an N×M rectangle out of its corner. A card texel `(cx, cy)` is covered
iff some opaque art texel lies within Chebyshev distance 1 of it — i.e. iff some `(ax, ay)` with
`ax ≥ N or ay ≥ M` satisfies `ax ∈ [cx-2, cx]`, `ay ∈ [cy-2, cy]`. Taking the largest candidates,
the corner texel stays clear exactly when `cx ≤ N-1` **and** `cy ≤ M-1`. **That is an N×M clear
rectangle in card space — the same N×M the art bit.**

So `corner_notch()` returns the right number, `SHIPPED_CORNER_NOTCH := Vector2.ONE` stays correct
*provided the new art keeps its 1-texel bite* (**Q8**), and the fix in (1) is the only change the
mask needs. Worth a unit test, since the result is exact and therefore cheap to assert.

#### (3) The rig and the outline compose cleanly — because skinning moves VERTICES, NOT UVs

All five polygons are skinned to the star rig (they carry `bones` weight arrays), so the question
is whether an animated card's outline still reads as part of its art. **It does, and the mechanism
is why:** Polygon2D bone weights transform vertex *positions*; each vertex keeps its UV. The
fragment shader therefore sees the same UV↔texel correspondence at rest and fully deformed. The
outline is computed in texture space and the deformed geometry carries it exactly as it carries the
art.

Four conditions make that true. Three are guards, one is already satisfied:

1. ⚠ **Tap in UV space via `TEXTURE_PIXEL_SIZE` — never `SCREEN_UV` or `FRAGCOORD`.** A
   screen-space neighbourhood holds a constant *screen* thickness while the art stretches, so the
   rim detaches from the drawing. Worst at the corners: `Arm_TopLeft` swings to ≈`(-25.3, -31.7)`
   at the new size, a ~26 % stretch. (Note this is the OPPOSITE of the rule the FX shaders follow —
   fire and glow deliberately quantize on a world-aligned grid so their pixels do not crawl under a
   moving card. Different job: those effects are not attached to the art's texels, and this is.)
2. ⚠ **Write no `vertex()` function.** The outline is pure fragment work and needs none. Godot
   applies 2D skinning in the vertex stage, and a custom `vertex()` is the one way to interfere
   with it — not having one removes the question entirely.
3. ⚠ **Nearest filtering, no mipmaps**, or the taps blur and the frame-rect clamp starts leaking
   fractional texels from neighbouring frames — the two failure modes arrive together.
   ✅ **Already correct, verified 2026-08-04:** `textures/canvas_textures/default_texture_filter=0`
   (Nearest) in `project.godot:92`, and `mipmaps/generate=false` on `card_types`, `suit_pips`,
   `suit_art` and `rank_pips`. This is a *don't regress* item, not a task.
4. **"The outline is exactly 1 unit" is a REST-POSE claim.** Deformed, the rim thickens with its
   cell — which is the behaviour to want; a rim that stayed 1 unit while the art stretched is what
   would look wrong. But a test asserting thickness must pin the pose: `new_animation_2` is on
   autoplay, so a card shot on instantiation catches an arbitrary frame. Same trap
   `test_the_card_mask_is_the_card_the_player_sees` documents at
   [card_visual.gd:224-236](Cards/card_visual.gd:224).

✅ **And the FX mask needs no change at all** — which is a consequence of B′ being framed as
*shrink the art, keep the polygon* rather than *keep the art, grow the polygon outward*. The
outline lives INSIDE the 40×54 polygon, so `_rig_outline()`'s arm tips at ±20/±27 already bound the
drawn silhouette exactly. Under the other framing the rig would have been 2 units short on every
side and every flame would have rooted itself inside the rim.

#### (5) ⚠ THE MASK DOES NOT FOLLOW THE ART — so "outline off" leaves the FX hovering

The agreement in (4) is **luck, not a mechanism**, and it is worth writing down before it is relied
on. If the outline were ever disabled, the drawn art shrinks to 38×52 while the mask still says
40×54: **every effect would root itself 1 art unit off the art on all four sides** — 2.5 screen px
at the default `card_scale`, against a fire that reaches 7 units, so about a seventh of the flame
height standing on nothing. It would not snap to the smaller art.

**Why:** a card's mask is **geometry-derived**. `_ready` calls
`fx.measure_outline(_rig_outline())` ([card_visual.gd:404](Cards/card_visual.gd:404)) — Bone2D
positions, which know nothing about what a shader painted — and the no-rig fallback is
`fx.measure_silhouette(type.polygon)`, also geometry. Cards configure as `Shape.BOX`
([card_visual.gd:397](Cards/card_visual.gd:397)); the alpha-sampling path
(`measure_sprite_silhouette`) exists but only props use it.

The one hybrid piece makes it slightly worse rather than better: `corner_notch()` **does** read the
sheet's alpha, so the corner bite would keep being measured off the 38×52 art while the rectangle
it is applied to stays 40×54 — the corners err in the same direction, not compensating.

**And this is still the right architecture.** The rig is what *deforms*; alpha can describe the
shape at rest but cannot say where it went when `Arm_TopLeft` swings out 26 %. Reading the mask
from the rig is what makes flames track a bending card at all — the fix for a silhouette baked once
leaving flames on a shape the card no longer had. Do not "fix" this by masking from alpha.

**Proportionate fix — make the coupling explicit instead of coincidental:**

```gdscript
const CARD_ART_SIZE := Vector2(38, 52)   # what the sheet frame actually is
const ART_OUTLINE   := 1.0               # the shader's rim, in art units
const CARD_SIZE     := CARD_ART_SIZE + Vector2.ONE * ART_OUTLINE * 2.0   # 40x54
```

…with the mask insetting by `ART_OUTLINE` when it is zero. Worth doing even though it ships at 1
and nobody plans to change it: today the mask and the drawn edge agree only because the outline
happens to fill the polygon exactly, and nothing in the code says so.

⚠ **It does not buy a one-line "remove the outline", and should not be sold as one.** The 16 bones
are authored in `card_visual.tscn`, not derived from any constant, so a real removal is still a
scene edit plus a skin re-bake (§8 step 5). The constant makes the shader and the mask follow; the
skeleton cannot.

#### (4) …and the colour rule has become circular

§2e resolved the outline colour as *"the type picks it, for contrast against the card's back."*
**The card's back IS the type art** — so the type's own outline cannot contrast against it. This is
a new fork, and it is not cosmetic: it decides how many outline colours a card carries.

- **(a) One ink per card.** The same colour rims the face and everything on it. Simplest, reads as
  a coherent object. But the face rim wants contrast against *the background and neighbouring
  cards*, while the element outlines want contrast against *the face* — one colour cannot be
  chosen for both, so one of the two guarantees is given up.
- **(b) Two colours, one uniform apart.** `face_outline` (contrast vs. what is behind the card) and
  `art_outline` (contrast vs. the face). Both guarantees hold, and it is one extra uniform on a
  shader that already carries several.
- **(c) The face rim is a fixed role**, on the grounds that what is behind a card is board
  background and other cards — a bounded, known set — while the face is arbitrary. Cheapest, and
  the current art effectively already does this (every frame's ring is the same `#290d2c`).

⚠ Whatever wins, note that cards **stack with only `CARD_SEPARATION` visible** — a card's rim is
usually against another card's face, not against the board. (c)'s premise should be checked against
that before it is taken as obvious. See **Q7**.

---

## 3. Impact — code

Everything below is grouped by whether it needs an edit. **Derived** entries are listed precisely
so nobody "fixes" them.

### 3a. Must change

| File | What |
|---|---|
| [card_visual.gd:7](Cards/card_visual.gd:7) | `CARD_SIZE := Vector2(40, 54)` — preferably as `CARD_ART_SIZE + 2 × ART_OUTLINE`, so the mask/shader coupling is stated rather than coincidental (§2f(5)) |
| [card_visual.gd:8](Cards/card_visual.gd:8) | `CARD_SEPARATION` **14 → 16** (D4). The outlined pip row ends 14 units below the card's top edge (4 margin + 10 pip); +2 clearance for the idle animation = 16 |
| [play_area.tscn:78](UI/play_area.tscn:78) | `Vector2(14, 14)` — the separation literal written into the scene. **Must follow to 16**, and it is the one copy the constant does not reach |
| [card_visual.gd:110-113, 196, 372-380](Cards/card_visual.gd:110) + `Cards/Statuses/status_layer.gd` | **DELETE the StatusLayer** (D5) — icons and stack counts come off the card entirely |
| [card_modifier_status.gd:75-76](Cards/card_modifier_status.gd:75) | `draw_icon` and its "un-arted status shows its count label" contract go with it |
| [card_visual.tscn](Cards/card_visual.tscn) | Type polygon → 40×54; Rank/Stamp/Suit → 10×10 at new y; Art → 34×34 at new y; **all 16 bone `position` + `rest`; both animations; all five polygons' `bones` weight arrays re-baked** |
| `Assets/card_types.png` | re-author at **304×416** (8×8 frames of **38×52**), painted `#290d2c` ring removed, + re-import — B′, §1e |
| [card_visual.gd:301-306](Cards/card_visual.gd:301) | ⚠ `per_texel` must divide by the **inner** rect (`CARD_SIZE − 2×outline`), not `CARD_SIZE`. Quiet ~5 % error otherwise — **§2f(1), the likeliest miss in this whole change** |
| [card_visual.gd:262](Cards/card_visual.gd:262) | `SHIPPED_CORNER_NOTCH` — stays `Vector2.ONE` **only if** the new art keeps its 1-texel bite (Q8, §2f(2)) |
| `Assets/color_picker.gdshader` | superseded by / folded into the new outline shader |
| [pip_suit.gd:46,53,64](Cards/Pips/pip_suit.gd:46) | `set_texture` / `set_material` / `set_art_texture` build the outline material instead of clearing it |
| [card_modifier.gd:43](Cards/card_modifier.gd:43) | base `set_material` no longer sets `null` |
| [card_modifier.gd:147](Cards/card_modifier.gd:147) | needs a padded-window variant (§2b) — **or** a second function; do not change the existing one silently, `PropVisual._draw_frame` and every prop shares it |
| [palette_roles.gd:22-46](Scripts/palette_roles.gd:22) | new `art_outline` role + `ROLE_NAMES` entry |
| `Assets/Palette/roles.tres` | the chosen index |
| [fire.gdshader:123](Shaders/fire.gdshader:123), [glow.gdshader:84](Shaders/glow.gdshader:84) | `u_body` **defaults** `vec2(38,50)` → `vec2(40,54)`. Cosmetic only — `FxAttachment` writes the real value every frame ([fx_attachment.gd:376,826](UI/Fx/fx_attachment.gd:376)) — but a wrong default is a wrong default |
| [fx_editor.gd:108](Tools/fx_editor.gd:108) | `@export var card_body := Vector2(38, 50)` |
| [hoop.tres:8](Cards/Props/Formations/hoop.tres:8) | formation points span exactly ±19 (the old card edge) → ±20 |
| [formation_editor.tscn:7](Tools/formation_editor.tscn:7) | same points, duplicated in the editor scene |

### 3b. Derived — verified correct, do not touch

- `card_size_play`, `card_separation_play`, `card_separation_play_custom`, `card_jump_rise_play`
  ([card_visual.gd:39-52](Cards/card_visual.gd:39)) and `recalculate_size`
  ([:431](Cards/card_visual.gd:431)).
- `CARD_JUMP_RISE = CARD_SIZE.y / 5.0` → 10.0 becomes 10.8. The hoop prop rides it via
  `rides_card_jump` ([prop_visual.gd:34](Cards/Props/prop_visual.gd:34)) and follows for free.
- `status_layer.position = (-CARD_SIZE.x*0.5 + 3, -CARD_SIZE.y*0.5 + 3)`
  ([card_visual.gd:375](Cards/card_visual.gd:375)) → `(-17, -24)`. ⚠ It already overlaps the rank
  pip today and will overlap the rank pip's *outline* after; pre-existing, but now visible against
  a hard edge. See **Q5**.
- ~~`_bind_rig`'s `per_texel = CARD_SIZE / frame_px`~~ — **MOVED TO §3a.** It was derived-and-safe
  while the type frame equalled `CARD_SIZE`; under B′ it does not, and it silently inflates the
  corner notch. See §2f(1).
- `notch_fraction` / `corner_points` / `star_outline` / `_rig_outline`
  ([card_visual.gd:237-347](Cards/card_visual.gd:237)) all take `body` as a parameter.
- `CardModifierType.corner_notch` ([card_modifier_type.gd:35](Cards/card_modifier_type.gd:35))
  measures the bite off the sheet's own alpha and caches per frame — it re-measures the new art
  automatically. ⚠ But `SHIPPED_CORNER_NOTCH := Vector2.ONE` is a hand-written default used by
  every harness; if the redrawn frames bite differently, that constant is wrong and only the
  harness panels will show it.
- `ControlCard.set_min_size` ([control_card.gd:23](UI/control_card.gd:23)) reads `child.card_size`.
- All of `play_area.gd`'s slot sizing (lines 226-683) goes through `card_size_play`.
- `prop_layer.gd` reach/pitch (lines 177, 566) likewise.
- `PropFormationSet.strip_ratio` / `norm_to_strip`
  ([formation_set.gd:44-69](Cards/Props/formation_set.gd:44)) normalise by `CARD_SIZE.y`;
  `formation_editor.gd:13,105` take `CARD` and `column_pitch` from `CARD_SIZE`.
- `FxAttachment._size_quad` ([fx_attachment.gd:723](UI/Fx/fx_attachment.gd:723)) sizes to the live
  circumscribed diagonal — see §5 for the number it produces.
- `PropVisual.art_size_for` ([prop_visual.gd:107](Cards/Props/prop_visual.gd:107)) reads frame size
  from the image; `AUTHORED_CARD_SCALE`/`ART_PIXEL_SCALE` are about *props*, not card size.

### 3c. Scene values worth a look, not necessarily an edit

- [game_view.tscn:337,356,376](Levels/game_view.tscn:337) — the Deck / Discard / Rules anchors are
  `custom_minimum_size = Vector2(100, 100)`. Cards only take their *centre*
  (`get_control_center`), so nothing breaks; but a card is 100×135 now, not 95×125, and these
  panels read as card-sized slots.
- [play_area.tscn:78](UI/play_area.tscn:78) — `Vector2(14, 14)`, the `CARD_SEPARATION` literal
  written into the scene rather than read from the constant.
- [play_area.tscn:71](UI/play_area.tscn:71) — `split_offsets = PackedInt32Array(38)`. Coincidence,
  not the card width: it is a split-container offset. Do not "fix" it.

---

## 4. Impact — the palette

`PaletteDB` / `PaletteRoles` is the one place a colour is named
([palette_db.gd](Scripts/palette_db.gd), [palette_roles.gd](Scripts/palette_roles.gd)).

⚠ **What gets added here depends on Q1a.** If the outline colour is *derived* per type (§2e, the
recommendation), what the palette owes is not one role but the **candidate set** the contrast
function may pick from — see §2e's last note on the `PaletteRoles` named-fields ruling. If it is
*authored* per type, it is one role per type, or one role plus a per-type override.

The list below is the single-role shape, which is the floor either way — a derived pick still wants
a documented fallback for a type whose histogram is degenerate (frame 7 is empty):

1. a new `@export_range(0,255,1) var art_outline : int` in the **right group** (a new
   `@export_group("Art")`, since it is neither a suit nor a status nor an effect);
2. its name appended to `ROLE_NAMES` ([palette_roles.gd:42](Scripts/palette_roles.gd:42)) — the
   list every preview, the range test and any iteration reads;
3. the index set in `Assets/Palette/roles.tres`;
4. `Tests/Engine/test_palette.gd` iterates `ROLE_NAMES` for range validity — it picks the new role
   up automatically and will fail if the index is out of the palette's width;
5. `ARCHITECTURE_REVIEW §4i` documents the role map.

Roles must be named for **meaning, never colour** (`palette_roles.gd:8-10`) — `art_outline`, not
`black`.

---

## 5. Impact — FX and the mask

Nothing in the FX layer is hardcoded to 38×50; it all flows from `configure(CARD_SIZE, …)`
([card_visual.gd:397](Cards/card_visual.gd:397)) and from the live rig outline. What changes is
the **numbers**, and FX performance is a paused-not-finished workstream, so they matter:

| Quantity | 38×50 | 40×54 | Δ |
|---|---|---|---|
| Card diagonal, `body.length()` — the rotating quad's bound ([fx_attachment.gd:745](UI/Fx/fx_attachment.gd:745)) | 62.80 | **67.20** | +7.0 % |
| Card FX quad, `diag + 2×(reach+margin)`, taking FX_HANDOFF's measured 84.8² as the baseline | 84.8² | **~89.2²** | **+10.7 % fill** |
| Card area | 1900 u² | 2160 u² | +13.7 % |
| Art square (the spotlight circle's subject) | 32×32 | **34×34 with outline** | +6.25 % |

Consequences:

- **The spotlight circle's radius is wrong.** `u_circle_radius = 16.0`
  ([glow.gdshader:104](Shaders/glow.gdshader:104), and the comment at
  [:290-292](Shaders/glow.gdshader:290) says in as many words that 16 units over a 32×32 art square
  "covers the whole picture and nothing else"). With the outline the picture is 34×34, so the
  circle now clips its own subject's outline. Design side: `design/spotlight/DESIGN.md` §14b
  (lines 517-518, 1693, 1826) and **Q217**; style side: `Shaders/Styles/glow_circle.tres` and
  [fx_glow_style.gd](UI/Fx/fx_glow_style.gd).
- **Every FX budget number in `FX_HANDOFF.md` is stated for a 38×50 card** (§0d.10's lever list,
  the 84.8² quad at §1682, the 2.1× `body_near` win at §1616, the area arithmetic at §958). They do
  not become wrong, they become *stale by ~12 % of fill*. Re-measure with `fx_cost.gd` before
  spending any of that budget again.
- `FxGlowStyle`'s `reach` default of 4 is documented against "a card is 38×50 art units"
  ([fx_glow_style.gd:76](UI/Fx/fx_glow_style.gd:76)) — the prose, at minimum.

---

## 6. Impact — tests

### 6a. Will fail, by construction

| Test | Why |
|---|---|
| **`test_pixels.test_one_pixel_size_for_all_art`** ([test_pixels.gd:414](Tests/Visual/test_pixels.gd:414)) | It renders the card's **suit pip** and the **Ball prop** and asserts their pixel footprints are *equal*. Both draw the same 8×8 `suit_pips.png` frame. **Q3 is answered — props get no outline** (§6d), so the card pip's footprint gains 1 art unit on every side where art touches and the prop's does not. The equality is now false by design and the check must be **restated, not relaxed** — see below. |

**How to restate it, without weakening it.** The claim the owner actually cares about
([prop_art_snapshot.gd:61](Tests/Visual/prop_art_snapshot.gd:61), owner 2026-07-27) is *"a prop
texel is the same size as a card texel at every `card_scale`"* — a statement about **scale**, which
the equality was only ever a convenient proxy for. Since the outline is exactly 1 art unit on each
side, the exact relation is:

```
box_pip.size == box_prop.size + Vector2(2, 2) * card_scale
```

That is **stronger** than the old check, not weaker: it still pins pixel-size parity at every
`card_scale`, and it additionally pins the outline at exactly one art unit — catching a 2-px or
half-px outline that the old equality could not have seen either. Do not replace it with a
tolerance.
| **`test_pixels.test_the_card_mask_is_the_card_the_player_sees`** ([test_pixels.gd:578](Tests/Visual/test_pixels.gd:578)) | It fits `star_outline` to the *real* animated rig and records the closest `warp` (documented at [card_visual.gd:224-236](Cards/card_visual.gd:224) as "off by 2.3 to 3.3 art units at four points"). Rescaling the animation keys rescales that residual. The recorded numbers in the comment become wrong. |
| Every **snapshot** harness — `fx_snapshot`, `prop_art_snapshot`, `fx_behind`, `fx_cost` | Their panels are card-sized. Every image changes. Per `/fx-verify` and CLAUDE.md rule 4, these must be **re-rendered and looked at**, not diffed to green. |

### 6b. Derived — will pass without edits, but the *images* change

`test_fx_attachment.gd` (lines 400, 518, 548, 582 — all `CardVisual.CARD_SIZE`),
`test_visual_layers.gd:615`, `test_ui_props.gd` (lines 339, 599, 662, 706, 739, 788-886 — the
formation-strip maths, all normalised by `CARD_SIZE.y`).

### 6c. Needs new coverage

- The padded UV window (§2b) samples **only** inside its own frame: a pip next to a
  non-transparent neighbour frame in the sheet must show no neighbour pixels.
  ⚠ **Correcting an earlier draft of this note**, which warned the bug would be "invisible on a
  sparse sheet". Measured: **13/13 rank, 18/19 suit-pip and 3/3 stamp frames have art touching
  their frame edge**, and those sheets are densely packed — so a missing or wrong clamp is *loud*,
  garbage on nearly every pip in the game. It is the 32×32 sheets that are sparse (2/52 `suit_art`,
  5/12 `skill_art` touch an edge), so **that** is where a subtle clamp error could hide. Test both,
  and expect the pip sheets to fail obviously and the art sheets to fail quietly.
- The outline is **8-directional and exactly 1 unit**: diagonal-only contact must produce a corner
  pixel. A 4-tap implementation passes a naive "is there an outline" check and fails this.
- The outline sits *outside* the source alpha and never eats a source pixel.
- **The alert is off by default and returns to rest.** A status that alerts and is then removed
  leaves the card's outline exactly as it was before — the leak case §2e.4 warns about, and the one
  a declared (rather than pushed) alert is supposed to make impossible. Assert it by removing the
  status, not by calling an "off" method.
- **Two simultaneous alerts:** clearing one leaves the other alerting.
- **The corner-bite identity (§2f(2)):** art biting N×M produces a drawn silhouette biting N×M.
  Exact, so assert it exactly, across every non-empty type frame.
- **`per_texel` is 1.0 art unit per source texel** for the type frame under the inner-rect
  mapping (§2f(1)). One line, and it is the guard on the thing most likely to be missed.
- **The outline rides the rig** (§2f(3)): at a DEFORMED pose the rim must still hug the art with no
  gap and no detachment. A screen-space tap passes every rest-pose check and fails only here, so
  this is the discriminator for the one mistake that would make animated cards look wrong. Pin the
  pose (`rig_pose`, as `fx_editor` does) rather than shooting an autoplaying card.

### 6d. Props are explicitly OUT of scope for the outline

**Owner, 2026-08-04: props get no outline — they are temporary, so they do not need the same level
of readability.** This is a scope boundary, not an oversight, and it wants to be written where the
next person will trip over it:

- `ball_visual.gd` / `fire_visual.gd` draw the **same `suit_pips.png` frames** as the card's suit
  pip ([ball_visual.gd:16](Cards/Props/Visuals/ball_visual.gd:16),
  [fire_visual.gd:14](Cards/Props/Visuals/fire_visual.gd:14)). Sharing a sheet with an outlined
  element and deliberately not being outlined is exactly the kind of asymmetry that reads as a bug
  later — put the reason in the code, next to `PropVisual.art_size_for`.
- It also means `PropVisual.art_size_for` ([prop_visual.gd:107](Cards/Props/prop_visual.gd:107))
  needs **no padding** and `ART_PIXEL_SCALE` / `AUTHORED_CARD_SCALE` are untouched. Props keep
  drawing `frame_px * 2.5` exactly as today.
- The consequence for the one shipping test that compares the two is in §6a, and the restated
  check is *stronger* than the one it replaces.

---

## 7. Proposed new geometry

Derived so that **every margin the card has today survives, measured to the outline**. X centres do
not move at all; only two Y centres shift.

Card 40×54, half-extent (20, 27):

**AUTHORED BY THE OWNER, 2026-08-04**, as two runs across the card. These are the numbers; the
table below is them resolved into node positions.

```
across (x):   3 | 10 | 2 | 10 | 2 | 10 | 3   = 40
down   (y):   4 | 10 | 2 |     34     | 4    = 54
            marg  pip  gap    art      marg
```

*(The owner's note wrote the vertical run as "= 52"; it sums to 54, which is the card height and is
what the terms describe. Recorded as 54 — the layout is right, the total was a slip.)*

| Node | Polygon | Position | Source art box | **Outlined box** | Margin |
|---|---|---|---|---|---|
| `Type` | **40×54** | `(0, 0)` | **38×52**: x −19..19, y −26..26 | x −20..20, y −27..27 | — (the outline *is* the rim) |
| `Rank` | **10×10** | `(-12, -18)` | x −16..−8, y −22..−14 | x −17..−7, y −23..−13 | left **3**, top **4** |
| `Stamp` | **10×10** | `(0, -18)` | x −4..4 | x −5..5 | top **4** |
| `Suit` | **10×10** | `(12, -18)` | x 8..16 | x 7..17 | right **3**, top **4** |
| `Art` | **34×34** | `(0, 6)` | x −16..16, y −10..22 | x −17..17, y −11..23 | side **3**, bottom **4** |

Gaps between *outlines*: rank→stamp **2**, stamp→suit **2**, pip row→art **2**.

⚠ **The 10×10 blocks are FULL, not nominal** — measured 2026-08-04: **13 of 13** rank frames, **18
of 19** suit-pip frames and **3 of 3** stamp frames have art touching their frame edge. So an
outlined pip really does occupy its whole 10×10, the 2-unit gaps really are 2 units of clear space,
and this layout has no hidden slack in it. (The 32×32 art is the opposite — only 2 of 52 `suit_art`
frames touch an edge — so the art square's outline usually hugs a shape well inside its box.)

**A note on the pip row and `CARD_SEPARATION`:** the outlined pip row now ends **13** units below
the card's top edge (it was 12). `CARD_SEPARATION = 14` is the strip of a covered card that stays
visible, so the pip row still fits — with 1 unit of clearance instead of 2. **Q4.**

---

## 8. Suggested order of work

Each step leaves the game runnable and is verifiable on its own. This is the sequence, not a plan —
a plan owes per-step done-when and acceptance gates.

1. **The colour plumbing.** Per D7 this is now small: one `art_outline` palette role defaulting to
   index **28** (`#290d2c`, today's painted ring), an optional per-type override, and the card-level
   resolution in `CardVisual.update_visual` (§2e). **No histogram, no solver** — D7 rejected them.
   Half a day, and it makes step 2 a pure rendering problem.
2. **The RESTING outline shader, against the current 38×50 card.** Build it, wire the padded-UV
   variant of `update_polygon_uv_frame` and the frame-rect clamp (§2b), grow *only the pip and art
   polygons* to 10×10 / 34×34 — they still fit inside a 38×50 face (margins drop to 2/3/3, ugly but
   valid). One outline-colour uniform (D7). The Type polygon is a client from this step on (§2f),
   so the padded mapping is written once and used by all five. **No alert behaviour yet**, but
   declare `u_alert_kind` / `u_alert_color` now (D6) so step 6 does not re-shape the material.
   ⚠ **Build the §11 atlas tool in this step, not later** — it is the only surface on which an
   authored ink can be judged, and every step after this one is easier with it running.
   Props are untouched (§6d); restate
   `test_one_pixel_size_for_all_art` per §6a in the same step that breaks it. This isolates the
   hard part from the geometry churn and lets the neighbour-bleed test be written and *looked at*
   before anything else moves.
3. **Re-author `card_types.png` at 304×416** (38×52 frames, painted `#290d2c` ring removed — §1e).
   Re-import. **Fix `per_texel` in the same commit** (§2f(1)) — the art change is what makes the
   old expression wrong, and separating them leaves a window where the notch is quietly off.
   Then verify `corner_notch` reports the bite the new art actually has, and settle **Q8**.
4. **`CARD_SIZE` → `(40, 54)` and the scene geometry.** Type polygon, pip/art positions per §7,
   all 16 bones (`position` **and** `rest`), both animations rescaled by the §1d ratios, `hoop.tres`
   points, `formation_editor.tscn` points.
5. **Re-bake the meshes and skin weights.** The editor tool buttons on `CardVisual` —
   "Bake Selected Mesh & UVs" per polygon, then "Generate Star Skeleton & Bind".
   ⚠ **Two traps in the bake tool**: it does `add_child(skeleton)` on the CardVisual *root*
   ([card_visual.gd:807](Cards/card_visual.gd:807)) while the shipped scene keeps `Skeleton2D`
   under `Offset/Visual` — and `_bind_rig` looks it up at
   `Offset/Visual/Skeleton2D/Bone_Center` ([:292](Cards/card_visual.gd:292)). It also
   `queue_free`s the existing skeleton, which orphans both animations' track paths until the
   regenerated bone names match (they will, at `edge_subdivisions = 3`). Re-parent and re-check
   the animation tracks after baking.
   ⚠ And per START_HERE rule 1: **the editor rewrites `.tscn`/`.tres` on disk.** Re-read from disk
   before diagnosing anything after this step.
6. **The alert.** The declaration path (statuses declare, `CardVisual` collects — §2e.5), the
   gated per-frame clock on `CardVisual._process` (§2e.2), the `get_delay()` fraction (§2e.3), and
   the set/refcount (§2e.4). Last because it depends on nothing above it and is the only step whose
   *appearance* cannot be settled from a spec — Q6a is an eye call under `/fx-verify`. Everything
   before this point is testable without one; keeping them apart means a failed look call here does
   not strand the geometry work.
7. **Shader defaults + docs literals** (§3a bottom, §5, §10's doc list).
8. **Full suite, then `/fx-verify`.** The suite is the floor. The snapshot images are the actual
   evidence and must be looked at — CLAUDE.md rule 4.

---

## 9. Decisions — all settled 2026-08-04

Nothing in this feature is now blocked on the owner. Recorded as decisions with their reasoning,
because the reasoning is what a later session needs in order to know when a decision may be
revisited.

| # | Decision | Consequence lives in |
|---|---|---|
| **D1** | Card is **40×54**; art elements occupy **10×10 / 34×34**; type art **38×52** | §0, §1, §7 |
| **D2** | Outline drawn by shader with a **frame-rect clamp**; sheets are **not** padded | §2b |
| **D3** | **Props get no outline** — they are temporary | §6d |
| **D4** | `CARD_SEPARATION` **14 → 16** | §3a, D4 note below |
| **D5** | **Status icons deleted from the card entirely** | §3a, D5 note below |
| **D6** | Statuses override the outline via an **alert mode**, not a colour | §2e |
| **D9** | The alert is **one effect across five polygons**, made coherent by a card-space coordinate (one static `vec2` per polygon) — not five local sweeps | §2e′ |
| **D7** | **One outline colour per card**, authored on the type, defaulted | D7 note below |
| **D8** | Type art **keeps its 1-texel corner bite** | §2f(2) |

### D7 — the colour: AUTHORED with a default, one ink per card

**Owner: *"allow authoring with default to same one colour if no authoring, I don't trust
derived"*, and Q7 = one ink.** So:

- **No histogram, no contrast solver, no candidate set.** The derived scheme argued for in an
  earlier pass of §2e is **rejected** — recorded here so it is not re-proposed on the grounds that
  it "would follow the art automatically". The owner's objection is that an automatic pick is a
  colour nobody chose, and on 114 frames of art that is 114 chances to be surprised.
- **A type may name its outline entry; unnamed types fall back to ONE shared default.**
  The obvious default is palette index **28 `#290d2c`** — the colour every type frame's ring is
  hand-painted in today (measured, §0), so shipping the default reproduces the current look
  exactly and any change is opt-in per type.
- **One colour rims the face AND everything on it.** Q7 = (a): the card reads as one object drawn
  in one ink. This is the *simplifying* answer — the shader needs **one** outline-colour uniform,
  not the `face_outline` + `art_outline` pair §2f(4) sketched.

⚠ **What this trades away, stated plainly:** a single ink cannot be simultaneously chosen for
contrast against the face (what the element outlines need) and against what is behind the card
(what the rim needs). Authoring is what covers the gap — the type author picks an ink that works
for both on that type, which a solver could not have been told to do. **The consequence is that a
badly chosen type ink is now possible, and nothing in code will catch it.** That is precisely what
the art tool in §11 is for.

**§4's palette work shrinks accordingly:** one `art_outline` role for the default, plus whatever
entries individual types name. No candidate-set resource.

### D4 — `CARD_SEPARATION` 14 → 16

Owner: *"pip added 2 pixels, need 2 unit clearance to account for animations."* The arithmetic
lands exactly: the outlined pip row ends **14** units below the card's top edge (4 margin + 10
pip), and 14 + 2 = 16.

⚠ **This is a board-layout change, not just a card change** — every stacked card sits 2 units
further down, so a tall column grows ~14 %. `PlayArea` slot maths is all derived
(`card_separation_play`), but [play_area.tscn:78](UI/play_area.tscn:78) carries a literal
`Vector2(14, 14)` that the constant does not reach.

### D5 — the status icons come off the card

Owner: *"no more status icons, they are represented by status effects like fire and juggling
shader... stack count and status names stay in description at top."*

✅ **Verified safe today, 2026-08-04:** the project has exactly **two** status classes —
`status_burning.gd` and `status_juggling.gd` — and **both already declare FX**
(`fx_request()`), so nothing loses its only representation. The names and stack counts are already
in the inspector text via `ControlCard.describe_card`
([control_card.gd:51-54](UI/control_card.gd:51)), so that half needs no work at all.

⚠ **But it creates a standing rule, and it should be written where a status author will hit it:**
**a new status that declares no FX now has NO card-side presence whatsoever.** Previously
`CardModifierStatus.draw_icon`'s base implementation drew nothing *and the StatusLayer still showed
its stack count* ([card_modifier_status.gd:75-76](Cards/card_modifier_status.gd:75)) — that
backstop is what is being deleted. Put the rule on `CardModifierStatus` itself.

✅ **And it resolves the overlap that was Q5 for free:** the StatusLayer sat at the card's
top-left and already collided with the rank pip; deleting it removes the collision rather than
relocating it.

### D6 — what the alert looks like (was Q6a)

Owner: *"bouncing glare between L R sides kind of like shiny effect, but bouncing gives more an
alert feel, glare can have thickness. A throb effect with maybe specific colour like red as well so
there are multiple notification types to choose from."*

So the alert is **not one effect but a small enumerated set**, and the shader takes a **kind**, not
a boolean:

| Kind | Behaviour | Notes |
|---|---|---|
| `GLARE` | a thick band sweeping the outline, **bouncing** L↔R | thickness is a knob |
| `THROB` | the outline pulses, optionally in a named colour (e.g. red) | the one kind that takes a colour |

Implications on top of §2e's four:

- **`u_alert_kind` (int) + `u_alert_color`**, since THROB names a colour and GLARE does not. A
  status therefore declares *which alert*, and only some kinds carry a colour.
- ⚠ **"Bouncing" is a ping-pong, and the shape of the reversal is the whole feel.** A sine eases
  into each end and will read as a gentle shine; a linear triangle wave reverses hard and reads as
  an alarm. The owner's stated reason for choosing bouncing over a repeating sweep is *"gives more
  an alert feel"*, so **the reversal should be sharp** — but this is an eye call, not a spec.
- **GLARE with thickness needs outline width > 1**, which is exactly the capability D2 preserved by
  refusing padded sheets (§2b). This is that decision paying off.
---

## 10. Docs carrying the literal `38×50` (update pass)

None of these are load-bearing code; all of them are the reason a future session would rebuild a
wrong mental model.

| File | Lines |
|---|---|
| `ARCHITECTURE_REVIEW.md` | 723 (the diagonal claim), 879 (the corner texel), 988 (one pixel size for all art) |
| `FX_HANDOFF.md` | 432-433, 523, 569, 958, 1372, 1382, 1616, 1682, 1791. ⚠ §1682 and `FX_SHADER_PLAN.md` §1081 both call the 38×50 card's diagonal **62.4**; it is **62.80** (`sqrt(38²+50²)`), and 62.23 is the *rotating* bound `(w+h)/√2` — two different numbers, neither of which is 62.4. Fix while passing through |
| `FX_SHADER_PLAN.md` | 223, 250-251, 979-984, 1081-1082 |
| `VFX.md` | 204 (prop art sizes vs "a card is 95×125") |
| `LAYERING.md` | 158 (`body_size` hardcoded per kind like `CARD_SIZE`) |
| `design/spotlight/DESIGN.md` | 517-518, 1693, 1826, 2230, 2237 (all the 32×32 / 38×50 scale arguments, and Q210/Q217) |
| Code comments | [fx_attachment.gd:215,285](UI/Fx/fx_attachment.gd:215), [fx_snapshot.gd:67,209](Tests/Visual/fx_snapshot.gd:67), [fx_behind.gd:60](Tests/Visual/fx_behind.gd:60), [fx_glow_style.gd:76](UI/Fx/fx_glow_style.gd:76), [glow.gdshader:258](Shaders/glow.gdshader:258), [prop_art_snapshot.gd:62,72,146,150,305](Tests/Visual/prop_art_snapshot.gd:62) |

---

## 11. The outline atlas tool — and why D7 makes it load-bearing

**Owner, 2026-08-04:** *"seems like this will need its own tool editor to check outline against all
art in the entire game as a massive recreated sprite sheet and test different outlines and outline
shader effects against all sprites at same time."*

Agreed, and D7 is what turns it from convenient into **the only place a bad outline can be caught**.
A derived colour scheme would have had a solver to unit-test; an authored one has a person choosing
114 times, and no assertion can tell a legible ink from an illegible one. §6's tests can prove the
clamp works, the bite survives and the rim rides the rig — none of them can prove the art *reads*.

### What it must show

Measured 2026-08-04, so the tool's scale is known rather than guessed:

| Sheet | Grid | Frame | Non-empty | Art touching frame edge |
|---|---|---|---|---|
| `card_types` | 8×8 | 38×50 → 38×52 | 15 | 15 |
| `rank_pips` | 13×5 | 8×8 | 13 | **13** |
| `suit_pips` | 8×8 | 8×8 | 19 | **18** |
| `stamp_pips` | 8×8 | 8×8 | 3 | **3** |
| `suit_art` | 13×13 | 32×32 | 52 | 2 |
| `skill_art` | 16×16 | 32×32 | 12 | 5 |
| | | | **114 total** | |

**114 non-empty frames** — one screen at a readable size, not a paged browser. That is small enough
that the tool can afford to show *every* frame every time rather than sampling, which is the
property that makes it a review surface instead of a spot check.

### Rules it inherits from this repo

1. ⚠ **NO MOCKS** (CLAUDE.md rule 5; owner 2026-07-29: *"no useless mocks when you can just use
   actual original scene"*). It must draw through the **real** path — the real
   `update_polygon_uv_frame`, the real material, ideally real `CardVisual` polygons — not a
   hand-rolled `draw_texture_rect_region` that re-implements framing. `fx_editor.gd` is the
   precedent that earned this rule: it *"paid for itself within hours of no longer being a mock"*
   by immediately showing the corner-texel bug (FX_HANDOFF §0c.5). A tool that re-implements
   framing cannot disagree with the game, which means it cannot find anything.
2. **`@tool` + no autoloads.** Same trap as every other editor-side script here: it runs with no
   `SettingsManager` and no `CardEnvironment`, so everything on the construction path needs the
   `FxAttachment.settings()` fallback (ARCHITECTURE_REVIEW §4g).
3. **Pin the pose.** The card rig autoplays. Anything judged at an arbitrary animation frame is
   judged at a different shape each time — `fx_editor`'s `rig_pose` slider is the existing answer.

### What it should let you change live

- **Outline colour** — the D7 default, and per-type overrides, against every frame at once.
- **Outline width** — the knob D2 preserved by refusing padded sheets.
- **Alert kind** (GLARE / THROB per D6) running on all frames simultaneously, which is the only way
  to see whether a bouncing glare reads on an 8×8 pip as well as it does on a 34×34 art square.
  ⚠ **Expect it not to.** A glare band sweeping a 10-unit pip has ~5 units of travel; the same
  effect on the card's 40-unit rim has 40. **D9 answers the coherence half** — one card-space band,
  so the pip shows the slice crossing it — but leaves the *legibility* half open: a pip lit for
  ~25 % of the sweep may read as a flicker rather than a shine, and a band thin enough for the card
  rim may barely touch a pip at all. Only this tool will settle it, and the fallback (a per-host
  thickness scale) is one more uniform, so it is worth asking early.

### The specific failures to build it to expose

- **Detail thinner than the outline.** A 1-unit rim around a 1-px feature swallows it. On 8×8 pips
  with art filling the cell (18/19), there is nowhere for a swallowed detail to hide.
- **Details 2 px apart merging** into a blob once each grows a 1-px rim.
- **Neighbour bleed**, which §6c now expects to be *loud* on the pip sheets and *quiet* on the
  32×32 sheets — so the tool is the thing that catches the quiet half.
- **An authored type ink that fails on its own card** — the gap D7 knowingly opened.

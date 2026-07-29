# FX_SHADER_PLAN.md — pixelated fire + juggling balls as composable shader overlays

Plan for the two requested shaders (fire tendrils, juggling balls), the "always on top no
matter the host's rotation/scale/shape" requirement, applying both to props (hoop/knife), and
the **effect-stacking model** (burning balls). Written to the workflow in
[START_HERE.md](START_HERE.md) §"How to plan & implement a feature here": audit facts first,
steps that each leave the game runnable, owner rulings recorded verbatim, test plan,
verification script.

---

## HANDOFF — read this first if you just picked this up

**Status (2026-07-27): BUILT.** T1–T14 and T17–T20 are done, verified on a GPU, full suite green.
T21 (the universal palette) landed 2026-07-28 — its contract is ARCHITECTURE_REVIEW §4i. What
remains is **T15** (the owner plays §10), then **T16** (which deletes this file).

**This document is now the SPEC AND THE RATIONALE, not the instructions.** The living contract — the
rules that prevent regressions, the snapshot commands, and every trap paid for — is
**ARCHITECTURE_REVIEW §4g** (FX) and **§4h** (pixel art / recolouring). Read those to WORK on the
feature; read this to find out WHY something is the way it is, or to check a ruling.

**If you are picking this up, read in this order:**

1. This block, then ARCHITECTURE_REVIEW §4g and §4h.
2. **§0b — the 25 owner rulings.** They are the spec. Several contradict the "obvious" way to
   build this; the section implementing each one says why. Do not redesign around them; if one
   seems wrong, ask the owner, do not quietly work around it.
3. **§7 — the task board**, for what is left and for what each finished task actually settled.
4. **§1 and §2 — the two ideas everything rests on.** If you only remember two things: the
   effect is never a material on the host, and an FX node is a *child of* its host. Both have alternatives that look easier and are wrong for reasons recorded there.

**Project rules that override anything in this doc** — read
[START_HERE.md](START_HERE.md) before your first commit:

- **No `git add`, no commits, no staging.** The owner commits via GitHub Desktop. Just edit files.
- **Never run headless Godot while the owner's editor is open.** With it closed, running the
  suite yourself is expected, not optional. Bound the launch with a killing timeout and grep for
  `Parse Error` in the same command — see HEADLESS_TESTING.md §0a.
- **Warnings are errors:** type every array and every for-loop variable.
- **`##` purpose comments on every new method.** Delete code that becomes dead; do not comment
  it out.
- Animation timings are **fractions of `get_delay()`**, never wall-clock. Tuning knobs live in
  `Scripts/player_settings.gd` or an `FxStyle` `.tres` (§5g), never as literals in a shader call.
- User-facing strings go through `TRANSLATION.find` — this feature adds none; keep it that way.
- Full suite green after **every** task, not just at the end.

**Where the risk is concentrated:** T7 (the `ball_fire` size invariant — the only task touching
game data and save format) and T11a (`ParticleEngine` — shared infrastructure the rest of the
game will depend on). Do not batch either with another task.

**Read §11 and §12 before T3.** §11 lists the ways this design could still be wrong — the largest
is fill rate, unmeasured, with a measurement step and kill criteria attached to T3. §12 lists the
code smells already fixed and the ones still open, including two real bugs (12.7, 12.8) that must
be handled when you reach T7 and T11b.

**Definition of done for the whole feature:** all of §7 checked, §9's suites green, the owner has
walked §10, and §7's T16 docs pass is complete — including deleting this file.

---

## 0. Audit facts this plan is built on (verified 2026-07-26, from code not docs)

| Fact | Where |
|---|---|
| `CardVisual` is a `Node2D` whose `rotation_degrees`, `scale`, `offset.position/rotation/scale` and `visual.transform` (written from `basis3d`, a 3-D flip that **squashes the basis to zero at edge-on**) are all animated every frame | `Cards/card_visual.gd:66-77`, `:259-326`, `:349-405` |
| A board card is **never still**: `delta_floating_anim` bobs and drifts it every frame, and `delta_self_moving_logic` eases it toward its slot | `Cards/card_visual.gd:259-326` |
| Card silhouette can be **deformed** by a generated `Skeleton2D` star rig (8/12/16 radial arms) bound to every face `Polygon2D` | `Cards/card_visual.gd:540-724` |
| Board draw order is **100 % structural — every board CanvasItem stays at `z_index == 0`**; order = sibling position + nesting | [LAYERING.md](LAYERING.md) §"Why all-structural" |
| Board layer siblings inside the scroll content, in draw order: `CardLayer → PropLayer → OverlayLayer` | `UI/play_area.tscn:108-115`, `UI/play_area.gd:37-45` |
| CardVisuals are ordered **row-major by `move_child`** every rebuild (`_order_board_cards`), and a held card is lifted to the END of CardLayer | `UI/play_area.gd:123-127`, `:354-376` |
| The "render a node's art on a *different* parent, transform mirrored per frame, `move_child`'d into place each frame, guarded" idiom already exists: `_PropHalf` + `_mirror_half` + `_apply_split` + `_row_bounds` | `Cards/Props/prop_visual.gd:199-207`, `UI/prop_layer.gd:145-252` |
| Fire is **already** drawn — as CPU polygons: `PropVisual._draw_fire_tips()` fans `fire_tips` triangles | `Cards/Props/prop_visual.gd:210-218` |
| **Fire provenance to props already exists**: burning card → `PropBurning.on_spawned` → `prop.fire_stacks` → `PropLayer._make_visual` → `vis.fire_tips` | `Cards/Props/Mods/prop_burning.gd:13`, `UI/prop_layer.gd:487` |
| **Fire provenance to the landed status does NOT exist**: `PropDropStatus.on_pass_card` adds a bare `stacked(script, 1)` — `prop.fire_stacks` is dropped on landing | `Cards/Props/Mods/prop_drop_status.gd:17` |
| Stack counts driving the shaders: `StatusBurning.stacks`, `StatusJuggling.stacks`; the setter emits `data_changed`, which already drives `CardVisual.update_visual` | `Cards/card_modifier_status.gd:9`, `Cards/card_visual.gd:35-49` |
| Statuses **merge by class** (stacks add) and a status bound to another card is `duplicate()`d on transfer | `Cards/card_data.gd:83-93` |
| Renderer is **`gl_compatibility`** (GLES3/WebGL2 feature set); global texture filter is **Nearest** | `project.godot:90-94` |
| **No gameplay shader exists yet** — `res://Shaders/` is a new directory | `find . -name "*.gdshader" -not -path "./addons/*"` → empty |
| Card sizes by context: PLAY_AREA `scale = card_scale`, DECK_VIEWER `scale = 2`, others `card_scale`; props `card_scale / AUTHORED_CARD_SCALE` | `Cards/card_visual.gd:205-221`, `UI/prop_layer.gd:99-100` |
| Animation timings must be **fractions of `get_delay()`**; tuning knobs live in `Scripts/player_settings.gd` | START_HERE rule 4 |

---

## 0b. Owner rulings (2026-07-26) — recorded verbatim, these are §8 material

1. *"fire tips should always point upwards generally, allowing for some angle skew as spread."*
2. *"fire paints props and cards, but just like props, should only show between cards. A card
   with fx should not show its fx in places it is covered."*
3. *"burning card does not mean its balls are burning, except if it is spawning burning balls
   according to fire effect. Each individual ball can be burning or not."*
4. *"Tendril cap of 8 is way too low. Either increase it to something like 50 or abandon cap and
   have fire increase in intensity per stack."*
5. *"balls ideally have no stack limit. If stack limit is hard requirement because infinity is
   not supported, make it something like 50, balls shrinking as count increases to fit in
   limited space."*
6. Delete `PropVisual._draw_fire_tips()` once shader fire ships: **yes**.
7. *"fx should be shared across all views, what it looks like on board should be what it looks
   like everywhere else."*
8. *"a resource and shared location for all visual effect tuning sounds more manageable than
   having to locate each shader one by one."*
9. *"embers shouldnt follow fire if flaming object leaves area, so particles makes more sense."*
10. *"Allowing focus highlight on effects sounds better than no focus highlight."*

**Second round (same day), answering §8:**

11. Balls **all pass in front** of the card, one layer — no depth split.
12. The pattern **speeds up** as ball count rises.
13. *"centered on card, bottom arc is at center of card, top arc should peak out above card."*
14. *"yes flame shifting color with stack count would also be another great lever to have."*
15. *"no burning object, just overlay, current plan"* — fire never tints or chars its host.
16. *"transitions when increase or decreasing stacks should be smooth, no jump in visuals."*
17. *"Burning ball does not transfer its status effect to card for no reason"* — no hand-off
    flourish, and no `StatusBurning` is granted by a landing ball.
18. *"any view that shows cards. If a card has a status effect and can be viewed, it should show
    status effect instead of hiding it behind selecting and reading description."*

**Universal rule (2026-07-27):** *"i dont want diagonal fire pixels, same for other vfx, it
should not rotate like that."* **No VFX pixel grid ever rotates — fire, balls, particles, or
anything added later.** This is a project rule, not a fire decision; see §2's rotation split and
§11.6.

**Third round, answering §8:**

19. `FX_LEVEL_REF` is *"a high number like 100+, doesnt matter too much as long as its tunable."*
20. Balls do **not** shift colour with count.
21. *"ball and card fire effects are separate effects, one is a prop status effect on the
    prop/status, other is status effect on card"* — a ball's flame level comes from the BALL,
    never from the card's Burning.
22. Transition speed: *"fast enough before next status effect gets applied, so that should be
    the metric."*
23. *"if card is flipped and hidden, its status effects should also be hidden. hidden card should
    reveal zero information to viewer."*
24. *"juggling keeps happening while card is moving, no freezing ever on any effect."*
25. *"yes add spin on balls, they can also spin faster as stacks increase. trails and other added
    effects would be too noisy."*

Where a ruling drives a specific technical choice, the section implementing it says so:

| Ruling | Consequence |
|---|---|
| 1 — tips point up | flames are combed across **x** and rise vertically by construction (§4c) |
| 2 — occluded like a prop · 7/18 — every view | FX is a **child of its host** (§2) |
| 4 — no small tendril cap · 5 — no ball cap | O(1) comb + **closed-form ball lookup**, no loops over the count (§4b, §5d) |
| 9 — embers escape their emitter | a shared **world-space particle engine** (§4e) |
| 14 — colour per stack | the palette is a **ramp texture**, u = heat, v = stacks (§4g) |
| 16 — no visual jumps | `u_count` is a **float**; cells resize continuously (§4h) |
| 21 — ball fire is the ball's own effect | **per-ball fire levels** in a 1×N data texture (§5e) |
| 24 — never freeze | one script-driven clock, scaled by pacing, never zeroed (§5c) |

---

## 1. The core idea

**1. The effect is never a material on the host.** A `ShaderMaterial` on the `CardVisual`'s
polygons is clipped to the polygon's UV rect (fire can't rise *above* the card) and inherits
`rotation`, the `offset` spin and the `basis3d` squash (flames tumble and flatten). The effect
is its **own world-aligned quad**, positioned from the host every frame.

**2. Decompose the host's transform instead of inheriting it.** The mirror rule:

| Component | Source | Why |
|---|---|---|
| `global_position` | host's `global_position` | the effect follows the host exactly |
| `rotation` | **always 0** | fire rises in world space; a knife spinning to face travel must not spin its flames (ruling 1) |
| `scale` | the host's **context** scale (`card_scale`, or `2` in DECK_VIEWER, or `card_scale / AUTHORED_CARD_SCALE` for props) — never the host's live `scale` | the host's live scale hits *zero* mid-flip (`basis3d` squash) and pulses on `anim_jump` |
| `modulate` | **mirrored** from the host | ruling 10: the focus highlight brightens the flames too |
| host rotation | passed as a **uniform** (`u_shape_rot`) | rotates the *silhouette* inside the quad while flames still rise up |

**The quad is world-aligned, the shape rotates inside it, the fire rises in quad space.** That is
what makes one shader work for a spinning card, a travelling knife and a static hoop.

**3. Fire is a decorator over a shape.** Every shape exposes `float shape_radius(float a)` — its
reach along the ray at angle `a` from straight up. From that the shader derives the contour above
or below any x, so fire, frost or anything else can attach to a card, a ring, a blade or a ball
without knowing what it is. Adding a prop kind is one branch; adding an effect is one shader.

---

## 2. Layering — FX is a CHILD of its host

**`CardLayer` stays strictly `CardVisual`s.** Nothing else is ever inserted into it, and no other
system needs to know FX exists.

**The FX quad is a child of its host**, added after the host's own art:

```
CardVisual
├─ Offset
│  ├─ Visual  (Type / Rank / Suit / Stamp / Art / StatusLayer)
│  └─ Fx      ← added AFTER Visual: draws above the card's own face
```

Godot draws a parent before its children and a subtree before the next sibling, so this gives
every requirement at once, with no coordination between systems:

| Requirement | How this satisfies it |
|---|---|
| Draws over its own card | `Fx` is a later child than `Visual` |
| **Occluded by the cards that overlap it** (ruling 2) | the whole `CardVisual` subtree — card *and* FX — draws before the next `CardVisual` in `CardLayer`, so a later card paints over both |
| Flames rise over the row *behind* | that row is an earlier sibling, drawn first |
| **Every view** (rulings 7, 18) | FX is part of the card, so it exists wherever the card does — deck viewer, pack preview, map — with zero context handling |
| Rides the jump and the card's scale | inherited from `Offset` (position, the `anim_jump` pulse) and from the root (`card_scale`, or `2` in DECK_VIEWER) |
| Focus highlight brightens the flames (ruling 10) | `modulate` is inherited. Nothing to mirror |
| Hidden when face-down (ruling 23) | one `visible` flag |

### The rotation split — why the QUAD holds still and the SHAPE turns

Verticality could live in either place, and the two are exact duals:

| | Quad world-aligned, **shape** turns inside it (chosen) | Quad turns with the card, **flame frame** turns inside it |
|---|---|---|
| How | cancel the inherited rotation; pass it on as `u_shape_rot` | inherit the rotation; pass world-up in as `u_up` |
| Quad size | must bound the card at **every** angle → its **diagonal** | bounds the card exactly → its box, plus flame reach on all four sides |
| Fill cost | ~62×62 + flames | ~38×50 + flames on all sides — **about the same** |
| **Pixel grid** | world-aligned, like the flame it draws | **rotates with the card** |

Size and cost are a wash. The **pixel grid** decides it. `fx_quantize` snaps in the quad's own
space, so a turning quad turns the fire's pixels — and the flame's *shape* would still be
world-vertical, so the grid would shear against the silhouette it is drawing. A vertical flame
made of tilted pixels reads as broken in a way a tilted card of tilted pixels does not, because
the card's pixels and the card's shape turn together. Keeping the quad still keeps grid and
flame in the same frame.

So: **cancel the inherited rotation on the quad, and hand that same rotation to the shader as
`u_shape_rot` so the silhouette turns inside the still frame.** Parenting to `Offset` — not to
`Visual` — is what makes cancelling *sufficient*: the `basis3d` squash that collapses the basis
to zero at edge-on is written onto `Visual` (`card_visual.gd:66-71`), so `Fx` never inherits a
singular matrix. What it does inherit is a rotation and a uniform scale:

```gdscript
## Flames are gravity-aligned, so the quad holds still in world space and the SILHOUETTE turns
## inside it (u_shape_rot). Keeping the quad unrotated is what keeps the fx pixel grid aligned
## with the fire it draws instead of shearing against it. Parented under Offset, never under
## Visual, so the basis3d flip squash is not in this chain.
var rot := host.rotation + host.offset.rotation
fx.rotation = -rot
mat.set_shader_parameter(&"u_shape_rot", rot)
```

⚠ **The quad must therefore be sized to the card's DIAGONAL, not its box** — a world-aligned box
around a turning 38×50 card must hold 62×62 at 45°, and `anim_spin_start` turns it through every
angle. Sizing to 38×50 shears the corners off the silhouette and cuts the flames rooted there.
See §5f.

Props take the same shape: the FX quad is a child of the `PropVisual`, added last, with the
prop's rotation cancelled (a knife turns to face travel; its flames must not).

**Split props (the hoop) inherit the split for free.** `_PropHalf` nodes already exist and already
bracket the occupied card (`prop_layer.gd:145-252`); the FX halves are children of *those*, so the
ring's back-arc flames sit behind the card exactly as its back arc does. A `u_half` uniform masks
each half's emitters — `HoopVisual.SPLIT_TOP/SPLIT_BOTTOM` already define the angles.

`z_index` stays untouched, so [LAYERING.md](LAYERING.md)'s all-structural rule holds: this is
pure parent/child nesting, the most structural ordering primitive there is.

**Why not `top_level = true` on the child** (the obvious way to escape the parent transform):
`CanvasItem.set_as_top_level` re-attaches the item to the **canvas root** for rendering, not just
for transforms — it would leave its position in the draw order entirely and break ruling 2.
Cancelling rotation keeps the node where it belongs in the tree.

---

## 3. File layout (NEW FILES — approved, ruling: yes)

```
res://Shaders/
  fx_common.gdshaderinc     # noise / quantize / palette / dither + the shared ball path
  fire.gdshader
  juggle.gdshader
  Styles/                   # FxStyle .tres presets (ruling 8: one place for all FX tuning)
    fire_card.tres  fire_prop.tres  fire_ball.tres  juggle_default.tres
res://UI/Fx/
  fx_style.gd               # class_name FxStyle       — every static lever, as a Resource
  fx_attachment.gd          # class_name FxAttachment  — one host's quads (a CHILD of that host)
  particle_engine.gd        # class_name ParticleEngine — THE particle path for the whole game
  particle_spec.gd          # class_name ParticleSpec   — one particle kind, as a Resource
```

`ParticleEngine` is **shared infrastructure**, not part of this feature — see §4e.

`FxAttachment` is owned by the host (`CardVisual`, `PropVisual`) rather than by a board-level
manager — that is what makes ruling 7 free: any CardVisual in any context builds its own.

---

## 4. The shaders

### 4a. `fx_common.gdshaderinc`

```glsl
// --- pixel grid -------------------------------------------------------------
// `grid` = u_extent / u_pixel, where u_pixel is ART UNITS PER FX PIXEL — a free per-material
// knob (mixed densities across hosts are wanted). Quantize in LOCAL space, never SCREEN_UV:
// that locks the chunkiness to the art rather than the window.
vec2 fx_quantize(vec2 uv, vec2 grid) { return (floor(uv * grid) + 0.5) / grid; }

float fx_hash11(float n) { return fract(sin(n * 127.1) * 43758.5453); }
float fx_hash21(vec2 p)  { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float fx_value_noise(vec2 p) { /* bilinear smoothstep of fx_hash21 over the lattice */ }
float fx_fbm(vec2 p) {
	return fx_value_noise(p) * 0.6 + fx_value_noise(p * 2.03) * 0.3
	     + fx_value_noise(p * 4.01) * 0.1;
}

// --- palette ----------------------------------------------------------------
// 4 bands with HARD steps — the banding is what reads as "pixel art"; quantized UV alone gives
// blocky gradients. Bands and thresholds are UNIFORMS: a cold ramp makes this shader frost.
vec4 fx_palette(float heat, vec4 t, vec4 c0, vec4 c1, vec4 c2, vec4 c3) {
	if (heat < t.x) return vec4(0.0);
	if (heat < t.y) return c0;
	if (heat < t.z) return c1;
	if (heat < t.w) return c2;
	return c3;
}
// Bayer 4x4 — lift the matrix from ../necromii/Shaders/retro.gdshader:19 so the repo dithers
// one way. Breaks band EDGES without softening them.
float fx_bayer(vec2 frag) { /* 0..1 */ }

// --- the juggling path ------------------------------------------------------
// A real cascade is a CLOSED LOOP, not a ball bouncing along one line: a TALL arc carries balls
// one way across the top, and a SHALLOWER return arc carries them back the other way along the
// bottom. Balls are spread evenly around the whole loop, so at any moment roughly half are
// travelling each direction (owner spec 2026-07-26).
//   `f`     = share of the cycle spent on the tall arc. 0.5 = even; > 0.5 = longer hang time,
//             which is what real juggling looks like (the throw takes longer than the carry).
//   h_bot   = the "flat" return — a small upward arc, not a straight line.
// Both halves are MONOTONIC in x, which is what keeps §4b's closed-form lookup invertible; do
// not add a timing ease inside a half without checking that it stays invertible.
// ONE definition, #included by both juggle.gdshader and fire.gdshader, so burning balls
// physically cannot drift off their balls.
vec2 fx_ball_at(float s, float span, float h_top, float h_bot, float f) {
	float u = fract(s);
	if (u < f) {                                    // tall arc, +x -> -x
		float a = u / f;
		return vec2(span * 0.5 * (1.0 - 2.0 * a), -h_top * sin(a * PI));
	}
	float a = (u - f) / (1.0 - f);                  // shallow return, -x -> +x
	return vec2(span * 0.5 * (2.0 * a - 1.0), -h_bot * sin(a * PI));
}
```

### 4b. `juggle.gdshader` — **unlimited balls, no loop** (ruling 5)

Ruling 5 asks for no stack limit. A shader loop always needs a constant bound, so **do not use a
loop**. Balls are evenly spaced on one shared path whose two halves are each monotonic in x,
which makes the nearest-ball test invertible in closed form:

> Ball `i` sits at cycle position `s_i = phase + i/n`. Within either arc, x is monotonic in the
> arc parameter, so from a fragment's `x` you can **recover the `s` that would put a ball
> there** — one per arc — convert each to a real-valued index `m = (s − phase)·n`, and the only
> balls that can possibly cover this fragment are `floor(m)` and `ceil(m)`. Two arcs × two
> candidates = **four evaluations, O(1) at any count, including 500.**

```glsl
uniform vec2  u_extent, u_body;
uniform float u_pixel = 1.0;
uniform int   u_count = 0;          // == StatusJuggling.stacks, UNCAPPED
uniform float u_phase = 0.0;        // script-driven, pacing-aware
uniform float u_span  = 30.0;
uniform float u_h_top = 22.0;       // tall throw arc — GDScript grows it with the count (§5d)
uniform float u_h_bot = 4.0;        // shallow return ("the flat part is a smaller arc upwards")
uniform float u_top_fraction : hint_range(0.2, 0.8) = 0.6;   // hang time vs. carry time
uniform float u_radius = 3.0;       // GDScript already shrank this for the count (§5d)
uniform float u_spin = 0.0;         // spin rate; GDScript raises it with the count (ruling 25)
// FLAT colours — balls do NOT ride the stack ramp (ruling 20). Their count already reads
// through size and speed; a third channel would be redundant.
uniform vec4  u_lit : source_color;
uniform vec4  u_shade : source_color;
uniform vec4  u_gloss : source_color;

// Nearest ball to `p`: invert x on BOTH arcs, then check the two bracketing indices of each.
float nearest_ball(vec2 p, float n, out float id) {
	float best = 1e9; id = 0.0;
	for (int arc = 0; arc < 2; arc++) {
		float a = (arc == 0) ? (0.5 - p.x / max(u_span, 1e-4))    // tall arc runs +x -> -x
		                     : (0.5 + p.x / max(u_span, 1e-4));   // return runs -x -> +x
		if (a < 0.0 || a > 1.0) continue;
		float s = (arc == 0) ? a * u_top_fraction
		                     : u_top_fraction + a * (1.0 - u_top_fraction);
		float m = (s - u_phase) * n;                    // real-valued ball index at this x
		for (int j = 0; j < 2; j++) {                   // floor and ceil — a fixed 2, not a cap
			float i = floor(m) + float(j);
			vec2  c = fx_ball_at(u_phase + i / n, u_span, u_h_top, u_h_bot, u_top_fraction);
			float d = dot(p - c, p - c);
			if (d < best) { best = d; id = i; }
		}
	}
	return best;
}

void fragment() {
	vec2 p = (fx_quantize(UV, u_extent / u_pixel) - 0.5) * u_extent;
	float n = float(max(u_count, 1));
	float id;
	float d2 = nearest_ball(p, n, id);
	vec4 col = vec4(0.0);
	if (d2 <= u_radius * u_radius) {
		vec2 c = fx_ball_at(u_phase + id / n, u_span, u_h_top, u_h_bot, u_top_fraction);
		vec2 d = p - c;
		// SPIN (ruling 25): rotate the ball's own shading frame. A per-ball phase keeps them from
		// turning in unison, and the off-centre gloss dot is what actually reads as rolling — a
		// symmetric two-tone split is identical every half turn. No trails: ruled too noisy.
		float sp = u_spin * u_time + fx_hash11(id) * TAU;
		vec2  q  = vec2(cos(sp) * d.x - sin(sp) * d.y, sin(sp) * d.x + cos(sp) * d.y);
		bool rim   = (sqrt(d2) > u_radius - 1.0) || (q.y > u_radius * 0.35);
		bool gloss = length(q + vec2(0.3, 0.3) * u_radius) < u_radius * 0.3;
		col = gloss ? u_gloss : (rim ? u_shade : u_lit);   // hard steps, no AA
	}
	COLOR = col;
}
```

The identical inversion is what lets fire mark **individual** balls as burning (ruling 3): the
ball's integer index falls out of the lookup, so `id < u_burning` is a per-ball test.

### 4c. `fire.gdshader` — the comb runs across x, so tips point up by construction (ruling 1)

If flames must rise vertically (ruling 1), then **measuring height vertically is the natural
formulation** — and it is also the cheap one:

- Comb the emitting width into exactly N cells → **exactly N tendrils, O(1), no loop**. Ruling 4
  is then free: the count can be 3 or 300 at identical cost.
- Each tendril rises straight up from the contour beneath it, so tips point up with no bending
  hack — nothing has to bend a flame back toward vertical, because none ever leaves it.
- **Surrounding the object** (the lever the polar version was introduced for) survives as
  `u_wrap`: it lerps each flame's base from the silhouette's **top** contour down to its
  **bottom** contour. At 0 fire sits on top; at 1 it starts underneath and rises across the whole
  body. Cheaper, simpler, and it keeps every tip vertical.
- **Skew as spread** (ruling 1's allowance) is `u_skew`: tendrils lean away from centre in
  proportion to how far out they sit, so the crown fans.

```glsl
// ===== LIVE (pushed per frame by FxAttachment) ============================================
uniform int   u_mode = 0;        // 0 = silhouette, 1 = balls
uniform int   u_shape = 0;       // 0 card (radius table), 1 ring, 2 blade
uniform int   u_count = 0;       // tendrils (UNCAPPED — see §5d for how it is derived)
uniform int   u_half = 0;        // split props: 0 whole, 1 back arc only, 2 front arc only
uniform vec2  u_extent, u_body;
uniform float u_pixel = 1.0, u_shape_rot = 0.0, u_time = 0.0, u_seed = 0.0;
uniform float u_radii[32];       // deformable card silhouette (32, not 16 — see the note below)
uniform vec2  u_lag = vec2(0.0); // motion trail, see §4f
uniform int   u_burning = 0;     // balls mode: how many of the balls are on fire (ruling 3)
uniform float u_phase = 0.0, u_span = 30.0, u_arc_height = 22.0, u_ball_radius = 3.0;

// ===== STATIC (written once from FxStyle) =================================================
uniform float u_wrap        : hint_range(0.0, 1.0) = 0.0;   // top contour -> bottom contour
uniform float u_skew        : hint_range(0.0, 1.0) = 0.15;  // outward lean of the crown
uniform float u_inner_alpha : hint_range(0.0, 1.0) = 0.5;   // opacity where fire covers the body
uniform float u_height = 14.0;
uniform float u_height_var  : hint_range(0.0, 1.0) = 0.45;
uniform float u_base_width  : hint_range(0.1, 2.0) = 1.0;
uniform float u_dome_power  : hint_range(0.2, 3.0) = 1.0;
uniform float u_sink = 2.0;
uniform int   u_merge = 0;
uniform float u_sway_amp = 0.35, u_sway_speed = 4.0, u_flicker_speed = 1.7;
uniform float u_wave_amp = 0.0, u_wave_freq = 0.35, u_wave_speed = 6.0;
uniform float u_desync : hint_range(0.0, 1.0) = 1.0;
uniform float u_pulse_amp = 0.0, u_pulse_speed = 2.0;
uniform float u_lag_amount : hint_range(0.0, 2.0) = 1.0;
uniform vec2  u_wind = vec2(0.0);
uniform float u_noise_amp = 0.5, u_noise_scale = 0.35, u_noise_scroll = 18.0;
uniform vec4  u_c0, u_c1, u_c2, u_c3 : source_color;
uniform vec4  u_thresholds = vec4(0.18, 0.35, 0.55, 0.78);
uniform float u_intensity = 1.0, u_brightness = 1.0, u_opacity = 1.0, u_dither = 0.0;

// Silhouette reach along the ray at angle `a` from straight up. One branch per prop kind.
float shape_radius(float a) {
	float th = a - u_shape_rot;
	if (u_shape == 1) return u_body.x * 0.5;
	if (u_shape == 2) {                                   // blade: ray/box exit
		vec2 h = u_body * 0.5;  vec2 d = vec2(sin(th), -cos(th));
		return min(h.x / max(abs(d.x), 1e-4), h.y / max(abs(d.y), 1e-4));
	}
	// card: deformable table. 32 entries, NOT 16 — the star rig goes up to 16 arms
	// (card_visual.gd:540) and 16 samples cannot represent 16 alternating features (Nyquist);
	// at 16 the arms either smooth into a blob or beat against the grid depending on phase.
	float t = (th / TAU + 1.0) * 32.0;
	int i0 = int(floor(t)) % 32;
	return mix(u_radii[i0], u_radii[(i0 + 1) % 32], fract(t));
}

// Contour y at horizontal position x, top side (sgn -1) or bottom (sgn +1). A polar table is
// not directly invertible for a vertical line, so this is a fixed-point iteration.
// ⚠ Exact for the ring, and it converges in ONE step for a rectangle (the top edge is flat, so
// the first angle is already the answer) — but a DEEPLY star-deformed card is NOT near-convex,
// and a vertical line can cross its outline three times. There the iteration settles on the
// convex-hull contour, so flames bridge across a notch instead of dipping into it. Fine for mild
// deformation; if deep stars must be hugged, raise the iteration count or emit from the polar
// contour directly and pay for it.
float contour_y(float x, float sgn) {
	if (u_shape == 1) {
		float r = u_body.x * 0.5, d = r * r - x * x;
		return d <= 0.0 ? sgn * 1e9 : sgn * sqrt(d);
	}
	float y = sgn * u_body.y * 0.5;
	for (int it = 0; it < 2; it++) {
		float a = atan(x, -y);
		y = -shape_radius(a) * cos(a);
	}
	return y;
}

// Heat from tendril `id` at (x, rise). Factored out so u_merge can tap the neighbours.
float tendril(float id, float x, float rise, float n, float w) {
	float half_w = (w / n) * 0.5 * u_base_width;
	float xc     = ((id + 0.5) / n - 0.5) * w;
	float ph     = fx_hash11(id + u_seed) * TAU * u_desync;

	float h = u_height
	        * mix(1.0, 0.55 + 0.45 * fx_value_noise(vec2(id * 3.7 + u_seed,
	                                                     u_time * u_flicker_speed)), u_height_var)
	        * (1.0 + u_pulse_amp * sin(u_time * u_pulse_speed));
	if (rise >= h) return 0.0;
	float k = clamp(rise / h, 0.0, 1.0);         // 0 base -> 1 tip

	// Everything that displaces the spine grows with height, so the base stays planted on the
	// body and only the TIP moves: skew (systematic outward fan), sway (oscillating drift),
	// wave (snaking), wind, and the motion lag (§4f).
	float drift = u_skew * (xc / max(w * 0.5, 1e-4)) * k
	            + sin(u_time * u_sway_speed + ph) * u_sway_amp * k * k
	            + sin(rise * u_wave_freq - u_time * u_wave_speed + ph) * u_wave_amp * k
	            + (u_wind.x + u_lag.x * u_lag_amount) * k * k;

	float u = clamp((x - xc - drift * half_w) / half_w, -1.0, 1.0);

	// DOME — the flame's TOP falls to 0 at its cell edges, so its BASE spans the full cell and
	// the outline curves into ONE tip. This is what keeps a single stack a triangle, not a pole,
	// AND what makes a 300-stack card degrade into a clean sheet of flame instead of noise.
	float dome = pow(max(1.0 - u * u, 0.0), u_dome_power);
	float top  = h * dome;
	if (rise >= top) return 0.0;
	return (1.0 - rise / max(top, 1e-4)) * (0.6 + 0.4 * dome);
}

void fragment() {
	vec2 p = (fx_quantize(UV, u_extent / u_pixel) - 0.5) * u_extent;
	float heat = 0.0, alpha_mul = 1.0;

	if (u_mode == 0) {
		float w = u_body.x;
		float n = float(max(u_count, 1));
		// WRAP: the base slides from the top contour down to the bottom one, so the same comb
		// gives "flames on top" and "engulfed" without ever tilting a flame.
		float base = mix(contour_y(p.x, -1.0), contour_y(p.x, 1.0), u_wrap) + u_sink;
		float rise = base - p.y;                       // > 0 == above the base line
		if (rise > 0.0 && abs(p.x) <= w * 0.5) {
			float id = floor((p.x / w + 0.5) * n);
			heat = tendril(id, p.x, rise, n, w);
			if (u_merge == 1) {                        // neighbours fuse, no V-notch
				heat = max(heat, tendril(id - 1.0, p.x, rise, n, w));
				heat = max(heat, tendril(id + 1.0, p.x, rise, n, w));
			}
			// Where the flame overlays the body (wrap > 0), draw it at its own alpha so a
			// burning card keeps its rank and suit readable.
			if (p.y > contour_y(p.x, -1.0)) alpha_mul = u_inner_alpha;
		}
		// Split props: keep only the emitters belonging to this half (LAYERING.md bracket).
		if (u_half == 1 && p.x >  0.0) heat = 0.0;
		if (u_half == 2 && p.x <= 0.0) heat = 0.0;
	} else {
		// BALLS: same closed-form lookup as juggle.gdshader, so the plume is welded to the ball.
		// Only balls with index < u_burning are lit (ruling 3: per-ball, not per-card).
		float n = float(max(u_count, 1));
		float id; float d2 = nearest_ball_both(p, n, id);
		if (mod(id, n) < float(u_burning)) {
			vec2 c = fx_ball_at(u_phase + id / n, u_span, u_arc_height);
			heat = tendril(0.0, p.x - c.x, (c.y - p.y) + u_ball_radius, 1.0, u_ball_radius * 3.0);
		}
	}

	// GUARD THE NOISE. Most fragments in the quad are empty, and fx_fbm is 7 hash+lerp taps —
	// running it unconditionally triples the shader's cost for pixels that draw nothing. This
	// one branch is the difference between a cheap effect and the fill-rate problem in §11.
	if (heat <= 0.0) { COLOR = vec4(0.0); return; }
	heat *= mix(1.0, 0.7 + 0.6 * fx_fbm(vec2(p.x, p.y - u_time * u_noise_scroll) * u_noise_scale
	                                    + u_seed), u_noise_amp);
	heat *= u_intensity;
	heat += (fx_bayer(FRAGCOORD.xy) - 0.5) * u_dither * 0.15;

	vec4 col = fx_palette(heat, u_thresholds, u_c0, u_c1, u_c2, u_c3);
	col.rgb *= u_brightness;
	col.a   *= u_opacity * alpha_mul;
	COLOR = col;
}
```

### 4d. The lever reference

| Lever | Default | What it does |
|---|---|---|
| **Coverage** | | |
| `u_wrap` | 0 | slides the flame base from the top contour (0, fire on top) to the bottom (1, engulfed). Tips stay vertical at every value. |
| `u_skew` | 0.15 | outward lean of the crown — ruling 1's "some angle skew as spread". |
| `u_inner_alpha` | 0.5 | opacity where flames overlay the body, so the card face stays readable. |
| `u_half` | 0 | split props only: restrict emitters to the back or front arc. |
| **Tendril shape** | | |
| `u_height` / `u_height_var` | 14 / 0.45 | length, and how ragged the crown is. |
| `u_base_width` | 1.0 | share of its cell each flame fills — gaps vs. touching. |
| `u_dome_power` | 1.0 | 0.6 fat shoulders → 1.0 parabolic → 2.0 spike. |
| `u_sink` | 2 | how far the base sinks into the body (guarantees no seam). |
| `u_merge` | 0 | 1 = 3-tap max, neighbours fuse into a sheet. **Turn this on at high stacks.** |
| **Motion** (five independent speeds — they read completely differently) | | |
| `u_sway_amp` / `_speed` | 0.35 / 4 | the tip drifts side to side. |
| `u_flicker_speed` | 1.7 | how fast tendril *lengths* churn. |
| `u_wave_amp` / `_freq` / `_speed` | 0 / .35 / 6 | the spine **snakes** — distinct from sway. |
| `u_desync` | 1.0 | 0 = every tendril in unison (one sheet), 1 = independent. |
| `u_pulse_amp` / `_speed` | 0 / 2 | whole-effect breathing. |
| `u_lag_amount` | 1.0 | how hard the flames trail the host's motion (§4f). |
| `u_wind` | (0,0) | one vector biasing lean and noise scroll. |
| **Texture** | | |
| `u_noise_amp` / `_scale` / `_scroll` | .5 / .35 / 18 | turbulence strength, grain size, scroll speed. |
| **Colour** | | |
| `u_c0..u_c3` + `u_thresholds` | fire ramp | the whole palette is uniform. Cold ramp = frost, no second shader. |
| `u_intensity` | 1.0 | pushes heat **up the ramp** — more of the flame reaches hotter bands. **This is the lever surplus stacks feed (ruling 4).** |
| `u_brightness` | 1.0 | multiplies the ramp's RGB. Recolour vs. relight — deliberately separate. |
| `u_opacity` | 1.0 | global fade (use for spawn/despawn, not `modulate`). |
| `u_dither` | 0 | Bayer-dithers band edges while keeping them hard. |

### 4e. Embers are world-space particles (ruling 9)

Embers that follow their emitter are wrong (ruling 9), so they must live in **world space** —
which an in-shader effect fundamentally cannot do, since its fragments only exist inside the
host's quad. Particles are the right tool.

**But this is not an ember feature. It is `ParticleEngine`: the one path every particle in the
game goes through**, whatever creates it and whatever it looks like. Owner direction: all particle
creation of any type and any source routes through it and lives under a single universal cap,
evicting the oldest when full. Embers are simply its first client.

> ⚠ This is **shared infrastructure**, not part of the fire feature. It outlives this plan, so it
> gets its own home (`UI/Fx/particle_engine.gd`), its own section in ARCHITECTURE_REVIEW, and its
> own tests. Future systems (score bursts, card dust, prop impacts) are expected to call it
> instead of adding a `CPUParticles2D` anywhere.

**Shape:**

```gdscript
class_name ParticleEngine
extends Node2D
## THE particle path for the whole game. Every particle, from any source, is spawned here and
## simulated in one pass under one global cap — so total cost is bounded by construction and no
## single effect can starve the frame. World-space by design: a particle's position is its own,
## so an emitter moving or being freed never moves or removes particles it already emitted.

const MAX_PARTICLES := 1024   ## the ONE cap; when full, the OLDEST particle is recycled

## Spawn `count` particles at a GLOBAL position. Any system may call this; nothing else in the
## game creates particles. Over-cap requests recycle the oldest slots rather than being dropped,
## so a burst always shows and old debris is what gives way.
func emit(spec: ParticleSpec, at: Vector2, count: int, dir := Vector2.UP) -> void: ...
```

Four decisions worth locking in:

- **Storage is a fixed-size ring buffer of `PackedFloat32Array`s** (position, velocity, age,
  lifetime, size, colour index) — not an array of objects. Fixed size means the cap is structural,
  the ring gives oldest-first eviction for free, and packed arrays match the project's own
  guidance for heavy numeric data. Simulation is one O(n) pass per frame, no allocation.
- **Rendering is one `MultiMeshInstance2D`** — a single draw call for every particle in the game,
  written per frame via `multimesh.buffer` in one assignment rather than per-instance setters.
  This is what makes "lots of particles" a non-issue and removes the CPU-vs-GPU question the
  earlier per-emitter node design raised.
- **`ParticleSpec` is a `Resource`** — lifetime, gravity, drag, spread, size curve, colour ramp,
  texture region. Kinds are `.tres` files (`ember.tres`, `dust.tres`), never code, consistent with
  `FxStyle` (§5g).
- **It renders on its own layer**, a `Node2D` sibling after `PropLayer` inside the scroll content.
  Detached particles have no host to be occluded by — they are world debris — so the ruling-2
  occlusion logic simply does not apply to them. That layer is a normal sibling and pollutes
  nothing.

**Pacing** follows the same rule as everything else: the simulation step is `delta * _pacing()`
(§5c), so particles slow and quicken with act compression.

**Emitters own no particles.** `FxAttachment` calls `ParticleEngine.emit(...)` at an interval and
forgets — there is nothing to detach or free when a host despawns, and a freed card cannot take
its embers with it. That is ruling 9 satisfied by construction rather than by teardown discipline.

Ember *rate* is what scales with stacks, under a per-source ceiling so one blazing card cannot
consume the global cap:

```gdscript
const FX_EMBER_RATE_MAX := 24.0   ## embers per second from a single host, however many stacks
```

### 4f. Motion lag — "can the tips trail like a flag/cape?" **Yes, and cheaply**

It is a good idea and it costs one uniform, because the machinery is already there: `tendril()`
displaces the spine by terms that scale with `k` (height up the flame). A trailing flame is just
one more such term, driven by the host's velocity instead of a sine.

**Tier 1 — spring-damped lag (start here).** In `FxAttachment._process`, track the host's
`global_position` delta, and drive a damped spring toward it:

```gdscript
## Flames trail the host like a cape: the tips lag its motion and OVERSHOOT when it stops.
## A spring, not a raw velocity — raw velocity snaps to zero the instant the card stops, which
## reads as the flames teleporting upright instead of whipping past and settling.
func _update_lag(delta: float, host_pos: Vector2) -> void:
	var vel := (host_pos - _last_pos) / maxf(delta, 1e-4)
	_last_pos = host_pos
	# Deadzone FIRST: board cards are never still (delta_floating_anim bobs and drifts them
	# every frame, card_visual.gd:311), so an unfiltered velocity makes the flames jitter
	# permanently. Only genuine travel should register.
	if vel.length() < LAG_DEADZONE: vel = Vector2.ZERO
	var accel := (-vel * LAG_STIFFNESS - _lag_vel * LAG_DAMPING)
	_lag_vel += accel * delta
	_lag += _lag_vel * delta
	mat.set_shader_parameter(&"u_lag", _lag / CardVisual.CARD_SIZE.x)   # normalized
```

Sign is negative because the flame trails *behind* the motion. The overshoot on stop is what
sells it — that is the cape snapping.

**Tier 2 — a position history (the real S-curve).** A single lag vector bends the flame as one
arc. A genuine cape bends *through the path the object took*: the tip should respond to where the
host was several frames ago. Push a small ring buffer of recent offsets as an array uniform
(`uniform vec2 u_trail[8]`) and sample it by height: `trail_offset = u_trail[int(k * 7.0)]`. Then
a card yanked left and then up leaves a flame with a real bend in it. 8 samples is plenty and the
array uniform is free on `gl_compatibility`.

**Two traps.** (1) The deadzone above is not optional — cards bob every frame by design.
(2) Lag must be computed from `global_position` only; the host's `rotation` and `basis3d` do not
move the flames (ruling 1), so feeding them in would tilt the tips off vertical.

### 4g. Colour: one ramp texture, not eight uniforms (ruling 14)

Ruling 14 wants the flame's colour to shift with stack count. That makes the 4-colour +
4-threshold uniform set the wrong shape — it would need eight more uniforms for the "high stack"
ramp plus interpolation code. **Replace all of it with a single ramp texture:**

```glsl
uniform sampler2D u_ramp : source_color, filter_nearest;   // u = heat, v = stack level
uniform float u_level : hint_range(0.0, 1.0) = 0.0;        // normalized stack count

// ...replaces fx_palette entirely:
vec4 col = texture(u_ramp, vec2(clamp(heat, 0.0, 1.0), u_level));
```

Strictly better on every axis:

- **Colour-per-stack is one texture coordinate.** `v` = normalized stack level; the artist paints
  the progression (red → orange → white-hot → blue) down the image.
- **The band count stops being 4.** Banding is wherever the texture has hard pixel columns, so a
  7-band ramp costs the same as a 3-band one. `filter_nearest` + the project's global Nearest
  default is what keeps the steps hard.
- **Eight uniforms become two.**
- **Frost, poison, holy** are each a different `.tres` texture, not a code path.
- It plugs straight into the **`palette` project**, which already generates okhsl ramps — the
  ramps can be authored there and exported.

Normalize the level logarithmically so the colour crawls rather than saturating at 3 stacks:
`u_level = clamp(log(stacks) / log(FX_LEVEL_REF), 0.0, 1.0)`. `FX_LEVEL_REF` — the stack count
that reaches the top of the ramp — is **~100+, and lives in `FxStyle` so it stays tunable**
(ruling 19). A log curve at that reference spends most of the ramp on the first ~20 stacks, which
is where the game actually lives, and keeps a visible difference all the way up.

**Balls do not use the ramp** (ruling 20) — their count already reads through size and speed, so
`juggle.gdshader` keeps flat colour uniforms.

### 4h. Smooth stack transitions — the count must be a FLOAT (ruling 16)

This is the ruling with the least obvious cost. `u_count` drives a comb that partitions the
emitting width into N cells, so going 3 → 4 tendrils **re-partitions the whole width**: every
existing flame jumps to a new position. Same for balls — they sit at `phase + i/n`, so changing
`n` teleports all of them. Tweening the stack count is not enough; the *count itself* has to be
continuous.

**Make `n` a float and let the partial tendril grow in place.**

```glsl
	float n  = max(u_count, 1.0);             // u_count is now a FLOAT, tweened by GDScript
	float id = floor((p.x / w + 0.5) * n);
	// The newest tendril occupies a partial cell — ramp its HEIGHT by the fraction so it grows
	// out of the surface instead of sliding in from the edge. Cell boundaries move continuously
	// as n changes, so the established flames just shuffle a little rather than jumping.
	float grow = (id >= floor(n)) ? fract(n) : 1.0;
```

and inside `tendril()`, `h *= grow`. Balls take the identical treatment: `n` float, the newest
ball's **radius** ramps by `fract(n)`, and the wrap gap absorbs the partial spacing.

⚠ **Gotcha:** with fractional `n` the recovered ball index can land on `ceil(n)`, one past the
last real ball. Wrap it (`id = mod(id, ceil(n))`) or the newest ball ghosts at the seam.

GDScript side: tween `u_count` toward the live stack count, and let `u_level`, `u_intensity`,
`u_height`, `u_h_top`, `u_radius` and `u_spin` ride the same tween. They are already floats, so
they are smooth for free once the count is.

**The duration is derived, not guessed (ruling 22).** The owner's metric is "fast enough before
the next status effect gets applied" — and that interval is a known quantity: statuses land on
**prop ticks**, whose live length is `game.get_delay() * settings.prop_tick_fraction`
(`prop_layer.gd:82-84`). So:

```gdscript
## A stack change must finish before the NEXT one can land (owner ruling #22), and statuses land
## on prop ticks — so the transition is a fraction of ONE PROP TICK, re-derived live like every
## other timing here. Never a wall-clock number, and never a guess: 0.6 of a tick always
## completes with margin, at any pacing, under any compression.
func _transition_secs() -> float:
	if not play_area: return 0.0
	return play_area.prop_layer.current_tick_seconds() * settings.fx_transition_fraction
```

Under heavy compression `current_tick_seconds()` approaches zero and transitions snap — which is
already how prop motion behaves at the compression floor (`prop_layer.gd:115`), so the whole board
degrades consistently rather than fire alone lagging behind.

**Reaching zero is a special case:** `stacks → 0` must fade the effect out (`u_opacity`) and only
then release the quad, or the flames vanish mid-frame — exactly the jump ruling 16 forbids.

**Never freeze for a game state (ruling 24).** No effect pauses for grabbed, held, hovered,
mid-move or mid-flip. `u_time` advances every frame; the pacing ratio only ever *scales* it.

**Pausing the whole game is a different thing, and it is free.** The project has no pause
mechanic today (`get_tree().paused` and `process_mode` appear nowhere outside `addons/`). If one
is ever added, FX stops with it and **no change is needed here**: `u_time` and the particle
simulation both advance in `_process`, which `SceneTree.paused` halts for any node at the default
`PROCESS_MODE_INHERIT`. This is a second reason the clock is script-driven — the shader built-in
`TIME` is advanced by the rendering server and would keep running straight through a pause, which
is the classic "paused game with a still-flickering fire" bug. Nothing to build; just do not give
FX nodes `PROCESS_MODE_ALWAYS`.

---

## 5. The GDScript side

### 5a. `FxAttachment` — owned by the host, so every context works (ruling 7)

**`FxAttachment` is a `Node2D`** — it *is* the `Fx` node in §2's tree. That gives it `_process`
for free, frees it with its parent automatically, and avoids a `RefCounted` owning `Node`s with
unclear teardown.

**It does not know what effects exist.** Statuses declare their own, exactly as they already
declare their own icon: `StatusLayer` iterates `data.statuses` and calls `draw_icon`
(`status_layer.gd:17-26`, `card_modifier_status.gd`). FX mirrors that idiom, so adding frost or
poison later touches **only the new status class**:

```gdscript
# card_modifier_status.gd — alongside the existing draw_icon / get_frame slots
## The visual effect this status renders, or null for statuses that only show an icon. Mirrors
## draw_icon: the status owns its own presentation, so FxAttachment never learns effect names
## and a new visual status is a new class, not an edit to the FX layer.
func fx_request() -> FxRequest:
	return null
```

```gdscript
class_name FxAttachment
extends Node2D
## One host's visual effects, and the `Fx` node of §2's tree. Built by the CardVisual /
## PropVisual itself — never by a board-level layer — so a card in the deck viewer, the pack
## preview or the map renders exactly what a card on the board does (rulings 7, 18).

var _quads : Dictionary[StringName, MeshInstance2D] = {}   ## keyed by request id, in draw order
var _ember_accum : float = 0.0                             ## owns no particles (§4e)

## Rebuild the quad set from whatever the host's statuses ask for. Idempotent, and GENERIC: it
## reads FxRequests, it does not know that fire or juggling exist. Called from
## CardVisual.update_visual (already fired by CardModifierStatus.stacks' data_changed).
func sync(requests: Array[FxRequest]) -> void: ...

## Per frame: cancel the inherited rotation (§2), advance the lag spring (§4f), push the LIVE
## uniforms, and accumulate emitter time. Early-outs when there are no requests.
func _process(delta: float) -> void: ...
```

An `FxRequest` is a small value: `id`, `shader`, `style`, `count`, `level`, plus the handful of
per-effect live values. `StatusBurning` returns one; `StatusJuggling` returns **two** (its balls,
and the ball-fire pass), which is exactly the nesting §6 describes — and it keeps the knowledge
that ball-fire depends on ball positions inside the one class that owns both.

**The quad is a `MeshInstance2D` + `QuadMesh`**, not a `ColorRect`. Both rasterize a rect with
`UV` 0..1, but `ColorRect` is a `Control`: dropped into the card's Node2D subtree it joins the
GUI input pass and **eats the mouse events the card needs for grabbing** unless every one is set
to `MOUSE_FILTER_IGNORE`. A `QuadMesh` is Node2D-native, is centred on its origin already, takes
its size directly, and cannot swallow input. (`Sprite2D` with no texture draws nothing, so it is
not an option.)

### 5b. One `Shader`, many `ShaderMaterial`s

The `Shader` resource compiles **once**; the `ShaderMaterial` is the per-node uniform set.

```gdscript
const FIRE_SHADER := preload("res://Shaders/fire.gdshader")   # ONE compile for the whole game
var mat := ShaderMaterial.new()
mat.shader = FIRE_SHADER      # shared resource — never .duplicate() it, that recompiles per card
```

**Warm the compile at load** (one hidden quad of each shader in `_ready`): on `gl_compatibility`
first-use compilation is a visible hitch, and the first fire in a run is exactly when you don't
want one.

### 5c. Time comes from `get_delay()`, never `TIME`

START_HERE rule 4. A shader's built-in `TIME` is wall-clock and ignores the compression ramp, so
`u_time` is accumulated in GDScript as `delta * _pacing()`:

```gdscript
## Ratio of the base delay to the LIVE delay: 1.0 at rest, > 1 as act compression speeds
## everything up, so ambient FX quicken in lockstep with card and prop animation.
func _pacing() -> float:
	var game := CardEnvironment.get_current_game()
	if not game: return 1.0
	return SettingsManager.settings.base_delay / maxf(game.get_delay(), 0.001)
```

It also makes FX pause with the game and replay deterministically. The same ratio drives
`ParticleEngine`'s simulation step.

### 5d. Counts — no arbitrary caps (rulings 4 and 5)

**Tendrils.** The tendril budget is **one constant for every host**, not derived per host
(owner ruling 2026-07-26):

> Flame size already scales linearly with the host (§5f). If a knife's flames are proportionally
> smaller, its tendrils are proportionally *narrower* too — so the number that fits is **the same
> on every object**. A knife shows the same 12 tendrils as a card, each physically smaller. The
> derived "room = width / min_tendril_units" version silently gave a knife *fewer, relatively
> fatter* flames, which distorts the proportions the linear scaling was there to preserve.

```gdscript
## One tendril budget for every host: flame WIDTH scales with the host exactly like flame
## height, so the same count fits everywhere and a small object simply gets a small version of
## the same fire (owner correction 2026-07-26). Surplus stacks make the fire FIERCER rather than
## sprouting more slivers (ruling #4) — no hard cap exists anywhere in the pipeline.
const FX_MAX_TENDRILS := 12   ## how many flames still read as distinct; the ONLY number to tune

func _fire_params(stacks: int) -> Dictionary:
	var n := clampi(stacks, 1, FX_MAX_TENDRILS)
	var overflow := float(stacks) / float(n)                  # 1.0 until the crown is full
	return {
		"count":     n,
		"intensity": style.intensity * (1.0 + log(overflow) * 0.45),
		"height":    style.height    * (1.0 + log(overflow) * 0.30),
		"merge":     1 if overflow > 1.5 else style.merge,    # fuse into a sheet when dense
		"embers":    _ember_budget(stacks),                   # BUDGETED, not unbounded (§4e)
	}
```

`log` not linear: 100 stacks should look terrifying, not 100× brighter than 1 stack.

At small host sizes those 12 tendrils go sub-pixel — which is correct ("the fire effect should
become smaller if the object is smaller") and self-handling, since the dome merge blurs them into
a sheet. If a prop's fire needs more visible detail, that is what its own `u_pixel` is for
(finer pixels on props), not a different tendril count.

**Balls.** Genuinely uncapped — §4b's closed-form lookup has no loop over the count, so 500 balls
cost the same as 5. Two things scale with the count, both per owner spec:

```gdscript
## Balls SHRINK to fit as the count grows (ruling #5): area-preserving (1/sqrt n) so the total
## mass of ball on screen stays roughly constant, with a one-pixel floor — past that they read
## as a stream, which is the honest way to show 200 of them.
var radius := maxf(style.ball_radius / sqrt(n), MIN_BALL_UNITS)

## The throw arc gets TALLER to fit more balls (ruling #13) — the loop lengthens so the same span
## holds more of them without bunching. log, not linear: 50 balls should not throw the arc off
## the top of the screen. The return arc stays shallow (it is the "flat part").
var h_top := style.ball_arc_height * (1.0 + log(n) * 0.35)

## The pattern also QUICKENS with the count (ruling #12). Note this fights the taller arc
## physically — a higher throw means a longer flight — so keep the coefficient small or the
## motion reads wrong. Most of the added busyness comes free anyway: n balls on one loop of
## period T already cross any point at rate n/T.
var period := base_period / (1.0 + log(n) * 0.20)
```

**Pattern geometry (ruling #13):** the loop's baseline `y = 0` is the **card's centre**, so the
shallow return arc rides across the middle of the card face and the tall arc **peaks above the
card's top edge**. That fixes the defaults relative to `CARD_SIZE` (38 × 50):

```gdscript
const BALL_SPAN   := CARD_SIZE.x * 0.80    # 30 — pattern width
const BALL_H_TOP  := CARD_SIZE.y * 0.75    # 37.5 — peaks ~12 units ABOVE the card
const BALL_H_BOT  := CARD_SIZE.y * 0.12    # 6 — the shallow "flat" return, inside the face
```

The FX quad's extent must therefore reach `h_top + radius + margin` above the card centre —
and `h_top` grows with the count, so the extent has to be recomputed with it, not fixed.

**All balls draw in front of the card, on one quad (ruling #11)** — no depth split, no second
bracket node. When two balls overlap, the closed-form lookup keeps the **nearest** one, which is
stable and cheap; if overlaps read ambiguously, bias the test toward the return-arc ball (in a
real cascade the carry passes nearer the viewer).

### 5e. Per-ball burning — the data change (ruling 3)

Ruling 3 requires per-ball provenance, and **ruling 21 sharpens it into per-ball fire *levels***:
a ball's flame is the ball's own effect, carrying the fire stacks *it* was spawned with, and is
never derived from the card's `StatusBurning`. A single `burning : int` count cannot express that
— two balls on one card can carry different fire levels. So:

```gdscript
## Fire stacks carried by EACH juggled ball, index-aligned with the rendered balls. A ball's
## flame is its own effect at its own level (owner ruling #21) — it is never read from this
## card's StatusBurning, and a burning card does not light its balls (ruling #3). 0 = not on
## fire. Packed for save size, matching the packed score arrays already used in persistence.
@export_storage var ball_fire : PackedInt32Array = PackedInt32Array()
```

`stacks` stays the ball count and `ball_fire.size()` must track it exactly — an invariant worth
asserting, because every bug in this area is the two drifting apart.

**Getting per-ball levels into the shader without a cap.** Uniform arrays need a constant size,
and ball count is unbounded (§4b). Upload the levels as a **1×N data texture** instead — one texel
per ball, updated when the status changes, *never* per frame:

```glsl
uniform sampler2D u_ball_fire : filter_nearest;   // 1 texel per ball, r = fire level (normalized)
// ...
float lvl = texelFetch(u_ball_fire, ivec2(int(id), 0), 0).r;
if (lvl > 0.0) { /* plume at this ball's OWN level, not the card's */ }
```

This replaces `u_burning` entirely — and with it the "burning balls are always the lowest indices"
trick, which ruling 21 makes both unnecessary and wrong. If per-ball level *variance* never
actually occurs in play, this collapses to one float uniform; the data model stays faithful
either way.

⚠ **Index stability landmine.** Ball `i` renders at `phase + i/n`, so its index is its identity.
**Append on add, and remove from the END** — removing from the middle re-indexes every later ball
and makes flames jump between balls, violating ruling 16 in the least debuggable way.

Four touch points, each a landmine if missed:

1. **`PropDropStatus.on_pass_card`** (`prop_drop_status.gd:17`) — currently drops the prop's fire
   on the floor. Carry it: **append** `prop.fire_stacks` to `ball_fire`.
2. **Merge** (`card_data.gd:86-93`) — `stacks` add, so `ball_fire` must be **concatenated** in the
   same operation. A merge that adds stacks without extending the array breaks the size invariant
   and silently extinguishes the incoming balls.
3. **`stacks` setter** (`card_modifier_status.gd:9`) — when stacks fall, `ball_fire` must be
   **truncated from the end** to match (per the index-stability rule above).
4. **Save compatibility** — `@export_storage` on an existing status class: old saves load with an
   empty `ball_fire`, so the load path must **resize it to `stacks` with zeros**. Defaulting to
   empty is correct (nothing burned before this shipped) but an empty array against a non-zero
   `stacks` is exactly the drift the invariant guards. No migration file needed; the load path
   deserves a test.

**Ruling 17 bounds this deliberately:** a burning ball landing on a card raises that card's
`StatusJuggling.burning`, and **nothing else**. It does not grant `StatusBurning`, and there is no
hand-off flourish — the plume simply appears (smoothly, per §4h). Likewise ruling 15: fire is
**overlay only** and never tints, lights or chars the host's own art, so nothing here ever writes
to a `CardVisual` polygon's material.

### 5e-bis. Every view that shows a card shows its FX (ruling 18)

Ruling 18 is a readability requirement, not just a rendering one: *a status you can see is a
status you don't have to click to discover.* So `FxAttachment` is built by `CardVisual`
unconditionally — no `current_context` gate anywhere — which §2's child placement already makes
free.

Two consequences to handle rather than discover:

- **Density.** A deck viewer can show 50+ cards at once; at 3 quads each that is 150+ shader
  quads on one screen. The quads are small there, but this is the worst case in the game and it
  needs measuring (§8.2). **Mitigation, recommended: a `viewer` `FxStyle` variant with embers and
  motion lag off** — both are motion effects for a board where cards move, and neither earns its
  cost in a static grid. Flames and balls stay.
- **Face-down cards are hidden entirely (ruling 23):** *"hidden card should reveal zero
  information to viewer."* FX draws *outside* the silhouette, so it leaks unless explicitly
  gated — bind every quad's visibility to **`show_front`** (`card_visual.gd:73`), the same gate
  `status_layer.visible` already uses. Note this is a *snap*, not a fade, and that is correct:
  `show_front` flips at the basis3d midpoint, when the card is edge-on and a sliver, so the cut
  is invisible. It is the one exception to ruling 16, and it is exempt because hiding information
  outranks smoothness.

### 5f. Per-host extent and density

```gdscript
## The quad must bound the host AT EVERY ROTATION plus the flames above it, or its edge clips.
## The quad stays world-aligned (§2) while the host turns inside it, so the bound is the host's
## CIRCUMSCRIBED extent — its DIAGONAL — not its box: a 38x50 card is 62x62 at 45 degrees, and
## anim_spin_start turns it through every angle. Sizing to 38x50 would shear the corners off the
## silhouette and cut the flames rooted there.
## Inputs exist already: CardVisual.CARD_SIZE for cards, PropVisual.body_size for props.
func _extent(body: Vector2, height: float) -> Vector2:
	var d := body.length()                                   # circumscribed diameter
	return Vector2.ONE * d + Vector2.ONE * (height + FX_MARGIN) * 2.0
```

**Non-rotating hosts skip this.** If a host's rotation is pinned (a static preview card), the box
bound is enough; the diagonal is the price of arbitrary rotation, and it costs ~1.6× the fill of
a card-sized quad. Do not pay it where it is not needed.

`u_pixel` (art units per fx pixel) is read straight from a per-host setting, not derived — mixed
densities across hosts are wanted, and the grid is `u_extent / u_pixel` so raising it chunkifies
without touching the flame's geometry.

**Flame length scales linearly with the host.** A knife's fire really is smaller than a card's;
the dome profile, not a minimum size, is what keeps a short flame readable. Use the host's **max
extent** (a knife is 20×8 — width or height alone gives wildly different answers).

### 5g. Knobs, and where each kind lives (ruling 8)

- **`Shaders/Styles/*.tres` (`FxStyle : Resource`)** — the ~35 art levers, one place for all FX
  tuning, live-editable in the inspector against a running game. Named variants per host
  (`fire_card`, `fire_prop`, `fire_ball`) and per future effect (`frost`) are files, not code.
  Written to the material **once**, on creation and on style swap.
- **`Scripts/player_settings.gd`** — only what the *player* or the pacing system moves:
  `fx_pixel_card` / `fx_pixel_prop` / `fx_pixel_ball`, `fx_juggle_period_fraction`, and a master
  `fx_intensity` for a "reduce effects" accessibility setting.
- **Per frame** — five values only: `u_time`, `u_count`, `u_extent`, `u_shape_rot`, `u_lag`
  (plus `u_phase` / `u_burning` in balls mode). Never push the style set per frame.

---

## 6. Effect stacking

**Emitters** (card silhouette, a juggled ball, a ring, a blade) are shapes that exist on screen;
**effects** (fire today, frost later) decorate them; **emitters nest** — a card's Juggling status
produces ball emitters, and a ball is itself an emitter fire can decorate.

A card with `J` juggling stacks (of which `B_j` burn) and `B` burning stacks gets at most three
quads, in this order (later = on top):

| # | Quad | Shader | Condition |
|---|---|---|---|
| 1 | card fire | `fire.gdshader`, `u_mode=0`, `u_shape=0` | `B > 0` |
| 2 | balls | `juggle.gdshader`, `u_count=J` | `J > 0` |
| 3 | ball fire | `fire.gdshader`, `u_mode=1`, `u_burning=B_j` | `B_j > 0` |

Balls are juggled in front of the card, so they occlude its flames; their own flames sit on top of
them. Hoop and knife get quad #1 only, with `u_shape = 1 / 2` (and `u_half` set per §2 for the
hoop's two brackets).

**The one rule that keeps it correct:** #2 and #3 must read ball positions from the same
function. They do — `fx_ball_at` in `fx_common.gdshaderinc`, `#include`d by both, with the same
closed-form index lookup. And `FxAttachment` computes `phase / span / height / count / radius`
**once** and writes them to both materials in one sweep. Two copies of the arc maths is the bug
that makes flames trail their balls by a frame; the shared include prevents it structurally.

Adding a new effect is one `.gdshader` + one `FxStyle` preset reading the same shape contract;
adding a new prop kind is one branch in `shape_radius`. Neither touches the other.

---

## 7. Task board

**Rules for working this board.** Do tasks in order — each depends on the ones above it. Every
task must leave the game runnable and the **full suite green** before the next one starts. Tick
the box and note the date + anything the next person needs. Never batch **T1** or **T7** with
another task: both are where this feature can silently break something else.

Legend: **Files** = what you will touch · **Done when** = the objective check · **⚠** = the thing
that bites.

---

### Phase A — placement (no shaders yet)

- [x] **T1 · FX child placement** ← START HERE
  **Read:** §2, §5a.
  **Files:** new `UI/Fx/fx_attachment.gd`, `UI/Fx/fx_request.gd`; `Cards/card_modifier_status.gd`
  (the `fx_request()` slot); `Cards/card_visual.gd` (build in `_ready`, refresh from
  `update_visual`).
  **Build:** `FxAttachment` as a `Node2D` child of `Offset`, added **after** `Visual`, holding one
  flat `MeshInstance2D`+`QuadMesh` per `FxRequest` (no material yet); per frame cancel the
  inherited rotation (`-(host.rotation + host.offset.rotation)`) and nothing else. Build the
  generic `fx_request()` path now — do not hardcode effect names even temporarily.
  **Done when:** a coloured box sits on every card; stays upright through `anim_jump`,
  `anim_spin_start` and a flip; rides the jump and the card's scale; brightens with the focus
  highlight without any mirroring code; is **occluded by the cards overlapping its host** and not
  by the row behind; appears identically in the deck viewer; **`CardLayer` and `play_area.gd` are
  untouched**; suite green.
  **⚠** Parent to `Offset`, never to `Visual` — `Visual` carries the `basis3d` squash
  (`card_visual.gd:66-71`) that collapses the basis to zero at edge-on. Do not reach for
  `top_level = true`: it re-attaches the item to the canvas root for *rendering*, not just
  transforms, which would drop it out of the draw order and break ruling 2. Use
  `MeshInstance2D` + `QuadMesh`, **not `ColorRect`** — a Control in the card's subtree eats the
  mouse events card grabbing needs (§5a). And guard construction with `Engine.is_editor_hint()`,
  setting no `owner`: both hosts are `@tool` (§11.2).

- [x] **T2 · Visibility, lifetime and release**
  **Read:** §5e-bis, §1 (mirror table).
  **Files:** `fx_attachment.gd`; `Cards/card_visual.gd`.
  **Build:** bind quad visibility to `show_front` (ruling 23 — a face-down card leaks nothing);
  free the attachment with its host; handle `data` swap and context differences.
  **Done when:** flipping a card face-down removes every quad at the edge-on frame and flipping
  back restores it; freeing a CardVisual leaves no orphan node and no leaked `ShaderMaterial`.

### Phase B — fire

- [x] **T3 · `fx_common.gdshaderinc` + `fire.gdshader` skeleton (card shape)**
  **Read:** §4a, §4c, §5b, §5c, §5f.
  **Files:** new `Shaders/fx_common.gdshaderinc`, `Shaders/fire.gdshader`; `fx_attachment.gd`.
  **Build:** quantize + noise + `shape_radius`/`contour_y` + `tendril()` + the x-comb; `u_count`
  from `StatusBurning.stacks`; `u_time` from the pacing accumulator (§5c); shared `Shader`
  resource + per-node `ShaderMaterial` + a compile warm-up.
  **Done when:** 1 stack renders **one full-width triangle** flush with the card's top edge;
  3 stacks render 3; flames stay vertical while the card spins and flips, with **no clipping at
  any rotation** (§5f's diagonal bound); and the **fill-rate measurement in §11.1 is recorded**
  — 20 burning cards on the board and 50 in the deck viewer, frame time noted in the handoff log.
  **⚠** Never `preload(...).duplicate()` the shader — that recompiles per card. Use `u_time`,
  never the built-in `TIME`. Keep the `heat <= 0.0` early-out before `fx_fbm` (§11.1) — it is the
  single biggest cost saving in the shader and easy to drop while refactoring.

- [x] **T4 · `FxStyle` resource + the static/live split**
  **Read:** §4e (levers), §5g.
  **Files:** new `UI/Fx/fx_style.gd`, `Shaders/Styles/fire_card.tres`.
  **Build:** an `@export` per static lever; `apply(mat)` writing them once; only `u_time`,
  `u_count`, `u_extent`, `u_shape_rot`, `u_lag` pushed per frame.
  **Done when:** editing a `.tres` in the inspector retunes a running game, and a profiler shows
  five `set_shader_parameter` calls per host per frame, not forty.
  **Do this before serious tuning** — hand-editing 35 uniforms through code is what makes people
  give up on tuning.

- [x] **T5 · Fire levers, in three passes**
  **Read:** §4d.
  **Files:** `fire.gdshader`, `fx_style.gd`, the `.tres` presets.
  **Build:** **5a** shape (`u_height`, `u_dome_power`, `u_base_width`, `u_skew`, `u_sink`,
  `u_merge`) · **5b** motion (sway / flicker / wave / desync / pulse / wind) · **5c** coverage +
  colour (`u_wrap`, `u_inner_alpha`, the §4g ramp texture, `u_level`, `u_dither`).
  **Done when:** every lever in §4d's table moves what its row says, and `u_wrap = 1` engulfs the
  card with every tip still vertical. Settle `FX_MAX_TENDRILS` and `FX_LEVEL_REF` here.

- [x] **T6 · Smooth transitions (fractional count)**
  **Read:** §4h.
  **Files:** `fire.gdshader`, `fx_attachment.gd`, `Scripts/player_settings.gd`.
  **Build:** `u_count` as a **float**; the partial tendril's height ramped by `fract(n)`; the
  transition tween timed at `prop_layer.current_tick_seconds() * fx_transition_fraction`;
  `stacks → 0` fades before the quad is released.
  **Done when:** adding and removing stacks one at a time never jumps — the new tendril grows out
  of the surface and the others shuffle; the last one fades rather than vanishing.
  **⚠** Tweening the stack count is not enough; the *count itself* has to be continuous or the
  comb re-partitions and every flame teleports.

### Phase C — juggling

- [x] **T7 · `StatusJuggling.ball_fire` (the data change)**
  **Read:** §5e — every word, including the four touch points and the index landmine.
  **Files:** `Cards/Statuses/status_juggling.gd`, `Cards/Props/Mods/prop_drop_status.gd`,
  `Cards/card_data.gd` (~:86-93), `Cards/card_modifier_status.gd` (~:9).
  **Build:** `@export_storage var ball_fire : PackedInt32Array`; append on drop; concatenate on
  merge; truncate **from the end** on decay; resize-with-zeros on load. Route every write through
  a setter that emits `data_changed` (§12.7).
  **Done when:** `ball_fire.size() == stacks` holds after a drop, a merge, a decay, a transfer
  (`duplicate()`) and loading a pre-change save — with a test for each; and changing `ball_fire`
  **alone**, with `stacks` untouched, refreshes the visual (§12.7).
  **⚠** This is the only task touching game data and save format. Ball index is ball *identity*:
  append on add, remove from the END. Removing from the middle re-indexes every later ball and
  makes flames jump between balls. Do not batch this with anything.

- [x] **T8 · `juggle.gdshader`**
  **Read:** §4b, §5d (ball half).
  **Files:** new `Shaders/juggle.gdshader`, `Shaders/Styles/juggle_default.tres`;
  `fx_attachment.gd`.
  **Build:** the closed-form nearest-ball lookup over both arcs; the §5d count scaling (radius
  `1/sqrt n`, arc height and period by `log n`); spin with a per-ball phase and the gloss dot;
  fractional `n` for smooth count changes.
  **Done when:** the pattern is a visible closed loop — tall arc peaking above the card's top
  edge, shallow arc across the card's centre, roughly half going each way; counts of 1 / 5 / 50 /
  500 all render correctly with **flat frame cost**; balls spin out of sync and faster at higher
  counts.
  **⚠** With fractional `n` the recovered index can land on `ceil(n)`, one past the last real
  ball — wrap it or the newest ball ghosts at the seam.

- [x] **T9 · Per-ball fire (fire.gdshader POINTS mode)**
  **Read:** §4c (POINTS branch), §5e (the data-texture half), §6.
  **Files:** `fire.gdshader`, `fx_attachment.gd`.
  **Build:** the 1×N `ball_fire` data texture, refreshed on status change and **never per frame**;
  `texelFetch` by recovered ball index; quad #3 sharing `phase/span/height/count/radius` with
  quad #2 from a single computation.
  **Done when:** a card juggling 5 balls with 2 lit shows exactly 2 plumes welded to their balls
  at every speed and under compression; a card with `StatusBurning` and unlit balls shows **no**
  ball fire; a 30-stack burning card's ball flames sit at the *balls'* colour level, not the
  card's (ruling 21).

### Phase D — props, embers, polish

- [x] **T10 · Props (hoop, knife, and the CPU-draw deletion)**
  **Read:** §2 (split-prop half), §4c (`u_half`, `u_shape`).
  **Files:** `Cards/Props/prop_visual.gd`, `UI/prop_layer.gd` (`_make_visual` ~:478,
  `_free_visual` ~:256, `_prune_done` ~:498, `abort_all` ~:403).
  **Build:** attach from `_make_visual` and release in all three teardown paths; `u_shape = 1`
  ring / `2` blade; the hoop's FX split into two `_PropHalf`-style nodes with `u_half`.
  **Then delete `PropVisual._draw_fire_tips()` and its call site** (`prop_visual.gd:134`,
  `:210-218`) — ruling 6.
  **Done when:** a burning knife's flames stay upright as it rotates to face travel; a burning
  hoop's back-arc flames sit behind the occupied card while the card still passes through the
  ring; `abort_all` clears everything; no `_draw_fire_tips` remains anywhere.

- [x] **T11a · `ParticleEngine` (shared infrastructure — not part of the fire feature)**
  **Read:** §4e in full.
  **Files:** new `UI/Fx/particle_engine.gd`, `UI/Fx/particle_spec.gd`; `UI/play_area.tscn`
  (a `ParticleLayer` `Node2D` sibling after `PropLayer`).
  **Build:** fixed-size ring buffer of `PackedFloat32Array`s under `MAX_PARTICLES`, oldest-first
  eviction, one O(n) simulation pass stepped by `delta * _pacing()`, one `MultiMeshInstance2D`
  writing `multimesh.buffer` in a single assignment, `ParticleSpec` as a `Resource`.
  **Done when:** `emit()` from an arbitrary caller produces particles that ignore the caller's
  later movement and destruction entirely; the live count never exceeds `MAX_PARTICLES` however
  hard it is hammered; the whole system is **one draw call**; the simulation allocates nothing
  per frame; and it has its own suite.
  **⚠** This is the game's only particle path from here on. It is generic on purpose — do not let
  ember-specific behaviour leak into it, and do not add a `CPUParticles2D`/`GPUParticles2D`
  anywhere else. Give it a design note in ARCHITECTURE_REVIEW at T16 as shared infrastructure.

- [x] **T11b · Embers, as `ParticleEngine`'s first client**
  **Files:** new `Shaders/Styles/ember.tres` (a `ParticleSpec`); `fx_attachment.gd`.
  **Build:** call `ParticleEngine.emit(...)` on an interval, rate from stacks under
  `FX_EMBER_RATE_MAX`, spawning from a random point along the host's top contour scattered by
  `u_height` (§12.8 — do NOT replicate `tendril()` on the CPU to find real tip positions). The
  attachment owns **no** particles and has nothing to tear down. Particle sprites carry no
  rotation (§11.6).
  **Done when:** dragging a burning card leaves its embers where they were dropped; a despawning
  prop's embers keep living; a burning card that is freed mid-flight loses nothing already
  emitted. Settle §8.3 by measuring in the **deck viewer**, the worst case.

- [x] **T12 · Motion lag (the cape)**
  **Read:** §4f.
  **Files:** `fx_attachment.gd`, `fire.gdshader`.
  **Build:** tier 1 — the spring-damped `u_lag` with its deadzone. Tier 2 (the 8-sample trail
  history) **only if** tier 1 reads flat; show the owner tier 1 first.
  **Done when:** a fast drag trails the flames and stopping makes them whip past and settle; an
  idle card's flames do **not** jitter.
  **⚠** The deadzone is not optional — `delta_floating_anim` bobs every card every frame
  (`card_visual.gd:311`), so raw velocity is never zero.

- [x] **T13 · Deformable silhouette**
  **Read:** §4c (`card_radius`), audit fact re: the star rig.
  **Files:** `fx_attachment.gd`, `Cards/card_visual.gd`.
  **Build:** sample 16 radii from the card polygon behind a **dirty flag** (not per frame), push
  to `u_radii`.
  **Done when:** flames hug a star-deformed card instead of its nominal rectangle.

### Phase E — closing out

- [x] **T14 · Test suites**
  **Read:** §9.
  **Files:** new `Tests/UI/test_fx_attachment.gd`; `Tests/UI/test_visual_layers.gd`;
  `Tests/all_tests.tscn`.
  **Done when:** every bullet in §9 has a check, and the full suite is green.
  *(Write each task's tests as you go — this task is the sweep for what slipped, not the first
  time tests appear.)*

### Phase F — added 2026-07-27 (owner, after seeing the first snapshots)

T17–T20 landed 2026-07-27; their contracts live in **ARCHITECTURE_REVIEW §4g**. T21's audit and the
decisions it needed were ruled on 2026-07-28; it landed, and its contract is
**ARCHITECTURE_REVIEW §4i**.

- [x] **T17 · Fix ball positions at low counts** — 2026-07-27. **It was the HARNESS, not the
  shader.** `fx_nearest_ball` and `fx_ball_at` were correct at every count; nothing in
  `Shaders/` changed. `FxAttachment._push_live()` ends with `set_process(not _fx.is_empty())`, so
  `fx_snapshot.gd` disabling the process BEFORE its push silently re-enabled it, and the two frames
  awaited before the capture advanced `_phase` by ~0.15 of a cycle past the phase the oracle (and
  the debug print the last pass trusted) used. Fixed by disabling the process LAST.
  The harness now also (a) draws every reference line at a width scaled to the shot's zoom — at
  ~1 art unit per pixel the old 0.5-unit crosses lost half their lines to the rasterizer, which is
  why this could not be judged by eye — and (b) MEASURES ITS OWN CAPTURE, printing `PROBE` lines
  with each ball's disagreement in art units. Every ball at 1 / 3 / 8 / 50 now lands within 0.6 art
  units (sub-pixel) of its oracle position.

- [x] **T18 · Spherical balls** — 2026-07-27. `juggle.gdshader` lifts the fragment onto the
  hemisphere (`z = sqrt(1 - |nd|²)`) and shades by that normal: the Lambert term is quantized into
  `u_ball_bands` hard tones spanning `ball_shade → ball_lit`, and a half-vector threshold
  (`u_ball_spec`) puts the highlight ON the surface. The spin rotates the LIGHT — the shading frame
  — after quantization, so the grid never turns. Levers: `ball_bands`, `ball_light`, `ball_light_z`,
  `ball_spec`. New shot **`05c_ball_sphere`** (r = 14 / 7 / 3 / 1) — a big ball reads as a sphere and
  the 1-unit floor still shades.

- [x] **T19 · Onion-layered fire (not row-layered)** — 2026-07-27. `tendril()`'s heat is now
  `pow(1 - across, u_onion_power) * (1 - u_onion_rise * k)`, where `across = |u| / half_at_k` and
  `half_at_k` INVERTS the same ogee the outline uses — so every iso-heat contour is a scaled copy of
  the outline and each colour wraps the one inside it. Height is the weak secondary term only.
  Verified in `00_tendril_count.png` (noise off): pale core spine, wrapped by orange, then red at
  the rim, converging at the tip — no horizontal stripes.

- [x] **T20 · Every effect's height stays adjustable** — 2026-07-27. Nothing added by T18/T19 bakes
  a size: the four new ball levers are shading-only and the two onion levers are unitless shape
  exponents. `height`, `ball_radius`, `ball_arc_height`, `ball_return_height` are untouched
  `FxStyle` levers, and `Shaders/Styles/*.tres` remains the single place FX tuning lives.

- [x] **T21 · Universal palette system** — LANDED 2026-07-28. Contract: ARCHITECTURE_REVIEW §4i.
  Built as `Palette` + `PaletteRoles` + `PaletteRamp` + a STATIC `PaletteDB` (the owner ruled against
  the autoload this plan sketched: nothing changes at runtime and the `@tool` hosts have no
  autoloads). `num_colors` and the palette image now come from `PaletteDB`, `fire_ramp.png` and its
  generator are deleted, and fire/ball/ember colours SAMPLE ordered ramps instead of lerping.
  Map + in-game UI chrome deferred by the owner pending custom art; they warn every run.
  **⚠** Do not start this inside this plan. Write it up to START_HERE's workflow (audit, owner
  APPROVAL lines, runnable steps) and get it ruled on first.

- [ ] **T15 · Owner verification**
  Hand the owner §10's numbered checklist and let them run it. **You do not run game scenes**
  (START_HERE) — you run the headless suite; they play.

- [ ] **T16 · Docs pass (mandatory — the feature is not done without it)**
  **Files:** [LAYERING.md](LAYERING.md), `ARCHITECTURE_REVIEW.md`, `todo.md`, this file.
  - LAYERING.md: FX as a child of its host (and why `CardLayer` stays cards-only), the hoop's
    split FX, the new `ParticleLayer` sibling, and any new entries for its "every moment the
    order can change" list.
  - ARCHITECTURE_REVIEW.md: §0b's 25 rulings verbatim into §8; **`ParticleEngine` as the game's
    single particle path** (its own subsection — it outlives this feature); the emitter/effect
    contract; the `ball_fire` invariant + its four touch points; the shared-include rule;
    shared-`Shader`/per-material; the pacing-clock rule.
  - todo.md: close this, add any deferred follow-ups.
  - **Then delete this file** — git keeps the full text (START_HERE doc hygiene).

---

### Handoff log

Append a line per session so the next person knows where things stand.

| Date | Tasks done | State / next step | Notes for the next person |
|---|---|---|---|
| 2026-07-26 | — | Plan written and fully ruled; nothing implemented. Next: **T1**. | 25 owner rulings in §0b are the spec. Risk is concentrated in T7 (save data) and T11a (shared particle infrastructure). |
| 2026-07-27 (2) | — | Snapshot harness added and four render bugs fixed; ogee profile landed. | Owner added T17–T21. (This row's warning that the file was untracked is now stale — the owner committed it in `22f2aac "VFX plan"`, so git has it.) |
| 2026-07-27 (3) | T17, T18, T19, T20 (+ prop/pip ART) | Implemented; full suite green (26 suites / 0 failures); all verified on a GPU. Next: **T21** (needs its own plan doc + owner approval), then **T15**, then T16. | T17 was a HARNESS bug, not a shader one — see its board entry; no `Shaders/fx_common.gdshaderinc` change was needed and the previous "already ruled out" list was reasoning from a print taken before the drift. The snapshot harness now measures its own capture (`PROBE` lines, art units) — trust those, never a by-eye read of the PNGs. Also landed this session, outside this plan: the owner's real hoop/knife prop art, ball+fire props drawing their suits' pips, one-pixel-size scaling (`PropVisual.ART_PIXEL_SCALE`), mirror-instead-of-rotate facing, suit pips keeping their own colours, `SHAPE_RING` as an ellipse, and `Tests/Visual/prop_art_snapshot.tscn`. All of it is written up in ARCHITECTURE_REVIEW §4g/§4h. |
| 2026-07-27 | T1–T14 | Implemented; full suite green (26 suites). Next: **T15** (owner walks §10), then T16. | Docs pass for LAYERING/ARCHITECTURE_REVIEW/todo is already written — only "delete this file" is outstanding, and it is BLOCKED on owner review. ⚠ This file was never committed; do not `rm` it assuming git has it. Deviations from the plan, all commented in code: shape enum is BOX/RING/RADII (a blade and an undeformed card are both boxes) with a test reading the constants out of the shader; the lag spring gained a restoring term (§4f's version has no force returning the flames upright, so `_lag` drifts permanently); `fire_tips` renamed `fire_stacks` (§12.4). Shader PIXELS are still unverified — see the snapshot harness in §9. |

---

## 8. Open questions

**Deferred by the owner — decide from the running game, not now:**

- **8.1 Motion-lag tier** (§4f): tier 1 (one spring) ships first; the 8-sample trail history only
  if a single arc reads flat.
- **8.2 `FX_MAX_TENDRILS`** — 12 is the starting guess; it is now the only tendril number in the
  codebase, so it is one slider to find by eye.
- **8.3 `MAX_PARTICLES`** — 1024 is the starting cap (§4e). Settle it by **measuring** the worst
  case, which is the **deck viewer** (50+ cards with FX, ruling 18), not the board — with the
  recommended embers-off viewer style as the comparison.

**Everything else is ruled.** The design is closed enough to build; what remains are numbers to
find by eye during T5-T8, all of them single tunables rather than decisions:

| Tunable | Where | Starting value |
|---|---|---|
| `FX_MAX_TENDRILS` | constant (§5d) | 12 — settle at T5 |
| `FX_LEVEL_REF` | `FxStyle` (§4g) | 120 — settle at T5 |
| `fx_transition_fraction` | player_settings (§4h) | 0.6 of a prop tick — settle at T6 |
| `MAX_PARTICLES` / `FX_EMBER_RATE_MAX` | `ParticleEngine` / §4e | 1024 / 24 per sec — settle at T11 |
| ball `u_spin` base + count coefficient | `FxStyle` (§4b) | tune at T8 |
| the ~35 `FxStyle` art levers | `.tres` presets (§4d) | tune at T5 |

---

## 9. Test plan

Shader *pixels* aren't headless-testable; the GDScript contract is, and that is where the bugs
will be.

**New — `Tests/UI/test_fx_attachment.gd`** ("FX ATTACHMENT", in `all_tests.tscn`):
- FX is a child of its host and stays one after a board rebuild, a grab lift and a zone change;
  `CardLayer` contains **only** `CardVisual`s at every moment
- tendril `u_count` == stacks while stacks ≤ the derived room, and **stops growing** past it
  while `u_intensity` rises (ruling 4)
- ball `u_count` == stacks at 1 / 50 / 500 with **no clamp**, radius shrinking by `1/sqrt(n)`
  down to the floor (ruling 5)
- quads #2 and #3 hold **identical** `u_count / u_phase / u_span / u_arc_height` on the same
  frame (the §6 correctness rule)
- the ball-fire data texture matches `StatusJuggling.ball_fire` texel for texel; a card with
  `StatusBurning` but no burning balls produces an all-zero texture (rulings 3 and 21 — the
  negative case is the point), and each lit ball's level is **its own**, not the card's
- `StatusJuggling`: `ball_fire.size() == stacks` **always** — after a merge (concatenated), after
  a decay (truncated from the END, never the middle), and after loading a pre-change save
  (resized to `stacks` with zeros). This invariant is the whole §5e bug surface
- removing a ball never re-indexes the survivors (the index-stability landmine)
- transition duration == `prop_layer.current_tick_seconds() * fx_transition_fraction`, re-derived
  live, and snapping to 0 at the compression floor (ruling 22)
- `u_count` is a **float** mid-transition and never an integer jump (ruling 16); reaching 0
  fades before releasing the quad
- FX visibility follows `show_front`: a face-down card exposes nothing (ruling 23)
- no effect stops advancing while its card is grabbed, held or mid-move (ruling 24)
- quads are `rotation == 0` at the host's `global_position` while the host is rotated, spinning
  and mid-flip; `modulate` mirrors the focus highlight (ruling 10)
- a CardVisual built in **DECK_VIEWER** gets the same quads as one in PLAY_AREA (ruling 7)
- freed host / despawned prop / `abort_all` releases everything, and an ember emitter
  **outlives** its despawned host by exactly its lifetime (§4e trap)
- every quad's `material.shader` is the **same `Shader` instance**

**Extend — `Tests/UI/test_visual_layers.gd`**: every FX node at `z_index == 0`; a burning card's
FX **below** the cards that overlap it and above its own card; the hoop's FX halves bracketing
the occupied card like the ring itself.

**Snapshot harness (added 2026-07-27) — `Tests/Visual/fx_snapshot.tscn`.** "Shader pixels aren't
headless-testable" is true of the HEADLESS suite and was wrong as a reason to test nothing: run
the same scene **windowed** and the GPU compiles and renders for real. The harness builds a grid
of cases, captures the viewport and writes PNGs to `user://fx_snapshots/`, then quits. It catches
the whole class of bug the headless suite structurally cannot — a GLSL compile error, an inverted
sign, a flame growing downward, an invisible effect — and the PNGs are reviewable by a human or
an agent. Run it after ANY shader edit. It is deliberately NOT in `all_tests.tscn`: it needs a
window and a GPU, so it stays a separate, explicit run.

**Must stay green:** the full suite (`Godot --headless --path solatro res://Tests/all_tests.tscn`,
bounded by a killing timeout and grepped for `Parse Error` — HEADLESS_TESTING.md §0a).

---

## 10. Owner verification script (run in-game)

1. Card with **1** Burning stack → one flame spanning the card's width, base flush with the top
   edge, curving into a single tip — a triangle, not a pole. Then 3 stacks → 3 tendrils.
2. Crank to 40 stacks → the crown fills, tendrils fuse into a sheet, and it gets **fiercer**
   rather than sprouting 40 slivers.
3. Same 1 stack on a knife → honestly small, still a triangle covering the blade's top edge.
4. **A burning card partly behind another card** → its flames are cut off exactly where the card
   in front covers it, and are **not** painted over that card (ruling 2).
5. Open the deck viewer on that card → identical effect, scaled to the viewer's card size
   (ruling 7).
6. Drag the burning card fast and stop → flames trail behind, then **whip past and settle**.
   Let it rest → no jitter from the idle bob (§4f deadzone).
7. Card juggling 5 balls, 2 of them burning → exactly 2 plumes, welded to their balls at every
   speed and under act compression. A *burning card* with non-burning balls → **no** ball fire.
   A card at 30 Burning whose 2 balls carry 1 fire stack each → the card's flames are far up the
   colour ramp and the **ball flames are not** (ruling 21 — they are separate effects).
7a. Balls **spin**, out of sync with each other, faster at higher counts. No trails.
7b. Watch the pattern itself → balls travel a **closed loop**: a tall arc one way across the top
   **peaking above the card's top edge**, a shallow arc back across the **card's centre**, with
   roughly half going each direction at any moment, and all of them in front of the card.
7c. Add a Burning stack one at a time → the new tendril **grows out of the surface** and the
   others shuffle slightly; nothing jumps. Remove them one at a time → the same in reverse, and
   the last one **fades out** rather than vanishing. Watch the colour crawl up the ramp.
7d. Open the deck viewer on a shelf of statused cards → every card shows its effects without
   being selected (ruling 18), and the frame rate holds.
7e. **Flip a burning card face-down** → every effect disappears at the edge-on frame; a face-down
   card leaks nothing about its statuses (ruling 23). Flip it back → they return.
7f. Grab, drag, hover and hold a burning juggling card → **nothing ever freezes** (ruling 24).
8. Push juggling to 50 stacks → balls shrink, the throw arc grows taller to hold them, they read
   as a stream; **frame rate unchanged** (the closed-form lookup means 50 costs what 5 costs).
8b. Every card burning at high stacks at once → the particle count saturates at `MAX_PARTICLES`,
   oldest debris giving way first, and the frame time holds (§4e; this settles 8.3).
9. Drag a burning card across the board → embers stay **where they were dropped** (ruling 9).
10. Burning hoop threading a card → flames above the ring, upright; the card still passes
    **through** the ring, and the ring's back-arc flames are behind the card.
11. Focus a burning card → the card and its flames brighten together (ruling 10).
12. Undo mid-act → flames, balls and props all clear; embers finish their lifetime and vanish.

**Added 2026-07-27 with T17–T20 and the prop/pip art pass** (this list is the ONE copy — todo.md
points here rather than restating it):

13. Look INTO a flame → the colours are nested **shells wrapping each other**, pale core through to a
    dark rim, following the flame's outline and converging at the tip. NOT horizontal stripes stacked
    up the flame (owner: "like actual candle lights").
14. Watch a juggled ball closely → it reads as a **sphere**: bands that curve around the light with a
    bent terminator, and a highlight sitting on the surface rather than a dot in the middle. At 50
    balls, where each is ~1 px, they should still read as lit specks and not flicker.
15. **Hoop and knife are real art now.** A knife crossing the row left-to-right vs right-to-left → the
    same blade **mirrored**, its top edge still on top (never rotated 180°). A hoop threading a card →
    the card passes between its left (shaded, far) and right (bright, near) arcs.
16. **One pixel size for all art.** Compare a ball prop against the Ball pip on a card — the pixels
    should be the same size. Change `card_scale` in settings and check they stay matched. Then say
    whether the hoop's on-screen size is right: it is 80×180 px at default scale against a 95×125
    card, which is what the art implies at matched pixel size.
17. Look at a card face → the **suit pip keeps its own multi-tone colours** while the rank pip and the
    card art are flat in that suit's colour.

---

## 11. Known weaknesses and unmeasured risks

Everything above is a design. These are the places it could still be wrong, ranked by how much
they would cost to discover late. **Read this before T3** — three of them are cheap to defend
against up front and expensive to retrofit.

### 11.1 Fill rate is the largest unmeasured risk in the plan ⚠

Every other cost in this design is bounded and reasoned about. This one is not. A card's fire
quad is roughly 62 + 2·14 ≈ 90 units square (§5f), which at `card_scale = 2.5` is ~225 × 225 =
**50 000 fragments per quad**. Three quads per card × 20 burning cards ≈ **3 M fragments/frame**,
and the deck viewer (ruling 18, 50+ cards) is worse. The fire shader per fragment runs
`contour_y` (2 `shape_radius` taps), up to 3 `tendril()` evaluations with `u_merge`, and `fx_fbm`
(7 hash+lerp taps). On `gl_compatibility` on an integrated GPU that is a plausible frame-killer.

Defences, in order of value:

1. **The `heat <= 0.0` early-out before the noise** (§4c). Most fragments in a quad are empty;
   this is the single biggest win and it is one line.
2. **Size quads honestly.** Do not pay the diagonal bound (§5f) for hosts that cannot rotate.
3. **`u_merge` off by default** — it triples `tendril()` calls. Turn it on only at high stacks,
   which is what §5d already does.
4. **The viewer style** (embers and lag off) should probably also cap `u_merge` and raise
   `u_pixel`, since viewer cards are small and detail is wasted there.

**Measure at T3**, before any lever work: put 20 burning cards on the board, then 50 in the deck
viewer, and read the frame time. This is the number that decides whether the whole approach
holds.

**Kill criteria — if T3 measures badly, in this order:** raise `u_pixel` (fewer, chunkier fx
pixels is a *look* change, not a capability loss) → drop the noise to a single octave → shrink
quads by capping `u_height` → and only then reconsider the one-quad-per-effect structure. Do not
start by cutting features; the levers are there to be spent.

### 11.2 `@tool` hosts mean this code runs in the editor

`CardVisual` and `PropVisual` are both `@tool` (`card_visual.gd:1`, `prop_visual.gd:1`), and the
formation editor instantiates `PropVisual`s live. So `FxAttachment` **will** run in the editor
unless it is stopped, where `CardEnvironment.get_current_game()` is null, `SettingsManager` may
not exist, and nodes added by a `@tool` script appear in the open scene.

Guard construction with `Engine.is_editor_hint()` and **never set `owner`** on an FX node —
`StatusLayer` is the existing precedent for a runtime-only child (`card_visual.gd:172-179`).
Getting this wrong risks writing FX nodes into `card_visual.tscn`, which the owner's editor would
then save to disk.

### 11.3 `ParticleEngine` is reachable only where it exists

It is a node on the play area (§4e), but ruling 18 puts FX in viewers that have no play area. So
`emit()` needs a null-safe access path and must **no-op when there is no engine**, rather than
crashing a deck viewer. Either register it in a static on first `_ready` or reach it through
`CardEnvironment`. Embers are off in viewers anyway (§5e-bis), so no-op is the correct behaviour
— but "no engine" must be a supported state, not an assumption.

### 11.4 Time-driven tests are flaky by construction

`u_time` accumulates from `delta`, so any test asserting a time-dependent uniform is a race.
Tests must call `attachment.drive(delta)` with **fixed** deltas and never rely on real frames.
Assert on the count/level/geometry uniforms, which are pure functions of the data — not on
anything that has integrated time.

### 11.5 Smaller things, listed so they are not rediscovered

- **`FxAttachment` is a `RefCounted`, so it has no `_process`** — the host drives it from its
  own `_process`. Fine, but it means every host now does per-frame FX work even with zero stacks;
  early-out on "no effects" before touching anything.
- **`CardVisual` reuse.** If a visual is ever re-pointed at different `data`, the attachment must
  resync. The `data` setter already calls `update_visual` (`card_visual.gd:35-49`), so this works
  today — but it is load-bearing and undocumented.
- **`duplicate()` and `ball_fire`.** `card_data.gd:92` duplicates a status on transfer.
  `PackedInt32Array` has copy-on-write value semantics so this is safe, but it is exactly the
  shape of thing that bites (cf. the `WeakRef` backref rule, ARCHITECTURE_REVIEW §6) — assert the
  size invariant after a transfer as well as after a merge.
- **Ball index wrapping.** The closed-form lookup recovers a real-valued index that may be
  negative or ≥ n before wrapping; `mod(id, n)` is needed in the general case, not only for the
  fractional-count seam (§4h).
- **Photosensitivity.** Flicker, pulse and high-intensity banding are a genuine accessibility
  concern, not just a taste one. The `fx_intensity` master knob (§5g) should reach zero, and
  `u_pulse_amp`/`u_flicker_speed` should be reducible independently of overall brightness.

### 11.6 The pixel grid never rotates — the rule, and how to keep it

Project rule (owner, 2026-07-27): **no VFX pixel grid ever rotates.** The mechanical form of it:

> **Quantize first, rotate after.** Snap the sample point to the grid in the quad's own
> world-aligned space, and let every rotation act on the *already-quantized* coordinate.

That one ordering is the whole rule, and it draws a line that is easy to get wrong:

- Rotating a coordinate frame **before** quantizing rotates the grid → diagonal pixels. Never.
- Rotating **after** quantizing moves *content* through a fixed grid → chunky pixels that stay
  square while the thing they depict turns. Always.

Both existing shaders already obey it, and it must stay that way through every refactor:
`fire.gdshader` quantizes `p`, then rotates only the shape *lookup* (`shape_radius(a -
u_shape_rot)`); `juggle.gdshader` quantizes `p`, then rotates only the ball's *shading* frame for
spin. Neither ever rotates `UV` before `fx_quantize`.

**This extends to `ParticleEngine`.** Particles must not carry per-instance rotation on a
quantized sprite — a rotating ember is a rotating grid. Either keep particle sprites rotation-free
(recommended: embers are blobs, orientation carries nothing) or snap any rotation to 90° steps.
The `MultiMesh` transform should carry position and uniform scale only.

**Known trade-off, deliberately accepted:** quantization happens in *quad-local* space, so the
grid travels with the card rather than being anchored to the screen. The fire's pixels therefore
stay stable relative to the card (no crawling as it moves) but do not line up with screen pixels.
That is the right side of the trade, because the card's own art does not line up either — it is a
smoothly-positioned, scaled `Polygon2D`. Snapping FX to the screen grid while the card underneath
moves smoothly would make the fire visibly detach from it.

---

## 12. Code smells found on review (2026-07-27)

Fixed in place above:

- **§5a — `FxAttachment` hardcoded the effect list.** `sync(fire_stacks, ball_stacks, ball_fire)`
  is a parameter list that grows with every effect, and it puts knowledge of *which effects exist*
  in the FX layer. Every new visual status would have edited it. Now statuses declare their own
  via `fx_request()`, mirroring the `draw_icon` idiom the project already uses — a new visual
  status is a new class and nothing else.
- **§5a — `RefCounted` owning `Node`s.** Muddy ownership (who frees the quads?) and no
  `_process`. It is a `Node2D` now, and it *is* the `Fx` node of §2's tree.
- **§5a — `ColorRect` in a Node2D subtree** would have eaten the mouse events card grabbing
  needs. `MeshInstance2D` + `QuadMesh`.
- **§4c/§5f — the quad was sized to the card's box** while being world-aligned around a card that
  turns through every angle. Now the diagonal.
- **§4c — `fx_fbm` ran on every fragment**, including the empty majority.

Still open — decide when you reach them:

- **12.1 Pixel density is in the wrong file.** `fx_pixel_card` / `_prop` / `_ball` sit in
  `player_settings.gd`, but §5g's own rule is that player settings hold what the *player* moves.
  Density is an art decision → it belongs in `FxStyle` with the other ~35 levers. Only
  `fx_intensity` (an accessibility control) is genuinely a player setting.
  *(Resolved 2026-07-27: `pixel` is an `FxStyle` lever; only `fx_intensity` and
  `fx_transition_fraction` are player settings.)*
- **12.2 Two style systems, two locations.** `FxStyle` lives in `Shaders/Styles/` and
  `ParticleSpec` has no home, yet ruling 8 asked for *one* place for all visual-effect tuning.
  Put shaders, styles and specs under a single `res://Fx/` tree — `ember.tres` living in a folder
  called `Shaders/` is already wrong.
  *(Still open 2026-07-27: everything DOES live in one place — `Shaders/Styles/` — which is what
  ruling 8 asked for, but the folder name is now wrong. Renaming the tree to `res://Fx/` is a
  separate mechanical change.)*
- **12.3 `u_mode` / `u_shape` are magic ints duplicated across the language boundary.** GDScript
  and GLSL cannot share an enum, so `0 = card, 1 = ring, 2 = blade` exists twice and can drift
  silently. Either name them in a GDScript enum with a test asserting the mapping, or split the
  shapes into `#include` variants and delete the switch. The one-shader-with-branches version is
  cheap at runtime (the branch is uniform across the quad) — this is a maintainability cost, not
  a performance one.
  *(Resolved 2026-07-27: named `const int` in the shader, `enum` in `FxAttachment`, and the FX
  ATTACHMENT suite reads the constants out of the shader source and asserts the mapping.)*
- **12.4 `PropVisual.fire_tips` becomes a misnomer at T10**, once `_draw_fire_tips` is deleted and
  it is only a stack count. Rename to `fire_stacks`, matching `PropData`. *(Done 2026-07-27.)*
- **12.5 `_transition_secs()` reaches through `play_area.prop_layer`** — two hops through
  unrelated objects, and it returns 0 in every viewer (no play area), so viewer cards would snap
  where board cards ease. Ruling 18 wants them identical. Read the tick duration from the Game via
  `CardEnvironment`, with a settings fallback when there is no game.
  *(Resolved 2026-07-27: `FxAttachment.transition_secs()` reads the Game via `CardEnvironment`
  and falls back to `settings.base_delay`.)*
- **12.6 Some shader constants are levers and some are baked, with no principle.**
  `0.6 + 0.4 * dome` (shoulder falloff) and the `* 0.15` dither scale are hardcoded while
  neighbouring numbers are uniforms. Promote them or write down why not.

Two real bugs the review turned up:

- **12.7 ⚠ Mutating `ball_fire` does not emit `data_changed`.** Only
  `CardModifierStatus.stacks`' setter emits it (`card_modifier_status.gd:9`), so a ball catching
  fire *without* the ball count changing would never refresh the data texture — the plume would
  simply not appear until something else touched the card. Route `ball_fire` writes through a
  setter that emits, and test exactly that case: change `ball_fire` alone, assert the texture
  updated. *(Fixed 2026-07-27, with that exact test.)*
- **12.8 ⚠ Ember spawn position is undefined.** §4e says "call `ParticleEngine.emit(...)`" and
  never says *where*. The visually correct answer is "from the flame tips", but tip positions are
  computed in the shader, and replicating `tendril()` in GDScript to find them would be exactly
  the duplicated-motion bug that `fx_common.gdshaderinc` exists to prevent (§6). **Decide
  explicitly and cheaply:** spawn from a random point along the host's top contour, scattered by
  `u_height`. It is an approximation, it is one line, and writing that down stops the next person
  from trying to mirror the shader on the CPU. *(Implemented as specified 2026-07-27.)*

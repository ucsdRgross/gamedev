# PALETTE_PLAN_BRIEF.md — the brief for writing the universal-palette plan (T21)

**This file is NOT the plan.** It is the scoping brief for the agent who writes the plan, so that
agent spends its budget on design decisions instead of re-running the audit. Your deliverable is a
plan doc (`PALETTE_PLAN.md`) written to [START_HERE.md](START_HERE.md)'s workflow: audit facts →
numbered questions with **owner APPROVAL lines** → steps that each leave the game runnable → test
plan → owner verification checklist. **Write the plan; implement nothing until the owner rules on the
approval lines.**

Read first: [START_HERE.md](START_HERE.md) (rules + workflow), then ARCHITECTURE_REVIEW **§4h**
(the current recolour contract) and **§4g** (how FX colour works today). The owner's original ask is
FX_SHADER_PLAN.md T21.

---

## 1. The owner's requirement, verbatim

> *"colors should come from universal palette ... given a palette (1xN pixel image), we can assign
> to every color using system in the project a color from the palette via some resource of
> pointers, and make it easy to reassign to different colors especially if the palette changes."*

Two demands, and they are separable: **(a)** every colour in the game resolves to a palette entry,
and **(b)** reassigning one is editing ONE named entry in ONE place. (b) is the part that makes a
palette swap survivable, and it is the part a naive "just replace the literals" pass would miss.

---

## 2. Audit — measured 2026-07-27, from files, not docs

Do not re-derive this; DO re-verify anything you are about to change (docs go stale, code wins).

### 2.1 What the palette is

| Fact | Where |
|---|---|
| The live palette: **32×1** PNG, 32 distinct colours | `Assets/CircusCrayon.png` |
| Dead palettes still in the repo, referenced by nothing | `Assets/CircusCamping.png` (24×1), `Assets/palette.png` (20×1) |
| The recolour shader: VisualShader sampling the palette at `(color_x + 0.5) / num_colors` | `Assets/color_picker.tres` |
| It replaces **RGB only** — the polygon's texture supplies alpha, so it flattens whatever it touches to ONE flat colour | same |
| `num_colors` now lives **only** as that shader's default (32). The three `card_visual.tscn` overrides that said 20 were deleted 2026-07-27 | `Assets/color_picker.tres` |
| Suit → index is a magic array, `[30, 11, 8, 2, 14]` (hoop, knife, ball, fire, firework) | `Cards/Pips/pip_suit.gd` |

### 2.2 Who is already ON the palette

- **Suit pips** (`Assets/suit_pips.png`) — authored IN the palette, multi-tone per frame, drawn with
  no material at all. Also the ball and fire PROP art (same frames). Nothing to migrate.
- **Rank pips** and **card art** — single-colour silhouettes, recoloured through `color_picker.tres`
  to `PipSuit.PALETTE[suit]`. Already a pointer; it just has no NAME.
- The hoop and knife prop sheets are authored in the palette too (hoop = indices 5 + 6, knife = 10 +
  11 + 12), baked into the images, no material.

### 2.3 Who is OFF the palette — measured, with numbers

**This is the answer to "do the VFX have wrong colours?" — they are not corrupted, they are simply
not from the palette at all, and a palette swap will not touch them.**

| Offender | Measured | Where |
|---|---|---|
| The fire ramp | **64 distinct opaque colours, exactly 0 of which are palette entries.** Nearest-palette distances run from 11 to 76 (in 0–255 RGB) | `Shaders/Styles/fire_ramp.png`, baked by `tools/make_fx_ramp.py` |
| Ball colours | `ball_lit` (255,209,89) dist 80 from its nearest entry · `ball_shade` (184,115,31) dist 40 · `ball_gloss` (255,250,217) dist 43 | `FxStyle` defaults + `Shaders/Styles/juggle_default.tres` |
| Ember gradient | a `Gradient` of 3 interpolated colours | `Shaders/Styles/ember.tres` |
| Everything else hardcoded | **20** `Color(...)` literals in non-test, non-addon scripts, and **8** scenes/resources carrying colour literals | map controller, player token, card focus modulate, formation editor, `FireworkVisual`, … |

**The trap that makes this more than a find-and-replace:** two mechanisms currently GENERATE
in-between colours, so palette-valid endpoints are not sufficient.

1. `tools/make_fx_ramp.py` interpolates every ramp row between a `COLD` and a `HOT` band table —
   that interpolation is where most of the 64 colours come from.
2. `juggle.gdshader`'s sphere banding does `mix(u_shade, u_lit, step/(bands-1))` (added 2026-07-27
   for T18). At `ball_bands = 3` the middle band is the average of the two — e.g. (220,162,60),
   which is 49 away from its nearest palette entry even though both endpoints were chosen by hand.

So the plan must decide: **a palette-driven effect's band colours have to be SAMPLED from an ordered
list of palette entries, not lerped between two.** That is a shader-and-generator change, not a
data change, and it is the single most consequential decision in this plan.

---

## 3. The design the owner already described (start here, don't redesign it)

FX_SHADER_PLAN T21 sketched this and the owner has not objected to it:

- **`Palette` (`Resource`)** — wraps the N×1 texture; `width` derived FROM the texture, never
  hand-entered. Swapping palettes = swapping this resource.
- **`PaletteRoles` (`Resource`)** — the "resource of pointers": semantic ROLE → index. Roles are
  named for MEANING (`fire_core`, `ball_lit`, `ui_focus`), never for colour (`orange`) — that is
  what survives a swap.
- **`PaletteManager` (autoload)** — holds the current `Palette` + `PaletteRoles`; `color(role) ->
  Color` for GDScript drawing, `index(role) -> int` for `color_x`; emits `palette_changed` so live
  materials re-push, exactly as `SettingsManager` does. `num_colors` comes from the texture width.

Your job is not to invent this; it is to pin down the parts it does not answer (§4) and to sequence
the migration so the game runs after every step (§5).

---

## 4. The questions your plan must answer — each needs an owner APPROVAL line

These are the real decisions. Recommend a default for each; the owner rules per item.

1. **Roles as a Dictionary or as named `@export`s?** A `Dictionary[StringName, int]` is open-ended
   but typo-prone and invisible to autocomplete; a resource with one named `@export_range(0,31)` per
   role is inspector-friendly and compile-checked but needs an edit to add a role. *(Recommend:
   named exports for the fixed set, since the role list is small and stable.)*
   Input: named exports since it might allow visualizing color in editor while choosing int
2. **What is the role list?** Enumerate it in the plan — one row per role with what it colours. Derive
   it from §2.3, not from imagination. Suits alone are 5; fire needs an ordered ramp; balls need
   3 + however many bands. Input: yes
3. **Ordered ramps: how is a heat ramp expressed as roles?** An `Array[StringName]` of roles from
   core to rim? A separate `PaletteRamp` resource? And is `fire_ramp.png` (a) regenerated at build
   time from roles, (b) built at load into an `ImageTexture`, or (c) replaced by sampling the palette
   texture directly in the shader with a role-index array uniform? *(Recommend (b): no build step, no
   new shader plumbing, and a palette swap recolours fire the moment `palette_changed` fires.)*
   Input: No palette swapping at runtime, we can simulate that with different status effect with its own palette. Should still have large color ramp for increasing intensity, but ramp should still be preset. Choose whatever option is fastest and allows most in tune editing. I think PaletteRamp makes most sense, since it can be reusable for other effects. For example, ramp could have 10 colors, and fire ramp can focus on window of 3 and move through the ramp when intensity increases.
4. **Banding must sample, not lerp** (§2.3). Confirm the owner wants band colours to be exact palette
   entries — it changes how the balls look (three chosen tones instead of an even ramp), so it is a
   LOOK decision, not just an architecture one. Input: Yes exact colors from palette. blending can create unpredictable and bad looking colors
5. **How strictly universal?** Does "every colour" include UI chrome, map, debug/editor tools, and the
   `@tool` formation editor, or only in-game art? *(Recommend: art + UI chrome in scope; debug and
   editor-only tools explicitly out, and say so in the doc so the next person does not "finish" it.)* Input: only in game art during play. Debug and tests are whatever.
6. **Enforcement.** Is there a test that FAILS on a new hardcoded `Color(...)` in the view layer, or
   is this convention-only? A grep-based test is cheap and is the only thing that stops re-drift.
   *(Recommend: a test with an explicit allowlist.)* Input: Sure let's fail some tests, but only as warnings, not true errors that means something needs to be fixed, just that something in scene is still a placeholder.
7. **What happens to a role whose index is out of range** after a palette shrinks (32 → 16)? Clamp,
   push_error, or refuse to load? *(Recommend: `push_error` + clamp — never a silent wrong colour,
   never a crash on load.)* Input: yes, but I have already decided palette will never be smaller than 32 so this step may be unnecessary for this plan.
8. **`@tool` safety.** `PaletteManager` is an autoload; the formation editor and both FX hosts are
   `@tool` scripts that run with no autoloads in some contexts. What is the fallback — a static
   default, or does every call site null-check? *(This is the most likely source of an editor-only
   crash; ARCHITECTURE_REVIEW §4g's "both FX hosts are `@tool`" trap is the precedent.)*
   Input: Autoload seems kind of overkill and has bad code smell? Can't everything be static instead? Don't expect colors or ramps to change at runtime. If I remember correctly formation editor exports to a statis resource that gets used by anything, we can do same thing here. Null check every time seems overkill, should never be null if stuff is working right, if its null and I get runtime error that means immediate need to fix, final product should have no null.

---

## 5. Sequencing constraints your plan must respect

- **Every step leaves the game runnable and the full suite green** (26 suites today).
- Suggested order, refined from FX_SHADER_PLAN T21: (1) resources + autoload + a test that every role
  resolves inside `0..width-1`; (2) repoint `PipSuit.PALETTE` at roles; (3) `num_colors` from the
  manager instead of the shader default; (4) the FX ramp + ball colours + ember gradient — LAST,
  because it is the one with a look change in it; (5) only then delete the two dead palette PNGs.
- **Save format is not involved.** Colour is presentation; nothing here touches `run.tres`. Say so
  explicitly in the plan's migration section so nobody adds a save migration.
- **Pixel art is authored in the palette and stays that way.** Do not add a recolour pass over
  `suit_pips.png` / the prop sheets — they are already correct, and recolouring them would flatten
  their shading (ARCHITECTURE_REVIEW §4h).

---

## 6. How the plan gets verified

- **Headless:** roles resolve in range; `num_colors` equals the texture width; a swapped `Palette`
  changes what `color(role)` returns; the anti-drift grep test.
- **Pixels — required, this is a colour feature.** Extend `Tests/Visual/prop_art_snapshot.tscn`
  (which already has a per-suit recolour shot) and re-run `fx_snapshot.tscn`. The decisive check is a
  **swap test**: point the manager at a deliberately different palette, re-shoot, and confirm every
  surface moved. Read the PNGs; run both scenes yourself (windowed, GPU, they self-quit).
- A **palette-conformance script** is worth writing: walk the captured PNGs and assert every opaque
  pixel is exactly a palette entry (allowing the FX quads' alpha blending). That is the only check
  that actually proves "universal", and today it would report 64 violations from the fire ramp alone.

---

## 7. Out of scope — do not fold these in

- Retuning what the colours ARE. This is plumbing; if the fire looks worse on-palette, that is an
  owner art decision, raised separately.
- The FX feature itself (T15 owner playtest, T16 doc pass + deleting FX_SHADER_PLAN.md).
- `FireworkVisual` has no art yet; it is a placeholder polygon, not a palette problem.

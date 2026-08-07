---
name: solatro-card-outline
description: Solatro card grew 38x50 -> 40x54 and every element wears a shader outline; landed 2026-08-06, suite green except GAP-001 (board wider than the window)
metadata:
  type: project
---

**Landed 2026-08-06.** The card is `40x54` and `Shaders/outline.gdshader` draws a 1-unit,
8-directional palette rim around all five elements (face, rank/suit/stamp pips, art). It absorbed and
replaced `Assets/color_picker.gdshader`. Design record: `solatro/design/card_size_outline/`
(IMPACT.md is the inventory; ASSUMPTIONS.md logs what implementation decided beyond it).

**The rules that must not regress live in `ARCHITECTURE_REVIEW.md §4j`** — read that, not this. The
two most easily broken: no polygon on a card may be left material-less (they are POOLED, so a `null`
strips the rim from whichever cards land on a recycled node), and `_bind_rig`'s `per_texel` must
divide by the INNER rect, not `CARD_SIZE`.

**Suite: 30 suites, ~1880 checks, 1 deliberate failure.**

- ⚠ **`gaps/GAP-001.md` is OPEN and its test is left RED on purpose.** A 7-column board is now wider
  than a 1152-px window (a fire prop spawns at x=1187); the card gained 5 px per column and the board
  was already sitting exactly on the edge. Three ways out, all game-feel calls for the owner. Do not
  "fix" it by relaxing the check — that check exists because the owner reported props never showing.
- The LEAK CANARY object-count check is **intermittent** here (growth 0/1/2 across a dozen runs, both
  before and after this work). Judge it across runs, not on one.

**ALL outline tuning is one RESOURCE the game reads** — `Shaders/Styles/outline_default.tres`
(`OutlineStyle`), instance `CardOutline.STYLE`: rim ink + width, and each alert kind's own colour,
tempo, thickness and side buffer. The atlas edits that same resource, so tuning there moves the board
(the `fx_editor`/`FxStyle` arrangement). ⚠ `art_outline`/`alert_glare` were MOVED OUT of `roles.tres`,
not copied — §4i's rule is one home per pointer, not "every pointer in PaletteRoles"; `PaletteRamp` is
the precedent. ⚠ `width` above `CardOutline.WIDTH` clips (the const is geometry — the polygons are
baked at `frame + 2*WIDTH`). `glare_buffer` exists because a card's side rims are vertical lines, so an
unbuffered band lights a whole side at once at the turn — a blink, not a sweep.

**Three override layers, resolved LATE:** shipped style → the TYPE's own
(`CardModifierType.outline_style()`) → the individual `CardAlert`'s fields. Every `CardAlert` number is
the sentinel **-1** until push time; resolving at construction bakes the shipped defaults in and makes
the type layer unreachable, which looks right on the default type and wrong on every other.

**Two open eye calls, both on `tools/outline_atlas.tscn`** (`@tool`, shows every non-empty frame
through the real draw path — 127 of them, not the 114 the design counted):

- the rim MERGES the dense `suit_art` frames — the high-rank ones invert into a dark lattice. Art
  decision, not a bug.
- the alert's look (GLARE / THROB) is implemented and live-tunable but unjudged.

**Two editor-only breakages this shipped with on the first pass, both now fixed and both invisible to
the test suite** — the suite was green while the owner's editor was broken:

1. **`tools/` is LOWERCASE on disk while every `res://` path said `Tools/`.** Old scenes survived on
   `uid=`; a NEW scene referencing by path registered the script twice → *"Class X hides a global
   script class"* → parse error → `palette_roles.gd` became a PLACEHOLDER → the editor re-saved
   `roles.tres` **with every role index gone**. Also cached in `.godot/editor/*.cfg`, which had to be
   rewritten separately. All paths normalised to lowercase.
2. **A built-in sampler (`TEXTURE`) passed to a user shader function** compiles on the GLES3 runtime
   path and is REJECTED by the editor's shader compiler. Tap inline in `fragment()`.

⚠ The general lesson, now in ARCHITECTURE_REVIEW §4j: **a green suite says nothing about whether the
editor can open the project.** Run `Godot -e --headless --path solatro --quit` and grep for SCRIPT
ERROR after touching `@tool` scripts, shaders or `class_name`s.

**Two more traps found building the atlas's card preview, both in §4j:**

3. **Add a `CardVisual` to the tree BEFORE assigning `data`.** The setter's `update_visual()` awaits
   `ready`, so configuring an out-of-tree card suspends the face build forever. Symptom is a card that
   reports visible, with textured polygons at correct global transforms, drawing **nothing**. Skinning,
   SubViewports and the basis3d mirror all look guilty and are not.
4. **`CardOutline.set_card_offset` exists for grid-laying tools.** `frame_polygon` takes the card
   offset from `poly.position`, right on a card and wrong in an atlas — the alert band is card-space
   and only lit 3 frames of 126 until the offsets were pushed per sheet.

**Owner corrections to the design doc, worth knowing before re-reading it:** the re-authored
`card_types.png` KEPT its painted perimeter ring (recoloured per type) rather than removing it — the
owner confirmed painted inner line + shader outer rim is intended. And their `new_animation_2` had a
half-converted key that made every card pop once per loop; both animations were rebuilt from the §1d
ratios.

# ASSUMPTIONS — card size + outline

Decisions taken during implementation that IMPACT.md did not cover, and that were reversible and
clearly within intent (CLAUDE.md's gap protocol). Anything that was not, went to `gaps/`.

---

**A1 — GLARE needed a colour after all.** D6 is right that an alert is a MODE, not a colour — that is
what makes it read as an alert. But a band still has to be painted in something. It ships at **31
`#eddcc0`**, the light entry most type frames are dominated by, so it reads against the dark inks the
rim defaults to. ⚠ Unlike the rim's 28 this has no measured precedent: it is a starting point, judged
on the atlas. ⚠ **SUPERSEDED in placement (see A12):** it began as an `alert_glare` palette ROLE and
now lives in `OutlineStyle` with the rest of the outline's tuning.

**A2 — THROB is quantized, not blended.** A continuous mix between two palette entries spends most of
its time on colours in no palette at all, which the rest of this project does not do. It toggles on a
`step(0.5, …)` of the bounce instead. Same reasoning as the glare band being hard-edged rather than
smoothstepped.

**A3 — When several statuses alert at once, the LAST declared wins.** The shader runs one kind at a
time. `_fx_requests` already resolves "several statuses, one card" as *later draws on top*, and the
status list is ordered, so the alert follows the same tie-break rather than inventing a priority.
§2e.4's requirement — that clearing one of two alerts must not switch off the other — is satisfied by
the list being RE-DERIVED, which is a stronger property than any tie-break.

**A4 — `generate_editor_mesh` now pads by `ART_OUTLINE` unconditionally**, rather than gaining a
checkbox. The bake tool built polygons at exactly frame size, which is correct for a polygon that
draws nothing but its art and wrong for every polygon on a card. A checkbox is a thing to forget, and
forgetting it silently deletes one element's outline and makes its art 25 % too big. Every polygon
this tool bakes is a card polygon.

**A5 — the skeleton bake was re-parented to `Offset/Visual`.** It looked its skeleton up at
`"Skeleton2D"` and re-added it with `add_child(self)`, while the shipped scene keeps it at
`Offset/Visual/Skeleton2D` and `_bind_rig` reads it from there. So a re-bake found nothing to replace,
left the real skeleton alone and parented a second one at the root. Fixed rather than documented,
because the tool was going to be run as part of this very change.

**A6 — both idle-animation tracks were rebuilt from the §1d RATIOS, not scaled from the file.** The
working tree's `new_animation_2` had been partly converted: `Arm_TopLeft` started at y −26 (the new
rest) and ENDED at y −25 (the old one). It loops, so every card crept and popped once per cycle.
Rescaling what was there would have preserved the defect. Every key is now `ratio × new rest`, with
the ratios read off the original 38x50 authored animation exactly as §1d records them.

**A7 — `EDGE_WEDGE_DRIFT` 1.5 → 1.7 and `CORNER_BITE_DRIFT` 2.5 → 2.6 in `test_pixels`.** Both are
MEASURED constants and both carry a "DO NOT RAISE IT TO GO GREEN" warning, so they were re-measured
deliberately (raised to 99, worsts read off the loop, put back with headroom in the same proportion
the originals had). The increase is the model, not a regression: the edge error is a chord across an
angular slot and the corner error is a fraction of the corner cell, so both are proportional to the
card's size and a bar that stayed put would have silently tightened every time the card changed. New
worsts, all four poses: edge 0.00 / 0.48 / **1.50** / 0.00, corner 0.00 / 1.21 / **2.45** / 2.39.

**A8 — `test_pixels.test_one_pixel_size_for_all_art` now pins its own zoom.** While it compared two
8-unit draws of one frame, whatever zoom the previous shot left behind applied identically to both and
cancelled. The pip is 2 units bigger now, so a fractional zoom rounds the two footprints differently
and the difference stops being a whole number of art units.

**A9 — `Assets/color_picker.gdshader` was DELETED, not left orphaned.** §3a says "superseded by / folded
into" and the fold is complete: its whole body is `outline.gdshader`'s PALETTE fill mode. Leaving the
file would have left a second, materially different way to recolour a card element.

**A10 — the atlas tool draws TWO backdrops, not one.** The first version put every frame on the board
colour, where the default dark ink is nearly invisible — which looks like a damning finding and is the
wrong question, because a pip never sits on the board, it sits on the card's face. Types are drawn on
the board colour and everything else on `#eddcc0`. Judging the ink against the wrong background is the
one way this tool could actively mislead.

---

## What the atlas actually showed, 2026-08-06 (eye check, CLAUDE.md rule 4)

Rendered `tools/outline_atlas.tscn` at zoom 3 and looked at it. **126 non-empty frames**: the
re-authored `card_types.png` carries **27**, not the 15 §11's table recorded, so that table is stale
in the owner's favour — more art, same one screen.

- ✅ The rim is present on every frame, one unit, and 8-directional (the diagonals on the suit-art
  shapes carry their corner texels).
- ✅ Against the card face the default `#290d2c` reads clearly on both the recoloured red art and the
  in-palette pips. Against the board, the card's own rim reads.
- ⚠ **THE MERGE IS REAL, AND IT IS THE ONE THING TO LOOK AT.** On the highest-rank `suit_art` frames —
  the ones packing nine or more small pips into 32x32 — a one-unit rim closes the gaps between adjacent
  pips and the frame inverts: it reads as a dark lattice with red holes rather than as countable pips.
  This is exactly the failure §11 predicted ("details 2 px apart merging into a blob once each grows a
  1-px rim"). It is an ART finding, not a bug — nothing in code is wrong — and the fixes are art-side
  (space those pips by 3 instead of 2) or scope-side (exempt the 32x32 art from the rim). **The owner's
  call; nothing was changed on their behalf.**

---

## Added after the first landing (2026-08-06)

**A11 — the atlas now edits a RESOURCE the game reads** (`OutlineStyle`). Owner: *"does tuning in atlas
tool affect real game? it should just like all the other tools."* It did not — the knobs were local
`@export`s. Same arrangement `fx_editor` has with `FxStyle`.

**A12 — the outline's colours moved OUT of `PaletteRoles`.** §4i's rule is one home per palette
pointer, not "every pointer in that file"; `ramp_fire.tres` has always held its own indices. Deleted
there, not copied.

**A13 — `OutlineStyle.width` is NOT clamped to `CardOutline.WIDTH`.** Above it the rim clips at the
polygon edge. A silent clamp would hide that widening costs a scene re-bake; the atlas shows the clip.

**A14 — three override layers, resolved LATE.** `CardAlert` fields are `-1` sentinels resolved at push
time against the card's style, so a TYPE's `outline_style()` stays reachable for anything a status did
not name.

**A15 — `glare_buffer` ships at 4**, chosen by eye from a buffer-0-vs-4 comparison rendered at the
turn of the sweep, not derived.

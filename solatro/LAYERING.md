# LAYERING.md — board rendering order (draw-order reference)

The `solatro` board (`Levels/game_view.tscn` → `UI/play_area.tscn`) draws its whole board — the
grids, the Entrance, the score gutters, the props and the overlays — on **one canvas layer** — there is **no `CanvasLayer` anywhere**. The entire board
draw order is **structural**: every board `CanvasItem` stays at **`z_index == 0`** and order is
decided purely by **sibling position + parent nesting** (Godot draws a parent before its
children, and earlier siblings before later ones; ties at equal effective z break by tree
traversal order). This document lists the resulting order, every moment it can change, and the
layering-issue audit.

> **Reading the nested list below:** it is written in draw order — **the bottom of each group
> renders ON TOP.** Annotations give the *structural reason* for each item's position, never a z
> magnitude (there are none left in the board draw path).

---

## Why all-structural (no z_index) — the fact that drove it

Godot resolves each item's effective z through the `z_as_relative` chain (child effective z =
own `z_index` + parent's, default on), then sorts by that single resolved number **across the
whole canvas**; **tree order only breaks ties between items at *equal* resolved z.** So you
cannot mix a structural scheme with any stray nonzero z — a status at relative `z=1` resolves to
`1` and would draw over a prop at `0` regardless of tree position. Therefore **every board
CanvasItem is kept at `z_index == 0` and order is 100% tree-structural** (later sibling / higher
child index wins at equal z). `z_index` is also clamped to **[−4096, 4096]**, so the rejected
"big numeric bands" alternative (`100000`) was never even valid.

The one ordering primitive that carries a small integer is `move_child`'s **child index** — that
is a *tree position*, not a global z, and cannot be out-bid by an unrelated node acquiring a
bigger number.

---

## The nested draw-order list (bottom of each group renders ON TOP)

⚠ **THE BOARD HAS TWO CARD LAYERS NOW, AND THEY ARE NOT SIBLINGS OF EACH OTHER.** The grids live
inside the scroll container; the **Entrance** is a `Control` sibling of that container, with its
own `EntranceCardLayer`. `PlayArea` orders each layer independently, with `move_child` calls
confined to that layer alone — a card moving between them is a reparent, not a reorder.

```
game_view.tscn  (single canvas layer 0 — NO CanvasLayer anywhere)
└─ SceneRoot (Control)
   ├─ PlayContainer (Control)
   │  ├─ PlayArea  ── drawn FIRST → underneath the overlays (earlier PlayContainer child)
   │  │  ├─ SmoothScrollContainer → TopLevelVBox   (clip_contents=false; carries scroll)
   │  │  │  ├─ GridContainer (HBoxContainer)  ── ONE GridPanel per GameData.grids entry,
   │  │  │  │    │                               left to right, all bottom-aligned on one floor
   │  │  │  │    │  ⚠ IT CLIPS. A grid outside the board's window is OUT OF VIEW, not merely
   │  │  │  │    │    out of position — unclipped, a non-focused grid painted across the Deck
   │  │  │  │    │    button and the score column while its geometry was already correct.
   │  │  │  │    └─ GridPanel (VBoxContainer, ALIGNMENT_END)
   │  │  │  │       └─ Board (HBox)
   │  │  │  │          ├─ RowLabels (VBox)      — row scores, LEFT of the cells
   │  │  │  │          ├─ CellsColumn (VBox)
   │  │  │  │          │  ├─ Cells (VBox, ALIGNMENT_END) → one GridRow HBox PER ROW
   │  │  │  │          │  │    ⚠ ONE CONTAINER PER ROW, never one GridContainer for the panel:
   │  │  │  │          │  │      a real grid gives every cell the row's full height, so a cell
   │  │  │  │          │  │      has nothing to bottom-align against and a deep stack bleeds
   │  │  │  │          │  │      into the row above.
   │  │  │  │          │  └─ ColLabels (HBox)   — column scores, BELOW the cells, and a SIBLING
   │  │  │  │          │                          of Cells so the container puts each label under
   │  │  │  │          │                          its own column with nothing measuring an indent
   │  │  │  │          └─ SpecialLabel          — the ONE shared special-meld score, RIGHT of the
   │  │  │  │                                     grid, centred, opposite the row labels
   │  │  │  │       (all of these are invisible card-anchor Controls + BigNumberLabel gutters;
   │  │  │  │        earlier VBox siblings → BELOW CardLayer/PropLayer/OverlayLayer)
   │  │  │  ├─ CardLayer (Node2D, z 0)   ── THE GRIDS' cards  [earlier sibling → below props]
   │  │  │  │   ├─ CardVisual per card — CHILD INDEX assigned by _append_grids_row_major:
   │  │  │  │   │    · grid 0 before grid 1 before grid 2
   │  │  │  │   │    · within a grid: every CELL ZONE card first (so a card always draws OVER
   │  │  │  │   │      the cell frame it sits on), then the stacks HEIGHT-MAJOR — all of h 0
   │  │  │  │   │      across every cell, then all of h 1, and so on
   │  │  │  │   │    · GRAB LIFT: a held card is skipped by the ordering pass entirely and
   │  │  │  │   │      stays at the layer's end (above all resting cards, below PropLayer)
   │  │  │  │   │    └─ inside each CardVisual (Offset → Visual), tree order:
   │  │  │  │   │       ├─ Type / Rank / Suit / Stamp Polygon2D
   │  │  │  │   │       ├─ Art Polygon2D            (last face polygon → on top of the face)
   │  │  │  │   │       └─ StatusLayer (Node2D)     (added LAST under `visual` → on top; no z)
   │  │  │  │   └─ two _PropHalf nodes per occupying split prop, BRACKETING the occupied
   │  │  │  │       CardVisual: BACK half move_child'd to JUST BELOW it; FRONT half JUST ABOVE
   │  │  │  │       it. Both parented to the STABLE CardLayer (never to the card), transform
   │  │  │  │       synced to the PROP each frame so they never inherit the card's jump or drag.
   │  │  │  │       The card passes THROUGH the ring.
   │  │  │  ├─ PropLayer (Node2D, z 0)     [later sibling than CardLayer → above ALL grid cards]
   │  │  │  │   └─ PropVisual per live prop (order = add/tree order)
   │  │  │  │       └─ _draw(): non-split → whole body here; split (hoop) while over a card →
   │  │  │  │          nothing here, both arcs drawn by its two _PropHalf bracket nodes
   │  │  │  ├─ ParticleLayer (Node2D, z 0) — ParticleEngine's world debris; no host to be
   │  │  │  │                                occluded by, so ruling 2 does not apply to it
   │  │  │  └─ OverlayLayer (Node2D, z 0)  [LAST TopLevelVBox sibling → on top of the board]
   │  │  │     ├─ Focus inspector panel (PanelContainer)   — no z; tree order
   │  │  │     └─ Score TextPopup (Node2D, transient)      — no z; tree order
   │  │  └─ EntranceStrip (Control)  ── LATER PlayArea SIBLING → the whole Entrance draws OVER
   │  │     │                            the scrolled grid content, which is what lets a card
   │  │     │                            wait above a grid without being clipped by it
   │  │     └─ EntranceHTrack → EntranceVScroll → EntranceContent
   │  │        ├─ UpperZone (HSplitContainer) → UpperZoneLeft / UpperZoneRight
   │  │        │    (the Entrance's own anchor Controls; still the legacy `upper_zone` arrays)
   │  │        └─ EntranceCardLayer (Node2D, z 0) ── THE ENTRANCE'S cards, ordered by
   │  │             _append_zone_row_major: headers first, then each depth across all slots
   │  ├─ WinScreen (Label)  ── above PlayArea (later PlayContainer child, by tree order)
   │  │   └─ Dim (ColorRect, show_behind_parent → behind the Label text)
   │  └─ LoseScreen (Label) └─ Dim (ColorRect, show_behind_parent)
   ├─ Submit / Undo / Reroll (Buttons)   ── "Submit" is the node's NAME; it ends the show
   ├─ HUD Labels (ScoreName / Score / MultScore / Total / Goal / Turns / Rerolls / Preview)
   ├─ Deck / Discard / Rules (Control + Button)
   ├─ Background (TextureRect, visible=false; if shown, paints over SceneRoot — no back layer)
   └─ LightLayer (ColorRect, full rect, mouse_filter=IGNORE)   [LAST SIBLING → over EVERYTHING]
       · the spotlight dim, circles and beams — one screen-space surface, NOT scrolling
       · ⚠ ITS POSITION IS A CONTRACT, not a convenience. The dim exempts NOTHING — props,
         score popups, the focus panel and the HUD all dim, and so does the card glow, which is
         the entire mechanism by which a glow reads only inside its circle or beam. MOVING IT
         EARLIER SILENTLY UN-DIMS whatever now draws after it, with no error and no failing
         test — the symptom is "that one thing never goes dark".
```

⚠ **"ROW-MAJOR" ON THE GRID MEANS A HEIGHT LAYER, NOT A SCREEN ROW.** `_append_grids_row_major`
emits `for h: for every cell`, so one height layer is contiguous in `CardLayer` and a screen row
`y` is scattered through it. That is deliberate and `PlayArea.row_card_visuals` agrees:
`PropLayer._row_bounds` brackets `[first..last]` of whatever set it is handed, so a
non-contiguous set would swallow every card between its ends. The Entrance agrees by
construction — its depth is a level within a fanned slot, not a screen row.


## Shader FX is a CHILD of its host

Status effects (fire, juggled balls) render as shader quads on an `FxAttachment`, and it is a
**child of the host**, never a board-level layer:

```
CardVisual
├─ Offset
│  ├─ Visual  (Type / Rank / Suit / Stamp / Art / StatusLayer)
│  └─ Fx      ← FxAttachment, added AFTER Visual: draws above the card's own face
```

Godot draws a parent before its children and a whole subtree before the next sibling, so this
gives every requirement at once with no coordination between systems:

- draws over its own card (later child than `Visual`);
- **is occluded by the cards that overlap it** — card *and* FX draw before the next CardVisual in
  CardLayer, so a later card paints over both (owner ruling 2);
- exists in **every view** that shows a card (deck viewer, pack preview, map) for free, since the
  FX is part of the card;
- rides the jump, the card's scale and the focus-highlight `modulate` by inheritance.

**`CardLayer` stays strictly CardVisuals** (plus the hoop half-nodes it already brackets). No FX
node is ever inserted into it, and no `z_index` is touched anywhere — this is pure parent/child
nesting, the most structural ordering primitive there is.

Three rules that are load-bearing:

- **Parent to `Offset`, never to `Visual`.** `Visual` carries the `basis3d` flip, which squashes
  its basis to ZERO at edge-on; an FX quad there would inherit a singular matrix.
- **Never `top_level = true`.** `set_as_top_level` re-attaches the item to the canvas root for
  *rendering*, not just for transforms — it would leave the draw order entirely and break the
  occlusion rule above. The quad cancels its inherited *rotation* instead (see below).
- **The quad holds still; the silhouette turns inside it.** `FxAttachment` sets
  `rotation = -parent.global_rotation` and passes that rotation to the shader as `u_shape_rot`.
  Flames are gravity-aligned, and this is what stops the FX pixel grid shearing against them.

**Split props inherit the split for free.** A hoop gets one attachment per `_PropHalf` bracket
node instead of one on its body, so the ring's back-arc flames sit behind the occupied card
exactly as its back arc does; a `u_half` uniform masks each half's emitters.

**`ParticleLayer`** (`ParticleEngine`) is a plain `Node2D` sibling in TopLevelVBox, between
`PropLayer` and `OverlayLayer`. Its particles are world debris with no host to be occluded by, so
the ruling-2 logic does not apply to them.

⚠ **An Entrance card's FX rides the Entrance strip, so it draws over the grids.** The FX is a
child of its host and the host is in `EntranceCardLayer`, which is a later `PlayArea` sibling
than the whole scroll container — so a burning card waiting in the Entrance burns in front of
every grid, including the props on them. That follows from the strip's position and is correct;
it is only surprising if you expect one card layer.

## Every moment the order can change

- **Board rebuild** (`board_changed` → `queue_rebuild` → `set_card_zones_visuals` →
  `_order_board_cards`, `play_area.gd`): orders **each layer separately** via guarded
  `move_child`s in ascending target order (a still board does zero moves). `EntranceCardLayer`
  gets headers then depth-major; `CardLayer` gets, per grid in order, every cell zone card and
  then the stacks height-major. Targets are assigned only to visuals verified in THAT layer at
  that moment (deduped), so a `move_child` can never go out of bounds by construction.
- ⚠ **A freshly created CardVisual enters the tree deferred and is skipped by that pass.**
  Creation order is COLUMN-major, so without a follow-up a fresh board keeps the wrong order
  until some unrelated rebuild happens — which nothing guarantees, and the symptom was hoop
  halves bracketing scattered indices with back arcs behind the row above (owner report).
  Exactly ONE re-order is queued behind the pending `add_child`s (deferred FIFO: the adds run
  first).
- ⚠ **Grid cards used to get no index at all**, keeping creation order, so a cell frame rebuilt
  after its card drew on top of it. The cell zone cards going first is what fixes that, and it
  is why they lead each grid's block.
- **Card grab / drag** (`grab_cards`): a held card is SKIPPED by the ordering pass, so it stays
  at its layer's end — above every resting card, still below PropLayer. **Restored** by
  `ungrab_cards` → rebuild.
- **Scoring** (`score_line`, `game.gd`, once per completed line): `popup_meld` jumps melded cards (offset only —
  **draw order unchanged**; a later-ranked neighbor can still overlap a raised card); gutter
  labels pop; `popup_score` adds a `TextPopup` to **OverlayLayer**; `_run_score_effects` animates
  props on PropLayer over the jumped cards; `reset_meld` drops the jump after props finish.
- **Prop lifecycle** (`prop_layer.gd`): `_make_visual` adds a PropVisual to PropLayer; a split
  prop lazily builds two `_PropHalf` nodes and `PropLayer._update_back_halves` parents them into
  CardLayer and `move_child`s them around the bracket card's WHOLE ROW **every frame, guarded**
  (`_apply_split`/`_row_bounds`: back anywhere in the inter-row gap before the row's first card —
  behind every card in the row, above every earlier row; front in the gap after its last card —
  in front of the whole row, below the rows beneath; OK positions are ranges, so several hoops
  on one row coexist without churn). The bracket ROW is the prop's own ANCHOR SLOT row
  (`vis.anchor_coord`, re-pinned by every retarget/relocate — reroute modifiers move it with the
  data); GEOMETRY only decides WHETHER to split: the prop's authored body rect
  (`PropVisual.body_size`, hardcoded per kind — CARD_SIZE is no longer the parallel: it is DERIVED now, as `CARD_ART_SIZE + 2 * ART_OUTLINE`) must overlap some card's footprint
  (`_body_over_any_card`). Never derive the row from what's under the prop — fanned cards are a
  full card tall behind their ~strip-high visible slice, so a ring crossing a SHORT column's
  empty row sat "inside" that column's top card's rect and bracketed the wrong row.
  Over nothing → unsplit, whole ring above the board. It also
  mirrors the prop's transform + modulate onto both halves each frame (single fade source).
  Movement is position-only.
  Void-exiting split props keep their back half pinned until the exit frees both.
- **Card reactions** (`_update_reactions`): `anim_jump` / `anim_spin_*` — offset/rotation only,
  **no order change, no reparent**.
- **Focus / hover**: the inspector panel (OverlayLayer child) is shown/pinned; no card order change.
- **Game over** (`_on_show_resolved`): Win/Lose Labels shown (above PlayArea by tree order);
  dismissed on `_on_show_unresolved`.

---

## Method chosen, and alternatives (for future prop kinds)

- **A (chosen) — structural: sibling layers + back-half in `CardLayer` via `move_child`.**
  Coarse order = fixed scene siblings `CardLayer → PropLayer → OverlayLayer`; card-to-card and
  the back-half interleave = `move_child`. No z magnitudes → nothing can out-bid the order by
  acquiring a bigger number. The back half nests directly beneath its occupied card and above the
  row above, scales to any kind via `_draw_back()`, and reuses the existing occupancy tracking.
  Its parent (CardLayer) is **stable**, so it never inherits the card's motion — `PropLayer`
  writes its `global_position`/`rotation` from the prop each frame.
- **A′ (rejected) — absolute z bands (`PROP_FRONT=100000`, `back = card_z−1`).** Relies on large
  hardcoded numbers a future node can out-bid, AND `z_index` clamps to [−4096, 4096] so `100000`
  would not even hold.
- **CanvasLayer / Y-sort (considered, not used).** A `CanvasLayer` does not ride the SmoothScroll
  content transform (props/cards must scroll together); `y_sort_enabled` can't express "this
  ring's back is behind the card at the same Y while its front is in front."
- **B (rejected) — one static back layer below CardLayer.** Cards overlap with per-card order, so
  a single back plane sits behind *all* cards including the row above — can't interleave.
- **C (rejected) — parent the back-half TO the occupied CardVisual (`show_behind_parent`).** Clean
  ordering, but a child inherits the card's transform, so the card's `anim_jump`/drag/float would
  drag the back-half off the prop. A keeps the back-half on the stable CardLayer instead.

---

## Layering audit (latent issues; ✅ = resolved by the structural migration)

1. **Two halves of the board once shared z 1..N** (`card_count` reset per zone → an add-order
   tie). ✅ The halves are now two SEPARATE layers with two separate orderings, and the strip's
   position as a later `PlayArea` sibling decides which draws over which — so there is no tie
   left to break. Within `CardLayer`, `_order_board_cards` gives every CardVisual a unique child
   index across every grid, deterministically.
2. **Held-card z did not clear props/panel.** ✅ Held card is `move_child`'d within CardLayer, so
   it is above resting cards but structurally still below PropLayer and OverlayLayer.
3. **`anim_jump` raises a card without raising its order.** Still true by design — a jumped meld
   card is offset up but keeps its child index, so a later-ranked neighbor can overlap it. Scoring
   depends on this staying a pure offset animation (`reset_meld` drops it after props finish).
4. **All props were at a single z (no prop could go behind a card — the hoop bug).** ✅ A prop
   kind opts into a split (`has_back_half()` + `_draw_back()`/`_draw_front()`); `PropLayer` renders
   it as two `_PropHalf` nodes that BRACKET the occupied card in CardLayer (back just below, front
   just above), so the card passes through the ring and the front stays behind the row below.
   Non-split props still draw their whole body on the PropVisual (above all cards).
   The halves are the sheet's LEFT and RIGHT arcs — the
   ring is a foreshortened oval, so left is its far side and right its near side (ARCHITECTURE_REVIEW
   §4h). The bracket mechanism is unchanged; only which pixels each half draws moved.
5. **Scattered absolute-z constants (cards 1..N, props 100, popup 100, panel 300, status 1).**
   ✅ **All removed.** The whole board draw path is tree/sibling structure; the only new named
   constants are the hoop's art geometry (`HoopVisual.SHEET`/`FRAME_PX` — the sheet's frame size),
   which are draw parameters, not layer numbers.
6. **Score popup and props shared z 100 on different parents.** ✅ The popup is an OverlayLayer
   child (last sibling), unambiguously above every prop.
7. **`Background` is the last `SceneRoot` child, `visible=false`.** Unchanged — if ever enabled it
   paints over the entire board and HUD (there is no back layer). Left as-is.
8. **`clip_contents=false` on the scroll but the play-area rect still clips props/cards**
   (ARCHITECTURE_REVIEW §4b landmine 2). A split prop's back half rides the same content, so it
   is subject to the same clip — a back half staged off the play-area rect edge would be invisible;
   keep it within the clipped rect.

---

## Where this is verified

`Tests/UI/test_visual_layers.gd` ("VISUAL LAYERS", in `all_tests.tscn`) prints the live
draw-order tree at snapshot moments (fresh deal, held pickup, normal prop, hoop occupying a card,
overlay, real GameView deal, end screen) via a reusable dumper that reproduces Godot's canvas
ordering (effective z then tree traversal), and asserts: every board CanvasItem stays at z 0;
CardLayer → PropLayer → OverlayLayer sibling order; CardVisuals row-major; a normal prop above
all cards; a held card above resting cards; StatusLayer above the face; the overlay above
everything; and the hoop's **back half below its occupied card and above the row above, front
half in front** (the card passes through the ring).

It also asserts the FX placement above: a burning card's `FxAttachment` is a child of `Offset`,
draws above the card's own `Visual`, carries no `z_index`, and disappears entirely when the card
turns face-down. `Tests/UI/test_fx_attachment.gd` ("FX ATTACHMENT") covers the rest of the FX
contract standalone — no board and no game, which is the same thing that makes the effects
identical in every view.

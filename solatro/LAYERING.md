# LAYERING.md — board rendering order (draw-order reference)

The `solatro` board (`Levels/game_view.tscn` → `UI/play_area.tscn`) draws its whole board on
**one canvas layer** — there is **no `CanvasLayer` anywhere**. Since 2026-07-15 the entire board
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

```
game_view.tscn  (single canvas layer 0 — NO CanvasLayer anywhere)
└─ SceneRoot (Control)
   ├─ PlayContainer (Control)
   │  ├─ PlayArea  ── drawn FIRST → underneath the overlays (earlier PlayContainer child)
   │  │  └─ SmoothScrollContainer → TopLevelVBox   (clip_contents=false; carries scroll)
   │  │     ├─ UpperZone / MiddleZone / LowerZone containers + score gutters
   │  │     │    (invisible card-anchor Controls; BigNumberLabel gutter labels)
   │  │     │     └─ earlier VBox siblings → BELOW CardLayer/PropLayer/OverlayLayer
   │  │     ├─ CardLayer (Node2D, z 0)              [earlier sibling → below props/overlay]
   │  │     │   ├─ CardVisual per card — CHILD INDEX = row-major rank (move_child, no z)
   │  │     │   │    · later column / lower row = later child = drawn on top
   │  │     │   │    · counter runs continuously across BOTH zones (upper first, then
   │  │     │   │      lower) → every card gets a UNIQUE slot; lower zone draws over upper
   │  │     │   │    · GRAB LIFT: a held card is move_child'd to the LAST CardVisual slot
   │  │     │   │      (above all resting cards, still below PropLayer)
   │  │     │   │    └─ inside each CardVisual (Offset → Visual), tree order:
   │  │     │   │       ├─ Type / Rank / Suit / Stamp Polygon2D
   │  │     │   │       ├─ Art Polygon2D            (last face polygon → on top of the face)
   │  │     │   │       └─ StatusLayer (Node2D)     (added LAST under `visual` → on top; no z)
   │  │     │   └─ two _PropHalf nodes per occupying split prop, BRACKETING the occupied
   │  │     │       CardVisual: BACK half move_child'd to JUST BELOW it (behind the card, above
   │  │     │       the row above); FRONT half JUST ABOVE it (in front of the card, but BELOW
   │  │     │       the row below). Both parented to the STABLE CardLayer (never to the card),
   │  │     │       transform synced to the PROP each frame so they never inherit the card's
   │  │     │       jump/drag/float. The card passes THROUGH the ring.
   │  │     ├─ PropLayer (Node2D, z 0)              [later sibling than CardLayer → above ALL cards]
   │  │     │   └─ PropVisual per live prop (order = add/tree order)
   │  │     │       └─ _draw(): non-split → whole body here (above all cards); split (hoop) →
   │  │     │          only _draw_fire_tips() here, both arcs drawn by its two _PropHalf nodes
   │  │     │          bracketing the occupied card in CardLayer (above)
   │  │     └─ OverlayLayer (Node2D, z 0)           [LAST sibling → always on top of the board]
   │  │        ├─ Focus inspector panel (PanelContainer)   — no z; tree order
   │  │        └─ Score TextPopup (Node2D, transient)      — no z; tree order
   │  ├─ WinScreen (Label)  ── above PlayArea (later PlayContainer child, by tree order)
   │  │   └─ Dim (ColorRect, show_behind_parent → behind the Label text)
   │  └─ LoseScreen (Label) └─ Dim (ColorRect, show_behind_parent)
   ├─ Submit / Undo / Next / Reroll (Buttons)
   ├─ HUD Labels (ScoreName / Score / MultScore / Total / Goal / Turns / Rerolls / Preview)
   ├─ Deck / Discard / Rules (Control + Button)
   └─ Background (TextureRect, visible=false; if shown, paints over SceneRoot — no back layer)
```

---

## Every moment the order can change

- **Board rebuild** (`board_changed` → `queue_rebuild` → `set_card_zones_visuals` →
  `_order_board_cards`, `play_area.gd`): re-orders every CardVisual in CardLayer via
  **guarded `move_child`s** in ascending target order (a still board does zero moves). Order is
  ROW-MAJOR ACROSS COLUMNS per zone since 2026-07-16 — headers, then row 0 of every column, then
  row 1, … (upper zone before lower): cards only overlap within a column, so this renders
  identically for cards, but each row is CONTIGUOUS so a split prop can bracket a whole row.
  Targets are assigned only to visuals verified in CardLayer at that moment (deduped), so a
  move_child can never go out of bounds by construction.
- **Card grab / drag** (`grab_cards`): the held card is `move_child`'d to the end of CardLayer
  (last CardVisual slot). **Restored** by `ungrab_cards` → rebuild (row-major order).
- **Scoring / submit** (`score_line`, `game.gd`): `popup_meld` jumps melded cards (offset only —
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
  (`PropVisual.body_size`, hardcoded per kind like CARD_SIZE) must overlap some card's footprint
  (`_body_over_any_card`). Never derive the row from what's under the prop — fanned cards are a
  full card tall behind their ~strip-high visible slice, so a ring crossing a SHORT column's
  empty row sat "inside" that column's top card's rect and bracketed the wrong row (2026-07-16).
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

1. **Upper vs lower zone once shared z 1..N** (`card_count` reset per zone → an add-order tie).
   ✅ `_order_board_cards` gives every CardVisual a unique child index across both zones
   (row-major within a zone, lower zone after upper so it draws over), deterministically.
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
5. **Scattered absolute-z constants (cards 1..N, props 100, popup 100, panel 300, status 1).**
   ✅ **All removed.** The whole board draw path is tree/sibling structure; the only new named
   constants are the hoop's art geometry (`RING_SEGMENTS/RING_WIDTH/SPLIT_TOP/SPLIT_BOTTOM`),
   which are draw parameters, not layer numbers.
6. **Score popup and props shared z 100 on different parents.** ✅ The popup is an OverlayLayer
   child (last sibling), unambiguously above every prop.
7. **`Background` is the last `SceneRoot` child, `visible=false`.** Unchanged — if ever enabled it
   paints over the entire board and HUD (there is no back layer). Left as-is.
8. **`clip_contents=false` on the scroll but the play-area rect still clips props/cards**
   (`PROPS_BUGFIX_HANDOFF.md` landmine 2). A split prop's back half rides the same content, so it
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

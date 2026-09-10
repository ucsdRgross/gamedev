# PLAN.md — the description sidebar, the HUD container, and the input simplification

**This is the specification. It is the last document anyone should need to build the thing.**
`DESIGN.md` version 10 is the authority on BEHAVIOUR; where the two disagree the design wins and
this plan is wrong.

## Design provenance and gap protocol — COPY THIS BLOCK INTO ANYTHING DERIVED FROM THIS DOCUMENT

Derived from: `solatro/design/sidebar/DESIGN.md`, version 10, charts confirmed. Every step below
cites the design node IDs it implements.

If you are executing this and you reach a decision the design does not cover:
1. Reversible and clearly within intent → do it, and append one line to `ASSUMPTIONS.md` citing the
   node you were working on. Never silently.
2. Otherwise — two defensible choices differ in observable behaviour, or the choice is expensive to
   reverse, or it is an owner call (balance, look, scope) → **park that thread, file a gap, keep
   working on unaffected threads, and tell the owner.**
3. The design contradicts itself or the code → always a gap, highest priority.
4. ⚠ **Two documents disagreeing is NOT automatically (3).** If both are restating the same answer,
   go read that answer — the conflict is a documentation bug to fix against the source, not a
   decision to escalate. Quote the note in the gap and say why it does not settle the question; if
   you cannot, it was never a gap.
5. ⚠⚠ **THE CODE BEING BROKEN IS NOT A GAP — FIX IT.** If the design says what should happen and
   the code does not do it, that is a BUG, and the only open question is *how* to fix it, which is
   yours. Filing it spends an owner round to be told "yes, fix the bug". Measured: one run filed
   ~50 gaps and a large share were this. **Before filing anything, ask in order:** does the design
   already answer it (→ fix the code); would any defensible choice be invisible in the product
   (→ assume it, log one line); would the owner recognise this as a decision they want (→ only
   now, a gap). A gap asks for a RULING, never for permission — if you are filing to be told it is
   fine to proceed, write the assumption instead.

File gaps at `solatro/design/sidebar/gaps/GAP-NNN.md` using the template in `DESIGN.md`
§gap-protocol. Write the options in the questionnaire grammar; they become the next round's
questions unchanged.

Do not resolve a gap by picking an answer. Do not proceed on the parked thread. Do not delete a gap
— it is closed by a new design version.

This block, unchanged, goes into every document derived from this one.

---

## 1. Normative contracts

**Everything in this section is specified, not suggested.** Do not invent an alternative.

### 1.1 The container's geometry — authorised by `Q23`, `Q24`, `Q175`, `Q177`, `Q178`, `Q246`

```
container_is_top   := (window.x - container_px) / window.y  <  1.0
                      # "would the play area LEFT OVER be taller than it is wide"
container_px       := min(settings.container_size_fraction * reference,
                          settings.container_size_max_px)
  where reference  := window.x   when the container is on the SIDE
                      window.y   when the container is on the TOP
```

When clamped, the container is flush against the **inner** edge of its band: on the side its right
edge sits at `container_px` measured inward from the band's outer limit, leaving the empty space
outboard of it. (D1, D2, D4, D6, D7, `Q177`=a)

```
picture_scale      := max(window.x / 1576.0, window.y / 887.0)   # a focused picture COVERS
PlayArea.board_inset_left := container_px / picture_scale        # side case
PlayArea.board_inset_top  := container_px / picture_scale        # top case
```

⚠ **`board_inset_*` is in PICTURE pixels and `container_px` is in WINDOW pixels.** The conversion
is the focused picture's live scale and must be recomputed on resize. At the picture's own aspect
the window cancels: the inset is `0.25 * 1576 = 394 px`, which is exactly today's measured value.
(D8, D9, D10)

The MAP uses `container_px` directly with no conversion — it has no picture. (D11, `Q247`=a)

### 1.2 The container's contents — authorised by `Q170`, `Q255`, `Q257`

`HudContainer` shows **exactly one** of two children at a time. There is no state where both or
neither is visible.

```
show_hud()          -> HUD visible, description hidden, lock cleared
show_description(e) -> description visible, HUD hidden; lock untouched
```

Transitions, and nothing else may cause one:

| Trigger | Result | Node |
|---|---|---|
| a highlight arrives (hover, or key/pad selection) | `show_description` | B1, B2 |
| pointer leaves everything, nothing locked | **stays** on the last entry | B4 |
| click on a card | `lock_to(...)`, and the click still performs its game action | B5, `Q56`=a |
| a locked card, pointer over another card | description follows the hover; returns to the locked card when the pointer leaves everything | B7, `Q60`=c |
| exit X, cancel, click on bare board, or the held card leaves its cell **while following** | `show_hud()` | B9, B10, B11 |
| `Game.processing` goes true | `show_hud()`, **lock cleared and not restored** | B17, B18, C8 |
| hover during processing | **ignored entirely** | B19 |
| processing ends | HUD holds until **any** focus event, including onto the same card | B20, C9, `Q257`=b |

⚠ The processing rule is the **GAME screen only**. The map's container never swaps on processing.
(C10, `Q260b`=b)

### 1.3 Gesture metrics — authorised by `Q284`, `Q290`, `Q291`, `Q293`, `Q294`, `Q300`, `Q301`, `Q304`, `Q305`

**No DPI reading survives anywhere in the project.** `WallInput.mm_to_px()` is deleted.

```gdscript
# Scripts/gesture_metrics.gd
class_name GestureMetrics

## How far a press must travel before its RELEASE places instead of its click grabbing.
## Card-relative, so it is right at every board zoom.
static func drag_threshold_px(card_size: Vector2, settings: PlayerSettings) -> float:
    return card_size.x * settings.card_drag_threshold

## The minimum size of any overlay control. Window-relative, because the overlay lives outside
## the board where no card exists. NO CLAMP: the fraction cannot run away as a DPI reading could.
static func touch_target_px(window: Vector2, settings: PlayerSettings) -> float:
    return minf(window.x, window.y) * settings.touch_target_fraction
```

A gesture with **no card under it** (a swipe on bare board) passes the default card size at the
current `board_zoom`, so `drag_threshold_px` always has a reference. (M3, M4, M5, M7, M8, `Q296`=a)

`WallInput.touch_target_px(window, settings)` keeps its NAME with a new body and a new signature,
delegating to `GestureMetrics`. Its call site in `WallOverlay._apply_touch_targets()` remains
mandatory. (M9, M10, `Q305`=b, `Q306`=a)

### 1.4 Holding a card, two flags not one — authorised by `Q261`, `Q262`, `Q265`

```gdscript
# Cards/card_visual.gd
var held : int = 0          # UNCHANGED meaning: picked up, in data
var following : bool = false # NEW: does the visual track the cursor
```

`CardVisual`'s target becomes `get_global_mouse_position()` **only when `following`**. When `held`
and not `following`, the card rests at its slot centre raised by the lift height — the SAME lift
height it has while following, so the only visible change when following starts is that it begins
to move. (G4, G5, G8, `Q261`=a, `Q265`=a)

`following` is set by either of two events, with **no threshold**:

- focus landing on any card by key or pad;
- any mouse motion at all.

It is a **one-way latch**: once true it stays true until the card is placed or cancelled.
(G6, G7, G8, `Q262`=a, `Q263`=a)

A card the player CLICKS is `following` immediately — the mouse has moved by definition. (G11)

### 1.5 Arming — authorised by `Q117`, `Q252`

```
armed_slot() := the leftmost Entrance slot holding a card, or -1
```

Re-derived, never stored. Undo restores the board and the arm follows. (G1, `Q117`=a)

`arm_leftmost()` calls **`Game.try_grab()` then `PlayArea.grab_cards()`** — the same functions a
player pickup calls, **with no flag and no second code path**. Nothing suppresses the description,
because arming moves no focus and no selection highlight, and the description side only reacts to a
highlight moving. (G2, G3, `Q250`=a, `Q252`=b)

### 1.6 Click versus drag — authorised by `Q280`, `Q281`, `Q283`, `Q284`

```
on release:
    travelled := press_position.distance_to(release_position)
    if travelled <= GestureMetrics.drag_threshold_px(...):
        -> it was a CLICK: grab and stay held
    else:
        -> the RELEASE places, if and only if the release is over a LEGAL cell
           otherwise the card returns to its slot: still armed, still lifted, no longer following
```

Applies to **both mouse and touch** — one gesture model. A drag-placed card is an ordinary undo
step and commits the Entrance to its grid exactly as a clicked one does. (E12–E18, `Q282`=a,
`Q280`=a, `Q281`=a, `Q289`=a)

⚠ A touch TAP needs no threshold of its own: a release on the card's own slot is not a placeable
spot, so it returns to exactly where it already was. (E24, `Q285`=b)

### 1.7 Per-slot Entrance stocks — authorised by `QR9`, `Q200`, `Q201`, `Q202`, `Q206`, `Q204`, `Q205`, `Q211`, `Q224`

`GameData.draw_deck` is replaced by one ordered stock per Entrance slot.

```
deal:      shuffle ONCE (the shuffle Game.add_deck already does), then deal ROUND-ROBIN
           left to right, so earlier slots take the extras when the count does not divide
when:      at show start, and again whenever the SET of slots changes
draw:      pop from the TOP of that slot's own stock
```

⚠ **NO NEW RNG ANYWHERE.** One shuffle, then a fixed order — which is what keeps
`_replay_pending_placement()`'s determinism argument true as written. Its own comment is the
contract: *"there is no RNG anywhere in the path, so replaying reproduces the same board, scoring
and refill included."* (H2, H3, H4, H5, `Q200`=c, `Q201`=a, `Q202`=a, `Q206`=a)

Rebalance, a pure rule with no seed:

```
slot REMOVED: its cards go from ITS BOTTOM, round-robin, to the BOTTOMS of the remaining
              slots, left to right
slot ADDED:   the bottom card of each existing slot in turn, round-robin, until the new slot
              has its even share
```

**TOPS NEVER MOVE.** What is about to be drawn is stable, so a peek effect stays honest. A slot
whose stock exhausts stays empty; exhaustion never triggers a rebalance. (H7, H9, H11, `Q207`=a,
`Q210`=c)

Stocks are part of the board: `on_append` and every board walk reach their cards exactly as they
reach the draw deck today. (H13, `Q225`=a)

⚠ **An in-flight save written before this change is DISCARDED, not migrated.** (H14, `Q224`=b)

### 1.8 Automatic end of show — authorised by `QR5`, `Q101`, `Q109`

```
after a placement has FULLY resolved (every line scored, every prop tick finished):
    if state.has_met_goal():
        Goal label changes state
        pause
        Game.end_show()          # the same flag, save and resolve the End button drives
```

No declining. The End button survives for a show that can no longer be won, and is REVEALED when
either the deck is empty or no action remains on the board. Undo rewinds an automatic end exactly
as it rewinds a manual one. (J1–J9, `Q101`=a, `Q104`=a, `Q107`=c)

---

### 1.9 The node tree, and the migration that gets there — authorised by `QR1`, `QR3`, `Q83`, `Q170`

⚠ **THIS IS THE LOAD-BEARING STRUCTURAL DECISION AND IT WAS NEARLY LEFT AS ONE LINE.** Read it
before S1.

**Where the HUD lives today, measured:** `Main.enter_game()` (`main.gd:767`) instantiates
`game_view.tscn` and calls `game_wp.attach_screen(new_view)` — so `GameView`, its `SceneRoot`, and
every furniture control **live inside the game WallPicture's `SubViewport`**. That is *why* the HUD
scales with the picture and why `hud_scale()` exists at all. The map's Fame/Lap/Luck sit in
`map.tscn`'s own `$UI` `CanvasLayer`, inside the map picture's viewport.

**Where they go:** `QR3`=(a) says *"every button and label moves into it"*, and `QR1`=(a) says the
surface is ONE instance on the wall overlay, window-anchored. Both cannot be satisfied by leaving
the controls in the picture. So:

```
wall.tscn
└─ %Overlay              (CanvasLayer, PROCESS_MODE_ALWAYS, window-anchored)
   ├─ BackButton / ForwardButton / WallButton      ← unchanged, and they draw ON TOP (D12)
   └─ HudContainer                                  ← NEW, one instance for the whole game
      ├─ HudStack        (a Control per screen, exactly one visible)
      │  ├─ GameHud      ← the nine controls from game_view.tscn's SceneRoot
      │  └─ MapHud       ← Fame, Lap, Luck, Deck from map.tscn's $UI
      └─ DescriptionPanel                           ← NEW, replaces HudStack when shown
```

**`Main` is the only writer of which `HudHud` child is visible**, on the same focus change that
already drives `_focus_picture()`. That is the existing seam; do not add a second one.

**The migration, in order, and none of it is optional:**

1. The nine game controls move from `game_view.tscn`'s `SceneRoot` into `GameHud`. `%Preview` and
   `%MultScore` are deleted rather than moved.
2. `GameView`'s `@onready` refs to them (`submit_button`, `undo_button`, `deck_ui`, `discard_ui`,
   `rules_ui`, `goal_label`, `total_label`, `combo_label`, `mult_label` and friends) **all break.**
   Replace them with accessors on `HudContainer`, reached once in `_ready()`.
3. `GameView._ready()` connects six button signals (`submit_button.pressed`, `undo_button.pressed`,
   and the three viewer buttons at `game_view.gd:131-133`). Those connections now cross from a
   per-show `GameView` to a node that OUTLIVES it — so **`GameView._exit_tree()` must disconnect
   them**, or the second show connects a freed callable. There is no such teardown today because
   nothing needed it.
4. `%WinScreen` / `%LoseScreen` stay in `PlayContainer`, unchanged. `Q90`=(a) keeps the outcome
   overlay covering only the play area, and that is still true because the HUD is no longer in the
   picture at all.
5. `LightLayer` and `PlayContainer` do **not** move. Only the furniture does.

⚠ **The container is OUTSIDE every picture, so it does not ride the wall camera, does not scale with
a picture, and is not captured by a wall transition.** That is what makes `Q77`=(b) (no `hud_scale`)
and `Q80`=(b) (no pan-following) fall out for free rather than needing code to suppress them.

⚠ **`Q141`=(b) said the sidebar sits INSIDE the deck/discard/rules viewers.** With one overlay
instance that is impossible as written. The resolution, and it preserves the answer's intent: those
viewers are full-screen overlays that would otherwise COVER the container, so the viewer is given a
left inset equal to `container_px` and the container stays on top. The description is therefore
beside the viewer's cards, which is what "inside" was asking for. If that reads wrong when built,
it is a gap — not a licence to spawn a second container.

## 2. Decisions already made, so you do not have to

⚠ **THIS SECTION EXISTS SO YOU DO NOT FILE A GAP ABOUT ANY OF IT.** Each line is a decision taken
in advance, deliberately, because it is invisible in the finished product or already settled by the
design. Do it as written and move on.

| Thing you will hit | The decision |
|---|---|
| Where `HudContainer` is instantiated | Inside `wall.tscn`'s `%Overlay` `CanvasLayer`, one instance, window-anchored — the same home `InfoCard` had |
| Who owns the swap | `HudContainer` alone. `PlayArea` and `Map` PUBLISH `InfoEntry`s and never decide what is shown |
| How `PlayArea` reaches it | Through its existing `info_requested` signal, relayed by `GameView`, exactly as it reaches `Main` today. Do not add a new wire |
| Order of the HUD's children | Numbers, then piles as one row, then actions (C3). Exact pixel spacing is yours |
| `%MultScore` / `%Preview` removal | Delete the nodes AND their `@onready` vars AND their `_furniture` entries in one step. Expect the board to re-centre; that is correct |
| Whether `GameView._furniture` survives | No. The container replaces it. Delete the array and both authored-offset caches |
| Which node type for the container background | `PanelContainer` with a `StyleBoxFlat`. Not `NinePatchRect` — art comes later |
| Scroll container for the description | Reuse the shape `InfoCard` had: a `ScrollContainer` with content height computed synchronously, not left to the deferred layout pass |
| What `InfoEntry` looks like | Unchanged. Do not redesign it |
| Where `GestureMetrics` lives | `Scripts/`, a static-only class, no nodes, no singletons |
| `WallInput.touch_target_px`'s signature change | Update all three call sites in the same commit. It is a rename of parameters, not a seam change |
| Naming of the new `following` flag | `following`, on `CardVisual`. Not `is_following`, not `tracks_cursor` |
| Whether `held` becomes a bool | No. It stays an `int` — it carries the stack index for multi-card holds |
| Per-slot stock storage | An `Array[Array[CardData]]` on `GameData`, `@export_storage`, replacing `draw_deck`. Update `_iterate_board`, the flat card list, both save walkers and the stage verifier in the same step |
| Save migration | None. Old in-flight saves are discarded (`Q224`=b). Do not write a migrator |
| Deck viewer content | The union of every stock, sorted by suit then rank, one flat list (I12) |
| Whether to keep `MapHoverPanel` | Keep the class as `get_info()`'s home; it still has no scene. Do not revive its scene |
| Test suite naming | Exactly as `NAMES.md` §8 says |
| Localisation | Two new keys, `NAMES.md` §9. Add rows; do not translate |
| Where new knobs go | `Scripts/player_settings.gd` with setters emitting `settings_changed`, like every existing knob |
| Animation timings | Fractions of `get_delay()`. Never a wall-clock literal — project rule 4 |
| Commented-out code | TODO comment if unimplemented, delete if implemented elsewhere — project rule 5 |
| Typed arrays | Type EVERY array and EVERY for-loop variable. Warnings are errors — project rule 3 |

**There is no Phase 0 spike.** Every fact this plan rests on was measured or read out of the source
during design; nothing reaches you marked `UNVERIFIED`.

---

## 3. Anti-scope — do NOT do these, however tempting

1. **Do not author new card descriptions.** The sidebar ships with today's `describe_card()`
   strings (`Q160`=a).
2. **Do not build a tappable card mechanic.** One dummy effect for testing, nothing else
   (`Q161`=c, `Q222`=b).
3. **Do not rebalance anything** because auto-end changes show length (`Q162`=a).
4. **Do not add settings-screen UI** for the new knobs (`Q163`=a).
5. **Do not translate** the new localisation keys (`Q164`=a).
6. **Do not add sound** for the sidebar, the lock, or the tap (`Q165`=a).
7. **Do not build the `deck`, `settings` or `book` wall screens** (`Q167`=a).
8. **Do not refactor the wall's transition system.** Only the info branch comes out.
9. **Do not "improve" the scoring, prop or spotlight code** you pass through.
10. **Do not touch `addons/`.** `worldgen` is vendored; `godot_ai` is a third-party plugin.

⚠ `UI/deck_builder.gd` is the one repair that IS in scope: fix its broken preloads with the current
classes and remove its dead code, keeping the tool (`Q166`=c).

---

## 3a. The file map — every file each step touches

**Pinned during design, so no step opens with a search.** A path here that turns out to be wrong is
a BUG in this plan: fix it, note it, carry on (gap protocol item 5).

| Step | Touches |
|---|---|
| S1 | NEW `UI/hud_container.gd` / `.tscn`, `UI/description_panel.gd` / `.tscn`; NEW `Tests/Wall/test_sidebar.gd` / `.tscn`; `Tests/all_tests.tscn` (register the suite) |
| S2 | `UI/Wall/wall.tscn` (mount `HudContainer` under `%Overlay`), `Levels/game_view.tscn` (remove the nine controls, delete `%MultScore`+3 children and `%Preview`), `Levels/game_view.gd:34-58` (the `@onready` block), `:65` (`_furniture`), `:76-148` (`_ready`, incl. the six `pressed` connections at `:126-133`), `:195-206` (`_refresh_hud`), `:321-333` |
| S3 | `Levels/game_view.gd:228-320` (delete `_capture_furniture_authored_x`, `_furniture_authored_y`, `hud_scale`, `_publish_hud_reserve`, `_hud_authored_width`, `_process`), `UI/play_area.gd:40-57` (`board_inset_left`, add `board_inset_top`), `:695-699` (delete `pan_window_left_x`), `:768-778` (`hud_reserve_px`), `Levels/main.gd:_on_window_resized` (recompute on resize), `UI/hud_container.gd` |
| S4 | `Levels/map.tscn` (`$UI` labels out), `Levels/map.gd:17-20`, `:137-141` (`_update_hud`), `UI/hud_container.gd` (the `MapHud` child), `Levels/main.gd` (tell the container which screen is focused, on the existing focus change) |
| S5 | `UI/play_area.gd:2797-2831` (`on_control_focus_entered`), `:2896-2910` (`card_info`), `Levels/game_view.gd:129` (the `info_requested` relay), `Levels/main.gd:672-700` (`_on_screen_info_hovered` → route to the container), `UI/description_panel.gd`, `UI/cards_viewer.gd` (the visual) |
| S6 | `UI/play_area.gd:1435-1458` (`_on_gui_input`), `:1460-1500` (`_unhandled_input`), `:1501-1511` (`_input`), `:832-845` (`_publish_cell_rects` — the cell bounds `B11` needs), `UI/hud_container.gd` |
| S7 | `Levels/game.gd` (`processing` setter / `processing_changed`), `Levels/game_view.gd:321-326` (`_on_processing_changed`), `UI/hud_container.gd` |
| S8 | `UI/description_panel.gd`, `project.godot` (the `sidebar_scroll` action) |
| S9 | `Scripts/player_settings.gd:450`, `:522-566`, `UI/Wall/wall_overlay.gd` (whole Info half incl. `magnifier_icon`/`_distance_to_segment`), `Levels/main.gd:519-560`, `:600-668`, `Scripts/Wall/wall_transition.gd` (the info branch), `UI/Wall/wall_picture.gd` (`info_zoom_state`), `project.godot` (drop `wall_info`) |
| S10 | `UI/play_area.gd:2832-2930` (the whole focus-info block), `Scripts/player_settings.gd:544` |
| S11 | delete `Tests/Wall/test_wall_info.*`, `Tests/Visual/wall_info_snapshot.*`; NEW `Tests/Visual/sidebar_snapshot.*`; `Tools/wall_editor.gd:~706` (`_apply_info_mode` → sidebar preview), `Tests/Visual/wall_editor_soak.gd`, `Tests/all_tests.tscn` |
| S12 | `UI/deck_viewer.gd`, `UI/choice_viewer.gd`, `UI/cards_viewer.gd` (the `on_inspect` callback already exists), `UI/deck_builder.gd` (the `Q166`=c repair) |
| S13 | NEW `Scripts/gesture_metrics.gd`; `Scripts/Wall/wall_input.gd:53-60`, `UI/play_area.gd:1386-1396` (`_swipe_threshold_px`), `UI/Wall/wall_overlay.gd:36-56` (`_apply_touch_targets`), `Scripts/player_settings.gd:490-502`, `:624-638`; NEW `Tests/Engine/test_gesture_metrics.*` |
| S14 | `Cards/card_visual.gd:328` (`held`), `:698-712` (the mouse target), `UI/play_area.gd:1512-1546` (`grab_cards`/`ungrab_cards`) |
| S15 | `UI/play_area.gd:1512-1546`, `Levels/game.gd:366-368` (`try_grab`), `Cards/Types/type_input.gd` (`on_refill`), `Levels/game_view.gd:462-498` (`_on_data_selected`) |
| S16 | `UI/play_area.gd:1372-1434` (the swipe reader — the press/drag/release path lands beside it), `:1435-1511`, `Levels/game.gd:370-398` (`try_place`); NEW `Tests/Interaction/test_drag_place.*` |
| S17 | `UI/play_area.gd:1435-1511`, `project.godot` (`card_tap`), `Scripts/card_effect_api.gd` (the dummy effect's hook) |
| S18 | `UI/play_area.gd:1460-1511`, `Levels/main.gd` (Escape → menu/wall) |
| S19 | `Scripts/game_data.gd:128` (`draw_deck`), `:408-431`, `:483`, `:531`, `:575` (every walker), `Levels/game.gd:400-431` (`add_deck`/`shuffle_deck`), `:868` (`draw_card`), `Cards/Types/type_input.gd:on_refill`, `Levels/game_view.gd:131` (the Deck button); NEW `Tests/Engine/test_entrance_stocks.*` |
| S20 | `Levels/game.gd` (the rebalance), `Scripts/game_data.gd` |
| S21 | `Cards/card_visual.gd:595-610` (the spawn position and the flip), `UI/play_area.gd:644-730` (the Entrance strip), `Levels/game.gd:700-712` (`refill_entrance_if_due`), `UI/deck_viewer.gd` |
| S22 | `Levels/game.gd:690-790` (`place_card_in_grid` — the goal check goes after the cascade), `:881-910` (`end_show`), `Levels/game_view.gd:195-206` (the Goal label state) |
| S23 | `Levels/map.gd:120-135` (`_on_node_hovered`), `UI/map_hover_panel.gd` (`get_info` stays), NEW `UI/map_name_popup.gd` / `.tscn` |

⚠ **Line numbers are from the design audit and will drift as earlier steps land.** They are a
starting point, not an assertion — the function names are the durable half.

## 4. The phases

Dependency order. **Phases 1 and 2 must land before 3**; 4 is independent and may run in parallel
with 1–3 if you have the appetite; 5 depends on 1; 6, 7 and 8 depend on nothing but each other's
absence.

### Phase 1 — the container

**S1 — Build `HudContainer` and `DescriptionPanel` as empty shells** *(implements QR3, C1, C2, B2, Q150, Q170)*
Both scenes, both scripts, `show_hud()`/`show_description()` swapping visibility. Not yet wired to
anything.
**Done-when:** `TestSidebar` constructs a `HudContainer` with no `Main` in the tree and asserts
exactly one child is visible after each call (`Q150`=a).

**S2 — Move the HUD's controls into it** *(implements C3, C4, L9, Q73, Q74, Q75)*
Deck, Discard, Rules, Goal, Total, Combo, Undo, End. Delete `%MultScore`, its three children and
`%Preview`, plus their `@onready` vars.
**Done-when:** the game screen renders with every control reachable and the suite is green.

**S3 — The geometry** *(implements D1, D2, D4, D6, D7, D8, D9, D10, C12, L8, L10, Q23, Q24, Q25, Q26, Q27, Q48, Q49, Q50, Q76, Q77, Q78, Q79, Q80, Q81, Q82, Q84, Q85, Q88, Q89, Q90, Q175, Q176, Q177, Q178, Q246)*
§1.1 exactly. Delete `hud_scale()`, `_publish_hud_reserve()`, both authored-offset caches,
`GameView._process()`'s furniture slide and `PlayArea.pan_window_left_x()`. Add
`board_inset_top`.
**Done-when (hard gate):** a headless arithmetic test asserts `board_inset_left == 394.0` at a 16:9
window of any size, and that a 32:9 window yields `640 / (3840/1576) = 262.7 ± 0.5`.

**S4 — The map gets the same container** *(implements C13, D11, Q83, Q247)*
Fame, Lap, Luck and the Deck button move in. The map uses `container_px` with no picture
conversion.

### Phase 2 — the description

**S5 — Publish and show** *(implements B1, B2, B4, C5, C6, Q19, Q20, Q21, Q22, Q28, Q29, Q30, Q32, Q33, Q34, Q35, Q36, Q38, Q39, Q46)*
Route `PlayArea.info_requested` into `HudContainer`. Content per `Q33`=c: name and visual side by
side at the top, then the description. Card visual at the board's own card size, frozen
(`Q34`=b, `Q35`=b).

**S6 — Lock, follow, dismiss** *(implements B5, B6, B7, B8, B9, B10, B11, C7, C16, Q47, Q56, Q57, Q58, Q59, Q60, Q61, Q62, Q63, Q64, Q65, Q66, Q67, Q171, Q179, Q180)*
Click-lock; hover follows while locked and returns on leaving; four dismissals; the exit X sized by
`GestureMetrics.touch_target_px`.
**Done-when:** `TestSidebar` covers each of the four dismissals and the locked-hover-return.

**S7 — The processing rule** *(implements B17, B18, B19, B20, C8, C9, C10, Q255, Q256, Q257, Q258, Q259b, Q260b)*
`Game.processing` → `show_hud()`, lock cleared. Hovers ignored while processing. HUD holds until
any focus event. Game screen only.
**Done-when (hard gate):** a test drives processing true→false and asserts the container shows the
HUD throughout and after, and that a hover mid-processing changes nothing.

**S8 — Scroll and multi-modal reach** *(implements B2, C16, Q40, Q41, Q42, Q43, Q44, Q45, Q68, Q70, Q71, Q72)*
`ScrollContainer`, always-visible scrollbar when overflowing, resting at the top; `sidebar_scroll`
action; Page Up/Down and arrows once locked.

### Phase 3 — remove Info mode

**S9 — Delete the mode** *(implements L1, L2, L3, L4, QR1, QR2, Q14)*
Flag, `wall_info` action, the toggle button and its icon, the info zoom pose, `WallTransition`'s
info branch, four knobs, `Main`'s per-picture memory.
**Done-when:** `grep -r "wall_info" solatro --include=*.gd` returns nothing outside `archive/`.

**S10 — Delete the in-board popup** *(implements L7, QR8, Q145)*
`_focus_info` and all four of its methods, plus `wall_screen_popups`.

**S11 — Replace the tests and the tool panel** *(implements L5, L6, Q151, Q152, Q153)*
`test_wall_info` → `test_sidebar`; `wall_info_snapshot` → `sidebar_snapshot`; the wall editor's
Info panel becomes a sidebar preview panel.
**Done-when:** the full suite is green and the suite COUNT is unchanged or higher.

**S12 — Migrate the viewers** *(implements L11, Q140, Q141, Q142, Q143, Q144)*
Deck, discard, rules and choice viewers publish to the sidebar; their own panels go. The sidebar
sits INSIDE those full-screen viewers (`Q141`=b).

### Phase 4 — the units model

**S13 — `GestureMetrics`, and delete DPI** *(implements M1, M2, M3, M4, M5, M7, M8, M9, L14, L15, Q284, Q290, Q291, Q292, Q292b, Q293, Q294, Q296, Q300, Q301, Q304, Q305, Q306, Q307b)*
§1.3 exactly. Delete `mm_to_px` and all six millimetre/px knobs. Repoint
`PlayArea._swipe_threshold_px()` and `WallOverlay._apply_touch_targets()`.
**Done-when (hard gate):** `grep -rn "dpi\|DPI\|mm_to_px" solatro --include=*.gd` outside
`archive/` and `addons/` returns nothing, and `TestGestureMetrics` asserts both bases.

### Phase 5 — input

⚠ `Q249`, verbatim: *"glow means selected. lift means currently picked up which warns that next click on a highlighted space will put the lifted card down. the selection glow is over where selector is to show current selection as normal."*

**S14 — Split `held` from `following`** *(implements G4, G5, G6, G7, G8, G11, `Q261`=a, Q254, Q261, Q262, Q263, Q265, Q266, Q267, Q268, Q269, Q270, Q249)*
§1.4 exactly.

**S15 — Arming through the pickup path** *(implements G1, G2, G3, G9, G10, G12, G14, G15, G16, G17, QR6, Q111, Q112, Q113, Q114, Q115, Q116, Q117, Q118, Q119, Q124, Q126, Q127, Q128, Q129, Q240, Q250, Q251, Q252)*
§1.5. `arm_leftmost()` calls the same two functions a player pickup calls.
**Done-when (hard gate):** a test asserts arming moves neither `focused_control` nor the viewport's
focus owner, and that the container still shows the HUD after an arm.

**S16 — Click versus drag, and release-to-place** *(implements E1–E18, E23, E24, `Q282`=a, Q120, Q121, Q122, Q123, Q125, Q280, Q281, Q282, Q283, Q285, Q286, Q287, Q288, Q289)*
§1.6. This introduces the first press-drag-release path in the project.
**Done-when (hard gate):** `TestDragPlace` asserts a sub-threshold release grabs, an
over-threshold release on a legal cell places, and one on an illegal cell returns the card armed
and lifted.

**S17 — Tap** *(implements F1–F9, `Q98`=d, QR4, Q92, Q93a, Q94, Q95, Q96, Q96b, Q97, Q98, Q161, Q222)*
Double-click undoes the grab; refused after a placement; self-detected on touch; `card_tap` action
plus double-press; `card_tapped` signal; one dummy effect.

**S18 — Cancel** *(implements E19, E20, E21, E22, `Q99`=b, `Q100`=c, Q99, Q100)*
Held card first, description second. Escape cancels everything AND shows the menu/wall.

### Phase 6 — Entrance stocks

**S19 — Per-slot stocks** *(implements H1, H2, H3, H4, H5, H13, H14, H15, QR9, Q200, Q201, Q202, Q211, Q212, Q224, Q225)*
§1.7. Replace `draw_deck`; update every walker in the same step.
**Done-when (hard gate):** `TestEntranceStocks` asserts a deal of 23 cards across 5 slots gives
sizes `[5,5,5,4,4]`, and that two runs from the same shuffled order produce identical stocks.

**S20 — Rebalance** *(implements H7, H8, H9, H11, Q204, Q205, Q206, Q207, Q208, Q209, Q210)*
§1.7's two rules. Tops never move.
**Done-when (hard gate):** a test removes a slot and asserts every remaining slot's TOP card is
unchanged.

⚠ `Q245` fixes the face-down cap, verbatim: *"knob defaulting to 5"* — so `entrance_stock_face_down_cap` starts at 5.

**S21 — The flip** *(implements I1–I12, Q203, Q213, Q214, Q215b, Q216, Q217, Q218, Q219, Q220, Q221, Q223, Q244, Q245)*
Face-down stocks with the capped depth; flip in place, staggered left to right; no fly-in; hovering
a stock describes the slot; deck viewer shows the sorted union.

### Phase 7 — automatic end

**S22 — Auto-end on goal** *(implements J1–J12, QR5, Q91, Q101, Q102, Q102b, Q102c, Q103, Q104, Q106b, Q107, Q108, Q109, Q110)*
§1.8.
**Done-when (hard gate):** a headless test plays to the goal and asserts `show_ended` without any
button press, and that undo returns to a live board.

### Phase 8 — the map

**S23 — The name popup and the map's sidebar** *(implements K1–K12, QR7, Q130, Q131, Q132, Q133, Q133a, Q134, Q135, Q136, Q137, Q138, Q139)*
Name-only popup above the node, staying put; hover fills the sidebar; click still enters; first
touch tap behaves as hover; booster previews as a wrapping grid.

### Phase 9 — closing (ALWAYS LAST, never skipped)

**S24 — Run the closing sequence in `/plan-run`** *(implements A1–A11, and the whole branch, Q160, Q162, Q163, Q164, Q165, Q166, Q167)*
Work the numbered list under "Closing the run" in order, dispatching the reading work to subagents
**one at a time**. The adversarial review MUST run on a model that did not implement.

**Done-when (phase):** every numbered item in that sequence has run and its output is recorded in
the handoff; `doc_check.py` is clean on a FULL run; no reviewer finding is left unreproduced.

---

## 5. Owner verification script

Run the game and check, in order:

1. A fresh show opens with the leftmost Entrance card **lifted**, and the HUD showing — not a
   description.
2. Move the mouse. The lifted card starts following it.
3. Hover a board card. The container swaps to its description; move off, it stays.
4. Click a card. The description locks; the exit X appears.
5. Place a card. The container shows the HUD for the whole cascade, and keeps showing it until you
   hover something.
6. Drag an Entrance card onto a legal cell and release — it places. Drag onto the container and
   release — it returns, still lifted.
7. Resize the window narrow. The container moves to the top and the board stays roughly square.
8. Reach the goal. The show ends on its own.

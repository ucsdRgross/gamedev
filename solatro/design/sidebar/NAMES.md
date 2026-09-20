# NAMES.md — every identifier this design introduces or renames

**Use these exactly. Do not rename, do not "improve", do not shorten.** Two sessions inventing two
names for one thing is the most common way work that should compose does not.

Derived from: `DESIGN.md` version 10, charts confirmed.

## Design provenance and gap protocol — COPY THIS BLOCK INTO ANYTHING DERIVED FROM THIS DOCUMENT

Derived from: `solatro/design/sidebar/DESIGN.md`, version 10. Every step in `PLAN.md` cites the
design node IDs it implements.

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

## 1. New scenes and scripts

| Path | Class | What it is |
|---|---|---|
| `UI/hud_container.gd` | `HudContainer` | The ONE container. A `PanelContainer` that holds either the HUD or the description, never both (C1, C2, C5) |
| `UI/hud_container.tscn` | — | Its scene. Owns the tab-free content swap and the exit X |
| `UI/description_panel.gd` | `DescriptionPanel` | The description's contents: title, card visual, body, inside a `ScrollContainer` (C5, B2) |
| `UI/description_panel.tscn` | — | Its scene. Owns `%Back`, the way back out of a preview card picked from a pack's grid, at the head of the name's row and up only while such a card shows (K9, `GAP-010`=c) |
| `UI/map_name_popup.gd` | `MapNamePopup` | The small name-only popup above a map node (K2) |
| `UI/map_name_popup.tscn` | — | Its scene |
| `Scripts/gesture_metrics.gd` | `GestureMetrics` | The units model: `drag_threshold_px()` and `touch_target_px()` (M3, M7) |

## 2. Deleted files

`InfoCard` (script and scene), its `TestWallInfo` suite and its `wall_info_snapshot` scene are gone —
replaced by `DescriptionPanel` inside the container (L1), `Tests/Wall/test_sidebar.gd` and
`Tests/Visual/sidebar_snapshot.gd` (L6).

⚠ `Scripts/Wall/info_entry.gd` (`InfoEntry`) **survives unchanged** — it is the publish shape every
screen already uses, and nothing about it is Info-mode-specific.

## 3. Methods on existing classes

| Class | Signature | Notes |
|---|---|---|
| `HudContainer` | `func show_hud() -> void` | Revert to the HUD. The one place that swap happens (C2, B10) |
| `HudContainer` | `func show_description(entry: InfoEntry) -> void` | Swap to the description (C5) |
| `HudContainer` | `func lock_to(entry: InfoEntry, target: CardData) -> void` | Click-lock (B5) |
| `HudContainer` | `func clear_lock() -> void` | (B10) |
| `HudContainer` | `func is_locked() -> bool` | |
| `HudContainer` | `func container_rect() -> Rect2` | What `PlayArea.board_inset_left` is derived from (D8) |
| `PlayArea` | `var board_visible_crop : Vector2` | The picture px a covering window crops off the RIGHT and BOTTOM: the board's region ends there, so it fits and centres in what the player can SEE (D9, D10, `GAP-002`=a) |
| `PlayArea` | `static func reference_window_size() -> Vector2` | The project's own authored window shape, read from `ProjectSettings` — the aspect the game picture's height is built to and the container's cap is measured against (D6, `GAP-001`=b) |
| `WallPicture` | `static func visible_rect_beside(design: Vector2, window: Vector2, rect: Rect2, top: bool) -> Rect2` | `local_rect_beside()`'s whole arithmetic, for a caller holding a design size but no picture instance; the instance method delegates to it (D8, `GAP-002`=a) |
| `GestureMetrics` | `static func drag_threshold_px(card_size: Vector2, settings: PlayerSettings) -> float` | Card-relative (M3, M4) |
| `GestureMetrics` | `static func touch_target_px(window: Vector2, settings: PlayerSettings) -> float` | Window-relative (M7, M8) |
| `WallInput` | `static func touch_target_px(window: Vector2, settings: PlayerSettings) -> float` | ⚠ **KEEPS ITS NAME, NEW BODY AND NEW SIGNATURE** — delegates to `GestureMetrics`. Every caller keeps its seam (M9, `Q305`=b) |
| `PlayArea` | `func armed_slot() -> int` | Leftmost present, re-derived, never stored (G1, `Q117`=a) |
| `PlayArea` | `func arm_leftmost() -> void` | Calls the SAME `try_grab`/`grab_cards` a player pickup calls (G2, `Q252`=b) |
| `CardVisual` | `var following : bool` | NEW. `held` keeps its meaning; only `CardVisual`'s target reads this (G5, G8, `Q261`=a) |
| `Game` | `func stock_for_slot(slot: int) -> Array[CardData]` | One slot's ordered stock (H1) |
| `Game` | `func rebalance_stocks() -> void` | Add/remove rebalance, pure rule, no RNG (H7, H8) |
| `CardVisual` | `const CARD_BACK_FRAME : int = 3` | The card-sheet frame a face-down card draws — owner: *"cardback should be frame 3"* (I8) |
| `CardVisual` | `const BLANK_CARD_FRAME : int = 1` | The frame a card with no type draws |
| `CardVisual` | `var face_down : bool` | Hidden by the board: a stock's face-down card. Not `CardData.flipped` (I8) |
| `HudContainer` | `func dismiss_description() -> void` | A dismissal: frees the shown description, forgets the screen's remembered entry, shows the HUD |
| `HudContainer` | `func release_screen(screen: StringName) -> void` | A screen's content ended: hands back its memory, lock and cascade flag |
| `HudContainer` | `const MAP_SCREEN : StringName`, `const MENU_SCREEN : StringName` | The map's and the start menu's screen ids |
| `HudContainer` | `signal active_screen_changed` | A different screen is showing |
| `HudContainer` | `signal exit_accepted` | The X was accepted from keyboard or pad |
| `HudContainer` | `func return_to_pack() -> void` | What `%Back` is wired to: re-shows the pack a preview card was picked out of, its own grid and its own scroll with it (K9, `GAP-010`=c) |
| `DescriptionPanel` | `signal preview_card_picked(data: CardData, card_px: Vector2)` | A card listed in the mounted grid was pointed at, focused or tapped (K9, `Q135`=b, `Q137`=a) |
| `DescriptionPanel` | `var scroll_position : int` | How far the panel is scrolled — the seam `return_to_pack()` restores the pack's own reading through |
| `DescriptionPanel` | `func rest_focus_on(data: CardData) -> void` | Focuses the listed card that shows `data` as a REST, not a pick: `_focus_is_resting` makes `_pick_preview_card` ignore that one `focus_entered`, the way `PlayArea._rest_focus_on` rests without highlighting (K9, `GAP-010`=c) |
| `HudContainer` | `var _picked_card : CardData` | The card a shown preview was picked for; lives exactly as long as `_pack_entry` and is where the way back rests the focus when `%Back` held it (K9, `GAP-010`=c) |
| `HudContainer` | `func _join_focus_while_shown(button: Button, shown: bool) -> void` | The one rule for the X and `%Back`: a panel control is visible and in the focus chain for exactly the same span (C16, K9) |
| `HudContainer` | `func _hosting_a_viewer() -> bool` | Whether a Deck/Choice viewer is up, read off `host_viewer`'s own connections: the map's up-into-the-panel route yields to a viewer's focus chain (K10, `GAP-012`=a) |
| `HudContainer` | `func host_viewer(viewer: Node, picture: WallPicture, relay: Signal) -> void` | Wires a `DeckViewer`/`ChoiceViewer` on any screen: relay, return to the lock, focus fallback, fit and re-fit (republishing only while a description shows) |
| `GameView` | `func pile_center(pile: Control) -> Vector2` | Where a card leaving the board aims: the window pile's centre, in the game picture |
| `GameView` | `func arm_after_placement() -> void` | Drop the hand and re-arm after a placement's refill; the live and replay routes share it |
| `PlayArea` | `func return_focus_to_board() -> void` | After a key/pad accept on the X: focus on the described card, or the armed card |
| `PlayArea` | `func rest_focus_on_board() -> void` | After the outcome's own Undo: the focus rests on the armed card, or — End reached with the Entrance empty, so the undo re-arms nothing — on the selected grid's origin cell, the control the overview's arrow selection lands on (J13, `GAP-009`=b) |
| `GameView` | `func _on_outcome_undo_pressed() -> void` | The outcome row's Undo: awaits the shared `_on_undo_pressed` and then rests the picture viewport's focus on the board, which the HUD's Undo (a root-viewport press) must not do (J13, `GAP-009`=b) |
| `TestGridFixtures` | `static func tinted_cell_count(...) -> int` | Test support: the cells whose `modulate` wears `legal_cell_tint` (focused or not) — the one counter `TestSidebar` and the snapshot share |
| `WorldMapController` | `static func node_screen_rect(node: WorldGraphNode) -> Rect2` | A map node's marker rect in the map viewport's coordinates |
| `TestMainHost` | `static func mount(parent: TestSuite, host: Node, scene: PackedScene) -> Node`, `static func unmount(parent: TestSuite, node: Node) -> void` | Test support: record the tree's `paused` before a Wall mounts, write it back after it is freed |
| `GameView` | `var _outcome_buttons : HBoxContainer` | The row the outcome's Continue and its own Undo sit in, centred on the win/lose screen and freed as one. The Undo button itself is a local: nothing keeps it, and a test finds it by its label (J13, `GAP-009`=b) |
| `GameView` | `func _add_outcome_button(row: HBoxContainer, key: StringName, handler: Callable) -> Button` | One localised button in the outcome row, wired to `handler`; Continue and Undo are its two callers (J13, `GAP-009`=b) |
| `Game` | `func legal_cells_for(held: Array[CardData], grids: Array[GridData]) -> Array[CardData]` | THE ONE legality walk: the zone card of every cell in `grids` where `held` may land, asked through `on_can_place_stack` exactly as `try_place` asks. `_no_held_card_has_a_legal_placement`, `_no_legal_placement_remains_in_grid` and `PlayArea._sweep_legal_cells` all read it (G12, `GAP-005`=a) |

## 4. Deleted methods and properties

| Where | What | Node |
|---|---|---|
| `WallInput` | `mm_to_px()` | M1, L14 |
| `PlayArea` | `_focus_info`, `_ensure_focus_info()`, `_show_focus_info()`, `_position_focus_info()`, `hide_focus_info()`, `_info_mode()`, `_popups_allowed()`, `pan_window_left_x()` | L7, L8 |
| `GameView` | `hud_scale()`, `_publish_hud_reserve()`, `_capture_furniture_authored_x()`, `_furniture_authored_x`, `_furniture_authored_y`, `_process()`'s furniture slide | L8 |
| `Main` | `_info_by_picture`, `_info_entry_by_picture`, `_info_entry_owner`, `_restore_info_mode_for()`, `_stash_info_entry()`, `_on_info_toggled()`, `_on_info_toggle_requested()` | L4 |
| `WallPicture` | `info_zoom_state()` | L2 |
| `WallTransition` | the `wall_info_mode` branch in `sample_at()` | L2 |
| `WallOverlay` | `_info_button`, `toggle_info()`, `magnifier_icon()`, `_distance_to_segment()` | L1 |
| `GameData` | `draw_deck` as the single deck | L12, H1 |

## 5. Settings keys — `Scripts/player_settings.gd`

**Added:**

| Key | Type | Default |
|---|---|---|
| `container_size_fraction` | `float` | `0.25` |
| `container_size_max_px` | `float` | `640.0` |
| `card_tap_window_ms` | `float` | `300.0` |
| `card_drag_threshold` | `float` | `0.25` |
| `touch_target_fraction` | `float` | `0.06` |
| `entrance_flip_stagger` | `float` | `0.15` |
| `legal_cell_tint` | `Color` | `Color(0.72, 1.35, 0.86)` |

**Removed:** `wall_info_mode`, `wall_info_card_width`, `wall_info_card_max_height`,
`wall_info_card_overlap`, `wall_info_zoom_scale`, `wall_screen_popups`, `hud_width_fraction`,
`grid_swipe_threshold_mm`, `grid_swipe_threshold_min_mm`, `grid_swipe_threshold_max_mm`,
`wall_touch_target_mm`, `wall_touch_target_min_px`, `wall_touch_target_max_px`.

## 6. InputMap actions

| Action | Change |
|---|---|
| `wall_info` | **REMOVED** (L1) |
| `card_tap` | **NEW** — the bindable tap action that ships alongside the double-press (F5, `Q98`=d) |
| `sidebar_scroll` | **NEW** — the non-navigation stick, for scrolling a locked description (`Q42`=a) |

## 7. Signals

| Owner | Signal | Node |
|---|---|---|
| `PlayArea` | `card_tapped(data: CardData)` | F8. Nothing listens in v1 but the dummy test effect |
| `PlayArea` | `info_requested(entry: InfoEntry)` | **unchanged name**, now routed to `HudContainer` rather than `Main`'s card |
| `HudContainer` | `description_dismissed` | B10 |

## 8. Test suites

| Path | Class | Covers |
|---|---|---|
| `Tests/Wall/test_sidebar.gd` / `.tscn` | `TestSidebar` | Charts B, C — open, swap, lock, dismiss, processing |
| `Tests/Engine/test_gesture_metrics.gd` / `.tscn` | `TestGestureMetrics` | Chart M — both bases, no DPI anywhere |
| `Tests/Engine/test_entrance_stocks.gd` / `.tscn` | `TestEntranceStocks` | Chart H — deal, rebalance, exhaustion, determinism |
| `Tests/Interaction/test_drag_place.gd` / `.tscn` | `TestDragPlace` | Chart E — click vs drag, release targets |
| `Tests/Visual/sidebar_snapshot.gd` / `.tscn` | — | By-eye gate (`Q153`=a) |

## 9. Localisation keys — `Locale/localization.csv`

| Key | Where |
|---|---|
| `SIDEBAR_CLOSE` | The exit X's tooltip (C16) |
| `SIDEBAR_BACK` | `%Back`'s tooltip (K9, `GAP-010`=c) |
| `SIDEBAR_STOCK_REMAINING` | The face-down stock's description: how many remain (I10) |
| `GAME_UNDO` | The outcome screen's own Undo, beside Continue (J13, `GAP-009`=b) |

⚠ **Leave a new row's third column EMPTY.** Godot's CSV importer reads it as the message CONTEXT, so
a row that fills it is unreachable through `TRANSLATION.find` and the label renders as its own key.

⚠ **Every user-facing string goes through `TRANSLATION.find` and this CSV — never a literal.**
Project rule 4.

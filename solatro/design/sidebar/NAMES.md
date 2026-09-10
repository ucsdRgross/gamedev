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
| `UI/description_panel.tscn` | — | Its scene |
| `UI/map_name_popup.gd` | `MapNamePopup` | The small name-only popup above a map node (K2) |
| `UI/map_name_popup.tscn` | — | Its scene |
| `Scripts/gesture_metrics.gd` | `GestureMetrics` | The units model: `drag_threshold_px()` and `touch_target_px()` (M3, M7) |

## 2. Deleted files

| Path | Why |
|---|---|
| `UI/Wall/info_card.gd`, `UI/Wall/info_card.tscn` | `InfoCard` is replaced by `DescriptionPanel` inside the container (L1) |
| `Tests/Wall/test_wall_info.gd` / `.tscn` | Replaced by `Tests/Wall/test_sidebar.gd` (L6) |
| `Tests/Visual/wall_info_snapshot.gd` / `.tscn` | Replaced by `Tests/Visual/sidebar_snapshot.gd` (L6) |

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
| `GestureMetrics` | `static func drag_threshold_px(card_size: Vector2, settings: PlayerSettings) -> float` | Card-relative (M3, M4) |
| `GestureMetrics` | `static func touch_target_px(window: Vector2, settings: PlayerSettings) -> float` | Window-relative (M7, M8) |
| `WallInput` | `static func touch_target_px(window: Vector2, settings: PlayerSettings) -> float` | ⚠ **KEEPS ITS NAME, NEW BODY AND NEW SIGNATURE** — delegates to `GestureMetrics`. Every caller keeps its seam (M9, `Q305`=b) |
| `PlayArea` | `func armed_slot() -> int` | Leftmost present, re-derived, never stored (G1, `Q117`=a) |
| `PlayArea` | `func arm_leftmost() -> void` | Calls the SAME `try_grab`/`grab_cards` a player pickup calls (G2, `Q252`=b) |
| `CardVisual` | `var following : bool` | NEW. `held` keeps its meaning; only `CardVisual`'s target reads this (G5, G8, `Q261`=a) |
| `Game` | `func stock_for_slot(slot: int) -> Array[CardData]` | One slot's ordered stock (H1) |
| `Game` | `func rebalance_stocks() -> void` | Add/remove rebalance, pure rule, no RNG (H7, H8) |

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
| `entrance_stock_face_down_cap` | `int` | `5` |
| `entrance_flip_stagger` | `float` | `0.15` |

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
| `SIDEBAR_STOCK_REMAINING` | The face-down stock's description: how many remain (I10) |

⚠ **Every user-facing string goes through `TRANSLATION.find` and this CSV — never a literal.**
Project rule 4.

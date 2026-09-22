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
| `HudContainer` | `func lock_to(entry: InfoEntry) -> void` | Click-lock (B5) |
| `HudContainer` | `func clear_lock() -> void` | (B10) |
| `HudContainer` | `func is_locked() -> bool` | |
| `HudContainer` | `func container_rect() -> Rect2` | Where the container RESTS -- what both contents lay out inside, whatever the slide is doing |
| `HudContainer` | `func published_rect() -> Rect2` | The resting rect scaled along the band's axis by the slide: what `PlayArea.board_inset_left` and every screen beside the container are derived from |
| `HudContainer` | `func slid_fraction() -> float` | How far in the container has slid -- 1 at rest, 0 off the window |
| `HudContainer` | `func slide_to(target: float) -> void` | Runs the slide and returns once it is there; `Main` awaits the way out before the camera moves |
| `PlayArea` | `var board_slide_offset : Vector2` | How far the slide has displaced the board's window from its RESTING place. The board's SIZE, and so its zoom, is fitted against the resting reserve whatever the sidebar is doing; only its position follows the slide |
| `PlayArea` | `var board_visible_crop : Vector2` | The picture px a covering window crops off the RIGHT and BOTTOM: the board's region ends there, so it fits and centres in what the player can SEE (D9, D10, `GAP-002`=a) |
| `PlayArea` | `static func reference_window_size() -> Vector2` | The project's own authored window shape, read from `ProjectSettings` — the aspect the game picture's height is built to and the container's cap is measured against (D6, `GAP-001`=b) |
| `WallPicture` | `static func visible_rect_beside(design: Vector2, window: Vector2, rect: Rect2, top: bool) -> Rect2` | `local_rect_beside()`'s whole arithmetic, for a caller holding a design size but no picture instance; the instance method delegates to it (D8, `GAP-002`=a) |
| `GestureMetrics` | `static func drag_threshold_px(card_size: Vector2, settings: PlayerSettings) -> float` | Card-relative (M3, M4) |
| `GestureMetrics` | `static func touch_target_px(window: Vector2, settings: PlayerSettings) -> float` | Window-relative (M7, M8) |
| `WallInput` | `static func touch_target_px(window: Vector2, settings: PlayerSettings) -> float` | ⚠ **KEEPS ITS NAME, NEW BODY AND NEW SIGNATURE** — delegates to `GestureMetrics`. Every caller keeps its seam (M9, `Q305`=b) |
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
| `HudContainer` | `signal slide_settled` | The slide reached its aim, or the container is leaving the tree, which releases `slide_to()`'s waiters too |
| `HudContainer` | `func _join_focus_while_shown(button: Button, shown: bool) -> void` | The one rule for the X: a panel control is visible and in the focus chain for exactly the same span (C16) |
| `HudContainer` | `func _hosting_a_viewer() -> bool` | Whether a Deck/Choice viewer is up, read off `host_viewer`'s own connections: the map's up-into-the-panel route yields to a viewer's focus chain (K10, `GAP-012`=a) |
| `HudContainer` | `func mount_description_buttons(row: Control) -> void` | Hangs a screen's own row of buttons above the description body; the screen builds the row, decides when it shows and owns the node |
| `DescriptionPanel` | `func mount_buttons(row: Control) -> void` | The `%ButtonRow` slot: the panel never learns what the buttons do |
| `WorldMapController` | `func select_node(node: WorldGraphNode) -> void` | A pointer, finger or pad PICKS a reachable node; travelling is the map screen's Travel button |
| `WorldMapController` | `func clear_selection() -> void` | Back to the basic view: nothing picked, nothing marked |
| `WorldMapController` | `func selected() -> WorldGraphNode` | The standing pick, or null at rest |
| `WorldMapController` | `signal node_selected(node: WorldGraphNode)`, `signal selection_cleared` | The pick changed, or went |
| `WorldMapController` | `signal travel_focus_requested` | Accept on the map, a map node being no Control: the screen hands the pad to its Travel button |
| `Map` | `var travel_button`, `var selection_deck_button`, `var possible_cards_button` | The picked node's own buttons on the DESCRIPTION side, the HUD's Deck button being gone with the HUD |
| `Map` | `var _packs_shown : Dictionary[int, bool]` | The pack nodes already listed where the token stands; cleared by an arrival and by a new run |
| `Map` | `func _host_map_viewer(viewer: DeckViewer) -> void` | Every viewer this screen opens comes back to the picked node's description |
| `ChoiceViewer` | `var selected_card : CardData`, `func select(card: CardData) -> void` | The card the player picked out of a pack; Take adds the whole pack either way |
| `CardVisual` | `var selected : bool` | Drawn as the outer rim in `PaletteRoles.selected_rim`; the moving focus overrides it |
| `PaletteRoles` | `var selected_rim : int` | The ink a picked pack card's rim wears while the focus is elsewhere |
| `HudContainer` | `func host_viewer(viewer: Node, picture: WallPicture, relay: Signal) -> void` | Wires a `DeckViewer`/`ChoiceViewer` on any screen: relay, return to the lock, focus fallback, fit and re-fit (republishing only while a description shows) |
| `GameView` | `func pile_center(pile: Control) -> Vector2` | Where a card leaving the board aims: the window pile's centre, in the game picture |
| `PlayArea` | `func return_focus_to_board() -> void` | After a key/pad accept on the X: focus on the described card, or a board rest when that control is gone |
| `PlayArea` | `func rest_focus_on_board() -> void` | The board rest: the card in hand, or the selected grid's origin cell — the control the overview's arrow selection lands on, and what a pad player steps from with nothing in hand (J13, `GAP-009`=b) |
| `GameView` | `func _rest_the_board_focus() -> void` | Called wherever the board settles (`rebuild()`, the processing-false edge): rests the board focus only while NOTHING in the picture holds it, so it never takes the focus off the player |
| `GameView` | `func _on_outcome_undo_pressed() -> void` | The outcome row's Undo: the shared `_on_undo_pressed`, then a board rest of the picture viewport's focus, which the HUD's Undo (a root-viewport press) must not do (J13, `GAP-009`=b) |
| `TestGridFixtures` | `static func lit_cell_count(...) -> int` | Test support: the cells whose face is DRAWN at `highlight_glow` — one expected value, the focus being an outline that brightens nothing — the one counter `TestSidebar`, `TestDragPlace` and the snapshot share |
| `TestGridFixtures` | `static func leftmost_entrance_slot() -> int` | Test support: the leftmost Entrance slot holding a card, or -1, off the current game's state — the one query `TestSidebar` and `TestDragPlace` share |
| `TestGridFixtures` | `static func brightness_of(poly: Polygon2D) -> float` | Test support: the `u_brighten` one card polygon is drawn at; an unset uniform reads back as the shader's 1.0 |
| `PipSuit` | `func get_plural_str() -> String` | The suit's name in the plural, read by the card title alone ("King of Knives", and "Knives" for a card with a suit and no rank); every other surface, the suit's own description block included, names it through `get_str()` |
| `CardOutline` | `static func set_brightness(poly: Polygon2D, brightness: float) -> void` | The per-element highlight channel: an equal-channel multiplier on this polygon's drawn BODY, never its rim, 1.0 unlit |
| `CardVisual` | `var on_drop_map : bool` | This card's cell is one the held card may land in — the one mark `_apply_marks` brightens the face by |
| `CardVisual` | `var focused : bool` | The board is pointing at this card: `_apply_marks` draws it as the card's OUTER rim in the match ink, never as a brighter face |
| `PlayArea` | `signal hand_released` | A drag's release landed on nothing that takes the card, so the player dropped it — `GameView._finish_with_the_card` |
| `GameView` | `func _finish_with_the_card() -> void` | The player ACTED with the card (a placement, a drop): the description goes back to the HUD and the focus rests on the board. A cancel is not an act and reaches none of this |
| `WorldMapController` | `static func node_screen_rect(node: WorldGraphNode) -> Rect2` | A map node's marker rect in the map viewport's coordinates |
| `TestMainHost` | `static func mount(parent: TestSuite, host: Node, scene: PackedScene) -> Node`, `static func unmount(parent: TestSuite, node: Node) -> void` | Test support: record the tree's `paused` before a Wall mounts, write it back after it is freed |
| `GameView` | `var _outcome_buttons : HBoxContainer` | The row the outcome's Continue and its own Undo sit in, centred on the win/lose screen and freed as one. The Undo button itself is a local: nothing keeps it, and a test finds it by its label (J13, `GAP-009`=b) |
| `GameView` | `func _add_outcome_button(row: HBoxContainer, key: StringName, handler: Callable) -> Button` | One localised button in the outcome row, wired to `handler`; Continue and Undo are its two callers (J13, `GAP-009`=b) |
| `CardsViewer` | `var sticky : CardData`, `func stick_to(data)`, `func unstick()`, `signal sticky_changed(stuck: bool)` | THE ONE STICKY MODEL every viewer shares: a click on a listed card pins the sidebar to it, and the host turns that into `HudContainer.lock_to`/`clear_lock` — the same lock a board click makes |
| `CardsViewer` | `enum Modal { PASS, KEEP, CLOSE }`, `const NAVIGATION`, `func modal_verdict(event) -> Modal` | The modal rule, in one place: a viewer answers cancel and every arrow that walked off its list's own edge, so the map or board beneath never sees one |
| `CardsViewer` | `signal sidebar_requested` | An edge arrow with a card stuck: the X is in another viewport and focus never crosses one, so the host grabs it |
| `CardsViewer` | `func focus_first() -> bool` | A viewer opens with NOTHING focused, so the HUD stays reachable: the first navigation or accept press enters the list, here. Answers whether it took the press |
| `CardsViewer` | `func focus_is_inside() -> bool` | THE ONE TEST for "the player is navigating inside this list": `focus_first()` refuses a list already entered, and `HudContainer` hands the arrows back to a viewer that holds the focus |
| `HudContainer` | `func _enters_the_hosted_viewer(event) -> bool`, `func _another_hosted_viewer() -> Node` | The viewer is in another viewport, where the overlay's focus search never looks, so the first arrow is handed over ahead of the GUI pass; and a viewer closing over another hands the field back |
| `HudContainer` | `func _the_arrows_belong_to_the_hosted_viewer(event) -> bool` | The sidebar reads keys BEFORE the GUI pass, so its page scroll and its up-to-the-X would answer a grid key the focused viewer's own neighbour search can use: while a listed card holds the focus the arrows are left alone, and only one that finds no neighbour comes back as `sidebar_requested` |
| `ChoiceViewer` | `var _backdrop`, node `Backdrop` (was `Dim`) | The chooser is the new focus until Take: an OPAQUE whole-picture cover, so the map behind it is not visible at all |
| `Map` | `func _show_only_the_deck_button(chooser_is_up: bool)` | The chooser has no node, so the row a picked node owns is borrowed for its one useful button |
| `CardsViewer` | `signal highlight_left`, `var _hovering`, `func _enter_highlight(data)`, `func _leave_highlight()` | A later hover BORROWS the description while it lasts; the pointer leaving every listed card hands it back to the stuck card, or takes an unstuck one away |
| `DeckViewer` / `ChoiceViewer` | `func cards() -> CardsViewer`, `func close_from_sidebar() -> void` | How the host reaches the shared model, and how the sidebar's X asks the viewer to go |
| `ChoiceViewer` | `func _follow_the_pick()`, `func _held_by_a_sticky_description() -> bool`, `static func _hold(button, held)` | The pick's ink, and every button beyond reach — pointer AND pad — while a sticky description is up |
| `HudContainer` | `var _suspended_lock`, `var _entry_under_the_viewer`, `var _hosted_viewer` | What a viewer is covering: the screen's own lock, the description it was showing, and the viewer itself, so the X can close it |
| `HudContainer` | `func highlight_gone()`, `func _close_hosted_viewer()`, `func _entry_to_come_back_to()`, `func _refresh_exit_button()`, `func _follow_the_viewers_sticky(stuck)`, `func _dismiss_from_the_x()` | The one answer for a highlight that has gone -- the board's `highlight_cleared` and a viewer's `highlight_left` alike: back to the stuck card, else what was under the viewer, else the HUD |
| `InfoEntry` | `var transient : bool` | This entry is a HIGHLIGHT, not something the player made stay: no X, and the highlight leaving closes it. Set by every publisher a hover or a focus reaches |
| `PlayArea` | `static func highlight_info(data: CardData, card_px: Vector2) -> InfoEntry` | `card_info()` marked transient -- the ONE home for what a hover or a focus publishes, on the board and in both card viewers |
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
| `ChoiceViewer` | `_select_on_click()`, `_on_card_gui_input()`, `select()`, `selected_card` | The pick IS the sticky card: one record, `cards().sticky`, read directly |
| `HudContainer` | `_entry_to_come_back_to()` | Inlined into its one caller, `show_description` |

## 5. Settings keys — `Scripts/player_settings.gd`

**Added:**

| Key | Type | Default |
|---|---|---|
| `container_size_fraction` | `float` | `0.25` |
| `container_slide_duration` | `float` | `0.25` |
| `container_size_max_px` | `float` | `640.0` |
| `card_tap_window_ms` | `float` | `300.0` |
| `card_drag_threshold` | `float` | `0.25` |
| `touch_target_fraction` | `float` | `0.06` |
| `entrance_flip_stagger` | `float` | `0.15` |
| `highlight_glow` | `float` | `1.825` |

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
| `Tests/Visual/sidebar_snapshot.gd` / `.tscn` | — | By-eye gate (`Q153`=a); also the hover/sticky/closed trio and the map's card description |

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

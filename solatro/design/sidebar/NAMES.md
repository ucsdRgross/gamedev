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
| `UI/part_icon.gd` | `PartIcon` | (added during execution) One part of a pack's possible cards -- a type, stamp, skill, suit or rank -- as a small labelled icon instead of a card (thirty-second round, "c: icons, not cards"); built in code, no scene |
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
| `PlayArea` | `var board_slide_offset : Vector2` | How far the slide has displaced the board's window from its RESTING place: the centre of the space the slid sidebar leaves less the centre of the space the resting one leaves, so with no sidebar the board set sits centred in the whole picture. The board's SIZE, and so its zoom, is fitted against the resting reserve whatever the sidebar is doing; only its position follows the slide, the Entrance strip with it on both axes |
| `PlayArea` | `var board_visible_crop : Vector2` | The picture px a covering window crops off the RIGHT and BOTTOM: the board's region ends there, so it fits and centres in what the player can SEE (D9, D10, `GAP-002`=a) |
| `PlayArea` | `static func reference_window_size() -> Vector2` | The project's own authored window shape, read from `ProjectSettings` — the aspect the game picture's height is built to and the container's cap is measured against (D6, `GAP-001`=b) |
| `WallPicture` | `static func visible_rect_beside(design: Vector2, window: Vector2, rect: Rect2, top: bool, scale: float) -> Rect2` | `local_rect_beside()`'s whole arithmetic, for a caller holding a design size but no picture instance; the instance method delegates to it with its own drawn scale (D8, `GAP-002`=a). (`scale` added during execution: the canvas-to-window scale - the picture's drawn scale for the visible space, `cover_scale` for the board's reserve, forty-third and forty-fourth rounds) |
| `GameView` | `static func board_space_beside(window: Vector2, rect: Rect2, top: bool) -> Rect2` | (added during execution) The board's reserve beside `rect`: the game picture's space at the COVERING scale, not the drawn one the map, menu and pile aim read - grid isolation leans on the overfill (forty-fourth round); `_publish_board_inset` and the board rows read it |
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
| `HudContainer` | `signal exit_accepted` | The sidebar let the focus go: the X accepted from keyboard or pad, or a right press off its last control |
| `HudContainer` | `signal slide_settled` | The slide reached its aim, or the container is leaving the tree, which releases `slide_to()`'s waiters too |
| `HudContainer` | `func _join_focus_while_shown(button: Button, shown: bool) -> void` | The one rule for the X: a panel control is visible and in the focus chain for exactly the same span (C16) |
| `HudContainer` | `func _shown_hosted_viewer() -> _HostedViewer` | (changed during execution) The newest viewer up on the screen being shown, or null -- a viewer left open on another screen answers nothing here: the map's up-into-the-panel route yields to a viewer's focus chain (K10, `GAP-012`=a) |
| `HudContainer` | `func mount_description_buttons(row: Control) -> void` | Hangs a screen's own row of buttons at the head of the description, above its name and visual; the screen builds the row, decides when it shows and owns the node |
| `DescriptionPanel` | `func mount_buttons(row: Control) -> void` | The `%ButtonRow` slot: the panel never learns what the buttons do |
| `DescriptionPanel` | `func show_buttons(shown: bool) -> void` | (added during execution) Whether the mounted row may show at all: `HudContainer.set_active_screen` shows it on the map screen only, so no other screen's card description carries the map's buttons |
| `DeckViewer` | `static func read_close_while_open(opener: Button, close_key: StringName, viewer: DeckViewer) -> void` | (added during execution) The opener reads its Close label while its own viewer is up and gets its own text back when the viewer leaves the tree; `Map` and `GameView` call it for every opener |
| `DeckViewer` | `static func show_deck(parent: Node, new_deck: Array[CardData], opener: Control, over := false, parts := false) -> DeckViewer`, `var lists_parts`, `func _publish_part_info(data)` | (`over` and `parts` added during execution) `parts` lists the deck as `PartIcon`s and describes each through `PartIcon.part_info`; `Map._show_possible_cards` passes it. `over` `over` opens the new viewer OVER the open one, which stays open underneath and is on top again when the new one closes; `Map` passes it while a card is stuck in a pack's possible cards, so the run deck opens over that list |
| `DeckViewer` | `var close_tab : Button`, node `CloseTab` | (added during execution) The X tab sticking out of the top of the viewer window's right side, closing that viewer alone (a stack's lower viewer keeps its own); `HudContainer._fit_viewer` sizes it to the X's touch target. The pack chooser carries none |
| `CardsViewer` | `var close_tab : Control` | (added during execution) The viewer's close tab, or null: its focus counts as inside the list, so an arrow from it walks the viewer's own grid instead of being handed back to the first card |
| `WorldMapController` | `func select_node(node: WorldGraphNode) -> void` | A pointer, finger or pad PICKS a reachable node; travelling is the map screen's Travel button |
| `WorldMapController` | `func clear_selection() -> void` | Back to the basic view: nothing picked, nothing marked |
| `WorldMapController` | `func auto_select_if_single() -> void`, `var auto_picking` | One onward node needs no click, so it is picked on population, on a lap flip, and when a won show or a Take hands the map back; `auto_picking` is true only while that pick's `node_selected` runs, and `Map` reads it to leave a pack's contents unopened |
| `WorldMapController` | `func selected() -> WorldGraphNode` | The standing pick, or null at rest |
| `WorldMapController` | `signal node_selected(node: WorldGraphNode)`, `signal selection_cleared` | The pick changed, or went |
| `WorldMapController` | `signal travel_focus_requested` | Accept on the map, a map node being no Control: the screen hands the pad to its Travel button |
| `Map` | `var travel_button`, `var selection_deck_button`, `var possible_cards_button` | The picked node's own buttons on the DESCRIPTION side, the HUD's Deck button being gone with the HUD |
| `Map` | `var _packs_shown : Dictionary[int, bool]` | The pack nodes already listed where the token stands; cleared by an arrival and by a new run |
| `Map` | `func _host_map_viewer(viewer: DeckViewer) -> void` | Every viewer this screen opens comes back to the picked node's description |
| `ChoiceViewer` | `var selected_card : CardData`, `func select(card: CardData) -> void` | The card the player picked out of a pack; Take adds the whole pack either way |
| `CardVisual` | `var selected : bool` | Drawn as the outer rim in `PaletteRoles.selected_rim`; the moving focus overrides it |
| `PaletteRoles` | `var selected_rim : int` | The ink a picked pack card's rim wears while the focus is elsewhere |
| `HudContainer` | `func host_viewer(viewer: Node, relay: Signal, screen: StringName) -> void` | (`screen` added during execution: the chooser can open while the map is not the screen shown) Wires a `DeckViewer`/`ChoiceViewer` on any screen, filed under the screen that opened it: relay, return to the lock, focus fallback, fit and re-fit (republishing only while a description shows) |
| `GameView` | `func pile_center(pile: Control) -> Vector2` | Where a card leaving the board aims: the window pile's centre, in the game picture |
| `PlayArea` | `func return_focus_to_board() -> void` | After a key/pad accept on the X: focus on the described card, or a board rest when that control is gone |
| `PlayArea` | `func rest_focus_on_board() -> void` | The board rest: the card in hand, or the selected grid's origin cell — the control the overview's arrow selection lands on, and what a pad player steps from with nothing in hand (J13, `GAP-009`=b) |
| `GameView` | `func _rest_the_board_focus() -> void` | Called wherever the board settles (`rebuild()`, the processing-false edge): rests the board focus only while NOTHING in the picture holds it, so it never takes the focus off the player |
| `GameView` | `func _on_outcome_undo_pressed() -> void` | The outcome row's Undo: the shared `_on_undo_pressed`, then a board rest of the picture viewport's focus, which the HUD's Undo (a root-viewport press) must not do (J13, `GAP-009`=b) |
| `TestGridFixtures` | `static func lit_cell_count(...) -> int` | Test support: the cells whose face is DRAWN at `highlight_glow` — one expected value, the focus being an outline that brightens nothing — the one counter `TestSidebar`, `TestDragPlace` and the snapshot share |
| `TestGridFixtures` | `static func leftmost_entrance_slot() -> int` | Test support: the leftmost Entrance slot holding a card, or -1, off the current game's state — the one query `TestSidebar` and `TestDragPlace` share |
| `HudContainer` | `func set_card_in_hand(held: bool) -> void` | Added during execution: relayed from `PlayArea.hand_changed`; while the game screen holds a card, Up and Down reach the board instead of scrolling the stuck description or climbing to its X |
| `TestGridFixtures` | `static func arrow_keys_to_a_legal_cell(from: BoardCoord, card: CardData) -> Array[Key]` | Test support (added during execution): the arrows from `from` to a cell of its own grid `card` may land on, across then up or down, never off the bottom row — the one keyboard walk `TestSidebar` and `TestDragPlace` share |
| `TestGridFixtures` | `static func brightness_of(poly: Polygon2D) -> float` | Test support: the `u_brighten` one card polygon is drawn at; an unset uniform reads back as the shader's 1.0 |
| `PipSuit` | `func get_plural_str() -> String` | The suit's name in the plural, read by the card title alone ("King of Knives", and "Knives" for a card with a suit and no rank); every other surface, the suit's own description block included, names it through `get_str()` |
| `CardOutline` | `static func set_brightness(poly: Polygon2D, brightness: float) -> void` | The per-element highlight channel: an equal-channel multiplier on this polygon's drawn BODY, never its rim, 1.0 unlit |
| `CardVisual` | `var on_drop_map : bool` | This card's cell is one the held card may land in — the one mark `_apply_marks` brightens the face by |
| `CardVisual` | `var focused : bool` | The board is pointing at this card: `_apply_marks` draws it as the card's OUTER rim in the match ink, never as a brighter face |
| `PlayArea` | `signal hand_released` | A drag's release landed on nothing that takes the card, so the player dropped it — `GameView._finish_with_the_card` |
| `GameView` | `func _finish_with_the_card() -> void` | The player ACTED with the card (a placement, a drop): the description goes back to the HUD and the focus rests on the board. A cancel is not an act and reaches none of this |
| `WorldMapController` | `static func node_screen_rect(node: WorldGraphNode) -> Rect2` | A map node's marker rect in the map viewport's coordinates |
| `TestMainHost` | `static func mount(parent: TestSuite, host: Node, scene: PackedScene) -> Node`, `static func unmount(parent: TestSuite, node: Node) -> void` | Test support: record the tree's `paused` before a Wall mounts, write it back after it is freed |
| `TestMainHost` | `static func boot_in_players_window(parent: TestSuite, size: Vector2i) -> Array` | Test support (added during execution): boots a real `Main` in an embedded `Window` carrying the root's own `content_scale_*`, so it draws at the player's content scale at `size` (1.111 at 1280x720, 0.52 at 600x1000) where the run's own window, at the project's base size, draws at 1 like the harness's SubViewport; `unfocusable` and placed off the root's rect, so it takes none of the root's input |
| `TestSidebar` | `func test_every_viewer_draws_at_the_ui_size_in_the_players_window()`, `func test_the_chooser_fits_its_rows_beside_the_sidebar_in_the_players_window()`, `func test_the_menus_column_draws_at_the_ui_scale_beside_the_sidebar_in_the_players_window()`, `func test_the_board_is_centred_beside_the_resting_sidebar_in_the_players_window()`, `func test_the_maps_sea_buffer_is_whole_on_screen_in_the_players_window()`, `func _check_the_sea_buffer_beside_the_sidebar(viewport, where)`, `func _check_the_players_scale(window, where)`, `func _check_the_games_viewers_at_the_ui_size(where)`, `func _check_drawn_at_the_ui_scale(viewport, rect, control, where)` | Test support (added during execution): the four size and layout claims measured in the player's window's own pixels at 1280x720 and 600x1000, each printing the content scale it ran at and refusing a scale of 1 |
| `TestSidebar` | `func test_a_right_click_over_a_stuck_deck_viewer_card_cancels_as_esc_does()`, `func test_a_right_click_over_a_stuck_chooser_card_lets_it_go_as_esc_does()`, `func _click(at, viewport, button := MOUSE_BUTTON_LEFT)`, `func _push_mouse_button(at, viewport, pressed, device := 0, button := MOUSE_BUTTON_LEFT)` | Test support (`button` added during execution): the right-click rows push a real second-button press and release through the booted viewport |
| `GameView` | `var _outcome_buttons : HBoxContainer` | The row the outcome's Continue and its own Undo sit in, centred on the win/lose screen and freed as one. The Undo button itself is a local: nothing keeps it, and a test finds it by its label (J13, `GAP-009`=b) |
| `GameView` | `func _add_outcome_button(row: HBoxContainer, key: StringName, handler: Callable) -> Button` | One localised button in the outcome row, wired to `handler`; Continue and Undo are its two callers (J13, `GAP-009`=b) |
| `CardsViewer` | `var sticky : CardData`, `func stick_to(data)`, `func unstick()`, `signal sticky_changed(stuck: bool)` | THE ONE STICKY MODEL every viewer shares: a click on a listed card pins the sidebar to it, and the host turns that into `HudContainer.lock_to`/`clear_lock` — the same lock a board click makes |
| `CardsViewer` | `static func bar_in_the_frame(scroll: ScrollContainer, card_margin: MarginContainer, scrolls: bool) -> void` | (added during execution) Every viewer's vertical bar is drawn in its window's right frame band, never in the card area: shown only while the list scrolls, the card margin's right side giving the band back to the cards' gap otherwise, so a scrolling and a still viewer of the same columns are one width. `DeckViewer` and `ChoiceViewer` call it from their fits |
| `CardsViewer` | `enum Modal { PASS, KEEP, CLOSE }`, `const NAVIGATION`, `func modal_verdict(event) -> Modal` | The modal rule, in one place: a viewer answers cancel and every arrow that walked off its list's own edge, so the map or board beneath never sees one |
| `CardsViewer` | `signal sidebar_requested` | An edge arrow with a card stuck: the X is in a separate Control tree the neighbour search never crosses, so the host grabs it |
| `CardsViewer` | `func focus_first() -> bool` | A viewer opens with NOTHING focused, so the HUD stays reachable: a navigation press from outside the sidebar, or off its inner edge, enters the list, here. Answers whether it took the press |
| `CardsViewer` | `func focus_is_inside() -> bool` | THE ONE TEST for "the player is navigating inside this list": `focus_first()` refuses a list already entered, and `HudContainer` hands the arrows back to a viewer that holds the focus |
| `HudContainer` | `func _enters_the_hosted_viewer(event) -> bool` | (changed during execution) An arrow with the focus outside the sidebar -- or nowhere -- is handed into the hosted viewer ahead of the GUI pass, so no key reaches the screen beneath. With the focus in the sidebar the GUI pass walks it, and ANY arrow there that finds no neighbour (off the sidebar's inner edge, and equally Up off the Piles row, Down off the Actions row, Left off Deck or Undo, any direction off the map's lone Deck button) falls through to the viewer's `modal_verdict`, which enters the list |
| `HudContainer` | `func _leaves_the_viewer_for_the_sidebar(event) -> bool` | (added during execution) The mirror: Left off a listed card with no left neighbour enters the sidebar through `focus_sidebar()` whenever that finds a control to land on; otherwise the press stays the viewer's |
| `HudContainer` | `func focus_sidebar() -> bool` (now answers whether it took the focus; `CardsViewer.sidebar_requested`, `PlayArea.sidebar_requested` and `WorldMapController.sidebar_requested` all land here), `func _sidebar_focus_target() -> Control`, `static func _first_focus_in(root) -> Control`, `static func _shown_under(control, root) -> bool`, `func _what_a_lost_highlight_shows() -> InfoEntry`, `func _offers_the_x(shown) -> bool` | (added during execution) ONE order for every press into the sidebar: its X whenever the X shows, else the description's own mounted row, else the HUD's first control; the row is reached from the X by an arrow. The target is predicted BEFORE anything changes and the landing is what `highlight_gone()` then shows: both read the same `_what_a_lost_highlight_shows()` and `_offers_the_x()`, and the walk rows compare the focus owner after every press. With no target the press changes nothing, the description included. The grab ASSERTS its target is on screen: while the container is slid out no producer runs (measured: input unlocks frames before the sidebar slides in, but the wall's focus is then still the frozen screen being left, and a Left there asks no screen for the sidebar; a hidden viewer is disabled and has no focus) |
| `TestSidebar` | `func test_left_off_the_menus_viewer_stays_in_it_with_nothing_to_land_on()`, `func test_left_off_the_deck_over_a_stuck_chooser_card_lands_on_close_deck()`, `func test_left_off_the_possible_cards_lands_on_the_picks_x_first()`, `func test_a_left_before_the_sidebar_slides_in_asks_no_screen_for_it()`, `func _tap_pad_in(viewport, button)` | Test support (added during execution): the refusal where the menu shows no HUD, and the row that opened a deck over a stuck card taking the focus back from it |
| `TestSidebar` | `func test_tab_opens_the_wall_on_every_screen_as_the_pad_button_does()`, `func _stand_on(screen) -> ChoiceViewer`, `func _focus_owners() -> Array`, `func _push_wall_overview_press(press, pressed)`, `const TAB_SCREENS` | Test support (added during execution): on the menu, the bare map, a described map node, the board, the board with its deck viewer open and the pack chooser, Tab, Shift+Tab and the pad's View button each open the wall and move no GUI focus |
| `TestSidebar` | `func test_the_sidebar_and_an_open_viewer_are_one_walk_with_nothing_stuck()`, `func _walk_by(presses, landings, route)`, `func _walk_right_off_the_sidebar(press) -> bool`, `func _control_label(control)`, `const SIDEBAR_WALK_STEPS` | Test support (added during execution): arrows and the d-pad walk the sidebar and an open viewer as one, the focus owner asserted after every press |
| `HudContainer` | `func _the_arrows_belong_to_the_hosted_viewer(event) -> bool` | The sidebar reads keys BEFORE the GUI pass, so its page scroll and its up-to-the-X would answer a grid key the focused viewer's own neighbour search can use: while a listed card holds the focus the arrows are left alone, and only one that finds no neighbour comes back as `sidebar_requested` |
| `ChoiceViewer` | node `Layout` (a `Panel` in the HUD background), `func fit_beside(remaining)` | (changed during execution) The chooser's window on the sidebar's own layer, at the UI scale: wide enough for `ROW_CARDS` cards and exactly as tall as its rows over the Rerolls-and-Take foot row, growing a row at a time up to `ROWS_SHOWN` rows or the space beside the sidebar, whichever is less, with the rest scrolling, centred in that space (no longer a square: visual review round 3, "expand only when card count increases"). Its `_unhandled_input` stops every mouse event no control took, so the map around the window stays in view and inert; a touch passes to the wall's pinch |
| `ChoiceViewer` | `const ROW_CARDS := 5`, `const ROWS_SHOWN := 5` | (added during execution; `ROW_CARDS` replaces `PlayerSettings.chooser_row_cards`) Cards in one row, and the rows the window grows to show before the rest scroll |
| `ChoiceViewer` | node `Scroll` (a `ScrollContainer`, `var _scroll`) holding node `FlowContainer` (an `HFlowContainer`, `var flow_container`, replacing `flex_container`) | (added during execution) The card rows, each centred, the gap between rows the Reroll buttons hanging under the row above plus the viewer's card gap |
| `DeckViewer` | `func fit_catcher(shown: Rect2)` | (added during execution) The click-to-close catcher is everything beside the sidebar as it is shown, following its slide; `fit_beside()` then insets the list inside it to where the sidebar rests |
| `TestSidebar` | `func test_a_click_beside_the_menus_viewer_closes_it_and_the_sidebar_slides_out()` (renamed during execution: the viewer slides the menu's sidebar in), `func test_a_new_run_closes_the_last_runs_possible_cards()`, `func test_a_new_run_throws_away_the_last_runs_chooser()`, `func _start_a_new_run_from_the_wall()` | Test support (added during execution) |
| `HudContainer` | `func release_the_pick()` | (added during execution) A map pick dropped (leaving the map, a dismissal) releases only its own description: with no viewer open there, the map's whole sidebar state; with one, only what the viewers covered, keeping the lock each set aside and the lock a stuck viewer card holds, which the viewer's close hands back; `release_screen()` stays the teardown |
| `HudContainer` | `func close_the_map_viewers()` | (added during execution) A new run closes every viewer the map left up on the sidebar's layer, newest first, before `Map.start_run` releases the map's sidebar state: a list or deck closes, a pack chooser is thrown away |
| `ChoiceViewer` | `func discard()` | (added during execution) Closes the pack without adding a card, announcing the lost highlight: Take after it confirms, and a new run throwing the last run's pack away |
| `HudContainer` | `func _fade_overlay_viewers()` | (added during execution) Every viewer is on the sidebar's layer (asserted to be under the wall overlay): it fades with the slide, hidden and deaf to input on every screen but its own and in wall view; set by `host_viewer()`, ended by the viewer closing or leaving the tree |
| `Map` | `func _host_map_viewer(viewer: DeckViewer)` | (changed during execution) Every map viewer -- possible cards, the run deck, the deck over either -- opens on the sidebar's layer and is hosted with no picture |
| `ChoiceViewer` | node `BottomRow` (an `HBoxContainer` holding `RerollsLeft` and `ConfirmButton`), `var _bottom_row` | (added during execution) Rerolls left beside Take in one row along the window's foot, centred as a pair |
| `Map` | `func _show_only_the_deck_button(chooser_is_up: bool)` | The chooser has no node, so the row a picked node owns is borrowed for its one useful button |
| `Map` | `func chooser_is_up() -> bool` | (added during execution) A pack chooser is up, so its borrowed Deck row stays while a map viewer opens or closes over it |
| `HudContainer` | `func board_highlight_gone() -> void` | (added during execution) The board's `highlight_cleared` enters here, connected by `GameView`: `highlight_gone()` only while the game screen is the one shown, so a frozen show losing its focus leaves the map's sidebar alone |
| `CardsViewer` | `signal highlight_left`, `var _hovering`, `func _enter_highlight(data)`, `func _leave_highlight()` | A later hover BORROWS the description while it lasts; the pointer leaving every listed card hands it back to the stuck card, or takes an unstuck one away |
| `DeckViewer` / `ChoiceViewer` | `func cards() -> CardsViewer`, `func close_from_sidebar() -> void` | How the host reaches the shared model, and how the sidebar's X asks the viewer to go |
| `ChoiceViewer` | `func _follow_the_pick()`, `func _held_by_a_sticky_description() -> bool` | The pick's ink, and every button beyond reach — pointer AND pad — while a sticky description is up, through `HudContainer.hold` |
| `HudContainer` | `class _HostedViewer` (`viewer`, `screen`, `suspended_lock`, `covered`), `var _hosted_viewers` | (changed during execution) One record per viewer up, filed under the screen that opened it: what it covers there -- the screen's own lock and the description it was showing -- and the viewer itself, so the X can close it. A viewer opened over another (the run deck over the chooser) sets the chooser's stuck card aside and gives it back |
| `HudContainer` | `func highlight_gone()`, `func _close_hosted_viewer(viewer)`, `func _refresh_exit_button()`, `func _follow_the_viewers_sticky(stuck)`, `func _dismiss_from_the_x()` | The one answer for a highlight that has gone -- the board's `highlight_cleared` and a viewer's `highlight_left` alike: back to the stuck card, else what was under the viewer, else the HUD |
| `InfoEntry` | `var transient : bool` | This entry is a HIGHLIGHT, not something the player made stay: no X, and the highlight leaving closes it. Set by every publisher a hover or a focus reaches |
| `PlayArea` | `static func highlight_info(data: CardData, card_px: Vector2) -> InfoEntry` | `card_info()` marked transient -- the ONE home for what a hover or a focus publishes, on the board and in both card viewers |
| `HudContainer` | `func resting_rect_beside(picture: WallPicture) -> Rect2` | The space beside where the container RESTS: a hosted viewer's layout and the map's fit both read it |
| `WorldMapController` | `func apply_container_shift(shift: Vector2, space: Vector2)`, `func _place_camera()`, `func return_to_fit()`, `var _space`, `var _zoom_in` | The map is fitted to the space beside the resting sidebar; `_place_camera()` is the camera's one writer -- the fit is the zoom floor and the position is clamped to the map and its sea buffer; `return_to_fit()` drops the player's zoom on every map entry and at the start of every Travel |
| `WallPicture` | `func _crop_to_rect() -> Vector2` | (added during execution) `%Screen`/`%Shadow` show the canvas's centred part at the rect's aspect, whole texels, and draw it at `rect.size` -- a picture is cropped to the window's shape, never stretched; the scale actually drawn is the rect the camera frames |
| `WallPicture` | `func _shown_canvas() -> Vector2` | (added during execution) The canvas part a picture shows; `update_wall_view_size()` sizes the render target so that part gets a texel per footprint pixel, its short axis floored at `wall_view_min_texture_px` |
| `Map` | `var sea : ColorRect`, nodes `SeaLayer`/`Sea` | The map picture's background, painted the colour the map paints its own ocean |
| `Game` | `func legal_cells_for(held: Array[CardData], grids: Array[GridData]) -> Array[CardData]` | THE ONE legality walk: the zone card of every cell in `grids` where `held` may land, asked through `on_can_place_stack` exactly as `try_place` asks. `_no_held_card_has_a_legal_placement`, `_no_legal_placement_remains_in_grid` and `PlayArea._sweep_legal_cells` all read it (G12, `GAP-005`=a) |
| `Wall` | node `WallSurfaceLayer` (a `CanvasLayer`, layer -1) holding `%WallSurface` | (added during execution) Screen space, behind the camera-moved pictures: the surface fills the whole window at every zoom, in wall view and in transit |
| `TestSidebar` | `func test_the_wall_view_shows_one_surface_colour_behind_the_pictures()`, `func _uncovered_pixels()`, `func _off_surface_pixels(...)`, `func _drawn_wall_view_parts()`, `const TRANSIT_BASE_DELAY`, `const TRANSIT_MIN_FRAMES`, `const SURFACE_COLOUR_TOLERANCE`, `const PICTURE_EDGE_MARGIN` | Test support (added during execution): reads the booted root's pixels outside every drawn picture part and overlay button, at rest and through the move out to the wall |
| `TestSidebar` | `func test_wall_view_keeps_the_board_centred_in_its_picture()`, `func _board_set_parts(pa: PlayArea) -> Array[Rect2]` | Test support (added during execution): after the real Wall click, the grid and the Entrance row sit as far from the whole picture's centre as they sat from the resting space's centre, at 1280x720 and 600x1000 |
| `TestSidebar` | `func test_the_choosers_cards_draw_at_the_ui_size_whatever_the_map_zoom()`, `func test_the_chooser_and_its_deck_are_hidden_in_wall_view_and_back_on_return()`, `func test_keys_stay_in_the_chooser_on_the_windows_own_viewport()`, `func _check_cards_at_the_ui_size(cards, where)`, `func test_the_maps_viewers_draw_at_the_ui_size_whatever_the_map_zoom()`, `func test_the_maps_viewer_stack_is_hidden_in_wall_view_and_back_on_return()`, `func _ui_space(main) -> Rect2`, `func _drag_in_the_window(from, by)`, `func _wait_out_the_return()` | Test support (added during execution): the chooser and the deck over it on the sidebar's layer -- the UI card size at both window shapes and two map zooms, hidden and deaf in wall view and faded back in, and the key focus owner in the window's own viewport; the chooser rows' space, drags and returns in the window's own pixels |
| `TestUiViewers` | `func test_a_wrapped_row_lies_below_the_reroll_buttons_above()`, `func test_the_window_shows_five_rows_then_scrolls()`, `func _fitted_chooser(count, remaining) -> ChoiceViewer`, `func _cards_in_the_first_row(viewer) -> int` | Test support (added during execution): the wrapped row clears the Reroll buttons above it; five rows show, a sixth scrolls, a short space cuts the window |
| `SidebarSnapshot` (`Tests/Visual/sidebar_snapshot.gd`) | `const CHOOSER_WINDOW_OUT_PATH` (`chooser_window.png`, replacing `CHOOSER_OPAQUE_OUT_PATH` / `chooser_opaque.png`) | (renamed during execution) The chooser's window beside the sidebar with the map around it |
| `CardVisual` | `static func preview_window_px() -> Vector2` | (changed during execution) The one preview size, the deck viewer's card at the UI scale, for the board and every viewer |
| `CardVisual` | `func spotlight_scale() -> float` | (added during execution) The scale this card is DRAWN at, for a spotlight sized in art units: the root's global scale (`card_scale` and every scale above it, the board's zoom included), never `Offset`'s or `Art`'s, which the jump and the rig animate. `SpotlightDirector` and the spotlight tool both read it |
| `CardVisual` | `func spotlight_center() -> Vector2` | (changed during execution) The DRAWN card's centre (`Visual`), where it was the art square's - owner: "the card's centre" |
| `GameView` | `func _open_deck_viewer(cards, opener, close_key)` | (changed during execution) Deck, Discard and Rules open on the sidebar's layer, hosted with no picture, and are freed when the view leaves the tree, as they were when they lived inside it |
| `TestSidebar` | `class _FocusWarnings` (a `Logger`, `var count`) | Test support (added during execution): counts the engine's "can't grab focus" warning, which the gate's ERROR-only scan of `godot.log` never counts: across a new run started from the menu, and around the close of a list whose pick a leave dropped |
| `TestSidebar` | `func test_the_games_viewers_draw_at_the_ui_size_at_both_window_shapes()`, `func test_a_game_viewer_is_hidden_in_wall_view_and_back_on_return()`, `func test_the_board_behind_an_open_viewer_answers_no_pointer()`, `func _point_in_window(id, at)` (replacing `_map_point_in_window`) | Test support (added during execution): Deck, Discard and Rules at the UI card size in the window's own viewport at both window shapes; a game viewer hidden and deaf in wall view and faded back in with its stuck card; the board behind it deaf to a hover and a drag pushed at the window |
| `DeckViewer` | `func _ready()`, node `ColorRect` (its translucent literal colour removed) | (changed during execution) Every viewer's backdrop is opaque in `PaletteDB.ROLES.hud_background`, the sidebar's and the chooser's one colour: nothing behind shows between or under its cards (owner, thirty-fourth round: "Every viewer") |
| `DeckPicker` | `signal inspect_pressed(cards: Array[CardData], inspect: Button)` | (added during execution) Inspect on a deck's row; the menu opens that deck's viewer with `inspect` as its opener |
| `Menu` | `func _open_deck_viewer(cards, inspect, picker)` | (added during execution) Opens the picker's viewer on the sidebar's layer, hosts it on the menu screen, and frees it with the picker |
| `TestSidebar` | `func test_the_sidebar_is_hidden_on_the_menu_until_the_picker_shows_something()` (replacing `..._until_the_picker_describes_something`), `func test_the_menus_viewer_draws_at_the_ui_size_at_both_window_shapes()`, `func test_the_menus_viewer_fades_with_the_sidebar_across_a_leave()`, `func test_picking_a_deck_with_the_viewer_open_closes_it()`; `_check_cards_at_the_ui_size(viewport, cards, where)`, `_await_the_menus_slide(container, aim)`; `SidebarSnapshot.MENU_INSPECT_HOVER_OUT_PATH` (`menu_inspect_hover.png`) | Test support (added during execution): the menu's sidebar in, empty, for the picker's viewer and out when it closes; the viewer at the UI size at both window shapes, faded across a leave, closed by a Pick |
| `DeckPicker` | `extends Control` (was `CanvasLayer`, layer 64, in the menu picture), `static func add_to_scene(parent: Node, opener: Control)` (`opener` added), `func fit_beside(remaining: Rect2)`, `var _panel`, `var _scroll`, `func focus_the_first_pick()` | (changed during execution) The picker is UI on the sidebar's layer at the UI scale: the menu adds it to the overlay, handing in New Run as the control the focus returns to; `fit_beside` centres its list in the space beside the sidebar as it is shown; `focus_the_first_pick` takes the first Pick with its list at the top: at `_ready`, and from `HudContainer` each time it is shown again with no viewer over it |
| `HudContainer` | `func host_deck_picker(picker: DeckPicker)`, `var _deck_picker`, `func _forget_the_deck_picker()`, `func _refocus_the_deck_picker()`, `func _show_on_this_layer(node, drawn, shown)` | (added during execution) Files the menu's picker under the overlay's own controls (its dim takes the pointer over the picture, the Back row and the sidebar keep theirs), slides the menu's sidebar in, empty, while it is up (owner, thirty-fourth round), re-centres it on every container rect change, and fades it with the slide on the menu only, like every viewer; `_show_on_this_layer` is the one writer of an overlay occupant's alpha, visibility and process mode. Set by `host_deck_picker()`, cleared as the picker leaves the tree |
| `TestSidebar` | `func test_the_deck_picker_draws_at_the_ui_size_on_screen_at_both_window_shapes()`, `func test_the_deck_pickers_viewer_draws_over_the_picker()`, `func test_keys_reach_every_deck_picker_control_in_the_windows_own_viewport()`, `func test_the_menu_behind_the_deck_picker_answers_no_pointer()`, `func test_the_deck_picker_is_hidden_in_wall_view_and_back_on_return()`, `func _the_deck_picker(main)`, `func _press_new_run(main)`, `func _open_the_deck_picker(size)`, `func _drawn_in_window(viewport, control)`, `func _tap_key_in(viewport, keycode)`, `func _picture_point_in_window(picture, at)`, `func _a_picker_label_under_the_viewer_between_its_cards(viewport, picker, viewer)`, `func test_a_return_to_the_menu_leaves_the_focus_to_the_pickers_viewer()`; `SidebarSnapshot.MENU_PICKER_OUT_PATH` (`menu_picker.png`) | Test support (added during execution): the picker in the window's own viewport at the UI size, on screen and centred at both window shapes; its viewer over it, opaque, no picker row showing through; keys through Inspect, the viewer, Close and Pick; the menu deaf behind its dim with the overlay row still live; hidden in wall view and back on return |
| `PlayArea` | `static func viewer_separation_px() -> int` | (added during execution) The board's `BOARD_SEPARATION` in a card viewer's UI pixels, at the viewer's card scale: the deck viewer's and the chooser's gap between cards, across and down (the chooser's under its Reroll band) |
| `CardsViewer` | `func row_px(columns: int) -> float`, `func column_px(rows: int) -> float` | (added during execution) The width of `columns` listed cards and the height of `rows`, with the list's own gaps between them: the one rule the chooser's window and the deck viewer's whole columns size by |
| `DeckViewer` | `func fit_beside(remaining)` (changed during execution), `var _scroll` | (added during execution) The list is the widest whole number of columns inside the authored margins (a floor), centred where it rests: whole columns inside the frame, the spare width left outside the window in halves, the bar per `CardsViewer.bar_in_the_frame` |
| `TestUiViewers` | `func test_the_viewers_gap_is_the_boards_at_their_card_scale()`, `func test_the_deck_viewers_list_is_whole_columns_centred()`, `func _in_window(control)`, `func _fitted_deck_viewer(count, remaining)` | Test support (added during execution): measured in the root window at whatever size it has, after the host's re-fit; the 600x1000 top case is covered by shots |
| `TestOutline` | `func test_the_glare_slider_limits_are_the_card_width()` | (added during execution) `OutlineStyle`'s typed-out glare slider limits equal `CardVisual.CARD_SIZE.x` and half of it |
| `Menu` | nodes `Content` (`VBoxContainer`), `Content/Run` (`HFlowContainer`, was the `Play` HBox), `Content/Main` (`HFlowContainer`); `var play_row : HFlowContainer`, `var _content` | (changed during execution) The menu is one centred column at the UI scale beside the sidebar as shown: title, Play, the Play submenu below Play, the bottom row wrapping; `_fit_beside_container`, `_content_bounds`, `_authored_positions`, `_design_rect`, `_title`, `_main_control` are gone |
| `ChoiceViewer` | `func take_the_focus() -> void` | (added during execution) Where a key or pad player finds the pack: Take, or the stuck card while Take is held; called on opening and each time the chooser fades back in |
| `HudContainer` | `func _refocus_the_chooser(chooser: ChoiceViewer) -> void` | (added during execution) A chooser shown again (a return to the map) takes the focus back unless the run deck is up over it |
| `TestUiViewers` | `func test_the_pack_chooser_passes_a_cancel_on_once_nothing_is_stuck()` (was `test_the_pack_chooser_swallows_a_cancel_it_cannot_answer`) | Test support (renamed during execution): a cancel unsticks and stops; with nothing stuck it passes on to the wall |
| `TestSidebar` | `func _stuck_control(chooser)`, `func _check_the_key_focus_is_on(expected, when)` | Test support (added during execution): after each route back to the chooser, the focus owner in the window's own viewport is the stuck card, or Take |
| `TestSidebar` | `func test_every_menu_control_draws_at_the_ui_size_inside_the_window_and_none_overlaps()`, `func test_the_menus_bottom_row_wraps_beside_the_slid_in_sidebar()`, `func _menu_control_in_window(viewport, picture, control)`, `const _MENU_BUTTON_PATHS` (was `_MENU_BUTTON_NAMES`) | Test support (added during execution): every menu control at the UI scale across and down, inside the window, none overlapping, the Play submenu below Play, at 1280x720, 600x1000 and 1920x1080 (the harness's content scale 1: harness-scale only, the real window is covered by shots); the bottom row wrapped beside the picker's slid-in sidebar |
| `Menu` | `func take_the_focus()` | (added during execution) Grabs the key focus onto Play while `HudContainer.shows_the_bare_menu()`: on every `active_screen_changed`, and from `Main._end_the_warm_up`, whose throwaway board rested its own focus and cleared the menu's |
| `HudContainer` | `func shows_the_bare_menu() -> bool` | (added during execution) The menu is the screen shown with neither its deck picker nor a viewer up over it |
| `TestSidebar` | `func test_keys_alone_start_a_run_from_the_start_menu_and_find_it_again()`, `func test_a_pad_alone_starts_a_run_from_the_start_menu()`, `func _start_a_run_from_the_menu_with(device, accept, down, up, left)` (each press a bound `_tap_key`/`_tap_pad`), `func test_a_show_resumed_through_the_menu_rests_a_key_focus_on_its_board()`, `func test_a_resolved_show_resumed_through_the_menu_rests_the_key_focus_on_continue()`, `func _through_the_menu_and_back_by_keys()` | Test support (added during execution): one device alone from a fresh boot through Play, the submenu, the bottom row, New Run and a Pick onto the map, the focus owner checked in the menu's picture after each press; the menu takes no focus while the map is shown and rests it on Play again on return; a show left for the menu and resumed with keys lands with a key focus on its board, or on Continue with its outcome up |
| `TestSidebar` | `func test_the_menus_column_only_shifts_while_the_sidebar_slides()`, `func _sample_the_menus_slide(viewport, main, aim, start)`, `func _check_the_column_only_shifts(samples, what)`, `func _check_the_bottom_row_beside_the_sidebar(viewport, main, what)` | Test support (added during execution): every frame of the picker's opening and closing slides and of the landing back on the menu, at 1280x720 and 600x1000 (harness scale): one line layout from the frame before the slide to the frame after it (but for the one re-wrap frame), the column's centre stepping at most half the sidebar's step a frame and its buttons with it, the slide settled, and at rest the bottom row spanning the whole width beside the sidebar |
| `HudContainer` | `static func hold(button: Button, held: bool) -> void` | (moved during execution, from `ChoiceViewer._hold`) THE ONE RULE for a disabled button: disabled and out of the focus chain together, so arrows pass over it. Called by the chooser's Take/Reroll, the menu's Continue and the game's Submit |
| `TestSidebar` | `func test_a_keyed_end_leaves_no_focus_on_the_disabled_button()`, `func _holds_a_live_focus(viewport)` | Test support (added during execution): Enter on End moves the focus off the disabled button onto a live control in the show, and End is a focus target again once Undo resumes play |

| `CardsViewer` | `var controls : Array[Control]` (was `Array[ControlCard]`), `var _data_of : Dictionary[Control, CardData]`, `var item_px : Vector2`, `func populate_parts(cards, on_inspect) -> void`, `func _list(control, data)` | (added during execution) One list for cards and part icons alike: a key's stick reads the card a control stands for, and every row, column and whole-column fit is measured in the listed control's own size (the card preview size unless the list is of parts) |
| `PartIcon` | `var data`, `static func add_child_part_icon(parent, part_data) -> PartIcon`, `static func part_of(card) -> Resource`, `static func cell_of(icons) -> Vector2`, `func fit(cell)`, `static func part_info(part_data) -> InfoEntry` (at the one preview size) | (added during execution) The cell is the largest non-type part's framed window at `CardVisual.DECK_VIEWER_SCALE`, as wide as the widest label; a part draws one art unit per that scale, a type shrunk into the cell (forty-second round, "b: shrunk to the cell"). The sidebar gets the part's own `get_str`/`get_description` over a card preview carrying it; a part other than a type previews on `TypePaper`, whose frame is `CardVisual.BLANK_CARD_FRAME` |
| `CardModifierType` | `func has_effect() -> bool` | (added during execution) THE ONE RULE for naming a type on a card: `ControlCard.describe_card` gives a type a block, and `CardData.log_str` its `^`, only when it has an effect; `TypePaper` answers false, so its name and description show only on its own icon in a pack's possible cards (forty-third round, "b: only in the list") |
| `DeckViewer` | `SmoothScrollContainer.size_flags_horizontal = SHRINK_CENTER` (scene), `fit_beside` sizing the scroll to whole columns | (changed during execution) The opaque backdrop fills the viewer's whole window beside the sidebar; only the list inside is whole columns, centred, so a viewer over another hides it whatever either lists |
| `TestSidebar` | `func test_the_deck_over_the_possible_cards_hides_the_whole_list()`, `func _backdrop_of(viewer) -> ColorRect` | (added during execution) The run deck's backdrop encloses the possible-cards list under it |
| `PipRank` | `func get_description() -> String` | (added during execution) One line every rank shares, so a listed rank is never described empty |
| `PaletteRoles` | `var viewer_deck`, `var viewer_discard`, `var viewer_rules`, `var viewer_possible_cards`, `var viewer_pack`, `var viewer_inspect`, `var deck_picker`, `var close_tab` (all `int`) | (added during execution) Each overlay window kind's own placeholder backdrop, told apart from each other and from `hud_background` (owner, visual review round 3: "color each colored background differently"); `close_tab` is the X tab's solid fill |
| `DeckViewer` | `static func show_deck(parent, new_deck, opener, role: StringName, over := false, parts := false)`, `var backdrop_role : StringName` | (changed during execution) The opener names its viewer's kind as a `PaletteRoles` role, which paints the window; the X tab takes a solid `close_tab` style. Supersedes the one shared `hud_background` backdrop (row `DeckViewer` `_ready` above) |
| `GameView` | `func _open_deck_viewer(cards, opener, close_key, role: StringName)` | (changed during execution) Deck, Discard and Rules each pass their own role |
| `TestSidebar` | `func test_every_window_kind_draws_its_own_opaque_colour()`, `func _check_the_open_viewer_draws(role)`, `func _check_drawn_in(at, role, what)`, `const OPAQUE_COLOUR_TOLERANCE` | Test support (added during execution): the booted window's pixels show each kind opened by its product route in its own role and the X tab solid |
| `DeckViewer` | `fit_beside` insetting the list by `PlayArea.viewer_separation_px()` on every edge, `SmoothScrollContainer.size_flags_vertical = SHRINK_CENTER` (scene), the list's `focus` stylebox with no content margin | (changed during execution) The first row stands the board's gap below the window's top and the last row, scrolled to, the same gap above its bottom; a short list sits at the top with that gap; each side is at least the gap, the whole-columns slack on top |
| `TestUiViewers` | `func test_a_deck_viewers_rows_stand_the_gap_inside_its_window()`, `const SCROLL_SETTLE_TIMEOUT_SEC`, `func _scrolled_to_rest(card, window) -> bool` | Test support (added during execution): the four gaps from the backdrop's and the listed cards' drawn rects, a long list scrolled to its end by focusing its last card, and a short one |
| `TestUiViewers` | `func test_the_chooser_window_is_as_tall_as_its_rows()`, `func _cards_rows(cards) -> int`, `func test_the_pack_chooser_draws_only_its_window()` (renamed from `..._a_square_window`) | Test support (added during execution): 5, 6 and 11 cards, padded above and below as at the sides, the foot right under the last Reroll band, no scroll, centred |
| `TestSidebar` | `func test_the_chooser_is_a_fitted_window_with_the_map_around_it()` (renamed from `..._a_square_window_...`), `func _check_the_chooser_pads_its_rows_as_its_sides(chooser, where)` | Test support (changed during execution): the square check replaced by the fitted height, per visual review round 3 |
| `GameView` | `func _publish_board_inset()` (changed during execution), `func _place_the_outcome()`, `var _outcome_shift : Vector2`, `var _outcome_title : Label` | (added during execution) The Win/Lose screen still covers the whole play area; its title (a code-built child Label, the screen Label carrying no text, since a Label ignores its style margins when centring) and its buttons shift with the board's slid space, centre to centre |
| `TestSidebar` | `func test_the_outcome_centres_over_the_board_resting_and_slid()` | Test support (added during execution): the result's label and buttons across the board's drawn centre, resting and slid out, and the slide moving both alike, in the harness and the player's window at both shapes |
| `TestSidebar` | `func test_the_score_lines_draw_inside_the_sidebar_at_a_won_show()`, `func _check_the_score_lines_through_a_combo_pulse(view, moment)`, `func _check_the_score_lines_inside_the_sidebar(moment)`, `const LONG_SCORE_TOTAL`, `const LONG_SCORE_COMBO`, `const COMBO_PULSE_SAMPLES` | Test support (added during execution): Goal, Total and the score line's drawn text between the sidebar's inner margin and its right edge at a won show, through a stepped combo pulse and at long values, harness and player's window at both shapes; the pulse grows the score line from its left edge |
| `TestUiProps` | `func test_the_hoop_formation_is_one_horizontal_row()`, `func _run_tick(...)` (renamed from `run_tick`, a helper the registration gate read as a test) | Test support (added during execution): every hoop formation's points share one y; the suite now calls `check_all_tests_registered()` |
| `TestUiViewers` | `func test_each_reroll_text_centres_under_its_drawn_card()`, `func _drawn_card_in_window(card)`, `func _button_text_in_window(button)`, `const REROLL_CENTRED_TOLERANCE_PX` | Test support (added during execution): each Reroll label's text centre within half a UI px of its card's drawn centre |
| `PartIcon` | `const KINDS : Dictionary[StringName, StringName]`, `static func kind_of(card) -> StringName`; `part_of(card)` now reads `card.get(kind_of(card))` | (added during execution) Each kind of part keyed by its `CardData` field, in the order the possible-cards list groups them (owner: "type, talent, stamp, suit, rank"), to its header's locale key; a rank's art is filled with `PaletteRoles.part_rank_fill` through `CardOutline.fill_palette`, every other part in its sheet's own colours |
| `CardsViewer` | `var _headers : Dictionary[Label, int]`, `func fit_rows(columns: int) -> float` | (added during execution) `populate_parts` opens each kind's group with a left-aligned `Label` header (not listed, not focusable); `fit_rows` stretches every header to `row_px(columns)` so each group starts a row of its own, and returns the list's laid-out height (headers, rows, the card gap between every line), which `DeckViewer.fit_beside` decides the scrollbar by |
| `PaletteRoles` | `var part_rank_fill : int` (default 31) | (added during execution) The rank numeral's fill on a possible-cards icon: the cream of a Paper card's face, measured as palette index 31 in `card_types.png`'s blank frame (owner: "a: new role (Recommended)") |
| `TestSidebar` | `func test_the_possible_cards_group_each_kind_under_its_own_header()`, `func _check_the_groups(list, parts, kinds) -> bool`, `func _check_down_walks_every_group(list, kinds, press)`, `func test_a_possible_rank_is_filled_in_its_own_role_not_the_outlines_ink()`, `const RANK_SCROLL_FRAMES` | Test support (added during execution): each kind under its own left-aligned header one row wide, in order, a card gap under the header and under the group before, the list sized by its laid-out height, keys and d-pad walking down through every group; every texel of a rank numeral read off the window in `part_rank_fill` |
| `CardData` | `static var modifier_epoch : int` | (added during execution) A process-wide count of modifier attaches and removals on ANY card - the `skill` / `type` / `stamp` setters, `add_status`'s append and `remove_status` - monotonic and ended by nothing, read only for equality. `CardEnvironment._compare_implementers` keys its implementer cache on it beside `_revision_key()`, so a modifier attached or removed with no board mutation is seen by the next ask, and no revision moves |
| `TestMods` | `func run_implementer_cache_tests()`, `func run_attach_mid_walk_test()`, `func check_the_next_ask(g, mod, listed, revision, what)`, `const PROBE_HOOK`, `class ProbeSkill` / `ProbeType` / `ProbeStamp` / `ProbeStatus` | Test support (added during execution): on a real `Game`, each of the five attach and removal paths is seen by the next ask with the revision unchanged, and a status attached by a handler leaves the walk in progress whole |
| `TestSuitProps` | `func test_juggling_pays_in_the_placement_its_balls_land()` | Test support (added during execution): one placement scores a row and then a diagonal whose talented Ball juggles; its stacks pay into the column bucket in that same placement |

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
| `Main` | `_refuses_a_move()`, `_the_chooser_holds_the_player()` | The chooser no longer holds the player: Back, Forward and Wall leave it and come back to it in progress, so the move guard is `_move_in_flight` alone |
| `WallOverlay` | `refresh()`'s `held` parameter | Nothing greys the overlay while the chooser is up |
| `Map` | signal `chooser_changed` | Its one listener re-stated the overlay for the lock-out |
| `ChoiceViewer` | `var _backdrop`, node `Backdrop` | The chooser draws only its window; the map around it is kept inert by its `_unhandled_input` |
| `ChoiceViewer` | `_square_side()`, `_stops_at_the_window()`, `var flex_container` (the addon `FlexContainer`) | One call site each: folded into `fit_beside()` and `_unhandled_input`; the rows are an engine `HFlowContainer` in a `ScrollContainer` |
| `PlayerSettings` | `chooser_row_cards` | A setting nothing set: `ChoiceViewer.ROW_CARDS` |
| `ChoiceViewer` | `static func _hold(button, held)` | Moved to `HudContainer.hold`, the one home every disabled button shares |
| `GameView` | `_rest_the_board_behind_another_screen()` | `_start_on_screen` rests the show's focus on every go-live of its picture (Continue with the outcome up, else the board), which covers a viewer another screen closed |
| `TestSidebar` | `test_menus_scale_is_uniform_and_keeps_each_buttons_authored_aspect()` | It compared a button's size with its own global size; `test_every_menu_control_draws_at_the_ui_size_inside_the_window_and_none_overlaps` pins the drawn scale on both axes |
| `HudContainer` | `_size_the_preview_for_the_top_viewer()`; `TestSidebar.test_a_stuck_possible_card_comes_back_at_the_resized_preview_size()` | Every viewer that stacks over another is on the sidebar's layer at one scale, so a lock handed back never needs a new size; the row compared a constant with itself |
| `DeckViewer` | `_on_flow_container_hidden()` and its `hidden` connection | Only the overlay fade ever hid a deck's list, and hiding must not empty it: a viewer is emptied by closing |
| `HudContainer` | `window_scale(picture)`, `host_viewer()`'s `picture` parameter, `_HostedViewer.picture`; `CardsViewer.picture_to_window_scale`; `DeckViewer.fit_beside()`'s and `ChoiceViewer.fit_beside()`'s `window_scale`; `preview_window_px()`'s parameter | Every viewer is on the sidebar's layer at the UI scale: no picture scale is left to carry |
| `DeckPicker` | signal `viewer_opened`, `_inspect()` | The menu opens the viewer on `inspect_pressed`, as every screen opens its own |
| `WallPicture` | `window_scale(window)`; `TestSidebar`'s check that the drawn scale matches it | No caller left: every screen's UI is on the sidebar's layer at the UI scale |
| `HudContainer` | `_wants_container()`'s `showing_description()` half on the menu | Every description the menu shows comes from its hosted viewer |
| `HudContainer` / `DescriptionPanel` | `resize_preview()` | The preview is one UI size whatever the window, so a window change has nothing to re-size |

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
| `map_edge_buffer_fraction` | `float` | `0.03` -- sea shown around each edge of the fitted map |

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
| `ui_focus_next`, `ui_focus_prev` | **EMPTIED** — overridden in `project.godot` with no events, so Tab and Shift+Tab are `wall_overview`'s alone on every screen and the arrows alone move the GUI focus |

## 7. Signals

| Owner | Signal | Node |
|---|---|---|
| `PlayArea` | `card_tapped(data: CardData)` | F8. Nothing listens in v1 but the dummy test effect |
| `PlayArea` | `info_requested(entry: InfoEntry)` | **unchanged name**, now routed to `HudContainer` rather than `Main`'s card |
| `HudContainer` | `description_dismissed` | B10 |
| `PlayArea` | `sidebar_requested` | A left press off the board's own left edge; `GameView` hands it to `HudContainer.focus_sidebar()` |
| `WorldMapController` | `sidebar_requested` | A left press with no node picked; `Map` hands it to `HudContainer.focus_sidebar()` |
| `PlayArea` | `hand_changed(held: bool)` | Added during execution: the hand went from empty to holding or back, emitted by the `selected_cards` setter; `GameView` hands it to `HudContainer.set_card_in_hand()` |

## 8. Test suites

| Path | Class | Covers |
|---|---|---|
| `Tests/Wall/test_sidebar.gd` / `.tscn` | `TestSidebar` | Charts B, C — open, swap, lock, dismiss, processing |
| `Tests/Wall/test_sidebar.gd` | `func test_the_possible_cards_list_every_part_as_an_icon_and_no_card()`, `func test_a_possible_part_is_described_by_its_name_on_a_card_preview()`, `func _check_the_part_described(icon, how)`, `func _carries(card, part) -> bool`, `func _check_icons_at_the_ui_size(viewport, list, where)` | (added during execution) The possible cards as icons: one per part, no card body, one cell, a type shrunk; each described by name over a card preview by mouse, keys and d-pad |
| `Tests/Wall/test_sidebar.gd` | `func test_the_menu_lays_out_for_the_window_after_every_resize()`, `func _check_the_menu_centred_in_the_window(host, main, what)` | Test support (added during execution): the bare menu resized 1280x720 <-> 600x1000 in both orders, in the harness and the player's window, keeps its column centred in the whole picture and inside the window |
| `Tests/Wall/test_sidebar.gd` | `func test_a_resize_round_trip_shrinks_the_overlay_row_back()` | Test support (added during execution): in the player's window, 1280x720 -> 600x1000 -> 1280x720 returns every overlay button, the band's bottom and the sidebar's top margin to their fresh-boot values |
| `Tests/Wall/test_sidebar.gd` | `func test_the_menus_buttons_stack_wherever_the_whole_column_fits_beside_the_sidebar()`, `func test_a_resize_between_the_window_shapes_stacks_the_menu_and_unstacks_it()`, `func test_keys_and_the_d_pad_walk_the_stacked_menu_in_order()`, `const _MENU_STACKS_AT`, `func _check_the_menus_layout(host, main, stacked, submenu_open, what)`, `func _check_the_bottom_rows_lines(host, main, what)`, `func _check_the_walk(host, main, device, stack, what)`, `func _menu_controls_in_window(host, main)`, `func _menu_row_lines(host, main, row)`, `func _await_the_menu_laid_out(main)`, `func _press_on(host, device, key, button)` | Test support (added during execution): in the player's window the menu's buttons stack into one centred column where the whole column, the Play submenu open, fits beside the resting sidebar (600x1000) and keep their rows where it does not (1000x1000, 1000x800, 1280x720), unchanged by Play, the picker's slide; a resize switches both ways; keys and the d-pad walk the stack in order past a disabled Continue, Left and Right moving nothing |
| `Tests/Wall/test_sidebar.gd` | `func test_every_rules_viewer_card_draws_a_card_face()` | Test support (added during execution): every card the Rules viewer lists draws its type face, the grid creator's typeless card `CardVisual.BLANK_CARD_FRAME` |
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
| `MAP_CLOSE_DECK` | (added during execution) The map's Deck opener while the run deck it opened is up |
| `GAME_CLOSE_DECK` / `GAME_CLOSE_DISCARD` / `GAME_CLOSE_RULES` | (added during execution) The game's pile openers while their own viewer is up |
| `GAME_UNDO` | The outcome screen's own Undo, beside Continue (J13, `GAP-009`=b) |
| `TYPE_PAPER` / `TYPE_PAPER_DESCRIPTION` | (added during execution) `TypePaper`'s name and description: PLACEHOLDERS, read only by its possible-cards icon (see `RANK_DESCRIPTION`) |
| `RANK_DESCRIPTION` | (added during execution) `PipRank.get_description`: a PLACEHOLDER line (owner: "you can write them with placeholders"); the CSV has no placeholder marker and its third column must stay empty, so this row is the record |
| `PART_KIND_TYPE` / `PART_KIND_SKILL` / `PART_KIND_STAMP` / `PART_KIND_SUIT` / `PART_KIND_RANK` | (added during execution) The possible-cards list's group headers: Card Type, Talent, Stamp, Suit, Rank (`PartIcon.KINDS`) |

⚠ **Leave a new row's third column EMPTY.** Godot's CSV importer reads it as the message CONTEXT, so
a row that fills it is unreachable through `TRANSLATION.find` and the label renders as its own key.

⚠ **Every user-facing string goes through `TRANSLATION.find` and this CSV — never a literal.**
Project rule 4.

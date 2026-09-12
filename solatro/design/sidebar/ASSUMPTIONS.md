# ASSUMPTIONS.md — reversible decisions taken while executing PLAN.md

- `HudContainer`'s children are authored in `hud_container.tscn`, so `HudContainer.new()` yields a
  bare `PanelContainer` with no children. `TestSidebar` instantiates `hud_container.tscn` instead,
  still with no `Main` and no wall in the tree (C1, Q150).
- `Main.enter_game()` hands its wall's own `HudContainer` to `GameView.hud_container` before
  attaching the view, so `_bind_hud_container()` binds to exactly that wall's container. A
  standalone fixture with no `Main` leaves it null and gets a private `HudContainer` as its own
  child instead -- same scene, same accessors, freed with the view like everything else it owns.
- TEST_PLAN 3.4 expected the board's centre to MOVE when `%MultScore`/`%Preview` were deleted. It
  cannot: the inset was `_hud_authored_width() * hud_scale()`, which is `0.25 * 1576` = 394 whatever
  the widest control. Measured pre-deletion centre 733.808; 3.4 asserts it is unchanged (C4, L9).
- `HudContainer.set_active_screen(screen: StringName)` is a new method NAMES.md does not list: it
  takes `Main`'s own focus id (`&"game"`, `&"map"`, `&"start_menu"`, `&""`) rather than inventing a
  second enum, since that id is already the one thing every call site has in hand (C13, Q83).
- D11/`Q247`=a's "no conversion" is read literally for the map: `WorldMapController.container_inset`
  is handed `container_px` in window px with no `picture_scale` division, but Camera2D.offset shifts
  the whole view rather than reserving a margin, so it is applied at half that value to land the
  look point on the centre of the space actually left over beside the container.
- The menu's own inset (Q22=b, Q27) scales and centres the WHOLE menu (title and buttons alike) in
  the space beside `container_rect()`, uniformly (one factor on both axes, never distorting a
  glyph) and only once its own authored content bounds -- title, buttons and the run row union'd,
  not the window's empty margin around them -- would not otherwise fit there.
- `Menu.hud_container` falls back to a private instance when null, the same shape `GameView`/`Map`
  already use -- `Tools/wall_editor.gd`'s preview hosts a real `menu.tscn` with no `Main` in the tree.

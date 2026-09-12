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
- GAP-003 corrects D11/`Q247`=a: the map DOES sit in a picture, so `Map._publish_map_inset()`
  converts the container's window px through `WallPicture.local_rect_beside()`, the same conversion
  `Menu` uses, into the shift from screen centre to the space left over beside the container.
  `Camera2D.offset` is a world offset the engine multiplies by `zoom` before it reaches the screen
  (`Camera2D::get_camera_transform()`), so `WorldMapController` divides the shift by its own zoom
  and re-applies it on every zoom change, not only when the container moves.
- The menu's own inset (Q22=b, Q27) scales and centres the WHOLE menu (title and buttons alike) in
  the space beside `container_rect()`, uniformly (one factor on both axes, never distorting a
  glyph) and only once its own authored content bounds -- title, buttons and the run row union'd,
  not the window's empty margin around them -- would not otherwise fit there.
- `Menu.hud_container` falls back to a private instance when null, the same shape `GameView`/`Map`
  already use -- `Tools/wall_editor.gd`'s preview hosts a real `menu.tscn` with no `Main` in the tree.
- The menu's inset conversion (review finding 2) reuses `GameView`'s own UNMARGINED `picture_scale`
  shape rather than the live camera transform: `Menu._apply_container_inset()` runs mid-`WallPicture.
  build()`, before `Main` positions the focused camera, so a transform read off the screen sprite at
  that point is still the unfocused identity. `WallPicture.local_rect_beside()` is the one owned
  conversion (window px beside `container_rect()` -> this picture's own space), called by `Menu` and
  by the SIDEBAR suite's own menu geometry tests.
- `board_inset_left`/`board_inset_top` divide by the UNMARGINED `picture_scale` (`max(window/1576,
  window/887)`), not `WallPicture.focused_scale()` (which adds `wall_overfill_margin` when the two
  axis ratios differ). Measured at 1280x720 (side case, container 320 window px wide):
  `picture_scale` 0.812183 gives `board_inset_left` 394.0 picture px (the gate); the live camera's
  `focused_scale` 0.828427 puts the rendered board edge 6.4 window px right of the container's own
  edge -- a gap, never an overlap, so the 394/262.7 gates stay on `picture_scale`.

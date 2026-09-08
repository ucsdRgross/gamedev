# PICTURE_WALL.md — the wall shell, as it is now

**Read this before changing anything under `UI/Wall/`, `Scripts/Wall/`, or `Levels/main.gd`.**
`design/picture-wall/DESIGN.md` is the authority on *what the wall should do* and is cited by
question id (`Q56`, `J1`, `G10`) from code all over this subsystem. This file is the authority on
*how it is put together* and what will bite you.

⚠ **THE GAME PICTURE IS SEVERAL SCREENS WIDE NOW, AND THE CAMERA PANS OVER IT.** A show is
played on one to three grids side by side, so the game picture's resting pose stopped being one
pose and became a **family** of them — one per grid. Everything in this file that talks about
"the focused picture" still holds; what changed is that the focused game picture also has a
horizontal position within itself, and that position is state the wall owns.

| Concept | Where it lives |
|---|---|
| The pan offset, in picture pixels | `WallPicture.saved_pan_x` — written at the step, read for every resting pose, re-snapped on a resize, and restored into the board BEFORE re-focusing |
| The rest pose at one grid | `WallPicture.grid_state()` — `resting_state()` evaluated at one of the pan's discrete target values |
| Snapping a free pan back onto a grid | `WallPicture.snap_pan_to_grid()` — pure |
| The board asking for a pan | `PlayArea.overview_pan_requested` → `GameView` → `Main`; the board lives inside the view's own `SubViewport` and has no reach to the camera outside it |
| A pan past the first or last grid | `PlayArea.overview_bounce_requested`, carrying the direction, so `Main` can push the camera and spring it back |
| The render-target ceiling | `settings().game_picture_max_render_px` (ships 4096) — a wide picture's `SubViewport.size` is clamped to it |

⚠ **THE HORIZONTAL AIM IS DEAD RANGE IN THE OVERVIEW.** The board container is picture-wide
there, so the CAMERA is the single horizontal authority — the board publishes the intent and
must not also try to scroll itself, or the two fight.

## The map

| File | Owns |
|---|---|
| `Levels/main.gd` (`Main`) | **The orchestrator.** Focus, transitions, the `FocusStack`, every wall↔screen connection. Nothing else decides what a wall intent *means*. |
| `UI/Wall/wall.gd` (`Wall`) | The camera, the pictures, input reading, selection. Announces player INTENT as signals; never resolves it. |
| `UI/Wall/wall_picture.gd` | One picture: its SubViewport, frame, shadow, focus/unfocus, filter, `get_info()`. |
| `UI/Wall/wall_overlay.gd` | Back / Forward / Wall / Info controls, and the touch-target clamp. |
| `UI/Wall/info_card.gd` | The ONE info card, on the overlay. Anchored to the window, not to any screen. |
| `Scripts/Wall/wall_packer.gd` | Pure layout. No singletons, no nodes — keep it that way (§1.3). |
| `Scripts/Wall/wall_transition.gd` | The camera tween and its clock. Pure `sample_at()` core plus a thin `_apply()`. |
| `Scripts/Wall/focus_stack.gd` | Back/Forward history, ids only. Never positions. |
| `Assets/Wall/layout_default.tres` | The authored layout the game LOADS. `Tools/wall_editor.tscn` edits this same file. |

## ⚠ The wiring contract — the thing this subsystem gets wrong

The wall's whole failure history is one shape: **a component built, unit-tested, and never
called.** A green suite does not detect it. Every row below is a call site that must keep
existing; if you delete one, the feature silently stops existing and its unit tests stay green.

| This must be called | From | Or else |
|---|---|---|
| `WallTransition.retarget()` | `Main._on_window_resized()` | resize/fullscreen leaves the wall packed for the old aspect |
| `Main._on_window_resized()` | `get_viewport().size_changed`, connected in `Main._ready()` | as above — nothing else listens |
| `Wall.clamp_pan()` | `Wall.pan_by()`, from the drag branch of `_unhandled_input()` | free pan (G10) does not exist |
| `WallPicture.update_filter()` | `Wall._process()` | the focused picture samples NEAREST through every zoom (S13 dead) |
| `WallInput.touch_target_px()` | `WallOverlay._apply_touch_targets()` | GAP-004's mandatory clamp never runs |
| `WallPicture.get_info()` | `Main._on_picture_hovered()` | info mode on the wall describes nothing |
| `Wall.back_requested` etc. | connected in `Main._ready()` | the key/button does nothing at all |
| `WallTransition.input_unlocked` | connected to `wall.unlock_input` in `Main._focus_picture()` | input stays locked until landing, defeating C13 |
| `Map.info_hovered` | connected in `Main._ready()` | the map's hover reaches no card |
| `Wall.apply_layout()` | `Main._build_pictures()` **and** `_repack_wall()`/`_on_window_resized()` | `_placement_order` stays empty, so all nine `wall_jump_N` keys are inert until something else happens to re-pack |

**Every overlay control is `FOCUS_NONE`.** A `Control` holding GUI focus eats `ui_up/down/left/right`
and `ui_accept` before `_unhandled_input` runs, so one mouse click on an overlay button used to kill
wall-view arrow selection and Enter-to-enter for the rest of the session. They are mouse/touch
affordances; each also has its own `wall_*` action for the keyboard.

**Every `wall_*` InputMap action needs BOTH a reader and a binding.** `wall_back`/`wall_forward`
shipped with readers missing *and* empty event lists. `TestWallInput` asserts both halves.

**A knob nothing reads is a defect.** Either wire it or strike it from `PlayerSettings` *and*
`DESIGN.md` §5 — see `ASSUMPTIONS.md`'s M9 entry for three that were struck and why.

## Landmines

- **`Main` decides, `Wall` announces.** `Wall` holds no `FocusStack` and must not grow one. Back is
  `back_requested`, not "go to wall view" — only the stack knows whether Back bottoms out (`Q65`=a).
  `wall_view_entered` means the overview specifically: the Wall button and pinch-in (`Q119`=a).
- **Never detect a timed geometric event by sampling frames.** Both latches that do this —
  `_source_pause_time` and `_input_unlock_time` — precompute the crossing analytically from the pure
  `sample_at()`. The windows they look for OPEN AND CLOSE mid-transition (a focused picture overfills
  at rest, so its frame is off-screen by construction), and a sparse frame steps straight over them.
  Both were per-frame checks once; both were wrong.
- **A focused picture overfills the window** (`Q27`/H3), so its frame is off-screen at rest. Any test
  asserting "the frame is visible" is asserting something only true mid-transition.
- **`focused_scale()` applies its margin only when the aspects DIFFER.** That conditionality is what
  makes G10's "panning is off when everything fits" an exact zero rather than a few per cent of
  slack. Do not make it unconditional.
- **Constructing a `Main` CLEARS the shared `wall_info_mode`** (C3, its own startup rule). Every
  concurrently-running suite sees that, so a test that builds one while another suite is mid-await
  on that flag will fail the OTHER suite. Preserve and restore it around any `Main` a suite builds
  for some unrelated reason.
- **A live `Main` puts a real `Map` in the tree, and `Map` is a `CardEnvironment`,** so
  `CardEnvironment.CURRENT` is non-null for as long as it lives. Any test holding one is visible to
  every concurrently-running suite.
- **`Camera2D.zoom` here is DIRECT MAGNIFICATION**: the visible span is `window_size / zoom`.
- ⚠ **THE WALL IS THE ONLY THING THAT CLIPS. THE BOARD INSIDE IT DOES NOT.** The wall clips the
  picture to the window, and that is the whole of it: `PlayArea` sets
  `scroll_container.clip_contents = false` and GRID VIEW asserts that nothing between the card
  layer and the `PlayArea` clips either. **Hiding a non-focused grid is the CAMERA's job and only
  the camera's** — props and animations are authored to leave the board's edges, and a clip there
  culls them. So a grid that is off-window is off-CAMERA, not culled, and a card flying between
  grids is never cut.
- ⚠ **The HUD follows the camera, and that is a decision, not an accident.** `GameView`
  publishes the HUD's width to `PlayArea.board_inset_left` and the board centres in what is
  LEFT of the screen, not on the screen. **The board's WINDOW is what moves, not the content** —
  insetting the scroller's own left edge makes every centring the board already does (the focused
  aim, the resting position, the removal re-centre) land in the post-HUD space for free.
  Offsetting the content instead leaves each of those to rediscover the inset separately.
- **Gate on a PROPERTY, never on object identity.** The game loads `layout_default.tres` (C6), and a
  resource deserialises to a DIFFERENT instance than the one code generates — so
  `entry.frame_texture == shared_frame_texture()` was never true in the product while every fixture
  that assigns the shared texture directly kept passing. `WallPicture._frame_corner_px()` asks the
  texture how big it is instead.
- **The one-move flag goes on the HANDLER that mutates, not only on the mover.** `FocusStack.back()`
  and `forward()` change history BEFORE `_focus_picture()`/`_go_to_wall_view()` reach their own
  `if _move_in_flight: return`, so a second press popped an entry and then refused to navigate to
  it. `Q56`=b means IGNORED, not half-applied. The Info toggle is a move too and holds the same flag.
- **In wall view the stack's top is still the picture you LEFT** (`Q66`=b: wall view is never an
  entry), so `_current_focus` and `FocusStack` disagree there by construction. Back reads
  `current()`, not `back()`, or it steps past that picture and files it under Forward
  (GAP-020=a) — and `WallOverlay.refresh()` needs `in_wall_view` for the same reason, or the button
  and the key diverge.
- **`Pacing.wait()` takes the WAITING NODE.** A `SceneTreeTimer` has no node binding, so under
  §1.6's permanent pause `process_always = false` means "never fires", in any screen. The `Timer`
  child obeys its host's process mode, which is what makes a frozen screen's pacing freeze and a
  live screen's run (D6/`Q75`=b).
- **A move keeps the settings it was REQUESTED with.** `sample_at()` branches on
  `wall_reduced_motion`/`wall_info_mode` and the tween callback re-reads them every frame, so
  `request()` holds a `duplicate()`. Flipping a knob mid-move otherwise switches the camera's whole
  model underneath the running tween.
- **`%Screen` and `%Shadow` draw `viewport.size * scale`, not `design_size * scale`.** Their texture
  IS the picture's `SubViewport` render target, and `ViewportTexture.get_size()` is always
  `viewport.size` — which GAP-002 rewrites to the wall-view footprint on every `unfocus()` and every
  resize. Any scale computed against `_design_size` collapses the picture the moment it is
  unfocused. `WallPicture._rescale_screen()` is the one place that arithmetic lives; call it
  wherever `rect` or `viewport.size` moves.
- **The wall pauses the whole tree at construction and never clears it** (§1.6), so the shipped
  game runs entirely under `get_tree().paused == true`. A `Tween` bound to a PAUSABLE node never
  advances there, and `await tween.finished` never returns: that is how a total soft-lock on the
  first Wall press shipped with a green suite. Any tween driving the wall goes on `%Camera2D`
  (PROCESS_MODE_ALWAYS), never on `Main`, which has no `process_mode`.
- ⚠ **A test that unpauses cannot see any of that.** Most Wall-building suites do set
  `get_tree().paused = false` right after `add_child()`, and must — they run alongside ~38 others
  that need frames. But that workaround is a blind spot, not a rule: it is why the soft-lock,
  `Pacing.wait()` and reduced motion's resting zoom all stayed invisible. **Anything asserting the
  PAUSE MODEL itself belongs in `TestWallPause`**, the one suite that runs dead last and alone and
  leaves the tree paused — and it must drive each move without `await`, polling `process_frame`
  under a bounded escape, so a move that never returns fails a check instead of hanging the run
  with no banner.

## Tuning it — `Tools/wall_editor.tscn`

**Every wall number is an editable field here, not a constant.** Open the scene and edit the
`WallEditor` root in the Inspector; the wall re-packs on every change. There is no custom UI — the
Inspector already gives arrays, undo and nested resources.

| Panel | What it holds |
|---|---|
| `layout` | `gap_px`, the ellipse clamps, `view_margin`, `home_id`, and every `PictureEntry`: `slot` (placement ORDER — the packer resolves the angles), `size_multiplier`, `design_size`, `frame_px`, `frame_colour`, `keep_aspect`, `music`, `background_texture`. |
| `preview_settings` | A standalone `PlayerSettings`. Transition duration and phase fractions, easing curves, overfill margin, shadow offset/opacity, info-card size, reveal scale, touch targets. |
| `preview_aspect` | 0.5–4.0, re-packs live. The clamps only do something at the extremes. |
| `unlocked_ids` | Seeded with EVERY id. Delete some to simulate a partial unlock. |
| Transition preview | `preview_source_id`/`preview_dest_id` are seeded with the longest move on the wall; `play_transition` runs the real `WallTransition`. |
| Focus | `preview_focus_id` focuses that picture through the real `WallPicture.focus()` and poses the camera at its resting pose — the state a player is in most of the time, and the only place a too-small `wall_overfill_margin` shows as a sliver of frame at a window edge. `&""` is wall view. `preview_selected_id` drives the real `set_selected()`, so `wall_selected_lift` is visible. `preview_wall_view_resolution` renders unfocused pictures at their wall-view footprint, as the game does. |
| Gestures | `preview_pinch` routes real touch through the real `WallInput.PinchTracker`, so `wall_pinch_threshold_px` is tunable against actual fingers. Needs a touch device or `emulate_mouse_from_touch` off; `gesture_log` shows what the tracker saw. |
| Info mode | PER PICTURE — each screen remembers whether it is on, and the card it was showing. `preview_info_mode` ANIMATES the camera to `preview_info_id`'s info pose (bottom frame revealed, the other three edges covered) and shows the real `InfoCard`. The ONLY way to reach `wall_info_mode` from an Inspector — it is not `@export`ed on `PlayerSettings`, being session state that must never persist. With it on, `play_transition` previews the INFO transition: a pure travel at constant zoom. |
| Overlay | The REAL overlay from the hosted `wall.tscn`, with its info card. Back / Forward / Wall / Info are **pressable** and drive real moves through a real `FocusStack`, so the overlay and a running transition contend the way they do in the game. `_apply_touch_targets()` runs, so the touch-target knobs are live. |
| Save | `save_now` writes `Assets/Wall/layout_default.tres` — the resource the game boots from. `revert_now` reloads it. `preview_settings` is NOT saved. |

`save_now` / `revert_now` / `play_transition` are booleans acting as BUTTONS: they run on the rising
edge and reset themselves.

⚠ **PREVIEW vs F6 differ, deliberately.** In the Inspector the tool draws empty frames, builds no
`InfoCard`, and the camera does not follow — the editor's 2D view is the user's own; `menu.tscn` /
`map.tscn` are not safe to instantiate there; and `InfoCard` is not `@tool`, so it would load as a
placeholder and throw on any call. **Run it (F6) for real screens, the info card, and transitions.**
Geometry, framing, packing and the info camera POSE are live in both.

⚠ **Info mode ANIMATES, over `wall_transition_delay * wall_info_zoom_scale`.** It is not a snap in
the game and must not be one here — a tool whose timing differs from the product cannot be used to
judge timing. `wall_info_zoom_scale` defaults to 1.0, i.e. exactly an ordinary wall move; drop it
below 1.0 for a snappier reveal, since the info pose only shifts the camera a little way down.

`Tests/Visual/wall_editor_soak.tscn` drives the tool through aspects 0.5–4.0, `gap_px` 0 and 200,
overfill 1.0 and 1.25, one/two/all pictures, reduced motion, the info animation, and every overlay
button including a press landing mid-move — 55 checks plus a screenshot per case. Run it after
touching the tool.

⚠ **RUN (F6), THE TOOL HOSTS THE REAL `wall.tscn`** — surface, camera, pictures, viewports,
overlay, info card and both music players. Not a stand-in and not a re-derivation: the wall's own
input runs, so arrow selection with its held repeat, click-to-enter, `wall_jump_N`, pinch and the
Back/Forward/Wall/Info actions all reach the preview, and every knob goes through the same code the
game runs it through. **`knobs_this_preview_does_not_drive` is empty when run.**

⚠ **The global pause is KEPT.** `Wall._ready()` pauses the whole tree and the tool leaves it
paused, because that is what freezes an unfocused screen in the real game. `WallEditor` is
`PROCESS_MODE_ALWAYS`, as `Wall`, `%Camera2D` and `%Overlay` already are in `wall.tscn`.

⚠ **The EDITOR preview keeps the hand-built scaffold**, because `Wall` is not `@tool` and would
load as a placeholder. Four knobs are inert there and the tool names them in
`knobs_this_preview_does_not_drive`: `wall_selection_repeat_delay`, `wall_debug_readout`,
`wall_reveal_delay_scale`, `wall_unlock_all`.

⚠ **Every non-focused picture is really `unfocus()`ed, never skipped.** A stale `is_focused` makes
`Wall._focused_picture()` non-null, and both the texture-filter update and the selection repeat bail
whenever anything is focused — silently, with no other symptom.

⚠ **It is NOT in `all_tests.tscn` and never will be.** The suite carries only the two `Tests/Visual`
scenes that assert on pixels (`test_pixels`, `test_outline`); everything else under `Tests/Visual`
is a hand-run diagnostic that renders, screenshots and prints. That is why the wall-editor runs look
different from a suite run — they are a different kind of instrument.

⚠ **Info mode covers NOTHING.** The camera zooms out — it never pans, which would crop the top of
the screen — far enough that the whole screen clears the info card, bar `wall_info_card_overlap`.
The reserve is the card's LIVE height, not `wall_info_card_max_height`; that cap is only the
fallback for callers with no card on screen. Every mover aims at `WallPicture.resting_state()`,
which is info-aware, so a move made in Info mode LANDS in the info pose instead of being cut there.

⚠ **A visual inside the info card is a real game node made inert.** `InfoCard._make_inert()` strips
`focus_mode` and `mouse_filter` recursively as the card takes ownership, so a preview cannot take
focus or swallow a click. It cannot mutate what it shows either: `CardVisual` never writes to its
`CardData`. Keep that guarantee at the ONE site — a per-builder rule would have to be remembered
every time a new `get_info()` is written.

⚠ **Wall view is framed with `layout.view_margin`, exactly as `Wall.wall_view_zoom()` frames it —
NOT with `wall_overfill_margin`, which is a picture's own overfill when focused.** Using the picture
knob here framed the preview ~4% tighter than the game and made `view_margin` do nothing, which
would have made this tool useless for the one composition call it exists to support.

⚠ **The tool assigns `WallPicture.editor_settings`, and that override wins PREVIEWED OR PLAYED.**
Making it editor-only is the bug `LightLayer` already paid for: a played tool scene would read the
player's `settings.tres` while the panel showed its own resource. `_exit_tree()` restores whatever
was there before, and nothing here writes `user://settings.tres`.

## The contracts the reviews established

⚠ **Code does NOT cite these ids** — a comment states the rule and the design docs keep the
provenance (`.claude/memory/design-ids-stay-out-of-code.md`). This table is the index from a review
id to the contract it produced, for anyone reading the review documents.

| Id | The contract it pins |
|---|---|
| A1–A4 | The info card lives on the wall; the Info button has a consumer; `PinchTracker` is wired; `NAMES.md`'s `Wall` signals are declared and emitted. |
| B1–B2 | `WallPacker` rejects intersection independently of `gap_px`; the selected lift is a knob, not a literal. |
| C1 | Alt-tab re-renders every FROZEN picture — never the focused one, which must stay `UPDATE_ALWAYS`. |
| C2 | Reduced motion cross-fades IN PLACE (no camera move at all, GAP-019=c) and still ARRIVES at the destination — by a cut on landing, not by travel. |
| C3 | Info mode never survives a quit. |
| C4 | `wall_jump_N` enters through the same path a click does, in placement order. |
| C5 | One move at a time (`Q56`=b); input is inert mid-move and unlocks early (I12/C13). |
| C6 | The game loads the layout the tool edits. |
| M1–M9 | The wiring contract above, row by row. |

## Open

Tracked in [todo.md](todo.md) under "Picture wall", with the stream's state in
[HANDOFF_picture_wall.md](HANDOFF_picture_wall.md). Every gap in `design/picture-wall/gaps/` is
answered. What is left is the playtest, what unlocks `book`, and the two composition calls — all
three of them owner calls, and the composition ones are now judgeable live in the tool above.

⚠ **Two gaps from the GRID side reach into this file and are NOT closed:**

- **`design/poker-patience/gaps/GAP-038`** — answered `(d)` and **NOT BUILT**. The whole
  HUD-scales-with-the-picture pass is parked on it.
- **`design/poker-patience/gaps/GAP-039`** — the focused fit's isolation derivation is short by
  35 px of 510, and the 35 is a FONT metric (the panel's column-label gutter, 27) plus a THEME one
  (the scroller's reserved horizontal band, 8). `game_picture_design_size()` runs before any board
  exists to measure either. ⚠ **DO NOT CLOSE IT BY DELETING THE TWO TERMS FROM THE LIVE FIT.**
  The gutter is real content and the band is really reserved; dropping them makes the model agree
  by letting the board overflow its window, and the board is bottom-anchored, so the overflow goes
  off the TOP and the top row clips again — which is the bug that stream started on.

⚠ **The wall currently RENDERS WRONG in the running game** — the map sits outside its frame and
is unclickable. Known, reported by the owner, and owned by the wall stream rather than by any doc
pass.

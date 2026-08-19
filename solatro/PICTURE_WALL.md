# PICTURE_WALL.md — the wall shell, as it is now

**Read this before changing anything under `UI/Wall/`, `Scripts/Wall/`, or `Levels/main.gd`.**
`design/picture-wall/DESIGN.md` is the authority on *what the wall should do* and is cited by
question id (`Q56`, `J1`, `G10`) from code all over this subsystem. This file is the authority on
*how it is put together* and what will bite you.

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
- **A live `Main` puts a real `Map` in the tree, and `Map` is a `CardEnvironment`,** so
  `CardEnvironment.CURRENT` is non-null for as long as it lives. Any test holding one is visible to
  every concurrently-running suite.
- **`Camera2D.zoom` here is DIRECT MAGNIFICATION**: the visible span is `window_size / zoom`.
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

## Defect ids cited from code

Code comments across this subsystem cite ids from the two reviews this run produced. Each id names a
contract, not an incident — the id is what the comment is pointing at:

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

Tracked in [todo.md](todo.md) under "Picture wall". `GAP-018` (is `WallLayout.view_margin` extra crop
or vestigial?) and `GAP-019` (what the camera does during a reduced-motion cross-fade) are open and
owner-facing; every other gap in `design/picture-wall/gaps/` is answered.

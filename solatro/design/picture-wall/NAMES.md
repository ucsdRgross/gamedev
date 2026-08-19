# NAMES.md — the identifier registry for the picture-wall shell

**Every name is fixed here before anyone types it.** Use these exactly: do not rename, do not
shorten, do not "improve". A name that is wrong is a gap, not a judgement call — file it.

If you need a name that is not in this table, **that is a plan defect**: file a gap rather than
inventing one. Two sessions inventing two names for one thing is the most common way work that both
"succeeded" fails to compose.

## Scripts — pure logic (`solatro/Scripts/Wall/`)

| Path | `class_name` | Extends | Role |
|---|---|---|---|
| `Scripts/Wall/wall_layout.gd` | `WallLayout` | `Resource` | the authored PATTERN — gap, ellipse clamps, the picture list (rings rejected, GAP-009) |
| `Scripts/Wall/picture_entry.gd` | `PictureEntry` | `Resource` | one picture's authored data — id, scene, slot, size multiplier, frame thickness/colour, music, background |
| `Scripts/Wall/wall_packer.gd` | `WallPacker` | `RefCounted` | the pure packer: layout + unlocked ids + window aspect → rects |
| `Scripts/Wall/picture_rect.gd` | `PictureRect` | `RefCounted` | one packed result — id, centre, size, frame insets |
| `Scripts/Wall/focus_stack.gd` | `FocusStack` | `RefCounted` | the Back/Forward history, ids only |
| `Scripts/Wall/info_entry.gd` | `InfoEntry` | `RefCounted` | what `get_info()` returns — title, body, optional visual |

## Scripts — project-level

| Path | `class_name` | Notes |
|---|---|---|
| `Scripts/profile_manager.gd` | `ProfileManagerClass` | **autoload `ProfileManager`** — mirrors `RunManagerClass`/`RunManager` |
| `Scripts/player_profile.gd` | `PlayerProfile` | `Resource`, saved to `user://profile.tres` |
| `Scripts/pacing.gd` | `Pacing` | the pause-safe timer helper — **not** wall-specific |

## Scenes and view nodes (`solatro/UI/Wall/`)

| Path | `class_name` | Extends | Role |
|---|---|---|---|
| `UI/Wall/wall.tscn` / `wall.gd` | `Wall` | `Node2D` | the shell root — owns the camera, the pictures, the overlay |
| `UI/Wall/wall_picture.tscn` / `wall_picture.gd` | `WallPicture` | `Node2D` | one picture: frame + screen sprite + its `SubViewport` |
| ~~`UI/Wall/wall_frame.gd`~~ | ~~`WallFrame`~~ | — | **RETIRED, never built.** This row's own description — *"a `NinePatchRect`, not a system"* — says it needs no behavioural script, and S24 ships every frame requirement without one. Kept struck rather than deleted so the name is not reused for something else. |
| `UI/Wall/wall_overlay.tscn` / `wall_overlay.gd` | `WallOverlay` | `CanvasLayer` | Back / Forward / Wall / Info controls |
| `UI/Wall/info_card.tscn` / `info_card.gd` | `InfoCard` | `Control` | the self-sizing notecard |
| `Scripts/Wall/wall_input.gd` | `WallInput` | `RefCounted` | event routing: wall-space hit test, `make_input_local`, `push_input` |
| `Scripts/Wall/wall_transition.gd` | `WallTransition` | `RefCounted` | the camera tween and its phase clock |

## Node names inside `wall.tscn` (a `%unique` lookup depends on these)

`%Camera2D` · `%Pictures` (Node2D, parent of every `WallPicture`) · `%Viewports` (Node, parent of
every `SubViewport`) · `%Overlay` · `%WallSurface` (ColorRect) · `%Overlay/InfoCard` (`InfoCard`,
CODE_REVIEW.md A1 — mounted inside `%Overlay` so it draws on top of the wall like the rest of the
overlay's own controls) · `%MusicA` / `%MusicB` (AudioStreamPlayer, S33)

Inside `wall_picture.tscn`: `%Frame` (NinePatchRect) · `%Screen` (Sprite2D) · `%Shadow` (Sprite2D)

## Signals

| Emitter | Signal | Payload |
|---|---|---|
| `Wall` | `focus_changed` | `(picture_id: StringName)` |
| `Wall` | `transition_started` | `(from_id: StringName, to_id: StringName)` |
| `Wall` | `transition_landed` | `(picture_id: StringName)` |
| `Wall` | `wall_view_entered` | — |
| `Wall` | `back_requested` | — |
| `Wall` | `forward_requested` | — |
| `Wall` | `info_toggle_requested` | — |
| `Wall` | `picture_enter_requested` | `(id: StringName)` |
| `Wall` | `picture_hovered` | `(picture_id: StringName)` |
| `ProfileManager` | `picture_unlocked` | `(picture_id: StringName)` |
| `InfoCard` | `info_shown` | `(entry: InfoEntry)` |
| `Map` | `info_hovered` | `(entry: InfoEntry)` |

## Picture ids (`StringName`, and the key for every derived name)

`&"start_menu"` · `&"map"` · `&"game"` · `&"deck"` · `&"settings"` · `&"book"`

⚠ `&"book"` is **registered but has no scene in v1** (`Q214`=a). `&"settings"` is registered and its
contents are out of scope (`Q212`, §3d item 5).

## InputMap actions (all new, all rebindable — `Q102`=a)

| Action | Default binding |
|---|---|
| `wall_overview` | `Tab`; controller Select/View button |
| `wall_back` | controller shoulder button (L1/LB). ⚠ **Keyboard Back is `ui_cancel`**, with the focused screen taking first refusal (`Q100`=a) — it is not bound here |
| `wall_forward` | controller shoulder button (R1/RB); no keyboard default |
| `wall_info` | `I`; controller d-pad up is NOT used — on-screen button only for mouse/touch |
| `wall_jump_1` … `wall_jump_9` | number keys `1`–`9` (`Q104`=a) |

## Settings keys (`PlayerSettings`, group "Picture wall")

Exactly the rows in `DESIGN.md` §5. Do not add, rename or re-default any of them.

## Localisation keys (`Locale/localization.csv`)

`WALL_BACK` · `WALL_FORWARD` · `WALL_OVERVIEW` · `WALL_INFO` · and per picture
`PICTURE_<ID>_NAME` / `PICTURE_<ID>_DESC` with `<ID>` upper-cased, e.g. `PICTURE_MAP_NAME`.

## Files on disk

| Path | Written by | Format |
|---|---|---|
| `user://profile.tres` | `ProfileManager` | `PlayerProfile` via `ResourceSaver` |
| `res://Assets/Wall/layout_default.tres` | the layout tool | `WallLayout` |

## Test suites

| Suite node in `all_tests.tscn` | Script | `suite_name()` |
|---|---|---|
| `TestWallPacker` | `Tests/Wall/test_wall_packer.gd` | `"WALL PACKER"` |
| `TestWallFocus` | `Tests/Wall/test_wall_focus.gd` | `"WALL FOCUS"` |
| `TestWallProfile` | `Tests/Wall/test_wall_profile.gd` | `"WALL PROFILE"` |
| `TestWallPause` | `Tests/Wall/test_wall_pause.gd` | `"WALL PAUSE"` |
| `TestWallTransition` | `Tests/Wall/test_wall_transition.gd` | `"WALL TRANSITION"` |
| `TestWallInput` | `Tests/Wall/test_wall_input.gd` | `"WALL INPUT"` |
| `TestWallRender` | `Tests/Wall/test_wall_render.gd` | `"WALL RENDER"` |
| `TestWallInfo` | `Tests/Wall/test_wall_info.gd` | `"WALL INFO"` |

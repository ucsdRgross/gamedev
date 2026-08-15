# PLAN.md — implementing the picture-wall shell

**Read this file first; it is self-contained.** `DESIGN.md` is the authority on behaviour — where
they disagree, the design wins and this plan is wrong.

Three documents ship together and you need all three:

- **this file** — the steps and the normative contracts
- **`TEST_PLAN.md`** — every test that must exist, with its fixtures. You may ADD lower-level tests;
  you may **not** decide a planned one is unnecessary
- **`NAMES.md`** — every identifier. Use them exactly

⚠ **You should not have to design anything.** If you find yourself choosing a name, a number, a
file, a test, an order or a shape that none of these three documents fixes, **that is a defect in
this plan**: file a gap and keep working the unaffected steps. Do not "just pick something
sensible" — the decision was already made with more context than you have.

## Design provenance and gap protocol — COPY THIS BLOCK INTO ANYTHING DERIVED FROM THIS DOCUMENT

Derived from: `solatro/design/picture-wall/DESIGN.md`, version 5, charts confirmed by the owner
2026-08-15. Every step below cites the design node IDs it implements.

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

File gaps at `solatro/design/picture-wall/gaps/GAP-NNN.md` using the template in `DESIGN.md`
§7. Write the options in the questionnaire grammar; they become the next round's questions unchanged.

Do not resolve a gap by picking an answer. Do not proceed on the parked thread. Do not delete a gap
— it is closed by a new design version.

This block, unchanged, goes into every document derived from this one.

---

## §0. Repo rules that override anything below

From `solatro/START_HERE.md` and `/CLAUDE.md`. These are not negotiable and this plan does not
restate them elsewhere:

1. **No `git add`, no commits, no staging.** Edit files only.
2. **Warnings are errors** — type every array element and every for-loop variable.
3. **User-facing strings** go through `TRANSLATION.find` + `Locale/localization.csv`. **Tuning knobs**
   go in `Scripts/player_settings.gd` via `SettingsManager.settings`.
4. **The full suite runs WINDOWED**, `GODOT_BIN=<console exe> py solatro/Tools/run_tests.py`. Judge
   by the SUITE count and the failure set, never the check total. Green after every landed step.
5. **`##` purpose comments on every new method.** Delete commented-out code.
6. **Verify visuals by eye.** No green test is evidence about pixels.
7. **`addons/worldgen/` is vendored** — never edited here.

---

## 1. NORMATIVE CONTRACTS — specified, not suggested. Do not invent these.

⚠ **This section is what an executor actually obeys, and it is the section the owner reviews before
you run.** Everything here is a literal.

### 1.1 `PictureEntry` (Resource)

```gdscript
class_name PictureEntry extends Resource
@export var id : StringName = &""              ## NAMES.md picture ids; unique within a WallLayout
@export var scene : PackedScene = null         ## null = registered but unbuilt (&"book", Q214=a)
@export var ring : int = 0                     ## 0 = the home ring
@export var slot : int = 0                     ## authored position within the ring (Q12=a)
@export var size_multiplier : float = 1.0      ## Q16=c, any positive value
@export var design_size : Vector2i = Vector2i(1152, 648)   ## per-screen, Q29=b
@export var frame_px : Vector4 = Vector4(24,24,24,24)      ## L,T,R,B in wall units; Q36, Q37=a
@export var frame_texture : Texture2D = null   ## null = no drawn frame (Q35=c) but geometry stands
@export var unlocked_by_default : bool = false
@export var keep_aspect : bool = false         ## true = never stretched to window aspect (Q32=b)
```

### 1.2 `WallLayout` (Resource)

```gdscript
class_name WallLayout extends Resource
@export var pictures : Array[PictureEntry] = []
@export var home_id : StringName = &"start_menu"     ## Q9=a
@export var gap_px : float = 24.0                    ## between FRAME OUTER EDGES (Q14=a, Q36)
@export var ellipse_aspect_min : float = 1.2         ## Q10=c
@export var ellipse_aspect_max : float = 2.6
@export var view_margin : float = 0.06               ## Q5=b fill, this is the crop bias
```

### 1.3 `WallPacker` — the pure function

```gdscript
class_name WallPacker extends RefCounted
## Deterministic (Q18=a). No randomness, no node access, no engine singletons — so it is
## testable headless (Q197=a). Same inputs, same output, always.
static func pack(layout: WallLayout, unlocked: Array[StringName],
        window_aspect: float) -> Array[PictureRect]
```

Rules, in order:
1. Ellipse aspect = `clamp(window_aspect, layout.ellipse_aspect_min, layout.ellipse_aspect_max)`.
2. Each picture's base size = `design_size * size_multiplier`, then stretched to the window aspect
   **unless** `keep_aspect` (`Q22`=b, `Q32`=b).
3. Ring capacity is **computed**, not authored: fill a ring until the next picture's outer width
   plus `gap_px` would exceed the ring's circumference (`Q11`=b).
4. Within a ring, order by `slot` ascending (`Q12`=a). A partial ring **keeps its authored angles**
   and reads as unfinished — it is NOT spread or compacted (`Q13`=b).
5. Locked ids are absent entirely, not placeholders (`Q158`=a).
6. **Assert no two rects overlap** (`Q20`=a) — `push_error` and return the un-overlapped prefix.

`PictureRect` carries `id`, `centre: Vector2`, `size: Vector2`, `frame_px: Vector4`.

### 1.4 `FocusStack` — Back and Forward

```gdscript
class_name FocusStack extends RefCounted
func visit(id: StringName) -> void   ## Q64: if id is already in the stack, MOVE it to the top
func back() -> StringName            ## &"" when empty → caller goes to wall view (Q65=a)
func forward() -> StringName         ## &"" when there is nothing ahead
func can_back() -> bool
func can_forward() -> bool
```

- Depth is bounded by the number of registered pictures (`Q64`) — never a fixed cap.
- **Wall view is never an entry** (`Q66`=b).
- `visit` clears the forward list, as a browser does.

### 1.5 `PlayerProfile` and `ProfileManager` (Q152, Q151, Q153)

```gdscript
class_name PlayerProfile extends Resource
@export var unlocked : Dictionary[int, Array] = {}   ## slot index -> Array[StringName] (Q151=b)
```

- Path `user://profile.tres`, saved with `ResourceSaver`, loaded with `ResourceLoader.exists` first
  — **the same pattern as `Scripts/settings_manager.gd:19-31`**, not the threaded `RunManager` one.
- `ProfileManager.unlock(id: StringName) -> bool` returns true when it was new; emits
  `picture_unlocked`; saves immediately (`Q153`=a).
- **Slot 0 is the only slot in v1** (`Q213`=a), but the format is keyed by slot from day one.
- `SettingsManager.settings.wall_unlock_all` (debug flag, `Q159`=a) makes `is_unlocked()` return true
  for everything without touching the file.

### 1.6 Pause — the engine's system, nothing hand-rolled

- `get_tree().paused = true` is set **once, at wall construction, and never cleared** (`QR6`=a).
- `Wall`, `%Camera2D` and `WallOverlay` are `PROCESS_MODE_ALWAYS`.
- Every `WallPicture` and every screen root is `PROCESS_MODE_PAUSABLE`.
- **Exactly one screen root is `PROCESS_MODE_ALWAYS` at a time.** Wall view sets zero (`Q74`=a).
- ⚠ **`Pacing.wait()` replaces every `get_tree().create_timer()` in game code** (`Q75`=b):

```gdscript
class_name Pacing
## Pause-respecting timer. SceneTree.create_timer defaults process_always = true, so a bare
## create_timer keeps counting through a pause and a "frozen" screen advances anyway.
## The cast is required: get_main_loop() is typed MainLoop, which has no create_timer.
static func wait(secs: float) -> SceneTreeTimer:
    return (Engine.get_main_loop() as SceneTree).create_timer(secs, false)
```

**S6 sweeps every existing call site.** A bare `create_timer` left in game code is a bug.

### 1.7 The picture — `Sprite2D`, not `SubViewportContainer`

Per **GAP-001**=(b). Per picture:

- a `SubViewport` under `%Viewports`, `size = design_size` (or the wall-view size, §1.8),
  `render_target_update_mode` per §1.8, and ⚠ **`canvas_item_default_texture_filter` set explicitly
  to `NEAREST`** — a `SubViewport` defaults to LINEAR and does **not** inherit the project setting
  (§1c, documented four times in this repo);
- a `Sprite2D` (`%Screen`) whose texture is that viewport's `ViewportTexture`, `centered = true`,
  positioned and scaled from its `PictureRect`;
- `%Frame`, a `NinePatchRect` sized to the rect grown by `frame_px`, drawn **before** `%Screen` so
  the screen is on top (frame entirely outside the picture rect, `Q38`=a);
- `%Shadow`, offset from one authored light position shared by the whole wall (`Q7`=b).

**Filter swap** (`QR7`=c, `Q34`, chart H5): `%Screen.texture_filter` is
`TEXTURE_FILTER_NEAREST` when this picture is focused **and** the camera's zoom did not change this
frame; `TEXTURE_FILTER_LINEAR` otherwise. **Zoom changes only** — pure translation must not flip it.

### 1.8 Render gating

| State | `render_target_update_mode` | `SubViewport.size` |
|---|---|---|
| focused / live | `UPDATE_ALWAYS` | `design_size` |
| any other | `UPDATE_DISABLED` (`Q82`=a — the texture persists) | wall-view size, §below |
| never yet rendered | `UPDATE_ONCE` at wall construction (`Q78`=b) | `design_size` |
| window restored from minimise | `UPDATE_ONCE` for every picture (`Q208`=b) | unchanged |

**Wall-view size** (`Q86`=a, `Q87`=b, GAP-002): `SubViewport.size` is written directly from the
picture's on-screen pixel footprint at wall-view zoom, clamped below by
`settings.wall_view_min_texture_px`. **There is no resolution manager** — it is one property,
written when the footprint changes.

⚠ **No number in this section is a constant.** Every value an author could reasonably argue with is
either a `PlayerSettings` knob (`DESIGN.md` §5) or a field on `WallLayout` / `PictureEntry`, and
**S34's tool exposes all of them live**. If you find yourself typing a literal into a `.gd` file that
is not in one of those three places, stop — that is a gap.

### 1.9 Input routing (Q94, Q100, Q101, Q123, GAP-001, GAP-003, GAP-004)

```gdscript
class_name WallInput extends RefCounted
## Convert a wall-space event to the focused SubViewport's space and hand it over.
## GAP-001=b: SubViewportContainer is documented as distorting when scaled, and the camera
## scales every picture continuously, so the routing is ours.
static func route(event: InputEvent, picture: WallPicture) -> bool
```

- Only the **focused** picture is ever routed to (`Q95`=a).
- The local transform is the `%Screen` sprite's `get_global_transform_with_canvas()` inverse, scaled
  by `SubViewport.size / (sprite.texture.get_size() * sprite.scale)`; hand the result to
  `SubViewport.push_input(local_event, true)`.
- **The wall reads input in `_unhandled_input` only**, so a focused screen always gets first refusal
  (`Q100`=a, and the existing `world_map_controller.gd:217` pattern).
- Bindings are exactly `NAMES.md`'s action table. Nothing is hard-coded to a keycode except the
  `wall_jump_*` defaults, which are actions like any other.
- **Pinch is derived by hand** (GAP-003=a): track two `InputEventScreenTouch` ids, compare the
  distance delta against `wall_pinch_threshold_px`. `InputEventMagnifyGesture` is **never** listened
  for — it does not fire on Windows.
- **Touch target size** (GAP-004=b):
  `clamp(mm_to_px(settings.wall_touch_target_mm), settings.wall_touch_target_min_px, settings.wall_touch_target_max_px)`
  where `mm_to_px` uses `DisplayServer.screen_get_dpi()`. **The clamp is mandatory**; DPI is
  unreliable on multi-monitor Windows and on Android.

### 1.10 The transition

One `Tween` on the camera (`WallTransition`), phases overlapping (`Q47`=b), total duration
`settings.base_delay * settings.wall_transition_delay_scale`, **never** `Game.get_delay()`
(`Q46`=b — it compresses to 0 on an act cancel).

| Phase | Share | Curve |
|---|---|---|
| zoom out | `wall_zoom_out_fraction` | `TRANS_EXPO` / `EASE_OUT` |
| travel | `wall_travel_fraction` | `TRANS_SINE` / `EASE_IN_OUT`, straight line (`Q51`=a) |
| zoom in | `wall_zoom_in_fraction` | `TRANS_EXPO` / `EASE_IN` |

- Zoom-out target = far enough to show **both** frames plus `wall_frame_reveal_margin` (`Q48`=b).
- Travel duration is **fixed**, not distance-scaled (`Q50`=a).
- **Pause boundary:** source pauses the frame its outer edge enters the view (`Q72`=a); destination
  unpauses the frame it becomes visible in the camera window at all (`Q73`=c).
- **Input unlocks before the tween ends** — the frame the picture and its frame are fully in view
  (`Q58`). A new destination is ignored until then (`Q56`=b).
- The destination screen is built **synchronously during the zoom-out phase** (`Q205`=a, `Q206`=b).
- `settings.wall_reduced_motion` replaces all of it with a cross-fade at a fixed zoom (`Q172`=a).

### 1.11 `InfoEntry` and the hover interface (Q133, Q132, Q135, Q130)

```gdscript
class_name InfoEntry extends RefCounted
var title : String       ## already localised
var body : String        ## already localised
var visual : Node        ## optional copy of the hovered thing (Q130); may be null
```

Anything hoverable implements `func get_info() -> InfoEntry` (`Q133`=b). The `InfoCard` sizes itself
to the entry (`Q130`), shows the **last** entry until info mode is left (`Q131`), and scrolls upward
over the picture when it does not fit (`Q140`).

---

## §2. Phases and steps

⚠ **A step number is an ID, not a position.** `S35`–`S39` were added after the first pass and sit
inside the phase they belong to; read the phases in order and the steps within a phase in the order
written. IDs are never reused or renumbered — a citation must keep meaning.

**Design nodes deliberately claimed by no step:** all of chart **A** (it documents the *existing*
`main.gd` navigation, which this shell replaces — there is nothing to build), and the cross-chart
pointer nodes **B11, B12, C17, D11, G14, I13, L13** (they are drawn links to other charts, not
behaviour). **H7** is claimed by nothing because it is already true — the map pans with its own
camera today (`world_map_controller.gd:24`). Everything else is claimed.

**Dependency order.** Phase 0 gates everything. Phase 1 is pure logic and can be built and tested
with no scene at all. Phases 2→3→4 are strictly sequential. **Phase 5 (frames), Phase 6 (info) and
Phase 8 (tool) are independent of each other** and may be done in any order once Phase 4 lands.
Phase 7 depends on 2.

### Phase 0 — spikes with pre-bound outcomes

Two facts in the design are `UNVERIFIED`. **You are not deciding anything here** — the experiment
runs and the written rule fires.

**S1 — shader `TIME` under pause** (implements D7, D10, Q222)
Scene with one card burning, `get_tree().paused = true`, screenshot at t=0 and t=+20 s.
**Done when:** you can state whether the flame advanced.
**Pre-bound:** if it advanced → proceed exactly as D7 says (accepted, hidden by the frozen texture).
If it did NOT advance → note it in `ASSUMPTIONS.md` and proceed identically; nothing changes either
way, this only tells us whether the hiding is load-bearing. **Neither outcome is a gap.**

**S2 — `accessibility_should_reduce_animation()` on Windows** (implements K8, GAP-005)
Print it, toggle the Windows animation setting, print again.
**Done when:** you can state whether it tracks.
**Pre-bound:** if it tracks → it seeds the first-launch default as GAP-005 says. If it does not →
the seed is skipped and `wall_reduced_motion` defaults to `false`, which GAP-005 already names as
the fallback. **Neither outcome is a gap.**

### Phase 1 — pure logic, no scene (headless-testable)

**S3 — `PictureEntry` + `WallLayout`** (implements B3, §1.1, §1.2)
Done when: both resources exist with exactly the exported fields above and load in the editor.

**S4 — `WallPacker`** (implements B4, G1–G6, G12, G13, §1.3)
Done when: `TestWallPacker` is green, including the overlap assertion.

**S5 — `FocusStack`** (implements F1, F2, F3, F4, F5, F6, §1.4)
Done when: `TestWallFocus` is green.

**S6 — `Pacing` + sweep every `create_timer` call site** (implements D6, §1.6)
Done when: `grep -rn "create_timer" solatro --include=*.gd` returns no hit in GAME code — only
`Scripts/pacing.gd`, test files, and vendored `addons/`, which is never edited here. **The full
suite is green** — this touches the show's pacing and is the step most likely to break existing
behaviour.

**S7 — `PlayerProfile` + `ProfileManager` autoload** (implements B9, K1, K5, K7, §1.5)
Done when: `TestWallProfile` is green; `project.godot` registers the autoload after `SettingsManager`.

**S8 — the `PlayerSettings` block** (implements C15, G5, G1, E5, H5, I8c, K8, K10, J2)
Every row of `DESIGN.md` §5 — the transition clock and phase fractions, the frame-thickness
fraction, the live-screen cap, the wall-view texture floor, the touch-target trio, the
reduced-motion flag, the debug flags and the pinch threshold.
Done when: every row exists as an `@export` with a `settings_changed` setter, in a
`@export_group("Picture wall")`. No extra knobs, no renames, no re-defaults.

⚠ The gap, view margin and ellipse clamps are **not** knobs — **GAP-008**=(a) puts them on
`WallLayout` only. `wall_view_texture_scale` is not one either; **GAP-002** removed the need.

### Phase 2 — the wall scene

**S9 — `wall.tscn` skeleton** (implements B1, B2, B10, §1.6)
Wall root, camera, `%Pictures`, `%Viewports`, `%WallSurface`, process modes per §1.6, and
`get_tree().paused = true` at `_ready`.
Done when: the scene runs and shows a flat coloured wall with nothing on it.

**S10 — `WallPicture` construction** (implements B5, B6, H1, H2, §1.7)
Done when: pictures appear at their packed rects with `NinePatchRect` frames, and
`TestWallRender`'s construction group is green.

**S11 — render gating** (implements E1–E8, §1.8)
Done when: `TestWallRender` is green — a non-focused picture reports `UPDATE_DISABLED` and a
non-null texture.

**S12 — pause wiring** (implements D1–D5, D8, D9, §1.6)
Done when: `TestWallPause` is green — exactly one screen root is `ALWAYS`, zero in wall view.

**S35 — `WallOverlay`** (implements B8, F7, F8, F9)
The persistent `CanvasLayer` carrying Back, Forward, Wall and the top-right Info toggle. Back closes
an open popup first and only then leaves the picture; the Wall button leaves a popup open behind it.
Done when: all four controls exist, are localised, and Back visibly disables itself at the bottom of
the stack (`Q65`=c's requirement that an unavailable control *look* unavailable).

**S37 — overfill at rest** (implements H3)
The focused picture overfills the window whenever its aspect does not match, so no frame is ever
visible at rest.
Done when: at aspects 1.33, 1.78 and 2.33 the square `map` picture shows no frame at rest.

**S13 — the filter swap** (implements H4, H5, H6, §1.7)
Done when: the focused picture at rest is `NEAREST`, everything else `LINEAR`, and a pure pan does
not flip it. ⚠ **By-eye sign-off required** (repo rule 6) — a test cannot tell you it looks right.

### Phase 3 — the transition

**S14 — `WallTransition`** (implements C1–C15, §1.10)
Done when: `TestWallTransition` is green on phase boundaries and durations.

**S15 — pause/unpause boundaries** (implements C9, C11, Q72, Q73)
Done when: `TestWallTransition`'s boundary group is green.

**S16 — early input unlock** (implements C13, Q58)
Done when: input is accepted before the tween reports finished, and never earlier than both the
picture and its frame being fully in view.

**S17 — resize and fullscreen** (implements C16, G7, G8, Q26, Q28)
Done when: a mid-transition resize retargets and continues without a visible snap.

**S18 — reduced motion** (implements K8, K9, K10)
Consumes the Phase 0 spike result: seed the first-launch default only if that spike said the query
tracks; otherwise default `false`.
Done when: with the flag on, every transition is a cross-fade and no zoom occurs.

**S36 — wall view: framing, pan and selection** (implements G9, G10, G11, F10, F11, F12)
Fill-and-crop framing, free pan **only** when pictures fall outside the view and never into void, no
free zoom, one selected picture starting at the one you came from, highlight by lift plus outline,
every picture enterable, and per-view focus memory.
Done when: `TestWallInput` I5, I6, I9 are green and the wall button is hidden while only one picture
exists.

### Phase 4 — input

**S19 — `WallInput.route`** (implements I1, I1b, I2, §1.9)
Done when: `TestWallInput`'s routing group is green at three zoom levels.

**S20 — mouse** (implements I3, I9, I12)
Done when: `TestWallInput` I1, I2, I8 are green.

**S21 — keyboard** (implements I4, I5, I6, I10)
Done when: `TestWallInput` I3, I4, I5, I6, I7, I9, I14 are green.

**S22 — controller** (implements I7, I10, I11)
Done when: `TestWallInput` I10 is green and the controller is driven by hand through one full
navigate-enter-back-wall cycle.

**S23 — touch: hand-derived pinch and the clamped target size** (implements I8, I8b, I8c)
Done when: `TestWallInput` I11, I12, I13 are green.

### Phase 5 — frames and wall surface (visual)

**S24 — frame art parameters** (implements B6, Q36, Q37, Q38, Q39, Q41)
**S25 — shadows from one light position** (implements B10, Q7)
Done when: ⚠ **by-eye sign-off.** No test gates these.

### Phase 6 — Info mode

**S26 — `InfoEntry` + `get_info()` on wall pictures** (implements J7, §1.11)
**S27 — `InfoCard`** (implements J3, J4, J5, J6, J12)
**S28 — the info zoom and its interaction with transitions** (implements J1, J2, J9, J10, J11)
**S29 — migrate the existing tooltips onto the info card** (implements J8, Q134=c)
⚠ S29 deletes `UI/map_hover_panel.gd`'s role as a separate system. Done when: `TestWallInfo` is
green **and** the map's node hover still shows its preview cards.

### Phase 7 — the screens move onto the wall

**S30 — `start_menu`, `map`, `deck` as pictures** (implements M1, M2, M3, M4, B7, K6, Q211)
⚠ K6 is a *negative* requirement and is easy to violate by accident: **wall state must not survive a
quit.** Every launch opens on the start-menu picture, as `main.gd:22` does today.
**S31 — `game` as a picture, and the freeze** (implements L1–L11, Q186=d, Q221–Q226)
**S38 — unlock reactions** (implements K2, K3, K4, K11)
No reveal ceremony; a live animated re-pack if the player is already in wall view; a silent re-pack
otherwise, with Back surviving because the stack holds ids and not positions; the debug unlock-all
flag honoured.
Done when: unlocking while inside a picture leaves the focus stack valid and the wall re-packed.

**S39 — memory instrumentation** (implements E9, E10)
A live count of instantiated screens and their texture memory behind the same debug gate as the leak
sentinel, plus the state-blob contract on `WallPicture` left unreachable but implemented, so the
unload-to-placeholder fallback is a measurement away rather than a rewrite (`Q79`, `Q143`=a).
Done when: the readout prints under the debug flag and nothing calls the blob path.

**S32 — the lost-run behaviour** (implements L12, Q157)
**S33 — audio** (implements M10, Q167, Q168, Q170, Q171)
Done when: the full existing suite is green — S31 touches `Game` and is the highest-regression step
in the plan.

### Phase 8 — the layout tool

**S34 — `Tools/wall_editor.tscn`** (implements M5, M6, M7, M8, M9, Q179, Q181, Q182, Q183, Q185, Q200)
⚠ Every script it touches must be `@tool` (§1j) — `WallLayout`, `PictureEntry`, `WallPicture`,
`WallFrame`.

⚠ **THE TOOL IS WHERE THE NUMBERS GET DECIDED, NOT THIS DOCUMENT.** Every value in `DESIGN.md` §5 is
a *starting* value, not a decision. The tool must expose, with a live re-pack or re-preview on every
change:

- **every `WallLayout` field** — `gap_px`, `home_id`, the ellipse clamps, `view_margin`;
- **every `PictureEntry` field per picture** — `ring`, `slot`, `size_multiplier`, `design_size`,
  the four `frame_px` sides, `frame_texture`, `keep_aspect`;
- **every `PlayerSettings` "Picture wall" knob** — the transition clock and its three phase shares,
  the easing selections, `wall_frame_reveal_margin`, `wall_view_min_texture_px`, the touch-target
  trio, `wall_pinch_threshold_px`;
- **a Save button** writing `layout_default.tres`, and a Revert.

Done when: it edits `layout_default.tres` directly, simulates aspect (`Q181`=a) and unlock state
(`Q182`=a), previews a transition with the real curves (`Q183`=a), and **no knob above requires
editing a `.tres` or a `.gd` by hand to change.**

---

## §3. Acceptance gates — objective and self-checking

| Phase | Gate |
|---|---|
| 1 | `TestWallPacker`, `TestWallFocus`, `TestWallProfile` green; `create_timer` grep clean; **full suite green** |
| 2 | `TestWallRender`, `TestWallPause` green; wall scene runs at 1280×720 and at 32:9 without an overlap error |
| 3 | `TestWallTransition` green; a scripted 20-transition soak leaves exactly one `ALWAYS` screen every time |
| 4 | `TestWallInput` green at 3 zoom levels per medium |
| 5 | by-eye only — no automated gate, and that is deliberate |
| 6 | `TestWallInfo` green; map hover still shows preview cards |
| 7 | **full suite green (31+ suites)**; a freeze/resume soak mid-act leaves `GameData.revision` unchanged |
| 8 | tool opens, writes the resource, and re-opens with the same layout |

---

## §4. ANTI-SCOPE — do not do these, however tempting

1. **Do not redesign any existing screen's layout or content** (`Q211`=a). Screens are reparented
   unchanged. A screen that looks wrong at a new aspect is a follow-up, not this run.
2. **Do not build the settings screen's contents or the information book** (`Q212`, `Q214`). They are
   registered ids with no scene.
3. **Do not add a touch-gesture addon.** GAP-003's resolution makes it a later testing convenience
   and explicitly **not** a shipping dependency.
4. **Do not build a resolution manager.** GAP-002: `SubViewport.size`, one property.
5. **Do not convert the existing `CanvasLayer` popups to Controls** (`Q161`=a) — inside a SubViewport
   their behaviour is already correct.
6. **Do not touch `LightLayer`'s sibling position** (`LAYERING.md:77-83`) — it is a written contract.
7. **Do not add per-frame shaders or unique frame art.** `QR4`=b is one shared parameterised style.
8. **Do not optimise the card layer.** It has never been measured (`PERFORMANCE.md` §1); an
   unmeasured optimisation is not an optimisation.
9. **Do not persist wall state across a quit** (`Q145`=b) or add wall fields to the run save
   (`Q150`=a).
10. **Do not add multi-slot save UI** (`Q213`=a). The profile format is slot-keyed; only slot 0 is used.

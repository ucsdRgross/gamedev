# HANDOFF — picture wall

**Goal:** the picture-wall shell is playable and correct on the paths a player actually takes.
"Done" is the owner's call after a playtest — not a green suite, which this feature has had
throughout every defect it ever shipped.

**State:** all criticals and majors from two independent adversarial reviews are fixed, each with a
red-then-green proof and a full suite between. The three open gaps are answered. **The suite is
green: `ALL 39 SUITES: 3116 CHECKS PASSED`.** What remains is one owner call on what unlocks
`book`, two composition questions that want real renders, and the playtest itself. **Nobody has
played it.** Every claim below comes from tests, probes and rendered snapshots.

**The layout tool is now the way to playtest composition.** `Tools/wall_editor.tscn` run with F6
hosts the real screens and opens on the whole wall with every field populated — see
PICTURE_WALL.md. S43's composition calls can be made in it directly rather than from snapshots.

**Entry docs:** solatro/PICTURE_WALL.md (how it is put together, and the landmines),
solatro/todo.md ("Picture wall" — everything still open),
solatro/design/picture-wall/ (DESIGN, PLAN, TEST_PLAN, NAMES, ASSUMPTIONS, gaps/).

## Tasks
```yaml
- id: S54
  description: >
    Owner playtest round 1 through the wall editor. Three rulings, recorded as GAP-021/022/023:
    the transition zooms out to the SOURCE frame only (Q48 b->a, a gate flip); Info mode ZOOMS OUT
    until the whole screen clears the info card rather than panning down and cropping the top; and
    a click describes a card while Info mode suppresses every game action.
  files_touched: [solatro/Scripts/Wall/wall_transition.gd, solatro/UI/Wall/wall_picture.gd,
    solatro/Scripts/player_settings.gd, solatro/UI/play_area.gd, solatro/Levels/game_view.gd,
    solatro/Levels/main.gd, solatro/Tests/Wall/test_wall_transition.gd,
    solatro/Tests/Interaction/test_interaction.gd, solatro/Tests/Visual/wall_editor_soak.gd]
  verification_command: '<godot> --path solatro res://Tests/all_tests.tscn'
  verification_kind: suite
  status: done
  evidence: >
    Suite ALL 39 SUITES: 3104 CHECKS PASSED; soak 87 checks / 0 problems. Info-mode gate proven
    red-then-green (2 FAILED when _info_mode() forced false). Q48's six old T4 assertions pinned the
    superseded answer and were rewritten to the new contract, including that the plateau zoom is
    IDENTICAL whatever the destination is.
  notes: >
    This also lands the half of Q134=c/J8 that S29 skipped: the board's in-screen inspector now
    yields to the wall's one info card. S29's done-when named the map and never the board.
    Round 2 of the same playtest corrected the info zoom (the reserve is the card's LIVE height,
    not the cap -- reserving the cap read as being thrown out to the wall) and added
    wall_screen_popups, which decides whether a screen's own description exists outside Info mode.

- id: S55
  description: >
    Owner playtest rounds 2-5 through the wall editor. Landed: the transition zooms out to the
    SOURCE frame only; Info mode zooms out (never pans) far enough to clear the card; a click
    describes a card and Info mode suppresses game actions; wall_screen_popups; Info mode is per
    picture; the card's visual is made inert; and the crop/aspect/stale-tween defects found on the
    way. Recorded as GAP-021, GAP-022 and GAP-023.
  files_touched: [solatro/Scripts/Wall/wall_transition.gd, solatro/UI/Wall/wall_picture.gd,
    solatro/UI/Wall/info_card.gd, solatro/Scripts/player_settings.gd, solatro/UI/play_area.gd,
    solatro/Levels/game_view.gd, solatro/Levels/main.gd, solatro/Tools/wall_editor.gd,
    solatro/Tests/Wall/test_wall_transition.gd, solatro/Tests/Wall/test_wall_info.gd,
    solatro/Tests/Interaction/test_interaction.gd, solatro/Tests/Visual/wall_editor_soak.gd]
  verification_command: '<godot> --path solatro res://Tests/all_tests.tscn'
  verification_kind: suite
  status: done
  evidence: 'ALL 39 SUITES: 3141 CHECKS PASSED; wall_editor_soak 105 checks / 0 problems; LEAK
    CANARY 17/17. Every behaviour change proven red-then-green.'
  notes: >
    Three defects remain OPEN and are the first thing to pick up -- see todo.md "Picture wall", the
    three red entries: the card lays out before the zoom finishes, the deck/discard/rules viewers
    still cannot show a description, and the per-screen card does not actually persist. Each has a
    diagnosis and a fix path written down. The third one has a mechanism that landed and a
    behaviour that did not, so write the soak case before touching the code.

- id: S40
  description: Owner playtest of the wall shell — navigate, resize, alt-tab, controller, Info.
  files_touched: []
  verification_command: 'manual'
  verification_kind: manual
  status: pending
  evidence: ''
  notes: 'The only remaining gate. Two reviews traced journeys; neither played it.'

- id: S41
  description: >
    Decide what PIXELS' mask-vs-art check should be. It fails intermittently
    (0 mask-without-art, 3773 art-without-mask at rest) and its own comment says
    DO NOT RAISE IT TO GO GREEN, so it was left untouched.
  files_touched: [solatro/Tests/Visual/test_pixels.gd]
  verification_command: '<godot> --path solatro res://Tests/all_tests.tscn'
  verification_kind: suite
  status: blocked
  evidence: 'Observed failing in 1 of 3 consecutive runs of an unchanged build; clean in the other 2.'
  notes: 'Owner call. Reads like a capture/settle race in _real_card()/_shoot(), not a bad bound.'

- id: S45
  description: >
    WALL PAUSE read its transition DURATION off the machine's saved settings.tres, so two
    "is the move still in flight?" preconditions failed on any box tuned for speed and the
    real assertions behind them never ran. Both now pin the clock and snapshot with no prefix.
  files_touched: [solatro/Tests/Wall/test_wall_pause.gd]
  verification_command: '<godot> --path solatro res://Tests/all_tests.tscn'
  verification_kind: suite
  status: done
  evidence: 'Was 2 FAILED on 3 of 3 runs (base_delay 0.1 x wall_transition_delay 0.001 = 0.0001s,
    one frame). Now ALL 39 SUITES: 3116 CHECKS PASSED, with settings.tres restored unchanged.'
  notes: 'Any test whose precondition is a DURATION must set that duration itself.'

- id: S46
  description: >
    The wall editor previewed against the wrong settings in both modes and showed empty frames.
    It now assigns WallPicture.editor_settings (an override that wins previewed OR played, the
    LightLayer idiom), opens on every picture unlocked with the transition pair seeded, and
    hosts the real screens when run.
  files_touched: [solatro/Tools/wall_editor.gd, solatro/UI/Wall/wall_picture.gd,
    solatro/UI/Wall/wall.gd, solatro/UI/Wall/info_card.gd]
  verification_command: '<godot> --path solatro res://Tests/Visual/wall_editor_snapshot.tscn'
  verification_kind: snapshot
  status: done
  evidence: 'Editor mode: packed 6/6, zero SCRIPT ERRORs (was 10x wall_light_offset on Nil).
    F6: packed 6/6 with menu, map and game rendering inside their frames.'
  notes: 'Info mode is covered too: `preview_info_mode` is the only Inspector route to
    `wall_info_mode`, which is not exported on PlayerSettings by design.'

- id: S42
  description: >
    Decide what unlocks `book`. ProfileManager.unlock() has no production caller, so
    S38/K2-K4, _repack_wall(), apply_layout(animate=true) and picture_unlocked are
    unreachable in the shipped game.
  files_touched: [solatro/Scripts/profile_manager.gd, solatro/Levels/main.gd]
  verification_command: '<godot> --path solatro res://Tests/all_tests.tscn'
  verification_kind: suite
  status: blocked
  evidence: 'Only Tests/Wall/test_wall_profile.gd and test_wall_focus.gd call unlock().'
  notes: 'Owner call: the trigger is a design decision, not something to invent.'

- id: S43
  description: >
    Look at real renders and rule on wall-view composition — at 16:9 four of twelve
    pictures are cut by the frame; at 32:9 the corners are empty and content bands
    across the upper middle.
  files_touched: [solatro/Assets/Wall/layout_default.tres]
  verification_command: '<godot> --path solatro res://Tests/Visual/wall_verify_snapshot.tscn'
  verification_kind: snapshot
  status: blocked
  evidence: 'Captured and described below; both readings confirmed by eye.'
  notes: 'GAP-018=(a) keeps view_margin as extra crop, which makes the 16:9 crop more pronounced.'

- id: S44
  description: >
    Understand why the full suite intermittently HANGS at 30 of 39 suites with no
    banner, in clusters.
  files_touched: [solatro/Tests/Support/test_base.gd]
  verification_command: '<godot> --path solatro res://Tests/all_tests.tscn'
  verification_kind: suite
  status: pending
  evidence: '3 consecutive hangs, then clean HEAD twice, then the same change green twice.'
  notes: >
    Every suite involved (PIXELS, OUTLINE, INTERACTION, WALL INPUT, WALL PAUSE) completes
    when run ALONE, so it is in the concurrency. Re-run before bisecting: a hung run here is
    NOT reliably attributable to the change that produced it.

- id: S47
  description: >
    The wall editor now hosts the REAL overlay and info card, drives them from a real FocusStack,
    and is exercised by wall_editor_soak.tscn. Two product defects surfaced and were fixed:
    InfoCard sized itself ignoring the preview image BESIDE its text (card 74px vs a 90px visual,
    so it scrolled content it had room for, and the body was measured at full card width instead
    of the narrower text column); and setting info mode outside the button left the button
    reading un-pressed.
  files_touched: [solatro/Tools/wall_editor.gd, solatro/UI/Wall/info_card.gd,
    solatro/UI/Wall/wall_overlay.gd, solatro/Tests/Visual/wall_editor_soak.gd]
  verification_command: '<godot> --path solatro res://Tests/Visual/wall_editor_soak.tscn'
  verification_kind: snapshot
  status: done
  evidence: 'Soak 52 checks / 0 problems; both fixes proven red-then-green (card 74 vs visual 90
    when neutralised; wall framing 0.32210 vs 0.31579/0.47368 when the view_margin fix was
    neutralised). Suite ALL 39 SUITES: 3122 CHECKS PASSED.'
  notes: 'The soak is a diagnostic, not a suite member -- run it by hand after touching the tool.'

- id: S48
  description: >
    Info mode SNAPPED in the tool while the game animated it, so the reveal read as instant and
    could not be judged. The tool now tweens to the info pose, and wall_info_zoom_scale is a new
    knob for that leg alone (default 1.0 = exactly an ordinary wall move, so nothing changes
    until it is tuned). Pinch is previewable through the real PinchTracker.
  files_touched: [solatro/Tools/wall_editor.gd, solatro/Scripts/player_settings.gd,
    solatro/Levels/main.gd, solatro/Tests/Visual/wall_editor_soak.gd]
  verification_command: '<godot> --path solatro res://Tests/Visual/wall_editor_soak.tscn'
  verification_kind: snapshot
  status: done
  evidence: 'Soak 55 checks / 0 problems. Animation proven red-then-green: neutralised, the camera
    is already at the info pose two frames in (mid (0.0, 82.19) vs target (0.0, 82.19)).
    Suite ALL 39 SUITES: 3094 CHECKS PASSED.'
  notes: 'wall_info_zoom_scale is a NEW knob at its no-op default -- it wants an owner ruling in
    the playtest, not a silent number. Its suite test measures TWO durations and compares them:
    the weaker "is it still running after N frames" form passed with the knob ignored, because the
    unscaled clock is already longer than any small frame count.'

- id: S49
  description: >
    The wall editor now HOSTS the real wall.tscn when run (F6), keeping its global pause, with the
    tool itself PROCESS_MODE_ALWAYS. Owner ruling: the tool must have the same functionality as the
    game. Every knob now reaches the code the game runs it through -- selection repeat,
    wall_debug_readout, wall_unlock_all and wall_reveal_delay_scale were all inert before.
    A play_reveal button drives the last of those.
  files_touched: [solatro/Tools/wall_editor.gd, solatro/Tests/Visual/wall_editor_soak.gd]
  verification_command: '<godot> --path solatro res://Tests/Visual/wall_editor_soak.tscn'
  verification_kind: snapshot
  status: done
  evidence: 'Soak 66 checks / 0 problems, including a held-direction repeat, the debug readout, an
    unlock_all widening and a reveal duration ratio. Editor mode still clean (hand-built scaffold;
    Wall is not @tool). Suite ALL 39 SUITES: 3139 CHECKS PASSED.'
  notes: >
    Found and fixed while wiring it: _apply_focus() was SKIPPING unfocus() on non-focused pictures
    whenever preview_wall_view_resolution was off, so whatever was focused last kept is_focused
    true forever. Wall._focused_picture() then reported a focused picture in wall view, and both
    the texture-filter update and the selection repeat bail on that -- silently. The soak now
    guards it directly.

- id: S52
  description: >
    The wall editor opened at a ROUNDED preview_aspect (1.7778), which lands 1.4e-05 past
    is_equal_approx -- so focused_scale() applied its 2% overfill margin at what is really a
    matching aspect and cropped real UI. It made start_menu look like its button row overflowed,
    which it does not (widest content ends at x=1148 of 1152).
  files_touched: [solatro/Tools/wall_editor.gd, solatro/Tests/Visual/wall_editor_soak.gd]
  verification_command: '<godot> --path solatro res://Tests/Visual/wall_editor_soak.tscn'
  verification_kind: snapshot
  status: done
  evidence: 'Red-then-green: neutralised, the soak reports "1.77780000 vs 1.77777778". preview_aspect
    is now seeded from the live window in _ready().'
  notes: >
    Generalises: any caller handing WallPacker a rounded aspect rather than window.x / window.y
    crops 2% off every focused picture. Main computes it exactly, so the game was never affected.

- id: S53
  description: >
    Bug hunt through authoring extremes an author can reach but no fixture had used --
    size_multiplier 0.05 and 8.0, a frame thicker than its own picture, keep_aspect at a 3.0
    window, and a 16x9 design size. No defects found; the cases are now guarded.
  files_touched: [solatro/Tests/Visual/wall_editor_soak.gd]
  verification_command: '<godot> --path solatro res://Tests/Visual/wall_editor_soak.tscn'
  verification_kind: snapshot
  status: done
  evidence: 'Soak 83 checks / 0 problems, asserting non-overlap, finite rects and the
    wall_view_min_texture_px floor at each extreme. 17_fat_frame.png confirms the case is not
    vacuous -- a real 400px frame renders and pushes its neighbours away.'
  notes: ''

- id: S51
  description: >
    CONFIRMED DEFECT IN THE SHIPPED GAME: every unfocused picture shows an enlarged top-left CROP
    of its screen, not the screen. update_wall_view_size() takes the render target from 1152x648 to
    385x216 and the screen does not re-flow into it. Main._build_pictures(), _repack_wall() and
    _on_window_resized() all make the identical call, so this is wall view at cold launch and after
    every re-pack.
  files_touched: [solatro/UI/Wall/wall_picture.gd]
  verification_command: '<godot> --path solatro res://Tests/Visual/wall_editor_soak.tscn'
  verification_kind: snapshot
  status: done
  evidence: >
    Fixed with SubViewport.size_2d_override = design_size + size_2d_override_stretch, so the screen
    LAYS OUT at design size and RENDERS into the footprint. Rendered and read by eye: the whole
    start menu, board and map now appear scaled down where a giant "S" used to be. Red-then-green:
    neutralised, the soak reports "override (0, 0), size (385, 216)" on two checks.
  notes: >
    focus() CLEARS the override, because a focused picture renders 1:1 and WallInput.route() maps
    into a plain viewport -- a stale override would displace every click inside a focused screen.
    Guarded by the soak in both directions.

- id: S50
  description: >
    wall_reveal_delay_scale had no SUITE test -- nothing covered Main's own opening reveal. Added
    one that drives _on_new_run() (the REAL call site, not _go_to_wall_view directly) at two scales
    and compares the measured durations.
  files_touched: [solatro/Tests/Wall/test_wall_pause.gd]
  verification_command: '<godot> --path solatro res://Tests/all_tests.tscn'
  verification_kind: suite
  status: done
  evidence: 'Red-then-green: with both Main call sites neutralised the check reports
    "scale 4.0 took 762 ms, scale 0.1 took 811 ms" -- a constant clock.'
  notes: 'Driven through _on_new_run(), not _go_to_wall_view(): the helper would prove the parameter
    is plumbed and say nothing about whether the launch path passes the knob at all, which is
    exactly the gap that left this knob unread.'
```

## Verified vs assumed

**Verified — rendered and looked at** (`Tests/Visual/wall_verify_snapshot.tscn`,
`wall_frame_shadow_snapshot.tscn`, WINDOWED, PNGs read):
- A focused picture at rest fills the window edge to edge — no frame, no wall at any edge. H3/`Q27`/S37.
- Six pictures at different sizes each draw their screen exactly filling their frame, with no gap
  at the inner lip. This is the fix for the postage-stamp defect.
- Frames render as a real nine-slice: constant border thickness on very wide rects, corners matching
  edges. Not the smeared concentric gradient that shipped.
- Shadows fall in one consistent direction across every picture.
- ⚠ These fixtures assign the shared frame texture DIRECTLY, so they do not exercise the
  `.tres` path that was actually broken. `TestWallRender`'s nine-slice row does — it builds from
  the real `layout_default.tres` entry and first asserts that texture is a different instance.

**Verified — measured under the real paused tree, on a real `Main`:**
- Every wall journey completes: Wall press, wall-view entry, picture-to-picture, Back x3, Forward,
  Info on/off, `enter_game`, `game_ended`, reduced motion.
- `Pacing.wait` inside a live screen fires; inside a frozen screen it does not; a `Timer` child of
  the real `Game` node fires.
- Routing lands on the aimed viewport pixel at three zooms and at a non-16:9 aspect, for mouse and
  for raw touch.

⚠ **The three red `todo.md` entries were found by PLAYING it, after every one of the above was
green.** The suite and the soak are necessary and they are not sufficient — none of the three
shows up as a failing check, because each is about ordering, reachability or a journey nothing
drives. Write the missing journey first; do not trust a green banner to have covered it.

**Assumed, not checked:** anything about how the wall FEELS — transition timing, the reveal's
"longer, slower", whether GAP-019=(c)'s cut reads as abrupt, whether the 14px selection lift is
legible, whether the info pose reveals the right amount of frame. All of it needs the playtest,
and all of it is now reachable from `Tools/wall_editor.tscn` on F6.

## Open bugs

See `todo.md` "Picture wall" — it is the live list and is not duplicated here. Nothing on it is a
known crash or soft-lock. The one remaining suite-reliability item is S44 (the intermittent hang);
S41's PIXELS check is a bound nobody has ruled on, not a failure it produces every run.

## Files touched

29 commits on `picture-wall` since the run began. `git diff --stat 76ac7a1..HEAD` for the list;
the wall subsystem is `Levels/main.gd`, `UI/Wall/*`, `Scripts/Wall/*`, `Scripts/pacing.gd`.

## Next up

1. **S40 — playtest**, now easiest through `Tools/wall_editor.tscn` (F6) for composition and the
   real game for feel. Everything else waits behind knowing how it plays.
2. **S42 — what unlocks `book`.** Until this exists, a whole subsystem is dead code.
3. **S43 — composition at 16:9 and 32:9**, rulable live in the tool.
4. **S41 / S44 — suite reliability.** Neither blocks play.

Opening prompt for the next agent:

> Resume the picture wall in `solatro/`. Read `HANDOFF_picture_wall.md`, then `PICTURE_WALL.md`
> (especially Landmines) and `todo.md`'s "Picture wall". Run the full suite WINDOWED first and
> trust nothing until you see the banner — and if it hangs with no banner, RE-RUN before
> bisecting, that is a known intermittent. Everything blocking is an owner call or a playtest;
> do not invent an unlock trigger or widen a test tolerance to go green.

## References

- `design/picture-wall/DESIGN.md` — the provenance for every wall decision. ⚠ **Code no longer cites
  question ids**; the design docs keep the traceability and the code states the rule. See
  `.claude/memory/design-ids-stay-out-of-code.md`.
- `design/picture-wall/gaps/GAP-018.md`, `GAP-019.md`, `GAP-020.md` — all three answered.
- `.claude/memory/tests-that-prove-nothing.md` — the ten ways a test passes while proving nothing.
- `.claude/memory/running-godot-scenes.md` — how to run the suite and what a banner does not prove.

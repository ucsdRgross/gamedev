# HANDOFF — picture wall

**Goal:** the picture-wall shell is playable and correct on the paths a player actually takes.
"Done" is the owner's call after a playtest — not a green suite, which this feature has had
throughout every defect it ever shipped.

**State:** all criticals and majors from two independent adversarial reviews are fixed, each with a
red-then-green proof and a full suite between. The three open gaps are answered. What remains is
one owner call on a flaky test, one on what unlocks `book`, two composition questions that want
real renders, and the playtest itself. **Nobody has played it.** Every claim below comes from
tests, probes and rendered snapshots.

**Entry docs:** solatro/PICTURE_WALL.md (how it is put together, and the landmines),
solatro/todo.md ("Picture wall" — everything still open),
solatro/design/picture-wall/ (DESIGN, PLAN, TEST_PLAN, NAMES, ASSUMPTIONS, gaps/).

## Tasks
```yaml
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

**Assumed, not checked:** anything about how the wall FEELS — transition timing, the reveal's
"longer, slower", whether GAP-019=(c)'s cut reads as abrupt, whether the 14px selection lift is
legible. All of it needs the playtest.

## Open bugs

See `todo.md` "Picture wall" — it is the live list and is not duplicated here. Nothing on it is a
known crash or soft-lock; the two 🔴 entries are both about the TEST SUITE's reliability, not the
game.

## Files touched

29 commits on `picture-wall` since the run began. `git diff --stat 76ac7a1..HEAD` for the list;
the wall subsystem is `Levels/main.gd`, `UI/Wall/*`, `Scripts/Wall/*`, `Scripts/pacing.gd`.

## Next up

1. **S40 — playtest.** Everything else is waiting behind knowing how it actually plays.
2. **S42 — what unlocks `book`.** Until this exists, a whole subsystem is dead code.
3. **S41 — the PIXELS mask check.** The suite is not trustworthy run-to-run until it is settled.

Opening prompt for the next agent:

> Resume the picture wall in `solatro/`. Read `HANDOFF_picture_wall.md`, then `PICTURE_WALL.md`
> (especially Landmines) and `todo.md`'s "Picture wall". Run the full suite WINDOWED first and
> trust nothing until you see the banner — and if it hangs with no banner, RE-RUN before
> bisecting, that is a known intermittent. Everything blocking is an owner call or a playtest;
> do not invent an unlock trigger or widen a test tolerance to go green.

## References

- `design/picture-wall/DESIGN.md` — cited by question id (`Q56`, `J1`, `G10`) from code throughout.
- `design/picture-wall/gaps/GAP-018.md`, `GAP-019.md`, `GAP-020.md` — all three answered.
- `.claude/skills/plan-run/SKILL.md` — the nine ways a test passes while proving nothing.
- `.claude/memory/running-godot-scenes.md` — how to run the suite and what a banner does not prove.

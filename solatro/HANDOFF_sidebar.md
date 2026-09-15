# HANDOFF — sidebar (PLAN.md Phases 1–9, S1–S24)

**Goal:** land ALL of `solatro/design/sidebar/PLAN.md` — S1 through S23 and the closing phase S24 —
on branch `sidebar`, one verified step per commit (owner ruling: the original S1–S18 scope was
widened to every phase; do not stop at S18).
**State:** Phases 1–5 done (S1–S18 committed; S18 at 8cfb5eee). The Phase 5 boundary review
(Fable 5.1, over `17e9cc1c..8cfb5eee`) found 5 confirmed + 4 suspected — see "Phase 5 review":
three confirmed are ruling contradictions filed as GAP-006/007/008 (owner calls, non-blocking);
fixes 1–4 landed (1925fd9b, dcc81b8d, 22aa4207, fix 4 after 582e1883); suspected 6 and 8 did
not reproduce (rows pin them); the bounded re-review found 3 confirmed, fixed as fix 5 and fix 6
(after dabde1e1). Phase 6 landed: S19 fde80a92 (48 suites), S20 0cdd8e23, S21 under the owner's
mid-run one-face-down ruling (see Owner rulings); its review's two confirmed defects fixed (fix
7, fix 8). Phase 7 landed: S22 52f293b9; its review's root cause fixed (fix 9), End's authored
default (fix 10), the resolve ungrab (fix 11); the card back is frame 3 (owner ruling). Phase 8
landed: S23 eb635e79; its review's four confirmed defects fixed (fix 13 popup follows/hides, fix
14 touch pan, fix 15 panel resize); the fix-commit re-review's two confirmed fixed (fix 12, the
replay route). **EVERY PLAN STEP S1–S23 IS ON THE BRANCH. Next: the closing phase S24** per
`.claude/skills/plan-run/SKILL.md` "Closing the run", every numbered item, results recorded here;
still-open suspected items to reproduce inside the close: re-review 3 (undo after the automatic
end arming a card of the popped state) and 4 (Back during the locked hold), Phase 8 item 5
(`_tapped_node` never cleared by mouse hover). GAP-004 is open, non-blocking.
⚠ The owner's other worktree (`../gamedev-boardplan`) runs the suite unannounced; check
`tasklist | findstr Godot_v4.7` before every run and wait it out — a concurrent run rotates
`godot.log` and fabricated one GRID VIEW failure this session. PID 3020 is a stale Godot 4.1.2
window of `sidebar_snapshot.tscn` from 01:52 that the permission classifier refused to stop —
harmless so far; the owner should close it. `test-speed` (one test pacing for every suite, a suite filter, a headless logic tier —
`py solatro/Tools/run_tests.py --filter <Node> | --logic`) is merged at 587f2d60; the full run is
~200 s and a single suite ~30 s. Open: GRID LAYOUT fails 2 of 4 runs on the merged branch
(rotating check; 0 of ~15 before the merge) — being diagnosed before S5. Phase 1 (S1–S4) done and reviewed: the adversarial pass at the phase boundary found 8
confirmed defects, fixed in four commits (3d858441, 1f34cf5e, ce0f918b, 784f173e). S5 next. An
owner report that the game board sits too far right with a gap beside the sidebar is OPEN — not
reproduced at ten window sizes (grid centre within 7 logical px of the remaining-space centre);
awaiting the owner's screenshot and window size. Implementers now append evidence to a scratch file as they go,
because a turn-cap stop loses the final report (it happened on most S2/S3 dispatches). A throwaway
detached worktree of unmodified main (`../gamedev-baseline`, a28c79aa) exists for by-eye
before/after captures — local only; `git worktree remove` it at the close. Single-suite runs: launch the NON-console exe, wait for the
suite banner in test_output_all.log, end `$p.Id` (the console exe is a wrapper; ending it orphans
the game window).
**Entry docs:** solatro/design/sidebar/PLAN.md (self-contained), DESIGN.md (authority on behaviour),
TEST_PLAN.md (every test that must exist), NAMES.md (every identifier), solatro/START_HERE.md
**IMPLEMENTED-BY:** `plan-implementer` subagent. S1–S4 (through commit 5b8f84b9 and S4's
uncommitted first pass): `sonnet` at `effort: low`. From S4's finish onward: `opus` (Opus 5) at
default effort. Overseer: Opus 5 through S4, then Fable 5.1 at high effort through the close's
items 1-4 and close fix 1, then Opus 5 (Fable's usage limit hit mid-close); it writes no source.
Reviewers: every phase review and close items 2-4 ran on Fable 5.1; close item 5 onward on
Opus 5, which is at the floor.

## Provenance
- Code: `plan-implementer` — sonnet (effort low) for S1–S4's first pass; Opus 5 (default effort)
  for everything after. Both models wrote code on this branch.
- Reviewer floor: the highest tier present — Opus 5 at default effort or higher (`opus` or
  `fable`), same generation or newer.

## Run rules in force
- Worktree `../gamedev-sidebar`, branch `sidebar`. Overseer commits one verified step per commit.
- ONE subagent at a time (hook-enforced). Implementer never stages or commits.
- Every `--import` rewrites `solatro/design/effect-review/EFFECTS.*.translation` and `.csv.import`.
  Revert them before each commit: `git checkout -- solatro/design/effect-review` then
  `git clean -fq -- solatro/design/effect-review/*.translation`.
- The main checkout shares `app_userdata/Solatro` with this worktree — never run the suite from both.
- Dispatch every implementer FOREGROUND (`run_in_background: false`): the lock's PostToolUse
  release only fires for foreground calls. `plan-implementer` maxTurns is 150; a step bigger than
  that is split into parts that each leave the suite green.
- An implementer cut off mid-step: reset to the last commit, unless its last act was a completed
  full-suite run, in which case the tree is coherent and a fix-forward dispatch is cheaper.

## Baseline (main @ a28c79aa, unmodified, this box)
- `py solatro/Tools/run_tests.py` (GODOT_BIN = the box's console exe), windowed, ~400 s.
- Banner: `ALL 45 SUITES: 4002 CHECKS PASSED [23 placeholder warnings]`
- Exit-time (wrapper, pre-existing): `Pages in use exist at exit in PagedAllocator:
  N16WorkerThreadPool5GroupE`, `15 resources still in use at exit`. Wrapper exit code 2.
- ⚠ An owner editor open on the MAIN checkout (shared `app_userdata`) made GRID VIEW's three
  `grid_pan_right` real-key-press checks fail. Check for editor processes before every run.
- Suite count derivation: `grep -c 'ext_resource type="PackedScene"' solatro/Tests/all_tests.tscn` = 45.
- **Gate for every step:** suite count ≥ 45 (rising as suites are added), zero failures, no
  exit-time error lines beyond the two above.

## Owner rulings made during this run
- **S21 visual (supersedes `Q217`=b, `Q244`=a, `Q245` "knob defaulting to 5"; `Q218`=b stands),
  the owner's words verbatim, given mid-run while S21 was in flight:** *"the entrance cards refill
  looks wrong to me. you set it as a bunch of stacks of cards, but the implementation in
  board-plan worktree is closer to what i expected with cards revealed right on top of the
  entrance slots and only being stack of 1, which it has already implemented. unrevealed cards in
  the stocks should not be entities yet until ready to be flipped. expected behavior should be
  zone should be replaced with a flipped over card with new card on top. once its flipped over to
  reveal new set of entrance cards, the flipped card should take place of previously revealed card
  and there is another back facing card underneath, implying the stack instead of showing it."*
  Reading built: a non-empty stock shows exactly ONE face-down card beneath the revealed card; no
  entity exists for any other stock card; at a refill the face-down card flips up to become the
  revealed card and a fresh face-down appears beneath it while the stock still has cards; the cap
  knob is deleted (no caller). DESIGN §4 / chart I8 need the owner's correction at the close.
- **Card back, the owner's words verbatim (given after S21 landed):** *"cardback should be frame
  3"* — the face-down card draws frame 3 of the card sprite sheet. Built after fix 9:
  `CardVisual.CARD_BACK_FRAME` = 3 (and `BLANK_CARD_FRAME` = 1 names the branch's old bare
  literal); a "frame" is the UV window `CardOutline.frame_polygon` writes. By eye
  entrance_stocks.png: a red back with a gold star under each revealed card.
- `plan-implementer` maxTurns 50 → 150 (edited on main and on this branch).
- Legacy comment debt is DEFERRED to its own pass: a step keeps every comment it writes or edits
  compliant and leaves old comments in touched files alone. `doc_check --changed` findings on those
  lines are expected. Counts when this run started touching them: play_area.gd 638, game.gd 352,
  test_visual_layers.gd 293, test_grid_view.gd 252, test_ui_props.gd 241, card_visual.gd 205,
  test_grid_layout.gd 197, main.gd 181, wall_editor.gd 115, wall_picture.gd 97,
  wall_editor_soak.gd 67, wall_transition.gd 53, test_interaction.gd 51, player_settings.gd 47,
  wall_input.gd 31, map.gd 12, wall_overlay.gd 11, choice_viewer.gd 11, deck_builder.gd 10,
  card_effect_api.gd 9, deck_viewer.gd 4, cards_viewer.gd 3, type_input.gd 3.

## Phase 1 review (adversarial, Fable 5.1) — what it found and where it went
- Top-case board zoom ignored `board_inset_top` (fixed, 3d858441); menu laid out in window px
  inside a picture (fixed, `WallPicture.local_rect_beside`, 1f34cf5e); map camera shift in window
  px vs world units × zoom (fixed, ce0f918b, GAP-003 filed); S4 fixtures that removed the unit
  mismatch (rewritten); connection bookkeeping and the private-container fallback in three homes
  (now `HudContainer.connect_for_screen/disconnect_for_screen/ensure`, 784f173e); a check that
  could not fail (deleted). Open from it: GAP-001 note — on a clamped ultrawide the flush-inner
  container overlaps the board region by the outboard gap (finding 10); the inset uses the
  design's unmargined scale, ~6 window px narrower than the picture's real overfilled scale
  (recorded in ASSUMPTIONS).
- ⚠ The whole geometry runs in the project's LOGICAL canvas (`canvas_items` + `expand`, base
  1152×648): every 16:9 window is the same layout scaled; only non-16:9 windows change it.

## Phase 2–5 audits (plan-auditor, read-only) — defects the briefs must carry
- §3a line numbers: play_area.gd −4 everywhere; game_view.gd rewritten in S2/S3 — the relay is
  `:86`, `_on_processing_changed` `:208`, `_on_data_selected` `:323` (S15's `:462-498` is past EOF).
- S5: `info_requested` fires only on CLICK and only in Info mode (`play_area.gd:1440-1450`,
  `:1476-1481`, gate `_info_mode()`); hover goes `mouse_entered → grab_focus →
  on_control_focus_entered` (`:2782-2813`) into the in-board popup. S5 must emit on focus and
  keep click semantics; no hover-EXIT publication exists (S6 needs one — an invisible mechanism
  choice, log it); `Main._on_screen_info_hovered` (`main.gd:685`) is gated on `wall_info_mode`
  and also receives the map's `info_hovered`. `DescriptionPanel` is a 4-line shell;
  `show_description(entry)` discards its argument. `InfoCard._resize_to_content` measures
  against knobs S9 deletes — size off `container_rect()`. Per-screen memory (1.14) lives only in
  Info-mode code S9 deletes — the container must own it.
- S6: exit X sized by `WallInput.touch_target_px(DisplayServer.screen_get_dpi(),
  PlayArea.settings())` today (S13 repoints; four call sites, not three). TEST_PLAN 1.7's fourth
  dismissal and 1.8 need `following` → moved to S14 (plan defect, not dropped). Bare-board click
  has no branch in `_on_gui_input`; per-cell geometry is `_grid_slot_center_global` /
  `_card_control_at`, not `_publish_cell_rects`.
- S7: `game.gd` needs no edit (`processing_changed` exists, `game_view.gd:55` listens).
- S9: `wall.gd:290-293` holds the only `wall_info` reader (missing from the map);
  `player_settings.gd:522-566` interleaves two SURVIVING knobs; `main.gd` Info surface is ~20
  sites incl. `_info_card_height()` (6 callers) and `_on_picture_hovered`; `WallTransition`'s
  Info removal is a signature change (`card_height_px`); `test_wall_input.gd:60,1029,1111` and
  `test_wall_focus.gd` assert Info mode and go red loudly.
- S10: landed. `_process()` is stopped by `_ease_row_openings()`'s own return, which reports the
  row openings and the depth-layer growth together; `PlayArea.card_info()` survives as the
  sidebar's publish shape.
- S11: `sidebar_snapshot` exists (six PNGs; no description capture yet — 9.2 needs one); the
  wall editor has NO Info panel node — its Inspector `preview_info_mode` + borrowed InfoCard go;
  suite count lands at 45 after deleting test_wall_info (46 today) — TEST_PLAN says ≥ 45.
- S12: only ChoiceViewer has a panel (`%CardInfo`); DeckViewer has none and Rules is DeckViewer
  on `rules_deck`; viewers live inside a picture's SubViewport → the inset goes through
  `WallPicture.local_rect_beside()`; `deck_builder.tscn` is broken too (missing ext_resource).
- S13: `test_wall_input.gd:947-964,1246-1285` and `test_grid_view.gd:1538-1562` assert the
  clamp/mm knobs and must change in the same commit.
- S14: no LIFT quantity exists (held offset is cursor-relative, `card_visual.gd:700-704`) →
  GAP candidate; `prop_layer.gd:277` reads `held`; emulated mouse motion from touch (device −1).
- S15: no auto-arm exists; `grab_cards` has one production caller (`game_view.gd:336`).
  TEST_PLAN 6.3's spy has no seam — assert effects instead.
- S16: `game_view.gd:327-329` ungrabs on a click on the held card (contradicts 5.5); a release
  over the container cannot reach PlayArea (root-viewport STOP control vs SubViewport) → GAP
  candidate; 5.6 needs a test rules card (no shipped rule grabs a grid card).
- S17: `card_effect_api.gd` has no subscription surface; the tap reaches effects via
  `Game.run_all_mods(&"on_card_tapped")` with a test-local CardModifierType (precedent
  `test_board.gd:313`).
- S18: Escape is read in `wall.gd:270-273` → `Main._on_back_pressed` (`main.gd:716`): one step
  back on the FocusStack, wall view when empty — there is no 'menu' destination;
  `ungrab_cards()` also hides the description (`play_area.gd:1530`), collapsing the two steps.
- Wall-view picture hover (`Wall.picture_hovered` → `WallPicture.get_info()`) has no destination
  after S9 — Q21=(b) says no sidebar in the overview → it is deleted with Info mode (assumption).
- S19–S23 (plan-auditor): S19's blast radius is ~3x §3a — add `card_effect_api.gd:57,154,177`
  (`draw_deck()/draw_card()/return_to_draw_deck()`), `game.gd:924-941` `return_to_map()` (the run
  deck is rebuilt there — miss it and stock cards leave the run), `skill_grid_allotment.gd:35`
  (grid count from deck size), `skill_hungry_hippo.gd:40`, and eleven test files (notably
  `test_iterator.gd:194-210` asserting collection ORDER and `test_persistence_fuzz.gd:196`).
  §2's `Array[Array[CardData]]` is not an expressible GDScript type (`scoring.gd:919` writes it as
  a comment; `card_data_array.gd` is the wrapper) and a top-level per-slot array drifts from
  `entrance_zone().cells`, which `Board.add_column/remove_column` (`board.gd:235,243`, driven by
  `zone_adder.gd`) mutate — the stock rides the entrance zone's per-cell data (assumption, invisible).
  `on_append` is a shuffle-time hook (`game.gd:429-433`), not a board walk; the walk is
  `get_card_collections()`/`all_card_datas()` (`game_data.gd:412/428`); the stage verifier is
  `validate()` I1/I3/I5 (`:483/:531/:575`). No RunState version exists: 'discarded, not migrated'
  needs a load-time check (assumption). `draw_card()` pops the BACK — today's 'top'. S20 has no
  call site in its two files. S21: `CardVisual` spawns Stage.DRAW cards at `deck_ui`'s centre — now
  a ROOT-viewport control (latent bug since S2: wrong space); flip = `data.flipped` slerped at a
  hard-coded 6.5/s only while `floating`; `deck_viewer.gd`'s sort enums are dead — sort at the
  caller. S22: 'fully resolved' is a code position after `refill_entrance_if_due()` and AFTER
  `save_state()` (`game.gd:774-782`), guarded on `not processing` (re-entrancy `:733-739`);
  `submit_button.visible` is never written — Q107=(c) owner note 'end button becomes revealed
  when either deck empty, or no more possible action on board (no empty tiles)' means End starts
  HIDDEN; `test_game_headless.gd:772-802` asserts a scored line does not resolve (pin its goal).
  S23: hover→container already routed (S5); `map_hover_panel.tscn` EXISTS (leak canary preloads
  it) — 'do not re-instantiate on the map'; `_on_node_hovered` is `map.gd:162`. 4.3's
  `_replay_pending_placement()` dereferences `RunManager.run` unguarded — populate it.

## Phase 2 review (adversarial, Fable 5.1) — all seven fixed in 7fafbfb3
1. CONFIRMED `hud_container.gd` per-screen state (`_entry_by_screen`, `_lock_by_screen`,
   `_locked_entry_by_screen`, `_processing_screen`) outlives a show: a WON show leaves
   `processing` true so the next show's whole first pick has no description; a mid-show Back then
   New Run re-shows the previous show's entry/lock. Nothing resets on `detach_screen`/new run.
2. CONFIRMED leaving the game while locked: `set_active_screen` sets the new screen BEFORE
   `show_hud()`, so `clear_lock` erases the wrong screen's lock while `description_dismissed`
   still drops the board's marking — on return the lock is half-alive (X focusable, marking gone).
3. CONFIRMED (by reading) a remembered entry detached on a mid-cascade screen change and never
   re-mounted is orphaned by the next publication (`_entry_by_screen` overwrite at `:178`).
4. CONFIRMED Q68=b met in flag only: `%ExitX` is FOCUS_ALL when locked but arrows are consumed
   for scrolling and nothing in the root viewport can navigate to it; the test asserts the flag.
5. CONFIRMED preview size baked at publish — a resize/board zoom with a description up leaves it
   stale (Q34=b, Q48=a).
6. SUSPECTED stick scroll rounds to 0 px/frame at low deflection on a short panel — use a
   fractional accumulator.
7. Test shape: the cancel test calls `wall._unhandled_input` directly (item 13); the rebuild test
   compares `locked_data` to a value it set itself.

## Phase 3 review (adversarial, Fable 5.1, at S12) — 5 confirmed, 6 suspected; where each went
1. CONFIRMED a viewer opened from a pile button never returned focus on close (`show_deck` read the
   picture SubViewport's focus owner, always null once an overlay button holds focus) — fixed,
   `show_deck(parent, deck, opener)`, 54317308.
2. CONFIRMED `ChoiceViewer.fit_beside` moved only the near edges: the pack centred half off-screen
   in the top band — fixed, four-edge fit on BOTH viewers (the deck viewer's rows overran too),
   74897f3a.
3. CONFIRMED opening a viewer by pad published nothing (first focus landed before the opener
   wired the relay; ASSUMPTIONS had rationalised it as B4) — fixed, deferred first `grab_focus`,
   54317308.
4. CONFIRMED the start menu's Inspect viewer was neither inset nor publishing — fixed, same rule
   as every viewer through `Menu`, fix dispatch 3.
5. CONFIRMED a viewer was fitted once and never on resize — fixed, re-fit on
   `container_rect_changed` after the board/map inset publish, 74897f3a.
- SUSPECTED: preview re-drawn at the board's size on a rect change (fixed: the viewer re-publishes
  its remembered highlight, 74897f3a); `fit_beside` adding margins (fixed: set from the authored
  margins); the reroll's stale description (reproduced and fixed: `CardsViewer.rehighlight`, fix 3);
  a viewer swap announcing nothing (NOT reproduced — the incoming viewer's opening publish covers
  it; pin test kept); the S9 `card_environment` guard (caller found, guard kept — see State);
  `settings.tres` carrying deleted keys (engine drops them silently; nothing to do).
- Residue: `_key_scroll_pages`, `PlayArea._grid_panel_height`, `PlayArea.get_data_from_control`
  deleted (fix 3); deck_builder's `TypeOption` and skill-Random path deleted (fix 3).
- Observed by the overseer at fix 3: the choice viewer's "Take all"/"Rerolls" chrome was still
  anchored to the picture — fixed in the same dispatch (one `Layout` control insets pack + chrome).
- Plan drift it named: Q34=b's reading inside a viewer → GAP-004; L5's "opacity" exposed as
  nothing (ASSUMPTIONS S11, defensible, for the owner to see); the deck picker's viewer → wired
  (Q140=a + Q143=a make it the consistent reading; ASSUMPTIONS records it).

## Phase 3 re-review of the fix commits (Fable 5.1, at S13) — 3 confirmed, 4 suspected
1. CONFIRMED `HudContainer.disconnect_for_screen()` is one flat list: a GameView teardown (show
   ends, New Run) drops the Map's and Menu's connections too — the map's Deck button dies and no
   resize re-insets map or menu after the first show. Predates the fix range (784f173e). Fix
   dispatch 4: key the list by owner.
2. CONFIRMED the viewer re-fit re-publishes unconditionally, so a resize re-opens a description
   the player dismissed with the X. Fix dispatch 4: republish only while a description is showing.
3. CONFIRMED S12.9 asserts focus on a HIDDEN pile button (a pad close of a viewer while its
   description is up strands the player). Overseer decision (reversible, ASSUMPTIONS): the exit X
   is focusable whenever a description shows; a viewer's close focuses its opener if visible, else
   the X. Fix dispatch 4.
- SUSPECTED: the menu picker's `Dim` (layer 64, STOP) swallows hover/click over the Inspect viewer,
  so the menu's viewer publishes by keyboard only (pre-existing layering) — fix dispatch 4
  reproduces and fixes; two viewers up on the map republish in an order that lets a stale pack
  highlight win (unrun); every viewer open now hides the HUD stack even for a mouse open, so a
  mouse user cannot swap Deck→Discard without closing first — §1.2's exclusive HUD/description
  makes this by design, but the OWNER should look; S12.14's label cites Q34=b for the built
  viewer-size reading (GAP-004) — reworded in dispatch 4.
- Answered: the picker panel drawing over the inspected cards in `menu_inspect.png` is
  PRE-EXISTING on main (picker layer 64 over the viewer's layer 1; the cards measure exactly 0.4x
  under the picker's dim).

## Phase 5 review (adversarial, Fable 5.1, at S18 over 17e9cc1c..8cfb5eee) — 5 confirmed, 4 suspected
1. CONFIRMED a pad/keyboard player's armed card follows the last pushed pointer position (PLAN
   §1.4 literal vs Q249=d's "glow is over where selector is"; TEST_PLAN 9.4 unreachable) → GAP-006.
2. CONFIRMED on touch a tap after a placement was never refused: Godot dispatches the emulated
   mouse form BEFORE the touch, so the closing press re-armed the gesture and reset the depth the
   refusal reads — fixed, `PlayArea._touch_press_depth`, 1925fd9b; the test helper `_touch_tap`
   now pushes events in the engine's order (it was reversed, proving the reader not the route).
3. CONFIRMED Q281=a's "no longer following" after a failed drag lasts one mouse motion (Q262=a
   re-latches) → GAP-007.
4. CONFIRMED a mouse click-lock on a grabbable card dies when the pointer crosses its cell edge,
   before any placement is possible (Q56=a+Q62=b+Q267=a+Q268=a read literally; Q62's own note
   warned of it) → GAP-008.
5. CONFIRMED a cancel mid-drag left `_press_data` armed, so the release fired `card_dropped` with
   an empty hand (try_place stack=0 in the EventLog) — fixed, `PlayArea._end_the_gesture()` is the
   one clearing site, both cancel paths call it, dcc81b8d. The Escape twin was already green (the
   wall's transition lock swallows the release); it ships as a guard.
6. SUSPECTED → NOT REPRODUCED as stated: after Up the focus owner is a board card control and the
   sidebar describes it (`_board_control_has_focus()` holds; pinned by a TestSidebar row). The two
   lines ARE the SmoothScrollContainer's focus stylebox, drawn because a DESCENDANT holds focus
   (`draw_focus_border`; measured: off → lines gone; they also show in description.png, never in
   game_hud.png). Cosmetic, unfixed — OWNER CALL: `draw_focus_border = false` on the board's
   scroll container is the one-line fix if the lines are unwanted.
7. SUSPECTED → REPRODUCED: the refused pair's closing release emitted `data_selected` (a second
   placement) — fixed, a closed pair (tapped or refused) eats its own closing release, fix 4.
8. SUSPECTED → NOT REPRODUCED: root-viewport motion pushed inside the container's rect still
   reached `PlayArea._on_pointer_moved` (pinned by a TestSidebar row: a following card keeps
   following over the sidebar, Q270=a). The engine claim behind it was not verified against docs
   this session; the measurement contradicts it.
9. SUSPECTED → reproduced: a click during processing left `_next_grab_follows` set and the card
   that armed at the cascade's end followed from birth (at the cursor, lift −0.2 vs 18.8) — fixed,
   `stop_following()` clears the pending flag and the dropped-selection path calls it, fix 3.
- TEST SURFACE: `_touch_tap` order (fixed in fix 1); every TestDragPlace event except 5.4 bypasses
  the root GUI pass; `_pa.armed_slot() != -1` at test_drag_place.gd cannot fail for what it names
  (the held/lifted checks beside it carry the row); 5.6/5.7/tap-hook rows ride test-local stamps
  (nothing shipped grabs a board card or listens to `on_card_tapped` — recorded in ASSUMPTIONS).
- PLAN DRIFT it named: 9.4 signed off on a still showing `following=true, glow=false` (GAP-006);
  Q280=a's "drop map" ships with none (GAP-005); Q93a=a was mouse-only (fix 1); after Escape →
  Back → re-enter the board has no armed card until a placement, undo or processing edge (Q115=a,
  built as ruled — owner should see).
- Fix 3's implementer noted, unreported by the review: a refused `try_grab` inside `arm_leftmost`
  also leaves `_next_grab_follows` set; `arm_leftmost`'s body is pinned by 6.3's source test to
  exactly two "grab" occurrences, so the clear cannot live there. Open, low.

## Phase 5 re-review of the fix commits (Fable 5.1, 8cfb5eee..9d69ac1e) — 3 confirmed, 2 suspected
1. CONFIRMED fix 4 does not reach the TOUCH route: `_consume_as_touch_tap` sets
   `_tapped_this_gesture` from `_pair_taps`' answer, false on a refusal, so the refused finger
   pair's emulated release falls through to `_on_gui_input` and places again (finding 7 on touch).
   The touch refusal row spied only `save_history.size()`. → fixed, `PlayArea._close_a_pair()` is
   the one pair-closing site for both readers; the row now spies `data_selected` (fix 5).
2. CONFIRMED (test surface) the finding-6 pin row asserted only `not (owner is ScrollContainer)`,
   which a null owner satisfies → the row asserts the owner is in `ui_data` (null → 4 FAILED),
   fix 5.
3. SUSPECTED fix 4 swallows a legitimate rapid second placement on the SAME cell inside the OS
   double-click interval (place A on X, click X again to stack B) — Q93a=a refuses the TAP, not
   necessarily the click. OWNER CALL: is rapid same-cell stacking meant to cost a wait? Recorded,
   not changed.
4. CONFIRMED `_next_grab_follows` survived a REFUSED pickup (click a board card while nothing is
   grabbable) and the processing-edge arm never ungrabs first: reproduced, the auto-armed card
   born following 550 px off its slot → fixed, the refused pickup calls `stop_following()` like
   the refused drop does (fix 6).
5. SUSPECTED the finding-8 pin row pins the fixture's tree order (container above the board's
   viewport) rather than the product's. Noted; low.
- Fixes 1–3 traced clean on the real routes; no design ids in production code from these commits
  (test-side citations are the standing backlog pattern).

## Phase 6 review (adversarial, Fable 5.1, at S21 over 62a0302f..3a0ce903) — 2 confirmed, 4 suspected
1. CONFIRMED a click or `ui_accept` on the face-down card locks the sidebar to the HIDDEN card's
   own description: `_bind_stack` binds the control to the real top stock card, the hover route
   checks `is_stock_control` but the click/accept routes emit `data_selected` with the hidden card
   and the view locks to it (the pickup is then refused, the lock stays). S21.5's rows only drove
   `grab_focus()`. → fixed, `PlayArea._consume_as_stock_press` gates both press routes on
   `is_stock_control` (S21.5b/c red on HEAD), fix 7.
2. CONFIRMED (engine semantics, then measured red) the face-down card was an arrow stop when its
   slot held no revealed card: the link builder chained `get_child(0)`, and Godot rejects an
   explicit neighbour only at FOCUS_NONE. → fixed, `PlayArea._link_arrow_stops()` chains only
   slots whose top control is not a stock control (S21.7 red on HEAD), fix 8.
3. SUSPECTED a card picked up inside its stagger wait is carried face-down and turns over in
   hand (cosmetic; the rebuild is deferred past `processing`'s release). Not reproduced; noted.
4. SUSPECTED latent: `skill_spotlight_check()` is not awaited before `deal_stocks()`; today no
   `on_spotlight` suspends, so the adders run first. Pre-existing call shape; noted.
5. SUSPECTED `_entrance_slot_of` defaults to slot 0 for a card in no slot (unreachable today).
6. SUSPECTED `sorted_stock_union` dereferences `suit` unconditionally; no suitless card reaches a
   stock today.
- Traced sound: resume-replay determinism (the final permutation is a fixed function of the one
  shuffle: round-robin over the adder-by-adder rebalance), card conservation through park/pour/
  sweep/undo, the flip mechanics, the re-indexed `control_for_coord`, the Q211 readers, Q224.
- PLAN DRIFT: 4.7's "End is not revealed; nothing disarms" was letter-only in S19 (asserted the
  predicate) — S22's 7.5 owns the reveal; the "nothing disarms" half is still owed (fix 7's
  dispatch adds it). No test exercises the old-save refusal (Q224). TEST_PLAN 9.5 still says
  "capped depth" against the mid-run ruling (fold at the close).
- TEST SURFACE: TestUIProps' seed is coupled to the whole bootstrap permutation (moved twice);
  test_grid_cards TP-70 now reads its expectation from `stock_for_slot().back()` so it proves only
  that `draw_card(slot)` pops that slot's back; 4.3's digest compares the union flat (a wrong split
  with the same union would pass). Missing rows: click on the face-down card (fix 7), arrow across
  an empty-held slot (fix 8), old-save refusal, `return_to_map` with a parked stock.

## Phase 7 review (adversarial, Fable 5.1, at S22 over bbc544e7..52f293b9) — 4 confirmed, 2 suspected
One root cause behind 1–3: the goal check's early `return` skipped the placement's `save_state()`,
and the hold beat ran with `processing` false. → fix 9: the winning placement commits (the grid
commitment lift + its own `save_state()`) before the hold, the hold runs locked, the resume path
re-fires the check when a board loads with the goal met and no outcome saved (a resume after
"undo the automatic end, then quit" therefore ALSO lands on the outcome — Q104=a decides it;
OWNER SHOULD SEE), the false comment names the lock. Six checks red with the fix neutralised.
GRID CARDS TP-122 and LEAK CANARY phase 4 had passed only because the automatic end masked them
(pinned out of reach). Open observation: a two-suite `--filter TestGameHeadless TestEntranceStocks`
run showed a teardown-only 0xC0000005 after its banner, never alone and never in the full run.
1. CONFIRMED the hold is an open window: the re-arm fires, Undo is enabled and pops the
   PRE-placement snapshot, then the timer's `end_show()` resolves the rewound board as a LOSS; a
   second placement inside the hold runs its cascade under the outcome screen. → fix 9.
2. CONFIRMED a quit inside the hold resumes onto a live/locked board with the goal met: only the
   pre-placement board plus the `on_placement` marker are on disk; the replay runs with
   `processing` true, so the goal check is skipped and the refill runs. → fix 9 (the check must
   re-fire on resume when the outcome was never saved).
3. CONFIRMED undo after an automatic end rewinds the WINNING PLACEMENT too (history holds
   pre-placement, ended — the post-placement snapshot was never written); Q109=a "exactly as a
   manual one" not met. 7.3 never asserts the winning row survives. → fix 9.
4. CONFIRMED (dormant) the comment "an effect's nested placement is part of the act" is false:
   `on_card_placed` handlers run with `processing` false, so a nested `place_card_in_grid` enters
   as a player placement with its own goal check. No shipped handler exists. → fix 9 (comment).
5. SUSPECTED → REPRODUCED (the `visible` flag, not the screen: every flash frame precedes the
   GameView, so the cause was `%Submit`'s authored default in `hud_container.tscn`, not the
   zero-grid `grids_are_full()`) → fixed, the authored default is hidden; the bare-wall
   reachability test forces Submit visible to measure geometry (fix 10).
6. SUSPECTED → REPRODUCED: `end_show()` puts the outcome up while `play_area.selected_cards`
   still holds the armed card (red: "the resolved show holds no armed card"; the test is in the
   P7REPRO evidence file, not the tree). → fixed, `GameView._on_show_resolved` ungrabs through
   the existing `ungrab_cards()` BEFORE `disable_board_focus()` (measured: the reverse order
   breaks TestInteraction's game-over focus check, since a rebuild births FOCUS_ALL controls),
   fix 11.
- TEST SURFACE: `test_e2e_run.gd` still prints "a show never resolves on its own" and
  `test_end_show_is_the_only_resolver` keeps its name — both true only because their goals are
  pinned to 10^8/10^6 (re-aim their text at the close); `test_full_board_does_not_end_the_show`
  proves only the trivial half (total 0); 7.5 drives `revision` by hand (the real edges bump it
  by reading). A fixture that WOULD prove 7.2's position: a test-only modifier whose
  `on_card_placed` adds score.
- Clean: `_refresh_end_reveal` one writer, rebound on state swap; the Goal colour through
  `PaletteDB.ROLES.goal_met`; `end_show()`'s save-before-resolve for a post-timer quit.

## Re-review of the Phase 6–7 fix commits (Fable 5.1, 82c6d15f..9a9bcd16) — 2 confirmed, 4 suspected
1. CONFIRMED the REPLAY route still skips the placement's tail: quit mid-cascade of the winning
   placement → resume → `_replay_pending_placement` → `place_card_in_grid` with `processing` true
   → the goal branch is skipped, the refill runs on the won board, `save_state()` is skipped, then
   `_end_show_if_goal_met()` writes the only post-placement snapshot as ended → undo at the
   outcome rewinds the winning placement (Phase 7 finding 3 re-opened on this route). The resume
   row sets `pending_action = ""` and never walks it. → fix 12.
2. CONFIRMED a replayed NON-winning placement leaves the board LOCKED and its marker uncleared
   (`_commit_placement` skips `save_state()` under `processing`, nothing unlocks; every later
   resume replays it again) — pre-existing shape, re-authored by fix 9. → fix 12 (same root: the
   replay must run the placement's tail — commit, unlock, goal check).
3. SUSPECTED undo after the automatic end arms a card of the POPPED state: `undo()` writes
   `processing = false` (synchronous `processing_changed` → `_arm_the_entrance`) BEFORE the
   history pop; if `try_grab` does not yield a frame, `selected_cards` holds a stale CardData and
   nothing is armed until Escape. → reproduce with a real view after fix 12.
4. SUSPECTED Back during the locked hold: `_cancel_everything` is not gated on `processing`; the
   wall steps back with the Game alive and the timer ends the show off-screen. Probably benign;
   untested.
5. Test surface: S21.7's "selection stays" check passes because the geometric fallback finds
   nothing to the left in that fixture; the "reaches slot 3 over an emptied slot 2" check carries
   the row. Test check strings carry plan row ids ("(S21.5b)", "(7.3)") — the standing test-side
   pattern doc_check accepts; production code is clean.
- Fixes 7, 8, 10, 11 and the card back traced clean on the real routes.

## Phase 8 review (adversarial, Fable 5.1, at S23 over 9a9bcd16..eb635e79) — 4 confirmed, 3 suspected
1. CONFIRMED the popup detaches from its dot: `show_above` places once (the only call, on hover)
   and nothing follows the node through travel (the camera follows the token every frame), a
   drag-pan, a wheel zoom or a resize — the label floats over empty map. S23.2 moves only the
   pointer. → fix 13.
2. CONFIRMED the popup never hides: nothing writes `visible = false`; a New Run regenerates the
   map under the old label at its old position; entering a show leaves the label on the map
   picture. ASSUMPTIONS' "mirrors Q133a=c" overreaches. S23.7 cannot fail (the game fixture never
   hovers a map node) and the real sequence would fail. → fixed with 1: the popup holds its node
   and re-places itself against `WorldMapController.node_screen_rect` (now static) every frame
   it is up (the camera is written per frame during travel, so no notification covers it);
   `hide_name()` on run start, on node entry, and on the new no-argument
   `HudContainer.active_screen_changed` signal (one listener, the map). S23.7 rewritten to hover
   first, then enter. Fix 13.
3. CONFIRMED touch pan of the map is lost: the swallow of every `device == -1` mouse press runs
   before `_pressed` is set, and `_pressed` has no other writer, so a one-finger drag never pans
   and only hovers dots under the finger. Scope: the map only. → fixed: the first-tap rule
   consumes only the emulated release that closes a press which never crossed the map's own
   `DRAG_THRESHOLD`, so a travelled finger pans as a mouse drag does; S23.4 reordered to the
   engine's dispatch order (outcome unchanged). Fix 14.
4. CONFIRMED `DescriptionPanel.resize_to` counts the previous entry's queue-freed visual (still a
   child until end of frame): pack → show leaves a grid-sized blank scroll area; pack → pack sums
   both flows. → fixed: the previous visual leaves its slot (`remove_child`) before `queue_free`,
   so the slot's minimum size is honest; the pack → pack row asserts the laid-out content height
   because the scrollbar's extent lags a re-mount by a frame (recorded in ASSUMPTIONS). Fix 15.
5. SUSPECTED `_tapped_node` is never cleared by mouse hover or `start_run`, so mouse-hover A then
   finger-tap A describes again instead of entering. Defensible under K5; noted.
6. SUSPECTED popup unclamped at the top edge (already "owner should see").
7. Evidence counts: the implementer's 4715 vs the overseer's 4680 on the same tree — the check
   TOTAL drifts (data-dependent suites); the failure set was empty in both.
- PLAN DRIFT: K2 "stays put" not met under camera motion (1); K5 built but touch pan regressed
  (3); the popup's lifetime across New Run is un-ruled (2); six names without a NAMES entry
  (`node_screen_rect`, `_travel_to`, `_consumed_as_touch`, `_tapped_node`, `%GridSlot`,
  `_slot_for`) — in ASSUMPTIONS.
- TEST SURFACE: S23.7 cannot fail as written; S23.4 pushes touch-first (the reverse of the
  engine order the code claims — same outcome because the swallow is unconditional); S23.5's
  "hovering a preview card changes nothing" is trivially true (nothing listens); S23.2 untested
  under camera motion; no test for the popup after New Run / screen leave / resize, or for
  `resize_to` after pack → show.
- Clean: `_slot_for` routing (only one FlowContainer visual exists), the wall's `device`
  forwarding, the touch swallow's scope, the keyboard path, Q136/Q139.

## Gaps
- GAP-008 (open, OWNER CALL, not blocking) — a mouse click-lock on any grabbable card is dismissed
  by the motion a placement needs; options a/b/c in the file, recommendation (a).
- GAP-007 (open, OWNER CALL, not blocking) — after a failed drag the card is "no longer following"
  for exactly one mouse motion (Q262=a vs Q281=a); recommendation (a): re-latch only on a new press.
- GAP-006 (open, OWNER CALL, not blocking) — a pad/keyboard player's armed card follows a mouse
  position nobody is controlling (PLAN §1.4 vs Q249=d; 9.4 unreachable); recommendation (b): a
  key/pad focus does not start following.
- GAP-005 (open, OWNER CALL + plan hole, not blocking) — the legal-cell highlight (Q24=a, Q124=a,
  G12, "the drop map" of Q280=a) does not exist in the code and has no visual design; TEST_PLAN §11
  claims G12 covered and it is not. Options a/b/c in the file; S16 builds release-to-place on
  `try_place` legality with no visual.
- GAP-004 (open, OWNER CALL, not parked) — inside a viewer, is the description's preview drawn at
  the board's card size (Q34=b literally) or the viewer's own (built)? One line per viewer either way.
- GAP-001 (open, non-blocking) — a 16:9 window wider than 2560 px clamps, so "394 at any 16:9" fails
  there. S3 builds §1.1 as written; gate checked at TEST_PLAN 3.1's fixtures.
- GAP-002 (open, CONTRADICTION, parked thread) — §1.1's inset ignores the covering picture's crop, so
  on windows narrower than 1576:887 (16:10, 4:3) the board's region starts under the container
  (measured −70 px at 1920×1200). The portrait spill was a bug, fixed (3d858441).
- GAP-003 (open, CONTRADICTION, not parked) — D11's 'the map has no picture' is false; the code
  converts through the picture scale and camera zoom (ruling a). Needs D11's text corrected.

## Tasks
```yaml
- id: S1
  description: HudContainer + DescriptionPanel empty shells, show_hud/show_description swap
  status: done
  evidence: 'full suite ALL 46 SUITES: 3997 CHECKS PASSED (log mtime 17:48, overseer-read); SIDEBAR: ALL 9 CHECKS PASSED == 9 check( calls; no lock_to/GameHud/MapHud yet; extends PanelContainer + StyleBoxFlat'
  notes: 'container bg is a hardcoded colour (+1 PALETTE placeholder, 23->24) - S2 routes it through the palette'
- id: S2
  description: move the HUD controls into HudContainer; delete %MultScore (+3 children) and %Preview
  status: done
  evidence: 'S2d d53f8261: ALL 46 SUITES 4069 PASSED [22], SIDEBAR 80; overseer LOOKED at user://sidebar_snapshot/game_hud.png - Goal/Total legible below the overlay buttons, piles row, Undo/End, board centred beside the container. S2c 3123530c: ALL 46 SUITES 4034 PASSED, TestSidebar 57 checks, red-then-green per test. S2a 2b88ea90: ALL 46 SUITES 3981 PASSED [23 placeholders]; pre-change board_inset_left 394.0, _hud_authored_width 402.0, board centre (scroll_container.position.x + size.x/2) 733.808. S2b 07aa305f: ALL 46 SUITES 3979 PASSED [22 placeholders], godot.log 0 SCRIPT ERROR'
  notes: 'Tests/Visual/sidebar_snapshot built here (ahead of S11) - boots Main, enters the game, writes user://sidebar_snapshot/game_hud.png; run with the NON-console exe and wait for exit'
- id: S3
  description: geometry per PLAN 1.1; add board_inset_top; delete pan_window_left_x
  status: done
  evidence: '03e85767: ALL 46 SUITES 4076 PASSED [22]; SIDEBAR 109. 3.1 394+-0.5 at 1280/1920/2560 wide, 3.2 262.7 at 3840x1080 flush inner, 3.3 top case; red-then-green logged per check (clamp, max->min [only 3.2 catches it - min==max at 16:9], top branch, resize hook, HUD overflow). grep of removed names: nothing. By eye 1280x720: 320 px container, HUD inside, board beside it'
  notes: 'Top case (600x1000) board spills under the band - GAP-002, parked. The Entrance/grid offset check cannot fail for the neutralisations tried (test-surface review at close). The Entrance x in any still is MID-DEAL-ANIMATION (measured -165..-30 px vs grid across captures; layout rule is identical to main) - sidebar_snapshot must wait for the deal to settle; fold into S5 which extends it'
- id: S4
  description: the map gets the same container (Fame, Lap, Luck, Deck)
  status: done
  evidence: 'commit after 5b8f84b9: ALL 46 SUITES 4151 PASSED [22]; SIDEBAR 148; tests a-e + menu aspect/centring red-then-green (s4 evidence); by eye at 1280x720 menu centred beside the container, map start node x~800, game screen unchanged'
  notes: 'menu and wall-overview rules landed here too (Q22=b, Q21=b). GAP-002 also applies to the map on windows narrower than 16:9 only if map content sits under the band - unmeasured'
- id: S5
  description: route PlayArea.info_requested into HudContainer; description content
  status: done
  evidence: '16f107a5 + 7904d1c7: ALL 46 SUITES 4180 PASSED; 1.2/1.3/1.14 red 17 -> green; by eye description.png: name beside a board-sized preview, body below'
- id: S6
  description: lock, follow, the four dismissals, exit X
  status: done
  evidence: 'S6a e9e1754f + S6b: ALL 46 SUITES 4282 PASSED [22], SIDEBAR 303, exit profile = the two standing lines + 135 ObjectDB; red-then-green per test logged; by eye description_locked.png (X, lifted locked card) and description_follow.png (hovered card shown, locked card marked)'
  notes: 'the fourth dismissal (card leaves its cell while following) and TEST_PLAN 1.8 are owed by S14 (need following). S6b shipped a production leak (a displaced lock orphaned its visual) caught by the leak probe and fixed with a regression check'
- id: S7
  description: the processing rule
  status: done
  evidence: '6d4d9b8c: ALL 46 SUITES 4336 PASSED; 1.9-1.12 red 10 -> green; SIDEBAR 342; by eye description_processing.png: HUD only mid-cascade'
- id: S8
  description: scroll and multi-modal reach, sidebar_scroll action
  status: done
  evidence: 'ALL 46 SUITES 4337 PASSED (overseer run, alone); 7 new tests red -> green; SIDEBAR 372; by eye description_scroll.png'
  notes: 'at the shipped container width no card text overflows at any window - the scrollbar is real but idle until descriptions grow (Q36=c later design)'
- id: S9
  description: delete Info mode
  status: done
  evidence: '0d323d8c: ALL 45 SUITES 4249 PASSED; wall_info grep empty; suite count 46->45 (TEST_PLAN 8.4 >= 45)'
- id: S10
  description: delete the in-board popup
  status: done
  evidence: '5ca37f5f: ALL 45 SUITES 4257 PASSED; _focus_info/wall_screen_popups grep empty; by eye no popup in description.png'
- id: S11
  description: replace test_wall_info / wall_info_snapshot / the wall editor Info panel
  status: done
  evidence: 'S9 (tests) + S11 commit: ALL 45 SUITES 4264 PASSED; WALL EDITOR SOAK 83 checks 0 problems; by eye wall_editor_sidebar_locked.png'
- id: S12
  description: migrate the deck/discard/rules/choice viewers to the sidebar
  status: done
  evidence: '7f6a2219: ALL 45 SUITES 4287 PASSED [21]; SIDEBAR 404 -> 432 (S12.1-S12.7, 28 checks); red: relays removed 9 FAILED, insets/close/panel/deck_builder neutralised 6 FAILED; CardInfo grep in choice_viewer.* empty; doc_check 0 of 221 on added lines; by eye viewer_description.png (deck viewer grid from ~x396 beside the 320 px sidebar, the hovered viewer card described) and choice_viewer_description.png (pack row beside the sidebar); map_hud.png start node still ~x800 after the inset refactor'
  notes: 'ASSUMPTIONS records: preview at the VIEWER''s card size (Q34=b read as the object pointed at); viewers publish highlights only, no lock; close announces highlight_cleared; OPENING a viewer publishes nothing (first focus lands before the relay is wired) - flagged to the Phase 3 review; the deck picker''s Inspect viewer on the start menu is NOT wired (Q143=a, 3a names neither menu.gd nor deck_picker.gd); new names InfoEntry.relay_to, HudContainer.rect_beside/window_scale, WallPicture.window_scale, CardsViewer.card_window_px, DeckViewer/ChoiceViewer.fit_beside, GameView.wall_picture/_open_deck_viewer. main.gd touched beyond 3a (enter_game hands the picture to the view). A second todo.md item (deck_builder broken preloads) closed with Q166=c. Phase 3 review fixes (three dispatches, one commit each) followed - see the State line and the Phase 3 review section'
- id: S13
  description: GestureMetrics, delete DPI and the six mm/px knobs
  status: done
  evidence: 'bb2484db: ALL 46 SUITES 4356 PASSED [21]; suite count 45 -> 46 (TestGestureMetrics rows 2.1-2.6 + 8.3, 14 checks); hard gate grep dpi|DPI|mm_to_px empty outside archive/addons; six knob names resolve nowhere outside design docs; red: model neutralised 5 FAILED, clamp/density put back 2 FAILED, WallInput stops delegating 7 FAILED, swipe stops asking the model 3 FAILED, a knob put back 1 FAILED; doc_check 0 of 1014 on added lines'
  notes: 'new name PlayArea.board_card_picture_px() (the swipe travel is in picture space, so board_card_window_px was the wrong space; the window helper now derives from it) - ASSUMPTIONS. Four production touch_target_px call sites, not three (the exit X). PICTURE_WALL.md wiring row kept with its new reason (Q306=a)'
- id: S14
  description: split held from following on CardVisual
  status: done
  evidence: '4a008669: ALL 46 SUITES 4410 PASSED [21]; SIDEBAR 89 -> 97 tests (6.4-6.9, 1.7 fourth dismissal, 1.8); red per neutralisation 8/2/3/8/3 FAILED; lift 18.3 held vs 18.2 following (non-zero, equal); doc_check 0 of 775 on added lines; by eye card_lifted.png (raised in its slot) and card_following.png (riding over the grid, same lift)'
  notes: 'no lift quantity existed for a HELD card (a grab never called anim_jump) - the jump rise card_jump_rise_play is applied in both states, no new knob (ASSUMPTIONS). Q267=a lands behind try_grab''s await, so the click sets PlayArea._next_grab_follows and grab_cards consumes it. OWNER SHOULD SEE: Q56=a + Q62=b + Q267=a together mean a click-lock on a grabbable card is dismissed the moment the pointer leaves that card''s cell (the click also grabs, and a clicked card follows at once); four S6 tests now lock through _lock_without_holding(). New names: CardVisual.held_lift_px/cursor_ride_offset, PlayArea.follow_cards/_on_pointer_moved/_origin_cell_rect/_next_grab_follows'
- id: S15
  description: arming through the pickup path
  status: done
  evidence: 'a5449e77: ALL 46 SUITES 4452 PASSED [21]; SIDEBAR 97 -> 109 tests (6.1, 6.2, 6.3 effects + source pin, 6.10, Q251/Q116/Q118/Q114/Q115/Q119/G1); red per neutralisation 9/6/12/9 FAILED; no armed field; arm_leftmost has one production caller (GameView); doc_check 0 of 817 on added; by eye game_hud.png (leftmost card lifted+brightened at the deal, HUD up), armed_focus_elsewhere.png'
  notes: 'GAP-005 filed (legal-cell highlight never built, no visual design - owner look call; parked = the visual only). Q123=b board-card test NOT written: nothing outside the Entrance can be picked up today (only TypeInput has on_can_grab_stack) - S16 5.6/5.7 need a test-local grabber. S14 cell-leave became a CROSSING of the origin cell (a position test dismissed on every move once a card is always armed). Undo held-cards guard deleted (always true now). _publish_focus_left_cards assert -> guard naming the teardown case. OWNER SHOULD SEE: (1) TEST_PLAN 9.4 "lifted, glowing, focus elsewhere" is unreachable after any input - a key focus or any mouse motion latches following (Q262=a), so the armed card rides the MOUSE position even when the player is on keyboard (section 1.4 targets get_global_mouse_position); (2) armed_focus_elsewhere.png shows two horizontal lines across the board area of unknown origin - handed to the Phase 5 review'
- id: S16
  description: click versus drag, release-to-place
  status: done
  evidence: '99644d39: ALL 47 SUITES 4470 PASSED [21]; suite 46 -> 47 (TestDragPlace 5.1-5.7, 31 checks); red per neutralisation 1/7/1/1/3/4 FAILED (the 1 for wall routing removed is exactly 5.4 - the container release measurement); doc_check 0 of 1614 on added; LF verified at byte level after a CRLF scare; by eye drag_release_returned.png (card back in its slot, lifted, not following)'
  notes: 'Q288=a needed NO new forwarding: a press on the board sets no gui.mouse_focus in the root viewport, so the release over the container reaches Wall._unhandled_input and rides WallInput.route into the picture (the earlier "gap candidate" was a misunderstanding of the engine, not a gap). The click is decided at the RELEASE. 5.1''s discriminator is the description LOCK (only the click route locks). A held card''s control is MOUSE_FILTER_IGNORE so no tap reaches the card in hand - 5.5''s toggle half is driven by key accept. 5.6/5.7 ride a test-local STAMP. New: Tests/Support/test_main_host.gd (TestSidebar''s _boot_main_at moved there). ⚠ Path.write_text on Windows rewrites sources to CRLF - the implementer''s neutralise driver now writes bytes; two source-reading test gates (registration, 6.3''s source pin) break on CRLF'
- id: S17
  description: tap — double-click, card_tap action, card_tapped signal, one dummy effect
  status: done
  evidence: 'bf4b2b70: ALL 47 SUITES 4516 PASSED [21]; DRAG PLACE 31 -> 63 checks (S17.1-S17.8, overseer-defined rows - TEST_PLAN has none for S17/S18); red per neutralisation 8/2/3/5/4 FAILED; card_tap action, card_tapped signal, card_tap_window_ms knob, on_card_tapped dispatched only from GameView, nothing under Cards/ listens; doc_check 0 of 683 on added lines; LF verified'
  notes: 'card_tap binding: key T + joypad button 2 (X) - NAMES fixes the name only. The refusal after a placement compares the board''s committed depth at the pair''s opening press vs at the tap; the bound action is exempt (no first press). A tap eats its closing release (else the second release re-grabs). The dummy effect is a test-local STAMP recording instance ids (holding the card leaked). New: TestSuite.await_the_tap_window() - an INTERACTION check whose two accepts now pair as a tap waits it out (Q98=d working). card_effect_api.gd unchanged (no subscription surface; run_all_mods forwards any hook)'
- id: S18
  description: cancel — held card first, description second, Escape cancels everything and takes the existing Back step
  status: done
  evidence: '8cfb5eee: ALL 47 SUITES 4545 PASSED [21]; S18.1-S18.5 in TestSidebar, red per neutralisation 3/3/2/10 FAILED; done-when grep: same signals, only the view''s set_input_as_handled removed; doc_check 0 of 571 on added lines; LF verified; by eye cancel_first_press.png: five Entrance cards flat at equal height, the locked description (name, preview, Knife text, exit X) still up'
  notes: 'PlayArea._cancel_one_step (second button, consumed) and _cancel_everything (ui_cancel, NOT consumed so Wall.back_requested fires on the same press). ungrab_cards never hid the description - the collapse was in the placement path. 1.7''s cancel row lost its second-press half: the first Escape starts the wall''s locked transition, so a second press is inert by design. Fix 2 later added PlayArea._end_the_gesture() so a cancel also ends the press gesture'
- id: S19
  description: per-slot Entrance stocks replace draw_deck; every walker updated
  status: done
  evidence: 'fde80a92: ALL 48 SUITES 4594 PASSED [21]; suite 47 -> 48 (TestEntranceStocks 4.1, 4.2, 4.3, 4.7, 4.8; 14 checks); red per neutralisation: flat deal 3 FAILED (4.1 sizes [23,0,0,0,0], 4.7 x2), RNG in the deal 1 FAILED (4.2), walker skipped 1 FAILED (4.8 on_append 0); draw_deck grep outside archive/: only CardEffectApi.draw_deck()/return_to_draw_deck() (the flat union view); no new RNG site; doc_check 0 of 1472 on added lines; LF on all 31 files'
  notes: 'Stocks ride the Entrance zone''s per-cell data (GridData.stocks) so the slot set and the stock set cannot disagree. Game.deal_stocks() runs twice at show start (inside add_deck before the zone adders exist, then after the first spotlight sweep - the real deal and S20''s seam); add_deck is now a coroutine. Board.remove_column carried a slot''s stock out with its orphans (S20 replaced that with parking). Old saves refused through RunState.stock_format (RunManager._drop_unrebuildable_show for Game._resume_show). test_iterator TP-15 and test_grid_cards TP-70 re-aimed (stocks first, then the board; each slot takes its OWN top); TestUIProps seed 424242 -> 424243 (the deal hands that row different cards). TestGridFixtures.draw_any() added. All eight in ASSUMPTIONS'
- id: S20
  description: rebalance on slot add/remove, tops never move
  status: done
  evidence: 'commit after 62a0302f: ALL 48 SUITES 4600 PASSED [21] (implementer) - overseer run recorded in the commit; TestEntranceStocks 14 -> 20 checks (4.4, 4.5, 4.6 through the REAL seam: spotlighting/unspotlighting a SkillAdderInputUpper); red per neutralisation: tops-not-bottoms 2 FAILED, re-deal 3 FAILED, rebalance on exhaustion 1 FAILED, production caller deleted 2 FAILED; rebalance_stocks grep: one definition (game.gd), one production caller (card_effect_api.gd add/remove_column when the zone is the Entrance), tests never call it; no new RNG; doc_check 0 of 638 on added lines; LF on all six files'
  notes: 'S20 - Board.remove_column PARKS the removed Entrance stock at the end of GridData.stocks (Board is static and holds no Game); a parameterless rebalance_stocks() pours the slotless stock into the survivors'' bottoms then pulls bottoms from over-share slots into the leftmost short slot until every slot holds deal_stocks()''s share. TestUIProps seed moved again 424243 -> 424245 (the bootstrap''s adders now rebalance as each slot appears) - the fixture depends on the deal permutation; a candidate for the test-surface review at close. Five private names + three test helpers in ASSUMPTIONS'
- id: S21
  description: the flip - one face-down card implies the stock; flip in place, staggered; no fly-in; stock hover describes the slot; deck viewer shows the sorted union
  status: done
  evidence: 'commit after b2c3bb59: implementer ALL 48 SUITES 4628 PASSED [21]; overseer run in the commit; S21.1-S21.6 + S21.4b red-then-green (N1 deck-button spawn restored 1 FAILED in the wrong SPACE (-3.18,121.78) vs slot (830.54,699.16); N2 refill an occupied slot 1 FAILED; N3 zero stagger 4 FAILED; N4 entity per stock card -> red; N5 publish the card not the slot 2 FAILED with the hidden card''s text; N6 unsorted union 2 FAILED); deck_ui grep in card_visual.gd empty; entrance_flip_stagger defined once, read at one production site; cap knob gone; doc_check 0 on added lines (after the brief''s path fix); LF by bytes; by eye entrance_stocks.png: five slots, one revealed card over ONE blank face-down card each, nothing deeper, leftmost lifted; entrance_flip_mid.png: leftmost face-up, the four to its right still turning at successive phases over their face-down cards'
  notes: 'OWNER RULING mid-step (see Owner rulings): one face-down card per non-empty stock, no entities for unrevealed cards, the face-down flips up in place and a fresh one appears beneath; entrance_stock_face_down_cap DELETED. Face-down-ness is CardVisual.face_down (not CardData.flipped, so saves and the viewer are untouched). CardVisual.on_stage_changed''s DRAW branch (fly to the Deck control) deleted - a card dealt into a stock hit it and freed its own visual. control_for_coord re-indexed (its old z+1 was already wrong for the reversed stack); _apply_row_openings via _control_height. Face-down controls FOCUS_CLICK. The 6.5 flip-rate literal untouched (pre-existing, no knob named). DESIGN chart I8 / Q217 / Q244 / Q245 need the owner''s correction at the close'
- id: S22
  description: automatic end on goal; End starts hidden and is revealed when every stock is empty or no cell is empty
  status: done
  evidence: 'commit after bbc544e7: implementer ALL 48 SUITES 4636 PASSED [21] (and 4654 before the snapshot edits); overseer run in the commit; 7.1-7.4 in TestGameHeadless, 7.5 in TestSidebar; red per neutralisation: goal check deleted 4 FAILED, fired mid-cascade 4 FAILED, undo skips the flag 2 FAILED, end on a full board 1 FAILED, End always shown 3 FAILED; has_met_goal read at the post-cascade position (game.gd) and by the label (game_view.gd); submit_button.visible written from ONE site (GameView._refresh_end_reveal); doc_check 0 of 649 on added lines; LF by bytes; by eye goal_met.png: Goal value green beside a white Total, no End button (Undo alone), board settled'
  notes: 'The check sits between on_card_placed and refill_entrance_if_due() and RETURNS, so an ended show never refills (Q101=a, not c). The pause reuses spotlight_hold_fraction of get_delay() through Pacing.wait (no new knob). Goal met colour = new PaletteRoles.goal_met (index 9, bright green). HONEST LIMIT 7.2: every line in the fixtures scores inside the mutation broadcast, so it proves "after all scoring, before the placement''s tail". Four existing tests had their goals pinned out of reach (a real consequence of the automatic end), each says why at the site. Q102b/Q102c/Q106b unanswered - skipped branches'
- id: S23
  description: the map's name popup and sidebar; first touch tap describes; booster previews wrap
  status: done
  evidence: 'commit after 9a9bcd16: implementer ALL 48 SUITES 4715 PASSED [21]; overseer run in the commit; S23.1-S23.7 in TestSidebar, red per neutralisation 5/5/1/1/2/2 FAILED (S23.7 by construction); map_name_popup.gd/.tscn exist, owned by map.tscn''s $UI (%NamePopup), no MapNamePopup on the board; no new loader of map_hover_panel.tscn (the leak canary''s preload is the only one, as at HEAD); doc_check 0 of 30 on added lines; LF on all files; by eye map_popup.png: "Talent pack" popup above its node, the sidebar with name, biome, body and a wrapping preview row'
  notes: 'Q135=(a) built; chart K9 contradicts it (stale, fold at the close). WorldMapController first-tap-names / second-tap-enters reuses play_area.gd''s device == -1 discrimination and swallows the emulated mouse press (it arrives first). DescriptionPanel gained %GridSlot + _slot_for(): a FlowContainer visual mounts below the body at full width, routed by TYPE. TestSidebar''s Main fixture split into _start_map_fixture/_start_game_fixture. The popup keeps the last node''s name after the pointer leaves (mirrors Q133a=c; not explicitly ruled - owner should see). OPEN BUG seen by eye (pre-existing, reproduced under HEAD''s mounting): preview cards below the sidebar''s fold draw their modifier art past the ScrollContainer''s clip while their frames are clipped - the FX attachment nodes escape the clip. map_popup.png catches the wall''s focus transition mid-flight (the same still rendered at two rects from identical code) - a settled capture should await the transition before _capture. The popup is not clamped: at the picture''s top edge the name clips off (Q131=b asked for no clamp) - owner should see'
```

## Open bugs
- TestSidebar `Fix 13.1: the pan moved the node on screen` failed once in the full run after
  close fix 1: identical screen positions before and after the test's pan, so the camera did not
  move and the follow checks after it passed vacuously. Close fix 1 touches only `undo()`'s
  order. Measured: 1 failure in 4 runs (three `--filter Sidebar` reruns all passed 704 checks).
  The test's pan is timing-dependent; the row should wait for the camera to move before it
  measures (test-surface item 8's two-frame settle trap). Fix it with close fix B.
- Preview-card FX art escapes the description panel's scroll clip below the fold (seen in
  map_popup.png; pre-existing, reproduced by S23 under HEAD's mounting). Owner should see.
- GRID VIEW `one more pan-right at the board's end does not move the camera past it` failed once
  by 0.018 px (edge 545.640 vs 545.658) in ~14 branch runs; green on the rerun. Pre-existing
  camera-settle timing, not touched by this run. Quote the denominator if it recurs.

## Close (S24) — each numbered item of "Closing the run", with its output
1. `py .claude/tools/doc_check.py` FULL: `66 living docs + 314 source files checked - 0 error(s),
   9 warning(s)` after fixing the one error (this handoff's resume prompt hard-coded the worktree
   path). The 9 warnings are the repo-wide comment backlog counts (5336 indented, 2021 long doc,
   699 long block, 556 trailing, 363 design id, 130 dated, 87 history, 54 restated, 4 line ref) —
   the owner's deferred legacy-comment pass, not this run's.
2. `adversarial-review` over `main...HEAD` (Fable 5.1, read-only) — 3 confirmed, 4 suspected:
   (1) CONFIRMED undo at any outcome screen: `undo()`'s resolved branch writes `processing =
   false` BEFORE the history pop, the false edge arms the leftmost card of the state about to be
   discarded (`try_grab` never suspends), the rebuild keeps `selected_cards`, and the next click
   on an empty cell places that phantom — `Board.place_in_cell` finds it nowhere and appends it,
   the card is now in the grid AND the Entrance, and `return_to_map` sweeps both copies into the
   run deck permanently (re-review 3, now traced) → close fix 1.
   (2) CONFIRMED the map's and menu's sidebar memory survives New Run / Continue: only
   `GameView._exit_tree` calls `release_screen`; the next run's map opens on the old run's node
   description (Phase 2 finding 1's shape, fixed for the game screen only) → close fix 2.
   (3) CONFIRMED a drag that starts on a card the board REFUSES to grab (a grid card, or an empty
   cell's zone card) still places the ARMED card at the release point; a drag from bare board
   places nothing → close fix 3 (only a drag whose pickup was accepted places).
   (4) SUSPECTED a pad player who dismisses a description through the X is left with no focus
   anywhere (the HUD lives in the root viewport since S2; the board only re-focuses from the
   mouse, the one-shot rest, or the overview); same after an outcome undo → reproduce.
   (5) SUSPECTED a replayed placement of the LAST Entrance card leaves nothing armed after its
   refill (the replay route has no re-arm tail). (6) SUSPECTED Back during the winning hold
   resolves the show off-screen; the map's `_start_show` then overwrites `pending_node_id` before
   the old show's `return_to_map` resolves (re-review 4). (7) SUSPECTED `sorted_stock_union`
   dereferences `suit` (no suitless card reaches a stock today).
   PLAN DRIFT: 7.3 met in letter (headless); per-screen memory never scoped to the run; S16 built
   "any drag from a card control" not "the held card"; Q68=b's return trip to the board unbuilt.
   NAMES.md resolves except the plan's deletions and the overruled cap knob.
3. `/code-review` high — run as its eight angles serially in ONE read-only Fable reviewer (the
   skill's eight parallel finders exceed the two-subagent cap), filed through ReportFindings:
   10 findings, 4 CONFIRMED / 6 PLAUSIBLE. CONFIRMED: (a) `HudContainer.show_hud()` never
   erases the remembered entry, so a description dismissed with the X (or taken down by a
   placement) re-shows on leave-and-return → close fix 4; (b) `CardVisual`'s DISCARD/RULES
   fly-to still reads a ROOT-viewport control's centre inside the picture (the DRAW branch was
   deleted for that reason; `api.discard_data()` callers reach it) → close fix 5; (c) the popup
   calls `reset_size()` every frame it is visible → close fix 6 (with the simplify residue);
   (d) 24 in-method comments relabelled `##` in game_view.gd (+main.gd:601, game.gd:828-830 a
   column-0 block mid-body) to dodge the indent rule → close fix 6. PLAUSIBLE: the overlay's
   touch targets are sized once at launch while the exit X follows resizes; Undo runs two
   concurrent `_arm_the_entrance` coroutines (a mechanism for re-review 3 — close fix 1's
   reorder removes the edge before the pop; reproduce the double grab after it); the board lock
   doubles as the player-vs-effect discriminator (altitude; recorded, not changed);
   `_next_grab_follows` is cross-await board state the pickup route should carry (altitude;
   recorded); a speculative listener guard in `_publish_stock_info`; seven
   `get_node(%HudContainer)` lookups in main.gd and the `WallInput.touch_target_px` pass-through
   → close fix 6.
4. Test-surface review (Fable 5.1, `tests-that-prove-nothing` as checklist) — 4 confirmed, 8
   suspected/minor; none of the run's production names has only test callers:
   (1) CONFIRMED every Main-hosted fixture sets `paused = false` (test_main_host.gd + eleven
   copies in test_sidebar.gd) while the product runs with the tree paused and only the FOCUSED
   screen root ALWAYS — 1.14, 1.12, the leave-while-locked row and every settle poll on an
   unfocused screen run under a state the game never has → close fix A: run the Main fixtures
   under the product's pause state and see what changes colour.
   (2) CONFIRMED TEST_PLAN 2.2/2.6 restate `GestureMetrics`' arithmetic; no threshold check runs
   at a board zoom other than 1.0 through `PlayArea` → close fix B.
   (3) CONFIRMED 7.5's fixture is symmetric (every stock empty AND every cell full) so an AND
   passes; Q107=c's "either ... or" is OR (End reveals with Entrance cards still placeable when
   every stock is empty — as ruled) → assert each arm alone → close fix B.
   (4) CONFIRMED 6.3 pins SOURCE TEXT (`arm_leftmost`'s body counts "grab" twice) — cannot fail
   for the behaviour and blocked fix 6's clear → replace with the behavioural row → close fix B.
   (5) 4.7 "nothing disarms" drains a slot unrelated to the arm; (6) hand-emitted signals /
   `pressed.emit()` prove readers not routes (1.12, 6.10, the cross-show rows); (7) 6.1 measures
   against a hand-set null; (8) two-frame settle polls in the new suites (the branch's own
   measured trap); (9) 3.1–3.3 reconstruct the inset in the test; (10) the End-hidden sampler
   never asserts it sampled; (11) TestDragPlace keeps `pending_goal = 1` (holds by luck);
   (12) no registration gate in TestSidebar/TestDragPlace (mechanically verified: zero uncalled).
   Docs: NAMES.md still lists `entrance_stock_face_down_cap`; ASSUMPTIONS names
   `_publish_focus_description`/`_stash_description` are stale; TEST_PLAN 3.4's text says the
   opposite of its test; 8.4 has no asserting test; 7.2's "after the last line" fixture (a
   score-adding `on_card_placed` modifier) is still unwritten → close fix B / item 8.
5. `/simplify`, four angles in one read-only reviewer (Opus 5; the first attempt on Fable died to
   the usage limit): 14 cleanup items, no defects. Ranked by cost: (1) viewer hosting — the
   relay/`return_to_lock`/fit/re-fit wiring is copied across game_view.gd, map.gd and menu.gd →
   one `HudContainer` method; (2) three hand-rolled `_exit_tree` → `disconnect_for_screen` pairs
   → connect `tree_exiting` once in `connect_for_screen`, also the home for `release_screen`
   (close fix 2's cause); (3) the cover-scale formula has three homes (`game_view.gd`,
   `local_rect_beside`, `focused_scale`) and the view re-branches the top/side inset; (4) the
   "no listener" guard in three homes, two styles; (5) `PlayArea.card_info` lives on the board
   though two viewers and the wall editor call it; (6) `_entrance_drawn_columns()` rebuilt three
   times per rebuild and on every hover, `_refresh_card_marking()` twice per focus change;
   (7) eight `GameView` alias fields for HudContainer controls; (8) `_processing_screen` is a
   bool stored as a StringName; (9) `WorldMapController.is_generated()` has ONLY test callers —
   contradicts item 4's "none"; (10) one-call-site wrappers to inline: `_apply_container_inset`,
   `_visual_height`, `focus_exit`, `_end_the_gesture`; (11) `DeckViewer` reaches through its
   opener's owner to the sidebar; (12) two even-share models for stocks; (13) two four-edge
   viewer insets (acceptable); (14) `_refresh_end_reveal` runs twice per revision bump.
   dup_check: no pair in production code the branch changed (three pairs in touched files blame
   to main); in the branch's tests, five self-pairs in test_sidebar.gd and a 38-line pair between
   two probe scripts. diff_shape: only the uncommitted test_interaction.gd add-only edit.
6. `/fx-verify`: PENDING.
7. Fixes from 1–6, one at a time, full run between:
   - close fix 1 (review item 2 finding 1, undo at the outcome armed a card of the discarded
     state, next placement duplicated it into the run deck): `Game.undo()` releases
     `processing` as its last statement, after the history pop. Two checks in
     TestInteraction's outcome-undo test, RED on HEAD (armed card not in the restored
     Entrance; card total 71 vs 70), green after. Full runs: one failed on the flaky Fix 13.1
     pan precondition, the second passed `ALL 48 SUITES: 4723 CHECKS PASSED [21]`.
   - close fix 2 (review item 2 finding 2, the map's and menu's remembered description
     survived New Run and the picker's close): `HudContainer.connect_for_screen` connects the
     screen's `tree_exiting` one-shot to `disconnect_for_screen`, and the three hand-written
     `_exit_tree` pairs are deleted. Each screen calls `release_screen` where its content ends:
     GameView on leaving the tree, `Map.start_run` (the map scene persists across runs), the
     deck picker leaving the tree. New consts `HudContainer.MAP_SCREEN`/`MENU_SCREEN`
     (main.gd still spells the strings). Two TestSidebar rows RED on HEAD (Sidebar 708 passed,
     2 FAILED), green after (710); 1.14 still green. Continue shares `start_run` but no test
     drives it.
   - close fix 3 (review item 2 finding 3, a drag from a card the board refused to grab placed
     the armed card): `PlayArea._consume_as_card_release` places a travelled release only
     when the dragged card is in `selected_cards`; the press still ends through
     `_end_the_gesture()`. Two TestDragPlace rows (from an empty cell's zone card, from a grid
     card) RED on HEAD, 6 FAILED; DRAG PLACE 87 -> 95 green. The grid-card row first passed
     vacuously: `_legal_cell_control` picked a zero-height cell (`Rect2.encloses` accepts a
     zero-area rect); the shared `_is_reachable()` now also requires `has_area()`.
   - still owed: close fix 4 (a dismissed description re-shows on return), 5 (DISCARD/RULES fly-to in
     the wrong space), 6 (conventions and simplify residue), A (Main fixtures under the
     product's pause state), B (weak test rows and the pan flake); reproduce first: the pad
     focus after the X, the replayed last-card arm, Back during the hold, the double arm on
     Undo.
8. `/docs`: PENDING. 9. `consolidate-memory`: PENDING. 10. Tooling feedback: PENDING.
11. Delete the temporary plan documents (briefs, this handoff once folded): PENDING.

## Next up
1. **S24 — the closing phase**, per `.claude/skills/plan-run/SKILL.md` "Closing the run", every
   numbered item in order, each result recorded in a `## Close` section here (the output, not a
   claim): (1) `py .claude/tools/doc_check.py` FULL; (2) `adversarial-review` over `main...HEAD`
   with a priority order and "report early"; (3) `/code-review` at high effort; (4) a
   test-surface review subagent with `tests-that-prove-nothing` as its checklist; (5) `/simplify`
   serially (four angles); (6) `/fx-verify` (S21's flip, the card back, the popup); (7) fix
   everything found, one at a time, full run between, then re-run whichever of 1–6 a fix could
   have invalidated — include the three still-open suspected items named in State; (8) `/docs`
   (fold the briefs, GAPs and this handoff's residue into the living docs; correct DESIGN chart
   K9 and I8/Q217/Q244/Q245 and TEST_PLAN 9.5 to the owner's rulings; re-aim the test text that
   still says "a show never resolves on its own"); (9) `consolidate-memory`; (10) feed the
   run's traps back into the skills and agents; (11) delete the briefs and this handoff once
   folded. Then print the READY FOR CLOSING block if the owner wants the close in a NEW
   session (the skill's rule) — the owner ruled S24 runs in THIS run, so run it here.
- Doc defects to fold at the close: DESIGN chart node K9 contradicts Q135=a (the answer wins);
  TEST_PLAN §11 claims every chart node is covered but charts I and K have only by-eye rows.
- ⚠ Line endings: shell `grep -c $'\r'` is unreliable in this Git Bash (it reported every line
  as CR on an LF file). Check with python bytes: `open(f,'rb').read().count(b'\r\n')`.
  `git ls-files --eol` is the other honest check (`i/lf w/lf`). An implementer appending to
  ASSUMPTIONS.md wrote CRLF lines once (fix 2) — normalise before committing.

Working method that held up (keep it): the implementer appends evidence to a scratch file as it
goes (turn-cap and API-limit stops lose the report — three dispatches this run were cut off and
resumed with `SendMessage` to the same agent id, context intact, which beats a fresh dispatch);
verify doc_check on ADDED lines only by intersecting its findings with `git diff HEAD -U0`'s
`+` hunk ranges (the legacy backlog is hundreds of findings per touched file); check
`tasklist | findstr Godot_v4.7` before and after every run and confirm the run's own log was not
rotated (a new `godot2026-...log` inside the run window means another process started); the
check TOTAL drifts ±30 between green runs (data-dependent suites) — judge on suite count and the
failure set.

Resume prompt: *"Resume /plan-run on solatro/design/sidebar/PLAN.md — ALL phases (owner ruling).
Worktree `../gamedev-sidebar` beside the main checkout, branch sidebar. Read
solatro/HANDOFF_sidebar.md FIRST (state, per-step evidence, owner rulings, the S19–S23 audit,
open gaps GAP-001..005, ASSUMPTIONS.md), then `git log --oneline main..HEAD`, `git status
--porcelain`, and a full suite run (`py solatro/Tools/run_tests.py`, GODOT_BIN = the box's
console exe, ~5 min, gate `ALL 47 SUITES ... CHECKS PASSED` + 0 SCRIPT ERROR + the two standing
exit lines + 135 ObjectDB) before continuing. Next: S18 from briefs/S18.md."*

## References
- solatro/design/sidebar/PLAN.md, DESIGN.md, TEST_PLAN.md, NAMES.md, answers.json
- .claude/skills/plan-run/SKILL.md, .claude/skills/handoff/SKILL.md
- .claude/memory/running-godot-scenes.md, .claude/memory/tests-that-prove-nothing.md

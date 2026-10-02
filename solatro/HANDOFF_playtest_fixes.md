# HANDOFF — playtest fixes (the combined branch's first playtest)

**Goal:** the sixteen findings of the owner's first playtest on `combine-sidebar-boardplan` fixed
and gated, each against the ruling below, on this branch, ready for the owner to merge.
**State:** THE CLOSE IS IN PROGRESS - stopped by a usage limit after its review items; nothing is fixed yet and no source changed (see "## The close"). Every row is done or closed, each red-then-green, by eye where it draws, one verified step per commit; visual review rounds 1-5 answered, round 5 all 13 shots approved. Last full gate (2367ee91, P96): `ALL 51 SUITES: 10017 CHECKS PASSED` (SIDEBAR 4525, MODS 65, SUIT PROPS 23, VISUAL LAYERS 230, UI VIEWERS 177, WALL PAUSE 71/72, BOARD FUZZ random), ~15 min with `-- --timeout 1800`; 19 placeholder warnings, 24 resources + 1150 ObjectDB. Left out by the forty-fifth round: P93-P95 (solatro/todo.md, Performance). Next: the close per /plan-run in a NEW session; after it, solatro/todo.md's first section (merge every branch, the Showitaire split, a todo review). Gate at the stream's start: `ALL 51 SUITES: 5839 CHECKS PASSED`.
**Entry docs:** solatro/START_HERE.md, solatro/design/sidebar/DESIGN.md,
solatro/design/poker-patience/DESIGN.md, solatro/design/grid-view/DESIGN.md,
solatro/design/board-plan/DESIGN.md, solatro/PICTURE_WALL.md
**IMPLEMENTED-BY:** P1-P37 and P41: `general-purpose` on `opus` (Opus 5); P38 Sonnet 5 then Opus 5;
P39-P40 Opus 5; P44 onward: `plan-implementer` (medium) / `plan-implementer-low` (low) on Opus 5.5,
`plan-implementer-sonnet` (Sonnet 5, low) for mechanical steps. Overseer Fable 5.1 through P44 (4),
Opus 5.5 from P44 (3) onward; writes no source. P64b-P74: `plan-implementer` (medium) and
`plan-implementer-low` (low), both Opus 5.5. P75-P58e and P76: overseer Opus 5.5 (high); `plan-implementer`
(medium) and `plan-implementer-low` (low), Opus 5.5; recon Explore on Sonnet 5. P73-P82: overseer Opus 5.5 (high); `plan-implementer` (medium: P64b-3a/3c/3f, P71, P77, P78 b, P80, P82) and `plan-implementer-low` (low: P64b-3e, P64b-4, P66, P78 a/c/d/e/g/h, P79, P81, round-4 shots), all Opus 5.5 - P73 and P64b-3b/3d by the medium implementer; recon Explore on Sonnet 5. Every reviewer Fable, read-only. P83-P91 (the session of 2026-09-30): overseer Opus 5.5 (high); `plan-implementer` (medium: the lag profiling, P85, P87, P90, P91), `plan-implementer-low` (P83, P86, P88, P89 and the three review follow-ups), `plan-implementer-sonnet` (P84, Sonnet 5.5 high), all Opus 5.5 otherwise. P91's follow-up to P96 (the session of 2026-10-01): overseer Opus 5.5 (high); `plan-implementer` (medium: P92a, P96), `plan-implementer-low` (P91's follow-up, P92b, the round-5 shots), all Opus 5.5.

## Owner rulings
In `solatro/RULINGS_playtest_fixes.md` (R1-R10 and every numbered round, verbatim). They outrank the design
docs they name; a new ruling goes there, verbatim, in the commit that records it.

## Run rules in force
- One implementer at a time: `plan-implementer-low` (Opus 5.5, low) for a named-writer row, `plan-implementer` (medium) otherwise (owner: costs); never two Godot runners; the second
  subagent slot is read-only work. Implementers run `--logic` and `--filter`; only the overseer
  runs the full windowed gate, and it is the verdict.
- Private `APPDATA` for every run; `GODOT_BIN` from `.claude/memory/machine-profiles.md`.
  Effect-review `.import` files are frozen (`importer="keep"`).
- Every fix: red-then-green on a named test row, `doc_check --changed` silent, one commit per
  verified fix with the evidence.
- Every reviewer is Fable and read-only (owner ruling); the floor is always cleared.

## Tasks
Finished rows carry only their commits: each commit message holds that step's measurement, red, green, review and gate evidence (`git show <hash>`). Open items that finished rows carried are in Open bugs.

```yaml
- id: P1
  description: B9 - the drop map asks only the committed grid once one is committed (the match rim's site is the pattern).
  status: done
  commits: [3fcbea90]
- id: P2
  description: B15 - a right-click over the sidebar container still cancels; the container passes the second button through to the wall's routing.
  status: done
  commits: [7795568f]
- id: P3
  description: R2 - ui_cancel zooms out to wall view after the focused screen's first refusal; wall_back stays Back; PICTURE_WALL.md and picture-wall Q100 annotated.
  status: done
  commits: [7795568f]
- id: P4
  description: R3 - after the wall reveal, Main focuses the map picture through the existing focus route; Continue with nothing pending does the same.
  status: done
  commits: [af9d4f8e]
- id: P5
  description: B11 - the face-down stock card no longer displaces the Entrance cards one depth pitch up; only a held card is lifted (CardVisual.held_lift_px), and it must read against a flat row.
  status: done
  commits: [c5c554f0]
- id: P6
  description: R6 - the legal-cell highlight brightens the zone card back toward white with the mark pips excluded; legal_cell_tint becomes that brightening, no green.
  status: done
  commits: [9d02fd83, 89ccb325]
- id: P7
  description: R10 - describe_card/card_info produce a title and per-effect blocks; DescriptionPanel draws names large and bodies small; PipRankNumeral.get_str retired in favour of a display name.
  status: done
  commits: [c5c554f0]
- id: P8
  description: R9 - every description preview draws at the deck viewer's card size.
  status: done
  commits: [c5c554f0]
- id: P9
  description: R5 - the pickup model. Auto-arm removed; click lifts; drag follows while held; release places or returns; click on a legal cell places a lifted card.
  status: done
  commits: [fc919e21, 89ccb325]
- id: P10
  description: R8 - a small fixed overview gap; the isolating buffer applies only while focused.
  status: done
  commits: [342199af, 89ccb325]
- id: P11
  description: R7 - the uncommitted Entrance is centred and grid-free; a pickup focuses the nearest grid and the Entrance slides under it; a committed Entrance stays with its grid.
  status: done
  commits: [f9095b68, 89ccb325]
- id: P12
  description: R1 - the sidebar overlays and slides in after a picture lands and out before it leaves; no picture inset; hidden on the menu and in wall view; the half-width all-edge inset decided on the investigation's numbers.
  status: done
  commits: [c6c07d61, 01d107cf]
- id: P13
  description: R4 as re-ruled - a click on a map node SELECTS it and a Travel button in the sidebar travels; the node description sidebar carries its OWN Deck button (a second button, not the HUD one special-cased) and, on a talent-pack node, a button that re-opens a deck viewer of every card the pack can roll - that viewer opens by itself on the FIRST click of the node only; in the pack chooser a click selects (a different-colour ink, the moving focus ink drawn over it) and Take still takes the whole pack. NO second panel.
  status: done
  commits: [d3605b0b]
- id: P14
  description: The comment sweep the fixes owe - main.gd, test_wall_input.gd, test_wall_focus.gd, test_wall_pause.gd leave compliant (whole-file on touch), code byte-identical.
  status: done
  commits: [6e669b47]
- id: P15
  description: B15 remainder - a right-click over the WallOverlay button band (Back/Forward/Wall, outside the container) still cancels; the owner ruled cancel works from anywhere.
  status: done
  commits: [bbc16f09]
- id: P16
  description: R10 follow-up - the title pluralises the suit ("King of Knives"): five title-only localisation keys and one accessor; the singular stays everywhere else.
  status: done
  commits: [63c71de8]
- id: P22
  description: The follow-up answers, built - an off-cell drag release DROPS the card (hand empty, drop map out, description unlocked as a cancel leaves it); PlayArea.armed_slot() deleted, its query moved into the suites; the suit-only title arm uses the plural; legal_cell_glow and FOCUS_GLOW become ONE value in one home.
  status: done
  commits: [c6c8e53f, 709b4ab4]
- id: P23
  description: The second follow-up answers, built - FOCUS is shown by the card OUTER OUTLINE changing/glowing, not by brightening the face; LEGAL brightens the inside of the card and never the outline; a placed or dropped card clears its locked description and its focus glow.
  status: done
  commits: [19ace1be]
- id: P27
  description: The legal-cell brightening leaves the cell OUTER RIM alone - u_brighten lifts the face of the Type polygon only, never its outline band (today outline.gdshader multiplies the whole polygon output, so a lit cell rim lifts with its face).
  status: done
  commits: [d8660da6, 9b73809b]
- id: P25
  description: The quit-mid-generation crash, fixed at its cause in worldgen - the generator stops stepping once its owner is leaving the tree (a cancel the stage loop checks between stages, set on exit, or stepping on its own node instead of the tree process_frame); fixed in worldgen/ and re-vendored into solatro/addons/worldgen.
  status: done
  commits: [3828da2b, d3c3717b]
- id: P26
  description: Picture frames are invisible while a picture is focused - hidden once the zoom-in has landed, shown again only when switching out to wall view; never visible mid-screen while focused (the owner saw one near the middle in an edge-swipe test).
  status: done
  commits: [fed00cbe, d3c3717b]
- id: P28
  description: The owner fifth-round rulings, built - (1) frames SHOW during any camera travel between pictures and hide on each landing; (2) the window never leaves the focused picture - the overview pan and its end-stop bounce are clamped so no wall is ever visible inside a picture.
  status: done
  commits: [8ed5e209]
- id: P29
  description: Retire the overview camera pan and its end-stop bounce, which the no-wall clamp left unable to move - delete, not disable - keeping pan_grid (the Entrance reads it) and everything FOCUSED uses.
  status: done
  commits: [3b9062ce, efba780d]
- id: P24
  description: Re-entering a picture from wall view draws its content about 2x for a frame or two - the SubViewport is still at its wall-view render size when the picture is first shown focused (WallPicture.focus / update_wall_view_size).
  status: done
  commits: [ded4fc87]
- id: P30
  description: The comment sweep P12/P13 owe - Levels/map.gd, Scripts/Map/world_map_controller.gd and Tests/Map/test_map_traversal.gd leave compliant, code byte-identical.
  status: done
  commits: [e9981514]
- id: P31
  description: The comment sweep P26/P29/P24 owe - UI/Wall/wall_picture.gd and Tests/Visual/overview_pan_route_probe.gd leave compliant, code byte-identical.
  status: done
  commits: [890404e2]
- id: P32
  description: PlayArea.rest_focus_on_board() fallback for a held card with no control - its one named producer (the auto-arm) is deleted; replace with assert, run the suites, back out if a fixture fires it. Then the P20 /simplify item (collapse _lock_by_screen onto _locked_entry_by_screen; lock_to loses its dead target parameter).
  status: done
  commits: [affac31a]
- id: P33
  description: The viewer is MODAL (deck viewer, possible-cards viewer, pack chooser alike) - keys never leave it for the screen beneath; a pointer click never reaches beneath it and a click outside closes it; closing clears the card focus so the sidebar never describes a card no longer visible; a viewer card is described on hover/focus but becomes sidebar-STICKY only on a CLICK (the game-view model), with the X shown only while sticky; cancel unsticks first, then closes; keys from a card at the viewer edge enter the sidebar so the X is reachable; Deck (and Possible cards) TOGGLES - a second press closes; a CARD description on the map shows no Travel/Deck buttons.
  status: done
  commits: [b41421e1, 7185a5a4, 90ab547b]
- id: P34
  description: Hovering a board card describes it but must NOT make it sticky (only a click does) - the game grid gets the same hover/click split as the viewer.
  status: done
  commits: [11ee3e69]
- id: P35
  description: In the in-game deck viewer the focus outline does not move and the arrow keys do not move it - find why (a focus that never lands in the viewer viewport, or the rim not redrawn) and fix; the row asserts the FOCUS OWNER after each arrow.
  status: done
  commits: [b1e053a7]
- id: P36
  description: The board must not scroll vertically while nothing is out of view - the grid sits still through placements and scoring instead of shifting as the container re-sizes.
  status: done
  commits: [25c1a1b8]
- id: P37
  description: Base prop speed tripled (one knob, one home).
  status: done
  commits: [394347e5]
- id: P38
  description: On the map, when exactly one node is reachable it is selected automatically (Travel live without a click); more than one leaves nothing selected (R4).
  status: done
  commits: [d59f514c, ee29da90]
- id: P39
  description: Two-grid board - (a) the overview gap is ONE CARD WIDTH and the overview is not a shrunk board; (b) focusing a grid ANIMATES into place, never snaps; (c) a drag pan requires the button HELD (no click-toggle), and on release the grid nearest the centre snaps in as if Left/Right were pressed; (d) cancel zooms back out to the every-grid overview; (e) the Entrance stays CENTRED until a card is actually PLACED - a focus or a Left/Right does not take it, the grid comes to it; (f) once the Entrance is used up (no card can go on the committed grid) it is free to commit to another grid.
  status: done
  commits: [9f2ce814, a3559d86, 286b1a79, f2ab104b, 685c0d54]
- id: P40
  description: Keyboard/pad parity on the board - Left from the leftmost card (and the matching edge on every screen) enters the sidebar, so the sidebar is reachable with no mouse; and every route in P33-P39 is completable with one device alone.
  status: done
  commits: [8ef0873d, 90ab547b]
- id: P41
  description: P33 follow-up as ruled - (1) with no sticky card the sidebar is INTERACTABLE while a viewer is open (the HUD with its Deck button shows whenever no viewer card is hovered or control-focused; a cancel/X from a sticky description leaves the focus in the sidebar with no card description), so the Deck toggle is reachable by mouse and by pad; (2) the pack CHOOSER covers the map entirely, opaque, to the right of the sidebar; the sidebar describes the card being chosen and carries a Deck button whose viewer overlays the chooser; the chooser cannot be left until Take; (3) a click outside the possible-cards viewer closes it, a click outside the chooser does nothing.
  status: done
  commits: [2d1a90b4, b41421e1]
  notes: '(2) superseded by P64: the chooser is a window with the map visible around it, and Back/Forward/Wall stay live.'
- id: P42
  description: SIDEBAR "the map has read nothing of its own, so it shows its own HUD (B15)" is order-dependent since P38 - failed 4 of 5 six-suite filtered runs, passed 3 of 3 Sidebar-only runs and the full gates; find the route by which an auto-picked node's description reaches that row and make the row's precondition true by fixture or by product, whichever the measurement says.
  status: done
  commits: [cab18b74]
- id: P43
  description: At 3 grids the fitted overview (width-bound, no slack) draws the set exactly 4.0 authored px right of the board window centre; at 1 and 2 grids (height-bound) it centres to the pixel. Find the writer; the two GRID VIEW rows pin the 4.0 exactly and go red when it is fixed.
  status: done
  commits: [b90ad180]
- id: P44
  description: The seventh-round board rulings, built - (2) a drag-pan release also puts the keyboard focus on an Entrance card; (3) a cancel that ends a latched pan also snaps the nearest grid into place; (4) a ONE-grid show commits its Entrance to the grid as it opens (nothing to choose, nothing moves); (5) a show EASES in as it opens instead of arriving at scale; (6) the board eases to the sidebar arriving reserve too, the re-fit throttled to once per slide; (1) as built - a one-grid cancel goes straight to the wall; name the Back/cancel difference in one line at the wall_back site.
  status: done
  commits: [9a413bd8, 6010fca9, 8287aabf, 51297f48, 83ed4158, 4eba2657, 10b7d4f9, b6167a68]
- id: P45
  description: An existing user://settings.tres carrying prop_tick_fraction 0.45 is brought to the new default on load - the owner: "dont keep old speed".
  status: done
  commits: [849b81eb]
- id: P46
  description: While a viewer is hosted, the board and its cards are not the focus - a board card holding keyboard focus publishes NO description to the sidebar (the HUD or the viewer card's description shows), so the game screen matches the map (owner, eighth round, 7 = b).
  status: done
  commits: [3695b183, 20ebffbe]
- id: P47
  description: A pointer re-entering the card that holds the keyboard focus describes it again (a closed hover left the focus behind, so the second hover published nothing) - the focus rim stays (owner, eighth round, 8 = a with fix).
  status: done
  commits: [a63b62c7, 20ebffbe]
- id: P48
  description: Keyboard parity - arrow keys cannot move the focus from a focused grid onto the Entrance (Up and Down stay in the grid), so a keyboard-only player cannot pick up a card from the board (the standing one-device principle).
  status: done
  commits: [52980893]
- id: P49
  description: A focused Entrance card wears the same clear focus rim as a focused grid cell (sixteenth round); today its paper brightens a shade with a faint pale edge (P48 frames p48_1_down_on_entrance vs p48_1_up_on_cell).
  status: done
  commits: [e7ead6cc]
- id: P50
  description: The focus and would-match rim ink goes back to cream (palette 31) everywhere - the owner's visual review reversed P49's pink.
  status: done
  commits: [9cfe7b0c, 6ffa2876]
- id: P51
  description: A card description in the game screen's sidebar shows a Deck button; only a MAP NODE's description carries one (the owner's visual review; second playtest: no Travel/Deck on a card description; sixth round: a node description shows Deck).
  status: done
  commits: [528d3020]
- id: P52
  description: The pack CHOOSER can be left before its cards are taken - overlay Back/Forward (and Wall?) leave the map with the chooser still up; the owner ruled the chooser is the new focus until Take is pressed.
  status: done
  commits: [a83e9b32]
  notes: 'Superseded by P64: Back/Forward/Wall stay live and returning finds the chooser in progress.'
- id: P53
  description: With a show live, closing a pack node's possible-cards viewer on the map lands the sidebar on the HUD instead of back on the node, so Travel is out of reach (measured by P51: panel=false, hud=true, the pick still set; without a live show it comes back to the node).
  status: done
  commits: [08d246e2]
- id: P54
  description: Stick a chooser card, open the Deck viewer over the chooser, close it - the chooser's stuck card survives with Take disabled but the sidebar shows the HUD with no X (measured by P52: sticky set, Take disabled, not locked, no description); one Escape clears it.
  status: done
  commits: [1aaad4ed]
- id: P55
  description: The map fits its picture (twentieth round): by default zoomed out so the whole map fills the space beside the resting sidebar with a small sea-coloured buffer; zoom only goes IN from there; panning only while zoomed in, clamped so the map never leaves the window. Was: two frames after Take on the pack chooser the map is drawn off-centre - the map image starts at about x=760, y=190 of a 1280x720 window with an empty grey band above and left of it (P52 shot p52_after_take_live.png, UNVERIFIED whether mid-ease or at rest, and whether HEAD before P52 does the same).
  status: done
  commits: [543c1f87]
- id: P56
  description: While the run deck is open over the chooser, the sidebar's Deck button is hidden, so the ruled toggle (press Deck again to close an open deck - Viewer paths 10, second playtest) cannot be reached there.
  status: done
  commits: [6d49b491, 40917b9d]
- id: P57
  description: Only a STUCK description comes back when the player returns to a screen; an unstuck (hovered or focused) one is forgotten when the screen is left (nineteenth round). Today, by keys, a focused card's description survives Back and is re-shown on Forward with no card under it.
  status: done
  commits: [826857f9]
- id: P59
  description: A card description shows the X only while it is the STUCK entry; with a card lifted, a focused or hovered other card/cell is described without an X (visual review round 2, lifted_focus_elsewhere).
  status: done
  commits: [75493636]
- id: P60
  description: The game sidebar shows Goal, the current Total (live_total) and board_total x combo, each always (twenty-second round); the Combo label's hide-below-1 goes.
  status: done
  commits: [c010bb37]
- id: P61
  description: The map shots in sidebar_snapshot.gd stop leaving a fake current node behind - _make_the_node_reachable writes controller._current directly and never restores it, so later map shots draw edges from a node the token is not on (the owner asked about missing edges in map_zoomed_edge).
  status: done
  commits: [905cfc1c]
- id: P62
  description: While a card is held, an occupied grid cell whose mark is a legal drop shifts its top card slightly to reveal the mark beneath (with its legal glow); otherwise focus selects the card on top (twenty-second round context; visual review round 2, grid3_overview).
  status: closed
  evidence: 'No code - see the twenty-third round.'
- id: P62b
  description: The focus rim on an occupied grid cell lands on the hidden MARK under the placed card - PlayArea.focused_visual goes stale when a placement reuses the focused slot's control - so the top card, which holds the focus, shows no rim (the 1 px cream sliver in grid3_overview is the mark's rim peeking past the placed card's float tilt).
  status: done
  commits: [cbda7ec3]
- id: P63a
  description: The sidebar description's button row (Travel / Deck / Possible cards) moves to the top of the sidebar, under Back/Forward/Wall, above the described card; while its own viewer is open, an opener reads "Close <viewer>" and closes it (twenty-second round "Both").
  status: done
  commits: [b980b5c4, 616c6cea]
- id: P63a2
  description: P63a round 2 - a card stuck in a pack's possible-cards list shows the row with Deck only (twenty-fourth round); every opener (the map HUD Deck, the game's Deck/Discard/Rules) reads "Close <viewer>" while its viewer is open (twenty-second round "Both"); the row checked at the top-band window too.
  status: done
  commits: [b980b5c4]
- id: P63c
  description: Twenty-fifth round - Deck pressed from a card stuck in a pack's possible-cards list opens the run deck OVER the list (as over the chooser), the row up reading "Close deck", and closing the deck returns to the list with the card still stuck; closing the possible-cards list while a card is stuck returns the sidebar to the pack node's description with Travel live.
  status: done
  commits: [ef4591f2]
- id: P63b
  description: Every viewer (Deck, Discard, Rules, Possible cards, the chooser's deck) carries a bookmark-style X tab sticking out of its side that closes it (twenty-second round "Both").
  status: done
  commits: [342e7a4e]
- id: P64
  description: The pack chooser is a square window sized to its contents, centred beside the sidebar, the map visible and inert around it; Back/Forward/Wall stay live and returning finds the chooser in progress (overturns P52's lock-out and P33's "cover the map entirely").
  status: done
  commits: [d7936ddf, 4ae86508, 2f0460e1]
- id: P64b
  description: The chooser to the twenty-sixth, twenty-seventh and twenty-ninth rounds - Rerolls beside Take, five columns then scroll, everything centred; every viewer on the sidebar's overlay layer at the UI scale (2a chooser, 2b map viewers, 2c game viewers + one preview size, 2d the menu picker's viewer); part 3 = Tab and ui_cancel-with-nothing-stuck reach the wall while the chooser is up (R2).
  status: done
  commits: [4ae86508, 2f0460e1, 594589ca, 0c2b3979, 336b4a98, 2d40cff1, 20e47bc7, e6f9c141, e7e42b2a, 565cefaa, 9bd87874, e7bb30d9, fb244268]
  notes: 'Part 3 split: 3a ui_cancel with nothing stuck reaches the wall from the chooser, the focus back on the chooser on return (DONE, 2d40cff1); 3b the start menu''s buttons take keyboard focus (DONE, 20e47bc7; round 2: the review''s dup helpers, an unbounded wait, the warm-up re-grab''s own mutant, a frozen show''s board focus after the menu grabs); 3d the menu lays out against the sidebar''s RESTING rect (DONE, e6f9c141; fortieth round; resting_rect_beside is the map''s precedent) - measured before: the bottom row re-wraps mid-slide, Language 367 px right / 41 px up in one frame; 3e a disabled button cannot take focus, every one of them (DONE, 565cefaa - HudContainer.hold; geometric neighbours kept: the ruling pins focus, not a route) (fortieth round) - SIZED (recon, traced): only the menu''s Continue (menu.gd ~78, no save) and the game''s Submit while processing (game_view.gd ~330) lack it; Back/Forward/Wall are FOCUS_NONE always (test_wall_focus ~816 pins it); the chooser''s Take/Reroll already pair disabled with FOCUS_NONE in ChoiceViewer._hold (~215-218) - make that the one shared helper and use it at both sites; the docs: BaseButton.disabled says nothing of focus, only focus_mode (or 4.5+ focus_behavior_recursive) removes it; 3f (DONE, e7bb30d9; in FRONT of 3c, which depends on it - measured by 3c: with a viewer hosted, HudContainer._enters_the_hosted_viewer hands ANY arrow to the viewer and an arrow off the list''s edge with nothing stuck is KEEP, so Undo/End/the Deck row were reachable only by Tab - never by a pad): every visible enabled sidebar control reachable by arrows and d-pad while a viewer is up with nothing stuck (P33, P41 (1)), the viewer''s edge enters the sidebar and the sidebar''s inner edge enters the viewer, a stuck card reaches its X and - on the possible-cards list only - the Deck row (Viewer paths (5), 24th/25th rounds); 3c Tab = wall on every screen (DONE, fb244268 - project.godot empties ui_focus_next/ui_focus_prev) (thirty-ninth round) - drop KEY_TAB from ui_focus_next (project.godot has no override today) or read wall_overview before the GUI pass (hud_container.gd ~715 and wall_overlay.gd ~81 already read _input) - one place; re-point test_sidebar ~5623/~6559/~6586 to arrows (measure ~5623 first: Down from Deck may land on a viewer card, neighbour search ignores occlusion) and drop the route test''s Tab skip. Earlier inputs: the Fable review of P64 found test_sidebar test_every_route_leaves_the_chooser_and_comes_back_to_it_in_progress SKIPS the Tab route (Tab is focus-next while a chooser control holds focus - wall_overview never fires); the Open bugs line "FOR P64b part 3" (P73''s review items: the start menu''s buttons never take keyboard focus; a tautological aspect check; the re-wrap under the pointer).'
- id: P65
  description: A focused picture is drawn at one scale on both axes at every window shape - cropped to the window, never stretched (owner - "map has become very squished and distorted which shouldnt happen"); P65b sizes the wall-view target for the part a picture shows.
  status: done
  commits: [498090ae, d0743a6d]
- id: P74
  description: The test window can be minimized with no consequences (owner - "goal is that i can minimize test running windows with no consequences. this should only trigger for testing related code") - Tests/all_tests.gd opens a hidden force_native 1x1 window so the engine keeps drawing, and an end-of-run check fails if a minimized run stops drawing.
  status: done
  commits: [d0670eca]
- id: P76
  description: The listed intermittents already past the three-failure budget become fixes (thirty-seventh round, queued right after the square cards) - PLAN VISUALS TP-92 (a wall-clock stagger row, ~1 gate in 3), SIDEBAR test_the_wall_view_shows_one_surface_colour_behind_the_pictures's frame-count sanity (a full-image readback per frame; ~4-5 informative frames against >4), UI VIEWERS "a later arrow never drags the focus back to the first card" (a focus race with another suite's Main in the same window). One fix at a time, each MEASURED first (the Open-bugs lines carry the counts and leads); a row that measures a wall-clock quantity is made robust to frame rate or re-pointed to what the player sees, never loosened.
  status: done
  commits: [2b6804de, 763dac1f, bfd03c32]
  progress: 'P76a TP-92 DONE (the cascade dealt early - a product defect; the rows on the frame clock). P76b DONE (763dac1f, the sanity was starved by the test''s own per-pixel classification). P76c DONE (bfd03c32, another suite''s Main took the shared window''s focus - the rows host their viewers in a Window of their own).'
- id: P58e
  description: The square-card group's broad Fable review, its findings (queued right after P76, ahead of P73 - the group's own follow-ups, and P73 touches the same test file).
  status: done
  commits: [8b258569, 725230ff, ab77f93e, 6a7cc42c]
  notes: 'Each MEASURED first, one fix per commit. (1) seam: CardVisual.star_outline(CARD_SIZE, 0.0) - the hand model every harness and formation_editor stands on - equals a real TypePaper _rig_outline() at rest, and nothing pins it (card_visual.gd ~533-549); add the check to OUTLINE''s per-type row. (2) a FACE-DOWN card binds its type''s drawn extent (_bind_rig ~578-612): a TypeInput dealt face-down carries a 52-box mask under the 54-box back frame - rebind on show_front/frame change, or state it at _bind_rig (read, not measured). (3) tools/outline_atlas.gd _non_empty reads alpha > 0.5 against > 0 everywhere else - one line. (4) T1: the WEDGE_CANDIDATES bound (busiest slot + 1 <= 8) is asserted only on star_outline, never on a real posed rig (RIG_ANIM t 0.15, 0.30) - a sheared corner needing 9 reads as a hole. (5) T2: OUTLINE''s per-type loop is a fixed list of 4 checked == 4 - discover the shipped types under res://Cards/Types and assert the frame set covered. (6) C1 per-frame cost: every card walks 40 atan2 + wedges in _fill_poly_from_outline (fx_attachment.gd ~350-400) BEFORE comparing to the last poly - compare the input outline first (measure fx_cost / a board frame time before and after). (7) C2: the staircase''s short step edges shrink the resting early-accept inner box to 23/27 (was 26/27) so ~27% of a resting card''s fragments build wedges - the comments at fx_attachment.gd ~404-405 and fire.gdshader ~322-324 say none do (stale); a corner-aware inner box (25/27) is an unmeasured lever. (8) C3: glow.gdshader mask_dist now runs 40 segments per lit fragment (its comment says 24) - measure the glow/spotlight row in fx_cost. (9) T3: test_ui_viewers _fitted_deck_viewer''s comment overstates the host''s re-fit. Plan drift to answer, not build: P58b named the sidebar''s minimum width among card holders; hud_container.gd has no card term (container_size_fraction) - whether the preview card must fit it is the owner''s deferred ''font and button sizes''.'
- id: P77
  description: Size / scale / layout rows run in the harness's scale-1 test SubViewport, not the player's window (tests-that-prove-nothing item 22) - add root-window checks at 1280x720 and 600x1000 for the few claims that matter (every viewer at the UI size, the chooser square, the menu column, the board centred), or mark each harness-only row as such. Queued at the end. MEASURED by P58b-7's first round: a suite cannot resize the OS window - in the full gate DisplayServer.window_set_size to 1280x720 / 600x1000 was not granted (the window stayed 1152x648), every suite shares that window (test_wall_focus.gd ~453: only a SubViewport can be resized safely), and a mid-test error would strand later suites at the wrong size. Measured by P77: the root's scale in the gate is 1 - the rows run in an unfocusable embedded Window (tests-that-prove-nothing item 22).
  status: done
  commits: [dc65ba74]
- id: P78
  description: Visual review round 3's comments (verbatim in the rulings) - each its own measured step: (a) the chooser's 'Reroll' text centred under its card; (b) the map fit's top (and bottom) sea buffer; (c) each overlay window (deck viewer, pack chooser, possible cards, rules) a distinct placeholder background colour, and the bookmark X tab opaque; (d) the deck viewer's list with the same buffer above its top row and below its bottom row as at its sides; (e) the pack chooser sized to its cards - no extreme space above and below, growing with the card count, scrolling at the limit (the thirty-first round's 'window to screen, scroll' now reads: grow only as rows are added); (f) an empty (blank) card described in the sidebar; (g) the formation editor's hoops aligned horizontally; (h) the win/lose result centred over the game view.
  status: done
  commits: [4d1478cf, 4dedf09d, f316bd6a, 6577d92d, 1e10b580, 73682225, d9b0fe5c]
  progress: '(a) DONE 4d1478cf; (c) DONE 4dedf09d; (b) DONE f316bd6a (forty-third/forty-fourth rounds); (d) DONE 6577d92d; (f) done by P71; (e) DONE 1e10b580; (g) DONE 73682225; (h) DONE d9b0fe5c.'
  notes: 'Recon (traced, not measured): (a) choice_viewer.gd ~156-164 _add_reroll_button, PRESET_BOTTOM_WIDE on the ControlCard (width = child.card_size) - the miscentre not located by reading; (b) world_map_controller.gd ~98-102 _framed_map grows the drawn rect equally on all sides (player_settings map_edge_buffer_fraction 0.03) - symmetric by construction, so MEASURE what the owner saw; test_the_maps_background_is_its_sea samples only the top buffer; (c) every backdrop is PaletteDB hud_background (choice_viewer ~71, deck_viewer ~38, hud_container ~82); the CloseTab (deck_viewer.tscn ~31-36) has no authored style; (d) DeckViewer top-aligns its rows, slack below the last row; (e) ChoiceViewer.fit_beside ~128-149 sizes for ROW_CARDS=5 always and forces a square - the round-3 comment ("expand only when card count increases. at max limit it becomes scrolling") is the owner''s latest word and supersedes round 2''s "square window" for the height (width stays five cards, twenty-sixth round); (f) DONE by P71 (36c20f0b: Paper named with a placeholder description in the list) - shown in review round 4; (g) the offset is in the DATA: Cards/Props/Formations/hoop.tres points y -2.25..2.94, the editor only draws them; (h) game_view.gd ~351-365 centres the outcome on the whole picture (Win/LoseScreen full rect), not the board''s space beside the sidebar. One measured step each, one gate each.'
- id: P79
  description: The visual-review tool - (a) a new round shows the previous round's comments as if new (owner: "bug with new visual reviews leaving behind comments from previous reviews"; grid1_focused's round-3 approve carried round 2's text); (b) the page's Done never reaches solatro/visual-review/status.owner.json (still round 1, 2026-09-24 - rounds 2 and 3 both) so the watch never wakes (designloop/src/visualreview.mjs writeOwnerStatus keeps the old round; markDone passes none - read by the P58d-shots implementer); (c) the review images alias heavily (owner, grid1_overview and pip_row: "resolution looks off ... heavy aliasing", "screwing with outline shader results") - the grid shots are 1625x914 captures shown scaled with no smoothing; measure whether the capture or the page's scaling aliases; (d) the npm command given in chat failed for the owner ("auth issues") - give the owner the exact command they can run.
  status: done
  commits: [497b3a1a]
  notes: 'Fix before the next review round. designloop is its own project (designloop/README.md). Recon (traced, not measured): (a) solatro/visual-review/index.html ~103 fills the comment box from review.json''s last verdict BEFORE computing stale (~104) - only the label honours it; review.log shows grid1_focused''s round-2 text resubmitted on round 3; fix: no pre-fill when the AFTER is newer. (b) premise likely wrong: Done -> server.mjs ~753 -> visualreview.mjs markDone -> registry.mjs ~84 always stamps a fresh at; status.owner.json''s round-1 record is simply the last Done pressed (round 3''s Done never pressed?) - measure by pressing it on a scratch copy, then fix nothing if it lands. (c) index.html ~12 downscales the pair with image-rendering: pixelated (nearest neighbour) - aliasing on a DOWNscale; crops (~17, upscale) are right as pixelated; measure whether the capture itself aliases (the outline shader at the shot''s scale) before changing the page. (d) npm --prefix designloop start runs node src/server.mjs - no registry, install or git: the failing chat command was something else; give the owner that exact line (and Box B''s Node PATH note from machine-profiles).'
- id: P64b-4
  description: The P64b part 3 group's broad Fable review, its findings (queued right after P80 - the group's own follow-ups, as P58e was). (1) Menu.refresh_continue (menu.gd ~80) runs only in _ready and on a Play press, never when the menu is shown again: a save made during a run leaves Continue held on return, and a lost run (main.gd ~587 clear_save) leaves Continue LIVE with no file - Enter reaches main.gd ~536 _on_continue -> RunManager.load_run() unguarded (read, not measured); refresh on every show (Menu.take_the_focus already fires on active_screen_changed), and drop the fold/reopen of Play from test_keys_alone_start_a_run_from_the_start_menu_and_find_it_again (~2449-2454) so the row can fail. (2) test_sidebar ~2328 and ~2342 pin _check_the_bottom_row_beside_the_sidebar for the same state (picker up, at rest, 1280x720) - drop the older row's call, keep its wrap check. (3) CardsViewer.sidebar_requested's doc (NAMES.md ~141, cards_viewer.gd ~54) says "another viewport"; every hosted viewer is in the sidebar's root viewport - "a separate Control tree the neighbour search never crosses".
  status: done
  commits: [bfd3c0c0]
- id: P81
  description: The game sidebar's score line (board_total x combo, P60) is drawn starting left of the window's edge - its first characters are cut off ("26 x 14.0" at x < 0 in P78 (h)'s 1280x720 win_overlay shot). Measure the writer (the label's container/alignment in the HUD) and keep every score line inside the sidebar.
  status: done
  commits: [5280f299]
- id: P82
  description: After a window resize the start menu keeps a stale layout - seen in review round 4's menu_focused_by_keys (1280x720 right after the 600x1000 still): no sidebar drawn, yet the column laid out as beside one (shifted right, pushed down) and its bottom row's third line cut off at the window's bottom edge. Inserted AHEAD of review round 4 (a known-broken shot would cost an owner verdict). Measure the writer (menu.gd _apply_container_inset's resting/slid inputs across a resize) first; stop if only the snapshot's staging reaches it.
  status: done
  commits: [7cc213c5]
- id: P83
  description: The overlay's Back/Forward/Wall buttons only ever GROW - WallOverlay._grow_to (wall_overlay.gd ~46) keeps maxf(button.size, target), so after the window's smaller side shrinks (a visit to 600x1000) and grows back they stay 80x69.12 at 1280x720 against a 38.9 target, and the band's bottom (81.1) keeps the sidebar's content pushed down (_position_below_overlay_buttons). Most of review round 4's 1280x720 shots show it (the band 78 px tall vs 44 on a fresh boot). Measured by P82's implementer (named writer). Ahead of review round 4.
  status: done
  commits: [b9f5bdc7]
- id: P84
  description: Inline WallOverlay._grow_to (wall_overlay.gd ~46-48) into its one call site, the row loop in _apply_touch_targets - one call site, no test seam (Fable review of P83; the handoff's rows name it only as P83's writer). Mechanical, plan-implementer-sonnet.
  status: done
  commits: [8a4284d3]
- id: P85
  description: 'Every viewer window is a picture frame (review round 4, deck_over_chooser + deck_viewer). Owner, verbatim: "appears to be wider than before. scrollbar too close to the card. separation between cards should also exist on edges from the window. window''s own buffer separate from card container should be a same value border along entire window, not just the left and right sides, since right now there is extra space on left and right that top and bottom doesnt have. think picture frame." and "as mentioned in previous comment, if adding a border it should be along all 4 sides. otherwise all good." And (pack_chooser): "assume same separation as card separation if there is ever separation being used." So: the card separation also between the outer cards and the card container''s edges, and one border of that same value on all four sides of each viewer window (deck, discard, rules, possible cards, the chooser, the picker''s Inspect); the scrollbar kept clear of the cards. Measure first what makes the deck over the chooser wider than before and where each margin comes from (P58b-7 made the deck viewer whole columns centred).'
  status: done
  commits: [39241dc3]
- id: P86
  description: 'The pack chooser''s foot row (review round 4, pack_chooser). Owner, verbatim: "there should probably be separation buffer between rerolls: 5 take row and the choosing cards. take button should not be touching the reroll buttons. use same separation as card separation. assume same separation as card separation if there is ever separation being used." The Rerolls/Take row and the Reroll buttons get the card separation between them and the cards; Take never touches a Reroll button.'
  status: done
  commits: [9e000089]
- id: P87
  description: 'The possible-cards list by type (review round 4, possible_cards). Owner, verbatim: "including name is great. rows should be split by type though to make it easier to determine the type, similar to starting a new line for a new paragraph, with header label such as Card Type, Talent, Suit, Rank separating the rows, left aligned. rank should not be black as well since outline is also black. use the white cream color as the rank filling instead." Rows grouped by part type, each group opened by a left-aligned header label (Card Type, Talent, Suit, Rank); the rank numerals filled cream, not black.'
  status: done
  commits: [67449ddb]
- id: P88
  description: 'Hoop overlap (review round 4, formation_editor_hoop). Owner, verbatim: "hoop top portion should always cover any other hoops'' bottom half. if this is just tool editor idiosyncrasy then its fine if actual game already does this, this editor is just for positioning." MEASURE FIRST whether the game draws each hoop''s top over the others'' bottom halves; if it does, the editor-only difference needs no fix (report it); if the game does not, fix the game.'
  status: closed
  evidence: 'No code (owner: a: leave it). Measured with 4 tinted hoops on a real PlayArea: over a card PropLayer._apply_split (prop_layer.gd ~232-261) draws all far halves, the row''s cards, then all near halves; off any card (the staged queue, the exit) and in the formation editor the halves hide and whole rings draw in child order (prop_visual.gd ~203-209). The overseer read the three tinted crops.'
- id: P89
  description: 'The win overlay''s vertical centre (review round 4, win_overlay). Owner, verbatim: "middle centering is good, but it does not look vertically centered." Horizontal stays over the board''s columns; centre it vertically over the same space.'
  status: done
  commits: [52934da9]
- id: P90
  description: 'The start menu in a portrait window (review round 4, menu_top). Owner, verbatim: "would look better if buttons were aligned top to bottom in a vertical window." At a vertical window the bottom row''s buttons stack top to bottom; the landscape row stays.'
  status: done
  commits: [88a2b988]
- id: P91
  description: 'The spotlight circle as wide as the card. Owner, verbatim: "i notice that spotlight effect circle is not as wide as card talent art 32x32 is. in fact, lets make spotlight effect as wide as entire card is now, which should be 52x52, since square card can now fit a whole circle inside. could not do this previously with rectangular card." Today: FxSpotlightStyle.circle_radius (UI/Fx/fx_spotlight_style.gd ~37, default 16 art units, @export_range 4..48 per the owner''s Q85 ask that it stay adjustable), saved 16 in Shaders/Styles/glow_beam.tres and 17 in glow_circle.tres, fallback CIRCLE_ART_UNITS_FALLBACK 16 (UI/spotlight_director.gd ~35), used at ~446 as radius x scale; the card art is CARD_ART_SIZE 52x52 (Cards/card_visual.gd ~8). MEASURE FIRST the drawn circle''s diameter on a real card against the talent art''s drawn 32 and the card''s 52 - the owner sees it narrower than 32, so a lost scale may be the first defect; stop if so. Then the default derives from the card (radius = CARD_ART_SIZE.x / 2, no typed 26), both saved styles follow it, the knob stays adjustable; the cone''s mouth derives from the radius, so check the beam still meets the circle. By eye on fire/spotlight shots.'
  status: done
  commits: [62a38609, b86da4c3]
  notes: 'The 16 and 17 the description names are FxGlowStyle literals (glow_beam.tres, glow_circle.tres), not the spotlight''s, and stay literal; the spotlight default derives (fx_spotlight_style.gd circle_radius).'
- id: P92a
  description: 'The implementer cache notices a modifier attach (found by P92''s measurement). CardEnvironment._compare_implementers (Scripts/card_environment.gd ~127-153) is keyed on [state id, state.revision]; a skill/type/stamp set (card_data.gd ~34-45) or add_status/remove_status (~86-101) on a live card changes neither, and a revision bump mid-cascade is ruled out (spotlight Q17=a, design/spotlight/PLAN.md ~241). Fix: the cache key also reads a modifier epoch those five paths bump - no rebuild, no revision change. Traced by the Fable check, to reproduce RED first: the first juggling balls of a show can miss on_score in the commit they land (run_all_mods'' gate at ~114 reads an on_score entry built empty earlier in the same commit). plan-implementer (medium).'
  status: done
  commits: [a711b4ce]
- id: P92b
  description: 'The legality walk''s dispatch (placement lag, measured: ~85% of each ~15 ms Game.legal_cells_for walk). CardEnvironment.return_first_data_array_result (Scripts/card_environment.gd ~249) re-scans every card''s modifiers with has_method per cell; replace its body with a FIRST-NON-EMPTY loop over the cached active_implementers(function) (~181; same order, spotlit gated at call time, _note_mod_fired and await unchanged) - NOT return_first_mod_variant, which returns the first implementer''s answer verbatim and TypeGridCell.on_can_place_stack (Cards/Types/type_grid_cell.gd ~54) answers [] for every other cell. Callers: game.gd ~348, ~720, card_effect_api.gd ~120. After P92a. plan-implementer-low.'
  status: done
  commits: [e07c1235]
- id: P93
  description: 'The existence checks stop at the first legal cell (placement lag; solatro/todo.md''s lost early exit). Game._no_legal_placement_remains_in_grid (game.gd ~819) and its callers _lift_a_spent_commitment (~800) and _no_held_card_has_a_legal_placement (~726) only test is_empty(), but call the full legal_cells_for walk; main stopped at the first legal cell. An early-exit parameter on legal_cells_for (THE one walk - NAMES.md), no second walk. Fable''s suggestions, measure each: _lift_a_spent_commitment walks and discards on a one-grid board; the refill check walks grids a commitment refuses (PlayArea._sweep_legal_cells already narrows to the committed grid). plan-implementer-low.'
  status: closed
  evidence: 'Not built - left as a todo by the forty-fifth round (solatro/todo.md, Performance).'
- id: P94
  description: 'The release frame''s rebuild while the card is still held (placement lag: ~15 ms walk + rebuild in PlayArea.ungrab_cards). ungrab_cards rebuilds before it clears selected_cards, so the rebuild lays out the HELD look (_bind_slot ~2814, _append_ordered_visual ~2931, _refresh_mark_matches ~3621, _sweep_legal_cells ~3718) the ungrab then undoes. New order: the visual reset loop (~2169-2175, which reads selected_cards - clearing first would leave the visual lifted) -> selected_cards = [] -> flush_rebuild(). hand_changed then fires before the rebuild; its one listener HudContainer.set_card_in_hand reads no board maps. plan-implementer-low.'
  status: closed
  evidence: 'Not built - left as a todo by the forty-fifth round (solatro/todo.md, Performance).'
- id: P95
  description: 'Game.save_state''s second, debug-only snapshot (4-9 ms a commit in debug builds). _debug_commit (game.gd ~600) takes a fresh to_saveable(); append save_history.back() instead - entries are immutable by contract (run_manager.gd ~143), every reader duplicates before use, and _resume_show already shares them. Update the two ''FRESH to_saveable() duplicate'' comments (test_leak_canary.gd ~188, leak_holder_probe.gd ~140). plan-implementer-sonnet.'
  status: closed
  evidence: 'Not built - left as a todo by the forty-fifth round (solatro/todo.md, Performance).'
- id: P96
  description: 'A wheel under an open viewer reaches the screen beneath (found by the round-5 shots). Measured on a real Main with press+release notches: over a possible-cards list at its top or end limit, over the viewer''s frame border and over the catcher outside the window, one notch zooms the map (1.5209 -> 1.7490); mid-list and over the scrollbar band it does not. The escape: ScrollContainer accepts a wheel only when its value changed; the catcher''s STOP filter passes scroll events (mouse_force_pass_scroll_events defaults true); DeckViewer._unhandled_input passes it; the wall routes it to the map. The viewer is MODAL (P33; second playtest) - the wheel never reaches beneath. With it, the harness fix: sidebar_snapshot.gd and test_sidebar''s _wheel_event push a wheel PRESS with no release, which latches the viewport''s mouse focus so the next click goes to the control under the last notch - the "Deck click closes a scrolled list" the shots implementer saw is that artefact, not a product bug (with a release the click opens the deck, the list still scrolled, the card still stuck).'
  status: done
  commits: [2367ee91]
- id: P80
  description: The listed PlayArea._deal_next_mark freed-instance SCRIPT ERROR (x20-x25 per run, play_area.gd ~2409, during the WALL FOCUS / WALL TRANSITION soaks) is past its three-failure budget - find the writer that frees the board (or its Main) while the plan-mark deal is still stepping, and make the deal end with its owner; measure first (the deal is released at go-live; P64b-3b round 2 rests the board focus on every game went_live - check whether it moved the frequency).
  status: done
  commits: [146eb824]
- id: P75
  description: The test window boots MINIMIZED and pops up only when the first suite starts (owner, verbatim - "when testing window boots up, it blocks screen and is unable to be interacted with until tests start running due to loading. This is extremely annoying. Instead have it be minimized during loading, and only pop up to become visible once actual tests starts since bootup has ended. this way i can choose between closing immediately when it popups vs watching it."). Test-only code (the test wrapper and Tests/all_tests.gd); project.godot sets window/size/always_on_top=true for the game - do not change the shipped setting.
  status: done
  commits: [bd8c9f81]
- id: P66
  description: At the 600x1000 top-band window sidebar_snapshot hung at map_after_travel - the Travel press left the token where it was (HEAD too, measured by P64b). P72's implementer saw the 600x1000 snapshot finish in under a minute with no hang - re-check before building anything; the hang may have been a minimized window (see Open bugs, the minimized-window row).
  status: closed
  evidence: 'No code. 3 of 3 visible runs of sidebar_snapshot at 600x1000 (cc387049) finished in ~39 s; Travel moved the token every run (moving=true, token between nodes; the scene awaits node_entered before quit); exit profiles clean; the overseer read run1_map_after_travel (the token mid-route on the highlighted path). The P64b hang fits the minimized window.'
- id: P67
  description: The map's wall picture is a 648x648 square (thirtieth round); focused it still fills the window and the map fit keeps the whole map in view.
  status: done
  commits: [83e6f46f]
- id: P68
  description: A visited picture's wall-view thumbnail shows its content - a frozen picture renders once at its new wall-view size (it was a blank panel).
  status: done
  commits: [37a1b40b]
- id: P69
  description: Wall view shows one surface colour behind the pictures; the placeholder starfield and the inert WorldEnvironment are gone (owner - "one surface color for now, you can remove the starfield it was placeholder").
  status: done
  commits: [00f8a560]
- id: P70
  description: With no sidebar the board sits centred in its picture - the slide shifts it centre to centre, the Entrance row with it (owner - "in wall view the center grid board isnt centered").
  status: done
  commits: [00573e4b]
- id: P71
  description: The map's possible-cards list draws its cards' PARTS loose (rank numerals, suit icons, "+1", a label) with only three card bodies - a partial possible card (a type, stamp, skill, suit or rank alone) has no body because the body is the type polygon (traced by the P64b-2b review, card_visual.gd ~246-249; booster_template.gd ~76-85 get_possible_preview_cards). Owner (thirty-second round): "c: icons, not cards" - each possible part as a small labelled icon in a grid.
  status: done
  commits: [36c20f0b]
  notes: 'For review round 4 (looks, not asked): the rank numerals and the skill "+1" are dark ink on the dark viewer backdrop; the 8x8 stamp/suit icons are tiny in 119 px cells; at 600x1000 a large empty space under the grid; every deck viewer now shows spare window width beside its centred columns and a click there no longer closes it; the sidebar preview reading of the forty-second round (a non-type part on a blank Paper body).'
- id: P72
  description: The menu's deck picker lives on the overlay at the UI scale and slides the sidebar in; every viewer is opaque (hud_background); a return never focuses a Pick behind a viewer (thirty-fourth round).
  status: done
  commits: [a8bd4f31]
- id: P73
  description: The start menu as ONE centred column (title, Play, the Play submenu BELOW Play, the bottom row wrapping) drawn at exactly the UI scale (thirty-fourth "c: pin to UI scale", thirty-fifth "one center column, but keep in mind this is not final UI for start menu. all visuals will be replaced with drawn art in the future as well.").
  status: done
  commits: [c523b64b]
  notes: 'For review round 4 (a look, not asked): at 600x1000 with the sidebar hidden the bottom row fits one line (~87% of the width) and wraps only once the sidebar slides in - read as the thirty-fourth round''s "can wrap"; wrapping at rest needs a new width limit (new tuning surface).'
- id: P58a
  description: Merge main into combine-sidebar-boardplan (the square-card commits 2b49618c, ab83344a, 93a1ee4c - CardVisual.CARD_ART_SIZE 38x52 -> 52x52, the card polygons in card_visual.tscn re-authored), per /merge-branches; conflicts resolved against both sides; the full gate as the new baseline (rows pinned to the old 40x54 card go red here - list them, re-point in P58b, do not weaken them here).
  files_touched: [solatro/Cards/card_visual.gd, solatro/Cards/card_visual.tscn]
  verification_command: 'the full windowed gate; git log shows a merge commit'
  verification_kind: suite
  status: done
  commits: [b4f4692c]
  evidence: 'Red baseline, 12 failures, listed in the merge message - P58b''s input. One is MERGE-INTRODUCED, not an old-size row: main''s editor save added three saved ShaderMaterials to card_visual.tscn (OUTLINE x2 guard the frozen-uniform regression).'
  notes: 'Owner: "a: merge main in here" (a merge, never a rebase). card_visual.gd changed on both sides (this branch: P5b move tween, P49/P50 rims, comments; main: the size and its comment block) - expect a conflict there. Record every red row with its old-size assumption; they are P58b''s input.'
- id: P58b
  description: One card size across the whole project (twenty-first round, the overseer''s recommendation) and every hardcoded card-size assumption found and removed - GDScript, shaders, tools, tests; every card holder (grid cells, the Entrance, every viewer, the chooser, the description preview, the sidebar's minimum width) sizes itself from the card size through container minimum sizes, the separations between cards included (twenty-eighth round); fonts and buttons out of scope.
  files_touched: [project.godot, solatro/Cards/card_visual.gd, solatro/Cards/card_outline.gd, solatro/Cards/outline_style.gd, solatro/Shaders/outline.gdshader, solatro/Shaders/fire.gdshader, solatro/Shaders/glow.gdshader, solatro/UI/play_area.gd, solatro/UI/Fx/fx_attachment.gd, solatro/UI/prop_layer.gd, solatro/Cards/Props/]
  verification_command: 'the suites that pin card geometry (Outline Pixels VisualLayers UiProps GridLayout GridView FxAttachment DragPlace Sidebar Spotlight GestureMetrics) filtered, then the full gate; by eye'
  verification_kind: snapshot
  status: done
  commits: [85b1e6d8, 3233a90b, 44f023f0, e750fc82, f789c4ab, 6473485a, 7784e687, 8a5f6b0b, 7623fb02, b2724d0c, 3eea92a6]
  evidence: ''
  plan: 'The one source is the GDScript constant (thirty-eighth round). Sub-steps, one gate each: P58b-0 DONE (the merge''s saved ShaderMaterials out); P58b-1 DONE (measured, no code); P58b-2 DONE (44f023f0: each type's drawn extent and exact staircase corners, read once from the sheet's alpha, drive the rig and the FX mask; POLY 40, WEDGE_CANDIDATES 8); P58b-2 round 2 DONE (e750fc82); P58b-2b DONE (f789c4ab, partial alpha is translucent body; the grid cells share the fill); P58b-3 DONE (6473485a, the KEY_LEFT viewer rows); P58b-3b DONE (7784e687, the rows click the viewer's backdrop); P58b-M DONE (measured: the slowdown was the rig's bone flags; POLY 40 = +0.76 ms on the burning screen); P58b-B DONE (3233a90b, the bone flags + a guard row); P58b-4 DONE (8a5f6b0b, a stale pinned constant; the row compares with the space beside the resting sidebar); P58b-5 DONE (7623fb02, AutosizeLabel.best_font_size measured the label's font-inflated size; a new label's font now syncs before its pop) - every square-card red is fixed; focused_board_zoom''s wide branch traced); P58b-6 DONE (b2724d0c: shader defaults gone, fx_editor/hoop derive, stale prose, five files swept; outline_style's glare slider limits stay literal - a cyclic parse reference - pinned by P58b-7's seam row); P58b-7 DONE (3eea92a6: one gap in art units at each holder's scale; the deck viewer in whole columns, centred; the glare slider seam row) - the first fully green gate since the merge, 8100 checks. For P58d's review: the pip row (Rank/Suit/Stamp x -12/12/0, 10 art units wide) now sits bunched mid-card with ~10 units of face each side (was 3) - the owner's call. Causes marked traced are code readings, not measurements.'
  notes: 'MEASURE FIRST: an audit (Explore on sonnet, then an implementer) of every literal that encodes the OLD card (38, 40, 52, 54 and their halves/ratios 19, 20, 26, 27, 0.73, 0.74 in a card context) in .gd, .gdshader, .gdshaderinc, .tscn, .tres under solatro/ - each hit classified: derives from CardVisual.CARD_SIZE already / a hardcoded copy (fix) / unrelated. Files known to name the card size: Cards/card_outline.gd, card_visual.gd, outline_style.gd, Cards/Props/{formation_data,formation_set,prop_visual}.gd, UI/{play_area,prop_layer}.gd, UI/Fx/fx_attachment.gd, Tools/{formation_editor,fx_editor,outline_atlas,spotlight_tool}.gd, Shaders/{outline,fire,glow}.gdshader, and ~15 test/visual files. The one value: a project Shader Global card_size read by every card shader and by CardVisual/GDScript (verify the engine''s global-uniform contract and cost first, rule 6 - if it disagrees with the recommendation, STOP with lettered owner options). Reference: the outline pass a199dc6f ("add art outlines and alerts and tool") - read how it threaded the 1-unit rim (CardVisual.ART_OUTLINE, CARD_SIZE = CARD_ART_SIZE + 2*ART_OUTLINE) through shaders, masks and tools. Split into steps by subsystem (outline/glare, fire/fx, glow/spotlight, props/formations, board layout) - one fix at a time, each red-then-green.'
- id: P58c
  description: The four tool bugs the owner saw in the editor after the square change - fx editor fire not wrapping the square''s corner; the prop position editor still assuming a rectangular card; the outline atlas editor''s glare still using the old card size in its shader; the spotlight tool''s glow outline ignoring the square''s bevelled corners (treated as a perfect square).
  files_touched: [solatro/Tools/fx_editor.gd, solatro/Tools/formation_editor.gd, solatro/Tools/outline_atlas.gd, solatro/Tools/spotlight_tool.gd, solatro/Shaders/fire.gdshader, solatro/Shaders/outline.gdshader, solatro/Shaders/glow.gdshader]
  verification_command: 'each tool shot by an in-repo shot scene; by eye; the owner''s visual review'
  verification_kind: snapshot
  status: done
  commits: [0eae10c0, 500ec38b]
  evidence: 'P58c-1 measured three of the four fixed by P58b (fx fire corner, atlas glare, spotlight bevel); P58c-2 the formation editor''s outline + the knife rescale.'
  notes: 'Owner: "common issue appears to be hardcoded card size across shaders with old size" - likely fixed by P58b''s one value; verify each tool afterwards and fix what remains (the spotlight glow must follow the card polygon''s bevel, not its bounding box). No mocks in tools (CLAUDE.md rule 9): the shots host the real scenes. Since P58b-2 the rig binds a type''s drawn extent once, in CardVisual._ready - a tool that swaps data on a live card (fx_editor, outline_atlas: check) keeps the old type''s extent (traced, not measured). outline_atlas._non_empty (~357) still reads alpha > 0.5 (no shipped result changes).'
- id: P58d
  description: The owner''s visual review of the square-card pass - every in-game view the card shape touches AND the four tools, before/after pairs (owner: "a: yes, all of them").
  files_touched: [solatro/visual-review/manifest.json, solatro/Tests/Visual/]
  verification_command: 'the review tool refresh; the Design Loop watch'
  verification_kind: snapshot
  status: done
  evidence: 'Round 4 shot on 62d82c0e+ (review.py shoot; shoot --base 9d7d1f2f = round 3''s tree): 47 shots, 45 with BEFORE (menu_focused_by_keys and score_line_pulse are new stills). New in the manifest: menu, menu_top, menu_focused_by_keys, menu_picker, menu_inspect, deck_over_possible_cards, score_line_pulse. The overseer read every changed AFTER/BEFORE and wrote each seen (Fable drafted from the pixels; reconciled); round 3''s crops dropped from the rewritten shots. AFTER re-shot on b9f5bdc7 (P83): every 1280x720 shot with a sidebar now shows the short band; the overseer read every sidebar_snapshot AFTER and rewrote 21 seens (a new random deal and map, the band) - menu_focused_by_keys shows P82''s fix; possible_cards flags a ''Talent pack'' map tag cut by the list (not in BEFORE) for the owner. score_line_pulse''s AFTER is from a second run of the scene (the shoot''s run wrote none). PARKED on the watch. Then cut to 17 shots per the owner's round-4 ruling (RULINGS): the 30 approved in round 3 left the manifest; grid1_overview and pip_row now say BEFORE is round 3's square tree and are there only for the page's smoothing.'
  notes: 'Shots: the board at 1/2/3 grids (overview and focused), the Entrance with a lifted card, a stacked cell, the deck/discard/rules viewers, the pack chooser, the description card, fire/fx on a card (the corner wrap), props/formations on a card, the outline and glare, the spotlight glow, the win/lose overlay, plus shot scenes for fx_editor, formation_editor (prop positions), outline_atlas and spotlight_tool. BEFORE: the tool shoots it on git merge-base main HEAD, which after P58a is main''s tip and already square - shoot BEFORE on the pre-square commit 0d5b6248 instead (shoot --base) and say so. Read every AFTER yourself and write its seen; every crop you look at goes in crops.'
- id: P20
  description: The SCRIPT ERROR reported in HudContainer.return_to_lock (key game missing from _locked_entry_by_screen) - closed as NOT REPRODUCIBLE on HEAD; a regression net lands instead.
  status: done
  commits: [80171ae8]
- id: P21
  description: R8 on an EDGE grid - FOCUSED on the last (or first) of three grids the scroll clamps, the grid sits off-centre (cells 1124..1500 in a window centred at 985) and its neighbour is wholly visible inside the window; P10 measured only the middle grid.
  status: done
  commits: [b2a74f87]
- id: P19
  description: The comment sweep P10 owes - test_grid_view.gd and grid_zoom_shot.gd leave compliant, code byte-identical; the five dead references in poker-patience DESIGN.md and NAMES.md resolved.
  status: done
  commits: [2bb0b55c]
- id: P18
  description: The comment sweep P6 owes - test_pixels.gd, fx_snapshot.gd, player_settings.gd and (owed by P16) Tests/Support/pip_suit_test.gd leave compliant, code byte-identical.
  status: done
  commits: [ca4fa890]
- id: P17
  description: The comment sweep P9 owes - game.gd and test_interaction.gd leave compliant, code byte-identical; sidebar DESIGN.md loses its three dead file references (~220, ~225, ~485).
  status: done
  commits: [30143594]
```


## Viewer paths (the owner asked "is there anything i missed?") - each a row in P33 or an owner question
Covered by the ruling: keys stay in; click beneath blocked / click outside closes; close clears focus; hover describes, click sticks; X only while sticky; cancel unsticks then closes; Deck toggles; edge key -> sidebar; no Travel/Deck on a card description.
Not covered - built on the reading given, to confirm: (1) opening a viewer by pad/keyboard lands the focus on the FIRST card (else keys have nowhere to start); (2) RULED: a hover over another card shows that card while hovered; the sticky one returns when nothing is hovered or the pointer reaches the sidebar; (3) a viewer opened while a BOARD card is lifted or its description locked: the board lock is suspended and restored on close - built: restored; (4) the possible-cards viewer auto-opens on the first click of a pack node - with click-outside-closes, the NEXT map click closes it rather than picking a node; (5) RULED: Take, Deck and every other button are NOT accessible while a sticky description shows, until it is cancelled; (6) closing a viewer with nothing sticky on the MAP returns the sidebar to the picked node's description (Travel live) - or hides it when no node is picked (R1); (7) RULED: one cancel unsticks AND closes; the X exists only on a sticky description (an unsticky one closes by itself when the card is no longer hovered); (8) the X while sticky: unsticks only, or closes the viewer too? built: unsticks only; (9) wheel / page keys scroll the viewer, never the screen beneath; (10) the sidebar's own Deck / Possible cards button while its viewer is open = close (the toggle), from the pad too.

## Verified vs assumed
- The research behind every ruling's "overturns" line: two read-only Explore agents on `opus`,
  file:line cited in their reports; not re-read by the overseer.

## Open bugs
Every open line moved to `solatro/todo.md` "## Open bugs from the playtest-fixes stream"; pass
`--handoff solatro/todo.md` to `gate.py` to match a failure against it. What stays here is the
rule-audit tally, input to the close's Reflect step (item 10).
- TOOLING, rule audit - session of P83-P91 (2026-09-30): CAUGHT - measure-first stops (the spotlight's dropped zoom, P87's stamps and missing cream role, P88's split, P90's overflow table, the lag's real shares - the save thread was innocent); Fable checks of mechanism questions (the lag fix: two drafted options would have refused every placement / left the card lifted; P90: the no-re-layout option); Fable per-step reviews (P85's frame row blind to a hidden bar; P87's callerless guard; P90's vacuous layout row); the full gate (P85's four SIDEBAR reds a one-suite filter hid); the mutant rule (P86's overlap check never red); the owner's eye (round 4 re-asked approved shots with stale 'pre-square' seens; the spotlight too small). Reviewer latent findings REPRODUCED 2 (P85's right-edge check via a 28-vs-8 mutant; P90's empty-list pass via a mutant), REFUTED 0. FALSE ALARM - two gate reds from a shared box (TP-85; UI PROPS + GRID VIEW TP-105), each ~30 min; doc_check --changed counted another agent's in-progress files. COST - ~16 gates plus 2 reruns, four of them for test/doc-only review follow-ups - propose: such a follow-up rides the next step's gate; the gate verdict + leak-scan one-liner typed ~14 times - propose: gate.py prints the leak-line scan itself; the mark-row-done-with-hash script typed ~8 times and a PIL tiling snippet ~10 times - propose: two small tools under .claude/tools (mark a handoff row done with its commit; tile shots before/after), each its own small reviewed step; the watch never woke (Done not pressed) - a verdict told in chat is a handback (RULINGS), the overseer reads review.json. CEREMONY - the ~300-line handoff rule (this file ~600 lines, the Open bugs list the bulk) - propose: the intermittent ledger in its own file the handoff points at, as the rulings did.
- TOOLING, rule audit - session of P73-P82: CAUGHT - Fable per-step reviews (P64b-3b: a frozen show's lost focus, Play focused behind the picker's viewer, a resolved show's Continue lost - all reproduced; P64b-3f: a SCRIPT ERROR on Left in the menu's viewer and a swallowed Left - reproduced; P77: a focusable embedded Window taking the root's input; group passes: a stale Continue, stale docs); reviewer latent findings REPRODUCED 5, REFUTED 3 (P64b-4's lost-run Continue, P64b-3e's missing writer, P78 b's 'viewers move'); mechanism-question checks (Tab: a missing option; the overfill: the real callers); measure-first stops (the Tab premise, P71's design, the overfill and the menu's premise, P80's race, P77's root scale 1, P66's hang = a minimized window); the gate (the _deal_next_mark third count -> P80). FALSE ALARM - commit-gate.ps1 blocked ~15 test_sidebar commits on two duplicate pairs already on HEAD (each needed [dup-ok]) and reads [dup-ok] only from the command text, not a -F message file; the auto-mode classifier refused a handoff commit after that workaround (the owner said continue). COST - two implementers ran gate.py themselves (~15 min each): the implementer definitions say 'Run the full suite before reporting done' while /plan-run and this handoff say only the overseer runs the full gate - propose rewording it to the brief's filter; an implementer's mutant chain outlived its report with a pending copy-back over menu.gd (rule added to the implementer definitions); classifier no-verdict outages (5 in a row stopped a turn); a double-backgrounded gate lost its notification; a handoff script whose assertion failed was followed by a ';' commit (chain the commit with &&). CEREMONY - the ~300-line handoff rule (~730 lines) - propose again: give the rulings block its own file. The owner approved all four proposals ("yes make the fixes"): the implementer definitions' full-suite line and the rulings file (71f3216d); the context-threshold hook .claude/hooks/context-handoff-nudge.py (main-thread Stop, once per session; fired live at 83% of the window; then an absolute token count: the evidence pointed at 200k (the Opus 5 system card's long-horizon eval compacts at 200k; this session's measured main-thread cost was lowest closing at 200-250k, ~$54 vs $79 unclosed) and the owner chose "lets go with 500k." - fewer restarts for some extra cost); the commit-gate fix: only pairs the staged diff creates block, and [dup-ok] is read from -F files too (dup_check --staged --new-only).
- TOOLING, rule audit - session of P75-P58e-3, P76: CAUGHT - the Fable broad group pass (p73-wip's wholesale restore would have reverted four steps - critical), Fable per-step reviews (the zero POLY headroom, the resample skip, one-call helpers), measure-first stops (6: the Shader Global premise, the corner model, the board-centre cap, the wall-view cost, the SubViewport focus, TP-92's cause), the full gate (the OS-window resize, the merge's 48% slowdown via a timeout), the OUTLINE saved-ShaderMaterial guard (main's editor re-save), the mutant rule on every new row. FALSE ALARM - godot-needs-private-appdata.ps1 blocked a python edit whose TEXT named 'Godot editor' (again - match a launch, not a substring); block-process-kill.ps1 blocked an explicit-PID foreach (one explicit Stop-Process per PID passed); one reviewer finding refuted by measurement (P58b-7's scrollbar double count). COST - the full gate per step (~15 min, ~22 gates; kept); a permission-classifier outage blocked an implementer's writes (8 failures, retried); the classifier refused ending orphaned Design Loop watch processes (left to the owner); ~18 hand-typed handoff-edit scripts and a per-suite diff script typed per gate - propose: gate.py compares per-suite counts with the PREVIOUS completed gate (today it compared a stale one: OUTLINE 43 -> 51 across two gates that were both 51), which retires the per-suite script. CEREMONY - the ~300-line handoff rule (672 lines; the verbatim rulings ~190) - propose again: count the rulings block out, or give the rulings their own file the handoff points at.
- TOOLING, rule audit (the /handoff Reflect step 3 tally; add to it each session). Session of P64b-P74: CAUGHT - Fable per-diff reviews (a real defect in most: the deck back empty, the menu click-outside strip, an undeleted helper, focus behind an opaque viewer), measure-first stops (6 premises overturned into owner questions), one Godot at a time, mutant red (4 rows proven on a restructured scene). FALSE ALARM - godot-needs-private-appdata.ps1 blocked 2 commands that only MENTIONED run_tests.py (a handoff edit, a docs heredoc): propose matching a launch, not a substring. COST - the full gate per step (~13-14 min, ~25 gates) - kept, it caught TP-63/GRID VIEW/P73 reds a filter missed. CEREMONY - the handoff's ~300-line rule (620 lines; the verbatim rulings block alone is ~160) - propose re-measuring the limit or giving the rulings their own section the count excludes; red-then-green satisfied while two rows still compared a value with itself (P65b, P73) - the mutant rule now covers it.
- TOOLING, rule audit - session of P91's follow-up to P96 (2026-10-01): CAUGHT - the shadow comparison a brief asked for (P92: 28 differences in 15731, a cache stale where the scan was fresh - the earlier Fable check of the options had passed it); the Fable check of the stop (not an owner question; it traced the juggling miss, REPRODUCED red - reviewer latent findings reproduced 1, refuted 0); measure-first stops (fx_cost hosts no card; P92; P96's premise - a harness artefact, not a product bug); the visual-review README's reachable-state rule (the game spotlight restaged on a really scored row). FALSE ALARM - an implementer's 'product bug' (a Deck click closing a scrolled list) was its own press-only wheel: one medium round to refute. COST - a new session's scratchpad holds no last-gate state, so the first gate prints no per-suite diff - propose: gate.py keeps its last-gate state in one untracked place that outlives a session; the whole-file comment sweep on touch added 133 + 40 comment-only findings' worth of lines to two one-line fixes (sweep_check proved them, but the diffs are noise) - propose: a file over ~50 legacy findings is swept in its own step, as the close already does for game.gd; Sidebar alone (~770 s) exceeds an implementer's 10-minute foreground cap, so every Sidebar filter is a background wait and a 'stopped with background work' notice - known, kept; the handoff-edit script typed 8 times and the leak-line scan 4 - the two tools proposed last session are still unbuilt. CEREMONY - none new. ROUTING, from the implementers' own lines: P91's follow-up items and P96's round 2 'could go lower' (a named inline, a named scene property); P92's first round 'needs medium' on its stop. Recorded this session: tests-that-prove-nothing item 11 (a wheel notch is press AND release), brief-premise-is-a-hypothesis (a speed-only rewrite gets a shadow comparison).

## The close (in progress - /plan-run "Closing the run")
Overseer Opus 5.5; every reviewer Fable, read-only. Ground truth and every review ran on 69b975bb; no source file has changed since. IDs (A1, B1, T1, C1, F1) are this section's own.

**Done:** 1 doc_check full (0 errors); 1a plan-auditor -> solatro/AUDIT.md (107 PASS, 0 FAIL); 2 adversarial-review, two passes (areas listed below); 6 /fx-verify (three LOOKS WRONG, each also read by the overseer).
**Also done:** 3 /code-review - the Fable finder (C1-C4) and its ONE verifier over the 15 candidates (verdicts below; they outrank the finders' labels). 4 test-surface - DONE in two passes (T1-T11, U1-U14); unread: test_sidebar's P64 / P64b-2a..2c hunks (d7936ddf, 4ae86508, 594589ca, 0c2b3979).
**Not started:** 5 /simplify (four angles serially, as a Fable subagent; the Open bugs lines marked FOR /simplify are its input); 7 the fixes; the whole-file comment sweeps; 8 /docs; 9 consolidate-memory; 10 Reflect and record; 11 delete the temporary plan documents.

**The close runs in a Linux cloud container.** Owner (verbatim): "a: Port, gate here". 227197a merged claude/godot-cloud-test (Godot 4.7.2 via `bash .claude/tools/cloud_setup.sh && source /opt/godot/env.sh`); b93de15 made gate.py and solatro/tools/run_tests.py OS-aware (XDG_DATA_HOME, `pgrep ^Godot`, xvfb-run, `--audio-driver Dummy` with no display). No repo hook fires there (all PowerShell): the subagent cap and commit gate are held by hand.

Ground-truth gate on 2fc1961 (Linux): GREEN, exit 0, `ALL 51 SUITES: 10017 CHECKS PASSED [19 placeholder warnings]`, 1150 ObjectDB, 24 resources, grab-focus test_plan_visuals.gd:1514 x1, test_wall_focus.gd:827 x3 - identical to the Windows gate; no Godot left.

**Resume here:**
1. Done (above).
2. /simplify (item 5), read-only, no Godot - running.
   Item 7 so far: A1 12d8746 (red reproduced: SIDEBAR missing key 'game' at hud_container.gd:318; the claimed null lock did not reproduce - the error aborts before lock_to; the row opens Discard, Deck is empty after End). TP-63 eba6c12 (test cause: settle_on accepted a frame with no physics tick while the Entrance card was mid-move; 20/20 filtered green; a grid-1 mutant goes red). Gate on eba6c12: GREEN, 10057, 1150 ObjectDB, 24 resources.
   Forty-sixth round (RULINGS): A6 closed, no change; B4 is a fix - a drag pan's landing focuses the grid; A4b is a fix - a right-click over a stuck viewer card unsticks it. B3 ee95bb9 (undo re-anchored the scroll: 271 -> 380; the anchor moved to open_show_view; gate GREEN 10052). B4 04277a7 (a FOCUSED drag landing calls focus_grid; row in test_drag_place.gd; a cancel mid-pan now focuses too). B4b 3ce874b (one landing, `_land_the_pan_on`, for drag, pan keys and swipe; the nearest-grid pickup row re-pointed mid-pan, mutant red; gate GREEN 10042). A4b 29bc11a (the chooser's STOP cards swallowed the right press - cards_viewer.gd:133 unsticks; the deck viewer already closed on a right-click; gate GREEN 10073). Owner question: with a card stuck, a right-click on EMPTY chooser space does nothing - does B15's cancel-from-anywhere want it to unstick? C4 bbbb623 (pack size from get_frame(); 14 MAP_* keys in Locale/localization.csv; gate GREEN 10061). Owner question: the map's "3 acts to reach it" has no data source (Levels/game.gd:64: a show has no act count) - stale? F2 ebf4b4c (a typeless face-up card drew no body - card_visual.gd draws the blank frame; by eye the "12" sits on a full card; gate GREEN 10091; for the owner's visual review: rules_viewer before/after; part_icon.gd:111's paper-type copy is probably now removable - FOR /simplify). F3 measured (the idle float bobs the next clipped row's top rim into view; owner: leave as built). F1 96d2e52 (the wall editor built each screen without the wall's HudContainer, so each made its own inside its picture; by eye the focused menu now fills the window; gate GREEN 10084; open, tool-only: the editor never calls slide_to, so a focused game picture there shows no sidebar). T1-T5 e0bc155 + fd8bb9f (real input through the root; every old row green under its mutant except T4, refuted - its row re-pointed to a hovered card, mutant red). U6 d82a8b0 (sampled mid-slide; mutant red). T6 refuted (old row red under its mutant; its else branch still passes a rebuilt board - unproven). T7 measured (map.gd:154 unreachable, 0 of 34 arrivals) and exposed a product bug against the playtest ruling "if only one possible node option ... automatically select it": T7b e6f1466 auto-selects after a won show and after Take, the dead branch deleted; for the fix commits' adversarial pass - the Take pick relies on signal connection order, and _continue_to_the_map now waits for the slide (three callers). Gate on e6f1466: GREEN, 10104, 1150 ObjectDB, 24 resources. Owner question: back on the map from a frozen show or from the wall, nothing is auto-picked - does the ruling cover that? Unfiled intermittent: test_leaving_mid_walk_onto_a_pack_never_strands_the_chooser failed its sanity check once on HEAD ("landed... -- start_menu"). U1 + U4 536ecca (mutants red). U5 refuted (old row red under its mutant). U3 and U5's vacuous scroll_vertical-write check: follow-up running. U2 -> /simplify V5: the overview gap knob (an asked one-card width) never reached the output - the eighth round rests the gap on the score-label gutters (116 px here vs a 54 px card); raised above the floor, the overview set measures off-centre by asked-minus-floor per gap (34.86 px, 2 grids). Delete the knob (rule 8) and assert gap == gutters, rather than fix a centring path no ruling reaches. U3 + U5 defa0af (U3 red under a survivor-choice mutant in _on_grid_removed; U5's vacuous write check deleted).
   Item 5 /simplify (relaunched - the first launch died with the owner's interrupt at 01:34 and wrote nothing): verdicts V1 outline_atlas.gd:339-342 DBG2 print - delete; V2 hud_container.gd:489-493 keep branch - LIVE, leave; V3 the three label/panel scenes no production scene instanced - deleted in 67d7e11; V4 duplicate_state epochs - leave; V5 overview gap knob - dead (eighth round), delete with its tests and NAMES/DESIGN lines; V6 part_icon.gd:110-116 paper copy - removable; V7 the T7b auto-select - one deferred home, public controller method (fixes the signal-order dependence). New: S1 game_view.gd:55-57/320-322 + main.gd:564-565 wall-camera binding written never read - delete; S2 map.gd:170/173 two handlers on viewer.confirmed - fold; S3 (suspected) hud_container._apply_container_rect re-fits content every slide frame - measure; S4 (suspected) play_area.gd:2096 reaches into the scroll addon's private _end_content_drag; S5 board_card_window_px has only a test caller - leave (the seam is a test's). dup_check: no new production pair. Fix commits' adversarial pass (Fable, over 12d8746..defa0af): no plan drift. R1 CONFIRMED (96d2e52, tool-only): each wall-editor _repack() builds a new Map whose mount_buttons adds another selection-buttons row to the one wall container's description panel; old rows are never freed (Map._exit_tree frees only an unparented row). R2 suspected = the A1 owner question (B14 vs B17-B19). R3 suspected: main.gd:574-575 `await _focus_picture(&"map")` returns at once while _move_in_flight, so returned_from_game could auto-pick under the game screen - measure whether Continue is reachable mid-move. R4: grid_zoom_shot.gd:87's "uncommitted_panned" shot now re-zooms (B4b) - its meaning changed. V1 5cdb301, V3 67d7e11, S1 c54705f (deletions; gate GREEN 10108; LeakCanary's OBJECT_COUNT check fails when the suite runs ALONE, on the parent commit too, and passes in every full gate). R1 35f7929 (Map._exit_tree frees its mounted row; gate GREEN 10096). Left: AUDIT.md:136 still lists the DBG2 print (FOR /docs). R3 measured unreachable (the leaving screen pauses at 0.002 s, input unlocks at 0.037 s of a 0.060 s move; harness geometry only). V7+S2 8d711e8 (Map._hand_the_map_back, a deferred public auto_select_if_single; a reordered-close row red on the old code; gate GREEN 10107). Leak sentinel's unreachable hover-panel branch 76637d1 (+ that file's comment sweep, comment-only). V6 fe7eacb (part_info drops its paper copy; 0 sidebar pixels differ; the part-description check now reads the drawn body, 28 red under a bodiless mutant; gate GREEN 10110). V5 01eb3fe (the overview gap knob deleted; 40 render frames pixel-identical; rows assert gap == the gutters; gate GREEN 10119). S4 left as is: the reach-in is into a vendored addon, and a public alias there costs every addon update a merge. Test row to repair: test_a_game_viewer_left_open_across_back_changes_nothing_on_the_map branches on whether its arrow lands on a pack (item 20). Queue now: S3 (measure) + that row (running), V7+S2, V6, V5, S3 (measure first), S4; then the fix commits' own adversarial pass, the comment sweeps, /docs, consolidate-memory, Reflect, delete the plan docs. F2/F3/F1, then T1-T7 and U1-U6.
   Unverified, from TP-63's measurement: adding a grid leaves the board 244 px left for one physics tick (a possible one-frame flicker; seen only in the fixture). A1's open question: chart B14 (outcome keeps the description) vs B17-B19 (processing shows the HUD) - the code follows B17-B19.
3. Item 7: every finding is a claim - an implementer reproduces it RED first, one fix at a time, a full gate between, "touch only the comments this fix changes". Order, by the verifier's verdicts: A1, A6, B4, B3 (its red test is the measurement), C4, then F2/F3/F1 (measure the cause first), then the test repairs T1-T7 and U1-U6 (each proven with its mutant; test-only repairs in different suites may share one gate). Refuted, no step: A2, B2, A3, A4, A5, B1, B5, C1, C2, C3. The fix commits get their own adversarial pass.
4. Owner questions gathered so far (lettered options when asked): A6 (the twentieth round's words are "c: reset after each Travel" - does a mid-walk wheel notch that leaves the map zoomed at arrival break it; the verifier reads yes); B4 (a FOCUSED drag pan lands without focusing the grid - should the landing focus it, as Left/Right does; that would also fix the resize); the verifier's note under A4 (a right-click over a stuck viewer card unsticks nothing - does R5/B15's cancel-from-anywhere cover a viewer card); B5 only if the owner meant disk resumes too; plus the four already under Next up.
5. For /docs (from the audit): prune the Open bugs lines the audit lists as stale (AUDIT.md's last section); P91's row misnames the glow styles; P52 and P41 (2) are superseded by P64 and the ledger should say so; the Open bugs mention of HudContainer.resize_preview is stale (no such function).

Item 1 doc_check full: exit 0, 0 errors, 10 warnings (standing comment backlog; 4 dated lines in HANDOFF_playtest_fixes.md).

### Item 2 adversarial-review, pass A (areas 1-3 read; play_area ~120 lines only; 4,5,6 NOT read)
CONFIRMED (claims - reproduce before fixing)
- A1 hud_container.gd:318 `_follow_the_viewers_sticky` reads `_entry_by_screen[_active_screen]` with []; show_description (557-559) drops publications mid-cascade without writing the key. Sequence: place a card so a cascade runs (Game.processing), press Deck (live; game_view 352-355 holds only Submit), click a listed card -> stick_to -> ... -> line 318 missing key SCRIPT ERROR. Red test: GameView fixture + real HudContainer, scoring placement, during processing press deck_ui/Button, click viewer.cards().controls[0]; assert no SCRIPT ERROR and is_locked() (or Deck held while processing).
- A2 world_map_controller.gd:316-331 `_pressed` set on left press, cleared only by a release reaching this _unhandled_input; a release consumed by root GUI (sidebar Deck/Travel, overlay Back row) never reaches the picture (wall.gd:171-180) -> next motion pans with no button held, hover naming stops. Red test: press on map, release on overlay button only, motion 20px over map; assert camera.position unchanged, controller._dragging false.
SUSPECTED
- A3 hud_container.gd:325 find_custom -1 index = last hosted viewer on a double close (no one-device sequence named).
- A4 wall_overlay.gd:82-87 right-click over the pack chooser routed as cancel into the map picture (same shape as the listed deck-picker latent); unconfirmed whether right button is ui_cancel at world_map_controller.gd:301.
- A5 card_visual.gd:886,911,936,971,981,989 CardEnvironment.CURRENT.get_delay() unguarded while CURRENT null on the map after a WON show - no caller named.
- A6 world_map_controller.gd:357-360 vs 456: return_to_fit at START of move_to; wheel during walk (310-313, _zoom_at not gated by _moving) leaves the map zoomed at arrival. PLAN DRIFT vs twentieth round "c: reset after each Travel - the map returns to the fit whenever the token travels".
Known items re-read: P53 latent (game_view.gd:168-169) CONFIRMED by reading. Area 1 (implementer cache) CLEAN. worldgen copies: .gd identical; an untracked `~...dll~RF580659a4.TMP` debris file under solatro/addons/worldgen/bin.

### Item 1a plan-auditor -> solatro/AUDIT.md (untracked): 107 rows, PASS 107, FAIL 0, UNCHECKED 0 (13 spot-checked only: P7 P14 P17 P18 P19 P20 P30 P31 P42 P58c P79, worldgen source half of P25)
- P58d row stale: in_progress -> done (RULINGS:170 round 5, 13 approved).
- Stale Open-bugs lines to drop (handoff line numbers at 69b975bb): 502, 503, 507, 544, 506, 527, 513, 555, 514, 537(probably), 546 second half, 553, 558, 578 first item, 576, 593 last clause, 594, 516 second half (docs give 31 again).
- Still true (keep): 519, 520, 521, 522, 531, 536, 554, 559 (test_sidebar.gd:7547), 572 (:8532), 573 (now EIGHT bare frame_post_draw: 1550 1571 1587 5340 6849 6850 8118 8119), 586, 598, 603, 604.
- For /docs: P91 row misnames glow_beam/glow_circle (FxGlowStyle literals; spotlight derivation real, fx_spotlight_style.gd:21); P52 and P41(2) superseded by P64 - ledger should say so; P61 commit message vs HEAD (sidebar_snapshot.gd:886-897 moves token WITH _current).
- Tooling: godot-needs-private-appdata.ps1 blocked a read-only bash command that mentioned a .py filename (text match).

### Ground-truth gate on 69b975bb: GREEN, exit 0
ALL 51 SUITES: 10034 CHECKS PASSED [19 placeholder warnings]; 1150 ObjectDB, 24 resources; grab-focus warnings test_plan_visuals.gd:1514 x1, test_wall_focus.gd:827 x3; no Godot left running.

### Item 2 adversarial-review, pass B (play_area.gd whole, game_view.gd whole, wall_picture/wall/wall_input whole, card_visual 520-720 + 1000-1130, fx_attachment 205-404, spotlight; NOT read: all_tests.gd, shader bodies)
CONFIRMED (claim)
- B1 play_area.gd:1669-1673 with 1649-1659: in OVERVIEW on a 2+ grid board, Left/Right on a focused ENTRANCE card is consumed by _consume_as_grid_select (moves selected_grid, grabs that grid's origin cell), so the Entrance's own arrow chain (_link_arrow_stops 2959-2968) is unreachable. Red test: 2-grid board, open_zoomed_out(), _entrance_stops[0].grab_focus(), push ui_right; assert focus owner == _entrance_stops[1].
SUSPECTED
- B2 play_area.gd:2089-2100 _end_the_content_drag: drag begun on the board, released over a sidebar Button -> content_dragging latched (same mechanism as A2; if A2 reproduces, test this).
- B3 play_area.gd:601 setup_gui -> _anchor_scroll_to_bottom.call_deferred() runs on every undo (GameView.rebuild :433), comment :988 says ON ENTRY ONLY; an undo on a FOCUSED grid with a deep stack may shift the board vertically.
- B4 play_area.gd:101-107 _re_fit_after_inset_change: a resize after a Left/Right pan in FOCUSED re-aims at focused_grid, not pan_grid - view jumps back. No ruling says which grid a resize keeps (owner question?).
- B5 game_view.gd:140-142 + play_area.gd:1069-1079: a show resumed from DISK after relaunch plays the opening ease (new PlayArea, _opening_ease_owed true). PLAN DRIFT vs ninth round "Re-entering a frozen, resumed show: 'a: fresh show only'" - whether "resumed" includes relaunch is the owner's reading.
- B6 play_area.gd:1869-1875 + game_view.gd:598-606: future-only (an awaiting on_can_grab_stack) - not reachable today; record only.
Refuted/clean: P32 assert safe; P45 no migration code needed (fourteenth round "a: close, already done"); P80 ok; POLY 40/WEDGES 32/WEDGE_CANDIDATES 8 consistent, no stale counts.

### Item 4 test-surface review, pass A (NOT read: bulk of test_drag_place, test_grid_view, test_sidebar P85-P89 rows, test_wall_input, test_wall_render, test_wall_pause body, test_pixels, test_outline)
CONFIRMED (claims; each has a mutant)
- T1 test_ui_viewers.gd:648 test_a_click_on_a_listed_card_never_closes_the_viewer - item 11: _click() (:899) emits gui_input on the card. Mutant: drop control.accept_event() at cards_viewer.gd:132.
- T2 test_ui_viewers.gd:585 test_a_hover_describes_a_viewer_card_and_a_click_sticks_it - item 11: mouse_entered.emit()/_click by signal. Mutant: ControlCard mouse_filter IGNORE.
- T3 test_ui_viewers.gd:669 test_an_arrow_off_the_lists_edge_never_reaches_the_screen_beneath - item 11: asserts only modal_verdict()==KEEP. Mutant: host stops set_input_as_handled() on KEEP.
- T4 test_ui_viewers.gd:943 test_take_ignores_the_selection - item 3/12: both branches unstick() before Take, so nothing is picked at the press. Mutant: confirm emits [_cards.sticky] when sticky != null.
- T5 test_ui_viewers.gd:410-416 test_a_deck_viewers_rows_stand_the_gap_inside_its_window - item 20: branches on bar.visible not fixture count. Mutant: _scroll.vertical_scroll_mode = SHOW_NEVER.
- T6 test_sidebar.gd:4853-4860 test_accepting_the_exit_x_hands_the_focus_back_to_the_board - item 20: if/else on product state.
- T7 test_map_traversal.gd:173,183 - item 12: row calls controller.auto_select_if_single() itself. Mutant: delete the call at Levels/map.gd:154 (SIDEBAR may cover arrival through Main - unread).
SUSPECTED
- T8 test_sidebar.gd:7195-7199 _check_the_row_heads_the_description vacuous when X hidden.
- T9 test_wall_focus.gd ~999 + 2 sibling rows write get_tree().paused = false (item 9).
- T10 test_sidebar.gd:2183-2189 _zoom_the_map_under_a_viewer: press-only wheel via main.wall._unhandled_input (fixture only).
- T11 unbounded waits added by the stream: test_sidebar `while _map.controller._moving`, `while view._combo_tween.is_running()`, `while main._current_focus != &"start_menu"` x3; test_wall_focus `while main._move_in_flight` x4.
Item 14: none (191 funcs grepped). Item 17: none. Listed: test_sidebar.gd:8216-8233 still branches (confirmed). P92a/b rows sound (epoch mutant goes red).

### Item 3 verifier (one Fable pass over A1-A6, B1-B5, C1-C4; static, engine questions from Godot's scene/main/viewport.cpp on GitHub master - not diffed against 4.7.2)
- A1 CONFIRMED, player-visible error. The clean repro is the OUTCOME screen or End (processing stays true until Continue/undo, Levels/game.gd:909,923), not a placement cascade (lock_to wrote the key there). Chain: the key is erased by dismiss_description (hud_container.gd:521-524) or the pointer leaving the board (play_area.gd:3647-3650 -> hud_container.gd:289-298); Deck is live (game_view.gd:352-355); a click on a listed card -> cards_viewer.gd:137-139 -> main.gd:480-481 -> hud_container.gd:556-559 returns without writing -> :317-318 missing key. Worse than claimed: it leaves _locked_entry_by_screen[game] = null, so is_locked() is true with a null lock and every later return_to_lock (:613-617) errors again. Red test: test_sidebar.gd, _start_game_fixture() + _end_the_show_by_its_button(view) (:3691), no card hovered, a Logger counting errors (as _FocusWarnings :5002), press Deck, a real press+release at the first listed card through the ROOT viewport; assert zero errors and no null lock.
- A2 REFUTED, B2 REFUTED: a release is delivered only to the control that took the PRESS (`if (!gui.mouse_focus) return;`), so a release over a root Button after a press on the picture is unhandled, forwarded by wall.gd:171-180, and clears the latch. Docs/source reading, not measured here.
- A3 REFUTED: every highlight_cleared emitter fires with the viewer still hosted; a second _close() is blocked (deck_viewer.gd:63-64). hud_container.gd:325 is still an unguarded find_custom - latent.
- A4 REFUTED as claimed: the right press is routed into the map but ui_cancel has no mouse button (project.godot:70-75), so the map does nothing. Note: a right-click over a STUCK viewer card unsticks nothing (choice_viewer.gd:122-125, deck_viewer.gd:195-198) - an owner question.
- A5 REFUTED: card_visual.gd:748 returns for every context but PLAY_AREA; the anim_* callers are board-side only.
- A6 CONFIRMED statically, minor: world_map_controller.gd:456 resets at the walk's START, :310-313 _zoom_at has no _moving gate, :459-463 arrival resets nothing. Red test: test_sidebar.gd, _start_map_fixture(), _focus_map, select a reachable node, press Travel, _push_wheel_notch (:2193) while controller._moving, await node_entered; assert _zoom_in == 1.0 and _check_map_fits_the_space (:2119).
- B1 REFUTED as intended: the overview's Left/Right ARE the grid select (second playtest, sixteenth round, seventh round 2b); the Entrance chain is reachable in FOCUSED mode.
- B3 PLAUSIBLE: undo -> game_view.gd:433-435 rebuild -> play_area.gd:601 _anchor_scroll_to_bottom, against the comments at :947-949 and :988-989 ("ON ENTRY ONLY"). The measurement: test_grid_view.gd, a one-grid FOCUSED show, one cell stacked until the v-scroll bar's max_value > 0, settle, record scroll_vertical, view.game.undo(), assert it unchanged.
- B4 CONFIRMED statically, minor: a FOCUSED drag pan lands on pan_to_grid without focus_grid (play_area.gd:2089-2100, :1460-1463), breaking the invariant stated at :1155-1157; a resize then re-fits at focused_grid (:101-107). Red test: test_grid_view.gd, 2 grids, focus_grid(0), pan_to_grid(1) or a real drag release, resize the host, assert pan_grid == 1 and grid 1 centred.
- B5 REFUTED: the ninth round's question text is "Re-entering a frozen, resumed show" - a show already on the wall; a Continue from disk builds a new GameView. The comment at play_area.gd:1068 is ambiguous - reword at the sweep.
- C1 REFUTED (tool-only: Tools/wall_editor.gd:552). C2 REFUTED (no null-style producer). C3 REFUTED (unreachable by one device; a one-frame window).
- C4 CONFIRMED, cosmetic: map_hover_panel.gd:42 writes "5" where BoosterTemplate.get_frame() (booster_template.gd:16-17) is the real count, and :41-50 plus map.gd:220,224,322-324 are untranslated literals. Red test: test_ui_viewers.gd, StubBooster (:742) with get_frame() 3, a booster node, assert MapHoverPanel.get_info(...).body contains "3 cards".

### Item 4 test-surface review, pass B (read: test_drag_place, test_grid_view, test_wall_input/pause/render, test_outline, test_pixels stream diffs; test_sidebar hunks of 39241dc3, 67449ddb, 52934da9, 2367ee91, 336b4a98)
CONFIRMED (claims; each has a mutant)
- U1 test_drag_place.gd:1810 test_a_cancel_that_steps_out_lands_first_and_is_superseded - items 3 + 6: the pan lands on grid 1 and resting_grid() in OVERVIEW is also 1 on the three-grid fixture (play_area.gd:1139-1144), so :1832 compares two values that coincide. Mutant: drop the step-out's rest_board() call.
- U2 test_grid_view.gd:1005 run_the_overview_draws_the_grids_close_test (:1028, :1047) - items 6 + 3: expected gap = maxf(asked, the two gutters) and the floor wins on this board, so the one-card-width knob never reaches the measured number. Mutant: PlayArea.overview_grid_gap_px returns half a card width.
- U3 test_grid_view.gd:2168 run_the_overview_view_and_cursor_agree_after_a_removal_test (:2203) - item 5: the two surviving neighbours are equidistant by construction, so `a < b or is_equal_approx(a, b)` is always true. Mutant: remove the removal path's re-centre in OVERVIEW.
- U4 test_grid_view.gd:1438 run_the_board_edge_does_not_move_test (:1469-1483) - item 6: every assertion is on the wall Camera2D, which no pan path writes. Mutant: delete the OVERVIEW early return in _bounce_board (play_area.gd:1504).
- U5 test_grid_view.gd:2822 run_the_board_does_not_scroll_while_it_fits_test (:2845, :2862) - item 10: a scroll_vertical write "moves nothing" because SmoothScrollContainer rewrites it each physics frame, not because the range is zero. Mutant: grow the board floor 40 px past the page - the two write checks stay green.
- U6 test_sidebar.gd:8664 test_the_menus_viewer_fades_with_the_sidebar_across_a_leave (:8679-8683) - items 5 + 16: one sample, alpha == slid, with no 0 < slid < 1 assertion. Mutant: hold the viewer's alpha at 0 until the slide completes, then 1.
SUSPECTED
- U7 test_grid_view.gd:2972 run_a_mode_change_eases_into_place_test (:3045): `... or not scale_changes` (item 20).
- U8 test_grid_view.gd:2746 _wheel_the_board (:2761): 30 process frames as a settle (item 16).
- U9 test_grid_view.gd:2705 run_an_edge_touch_is_not_an_intrusion_test: exercises only the suite's own _rect_intrudes (instrument self-test).
- U10 test_grid_view.gd:1800 run_overview_arrows_select_a_grid_test (:1873): sets DEFAULT_BOARD_ZOOM, a state the shipped overview never enters (item 12).
- U11 test_sidebar.gd:7447 _check_the_outcome_is_centred_down_its_space: slack absorbs the 2.5 px residual at 600x1000 (item 7).
- U12 test_drag_place.gd:830 test_a_rebuild_under_the_outcome_overlay_rests_on_nothing (:843): a same-value write to container_slide_duration mid-row - the no-op broadcast (item 8).
- U13 test_wall_input.gd:93 _build_wall: get_tree().paused = false for every row (item 9, pre-existing).
- U14 test_pixels test_a_resolve_that_changes_nothing_still_moves_the_skip: asserts the internal _poly_source field (item 6).

### Item 3 /code-review finder (angles B removed-behaviour, C cross-file, A on unread files): B and C closed clean on every large deletion / changed signature
Candidates (all low/medium confidence)
- C1 hud_container.gd:160-166 slide_to() awaits slide_settled; _jump_slide() (:190-192) lands without emitting -> a pending awaiter never resumes. Product callers safe by ordering; Tools/wall_editor.gd:552 can strand one. low.
- C2 spotlight_director.gd:313-322 _push() derefs _layer.style unguarded after the fallbacks were removed; no production null-style producer found (rule 7 consistent). low.
- C3 menu.gd:83-89 second New Run press while the picker is up -> two DeckPickers, _deck_picker nulled by the first's tree_exiting. Reachability doubtful (Dim STOP, focus on Pick). low.
- C4 map_hover_panel.gd:42 literal pack size `% 5` + untranslated strings ("Talent pack", "Rest stop", "Fame required: %d", "3 acts to reach it"). medium.
Also: handoff's HudContainer.resize_preview mention (Open bugs, P59 latent) is stale - no such function; HAND_UNKNOWN missing from localization.csv (scoring.gd:275, pre-stream).

### Item 6 /fx-verify (Fable subagent; 11 Godot runs, all exit 0, none left; no tracked file dirtied; its PNGs were in a session scratchpad - re-render to look again)
Rows judged by eye and matching: P58b square cards/holders, P58c fire over the bevel, P91 circle card-wide (10_light_layer), P50 cream rims, P27, P63a, P85, P86, P87, P89, P90, P55 sea buffer, P69 one surface, P68 thumbnails. spotlight --verify: 14 scenarios, 0 SUSPECT, every section lit and fell; LeakSentinel 10 CardData (listed); exit code not captured; the three settings.tres errors listed in Open bugs did NOT appear.
Known: prop_art_snapshot 4x freed-instance TypedArray at prop_visual.gd:299 (listed).
LOOKS WRONG (the overseer read each image and agrees with what is described):
- F1 wall_editor_snapshot (wall_editor_before.png, wall_editor_focused_at_rest.png): every content picture (game, menu, map) carries a sidebar INSIDE the picture; focused, the menu picture shows it at the left with labels cut ("oal: 100", "otal: 0") under the overlay's Back/Forward/Wall. Tool-only (Tools/wall_editor); the game path (sidebar_snapshot) shows no such thing. Cause unmeasured.
- F2 sidebar_snapshot rules_viewer.png: a loose "12" numeral with no card body, 4th item of the rules viewer's second row (after 11, a hoops card, 13).
- F3 deck viewer (map_card_description.png; crop viewer_deck_bottom_right.png): a 1 px cream horizontal line under the last row's card inside the frame band, x~1010-1110 y~624.
UNVERIFIED: glow following the bevel on the glow_falloff panels (sharp-square harness hosts); P65 beyond a flat fill; P12's slide timing.

## Next up
1. Finish the close from "## The close" -> Resume here, at or above the reviewer floor (the block below). Owner questions for the close: the unused hoop formation, the sidebar wheel (both in Open bugs), the P13 / P44 carried questions.
2. After the close (forty-fifth round; solatro/todo.md's first section): merge every branch into main and delete the old ones, the Showitaire repo split, then a review of todo.md with the owner.

```
READY FOR CLOSING - solatro / combine-sidebar-boardplan
  steps verified : every row done or closed (P93-P95 left for the todo)     suite: ALL 51 SUITES: 10017 CHECKS PASSED [19 placeholder warnings]
  IMPLEMENTED-BY : Opus 5.5 at medium (plan-implementer) and low; Sonnet 5.5 at high for mechanical steps; Opus 5 early in the stream
  REVIEWER FLOOR : Opus 5.5 at medium or higher - never weaker; every review subagent runs Fable, read-only
```

### Opening prompt for the next session (type one line of your own above the paste, e.g. "do this" - a bare paste is asked about first)

```
Run the closing phase of /plan-run for the branch combine-sidebar-boardplan in this checkout (solatro/HANDOFF_playtest_fixes.md). The code was implemented by Opus 5.5 at medium and low effort (Sonnet 5.5 high for mechanical steps, Opus 5 early on). You are the reviewer side, and you must be at or above that: same generation or newer, same effort or higher. A weaker reviewer on stronger code is net negative, not merely useless. Never commit to main; one verified step per commit, staged by path; you write no source - implementers do; every reviewer is Fable and read-only.

Read CLAUDE.md, .claude/memory/MEMORY.md and the memories it indexes that apply, then .claude/skills/plan-run/SKILL.md "The reviewer's model floor" and "Closing the run", then the handoff and solatro/RULINGS_playtest_fixes.md (R1-R10, every round through the forty-fifth, visual review rounds 1-5 - they outrank the design docs they name). First `git status` and `git log --oneline -5`: expect the close's handoff commits at HEAD and a CLEAN tree - the owner had everything committed for a session on another machine (the workflow edits to CLAUDE.md, commit-gate.ps1 and NOT_INSTALLED.md; project.godot's reordered input block; the visual-review status files). Then one full gate as ground truth, in the background, unpiped: `py .claude/tools/gate.py --out <your scratchpad>/gate --handoff solatro/HANDOFF_playtest_fixes.md -- --timeout 1800 --stall-timeout 900`; expect exit 0, `ALL 51 SUITES: ~10017 CHECKS PASSED`, 19 placeholder warnings, 24 resources + 1150 ObjectDB (a new scratchpad has no previous gate, so no per-suite diff prints: BOARD FUZZ is random, SIDEBAR 4525 moves by 2, WALL PAUSE 71/72).

THE CLOSE IS PARTLY DONE: read the handoff's "## The close" first and continue from its "Resume here" list - do not redo items 1, 1a, 2 and 6. The close's numbered list, for reference, each item's output recorded in the handoff: doc_check full; plan-auditor -> AUDIT.md; adversarial-review over main...HEAD with a priority order and "report early"; /code-review (one Fable finder, one verifier); the test-surface review with tests-that-prove-nothing as its checklist; /simplify inline; /fx-verify; fix what they find one at a time with a full gate between, each finding reproduced first; the whole-file comment sweeps as their own final step; /docs (the Open bugs lines marked FOR /docs and FOR /simplify are its input; fold the spotlight handoff - done); consolidate-memory; /handoff's Reflect and record over the whole run; delete the temporary plan documents. At most two subagents at once, only one running Godot. Ask the owner only with lettered options; the close's owner questions are listed under Next up.

After the close, solatro/todo.md's first section is the owner's order: /merge-branches for every branch into main (the cloud Linux branch origin/claude/combine-cloud-test included), delete the old branches (confirm each that carries commits main lacks), the Showitaire repo split, then a review of todo.md with the owner.
```

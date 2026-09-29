# HANDOFF — playtest fixes (the combined branch's first playtest)

**Goal:** the sixteen findings of the owner's first playtest on `combine-sidebar-boardplan` fixed
and gated, each against the ruling below, on this branch, ready for the owner to merge.
**State:** P1-P76, P58a-c and P58e done except the rows marked otherwise (P62 closed, P45 without code), each red-then-green,
by eye where it draws, Fable-reviewed, one verified step per commit. Last full gate (P71, 36c20f0b): `ALL 51 SUITES: 8869 CHECKS PASSED`, ~15 min with
`-- --timeout 1800`; 19 placeholder warnings, 24 resources + 1150 ObjectDB. Pending, in order: P66, P77,
P78 (review round 3's comments), P79 (the review tool), review round 4 (P58d), the close. Gate at the stream's start: `ALL 51 SUITES: 5839 CHECKS PASSED`.
**Entry docs:** solatro/START_HERE.md, solatro/design/sidebar/DESIGN.md,
solatro/design/poker-patience/DESIGN.md, solatro/design/grid-view/DESIGN.md,
solatro/design/board-plan/DESIGN.md, solatro/PICTURE_WALL.md
**IMPLEMENTED-BY:** P1-P37 and P41: `general-purpose` on `opus` (Opus 5); P38 Sonnet 5 then Opus 5;
P39-P40 Opus 5; P44 onward: `plan-implementer` (medium) / `plan-implementer-low` (low) on Opus 5.5,
`plan-implementer-sonnet` (Sonnet 5, low) for mechanical steps. Overseer Fable 5.1 through P44 (4),
Opus 5.5 from P44 (3) onward; writes no source. P64b-P74: `plan-implementer` (medium) and
`plan-implementer-low` (low), both Opus 5.5. P75-P58e and P76: overseer Opus 5.5 (high); `plan-implementer`
(medium) and `plan-implementer-low` (low), Opus 5.5; recon Explore on Sonnet 5. Every reviewer Fable, read-only.

## Owner rulings (verbatim where quoted; each overturns or extends the design it names)

- **R1 sidebar space (B1, B16)** — overturns sidebar `Q27`=d, D8/D10, `GAP-001..003`.
  Owner: "overlay, never inset. include screen movement to include sidebar sliding in and out of
  view so picture edges match window edges always. for example when initially focusing on a
  picture, no sidebar, edges match. once edges have disappeared, have contents shift to the side as
  sidebar slides in. do exact reverse when leaving the scene. check if this means that we need
  inset around picture that is half or less of sidebar width. such an inset should cover all 4
  edges if needed to accommodate potential sidebar from any edge." The sidebar is also hidden when
  it has nothing to show (the menu) and in wall view.
- **R2 Escape (B6)** — overturns picture-wall `Q100`=a for the keyboard: `ui_cancel` cancels
  everything the second button would AND zooms out to wall view. Back stays on `wall_back` (pad 9,
  `[`); `wall_overview` (Tab, pad 4) still opens the wall.
- **R3 run start (B2)** — extends picture-wall `Q61`/`Q62`: keep the slow wall reveal, then the
  camera enters the MAP without a press. Same on Continue when no show is pending.
- **R4 pack picking and map travel (B3)** — new; overturns `choice_viewer`'s click-takes-the-pack
  and K4's accept-enters-the-node. Owner: "click selects; a take button confirms. choosing next
  path on map should always require pressing dedicated button press in sidebar to choose, so that
  player can click on nodes to preview it first. clicking on node to travel to it is bad since it
  doesnt allow preview of what is being chosen. second sidebar can cover screen without shifting
  remaining screen and moving it. map sidebar should also show a deck button to view current deck
  directly when nothing is focused similar to how game view scene does the same with deck buttons.
  map sidebar should start with this basic view since no path should be auto selected at first.
  path choices should still show deck button since its just 1 button. and doesnt require player to
  cancel current selection just to compare against talent pack." A clicked card is highlighted as
  selected; the second sidebar locks on click and is exited manually.
- **R5 pickup (B12, B13, B14)** — overturns sidebar `QR6`=a (and `Q111`–`Q129` that rest on it),
  `Q262`=a, `Q263`=a, `Q254`=d: nothing is armed until the player acts. A CLICK on an Entrance card
  lifts it (raised, not following). A DRAG from a card follows the cursor while the button is held;
  release over a legal cell places, release anywhere else returns it. With a card lifted, a click
  on a legal cell places it. Right-click and Escape cancel.
- **R6 legal-cell highlight (B7)** — narrows sidebar `GAP-005`: the legal cell's zone-card BACK
  brightens toward white, the way the focus glow lifts paper; the mark's rank and suit pips are
  excluded from the modulate. No colour cast. Follow-up ruling: the FOCUS GLOW takes the same
  exclusion - brightness lands on the card back (the Type polygon) only, never on rank, suit,
  stamp or art, on a held or focused card too.
- **R7 the Entrance (B8)** — answers grid-view's gated `Q34` (its option c); keeps poker-patience `Q40`=a: while no grid
  is committed the Entrance sits centred at the bottom of the window, aligned to no grid, and stays
  there as the view pans. Picking up a card focuses the grid nearest the screen centre and the
  Entrance slides under it. After the first placement it belongs to that grid and leaves the screen
  when the view looks elsewhere.
- **R8 grid views (B10)** — overturns the one-quantity gap ruling in `play_area.gd` (edge gap ==
  inter-grid gap): OVERVIEW draws the grids close, a small fixed gap, the set centred; FOCUSED
  centres the one grid and the isolating buffer pushes its neighbours off-screen (they stay drawn,
  outside the window).
- **R9 preview size (B4)** — overturns sidebar `GAP-004`=b: one preview size on every surface, the
  deck viewer's (`CARD_SIZE * 2`).
- **R10 card text (B5)** — extends sidebar `Q33`=c: the title is "<Rank> of <Suit>" (a face card by
  its name); below it one block per skill, stamp, status and type — the effect's NAME in the large
  font, its description in the small one. `PipRankNumeral.get_str()`'s "NumeralRank5.0" is retired
  with it. Follow-up rulings: the SUIT keeps a block of its own (title "5 of Hoop", then Hoop large
  with its prop effect small); the title uses PLURAL suit names ("King of Knives") through five
  title-only localisation keys, the singular staying everywhere else.
- **Follow-up answers (verbatim), asked after P9/P6/P16/P10/P11 landed.** R5: an off-cell drag
  release - "drag release drops"; `armed_slot()` - "delete armed slot"; HUD buttons behind the
  locked description while a card is lifted - "acceptable"; a cancelled pickup leaves the board
  focused - "yes". R6: the glow no longer lights FX - "ok"; an empty cell reads as a hotter frame
  - "ok"; the two glow values - "both should be same value", then on which - "ok 1.45". R10:
  "plural form, same as hearts spades clubs diamonds" (so "Fires", and the suit-only title is
  plural too). R8: the 100 px gap - "ok for now"; the low grid row - "not sure what this means,
  as long as no overlap and entrance is distinct". R7: any focus takes an uncommitted Entrance -
  "yes"; a committed pickup re-aims nothing - "yes until no more placeable option on grid or
  entrance cards run out"; stays under the focused grid while panning - "yes".
- **Second round of follow-up answers (verbatim).** Flat-white paper at 1.45 - "previous
  highlights looked fine, so use same value for that". The squared glow - "have card outer outline
  change/glow when focused, legal glows the inner art, not the outlines. matching marks get glow
  outline currently." A dropped card - "dropped/placed card should cancel its locked description
  and focus glow, since player should have finished reading it before they took action with the
  card." R1 on the menu - "ii hidden while nothing to show"; the overlay band - "back forward wall
  not being part of sidebar is fine."
- **The two glow clarifications (verbatim).** Which value - "same value should be whatever
  original was. if unknown go with lower value." Focus outline vs the match outline - "no
  difference between focus card outline and mark outline. both should show both outlined."
- **Third round (verbatim).** The worldgen fix for the quit-mid-generation crash - "yes you can
  make fixes." Picture frames - "i want picture frames to be invisible once zoom in has happened,
  so picture frame is never visible while focused on a picture, until switching out to wall view.
  I mention this because i see a test that seems to test swiping on edge of picture and it shows
  frame near the middle."
- **Fourth round (verbatim).** The focus rim ink - "focus outline color should be a. by default
  the outline is black before focus." The legal lift and the cell's rim - "yes exclude focus
  outline rim".
- **Fifth round (verbatim).** Frames in transit between pictures - "yes frames should show in
  transit since its through wall view." The wall seen past the picture's edge - "wall stuff
  should never be visible when inside a picture scene, since idea is that you have entered the
  picture internally and wall no longer exists, so panning to where wall would be visible is not
  possible."
- **Sixth round (verbatim), R4 re-ruled after the flow was traced.** "1. describing a node still
  shows deck button, which can be a second button on the description sidebar compared to first
  one which is on default sidebar. having special case for 1st button to show on other sidebars
  sounds overcomplicated. 2. b 3. different color ink for now. the one that shows when moving
  around takes precedent and shows over the different color sidebar focus one. 4. i changed my
  mind. no more second panel. first time you click on a talent pack node, show deck viewer
  showing all possible card effects that can be rolled. sidebar remains description shower.
  sidebar when on node shows a button to view the possible cards again, since further clicks on
  the node before travelling will not automatically open the deck viewer again, instead requiring
  going to sidebar button to show the deck viewer again. This is because I have found sidebar is
  simply too small to show enough cards together at the same time." The dead overview pan and
  bounce - "yes retire so as to not leave behind clutter".
- **Second playtest (verbatim), after P29/P15/P24/P30-P32 landed.** "deck viewer allows key clicking onto map while deck viewer is still open, when instead it should not be possible and go to sidebar instead so that x can be clicked. mouse click should also not be able to click behind deck viewer. instead clicks outside should close deck viewer first. closing deck viewer should also remove focus on a card inside deck viewer, so that sidebar does not remain on description of a card that is no longer visible. card description sidebar in map should not show travel here and deck button. clicking deck again should close an open deck. deck viewer is also missing focus behavior from game view. clicking on a card should cause it be sidebar focused so that it stays on sidebar description
pressing cancel button in deck viewer should close deck viewer if a card has not been clicked and focused to view in sidebar
if card is not clicked and sticky to sidebar, there should be no exit button by default to show that it will not stick around.
consider every path player can take when interacting with deck viewer, is there anything i missed?
same behaviors as i described should be same across all deck viewers, and when hovering cards in game grid as well. right now merely hovering a card causes it to become sticky as if it was clicked on.
for some reason outline highlight does not move when viewing deck in game. arrow keys does not seem to move it either.
i notice for some reason based grid board is scrollable such that you can make it sit higher or lower than spawn position. this is not ideal since it should not be scrollable at all while nothing is sitting out of view. this is not ideal as it causes grid to shift around everytime card is placed or scoring happens as it changes container sizing a tiny bit.
base prop speed should be tripled.
if only one possible node option to travel to on map, it should automatically select it to save player from having to click it.
when 2 grids, for some reason clicking is a toggle to drag when it should be drag pan requires holding down key.
for some reason on entering a 2 grid board, everything is just a shrunk down version and buffer size remains way too large when it should only be a card width worth of separation between grids. focusing on a grid causes everything to snap when it should smoothly interpolate/animate into position. entrance also snaps to a grid too early, before any cards have been placed, making it hard to choose other grid instead, entrance should remain in center of screen until card has actually been placed. clicking cancel button does not zoom back out to every board view either to reselect. clicking left and right seems to behave closer to what i expected, but entrance noticeably jumps to other grid instead of waiting in middle for grid to come to it instead. for sake of dragging, grid snapping to center should happen on closest grid to center once dragging is complete as if left or right was pressed with buttons and refocus the entrance card.
key presses from grid is unable to reach sidebar. for example clicking left on leftmost card does not enter sidebar ever, which means sidebar is never interactable.
once an entrance has been used up, it remains snapped to a grid forever when it should be possible to choose other grids to put those cards into instead.
a lot of these issues are with lack of parity between different modal input options. right now requires mixing of keyboard and mouse to do anything, when it should be possible to use only one for everything."
  It overturns, where they collide: the R7 follow-up "any focus takes an uncommitted Entrance - yes" (the Entrance now stays centred until a card is PLACED); R8's 100 px overview gap "ok for now" (one card width); the P13 node-description buttons on a CARD description (none). The standing principle: **every route is complete with one input device alone** - mouse only, keyboard only, pad only.
- **Second playtest, viewer-path answers (verbatim).** (2) "while a card is sticky, hovering another does change the description. but sidebar will keep the description of the sticky one until canceled regardless of how many other cards were hovered in between. this is so you can click on a card then move to the sidebar to view it if description is too long without other card hovers overriding it. sidebar will show the sticky one once no other card is hovered or reached sidebar" (5) "take button and deck button and other buttons should not be accessible during a sticky card description sidebar until canceling the description view" (7) "skip straight to unsticking and closing on first click. exit button only exists on sticky descriptions, since unsticky descriptions close immediately when not hovered over the card."
- **Answers to the three P33 questions (verbatim).** "1. deck viewer is to the right of the sidebar and doesnt cover it. no sticky card description means sidebar is interactable when not control focused on deck viewer or card inside. clicking cancel or exit on sticky card description also doesnt show a card description since focus will be in sidebar. therefore your claim is incorrect, deck is clickable while deck viewer is open. 2. also incorrect, you can view the pack deck from a sidebar button while i was playtesting to reenter the pack. if you mean the one where you can reroll and will get 5 cards added to deck, then yes you cannot exit it currently once it is in progress. have the chooser be to the right of the sidebar if it is not already in order to have descriptions of card being chosen. this sidebar will allow relooking at current deck via a deck button, which will overlay on top of the chooser.  the rerolling cards scene should essentially temporarily cover the map entirely and be opaque with background so map behind is not visible, it is the new focus until cards are taken for the deck. 3.  clicking outside of talent pack viewer closes it, but not the one where you choose. you cannot leave that one until cards have been taken via button press to accept selection. this makes sense since the rerolling cards scene is not a deck viewer."
- **Reviewers (verbatim).** "reviewer ideally fable always, but it never touches the code itself, just finds issues." Every review pass at the close runs on Fable, read-only; its findings are implementer steps.
- **P38 single-node cancel (verbatim).** Asked: with exactly one reachable node auto-picked, does cancel/X on its description (a) drop the pick, Travel gone until the player clicks the node, or (b) keep it and skip to wall view. Owner: "i choose a. b is unintuitive for player".
- **P39a picture size (verbatim).** Asked: (a) size the picture to the run actual grid count, or (b) keep the picture fixed and zoom the overview to fit the set. Owner: "no dont change picture size based on grid count. so it should be b."
- **Seventh round (verbatim), the numbered letters asked after P39.** Asked: 1 one-grid cancel (a straight to the wall as built / b match Back); 2 a drag release (a re-aim the board only / b also grab focus onto an Entrance card); 3 a cancel mid-pan (a undo only / b also snap to the nearest grid); 4 a one-grid show (a the Entrance moves on the first placement / b commits on open); 5 a show opening (a arrives at scale / b eases in); 6 the sidebar arriving reserve (a the re-fit snaps / b eases, throttled once per slide); 9 an existing settings.tres keeping prop_tick_fraction 0.45. Owner: "1. a 2. b 3. b 4. commits entrance to grid immediately 5. b 6. b 9. dont keep old speed". Unanswered: 7 the game-screen HUD while a viewer is open; 8 a closed hover dropping the board focus; the gutter floor (one card of separation vs the score labels).
- **Eighth round (verbatim).** 7 (the game-screen HUD while a viewer is open): "b, deck viewer being open means deck viewer is new focus and provides the descriptions, board and its cards are no longer the focus". 8 (a closed hover leaving the board focus): "a with fix" - keep the focus rim; a pointer re-entering the focused card describes it again. The gutter floor: "as close as possible. adding score labels should not change the distance between grids. so minimum distance between 2 grids is width of the score labels." - as built: the gap rests on the always-reserved gutters (88 px), never on the knob below it.
- **Ninth round (verbatim), P44 (5) after its measurement** (the board is first drawn when the camera LANDS, ~38 frames after open_show_view, so an ease begun at open is spent unseen). When the opening ease runs: "a: on landing" - on the landing frame, alongside the sidebar slide-in. Its start scale: "b: fixed fraction" - a fixed fraction of the rest scale. Re-entering a frozen, resumed show: "a: fresh show only".
- **Tenth round (verbatim), after P44 (5) was built on landing** (the deal animates unseen during the flight and its tail chases the slots through the opening). The deal: "a works, but it would probably be even better if everything started running after camera shows the game picture on screen and is zooming in. the camera flight time is used to hide the loading of the scene instead of running it instantly." When the picture starts drawing live: "b: a fixed point in flight". The board's own grow under a live zoom-in: "id say keep both. camera zooming in is necessary to hide the frame. the actual scene should be responsible for its own display." Card settle smoothing: "a: leave it". This moves the ninth round's "on landing" to the fixed flight point.
- **Eleventh round (verbatim), P44 (5b) after its measurement** (the scene is built before the flight; the one cost left is the picture's FIRST live render, one frozen frame up to ~0.35 s on Box A, ~40 ms warm). Where that frame falls: "c: at app launch" - rendered once, hidden, behind the start menu or wall reveal, so no flight pays it. The live point: "zoom-in start, 0.65" - the start of the flight's existing zoom-in phase (WallTransition.phase_bounds()), no new knob.
- **Twelfth round (verbatim), P44 (6) after its measurement** (the board is fitted to the sidebar's RESTING reserve before the picture is visible; a slide only shifts it). Ruling (6): "a: close as built" - the resting fit applies unseen, the slide shifts at one scale, the only visible ease on entry is the opening grow. An UNCOMMITTED Entrance during a slide: "a: slide with the set" - it shifts with the board as the committed one does, staying centred under the set.
- **Thirteenth round (verbatim), P46.** Where the keyboard focus goes when a viewer closes on the game screen: "a: back to the opener" - as built; the board card the player left is reached with Right x3, undescribed until they move.
- **Fourteenth round (verbatim), P45.** After the measurement (Godot omits a setting equal to its default from a saved .tres, so every file saved under the old 0.45 default loads the new 0.15): "a: close, already done".
- **Fifteenth round (verbatim), P43.** The board scroller's draw_focus_border (the two white lines across the board while a card holds focus, and the 4 px content inset that pushes 3 grids off centre): "a: remove them". Then the 8 authored px horizontal-scrollbar band SHOW_NEVER does not keep (the border's margin had filled it): "a: remove the band" - everywhere, the static furniture height included, so the game picture's design size moves.
- **Sixteenth round (verbatim), P48 keyboard route.** Up after a key lift: "b: Up stays on board" - while a card is in hand Up goes to the grid, the X is reached by Left into the sidebar. Down from the bottom row of a grid the committed Entrance is not under: "b: go to the Entrance" - focus it and bring the view to its grid. Down from an Entrance card: "a: nothing". Up/Down in the 2-grid overview: "a: screen geometry". Down on the bottom row while HOLDING a card: "a: nothing" - the aim stays on the grid. A focused Entrance card's mark: "a: same rim as a cell".
- **Seventeenth round (verbatim), P49.** The focus/match rim ink was palette 31, the Entrance card's own paper, so a focused Entrance card showed no rim: "c: pink" - match_rim becomes palette 15 (255,140,255), for the focus rim and the would-match rim alike; supersedes the fourth round's rim ink.
- **Visual review, round 1 (verbatim, solatro/visual-review/review.json).** grid3_overview: "pink looks off. go with the cream color after all for the outlines since its closest we have to white. after image looks fine, gap is much smaller than before." grid3_focused, grid1_focused, window_show_open: approved. lifted_focus_elsewhere: "deck button should not be in description sidebar. the only exception i mentioned for that was showing deck button when showing a map node." Asked whether a focused Entrance card needs another cue once the rim is cream again: "yes cream everywhere which is what it used to be. its fine since the paper cards already have a brown border so it should be clear. lift on focus should be on everything that is clicked and going to move, not just restricted to entrance cards which implies hardcoding special cases which we want to avoid whenever possible. try not to hardcode it since lifting may be replacing with animation in future of card being \"excited\" and doing little hops." This reverses the seventeenth round (pink).
- **Eighteenth round (verbatim), after P51.** The pack chooser's sidebar Deck button beside a chooser card's description (from the P33 answers) against round 1's "only a map node": "a: keep it" - the chooser keeps its Deck button; a card description anywhere else carries none.
- **Nineteenth round (verbatim), P54.** A stuck chooser card with the run deck open over it: "a: hide the X" - one rule everywhere, a stuck description set aside under a viewer shows no X until that viewer closes. A game viewer left open across Back and closed by the map: "a: rest on the board" - on Forward the board focus rests as after an ordinary Back and Forward. A card described WITHOUT being stuck, remembered across Back and re-shown on Forward: "a: unstuck closes" - only a stuck description comes back on return.
- **Twentieth round (verbatim), P55 - the map's framing** (measured: the 512x512 map at zoom 1 in a 1152x648 picture never fills it; the grey is the picture's own background; same on main): "ideally map edges match window size with just a small buffer zone around edges which is sea colored in case nodes are too close to the edge. this way you only zoom in, and map cannot go off edge of window since panning is only possible when zoomed in. by default it is zoomed out at max distance and map fills most of available space. we want minimal zoom in if possible since controller and pc inputs ideally wont need zoom at all while playing." Read by the overseer, per R1: the available space is the area beside the resting sidebar (as the board fits); the buffer is one named constant the owner judges in the visual review. Keeping a zoom-in: "c: reset after each Travel" - the map returns to the fit whenever the token travels, as well as on entry.
- **Twenty-first round (verbatim), the SQUARE-CARD task (P58), added at the end of a session.** The owner's brief: "pull in latest changes on main which make cards have square design instead. reason being grid should look better if its square and will take more space, and to have more room on card for card type art. i have already updated the size to be 52,52 in the latest commit and updated the polygons as well so animations continue working with new shape. however work needs to be done to make sure everything that could possibly touch card shape is updated as well. most controls and visual math i know of arent hardcoded, but still need to visually check everything as well and make sure nothing breaks from the changes. this is also a good oppurtunity to see if previous agents added hardcoded values in places that definitely should not have hardcoded values since i imagine that would be source of bugs once card shape size becomes different. already known bug fixes needed from brief check in editor: fx editor shows fire not wrapping corner of square properly; prop position editor still assume card shape is rectangular; outline atlas editor shows glare effect still assumes old card size for shader; glow outline from spotlight tool also shows square corners being ignored and being treated as perfect square with no bevel. common issue appears to be hardcoded card size across shaders with old size. make non hardcoded if possible, but hardcoded is fine since card shape shouldnt change during actual game. keep hardcoded if it keeps things efficient, since passing in card shape on every single shader sounds theoretically expensive for no added value. note that this process was done before previously when adding outlines to the cards. you can find past commits for reference first" Answers: where - "a: merge main in here" (merge main into combine-sidebar-boardplan, never a rebase, and do the pass on this branch). Order - "a: square cards, then close" (P56's nit, P57, visual review round 2, then the merge + square-card pass with its own review round, then the /plan-run close). Visual review - "a: yes, all of them" (every affected in-game view AND the four tools as before/after pairs; the tools need in-repo shot scenes). Card size in shaders - asked "which option makes more sense such that everything relies on one value across whole project, since i am setting in cardvisual scene right now as well. or is this case where having it in multiple places is better." and then "which one makes the most sense if i decide to change dimension again in the future?" - the OVERSEER'S ANSWER (a recommendation, not an owner pick; the owner may overrule it at review): ONE project Shader Global `card_size` is the single source (Project Settings > Shader Globals, so @tool editors and shader previews see it); every card shader reads `global uniform vec2 card_size`; CardVisual and all GDScript read the same project setting; a future dimension change is then one edit with nothing to keep in sync. Global uniforms live in one project-wide buffer, not per material (Godot docs, from memory - VERIFY per CLAUDE.md rule 6 before building).
- **Visual review, round 2 (verbatim, solatro/visual-review/review.json).** Approved: grid3_focused, window_show_open, entrance_focus_rim, map_fit, map_after_travel. grid3_overview: "before we switched to grids, cards stacked on top of a cell/zone would shift slightly to reveal the zone beneath if holding a card and the zone below was a legal spot to place a card. otherwise it should select card on top since no reason to view the zone/cell. otherwise looks fine." grid1_focused: "sidebar doesnt show current chips x mult and total score so far." lifted_focus_elsewhere: "looks fine except for x on the card description which implies card has been clicked on but that shouldnt be possible since an entrance card has also been clicked on?" chooser_overlay_greyed: "covering whole map looks off. have it be a square window which pack chooser and its elements are inside of instead. outside of the sub window you can still see map so you know which picture you are in. also no reason to lock out the back forward and wall, if you leave you can just come back to the in progress chooser" (overturns the P33 answer "cover the map entirely and be opaque" and P52's lock-out). map_zoomed_edge: "looks fine. i assume edges missing between nodes is expected from it no longer being reachable? if not thats an issue" deck_over_chooser: "deck button should be close deck, and should be before any of the descriptive stuff at very top, not in middle of card and descriptors. i think we can do better though, by having an x button tab sticking out the side of the deck viewer window instead similar to a bookmark sticking out which is used to close the viewer since that is more intuitive." deck_card_hover_over_chooser: "as mentioned in previous comment, deck button should not be in middle of description, it should be on top but below the back forward wall row."
- **Twenty-second round (verbatim), asked after visual review round 2.** Closing a viewer, the opener button (now at the top, under Back/Forward/Wall) vs the new bookmark X tab on the viewer's side, for every viewer (Deck, Discard, Rules, Possible cards): "Both" - the X tab closes the viewer, AND the opener reads "Close deck" (its own viewer's name) while that viewer is open and closes it too. The pack chooser's square window: "Fit its contents" - sized to the five cards, the Reroll row, Rerolls and Take plus padding, centred in the space beside the sidebar, the map showing on every side. The map around the chooser window: "Visible, inert" - it ignores clicks, drags and the wheel; Take is still the only way to finish; Back/Forward/Wall leave and return to the chooser in progress. The missing edges in map_zoomed_edge (answered from code, sidebar_snapshot `_make_the_node_reachable` writes `controller._current` directly and never restores it): a shot artefact - edges to unreachable nodes do hide by design (world_map_controller.gd `refresh_visuals`), but no player reaches that state; the shot is fixed. The game sidebar's score, asked "Chips x mult + Total" / "Also the run's fame": "should show, goal, current total, score/chips x combo/mult always. no hiding a label until its past 0" - Goal, the current Total (live_total), and board_total x combo, each always shown (the Combo label's hide-below-1 goes).
- **Twenty-third round (verbatim), P62 after its measurement** (no shipped rule lets a held card onto an occupied cell, so the reveal shift could never fire): "you can drop it for now, but the actual shifting should have existed already, but there is small chance a previous agent may have removed it." (It was: f53f3922 and 4d972aa3, both unconditional forms.)
- **Twenty-fourth round (verbatim), P63a** (asked: with a pack node's possible-cards viewer open the whole row hides, so "Close possible cards" is never seen - keep the row hidden / show the opener only / show the whole row): "deck button can show on sticky description from non deck viewer" - read as: a card STUCK in a non-deck viewer (the possible-cards viewer) shows the Deck button; Travel and Possible cards stay hidden under that viewer; a hovered card shows no row; MAP_CLOSE_POSSIBLE_CARDS is then never visible and goes (the viewer closes by its X tab, click outside or cancel). The twenty-second round's "Both" covered every viewer, so the map HUD's Deck and the game's Deck / Discard / Rules also read "Close <viewer>" while their viewer is open.
- **Twenty-fifth round (verbatim), P63a round 2.** Deck pressed from a card stuck in a pack's possible-cards list (today the run deck REPLACES the list and the stuck card is lost): "Open over the list" - the run deck opens OVER the possible-cards list as over the chooser, the row stays up reading "Close deck", and closing the deck returns to the list with the card still stuck. Closing the possible-cards list while one of its cards is stuck (the sidebar drops to the HUD, the pick still set): "Back to the pick" - the pack node's description comes back with Travel live, as when nothing was stuck.
- **Twenty-sixth round (verbatim), P64** (asked: at the 600x1000 top-band window the square cannot hold five cards + the Rerolls and Take bands - Rerolls beside Take / fill the space / smaller cards / cap and crowd): "reroll next to take. UI should be in same row. window should be wide enough for 5 cards, should be centered. wrapping for cards beyond 5 is fine." Read: Rerolls moves into one bottom row with Take in every layout; the window is always at least wide enough for five cards unwrapped and centred beside the sidebar; only a sixth card or more wraps. The overseer's reading of P64's other two questions, from R2 (not asked): with leaving now allowed, Tab (wall_overview) and ui_cancel with nothing stuck reach the wall while the chooser is up, as on every other screen.
- **Twenty-seventh round (verbatim), P64b** (measured: at the 600x1000 window the chooser lives inside the map picture zoomed ~3x, so five cards are 400 picture px against a 389 px space, ~630 screen px on a 600 px screen). First answer: "scale up window size if needed such that 5x5 cards should fit, then start having to scroll to see more rows. dont shrink cards." Asked which gives at the narrow size: "you can scale window if necessary or shink if forced, but windows should not be zoomed in along with map in the first place? only map gets zoomed in, ui type stuff doesnt." Read: the chooser is UI - drawn at the window's UI scale, never zoomed with the map; five columns, the window growing to show up to five rows, a sixth row onward scrolls; the window may grow past the space, and the cards shrink only when five cannot fit the screen at all. Then, unasked: "everything should be center aligned too btw" - the card rows (a short wrapped row included) and the Rerolls + Take row centred in the window.
- **Twenty-seventh round, continued (the owner's pick, option text verbatim)** - measured: EVERY viewer (the chooser, the deck over it, possible cards, the game's Deck/Discard/Rules) is a child of its picture's SubViewport and zooms with it, the sidebar's preview size too. Asked how to take them out of the map's zoom: "c: fix P65, counter-zoom (Recommended)" - "Fix the uneven picture stretch (P65) first. Viewers stay inside their picture but size their cards by dividing out the picture's zoom, so on screen they draw at the fixed UI size at every window size. No viewport move, no input re-routing. When you leave a picture mid-chooser, it flies away with the picture."
- **Owner, after pick c (verbatim):** "remember that UI is not visible in wall mode either by sliding away or fading out, so its not important whether UI matches picture in wall space, which helps with not having to consider how it has to respect wall/picture camera"
- **Twenty-ninth round (the owner's pick, option text verbatim), superseding pick c's counter-zoom half** - asked, after the remark above, where the viewers live: "b: move to overlay layer" - "Every viewer (chooser, deck viewers, possible cards) moves to the sidebar's overlay layer at the UI scale and slides or fades out in wall view like the sidebar. One home for all UI; the input routing is rebuilt and re-tested." P65 (the uniform picture) stands either way.
- **Thirtieth round (verbatim), the map picture:** "map picture should be a square". Asked which when focused: "a: square on wall, fills window" - "On the wall it is a square. Focused, it still fills the window edge to edge (R1), so the square's top and bottom (landscape window) or sides (tall window) are cut off. The map fit keeps the whole map inside the visible part, with the sea buffer." -> P67. Then, measured (the square's side sets the focused map's canvas scale: side 648 draws everything in the map ~1.78x bigger in landscape, the pack chooser covering the whole map; side 1152 keeps landscape but towers 1.8x over the other frames on the wall and draws portrait 1.8x smaller), asked which side: "a: 648, move viewers first (Recommended)" - "Side 648. Land the viewer move to the overlay layer first (your pick b), so the chooser draws at UI scale and the map's size stops mattering to it, then land the square."
- **Thirty-first round (the owner's pick, option text verbatim), chooser rows** - at 1280x720 five rows of full-size cards need ~830 UI px against 648: "a: window to screen, scroll" - "As built. The window grows to the screen's height (about 3 rows showing) and the rest scroll. Cards stay full size."
- **Thirty-second round (the owner's pick, option text verbatim), P71** - asked how a partial possible card (a pack's list entry carrying only a type, stamp, skill, suit or rank; the body is the type polygon, so non-type entries draw one part over nothing) should look: "c: icons, not cards" - "The list shows each possible part as a small labelled icon in a grid, not as cards at all."
- **Thirty-third round (the owner's pick, option text verbatim), the menu's deck picker viewer** - measured: every overlay viewer fades with the sidebar's slide, and the menu's sidebar is hidden while nothing is described: "b: opening slides sidebar in" - "Opening the picker's viewer slides the sidebar in (empty until a card is hovered), so the viewer fades with it like every other screen. One rule everywhere." -> P64b-2d.
- **Thirty-fourth round (the owner's picks, option text verbatim), P72.** The picker and its Inspect viewer sharing the space: "c: opaque viewer" - "The viewer gets a solid backdrop so the picker vanishes behind it. Changes every viewer's look unless scoped to this one."; asked the scope: "Every viewer" - "All viewers get the solid backdrop; nothing shows through between their cards anywhere." The start menu's own buttons: "c: pin to UI scale" - "Keep them in the picture but pin their scale to the UI scale exactly, so the 600x1000 bottom row can wrap instead of spanning edge to edge." -> P73. The picker alone: "a: yes, slide sidebar in" - "Opening the picker slides the empty sidebar in, so the picker fades with it like every other overlay UI (one rule everywhere)."
- **Thirty-fifth round (verbatim), P73** - measured: pinned exactly to the UI scale the bottom row takes 85% of a tall window and never wraps at rest; the Play submenu draws over the Play button ("Continue" overlaps "Play"). Asked a) pin only / b) one centred column, the submenu below Play, the bottom row wrapping / c) the column with the submenu over Play: "one center column, but keep in mind this is not final UI for start menu. all visuals will be replaced with drawn art in the future as well." Read as b, kept minimal (no new tuning surface).
- **Thirty-sixth round (verbatim), the queue:** asked whether the list grew by discovery: "yes put square cards in front after test minimize changes. from now on new tasks should go to end of queue unless it would make much more sense to put in the end." Read: P74 and P75 first, then the square cards (P58a-c), then everything else; a new task goes to the END unless it clearly belongs in front (read "in the end" as "in front").
- **Thirty-seventh round (the owner's pick, option text verbatim), the intermittent budget** (three failures -> a fix step; already exceeded by TP-92, the SIDEBAR wall-view frame-count sanity and UI VIEWERS "later arrow"): "c: after square cards" - "They become fix steps queued right after the square cards (P58a-c), ahead of the rest." -> P76. From now, each listed intermittent's Open-bugs line carries its count.
- **Thirty-eighth round (the owner's picks, option text verbatim), P58b** - measured by P58b-1: a Shader Global works under gl_compatibility and in the editor, but only outline.gdshader's u_card_extent is the card size (fire/glow u_body is the host's body); the tool bugs are GDScript/data copies. The one source: "GDScript constant" - "(Recommended) CardVisual.CARD_ART_SIZE stays the source, as today. The copies derive from it and the 40x54 shader defaults go. A future size change is one constant edit plus re-baking the card polygons. Editor shader previews still need a script to set the size, and they have one today." Supersedes the twenty-first round's Shader Global recommendation. Frame 2 (TypeInput) of the square card_types.png drawn 1 texel inside its frame on all sides: "Intentional" - "Input cards are meant to look 1 texel smaller. The rig and mask would then follow each type's drawn extent, not the frame box. That makes it a code change, and the OUTLINE row gets re-pointed to per-type extents." Frame 2's new 25%-alpha pale fill (202,185,188) inside its ink ring, which outline.gdshader drops (body = alpha > 0.5; the old sheet's Input was hollow by alpha 0): "Translucent fill" - "The outline shader treats any alpha > 0 as card body and draws the fill at its authored 25%, with no inner rim (right half of the image). This changes the shader's 1-bit contract." The mask's corner model, asked with P58b-M's fx_cost numbers (Box A, min of 3: the burning full screen 3.54 -> 4.30 ms, +21%; box hosts +0; deformed card fire +0.10 ms): "Exact staircase" - "(Recommended) The staircase becomes mask points: POLY 24→40 and WEDGE_CANDIDATES 4→8 in fire, glow and FxAttachment. The mask is exactly the drawn edge at any FX pixel size. Measured cost: +0.76 ms on the burning screen, paid by poly-mask hosts." TypeGridCell draws the same frame 2, so every board cell took the fill (shown the before/after board): "Yes, cells filled too" - "Frame 2 is the zone look. The board's cells get the fill as built; the legal lift brightens the ring fully and the fill at 25% weight (right of the image)." The gap between cards (answers the twenty-eighth round's open separation question): "Art units, one value" - "(Recommended) One named gap, BOARD_SEPARATION 4 art units, drawn at each holder's card scale: the board as built; viewers 4 × 2 = 8 UI px (today 4). The chooser's rows gain that gap under the button band. A future card-size change leaves the gap the same size in art." The deck viewer's ragged right edge: "Yes, whole columns" - "(Recommended) The list width is a whole number of columns and centred; no new number, the chooser's rule reused."
- **Visual review, round 3 (verbatim, solatro/visual-review/review.json; the square-card group, BEFORE bd8c9f81).** Approved: grid3_overview, grid3_focused, grid1_focused, window_show_open, lifted_focus_elsewhere, entrance_focus_rim, map_zoomed_edge, map_after_travel, deck_card_hover_over_chooser, grid2_overview, grid2_focused, board_window_1280x720, board_window_600x1000, entrance_card_lifted, deck_viewer_600x1000, rules_viewer, description_card, fire_on_cards, fire_on_bent_cards, fx_editor_overview, fx_editor_card_fire, props_on_a_card, hoop_on_a_card, formation_editor_knife, outline_glare_start / _middle / _end, spotlight_glow_field, spotlight_tool_glow, spotlight_tool_glow_rest (grid1_focused's approve carries round 2's comment text unchanged - the review tool's stale-comment bug, P79 - not a new comment). chooser_overlay_greyed: "center the reroll text under the card". map_fit: "looks like top buffer isnt there? check bottom too." deck_over_chooser: "cannot tell where deck viewer and pack chooser edges are separate. color each colored background differently from now on, they are all placeholders anyways. X button should not be transparent. otherwise looks improved and I accept." grid1_overview: "looks right, but I notice resolution looks off and causing heavy aliasing in general for your review images". deck_viewer: "no same buffer above and below top and bottom cards of deck viewer I believe. top cards are touching top edge of the window but there should be same separation." pack_chooser: "empty space above and below the cards is extreme. expand only when card count increases. at max limit it becomes scrolling." possible_cards: "looks fine but empty card should probably have a description. zero description at all looks off." formation_editor_hoop: "hoops should be aligned horizontally." pip_row: "looks fine except for the super heavy aliasing making it hard to judge, its screwing with outline shader results." win_overlay: "result is not centered over game view screen oddly." Read: the pip-row spacing and the knife formation's lean stay as built (approved / 'looks fine'); the chooser window's height is answered by pack_chooser (shrink to the cards, grow with the count, scroll at the limit); the open deck over the chooser by deck_over_chooser (distinct placeholder colours per window, an opaque X). The owner, outside the page: "bug with new visual reviews leaving behind comments from previous reviews"; the npm command in the chat "could not run ... due to auth issues".
- **Thirty-ninth round (the owner's pick, option text verbatim), Tab** - measured by P64b-3a: Tab is Godot's ui_focus_next wherever a Control holds the key focus (the board, a described map node, the chooser) and reaches the wall only when nothing is focused; three rows walk the focus by Tab. "a: Tab = wall (Recommended)" - "Tab opens the wall on every screen, as R2 and Q101 were written. Keyboard focus moves by arrows only, which is already how a pad player moves; three test rows that walk by Tab move to arrows." -> P64b-3c. Corrects the twenty-sixth round's overseer reading ("as on every other screen" was measured false).
- **Fortieth round (the owner's picks, option text verbatim), the start menu by keys (P64b-3b).** Down from Play lands on a disabled Continue: "b: skip disabled (Recommended)" - "A disabled button cannot take focus, so Down from Play goes past Continue to the next live button. One rule for every disabled button." Measured, closing the deck picker re-wraps the bottom row mid-slide (Language 367 px right, 41 px up in one frame): "b: lay out at rest (Recommended)" - "The menu lays out against the sidebar's RESTING position (as the map already does), so the column shifts smoothly with the slide and re-wraps at most once, at the slide's start or end, never mid-slide." -> P64b-3d, P64b-3e.
- **Forty-first round (the owner's pick, option text verbatim), P80** - measured: Main's start-up shader warm-up briefly makes its throwaway game view the global CardEnvironment.CURRENT; a play-area CardVisual frees itself when its card is not in the CURRENT view's data (card_visual.gd ~826), so another suite's still-dealing board loses every card and its deal reads freed instances (x = marks left to deal). "a: own board (Recommended)" - "Product: a board card asks the board that hosts it whether it still holds its card, not the global CURRENT. Cards live and die with their own board; no suite's Main can free another's. Plus a red-then-green row that mounts a real Main mid-deal."
- **Forty-second round (verbatim), P71** - measured: a type's art frame is the whole 52x52 card face; a part hovered in the list would be previewed in the sidebar as loose art over nothing; Paper's name/description and every rank description are empty. The type icon: "b: shrunk to the cell" (option text: "The type's face drawn scaled down to the same small cell as the other parts (the one exception to the one-art-unit-per-card-scale rule)."). The sidebar picture of a part: "card preview makes sense to immediately tell what type of pip it is by position on card" - read by the overseer (to confirm in review round 4 with a shot): the sidebar keeps a card preview with the part in its own place on a card; a part that is not a type sits on a neutral blank card body so its position reads. The missing text: "you can write them with placeholders". Then, measured (naming Paper adds a Paper block to every card's description, R10's one block per type): "b: only in the list (Recommended)" - "Paper keeps no block in a card's description (it has no effect to explain); its name and placeholder description appear only on its icon in the possible-cards list and when that icon is described." The overseer's own calls (from the rulings, not asked): a new part-icon control listed by the same CardsViewer (no duplicate viewer; no card bodies in the list), uniform grid cells ("a grid").
- **Twenty-eighth round (verbatim), card holders** (asked whether all UI should scale off the card size; the overseer proposed: card-holding UI sizes itself from CARD_SIZE through container minimum sizes, text and chrome from the UI scale, no hardcoded card number anywhere): "yes have all card holders scale based on card size. it will also need to consider separation buffer sizes between the cards. we can figure out font and button sizes later." Folded into P58b. Open, to ask with P58b's measured list: whether a separation between cards derives from the card size or stays one fixed named value.
- **Plain bugs, ruled already:** B9 the drop map obeys `committed_grid` (board-plan ASSUMPTIONS "a
  cell the show cannot place into"); B11 the face-down stock card must not raise the Entrance cards
  above it (sidebar `Q249`/`Q265`: the lift belongs to the held card alone); B15 cancel works from
  anywhere on screen.

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
  description: Size / scale / layout rows run in the harness's scale-1 test SubViewport, not the player's window (tests-that-prove-nothing item 22) - add root-window checks at 1280x720 and 600x1000 for the few claims that matter (every viewer at the UI size, the chooser square, the menu column, the board centred), or mark each harness-only row as such. Queued at the end. MEASURED by P58b-7's first round: a suite cannot resize the OS window - in the full gate DisplayServer.window_set_size to 1280x720 / 600x1000 was not granted (the window stayed 1152x648), every suite shares that window (test_wall_focus.gd ~453: only a SubViewport can be resized safely), and a mid-test error would strand later suites at the wrong size. So a root-window row measures at the gate window's size (its real content scale); other window sizes are shots.
  status: pending
- id: P78
  description: Visual review round 3's comments (verbatim in the rulings) - each its own measured step: (a) the chooser's 'Reroll' text centred under its card; (b) the map fit's top (and bottom) sea buffer; (c) each overlay window (deck viewer, pack chooser, possible cards, rules) a distinct placeholder background colour, and the bookmark X tab opaque; (d) the deck viewer's list with the same buffer above its top row and below its bottom row as at its sides; (e) the pack chooser sized to its cards - no extreme space above and below, growing with the card count, scrolling at the limit (the thirty-first round's 'window to screen, scroll' now reads: grow only as rows are added); (f) an empty (blank) card described in the sidebar; (g) the formation editor's hoops aligned horizontally; (h) the win/lose result centred over the game view.
  status: pending
  notes: '(e) revisits P64b / the thirty-first round - measure the chooser window rule first and ask if (e) contradicts a ruling. (g): measure whether the hoop formation points or the editor preview offsets the rings vertically.'
- id: P79
  description: The visual-review tool - (a) a new round shows the previous round's comments as if new (owner: "bug with new visual reviews leaving behind comments from previous reviews"; grid1_focused's round-3 approve carried round 2's text); (b) the page's Done never reaches solatro/visual-review/status.owner.json (still round 1, 2026-09-24 - rounds 2 and 3 both) so the watch never wakes (designloop/src/visualreview.mjs writeOwnerStatus keeps the old round; markDone passes none - read by the P58d-shots implementer); (c) the review images alias heavily (owner, grid1_overview and pip_row: "resolution looks off ... heavy aliasing", "screwing with outline shader results") - the grid shots are 1625x914 captures shown scaled with no smoothing; measure whether the capture or the page's scaling aliases; (d) the npm command given in chat failed for the owner ("auth issues") - give the owner the exact command they can run.
  status: pending
  notes: 'Fix before the next review round. designloop is its own project (designloop/README.md). Recon (traced, not measured): (a) solatro/visual-review/index.html ~103 fills the comment box from review.json''s last verdict BEFORE computing stale (~104) - only the label honours it; review.log shows grid1_focused''s round-2 text resubmitted on round 3; fix: no pre-fill when the AFTER is newer. (b) premise likely wrong: Done -> server.mjs ~753 -> visualreview.mjs markDone -> registry.mjs ~84 always stamps a fresh at; status.owner.json''s round-1 record is simply the last Done pressed (round 3''s Done never pressed?) - measure by pressing it on a scratch copy, then fix nothing if it lands. (c) index.html ~12 downscales the pair with image-rendering: pixelated (nearest neighbour) - aliasing on a DOWNscale; crops (~17, upscale) are right as pixelated; measure whether the capture itself aliases (the outline shader at the shot''s scale) before changing the page. (d) npm --prefix designloop start runs node src/server.mjs - no registry, install or git: the failing chat command was something else; give the owner that exact line (and Box B''s Node PATH note from machine-profiles).'
- id: P64b-4
  description: The P64b part 3 group's broad Fable review, its findings (queued right after P80 - the group's own follow-ups, as P58e was). (1) Menu.refresh_continue (menu.gd ~80) runs only in _ready and on a Play press, never when the menu is shown again: a save made during a run leaves Continue held on return, and a lost run (main.gd ~587 clear_save) leaves Continue LIVE with no file - Enter reaches main.gd ~536 _on_continue -> RunManager.load_run() unguarded (read, not measured); refresh on every show (Menu.take_the_focus already fires on active_screen_changed), and drop the fold/reopen of Play from test_keys_alone_start_a_run_from_the_start_menu_and_find_it_again (~2449-2454) so the row can fail. (2) test_sidebar ~2328 and ~2342 pin _check_the_bottom_row_beside_the_sidebar for the same state (picker up, at rest, 1280x720) - drop the older row's call, keep its wrap check. (3) CardsViewer.sidebar_requested's doc (NAMES.md ~141, cards_viewer.gd ~54) says "another viewport"; every hosted viewer is in the sidebar's root viewport - "a separate Control tree the neighbour search never crosses".
  status: done
  commits: [bfd3c0c0]
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
  status: pending
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
  status: pending
  evidence: ''
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
- FIXED by P25. A product crash at quit: quitting (or freeing Main) while the world map is still generating lets the vendored generator resume one more stage on a dying tree - 0xC0000005 at process exit, no backtrace. Isolated: Main._on_continue calls map_scene.start_run un-awaited -> Map.start_run -> WorldMapController.start_run `await map.generate()` -> addons/worldgen/world_map_2d.gd ~169 `await gen.generate_world_map()`, whose stage loop steps on get_tree().process_frame; the last line logged after the banner was the Rivers stage at 0.857, Painting never reached. `test_continue_after_a_mid_show_quit_still_reveals_wall_view` alone crashes 3 of 3 (~2 s), 0 of 3 when it waits 243 ms for generation's true end. Map cannot settle or cancel from _exit_tree and the addon exposes no cancel. Minimal addon-side change (NOT made; worldgen is vendored from worldgen/): a cancel flag the stage loop checks between stages, set on exit, or stepping on its own node instead of the tree's process_frame. P12 only exposes it: its slide adds ~0.5 s per focus move, moving the fixture's free from before the generator spawns to inside its stage loop. The fixture now latches on generation's end, as the reveal test already did.
- FIXED by P42: the SIDEBAR map Deck-button click flake (a stale map description over the button).
- A worldgen teardown abort (0xC000001D in addons/worldgen/core/steps/rivers.gd, a river step reading a freed object while a Main is torn down mid-generation - the un-awaited map_scene.start_run path P4 notes) hit 1 abort plus 1 post-banner SCRIPT ERROR in an implementer's 5 Sidebar-including runs during P22; 0 of the overseer's gates.
- `PIXELS: fire brightens when its host is highlighted` failed once (0.272 plain vs 0.250 highlighted) in 1 of 5 overseer gates on the P12 tree, never before; nothing in P12 reaches that suite. Measure before naming a cause.
- PLAN VISUALS TP-92 (cell k starts k shares of the stagger in) failed once - worst drift 0.084 s against a 0.080 s stagger - in 1 of 3 overseer gates on the P23 tree, green on the rerun and in every filtered run; a wall-clock timing row under full-gate load. Measure before naming a cause.
- FIXED by P54: the container-global viewer fields (one record per viewer, filed under its screen).
- prop_art_snapshot.tscn emits four `previously freed ... TypedArray` teardown errors from prop_visual.gd ~299 (found by P37, identical with the knob parked at its old value) - not caused by any P row; measure before naming a cause.
- Gate totals move run to run ONLY through BOARD FUZZ (347..376 over six gates, a randomised suite); every other suite count is stable, so compare per-suite tables in logs/test/test_output_all.log, never the banner totals. Unexplained: before P15 SIDEBAR read 1391 on the full gate against 1406 filtered (equal, 1414, after P15) - 15 checks the full gate did not run; fits the leaked-board item below, not measured.
- A LEAKED LIVE BOARD between suites: a settings write in WALL FOCUS rebuilt a PlayArea another suite left alive (the P23 SCRIPT ERROR surfaced only on the full gate, under no filtered subset). Harmless now, but it is an order-dependence source - find the suite that does not free its Main/GameView.
- none else beyond the tasks. OWNER, R5 reading to confirm: a drag released off a legal cell puts the card back over its slot but it stays IN HAND (lifted, drop map lit) until placed or cancelled - 'release anywhere else returns it' was read as returns-to-slot, not drops-the-hold. From the bloat review of the P9 commit (opus, read-only): `PlayArea.rest_focus_on_board()` keeps a fallback for a held card with no control, whose only named producer was the deleted auto-arm - settle by `assert` plus a suite run, back it out if a fixture fires it; `_release_places` and `follow_cards` each have one call site (both predate P9).
- VISUAL LAYERS "one frame after the section changes, no circle has SNAPPED to its new card" failed 1 of 3 implementer nine-suite runs on the P44 (5b) tree, 0 of 1 overseer gates; the (5b) move-tween change is the one edit that reaches a bare GameView. Measure before naming a cause.
- UI VIEWERS "a later arrow never drags the focus back to the first card" failed 3 of 3 implementer runs that included SIDEBAR on the P52 tree and 0 of 3 run alone - a cross-suite focus steal is the lead; also 1 of 2 overseer gates on the P47 tree (its failure line interleaved with WALL TRANSITION's soak output): the row grabs focus on a standalone DeckViewer's second card, waits ONE frame, and the focus is gone. P47 cannot reach it (no PlayArea in that fixture; its new branch grabs no focus). Suspect a focus steal from a concurrently running suite in the same window - measure before naming a cause.
- A freed-instance SCRIPT ERROR x20 at PlayArea._deal_next_mark ("Trying to assign invalid previously freed instance") during the WALL FOCUS soak: 1 of 3 runs on the P43 tree (2 implementer combined runs + 1 overseer gate), 0 of 5 overseer gates between P44 (5b) and P47. The plan-mark deal is released at go-live since (5b); suspect a Main freed mid-deal by the soak. Measure before naming a cause.
- GRID VIEW TP-138 "the board at rest is already where an explicit pan puts it" (rest -445.7 vs pan -443.3, 1 px bound): 1 of 5 runs on the P43 tree.
- FOR /docs AT THE CLOSE: the rim-ink records - design/board-plan/gaps/GAP-004.md ("match_rim = 31 ... stand") and design/sidebar/ASSUMPTIONS.md ~993 (the fourth-round ink ruling) with no pointer to the seventeenth round; ARCHITECTURE_REVIEW.md ~1599 and board-plan ASSUMPTIONS.md ~306 now give 15 but still reason "the ruling says WHITE, so" - pink was chosen because cream vanished on the Entrance paper.
- FOR /docs AT THE CLOSE: the design records still quote the pre-P43 picture (1576x887, inset 394, 262.7, 733.808, the 27+8 band): design/sidebar/{DESIGN,PLAN,TEST_PLAN,ASSUMPTIONS}.md, gaps GAP-001/GAP-002, design/poker-patience/gaps/GAP-039.md, Tests/Visual/grid_zoom_shot.gd ~214; test_grid_layout.gd ~1709 has a tab-joined line.
- Measured by P58b-4 (1152x648): the wall camera draws a focused picture at zoom 0.723 against the covering scale 0.709 (the overfill margin), while the board's reserve uses the covering scale - in window pixels the board's window starts 5.8 px under the sidebar's edge and its centre sits 2.9 px right of the space's; no card is under the sidebar. game_view._publish_board_inset says both scales are intended. Not asked.
- Found by P58c-1 (read, not fixed): solatro/Tools/spotlight_tool.tscn has an ext_resource pointing at user://settings.tres - the PLAYER's settings file (CLAUDE.md: the player's save and settings are not ours); formation_editor.tscn and spotlight_tool.tscn reference their scripts as res://tools/... and spotlight_tool.gd ~10 res://tools/spotlight_scenarios.json (the folder is Tools/ - Godot warns on every load; breaks on a case-sensitive export); a fresh editor printed parse errors for Tests/Engine/test_palette.gd ('Could not resolve member ROLES: Cyclic reference') and Tests/Visual/pixel_probe.gd ~133 (PaletteDB not found) - editor-only, unverified beyond the log.
- FOR /simplify AT THE CLOSE: outline_atlas.gd ~339-342 prints a 'DBG2 ...' line per card polygon on every rebuild.
- FOR /docs AT THE CLOSE: solatro/design/card_size_outline/IMPACT.md (~77, 162, 287, 480, 491, 548, 614, 640-644) still names corner_notch, SHIPPED_CORNER_NOTCH, notch_fraction (removed by P58b-2) with file:line links that no longer hold them - doc_check checks files, not symbols.
- Found by P76a: Tests/Visual/plan_reveal_shot.gd does not parse (~116 draw_card() with too few arguments) - the plan-reveal by-eye shot is broken; PLAN VISUALS TP-63 held-card rows failed 3 checks in 1 of 7 implementer runs under an artificial 40 ms/frame load (old code), not since. Measure before naming a cause.
- For when the glow ships in game (measured by P58e-3, Box A): the ruled POLY 40 costs the card glow +1.56 ms (+40%) on a window full of glowing cards against POLY 24 (glow.gdshader mask_dist runs every polygon edge per lit fragment); only the spotlight tool builds a glow today. And the posed rig's busiest wedge slot sits exactly on WEDGE_CANDIDATES (7 + 1 = 8, RIG_ANIM t 0.27-0.67) - zero headroom, no hole; OUTLINE's posed row goes red first if a staircase step or a stronger shear is ever added.
- VISUAL LAYERS 'one frame after the section changes, no circle has SNAPPED to its new card' (the light-snap row): 1 of 4 implementer runs on the P58e-3 tree; lead, read not measured: spotlight_director advances b.t += delta / travel, so one long frame can finish a whole travel.
- A teardown 0xC0000005 after the banner (THE ENGINE TERMINATED ABNORMALLY): 1 of 1 implementer six-suite filtered run on the P58b-2b tree (Outline Pixels VisualLayers UiProps FxAttachment Interaction), 0 of 1 overseer gates; 1 of 3 overseer DragPlace-alone runs on the P64b-4 tree (after P80's own-board rule; all 491 checks passed first). COUNT 2. Measure before naming a cause.
- An editor re-save of Cards/card_visual.tscn can drop `auto_calculate_length_and_angle = false` from the leaf Arm_* bones (the merge did: ~48% slower suite, a warning per transform change); OUTLINE test_leaf_bones_do_not_auto_calculate catches it. About 58 s of the full run (mostly SIDEBAR, +48 s) is still slower than on bd8c9f81 - one run, uninvestigated.
- PLAN VISUALS TP-92 failed 1 of 1 overseer gates on the P58b-6 tree (0.083 s), 1 of 1 on the P58b-5 tree (0.113 s) and 0 of the 6 gates between P58b-B and P58b-4; 1 of 1 overseer gates on the P58b-3 tree (0.115 s), 1 of 1 on P58b-0's (0.135 s), 1 of 1 overseer gates on the P58a merge tree (0.118 s), 0 of 1 on P75's; 1 of 2 overseer gates on the P56-nit tree (worst drift 0.116 s, a test-only diff in SIDEBAR) and 1 of 2 on the P63b tree (0.082 s). TP-92 also failed 1 of 2 overseer gates on the P50 tree (worst drift 0.086 s against a 0.080 s stagger) and 3 of 4 runs on the P48 tree (all three in the implementer's filtered runs, passed the overseer gate) against ~1 of 3 gates before; a wall-clock stagger row. Measure before naming a cause.
- Latent, recorded by the P48 review: a Down pressed within a pan's ease picks the Entrance stop from a mid-flight x.
- DRAG PLACE timing rows, 1 of 2 runs on the P50 tree (a Sonnet report called them a known flake - they are NOT on any list): "...and bare motion afterwards moves the board not at all" (content x -836.74 -> -837.32), "leaving the picture stops the slide exactly where it stood" and its precondition "the slide was caught part way across" (travelled 1.000). The palette change cannot reach them; measure before naming a cause.
- Picture-wall design DAG warning (Design Loop check): QR6's default (a) reaches nothing - Q76 is gated [QR6=b|c], Q77 [QR6=b]. A design decision for the owner: widen the gates or change the default.
- map.gd shows literal user-facing strings ("Tour complete!", "Continue tour", "Fame: %d") that bypass TRANSLATION (found by P52).
- SIDEBAR "Close fix 2: a new run's map opens on the HUD, not the last run's pack description" failed 1 of 2 SIDEBAR-including runs on the P53 tree, 0 of 8 alone; a map-only fixture with no GameView. Unexplained.
- Latent, traced by the P53 review (unmeasured): GameView's description_dismissed handler nulls play_area.locked_data with no screen check, so dismissing a MAP description with its X strips the frozen board's lock marking while the game's locked entry survives (Forward re-shows it, the marking gone); exit_accepted likewise rests focus on a frozen cell.
- OWNER QUESTION for the next round (traced by the P53 review, pre-existing): by keys, a transient (unsticky) game description remembered under the game screen survives overlay Back and is re-shown on Forward, describing a card nothing is on, with no X. HudContainer's _entry_by_screen says a return re-shows; the second playtest (2) says an unsticky description closes when the card is no longer hovered. Which wins?
- Latent, traced by the P54 review (unmeasured): with the deck open over the chooser and nothing stuck, an arrow off a deck card may land on Take under it (Godot's neighbour search ignores occlusion); if Take closes the chooser while the deck is open, the deck's own stuck lock is freed with its sticky left set.
- FOR /docs AT THE CLOSE: design/picture-wall/DESIGN.md ~150 and ~890 still cite the map's ZOOM_MIN 0.5 (deleted by P55).
- UI VIEWERS test_pack_click_selects "the click also focuses the card it picked, so the sidebar can stay on it" (focus owner null) and "the moving focus takes the rim while it is on the picked card" failed together in 1 of 2 overseer gates on the P57 tree and 1 of 2 on the P63c tree (2 of the 12 overseer gates between), WALL TRANSITION running just before; 0 of 10 filtered runs (UiViewers alone x3, with WallTransition x2, each on the P57 tree and on HEAD's hud_container.gd). A standalone ChoiceViewer fixture P57 cannot reach - same shape as the later-arrow row above (focus gone a frame later). Measure before naming a cause.
- FOR /simplify AT THE CLOSE (P57 re-review): HudContainer.set_active_screen's keep-what-a-viewer-holds branch may be dead - on the game screen no opener hosts a viewer while a description is up, and on the map release_screen frees the pick's covered entry; what is left is a chooser card that is already a suspended lock.
- Latent, traced by the P59 review: a window resize while another card is described over a board lock leaves the lock's detached preview at its old size - HudContainer.resize_preview re-sizes only the mounted visual, and return_to_lock re-mounts the lock's without re-sizing (P59 removed the re-hover republish that used to redraw it).
- SIDEBAR test_a_game_viewer_left_open_across_back_changes_nothing_on_the_map, route "an arrow": whether the map's arrow closes the game viewer left open behind it varies run to run - the test's branch on it took "closed" in 3 of 6 overseer gates (P57 round 2, VR2 shots, P62b) and "still open" in 3 (P59, P60, P61), no SIDEBAR change between; both branches pass, so the gate stays green while the product behaves two ways. Measure before naming a cause.
- Latent, product (found through P63c's leak): freeing Main while the token walks onto a pack node (a quit mid-walk) leaks the chooser _open_booster is still building - RID skeleton/mesh/texture and GL texture leaks plus a PagedAllocator line at exit, 1 of 5 filtered runs. Same shape as the fixed worldgen quit crash. Measure before naming a cause.
- Latent, traced by the P63c review: a game pile opened (over = false) while the map's deck-over-list stack is up takes DeckViewer._open and drops the list out of both _open and _under - still closable by its own input and the X, but a Possible cards press then opens a second list.
- Product, read from code by the P64 implementer (not reproduced in play): the wall drops input while a move is in flight (Wall._unhandled_input returns while input_locked), so fingers lifted during a pinch-in's zoom-out never reach PinchTracker, which keeps both marked down; every later pinch is then refused. Tests work around it (_pinch_in_at lifts after the move lands).
- FIXED by P80 (146eb824): The _deal_next_mark freed-instance SCRIPT ERROR x20 fired again during the WALL TRANSITION soak: 1 of 2 implementer seven-suite filtered runs on the P65b tree; and x25 (play_area.gd:2409) in WALL FOCUS right after test_a_published_info_entry_is_owned_by_whatever_shows_it, 1 of 1 overseer gates on the P64b-3b round-2 tree (that round rests the board focus on every game went_live; the deal is released at go-live). COUNT: 3 - budget reached, a fix step (P80) queued right after P64b part 3. Measure before naming a cause.
- LEAK CANARY "OBJECT_COUNT returns to baseline after 3 full simulated play sessions" FAILS when run alone or in a small filter: HEAD (498090ae) 3 of 3 LeakCanary-only runs (growth 40, 40, 4, all RefCounted, nodes +0, resources +0); P65b tree 1 of 2 alone and 1 of 2 seven-suite runs (growth 32); passes in every full gate. An order/warm-up dependence in the canary's baseline, or a real RefCounted leak the full run's earlier suites pre-warm - measure before naming a cause.
- Tests/Visual/wall_frame_probe (staged at 600x1000) draws every non-game wall-view picture as a flat brown panel with no content, HEAD and P65b alike; Tests/Visual/sidebar_overlay_probe.gd does not parse (a stale ChoiceViewer.select() call, ~210). Found by P65b.
- WALL FOCUS test_focus_and_transition_signals_fire_during_real_navigation: 3 freed-instance SCRIPT ERRORs in PlayArea (_turn_the_entrance_over ~2768, the focused_visual getter ~3679, _refresh_card_marking ~3694) while hud_container.slide_to runs - 2 of 4 six-suite filtered runs on the P69 round-2 tree, 0 of 1 full gates, WALL FOCUS alone 0 of 2. Unmeasured lead: the SIDEBAR wall-surface row writes settings.base_delay 1.0 then back, and the setter broadcasts to every live listener in the shared window. Measure before naming a cause.
- PLAN VISUALS TP-63 (the two-grid card lighting): 2 checks ("precondition: the card is held -- 0", "grid 0 drew 0 of 3, grid 1 drew 0 of 3") in 1 of 1 overseer gates on the P64b-3f round-2 tree (it changes HudContainer.focus_sidebar, which game_view calls - not yet excluded). COUNT 2 natural (+1 under an artificial 40 ms/frame load, P76a). Earlier: 6 checks failed from its precondition "the card is held -- 0" in 1 of 2 overseer gates on the P70 tree, green alone and in an 8-suite filtered run; measured: P70's change is a no-op in that bare-GameView fixture (slide offset 0, card drawn where the press lands). Lead (unmeasured): settle_on accepts one unchanged frame after the second grid is added. Measure before naming a cause.
- VISUAL LAYERS light-snap row fired again: 1 of 1 implementer 8-suite runs on the P70 tree.
- Latent, traced by the P64b-2a re-review (unmeasured): at a side-layout window narrower than ~1072 px (the container is 0.25 of the width, the Back/Forward/Wall row authored at x 12..268) the deck over the chooser (overlay layer + 1) covers the Wall button's outboard ~18 px, and a click there closes the deck instead of pressing Wall.
- PIXELS "card_scale 1.5 ... one source texel is one size on both, and the pip's rim is exactly 1 art unit" (pip (46,46) vs prop (36,36) + rim (12,12), 6.0 px per art unit): 1 of 2 overseer gates on the P64b-2a round-2 tree, 0 of 1 on round 1's; never seen before. Measure before naming a cause.
- GRID VIEW "3 grids, grid 1 reached by a click on it: it is centred in the board's window" (block centre 970.72 vs window 971.87) and its "...Entrance is drawn under it" follow-on: 1 of 2 overseer gates on the P67 tree (P67 touches only the map picture); 1 of 1 on the P64b-3b round-1 tree (1014.40 vs 1015.61; 3b touches the menu focus and Main's warm-up end). COUNT: 2 of the 3-failure budget. Measure before naming a cause.
- FOR P64b-2b: Wall.initial_layout (wall.gd ~81-82) restates the map's square (design_size from the default's height, keep_aspect) beside layout_default.tres, and nothing compares them (Fable review of P67) - add the comparison to test_layout_is_loaded_from_disk_not_hardcoded or delete the two lines (only the editor reseed and that test reach initial_layout). And test_sidebar's _click_outside_the_map_viewer pushes into _map_viewport - it breaks when 2b moves the map viewers to the overlay.
- Scripts/Map/world_map_controller.gd _unhandled_input carries a typed-in wheel zoom factor 1.15 (a tunable literal, found by P64b-2b round 3).
- UI VIEWERS "a later arrow never drags the focus back to the first card": 1 of 1 overseer gates on the P58c-2 tree, 1 of 1 on P58b-B's; 1 of 1 implementer nine-suite runs on the P64b-2b tree (WALL FOCUS booting Main in the same window), 0 of 4 alone.
- FOR /simplify AT THE CLOSE: solatro/UI/autosize_label.tscn, big_number_label.tscn and map_hover_panel.tscn are instantiated by no production scene (map_hover_panel only by test_leak_canary; map.gd calls its static get_info) - Fable reviews of P58b-5 and P58b-7's question.
- sidebar_snapshot (not a suite) sometimes leaks at quit - "631 ObjectDB instances leaked, 27 resources still in use", --verbose: 398 Resource (CardData, game scripts), 184 WeakRef, 3 GDScriptFunctionState - it quit()s while the map token is still travelling (map_after_travel ... moving=true): 3 of 7 runs on the P72 round-2 tree, 0 of 3 with HEAD's DeckViewer, 0 of 2 on round 1. Same shape as the quit-mid-walk chooser leak above. Measure before naming a cause.
- SIDEBAR test_the_wall_view_shows_one_surface_colour_behind_the_pictures "sanity: the move out to the wall showed the wall on enough frames" (3 of 7 / 4 of 9 frames); 1 of 1 overseer gates on the P58b-6 tree (4 of 11 at 600x1000), 1 of 1 on the P58c-2 tree (4 of 9 at 1280x720): 2 implementer filtered runs (2b, P72); a wall-clock frame count on a slow box.
- Hang risk, measured by P64b-3a's guard mutant: test_sidebar test_the_chooser_and_its_deck_are_hidden_in_wall_view_and_back_on_return waits in an unbounded `while _main._move_in_flight or slid_fraction() < 1.0` (~6280), so a broken return stalls SIDEBAR instead of failing it - bound it (await_drawn_frames' watchdog). Its deck-over-chooser focus check (~6079) passes with no focus owner at all - it proves "not under the deck", not "somewhere useful".
- SIDEBAR test_the_map_around_the_chooser_ignores_clicks_drags_and_the_wheel "sanity: a reachable node lies on the map outside the window" (a random map, no input involved): 1 of 4 implementer Sidebar-filtered runs on the P64b-3f tree. COUNT 1. Measure before naming a cause.
- SIDEBAR test_deck_from_a_stuck_possible_card_opens_over_the_list, its "a click outside the deck" pass, 7 checks from "a real click pressed the stuck card's Deck" on: 1 of 1 implementer six-suite soaks on the P80 tree (PlanVisuals WallFocus WallTransition Sidebar GridView DragPlace), green on its rerun. The row was re-pointed by P64b-3f. COUNT 1. Measure before naming a cause.
- Latent, traced by the P80 review: PlayArea.set_card_zones (play_area.gd ~2663) still fills the board's data_ui from CardEnvironment.get_current_game(), and P80's own-board rule compares against that dict - a rebuild of board A while CURRENT is game B would refill A's dict with B's cards and free every A card a frame later. No caller today (one live show; the warm-up never rebuilds another board). Same shape: the discard/rules flights (card_visual.gd ~709-713, ~755-761) still target CURRENT's piles.
- NEW on the P64b-4 tree, 1 of 1 overseer gates: DRAG PLACE "precondition: the drag carried grid 1 nearest the middle of the window while the board is still AIMED at grid 0 -- nearest 0, pan_grid 0" and its two follow-ons (the cancel lands the nearest grid; 870.30 px off centre) - the drag pan moved nothing. That gate ran slow (SIDEBAR 787 s, DRAG PLACE 884 s vs ~555 s filtered); same family as the listed P50 DRAG PLACE timing rows (bare motion moving the board not at all). P64b-4 touches the menu, Main._on_run_lost, test_sidebar and a comment - no DRAG PLACE reach traced. DragPlace alone on that tree: 491/491 in 3 of 3 runs. COUNT 1. Measure before naming a cause.
- Latent, traced by the P71 review: CardsViewer._data_of (a third home for the card a listed control stands for) is filled only in inspect_on_highlight, i.e. only when populate got an on_inspect; modal_verdict's accept reads it unguarded. Every list that receives input passes on_inspect today (deck_viewer, choice_viewer, map_hover_panel).
- Test helper, traced by the P64b-3b review: test_sidebar _await_the_menus_slide (~7274, 9 callers, now also behind _wait_out_the_return) carries NO check although its docstring says it must fail one - a landing where the container is not wanted (wall view, the bare menu) silently burns CARD_CONTROL_TIMEOUT_SEC. Make it check, or fix the docstring.
- Hang risk, traced by the P72 review: test_sidebar.gd has six bare `await RenderingServer.frame_post_draw` with no watchdog (~1475, ~1496 inside a bounded while whose bound cannot help, ~1512, ~4645, ~5770, ~5771); one bare await stalled a SIDEBAR run once on the P72 tree (1 of 4 implementer runs; that row now uses TestSuite.await_drawn_frames). Move them onto await_drawn_frames.
- Latent, traced by the P72 review: WallOverlay._input (wall_overlay.gd ~84-89) treats every visible Control child under the pointer as a cancel target; the deck picker is now a full-window overlay child, so a right-click over its Dim is routed into the menu picture behind it (nothing on the menu reads the second button today).
- SIDEBAR "the map shows on the window's bottom" (_check_the_map_shows_around_the_chooser, test_sidebar ~5858: (0.1294, 0.1059, 0.1216) at (800, 656)): 1 of 2 implementer filtered runs on the P73 tree (P73 touches only the menu). Measure before naming a cause.
- FOR P64b part 3 (the Fable review of P73): the start menu's own buttons NEVER take keyboard focus (no grab_focus / focus_mode anywhere in menu.gd, menu.tscn, main.gd - pre-existing) against the one-device principle - a keyboard/pad player cannot start a run; latent: closing the picker slides the sidebar out and Content/Main re-wraps two lines -> one per slide frame, so a button can jump rows under a still pointer (resting_rect_beside is the map's precedent; the thirty-fourth-round wording "beside the sidebar as shown" may prefer today's).
- TOOLING, .claude/tools/gate.py (a small reviewed step of its own, not mid-run): it writes its last-gate state after ANY full run, a red one included, so the next per-suite diff can compare against a failed gate; a filtered run prints no ObjectDB/resources lines ("None" is expected there, not a parse fault); it tagged a GRID VIEW TP-138 failure NEW although Open bugs lists "GRID VIEW TP-138" (its Open-bugs match missed).
- AT THE END OF THE QUEUE: SIDEBAR test_the_wall_view_shows_one_surface_colour_behind_the_pictures "sanity: the move out to the wall showed the wall on enough frames" samples by a full get_image() readback per frame (~100 ms per sample visible, ~132 ms minimized), so a 1.0 s move yields 4-5 informative frames against a minimum of >4 - failed in the minimized P74 gate (4 of 9) and in implementer runs visible and minimized; make it count frames without a readback per frame, or sample a region. P74 review nits: all_tests.gd's keep-drawing window creation has three lines of ceremony (visible=false / show() / position after show) the engine may not need - check Window.force_native / initial_position in the 4.7 docs; the end check restores the window from MINIMIZED, which activates it for a frame before quit.
- TOOLING, rule audit - session of P75-P58e-3, P76: CAUGHT - the Fable broad group pass (p73-wip's wholesale restore would have reverted four steps - critical), Fable per-step reviews (the zero POLY headroom, the resample skip, one-call helpers), measure-first stops (6: the Shader Global premise, the corner model, the board-centre cap, the wall-view cost, the SubViewport focus, TP-92's cause), the full gate (the OS-window resize, the merge's 48% slowdown via a timeout), the OUTLINE saved-ShaderMaterial guard (main's editor re-save), the mutant rule on every new row. FALSE ALARM - godot-needs-private-appdata.ps1 blocked a python edit whose TEXT named 'Godot editor' (again - match a launch, not a substring); block-process-kill.ps1 blocked an explicit-PID foreach (one explicit Stop-Process per PID passed); one reviewer finding refuted by measurement (P58b-7's scrollbar double count). COST - the full gate per step (~15 min, ~22 gates; kept); a permission-classifier outage blocked an implementer's writes (8 failures, retried); the classifier refused ending orphaned Design Loop watch processes (left to the owner); ~18 hand-typed handoff-edit scripts and a per-suite diff script typed per gate - propose: gate.py compares per-suite counts with the PREVIOUS completed gate (today it compared a stale one: OUTLINE 43 -> 51 across two gates that were both 51), which retires the per-suite script. CEREMONY - the ~300-line handoff rule (672 lines; the verbatim rulings ~190) - propose again: count the rulings block out, or give the rulings their own file the handoff points at.
- TOOLING, rule audit (the /handoff Reflect step 3 tally; add to it each session). Session of P64b-P74: CAUGHT - Fable per-diff reviews (a real defect in most: the deck back empty, the menu click-outside strip, an undeleted helper, focus behind an opaque viewer), measure-first stops (6 premises overturned into owner questions), one Godot at a time, mutant red (4 rows proven on a restructured scene). FALSE ALARM - godot-needs-private-appdata.ps1 blocked 2 commands that only MENTIONED run_tests.py (a handoff edit, a docs heredoc): propose matching a launch, not a substring. COST - the full gate per step (~13-14 min, ~25 gates) - kept, it caught TP-63/GRID VIEW/P73 reds a filter missed. CEREMONY - the handoff's ~300-line rule (620 lines; the verbatim rulings block alone is ~160) - propose re-measuring the limit or giving the rulings their own section the count excludes; red-then-green satisfied while two rows still compared a value with itself (P65b, P73) - the mutant rule now covers it.
- Carried from finished rows (still open):
  - P12: mid-slide, the board window's white outline shows with bare board to its right; the zoom-never-changes row cannot fail at 1280x720 with one grid.
  - P13 (owner feedback, never answered): a map HOVER names the dot but no longer describes the node in the sidebar (so Travel and the description cannot disagree); clicking the chosen chooser card keeps it chosen; a click on bare map leaves the pick alone; the possible-cards viewer is translucent and sparse.
  - P17, FOR /docs AT THE CLOSE: sidebar DESIGN.md "Info mode, as it exists" (~214-224) names wall_info_mode, _on_info_toggled, info_zoom_state, _apply_info_mode, _restore_info_mode_for - none exists.
  - P18: fx_snapshot.gd's header says rotated panels are not reproducible while _settle_poses says the cause is fixed - reconciling them is a measurement (snapshot_diff.py NOISY).
  - P21: one TP-105 failure in 8 GridView runs (edge 316.000 vs 413.119, 97 px, not a ULP), not reproduced.
  - P23: no row covers a goal-met placement leaving the focus on Continue.
  - P24: the travel destination renders full-size for ~35 frames - cost on Box A unmeasured; a window resize mid-move shrinks it (not observed).
  - P42: no row drives a cancel over a viewer hosted on the map.
  - P44, latent: a re-parent mid-move lerps from a stale parent-space start; a dying view hears a re-emitted went_live; enter_game while the camera flies AWAY from a live game picture starts a show then freezes it. OWNER QUESTION never answered: a grid ADDED mid-show to a one-grid board waits for the ordinary lift (a, built) or clears the commitment (b); a one-grid commitment is never lifted (a, built) or lifts as before (b).
- FOR THE CLOSE (tooling, from the session reflection): two hooks match command TEXT, not the action - godot-needs-private-appdata.ps1 blocked a python script whose text contained run_tests.py, and block-source-rewrite.ps1 blocked a `sed` on MEMORY.md whose text contained the words of a PowerShell cmdlet; match a launch / a write to a source path, not a substring; solatro/visual-review/status.agent.json is rewritten by every shoot and never committed - gitignore it; round 2's Done never reached status.owner.json (still round 1), so the watch never fired - check the page's Done before round 3.
- TOOLING, .claude/hooks/commit-gate.ps1: it blames a commit for duplicate pairs already on HEAD (test_sidebar 959/1114 and 2150/2210 blocked P73, which created neither) - it should report only pairs the staged diff creates; and its [dup-ok] check reads the command line, not a `-F` message file.
- AFTER THE MERGE (owner: "After the merge"): GDScript lines where a `\` continuation was collapsed into one line, a space then 2+ tabs where the break was - 19 on this branch, 24 on main, partly different sets (`git grep -nP "\S \t{2,}\S" -- '*.gd' ':!*/addons/*'`). Once this branch is in main, split them all on a fresh branch off main, one commit, parse-checked by the logic tier.

## Next up
(Thirty-sixth round: a NEW task goes to the END of this list.)
1. P66 (re-check the 600x1000 Travel hang first).
2. P77 (root-window rows at the gate window's own size - a suite cannot resize the OS window).
3. P78 (visual review round 3's comments, one step each), then P79 (the review tool: stale comments, Done not landing, aliased images, the owner's command).
4. Visual review round 4 = P58d for everything not yet reviewed (P64b-P73, P78), then the close per /plan-run.

### Opening prompt for the next session (paste as is)

```
Resume solatro/HANDOFF_playtest_fixes.md on branch combine-sidebar-boardplan as the OVERSEER (never main; one verified step per commit, staging BY PATH, never `git commit -a`; you write no source - implementers do). Read CLAUDE.md, .claude/memory/MEMORY.md and the memories it indexes that apply (implementer-routing, brief-premise-is-a-hypothesis, tests-that-prove-nothing, one-fix-at-a-time, verify-visuals-by-eye, seam-checks-not-rereading, read-the-engine-docs, godot-key-events-no-bubble), solatro/visual-review/README.md, then the handoff: R1-R10 and every verbatim round through the thirty-eighth and visual review round 3 outrank the design docs they name. First `git status` and `git log --oneline -5`: expect a clean tree (only solatro/visual-review/status.agent.json modified - never committed) at or after the session-end handoff commit; `git branch --list p73-wip` shows the parked P73 (local to the machine that made it).

Then do "Next up" in order - a NEW task goes to the END of it: (1) P73, restored by its OWN hunks only (the command is in Next up 1 - never a wholesale checkout of test_sidebar.gd/NAMES.md from p73-wip), re-proved, the re-fit hypothesis measured, gated; (2) P64b part 3, P71, P66; (3) P77; (4) P78 (round 3's comments, one measured step each) and P79 (the review tool - fix before the next round); (5) review round 4 = P58d, then the close per /plan-run.

THE LOOP, every step: a brief naming the suspected writer with file:line, MEASURE FIRST, STOP with lettered owner options when a measurement contradicts the premise; Edit tool or python utf-8 only; one Godot at a time; park by file copy, never git stash; tests that press Travel for real see the travel through before teardown. Look at every PNG yourself. Spend the Fable reviewer per /plan-run § "Spending the reviewer" (targeted per judgement step with tests and shots, one broad pass per group, a check of every mechanism-shaping owner question, the close) - a finding is an implementer step. After TaskStop, or an agent that stopped with background work, list Godot/python/bash/node processes by start time and end orphans by explicit PID (/plan-run Interruptions). Then YOUR full windowed gate, in the background (~15 min): `py .claude/tools/gate.py --out <your scratchpad> --handoff solatro/HANDOFF_playtest_fixes.md -- --timeout 1800 --stall-timeout 900`; expect `ALL 51 SUITES: ~8130 CHECKS PASSED` (last: 8130 at 6a7cc42c), 19 placeholder warnings, 24 resources + 1150 ObjectDB, wrapper exit 1; compare PER-SUITE counts against the previous gate yourself (gate.py's own per-suite diff can compare against a stale gate - Open bugs) - BOARD FUZZ is random, SIDEBAR and WALL PAUSE move by their timing-conditional checks. Any RID / GL texture / PagedAllocator line or a higher ObjectDB count is a LEAK - never commit on it. Count the listed intermittents and never call one a flake. Commit with the evidence in the message and update the row.

ROUTING (.claude/memory/implementer-routing.md): plan-implementer (Opus, medium) when the cause is open or a state machine moves; plan-implementer-low when the writer is named; plan-implementer-sonnet for mechanical steps only; Explore on sonnet for read-only recon (the second slot). Continue a finished implementer with SendMessage for its next round. Answer from the handoff and the design docs before asking the owner; ask only with lettered options; record the owner's ACTUAL answer verbatim. At most two subagents at once, only one running Godot. The owner runs Design Loop themselves (`npm --prefix designloop start`); never stop a server you did not start. End the session - and every plan finish - with /handoff's "Reflect and record", unprompted, and say in your last message what you recorded and where.
```

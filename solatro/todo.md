# TODO — open backlog (owner-endorsed unless marked otherwise)

Add new items here; **delete an item when it lands**, recording the regression-critical residue in
ARCHITECTURE_REVIEW.md rather than keeping a log here. Current-state facts live in
ARCHITECTURE_REVIEW.md; done-work history lives in git.

## Next, in the owner's order

After the playtest-fixes stream closed. Owner: "prioritize the existing
todo after closing to merge all branches, including the new cloud linux branch, then the todo step
to migrate everything related to claude and solatro to new showitaire repo so we stop cloning entire
gamedev repo every time we create a branch. and any other related todo.md that is relevant to goal
of new repo split from gamedev. then we can review remaining todo again when done and decide what
task to do next."

1. **Merge every branch into `main`** (`/merge-branches`): `combine-sidebar-boardplan`,
   `board-plan`, `sidebar`, `test-speed`, `card-index`, `effect-levels`, `p73-wip`, the detached
   `gamedev-baseline`, and the cloud Linux branch `origin/claude/combine-cloud-test` (it contains
   `origin/claude/godot-cloud-test`). Measure first which of them main does not already hold.
2. **The Showitaire repo split** - the first item under "Planned by the owner" below, with every
   item here that serves it: the worldgen heavy images, the docs that name `gamedev`, and the
   whole-repo comment sweep that waits for the split (§ Doc hygiene backlog).
   Owner: "this will include cleaning up all the old branches no longer in use. end goal is new
   repo with one branch, and one branch for old repo too." So: once a branch is merged (or
   measured as already held by `main`), delete it locally and on `origin`, its worktree with it;
   `gamedev` ends with `main` alone, and Showitaire starts with one branch. Deleting a branch is
   confirmed with the owner per branch that carries commits `main` lacks.
3. **Review what is left of this file with the owner** and pick the next task.
4. **Build the forty-seventh round's rulings** (`RULINGS_playtest_fixes.md`), each red-then-green:
   a right-click anywhere unsticks a stuck chooser card; the show's map hover drops "3 acts to reach
   it"; the map auto-picks a lone onward node whenever it becomes the active screen (today only after
   a show or a Take); hoops are laid out by `Cards/Props/Formations/hoop.tres` (`prop_layer.gd` skips
   kind 0); a wheel over the sidebar never reaches the picture.

## Planned by the owner — notes to design in a later session

Recorded so they are not forgotten; none is designed yet. Each goes through `/flowchart-design`
(Design Loop) before anything is built.

- ⬜ **Split the repo: a new repo, "Showitaire".** It takes everything Claude works on or has
  touched: `solatro/`, `palette/`, `designloop/`, `worldgen/`, `.claude/`, `CLAUDE.md`,
  `.gitignore`. Everything else (the jam and study projects, `README.md`) stays behind.
  **Why:** every branch worktree checks out the whole tree. Tracked size at HEAD: ≈1.0 GB per
  checkout, of which the moving set is ≈175 MB (palette 82, worldgen 56, solatro 34, designloop
  0.7, .claude 0.3). Most of the rest is pokerlands 386, game jam fall ucsd 254, necromii 86 and
  martial rhythm 55. The 488 MiB history pack is shared by worktrees, but a fresh clone on another
  machine carries all of it.
  **Owner rulings:**
  - **Only after every current change is combined into `main`.** That covers this branch and the
    other worktrees (`board-plan`, `sidebar`, `test-speed`, the detached `gamedev-baseline`); the
    split starts from one `main`.
  - **Keep history where it is relevant to what moves**: `git filter-repo` on the moved paths keeps
    their history and drops the other projects' history from the pack.
  - **In the same phase, worldgen stops tracking heavy images**; they are generated at runtime.
    Measured at HEAD: 110 tracked images, 13.2 MB (`placement_debug/*.png`, `snapshot_*.png`,
    `procedural_generation_snapshot.png` 1.0 MB, `tests/height.exr` 0.5 MB). Check whether any test
    reads `tests/height.exr` as an input first. Other heavy tracked worldgen files that are not
    images, for the owner: `map_viewer.tscn` 20.3 MB, `worldgen_native/.sconsign.dblite` 13.6 MB
    (the SCons build database) and `worldgen_native/api/extension_api.json` 6.6 MB (Godot-generated).
    Dropping them from history as well is a `filter-repo` flag.
  - **Every doc stops pointing at the `gamedev` repo.** Files that name it today:
    `.claude/memory/machine-profiles.md`, `.claude/settings.local.json`,
    `.claude/skills/docs/SKILL.md`. Also rewrite the "monorepo of separate games" framing in
    `CLAUDE.md` and `dup_check.py`'s within-a-top-level-project rule.
  Also:
  - Claude Code's machine-local memory cache is keyed by the repo path, so it starts empty;
    `.claude/memory/` travels.
  - `worldgen/worldgen_native` is 591 MB on disk and untracked (build output), so a new clone must
    rebuild it.
  - `.git` has 54 orphan pack `.idx` files and 1.8 MiB of garbage; clean up when splitting.

- ⬜ **An effect demo system that is also the effect test system.** Owner's intent:
  - **One demo scene** for every effect added from now on. It is filled from a preset (environment
    settings plus the effect being demoed), and every demo uses it.
  - **It runs recorded actions**, and can run many recordings. Recordings are also the effect's
    unit tests: a replay's outcome is validated.
  - **A dedicated viewer** loops a recording's actions, resets, then repeats or moves to another
    preset. It is the preview in card descriptions: the real scene running, not a video. The viewer
    can choose which recordings a preview focuses on, how many it cycles through, and its viewport
    zoom.
  - **Playtestable:** enter a demo and play on from its current environment for playtesting and
    debugging, recording what happens so the outcome can be validated.
  - Model: Minecraft's GameTest, where test structures spawn inside a playable world the player can
    walk into. This goes one step further with a preview on top.
  Related, already here: recorded actions are a command log, the same thing as D6 command-log undo
  (Architecture below). A replay is only valid if randomness is deterministic, which is the RNG
  layer below. The description preview is `CARD_SIZE * 2` on every surface. Hard rule 9 (no mocks
  in tools) means the demo hosts the real board. `design/effect-review/` lists the effects that
  will need demos.

- ⬜ **A dedicated random-number layer**, built from
  [Correlated randomness in Slay the Spire 2](https://tck.mn/blog/correlated-randomness-sts2/).
  Owner: do not copy Slay the Spire 2's system — the article is about its bugs and their fixes —
  build the best version. What the article measured going wrong:
  - Each stream was seeded as `seed + hash(name)` on a generator whose state is LINEAR in its seed,
    so streams meant to be independent were correlated. Early draws in one stream constrained
    another's: an act's curse pool skewed the first potion drop (76 % against 4 %), the first orb
    target and reward gold, and some items became unreachable.
  - A save stored each stream's call count, and a load replayed that many calls: quadratic, and
    stateful.
  - The engine's library generator differed across platforms and runtime versions, so one seed gave
    different runs.
  Its fixes, to weigh rather than adopt: a non-linear generator (PCG32, xoshiro256**); keys DERIVED
  by a strong hash of (run seed, stream name, context), never seed arithmetic; stateless or
  counter-based draws (`value = hash(key, index)`), so a save is a key plus a counter and a load
  replays nothing; our own implementation, so results do not change with an engine version or
  platform; and a test that correlates draws across stream pairs over many seeds.
  Where Solatro stands: 46 random call sites in 16 production files (`randi`, `randf`,
  `*_range`, `shuffle()`, `pick_random`, `RandomNumberGenerator.new`), most on Godot's global
  generator. `Game.shuffle_deck` is unseeded (board plan, above). `BoardPlan.deal` already derives
  a context key, `plan_seed = hash(Vector2i(world_seed, current_node_id))`, with its own
  Fisher-Yates (ARCHITECTURE_REVIEW §3e). `worldgen/` seeds itself. Required before any
  seed-sharing feature and before demo replays.

- ⬜ **An effect-review pass for each effect's level-2 form "when hitting its mark".** Opus 5.5 is
  the main agent on high effort and Fable 5.1 (`pair-reviewer`) reviews it.
  **In flight: `HANDOFF_effect_review.md` S14.** It goes through
  `design/effect-review/` (1,595 live questions; `build/dupes.tsv` already lists ~150 duplicate
  candidates) and proposes each effect's level-2 form. Bonus: it weeds out duplicates. Where one
  effect's level 2 is the same as or close to another effect's level 1, merge or drop one.
  **Already designed:** board-plan `PLAN.md` §1.7 has exactly two levels, passed as the `level`
  argument of `on_mark_hit` and `on_mark_covered` (0 = normal, 1 = realized; the owner calls these
  level 1 and level 2). A talent match fires the skill's level-2 form and always pays a flat mult,
  even for an effect with an upgraded form. A mark is the cell's own zone card printing a rank, a
  suit, a talent and a hat (ARCHITECTURE_REVIEW §3e).
  **Owner rulings:**
  - **A match is same kind to same kind**: suit to suit, rank to rank, hat to hat, skill to skill.
    A property's level 2 is unlocked by its own match only.
  - **Suit level 1 is a normal suit for scoring and making melds. Level 2 is level 1 plus its
    additional effect.** The same for rank. The built suit rule stands (`PLAN.md` §1.6): a suit
    effect fires only where its cell's mark agrees on suit. So today's suits already have this
    shape: the suit counts for melds everywhere, and its prop effect is the level-2 addition on a
    suit match.
  - **Level 1 and level 2 are two different effects in the same class and file**, not a subclass.
    Do not extend; that is more complicated.
  By the same reading, today's rank-match points bonus (`plan_rank_match_step`, §3a) is rank's
  level-2 addition. Confirm that at the start of the pass.

- ⬜ **Effects become data: one `.tres` row per effect, catalogued by YARD.** `addons/yard` (v1.2.0)
  is installed and enabled; nothing uses it yet. Goal: every value an effect carries is a table
  cell, tuned without opening the effect's class, and a class holds behaviour only.
  **Owner rulings:**
  - *"shared stats should become export if its necessary to fit into yard"* — this reverses the
    TODO at `Cards/card_modifier.gd` that asks for abstract getters instead.
  - *"combo identity for stable id sounds reasonable"* — `combo_key` stops using the script path.
  - *"one script per effect sounds better"* — no shared scripts with numeric variants.
  - *"dont randomly upgrade before a full release"* — YARD stays on a released version.
  - Edit Resources as Table 2 (don-tnowe) is the suggested bulk editor, **not installed until
    needed**. Check it on 4.7 first; it shows typed arrays of custom resources empty (its issue 117).
  **The shape:**
  - Each effect is a `.gd` (hooks only) plus one `.tres` (its values). A registry lists saved
    instances, not scripts, so the `.tres` is required even with one script per effect.
  - Shared stats are `@export` on `CardModifier`: `effect_id`, `name_key`, `description_key`,
    `rarity`, `tags`, `frame`, pack weight. Per-effect numbers are `@export` on the effect's own
    class, with shared names (`amount`, `mult`, `count` and their level-2 twins) so one column
    sorts across every effect.
  - **Store the fact, derive the words.** `get_str()`/`get_description()` are written once on the
    base and read the fields; the description key carries a slot the number fills, or a retune
    leaves the text lying. A method stays a method where the answer is computed or differs by class
    (`PipRankNumeral.get_str`, every hook).
  - Expose a value when someone will tune it; a literal whose change makes a different effect stays
    in code (hard rule 8). Game-wide knobs stay in `player_settings.gd`.
  **Why values live in the `.tres`, not the script:** GDScript cannot redeclare a parent's `var` or
  `const` in a subclass, and the engine will not add it (godot-proposals issue 10060, closed). A
  subclass declares none of the base stats; its `.tres` sets them. ⚠ **No subclass assigns a base
  stat in `_init()`**: a stored value overwrites it after `_init` (godot issue 98342), and since
  4.5 a value equal to the declared default is not written to the file (godot PR 107049), so the
  `_init` value would replace a row set back to the default.
  **What replaces `@abstract`:** a `.tres` cannot be forced to hold a value — a missing property
  loads as the declared default, silently. So the defaults are neutral and detectable
  (`Rarity.UNSET` first, `frame = -1`, empty keys), and:
  - a catalogue test walks every registry row and fails on an unset stat, on an effect script with
    no row or two, and on `effect_id` disagreeing with the row's registry id;
  - the registry load path `assert`s the same preconditions (debug only, hard rule 7).
  **Seams the migration must close:**
  - **`.new()` skips the table** — it returns script defaults. Every construction site loads the
    row and `duplicate(true)`s it: `Decks/deck.gd`, `Cards/Types/type_booster_basic.gd`,
    `Cards/Skills/Rules/skill_grid_allotment.gd`, and tests. A duplicate per card is also required
    because a modifier holds per-game state.
  - **`effect_id` is stored on the effect**: a duplicate has no path, so YARD's
    `get_string_id_of()` cannot find it. The combo identity reads `effect_id`.
  - **Tests read the row, not a literal**, or every retune breaks them.
  - **Open, for the owner — a saved run keeps the values it was dealt.** `run.tres` embeds each
    card's modifiers, so a retune does not reach a saved run. Either accept that, or save only
    `effect_id` plus per-game state and reload values from the registry. Rarity and weights do not
    matter once a card is in the deck; per-effect numbers do.
  **Tooling:**
  - A one-off importer from `design/effect-review/EFFECTS.csv` (id, name, slot, class, family)
    to `.tres` rows, in the `design/effect-review/build/` Python pipeline.
  - One registry per slot (skills, stamps, hazards…), class-restricted. Index the fields booster
    packs query (`rarity`, `tags`, class, family, weight) so `where({...})` needs no loads.
  - Bulk edits by an agent go through a windowless Godot script (load, set, `ResourceSaver.save`)
    with the editor closed, then YARD's `sync_from_scan_directories` and `rebuild_property_index`
    (`addons/yard/editor_only/registry_io.gd`); whether those run without the editor is unmeasured.
    A new `.tres` gets its UID only on import, and YARD keys on the UID: create, import, then sync.
  **YARD cautions:** keep registries committed (an upgrade once wiped them, its issue 95); never move
  a registry's class-restriction script (it resets every string id, its issue 122, open on 4.7);
  no multi-cell bulk edit (its issue 56).

- ⬜ **By default a grid and its score labels form a perfect square: treat it as 6×6.** The 5×5
  cells, row scores in the LEFT column, column scores in the BOTTOM row, and the special score in
  the bottom-left corner square. The gap between squares is the same everywhere, in x and in y.
  This is the default look only: once cards stack, the grid still deforms to keep every card
  visible. Cards are becoming 52×52 (owner's change in progress), so square cells come free.
  Today `PlayArea._create_grid_panel` puts row labels left and column labels below, as wanted, but
  the special label sits RIGHT, centred on the grid, and the gutters are only as wide as the label
  font needs.
  Open:
  - The gap between grids rests on the score gutters (owner ruling: the minimum distance between
    two grids is the score labels' width), so a cell-wide gutter moves that gap.
  - Height scores stand above their stacks and are not part of the 6×6.

## Known intermittent test failures (not owned by any current work stream)

✅ **THE LOG-COPYING THIS SECTION ASKED FOR IS NOW AUTOMATIC.** `run_tests.py` copies the whole log
directory aside — to `<user data>/Solatro/logs-stalled-<stamp>` or `logs-failed-<stamp>` — before it
kills a stalled run or reports a failing one. `--stall-timeout` (default 600 s) also watches the test
log's SIZE as a heartbeat and NAMES the suite that started without finishing, instead of letting one
silent suite eat the whole budget and report `NO SUITE BANNER` for all 48.
⚠ **SO THE RULE IS NOW: DO NOT RE-RUN BEFORE READING THE PRESERVED LOGS.** The evidence survives one
occurrence, not two — the next run still truncates the LIVE log, and a preserved directory is only
written when a run stalls or fails.

- ⬜ **The suite intermittently HANGS — a third mode, distinct from the segfault and the leak.**
  Killed at the timeout with **no banner**, so it never reached its own verdict. ⚠ A hang is not a
  crash and not a failure count — the wrapper prints `NO SUITE BANNER` + `TIMEOUT` with both gates
  "clean" underneath, which skims as healthy. Where it stops: **30 of 39 suites banner and pass**;
  `PIXELS`, `OUTLINE`, `INTERACTION`, `WALL INPUT`, `WALL PAUSE` and the chain behind them never
  print. Every one of those completes cleanly when run ALONE, so it is in the concurrency, not in
  any suite's logic — suspect shared render/GPU state or an `await_siblings_except` race.
  **Clusters in time: 3 consecutive hangs, then a clean HEAD twice, then the same working tree
  twice — 3 hangs and 4 passes with no code difference between them.**
  ⚠ **So a hung run is NOT reliably attributable to the change that produced it.** Re-run before
  bisecting; each attempt costs ~7 minutes. (The one-fix-at-a-time working agreement used to say a
  hang IS the change's fault outright; it now carries this exception.)
  ⚠ **SEEN AGAIN IN THE 45-SUITE ERA, AND IT PREDATES THE GRID BRANCH** — so this is not
  poker-patience's. One occurrence in 13 full runs: `GRID VIEW` printed its banner and then emitted
  ZERO checks for 27 minutes until the global timeout. Six runs aimed straight at reproducing it
  produced none. **What the evidence narrowed it to, and it is stranger than the concurrency theory
  above:** `TestLog.line` flushes EVERY line, so the log is write-through and its last line is the
  last line reached. The next statement after that banner is another `TestLog.line` that never
  appeared — so the stall sits between two consecutive log writes, in a window with no loop, no
  await and no branch, while the process burned a full core. ⚠ Two confident explanations were
  written down and both were WRONG: `GRID VIEW` has no concurrent siblings (every suite it excludes
  waits for IT), and every wait on its path is bounded. Do not re-derive either.
  **Untried, and now cheap:** subsets cost seconds since `run_tests.py --filter`, so the hang is
  bisectable BY SUBSET for the first time — the suites above pass alone, so ask which COMBINATION
  reproduces it.
- ⬜ **Godot intermittently SEGFAULTS during final teardown**, after the banner and log paths print
  normally. Still unattributed — likely the exit-time leak's family, objects surviving into
  `cleanup()`. ✅ `run_tests.py` no longer misreports it: an exit status outside 0..125 is not a
  failure count, so a crash is named as a crash rather than read as 125 failures under a banner
  saying PASSED. **One observation total; did not recur in 7 runs.**
- ⬜ **PIXELS' mask-vs-art check is intermittent, and it is NOT ruled on.**
  `t=0.00: at rest the mask and the drawn face agree exactly` fails with **0 mask-without-art,
  3773 art-without-mask** — the mask polygon is valid (the "hands its rig to the mask, vertex for
  vertex" check passes in the same run) but disagrees with the drawn art everywhere, which reads as
  the card's art captured at a different pose than `card.fx._poly` describes. Seen in 1 run of 3,
  then again later. Most likely a settle/capture race in `_real_card()`/`_shoot()`, not a bad bound.
  ⚠ **Do not widen the bound** — the test's own comment says DO NOT RAISE IT TO GO GREEN, and the
  owner's ruling on the rotated-ball rows deliberately did not cover this one.
- ⬜ **LEAK CANARY +1, intermittent.** Rate has moved: ~1 run in 6, then 0 in 8 after S23, now **0 in
  7 more**. ⚠ Not fixed — it once passed 6 consecutively before failing. The suite prints
  `_report_growth` on the failing run (node/resource/other split, plus a running-tween count — a
  `Tween` is RefCounted and self-sustaining, which fits every observed property), so the next
  occurrence explains itself if the log is kept.
  ⚠ The **exit-time** ObjectDB count is a different measure and **not** a regression: 4 before this
  work and 4 now.

## Open bugs from the playtest-fixes stream

The `combine-sidebar-boardplan` stream's residue. The heading starts `## Open bugs` so
`gate.py --handoff solatro/todo.md` can match a failure against it. Every intermittent: measure
before naming a cause; a third failure makes it a fix step (RULINGS_playtest_fixes.md, thirty-seventh
round). Counts are failing runs of runs.

**Owner questions**
- OWNER QUESTION (R5 reading): a drag released off a legal cell puts the card back over its slot
  but keeps it IN HAND (lifted, drop map lit) until placed or cancelled — "release anywhere else
  returns it" was read as returns-to-slot, not drops-the-hold.
- OWNER QUESTION: by keys, a transient (unsticky) game description survives overlay Back and is
  re-shown on Forward over a card nothing is on, with no X. `HudContainer._entry_by_screen` says a
  return re-shows; the second playtest (2) says an unsticky description closes when unhovered.
- OWNER QUESTION: the picture-wall design DAG warns QR6's default (a) reaches nothing — Q76 is gated
  `[QR6=b|c]`, Q77 `[QR6=b]`. Widen the gates or change the default.
- A look for review round 4: at 600x1000, sidebar out, the portrait board's centre y is 383 against
  the picture's 457; the formation editor's hoop group sits left of the stand-in card's centre.

**Intermittent test failures**
- VISUAL LAYERS "one frame after the section changes, no circle has SNAPPED to its new card": 3
  implementer runs (P44, P58e-3, P70 trees). Lead, read not measured: `spotlight_director` advances
  `b.t += delta / travel`, so one long frame can finish a whole travel.
- PIXELS "fire brightens when its host is highlighted" (0.272 plain vs 0.250): 1 of 5 gates.
  PIXELS "card_scale 1.5 ... the pip's rim is exactly 1 art unit": 1 of 2 gates.
- GRID VIEW TP-138 "the board at rest is already where an explicit pan puts it" (-445.7 vs -443.3,
  1 px bound): 1 of 5 runs.
- GRID VIEW "3 grids, grid 1 reached by a click on it: it is centred in the board's window" (970.72
  vs 971.87) and its "...Entrance is drawn under it": COUNT 2.
- GRID VIEW TP-105 "a real grid_pan_right key press steps the view one grid" and "repeated
  pan-right presses stop at the board's last grid", with UI PROPS "the row sweep never reverses
  direction" and "hoop sweeps its row in ONE direction": 1 of 2 gates on a shared box. A different
  TP-105 check failed 1 of 8 GridView runs (edge 316.000 vs 413.119).
- GRID LAYOUT "TP-85: caught mid-growth, the row is PART WAY to its new height": 1 of 2 gates on a
  shared box; 139/139 alone.
- DRAG PLACE "...and bare motion afterwards moves the board not at all" (-836.74 -> -837.32),
  "leaving the picture stops the slide exactly where it stood" and "the slide was caught part way
  across": 1 of 2 runs. DRAG PLACE "precondition: the drag carried grid 1 nearest the middle of
  the window while the board is still AIMED at grid 0": 1 slow gate (884 s vs ~555 s); 491/491
  alone 3 of 3.
- SIDEBAR "Close fix 2: a new run's map opens on the HUD, not the last run's pack description": 1
  of 2 SIDEBAR-including runs, 0 of 8 alone.
- SIDEBAR "sanity: a reachable node lies on the map outside the window" (a random map): COUNT 1.
- SIDEBAR test_deck_from_a_stuck_possible_card_opens_over_the_list, its click-outside pass (7
  checks from "a real click pressed the stuck card's Deck"): COUNT 1.
- SIDEBAR "sanity: the picker opening at (1280, 720) is sampled mid-slide" (frames over ~100 ms in
  a 0.25 s slide): COUNT 1.
- SIDEBAR "the map shows on the window's bottom" (test_sidebar ~5858): 1 of 2 filtered runs.
- SIDEBAR "with no sidebar the map's camera carries no shift at all" (-0.00051) and "the
  container's own rect follows a real resize" (x -0.00384): exact compares against a derived float
  (tests-that-prove-nothing item 19). COUNT 1 each.
- WALL FOCUS test_focus_and_transition_signals_fire_during_real_navigation: 3 freed-instance
  SCRIPT ERRORs in PlayArea during `hud_container.slide_to`, 2 of 4 filtered runs, 0 full gates.
  Lead, unmeasured: the SIDEBAR wall-surface row writes `settings.base_delay`, and the setter
  broadcasts to every live listener in the shared window.
- LEAK CANARY "OBJECT_COUNT returns to baseline after 3 full simulated play sessions" fails ALONE
  or in a small filter (growth 40, 40, 4, 32, all RefCounted) and passes in every full gate.
- A teardown 0xC0000005 after the banner (THE ENGINE TERMINATED ABNORMALLY): COUNT 2, filtered runs.
- A worldgen teardown abort 0xC000001D in `addons/worldgen/core/steps/rivers.gd` (a Main torn down
  mid-generation): 1 abort + 1 post-banner SCRIPT ERROR in 5 Sidebar-including runs, 0 gates.
- WALL PAUSE's count moves 71 <-> 72 on unchanged code (a timing-dependent emit); never red.
- Gate totals move only through BOARD FUZZ (randomised): compare per-suite tables in
  `logs/test/test_output_all.log`. Unexplained: before P15 SIDEBAR read 1391 full vs 1406 filtered.
- A LEAKED LIVE BOARD between suites: a settings write in WALL FOCUS rebuilt a PlayArea another
  suite left alive. Find the suite that does not free its Main/GameView.

**Latent product defects** (traced from code, unmeasured unless stated)
- GameView's `description_dismissed` handler nulls `play_area.locked_data` with no screen check: an
  X on a MAP description strips the frozen board's lock marking while the game's locked entry
  survives; `exit_accepted` likewise rests focus on a frozen cell.
- Deck over the chooser, nothing stuck: an arrow off a deck card may land on Take under it; Take
  closing the chooser frees the deck's stuck lock with its sticky left set.
- A game pile opened (over = false) over the map's deck-over-list stack takes `DeckViewer._open`
  and drops the list from `_open` and `_under`; a Possible cards press then opens a second list.
- Freeing Main while the token walks onto a pack node leaks the chooser `_open_booster` is building
  (RID and GL texture leaks, a PagedAllocator line; 1 of 5 runs). `sidebar_snapshot` leaks the
  same way when it quits mid-travel (631 ObjectDB; 3 of 7 runs).
- The wall drops input while a move is in flight (`Wall._unhandled_input`, `input_locked`), so
  fingers lifted during a pinch-in's zoom-out never reach PinchTracker and every later pinch is
  refused. Tests work around it.
- A Down pressed within a pan's ease picks the Entrance stop from a mid-flight x.
- Below ~1072 px wide (side layout) the deck over the chooser covers the Wall button's outboard
  ~18 px; a click there closes the deck.
- `PlayArea.set_card_zones` fills `data_ui` from `CardEnvironment.get_current_game()`: a rebuild of
  board A while CURRENT is game B frees every A card a frame later. No caller today.
- `CardsViewer._data_of` is filled only when populate gets an `on_inspect`; `modal_verdict`'s accept
  reads it unguarded. Every input-receiving list passes one today.
- A chooser of 11+ cards would show above/below a run deck opened over it (the deck window is the
  space less margins; the chooser may grow full height). No pack offers 11+ today.
- `WallOverlay._input` treats every visible Control under the pointer as a cancel target: a
  right-click over the deck picker's Dim reaches the menu picture (nothing reads it today).
- Measured: a Container resets its child's scale on every re-layout, so a score-line text change
  during the combo pulse (`game_view.gd _on_combo_changed`) cuts the pulse short.
- P12: mid-slide, the board window's white outline shows with bare board to its right.
- P24: the travel destination renders full-size for ~35 frames — cost unmeasured.
- P44: a re-parent mid-move lerps from a stale parent-space start; a dying view hears a re-emitted
  went_live; `enter_game` while the camera flies AWAY from a live game picture starts a show then
  freezes it.
- `map.gd` shows literals that bypass TRANSLATION ("Tour complete!", "Continue tour", "Fame: %d");
  `world_map_controller.gd` `_unhandled_input` types the wheel zoom factor 1.15.
- A cold editor parse of `FxSpotlightStyle.circle_radius`'s derived default is unmeasured; saving
  `spotlight_default.tres` from the inspector with that knob touched writes a literal and stops
  the derivation.
- An editor re-save of `Cards/card_visual.tscn` can drop `auto_calculate_length_and_angle = false`
  from the leaf Arm_* bones (~48% slower suite); OUTLINE test_leaf_bones_do_not_auto_calculate
  catches it. ~58 s of the full run (mostly SIDEBAR) is still slower than on bd8c9f81 — one run.
- For when the glow ships in game (Box A): POLY 40 costs the card glow +1.56 ms (+40%) over POLY 24
  on a window of glowing cards; the posed rig's busiest wedge slot sits exactly on
  WEDGE_CANDIDATES (8), zero headroom — OUTLINE's posed row goes red first.

**Tests, harnesses and tooling**
- `Tests/Visual/plan_reveal_shot.gd` does not parse (~116 `draw_card()` with too few arguments).
- `Tests/Visual/wall_frame_probe` (600x1000) draws every non-game wall-view picture as a flat brown
  panel.
- `prop_art_snapshot.tscn` emits four "previously freed ... TypedArray" teardown errors from
  `prop_visual.gd` ~299.
- `sidebar_snapshot` hung twice (after chooser_window, after description_follow; COUNT 2) — lead:
  `_leave_the_map_and_come_back` awaits `slide_settled` with no timeout. Its score_line_pulse is
  staged on the random deal, so 1 of 2 runs wrote no PNG and `review.py shoot` failed the round.
- test_sidebar hang risks: `test_the_chooser_and_its_deck_are_hidden_in_wall_view_and_back_on_return`
  waits in an unbounded `while` (~7547) — bound it; its deck-over-chooser focus check passes with
  no focus owner at all. Eight bare `await RenderingServer.frame_post_draw` (~1550, 1571, 1587,
  5340, 6849, 6850, 8118, 8119) belong on `await_drawn_frames`. `_await_the_menus_slide` (~7274)
  checks nothing although its docstring says it must fail one.
- P18: `fx_snapshot.gd`'s header says rotated panels are not reproducible while `_settle_poses`
  says the cause is fixed — reconcile by measurement (`snapshot_diff.py` NOISY).
- P23: no row covers a goal-met placement leaving the focus on Continue. P42: no row drives a
  cancel over a viewer hosted on the map.
- `PlayArea.rest_focus_on_board()` keeps a fallback for a held card with no control whose only
  producer (the auto-arm) is deleted — settle by `assert` plus a suite run.
- `Tools/spotlight_tool.tscn` has an ext_resource at `user://settings.tres` (the PLAYER's
  settings); it and `formation_editor.tscn` reference scripts as `res://tools/...`, and
  `spotlight_tool.gd` ~10 loads `res://tools/spotlight_scenarios.json` — the folder is `Tools/`.
  Its `-- --verify` under a fresh APPDATA exits 1 on `LeakSentinel: 10 CardData alive, 0
  reachable` (the missing settings file's three errors appeared in one measurement, not the next).
- `gate.py` writes its last-gate state after a red full run too; its Open-bugs match once missed
  "GRID VIEW TP-138" and tagged it NEW.
- Two hooks match command TEXT, not the action: `godot-needs-private-appdata.ps1` blocks a command
  that only mentions `run_tests.py`, `block-source-rewrite.ps1` a `sed` whose text names a cmdlet.
  `solatro/visual-review/status.agent.json` is rewritten by every shoot and tracked — gitignore it.
- After the merge (owner): split the GDScript lines where a `\` continuation was collapsed (`git
  grep -nP "\S \t{2,}\S" -- '*.gd' ':!*/addons/*'`; 19 here, 24 on main) on a fresh branch off main,
  one commit, parse-checked by the logic tier.

**Docs**
- The rim-ink records (`design/board-plan/gaps/GAP-004.md`, `design/sidebar/ASSUMPTIONS.md` ~993)
  carry no pointer to the seventeenth round.
- The design records still quote the pre-P43 picture (1576x887, inset 394, 262.7, 733.808, the 27+8
  band): `design/sidebar/{DESIGN,PLAN,TEST_PLAN,ASSUMPTIONS}.md`, sidebar gaps GAP-001/GAP-002,
  `design/poker-patience/gaps/GAP-039.md`, `Tests/Visual/grid_zoom_shot.gd` ~214.
- `design/card_size_outline/IMPACT.md` names `corner_notch`, `SHIPPED_CORNER_NOTCH`,
  `notch_fraction` (removed) with file:line links that no longer hold them.
- `design/picture-wall/DESIGN.md` ~150 and ~890 cite the map's deleted `ZOOM_MIN 0.5`.
- `design/sidebar/DESIGN.md` "Info mode, as it exists" names `wall_info_mode`, `_on_info_toggled`,
  `info_zoom_state`, `_apply_info_mode`, `_restore_info_mode_for` — none exists.

## Doc hygiene backlog (code comments — measured, not yet triaged)

- ⬜ **`doc_check.py` scans code comments. Standing count over 334 source files (the combined
  branch): 2515 indented · 952 long doc · 329 long block · 307 trailing · 257 design id · 84 dated
  · 55 history · 49 restated · 3 line refs.** Zero errors — every reference resolves.
  ⚠ **A BACKLOG, not a regression**: the rules postdate the comments.
  **Owner ruling: two halves.** (1) Every file an agent edits leaves compliant — the whole file,
  not only the lines it wrote (`plan-implementer` says so; `doc_check.py --changed` errors on
  the three hard rules for touched files). (2) ⬜ **A FULL PASS OVER EVERY SOURCE FILE is
  planned by the owner**, because files nobody edits are never swept by (1): the untouched
  majority of the count above only drains that way. Schedule it between work streams — it touches
  every file and would conflict with any branch in flight — and after the repo split below, so it
  sweeps only what moves. `--verbose` lists them; `dated` is the category to leave alone (see
  below).
  ⚠ **`dated` will not go to zero and should not**: many are measurements, where the date is part
  of the fact, and the checker cannot tell those from bookkeeping.
  ⚠ **`design id` is the one that matters most** — 362 citations of design documents the code's
  reader cannot open. It is a standing breach of the no-design-ids-in-code rule
  (ARCHITECTURE_REVIEW §8), inherited from earlier work streams.

## Waiting on the owner

- ⚠ **`design/board-plan/` is BUILT and CLOSED** — every cell opens with
  a mark, a match pays into the line it scores, a suit effect fires only where its cell's mark
  agrees on suit, marks act at landing and at every line score, the layer view and the reveal
  cascade ship (ARCHITECTURE_REVIEW §3a/§3e/§4). All six gap rulings are landed (`PLAN.md`
  §1.10-bis). Waiting on the owner:
  - ⬜ **Input during the opening reveal.** The board is live while the deal animates (a placement
    made then is an undo step since the close); whether the deal should lock input for its ~1 s is
    undecided by the design — today it does not.
  - ⬜ **A row reroll on a saturated board redistributes the row's own faces** (the deck-cycling rule:
    the given-up faces are the fewest-copies tier); only unused identities yield fresh ones. Whether
    a line reroll should prefer faces the line did not have is the owner's call
    (`design/board-plan/ASSUMPTIONS.md`, close F2).
  - ⬜ **Same node, same plan holds only while the draw pile's order is the same** — `plan_seed` is per
    node, but `Game.shuffle_deck` uses the unseeded global generator, so a node replayed shuffles
    differently. Seeding the deck shuffle is outside the plan.
  - ⬜ **For the owner's eye:** whether "no rim" alone reads as a mark at overview zoom; and under a
    scoring beam at phase 0 the activated gold rim is the least tellable instant (verified at the
    close, `TEST_PLAN.md` TP-72's beam half).
  - ⬜ **`_check_board_fits_window` measures a stale invariant.** It compares Entrance coords against
    the board's `SmoothScrollContainer`, but the Entrance is pinned OUTSIDE that scroll, so the check
    fails on the shipped five-slot board (the board's right edge past the scroll's) although the
    board fits the window with room to spare; the surviving WIDE=12 row passes only
    because the grid container is sized from the Entrance width. The board plan dropped the call on
    the moved all-kinds fixture rather than assert it. What the pinned Entrance's reachability
    invariant is (fits the window, or its own `EntranceHTrack`) is the owner's; then the helper
    and both callers follow.
  - ⬜ **Touchscreen:** tapping on nothing while a card is held should cancel the hold (owner,
    from playtest); today only a real drop target or a second tap on the card releases it.
  - ⬜ **Recorded, no producer today.** A card an EFFECT moves off a marked cell keeps its last
    `match_rim_active` rims on the pooled visual until the next rebuild (`Game.move_card_in_grid`
    has no shipped caller); an effect MOVING a card onto a mark fires no landing hook until a line
    scores; a window losing focus while `M` is held may leave the layer view open until the next
    press or board mutation (what the engine delivers on focus-out is unverified); the debug
    undo/redo bar is not gated by `GameView._board_is_playable()` (debug builds only); a
    `grant_mark` source printing neither rank nor suit is not `is_marked`; a grid added after the
    draw pile is empty opens unmarked (no shipped path adds one that late); `is_ace` treats a
    fractional rank in [1, 2) as the Ace; `_refresh_mark_matches` is not awaited, so a leniency hook
    that suspends could land its rims after a rebuild (no shipped hook suspends).
- ⬜ **Keep answering `design/effect-review/`** — every question was re-read against the live board
  and the confirmed designs; `build/_verdicts.tsv` has one verdict per question and `build/REVIEW.md`
  says how to change the build without renumbering recorded answers.

- ⚠ **`GAP-042` — a prop scoring a card in the ENTRANCE banks into a dead bucket.**
  `PropScoreProps`/`PropScoreTalents` use the legacy `ScoringSection.of_line` for an Entrance
  card, which leaves `grid == -1`, so `add_line_score` takes the legacy path into
  `scores_row_upper`/`row_total` — neither of which `live_total()` reads. The combo still bumps.
  **LATENT: no shipped content can put a prop on the Entrance row** (props spawn only from a
  scored meld, which is always a grid line), but `row_slot_path` has an explicit Entrance branch
  and the first effect that re-routes a prop there fires it. Three options in
  `design/poker-patience/gaps/GAP-042.md`; it is an owner call about whether the Entrance
  participates in the economy at all.

- ⬜ **Playtest the picture wall** — `HANDOFF_picture_wall.md` S40. Nothing else on that stream can
  be judged until someone drives it; two adversarial reviews traced journeys, neither played it.
- ⬜ **Picture wall: decide what unlocks `book`** — until it exists a whole subsystem is dead code
  ("Picture wall" below).
- ⬜ **Picture wall: rule on wall-view composition** at 16:9 and 32:9 — now judgeable live in
  `Tools/wall_editor.tscn` (F6), not only from snapshots ("Picture wall" below).
- ⬜ **Picture wall: playtest the shell** — navigate, resize, alt-tab, controller, Info. The only
  remaining gate; nothing about how it FEELS has been checked by anything.
- ⬜ **Playtest the universal palette** (below) — the fire and ball colours changed.
- ⬜ **Playtest the shader FX** (FX_SHADER_PLAN §10, 17 steps).
- ⬜ **Delete FX_SHADER_PLAN.md + FX_HANDOFF.md** once that playtest passes. Their residue is
  already folded into ARCHITECTURE_REVIEW §4g/§4h.
- ⬜ **Delete HANDOFF_comparator_buckets.md** once the comparator playtest passes. Its residue is
  already folded into ARCHITECTURE_REVIEW §3c. ⚠ Keep `design/comparator_buckets/` — plan steps and
  code comments cite its question IDs (`Q85`, `Q96`) and its three gap files.
- ⬜ **Spotlight: answer GAP-010 / GAP-011** (overrun banking; emptied-section hooks —
  `design/spotlight/gaps/`), **judge G2.2** (rank-glyph readability), **pick
  `spotlight_separation_mode`**. Phases 1–4 are built; these are what is left.
  - **G2.2 is the owner's alone:** judge on the tool's scenario `S15` or on `reveal_shot`'s
    `user://reveal_shots/02_open_full.png` — the rank glyph must stay legible under the circle.
  - **The separation mode:** `CARD_HEIGHT` (pitch = one card) vs `JUMP_ADJUSTED` (card − separation
    − jump rise); `reveal_shot` captures both.
  - **The GAP-006 per-section pulse is untuned:** at shipped pacing the whole cycle is 1–3 frames.
    Judge it on the tool's `S17` preset with `play` on; the knobs are `spotlight_hold_fraction` and
    the two dim fractions, and `spotlight_dim_target = 0` turns the dim off, keeping every light.
  - **The log-parsing subagent** (owner: *"should only be used for massive logs such as recording an
    entire playthrough from start to lose/win"*); `EventLog.summary()` serves ordinary captures.
- ⬜ **Comparator buckets: a BALANCE call and one UX call.** ⚠ **Not a functionality question —
  the functionality is tested.** PLAN §6's six meld checks run through a real `Game`, stacking
  routes through its own hooks with GATE 8 asserting the isolation both ways, and the five authored
  cards from DESIGN §1e (Turk, Clever Hans, Humbug, Wildcard, plus StampedLoner) are each proven
  expressible. What is left is the two things a test cannot answer:
  - **Balance.** `Tests/Engine/scoring_cost.tscn` now prints the impact: a rank-merging rule
    multiplies a scored LINE by **x2.0 (5 cards) → x3.5 (8) → x6.0 (13) → x5.1 (30)**, and every
    line one placement completes gets it. Extra rank values alone are **x1.0** — they move positions, not
    score. Whether x5 per line is too strong is the same kind of call as everything under
    "Scoring / balance" below, which the sim explicitly cannot make.
  - **One UX judgement, `DEFERRED.md` R2.** A split meld shows three matching cards and counts
    two, with no cue explaining it (Q33=a chose that). That the cue is ABSENT is pinned by tests
    (`test_comparator.gd` §10 asserts the ordinary meld name, no marker); whether its absence reads
    as a scoring bug to a human is not a test's question.
- ⬜ **Sidebar: two measured costs the legal-cell highlight left behind.**
  - **The drop-map sweep is not free, and the number is here so nobody re-measures it.** It runs one
    `on_can_place_stack` dispatch per cell per rebuild (`set_card_zones`, once a frame) while a card
    is held — an empty hand is an empty map with no dispatch — which is the ruling's OWN cost: "the
    highlight follows what `try_place` accepts" means asking the real dispatch rather than a second
    legality rule. Before the empty-hand short-circuit the full suite went **351.6 s → 370.4 s**,
    carried by the board-mutating suites — E2E RUN 27.7→31.5, GRID LAYOUT 17.4→20.9, LEAK CANARY
    10.7→12.6, DRAG PLACE 14.0→15.3. No "skip while processing" narrowing was added: nobody ruled
    one, and it would leave the map stale at the end of a cascade.
  - **The two no-legal-placement loops in `game.gd` lost their early exit** when they were composed
    over `Game.legal_cells_for` (one walk, three readers): each now walks every cell of a grid
    before answering, after every placement and every commit. Measured on Box A: part of the
    placement lag; the narrowing is the first item of § Performance.
  - **Two stick "rest" checks in `test_sidebar.gd` hold `STICK_HELD_FRAMES` (10 frames, ~15 ms at
    Box B's ~660 fps)**, so they prove rest over a frame-rate-dependent span. A time span costs
    ~2 s per suite run; the owner's call.
  - **The placeholder-warning headroom is one.** The gate allows at most 22 and the run now emits
    21: the legal-cell knob became a `float` brightening and stopped being a colour at all, so the
    slot it held came back. The next two items to add an off-palette colour breach the gate.
- ⬜ **Sidebar: owner should see** — built as ruled or pre-existing; each is a look call:
  - The outcome's Continue and Undo sit under the spotlight layer's dim: text peaks at (73,71,80) over (12,10,22) in `outcome_buttons.png`. Whether the outcome row should be lit is a look call.
  - In the 600×1000 top case the stock row's top overlaps the grid's bottom row by about 10 px (`game_hud_top.png`).
  - A second click on the same cell inside the double-click window closes a pair, so a rapid same-cell stack is swallowed. Should stacking cost a wait?
  - The map's name popup keeps its name after the pointer leaves the dot, and is not clamped at the picture's top edge, where the name clips off.
  - A resume after "undo the automatic end, then quit" lands on the outcome again.
  - Opening any viewer hides the HUD stack, so a mouse player cannot swap Deck → Discard without closing first.
  - `Q102b`, `Q102c` and `Q106b` in `design/sidebar/` are unanswered; their branches were skipped.
  - Back mid-show, then travel: the new node is consumed with no show, and the frozen old show banks its win against it (pre-existing).
  - Preview-card FX art below the description's fold escapes its scroll clip while the card frames are clipped (pre-existing).
  - WALL FOCUS, WALL RENDER and WALL INPUT still run their Main fixtures unpaused, because they run beside the ordering chain.
  - The name column is narrow: about 170 px of title column before the way back, about 100 px with it up, because the way back takes the head of the same row. Shot: `map_preview_card.png`.
  - At a 1280×1000 window the HUD runs about 30 px past the bottom of its top band at the shipped `container_size_fraction`; the band is shorter than the HUD. Under a 0.1 fraction the exit X hangs below the band. The knob's range is a look call.
  - The exit X overlaps the top of the description's scrollbar (pre-existing).
  - The overlay buttons grow to the touch target when the window grows, but never shrink when it shrinks.
  - A resize pans the board to its new resting x over several frames while the Entrance moves at once, so the two are briefly out of line: measured mid-pan, 31 px at 1280x800 and 65 px at 600x1000, converging to within 1 px once the board stops. Whether the pan should be instant on a resize is a look call.
  - In the top case the map picture sits off-centre below the band, cut at its edge.
  - The start menu's title and buttons are squashed horizontally in the top case; whether the sidebar causes it is unmeasured.
  - In the top case an Entrance card draws over the deck viewer's panel; the deck picker's list text draws over the Inspect viewer's panel (pre-existing).
  - Mid-cascade, a stack of cards in column 0 draws above the picture's top edge.
  - No focus highlight is visible on the focused card inside a viewer.
  - In the 9.4 still, the focused empty grid cell is indistinguishable from the other 24 — every empty cell wears the same animated dashed border, so there is no way in the image to see where a pad player's selector is.
  - An intermittent engine crash in teardown (0xC0000005) after a passing banner makes `run_tests.py` exit 3; seen twice, unattributed.

Everything below is unscheduled backlog.

## Visual effects

**Anything fire, juggling, prop art or FX shaders starts at [VFX.md](VFX.md) §6/§7**, which carries
that whole backlog and its known bugs. Keeping the list here as well is exactly the two-places
drift this repo's doc hygiene forbids.

- ⬜ **Spotlight vs the embedded window's stretch-to-fit** (owner, from playtest): circles land and
  size as if the window were unscaled. VFX.md §7 item 14 carries it.

The current fire emitter is the **NOISE FIRE** (owner design): no tendrils, no comb, no ogee, no
onion shells. Fire is a cover field sampled from the art's own mask and carved by scrolling noise,
and every parameter ramps continuously with the stack count. Contract: ARCHITECTURE_REVIEW §4g;
the full record, including what only the owner can decide, is FX_HANDOFF §0.

- ⬜ **The two remaining FX tasks are FX_HANDOFF §0c/§0d** — the owner's words: *"our last tasks
  will be making fire vfx show behind the art and saving juggling performance"*. ⚠ Read §0c first:
  `inner_alpha` and `z_index` are NOT ruled out — the first attempt failed on a QUANTIZATION
  detail, and the one-line experiment to try before any layering change is named there. For the
  second, re-run the two levers whose blocker an unrelated fix removed. §0e explains `cover_taps`.
- **The three fire `.tres` were MIGRATED, not TUNED.** Only `noise_scale` was re-derived, because
  the retired build's value was ~6x too fine for a model where the noise IS the shape. **The art
  pass is the owner's and it is the biggest thing waiting.**
- **Fire still licks down a card's top corners.** The chamfer is in the RADII mask, not the flame
  model, so any correct model stands fire on it. FX_HANDOFF §8.

## Architecture / engine

- D6 command-log undo — the real fix for per-action deep-copy cost (E5); eliminates reference
  remapping entirely. Big.
- Board §5 step (5): delete the `move_data_to_coord` / `move_data_ontop_data` Vector3i adapters
  when convenient.
- D1 real mod-hook contract (single HOOKS list / signature checking) · D2 route ALL mod state
  mutation through Game/Board (some mods still write arrays directly) · D4 kill the
  `CardEnvironment.CURRENT` static reach-through (pass the environment/context instead).
- D8–D11 cosmetics: comparator speculative abstractions, editor-tool code out of `card_visual.gd`,
  unify the zone pair into one structure, Scoring section-banner rewrite.
- S3 same-column move edge cases (unit-test the remaining matrix), S4 `PlayArea.separation`
  int/float, S7 verify every ModsList consumer duplicates.

## Scoring / balance (playtest phase — the sim cannot answer these)

- Playtest per the SCORING_MATH_PLAN §10 protocol (git history): paired seeds, record sheets,
  acceptance bands. Open knobs: `difficulty` default, `combo_step` 0.1 vs 0.2,
  arrangement-capacity reality, mod-activation U generosity, Burning cascades as a combo source,
  δ fallback trigger, `score_additive` A/B (needs a goal_g0/alpha retune).
- Balance of the live `on_score` / `on_after_score` broadcasts — never balance-tested.
- Sim/doc fit drift: `--final --q 0.35` prints g0≈140/α≈2.03 while shipped constants are G0=130 /
  ALPHA=4.2. The owner is not worried (tunables cover it); arbitrate before recalibrating.
- Rarity tiers (luck currently only gates non-null stamp/skill/type rolls).

## Scoring — LIVE defects, found by the poker-patience close, none fixed

⚠ **ALL FOUR ARE SCORE LOSS OR SCORE SHORTFALL IN SHIPPED CONTENT, AND A GREEN SUITE DOES NOT SEE
ANY OF THEM.** `live_total() = board_total() * combo_mult()`, and `board_total()` sums `grid_score(i)`
over `state.grids`, reading ONLY `scores_row`, `scores_col`, `scores_cell` and `score_special`.
**Anything reaching `scores_row_upper`, `scores_row_lower`, `scores_col_legacy`, `row_total`,
`col_total` or `mult_score` is lost.** Grep those six names before adding any scoring path.

- ⬜ **No effect activation feeds the combo on a placement** — the grid game's only scoring action —
  contradicting `DESIGN.md` D11 (`Q323`=b). `game.gd:231` gates `register_combo` on
  `_act_cancellable`, written only inside `_perform_next`. See `gaps/GAP-043.md`: the design is
  ANSWERED (combo never resets, unbounded by design); what remains is which condition replaces it.
  **Not a bare delete** (setup would register) and **not `processing`** (that is the input lock —
  overloading it repeats the mistake that caused this). An explicit act-open flag set in
  `_begin_act()` is the honest fix; finding the clear sites is the work.
- ⬜ **`SkillExtraPoint` awards nothing, in 19 deck slots.** Description reads *"Gain 1 Extra Point
  Per Score"*; `add_points()` has no caller, its only call site commented out one line above. Even
  rewired it disagrees with the card (`add_total_score(10)`), and `total_score` has no other live
  writer. Pre-existing — dead on `main` before the branch too. `skill_hungry_hippo.eat_card()` is the
  same shape; between them they are the only consumers of `CardEffectApi.add_total_score`.
- ⬜ **`GameData.apply_act_score()` is dead production code its own tests keep alive.** Zero
  production callers; every caller is a test (`test_act_score.gd` ×7, `test_combo.gd` ×4,
  `test_game_headless.gd` ×1, whose comment already says *"there is no button that"* fires it).
  Deleting it removes a suite and part of another, so it is an owner call, not a cleanup.
  ⚠ The three `row_total`/`col_total` checks in `test_game_headless.gd` are DIFFERENT and should
  stay — they cover `add_line_score`'s legacy branch, which is still reachable and still defective.

## Scoring engine test gaps

- ⚠ **SE4 IS NOT A TEST GAP AND SHOULD NOT SIT UNDER THIS HEADING.** "single-walk `_scan_wrap`" is a
  micro-OPTIMISATION of `Scripts/scoring.gd`: the scan restarts its walk from every rank
  (`for start in range(A, W + 1)`), where one pass could find the longest wrap-around run. Nothing
  about coverage. ⚠ **A benchmark now EXISTS** (`Tests/Engine/scoring_cost.tscn`, DEFERRED E1), so
  this is measurable rather than speculative — but measure before optimising: the wrap scan is one
  term inside a call that costs 9.1 ms on 30 cards, and E3 (the repeated profile rebuild) and E6
  (the ~2x identity-path regression) are both larger.
- ⬜ **`LINE DETECT` cannot see the defect class this repo has hit four times.**
  `Tests/Engine/test_line_detect.gd` (1201 lines) asserts through a `RecordingGame` that captures the
  `amount` ARGUMENT to `add_line_score`. Verified: the file contains ZERO references to `live_total`,
  `board_total`, `grid_score`, `scores_row`, `scores_col`, `scores_cell` or `section.grid`. Every
  assertion is taken BEFORE `add_line_score` branches on `section.grid`, so a regression routing
  every grid section to the legacy bucket leaves the whole suite green while the score goes to zero.
  ⚠ The comments justifying this (*"which bucket a section banks into is a later step"*) are STALE.
  **Fix: one check on the DESTINATION per scoring test**, not on the argument.
- ⬜ **`combo_repeat_step` has ZERO references in the entire `Tests/` tree** — a shipped knob
  defaulting to 0.5 that multiplies the player's score. That is `TP-58`. `TP-59` (D11) has neither
  an implementation nor a test.
- ⬜ **`COMBO` leaks a `Game` and leaves the global pointing at it.** `test_combo.gd`'s
  `test_register_combo` does `Game.new()` + `CardEnvironment.CURRENT = g` and never frees or nulls —
  the file has ZERO `free()` and ZERO `CURRENT = null` — and it is the LAST test in the suite.
  `Game extends Node`, so that is a leaked Node plus global state left for whatever runs next.
- ⬜ **Two more production functions whose only callers are tests**: `GameData.discard_lower_board()`,
  and `Game.move_card_in_grid` / `remove_card_from_grid` — the latter pair unreachable from shipped
  content (no `CardEffectApi` wrapper, and the modifier boundary gate forbids naming `Game.`), yet
  three test-plan rows drive them.
- ⬜ **Only `Tests/Engine/` has ever had a test-quality review**, and eleven files in it got only a
  mechanical sweep. `Tests/UI`, `Interaction`, `Wall`, `Visual`, `Map`, `E2E` and `Support` have had
  none. The checklist is `.claude/memory/tests-that-prove-nothing.md`.
- ⬜ SD5 test-file section renumbering — cosmetic only, and `test_scoring.gd`'s own header already
  says the section numbers are historical and `_ready` order is the real one. Churn on a 1200-line
  file for no behavioural gain; left deliberately.

### ⬜ Comparator buckets — **phases 1–8 landed and verified; a playtest is what remains**

How the surface works and every landmine in it: **ARCHITECTURE_REVIEW §3c**. Behaviour authority:
[design/comparator_buckets/DESIGN.md](design/comparator_buckets/DESIGN.md); contracts and build
order: its [PLAN.md](design/comparator_buckets/PLAN.md); per-step evidence:
[HANDOFF_comparator_buckets.md](HANDOFF_comparator_buckets.md). Everything scoped OUT — with the
cards blocked on each and the seam it would land at — is
[DEFERRED.md](design/comparator_buckets/DEFERRED.md); add to that list rather than re-deriving it.

⚠ **Latent in shipped content, which is not the same as untested.** No authored card implements a
meld hook, so the identity path runs and scoring is unchanged until content asks otherwise —
while `test_game_headless.gd` drives PLAN §6's six checks through a real `Game`'s `submit()`.

**Open:**

- ⚠ **OWNER CALL — the identity path costs ~2x what it did before this work** (`DEFERRED.md` E6,
  numbers in PERFORMANCE.md §4d). No shipped card implements a meld hook, so **every real game
  today takes the path that got slower**: 30 cards with no rules went **5.01 ms → 9.15 ms** per
  scored line, 1.9–2.7x at every smaller size, measured current-tree vs a `HEAD~1` worktree in one
  session on one box, two runs each. C4's safety claim was verified byte-identical in RESULTS and
  never in COST — this is that gap closed, and it is a decision, not a bug: accept the 2x, or open
  a perf phase. Not diagnosed; E6 lists the suspects in the order worth measuring, and the extra
  classification profile per handler (ASSUMPTIONS S14) is first.

- ⬜ **DEFERRED E3 is now the biggest lever in the scoring path, and it is sized.** `Tests/Engine/scoring_cost.tscn`
  (E1, written): a scored line costs 9.5 ms on 30 cards unmodded, 16.2 ms with a rank-merging rule,
  31.9 ms with merging plus extra rank values. ⚠ `Game.score_line` runs per row AND column and
  `skill_eval_poker_best` scores both again from inside scoring, so a wide board with a merging
  rules card is HUNDREDS of ms for a placement that completes several lines at once. Numbers in PERFORMANCE.md §4d. Q57(a) scoped E3 out —
  reopening it is an owner call, but it is no longer an argument from arithmetic.
- ⬜ **Three fuzz invariants remain scoped rather than absolute** (3's held-cards set, 8's position
  model, 1's declared multi-key exception). Each is documented with why; each is also a place a real
  defect could hide. Invariant 9 is unrestricted again now that the generator's random predicate is
  a pure function.
- ⬜ **The fuzz's carrier axis is still not a full cross-product.** `stamp` / `status` / `skill` are
  typed to their own `CardModifier` subclasses, so one shim cannot hang in every slot; the generator
  rides on the type slot. The mounts that behave DIFFERENTLY are covered explicitly (all four for a
  pair rule, plus a skill carrying a whole-hand rule, which has its own dispatch and spotlit gate),
  so what is missing is combinations, not code paths.

## Props / UI (owner has NOT re-verified)

- ⬜ **Props read the pre-grid axes** (owner, from playtest): fire and juggle spawn against the old
  column-as-stack shape and do nothing; the grid column is the new axis and the old column is now
  height. VFX.md §7 item 15 carries it.
- ⬜ **A prop's back and front halves split around the wrong cards** (owner, from playtest): the
  hoop's halves sort against other rows and the same row instead of hugging their own card as one
  unit. VFX.md §7 item 16 carries it.

- Description-panel scroll-lock, knife row behavior, hoop visibility, ballistic poof,
  undo-across-a-placement feel, held-loop spin, formation system + editor end-to-end (no formation
  `.tres` authored yet).
- Firework in-run acquisition beyond deck12 (owner decision). Per-pip tooltip granularity.
- Win/lose screen font (226px) clips long "Fame +N" text. `game.tscn` grabs no initial focus, so
  keyboard/controller players must click first.
- A sprung grid card (`CardVisual.anim_spring_lift`) never resets `floating`, so it stays false
  until the next rebuild.

## Universal palette (owner playtest pending)

Contract: ARCHITECTURE_REVIEW §4i. Open follow-ups, all deferred by the owner rather than missed:

- **Map screen and in-game UI chrome are still hardcoded**, pending the owner's custom art
  (`world_map_controller.gd`, `map_player_token.gd`, `game_view.tscn`, `choice_viewer`,
  `deck_picker`, `deck_viewer`, `deck_builder`, `text_popup`). The PALETTE suite lists each as
  `[WARN][PLACEHOLDER]` every run — that list IS this task. When the art lands: add a role per surface, assign it in code at `_ready()`, never
  re-bake a literal into a `.tscn`.
- **`FireworkVisual` has no art** — its placeholder magenta polygon is the last non-deferred
  literal. The `suit_firework` role already exists for whenever that art is drawn.
- **The fire ramp's ENDS are an art call the owner has not made.** `ramp_fire` runs
  `[0, 20, 1, 2, 16, 30, 6, 3, 31, 19]`; entry 0 makes a 1-stack flame nearly black and entry 19
  puts a neutral grey at the white-hot end. Both are honest nearest-palette choices and both are
  one-line edits to `Assets/Palette/ramp_fire.tres`.
- **`suit_pips.png` has a few off-palette pixels** (e.g. `#ec0037`, 27 from entry 2). Authored art,
  not a plumbing bug; `tools/palette_conformance.py` finds them.

## Booster rerolls (owner playtest pending)

Full behavior and the settings list: ARCHITECTURE_REVIEW §4f.

- Pool ships at 5 (`booster_reroll_pool`); reroll-count modifiers (the `luck()`-style content hook)
  are not written yet.

⚠ **PATIENCE IS RETIRED AND ITS BACKLOG IS GONE WITH IT.** The whole family went with the tableau
(`design/poker-patience/PLAN.md` §1.6): no `patience_max`, no `patience_influence_*`, no
`patience_disabled_hooks`, no `patience_max_increased`, no `state.patience`. `test_grid_economy.gd`'s
TP-60 grep gate asserts zero readers of every one of those spellings in any `.gd` or `.tscn`, so
they cannot come back by accident. The open questions that used to live here — what counts as an
"interesting move", which comparator hooks should feed it — died with the mechanic; do not revive
them from git history without an owner ruling that patience is back.

## Card size + outline — landed, one thing open

Card is `CardVisual.CARD_SIZE`; every element wears `Shaders/outline.gdshader`'s rim. Rules and landmines:
**ARCHITECTURE_REVIEW §4j**. Design record: `design/card_size_outline/`. Tuning:
`Shaders/Styles/outline_default.tres`, edited live on `tools/outline_atlas.tscn`.

- ⚠ **ART, owner's call — the rim MERGES the dense `suit_art` frames.** The highest-rank frames
  pack nine+ pips into 32x32 and invert into a dark lattice. The fix is art-side (space by 3) or
  scope-side (exempt the 32x32 art). Nothing in code is wrong.
- **Q6a / the alert's LOOK is unjudged.** GLARE and THROB are tunable live on the atlas; whether a
  card-space glare reads on an 8x8 pip (lit ~25 % of the sweep) is the owner's eye. The escape
  hatch is a per-host thickness scale.
- **FX numbers are stale by ~12 % of fill.** FX_HANDOFF.md carries a banner; re-run `fx_cost.gd`
  before spending that budget.

## Design work not started (DESIGN_DOC pointers)

- Entrance drop-down between acts (DESIGN_DOC §2) — decide and implement.
- Tips / hype-wagering / fog of war / tour planning (§15); circus renames (§9); shop & economy
  (§16); meta progression (§19); leaders/acts (§11). Deterministic RNG streams (§6/§23) are
  planned above.

## Performance — lag moving and putting down cards

Measured on Box A (debug, windowed; harness `Tests/Visual/placement_lag_probe.tscn`, `GRIDS=3
PLACEMENTS=10`). The legality walk now reads the cached implementer list: a `Game.legal_cells_for`
walk costs 3.1 ms at pickup and 4.3 ms at commit (it was 14.8 / 17.8), and the worst commit frame's
median is 61 ms (it was 76). About 2.6 walks run in a commit, so roughly 50 ms of that frame is
NOT the walk and is unprofiled. NOT the save thread
(main-thread wait 0.001 ms max) and NOT history length; GPU <= 13.5 ms. Re-measure with the probe
before and after each fix, same session, same box. Three fixes are sized and not built (owner:
"leave remaining profiling after 92 as todo"):

- ⬜ **The existence checks stop at the first legal cell.** `Game._no_legal_placement_remains_in_grid`
  and its callers `_lift_a_spent_commitment` and `_no_held_card_has_a_legal_placement` only test
  `is_empty()` but run the whole `legal_cells_for` walk. An early-exit parameter on
  `legal_cells_for` (the one walk), no second walk. To measure: `_lift_a_spent_commitment` walks
  and discards on a one-grid board; the refill check walks grids a commitment refuses
  (`PlayArea._sweep_legal_cells` already narrows to the committed grid).
- ⬜ **The release frame rebuilds while the card is still held.** `PlayArea.ungrab_cards` rebuilds
  before it clears `selected_cards`, so the rebuild lays out the held look (`_bind_slot`,
  `_append_ordered_visual`, `_refresh_mark_matches`, `_sweep_legal_cells`) that the ungrab then
  undoes. New order: the visual reset loop (it reads `selected_cards`) -> `selected_cards = []` ->
  `flush_rebuild()`. `hand_changed` then fires before the rebuild; its one listener
  `HudContainer.set_card_in_hand` reads no board maps. A Fable check of two earlier drafts found
  one would refuse every placement and one would leave the card lifted - measure, do not reorder
  by reading.
- ⬜ **`Game.save_state`'s second, debug-only snapshot** (4-9 ms a commit in debug builds).
  `_debug_commit` takes a fresh `to_saveable()`; append `save_history.back()` instead - entries are
  immutable by contract (`run_manager.gd`), every reader duplicates before use, and `_resume_show`
  already shares them. Update the two "FRESH to_saveable() duplicate" comments
  (`test_leak_canary.gd`, `leak_holder_probe.gd`). It also halves the modifier-epoch bumps a commit
  makes (the snapshot's copies run the setters; 858 per placement with both snapshots).

## Testing / infrastructure

- ⬜ **Three small leftovers of the playtest-fixes close.** `solatro/tools/run_tests.py` falls back to
  `~/.local/share` on Linux when `XDG_DATA_HOME` is unset - the un-private user:// the private-user
  rule refuses; read `os.environ["XDG_DATA_HOME"]` as the Windows branch reads `APPDATA`. Two comments
  still name `Tools/run_tests.py` (`Cards/Props/prop_visual.gd`, `Tests/Visual/wall_transition_fuzz_soak.gd`;
  each edit pulls a whole-file comment sweep), and `Tools/snapshot_diff.py` names a deleted handoff.

### Rule-audit tally (the `/handoff` Reflect step 3 - add one line per session)
- TOOLING, rule audit - session of P83-P91 (2026-09-30): CAUGHT - measure-first stops (the spotlight's dropped zoom, P87's stamps and missing cream role, P88's split, P90's overflow table, the lag's real shares - the save thread was innocent); Fable checks of mechanism questions (the lag fix: two drafted options would have refused every placement / left the card lifted; P90: the no-re-layout option); Fable per-step reviews (P85's frame row blind to a hidden bar; P87's callerless guard; P90's vacuous layout row); the full gate (P85's four SIDEBAR reds a one-suite filter hid); the mutant rule (P86's overlap check never red); the owner's eye (round 4 re-asked approved shots with stale 'pre-square' seens; the spotlight too small). Reviewer latent findings REPRODUCED 2 (P85's right-edge check via a 28-vs-8 mutant; P90's empty-list pass via a mutant), REFUTED 0. FALSE ALARM - two gate reds from a shared box (TP-85; UI PROPS + GRID VIEW TP-105), each ~30 min; doc_check --changed counted another agent's in-progress files. COST - ~16 gates plus 2 reruns, four of them for test/doc-only review follow-ups - propose: such a follow-up rides the next step's gate; the gate verdict + leak-scan one-liner typed ~14 times - propose: gate.py prints the leak-line scan itself; the mark-row-done-with-hash script typed ~8 times and a PIL tiling snippet ~10 times - propose: two small tools under .claude/tools (mark a handoff row done with its commit; tile shots before/after), each its own small reviewed step; the watch never woke (Done not pressed) - a verdict told in chat is a handback (RULINGS), the overseer reads review.json. CEREMONY - the ~300-line handoff rule (this file ~600 lines, the Open bugs list the bulk) - propose: the intermittent ledger in its own file the handoff points at, as the rulings did.
- TOOLING, rule audit - session of P73-P82: CAUGHT - Fable per-step reviews (P64b-3b: a frozen show's lost focus, Play focused behind the picker's viewer, a resolved show's Continue lost - all reproduced; P64b-3f: a SCRIPT ERROR on Left in the menu's viewer and a swallowed Left - reproduced; P77: a focusable embedded Window taking the root's input; group passes: a stale Continue, stale docs); reviewer latent findings REPRODUCED 5, REFUTED 3 (P64b-4's lost-run Continue, P64b-3e's missing writer, P78 b's 'viewers move'); mechanism-question checks (Tab: a missing option; the overfill: the real callers); measure-first stops (the Tab premise, P71's design, the overfill and the menu's premise, P80's race, P77's root scale 1, P66's hang = a minimized window); the gate (the _deal_next_mark third count -> P80). FALSE ALARM - commit-gate.ps1 blocked ~15 test_sidebar commits on two duplicate pairs already on HEAD (each needed [dup-ok]) and reads [dup-ok] only from the command text, not a -F message file; the auto-mode classifier refused a handoff commit after that workaround (the owner said continue). COST - two implementers ran gate.py themselves (~15 min each): the implementer definitions say 'Run the full suite before reporting done' while /plan-run and this handoff say only the overseer runs the full gate - propose rewording it to the brief's filter; an implementer's mutant chain outlived its report with a pending copy-back over menu.gd (rule added to the implementer definitions); classifier no-verdict outages (5 in a row stopped a turn); a double-backgrounded gate lost its notification; a handoff script whose assertion failed was followed by a ';' commit (chain the commit with &&). CEREMONY - the ~300-line handoff rule (~730 lines) - propose again: give the rulings block its own file. The owner approved all four proposals ("yes make the fixes"): the implementer definitions' full-suite line and the rulings file (71f3216d); the context-threshold hook .claude/hooks/context-handoff-nudge.py (main-thread Stop, once per session; fired live at 83% of the window; then an absolute token count: the evidence pointed at 200k (the Opus 5 system card's long-horizon eval compacts at 200k; this session's measured main-thread cost was lowest closing at 200-250k, ~$54 vs $79 unclosed) and the owner chose "lets go with 500k." - fewer restarts for some extra cost); the commit-gate fix: only pairs the staged diff creates block, and [dup-ok] is read from -F files too (dup_check --staged --new-only).
- TOOLING, rule audit - session of P75-P58e-3, P76: CAUGHT - the Fable broad group pass (p73-wip's wholesale restore would have reverted four steps - critical), Fable per-step reviews (the zero POLY headroom, the resample skip, one-call helpers), measure-first stops (6: the Shader Global premise, the corner model, the board-centre cap, the wall-view cost, the SubViewport focus, TP-92's cause), the full gate (the OS-window resize, the merge's 48% slowdown via a timeout), the OUTLINE saved-ShaderMaterial guard (main's editor re-save), the mutant rule on every new row. FALSE ALARM - godot-needs-private-appdata.ps1 blocked a python edit whose TEXT named 'Godot editor' (again - match a launch, not a substring); block-process-kill.ps1 blocked an explicit-PID foreach (one explicit Stop-Process per PID passed); one reviewer finding refuted by measurement (P58b-7's scrollbar double count). COST - the full gate per step (~15 min, ~22 gates; kept); a permission-classifier outage blocked an implementer's writes (8 failures, retried); the classifier refused ending orphaned Design Loop watch processes (left to the owner); ~18 hand-typed handoff-edit scripts and a per-suite diff script typed per gate - propose: gate.py compares per-suite counts with the PREVIOUS completed gate (today it compared a stale one: OUTLINE 43 -> 51 across two gates that were both 51), which retires the per-suite script. CEREMONY - the ~300-line handoff rule (672 lines; the verbatim rulings ~190) - propose again: count the rulings block out, or give the rulings their own file the handoff points at.
- TOOLING, rule audit (the /handoff Reflect step 3 tally; add to it each session). Session of P64b-P74: CAUGHT - Fable per-diff reviews (a real defect in most: the deck back empty, the menu click-outside strip, an undeleted helper, focus behind an opaque viewer), measure-first stops (6 premises overturned into owner questions), one Godot at a time, mutant red (4 rows proven on a restructured scene). FALSE ALARM - godot-needs-private-appdata.ps1 blocked 2 commands that only MENTIONED run_tests.py (a handoff edit, a docs heredoc): propose matching a launch, not a substring. COST - the full gate per step (~13-14 min, ~25 gates) - kept, it caught TP-63/GRID VIEW/P73 reds a filter missed. CEREMONY - the handoff's ~300-line rule (620 lines; the verbatim rulings block alone is ~160) - propose re-measuring the limit or giving the rulings their own section the count excludes; red-then-green satisfied while two rows still compared a value with itself (P65b, P73) - the mutant rule now covers it.
- TOOLING, rule audit - session of P91's follow-up to P96 (2026-10-01): CAUGHT - the shadow comparison a brief asked for (P92: 28 differences in 15731, a cache stale where the scan was fresh - the earlier Fable check of the options had passed it); the Fable check of the stop (not an owner question; it traced the juggling miss, REPRODUCED red - reviewer latent findings reproduced 1, refuted 0); measure-first stops (fx_cost hosts no card; P92; P96's premise - a harness artefact, not a product bug); the visual-review README's reachable-state rule (the game spotlight restaged on a really scored row). FALSE ALARM - an implementer's 'product bug' (a Deck click closing a scrolled list) was its own press-only wheel: one medium round to refute. COST - a new session's scratchpad holds no last-gate state, so the first gate prints no per-suite diff - propose: gate.py keeps its last-gate state in one untracked place that outlives a session; the whole-file comment sweep on touch added 133 + 40 comment-only findings' worth of lines to two one-line fixes (sweep_check proved them, but the diffs are noise) - propose: a file over ~50 legacy findings is swept in its own step, as the close already does for game.gd; Sidebar alone (~770 s) exceeds an implementer's 10-minute foreground cap, so every Sidebar filter is a background wait and a 'stopped with background work' notice - known, kept; the handoff-edit script typed 8 times and the leak-line scan 4 - the two tools proposed last session are still unbuilt. CEREMONY - none new. ROUTING, from the implementers' own lines: P91's follow-up items and P96's round 2 'could go lower' (a named inline, a named scene property); P92's first round 'needs medium' on its stop. Recorded this session: tests-that-prove-nothing item 11 (a wheel notch is press AND release), brief-premise-is-a-hypothesis (a speed-only rewrite gets a shadow comparison).
- TOOLING, rule audit - the close (Linux cloud session): CAUGHT - the close's reviewers: reproduced A1, B3, B4, C4, F1, F2, R1, T1-T3, T5, U1, U3, U4, U6, T7 (a real product bug, T7b), the A4b chooser half, S3, and /simplify's V1 V3 V5 V6 S1 S2 V7; REFUTED on measurement - A1's null lock, T4, T6, U5, the A4b deck half, R3; owner left as built - A6, F3; traced-only refutations never measured - A2 A3 A4 A5 B1 B2 B5 C1 C2 C3. The intermittent budget (TP-63 at 2 of 3, fixed eba6c12). doc_check --changed caught two dead references after a deletion. sweep_check proved the sweep. COST - every repo hook is PowerShell or `py`, so none fired on Linux (owner: "c: Cloud is rare" - note only); the environment's git Stop hook flagged implementer work in progress about ten times. CEREMONY/ERROR - the overseer's briefs told implementers to commit, against /plan-run's "the overseer COMMITS"; every report flagged it. NEW TRAPS, written where read: a background agent dies with an interrupt and no notice (/plan-run Interruptions); a filter naming no suite ran 0 checks GREEN (now RED, 6e6273e; memory #15); a one-frame settle under physics motion (memory #16).

- E2E first-card fly-in in the pack preview: confirm fixed on a real run.
- Cloud sessions (optional): run `.claude/tools/cloud_setup.sh` from a SessionStart hook
  (`session-start-hook` skill) instead of by hand.
- Cloud: confirm the newest Godot release (the proxy blocked the API); the project pins 4.7.2.
- `PipSuitTest.id` is a plain `var`, so `duplicate_deep` and a save do not carry it: a row of
  distinct test suits comes back from a snapshot as ONE suit and flushes. A fixture that must
  survive a copy uses real suits.
- Background-save robustness at scale unverified (large history serialize on a worker thread) —
  watch the console; the history cap bounds it.
- **PIXELS `test_the_card_mask_is_the_card_the_player_sees` WAS GREEN but PINNED, not fixed.** While
  the idle rig animation is off the check runs the REST POSE ONLY and asserts exact agreement; the
  band below is what returns if the idle is re-enabled (`test_pixels.gd` says how). The
  check no longer demands exact cell agreement — that bar was unachievable and passed at rest by
  alignment. It asserts a band around the outline: **edges ≤ 1.7 FX cells** (the fraction is the
  32-slot wedge index, whose quantization is angular; measured worst 1.50) and **corner bite ≤ 2.6
  cells** (measured worst 2.45 at t=0.30). Both bounds are in CELL units so one `pixel` knob moves
  them together. The **COUNT** is asserted too — rest pose exact (0/0), deformed poses ≤ 130
  disagreeing cells (measured worst 104) — because the distance bars alone cannot see a shallow
  uniform boundary shift. ⚠ **All numbers are measured and deliberately tight so any worsening
  fails — do not raise them to go green.**

  Underneath it are **two independent model approximations**, diagnosed and NOT fixed; the fix is a
  model choice, so it is the owner's. The `[mask vs face WHERE]` line in `test_pixels.gd` buckets
  every disagreeing cell: corner cells 22/62/60 and edge cells 36/42/0 at the three deformed poses.
  - **CORNER class — `CardVisual.corner_points()`.** It puts the bite's middle point at
    `corner + along_prev + along_next`, assuming the corner cell stays a **parallelogram**. It is
    really a bilinear patch whose fourth point (the internal vertex, e.g. `(-14.25,-18.75)`) is
    skinned independently. Exact while the cell is a rectangle — which is why t=0.00 passes — and
    drifting as it shears. ⚠ **The function's own comment claims it is "exact under deformation";
    that claim is false**, and this is the measurement that shows it.
  - **EDGE class — the radial wedge mask.** `WEDGES = 32` (11.25° per slot) indexes which polygon
    segment a fragment is tested against, with only `WEDGE_CANDIDATES` consecutive slots tried.
    Deformation spreads the 24 vertices unevenly in angle, so a slot can span more segments than
    the window covers and points near a slot boundary test against the wrong segment.
  - **Options.** (1) Exact corner: re-do the skinning in GDScript from `Polygon2D.bones` weights
    for the 4 corner diagonals only — per-frame per-card code the comments already guard for cost.
    (2) Widen the candidate window, or drop the radial mask for a non-radial one. (3) Give the
    check a stated tolerance instead of demanding exactly 0.
  - **Already ruled out, do not re-open:** the baked `Offset/Visual` pose; the animation driving it
    (it does not — only bone `:position` tracks exist); bilinear filtering (a real harness bug,
    fixed, but t=0.30's 887 undecidable cells did not move); "tips vs skinning blend" (bone rests
    equal their vertices exactly and each vertex is ~0.99997 weighted to its own arm).
- **G2.3 / spotlight cost** (`fx_cost.gd::_spotlight_rows`). Over a 1.947 ms empty-scene floor:
  0 lights +0.478, 1 +0.607, 8 +1.537, 24 +4.666, 64 (MAX_LIGHTS) +12.237 ms. **≈0.19 ms per light,
  near-linear**, swept over LIGHT COUNT because `light.gdshader` shades the whole viewport
  regardless of host count. A realistic section (5–12 lights) is ~1–2.5 ms; 64 would blow a
  16.67 ms frame alone. `Q254`=(a): reported, nothing trimmed — the cut is the owner's call.
  ⚠ The GLOW is still unpriced: there is no `FxGlow` effect class, only the shader.

## Picture wall

See [PICTURE_WALL.md](PICTURE_WALL.md) for how it is put together and what will bite you, and
[HANDOFF_picture_wall.md](HANDOFF_picture_wall.md) for where the stream stands.

- ⬜ **Camera/view findings — PARKED BY THE OWNER as todo, and NONE of them is verified.**
  ⚠ **The suite structurally cannot see any of these**: the layout suites are pinned to the OVERVIEW,
  and no `Tests/Visual/` harness drives props at all, so nothing renders a prop over a card at a
  non-1.0 `board_zoom`. **Building that harness is the first task, not the fix.**
  - `wall_picture.gd:235` — `focus()` used to force `size_2d_override = Vector2i.ZERO`; the
    replacement engages a non-identity override on a FOCUSED picture whenever the render clamp
    bites, displacing every click inside the show.
  - Four zoom-awareness sites, all correct at zoom 1.0 and claimed wrong in FOCUSED mode:
    `play_area.gd:1399` `_card_control_at`, `play_area.gd:2919` `_position_focus_info`,
    `prop_layer.gd:193` `_body_over_any_card`, `card_visual.gd:696`'s held-card grab offset.
    ⚠ `/fx-verify` MEASURED the hoop's jump alignment and it is scale-aware and correct
    (jumped-card centre == ring centre exactly at `card_scale` 2.5 and 4.0, rest offset exactly
    proportional), so `card_scale` is NOT the axis in question — `board_zoom` is.
- ⬜ **`anim_spring_lift` / `anim_jump` descent mismatch** — confirmed by reading the tween chains,
  unverified by render. `anim_jump` tweens `offset.position:y` to `-CARD_JUMP_RISE` and NEVER
  returns it (only the SCALE pulses back); the card comes down separately via `anim_reset()` when
  the prop's HOLD ends. `anim_spring_lift` rises, holds, then returns y to 0 itself. **So the riders
  descend while the jumped card is still held up** — `Q310`=a (*"as if jumping card has all above
  cards on its shoulder"*) holds for the lift and breaks for the rest of the hold, and
  `_update_reactions` re-lifts the riders per arriving prop while the jumped card just stays up.
  ⚠ The function's own doc comment claims the opposite (*"then down together"*, *"as ONE RIGID
  BODY"*). It has a DURATION, so a still frame cannot settle it — run it and report what MOVED.
- **The Entrance renders through the LEGACY zone renderer, and switching it is the last piece.** Banking, the zone shape and the
  HEIGHT labels are all landed; what is left is its ROW label and multi-row cells, and both come
  free once it binds to `_create_grid_panel` / `_bind_grid_panel` -- which already take a panel and
  a `GridData` and never touch `state.grids`. Three things to add: label stacks
  for the Entrance's rows, height labels for the Entrance -- which stay ABOVE their stack like every
  other, the owner having reversed an earlier call, so the arithmetic is unchanged and only the
  separation band's BUDGET grows (column scores on top, Entrance height scores directly beneath) --
  and a cell lookup in `_sync_cell_score_labels` that is ZONE-GENERIC rather than grid-only.
  ⚠ Owner: *"no special cases"* -- no Entrance branch anywhere; the general form resolves a cell
  through whichever zone owns it, which is why the Entrance was made a `GridData` in the first
  place. What is still missing is an accessor handing back every zone rather than just `grids`. ⚠ A multi-row Entrance (the owner named 2x3) is SETTLED as real rows, with a slot's
  stack depth staying the HEIGHT axis -- which confirms the shipped banking rather than changing
  it. But `upper_zone` is a flat array of slots with nowhere to put a second row, so giving the
  Entrance rows is a STRUCTURAL change (it becomes cell-shaped like GridData), not a label one. ⚠ Row/col label COUNTS and the
  per-height stacks are ALREADY derived from the grid's own dimensions and buckets, so an 8x7 grid
  needs no work there; do not rebuild them.
- **`ProfileManager.unlock()` has no production caller** — only tests call it, and `book` is the only
  locked entry, so S38/K2/K3/K4, `_repack_wall()`, `apply_layout(animate = true)` and
  `picture_unlocked` are all unreachable in the shipped game. Built-but-not-wired, and on neither
  PICTURE_WALL.md's wiring table nor this list until now.
- **Wall view never shows the whole wall, by design, and it may be too much.** `Q5`=b fills and
  crops, and `G10` supplies pan to reach what falls outside — but at 16:9 four of twelve pictures
  are cut by the frame, more at 32:9, and GAP-018=(a) keeps `view_margin` as extra crop, which
  makes it more pronounced. Wants an owner look at real renders before anything builds on it.
- **At 32:9 the ellipse clamp saves the layout but does not compose it** — nothing is stretched into
  a pancake, but the result is upper-heavy with empty bottom corners (`TEST_PLAN.md` §10 item 7).
- ⚠ **`start_menu` does NOT overflow its picture — an earlier note here said it did and was wrong.**
  Its widest content ends at x=1148 of a 1152 design width. The clipping seen in the tool was the
  tool's own rounded `preview_aspect` default (1.7778) landing 1.4e-05 past `is_equal_approx`, so
  `focused_scale()` applied its 2% overfill margin at what is really a matching aspect. Fixed by
  seeding `preview_aspect` from the live window. **The lesson generalises: any caller that hands
  `WallPacker` a rounded aspect instead of `window.x / window.y` will crop 2% off every focused
  picture.** `Main` computes it exactly, so the game is unaffected.
- **Nothing has ever HEARD a wall transition** — no `PictureEntry.music` is authored on any entry,
  so the crossfade has never had a stream to blend. The machinery is now previewable (the tool hosts
  the real `Wall`, and `_move_to()` drives `begin_music_crossfade()`/`update_travel_music()`/
  `finish_music_crossfade()`); what is missing is audio to point it at.
- **The editor's INSPECTOR preview still cannot drive four knobs** (`wall_selection_repeat_delay`,
  `wall_debug_readout`, `wall_reveal_delay_scale`, `wall_unlock_all`) because `Wall` is not `@tool`
  and loads there as a placeholder. All four work when the tool is RUN (F6), which hosts the real
  `wall.tscn`. Making `Wall` `@tool` would close this, but it would also instantiate the shipped
  autoload-facing shell in the editor — not attempted.
- **Controller still untested by anything automated**: deadzones, analogue-stick ramps, and device
  hotplug mid-session. `wall_selection_repeat_delay`'s repeat is now real and covered by a synthetic
  action test, but no real stick has driven it.
- **`deck`, `settings` and `book` are registered ids with no screen** — they pack, frame and accept
  navigation, and draw whatever `background_texture` they are given, or nothing. Building their
  contents is out of scope for this stream; the wall does not need changing to host them.

# Efficiency Audit — Phase 2 Proposals & Implementation Handoff

**2026-07-16 IMPLEMENTATION PASS COMPLETE.** Every owner-approved item (P1, P3-P8,
P10-P12, P14, P15) is DONE; P2/P9/P13 SKIPPED per owner NO. The full 22-suite run was
green after every step (see EFFICIENCY_AUDIT_TRACKER.md test-run log). Per-item STATUS
lines below carry the implementation notes a future agent needs.

Self-contained handoff for a fresh agent. The 2026-07-16 audit pass applied every
approval-free fix (see [EFFICIENCY_AUDIT_TRACKER.md](EFFICIENCY_AUDIT_TRACKER.md)); this
document lists everything that REMAINS, one proposal per item, each with an **APPROVAL:**
line the owner fills with YES / NO (optionally with notes). Implement only the YES items.

## Context for the implementing agent (read first, no other context needed)

- Project: `C:\richard\gamedev\solatro` — Godot 4.7 GDScript, Using github desktop and git location is "C:\richard\gamedev\.git"
- Run tests: `C:\richard\Godot_v4.7-stable_win64_console.exe --headless --path
  C:\richard\gamedev\solatro res://Tests/all_tests.tscn` — exit code = failure count.
  If the process hangs after the final banner, read the result from
  `%APPDATA%\Godot\app_userdata\Solatro\test_output_all.log` and kill it.
  **All suites pass as of the owner's 2026-07-16 interaction-test fix — keep it that way.**
- If you ever see cascading `Could not find type X` parse errors: the global class cache
  is stale. Run `--headless --path <project> --import` to rebuild it BEFORE debugging.
- Ground rules (from `efficiency_audit.txt` + ARCHITECTURE_REVIEW.md §8): strict logic
  preservation unless a proposal explicitly says otherwise and is approved; all board
  mutations go through `Board.*` / Game's deck functions and bump `state.revision` AFTER
  consistency; anything reading PlayArea maps calls `flush_rebuild()` first; do not "fix"
  owner rulings B10 / S6 / N8 / D7 (P11 below asks about D7 explicitly).
- `addons/worldgen/` is vendored — never edit it here (P14 items go to the separate
  worldgen project).
- Docs to update as you land items: ARCHITECTURE_REVIEW.md (item checkboxes),
  EFFICIENCY_AUDIT_TRACKER.md (fixes table + test-run log), and this file (mark each
  proposal DONE/SKIPPED).

## Audit coverage — what has and hasn't been audited

Audited line-by-line (2026-07-16, don't re-audit): all of `Scripts/` (+`Scripts/Map/`),
`Levels/`, `UI/`, `Cards/` (including Props/Skills/Stamps/Statuses/Types/Pips), and now
`Decks/deck.gd`. Surveyed at architecture level: `addons/worldgen/` (vendored).

NOT yet audited:
- `Tests/**` (~25 files, ~350KB) — deliberately last per plan §6 (P13 below).
- `Cards/Props/Tools/formation_editor.gd` (15KB) — editor-only authoring tool, skimmed
  not line-audited; zero runtime impact.
- worldgen line-level detail (world_settings, graph_spec/detail, biome_*, painting,
  world_randomizer) — surveyed only; vendored, so line fixes belong upstream (P14).
- `.tscn` scene files, third-party addons (big_number, flex_container, script-ide,
  SmoothScroll, yard), Assets/Audio/Locale — out of scope by design.

---

# PROPOSALS (answer YES / NO per item)

Ordered by expected payoff within each group. "Behavior after" describes what a player /
test would observe differently — "identical" means provably none.

## Group A — Performance

### P1. Skip dispatch walks for hooks nothing implements (implementer-cache gating)

**STATUS: DONE 2026-07-16.** Gate in run_all_mods (cacheable envs consult the SE1 implementer cache; empty = skip walk) + owner's ruling implemented: the on_anything tail now fires only when the event actually invoked a mod. shuffle_deck checks on_append implementers once before its loop. One deliberate test update: test_dispatch's "unimplemented hook -> on_anything still runs" now asserts the tail is skipped.

- **What changes:** `Scripts/card_environment.gd` — generalize the existing SE1
  `_compare_implementers` cache (already keyed on `[state id, state.revision]`) so
  `run_all_mods(hook)` first asks "does ANY card on the board carry a mod implementing
  this hook?" and returns immediately when the answer is no. Same for the automatic
  `on_anything` tail it fires after every event, and `shuffle_deck`'s per-card
  `on_append` broadcast.
- **Why:** today EVERY event pays a full board walk for `on_anything` (nothing in
  production implements it — only test fixtures do), and dealing a 52-card deck walks
  the board 52 times for `on_append` (also unimplemented). These are pure no-op scans.
- **Expected improvement:** roughly halves the per-event dispatch cost (the on_anything
  tail disappears), and removes O(deck × board) no-op scanning from every game start /
  shuffle. The biggest safe dispatch win available.
- **Behavior after:** identical. When no mod implements a hook, the walk called nothing
  and triggered no `skill_active_check` anyway — skipping it is observation-equivalent.
  Test fixtures that DO implement these hooks still run: base environments (tests' fake
  envs) return an empty revision key, which makes them uncacheable and always walk.
- **Risk / tests:** LOW. One caveat to verify while implementing: adding/removing a
  status or modifier on an in-play card must bump `state.revision` (MUTATION GUIDELINES
  already require this for the compare cache — same exposure, no new invariant). Full
  suite + a manual playthrough.
- **APPROVAL:** Yes, if run_all_mods triggered nothing, don't bother running on_anything since nothing could have changed.

### P2. E1a — run `skill_active_check` once per event, not after every mod call

**STATUS: SKIPPED (owner NO).** skill_active_check stays per-mod-call.

- **What changes:** `Scripts/card_environment.gd run_all_mods` — the
  `await skill_active_check()` after EVERY mod invocation (lines 50/55) moves to a
  single call at the end of the event dispatch.
- **Why:** `skill_active_check` is itself a full board walk. An event that invokes M
  mods currently does M+1 full walks; this drops it to 2 (the dispatch walk + one check).
- **Expected improvement:** large constant-factor cut on busy events (scoring cascades,
  on_next with many zones) — dispatch cost goes from O(mods × board) to O(board).
- **Behavior after:** NOT identical — this is the one real behavior change in Group A.
  `on_active` / `on_deactive` currently fire mid-event, immediately after the mod call
  that changed a skill's condition; they would now fire once, after the event finishes.
  Concretely: a ZoneAdder whose activation condition flips halfway through an event
  would add/remove its column at event end instead of mid-event, so LATER mods in the
  same event would see the old column layout. No current production content is known to
  depend on mid-event flips, but that is exactly the kind of thing that silently matters.
- **Risk / tests:** MEDIUM. `test_dispatch`, `test_mods`, `test_board` cover ordering;
  Submit/Next need heavy retest (arch review's own instruction for E1).
- **APPROVAL:** No, skills that trigger on active should immediately trigger when their conditions are true, not wait for everything else to finish.

### P3. E4 / §5.4 — position index (`Dictionary[CardData, Vector3i]`)

**STATUS: DONE 2026-07-16.** Implemented as a LAZY revision-keyed index (GameData.position_of + _scan_positions), deliberately not eager-per-primitive: invalidation rides the existing bump-after-consistency rule (same key as the SE1 compare cache), so there is no per-mutation-path index surgery to miss (the owner's catastrophic-staleness worry). Board.move_stack invalidates once after its extraction (the mid-mutation locate). I4 added to validate(); locate/find_data_vec3/is_data_topmost now O(1). Chaos tests: test_fuzz cross-checks EVERY card's indexed position against an independent linear scan after EVERY action, plus periodic duplicate_state hops; the fuzz's raw mutations now bump revision per the guidelines (as the sanctioned paths they simulate do). Board.remove_column also fixed to finish mutating BEFORE its revision bump.

- **What changes:** `Scripts/board.gd` + `Scripts/game_data.gd` — maintain a
  card→coordinate dictionary updated by the existing mutation primitives (`move_stack`
  extract/insert, `place_card`, `add_column`, `remove_column`, draw/discard/deck ops).
  `Board.locate`, `Game.find_data_vec3`, `find_vec3_data`, `is_data_topmost` become O(1)
  lookups instead of scanning every column. Rebuild the index in `duplicate_state()` /
  `restore_runtime()` (it must not be serialized). Add invariant I4 to
  `GameData.validate()` (index agrees with a full rescan) so debug builds self-check.
- **Why:** position lookups are the hottest primitive in the project: every move locates
  its source, `is_active()`'s topmost rule runs constantly, and the prop tick loop calls
  `find_vec3_data` once per prop slot entry per tick (each a full-board scan today).
- **Expected improvement:** move/scoring/prop-simulation cost stops scaling with board
  size; `validate()`'s I1 duplicate check becomes cheap enough to leave on in debug.
  Also the prerequisite that makes several log-only observations moot.
- **Behavior after:** identical (pure lookup acceleration). This is the architecture the
  review already designed (§5.4) — step 2 of its migration plan, steps 1/3/4 are done.
- **Risk / tests:** MEDIUM — every mutation path must maintain the index; a missed one
  = wrong positions. Mitigated by the I4 validate cross-check running after every move
  in debug + the board/fuzz suites. No new files needed (lives in Board/GameData).
- **APPROVAL:** Yes. This will need extremely comprehensive and fuzzy chaos tests since wrong position could be catastrophic.

### P4. N6 — stop building all 13 starter decks per `Deck.new()`

**STATUS: DONE 2026-07-16.** All 13 decks + rules1 are lazy getters (build on first access, cached in the backing var). Owner's leak question answered: the eager decks DID leak - CardData<->CardModifier backrefs are RefCounted cycles Godot never collects, and the suite's exit-time leaked-instance count dropped from ~146k to ~18k once eager construction stopped.

- **What changes:** `Decks/deck.gd` — the 13 `var deckN : Array[CardData] = _build_deckN()`
  member initializers become lazy (build on first access), so `Deck.new()` allocates
  nothing. (`get_deck()`/`get_rules()`/`get_deck_list()` keep their exact signatures;
  `get_deck_list` builds each deck when the picker actually opens.)
  Note: the OTHER half of the old complaint (N-E1, "~500 lines of copy-paste") turns out
  to be ALREADY DONE — deck.gd is now loop-built. Only the eager construction remains.
- **Why:** every `Game` (`@export var deck : Deck = Deck.new()`, one per show) and every
  DeckPicker open constructs all 13 decks + rules — roughly 250 CardData each carrying
  2-4 modifier/pip Resources ≈ ~1000 Resource allocations, of which one deck is used.
- **Expected improvement:** faster show start, less per-run garbage; the deck picker
  builds only what it lists when opened.
- **Behavior after:** identical (same decks, same order, same contents; construction
  just happens at first use).
- **Risk / tests:** LOW. Watch one subtlety: `rules1`/decks use `random_standard()` pips
  for cosmetics — construction timing changes WHICH global-RNG values they draw, which
  is cosmetic-only today (rules cards never score). Full suite covers the flows.
- **APPROVAL:** Yes. This does bring up the question of if those unused decks were being freed or not or causing memory leak.

### P5. E8 — BoosterTemplate: one gather helper + await the mod broadcasts

**STATUS: DONE 2026-07-16.** _gather(getter, hook) helper; all 10 pairs route through it and the broadcasts are awaited. Await ripple handled: ChoiceViewer.add_to_scene, map._open_booster, map_hover_panel._populate_cards, and 2 test call sites now await (coroutines that never suspend resume synchronously, so the flows stay effectively synchronous until a mod actually implements a pool hook).

- **What changes:** `Cards/Types/booster_template.gd` — `create_one_choice` and
  `get_possible_preview_cards` each repeat the "call `get_possible_X()`, broadcast
  `on_get_possible_x` over it" pair five times, and none of those `run_all_mods` calls
  are awaited. Extract one helper that does the pair, and `await` the broadcast.
- **Why:** dedup (10 copies → 1 helper) + a latent race: an async mod editing the pools
  could today finish AFTER the pick already happened, silently having no effect.
- **Expected improvement:** ~30 lines removed; the hook contract becomes reliable for
  future content.
- **Behavior after:** identical TODAY — nothing in production implements
  `on_get_possible_*` (verified by grep), so awaiting changes no observable behavior.
  It is future-behavior-defining, which is why it needs sign-off.
- **Risk / tests:** LOW. Booster flows covered by map/e2e suites.
- **APPROVAL:** Yes

### P6. E5-lite — cap the undo history length

**STATUS: DONE 2026-07-16.** MAX_UNDO_HISTORY=100 (hard memory ceiling) + game.undo_cap=25 (gameplay cap, a plain var so play mods can raise it; clamped to the max at trim time). save_state trims to the newest cap entries. entity_side_for_row hashes history_trimmed + size (persisted as RunState.game_history_trimmed), so prop-side picks stay identical to uncapped behavior and replay-stable across resume.

- **What changes:** `Levels/game.gd save_state()` — after appending, trim
  `save_history` to the newest N snapshots (N as a PlayerSettings knob, e.g. 100).
- **Why:** every action deep-duplicates the entire GameData into history, and the FULL
  history persists to disk with every background save. Long shows grow per-action save
  payloads (serialize time + file size) without bound.
- **Expected improvement:** bounded memory + bounded background-save cost late in a
  show. (The real per-click duplication cost remains — that fix is the D6 command-log
  redesign, which stays deferred as major architecture.)
- **Behavior after:** undo works exactly as today up to N steps back, then stops (the
  oldest boards are gone). Resume/anti-cheat unchanged (they only need the newest
  snapshot). Choose N generously and no player will notice.
- **Risk / tests:** LOW. test_game_headless/persistence fuzz cover undo + resume.
- **APPROVAL (and preferred N):** Yes add max cap, and a separate smaller default cap. Max cap is for memory, and default cap is changeable through play mods that manipulate this cap. It needs to be smaller so that if player gains more undos then they can go further back in time.

## Group B — Latent bugs (each changes behavior; that's the point)

### P7. Fix `SkillExtraPoint`'s always-true self-check

**STATUS: DONE 2026-07-16.** target == self.data. No test asserted the buggy Nx behavior; full suite green unchanged.

- **What changes:** `Cards/Skills/skill_extra_point.gd:11` — `if data == self.data`
  compares the field to itself (always true); change to `if target == self.data`.
- **Why / behavior TODAY:** every active ExtraPoint card fires its
  `on_mod_triggered` broadcast for EVERY card scored anywhere — so trigger-reactive
  content (SkillEchoingTrigger, StampDoubleTrigger) is being fed N× the intended
  events in decks 3/5/7/8/9/11.
- **Behavior after:** an ExtraPoint card announces a trigger only when ITS OWN card is
  scored — matching its description ("Gain 1 Extra Point Per Score" of itself).
  Trigger-stacking decks (5/7/8) will score measurably differently.
- **Risk / tests:** the mods/scoring suites assert current (buggy) behavior in places —
  expect to update those assertions deliberately, not paper over them.
- **APPROVAL:** Yes.

### P8. HungryHippo end-of-game board mutation bypasses the Board API

**STATUS: DONE 2026-07-16.** eat_card now takes the eaten card OFF the board (locate + erase, Stage.DATA while held) and bumps revision; on_game_end sets Stage.DRAW on returned cards and bumps once after the loop.

- **What changes:** `Cards/Skills/skill_hungry_hippo.gd on_game_end` — eaten cards are
  appended straight into `game.state.draw_deck` with no `revision` bump (violates the
  MUTATION GUIDELINES: stale UI + stale compare cache). Route it through the proper
  path + bump, and also make `eat_card`'s stage/bookkeeping consistent.
- **Why now / why ask:** the eating hook is currently fully commented out, so the path
  is DEAD — fixing it is future-proofing an unfinished mechanic. Alternative: leave
  untouched until the mechanic is actually revived.
- **Behavior after:** none today (dead path). Correct-by-construction when revived.
- **Risk / tests:** trivial.
- **APPROVAL (fix now / leave until revived):** Yes

### P9. Delete the orphaned Deck Maker tool

**STATUS: SKIPPED (owner NO - kept for refactor).**

- **What changes:** delete `UI/deck_builder.gd` + `UI/deck_builder.tscn` (and decide on
  `Scripts/player_save.gd`, which exists only as its profile container).
- **Why:** the script preloads `res://Cards/card.tscn` and `res://UI/card_control.tscn`
  — files that NO LONGER EXIST — and types against the deleted `Card` class. It cannot
  load; nothing references the scene. It is dead weight that also breaks any "compile
  everything" check.
- **Behavior after:** none (it was unreachable and unloadable).
- **Risk / tests:** none. If you'd rather rebuild the Deck Maker someday, say NO and
  it stays as reference material.
- **APPROVAL (delete builder? also delete player_save.gd?):** No, keeping it for refactor.

### P10. `GameData.validate()` I1 message never shows the second location

**STATUS: DONE 2026-07-16.** I1 walk now iterates named containers and reports both locations.

- **What changes:** the duplicate-card check stores `seen[card] = true`, then prints
  `seen[card]` in the "card in two places: X (also %s)" message — which prints `true`
  instead of where the card also lives. Store the container name instead.
- **Expected improvement:** debugging duplicate-card invariant breaks becomes one-read.
- **Behavior after:** identical (debug message text only).
- **Risk:** none.
- **APPROVAL:** yes

## Group C — Housekeeping / policy questions

### P11. Commented-out dead-code purge (needs a D7 ruling change)

**STATUS: DONE 2026-07-16 (owner overrode D7 with the TODO rule).** Removed (implementation exists elsewhere): pip_comparator's old-class graveyard, cascade scorer's old scoring body, card_modifier's stale hook lists (pointer to ARCHITECTURE_REVIEW SS1.4 left in place), card_visual's old-Card scraps + duplicate scoring-anim block, play_area's dead selection-emit block, card_data_array's clone/signal. Converted to TODOs (unimplemented logic): half-step ranks / multi-suit / stone pips in pip_comparator, TypeStone sinking behavior, card feedback popups (card_shake), CardVisual discard animation, modifier rarity/tags.

- **What changes:** delete the large commented-out blocks: `pip_comparator.gd`
  (~110 lines), `skill_scorer_cascade_lower.gd` (~110), `card_modifier.gd`'s stale hook
  list (~70 — replaced by a maintained hook list in ARCHITECTURE_REVIEW §1.4),
  `card_visual.gd` (~35), plus smaller scraps.
- **Why:** plan §5 explicitly wants this (token/context leanification, file size), but
  owner ruling D7 says "commented-out code kept as reference" — the two conflict, so
  nothing was touched. ~350+ lines across the hot files an agent reads every session.
- **Behavior after:** identical (comments only).
- **APPROVAL (override D7 for these blocks?):** Yes. Replace with TODO comments if commented out code refers to unimplemented logic, remove if already has implementation.

### P12. Dedup modifier backref relink helpers

**STATUS: DONE 2026-07-16.** Static GameData.unlink_card_backrefs/relink_card_backrefs are THE modifier slot list; RunManager calls them.

- **What changes:** `RunManager._relink_cards` re-implements
  `GameData.relink_modifier_backrefs`'s body (and `_to_saveable_cards` mirrors
  `unlink_modifier_backrefs`). Move the per-card link/unlink into small static helpers
  on GameData (or CardData) and call from both.
- **Expected improvement:** one place to extend when a new modifier slot is added
  (the suit slot was already added to both by hand — the drift risk is real).
- **Behavior after:** identical.
- **Risk:** trivial; persistence fuzz suite covers it.
- **APPROVAL:** Yes

### P13. Tests leanification (plan §6 — the designated LAST step)

**STATUS: SKIPPED (owner NO - tests are fast; the real annoyance is headless not detecting test end, not suite size).**

- **What changes:** audit `Tests/**` for redundant assertions / oversized fixtures and
  prune. The suite currently passes and takes a few minutes headless.
- **Recommendation:** measure per-suite timings first (all_tests prints them); only
  prune if a suite is actually a bottleneck. Test code is also the project's safety
  net — thinning it has real cost.
- **APPROVAL (audit tests now / skip until the suite feels slow?):** No, tests are fast currently. Headless isnt catching when tests end properly.

### P14. Worldgen upstream batch (implemented in the SEPARATE worldgen project)

**STATUS: DONE 2026-07-17 (implemented upstream + re-copied here).** All 4 items landed in the canonical worldgen project (implementation notes inline in its UPSTREAM_EFFICIENCY_TODO.md) and the 10 changed .gd files were re-copied into `addons/worldgen/` (README's vendored banner preserved). Full Solatro suite green after the copy (22 suites, 1252 checks, exit 0). Notable upstream findings: GDScript per-byte writes are ~3x SLOWER than `set_pixel` — the readback wins were taken as whole-image C++ passes (convert/create_from_data/blit_rect_mask), all verified bit-identical; and `--headless` never fires `frame_post_draw` in 4.7, which stalls any GPU-flush await (see the NEXT STEPS headless item).

- **What:** the vendored-addon findings from the tracker — Image raw-data readbacks
  instead of per-pixel `get_pixel`/`set_pixel` (world_generator, map_painter),
  `PackedInt32Array` river/lake node storage instead of `Array[Vector2i]`, typed local
  dicts, loading-spinner `set_process` gating. All behavior-identical; generation-time
  and memory wins on big maps.
- **Note:** these must land in the canonical worldgen project and be re-copied here —
  NOT edited in `addons/worldgen/`.
- **APPROVAL (open these as upstream work?):** Yes

### P15. Scoring `HandProfile.remove_card` reverse map

**STATUS: DONE 2026-07-16.** card_rank_keys/card_suit_keys reverse maps recorded during profiling; remove_card touches only its own buckets.

- **What changes:** `Scripts/scoring.gd` — removing a card from a hand profile walks
  every rank AND suit bucket; keep a card→keys map built during profiling so removal
  touches only its own buckets.
- **Expected improvement:** straight/flush extraction loops drop from O(cards × keys)
  to O(cards). Only matters on very large boards (30+ card lines); harmless otherwise.
- **Behavior after:** identical.
- **Risk / tests:** LOW; the scoring suite is exhaustive (~250 checks).
- **APPROVAL:** Yes

---

## Implementation order for approved items

1. P10, P12, P9, P8 (trivial, independent) → run suite once after the batch.
2. P4 (lazy decks), P6 (history cap), P15 (scoring map) — independent, suite after each.
3. P1 (hook gating) → heavy retest (Submit/Next/props/boosters + full suite).
4. P5 (booster await) — after P1 (same dispatch file).
5. P7 (ExtraPoint fix) — expect deliberate test-assertion updates; keep the diff to the
   skill + its tests only.
6. P3 (position index) — the big one; follow §5.4's design in ARCHITECTURE_REVIEW,
   land the I4 validate check FIRST, then swap lookup internals.
7. P2 (skill_active_check batching) — LAST of the dispatch changes; retest everything.
8. P11 purge and P13 tests-audit whenever convenient after the above.
9. P14 happens in the worldgen repo on its own schedule.

After each landed item: tick it here (DONE + date), update the tracker's fixes table,
and flip the matching ARCHITECTURE_REVIEW checkbox. All tests must pass at every step.


---

# NEXT STEPS (post-implementation, 2026-07-16)

1. **Manual playthrough** to sanity-check P1 dispatch gating and P5 booster flows in the
   real app (headless e2e covered them, but the handoff's own instruction for P1 was a
   playthrough; not possible from the implementing session).
2. **P14 worldgen batch** — DONE 2026-07-17: all 4 items implemented upstream, validated
   there (windowed test scenes — headless stalls, see item 4), re-copied here, full
   Solatro suite green (22 suites / 1252 checks).
3. **Memory-leak canary tests — APPROVED + IMPLEMENTED 2026-07-17.**
   `Tests/Engine/test_leak_canary.gd` ("LEAK CANARY", 2 checks): (a) proves the canary
   catches a deliberate drop-without-unlink leak, (b) 10 clean Game build/teardown cycles
   (unlink_modifier_backrefs + free) return Performance.OBJECT_COUNT to a post-warm-up
   baseline; print_orphan_nodes on failure. Runs LAST and ALONE (OBJECT_COUNT is global)
   — it was appended to the suite-ordering chain in test_base.gd: E2E RUN now excludes
   "LEAK CANARY" and the canary waits on everything (mind the DEADLOCK RULE when adding
   suites). **Residual attribution DONE 2026-07-17 (later session): all test-owned;
   teardown fixes cut the full-run exit leak 19,335 -> 699 after the tail sweep
   (details: todo.md §Memory, tooling: Tests/Support/leak_probe.tscn).**
4. **INVESTIGATED 2026-07-17 — does not reproduce.** 6 consecutive full headless runs
   (23 suites) all self-terminated cleanly (~20 s, exit 0); nothing in Scripts/ or Tests/
   awaits frame_post_draw (only vendored worldgen flush(), untouched by tests), and the
   RunManager saver thread joins in _exit_tree. Conclusion + recurrence workaround
   recorded in HEADLESS_TESTING.md §1. Original note kept below for history.
   **Owner-raised: headless test runs do not always terminate cleanly** (the P13 NO note).
   Worth a small investigation independent of test leanification. LEAD (2026-07-17, found
   while validating P14 upstream): in Godot 4.7 `--headless`, `RenderingServer.frame_post_draw`
   never fires, so ANY await on it (worldgen `flush()`, or anything similar in Solatro's
   UI tests) stalls forever. If a Solatro test path awaits frame_post_draw (directly or via
   addon code), that would exactly produce "hangs after the final banner".
5. Remaining ARCHITECTURE_REVIEW opens: SS5.4 step (5) delete the Vector3i adapters; D6
   command-log undo (the real E5 fix); D1/D2/D4, S3/S4/S6(owner ruling)/S7, D8-D11.

## Confidence notes from the implementing agent (weakest first)

- **P3 failure-mode shift:** with the lazy revision-keyed index, a FUTURE mutation path
  that writes state arrays without bumping revision now returns STALE positions instead
  of slow-but-correct scans. Guarded by I4 in validate() (debug builds warn after every
  move) and the fuzz cross-check, but the discipline is load-bearing - keep the MUTATION
  GUIDELINES in board.gd sacred.
- **P1 on_anything semantics:** the owner-ruled skip (tail only when a mod actually ran)
  is asserted in test_dispatch, but nothing in production implements on_anything, so real
  coverage is thin by nature. If passive content lands later, re-read run_all_mods first.
- **P6 edge:** a mod-raised undo_cap does not persist across quit/resume (documented in
  game.gd); resume falls back to the default cap and trims on the next action. Fine today
  (no such mod exists) but a future undo-granting mod must re-apply its cap on resume.
- **P5:** if an async mod that actually suspends ever implements an on_get_possible_*
  hook, ChoiceViewer creation becomes genuinely deferred - intended, but untested.

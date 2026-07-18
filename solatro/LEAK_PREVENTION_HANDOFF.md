# Handoff: permanent leak prevention (weakref backrefs) + playtest leak sentinel

**STATUS: LANDED 2026-07-18 (both workstreams).** This document is historical — see the
dated entry in `EFFICIENCY_AUDIT_TRACKER.md` and `todo.md` §Memory for what shipped
(benchmark gate passed; exit leak 547 → 4; sentinel autoload live in debug builds).

Written 2026-07-18 for an agent with NO prior context. Repo:
`C:\Users\khanr\Documents\GitHub\gamedev\solatro` (Godot 4.7 GDScript). Owner has seen
and approved this plan in outline (2026-07-18 conversation); the weakref conversion is
BENCHMARK-GATED — do not land it if the numbers fail (see §A5).

## Why this exists

`CardData <-> CardModifier` backrefs (`modifier.data` pointing back at its card) are
RefCounted CYCLES; Godot has no cycle collector, so any card graph whose last external
reference drops leaks until process exit. Today this is contained by MANUAL discipline:
`GameData.unlink_card_backrefs` / `unlink_modifier_backrefs` called at every drop site.
The 2026-07-18 production leak canary work (see `PRODUCTION_LEAK_CANARY_HANDOFF.md` and
`EFFICIENCY_AUDIT_TRACKER.md`, dated entries) found FIVE missed production drop sites in
one sweep — all the same mechanism, each a unique ownership blind spot. Manual
discipline demonstrably keeps failing; the owner wants (A) a structural fix and (B) a
debug-build anomaly detector for real playtests. Nothing here is landed yet.

## Current state you must know

- The cycle is created in `Cards/card_data.gd` `with_skill/with_type/with_stamp/
  with_suit` (each calls `modifier.with_data(self)`), and for statuses in
  `CardModifierStatus` (`st.data`).
- THE single unlink/relink slot list: `Scripts/game_data.gd:300-318`
  (`unlink_card_backrefs` / `relink_card_backrefs` — skill/type/stamp/suit + statuses).
- Existing unlink discipline (production): `Game.undo()` (quiescent point),
  `Game.return_to_map` (replaced deck copies + rules/zone headers), `Game.exit_show`
  loss branch, `RunManager.clear_save`, `DeckPicker._exit_tree`, `MapHoverPanel`
  preview cards. Test-side: `TestSuite.unlink_cards` + per-suite teardowns everywhere.
- ⚠️ OWNER RULINGS that stand: `Game._restore_pre_act_board` deliberately does NOT
  unlink (mods still run against the doomed state — see its comment); test-only leaks
  do not matter (the suite-exit floor is a tripwire, not a target).
- Regression net: `Tests/Engine/test_leak_canary.gd` — section 1 (bare Game cycles) +
  section 2 (PRODUCTION SESSION CANARY: full simulated session per cycle, asserts
  OBJECT_COUNT returns to baseline). Runs LAST and ALONE; mind ⚠️ THE DEADLOCK RULE in
  `Tests/Support/test_base.gd` (~line 44) if you add any suite.
- Serialization: ResourceSaver cannot write the cycles — `GameData.to_saveable()` and
  `RunManager._to_saveable_cards` unlink copies; `restore_runtime` / `_relink_cards`
  relink after load. Deck copies today rely on `duplicate_deep(DEEP_DUPLICATE_ALL)`
  REMAPPING the `data` backref to the copied card automatically.

## Workstream A — kill the cycle: `CardModifier.data` becomes a weak backref

The idea: store the backref as a `WeakRef` internally, expose the same `data` property
(getter returns `_data_ref.get_ref()`), so the cycle never exists and the ENTIRE unlink
discipline becomes deletable. Steps, in order:

1. **Benchmark FIRST.** `.data` is read in hot mod-dispatch/scoring loops. Build a
   before/after timing: run the scoring-heavy suites (SCORING, BOARD FUZZ, E2E,
   PROP ENGINE) 3x each and/or a micro-bench looping `mod.data` reads 10M times.
   Record numbers in the tracker. Gate: within a few percent on suite wall-time.
2. **Audit lifetime assumptions BEFORE converting.** Two known traps:
   - Anywhere a `CardModifier` (or status) is held WITHOUT its card, the weakref lets
     the card die early. Search for fields/arrays holding modifiers detached from
     cards (e.g. `ZoneAdder.card_data` is the reverse direction — a skill holding a
     card — that one is fine). Any real case found: that holder must keep the CardData
     itself, or the site is a blocker to raise with the owner.
   - `duplicate_deep(DEEP_DUPLICATE_ALL)` will NOT remap a WeakRef: duplicated
     modifiers would point at the ORIGINAL card. Every duplicate site must relink
     copies explicitly (`GameData.relink_card_backrefs` per copied card). Enumerate:
     `Game.add_deck`, `RunManager.new_run`, `RunManager._to_saveable_cards` (wants
     data ABSENT — set null instead), `GameData.duplicate_state`/`to_saveable`/
     `restore_runtime`, and any test factory relying on remap. Grep `duplicate_deep`.
3. **Convert.** In `card_modifier.gd` (and `CardModifierStatus`): private
   `_data_ref : WeakRef`, property `data : CardData` (setter wraps `weakref(v)` or
   null; getter unwraps). Keep the property NAME so ~every call site is untouched.
   Ensure the backing var is not `@export`ed (WeakRef doesn't serialize; saved decks
   must simply carry no backref, same as today's unlinked saves).
4. **Land in two passes.** Pass 1: weakref + the relink-after-duplicate fixes, with
   all existing unlink calls left in place (they become harmless no-ops writing null).
   Full suite green + benchmark + canary green. Pass 2 (separate, easy to review):
   delete the unlink calls and machinery — the five production sites listed above,
   test teardown unlinks, `TestSuite.unlink_cards` — and update the stale comments.
   KEEP: `to_saveable`'s data-stripping (saves still must not carry backrefs), the
   leak canary itself (it becomes the tripwire proving the class is dead — its
   deliberate-leak "prove it detects" step must be REWRITTEN, since a dropped card no
   longer leaks; leak a Node instead), and `_restore_pre_act_board`'s comment.
5. **Acceptance:** ALL suites green (two runs, exit 0); benchmark within gate;
   full-run exit-leak count should COLLAPSE (was 547 on 2026-07-18 — record the new
   figure); isolated `leak_probe` runs of the formerly-leaky suites near 0. Update
   the stale accepted-floor numbers in `todo.md` §Memory + the tracker.

**Fallback (only if the benchmark fails): Plan B** — an explicit owner type: a small
`CardGraph` RefCounted wrapping `Array[CardData]` that unlinks in
`NOTIFICATION_PREDELETE`; every deck-holding field routes through it. More invasive at
call sites, keeps the unlink machinery. Do not start it without owner sign-off.

Do NOT do blanket "unlink on _exit_tree" on display nodes: viewers/pickers often show
LIVE decks (DeckViewer shows the running draw pile) — only owners know when cards die.

## Workstream B — playtest leak sentinel (independent; land regardless of A)

Debug-build anomaly detector that runs during REAL playtests and prints an error when
cards leak, naming the source:

1. **Registry:** in `CardData._init` (debug builds only — `OS.is_debug_build()`),
   append `weakref(self)` to a static list. Zero release-build cost.
2. **Monitor:** a small autoload (suggest `Scripts/leak_sentinel.gd`, registered in
   project.godot like RunManager) that, at QUIESCENT moments only (entering the map,
   after `exit_show`, plus a slow timer — never mid-act), prunes dead refs, counts
   alive cards, and counts cards REACHABLE from the legitimate roots:
   - `Main.save_info` (`card_datas`, `rule_datas`, every `game_history` snapshot's
     collections);
   - `CardEnvironment.CURRENT`'s state collections (`Game.get_card_collections`) +
     `Game.save_history` snapshots;
   - open UI owners: `DeckViewer._open`'s deck, any live `DeckPicker`'s `_deck` lists,
     `MapHoverPanel._preview_cards`, `ChoiceViewer.data.current_choices`.
   `alive - reachable > SLACK` for N consecutive checks (start SLACK 8, N 3) →
   `push_error` with counts + a histogram of unreachable cards by `stage` and
   modifier class names — the histogram is what NAMES the leak source.
3. **Knobs** live in `Scripts/player_settings.gd` (project convention — all tunables
   there, read via `SettingsManager.settings`): enable flag, slack, strike count,
   timer interval.
4. **Tests:** the sentinel must stay quiet across the existing full suite (suites
   deliberately leak — either disable it under the test runner via a TestLog/flag
   check, or gate on the knob defaulting OFF outside debug play). Add a tiny check to
   the leak canary: force-leak a linked card, tick the sentinel, assert it reports;
   with workstream A landed, sentinel-relevant leaks are Node/array-held cards only.
5. If A does NOT land, the sentinel is the main defense — also add a cheap watermark:
   sample `Performance.OBJECT_COUNT` / `ORPHAN_NODE_COUNT` at the same quiescent
   points and warn on sustained unexplained drift (expected deltas: deck growth).

## Validation (this machine)

- Full suite: `& "C:\Users\khanr\Desktop\Godot_v4.7-stable_win64.exe" --headless
  --path C:\Users\khanr\Documents\GitHub\gamedev\solatro res://Tests/all_tests.tscn`
  — exit code = failure count; ALL 24 suites green is the bar (count the run's own
  banner). Totals VARY run-to-run (fuzz suites) — compare failure sets, not totals.
  Logs: `%APPDATA%\Godot\app_userdata\Solatro\test_output_all.log` / `_errors.log`.
- ⚠️ NEVER run headless while the Godot editor has the project open (check
  `Get-Process *odot*` — do not kill the user's editor; ask instead). Stale class
  cache ("Could not find type X" cascades): run once with `--import`.
- Per-suite exit-leak attribution: `... leak_probe.tscn -- <suite .tscn path>`
  (`Tests/Support/leak_probe.tscn`).
- Style gates: warnings are errors — type every array and every for-loop variable;
  user-facing strings go through `TRANSLATION.find` (Locale/localization.csv).
- Do NOT `git add`/commit — the owner uses GitHub Desktop and commits themselves.

## On completion, update

- `solatro/todo.md` §Memory (mark what landed; refresh the now-stale exit-leak
  numbers) and `EFFICIENCY_AUDIT_TRACKER.md` (dated entry: benchmark numbers, new
  exit-leak figures, files touched — call out every production file explicitly).
- If workstream A pass 2 deleted the unlink discipline, sweep the many comments that
  reference "leak-canary discipline" so they describe the weakref reality.

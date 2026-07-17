# TODO — future work (out of scope for the 2026-07 efficiency audit)

Owner-endorsed backlog, updated 2026-07-17. Current status of the audit itself:
AUDIT_PROPOSALS_HANDOFF.md (all approved items DONE incl. P14 upstream batch).

## Performance: worldgen C++ / GDExtension port (the real generation-time win)

Generation is dominated by pure-CPU GDScript (measured on the dev box, GTX 1070,
seed 12356: Rivers_Only ~60-75% of step time, Graph ~15-23%). The 2026-07-17 upstream
batch already took every behavior-identical GDScript win; the remaining hot loops need
native code. Port candidates, in impact order (from worldgen/UPSTREAM_EFFICIENCY_TODO.md):

1. `addons/worldgen/core/steps/rivers.gd` — hydrology: `fill_depressions`
   (priority-flood), `flow_accumulate_mfd`, lake labeling/dilation. Biggest single win.
2. `addons/worldgen/core/graph/graph_placement.gd` — MapField (landmass labeling,
   chamfer distance transform, Poisson land samples).
3. `addons/worldgen/core/biomes/biome_regions.gd` — region flood/voting.
4. `addons/worldgen/painting/map_painter.gd` `_paint` — per-pixel classifier
   (NOTE: keep `set_pixel` in GDScript; raw byte writes measured ~3x SLOWER there).

Rules: land in the canonical worldgen project first, re-copy into `addons/worldgen/`
here (never edit the vendored copy); keep outputs bit-identical or get owner approval.

**BLOCKED 2026-07-17: no C++ toolchain on this machine.** Two docs now exist in the
worldgen repo: `GDEXTENSION_PORT_HANDOFF.md` (full implementation handoff — candidates,
bit-identical traps, fallback wiring, validation checklist) and `CPP_SETUP_FOR_OWNER.md`
(the owner's one-time install steps: VS Build Tools 2022 C++ workload + `pip install
scons` + verify). Port starts once the owner confirms `cl` / `scons --version` work.

## Testing / infrastructure

- **Headless test hangs**: root-cause lead + workarounds in HEADLESS_TESTING.md
  (read that BEFORE debugging any "test hangs" report).
- Worldgen `graph_spec_test` full fuzz (1500 specs) takes ~17 min (~0.7 s/spec) —
  either trim `fuzz_count` for CI or accept the wall time; sampled 300-spec runs clean.
- Worldgen `addon_bake_test` / `addon_node_test` scenes have no `quit()` — fine for F6,
  but a CI runner must kill them after the PASS lines.

## Remaining ARCHITECTURE_REVIEW opens (unapproved / unscheduled)

- §5.4 step (5): delete the Vector3i adapters.
- D6 command-log undo (the real E5 fix).
- D1/D2/D4, S3/S4/S7, D8–D11. (S6/B10/N8 have standing owner rulings — leave.)

## Memory

- **OWNER-ENDORSED 2026-07-17: comprehensive PRODUCTION leak canary.** The current
  canary (test_leak_canary.gd) only covers bare Game build/teardown cycles — not the
  real game experience. What matters is leaks a PLAYER can accumulate (test-only leaks
  don't matter). Extend the canary (or add a sibling suite, also last+alone — mind the
  DEADLOCK RULE in test_base.gd) to run N full cycles of a simulated session and assert
  OBJECT_COUNT returns to a post-warm-up baseline. Each cycle should exercise, at
  minimum, everything that creates Nodes or RefCounted card graphs:
  - menus / DeckPicker open+close (builds decks), viewers (DeckViewer, ChoiceViewer,
    map hover panel) open+close
  - map: enter, traverse a node or two, open a booster choice
  - a real show with a GameView attached (not view == null): a few Nexts, grab/place
    moves on the board, draw + discard, a Submit with real scoring so props spawn and
    finish, then UNDO across the Submit (undo swaps whole GameData snapshots — the
    2026-07-17 Game.undo() unlink covers the quiescent path; the canary should prove it)
  - quit-mid-show -> resume (RunManager save/load relink), exit_show on both the win
    and loss paths, clear_save
  Baseline gotchas from the existing canary: warm-up cycle first (lazy deck caches,
  static registries), _settle() two frames before counting, print_orphan_nodes on
  failure, and OBJECT_COUNT is engine-global so it must run alone. Known accepted
  sources it must tolerate/pin: RunManager._saveable_deck cache (rebuilt per deck
  change, not a leak), TestLog file handles.
- **Residual exit leak ATTRIBUTED + mostly FIXED 2026-07-17 (later session):** the
  ~19.3k residual was 100% test-suite-owned (per-suite isolated runs sum to the full-run
  figure; production autoloads leak 0). Tooling: `Tests/Support/leak_probe.tscn` runs ONE
  suite scene then quits, so the engine's exit leak count attributes per suite — keep it.
  Teardown fixes landed (test_base.gd `unlink_cards` helper + per-suite unlink at every
  drop site): PERSISTENCE FUZZ 8943→0, E2E 1908→170, VISUAL LAYERS 1669→0,
  BOARD FUZZ 1490→0, UI PROPS 1378→0, INTERACTION 1233→275, GAME HEADLESS 1008→68,
  BOARD 540→26. One PRODUCTION fix: Game.undo() now unlinks the outgoing live state
  (quiescent point; _restore_pre_act_board deliberately does NOT — mods still run against
  the doomed state there, see its comment).
  Tail swept 2026-07-17 (same session): MODS 382→98, RUN MANAGER 278→0,
  PROP ENGINE 238→11, ITERATOR 161→0, GAME DATA 109→0, SUIT PROPS 104→0, STATUSES 54→0.
  **Full-run exit leak now ~700 instances (was 19,335).** Accepted floor, not worth
  further chasing: UI VIEWERS 46, DISPATCH 32, COMPARATOR 23 (cards built inline at
  dozens of scattered sites), LEAK CANARY 57 (its own deliberate leak fixture), plus
  small residues in MODS/E2E/INTERACTION/GAME HEADLESS/BOARD from cards dropped
  mid-test outside any state container. OWNER RULING 2026-07-17: test-only leaks don't
  matter — do NOT chase this floor further; production coverage (item above) is what
  counts. The suite-exit leak count is only useful as a regression tripwire now.

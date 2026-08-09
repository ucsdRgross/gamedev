# TODO — open backlog (owner-endorsed unless marked otherwise)

Add new items here; **delete an item when it lands**, recording the regression-critical residue in
ARCHITECTURE_REVIEW.md rather than keeping a log here. Current-state facts live in
ARCHITECTURE_REVIEW.md; done-work history lives in git.

## Waiting on the owner

- ⬜ **Playtest the universal palette** (below) — the fire and ball colours changed.
- ⬜ **Playtest the shader FX** (FX_SHADER_PLAN §10, 17 steps).
- ⬜ **Delete FX_SHADER_PLAN.md + FX_HANDOFF.md** once that playtest passes. Their residue is
  already folded into ARCHITECTURE_REVIEW §4g/§4h.
- ⬜ **Spotlight: answer GAP-010 / GAP-011** (overrun banking; emptied-section hooks —
  `design/spotlight/gaps/`), **judge G2.2** (rank-glyph readability), **pick
  `spotlight_separation_mode`**. Status ledger: HANDOFF_spotlight.md.

Everything below is unscheduled backlog.

## Visual effects

**Anything fire, juggling, prop art or FX shaders starts at [VFX.md](VFX.md) §6/§7**, which carries
that whole backlog and its known bugs. Keeping the list here as well is exactly the two-places
drift this repo's doc hygiene forbids.

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

## Scoring engine test gaps

- ⚠ **SE4 IS NOT A TEST GAP AND SHOULD NOT SIT UNDER THIS HEADING.** "single-walk `_scan_wrap`" is a
  micro-OPTIMISATION of `Scripts/scoring.gd`: the scan restarts its walk from every rank
  (`for start in range(A, W + 1)`), where one pass could find the longest wrap-around run. Nothing
  about coverage. ⚠ **No benchmark exists for the scoring path**, so doing it now would be
  speculative — measure first, and only if a real board's scoring shows up in a profile.
- ⬜ SD5 test-file section renumbering — cosmetic only, and `test_scoring.gd`'s own header already
  says the section numbers are historical and `_ready` order is the real one. Churn on a 1200-line
  file for no behavioural gain; left deliberately.

### ⬜ OWNER DECISION — comparator hooks reach CLASSIFICATION but not FORMATION

**Where `on_compare_ranks` / `on_compare_suits` DO land:**

| Site | What it governs |
|---|---|
| `skill_grabber_og_lower`, `skill_placer_og_lower` | whether a grab / place is legal (shipped rules cards) |
| `scoring.gd:273` (`build_multi` -> `Scoring.is_flush`) | whether a structure counts as a **Full Flush** — a x2 score multiplier |
| `scoring.gd:351`, `scoring.gd:796` | rank sort order; best-high-card choice |
| the placement legality query | feeds PATIENCE (see the patience section) |

**Where they do NOT:** hand FORMATION. Every cluster is built from profile bucket keys, and
`PipComparator.get_rank_profile` / `get_suit_profile` are PURE — they read `r.value` / `s.get_str()`
and are not even `async`, so they cannot dispatch to a mod without being rewritten.
- `scoring.gd:460` X-of-a-kind — rank buckets (`cluster.datas.size() >= 2` IS the definition of a set)
- `scoring.gd:412` / `:731` pure flush — suit buckets
- straights — rank buckets

**So the seam, stated precisely: within scoring, "are these the same?" is answered TWO WAYS — bucket
keys when FORMING a hand, the hook when CLASSIFYING or MULTIPLYING one.** Consequences:
- A **suit mod** cannot make five distinct suits into a flush (buckets), but CAN turn an existing
  structure into a Full Flush and double its score. ⚠ **This is the one that looks like a genuine
  inconsistency** — the same question about the same cards, answered differently at two steps.
- A **rank mod** cannot make five distinct ranks into a Five of a Kind, but does change sort order,
  high-card choice and move legality. That reads more like a deliberate boundary than a bug.

Measured (`test_comparator.gd` SECTION 5): a mod returning `0.0` from `on_compare_ranks` leaves five
distinct ranks scoring as **High Card**; with a suit mod, `is_flush(hand)` returns **true** while the
scored hand carries **no FLUSH type**. ⚠ That second result is explained by the fixture having no
structure at all (High Card never reaches `build_multi`), NOT by `build_multi` ignoring the hook.

⚠ **Entirely latent: no shipped card implements either hook.** The first one that does will land on
this, and it will look like a broken card rather than an engine boundary.

**OWNER RULING — this is a BUG:** *"If I wanted to override on compare,
I would not expect a valid hand to fail because it went down high card path instead before ever
checking valid on compare."* A hook that says "override rank comparison" and is then skipped by the
one step the player judges it on is a trap, whatever the implementation. **Owner has accepted this as
a BUG. Not resolved — implement later.**

⚠ **PROFILE KEYS ARE NOT THE ANSWER HERE.** They express *which equivalence classes a card belongs to*: right for WILD cards, half-step ranks and
multi-suit cards, wrong for a comparison override. "All ranks are the same" would need every card to
emit every rank key (degenerate), and "ranks within 1 are the same" is relational and cannot be
expressed as class membership at all.

---

#### ⬜ THE PLAN — build the buckets THROUGH the hooks, before the meld makers ever see them

Owner's framing: *"premake buckets already influenced by hooks such as on compare before sending it
to the meld makers."* That is exactly the shape — and it is a ONE-SITE change, because every handler
already reads its clusters out of one place.

**1. The site.** `Scoring._get_hand_profiles_async` is the only place buckets are built
(`profile.ranks.map` / `profile.suits.map`). Every handler downstream — `ExpandedGridHandler` (:460),
the pure-flush gate (:412), `MultiStraightHandler` (:570), `MultiFlushHandler` (:731) — consumes those
maps and nothing else. Fix it there and every meld maker inherits it; no handler needs touching.

**2. The gate, which is what makes this free today.**
```
if CardEnvironment.CURRENT._compare_implementers(&"on_compare_ranks").is_empty():
        -> current path: key = r.value           # bit-identical, zero cost
else:
        -> derive buckets from the comparator    # only when a mod actually exists
```
`_compare_implementers` is **cached per board revision** (`_revision_key()`, invalidated by
`GameData.revision`), so the gate is a dictionary lookup. No shipped card implements either hook, so
the fast path is always taken today and behaviour cannot change until content asks for it.

**3. The slow path: TRANSITIVE CLOSURE (union-find), not naive pairwise.** Walk the cards, union any
pair the comparator calls the same, then each disjoint set becomes one bucket.
⚠ This is what dissolves the transitivity objection: for a non-transitive hook like "within 1" on
1,2,3 the closure merges all three — a DEFINED answer rather than an order-dependent one. A bucket
must be an equivalence class or grouping means nothing. **Document the consequence:** such a rule
swallows a whole run.

**4. Do SUITS the same way**, and the second half of the seam closes with it: formation and
classification would both derive from one hook, so `is_flush` saying "yes" while the scored hand
carries no FLUSH type becomes impossible instead of merely tested-for.

**5. ⚠ Keep the reverse maps consistent.** `profile.card_rank_keys[card]` / `card_suit_keys[card]` are
the O(1) reverse index `HandProfile.remove_card` relies on. Closure-derived buckets must populate
them too, or removal silently leaves cards in buckets.

**6. Cost.** O(n²) comparisons, each possibly an async mod dispatch — but ONLY when a comparator mod
is present. Worth a bench before shipping content that uses it; scoring runs over the whole board
(30+ cards in the macro tests), so n² is not free at that size.

**7. Tests that must change when this lands.** `test_comparator.gd` SECTION 5 pins TODAY'S behaviour
and its checks are written to FAIL the moment grouping consults the hooks — that is deliberate. When
implementing, invert them: five distinct ranks under an "all ranks equal" mod must become a
Five of a Kind, and the suit-mod case must FORM a flush. The G1 fixture is already built for it.

**Alternatives, kept for the record:** **B** keep today's split (cheapest, trap stays);
**C** route `is_flush` through profiles so mods affect neither (removes the contradiction, costs
suit mods their Full-Flush effect).

`test_comparator.gd` SECTION 5 pins today's behaviour, and those checks FAIL if grouping is ever
wired through the hooks — which is the point.

## Props / UI (owner has NOT re-verified)

- Description-panel scroll-lock, knife row behavior, hoop visibility, ballistic poof,
  undo-across-submit feel, held-loop spin, formation system + editor end-to-end (no formation
  `.tres` authored yet).
- Firework in-run acquisition beyond deck12 (owner decision). Per-pip tooltip granularity.
- Win/lose screen font (226px) clips long "Fame +N" text. `game.tscn` grabs no initial focus, so
  keyboard/controller players must click first.

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

## Patience & rerolls (owner playtest pending)

Full behavior and the settings list: ARCHITECTURE_REVIEW §4e.

- Tune `patience_max` (ships 3) and the per-stage `patience_influence_*` flags (ships PLAY only);
  decide whether the legality query `on_can_place_stack` should count at all — if not, add it to
  `patience_disabled_hooks` and re-tune what "interesting move" means.
- ⚠ `patience_max` ships **3**, but the original spec asked for **1** — confirm which is intended
  before drawing playtest conclusions (3 = three idle moves per round).
- Rule cards that raise `patience_max` / grant patience: the grant path exists
  (`patience_max_increased`), no content uses it yet.
- Booster rerolls (§4f): pool ships at 5 (`booster_reroll_pool`); reroll-count modifiers (the
  `luck()`-style content hook) not written yet.
- Watch existing suites for auto-Next fallout: any test that makes 3+ boring moves in one round now
  advances the round mid-test.
- Comparator hooks reach patience: `on_compare_ranks/suits` fire through
  `return_first_compare_mod_result` during the placement legality query, so ANY board card with a
  comparator modifier holds the counter (once per round under uniques). Decide whether that is the
  intended "interesting move" bar or belongs in `patience_disabled_hooks`.
- `Game._on_patience_max_increased` edits `state.patience` with no commit — a mid-round grant is
  lost on quit and reverted by undo. Fine for a settings knob; revisit when a rule CARD grants
  patience (that grant should ride a committed action).
- `Game._ready` connects to `SettingsManager.settings.patience_max_increased` without the N9
  reconnect idiom, so the connection binds the settings resource that exists at show start. Only
  matters if `SettingsManager.settings` is ever reassigned at runtime (its setter supports it).
- Two gaps documented in ARCHITECTURE_REVIEW: the auto-Next pending-action replay caveat (§1.5) and
  the seen-set-only commit gap in `_perform_next` (§4e).

## Card size + outline — landed, one thing open

Card is **40x54**; every element wears `Shaders/outline.gdshader`'s rim. Rules and landmines:
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
  (§16); meta progression (§19); leaders/acts (§11); deterministic per-subsystem RNG streams
  (§6/§23 — required before any seed-sharing feature).

## Testing / infrastructure

- ⬜ **LEAK CANARY's session check is INTERMITTENT and the cause is still unknown.** Observed growth
  is 2 or 3; failure rate has ranged from ~0 in 30 consecutive runs to 5 in 10. **Judge it across
  runs, and never report a count without saying how many runs it took.**
  - **On failure it writes `user://logs/leak_forensics_<timestamp>.txt`** — growth split by
    node/resource/other, a phase x cycle table, a node-class histogram diff, and a running-tween
    count. **If that file exists it IS the finding; attach it rather than trying to reproduce.**
  - **Eliminated on evidence from real failures — do not re-try any of these:**
    - **NOT a Node.** `nodes +0`. This is why `print_orphan_nodes()` can never find it: on a failing
      run it prints only the four strays this suite abandons on purpose.
    - **NOT a Resource.** `resources +0` — so not a CardData / `.tres` graph, which is what the suite
      was originally built to watch.
    - **NOT a Tween.** `RUNNING TWEENS 0 -> 0`. (A Tween is RefCounted and keeps itself alive while
      running, so one still ticking at drain time would have read exactly like this.)
    - **NOT phase-localised.** All six session phases are identical across cycles, so it is not the
      menus, run start, map, show, loss path or `clear_save` accumulating.
    - **NOT a deferred-free straggler.** `queue_free` deferral applies to NODES; a RefCounted dies the
      instant its refcount hits zero. If it is alive after the drain, something still HOLDS it.
    - **NOT held to process exit.** `--verbose`'s exit ObjectDB dump on a FAILING run listed exactly
      `4x Node` (the deliberate strays) and nothing else, while non-Node leaks do appear there. So it
      is released during shutdown — which also kills the "coroutine that never resumes" theory, since
      that would pin its locals all the way to exit.
    - **NOT fixable by draining harder.** Retrying the drain up to 6 extra times left the growth in
      place on every failure. ⚠ **And the remedy back-fires: growth went 2 -> 3 and the failure rate
      roughly doubled**, because `_drain()` calls `create_timer()` and a `SceneTreeTimer` is itself
      RefCounted — so extra drains allocate into the very bucket being measured, asymmetrically
      (baseline drains once, the after-path seven times). This very likely explains the earlier
      "settle until stable" attempt too. Any future drain remedy must be allocation-free first.
  - **What is left:** a plain RefCounted, not a Tween, held by something alive at the check and
    released by shutdown — e.g. a `WeakRef`, a bound `Callable`'s object, or a script instance
    (`Scoring.Result`, `ArrayCardData`, `HandProfile`, `CardDataIterator`, `LightLayer.Light`).
    The next instrument would have to name RefCounted instances, which GDScript cannot enumerate;
    the practical route is a debug instance counter on the few suspect classes.
- E2E first-card fly-in in the pack preview: confirm fixed on a real run.
- Background-save robustness at scale unverified (large history serialize on a worker thread) —
  watch the console; the history cap bounds it.
- **PIXELS `test_the_card_mask_is_the_card_the_player_sees` WAS GREEN but PINNED, not fixed.** The
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

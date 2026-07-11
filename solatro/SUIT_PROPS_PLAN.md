# Plan v3 — Suit Modifiers as Data-Layer Props (Hoop / Knife / Ball / Fire / Firework)

## Revision history

- **v1** — banked closed-form scores, cosmetic entities. Superseded (couldn't support the
  pass hook; stale against the landed Game/GameView split, commit `baa4b00`).
- **v2** — data-layer entities, one-slot-per-wave sokoban lockstep, effects hardcoded in
  entity subclasses. Superseded by owner feedback (2026-07-10):
- **v3 (this plan)** — props carry **their own modifiers** (effects survive the spawner card
  leaving the board); movement is a **quantized tick simulation** with per-kind **density**
  (multiple props per slot, equidistant trains) and a **spawner schedule** (batch vs
  sequential emission, live-cap so huge spawns start moving before emission finishes);
  card reactions (jump/spin) are decided by a **per-tick view-side aggregation**, not by
  per-skill methods; Ball/Fire become **ballistic** (no board traversal — fly straight to
  precomputed targets); one shared system covers all of it.
  **Same-day addendum (future-proofing, owner):** prop movement is **per-prop async** — a
  prop's remaining route is *mutable mid-flight* (teleport / push-a-row / redirect by card
  effects like a future Strongman or Teleporter card); each pass runs a **three-phase
  protocol** with an interception phase so cards can **dodge** a prop's effect; visual
  travel must be fully general (both zones, vertical movement, instant relocations) while
  still riding the scrollable play area.
- **v3.2 (second same-day addendum + grill-session rulings, owner):** the tick pipeline is
  now *SPAWN → MOVE (instant data) → start the visual tick (not awaited) → EVENTS run in
  parallel with the animation (new-slot props only) → await tick completion* — the data
  layer is always one step ahead of the visuals (physics-interpolation analogy), and
  headless the whole submit resolves in one frame; per-prop speed is **`ticks_per_slot`**
  (integer countdown, 1 = fastest — replaces the density/speed-quanta pair); the view uses
  **per-frame interpolation against the live tick duration** (never locks a duration in at
  animation start — global speed scale/compression changes apply mid-slot); finished
  travelers exit **into the void** (extrapolated off-board slot) before fading. Rulings:
  travelers **pass their own origin card** (knives self-score by design; `source` becomes a
  supported input for future prop effects — must tolerate an off-board origin); card
  **reactions play at visual arrival** from pure hints, independent of the parallel mods;
  suits go **live in all decks at once** at Phase 3; the **same-act fire cascade**
  (row-scored Burning buffing later columns) is intended. Prop art ships as **placeholder
  draws with an explicit expected pixel size** on the visual.

### Audit facts this plan is built on (verified 2026-07-10)

- The seam is `game.view : GameView` (game.gd:29); `score_row`/`score_col` are unified into
  `score_line(result, is_row, zone, index)` (game.gd:432); the suit-phase insertion point is
  the surviving `#await play trigger score effects` comment (game.gd:446).
- Existing view methods: `rebuild / sync_scores / load_board_visuals / animate_meld /
  show_meld_score / reset_meld / update_line_score(zone, index, score)`
  (game_view.gd:129-169). This plan **adds** `play_prop_tick`.
- Dispatch is instance-based; `_compare_implementers` caches comparator mods on
  `state.revision`. Headless tests exist (`Tests/Engine/test_game_headless.gd` `make_game()`
  fixture + `check()` pattern; `test_game_data.gd`).
- `TestFactories.m_card` fabricates unlimited distinct suits via
  `PipSuitStandard.with_value(uc())` (test_factories.gd:7-11) — Phase 0.6 must replace it or
  every scoring test breaks.
- `CardVisual.anim_jump() -> float` exists (card_visual.gd:342); `anim_spin` does not.
- `unlink/relink_modifier_backrefs` cover `[skill, type, stamp]` at **four** sites:
  game_data.gd:195-203 and run_manager.gd:123-133.
- `statuses : Dictionary[String,int]` is still the vestigial field (card_data.gd:35).

### Locked decisions

- **Four real suit subclasses** (Hoop/Knife/Ball/Fire) + special 5th (Firework), all
  extending `PipSuit(→CardModifier)`. Suits are **nominal, not ordinal** — switching uses
  the `PipSuit.from_index` factory, never `value ± 1`.
- **Suit effects fire per meld membership** (row + col membership fires twice). No dedupe.
- **Status-Effect foundation built here** (STATUS_EFFECTS_PLAN.md is the detailed spec).
- **Keep "Knife"** (props are the thrower's target boards; talents spin clear).
- **Props are NOT CardModifiers.** CardModifier's contract is card-owned: the
  `data: CardData` backref (drives the four unlink/relink serialization sites),
  `is_active()` tied to board position / rules deck, texture-slot methods, save paths. A
  prop can never belong to a card, never serializes, and owns movement state — extending
  CardModifier would import wrong invariants for zero shared code. Props get their own
  parallel modifier system (`PropModifier`, below) that mirrors the *idiom* (duck-typed
  `has_method` hooks) without the inheritance.
- **Prop behavior lives on the prop** (its `PropModifier` list + spawn-captured coords), so
  props keep working when their spawner card is discarded/moved mid-flight. `source` is a
  **supported input for future prop effects** (owner ruling) — but no CORE v1 effect reads
  it, and any effect that does must tolerate the origin being off-board
  (`find_data_vec3 == Vector3i.MIN` / validity check), which is what keeps the
  survive-spawner-removal guarantee intact.
- **Travelers pass their own origin card** (owner ruling): the row IS the route — a
  knife's own card is a no-skill prop, so knives self-score their spawner on the way past
  (deliberate; balance via `KNIFE_POINTS`).
- **Each pass is a three-phase protocol** (targeted dispatch both ways; `run_card_mods` is
  the ONLY dispatch that sees suits, `run_all_mods` stays suit-free):
  1. `on_prop_passing(prop)` on the card's mods — interception: may `prop.negate_pass()`
     (dodge), teleport/redirect the prop, etc.;
  2. if not negated, the prop runs its own mods (`on_pass_card`) — the effect;
  3. `on_prop_passed(prop)` on the card's mods — notification (always fires).
- **Movement is per-prop and async-mutable.** Each prop owns `at` (current slot) +
  `route` (remaining slots, **mutable mid-flight**) + an integer **tick countdown**; its
  speed is **`ticks_per_slot`** (1 = fastest — advances every tick). When the countdown
  expires the prop decides its next slot by popping `route[0]` — which any hook may have
  rewritten meanwhile (teleport / push to a parallel row / redirect); the tick loop just
  re-reads. Train spacing emerges from emission stagger (ticks) × `ticks_per_slot`
  (staggered 1 tick apart at `ticks_per_slot = 2` → half a slot apart → 2 props per slot).
  All-integer math keeps `pending_action` replay exact (no float drift).
- **The tick pipeline** (owner-specified order): SPAWN → MOVE (instant, all props; props
  spawned this tick excluded) → **start** the visual tick (not awaited) → EVENTS **in
  parallel with the animation** — the 3-phase pass runs only for props that entered a NEW
  slot this tick (mid-slot props fire nothing), while their visuals are still crossing the
  boundary; prop-phase hooks must not add paced awaits (the tick's length is
  animation-bound) → await tick completion (animation AND events done) → FINISH. Headless
  (`view == null`) there is no visual tick to await — **an entire submit resolves in one
  frame** (physics-interpolation analogy: data one step ahead, visuals catch up).
- **Spawning = per-spawner schedule** (`batch_size` / `interval` / `max_live`): hoops and
  knives burst out of their card all at once into a staged stack at the row edge, then move
  in sync; Ball/Fire emit one prop per tick, very fast; a million-prop spawner starts its
  first props moving (and despawning) long before emission finishes.
- **Ball/Fire are ballistic**: targets precomputed by the mancala walk at spawn (pure
  data); each prop flies origin→target in one tick and applies its status on arrival. No
  board-traversal data needed — exactly one arrival event.
- **Card reactions are view-side aggregation**, not per-skill methods: the tick loop
  reports which props sit on which card each tick; the view composes JUMP (any hoop) /
  SPIN (any knife) / both (different tween properties), holding the pose while props keep
  arriving. Reactions play **at visual arrival** from pure hints (prop kind +
  `card.skill`), frame-synced with the prop reaching the card and independent of the mods
  running in parallel — dodge/negation alters the data effect, never the animation. Skills
  wanting custom reactions implement `on_prop_passed` themselves.
- **Determinism:** prop event order = spawner order, emission order, tick order — all
  integers. Hoop/knife side = `hash([submits_used, save_history.size(), zone, row])`
  (resume-persisted inputs only; direction affects hook order, so it is data).
- **Compression is elapsed-time driven** + an **event-count cap** as the infinite-chain
  valve; prop pass events feed the same cap.
- **Visual owner:** `PropLayer (Node2D)` inside the scrolled content
  (`SmoothScrollContainer/TopLevelVBox`, play_area.tscn) so props ride the scroll transform.
  Pacing is **per-frame interpolation against the LIVE tick duration** — re-read every
  frame, never locked in at animation start, so speed-scale/compression changes apply
  mid-slot. Finished travelers continue **into the void** (one extrapolated off-board
  slot, negative/overflow positions legal view-side) and fade there. Prop art is
  **placeholder** for now: each `PropVisual` exposes an expected pixel size
  (`@export var art_size : Vector2`) that both the placeholder draw and all
  spacing/staging math use, so swapping in real art later changes only the draw.

Memory flags gating execution: **[[godot-editor-disk-sync]]**, **[[running-godot-scenes]]**
(prints; the USER runs scenes/tests), **[[no-git-staging]]**,
**[[solatro-tres-cyclic-backrefs]]** / **[[solatro-persistence-gotchas]]** (suit + statuses
join the unlink/relink lists), **[[code-style-lean-documented]]**,
**[[solatro-multimodal-input]]** (Phase 5 tooltips must work for keyboard/controller focus).

---

## Architecture

```
DATA LAYER (headless-complete, deterministic, unit-tested — no nodes, no world coords)
  Game
   ├─ score_line(...) ──> _run_score_effects(result)         [game.gd:446 comment site]
   │      ├─ card.suit.spawn_props() per meld card ──> Array[PropSpawner]   (PURE)
   │      ├─ run_props(spawners)          THE tick simulation (data one step ahead of view)
   │      │     SPAWN  each spawner emits per schedule while under its live cap
   │      │     MOVE   (instant) live props: countdown -= 1; at 0 pop route[0] -> `at`,
   │      │            reset to ticks_per_slot  (route mutable mid-flight -> teleport/
   │      │            push/redirect; spawn-tick props excluded from MOVE)
   │      │     START  tick_done = view.begin_prop_tick(report)  — NOT awaited yet
   │      │     EVENT  in parallel with the animation, per prop that ENTERED a new slot
   │      │            (mid-slot props fire nothing), deterministic order — 3-phase pass:
   │      │             run_card_mods(card, &"on_prop_passing", prop)   interception/dodge
   │      │             if not negated: prop.run_mods(&"on_pass_card") the effect
   │      │             run_card_mods(card, &"on_prop_passed", prop)    notification
   │      │     FINISH route exhausted -> into the void; run_mods(&"on_finish"); despawn
   │      │     SYNC   if view: await tick_done   (animation AND events both complete;
   │      │            headless: nothing to await -> whole submit resolves in one frame)
   │      └─ run_all_mods(&"on_score", card) per meld card + on_after_score
   ├─ add_line_score(is_row, gutter, index, amount)        single scoring write path
   └─ elapsed-time compression + event cap (get_delay override, note_processing)
  PropData (RefCounted, transient)   at, route (MUTABLE), tick countdown, ticks_per_slot,
                                     mods, negate/teleport/redirect movement API
  PropModifier (RefCounted)          PropScoreTalents / PropScoreProps / PropDropStatus /
                                     PropBankColScore / PropBurning
  PropSpawner (RefCounted)           origin, remaining, batch_size, interval, max_live, factory
  CardModifierStatus (Resource)      StatusJuggling / StatusBurning
        │  view seam: Game only ever calls  if view: await view.play_prop_tick(...)
        ▼
VISUAL LAYER (optional, disposable — remove GameView, the data layer still runs)
  GameView.play_prop_tick(report) ──> PlayArea.prop_layer
  PropLayer (Node2D under %TopLevelVBox → rides the scroll transform)
    PropData -> PropVisual map; _process-driven interpolation (t += delta / LIVE tick
    seconds, re-read every frame — durations never lock in); begin_prop_tick/tick_done;
    spawn anim (pop out of origin card control, same t-drive), reactions AT ARRIVAL,
    per-card reaction state machine (raise while any JUMP prop over it, spin while SPIN,
    compose; anim_reset when clear), despawn into the void (fade past the edge / arrival poof)
  PropVisual (Node2D) + Hoop/Knife/Ball/Fire/Firework visuals; PLACEHOLDER art drawn to an
    exported art_size (Vector2, expected pixels) that spacing math shares; fire-tip overlay
```

### Algorithm choices (and what they were chosen over)

**1. Integer per-prop tick countdowns (`ticks_per_slot`)** (chosen) vs v2's one-slot
lockstep waves vs a global quanta clock vs continuous float positions:
- Lockstep (one prop per slot per wave) is too slow, forbids two props over one card at
  once, and can't express trains tighter than a slot — all owner-rejected.
- A single global quanta clock couples every prop to one speed; per-prop countdowns give
  per-prop speeds (fast hoops, slow future heavies) with the same determinism.
- Float progress animates identically but breaks replay determinism (accumulated float
  error changes *which tick* a boundary is crossed, which reorders hooks).
- Countdown semantics: `ticks_per_slot = 1` is the fastest (next slot every tick); train
  spacing = emission stagger × ticks_per_slot; slot entries are exact integer events; the
  view interpolates between slots so motion looks continuous.

**1c. Events run in parallel with the tick animation** (chosen, owner-specified) vs
events-after-await vs events-before-visuals:
- The data layer is one step ahead (physics-interpolation analogy): MOVE computes the new
  state instantly, the visual tick starts, and the new slots' mods execute while props are
  visually crossing the boundary — score labels react as props land, and the tick is never
  lengthened by mod execution (hooks must stay await-light, documented).
- Headless the visual tick doesn't exist, so `run_props` — and the whole submit — resolves
  in one frame with zero awaits beyond the mods themselves.
- Consequence: a phase-1 reroute/teleport takes effect at the NEXT move phase —
  deterministic and intended.

**1b. Per-prop mutable route (`at` + remaining `route` + countdown)** (chosen) vs a fixed
path with position derived from scalar progress:
- A derived position cannot be redirected: teleporting a prop or pushing it a row up would
  mean rewriting the whole path AND recomputing the scalar so it lands on the same slot —
  fragile and hook-hostile. Owning `at`/`route` per prop makes every future movement
  effect (Strongman push, Teleporter relocation, splitting, reversing) a plain data write
  from any hook; the tick loop re-reads state each tick and never assumes route
  immutability.
- Trains stay equidistant because staging/spacing lives in the countdown, not the route.
- Cost: slightly more bookkeeping per prop — pinned by the Phase 1 engine tests.

**2. Effects as `PropModifier`s on the prop** (chosen) vs v2's per-kind `EntityData`
subclass overrides:
- Owner requirement: props must run their own modifiers, so behavior composes (a burning
  hoop = hoop kind + `PropBurning` mod) and survives the spawner card leaving the board.
- Kind subclasses remain only where the *shape* differs (visual class, trajectory);
  everything a designer tunes is a mod list — new prop behavior = new PropModifier, no
  engine edits.

**3. Props separate from CardModifier** (chosen; owner-confirmed) vs extending it:
- No shared functionality exists (owner's observation is correct): CardModifier is
  card-owned, serialized, board-activity-gated; props are transient movers. The shared
  *pattern* (duck-typed hook dispatch) is ~5 lines, cheaper to mirror than to inherit
  around wrong invariants (backref unlink lists, `is_active`, texture slots).

**4. Per-spawner schedule with live cap** (chosen) vs spawn-everything-then-move:
- One `PropSpawner {batch_size, interval, max_live}` covers every requested mode: hoops
  `batch_size = remaining` (all at once), Ball/Fire `batch_size = 1, interval = 1` (fast
  sequential), and the million-prop edge case (`max_live` caps concurrent props; emission
  resumes as props despawn, so movement/despawn overlaps emission).

**5. Ballistic Ball/Fire with spawn-time target list** (chosen) vs v2's walking
distributor:
- Owner call: no traversal data needed; the mancala walk is pure data at spawn (reproduces
  the brief's worked example identically), delivery order = emission order (one per tick),
  and the visual is exactly "spawn from the card, fly to the target, apply status".
- A target card removed mid-delivery fizzles that drop (arrival re-checks occupancy).

**6. View-side reaction aggregation** (chosen) vs default reaction methods on every skill:
- Which animation a card plays is a function of *what props are over it right now* (hoop →
  jump, knife → spin, both → both) — that's per-tick state the simulation already has, not
  per-skill logic. Putting it in skills would mean every skill re-implements the same
  composition and none can see concurrent props. The tick report carries per-card prop
  sets; one view-side state machine composes. Skills that genuinely want custom reactions
  implement `on_prop_passed` (data hook) and trigger their own visuals through the
  existing seams.

**7. Deterministic side-hash** (unchanged from v2): direction affects hook order → data;
hash of resume-persisted fields is replay-stable with zero persisted RNG state.

### Hook contract (documented in card_modifier.gd's hook block + prop_modifier.gd)

```
## CARD side — heard by the passed card's own mods (type, stamp, suit, statuses, active
## skill) via the targeted run_card_mods; no self-guard needed:
##   on_prop_passing(prop: PropData) -> void      PHASE 1 — interception, BEFORE the effect:
##     may prop.negate_pass() (dodge), prop.teleport(...), prop.set_route(...) etc.
##   on_prop_passed(prop: PropData) -> void       PHASE 3 — notification, ALWAYS fires
##     (even for a negated pass; check prop.pass_negated if it matters).
##   Both run mid-tick: do NOT move/discard cards from here (B10 live-iteration caveat) —
##   score/status/prop-movement/bookkeeping only, for now.
## PROP side — heard by the prop's own PropModifiers:
##   on_spawned(prop, game)                  emission (once)
##   on_pass_card(prop, game, card)          PHASE 2 — the effect (skipped when negated)
##   on_finish(prop, game)                   route exhausted / arrival, before despawn
##   reaction_for(prop, card) -> Reaction    view hint (NONE/JUMP/SPIN/JUGGLE/BURN)
```

---

## Phase 0 — `PipSuit → CardModifier`, comparator, serialization, deck + test-factory wiring

**Files:** `Cards/Pips/pip_suit.gd`, new `Cards/Pips/Suits/pip_suit_hoop.gd`
(+knife/ball/fire/firework), delete `Cards/Pips/pip_suit_standard.gd`,
`Scripts/pip_comparator.gd`, `Cards/card_data.gd`, `Scripts/game_data.gd`,
`Scripts/run_manager.gd`, `Decks/deck.gd`, `UI/deck_builder.gd`,
`Tests/Support/test_factories.gd` (+ new `Tests/Support/pip_suit_test.gd`),
`Tests/Engine/test_comparator.gd`, `Tests/Engine/test_scoring.gd`.

### 0.1 Base class — shared visuals up, ordinal `value` out

```
# pip_suit.gd
@abstract class_name PipSuit extends CardModifier          # was: extends Resource
## CardData.suit's setter connects this (card_data.gd:9-13). Suits no longer mutate
## themselves (no `value`), but the seam stays for future dynamic suits.
signal data_changed
const SUIT_TEXTURE := preload("res://Assets/suit_pips.png")    # 8x8 frames
const ART_TEXTURE  := preload("res://Assets/suit_art.png")     # 13x13 frames
const COLOR_PICKER_SHADER := preload("res://Assets/color_picker.tres")
const PALETTE : Array[int] = [8, 11, 14, 2, 6]                 # by suit index; 5th = Firework TODO art

@abstract func get_suit_index() -> int     # 0..4 — art/palette slot ONLY, never orderable
## PURE factory: the spawners this suit launches when its card is scored in a meld.
## Empty when the card is talented (data.skill) or off-board. NO mutation in here.
@abstract func spawn_props() -> Array[PropSpawner]

func get_frame() -> int: return get_suit_index()
func set_texture(p: Polygon2D) -> void:
    CardModifier.update_polygon_uv_frame(p, SUIT_TEXTURE, 8, 8, get_suit_index())
    set_material(p)
func set_material(p: Polygon2D) -> void:   # moved up from PipSuitStandard, palette-indexed
    <ShaderMaterial(COLOR_PICKER_SHADER), color_x = PALETTE[get_suit_index()]>
func set_art_texture(p: Polygon2D, rank: PipRank) -> void:   # moved up from Standard
    <numeral: frame = 13 * get_suit_index() + (rank.value - 1); else texture = null>

## Registry + switching (replaces all `value` math). Firework excluded: never random.
const STANDARD : Array = [PipSuitHoop, PipSuitKnife, PipSuitBall, PipSuitFire]
static func from_index(i: int) -> PipSuit: return STANDARD[i].new()
static func random_standard() -> PipSuit: return STANDARD[randi() % STANDARD.size()].new()

## Fire-buff readers (self-inspection of the OWN card's statuses at spawn time).
func fire_stacks() -> int:
    for s in data.statuses:
        if s is StatusBurning: return s.stacks
    return 0
func fire_mult() -> int: return 1 + fire_stacks()
```
`fire_stacks()` needs Phase 2's statuses array — see Execution order (Phase 2 lands before
Phase 3's suit bodies; until then the shells return `[]`).

### 0.2 The five subclasses — thin shells (bodies in Phase 3)

```
# pip_suit_hoop.gd
@tool class_name PipSuitHoop extends PipSuit
func get_suit_index() -> int: return 0
func get_str() -> String: return "Hoop"
func get_description() -> String:
    return "On score: hoops equal to rank cross this row. Talents they pass jump through and score."
func spawn_props() -> Array[PropSpawner]: return []   # Phase 3
```
Same shape: Knife(1), Ball(2), Fire(3), Firework(4).

### 0.3 PipComparator — suits become equality-only

Current ordinal arm: pip_comparator.gd:59-69 (`a.value - b.value`); same-value arm in
`is_suit_same` (:73-87).

```
static func compare_suits(s1, s2) -> float:
    <null check; mod hook via return_first_compare_mod_result — unchanged>
    return NAN                      # suits have no order anymore

static func is_suit_same(s1, s2) -> bool:
    if not s1 or not s2: return false
    if s1 == s2: return true
    <mod hook on_compare_suits first, as today>
    return s1.get_script() == s2.get_script() and s1.get_str() == s2.get_str()
```
- The `get_str()` clause lets one parameterized test-suit class (0.6) represent unlimited
  distinct suits; real suits have one constant `get_str()` per class so it is a no-op for
  them. It also matches how flush detection already keys suits (`get_suit_profile` →
  `get_str()`, scoring.gd:220/267/345) — one identity rule everywhere.
- **Grabber/placer (closes review B7):** `skill_grabber_og_lower.gd:17` and
  `skill_placer_og_lower.gd:16` use `compare_suits` + NAN-compare traps → replace with
  `not await PipComparator.is_suit_same(...)`.
- **`test_comparator.gd` rewrite:** ordinal asserts (`compare_suits == 2.0` :89,
  `with_value` sameness :124-132, :197) become: `compare_suits` is NAN unless a mod
  answers; `is_suit_same` across the four real classes + the test suit.

### 0.4 CardData + serialization (the new back-cycle)

- `with_suit` wires the backref like the other slots (card_data.gd:45-47 doesn't today):
  `self.suit = suit.with_data(self) if suit else null`.
- **Backref cycle `card → suit → data`: FOUR sites** get `card.suit` beside
  skill/type/stamp (Phase 2 adds the statuses loop to the same four):
  `game_data.gd` `unlink_modifier_backrefs`/`relink_modifier_backrefs` (:195-203) and
  `run_manager.gd` `_to_saveable_cards`/`_relink_cards` (:123-133). Without all four, run
  saves fail on the cycle ([[solatro-tres-cyclic-backrefs]]).
- Undo/`add_deck` copies: `duplicate_deep(DEEP_DUPLICATE_ALL)` remaps the suit backref
  automatically — verify with a `card.suit.data == card` print after undo AND `add_deck`.

### 0.5 Deck construction

`Decks/deck.gd` (40+ sites) and `UI/deck_builder.gd`:
`PipSuitStandard.new().with_value(i)` → `PipSuit.from_index(i - 1)`;
`.with_random()` → `PipSuit.random_standard()`. Mechanical.

### 0.6 Test factories — the unlimited-distinct-suit problem

Scoring/headless tests rely on "every card a distinct suit so no flush forms"; four real
classes can't express that. New test-only suit:

```
# Tests/Support/pip_suit_test.gd
class_name PipSuitTest extends PipSuit
var id : int = 0
func get_suit_index() -> int: return id % 4          # art slot only; never rendered in tests
func get_str() -> String: return "TestSuit%d" % id   # distinct id => distinct suit (0.3 rule)
func get_description() -> String: return "test suit"
func spawn_props() -> Array[PropSpawner]: return []  # inert in scoring tests
static func with_id(i: int) -> PipSuitTest: ...
```
`m_card` keeps its signature, builds `PipSuitTest.with_id(suit_id)`. The `make_game()`
fixture inherits the fix untouched. Suit-behavior tests (Phase 3) use the real classes.

**Verify Phase 0** ([[running-godot-scenes]]): deck loads with correct pip art/colors;
same-suit stack rejected, different-suit run grabbable; save/undo round-trip prints
`card.suit.data == card` true; `test_comparator`, `test_scoring`, `test_game_headless` green.

---

## Phase 1 — Prop engine: PropData / PropModifier / PropSpawner, the tick loop, dispatch, scoring seam, compression

**Files:** new `Cards/Props/prop_data.gd`, `prop_modifier.gd`, `prop_spawner.gd`;
`Levels/game.gd`, `Scripts/card_environment.gd`, `Cards/card_modifier.gd` (hook doc), new
`Tests/Engine/test_prop_engine.gd`.

### 1.1 PropData (pure data, transient)

```
## A transient data-layer prop (hoop/knife/ball/...): lives ONLY inside one scoring pass,
## NEVER serialized — a quit mid-act replays the whole act from the pre-act board
## (pending_action), so props never survive a save by design.
class_name PropData extends RefCounted

enum Reaction {NONE, JUMP, SPIN, JUGGLE, BURN}

# --- movement state: per-prop and ASYNC-MUTABLE (any hook may rewrite it mid-flight) ---
var at : Vector3i = Vector3i.MIN  # slot currently over (MIN until first entry / after teleport)
var route : Array[Vector3i] = []  # slots still ahead, [0] = next to enter; MUTABLE — this is
                                  # what makes Strongman/Teleporter-style effects data writes
var countdown : int               # TICKS until the prop asks for its next slot (pops
                                  # route[0]); staging/train stagger lives HERE, never in
                                  # the route. Integer => replay-exact.
var ticks_per_slot : int = 1      # per-prop speed: countdown reset on each entry; 1 = the
                                  # fastest (advances a slot every tick)
var done : bool = false
var pass_negated : bool = false   # set during phase 1 of the CURRENT pass; auto-cleared

var mods : Array[PropModifier] = []       # ALL behavior lives here (composable)
var kind : int                            # visual selector (suit index); no behavior
var fire_stacks : int = 0                 # visual flame tips (PropBurning sets it too)
var source : CardData = null              # origin card, SUPPORTED input for future prop
                                          # effects (owner ruling) — no core v1 effect
                                          # reads it, and any effect that does must
                                          # tolerate the card being off-board (that is
                                          # what keeps spawner-removal survival intact)

# --- movement API (callable from ANY hook; the tick loop just re-reads next tick) ---
## Dodge: cancel the current pass's effect (phase 2). Notification (phase 3) still fires.
func negate_pass() -> void: pass_negated = true
## Instant relocation: continue traversal from `coord` along `new_route`. Recorded in the
## tick report so the view blinks/flashes instead of tweening across the board.
func teleport(coord: Vector3i, new_route: Array[Vector3i]) -> void: ...
## Rewrite only the slots ahead (e.g. Strongman pushes the prop one row up: same direction,
## parallel row — build the new tail with game.row_slot_path_from(...)).
func set_route(new_route: Array[Vector3i]) -> void: ...

## Duck-typed prop-mod dispatch, mirroring run_all_mods' idiom (not its class).
func run_mods(function: StringName, ...params: Array) -> void:
    for m in mods:
        if m.has_method(function):
            await Callable(m, function).callv(params)

## Union of the mods' view hints for the card currently under the prop.
func reactions_for(card: CardData) -> Array[Reaction]: ...
```

```
## Behavior unit for props. RefCounted, stateless where possible; NOT a CardModifier —
## props are transient movers, never card-owned, never serialized (see plan header).
class_name PropModifier extends RefCounted
# implementable hooks (duck-typed): on_spawned(prop, game) / on_pass_card(prop, game, card)
#                                   / on_finish(prop, game) / reaction_for(prop, card)
```

### 1.2 PropSpawner (schedule + factory)

```
## One scored suit card's emission plan. Owner-tunable spawn modes in one struct:
##   hoops/knives: batch_size = remaining (burst all at once, staged as a train)
##   ball/fire:    batch_size = 1, interval = 1 (fast sequential, one per tick)
##   million-prop edge case: max_live caps concurrency — first props move (and despawn)
##   while the spawner is still emitting; emission resumes as slots free up.
class_name PropSpawner extends RefCounted
var origin : Vector3i             # captured at spawn: survives source card removal
var remaining : int               # props still to emit
var batch_size : int = 1          # emitted per due tick
var interval : int = 1            # ticks between emissions
var max_live : int = 32           # concurrent live props from THIS spawner
var live : int = 0                # engine-maintained
var factory : Callable            # func(emit_index: int) -> PropData  (pure)

func due(tick: int) -> bool: return remaining > 0 and tick % interval == 0
```
Emission staging: the i-th prop of a batch gets `countdown = ticks_per_slot + i` (enters
one tick after its predecessor — an equidistant train staged behind the edge; the visual
staging stack mirrors these countdowns, extending off-screen for huge counts). A refill
emission (after the cap throttled) stages one tick behind the spawner's hindmost live prop
so followers never overlap. Props emitted this tick are excluded from the same tick's MOVE
phase (no pop-and-teleport).

### 1.3 The tick loop (Game)

```
## The prop simulation. Per tick: SPAWN -> MOVE (instant data) -> START the visual tick
## (not awaited) -> EVENTS in parallel with the animation (new-slot props only) -> FINISH
## -> await tick completion. The data layer is one step ahead of the visuals (physics
## interpolation); headless there is no visual tick, so the WHOLE submit resolves in one
## frame. Deterministic: spawners in spawn order, props in emission order, integer ticks.
const MAX_TICKS := 2048            # belt-and-braces alongside HARD_CAP (see notes)
func run_props(spawners: Array[PropSpawner]) -> void:
    if spawners.is_empty(): return
    var live_props : Array[PropData] = []
    var tick := 0
    while live_props or spawners.any(func(s): return s.remaining > 0):
        if act_overrun or tick >= MAX_TICKS: break     # audience went home (see 1.6)
        # SPAWN — each due spawner emits up to batch_size, throttled by max_live
        var spawned : Array[PropData] = []
        for sp in spawners:
            if not sp.due(tick): continue
            for i in mini(sp.batch_size, mini(sp.remaining, sp.max_live - sp.live)):
                var p := sp.factory.call(<emit_index>)
                <stage countdown per 1.2>; sp.remaining -= 1; sp.live += 1
                await p.run_mods(&"on_spawned", p, self)
                spawned.append(p); live_props.append(p)
        # MOVE — instant, data only; spawn-tick props excluded (no pop-and-teleport)
        var movers : Array[PropData] = []   # props that ENTERED a new slot this tick
        var relocated : Array = []          # (prop, from, to) — view blinks, not tweens
        for p in live_props:
            if p in spawned: continue
            p.countdown -= 1
            if p.countdown > 0: continue    # mid-slot: fires nothing this tick
            if p.route.is_empty():
                p.done = true               # into the void; FINISH handles on_finish
            else:
                p.at = p.route.pop_front()  # route re-read HERE — a hook that re-routed /
                p.countdown = p.ticks_per_slot   # teleported ANY prop took effect already
                movers.append(p)
        # START the visual tick — NOT awaited: animation and mod execution run in parallel
        # (while a prop visually exits its previous slot, its new slot's mods are running)
        var tick_done : Signal
        if view: tick_done = view.begin_prop_tick(live_props, spawned, movers, relocated)
        # EVENTS — new-slot props ONLY, in list (emission) order; hooks must stay
        # await-light (no paced visuals) — the tick's length is animation-bound
        for p in movers:
            note_processing()               # per SLOT ENTRY: an empty-slot route-rewrite
                                            # loop still feeds the runaway cap
            var card := find_vec3_data(p.at)
            if card:      # slot may have emptied mid-flight (hook moved the card)
                # --- the 3-phase pass protocol ---
                p.pass_negated = false
                await run_card_mods(card, &"on_prop_passing", p)   # 1: intercept/dodge
                if not p.pass_negated:
                    await p.run_mods(&"on_pass_card", p, self, card)  # 2: the effect
                await run_card_mods(card, &"on_prop_passed", p)    # 3: notification
                p.pass_negated = false
        # FINISH — void-arrived props: effect hook, release the spawner slot
        for p in live_props:
            if p.done:
                await p.run_mods(&"on_finish", p, self)
                <its spawner.live -= 1>
        await skill_active_check()          # once per tick: hooks may flip active states
        # SYNC — tick over when the animation AND the events above are both complete.
        # Headless: no visual tick exists -> nothing awaited -> one-frame submits.
        if view: await tick_done
        live_props = live_props.filter(func(p): return not p.done)
        tick += 1
```
- **Data/visual sync contract:** one data tick == one visual step; the view's tick
  duration is `get_delay() * PROP_TICK_FRACTION`, **re-read every frame** by the view's
  interpolation (§4.2) — speed knobs (`ticks_per_slot` in data, `PROP_TICK_FRACTION` in
  the view) cannot drift apart because the view never advances slots on its own.
- Ballistic props (route of one slot, `countdown = 1`) enter their slot one tick after
  emission and finish the tick after — i.e. land one per tick when emitted one per tick.
- `PropData.teleport()` appends its (prop, from, to) record to the current tick's
  `relocated` list (the loop hands props a reference), so the view can distinguish
  instant relocation from ordinary travel.
- Multiple props on one card in one tick is normal (several movers sharing `at`) — the
  composite reaction problem is solved in the view (Phase 4) from the movers report.
- `MAX_TICKS` + per-entry `note_processing` close the runaway blind spot: a hook that
  endlessly appends EMPTY slots to a route never finds a card, but still counts entries
  and still hits the tick ceiling.

### 1.4 Targeted dispatch — `run_card_mods` (CardEnvironment)

```
## Run `function` on ONE card's own modifiers — type, stamp, suit, statuses (Phase 2
## appends a snapshot), then the active skill. The ONLY dispatch that sees suits; the
## board-wide run_all_mods iterator stays suit-free. Cost: O(mods on this card).
func run_card_mods(card: CardData, function: StringName, ...params: Array) -> void:
    for mod : CardModifier in [card.type, card.stamp, card.suit]:
        if mod and mod.has_method(function):
            await Callable(mod, function).callv(params)
    var skill : CardModifierSkill = card.skill
    if skill and skill.active and skill.has_method(function):
        await Callable(skill, function).callv(params)
```

### 1.5 Scoring seam: `add_line_score` + phase wiring

Extract the gutter math from `score_line` so melds and props share ONE write path:

```
## Bank `amount` into a row/col gutter + the matching act total; animate the label when a
## view exists. THE single write path for line scores.
func add_line_score(is_row: bool, score_zone: Array[BigNumber], index: int, amount: int) -> void:
    resize_score_zone(score_zone, index + 1)
    if is_row: state.row_total += amount
    else:      state.col_total += amount
    var new_score := score_zone[index].plus_equals(amount)
    if view: view.update_line_score(score_zone, index, new_score)

func row_gutter(v: Vector3i) -> Array[BigNumber]:
    return state.scores_row_upper if v.x == 0 else state.scores_row_lower
```
`score_line` refactors onto it (no behavior change) and gains the phase at the
`#await play trigger score effects` comment (game.gd:446, before `reset_meld`):

```
func _run_score_effects(result: Scoring.Result) -> void:
    var spawners : Array[PropSpawner] = []
    for card in result.meld:
        if card.suit:
            spawners.append_array(card.suit.spawn_props())
    await run_props(spawners)                # all melds' props share one simulation
    for card in result.meld:                 # finally wires the designed broadcast
        await run_all_mods(&"on_score", card)     # SkillExtraPoint etc. self-guard
    await run_all_mods(&"on_after_score")
```
Notes: fires per meld (locked); activates the previously-inert `on_score` implementers
(SkillExtraPoint, StampDoubleTrigger, SkillEchoingTrigger) — intended, watch balance;
runs mid-`run_all_mods` (cascade scorer), safe because prop effects only touch gutters and
card-local statuses, never the zone/deck arrays the iterator walks (B10 stays untriggered —
documented on the hook).

### 1.6 Path helpers, deterministic sides, compression + cap

```
func entity_side_for_row(v: Vector3i) -> bool:      # replay-stable 50/50 (see decisions)
    return hash([submits_used, save_history.size(), v.x, v.z]) & 1 == 0
func row_slot_path(v: Vector3i, left_to_right: bool) -> Array[Vector3i]:  # all slots in row
func row_slot_path_from(coord: Vector3i, left_to_right: bool) -> Array[Vector3i]:
    # remaining slots of coord's row past coord — for mid-flight re-routes (Strongman
    # pushes a prop one row up: same direction, parallel row from the same column)
func column_rise_path(v: Vector3i) -> Array[Vector3i]:                    # slots above v
## Mancala TARGETS (ballistic Ball/Fire): walk below v.z wrapping to the column top,
## collecting `count` eligible cards' coords (each card may repeat); bounded at
## count+1 laps so no-eligible-target terminates.
func mancala_targets(v: Vector3i, count: int, eligible: Callable) -> Array[Vector3i]:
```
Compression + runaway cap — unchanged v2 design, revalidated:

```
# CardEnvironment (base): func note_processing(weight := 1) -> void: pass   (Map/tests: no-op)
# run_all_mods + run_card_mods: one note_processing() per mod actually invoked.
# Game:
const COMPRESS_RATIO := 0.85; const STEP_MS := 1500.0; const MIN_FACTOR := 0.05
const SOFT_MS := 20000.0; const HARD_CAP := 6000
func _begin_act(): act_start_ms = Time.get_ticks_msec(); act_calls = 0; act_overrun = false
func note_processing(weight := 1): act_calls += weight; if act_calls > HARD_CAP: act_overrun = true
func get_delay() -> float:
    if not processing: return SettingsManager.settings.base_delay   # normal play untouched
    var elapsed := float(Time.get_ticks_msec() - act_start_ms)
    if elapsed > SOFT_MS: return 0.0
    return SettingsManager.settings.base_delay * maxf(MIN_FACTOR, pow(COMPRESS_RATIO, elapsed / STEP_MS))
```
`_begin_act()` at the top of `_perform_submit`/`_perform_next`; overrun works headless
(`run_props` cuts the loop; `_perform_submit` resolves the show early as a loss —
"audience went home"). Prop tick durations read the shrinking `get_delay()` live.

### 1.7 Data tests — `Tests/Engine/test_prop_engine.gd` (register in `all_tests.tscn`)

`test_game_headless.gd` pattern (bare `Game.new()`, `CURRENT` by hand, `view == null`,
`check()` prints; the USER runs them). Probe classes:
`ProbeMod extends PropModifier` (records every hook call with tick/slot/card) and
`ProbeStamp extends CardModifierStamp` (records `on_prop_passed`).

- **Traversal:** one prop, density 1, 4-col row → enters 4 slots in order, `on_finish`
  once, done.
- **Train/speed:** `ticks_per_slot = 2`, batch of 3 staggered one tick apart → entry
  events every other tick, interleaved in exact emission order, equidistant throughout.
- **Mixed speeds:** a `ticks_per_slot 1` prop and a `ticks_per_slot 3` prop share a row →
  the fast one fires 3× the entries; combined order deterministic.
- **Same-slot silence:** a prop mid-slot (countdown > 0) fires zero mods that tick.
- **Spawn-tick exclusion:** a prop emitted this tick does not move this tick.
- **One-frame headless:** with `view == null`, `run_props` performs no awaits beyond mod
  calls themselves (assert via a frame counter — `process_frame` never elapses).
- **Schedules:** batch spawner emits all at tick 0; sequential (`batch 1, interval 1`)
  emits one per tick; `max_live = 2` with `remaining = 6` never exceeds 2 live and still
  delivers all 6 (movement overlaps emission).
- **Ballistic:** route of one slot → enters it one tick after spawn, `on_pass_card` +
  `on_finish`, one landing per tick in emission order.
- **Self-pass:** a knife-style prop scores its own origin slot (owner ruling); a probe
  effect reading `source` after the origin card is discarded doesn't crash.
- **Empty-route runaway:** a probe mod endlessly appending empty-slot route entries trips
  the cap (per-entry note_processing) or `MAX_TICKS`; the loop terminates.
- **3-phase pass:** ProbeStamp on a passed card hears `on_prop_passing` then
  `on_prop_passed` exactly once per prop; the prop's own ProbeMod fires between them; a
  second ProbeStamp elsewhere stays silent (targeted, not broadcast).
- **Dodge:** a card mod calling `negate_pass()` in phase 1 → phase 2 skipped (no score /
  status), phase 3 still fires with `pass_negated` set; the flag is clear again on the
  prop's NEXT pass.
- **Redirect (Strongman case):** a phase-1 mod that `set_route`s the prop onto the
  parallel row above → all subsequent passes happen in the new row; totals bank into the
  NEW row's gutter.
- **Teleport:** a mod teleporting a prop to another column/zone → the relocation is in the
  tick report, traversal continues from the new coord, event order stays deterministic on
  replay.
- **Spawner-card removal (the owner's edge case):** discard the source card after spawn →
  props keep traversing and their mods keep firing (origin coords captured).
- **Concurrent props:** hoop-kind and knife-kind over the same card in one tick → `hits`
  aggregates both.
- **Robustness:** empty slot mid-path skipped; a hook discarding a passed card mid-flight
  leaves `validate()` clean and later props see the slot empty; `act_overrun` cuts the
  loop.
- **Scoring seam:** `add_line_score` mutates totals + gutters headless (mirrors
  `test_score_line_headless_mutates_data`).
- **Determinism:** identical run twice from duplicated states → identical event logs.

---

## Phase 2 — Status-effect foundation (data)

Implements STATUS_EFFECTS_PLAN.md Steps 1–7 (that doc got its currency pass 2026-07-10).
Ball/Fire consume it in Phase 3.

**Files:** new `Cards/card_modifier_status.gd`, `Cards/card_data.gd`,
`Scripts/card_environment.gd`, `Scripts/game_data.gd` + `Scripts/run_manager.gd`
(backrefs), new `Tests/Engine/test_statuses.gd`.

```
@abstract class_name CardModifierStatus extends CardModifier
@export_storage var stacks := 1:
    set(v):
        stacks = v
        if stacks <= 0 and data: data.remove_status(self)
        elif data: data.data_changed.emit()
func can_merge_with(o: CardModifierStatus) -> bool: return get_script() == o.get_script()
func is_active() -> bool: return stacks > 0        # no rules-deck requirement
static func stacked(n: int) -> CardModifierStatus: <new() with stacks = n>
```
- `CardData`: replace the vestigial `statuses : Dictionary[String,int]` (card_data.gd:35)
  with `Array[CardModifierStatus]` + `add_status` (merge-by-class; defensively duplicate a
  status arriving with a foreign `data` — S7 trap) / `remove_status` / `with_status`;
  extend `_to_string()` with status strs + stacks.
- Dispatch: statuses join as a **snapshot** in `run_all_mods` (:37),
  `_compare_implementers` (:70-72), `return_first_data_array_result` (:85), **and
  `run_card_mods`** — four sites. Statuses self-guard targeted hooks
  (`if target != data: return`); they do NOT enter `skill_active_check`.
- Backrefs: `for st in card.statuses: st.data = ...` at the same four unlink/relink sites
  as Phase 0.4. Print-regression `status.data == card` after undo (C1).

**Data tests — `Tests/Engine/test_statuses.gd`:** the STATUS_EFFECTS_PLAN checklist —
merge stacking, heterogeneous coexistence, non-merge override, expiry at 0 (removal +
`data_changed`), self-scope guard, undo rebind, save round-trip via
`to_saveable()`/`restore_runtime()`, self-removal mid-pass doesn't skip other mods.

---

## Phase 3 — The five suits: spawner configs + prop mods (headless-complete feature)

**Files:** `Cards/Pips/Suits/*.gd` bodies, new `Cards/Props/Mods/prop_score_talents.gd`,
`prop_score_props.gd`, `prop_drop_status.gd`, `prop_bank_col_score.gd`, `prop_burning.gd`,
new `Cards/Statuses/status_juggling.gd`, `status_burning.gd`, new
`Tests/Engine/test_suit_props.gd`.

Shared spawn shape:

```
func spawn_props() -> Array[PropSpawner]:
    if data.skill: return []             # talent suppresses its own suit effect (locked)
    if not game: return []
    var v := game.find_data_vec3(data)
    if v == Vector3i.MIN: return []
    <build spawner(s); count = data.rank.value * fire_mult()>   # fire buff = COUNT only
```
Fire buff multiplies **count only** (v1 double-dipped count and points — dropped; one
knob). Constants: `HOOP_POINTS / KNIFE_POINTS / FIREWORK_POINTS := 1`, densities, caps —
all named, all tuning knobs. Burning spawners add `PropBurning` (sets `prop.fire_stacks`
for the flame-tip visual; future hook space) to every emitted prop.

### 3.1 Hoop — traveler, batch burst, talents jump & score

```
# spawner: origin = v; remaining = count; batch_size = count (ALL at once);
#          factory -> PropData{kind 0, ticks_per_slot HOOP_TICKS_PER_SLOT (=2..3, tune),
#                              route = game.row_slot_path(v, game.entity_side_for_row(v)),
#                              mods = [PropScoreTalents.new(HOOP_POINTS)] (+PropBurning)}
# The route includes the hoop's OWN slot (self-pass ruling) — harmless for hoops (origin
# is never a talent); for knives it means deliberate self-scoring (3.2).
class_name PropScoreTalents extends PropModifier
var points : int
func on_pass_card(prop, g: Game, card: CardData) -> void:
    if card.skill:      # talent PRESENCE (not .active — covered talents still count)
        var v := g.find_data_vec3(card)
        g.add_line_score(true, g.row_gutter(v), v.z, points)
func reaction_for(_prop, card) -> PropData.Reaction:
    return PropData.Reaction.JUMP if card.skill else PropData.Reaction.NONE
```

### 3.2 Knife — traveler, batch burst, opposite side, props score, talents spin

```
# spawner mirror: path side = not game.entity_side_for_row(v); mods = [PropScoreProps]
class_name PropScoreProps extends PropModifier      # scores NO-skill cards
func on_pass_card(prop, g, card): if not card.skill: <add_line_score row>
func reaction_for(_prop, card): return SPIN if card.skill else NONE
```
Hoop + knife over one talent in the same tick → the view composes JUMP+SPIN (different
tween properties; Phase 4).

### 3.3 Ball — ballistic, sequential, mancala targets, juggling status

```
# spawner: remaining = count; batch_size = 1; interval = 1 (one drop lands per tick);
#   targets = game.mancala_targets(v, count, func(c): return c.skill != null)  # PURE, at spawn
#   factory(i) -> PropData{kind 2, route = [targets[i]], mods = [PropDropStatus.new(StatusJuggling)]}
class_name PropDropStatus extends PropModifier
var status_script : Script
func on_pass_card(prop, _g, card) -> void:
    card.add_status(status_script.stacked(1))       # arrival == the drop
func reaction_for(_prop, _card): return JUGGLE      # (BURN for fire)
```
```
class_name StatusJuggling extends CardModifierStatus
func get_str(): return "Juggling"
func get_description(): return "When scored: +%d column score (balls juggled)." % stacks
func on_score(target: CardData) -> void:            # heard via the on_score broadcast
    if target != data: return
    var v := game.find_data_vec3(data)
    game.add_line_score(false, game.state.scores_col, v.y, stacks)
```
Correctness anchor: the brief's worked example `t,,b5,t,t` (b5 = rank-5 Ball at index 2) —
`mancala_targets` yields indexes 3,4,0,3,4 (skips the prop at 1 and b5 itself: no skill) →
final stacks `t1,,b5,t2,t2`. A Phase 3 test asserts this exact sequence and the
one-per-tick landing order.

### 3.4 Fire — ballistic like Ball; eligibility skips talents AND Fire suits

```
# eligible = func(c): return c.skill == null and not (c.suit is PipSuitFire)
# drops StatusBurning; reaction BURN
class_name StatusBurning extends CardModifierStatus
func get_str(): return "Burning"
func get_description(): return "This card's suit effect is boosted by %d." % stacks
# no hooks: read by PipSuit.fire_stacks()/fire_mult() at spawn time
```
**Same-act cascade is intended (owner ruling):** rows score before columns, so Burning
applied by a row meld already buffs those cards' suits when their columns score later in
the same submit — fire placement and scoring order are a deliberate lever.

### 3.5 Firework — traveler (column rise), banks col score at the edge

```
# spawner: remaining = count; batch_size = 1; interval = 1 (staggered rockets);
#   factory -> PropData{kind 4, route = game.column_rise_path(v),  # may be EMPTY -> banks
#                       mods = [PropBankColScore.new(v.y, FIREWORK_POINTS)]}   # immediately
class_name PropBankColScore extends PropModifier
var col : int; var points : int
func on_finish(prop, g: Game) -> void:
    g.add_line_score(false, g.state.scores_col, col, points)
```
Cards it rises past still hear `on_prop_passed` (free extension point). Firework is
outside `PipSuit.STANDARD` → never rolled randomly.

### 3.6 Data tests — `Tests/Engine/test_suit_props.gd`

Real suits, hand-built board, `view == null`:
- **Hoop:** rank-3 + 2 talents in row → row gutter += 3×2×HOOP_POINTS; non-talents
  unscored; either side gives the same total; batch stages all 3 at once.
- **Knife:** mirror on props; a row scoring both a hoop and a knife card banks both from
  opposite sides (`entity_side_for_row` opposition asserted).
- **Suppression:** a talented suit card spawns nothing.
- **Ball:** the worked example verbatim (targets, per-tick landing order, final stacks);
  no eligible talent → zero statuses, loop terminates.
- **Fire:** mixed column — Fire suits and talents skipped, props gain Burning; a Burning
  rank-2 Hoop spawns 2×(1+stacks) hoops (count buff only).
- **Firework:** rank-N → col gutter += N×FIREWORK_POINTS even with nothing above the card.
- **Per-meld double fire:** row+col membership → two spawns.
- **Spawner-card removal:** discard the hoop card mid-flight → remaining hoops still score
  talents (prop mods are self-contained).
- **`on_score` broadcast:** SkillExtraPoint on a scored card fires; Juggling pays col
  score when its card scores.
- Extend `test_game_headless.gd`: `submit()` on a suit-laden board completes headless,
  `validate()` clean.

---

## Phase 4 — Visual layer: PropLayer, PropVisual, spawn/staging anims, reaction state machine

**Files:** new `UI/prop_layer.gd` (+node under `SmoothScrollContainer/TopLevelVBox` in
`play_area.tscn`, `unique_name_in_owner` on), new `Cards/Props/prop_visual.gd` +
`hoop/knife/ball/fire/firework_visual.gd`, `UI/play_area.gd` (expose `prop_layer`),
`Levels/game_view.gd` (seam method), `Cards/card_visual.gd` (`anim_spin`).

### 4.1 Placement (v2 rationale, still valid) + generality requirements

PropLayer lives inside the scrolled content (`SmoothScrollContainer/TopLevelVBox`) so prop
local coordinates are scroll-invariant — the scroll transform moves cards and props
together, no per-frame tracking, mid-flight scrolling just works; container layout ignores
Node2D children. Verify edge clipping; widen margins/disable clip if staged trains pop.

Positioning must be **fully general from day one** (the async movement model means a prop
can be anywhere): `slot_point` accepts any `Vector3i` in the **upper or lower zone**
(`v.x` selects the zone containers), and `travel_to` interpolates arbitrary
displacements — horizontal (rows), **vertical** (Firework rise, Strongman push to the row
above), and diagonal (post-teleport continuation) are all the same linear tween between
two content-local points. Nothing in the view assumes row-only travel.

### 4.2 PropLayer — the per-tick processor

```
class_name PropLayer extends Node2D
const PROP_TICK_FRACTION := 0.12       # tick seconds = game.get_delay() * this — read LIVE
signal tick_done                        # all visuals reached their targets AND spawns landed
var _visuals : Dictionary = {}         # PropData -> PropVisual (each holds from/target + t)
var _reacting : Dictionary = {}        # CardData -> {jumping: bool, spinning: bool, ...}

## The tick duration is re-derived EVERY FRAME — changing the global animation speed scale
## (or compression kicking in) retimes props already mid-slot. Nothing locks in at start.
func current_tick_seconds() -> float: return game.get_delay() * PROP_TICK_FRACTION

## Per-frame interpolation drive (replaces per-tick tweens — durations must never lock in):
func _process(delta: float) -> void:
    var secs := current_tick_seconds()
    var all_done := true
    for vis in _visuals.values():
        vis.t += delta / secs if secs > 0.0 else 1.0    # secs == 0 -> snap (compression floor)
        vis.position = vis.travel_curve(vis.from, vis.target, min(vis.t, 1.0))
        if vis.t < 1.0: all_done = false
    if _tick_active and all_done:
        _tick_active = false
        tick_done.emit()            # floor: a visual tick is never shorter than one frame

## Start ONE data tick's animation and return immediately — Game runs the events phase in
## parallel and awaits `tick_done` afterwards (see §1.3 SYNC).
func begin_prop_tick(live, spawned, movers, relocated) -> Signal:
    play_area.flush_rebuild()
    for p in spawned:                    # pop out of the origin card to the staged spot
        _make_visual(p, at: slot_point(spawner origin)).retarget(staged_point(p))
    for entry in relocated:              # teleports: blink/flash at the new point,
        _visuals[entry.prop].relocate_to(prop_point(entry.prop))   # NEVER lerp across
    for p in movers:
        _visuals[p].retarget(slot_point(p.at))    # from = current pos; t = 0
    for p in live where p.done:
        _visuals[p].retarget(void_point(p))       # one slot past the edge; fade on arrival
    _update_reactions(live, movers)
    _tick_active = true
    return tick_done

## quanta->pixels via countdown: a mid-slot prop sits countdown/ticks_per_slot of the
## inter-slot distance behind its target — but position is OWNED by the interpolation
## drive above; this is only needed for staged trains (countdown > ticks_per_slot) whose
## offsets extend past the entry edge (huge trains run off-screen, accepted).
func staged_point(p: PropData) -> Vector2: ...
## Content-local point of ANY board slot, either zone (v.x picks the containers):
## occupied slot -> that card control's center; empty slot -> x from the column header
## control (always exists), y from an occupied control in the same row (fallback: header
## y + row offset). Direction-agnostic: rows, columns, diagonals all interpolate the same.
func slot_point(coord: Vector3i) -> Vector2: ...
## One extrapolated slot past the board edge, along the prop's last travel direction —
## "into the void" (negative/overflow slot positions are legal here); fade + free there.
func void_point(p: PropData) -> Vector2: ...

## Composite card reactions AT ARRIVAL (owner ruling): computed from pure hints (prop kind
## + card.skill) the moment a mover's visual reaches its card — frame-synced with landing,
## independent of the mods running in parallel (dodge alters data, never the animation).
## A card raises while ANY Jump-hinting prop is over it, spins while ANY Spin-hinting one
## is — both compose (offset vs rotation); set empties -> anim_reset. Skills wanting
## custom reactions use the on_prop_passed data hook instead.
func _update_reactions(live, movers) -> void:
    <per card: union of p.reactions_for(card) for props whose `at` is that card; diff
     against _reacting; rising edge -> anim_jump / anim_spin (fired when the visual's t
     crosses 1, i.e. on landing); empty -> anim_reset; JUGGLE/BURN one-shots hand off to
     the status visual>
```
`GameView` gains the seam method (extend its doc-comment contract list):
```
func begin_prop_tick(live, spawned, movers, relocated) -> Signal:
    return play_area.prop_layer.begin_prop_tick(live, spawned, movers, relocated)
```

### 4.3 PropVisual + subclasses

```
class_name PropVisual extends Node2D    # draw params only; NO CardData/PropData retention
## Expected art dimensions in pixels — PLACEHOLDER art draws to exactly this rect, and all
## spacing/staging math (train offsets, void extrapolation, arc heights) reads it, so real
## art later swaps in by matching the same footprint. No textures in v1.
@export var art_size : Vector2 = Vector2(16, 16)
var fire_tips := 0
var from : Vector2; var target : Vector2; var t := 1.0   # owned by PropLayer._process
func retarget(point): from = position; target = point; t = 0.0
## Shape of the interpolation, NOT its timing (timing = PropLayer's live per-frame drive):
func travel_curve(a, b, t) -> Vector2: return a.lerp(b, t)   # Ball/Fire: arc; Firework: rise
func relocate_to(point): <instant reposition + blink/flash effect (teleport events)>
func _draw(): <PLACEHOLDER: kind-colored primitive (ring / blade / circle / flame / rocket)
               sized to art_size; base overlays fire_tips flame ticks>
```
Subclasses: Hoop/Knife/Ball/Fire/Firework — placeholder `_draw` + `travel_curve` shape +
their own `art_size` defaults; `kind` picks the class. Spawn pops use the same `t` drive
(a spawn is just `retarget(staged_point)` from the origin card's center) so they can never
desync `tick_done`.

### 4.4 Card reactions

`CardVisual.anim_spin()` — rotation tween mirroring `anim_jump` (:342), returns duration;
different property → composes with jump. Rising-edge/held-pose logic lives entirely in
`PropLayer._update_reactions` (4.2), driven by tick occupancy.

**Verify Phase 4** (user runs): rank-3 Hoop + talent → burst of 3 staged hoops, synced
train, talent rises while the train passes and resets after; hoop+knife same tick →
jump+spin together; Ball/Fire pop out one per tick and arc to targets; scroll mid-flight →
props ride the board; huge count → staging runs off-screen, movement starts while
emission continues; headless test rerun → identical final state.

---

## Phase 5 — Status visuals + pip/status tooltips

**Files:** `Cards/card_visual.gd`, `UI/control_card.gd`, `UI/play_area.gd`.

- **Status visual v1** (STATUS_EFFECTS_PLAN Step 6): one extra `Polygon2D` "Status" slot +
  stack-count `Label`, updated in `update_visual()`. Juggling draws `stacks` looping
  balls; Burning draws `stacks` flame tips.
- **Tooltips:** `ControlCard.describe_card` (control_card.gd:36) already prints
  `suit.get_str()` — append `suit.get_description()` + one line per status
  (`"%s ×%d — %s"`).
- **Pip hover:** transparent `Control` over the Suit pip, `tooltip_text =
  suit.get_description()`; same per status icon. Must also surface on keyboard/controller
  focus ([[solatro-multimodal-input]]) — reuse the focused-card describe path.

---

## Phase 6 — Doc updates (at execution of each phase)

- **DESIGN_DOC.md §10:** the locked decisions — nominal suit subclasses, factory
  switching, per-meld firing, Firework special, Knife kept, fire count-buff, mancala rule,
  prop architecture (PropModifier composition, tick/density/spawner model, ballistic
  Ball/Fire, reaction aggregation), determinism rule.
- **ARCHITECTURE_REVIEW.md:** `PipSuit` is a CardModifier reached ONLY via `run_card_mods`
  + `spawn_props`; ordinal `compare_suits` removed (settles B7, D8's suit scaffolding);
  `on_score`/`on_after_score` broadcast wired; suit+status back-cycles in the four
  unlink/relink sites; the prop simulation (`run_props`) in the data layer + `PropLayer`
  in the view; compression + cap.
- **STATUS_EFFECTS_PLAN.md:** mark Steps 1–7 implemented (Phase 2); statuses also hear
  `on_prop_passed`.
- (The 2026-07-10 currency pass on both docs — split landed, dispatch renumbering,
  B11-fixed C1 — was applied alongside this plan revision.)

---

## Scalability contract

A **new prop behavior** = one `PropModifier` (hooks + reaction hint). A **new
prop-spawning suit** = one `PipSuit` subclass (`spawn_props` returning configured
spawners + mod lists), optionally one `PropVisual` (draw/trajectory), one `PALETTE`
entry. A **new status** = one `CardModifierStatus` subclass (heard by `run_all_mods`
broadcasts AND `run_card_mods` prop passes). Zero engine edits in all three cases — the
tick loop, spawner scheduling, dispatch, scoring seam, pacing, compression, and test
harness stay closed.

Dry-runs: **Confetti** = `PropScoreTalents` with an always-true predicate (generalize to
`PropScoreMatching(predicate, points)` if a third filter appears — flagged, not v1);
**Trampoline** = a PropModifier whose `on_finish` re-runs `_run_score_effects` for one
card; **a prop that burns cards it passes** = `PropDropStatus` on a traveler;
**Strongman** (card skill) = `on_prop_passing(prop): prop.set_route(game.
row_slot_path_from(<row above>, dir))` — pushes touching props up a row; **Teleporter**
(card skill) = `on_prop_passing(prop): prop.teleport(dest, new_route)`; **Dodger** (card
skill/status) = `on_prop_passing(prop): prop.negate_pass()`. All expressible today with
zero engine edits — that is what the mutable-route + 3-phase-pass design buys.

Guard rails: props mutate only via `add_line_score` / `card.add_status` (documented on
PropModifier); suits are dispatched ONLY via `run_card_mods` + `spawn_props`; every new
hook gets a signature line in the hook docs (D1 minimum).

---

## Suggested future prop-suits (design only — NOT in this plan)

Trampoline (re-score the card above), Cannon (fire the card itself to another column),
Tightrope (row-chain bonus for clean runs), Plate-spin (status paying if re-scored before
it "falls"), Whip (yank farthest same-rank adjacent), Confetti (weak hoop buffing every
card it passes), Trapeze (swap two talents on score), Magician's Rings (chain to the next
Ring-suited card, score the linked set). Knife re-theme was offered; owner keeps Knife.

---

## Execution order & risk notes

1. **Phase 0** — nothing compiles without it; includes the test-factory fix (0.6).
2. **Phase 2** — statuses (pure data, own tests); lets `fire_stacks()` land ungated.
3. **Phase 1** — prop engine + phase wiring + compression; `test_prop_engine` green with
   probe props before any suit body exists.
4. **Phase 3** — suit spawners + prop mods + `test_suit_props`; feature COMPLETE headless.
5. **Phase 4** — visuals (first visible payoff). 6. **Phase 5** — tooltips/status visuals.
7. **Phase 6** — docs.

Risks / verify-in-engine:
- **Tick-loop bookkeeping** (staging offsets, boundary-crossing iteration, live-cap
  refill) is the fiddliest data code — it is exactly what `test_prop_engine` pins down
  first.
- **Hook order** = spawner/emission/tick order — documented; add priorities only when a
  real effect needs them (YAGNI).
- **Hooks that move/discard cards** mid-tick stay formally deferred (B10 caveat); the
  engine tolerates vanished cards, but don't author such effects yet.
- **Feel knobs** (`HOOP_TICKS_PER_SLOT`, `PROP_TICK_FRACTION`, per-suit `max_live`, batch
  sizes, per-kind `art_size`) are named constants/exports to tune in-engine; the
  data/visual sync contract means retuning never desyncs them.
- **Mid-tick speed changes are visual-only by construction** (data ticks are unitless);
  the zero-duration snap in `_process` keeps full compression from stalling the loop;
  floor = one frame per visual tick (intended slideshow-instant behavior).
- **Prop-phase hooks must stay await-light** — events run in parallel with the animation
  and a slow mod extends the tick; documented on the hook contract, revisit only if a real
  effect needs pacing.
- **`source`-reading effects** (future) must handle an off-board origin — documented on
  PropData.
- **Reaction state machine** edge cases (train end vs `anim_reset`, jump+spin release
  order) — visual-only, iterate by eye.
- **Empty-slot `slot_point`** fallback and staged-train clipping — verify with ragged
  columns and huge counts.
- **Savegame**: nothing new persists (props transient; statuses/suits ride existing
  Resource paths) — but the four backref sites are load-bearing; test with real cards
  ([[solatro-tres-cyclic-backrefs]]).
- Testing/execution follows [[running-godot-scenes]] (prints; the USER runs), 
  [[godot-editor-disk-sync]] (re-read disk before diagnosing), [[no-git-staging]]
  (edits only, no commits).

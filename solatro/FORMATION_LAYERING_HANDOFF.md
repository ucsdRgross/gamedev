# Handoff — formation authoring, prop layering, geometry & test speed (next fixes)

**Status:** IMPLEMENTED and OWNER-VERIFIED 2026-07-16 (all four tasks + rounds 2–4 of playtest
feedback below; tests green, layering confirmed fixed in playtest). What landed:
- **TASK 1:** `all_tests.gd` `@export speed_base_delay` (default 0.01, near-instant) published to
  `TestLog.speed_base_delay` in `_enter_tree`; UI PROPS / VISUAL LAYERS / INTERACTION read it
  (per-suite `FAST_DELAY` consts deleted). Sampling tests keep their own absolute slow delays.
- **TASK 2:** spread_by_separation points now STORED in full-card normalized space
  (`PropFormationSet.strip_ratio/norm_to_strip/strip_to_norm` replace `stretched_y`);
  `offsets_for` projects with `norm_to_strip`. The formation editor edits/draws in the CURRENT
  strip and converts on push/pull (`_to_stored`/`_to_strip`); changing `stack_separation`
  re-projects live (`_pull_points`, guarded so scene load can't wipe unsaved points; `_syncing`
  guard keeps the spread toggle from clobbering stored points during a pull). No shipped
  Formations/*.tres existed, so no migration was needed.
- **TASK 3:** `PlayArea.slot_center_global` is PURE MATH (zone hbox origin + column/row pitch +
  card anchor; no `control_for_coord`/rect reads); hoops (kind 0) are skipped in
  `_assign_formation_offsets` so their lane_offset is always ZERO = the card center.
- **TASK 4:** the bracket card is chosen from pure GEOMETRY (`PropLayer._bracket_card_for`,
  rev 2 2026-07-16 after owner playtest): the card whose footprint contains the ring's center
  (nearest center among fanned overlaps); ring straddling a column gap → the lowest-child-index
  touched card so the BACK arc stays behind every card the ring touches; over nothing → unsplit.
  Covers mid-leg, cross-row reroutes, and exits. (Rev 1's "unsplit while between cards" gate drew
  the back arc in front of cards mid-gap — reverted.)

**Round 2 (owner playtest feedback, fixed 2026-07-16):**
- Formation offsets are now derived from LIVE settings every frame
  (`PropLayer._live_lane_offset`/`_refresh_lane_offset`; `PropFormationSet.assignment_for`
  returns stored points + spread flag) — changing card separation or card scale mid-flight
  re-projects immediately like the cards; spread clamps at exactly one card height.
- Prop ART scales with card_scale: `vis.scale = card_scale / PropVisual.AUTHORED_CARD_SCALE`
  (2.5 = authored default), written per frame for live + exiting visuals (poof tweens own scale).
  Formation editor preview applies the same rule; its `preview_scale` default is 2.5 and
  `column_pitch` default = card width + 4 (PlayArea.separation's unscaled default) for parity.
- `play_area.gd order_card_visual` clamps its move_child target (crash "Invalid new child index
  36" during settings changes — CardLayer also hosts half nodes/deferred removals).
- New tests: `test_ui_props.test_formation_live_rescale` (settings changed while a prop is
  airborne — the blind spot that hid the capture-at-spawn bug), and the multi-column hoop test
  now asserts mid-gap back-behind-both and row-change re-bracketing.

**Round 3 (owner feedback, 2026-07-16): row-wide layering + settings migration.**
- CardLayer order is now ROW-MAJOR across columns per zone (`play_area._order_board_cards`,
  replacing `order_card_visual`/`_card_order_index`): headers, then row 0 of every column, then
  row 1, … Cards only overlap within a column, so rendering is unchanged for cards — but rows
  are contiguous, so a split prop brackets the WHOLE ROW (`PropLayer._apply_split`/`_row_bounds`):
  back half in the inter-row gap before the row (behind every card in the row, above earlier
  rows), front half after it (in front of the whole row, below later rows). Mid-gap rings now
  read correctly: back behind both, front in front of both. Ordering is index-safe BY
  CONSTRUCTION now (targets assigned 0,1,2,… only to verified, deduped current children), not
  just clamped.
- Speed-up knobs migrated to PlayerSettings with editor descriptions on every field, read live.

**Round 4 (owner feedback, 2026-07-16):**
- Compression reworked to PER-ACTIVATION (owner: elapsed-time made a slow first prop phase
  inflate `elapsed`, then everything lurched to insane speed): multiplier =
  `compress_ratio ^ (act_calls / compress_step_calls)`, instant past `compress_soft_calls` —
  `act_calls` is the same note_processing counter `act_event_cap` trips on. NO ms values remain
  (`act_start_ms` deleted). Defaults step=50 / soft=2000 activations are FIRST GUESSES — tune.
- The row-major ordering pass now re-queues itself once behind deferred add_childs
  (`play_area._deferred_reorder`): fresh visuals enter the tree call_deferred in COLUMN-major
  creation order, and nothing guaranteed a later rebuild — this stale order was the cause of the
  11 VISUAL LAYERS failures AND the owner-seen "back arc behind the row above at an
  empty-column row" (row bounds computed over scattered column-major indices).
- Bracket-row selection REWRITTEN (final design, owner 2026-07-16): geometric row guessing is
  GONE — fanned cards are a full card tall behind their visible strip, so "which card contains
  the ring's center" picked a SHORT column's top card when the ring crossed its empty row (back
  arc behind the zone header / wrong rows; tests missed it because every test column had a card
  in the ring's row — `test_hoop_short_column_row_hold` covers it now on a [3,1,3] board). The
  bracket row = the prop's ANCHOR SLOT row (`vis.anchor_coord`); geometry only decides WHETHER
  to split: the prop's authored body rect (`PropVisual.body_size`, hardcoded per kind like
  CARD_SIZE — placeholders mirror art_size) must overlap some card footprint
  (`PropLayer._body_over_any_card`). Width-aware, so a ring between two cards is "over" both.
- All remaining animation flourishes promoted to PlayerSettings as FRACTIONS of get_delay (so
  they respect pacing + compression, never wall-clock): `prop_fade_fraction`,
  `prop_poof_fraction`, `prop_flash_fraction`, `card_jump_raise/pulse/settle_fraction`
  (were 0.15 / 0.12 / 0.15 / .4 / .3 / .2 literals in prop_layer / prop_visual / card_visual).
- **Tests:** `test_visual_layers.test_hoop_split_multi_column` (3×3 grid, separations 0.5/1/2:
  center-threading, bracket vs every same-column card, no cross-column overlap, mid-leg unsplit);
  `test_ui_props.test_formation_separation_agnostic` (ratio-1 reference, round trip, same stored
  points at every separation, strip-fraction projection); `test_slot_geometry` extended to verify
  the math against built controls at separations 0.5/1/2.

Original brief follows.
Written 2026-07-15. Companion docs: `LAYERING.md` (structural draw order), `PROPS_BUGFIX_HANDOFF.md`
(prop simulation reference), `ARCHITECTURE_REVIEW.md` §1.6.

Four independent tasks below. Read the "Current state" of each before changing anything, and keep
the project rules: type every `Array`/`for` element; no `git add`/commit; UI strings via
`TRANSLATION.find`; don't run headless Godot while the owner's editor is open (add prints, hand
off); re-read files from disk first.

---

## TASK 1 — Test run speed: near-instant, editor-tunable factor

**Goal:** make the suite run near-instant by default, with an **editor-side tool-modifiable factor**
(like `all_tests.gd`'s existing `@export terminal_output` / `close_when_done`), instead of the
hardcoded `FAST_DELAY := 0.05` per suite.

**Current state:**
- `Tests/all_tests.gd` already has `@export` fields (`terminal_output`, `close_when_done`) and
  configures shared state in `_enter_tree()` (runs before any child `_ready`). This is the model
  for a new export.
- Speed is set PER SUITE today: `Tests/UI/test_ui_props.gd:29` `const FAST_DELAY := 0.05`, applied
  at `:43-44` (`SettingsManager.settings.base_delay = FAST_DELAY`) and restored `:63`. Same in
  `Tests/UI/test_visual_layers.gd:33,47-48,61`. `base_delay` is the master timing knob
  (`Scripts/player_settings.gd:6`); prop tick seconds = `game.get_delay()*prop_tick_fraction`,
  read live every frame (`UI/prop_layer.gd current_tick_seconds`).
- **Watch out:** several tests DELIBERATELY slow down to sample mid-flight motion and would break at
  near-instant: `test_ui_props.gd:386` sets `base_delay = 0.4` (test_slow_props), `:~490` `0.3`
  (test_row_prop_never_leaves_its_row), `:~554` `0.3` (test_each_kind_moves_as_expected). These
  need many frames per leg; they must keep their own slower local delay OR opt out of the global
  factor. Also `WATCHDOG_SECS := 10.0` caps awaited coroutines.

**Suggested approach:**
- Add `@export var speed_factor : float = 1.0` (or a "near-instant" default like a very small
  `base_delay`) on `all_tests.gd`. Store it where suites can read it — a `static var` on `TestLog`
  (already a shared static, configured in `all_tests._enter_tree`) is the cleanest, e.g.
  `TestLog.speed_base_delay`. Suites replace `FAST_DELAY` with `TestLog.speed_base_delay`.
- The deliberately-slow sampling tests should NOT read the global; they set an absolute local delay
  as today (they need real frames). Alternatively give them a "min frames per leg" and derive delay.
- Verify: the whole suite still passes (the sampling tests especially — don't let near-instant make
  `delta/span > 1` overshoot their assertions). Owner runs `all_tests.tscn`.

---

## TASK 2 — Formation editor: separation-AGNOSTIC point placement

**Goal (owner's words):** *"point placing is completely agnostic to whatever default or current
separation is. Assume ratio 1 if separation size is same as card height. Placing points at any set
separation level automatically respects scalable separation, such that placed points will
automatically scale when I change separation again. It will make no difference if separation is
maxed out or scaled to min."*

**Interpretation:** points must be stored in a **separation-independent normalized space** and only
projected into the current visible strip for editing/preview. The invariant: authoring the SAME
visual pattern at any separation level stores the SAME normalized points, and changing separation
afterward re-projects them automatically. "Ratio 1 when separation == card height" defines the
normalization: the reference frame is the FULL card (separation == `CARD_SIZE.y`), so a point placed
when the visible strip already equals the full card is stored 1:1; a point placed in a smaller strip
is stored scaled UP into full-card space (so it fills the same fraction of the strip regardless of
strip size).

**Current state (differs — must change):**
- `Cards/Props/formation_data.gd`: `points : PackedVector2Array` (unscaled card space, center
  origin), `mode` (ORDERED/RANDOM), `spread_by_separation : bool`.
- `Cards/Props/formation_set.gd`:
  - `offsets_for(count, seed, separation_factor)` applies `stretched_y(y, factor)` when
    `spread_by_separation` is on.
  - `static func stretched_y(y, factor)` currently anchors at the card TOP and scales
    distance-from-top by `clampf(factor, 0, CARD_SIZE.y/CARD_SEPARATION)`. `factor` =
    `card_separation_scale` (game) or `stack_separation/CARD_SEPARATION` (editor).
  - **This is a display/consume-time stretch of points stored in strip space.** The new model
    inverts it: store points in FULL-CARD (ratio-1) space, and the editor EDITS them projected into
    the current strip. So the editor must convert screen/edit positions → normalized on input and
    normalized → strip on draw. `offsets_for` then only needs to map normalized → current strip
    using the live factor (which it already sort of does, but the stored representation flips).
- `Cards/Props/Tools/formation_editor.gd`: authoring tool. Key bits:
  - `points` export (edited in inspector), pushed/pulled to the formation (`_push_points`,
    `_pull_points`).
  - `stack_separation` (setter → `_live_update`), `spread_by_separation` (setter), preview via
    `_spawn_preview` (uses `offsets_for(n, seed, stack_separation/CARD_SEPARATION)`), scenery in
    `_draw` (draws fanned card rects by `stack_separation`, and the editable points on column 0).
  - `preview_scale` stands in for `card_scale`; `CARD := CardVisual.CARD_SIZE`.

**Suggested approach:**
- Decide the STORED space = full-card normalized (ratio 1 at separation == card height). Add a
  conversion pair, e.g. `strip_to_norm(y, factor)` / `norm_to_strip(y, factor)` on
  `PropFormationSet` (factor = current separation / card height, or / CARD_SEPARATION — pick ONE
  reference and document it). `offsets_for` uses `norm_to_strip` with the live factor.
- Formation editor edits in the CURRENT strip: when the user drags a point at separation S, convert
  the visible position to normalized before storing (`strip_to_norm`), and draw stored points via
  `norm_to_strip` at S. Then changing S re-projects automatically (the store didn't change).
- Anchor: keep the card TOP as the anchor (owner: spread grows downward from the visible top strip).
- Verify in-editor: place points at separation A, change to separation B — points visually occupy
  the same fraction of the (now different) strip; the stored `.tres` is unchanged. Max separation
  (== card height) shows points 1:1; min separation squeezes them into the top sliver.
- Keep `offsets_for` deterministic/seeded (batch replay) — only the y projection changes.

---

## TASK 3 — Hoop always card-center; row centers via pure math (no controls)

**Goal (owner):** *"hoop will always be card center since it won't respect separation. Row centers
should be calculated with only math and no reference to existing controls."*

### 3a. Hoop ignores separation → sits at card center
- The hoop must NOT take a separation-scaled formation offset; it should sit at the card's CENTER
  regardless of separation. Options: give the hoop kind no formation (or a single center point with
  `spread_by_separation` OFF), OR special-case kind 0 so `lane_offset` stays ZERO / centered.
- Where offsets are applied: `UI/prop_layer.gd _assign_formation_offsets` (`:349`) sets
  `vis.lane_offset`; it's added to every slot point in `begin_prop_tick` (`:262,281,287`). "Card
  center" = the slot point itself (slot_center_global already targets the card anchor center — see
  3b). So hoop = slot point + ZERO lane_offset.

### 3b. Row/slot centers from math only (no control lookups)
- **Current:** `UI/play_area.gd slot_center_global(v)` (`:213`) reads
  `control_for_coord(v)` (`:199`, walks the HBox/VBox tree) and uses `control.global_position` /
  `control.size`; the empty-slot fallback (`:222+`) uses the column HEADER control plus a computed
  pitch (`card_separation_play_custom + separation`). `PropLayer._slot_point` (`:404`) →
  `to_local(slot_center_global(coord))`, and `_repin` (`:206`) chases it every frame. Cards
  themselves anchor via `CardVisual.get_card_control_center(control)` (reads control).
- **Wanted:** compute slot centers purely from board math — zone origin + column index * column
  pitch + row index * row pitch + card anchor — with NO `control_for_coord` / `control.*` reads, so
  geometry is deterministic and independent of container relayout timing. This also removes the
  `_repin`-chasing-settling-controls behavior that made the earlier landing tests timing-flaky.
- **Gotchas / why controls were used originally (don't regress these):**
  - Columns can have different row counts; the LAST control in a column is full card height while
    row strips are `card_separation_play_custom` tall — the fan overlap. Pure math must reproduce
    the same row line (see the long comment at `play_area.gd:222-238` documenting header-top vs
    header-bottom and the diagonal-knife/invisible-hoop bugs from getting this wrong).
  - Empty edge columns: a completely empty column's header inflates to a full card; math must keep
    empty-column row-0 ON the same row line as occupied neighbors (there are dedicated tests:
    `test_ui_props.gd test_slot_geometry`, and the row-hold checks).
  - The board rides `SmoothScrollContainer`; slot math must be in the same content-local space props
    use (`PropLayer.to_local`). Scroll offset + zone container origins still need a reference point —
    decide whether "pure math" derives from a single known origin node (e.g. a zone container's
    global_position once) or fully from layout constants.
  - `separation` (PlayArea.separation) and `CardVisual.card_separation_play_custom` /
    `card_size_play` are the pitch inputs; `card_separation_play_custom` already folds in
    `card_separation_scale`.
- **Verify:** `test_ui_props.gd` slot-geometry + row-hold tests still pass; props hold their row
  through relayouts (score labels widening, focus resize) — the live cases `_repin` was built for.

---

## TASK 4 — Prop layering STILL looks wrong (needs more diagnosis)

**Symptom (owner, latest):** hoop pass-through layering still looks wrong in playtest even after the
"split only while over a card" fix. Earlier report: *"some hoops fully in front of bottom row cards,
including back half; not consistent among all hoops."* That specific case (halves floating on top
off-card) was addressed, but layering is still off — root cause not fully found.

**Current implementation (post-fix):**
- `Cards/Props/prop_visual.gd`: split prop has `back_node`/`front_node` (`_PropHalf` Node2D) and
  `_split_active` (set by PropLayer). `_draw()` draws the whole body when `not _split_active`
  (or non-split / editor); draws only fire-tips when split. `_draw_back(into)`/`_draw_front(into)`
  draw the two arcs onto the passed half node.
- `UI/prop_layer.gd _update_back_halves()`:
  - For each live prop over a mapped card → `_apply_split(vis, cvis)`: `set_split_active(true)`,
    ensure both half nodes exist + parented to `%CardLayer`, then GUARDED `move_child` the BACK to
    `cvis.get_index()-1` and FRONT to `cvis.get_index()+1` (stable bracket).
  - Off-card (and for `_exiting` props) → `_apply_split(vis, null)`: `set_split_active(false)`.
  - Then a mirror pass over ALL PropVisual children copies transform/scale/modulate onto both halves
    and sets `half.visible = _split_active and vis.visible` (single fade source).
  - `_free_visual` frees both halves with the prop.
- Occupancy uses `game.find_vec3_data(prop.at)` (data-side slot) → `play_area.data_card[card]`.

**Hypotheses to investigate (not yet confirmed):**
1. **Cross-column / same-row ambiguity:** the bracket is only relative to the ONE occupied
   CardVisual's child index. Other cards (different columns, or the row-below in a DIFFERENT column)
   have unrelated indices, so a hoop over card A can still render in front of / behind an unrelated
   overlapping card B. If hoops visually overlap neighbors, bracketing one card isn't enough — may
   need the front/back placed relative to the specific neighbors it overlaps, or a per-column scheme.
2. **Card center vs strip position:** props currently target `slot_center_global` (card anchor,
   top+half-card) while cards are drawn fanned; if the hoop sits at the strip position but the
   "occupied" card's visual center is elsewhere, the ring won't straddle the card cleanly. TASK 3
   (hoop at card center, math row centers) likely interacts — fix 3 first, then re-check 4.
3. **Occupancy vs visual interpolation:** `prop.at` is the discrete data slot; the visual
   interpolates between slots. Mid-leg the ring is between two cards but `_split_active` brackets the
   destination card — the ring may bracket the wrong card for part of the leg.
4. **`move_child` index vs the continuous row-major counter:** cards from upper+lower zones share
   one continuous CardLayer order (`play_area.order_card_visual`); a hoop's bracket assumes the
   occupied card's neighbors in CHILD order equal its visual neighbors — true within a column, but
   across zones/columns the child-order neighbor may not be the visual neighbor.
5. **Re-entrancy with board rebuilds:** `order_card_visual` re-orders cards on rebuild; half nodes
   are re-fixed next frame, but a rebuild mid-animation could show a 1-frame wrong order.

**Recommended next step:** reproduce in `test_visual_layers.gd` with a MULTI-COLUMN board (not just
the single stacked column `make_stack_game`) and a hoop sweeping a row that has cards above AND below
in several columns; dump `collect_draw_order` at each step and assert the ring's halves vs EVERY
overlapping card, not just the one occupied card. The current test only covers a single column, which
is why it passes while playtest fails (same blind spot that hid the off-card bug).

---

## Key files (quick index)

| Concern | File | Notes |
|---|---|---|
| Prop split draw | `Cards/Props/prop_visual.gd` | `_split_active`, `_draw`, `_draw_back/_draw_front`, `_PropHalf` |
| Hoop arcs | `Cards/Props/Visuals/hoop_visual.gd` | `RING_*`/`SPLIT_*`, `_draw_body` full ring for editor |
| Bracket + mirror | `UI/prop_layer.gd` | `_update_back_halves`, `_apply_split`, `_mirror_half`, `_free_visual`, `_assign_formation_offsets` (`:349`) |
| Slot geometry | `UI/play_area.gd` | `slot_center_global` (`:213`), `control_for_coord` (`:199`); TASK 3 makes these math-only |
| Card order | `UI/play_area.gd` | `order_card_visual`, `_card_order_index` (continuous across zones) |
| Formation data | `Cards/Props/formation_data.gd` | `points`, `mode`, `spread_by_separation` |
| Formation math | `Cards/Props/formation_set.gd` | `offsets_for`, `stretched_y` (TASK 2 inverts storage) |
| Formation editor | `Cards/Props/Tools/formation_editor.gd` | edit/preview; `stack_separation`, `_live_update`, `_spawn_preview` |
| Test speed | `Tests/all_tests.gd` (`@export`, `_enter_tree`), `Tests/UI/test_ui_props.gd` (`FAST_DELAY`), `Tests/UI/test_visual_layers.gd` | TASK 1 |
| Test log/ordering | `Tests/Support/test_base.gd` | `TestSuite`, `await_siblings_except` + DEADLOCK RULE, `TestLog` (`Tests/Support/test_log.gd`) |
| Settings knobs | `Scripts/player_settings.gd` | `base_delay`, `card_scale`, `card_separation_scale`, `prop_tick_fraction` |

## Suggested order
Do **TASK 3** (hoop center + math row centers) first — it likely unblocks **TASK 4** (layering) and
removes the geometry flakiness. **TASK 2** (formation normalized storage) is independent. **TASK 1**
(test speed) is independent and small. Re-run `all_tests.tscn` after each (owner runs scenes).

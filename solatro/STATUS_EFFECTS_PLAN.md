# Status Effects — Implementation Plan

Goal: each card can carry any number of *status effects* — self-affecting, stackable,
heterogeneous — stored on `CardData` as an array. Statuses are a fourth kind of
`CardModifier` (alongside skill / type / stamp), so they plug into the existing
`run_all_mods` hook system with no new dispatch machinery.

Design decisions locked in by this plan:
- **Merge-by-class stacking**: two statuses of the same class merge into one object with
  `stacks += n` (overridable for statuses that want independent instances).
- **Self-scope by guard convention**: statuses hear every event but open every hook with
  `if target != data: return` — same pattern every existing mod uses.
- **Always active**: unlike skills, statuses don't need the rules deck; `is_active()` is
  overridden to `stacks > 0`.

**Update 2026-07-10:** this plan is now Phase 2 of the suit-modifier plan
(`task-plan-out-adding-precious-mochi.md`), whose first consumers are `StatusJuggling` /
`StatusBurning`. Two deltas from the text below: (1) dispatch has since become
instance-based and the comparator walk moved into a cached `_compare_implementers` — see
the corrected site list in Step 3; (2) statuses also hear the new targeted per-card hook
`on_entity_passed(entity)` (fired via `run_card_mods` when a board entity passes over
their card).

---

## Step 1 — Base class `Cards/card_modifier_status.gd`

```gdscript
@abstract class_name CardModifierStatus
extends CardModifier

const STATUS_TEXTURE : Texture2D = preload("res://Assets/status_pips.png") # TODO: asset
const H_FRAMES: int = 8
const V_FRAMES: int = 8

@export_storage var stacks : int = 1:
    set(value):
        stacks = value
        on_stacks_changed()
        if data: data.data_changed.emit()

## Statuses of the same class merge instead of coexisting.
## Override to return false for statuses that want independent instances.
func can_merge_with(other: CardModifierStatus) -> bool:
    return get_script() == other.get_script()

## Hook for reacting to stack changes (e.g. expire at 0).
func on_stacks_changed() -> void:
    if stacks <= 0 and data:
        data.remove_status(self)

## Statuses work anywhere on their own card — no rules-deck requirement.
func is_active() -> bool:
    return stacks > 0

func set_texture(polygon2d: Polygon2D) -> void:
    update_polygon_uv_frame(polygon2d, STATUS_TEXTURE, H_FRAMES, V_FRAMES, get_frame())
```

Notes:
- Mirrors `CardModifierStamp`/`Type`/`Skill` exactly (texture consts + set_texture).
- `is_active()` override matters: the base `CardModifier.is_active()` requires the card to
  be in the rules deck or carry StampGlobal/StampRevealing — wrong semantics for statuses.

## Step 2 — CardData changes ([card_data.gd](Cards/card_data.gd))

Replace the vestigial `@export var statuses : Dictionary[String,int]` (line 35) with:

```gdscript
@export var statuses : Array[CardModifierStatus] = []

func add_status(status: CardModifierStatus) -> void:
    for existing in statuses:
        if existing.can_merge_with(status):
            existing.stacks += status.stacks   # setter emits data_changed
            return
    statuses.append(status.with_data(self))
    data_changed.emit()

func remove_status(status: CardModifierStatus) -> void:
    statuses.erase(status)
    data_changed.emit()

func with_status(status: CardModifierStatus) -> CardData:  # builder, matches with_skill etc.
    add_status(status)
    return self
```

Also extend `_to_string()` to append status strs + stack counts (debugging via
`GameData.print_board` depends on it).

Migration: grep for uses of the old `statuses` dictionary first; if it is truly unused
(audit found no readers), delete it outright — same name reuse is intentional.

## Step 3 — Dispatch ([card_environment.gd](Scripts/card_environment.gd))

In **all four** dispatch sites (dispatch is instance-based since 2026-07-02) —
`run_all_mods` (~line 37), `_compare_implementers` (~line 70; it feeds
`return_first_compare_mod_result`, which no longer walks cards itself),
`return_first_data_array_result` (~line 85), and the targeted `run_card_mods` (added by the
suit-modifier plan) — replace the fixed `[data.type, data.stamp]` inner list with a snapshot
that includes statuses:

```gdscript
var mods : Array[CardModifier] = [data.type, data.stamp]
mods.append_array(data.statuses)   # copies — safe if a status removes itself mid-hook
for mod : CardModifier in mods:
    if mod and mod.has_method(function):
        ...
```

Statuses do NOT go through `skill_active_check` (that machinery manages `skill.active`
transitions and on_active/on_deactive; statuses are unconditionally live while present).
If a status needs enter/leave behavior, do it in `add_status`/`remove_status` via a
dedicated `on_applied()` / `on_removed()` pair called from those two functions.

## Step 4 — Self-scope convention

A status implementing a targeted hook must guard, exactly like existing mods
(`SkillExtraPoint.on_score`, `TypeInput.on_can_place_stack`):

```gdscript
func on_score(target: CardData) -> void:
    if target != data: return
    # ...affect only this card
```

Hooks with no target (`on_next`, `on_after_score`, `on_game_start/end`) are inherently
per-card since the status only lives on one card.

## Step 5 — Example statuses (validate the design with these three)

```gdscript
# Decays each turn; heterogeneous-stack test partner for any second status.
class_name StatusBurning extends CardModifierStatus
func get_str() -> String: return "Burning"
func get_description() -> String: return "Loses 1 stack each Next; -stacks to score"
func get_frame() -> int: return 0
func on_next() -> void: stacks -= 1        # setter handles expiry at 0
```

```gdscript
# One-shot consumed on score — tests removal during a scoring pass.
class_name StatusCharged extends CardModifierStatus
func get_str() -> String: return "Charged"
func get_description() -> String: return "Next score with this card is doubled, then consumed"
func get_frame() -> int: return 1
func on_score(target: CardData) -> void:
    if target != data: return
    # ...apply bonus...
    stacks -= 1
```

```gdscript
# Non-merging — tests can_merge_with override.
class_name StatusSeal extends CardModifierStatus
func can_merge_with(_other: CardModifierStatus) -> bool: return false
```

## Step 6 — Visuals ([card_visual.gd](Cards/card_visual.gd))

The current pattern (one `Polygon2D` per mod slot: Type/Rank/Stamp/Suit/Art) doesn't
extend to a variable-count list.

- **v1 (ship first):** one additional `Polygon2D` "Status" + a small `Label` for count.
  Show `statuses[0]`'s frame and, if `statuses.size() > 1` or `stacks > 1`, the total.
  Update inside `update_visual()` (already connected to `data_changed`).
- **v2:** a small `HBoxContainer`/manual row of status icons along the card edge,
  rebuilt on `data_changed`; tooltip per icon from `get_description()` + stack count.

## Step 7 — Persistence

Mostly free: `@export`/`@export_storage` on an `Array[CardModifierStatus]` of Resources
serializes through the run save (`RunManager` → `user://run_save/run.tres`) the same way
skill/type/stamp already do — EXCEPT the `data` back-cycle, which must join the
unlink/relink lists (see C1 below). Verify `return_to_map` keeps statuses (it keeps the
CardData objects, so yes) and decide per-status whether it should survive the show — add an
optional `func persists_between_games() -> bool: return true` and strip non-persistent ones
in `Game.return_to_map`.

---

## CAVEATS — pre-existing issues this feature collides with

These are from ARCHITECTURE_REVIEW.md; both get *worse* once statuses exist.

### C1. Undo back-reference corruption (review item B11) — RESOLVED upstream, one task left

**B11 was fixed 2026-07-01:** `GameData.duplicate_state()` now uses
`Resource.duplicate_deep(DEEP_DUPLICATE_ALL)`, which remaps ALL cross-references — including
each status's `.data` backref and mod-internal card refs (`ZoneAdder.card_data`,
`SkillEchoingTrigger.triggered`, `SkillHungryHippo.consumed_cards`). No manual rebind pass
is needed for undo copies.

**What this feature still owes:** the *serialization* cycle. `card → status → data` is a
self-cycle ResourceSaver can't write, exactly like skill/type/stamp — add
`for st in card.statuses: st.data = ...` to all FOUR unlink/relink sites:
`GameData.unlink_modifier_backrefs` / `relink_modifier_backrefs` (game_data.gd) and
`RunManager._to_saveable_cards` / `_relink_cards` (run_manager.gd). And keep the undo
regression test (`status.data == its card` after undo) — cheap insurance on the
duplicate_deep behavior.

### C2. Mutation during dispatch (review item B10)

`run_all_mods` iterates live collections; statuses removing themselves mid-hook
(`StatusBurning` at 0 stacks) is a new mutation source. Two rules keep it safe:

1. The per-card inner mod list must be a snapshot — the `append_array` copy in Step 3
   provides this. Never iterate `data.statuses` directly inside dispatch.
2. `remove_status` only mutates the card's own array, not the zone/deck arrays the
   `CardDataIterator` indexes — so it cannot break the outer walk. But a status that
   moves/discards its own card mid-hook CAN (same as existing mods). Until B10 is fixed
   globally, statuses must not call `move_data_*`/`discard_data` from inside hooks that
   were themselves dispatched by `run_all_mods` — defer via a queued action instead.

### C3. Shared-instance trap (review item S7)

`ModsList` holds singleton mod instances. If statuses ever get a registry like it, or if
booster/shop code hands the *same* status instance to `add_status` on two cards, both
cards share one `stacks`/`data`. Rule: **always `duplicate()` (or `.new()`) a status at the
point of application**; consider making `add_status` defensively duplicate non-fresh
resources (`if status.data != null and status.data != self: status = status.duplicate()`).

### C4. Dispatch cost (review items E1/E2)

Every card now contributes `2 + statuses.size()` `has_method` probes per event, and
`run_all_mods` already re-runs `on_anything` + `skill_active_check` per hook. Statuses make
the multiplier bigger. Acceptable at current board sizes, but do E1 (snapshot card list,
single `skill_active_check` per event) when status counts grow.

### C5. Hook contract is stringly-typed (review item D1)

A typo'd hook name in a status class silently never fires. When adding the status hooks
(`on_applied`, `on_removed`, `on_stacks_changed`), add them to the documented hook list —
and if review D1 (central `HOOKS` registry) lands, register them there.

---

## Test checklist

- [ ] Same-class stacking: apply Burning ×2 then Burning ×1 → one entry, stacks == 3.
- [ ] Heterogeneous: Burning + Charged coexist as two entries.
- [ ] Non-merge override: two Seals → two entries.
- [ ] Expiry: Burning with 1 stack → press Next → status gone, `data_changed` fired, visual updates.
- [ ] Self-scope: two cards, one Charged; scoring the other card does not consume the charge.
- [ ] Undo: apply status → undo → status gone; gain stack → undo → previous stack count;
      AND after undo, status `.data == its card` (C1 regression test).
- [ ] Save/load round-trip via PlayerSave keeps statuses + stacks.
- [ ] Status removing itself during a scoring pass doesn't skip other mods (C2).

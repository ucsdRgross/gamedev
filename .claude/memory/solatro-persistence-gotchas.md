---
name: solatro-persistence-gotchas
description: "RunManager save gotchas — ResourceSaver picks format by extension, has_save gates on run.tres only, pending_action replay"
metadata: 
  node_type: memory
  type: project
  originSessionId: 5115d529-7a34-4e4a-8708-46ec3ae1e3c5
---

Solatro run persistence (`RunManager`/`RunState`/`GameData`) hard-won facts:

- **`ResourceSaver.save` picks its format from the file EXTENSION.** The atomic temp file
  must end in `.tres` (`run.tmp.tres`), NOT `.tres.tmp` — the latter returns
  `ERR_FILE_UNRECOGNIZED` (15) and silently writes nothing. This was the bug that left no
  `run.tres`, made `has_save()` false, and disabled the Continue button.

- **`has_save()` gates on `run.tres` ALONE**, not the `map/` bake. The map bake
  (`composite.png` etc.) is a deterministic cache of `world_seed`; `WorldMapController
  .start_run` rebakes it when missing. Deleting `run_save/map/` is safe — it regenerates on
  the next Continue. `RunManager.clear_save()` wipes the whole `map/` dir, so tests that call
  it can destroy a real run's map cache; the persistence tests skip when a real `run.tres`
  exists and the fuzz test deletes only its own `run.tres` (never `clear_save`).

- **BigNumber scores** persist as parallel typed packed arrays on `GameData`
  (`packed_*_mant : PackedFloat64Array` / `packed_*_exp : PackedInt64Array`), synced by
  `pack_scores`/`unpack_scores`. Packed arrays are copy-on-write — assign built arrays back
  to the fields, don't mutate a parameter. (Replaced an older Dictionary-of-`[m,e]`-pairs.)

- **Interrupted async board actions replay on resume.** Submit/Next persist
  `RunState.pending_action` (the mod event name) with the pre-action board before awaiting;
  `Game._resume_show` replays it with input locked so a mid-scoring quit can't rewind. Relies
  on those actions being deterministic. `save_state` clears the marker on commit.
  - The replay must FIRST await the board being visually ready
    (`Game._await_board_ready` loops until `play_area.visuals_ready()`).
    `CardVisual.add_child_card_visual` adds visuals via `call_deferred("add_child")`, so on a
    freshly rebuilt board their `@onready var offset` is null; scoring animations
    (`popup_meld`→`anim_jump`) tween `offset` and error ("rp_target null") if you replay too
    early. `anim_jump/anim_reset` also guard `if not offset`.

- **Card listing lives in `CardsViewer` (composition).** DeckViewer, ChoiceViewer,
  MapHoverPanel each CONTAIN a `CardsViewer` (`res://UI/cards_viewer.gd`, a RefCounted bound to
  one container) and call `.populate(cards, on_inspect)` / `.clear()` — the single listing path
  (loop + optional hover/focus inspector). NOT inheritance: the viewers' scene roots differ
  (CanvasLayer / Control / PanelContainer) so they can't share a base, and ControlCard stays
  singular (one card). All populate synchronously — the no-fly-in guarantee is CardVisual's
  (context-based), not per-viewer `call_deferred` timing.
- **Board-ready is a signal, not a poll.** `PlayArea.board_visuals_ready` fires after a
  rebuild's deferred CardVisual add_childs land (a `call_deferred` emit queued FIFO after them).
  Resume does check-then-await: `if not play_area.visuals_ready(): await board_visuals_ready`.

- **CardVisual positioning + flip are per-`current_context`, not per-instance flags.**
  `_process` only *eases* toward the anchor (`exp()`) for `PLAY_AREA` (slot moves + the
  intended fly-in from the deck pile seeded in `_ready`); every other context (DECK_VIEWER
  for deck viewer / pack ChoiceViewer / map hover preview, MAP, PREVIEW) tracks its anchor
  exactly, so no card ever flies in from the origin. Flip-in likewise: only a
  PLAY_AREA card with `previous_stage == DRAW` keeps the default face-down `basis3d` and slerps
  to front; everything else — non-draw board cards AND every viewer card (even DRAW-stage ones
  shown in the deck viewer) — snaps `basis3d` to its resting face (`data.flipped`) in `_ready`
  so it spawns showing the correct face. (Condition is PLAY_AREA AND DRAW, not just DRAW.)
  (Earlier I used a `_needs_initial_snap` bool for the fly-in — bad: instance state that only
  existed for parent layout timing. Branch on the context the node already owns instead.)
  - `CardVisual.update_visual()` must `await ready` at the TOP, before choosing the
    front/placeholder branch. It's called from the `data` setter before the node is in-tree
    (via `add_child_card_visual`'s `instantiate().with_data()`), so it suspends; if it decides
    the branch first and awaits inside the else branch, that early call resumes into the stale
    placeholder branch and clobbers a face set during `_ready` (the instant-face snap). The
    front appearing normally is driven by the floating slerp flipping `show_front` false→true
    (`basis3d` setter → `show_front` setter → `update_visual`); the resting face is
    `Basis.looking_at(Vector3(0,0,-3.5 * (-1 if flipped else 1)))`.

- **Per-act score gutters reset in `apply_act_score`.** The `scores_row_*/scores_col`
  BigNumber gutters accumulate via `plus_equals` during an act; `apply_act_score` must
  `.clear()` all three (alongside `row_total/col_total`) or the next act stacks onto them.
  The gutter LABELS only resync via `PlayArea.update_score_controls()` (called from
  `Game._perform_submit` and on resume) — the normal rebuild path (revision bump →
  `set_card_zones`) does NOT touch them, so a resumed show needs an explicit
  `update_score_controls()` to show persisted scores. `Game._load_board_visuals` does the
  full resume sync (cards + gutters) and prints `[resume] …` confirmations.

- **Save size**: ~34 KB per committed snapshot (72-card board, text `.tres`); `run.tres`
  grows ~34 KB per action since every snapshot re-stores all cards. Cap undo depth if it
  balloons.

See [[solatro-tres-cyclic-backrefs]], [[solatro-project-facts]], [[running-godot-scenes]].

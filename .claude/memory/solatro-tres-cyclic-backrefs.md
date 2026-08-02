---
name: solatro-tres-cyclic-backrefs
description: "CardModifier.data is a WeakRef property since 2026-07-18 (no cycles, no unlink discipline); relink after every duplicate_deep; saves carry no backref"
metadata: 
  node_type: memory
  type: project
  originSessionId: 1777a13a-9a84-4d8c-b5c0-c68f53f14cb2
  modified: 2026-07-30T21:58:55.149Z
---

**REWORKED 2026-07-18:** `CardModifier.data` is now a WeakRef-backed property (`_data_ref : WeakRef`, non-exported) — the card<->modifier RefCounted cycle no longer exists and the whole unlink-at-drop-site discipline was DELETED. Two rules survive: (1) `duplicate_deep` does NOT remap a WeakRef — every deep-copy site must call `GameData.relink_card_backrefs` on the copies (duplicate_state, Game.add_deck, RunManager.new_run, deck_builder do); (2) saves still carry no backref (`to_saveable`/`_to_saveable_cards` null it; loads relink). Debug builds run the `LeakSentinel` autoload (alive-vs-reachable card census, knobs in player_settings.gd). Historical context: Godot's .tres writer fails on cyclic sub-resource graphs ("Resource was not pre cached"), which is why backrefs were manually unlinked around saves before the weakref rework.

**Why:** RunState saves crashed the moment a real deck (cards with skills/types/stamps) was saved; unit tests missed it because they used a bare CardData.

**How to apply (post-rework):** do NOT reintroduce manual unlink/relink around saves — the WeakRef made that unnecessary and it was deleted. Do call `GameData.relink_card_backrefs` on the output of every `duplicate_deep`, and always test serialization with fully-populated cards (skills/types/stamps), never bare stubs — a stub is what hid the original crash, see [[no-mocks-in-tools]]. ZoneAdder.card_data is a plain forward ref (no cycle) — leave it.

**Update (run persistence, session 2026-07):** `GameData.to_saveable()`/`restore_runtime()` encapsulate this (unlink + pack scores → immutable snapshot; relink + unpack → runtime). `BigNumber` is RefCounted (not serialized) — GameData keeps runtime `Array[BigNumber]` un-exported and an `@export_storage scores_packed` of `[[mantissa,exponent]]` pairs. RunState persists the FULL undo history (`game_history: Array[GameData]` of saveable snapshots) so closing can't rewind (anti-cheat) and undo survives quit. RunManager saves on a background `Thread` (coalesced, temp-file+rename, flushed in `_exit_tree`); payload is built independent on the main thread (deck cache via `mark_deck_dirty`, immutable history entries shallow-copied). Related: [[solatro-multimodal-input]].

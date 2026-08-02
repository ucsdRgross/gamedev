---
name: solatro-tuning-knobs-in-settings
description: "Shared/adjustable tuning knobs in Solatro live in Scripts/player_settings.gd, not as scattered consts"
metadata: 
  node_type: memory
  type: feedback
  originSessionId: 9142ade9-f98d-4441-8895-a93351149aea
---

In Solatro, an **adjustable knob used by more than one part of the code — especially anything that
tunes animation speed/timing — belongs in `Scripts/player_settings.gd`** (`PlayerSettings extends
Resource`), not as a local `const` in whatever file happens to use it. Read it at runtime via
`SettingsManager.settings.<field>` (e.g. `SettingsManager.settings.base_delay`,
`.card_scale`). Each field is an `@export var` with a setter that emits `settings_changed`, so
listeners re-read live.

The "speedup settings" (base_delay and the prop/compression timing) are the canonical example —
keep them consolidated there. Done 2026-07-16: PlayerSettings now holds `compress_ratio`/
`compress_step_calls`/`compress_min_factor`/`compress_soft_calls`/`act_event_cap` plus flourish
fractions (`prop_fade/poof/flash_fraction`, `card_jump_raise/pulse/settle_fraction`). Every
settings field carries a `##` editor description (owner expects that on new fields).

Two hard rules the owner stated 2026-07-16: **no wall-clock (ms) pacing anywhere** — the act
speed-up compresses per ACTIVATION (`Game.act_calls`, the note_processing counter), never per
elapsed time (elapsed-time made speed lurch unpredictably); and **every animation derives its
duration from get_delay()** (a fraction of it), never a fixed seconds literal, so nothing can
outlive the pacing.

**Why:** these are player-/designer-tunable and read live every frame across systems; centralizing
them makes them editable in one place and keeps `settings_changed` refresh working. A buried const
can't be tuned without a code edit and won't emit the refresh signal.

**How to apply:** before adding a `const` for a timing/pacing/scale value, check whether it's a
tuning knob shared across systems — if so, add it to `player_settings.gd` and read
`SettingsManager.settings.<field>`. A truly file-local, non-tunable constant can stay a const.
Related: [[solatro-project-facts]], [[gdscript-type-all-arrays]].

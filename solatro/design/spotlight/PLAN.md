# SPOTLIGHT — IMPLEMENTATION PLAN

**Status: ready to execute. Design CONFIRMED 2026-08-03** (owner: *"i gave a look over the new charts
and they should be fine when combined with the questions and answers for creating execution plan"*).

Unlike `DESIGN.md`, **this document carries code-level contracts on purpose**: schemas, signatures,
uniform names, per-step done-when, and self-checking acceptance gates. A plan that names a file
without specifying it guarantees two incompatible inventions of the same thing.

⚠ **§1 IS ALSO WHERE BOTH OF PHASE 1'S GAPS WERE, and neither was in `DESIGN.md`.** The design was
reviewed and confirmed by the owner; §1's contracts were written afterwards and never were. §1.4
shipped a default (`false`) that inverted a confirmed flowchart, and §1.5's one-line shorthand was
read as contradicting §1.3. **If a normative contract here disagrees with the design, the design is
right and this document is wrong** — that is not a tie to be broken by whichever is more specific.
Corrections folded in 2026-08-04 are marked v7.

---

## Design provenance and gap protocol — COPY THIS BLOCK INTO ANYTHING DERIVED FROM THIS DOCUMENT

Derived from: `solatro/design/spotlight/DESIGN.md`, version 6, confirmed 2026-08-03. Every step below
cites the design node IDs it implements.

If you are executing this and you reach a decision the design does not cover:
1. Reversible and clearly within intent → do it, and append one line to `ASSUMPTIONS.md` citing the
   node you were working on. Never silently.
2. Otherwise — two defensible choices differ in observable behaviour, or the choice is expensive to
   reverse, or it is an owner call (balance, look, scope) → **park that thread, file a gap, keep
   working on unaffected threads, and tell the owner.**
3. The design contradicts itself or the code → always a gap, highest priority.

File gaps at `solatro/design/spotlight/gaps/GAP-NNN.md` using the template in
`solatro/design/spotlight/DESIGN.md` §20. Write the options in the questionnaire grammar; they become
the next round's questions unchanged.

Do not resolve a gap by picking an answer. Do not proceed on the parked thread. Do not delete a gap
— it is closed by a new design version.

This block, unchanged, goes into every document derived from this one.

---

## 0. What ships, in what order

| Phase | What | Verifiable by | Effort |
|---|---|---|---|
| **1** | The mechanical spotlight — rename, the block seam, forced spotlight, scoring **sections**, re-evaluation, compact-and-follow | **Headless. Hard gates, no pixels.** | lower, autonomous |
| **2** | The glow shader + the light layer (dim, circle, beam) | Snapshots + the owner's eye | higher, iterative |
| **3** | The reveal — derived row expansion, gutters, prop anchors | Snapshots + the owner's eye | higher, iterative |
| **4** | The tuning tool + reviewable snapshots | The tool itself | medium |
| **5** | The film-light pipeline | **A SEPARATE DELIVERABLE** — `Q239`=(a) ships it after Spotlight, against a finished picture. Do not start it here. | its own design |

⚠ **Phase 1 changes NO pixels and Phase 2 changes NO logic.** That split is deliberate: phase 1 is
fully gated by the headless suite, so it can run autonomously at lower effort; phases 2–3 need
iteration against a rendered frame and must not be attempted blind.

⚠ **`Q265`=(c) — the existing scoring animation does not change.** `CardVisual.anim_jump()`
(`Cards/card_visual.gd:576`) and `PlayArea.popup_meld` (`UI/play_area.gd:657`) keep working on
`result.meld` alone. The wider lit set is carried by the spotlight. **No step in this plan touches
either function.**

### The opening prompt for a fresh session

Paste this verbatim. It is self-contained.

```
Implement solatro/design/spotlight/PLAN.md, Phase 1 only (steps S1-S10). Stop at S10.

Read PLAN.md first, then solatro/HANDOFF_spotlight.md for status; they are self-contained.
solatro/design/spotlight/DESIGN.md is the authority on behaviour - where they disagree the
design wins and the plan is wrong.

Section 1 of the plan is NORMATIVE: ScoringSection's shape, the rename table, the
forced_spotlight state, the block seam signature, the activation sweep and the
compact-and-follow rules are specified, not suggested. Do not invent them.

Do S2 (the rename) FIRST - it is mechanical only while nothing new depends on the old names.
Dependencies for every other step are in PLAN.md section 0b.

Phase 1 changes NO pixels. If you find yourself editing a shader, a .tres or
CardVisual.anim_jump, you have left the phase - stop and re-read section 0.

Hard gates, self-checking, all must pass before you report done:
- G1.1 full suite green WINDOWED, errors log empty, SUITES count not lower than the
       baseline recorded in HANDOFF_spotlight.md
- G1.2 grep -rn "is_active|skill_active_check|on_active|on_deactive" --include=*.gd
       solatro/ returns nothing outside addons/
- G1.3 a run.tres written before the rename loads with the same spotlit set a fresh
       check would derive, and fires NO on_spotlight during the load
- G1.5 GameData.revision is unchanged across a whole submit
- G1.6 a skill whose on_spotlight discards a card in its own section terminates via
       act_event_cap rather than hanging - assert with a bounded watchdog
- G1.7 headless and windowed produce identical mod-fire logs for the same seed

Follow the gap protocol at the head of this plan: if you hit a decision the plan does not
cover, do not invent it - file a gap at solatro/design/spotlight/gaps/GAP-NNN.md and keep
working the unaffected steps. Q84 vs Q168 on dim_target is a known one.

Keep solatro/HANDOFF_spotlight.md updated after EVERY task - it is a status ledger only
(id / status / evidence / notes); everything else stays in PLAN.md.

Never run Godot while the owner's editor is open. No git add, no commits.
```

---

## 0b. Step order, dependencies, and where PROGRESS is tracked

⚠⚠ **DO NOT PUT CHECKBOXES ON THE `**Sn — …**` LINES.** Measured 2026-08-03: a `- [ ]` prefix does
not merely fail to parse — the step **disappears** and its `(implements …)` citations are silently
re-attributed to the previous step, so the gap protocol's stale-step report then names the wrong
steps. `designloop/src/gaps.mjs` `planSteps()` matches `**Sn — title**` at the start of a line, or a
bare `id: Sn` inside YAML. Nothing else.

**Progress lives in `solatro/HANDOFF_spotlight.md`, not here.** That file is this stream's live
journal — one YAML task per step, with `status`, `evidence` and `notes` — and `/handoff` owns it. It
uses the `id: Sn` form, which `planSteps()` also reads, so the stale-step report keeps working from
either document. **This plan is a specification and does not change as work proceeds**; a spec that
accumulates ticks stops being diffable.

### Dependencies — what actually blocks what

| Step | Blocked by | Touches |
|---|---|---|
| **S1** `ScoringSection` | — | `Scripts/scoring_section.gd` (new) |
| **S2** the rename | — (do it FIRST; every later step reads the new names) | 40 sites, 20 files |
| **S3** block seam | S2 | `Cards/card_modifier.gd` |
| **S4** forced state | S2 | `Scripts/game_data.gd`, `Cards/card_modifier.gd` |
| **S5** section phase | S1, S2, S4 | `Levels/game.gd`, `Scripts/card_environment.gd` |
| **S6** immediate mutation | S5 | `Levels/game.gd` |
| **S7** compact-and-follow | S6 | `Levels/game.gd` |
| **S8** re-evaluation | S5 | `Levels/game.gd` |
| **S9** release + headless parity | S5 | `Levels/game.gd` |
| **S10** cue seam | S2 | `Scripts/card_environment.gd` |
| **S11** `FxGlowStyle` | phase 1 green | `UI/Fx/fx_glow_style.gd`, 3 `.tres` |
| **S12** `glow.gdshader` | S11 | `Shaders/glow.gdshader` |
| **S13** light layer | S12 | `UI/`, `LAYERING.md` |
| **S14** origins + travel | S13 | light layer |
| **S15** cue visuals | S13, S10 | light layer |
| **S16** derived expansion | phase 1 green | `UI/play_area.gd` |
| **S17** gutters + anchors | S16 | `UI/play_area.gd` |
| **S18** the tool | S13, S16 | `UI/Fx/Tools/` |

**S1, S2 and S10 have no dependency on each other** and can be done in any order. **S3, S4** unblock
once S2 lands. **S7 is the only step that can hang** (§1.5's unbounded loop) — do it after S6 so the
re-derive it depends on is already tested.

⚠ **S2 FIRST, always.** Doing any other step before the rename means writing code against names that
are about to change, and the rename is mechanical only while nothing new depends on the old names.

---

## 1. NORMATIVE CONTRACTS

Everything in §1 is specified, not suggested. Do not invent an alternative shape for any of it.

### 1.1 The scoring SECTION — the abstraction that replaces "line"

`Q31`=(d), `Q260`=(a), `Q266`=(a), `Q27`: a section is **whatever card list one scorer invocation
evaluates together**. Nothing downstream may infer geometry from it.

```gdscript
## One scorer invocation's worth of cards. Rows and columns are the only shapes today; a future
## scorer may evaluate a diagonal, several rows at once, or an arbitrary set, and NOTHING that
## consumes this may assume otherwise (design Q260=a, Q266=a).
class_name ScoringSection
extends RefCounted

## Every card participating in the hand. THIS IS THE SPOTLIGHT SET (design Q31=d) — it is not
## derived from geometry and it is not `result.meld`.
var cards : Array[CardData] = []
## Opaque provenance, for logging and the tuning tool only. NEVER branched on for behaviour.
var origin : StringName = &""          # e.g. &"row", &"col"
var index : int = -1
var zone : Array = []
```

- `Game.score_line(result, is_row, zone, index)` (`Levels/game.gd:721`) keeps its signature for
  callers, and **builds a `ScoringSection` as its first act**. Everything spotlight-related consumes
  the section; nothing consumes `is_row`/`index` except `add_line_score`, which already does.
- ⚠ **`ScoringSection.cards` is re-read, never cached across a hook** — `Q252`=(b).

### 1.2 The rename: `active` → `spotlight` (`Q2`=b)

Exhaustive, and it is 40 call sites across 20 files (measured 2026-08-03). One mechanical pass:

| Was | Becomes |
|---|---|
| `CardModifier.is_active()` | `CardModifier.is_spotlit()` |
| `CardModifierSkill.active` (`@export_storage`) | `CardModifierSkill.spotlit` |
| `CardEnvironment.skill_active_check()` | `CardEnvironment.skill_spotlight_check()` |
| hook `&"on_active"` | `&"on_spotlight"` |
| hook `&"on_deactive"` | `&"on_unspotlight"` |

⚠ **`@export_storage var active` IS SAVED STATE.** Renaming the property renames the key in every
`run.tres`. **Step S2 carries a migration** — a save written before the rename loads with `spotlit`
absent, which defaults `false`, and `skill_spotlight_check()` then re-derives it on the first tick.
That is correct and needs no upgrade code, **but it must be asserted** (gate G1.3), because the
alternative is a silent board-wide re-activation storm on every existing save.

### 1.3 Forced spotlight — the state

`Q17`=(a) no revision bump, `Q18`=(a) does not survive undo, `Q16`=(c) the whole act, TRAVELLING.

```gdscript
# On GameData, per-act, NOT @export_storage (design Q18=a: undo rewinds it by not saving it).
var forced_spotlight : Dictionary[CardData, bool] = {}
```

- **Effective spotlight = `is_spotlit()` OR `forced_spotlight.has(data)`.** That one line is the
  whole mechanical change (design §2).
- Written only by `Game._spotlight_section()` / `_release_spotlight()`. Read only by
  `CardModifier.is_spotlit()`.
- ⚠ **It TRAVELS; it does not accumulate** (`Q16`=c, design D20, v7). It is never torn down
  between sections — that is what lets a light travel rather than strobe — while its MEMBERSHIP
  is whichever section is being scored: *"increases or **decreases** based on cards being scored"*.
  A section that has already scored is no longer force-spotlit. `_release_spotlight()` at the end
  of the act is the only place it empties.
- ⚠ **Never bump `GameData.revision` from it** (`Q17`=a) — a bump forces a board rebuild mid-cascade.

### 1.4 The block seam (`Q9`=a)

⚠ **CORRECTED 2026-08-04 (v7, GAP-001).** This section originally specified `return false`, which
under chart A8 would have made **every covered card on the board spotlit**. The default is `true`.

```gdscript
## Does this card HIDE the talents of whatever is stacked under it? Default `true` — a covering
## card is exactly what makes the card beneath dark. A Kuroko / Ghost Light modifier overrides it
## to `false`, unhiding the card beneath (design Q9=a, A8). Content that uses it is OUT of scope
## (Q185=a); ONE test implementation exists so the seam can be asserted at all.
func blocks_spotlight() -> bool:
    return true
```

- `CardModifier.is_spotlit()` **REPLACES** `Game.is_data_topmost()` with it — it does not consult
  it first. With every modifier blocking, "nothing above me" and "I am topmost" are the same
  statement, so the seam ships behaviour-neutral.
- **A card blocks unless ANY ONE of its modifiers opts out.** A single Kuroko stamp is enough; it
  does not have to convince its own card's type and suit to agree, or nothing could ever stop
  blocking.
- The walk stops at the first blocker — which, blocking being the default, is the card immediately
  above — so a covered card costs one comparison, not a column scan.
- A zone/type header is blocked by any card in its column, which is `is_data_topmost`'s header rule
  ("topmost exactly when its column is empty") restated.
- `StampRevealing` is **not** part of this seam: it is a property of the card ITSELF (chart A7) and
  is checked before it.
- ⚠ **A forced spotlight bypasses all of it** (`Q6`=a) — the beam is literally on the card.

### 1.5 The activation sweep

`Q25`=(b) immediate mutation · `Q252`=(b) re-derive after every hook · `Q201`=(b) **no per-section
cap**, only the existing act-level `act_event_cap`.

```
_spotlight_section(section):
    loop:
        note_processing()                       # or the act-level cap cannot see this loop
        forced_spotlight = section.cards        # D10 — REPLACES; the set travels (Q16=c)
        await skill_spotlight_check()           # fires on_spotlight for newly-spotlit cards
        if act_cancelled or act_overrun: return
        re-read section.cards from the board    # Q252=b — a hook may have mutated it
        if the set did not change: break
```

⚠ **This loop is unbounded by design.** `Q201`=(b) rejected a per-section cap; the act-level runaway
guard is the only bound. Gate G1.6 pins that a self-feeding chain terminates via that guard rather
than hanging.

### 1.6 Compact-and-follow (`Q24`=c, chart R, `Q198`–`Q206`)

A column is `ArrayCardData.datas`, a plain `Array` (`Levels/game.gd:613`). Erasing index `z` shifts
every higher `z` down by one **for free** — no code writes the slide.

| Rule | From |
|---|---|
| The card that was COVERING it takes the slot | `Q198`=a |
| Nothing to slide in (it was last) → the light retires | `Q199`=a |
| The light **does not move** — it is pinned to the SLOT | `Q200`=c |
| No cap on the follow chain | `Q201`=b |
| Cards below move up; nothing is skipped unless the discard was in an ALREADY-SCORED row | `Q202`=a |
| The reveal set is re-derived and re-tweened | `Q203`=a |
| The replacement fires `on_spotlight` even though it cannot change this score | `Q204`=a |
| Any card leaving a lit slot gets the same treatment, not just an `on_spotlight` discard | `Q205`=a |
| The light holds on the empty slot for one beat first | `Q206`=b |

### 1.7 Hand re-evaluation (`Q22`=b, `Q23`=a, `Q243`=a, `Q244`=a)

After the whole sweep settles and before `view.animate_meld`:

```
result = Scoring.PokerHands.score(section.cards)[0]   # ONCE (Q23=a)
if result is null or empty: the section scores NOTHING (Q244=a — no floor)
if result.meld != the previous meld: the lights and jumps RE-CUE (Q243=a)
```

### 1.8 `FxGlowStyle` — the shader's levers (phase 2)

A **subclass** of `FxStyle`, never knobs on the base (2026-07-31 ruling, `UI/Fx/fx_style.gd`).
Three `.tres`: `Shaders/Styles/glow_card.tres`, `glow_circle.tres`, `glow_beam.tres` — **no prop
style** (`Q221`).

| `@export` | Type | Default | From |
|---|---|---|---|
| `layers` | `int` 1–4 | 2 | `Q207` (2–4, owner tunes) |
| `layer_radius` | `PackedFloat32Array` | `[0.35, 1.0]` | `Q207` |
| `layer_gain` | `PackedFloat32Array` | `[1.0, 0.4]` | `Q207` |
| `inverse_square` | `float` 0–1 | 0.6 | `Q208`=a |
| `sink` | `float` | 4.0 | `Q209`=a |
| `reach` | `float` | 4.0 | `Q210` (owner: *"start with 4"*, tunable) |
| `glow_ramp` | `PaletteRamp` | — | `Q211`=a core→mid→edge |
| `grid` | `float` | finer than the art | `Q213`=d — **a knob spanning art-grid → screen resolution** |
| `dither` | `float` 0–1 | 1.0 | `Q214`=a |
| `inner_alpha` | `float` 0–1 | **0.35** | `Q216`=d — start low, tune against S15 |
| `circle_radius` | `float` (art units) | 16 | `Q85` |
| `circle_inner_alpha` | `float` 0–1 | 0.5 | `Q217`=a — its own knob |

⚠ **`brightness` and `opacity` stay on the `FxStyle` base** — that is where `fx_intensity` is folded
in, and it is the photosensitivity floor. ⚠ **Declare `u_brightness` in the shader**: `juggle.gdshader`
does not, which is why `fx_intensity` silently misses it (VFX.md §7.11). Do not repeat that.

⚠ **NO `glow_fade_fraction`.** `Q264`=(a): the glow snaps on and off. The knob is deleted, not zeroed.

### 1.9 `Shaders/glow.gdshader` — the uniform contract (phase 2)

One shader, two hosts (`QR9`=c). Mask kinds mirror `FxAttachment.Shape` exactly as
`fire.gdshader` does, plus one:

```glsl
const int MASK_OUTLINE = 0;   // the host's exact 24-vertex silhouette — Q124=b
const int MASK_SPRITE  = 1;
const int MASK_DISC    = 2;   // the spotlight circle — QR9=c, the cheap client
uniform int u_mask_kind = 0;
uniform int u_space = 0;      // 0 = host art space, 1 = light-layer screen space — Q229=a
```

- Reuse `fx_common.gdshaderinc` unchanged: `fx_local`, `fx_local_raw`, `fx_bayer`, `fx_hash21`.
- `u_time` is pushed by `FxAttachment`; **never GLSL `TIME`**.
- The over-art test uses the **unquantized** position (`fx_local_raw`), per `Q215`=(a) and the two
  seam bugs fire already paid for (`Shaders/fire.gdshader:687`).
- Blend: **additive outside the silhouette, tinted over the art** (`Q218`) — ⚠ *"(c) is fine if it
  doesnt lead to visible seam between additive and tinted parts, otherwise just tint, dont want
  blowout to white."* If the join seams, tint both. **This is an owner-visible call: show both.**

### 1.10 The light layer

One full-screen surface (`Q240`=b, `Q242`=a — the owner accepted that a beam crosses in front of
everything, props included; `Q102`'s original wording is withdrawn).

| Uniform | Meaning | From |
|---|---|---|
| `u_dim` | 0..1, **non-zero only while a BEAM is live** | `QR2`=d |
| `u_dim_scale` | shallower outside scoring | `Q245`=c |
| `u_lights[]` | per light: circle centre, radius, origin, widths, intensity | chart G |
| `u_light_count` | sized to the **widest board that fits on screen** — `Q107`: no cap | `Q107` |

- Coverage **accumulates** (`Q100`=a) and **clamps at 1** (`Q101`=a).
- Beam carries volumetric noise **from the start** (`Q98`=b), scrolling (`Q99`=a).
- Origins: content-anchored, `origin_rise` ~600 px **and tunable** (`Q114`), with a deterministic
  y scatter so no two share a y (`Q113`=d, `Q250`=a), and x **re-spreading every frame while the
  origin is above the viewport** (`Q251`=b, `Q262`=a) — pinned again once on screen (`Q164`).
- ⚠ **A beam never points upward** and only enters from the screen edge when the target is below the
  viewport bottom (`Q117`).

### 1.11 Tunables — `Scripts/player_settings.gd`

Every duration is a FRACTION of `Game.get_delay()` (`Q167`=a), never wall-clock.

```
spotlight_dim_in_fraction      0.5     spotlight_travel_fraction    0.5
spotlight_dim_out_fraction     0.5     spotlight_spawn_fraction     0.3
spotlight_reveal_fraction      0.4     spotlight_retire_fraction    0.3
spotlight_hold_fraction        0.5     spotlight_slot_hold_fraction 0.3   (Q206=b)
spotlight_expand_rows_scoring_row / _col     (Q46 — FOUR booleans, not two)
spotlight_skip_row_if_no_reactor_row / _col  (Q46)
dim_target  (player setting, Q84=b → style only… ⚠ see G0 below)
```

⚠ **`Q84`=(b) put `dim_target` on the style resource, not in settings.** `Q168`=(a) says
`dim_target` and `fx_intensity` are player settings. **These two answers conflict.** Resolve by the
later, more specific answer — `Q84`=(b), style-only — and **file a gap if that reading is wrong**;
do not split the difference.

---

## 2. PHASE 1 — the mechanical spotlight (headless)

**S1 — `ScoringSection`** (implements D3, Q31, Q260, Q266)
Create `Scripts/scoring_section.gd` exactly as §1.1. No behaviour yet.
**Done when:** it compiles and `Tests/` has a unit constructing one from a row and from a column.

**S2 — the rename** (implements A1, A2, B14, Q2)
Mechanical pass per §1.2 across all 40 sites. ⚠ Do NOT touch `addons/worldgen/` — its `active` is
unrelated (verified: `biome_assign.gd`, `graph_*.gd`).
**Done when:** `grep -rn "is_active\|skill_active_check\|on_active\|on_deactive" --include=*.gd .`
returns only `addons/`.

**S3 — the block seam** (implements A8, Q9, Q6)
Add `CardModifier.blocks_spotlight()` per §1.4; consult it in `is_spotlit()` before
`is_data_topmost()`.
**Done when:** a test card overriding it to `true` suppresses the spotlight of the card beneath, and
a **forced** spotlight ignores it.

**S4 — forced spotlight state** (implements D10, Q17, Q18)
Add `GameData.forced_spotlight` per §1.3 and fold it into `is_spotlit()`.
**Done when:** setting it makes `is_spotlit()` true for a buried card, `GameData.revision` is
unchanged, and an undo clears it.

**S5 — the section spotlight phase** (implements D3–D13, Q37, Q13, Q15)
`Game._spotlight_section(section)` per §1.5, called from `score_line` after the section is built.
**Done when:** every card in the section fires `on_spotlight` exactly once per transition; a card
already spotlit fires nothing (`Q13`, `Q15`).

**S6 — immediate mutation + re-derive** (implements D12b, Q25, Q252, Q201)
The loop of §1.5.
**Done when:** a hook that adds a card to the section causes that card to activate in the same phase.

**S7 — compact-and-follow** (implements R1, R2, R3, R4, R5, R6, R7, R8, R9, R10, R11, R12, R13, R14, R15, R16, Q24, Q198, Q199, Q200, Q201, Q202, Q203, Q204, Q205, Q206)
Per §1.6. ⚠ The slide itself is free; implement only the **light re-pin** and the **re-derive**.
**Done when:** discarding a mid-column meld card leaves the column compacted, the covering card in
the slot, spotlit, and activated.

**S8 — hand re-evaluation** (implements D13b, Q22, Q23, Q243, Q244)
Per §1.7.
**Done when:** a hook that breaks the meld produces the re-evaluated score, including zero.

**S9 — release and headless parity** (implements D22, D23, Q14, Q19)
Clear `forced_spotlight` at the end of the act; re-run the check so a still-naturally-spotlit card
does **not** fire `on_unspotlight` (`Q14`=a). `view == null` must behave identically with no waits.
**Done when:** the headless and windowed runs produce the same mod-fire log.

**S10 — the momentary cue seam** (implements T1, T2, T3, T4, T5, T7, T14, Q149, Q246, Q247, Q248, Q249)
`skill_spotlight_check()` emits a `spotlight_cued(cards)` signal on transition. **Phase 1 wires the
signal only; phase 2 draws it.**
⚠ **`Q248`=(b): no suppression on resume.** `spotlit` is `@export_storage`, so a saved-spotlit card
loads spotlit and transitions nothing. Do not add code to prevent a flash that cannot happen.
**Done when:** placing a card emits exactly one cue; loading a save emits **zero**.

### Phase 1 acceptance gates — objective, self-checking

- **G1.1** Full suite green, WINDOWED, with the suite count checked:
  `timeout 400 "/c/Users/khanr/Desktop/Godot_v4.7.1-stable_win64_console.exe" --path solatro res://Tests/all_tests.tscn`
  → exit 0, `test_output_errors.log` empty, and the `SUITES` banner count **not lower** than before.
- **G1.2** `grep -rn "is_active\|skill_active_check\|on_active\|on_deactive" --include=*.gd solatro/`
  returns **nothing outside `addons/`**.
- **G1.3** ⚠ **The save migration.** Load a `run.tres` written before S2: the board must come up with
  the same set of spotlit cards as after a fresh `skill_spotlight_check()`, and **no `on_spotlight`
  may fire during the load**. A new test asserts both.
- **G1.4** A buried card in a scored section has `is_spotlit()` true during its phase and false after.
- **G1.5** `GameData.revision` is byte-identical across a whole submit (`Q17`=a).
- **G1.6** A skill whose `on_spotlight` discards a card in its own section terminates, compacts, and
  activates the replacement — and a self-feeding chain ends via `act_event_cap`, **not by hanging**.
  Assert with a bounded watchdog.
- **G1.7** Headless and windowed produce identical mod-fire logs for the same seed (`Q19`=a).

---

## 3. PHASE 2 — the glow shader and the light layer

**S11 — `FxGlowStyle` + three `.tres`** (implements O1–O21, Q207–Q221)
Per §1.8. ⚠ `@tool` on the script or the editor silently drops properties (VFX.md §6.2b).

**S12 — `Shaders/glow.gdshader`** (implements O3, O5, O6, O7, O11, O12, O13, O14, O15, O16, O17, O18, O18b, O19, O20, O21, Q122, Q124, Q211, Q215, Q218)
Per §1.9. Halo **and** inner lift (`Q122`=c) on the exact outline (`Q124`=b).

**S13 — the light layer** (implements H1, H2, H3, H4, H5, H6, H7, H8, H9, G10, G11, G12, G13, G14, QR2, Q240, Q107, Q101)
Per §1.10. ⚠ **The dim is driven by BEAM COUNT, not by act state.**

**S14 — origins and travel** (implements I1, I2, I3, I4, I5, I6, I7, I8, I9, I10, I11, I12, E1, E2, E3, E4, E5, E6, E7, E8, E9, E10, E11, Q113, Q250, Q251, Q117)
Per §1.10's origin rules.

**S15 — the momentary cue's visuals** (implements T6, T8, T9, T10, T11, T12, T13, T15, T16, Q245)
Draw what S10 emits. Shallower dim outside scoring (`Q245`=c).

### Phase 2 acceptance gates

- **G2.1** `fx_snapshot.tscn` runs clean and **every panel is looked at by eye** — metrics are not
  evidence about pixels (project rule 4). State UNVERIFIED otherwise.
- **G2.2** **Scenario S15 of the design's §14 list**: the circle at full intensity, held on one frame,
  over the busiest card face the game can build. **The rank glyph must remain legible.** This is the
  `Q216` call and it cannot be judged from a description.
- **G2.3** `fx_cost.tscn` measured before and after; the worst window is reported in ms. `Q254`=(a):
  build, measure, then decide what gets cut — `Q255`=(d) says the cut is chosen when there is a
  number, so **report it, do not pre-emptively trim**.
- **G2.4** `fx_intensity = 0` removes glow, circle and beam and keeps a reduced dim (`Q83`=a).

---

## 4. PHASE 3 — the reveal

**S16 — derived row expansion** (implements K10, K10b, K10c, Q43-superseded, Q265)
⚠ **The opening is DERIVED, not a fixed card height.** Covering cards duck by exactly enough that
there is no gap between the top of a ducking card and the top of a lifted card, sized from the
**lowest lifted card in that row**. A row holding a card that did not lift may show a gap there.
⚠ **Computed ONCE at the start of the duck** — it stops tracking card bottoms afterwards, so a card
moving later may open a gap and that is accepted.

**S17 — gutters, `slot_center_global`, prop anchors** (implements K12, K13, Q57, Q59)
⚠ `PlayArea.slot_center_global()` is pure uniform-pitch math and every prop anchors to it. Any
per-row expansion breaks it unless the formula learns about it.

### Phase 3 acceptance gates
- **G3.1** A prop anchored to a row below an expansion stays glued to its slot through the whole
  expand/collapse cycle.
- **G3.2** Row gutter labels stay aligned with their rows at every phase.
- **G3.3** `snapshot_diff.py` shows **no unintended panel changes** outside the reveal shots.

---

## 5. PHASE 4 — the tuning tool

**S18 — the scenario player** (implements N1, N2, N3, N4, N5, N6, N7, Q173, Q174, Q175, Q176, Q177, Q178, Q179, Q180, Q181, Q182)
Standalone, hosting a **real** `PlayArea`, real `CardVisual`s and a real headless `Game` with a fixed
deck (`Q174`=a, `Q175`=a — the no-mocks rule). `@tool` **and** runnable (`Q176`=a). Viewport-size
control (`Q177`=a), step (`Q178`=a), freeze (`Q179`=a).
⚠ Scenario list S1–S17 from the design's §14 — `Q182`: *"we are still on first review pass we could
add more"*, so make the list data, not code.

### Phase 4 gate
- **G4.1** Every scenario plays to completion without an error, and S15 can be held on one frame.

---

## 6. PHASE 5 — the film-light pipeline

**Not in this plan.** `QR10`=(a) puts it in scope; `Q239`=(a) ships it as a **second deliverable,
after Spotlight, judged against a finished picture**. Its answers are already recorded (`Q230`–`Q238`)
and it needs its own design pass — it requires a screen read and an HDR viewport, neither of which
exists (`DESIGN.md` §1.6 fact 1).

---

## 7. Standing rules for whoever executes this

1. **No `git add`, no commits.** The owner commits through GitHub Desktop.
2. **Never run Godot while the owner's editor is open** (`Get-Process *odot*`).
3. **Verify visuals by eye.** Render, look at the PNG, describe what it shows — or say UNVERIFIED.
4. **Type every array element and every for-loop variable** — warnings are errors.
5. **`/handoff`** — this spans more than one session; keep `solatro/HANDOFF_spotlight.md` current.

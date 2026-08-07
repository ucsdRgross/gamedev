---
name: architecture-map
description: "What each project in this repo is, how they connect, and the seams where a change in one place breaks another — enough to spot a collision; read the named doc for detail"
metadata:
  node_type: memory
  type: project
---

Enough to know what you are touching and what it can break. **No status, no detail** — every
line names the doc that has it.

## The projects and their entry docs

| Project | What | Read |
|---|---|---|
| `solatro/` | Godot 4.7 card game — the main project | `START_HERE.md`; `VFX.md` for effects |
| `worldgen/` | Godot map-generation addon + C++ GDExtension | `START_HERE.md`, `GRAPH_DESIGN.md` |
| `palette/` | Node palette generator, zero deps | `ARCHITECTURE.md` |
| `designloop/` | Node front end for the design questionnaire | `README.md` |

The rest are game-jam and study projects with no shared surface.

## Cross-project collisions

- **worldgen is VENDORED into solatro** at `solatro/addons/worldgen/`. Never edit it there —
  change it upstream in `worldgen/` and re-copy. The vendored `README.md` deliberately differs
  (it carries a vendored banner), so copy changed files, not the whole tree. An open Godot editor
  or a stray run LOCKS the vendored dll and blocks the copy.
- **The C++ GDExtension is optional at runtime.** Every native call site keeps a GDScript
  fallback, so a missing dll degrades silently to a slow-but-correct path — if something is
  mysteriously slow, check the dll registered before profiling anything.
- **designloop parses design markdown it does not own.** It reads the documents
  `/flowchart-design` writes; there is never a second authored copy. Changing that document
  format breaks the tool, and vice versa.
- **palette is standalone.** Nothing else in the repo consumes it.

## Seams inside solatro

The places where two things must agree, and nothing checks it for you:

- **Game (headless logic) vs GameView (UI)**, joined by a `view == null` seam. Data runs one tick
  AHEAD of the view.
- **`GameData.revision`** — every board mutation must bump it AFTER the state is consistent.
  A missed bump gives stuck UI, a stale comparator cache, and a stale position index.
- **Undo** rewinds `GameData`, not `Game` — per-act state on the wrong object survives an undo.
- **Serialisation** — `BigNumber` is RefCounted and invisible to `duplicate_deep`;
  `CardModifier.data` is a WeakRef. Both need manual handling after any copy.
- **Draw order is structural** (node order, not `z_index`), so reparenting changes rendering.
- **Pooled per-slot controls** are reused across cards — derive state on bind, never cache it.

Contracts and the current spec for all of these: `solatro/ARCHITECTURE_REVIEW.md`
(scoring §3, props §4, undo §5, memory §6, testing §7, owner rulings §8) and `LAYERING.md`.
The authoritative copy of the mutation rules is the "MUTATION GUIDELINES" block in
`Scripts/board.gd`.

## Conventions that are not the language default

- User-facing text goes through `TRANSLATION.find` + `Locale/localization.csv`, never a literal.
- Every UI must work with mouse, keyboard AND controller.
- Tuning knobs live in `player_settings.gd`; durations derive from `get_delay()`, never
  wall-clock.
- Warnings-as-errors: type every array element and every loop variable.

See [[machine-profiles]] for anything path- or hardware-shaped.

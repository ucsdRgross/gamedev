---
name: graph-spec-step-a
description: How worldgen/scripts/graph_spec.gd builds the abstract rule-correct DAG (Step A of graph placement)
metadata: 
  node_type: memory
  type: project
  originSessionId: 58446534-0680-4941-8307-260753a93361
  modified: 2026-07-30T22:00:31.292Z
---

`worldgen/scripts/graph_spec.gd` (`GraphSpec.build(...)`) is Step A of the graph-placement pivot: a PURE-DATA, map-independent, deterministic layered DAG. No coordinates (placement is Step B physics).

Core model (confirmed with user):
- **Depth = rank.** Rank 0 = start (depth 1); each next city sits `gap = nodes_between_cities + 1` ranks later; travel nodes fill ranks between. Every start→end path crosses exactly one node per rank → cities-per-path and nodes-between-cities are exact by construction.
- **Lane ramp** (`_lane_ramp`): lane count per rank goes 1 → … → width → … → 1, bounded so `lanes[r+1] ≤ lanes[r]*outgoing` (a single start/end node can't fan to `width` in one step).
- **Spread fan**: lane `L` → lanes `(L*outgoing + j) mod C1`. Guarantees coverage (no orphans), degree ≤ outgoing, maximal reach growth.
- **width is a TARGET not a hard rule.** A city should reach `min(width, ideal_reach)` other cities at the next city rank. `_ideal_reach` SIMULATES the actual fan per city lane (a clean `outgoing^gap` product overestimates because mod-wrap collides). If width is unattainable the graph just grows as wide as the fan allows.
- **trim + repair**: `_trim_edges` randomly drops surplus edges (variety, never orphans, keeps `min_outgoing_after_trim`) and RETURNS the removed list; `_ensure_width` re-adds removed edges to restore each city's width target (re-adding only restores original spread edges → never orphans, never exceeds cap, always attainable).

`GraphSpec.validate(...)` is the data-only checker (clamps inputs exactly as build does). Test: `worldgen/tests/graph_spec_test.*` — named + extreme + 1500 fuzz, all 1860 pass. New WorldSettings params: `spec_cities/nodes_between_cities/graph_width/outgoing/min_outgoing_after_trim/edge_trim_chance`.

Open for Step B ([[graph-placement-step-b]]): zigzag-across-continent prevention is a PLACEMENT constraint (keep depth monotonic along the start→end spatial axis); edges only ever connect adjacent depths. (The original plan file under `.claude/plans/` is gone — `worldgen/START_HERE.md` is the live worldgen doc.) Worldgen has been dormant since ~2026-07-18.

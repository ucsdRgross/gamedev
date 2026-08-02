---
name: graph-placement-step-b
description: "graph_placement.gd Step B — v4 ladder placement, edges-last forward sweep, plus the standing rules and the measured dead ends not to retry"
metadata: 
  node_type: memory
  type: project
  originSessionId: 75157de2-6326-43ea-b7df-1a25b81a7de6
  modified: 2026-07-30T22:00:24.253Z
---

Step B places the rule-correct node set from [[graph-spec-step-a]] onto the real map.
File: `worldgen/addons/worldgen/core/graph/graph_placement.gd` (moved out of
`worldgen/scripts/`). Verified visually by running `worldgen/tests/graph_placement_test.tscn`
WINDOWED — see [[running-godot-scenes]]; that test PRINTS on_land%/water_viol rather than
asserting them (`worldgen/START_HERE.md`, the consolidated worldgen doc, has the test table).
Worldgen has been dormant since ~2026-07-18; treat everything below as last-known state and
re-read the file before acting on it.

**Architecture: geometry-first, edges-last (v2 onward).** Place nodes deterministically —
NO physics — then build ALL edges in one geography-aware pass.

**Aggregate-axis poles (2026-07-06).** Eligibility (`large`, min_frac) is computed BEFORE the
axis; the axis is `land_pca_labels(large)` — PCA over the ELIGIBLE landmasses' samples only —
so it spans the whole eligible archipelago and start/end poles may sit on DIFFERENT landmasses.
`_legal_ferry` therefore no longer bans start/end and exempts poles from the coastal test.

**Current model = LADDER (v4, `_make_ctx`).** Nodes are GENERATED, not taken from spec counts:
- Global `land_pca()` gives journey axis + perp + extents. Rung count `D = graph["ranks"]`
  (spec depth), laid evenly along the axis. Rows 0/D collapse to one start/end node at the
  axis poles (`_pole_pos`); interior nodes within `pole_sep` (`field._cs * opts.pole_sep`,
  default 1.5) of a pole are skipped so nothing lands on top of start/end.
- Each interior rung is an INDEPENDENT slice across the land (`slice_land_coords` per large
  landmass), divided into `count` equal width-sections; `count` scales with that slice's land
  width between the globally thinnest and widest. Division is ENDPOINT-INCLUSIVE
  (`frac = k/(count-1)`) so outer nodes sit ON the coasts (no inland contraction). Each node is
  jittered by `jitter` × rung spacing. **Lanes are PER-RUNG and deliberately do NOT align across
  rungs** — the owner asked for this ("not a true square grid").
- Levers (PLACE_OPTS): `min_width`, `max_width`, `jitter`, `landmass_min_frac`,
  `lane_tol` (1.8), `branch_local_mul` (2.5), `pole_sep`.
- Edges (`_create_edges` / `_connect_rows`, single forward sweep, NO repairer): each u connects
  to its NEAREST same-landmass next-rung node by GEOMETRY (not lane index, since lanes don't
  align), branching only within `lane_tol` × the nearest distance. If the nearest crosses a
  LOCAL on-land edge, take the next nearest non-crossing. `_pick_link` coverage then links any
  still-unlinked node. Every node ends with ≥1 in and ≥1 out, so connectivity holds BY
  CONSTRUCTION — no repair pass, no trim.
- The test renders from `ctx` (`res["ctx"]`), NOT `graph["nodes"]`.

**Step C DONE** (`graph_detail.gd`, `GraphDetail.compute_curves`): A* over a downscaled bounded
grid + line-of-sight string-pull (`_los_simplify`/`_segment_clear`) so open-ocean runs stay
straight. Water/ferry edges route where water is cheap and land expensive; LAND edges penalise
height deviation from the endpoints' average and avoid water. **Never falls back to a straight
line** (looks out of place) — instead `_route` uses soft cost ramps as imaginary walls: a
corridor penalty keeps the curve near the straight line, an occupancy penalty (thickened stamp)
makes later routes avoid earlier curves so parallel routes keep a visible gap, and an overshoot
penalty (default 18) stops curves sailing past the destination and looping back. Levers:
`route_downscale`, `route_margin`, `route_land/water_penalty`, `route_slope_weight`,
`route_height_tol`, `route_corridor_ratio/penalty`, `route_occupancy_penalty`,
`route_overshoot_penalty`, `route_max_detour`.

**Export:** `GraphPlacement.export_graph(ctx, field, curves, opts)` → pure data
`{start, end, max_depth, nodes:[{id,pos,depth,landmass,height,biome,out:[{to,ferry,points}]}]}`.
The `ferry` flag means CROSS-LANDMASS only — a same-landmass bay edge is land travel.
`biome` comes from `opts.biome_fn: Callable(Vector2)->int` (wiring was still TBD).

**Still TODO when work stopped:** (a) scatter cities back onto depths; (b) tune curve penalties;
(c) driver + world_generator wiring + 5 debug images; (d) world_settings param overhaul.
Param audit (v4): USED = cities & nodes_between_cities (→ rung count D), spec_outgoing (edge
cap), and the PLACE_OPTS above. DEAD = `spec_graph_width`, `spec_layer_min/max`, `landmass_mode`
in opts. `_lane_gap` is dead since v3.

**RULES TO FOLLOW (standing, owner-stated):**
1. Edges exist ONLY after placement — render init/mid edge-free, final with edges.
2. Start & end on land from the very first image.
3. Active nodes 100% on land (trimmed nodes excluded from graph + render).
4. Each large landmass gets its own piece, pieces joined by ferries. The MAIN landmass does NOT
   necessarily get the main spline. Split by BREADTH for side-by-side land, by DEPTH where ocean
   interrupts the axis.
5. Water travel (ferry) only between two COASTAL nodes on DIFFERENT landmasses — except poles
   (rule 6, 2026-07-06), which may ferry and are exempt from the coastal test; the
   open-water-line test still applies to them.
6. Prefer no edge crossings, but tiered — never a hard ban.
7. Connectivity guaranteed BY CONSTRUCTION in the forward sweep; no repair pass.
8. Even spread, no clumping; trim nodes at thin slices.
9. Curve water travel AROUND land (Step C).

**Cost model rulings that were fought for — do not undo:**
- **Cost by LANDMASS, not by water** (2026-06-26). Treating a same-landmass bay-clipping edge as
  more expensive than a ferry pushed paths off their own landmass and created wrap-around edges.
  Same-landmass = land travel even across a bay; Step C curves it along the coast.
- **Every undesirable property is a PENALTY TIER, never a skip** (only a duplicate edge is
  skipped) — that is what makes coverage never fail. Order cheap→dear: clean on-land < legal
  ferry < on-land overlap < forced water < over branch-cap.
- **Repair takes the NEAREST node even if that node is already at `spec_outgoing`** (owner OK'd;
  hubs may exceed the cap). The over-cap penalty was removed from `_pick_link` for this. Step 1's
  primary branching still hard-respects `max_out`.
- **A node whose nearest forward node is farther than `branch_local` (~2.5 rung pitches) is
  ISOLATED and emits only its single required edge** — no extra branches. This plus repair=nearest
  fixed the long "skip-past" edges; after them, seed6434 flagged 0 edges and the owner confirmed
  the visuals. Residual `[EDGE?]` flags are harmless short local X-crossings and lobe-entry nodes.
- Crossing prevention is LOCAL and ON-LAND ONLY: two land roads never overlap, but long
  cross-landmass ferries are not blocked by crossings (Step C curves them).
- Deferred but owner-approved if this is picked back up: **geodesic curving rungs** — the only
  thing that would erase lobe-entry/empty-rung long edges.
- Diagnostic scaffolding left in the file: `_diagnose_edges`, `_explain_long_edge`, `ctx.edge_tag`
  (tags edges `s1.<branch>` / `s2in` / `s3out`). Remove when the work is truly finished.

**GOTCHA — Poisson must seed EVERY landmass.** Bridson Poisson-disk growth cannot jump open
ocean, so a single seed samples only one island and multi-landmass placement silently collapses
onto it (or "one dot" if that seed was a tiny island). `_label_landmasses` records
`label_seed[id]` and `_poisson_samples` seeds the active list from every landmass. A landmass
with zero samples makes every node assigned to it fall back to another island.

**DEAD ENDS — measured and rejected, do not retry:**
- Hard graph-wide no-cross ban, a `_prune_dead_ends` trim, and global monotonic matching
  (tried + reverted 2026-06-25). The owner wants nearest-as-primary with a local cross fix.
- Multi-phase opportunistic edges + a connectivity REPAIRER → repair forced random long
  cross-island edges. Replaced by the single forward sweep.
- Connecting to the nearest next-depth node GLOBALLY → full-width / cross-island jumps.
- A strict strait gate that SKIPPED illegal water, a max-ferry-distance gate, and allowing
  same-landmass-over-water in step 1 → all orphaned landmasses / made dead ends.
- Water_mode / bay-preference routing, and the crossing-DODGE, as fixes for long skip-past edges
  → neither was the cause (the target edge stayed byte-identical).
- Per-landmass lens/oval re-lay with lens pinch → poles clump, spines unequal, targets land in
  water and pile on the coast. Replaced by the 2D grid cross-section, then by the v4 ladder.
- Dividing PURELY by depth → tip-to-tip travel, size-blind clumping, broken start/end.
- Plain nearest-landmass division → a small island beside a dense region steals a
  disproportionate share. Area-proportional quotas + greedy nearest-first assignment work but
  zig-zag by assignment order. (v3's answer was an independent per-node distance/area rule; v4
  generates nodes per rung instead and sidesteps division entirely.)
- ONE global PCA oval with snap-to-nearest-land → the dominant island swallows every node.
- Pre-assigning nodes to a landmass by perpendicular breadth band → collapses when islands
  aren't separated along the perp axis.
- Force-directed settling (FDP/Sugiyama/Lloyd) for placement → collapses onto one/tiny island,
  and snap-after-settle makes nodes jump at the final frame. Deterministic assignment only;
  that dead code (~520 lines) has since been deleted along with `place()`'s `integrator` param.
- Crossing-removal / edge contraction on a pre-built rule graph → shatters connectivity.
- Confining to the largest landmass in "multi" mode → contradicts multi-landmass.

- **2026-07-18 CROSS-MACHINE DETERMINISM INVESTIGATED (finding, no code change):**
  follow-up to the Phase 4 review. First, the port chain is **proven
  behavior-neutral** — pre-port code (`3750300`, before ANY C++ work), HEAD, and
  Phase 4 all produce byte-identical debug images on one machine (78/78 placement
  + 6/6 biome, via throwaway `git worktree`). What is NOT stable is the machine:
  the commit that generated the committed PNGs **cannot reproduce them here**, so
  those images are a SAME-MACHINE regression check only and must not be treated as
  a cross-machine baseline. Root cause: the four heightmap steps are GPU shader
  passes read back at `FORMAT_RF` float32, using ops (`sin`/`cos`/`atan`/`pow`/
  `exp`/`smoothstep`/`texture`) whose precision is implementation-defined; every
  step downstream is deterministic CPU code. Impact is structural, not cosmetic:
  vs the dev box, **route lines and node markers move** (6.8% of pixels differ,
  3.5% large-jump; ~1800 route-line pixels relocated). A same-box renderer swap
  (gl_compatibility vs forward_plus/d3d12) was milder — `graph.json` and
  `water.png` survived, `land.png`/`composite.png` did not. This reaches players
  because Solatro generates the map at RUNTIME per machine
  (`Scripts/Map/world_map_controller.gd:64`). Logged as an open risk in
  `todo.md`; options (port GPU steps to CPU / quantise / ship bakes / split visual
  vs gameplay field) written up in `worldgen/DETERMINISM_FINDINGS.md`. Also
  recorded there: only 1 of 8 worldgen test scenes propagates a failure exit code
  (the other seven always exit 0 — `graph_spec_test` counts failures then discards
  them), and routing has unused quality headroom now that it is 20x faster
  (`route_downscale` 4 -> 2 is ~90 ms, was 1.3 s).

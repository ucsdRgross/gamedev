---
name: machine-profiles
description: "Per-machine paths and hardware quirks (Godot binary, repo root, GPU, Node) — the ONLY place absolute paths belong; every other doc stays machine-neutral"
metadata:
  node_type: memory
  type: project
---

Absolute paths and hardware facts differ between the owner's two computers. **They belong
here and nowhere else** — no other doc or memory may hard-code one. Identify the current
machine by which repo root exists, then use that column.

| | **Box A — daily driver** | **Box B — the fast one** |
|---|---|---|
| Repo root | `C:\Users\khanr\Documents\GitHub\gamedev` | `C:\richard\gamedev` |
| Godot binary | `C:\Users\khanr\Desktop\Godot_v4.7.1-stable_win64_console.exe` | `C:\richard\Godot_v4.7-stable_win64_console.exe` |
| GPU | Intel UHD (integrated) — **the perf target** | GTX 1070 |
| Node | on PATH | `C:\Program Files\nodejs`, **not** on the tool-shell PATH |

⚠ **Box B is only ~2x Box A, not 12x.** Ratios transfer between them; absolutes do not.
Re-baseline before/after in the SAME session on the SAME box — never against a figure from
the other one. Optimisation targets are Box A's numbers.

⚠ **Box B's GPU timer is BIMODAL by ~1.3–1.7x** (the card sits in two power states, and every
row of a run is scaled by the same factor — five runs of one unchanged build read
0.594 / 0.597 / 0.753 / 0.874 / 0.924 on the same row). **Run `Tests/Visual/fx_cost.tscn`
three times and take the minimum**; a single run is not evidence.
`viewport_get_measured_render_time_gpu` does work on both.

Other per-box notes:
- **Node**: on Box B prepend `$env:Path = "C:\Program Files\nodejs;$env:Path"` to every
  command (bash: `export PATH="/c/Program Files/nodejs:$PATH"`). Versions drift — check
  `node -v` rather than trusting a note; `palette/` needs **≥ 22** (`palette/ARCHITECTURE.md`).
- **SCons** is a Python module only on Box A — `python -m SCons ...`, never bare `scons`
  (`worldgen/worldgen_native/BUILD.md`).
- Godot versions differ (4.7.1 vs 4.7). If a `class_name` suddenly won't resolve, it is the
  import cache, not the version — see [[running-godot-scenes]].

If you are on a third machine, add a column rather than editing an existing one.

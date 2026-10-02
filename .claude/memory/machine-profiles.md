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
| Godot binary | `C:\Users\khanr\Desktop\Godot_v4.7.2-stable_win64_console.exe` | `C:\richard\Godot_v4.7.2-stable_win64_console.exe` |
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
- ⚠ **Box A has TWO disagreeing Pythons**: `py` is 3.9.7, `python` is 3.14.6. They do not share
  installed modules, which is why SCons runs under `python` and `doc_check.py` under `py`. Check
  `py --version` / `python --version` before assuming a script will find its imports.
- Both boxes are on 4.7.2. If a `class_name` suddenly won't resolve, it is the
  import cache, not the version — see [[running-godot-scenes]].

## Cloud container (claude.ai/code session)

Linux, no GPU: Godot renders through Mesa llvmpipe on a virtual display. The container is
ephemeral, so every session starts with `bash .claude/tools/cloud_setup.sh && source
/opt/godot/env.sh` (~1 min; installs the pinned Godot, imports both projects, gives `godot <args>`,
which wraps `xvfb-run`; the Linux binary is already the console build). Importing does not reorder
`solatro/project.godot`.

- Logic, importing, snapshot scenes and `worldgen/tests/native_ab_test.tscn` work.
  `godot --path solatro res://Tests/Visual/fx_snapshot.tscn` writes its PNGs under user://
  `fx_snapshots/` — look at them. Perf numbers (`fx_cost`, GPU timer) mean nothing here.
- The gate runs here: `python3 .claude/tools/gate.py --out <scratch> --handoff <file> -- --timeout
  2400 --stall-timeout 900` (`py` does not exist). user:// is
  `$XDG_DATA_HOME/godot/app_userdata/Solatro` (lowercase `godot`). A full run takes ~18 min.
- ⚠ **No hook fires here**: every `.claude/settings.json` hook runs `powershell` or `py`, and
  neither exists. Hold the subagent cap, the commit gate's duplicate check, the private user://
  and the one-Godot rule by hand, and run `python3 .claude/tools/doc_check.py --changed` (and
  `dup_check.py`) yourself before a commit.
- The worldgen extension has a committed Linux debug `.so`; rebuild recipe in
  `worldgen/worldgen_native/BUILD.md`.

If you are on a third machine, add a column rather than editing an existing one.

---
name: fx-verify
description: Verification gate for Solatro visual/shader/prop-art work — render the snapshot scenes, LOOK at the PNGs, and report what the image actually shows; for anything with a DURATION, run it and report what moved. Use before claiming any FX, shader, prop-art, or layering change works. Also use when asked to check whether an effect looks right.
---

# FX verification gate

No FX/shader/prop-art change is "done", "working", or "fixed" until a rendered image has been
looked at. Passing tests, coverage numbers, and reasoning about the shader are **not** evidence
about pixels — that substitution is the single most common failure mode on this project.

If you cannot render, say **UNVERIFIED** in plain text and do not use the words "working",
"fixed", or "correct".

## ⚠ A STILL FRAME IS NECESSARY AND NOT SUFFICIENT

**The evidence hierarchy: green suite < printed counts < a rendered pixel < movement measured over
time.** A PNG settles a silhouette, an edge, a colour. **It cannot settle a pulse, a travel, a fade,
or a sequence** — a still of a working loop and a still of a dead one are identical.

Measured: three defects survived a full set of "looked at and passed" captures — a
per-section dim pulse, a retire beat that threw an error every frame, and a cascade stuck on its
first section. The owner found all three by watching. **So for anything with a DURATION, rendering is
the wrong verb:**

```bash
<binary> --path solatro res://Tools/spotlight_tool.tscn -- --verify
```

It plays every scenario and reports what MOVED — `sections=4/4 show_flips=14 max_dim=0.75
max_open=1.00` — and flags anything that changed nothing over its whole loop. It found a real thrown
error on its first run. **A capture harness for a temporal effect must report movement, not that it
did not crash.** Add the same shape to any new harness: print the counts beside every shot, because
a blank frame at exit 0 is this class of tool's characteristic failure.

⚠ `-- --trace` runs a REAL act with `EventLog` recording when the question is about ORDER
(`HEADLESS_TESTING.md` §0c). `-- --shoot-all` is the still-frame path.

## Preconditions

- **The owner's Godot editor must be closed** for suite runs. Check first:
  `Get-Process | Where-Object { $_.ProcessName -like '*odot*' } | Select-Object Id, MainWindowTitle`
  An editor/scene title is their session — stop and ask. Never kill by name (a hook blocks it).
- `cd` to the **repo root** — `--path solatro` is relative and fails from inside `solatro/`.
- Binary: the per-machine path is in `.claude/memory/machine-profiles.md` — glob `Godot_v4.7*` in
  the directory it names, since the binary set churns. There is a `_console` twin beside the main
  exe for redirectable output.
- **Never `--headless`** for anything pixel-related: a dummy renderer cannot compile a shader,
  so a headless pass proves nothing.

## Steps

1. **Render.** Run the relevant snapshot scene WINDOWED (each self-`quit()`s in a few seconds):
   - `<binary> --path solatro res://Tests/Visual/fx_snapshot.tscn` — shader FX
   - `<binary> --path solatro res://Tests/Visual/prop_art_snapshot.tscn` — prop / pip sprite art
   - **The picture wall has its own eight**, and they are the gate for anything under `UI/Wall/`:
     `wall_verify_snapshot` (wall view, mid-transition, focused-at-rest, 32:9),
     `wall_frame_shadow_snapshot` (frame nine-slice + shadow direction),
     `wall_picture_construction_snapshot`, `wall_overfill_snapshot`, `wall_filter_swap_snapshot`,
     `wall_info_snapshot`, `wall_skeleton_snapshot`, `wall_editor_snapshot`.
     ⚠ **They do NOT write to the `{fx,prop_art}_snapshots` folders.** Each takes an env var and
     falls back to `user://<scene_name>/` — `OUT_DIR` for the multi-shot scenes, `OUT_PATH` for the
     single-shot ones (`main_boot`, `wall_filter_swap`, `wall_overfill`,
     `wall_picture_construction`, `wall_skeleton`). Set it to a directory you can read back:
     `$env:OUT_DIR=<dir>` before `Start-Process`, since a scene's own header is otherwise the only
     place that convention is written down.
   Launch so you WAIT for exit (`Start-Process ... -PassThru` then `WaitForExit`), and run one
   Godot at a time — concurrent runs starve each other on the Intel UHD.

2. **Look at the output.** PNGs land in
   `%APPDATA%\Godot\app_userdata\Solatro\{fx,prop_art}_snapshots\*.png`.
   Read them with the Read tool. Crop and upscale with PIL when something is too small to judge.
   Prefer making the harness measure its own capture over eyeballing pixel positions.

3. **Run the PIXELS suite** (it asserts on real pixels and FAILS rather than skips if run under
   a dummy renderer): `<binary> --path solatro res://Tests/all_tests.tscn`, windowed, ~60 s,
   self-quits with the failure count. Read only failures: an empty `test_output_errors.log` plus
   the final banner means green. LEAK CANARY's stderr push_error lines are deliberate.

4. **Measure cost if the change could affect performance.**
   `Tests/Visual/fx_cost.tscn` reports per-effect GPU cost. Quote before/after numbers measured
   on this machine's Intel UHD — never an estimate, never a ratio you reasoned your way to.

5. **If the change has a duration, measure it over time** — see the section above. A rendered still
   is not evidence about a pulse, a travel, a fade or a sequence.

## Reporting

State, in words, **what the image actually shows** — silhouette, edges, clipping, artifacts,
whether the effect sits where it should relative to the card. Name what you checked and what you
did not. If something looks off, say so plainly rather than reaching for a metric that agrees
with you.

Related repo docs: `solatro/VFX.md` (map, runbook, backlog, known bugs), contracts in
`solatro/ARCHITECTURE_REVIEW.md` §4g/§4h, `solatro/LAYERING.md` for draw order.

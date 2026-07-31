---
name: fx-verify
description: Verification gate for Solatro visual/shader/prop-art work — render the snapshot scenes, LOOK at the PNGs, and report what the image actually shows. Use before claiming any FX, shader, prop-art, or layering change works. Also use when asked to check whether an effect looks right.
---

# FX verification gate

No FX/shader/prop-art change is "done", "working", or "fixed" until a rendered image has been
looked at. Passing tests, coverage numbers, and reasoning about the shader are **not** evidence
about pixels — that substitution is the single most common failure mode on this project.

If you cannot render, say **UNVERIFIED** in plain text and do not use the words "working",
"fixed", or "correct".

## Preconditions

- **The owner's Godot editor must be closed** for suite runs. Check first:
  `Get-Process | Where-Object { $_.ProcessName -like '*odot*' } | Select-Object Id, MainWindowTitle`
  An editor/scene title is their session — stop and ask. Never kill by name (a hook blocks it).
- `cd` to the **repo root** — `--path solatro` is relative and fails from inside `solatro/`.
- Binary: glob `C:\Users\khanr\Desktop\Godot_v4.7*` (the Desktop binary set churns; there is a
  `_console` twin beside the main exe for redirectable output).
- **Never `--headless`** for anything pixel-related: a dummy renderer cannot compile a shader,
  so a headless pass proves nothing.

## Steps

1. **Render.** Run the relevant snapshot scene WINDOWED (each self-`quit()`s in a few seconds):
   - `<binary> --path solatro res://Tests/Visual/fx_snapshot.tscn` — shader FX
   - `<binary> --path solatro res://Tests/Visual/prop_art_snapshot.tscn` — prop / pip sprite art
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

## Reporting

State, in words, **what the image actually shows** — silhouette, edges, clipping, artifacts,
whether the effect sits where it should relative to the card. Name what you checked and what you
did not. If something looks off, say so plainly rather than reaching for a metric that agrees
with you.

Related repo docs: `solatro/VFX.md` (map, runbook, backlog, known bugs), contracts in
`solatro/ARCHITECTURE_REVIEW.md` §4g/§4h, `solatro/LAYERING.md` for draw order.

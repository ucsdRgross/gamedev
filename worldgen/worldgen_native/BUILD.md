# worldgen_native — build notes

C++ GDExtension acceleration for the worldgen hot loops (function inventory +
contracts: `../START_HERE.md`). Ships as
`addons/worldgen/bin/worldgen_native.windows.*.dll` + `worldgen.gdextension`,
so the vendor-copy into Solatro carries it. GDScript fallbacks remain at every
call site — the addon works with the dll deleted.

Toolchain (installed 2026-07-17): Visual Studio Build Tools 2022 ("Desktop
development with C++" workload) + `pip install scons` + git on PATH.

## Layout

- `godot-cpp/` — shallow clone of godot-cpp **master** (no 4.6/4.7 branch exists
  upstream as of 2026-07). It is pinned to Godot 4.7 stable by overwriting
  `godot-cpp/gdextension/extension_api.json` + `gdextension_interface.h` with the
  dumps in `api/` (produced by
  `Godot_v4.7-stable_win64_console.exe --headless --dump-extension-api --dump-gdextension-interface`).
  If you re-clone godot-cpp, re-copy both files from `api/` before building.
- `api/` — the 4.7-stable API dumps (committed so builds are reproducible).
- `src/` — `worldgen_native.cpp/.h` (the ported functions), `register_types.cpp`.
- `.gdignore` — keeps Godot from importing MSVC `.obj` build artifacts as meshes.

## Build (Windows, MSVC + SCons)

```
cd worldgen_native
python -m SCons platform=windows target=template_debug
python -m SCons platform=windows target=template_release
```

(`scons` is often not on PATH — `python -m SCons` always works.) Output lands
directly in `../addons/worldgen/bin/`. Editor + debug exports use
template_debug; release exports use template_release (see `worldgen.gdextension`).

Gotchas: if SCons says "up to date" for a file edited during a running build,
delete `src/*.obj` and rebuild. If a scene reports "WorldgenNative class not
registered", the project lacks `.godot/extension_list.cfg` — run
`Godot --headless --path <project> --import` once. `SConstruct` pins
`/fp:precise` / `-ffp-contract=off` deliberately (determinism) — never add
`/fp:fast`.

## Bit-identical rule

Every method must produce byte-identical output to its GDScript twin: load
PackedFloat32Array elements to double, do ALL arithmetic in double, cast to
float only on store, keep exact loop/queue/tie-break order. Gate:
`Godot --path . res://tests/native_ab_test.tscn` (windowed, never --headless).
Run it after ANY change here or to the GDScript twins.

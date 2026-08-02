---
name: worldgen-native-build-env
description: "How to build the worldgen_native GDExtension on this box: python -m SCons, re-clone godot-cpp, --import to register the dll"
metadata: 
  node_type: memory
  type: project
  originSessionId: d76a2385-89a4-4029-b871-3cf5ea12918b
---

Building `worldgen/worldgen_native/` (the C++ GDExtension) on this machine, verified 2026-07-18 during the Phase 4 port:

- **`scons` is NOT on PATH.** Use `python -m SCons platform=windows target=template_debug` (and `target=template_release`) from `worldgen/worldgen_native/`. SCons 4.10.1 is installed as a Python module only.
- **`worldgen_native/godot-cpp/` is gitignored and is usually ABSENT.** Restore per `worldgen_native/BUILD.md`: `git clone --depth 1 https://github.com/godotengine/godot-cpp.git godot-cpp`, then copy `api/extension_api.json` + `api/gdextension_interface.h` over `godot-cpp/gdextension/`. First build is ~30 min (all of godot-cpp); after that it's incremental and takes seconds.
- **SCons can report "is up to date" for a source you edited while a build was running.** Delete `src/*.obj` and rebuild to be sure the dll matches current source.
- **A built dll does nothing until the project has imported it.** If a scene reports "WorldgenNative class not registered — dll missing?", the cause is a missing `.godot/extension_list.cfg`; run `Godot --headless --path <project> --import` once. Import is safe headless — it's the generation scenes that are not.
- The docs in these repos use `C:\richard\gamedev\...` paths; the real ones here are `C:\Users\khanr\Documents\GitHub\gamedev\...`.

Bit-identity + determinism contracts, native-function inventory, and test-scene caveats
live in `worldgen/START_HERE.md` (the port handoffs were consolidated there 2026-07-19). See [[running-godot-scenes]] and [[godot-editor-disk-sync]] — an open Godot editor (or a stray headless run) LOCKS the vendored dll in `solatro/addons/worldgen/bin/`, which blocks vendoring; check for Godot processes before copying and never kill the user's editor without asking.

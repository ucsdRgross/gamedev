# C++ toolchain setup — what YOU (the owner) need to install

One-time machine setup so the GDExtension port (`GDEXTENSION_PORT_HANDOFF.md`) can be
built. Nothing here touches the projects; it's all machine-level installs. Checked
2026-07-17: this box currently has NONE of these (no MSVC, no MinGW, no scons;
Python 3.13 IS already installed).

## Required (in order)

1. **Visual Studio Build Tools 2022** (compiler only — no need for the full IDE)
   - Download: https://visualstudio.microsoft.com/downloads/ → "Build Tools for
     Visual Studio 2022" (free).
   - In the installer, tick the workload **"Desktop development with C++"**.
     The defaults it selects (MSVC v143, Windows 11 SDK, CMake tools) are enough.
   - ~7 GB disk. A reboot is not usually needed.

2. **SCons** (the build tool godot-cpp uses) — Python is already installed, so:
   ```
   pip install scons
   ```
   Verify: `scons --version` in a NEW terminal (needs PATH refresh).

3. **Git** — already available if you use GitHub Desktop's git; the build needs it on
   PATH to fetch godot-cpp. Verify with `git --version` in a terminal; if missing,
   install https://git-scm.com/download/win (defaults are fine).

## Verify the toolchain works (2 minutes)

Open **"x64 Native Tools Command Prompt for VS 2022"** (installed by step 1 — building
MUST happen from this prompt or a shell that ran vcvars64.bat) and run:

```
cl
scons --version
git --version
```

`cl` should print "Microsoft (R) C/C++ Optimizing Compiler ... for x64". If all three
answer, setup is done — tell the agent to proceed with the port.

## Optional / notes

- Nothing needs to change in Godot itself: GDExtension loads a .dll at runtime; the
  stock `Godot_v4.7-stable_win64` binaries you already use are fine.
- godot-cpp (the C++ bindings) does NOT need pre-installing — the port checks it out
  pinned to the `4.7` branch as part of the build (needs internet on first build).
- Only win64 binaries are planned. If Solatro ever ships to another platform, that
  platform's builds are a separate (cross-compile or CI) task — flag it then.
- Disk/undo lever if 7 GB hurts: the "C++ build tools core features" + MSVC v143 +
  one Windows SDK are the true minimum inside the workload, but the default selection
  is the safe choice.

# Handoff — running Godot in a cloud session

Goal: do visual and test work in claude.ai/code sessions, not only on the owner's Windows boxes.

## Start of every cloud session (the container is ephemeral; /opt/godot is gone)

```bash
bash .claude/tools/cloud_setup.sh && source /opt/godot/env.sh   # ~1 min; installs Godot 4.7.2, imports both projects
godot --path solatro res://Tests/Visual/fx_snapshot.tscn         # PNGs -> ~/.local/share/godot/app_userdata/Solatro/fx_snapshots/
```

Read the PNGs with the Read tool and describe what they show (hard rule 5).

## Getting this into the branches being worked on

This work lives on branch `claude/godot-cloud-test`. It adds only tooling, so merge it into a
working branch with `git merge claude/godot-cloud-test`. It does not touch game code. Files it
carries:

- `.claude/tools/cloud_setup.sh` — the bootstrap above
- `solatro/addons/worldgen/bin/libworldgen_native.linux.template_debug.x86_64.so` and the two
  `worldgen.gdextension` files (one copy in `worldgen/addons`, one vendored in `solatro/addons`) —
  Linux library entries, so the native extension loads in the cloud
- `worldgen/worldgen_native/BUILD.md`, `.claude/memory/machine-profiles.md` — recipes and the cloud profile

A cloud session that starts on a branch without it can run
`git fetch origin claude/godot-cloud-test && git checkout origin/claude/godot-cloud-test -- .claude/tools/cloud_setup.sh solatro/addons/worldgen worldgen/addons/worldgen`.

## State

- Verified: import, `fx_snapshot` (21 PNGs, looked right: fire ladder, light layer), and
  `worldgen/tests/native_ab_test.tscn` PASS bit-identical on Linux with the native `.so` loaded.
- Full `solatro/Tests/all_tests.tscn` in the cloud: 3966 passed, 11 failed, exit 134 at
  teardown, ~7 min. Run BEFORE the native `.so` existed; not re-run since.
  Failures were geometry/pixel checks (OUTLINE rig, PIXELS mask-vs-face, GRID LAYOUT 39 px and
  10.8 px offsets, GRID VIEW framing) plus two OUTLINE checks that `card_visual.tscn` has no
  ShaderMaterial. Hypothesis, UNVERIFIED: virtual-display size or llvmpipe, not real regressions.

## Open

1. Settle whether the 11 are environmental: run the same suite on a Windows box, diff failure
   lists; or retry in the cloud with a window size matching the project's base resolution.
2. Investigate the exit 134 at teardown.
3. Docs cite `solatro/Tools/run_tests.py`; the tracked file is `solatro/tools/run_tests.py`
   (Windows ignores the case, Linux does not).
4. Optionally make `cloud_setup.sh` a SessionStart hook (`session-start-hook` skill). Not done.
5. Newest Godot release unconfirmed (API calls blocked by the proxy); 4.7.2 is what the project pins.

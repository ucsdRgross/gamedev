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

- Verified: import, `fx_snapshot` (21 PNGs, looked right), and `worldgen/tests/native_ab_test.tscn`
  PASS bit-identical on Linux with the native `.so` loaded.
- Branch `claude/combine-cloud-test` = `combine-sidebar-boardplan` + this tooling. Full
  `solatro/Tests/all_tests.tscn` in the cloud: 51 suites, 9673 passed, 6 failed, ~17 min (budget a
  40 min background timeout; a 10 min one kills it). Clean exit, no teardown abort.
- The only failures are `PLAN VISUALS` TP-63 (held-card lighting, two grids). Documented
  intermittent in `solatro/HANDOFF_playtest_fixes.md`, and reproduced 2 of 2 alone here
  (`... all_tests.tscn -- plan`, 2 checks), so the cloud's slow software-GL frames make it near-deterministic.
  Its documented lead: `settle_on` accepts one unchanged frame after the second grid is added.
- On `main`, GRID LAYOUT / GRID VIEW / OUTLINE / PIXELS failed; all pass on the combine branch
  (`main` is 608 commits behind it), so they were stale-baseline, not cloud, failures.

## Open

1. Fix or harden TP-63's `settle_on` (see above); it is the cloud's one red row.
2. `solatro/project.godot` is reordered by every import (`ui_focus_*` move) and two `.gd.uid` files
   appear; do not commit them.
3. Optionally make `cloud_setup.sh` a SessionStart hook (`session-start-hook` skill). Not done.
4. Newest Godot release unconfirmed (API calls blocked by the proxy); 4.7.2 is what the project pins.

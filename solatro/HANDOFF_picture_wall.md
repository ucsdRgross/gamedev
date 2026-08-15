# HANDOFF — picture-wall shell, Phases 0–1 (S1–S8)

| | |
|---|---|
| Branch | `picture-wall`, worktree `C:\Users\khanr\Documents\GitHub\gamedev-picture-wall` |
| Branched from | `6945c6f` on main |
| Implementer agent | `wall-impl` — agentId **`a492ec69f51bbc374`**, address it by that id |
| Current phase | Phase 0 — S1 done, S2 next |
| Scope | S1–S8 only. Stop at S8. |

Read first: `design/picture-wall/PLAN.md`, `TEST_PLAN.md`, `NAMES.md`. `DESIGN.md` is the
authority on behaviour — read only the section a dispute needs.

## Commit policy on this branch — the repo rule is REVERSED here

The overseer commits after every step it has verified itself. One commit per step,
`S<n>: <title>`. Never commit a red suite. The implementer never commits.

## Running the suite here

```
GODOT_BIN=C:\Users\khanr\Desktop\Godot_v4.7.1-stable_win64_console.exe py solatro/Tools/run_tests.py
```

Box A (see `.claude/memory/machine-profiles.md`). Runs WINDOWED, needs a killing timeout.

⚠ **A fresh worktree has no `.godot/` import cache, and the first run spends the whole of
`run_tests.py`'s 600 s ceiling reimporting.** It exits 0 with
`NO SUITE BANNER — the run did not reach its own verdict`, which reads exactly like the
`test_base.gd` parse-error hang and is not it. Warm the cache once, then re-run:

```
"<godot console exe>" --path solatro --import
```

## Baseline, before any step

`ALL 31 SUITES: 2492 CHECKS PASSED [18 placeholder warnings]`, `test_output_errors.log`
0 bytes. Failure set empty. Expect **34** suites once S4, S5 and S7 register theirs.
The 18 placeholder warnings, the 4 leaked ObjectDB instances at exit, and the
`res://tools` vs `res://Tools` case-mismatch warning all pre-date this branch.

## Overseer rulings — decisions the implementer must not re-make

**`wall_unlock_all` exists, and S7 owns it.** PLAN §1.5 and TEST_PLAN R4 require
`SettingsManager.settings.wall_unlock_all`; DESIGN §5's tunables table omits it while
NAMES.md and S8 say that group is *exactly* §5's rows. Not a gap: the source settles it —
**Q159 = (a) "yes, a `PlayerSettings` flag"** (`DESIGN.md:1098`, node K11), and
`wall_debug_readout` (Q210) shows debug flags do belong in that table. The omission is a
documentation bug against the source, i.e. PLAN's gap-protocol rule 4. Lands in S7, its
only consumer, default `false`, group "Picture wall", with one `ASSUMPTIONS.md` line.
**S8 then adds exactly the §5 rows and no more.**

**The implementer is a `general-purpose` agent carrying the `plan-implementer` persona inline,
not the `plan-implementer` subagent type.** That definition was added on this branch
(`8baef65`) and so exists only in this worktree; the overseer session runs from the main tree
and never loaded it. Copying it into main's `.claude/agents/` was refused — the main working
tree is off-limits for this run. The persona body, the report schema and the repo rules were
pasted into the spawn prompt verbatim, plus an explicit ban on spawning nested subagents
(the real definition omits the `Agent` tool to achieve the same thing).

**`ASSUMPTIONS.md` lives at `solatro/design/picture-wall/ASSUMPTIONS.md`** — PLAN cites the
bare filename; this is the sibling of `gaps/`. Fixed so two steps cannot create two files.

## Step ledger

Status: `pending` · `in progress` · `done` · `SUSPECT`. Each `done` step is one commit titled
`S<n>: …` — `git log --oneline` is the sha source, so shas are not copied here to go stale.

| Step | Status | Evidence proving the done-when | Files touched | Deviations | Gaps |
|---|---|---|---|---|---|
| S1 shader `TIME` under pause | done | flame does **NOT** advance. Overseer-verified: the t=0 and t=+20 s captures are **byte-identical**, `md5 4552e02bfa198039feb4e371219d5d1f` for both (implementer measured 0/746496 px). | `Tests/Visual/pause_time_spike.{gd,gd.uid,tscn}`, `design/picture-wall/ASSUMPTIONS.md` | none outstanding | NONE |
| S2 `accessibility_should_reduce_animation()` | pending | — | — | — | — |
| S3 `PictureEntry` + `WallLayout` | pending | — | — | — | — |
| S4 `WallPacker` (owes P1–P12) | pending | — | — | — | — |
| S5 `FocusStack` (owes F1–F7) | pending | — | — | — | — |
| S6 `Pacing` + `create_timer` sweep | pending | — | — | — | — |
| S7 `PlayerProfile` + `ProfileManager` (owes R1–R6) | pending | — | — | — | — |
| S8 `PlayerSettings` "Picture wall" block | pending | — | — | — | — |

### What S1 established — later steps depend on this

**Shader animation already stops under pause in this codebase, and not for the reason the
design assumed.** No shipped shader reads built-in `TIME`: `fire.gdshader:107` and
`fx_common.gdshaderinc:92` take a script-pushed `u_time`, driven by
`FxAttachment._process` (`UI/Fx/fx_attachment.gd:961`). `FxAttachment` and every ancestor sit
on the default `PROCESS_MODE_INHERIT`, and no shipped game code writes `process_mode` outside
the editor-only `Tools/fx_editor.gd:229` — so `_process` does not run while paused and the
clock simply stops.

That is Q222's option **(a)** — "every FX shader takes its clock from a CPU-fed uniform instead
of `TIME`" (`DESIGN.md:1159`) — already true by construction, while the design picked (c).
**No gap:** PLAN §2 pre-binds both S1 outcomes and says nothing changes either way. D7's hiding
is simply not load-bearing here.

⚠ **S12 (pause wiring) and S31 (the freeze) rest on this.** Both inherit their correctness from
`PROCESS_MODE_INHERIT` being untouched throughout the FX tree. A step that starts writing
`process_mode` inside `UI/Fx/` would silently un-freeze every effect.

Built-in `TIME` itself *does* keep advancing while paused (measured separately, 7350/120000 px
on a synthetic shader). True of the engine, irrelevant to this repo unless a future shader
starts reading it.

**Out of scope this run, though the test plan lists them:** F8–F13 (§6b) belong to S35/S38;
U5–U6 belong to S12. Do not create `TestWallPause` yet — a half-registered suite that a
later step rewrites is churn.

## Resuming after a lost session

The ledger above is a CLAIM. Ground truth is, in order: `git log --oneline -5`,
`git status --porcelain`, then a full suite run. If the suite is green **and** the
last-claimed step's done-when still passes, resume at the next step. Otherwise that step is
SUSPECT — `git reset --hard` to the last commit and redo it from scratch. Never resume
mid-step.

# HANDOFF — picture-wall shell, Phases 0–1 (S1–S8)

| | |
|---|---|
| Branch | `picture-wall`, worktree `C:\Users\khanr\Documents\GitHub\gamedev-picture-wall` |
| Branched from | `6945c6f` on main |
| Implementer agent | `wall-impl` — agentId **`a492ec69f51bbc374`**, address it by that id |
| Current phase | Phase 1 — S6 done, S7 next. **S4 PARKED on GAP-006**, S2 parked partial |
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

⚠ **Any one-off diagnostic scene must quit itself, and every Godot invocation needs an explicit
killing timeout.** A scene left sitting in its main loop hangs the run with no error and looks
like host flakiness; it is not. If a run stops producing output, check for live Godot pids and
kill them **by explicit `-Id <pid>`** — never by image name or wildcard, which
`.claude/hooks/block-process-kill.ps1` blocks outright.

⚠ **A brand-new `class_name` is not resolvable until Godot's global-class cache is rebuilt.**
Run one `--import` pass after adding one, or the next script referencing it by name fails to
parse. Also regenerate `.uid` files this way before committing: the repo tracks them (386 of
them, 9/9 in `Tests/Visual`), and a commit missing one is dirtied by Godot the moment it opens.

⚠ **`as` binds looser than `==` in GDScript.** `check(x == [&"a"] as Array[StringName], …)` casts
the *boolean result*, not the literal, and fails to parse. Type a local variable instead. Hit
while writing typed-array equality checks; S7's tests are the same shape.

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
| S2 `accessibility_should_reduce_animation()` | **partial — BLOCKED ON THE OWNER** | read-only half only: query = `false`; Windows `SPI_GETCLIENTAREAANIMATION` = `true` (animations enabled); query confirmed present on 4.7.1 via `has_method`. Consistent with tracking, **does not prove it** — one datapoint cannot answer a tracking question. | `Tests/Visual/reduce_animation_spike.{gd,gd.uid,tscn}`, `design/picture-wall/ASSUMPTIONS.md` | see below | NONE |
| S3 `PictureEntry` + `WallLayout` | done | overseer-verified by name: `@export` counts **10** (PE) and **6** (WL), every §1.1/§1.2 field present exactly once, every specified default literal present, **0 methods** in either file, `picture_rect.gd` correctly absent. Suite `ALL 31 SUITES: 2501 CHECKS PASSED`, errors log 0 bytes. | `Scripts/Wall/{picture_entry,wall_layout}.gd(+.uid)`, `Tests/Visual/wall_resource_load_spike.{gd,gd.uid,tscn}` | `class_name`/`extends` on separate lines, matching the repo's universal convention — syntax only, no field changed | NONE |
| S4 `WallPacker` (owes P1–P12) | **PARKED — GAP-006, owner decision** | not started; nothing written | — | — | **GAP-006** |
| S5 `FocusStack` (owes F1–F7) | done | overseer-verified: **exactly 5 methods**, the five §1.4 names and no sixth; 17 `##` comments; **7** test funcs, F1–F7 all referenced; `TestWallFocus` registered in `all_tests.tscn`; `_walk_stack` helper stayed test-side. Suite `ALL 32 SUITES: 2492 CHECKS PASSED`, `WALL FOCUS: ALL 31 CHECKS PASSED`, errors log 0 bytes. | `Scripts/Wall/focus_stack.gd(+.uid)`, `Tests/Wall/test_wall_focus.{gd,tscn}`, `Tests/all_tests.tscn` | none outstanding | NONE |
| S6 `Pacing` + `create_timer` sweep | done | **overseer-run suite** `ALL 32 SUITES: 2523 CHECKS PASSED`, errors log 0 bytes. Done-when grep: `grep -rn create_timer solatro/UI solatro/Levels solatro/Scripts --include=*.gd \| grep -v pacing.gd` → **0 lines**. `Pacing.wait` adopted 2/1/1 in `play_area.gd`/`game.gd`/`fx_attachment.gd`; `process_mode` still **0** in `fx_attachment.gd`. | `Scripts/pacing.gd(+.uid)`, `UI/play_area.gd`, `UI/Fx/fx_attachment.gd`, `Levels/game.gd`, `design/picture-wall/ASSUMPTIONS.md` | `as SceneTree` cast — §1.6's literal body does not compile; recorded in ASSUMPTIONS | NONE |
| S7 `PlayerProfile` + `ProfileManager` (owes R1–R6) | pending | — | — | — | — |
| S8 `PlayerSettings` "Picture wall" block | pending | — | — | — | — |

### Two defects found in PLAN.md's normative §1 — for the owner to amend at source

Neither is a gap; both are recorded in `ASSUMPTIONS.md`. Listing them here because §1 is the
section the owner reviews, and a plan whose literals do not compile will mislead the next reader.

1. **§1.6's `Pacing` body does not compile.** `Engine.get_main_loop()` is typed `MainLoop`, which
   has no `create_timer` — only its `SceneTree` subtype does. Shipped with an explicit
   `as SceneTree` cast, identical runtime behaviour.
2. **S6's done-when is imprecise.** It says the `create_timer` grep should return "only
   `Scripts/pacing.gd` and test files", but three hits live in vendored
   `addons/yard/editor_only/`. The vendored rule wins; the intent is "no bare `create_timer` in
   GAME code". `addons/` exempted.

### GAP-006 — S4 is parked, and this is the run's one real blocker

**Nothing fixes a ring's radius.** `Q10`=(c) fixes the ellipse's *aspect* — a ratio — and
`WallLayout` carries `gap_px`, `home_id`, the two aspect clamps and `view_margin`, none of
which set a scale. §1.3 rule 3 fills a ring "until the next picture's outer width plus `gap_px`
would exceed the ring's circumference" without saying what that circumference is.

It cannot be resolved locally, and the circularity is why: derive the radius from a ring's
contents and capacity becomes vacuous — no ring ever overflows, so `Q11`=(b), `G2`, **P2** and
**P3** describe behaviour that cannot occur; fix the radius first and capacity computes exactly
as written, but nothing fixes it. **P2's fixture ("ring 0 circumference fitting exactly 6")
cannot be constructed at all** until this is answered.

Options and a recommendation are in `gaps/GAP-006.md`. **Do not resolve it by picking one** —
it is closed by a new design version. §1.8's no-literals rule means the answer must land as
authored fields, not as constants in a `.gd`.

**Downstream and equally parked:** S10, S36, and the S34 tool all consume ring geometry.
Everything else in this run — S5, S6, S7, S8 — is untouched by it.

### S2 — what remains, and who can do it

**The overseer cannot finish S2.** Its done-when requires toggling the Windows animation
setting, and modifying a system/accessibility setting is the owner's action — not something the
overseer performs or delegates. The read-only half is done and committed.

**To close it:** the owner flips "Show animations in Windows", then the spike is re-run and the
second reading recorded. Same value as before → it does NOT track; flipped → it DOES track.

Blocks nothing in this run: S2's only consumer is **S18**, which is Phase 3 and out of scope.
Neither outcome is a gap — tracks → it seeds the first-launch default per GAP-005; does not
track → the seed is skipped and `wall_reduced_motion` defaults `false`, GAP-005's stated
fallback.

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

# PERFORMANCE.md — the optimisation survey

**This is a map of ANGLES, not a plan and not a backlog.** It exists so a future performance pass
starts from what this game actually is rather than from a generic 2D checklist, and so that the
things already tried, already measured, or measured to be worthless are not paid for twice.

- **There is no open engineering task in here.** FX performance is PAUSED by owner ruling
  (VFX.md §6). Items become work when the owner spends budget on them.
- **[FX_HANDOFF.md](FX_HANDOFF.md) §0d.10 is the authority for the FX half** — the priced lever
  menu, the ⛔ non-levers and the bench traps. Numbers repeated here are for orientation only; on
  any disagreement §0d.10 wins.
- **Every number below is tagged.** `MEASURED` carries its source and its box. `ESTIMATE` is
  arithmetic, not evidence. `UNKNOWN` means no instrument has ever pointed at it. **Do not let an
  ESTIMATE become a claim by being repeated.**

---

## 1. What kind of performance problem this game has

Three structural facts decide which optimisations can possibly matter here, and they rule out most
of a standard 2D checklist before it is opened.

**1. There is no physics.** No `Area2D`, `CollisionShape2D`, `RigidBody2D`, `CharacterBody2D` or
`RayCast2D` exists in any scene in this project; the only node of that family is one `Camera2D`.
There are **zero `_physics_process` functions** in game code. Board adjacency, targeting and slot
lookup are index math over `ArrayCardData`. So `PhysicsServer2D`, collision layer matrices, shape
simplification and physics tick rate are not levers here — they are levers for a game this is not.

**2. The renderer is GL Compatibility**, on both desktop and mobile presets, with
`default_texture_filter=0` (nearest) project-wide. That is the right choice for pixel art on an
Intel UHD target, and it sets the batching rules everything in §5b is scored against.

**3. The cost lives in two places, and only one of them has ever been measured.**

| | measured? | what it is |
|---|---|---|
| **The FX layer** — fire, juggling, embers, spotlight | **thoroughly** | fragment-bound shader work inside quads, plus one full-screen light pass |
| **The card layer** — the board itself | **never** | ~390 individually-materialled, individually-skinned `Polygon2D` and 78 autoplaying rigs on a full board |

Everything in §4 follows from that asymmetry. The optimisation pass that took the FX layer from
12.07 to 5.82 ms never looked at the thing drawing the cards, because no instrument in this repo
can see it.

---

## 2. The measured baseline

⚠ **Two different GPUs appear below and their absolutes are not comparable.** The Intel UHD is the
owner's slow box and the number that matters if this ships to laptops; the GTX 1070 rows are ratio
evidence only. Which box is which: `../.claude/memory/machine-profiles.md`.

### 2a. The FX budget — Intel UHD, `Tests/Visual/fx_cost.gd`, 3 runs, minimum taken

| row | ms | note |
|---|---|---|
| `burning + juggling, FULL SCREEN` | **5.82 GPU** | the worst window the game can build: 78 cards at board scale, every one burning AND juggling 5 lit balls. Owner has confirmed it is reachable in play |
| `burning, FULL SCREEN` | 4.66 GPU | ~80 % of the remaining FX cost |
| the juggling layer inside that window | ~1.2 GPU | |
| `_push_live`, 78 hosts / 234 quads | ~1.3 **CPU** | ⚠ the GPU timer cannot see this row; only `_cpu_row` can |
| tap slope on `fire_card` | 0.541 ms per tap | the cover ladder is ~2.16 ms of the 4.66 |
| everything else in card fire | ~2.50 ms | **no single item in here is large** — this is why the pass stopped |

**The owner's target is ~2 ms for ALL FX.** The saturated case misses it by ~3x. `MEASURED`,
FX_HANDOFF §0d.10.

### 2b. The rows that decided designs

| row | ms | source |
|---|---|---|
| card fire, BOX host x20 | 2.13 GPU | `Tests/Visual/fx_cost.gd` — Intel UHD |
| card fire, DEFORMED at rest x20 | 4.11 GPU | the radii branch is **~1.9x the box** before warp adds any fill |
| card fire, DEFORMED at ~25 % corner travel x20 | 4.90 GPU | what the shipped animation actually reaches |
| prop fire (hoop / knife) x20 | 1.21 / 0.36 | VFX.md §6.3 |
| per-cell ENGULF anchor, 20 hoops | **+21 ms** | dropped whole; more than a 60 fps frame |
| juggle balls / ball fire / both x20 | 0.52 / 0.69 / 1.20 | GTX 1070, AFTER the levers (was 1.28 / 1.68 / 2.37) |

### 2c. The spotlight — the only full-screen pass, and host count is the wrong axis

`Shaders/light.gdshader` shades the whole viewport every frame regardless of how many cards are
lit; its per-fragment work grows with the **light count**. Over a 1.947 ms empty-scene floor:

| lights | 0 | 1 | 8 | 24 | 64 (`MAX_LIGHTS`) |
|---|---|---|---|---|---|
| ms over floor | +0.478 | +0.607 | +1.537 | +4.666 | **+12.237** |

**≈0.19 ms per light, near-linear.** A realistic section (5–12 lights) is ~1–2.5 ms; 64 would blow
a 16.67 ms frame on its own. `MEASURED`, todo.md G2.3. Nothing was trimmed — that cut is an owner
call, not an agent's.

⚠ **The GLOW is still unpriced.** There is no `FxGlow` effect class, only `Shaders/glow.gdshader`
riding the `FxAttachment` path, so no bench row isolates it.

---

## 3. The instruments, and what each one cannot see

| instrument | sees | blind to |
|---|---|---|
| `Tests/Visual/fx_cost.tscn` | FX quad fill cost, the spotlight sweep, the tap sweep, `_push_live` CPU | everything outside the FX layer; anything not drawn at all |
| `Tests/Visual/fx_snapshot.tscn` + `fx_behind.tscn` + `prop_art_snapshot.tscn` | whether pixels changed | time |
| `Tools/snapshot_diff.py` | "nothing moved", across 31 panels | intent — it cannot say a change was *good* |
| `Scripts/event_log.gd` + `Tools/spotlight_tool.tscn --trace` | behaviour over TIME, ordering, per-frame sequencing | cost |
| `all_tests.tscn` (PIXELS suite) | correctness of what is drawn | cost |
| — | **the card layer's draw calls, skinning, `_process` and allocation** | **nothing measures these** |

### The traps, each of which has cost real time here

1. **`fx_cost` cannot tell "cheap" from "not drawn."** One build read 10x faster because it was
   culling most of its balls. Gate on `all_tests.tscn` or `fx_snapshot`, never on `fx_cost` alone.
   **A number that beats your own prediction is a bug report.**
2. **`fx_cost` cannot see CPU you add elsewhere.** A lever once made a deforming card rebuild its
   mesh every frame; the bench's hosts never deform, so the row stayed green while the game got
   slower. **Wall clock rising while the GPU timer falls is the signature.**
3. **Run a rendering harness twice.** The rotated and fire panels disagree with themselves run to
   run. A red picture from one run is not a red build.
4. **Do not A/B an animated suite without `git diff Tests/all_tests.tscn` first.** The scene's
   `speed_base_delay` decides whether some UI checks can pass at all, and the editor drops it —
   that one cost five bisects (VFX.md §7.9).
5. **On a box whose GPU timer is bimodal, three runs, take the minimum.** One run is not evidence.
6. **When a menu of knobs each buys 10–40 %, fit a cost model and check it for TWO wrong factors.**
   That is the lesson of §0d.6: not one of nine priced levers was what worked, and the structural
   change beat all of them at once.

---

## 4. The dark half — the card layer

**Nothing in this section has a number.** It is here because the arithmetic is suggestive enough
that measuring it should precede spending on anything in §5.

### 4a. What a card costs to exist

`Cards/card_visual.tscn` is **27 nodes**: a `Skeleton2D` with 17 `Bone2D`, an `AnimationPlayer`,
and **5 `Polygon2D`** — which are exactly the outline shader's five clients (the `Type` face, the
rank / suit / stamp pips, and the card art).

Each of those five carries **its own `ShaderMaterial`** (`Cards/card_outline.gd`, `material_of`),
because `u_frame_uv`, the fill mode and the alert state are per element. The material is created on
first use and reused across rebinds — that was already a deliberate cost decision, and it is the
right one — but it is still one material per polygon.

On a full board that is:

- **~390 canvas items with 390 distinct materials**, none of which can batch with any other
- **390 skinned polygons**, whose vertices Godot recomputes on the CPU whenever the rig moves
- **78 `AnimationPlayer`s, each driving 17 bones — but they sit IDLE.** `card_visual.tscn` does not
  autoplay its idle animation (`CardVisual.RIG_ANIM`) and nothing else writes a `Bone2D` position, so
  a card with no active tween is genuinely AT REST. ⚠ **The skinned-polygon recompute above and the
  FX layer's per-frame outline re-read are therefore far cheaper than a moving rig would make them —
  re-measure before pricing either.** `CardVisual._track_fx_outline` could be skipped entirely while
  the rig is unposed; not taken, because FX perf is paused (VFX.md §6).

`ESTIMATE`, from node arithmetic. No bench exists.

### 4b. The per-frame work every card does whether it needs to or not

`Cards/card_visual.gd` `_process` runs **unconditionally on every card in every view**:

- position easing and anchor tracking
- tilt/bob juice (gated to `PLAY_AREA`, correctly)
- `_track_fx_outline()` — **~24 `atan2` plus a wedge index, every frame, lit or not**
- `_advance_alert` (correctly gated on `_alert` being live — this one is already right)

⚠ **`_track_fx_outline` is the known one.** VFX.md §6.5 calls it *"the single biggest per-frame win
in the layer"* and records that the obvious guard — `if _fx.is_empty(): return` — **was applied and
broke `PIXELS / the mask and the drawn face agree in EVERY FX cell` at 3 of 4 phases**, because
`_poly` is a *published property*, not a cache for the quads, and the check that reads it must read
it off an **unlit** card. A guard at the call site has the same problem. **Collecting this needs
the resolve made cheaper or the HOST made to stop calling** — not a guard. The reasoning is
repeated at the guard site in the code; read it before touching this.

### 4c. Allocation churn

| site | what happens |
|---|---|
| `Cards/card_visual.gd` (`add_child_card_visual`) | a whole 27-node scene is `instantiate()`d per card entering a view, and `queue_free`d on leaving — **9 `queue_free` sites in that one file** |
| `UI/text_popup.gd` | one scene instantiated per popup |
| `Cards/card_visual.gd` (`create_move_tween`) | a `Tween` per card per move |
| `UI/big_number_label.gd` (`anim_pop`) | a `Tween` per score update |

The *contents* of a card are pooled (polygons, per-slot controls, materials). **The card scene
itself is not.** `ESTIMATE` — churn is visible in the code, its frame cost is not.

### 4d. The bench that would have to exist

`Tests/Visual/fx_cost.gd` is the template: an empty-scene floor, `WARMUP`/`FRAMES` averaging, a
`_cpu_row` that times a real call in a loop against `Time.get_ticks_usec()`. A board bench would
add rows for:

- N cards at rest, rig autoplay ON vs OFF — isolates skinning + animation
- N cards with `_process` on vs off — isolates §4b
- N cards, draw calls counted via `Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)`
- the deck viewer's 50+ card screen, which is the densest the game builds
- an instantiate/free churn row — cards cycling in and out

⚠ It must obey trap 1: **assert something is actually drawn**, or a culled board will read fast.

---

## 5. The angles

### 5a. GPU and fill rate

| angle | how it applies here | gain | risk / what it fights |
|---|---|---|---|
| **`cover_taps` 4 → 2 on `fire_card`** | the tap count is the cover ladder's whole cost curve | **0.98 ms `MEASURED`** (5.062 → 4.085 on the sweep) | **a LOOK the owner owns.** FX_HANDOFF §0e argues against: a card flame is 7 FX pixels tall, so 2 taps is 3.5 px/tap and the fire stops hugging the art, thin features get straddled entirely, and the vertical gradient collapses to two bands. Show `00_cover_field` and `01_fire_ladder` side by side before asking |
| **20-point diagonal chamfer** instead of the exact 24-vertex corner bite | the exact mask measured at 16 % of a burning screen; the cost is the array's size | ~0.3–0.4 ms `ESTIMATE`, unmeasured since the last lever landed | an ACCURACY trade the owner should see — same pixels on the FX grid, approximate off it |
| **`fire_card.height` down from 7** | a FILL knob as much as an art one: the lit band is `height + sink` thick around the whole silhouette | ~0.2 ms per unit `ESTIMATE` | a LOOK the owner owns |
| **A specialised card-fire shader** — one program per shape | a BOX host measured **25 % dearer purely from carrying two uniform arrays it never enters**, so program size costs real time on this GPU | `UNKNOWN`; that 25 % datum is the only reason to believe in it | fights "one shader per effect"; duplicates the cover/noise/ramp tail unless that tail is extracted to a shared `.gdshaderinc` first |
| **Spotlight light budget** | ≈0.19 ms per light, near-linear, independent of host count | 0.19 ms per light removed `MEASURED` | pure design: how many lamps a section may light. `MAX_LIGHTS = 64` is a cliff, not a budget |
| **Price the GLOW** | it rides `FxAttachment` with no effect class and no bench row | `UNKNOWN` — this is a measurement, not a lever | cheap: one row in the existing bench |
| **Mipmaps / texture compression** | ⛔ **actively forbidden.** `Shaders/outline.gdshader` rule 4: nearest filtering, no mipmaps, or the taps blur and the frame clamp leaks fractional texels from neighbouring frames | negative | enabling this breaks every outline in the game |
| **`Light2D` / shadow tuning** | N/A and already better — the spotlight is one custom full-screen pass, not a pile of `PointLight2D` | — | — |
| **`Parallax2D` culling** | N/A — no parallax layers exist | — | — |

### 5b. Draw calls and batching

**The card layer cannot batch today, and materials are only half the reason.**

Godot's Compatibility renderer batches consecutive canvas items sharing a material and texture.
Card polygons share neither — 390 distinct `ShaderMaterial`s — and **even if they did, a
`Polygon2D` bound to a `Skeleton2D` is CPU-skinned into its own item**. Unifying materials without
addressing the skinning buys nothing.

| angle | how | gain | risk |
|---|---|---|---|
| **Board-wide FX MultiMesh** — one MultiMesh per LAYER instead of per host | collapses 234 draws and 234 uniform sets to a handful | attacks the **~1.3 ms CPU row**, not GPU | wide: fights the attachment-per-host architecture that makes "FX shared across all views" free (owner rulings 7, 18). **Do not start without re-measuring the CPU row first** |
| **Shared material + per-instance data for card elements** | frame UV and palette role move into `INSTANCE_CUSTOM`, the way the juggling layer already does | `UNKNOWN`, potentially large | **blocked by the skinning** — see above. Only viable together with the next row |
| **Rig-at-rest fast path** | a card whose rig is not moving needs no re-skin and could be a static, batchable item | `UNKNOWN` | the autoplay is deliberate (cards breathe). Whether *every* card must breathe *always* is an owner call |
| **`RenderingServer` direct draw** | not used anywhere in game code today. The honest target is small static elements (pips, stamps), not cards | cuts node count, **not** draw calls unless paired with a shared material | high complexity, low ceiling on its own |
| **Texture atlases** | already done — `card_types.png`, `suit_pips.png`, `stamp_pips.png` are gutter-less sheets | 0 further, while materials stay per-polygon | ⚠ the missing gutter is why the frame clamp in the outline shader is not optional |
| **`z_index` / draw-order grouping for batching** | ⛔ not available as a lever: board draw order is **structural** (node order, no `z_index` — LAYERING.md). Reordering to help batching would reorder the game | — | — |

### 5c. Scene tree and per-frame CPU

| angle | how | gain | risk |
|---|---|---|---|
| **Visibility culling for cards** | `UI/Fx/fx_attachment.gd` already has `_on_screen()`; cards have nothing. Play-area cards live inside a scroll container, so scrolled-out cards still ease, tilt and walk their rig. The deck viewer is denser still | `ESTIMATE`: most of §4a+§4b for off-screen cards | ⚠ a card must be fully re-synced before it is drawn again; the FX layer's per-host randomness is read **when the quads are built**, so ordering matters (VFX.md §4.3/§4.4) |
| **`_track_fx_outline`** | §4b — make the resolve cheaper or stop the host calling it | `ESTIMATE`: ~24 `atan2` x up to 128 cards per frame | ⛔ **the naive guard is a known regression.** Read the guard site's comment first |
| **Pause the rig when it cannot be seen** | `AnimationPlayer.pause()` / `speed_scale = 0` off-screen; `PROCESS_MODE_DISABLED` on card subtrees behind a full-screen menu | `ESTIMATE`: removes 17-bone evaluation + 5 re-skins per card | the deformed outline feeds the FX mask; anything paused must be resumed **before** `sync()` |
| **`VisibleOnScreenNotifier2D` specifically** | awkward here — cards are Control-anchored and scroll with their content. A rect test against the scroll viewport in `UI/play_area.gd` / `UI/deck_viewer.gd` is the cheaper shape | see culling row | a notifier is one more node on a 27-node scene |
| **`SubViewport` refresh limits** | only `Scripts/Map/world_map_controller.gd` uses one in game code. If the map is static while open, `UPDATE_WHEN_VISIBLE` or `UPDATE_ONCE` | small `ESTIMATE` | cheap, low risk, easy to verify by eye |
| **`set_process` discipline generally** | already correct in `UI/Fx/fx_attachment.gd` and `UI/play_area.gd`; **absent in `Cards/card_visual.gd`** and worth auditing in `UI/prop_layer.gd` / `Cards/Props/prop_visual.gd` | `ESTIMATE` | `UI/prop_layer.gd`'s `_process` re-derives data→visual facts live *on purpose* — two owner reports came from capture-at-spawn. Do not "optimise" that into a bug |
| **Third-party `_process`** | the `SmoothScroll` addon runs a `_process` per scroll container | small `UNKNOWN` | vendored; changing it is a maintenance cost |

### 5d. Allocation and churn

| angle | how | gain | risk |
|---|---|---|---|
| **Pool `CardVisual`** | §4c — a free list keyed by nothing (cards rebind their data anyway; the polygons and materials are *already* rebind-safe by design) | `UNKNOWN`, likely a stutter win rather than an average-frame win | ⚠ **rebind hygiene is the whole risk.** `Cards/card_outline.gd`'s loud note explains why a pooled polygon may never be left material-less; a pooled *card* multiplies that surface. Pooled per-slot controls already derive state on bind and never cache it — a card pool must hold the same line |
| **Pool `TextPopup`** | same shape, much smaller surface | small `ESTIMATE` | low |
| **Tween reuse** | `Cards/card_visual.gd` and `UI/big_number_label.gd` already `custom_step(INF)` a running tween before replacing it, which is the correct idiom | ~0 further | — |
| **Array pre-sizing** | already done where it matters — `UI/Fx/particle_engine.gd` resizes six `PackedFloat32Array`s up front and evicts oldest-first through a ring head | 0 | — |
| **`call_deferred` for state mutations** | 15 sites already. The candidate is a frame where many card rebinds land at once after a board mutation | smooths spikes, no average win | ⚠ deferral interacts with the `GameData.revision` bump ordering — the bump must still follow consistency |

### 5e. Code and math

| angle | status here |
|---|---|
| **Static typing** | already enforced as **errors**, not warnings: `untyped_declaration=2`, `unsafe_method_access=2`, `unsafe_property_access=2`, `unsafe_call_argument=2` in `project.godot`. Nothing to gain |
| **`WorkerThreadPool`** | already used by `worldgen` for the pure-CPU pipeline steps (`add_task`, `add_group_task`). The remaining candidate is background save serialisation at scale, which is flagged unverified in todo.md |
| **GDExtension / C++** | already built and shipping for `worldgen`, with a **GDScript fallback at every call site** — so a missing dll degrades silently to slow-but-correct. ⚠ If something is mysteriously slow, check the dll registered *before* profiling anything |
| **C# migration** | not applicable — no C# in the project, and the hot paths identified here are engine-side (skinning, draw submission), not GDScript arithmetic |
| **`AStar2D` throttling** | not used. The map is a `worldgen` graph generated once, not per-frame pathfinding |
| **Hot-path idioms** | already the house style and documented in START_HERE.md: O(n) max, no recursion, single-pass traversals, `PackedArray`s for numeric data, `&"StringName"` for engine-name APIs, `"%d" %` over concatenation, signal-driven over `_process` polling |
| **`UI/autosize_label.gd`** | refits on every `resized` via a binary search over font sizes, then calls `add_theme_font_size_override` — which can itself resize. Worth confirming it settles rather than oscillating on a card that animates its size. `UNKNOWN` |

### 5f. Engine and project settings

| angle | note |
|---|---|
| **`physics_interpolation=true`** | set in `project.godot` with **zero physics bodies in the game**, and `UI/Fx/fx_attachment.gd` explicitly sets `PHYSICS_INTERPOLATION_MODE_OFF` on the juggle MultiMesh to work around it. Cards move in `_process`, which is the case global interpolation handles worst. **Whether this is deliberate (the world map) or inherited has not been established** — it is a one-line experiment, and it is the first thing to check in this section |
| **Physics tick rate** | default 60, nothing runs in `_physics_process`. Lowering it is near-free and near-worthless; it is listed only so nobody spends an afternoon on it |
| **`window/size/always_on_top=true`** | a development convenience visible in `project.godot`; unrelated to cost but worth a glance before shipping |
| **vsync / `max_fps`** | manipulated only by `Tests/Visual/fx_cost.gd`, which disables vsync deliberately so rows do not all report the refresh interval. Not a game-side lever |

---

## 6. Ruled out — do not re-tread

Each of these cost real time in a previous pass. FX_HANDOFF §0d.10 holds the authoritative list;
these are the ones most likely to be re-proposed by someone reading a generic checklist.

- **A ring / strip mesh around the silhouette.** Honest area arithmetic is 1.75x, not the 2.5x an
  earlier draft claimed — and the buried-fragment early-out already removed the whole interior from
  the expensive path. ~0.3 ms for a triangle strip, a reflex-corner problem on a deformed outline,
  and a per-frame vertex budget.
- **The noise source.** Procedural vs the baked tile has measured **flat three separate times**.
  It is a look knob, not a cost knob.
- **`FxStyle.pixel` ("chunkier FX pixels must be cheaper").** It quantizes a *coordinate inside the
  fragment shader*; the quad's screen footprint is unchanged and **the shader still runs once per
  screen pixel**. This one is convincing and wrong, which is why it is listed twice in this repo.
- **`cover_taps` on `fire_ball`.** The ball branch solves for the tap index with one `sqrt`, so that
  quad pays no mask lookups at all.
- **The arc maths.** Hoisted out of the fragment stage entirely; it is 4 evaluations per ball per
  frame now.
- **Shrinking a quad to `body_near`'s box.** Rejected fragments are ~1/26 the cost of an accepted
  one. **The win is always in the ACCEPTED area.**
- **Anything physics-shaped.** See §1.
- **Mipmaps.** See §5a.

---

## 7. If budget is spent, this is the order

1. **Measure the card layer** (§4d). Every §5b/§5c estimate is unfounded until this exists, and this
   project's own history is emphatic: not one of nine priced levers in the last pass was what
   worked, because the cost model had two wrong factors.
2. **The `physics_interpolation` question** (§5f) — one line, immediate answer.
3. **Card visibility culling** (§5c) — the largest structural candidate that fights nothing.
4. **Rig pausing** (§5c) — bundles naturally with 3.
5. **`_track_fx_outline`** (§4b) — known win, known trap, needs a real fix rather than a guard.
6. **Price the glow** (§5a) — a measurement, cheap.
7. Only then the FX knobs, which are owner LOOK calls: `cover_taps`, `fire_card.height`, the
   spotlight's light budget.
8. Structural FX work (board-wide MultiMesh, specialised shader) last — widest blast radius,
   least certain payoff.

---

## 8. What any pass here owes

1. Full suite green, **WINDOWED**, with the suite count checked — a dropped suite still prints
   "ALL n SUITES PASSED" with a smaller n (VFX.md §3).
2. Re-run whichever snapshot harness the change touches and **look at the PNGs**; use
   `Tools/snapshot_diff.py` for "nothing moved", never your eye.
3. Three runs of `fx_cost`, minimum taken, and **wall clock watched against the GPU timer**.
4. Every new number recorded with the box it came from and how it was produced, so it can be re-run.
5. Fold regression-critical residue into ARCHITECTURE_REVIEW.md, open items into todo.md, and keep
   this file's §2 baseline current.
6. No `git add`, no commits.

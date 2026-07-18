# SOLATRO — Scoring & Goal Math Plan

> **⭐ The settled design lives in §15 (FINAL REPORT).** Sections 1–14 are the working
> record: measurements, rejected branches, and the reasoning that led there.

Compiled 2026-07-16 from `Desktop/scoring_goals_math.txt`, verified code exploration, and
Monte Carlo measurement (`tools/scoring_sim.py`, exact `ScoreModel` port — every number in
this doc marked **[measured]** was produced by that harness with seeded runs; rerun any
table with the CLI line quoted beside it). **No game code changes ship with this doc** —
everything is mocked in the sim until the formulas are settled; §9/§12 record where each
toggle WILL live when the playtest phase starts.

**Status legend** (DESIGN_DOC.md conventions):

| Tag | Meaning |
|---|---|
| ✅ IMPLEMENTED | Exists in code today |
| 🔨 PARTIAL | Started/stubbed in code |
| 📋 DESIGNED | Settled design, not yet built |
| 💭 SKETCH | Raw idea, not yet committed to |
| ❌ REJECTED | Considered and vetoed, with reasons |
| 🧪 MEASURED | Number produced by the sim harness |
| 🎮 PLAYTEST | Decision deferred to the in-game A/B protocol (§10) |

---

## 1. The question (refined prompt)

Derive a scoring + goal-curve system where:
- **(a)** act pacing is a genuine decision — dumping the deck into one act is *viable but
  not dominant*;
- **(b)** score growth from deck size, card mods, and skill is matched by goal growth so
  win probability at par play stays in a target band (~85–92% per show for skilled-casual
  at par deck; <50% by mid-map with no deck upgrades);
- **(c)** every acquirable mod has measurable, non-decaying leverage;
- **(d)** numbers stay legible (≤4–5 digits through lap 1).

---

## 2. How a typical game scores today ✅ (verified in code)

- Show = 3 acts (`Game.MAX_SUBMITS`, Levels/game.gd). Next deals 5 cards → Entrance;
  the previous Entrance drops into the 6-column Ring. Submit scores **every Ring row and
  column** as the best single poker hand each, then `GameData.apply_act_score()` pays
  **`(Σ row scores) × (Σ col scores)`** into `total_score`; the Ring is discarded, the deck
  never reshuffles (24-card deck ≈ one show).
- Hand values (Scripts/scoring.gd `ScoreModel`): x-of-kind `n(n−1)`, straight `2n` (≥5
  consecutive, wrap 13→1), flush `2n` (≥5 suited), house scale-s
  `(3s(3s−1)+2s(2s−1))·1.5`, one-suit structure ×2, m copies ×`(1+0.5(m−1))` (sets ramp
  from the 3rd copy). A line's score = **best single Result**, not a sum.
- Goal (Scripts/run_manager.gd `goal_for`):
  `100 × 1.15^progress × 2.5^lap × (1 + 0.25·Σoverscore_ratio)^1.5`, ×2 boss.
  Fame = Σ won totals → `luck()` gates booster rarity. Boosters ≈ 1 per 3 nodes, 5 cards,
  take-all, no removal, no shop.
- Starting deck (deck11, 24 cards): ranks 1–4 only → **straights impossible at run
  start**; 8 ExtraPoint skill cards (+10 flat, topmost-only, bypasses the multiply); prop
  mods bank +1s into row/col **gutters, which DO get multiplied** by the opposite axis.

### 2a. Prop scoring (modeled term, currently the sim's weakest)

Suits are prop-spawners (spawn count = card rank; a talented card suppresses its OWN
suit's effect). During act resolution (`Game.run_props`, integer ticks):
**Knife** sweeps its row, +1 into that row's gutter per plain card passed; **Hoop** is the
mirror sweep for skilled cards; **Firework** banks into its column gutter; **Ball/Fire**
drop Juggling/Burning statuses (Burning buffs a card's suit-effect count — the one
*compounding* prop term). Every prop point routes through `add_line_score()` → gutters →
`row_total`/`col_total`, so **every prop point is multiplied by the opposite axis** under
CROSS; only ExtraPoint (+10) bypasses the multiply. The sim models props as **static
rank-weighted gutter points** (documented simplification); Burning cascades are a
measured-in-game correction factor. Full prop reference: `PROPS_BUGFIX_HANDOFF.md`.

---

## 3. Measured baseline 🧪 (`py tools/scoring_sim.py --baseline`, 2000 trials, seed 42)

| Policy (cards/act) | Arrangement | 3-act total mean (p10–p90) | Act-1 payout |
|---|---|---|---|
| 8/8/8 | random | 174 (132–222) | 42 |
| 8/8/8 | rank-rows | 308 (274–348) | 80 |
| 20/4/0 | random | 369 (232–528) | 327 |
| 20/4/0 | **suit-columns** | **1,274 (866–1,775)** | 1,252 |
| 52-card 17/17/18 | suit-columns | 646 (484–832) | 201 |

Act payout vs board size (deck11, random): 8→42, 12→90, 16→180, 20→327, 24→600 —
**growth exponent ≈ 2.4 in N** (local exponents 1.9→3.3, accelerating). Current goal
curve: node 0=100, 5=201, 8=305, 12=535.

### 3a. Diagnosis — R×C is unbalanced in four specific ways 🧪

1. **Concentration**: dump 20/4/0 beats even 8/8/8 by ×2.1–2.7 depending on arrangement
   (additive R+C: ×1.13) — a dominant strategy; acts are fake choices.
2. **Deck size is a hidden ×mult**: dS/dN ≈ 2.4·S/N — a **blank card** out-leverages
   designed mods late; goals (1.15^k) can't track N^2.4 without the overscore hack.
3. **Two mod currencies**: gutter +1 is worth ~the opposite axis total (grows with the
   board); flat +10 never scales — incomparable, untunable.
4. **Overscore detonation**: one skilled node-0 clear (1,274 vs goal 100) inflates node 1
   to ≈ 910 ≈ p10 of the *best possible* strategy — a wall from one good show.

---

## 4. Candidate framework 📋

**Primary variant V2-A (combo-mult):**
`payout = (R + C) × (1 + w_r·row_melds) × (1 + w_c·col_melds)`, melds = lines scoring
above a lone high card. Bounded concentration, near-linear in N, unifies all adders into
one multiplied currency. Only `apply_act_score()` changes (implemented as the COMBO
toggle, §12). **Sweep correction 🧪: the planned w=0.5 measures concentration ×2.6 — out
of band, because meld counts themselves grow with dump size. w=0.25 lands at ×1.72.**
Shipped default weights are therefore 0.25/0.25.

**Control variant V7 (embrace the quadratic):** keep R×C, re-anchor `G0` to skilled p15
and grow goals as `(N̂(k)/24)^2.4` — equivalently, calibrate goals by quantile (§6) under
the CROSS rule. Measured as `V0CAP` in the full-run tables (§8).

**Sub-variants (toggles on either):**
- **No high-card floor** (meldless lines score 0). 🧪 Measured: *raises* concentration
  (V0 ×2.4→×4.0, V2A ×2.6→×3.2) — disorganized dumps lose little (floor points were
  already trivial) while even play loses its baseline. **Rejected as a
  concentration fix; keep only if the "dead lines score nothing" feel is wanted.** ❌/🎮
- **Unused-act bonus** `total × (1 + b·acts_unused)`, b≈0.25 🎮 — rewards confident
  single-dumps and makes even play's deficit acceptable (band: ≤1.2× deficit).
- Organization pressure is real (random vs oracle ×1.7–2.3 at 24–32 cards 🧪) and real
  dump boards are *harder* to arrange than the sim's oracle — helps difficulty, unquantified.

### 4a. Uniqueness combo bonus 🧪 (owner design 2026-07-17)

Idea: reward each **distinct meld identity** on one board once (duplicates still score
base, they just don't raise the combo count U); mods count as identities too. Owner intent:
less punishing than penalizing repeats, rewards spreading duplicates across acts, and
incentivizes pulling duplicates out of dumps. Sweep on the proposed 20-card starting deck
(ranks 1–5 × 4 suits, no modifiers), `py tools/scoring_sim.py --combo`:

| Attachment | conc (dump/even) | even / dump means | Reading |
|---|---|---|---|
| none (R×C baseline) | 2.85× | 57 / 163 | this deck's baseline |
| **payout × (1+u·U)**, u=.25/.5/1 | **4.10 / 4.78 / 5.53×** | 78–144 / 321–797 | worst option — see below |
| flat + k·U, k=10/25 | 2.17 / **1.78×** | 96–154 / 208–275 | best conc; decays over a run like ExtraPoint unless k scales per node |
| (R + k·U) × C, k=5/10 | 2.18 / 2.03× | 153–248 / 333–503 | scales with the board (multiplied currency), good conc |
| R × (C + k·U) | 3.82 / 4.06× | | bad — cols are the small side under rank-row play; asymmetric |
| dedup penalty (repeats ×0.5 / ×0) | 2.69 / 2.53× | 54–56 / 136–149 | surprisingly weak, see below |
| coarse identity: mult / dedup f=0 / row k=10 | 3.71 / 2.03 / **1.95×** | | coarse tags bite harder everywhere |

Mean distinct-identities per show: even 3.9, dump 4.5 (fine tags); 3.1 vs 3.3 (coarse).

**Findings:**
1. **U grows with board size** — a 16-card dump board *contains more distinct meld kinds*
   than three small boards, so any reward keyed to per-board uniqueness favors the dump.
   As a top-level multiplier it compounds with the R×C quadratic → the worst measured
   attachment. A combo bonus is a *satisfaction/pacing* mechanism, not a concentration fix.
2. **The dedup penalty barely bites** (2.85→2.53) because the dump surplus isn't repeats —
   it's a few *big, mutually distinct* melds (quad of 1s ≠ quad of 2s ≠ 5-oak). Even
   coarse identity + repeats-score-zero only reaches 2.03.
3. **Identity granularity is the real dial**: coarse ("any pair is a pair") lowers every
   concentration number vs fine ("pair of 2s ≠ pair of 3s"). Coarse + additive row
   attachment (k=10) is the best scaling option measured: ×1.95.
4. Per-act counting already rewards spreading duplicates across acts (each act re-earns
   its identities); a per-show "only NEW identities count" rule would instead neutralize
   even play's re-earning — don't.

**Crossover analysis 🧪 (`--crossover`): when does even play beat the dump?**
For a flat combo (`payout + K·U` per act) the K→∞ concentration limit is
`ΣU(dump)/ΣU(even)`; for a multiplier (`payout×(1+u·U)`) the u→∞ limit is
`Σ(pay·U)dump / Σ(pay·U)even`. Measured (dupes decks, degraded f=0.6):

| Deck | Identity | U/show even vs dump | flat K=25 / K=100 / K→∞ | mult u=1 / u→∞ |
|---|---|---|---|---|
| 20 | coarse | 3.1 / 3.3 | 1.82 / 1.35 / 1.08 | 4.79 / 6.34 |
| 20 | class (arch+size) | 2.9 / 2.7 | 1.78 / 1.25 / **0.94** | 4.28 / 5.55 |
| 20 | archetype | 2.7 / 2.1 | 1.70 / 1.12 / **0.76** | 3.62 / 4.39 |
| 32 | class | 4.8 / 4.8 | 3.62 / 2.28 / 1.01 | 9.88 / 12.64 |
| 32 | archetype | 4.1 / 2.9 | 3.67 / 2.24 / **0.72** | 6.99 / 8.32 |
| 44 | class | 6.3 / 6.3 | 7.93 / 4.84 / 1.00 | 22.02 / 27.15 |
| 44 | archetype | 4.5 / 3.4 | 8.47 / 5.53 / **0.77** | 15.97 / 19.50 |

Readings: **as a multiplier, even play NEVER wins** — at any strength, granularity, or
deck size (limits 4.4–27), because the dump's per-act `pay×U` product dominates.
**As a flat post-multiply bonus with class-level identity, even play wins in the
strong-combo limit** (≤1.0 everywhere; archetype counting flips hardest, 0.72–0.77):
U caps per board (archetype: ≤4 classes), so three boards harvest up to 3× the combo of
one big board. The crossover is therefore not a deck size — it's a **combo-share**: the
larger K's share of the total, the closer to parity. K must scale with the score curve
(a fixed K fades exactly like ExtraPoint as R×C grows — visible in the K=25 column
worsening with deck size).

**Recommendation 📋:** ship the combo as `payout = row_total × col_total + K(node) · U`,
U = distinct **meld classes** on the board (duplicates still score base), with
`K(node) = γ · goal(node) / E[U per show]` so combo is a fixed goal-share γ at every
node; γ is THE dump-vs-even dial (γ≈0.3–0.5 puts concentration in the 1.3–1.8 band,
γ→1 approaches parity). Do NOT ship it as a payout multiplier. UI framing: a "Combo"
counter that banks K per new meld class as it reveals.

### 4b. Capacity arrangement model + float combo 🧪 (owner spec 2026-07-17, supersedes §4a's K(node))

Owner rulings: combo is a **float multiplier on the act payout, ×1.0 + 0.1 per unique
meld class** (classes = type+size+copies; rank/suit variants NOT distinct; multiples and
flush variants ARE distinct classes); resets per act; mods add U on first activation of a
unique effect; no unused-act bonus; difficulty = a scalable float (the quantile knob q);
K(node) rejected as illegible — correctly, since a payout *multiplier* is scale-free and
needs no per-node constant. The concentration objection to multipliers (§4a) was measured
under proportional arrangement; owner's model instead: **fixed arrangement capacity** —
a player can ideally place ~C cards per act, the rest fall as dealt, so big boards are
inherently disorganized. `--capacity` results (deck ranks 1–5 dupes, coarse classes):

| Deck | cap C | conc, no combo | conc, +0.1/U | conc, +0.2/U |
|---|---|---|---|---|
| 20 | 6 | **0.98×** | **1.11×** | 1.22× |
| 20 | 9 | 1.09× | 1.23× | 1.34× |
| 20 | 12 | 1.29× | 1.45× | 1.59× |
| 32 | 9 | 3.00× | 3.69× | 4.18× |
| 44 | 9 | 5.75× | 7.37× | 8.40× |

**The owner's model is confirmed at the starting deck**: with capacity ~6–9, dumping is
already NOT dominant at 20 cards (conc ≈ 1.0–1.2), and the float combo sits comfortably
in the [1.3, 1.8] band's lower half. **But at 32+ cards dump re-dominates with ZERO
arrangement** — a random 28-card board of ranks 1–5 dupes is saturated with collisions;
that's deal luck, not skill. Widening the spread as the deck grows fixes 32
(1–8 → ×1.72, 1–13 → ×1.38) but not 44 (1–13 → ×3.69): R×C over an unbounded board area
eventually beats everything. Conclusion: the float combo + capacity model ships, and
**deck growth is the safety valve** — either (a) the acquisition schedule keeps the deck
≤ ~32 through lap 1 with spread extensions accompanying growth, (b) the Ring physically
caps cards-per-act, or (c) late-game goals are calibrated against the dump policy
(dump-as-endgame becomes the intended power fantasy, priced into the curve). 🎮 owner call.

**Rejected combine rules ❌ (with reasons):** normalized R×C/(k+N) (adding a card can
*lower* payout), sqrt compression (illegible, kills concentration entirely), best-line-only
(90% of the board is dead), hard axis caps (feel-bad, eternal re-tuning).

**Decimals:** keep integers as the player-facing currency, floats internally, **round once
per act payout** (fixes compounding `int()` truncation). If finer granularity is ever
needed, multiply all bases ×10 — never introduce visible decimals. 📋

---

## 5. Mod-leverage unit — GSP (Goal Share Points) 🧪

`GSP = median Δ(total) from adding the mod to the par deck ÷ goal(k)`, measured at nodes
{0,5,8,12}, mid policy, degraded arrangement. Tiers: S ≥25%, A 10–25%, B 3–10%, C <3%
(dead). Acceptance rule: **a blank card must not out-rank designed mods.**

`py tools/scoring_sim.py --gsp --trials 1500` (mod = the same base deck + 1 appended card):

| Node (deck) | Mod | V0 GSP | V0 tier | V2A GSP | V2A tier |
|---|---|---|---|---|---|
| 0 (24) | blank card | 4.1% | B | 5.4% | B |
| 0 | flat +10 | 9.1% | B | 9.3% | B |
| 0 | gutter prop | 18.2% | A | 11.6% | A |
| 5 (29) | blank card | 22.2% | A | 18.6% | A |
| 5 | flat +10 | 24.4% | A | 21.3% | A |
| 5 | gutter prop | 31.2% | **S** | 23.9% | A |
| 8 (34) | blank card | 1.5% | C | 0.9% | C |
| 8 | flat +10 | 5.3% | B | 7.0% | B |
| 8 | gutter prop | 33.3% | **S** | 15.0% | A |
| 12 (44) | blank card | 3.4% | B | 3.0% | C |
| 12 | flat +10 | 5.6% | B | 5.9% | B |
| 12 | gutter prop | 30.5% | **S** | 17.8% | A |

Readings: the blank card sits **strictly below both designed mods at every node under
both variants** in this static model (kill-criterion passes — note this contradicts the
marginal-derivative argument in §3a.2 partially; the derivative matters most for *dump*
boards, this table is mid-policy; treat V0's blank-card risk as arrangement-dependent).
Under V0 the gutter prop runs away to S-tier late (it multiplies by a growing axis);
**V2A compresses gutter vs flat into the same A/B range — the "one currency" goal.**
The node-5 spike for all mods is a policy-boundary artifact (deck 29→30 shifts the mid
split) — tier boundaries stay 🎮 until playtested. A hypothetical ×mult mod would be the
only non-decaying class and must be rarest if ever added.

---

## 6. Goal-curve principle: slightly ahead of average 📋

The goal at node k sits **just above the average-play score curve** — continuing a run
requires above-average play, and the gap stays roughly constant in *probability* terms.
Formalized with a **difficulty quantile knob `q`**: `goal(k) = Q_q[T_avg(k)]`, where
`T_avg` = the sim distribution for the average policy at expected deck N̂(k) = 24 +
5·⌊k/3⌋. Starting proposal q ≈ 0.55–0.65 (average play loses slightly more than it wins)
while the same goal lands near p15–p30 of *skilled* play.

**Run-length compounding table** (per-show win p over 12 nodes → run win ≈ p^12; the
quantile knob IS the run-length dial):

| per-show p | 0.80 | 0.85 | 0.90 | 0.925 | 0.95 | 0.975 |
|---|---|---|---|---|---|---|
| run win p^12 | 7% | 14% | 28% | 39% | 54% | 74% |

🧪 Measured (q=0.6, V2A25, dupes boosters, §8): skilled-casual per-show 71–99%, run win
18%; V0CAP: 77–100%, run win 32.5%. Target band: per-show 85–92% skilled → run ≈ 25–45%.

**Overscore ruling (user decision, plus a sweep finding):** the rubber-band is kept but
defanged — per-show ratio capped at `min(ratio, 1.0)` and exponent 1.5 → 1.0; the worst
case is then ≈ ×1.25-per-big-win, a nudge not a wall. 🧪 **New finding: if goals become
quantile-calibrated, even the defanged tax makes skilled play self-defeating** (skilled
run-win drops from 32.5% to 0% at q=0.6 — the rubber-band was compensating for exactly the
N^2.4 growth quantile calibration now handles). Rule: *formula goals → defanged overscore;
quantile goals → overscore rate ~0.* Lap scaling 2.5^lap is only fair against compounding
income — an explicit endless-wall design, flagged as such.

---

## 7. Staged sweep results 🧪 (`--ofat all` / `--grid` / `--lhs 300`)

### 7a. Stage 1 — OFAT (reference point: 24 cards, spread 1–4, degraded f=0.6, mid policy)

Which variables matter (3-act total means, V0 → V2A@0.5):
- **Deck size** dominates: 16→96/91, 24→190/150, 32→361/291, 40→563/493, 52→1201/1097.
  V0 super-linear; V2A near-linear until meld counts compound.
- **Rank spread** (at 24 cards): 1–4→190, 1–5→169, 1–8→118, 1–13→103 (V0). Wider spread =
  fewer collisions = weaker sets; straights/flushes only partially compensate.
- **Policy**: even 157 / mid 190 / dump 379 (V0) — the concentration problem in one line.
- **Arrangement**: random 168 / degraded .6 190 / rank-oracle 289 / suit-oracle 205 (V0).
  Under V2A the oracle premium shrinks (159 vs 150) — V2A@0.5 under-rewards organization;
  another reason w must be tuned per the meld definition, 🎮.
- **Props** (static model): 0→190, 2→219, 4→249, 8→308 (V0) — near-linear, ~+15/prop card.
- **Combine × w**: concentration V0 ×2.42; V2A w=0.25 ×1.72 ✓, w=0.5 ×2.64 ✗, w=0.75 ×3.60 ✗.
- **High-card floor off**: V0 ×4.04, V2A ×3.22 — worsens concentration (see §4).

### 7b. Stage 2 — pairwise grids

**Deck size × combine** (concentration): both rules blow past the band as decks grow —
size 16: 1.7/1.3, 24: 2.4/2.7, 32: 3.9/4.5, 52: 6.6/6.8 (V0/V2A@0.5). **No combine rule
alone fixes concentration at large decks**; the dump premium is board-geometry (more cards
= superlinearly more/bigger melds). Mitigations: unused-act bonus, dump boards being
harder to arrange in real play, and goal calibration to the dominant policy. 🎮

**w × floor**: conc(w=0.25)=1.72 floor-on / 2.01 floor-off; every higher w or floor-off is
worse. Confirms w=0.25 + floor ON as the V2A ship point.

**Size × spread** (organization-difficulty proxy = oracle/random ratio): peak organization
leverage at 24–32 cards spread 1–4..1–8 (×1.74–1.91); 16 cards is flat (×1.25–1.35 — too
few cards to differentiate skill); 52×(1–4) is degenerate (×1.25 — everything collides
anyway), 52×(1–13) has leverage (×2.29) but only for straight/flush archetypes.

### 7c. Stage 3 — LHS (300 samples over w/size/spread/floor/act-bonus)

35/300 in the concentration+legibility bands. The Pareto cluster: **w ≈ 0.15–0.4, deck
17–31, spread 1–8..1–13, floor on, b ≈ 0.1–0.3**. Finalists advanced to Stage 4:
- **V2A25** = COMBO w=0.25/0.25, floor on, overscore cap 1.0 exp 1.0.
- **V0CAP** = CROSS + quantile goals (the V7 idea), overscore cap 1.0 exp 1.0.

### 7d. Stage 4 — full 12-node runs (q=0.6 goals, dupes boosters, no overscore tax)

`py tools/scoring_sim.py --run-sim V2A25 --q 0.6 --no-overscore --booster dupes`

| | V2A25 skilled | V2A25 average | V0CAP skilled | V0CAP average |
|---|---|---|---|---|
| show-win nodes 0–2 | 98–99% | 35–47% | **100%** | 38–47% |
| show-win nodes 3–5 | 86–89% | 40–69% | 94–96% | 37–48% |
| show-win nodes 6–8 | **71–74%** ⚠ | 0–33% | **77–79%** ⚠ | 0–20% |
| show-win nodes 9–12 | 88–99% | — | 91–98% | — |
| median margin | 1.09–1.37 flat ✓ | 0.83–1.04 | 1.09–**2.02** ⚠ | 0.93–0.99 |
| run win | 18% | 0% | 32.5% | 0% |
| skilled-no-booster | dies node 3–6 ✓ | | dies node 3–6 ✓ | |

Readings vs the acceptance bands (§11): margins are flat (no wall) ✓; average play loses
runs while winning ~40% of shows ✓; upgrades are mandatory ✓; digits ≤4 through the run ✓.
Two ⚠s: the **node 6–8 sag** below the 85–92 band (the +5-cards-per-3-nodes booster
income undershoots the goal quantile there — booster pacing or q(k) needs a within-lap
shape, 🎮) and **V0CAP's node 0–2 blowout** (margin 2.0, show-win 100% — CROSS still
over-rewards the skilled dump the goals weren't calibrated to; V2A25 controls it, 1.37).
**Neither finalist fully passes; V2A25 is closer. Per the §11 failure rule this goes to
in-game A/B rather than silently loosening the bands.** 🎮

### 7e′. Goal-curve reframing (owner ruling 2026-07-17) 📋

The natural N-scaling of scores is **accepted, not fought**: the goal curve's job is to
stay just ahead of it, and the score-vs-N curve is what tells us **how many cards the
player can be allowed to acquire between games**. Therefore:
`goal(k) = Q_q[ T_avg( N̂(k), Ū(k) ) ]` — quantile of average play at the deck size the
acquisition schedule *permits* by node k, including the expected combo level Ū(k) if the
uniqueness bonus ships. The booster schedule (cards offered per node) becomes a
first-class balance input: goals are calibrated to "took ~2 of 3 offers", so taking
everything puts you ~1 node ahead, skipping everything kills you by ~node 6 (measured,
§7d). Owner also proposes the starting deck become **20 cards, ranks 1–5 × 4 suits, no
modifiers** — straights are live from node 0, one exact copy of each card. Baseline means
on that deck (degraded f=0.6): even 57 / mid 81 / dump 163, so G0 re-anchors to ~55–65 at
q≈0.55–0.65 (vs today's 100). The 24×(1–4) recommendation in §7e below predates this
ruling and stands only as the measured alternative.

### 7e. The starting-deck answer 📋🧪

**Recommendation: keep 24 cards × ranks 1–4** — it sits at the organization-leverage peak
(×1.74), stays legible, and is the anchor all tables above assume. 16 is too flat to
express skill; 52-standard collapses either organization leverage (with narrow effective
spread) or set power (1–13: totals ×0.55 of the 24-deck at par play). **Boosters should
add duplicates within the current spread, not standard 1–13 cards** — the `standard`
booster model measurably *sags* the score curve mid-run (node-6 goal under it DROPS below
node 3's because average play gets worse as spread dilutes — a curve no goal formula
should be asked to track). Straights should enter by deliberate spread-extending boosters
(1–5, then 1–8), each of which re-anchors N̂/spread in the goal table. Boosters-per-lap:
taking ~2 of 3 keeps par (skilled-no-booster dies by node 6 ✓ band; the all-boosters line
is the 71–99% row).

---

## 8. Reference catalog (curves, heuristics, algorithms)

### 8a. Games

| Reference | Mechanism | Pro (for Solatro) | Con |
|---|---|---|---|
| Balatro | chips×mult split; blind ladder 300→50k with *declining* growth ratio per ante; ×mult scarce | proven feel; declining-ratio ladder = §6's flattening quantile curve | its exponential economy needs shops/removal Solatro lacks |
| Cribbage | pair formula IS n(n−1) | validates the set curve | no board geometry |
| Yahtzee | bounded threshold bonus (63→+35) | model for unused-act style bonuses | static difficulty |
| Luck be a Landlord | goal growth paced by attempt count | acts-per-show is an unused pacing lever | slot RNG, low agency |
| Ballionaire / CloverPit | exponential deadlines vs multiplicative loot | endless-lap analogue | accepts eventual walls by design |
| Slay the Spire | difficulty on map branches; community win ~5–25% at ascensions | map-branch difficulty fits worldgen | per-run win far below Solatro's target feel |
| Hades | death-as-progression, runs pay meta-currency | fame is the analogue — losses must still pay | needs meta-spend sinks |
| Vampire Survivors | in-run power deliberately outruns difficulty at the end | victory-lap feel = §7d's rising 9–12 tail (embrace it) | trivializes endgame if overdone |
| Isaac / roguelites | unlock ladder absorbs long-term difficulty | where extra difficulty should live (not the goal curve) | scope |
| Tetris guideline | concentration premium bounded ×2 (800 vs 4×100) | the [1.3, 1.8] band's spiritual ancestor | different genre |
| 2048 / Threes | exponentials as named tiers | legibility trick if numbers ever explode | cosmetic only |
| Idle/incremental | cost curves c·r^n, r≈1.07–1.15 | geometric goals fair ONLY vs compounding income (lap ruling, §6) | Solatro income is not compounding by default |
| Candy Crush tuning | per-attempt pass rates tuned per level band | per-node q(k) shaping (the node 6–8 sag fix) | needs telemetry at scale |
| Elo/TrueSkill | forced ~50% wins | cautionary: don't target 50% per show — feels bad without progression dressing | — |

### 8b. Heuristics & algorithms used

Flow-channel (difficulty tracks skill with sawtooth oscillation: within-lap ramp, relief
valve after boss); **85% success rule** (Wilson et al. 2019, learning-optimal — the
per-show band's anchor, cited as heuristic [R]); loss-aversion asymmetry (losses weigh
~2× → rare-but-fair walls beat frequent small failures); L4D Director / RE4 adaptive DDA
(bounded rubber-band with caps — the model for the defanged overscore); PID framing
(overscore cap = clamping the P-term); **quantile calibration** (goals from sim
percentiles — the recommended method, §6); response-surface + **Latin-hypercube sampling**
(§7c); **common-random-numbers / paired seeds** (variance reduction, the harness default);
greedy-bot floor / oracle-bot ceiling to bracket real play; Kelly-style risk framing for
the dump decision (bet sizing vs remaining acts).

### 8c′. Adaptive difficulty: consensus, and why overscore stays retired 📋

Punishing overperformance with goal-side scaling has the worst track record in the DDA
literature and in shipped games, because it incentivizes **sandbagging** — players
minimize whatever variable drives the punishment: *Oblivion* level scaling (players
deliberately stopped leveling; softened in Skyrim), *Homeworld* fleet-size scaling
(players scuttled their own ships between missions). Solatro's overscore had exactly
this shape — score fed both fame (reward) and future goal inflation (punishment), so
the theoretical optimum was "win by exactly 1, then stop scoring", the opposite of what
the combo celebrates — and the sim confirmed it (§6: on a calibrated curve even the
defanged tax made skilled play self-defeating). Loss aversion (~2:1, Kahneman &
Tversky) explains why a goal that rose *because you did well* reads as a taking-away.

Where adaptivity works (consensus: assist-side, bounded, hidden, or opt-in): L4D
Director / RE4 hidden difficulty (the load-bearing half is easing off strugglers);
God Hand / DMC style meters (challenge scaling framed as a *rank you earn*, instantly
resettable); and — the roguelite standard, strongest fit for Solatro — **opt-in
escalation**: StS Ascension, Balatro Stakes, Hades Heat. Winning unlocks the *right to
choose* a harder contract; nobody's goals inflate silently mid-run; being ahead reads
as prestige.

**Rulings for Solatro:** overscore stays retired. The positive loop already exists
(surplus score → fame → booster luck = reward-side escalation — keep it). For players
far ahead of the curve: (1) **every lap must raise overall difficulty** — the
`LAP_MULT^lap` term in §15b is this requirement, an explicit owner ruling, not an
accident of the formula; endless laps are the pressure vessel that eventually walls any
build (the victory-lap stretch before that is intended feel); (2) expose the
`difficulty` float as named opt-in tiers unlocked by winning (Stakes-style) rather than
any automatic in-run adjustment; (3) if in-run responsiveness is ever wanted, scale
**rewards** (overscore → better booster quality next node), never goals. Revisit only
if ×mult-class mods ever make in-run compounding outrun a fixed lap curve — and prefer
Balatro's answer (make ×mult scarce) even then.

### 8c. "Most fun" win-rate anchors [R]

Learning-optimal ~85% per challenge; casual-puzzle per-attempt 30–60% with cheap retries;
roguelike per-RUN 10–40% for seasoned players (StS/Balatro community figures), <5% reads
unfair, >60% flat; per-show success must sit FAR above per-run (0.9^12 ≈ 28%). Proposal:
tune q so per-show ≈ 85–92% skilled-casual → per-run ≈ 25–45%.

---

## 9. Where each tunable will live 📋 (build when the playtest phase starts, not before)

| Knob | Planned location | Default (= shipped behavior) |
|---|---|---|
| Combine mode CROSS/COMBO | `SettingsManager.settings.combine_mode` → a static `GameData.combine_payout` dispatch (CROSS path must stay bit-identical to `row_total * col_total`) | CROSS |
| COMBO weights w_r/w_c | `settings.combo_w_row/.combo_w_col` | 0.25 / 0.25 |
| Meld counting | `Game.score_line` → `state.row_melds/col_melds` on GameData (so undo snapshots carry them), reset in `apply_act_score` | read by COMBO only |
| Unused-act bonus b | `settings.unused_act_bonus`, applied ONCE at the final submit in `Game._perform_submit` BEFORE `save_state` (a quit-at-win resume re-runs `_resolve_game` — banking after save would double-apply) | 0.0 (off) |
| Overscore per-show cap | `settings.overscore_cap` → `RunManager.record_win` (`min(ratio, cap)`, negative = uncapped) | −1 (uncapped) |
| Overscore exponent | `settings.overscore_exp` → `RunManager.goal_for` | 1.5 |
| Goal base/growth/lap/boss | `RunManagerClass` consts (single goal authority; per-node baking stays in `map_node_roles.gd`) | 100 / 1.15 / 2.5 / 2.0 |
| Hand formulas | `Scoring.ScoreModel` — **not touched by any variant** | — |

Balance consts stay in run_manager/scoring until a variant wins — no premature
BalanceConfig resource. High-card floor gets no toggle (rejected as a concentration fix
in §4; build it only if the playtest wants the feel change). Until then, every one of
these knobs already exists as a sim flag — iterate there.

## 10. Playtest protocol + record sheets 🎮

Paired seeds, 6 runs per variant cell, one variant per session. A/B order:
1. **V0 control vs V2A25** (overscore inflation off in both: cap 0 — set
   `overscore_exp` such that inflation is neutral, or simply compare pre-lap-1 nodes).
2. Winner vs **V0CAP/quantile re-anchor** (edit goal consts per §6 table for the session).
3. **Overscore cap on/off** on the winner (cap −1 ↔ 1.0, exp 1.5 ↔ 1.0).
4. **Unused-act bonus** b=0 ↔ 0.25 (and high-card floor, if built) on the winner.

Pass thresholds: §11 bands, plus tension ≥3.5, legibility ≥3.5, "dumping felt mandatory"
≤2/6 runs. Derived metrics: **strategy entropy** (stddev of cards-per-act — near-zero AND
maximal both mean the choice is fake), margin trajectory, digit counts.

**Per-show record sheet** (one row per show):

| Run | Node | Variant | Goal | Deck N | Cards/act (a1/a2/a3) | Act payouts | Total | Margin | Ring moves | Sec-to-submit | Tension 1–5 | Legibility 1–5 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| | | | | | | | | | | | | |

*Tension: "was the last act in doubt?" — Legibility: "did you know roughly what you'd
score before submitting?"*

**Per-run record sheet:**

| Run | Variant | Seed | Win node (or W) | Boosters taken/offered | Fun 1–7 | Dumping mandatory? y/n | Notes |
|---|---|---|---|---|---|---|---|
| | | | | | | | |

## 11. Acceptance bands (the decision rule)

The shipping parameter set (or the 2–3 A/B finalists) must satisfy ALL of:
- **Win-prob curve**: per-show skilled-casual 85–92% at par deck at every node (no
  sag/spike >±5pts); average-policy 35–50%; no-booster play <50% by ~node 6.
- **Concentration ratio** (dump vs even) in **[1.3, 1.8]**; with the unused-act bonus on,
  even play's deficit ≤1.2×.
- **Mod leverage**: every designed mod A/B-tier GSP at acquisition AND 4 nodes later;
  blank card strictly below designed mods (the V0 kill-criterion); flat vs gutter within
  2× per point invested.
- **Legibility**: act payouts ≤4–5 digits through lap 1; median payout monotonically
  increasing node-over-node at par play.
- **Margin trajectory**: median total/goal flat at ~1.1–1.4 across the run; with the
  overscore cap, next-goal inflation ≤×1.3 after any single show.
- **Deck-size answer**: the recommended start = the (size, spread) needing the fewest
  special-case corrections (§7e: 24 × 1–4), plus boosters-per-lap to stay on curve
  (~2 of 3).

If several sets pass → ship all behind the settings toggles and let §10 decide. If none
pass → the bands themselves get revisited, **documented as an explicit failure outcome,
never silently loosened**. Current status 🧪: V2A25 passes concentration, legibility,
margins, mods; sags to ~71% at nodes 6–8 (booster-pacing artifact) — *conditional pass,
pending §10 step 1*.

## 12. Implementation map

**Shipped now ✅:** `tools/scoring_sim.py` — the harness (exact ScoreModel port;
`--baseline` reproduces §3 within MC noise; stages `--ofat/--grid/--lhs/--run-sim`;
`--gsp`; `--goals`; paired seeds; CSV via `--csv`) — and this document. Nothing in the
game changes until the formulas are settled.

**Deferred to the playtest phase 📋 (gate: a variant survives §11 + the owner signs off
on the formula):** the §9 toggles in `player_settings.gd` / `game_data.gd` / `game.gd` /
`run_manager.gd`, plus TestSuite cases in `Tests/Engine/test_act_score.gd` (CROSS
bit-identity, COMBO hand-computed examples, meld reset). `ScoreModel` and the SECTION 8
leaderboard (`test_scoring.gd`) are untouched by every variant.

## 13. Design-question grill (the ~40 questions this work answers or opens)

**Answered [measured/decided]:**
1. Is R×C fine? — No: four specific failures (§3a).
2. Is dumping dominant? — ×2.4 under V0; band is [1.3, 1.8].
3. Does w=0.5 fix it? — No, ×2.6; w=0.25 does (×1.72).
4. Does removing the high-card floor punish dumps? — No, it *rewards* them (§4).
5. Does deck size out-scale goals? — Yes, N^2.4 vs 1.15^k.
6. Is a blank card better than designed mods? — Not at mid policy (§5); dump boards remain the risk case.
7. Are gutter and flat mods one currency? — Only under V2A (§5).
8. Is the overscore wall real? — Yes; one node-0 clear ≈ ×9 next goal at exp 1.5.
9. Cap+exp defang enough? — Yes for formula goals; must be ~0 for quantile goals (§6).
10. Ideal starting deck? — 24 × ranks 1–4 (§7e).
11. Should boosters add standard cards? — No: dupes within spread; spread widens only by deliberate steps.
12. Decimals? — Never player-facing; round once per act (§4).
13. How many boosters to stay on curve? — ~2 of 3 (§7e).
14. Where do goals live? — `goal_for()` stays the single authority; nodes bake once.
15. Do straights matter at start? — Impossible by construction (ranks 1–4); a spread booster is the unlock moment.
16. What's the per-show → per-run math? — p^12 table (§6).
17. Is 52-card start viable? — Scores fine but concentration ×6.6 and weak org leverage; no.
18. Does organization difficulty rise with more cards? — Oracle/random ratio peaks at 24–32 then falls; *real* legality-constrained difficulty unmeasured (§14).
19. Is even play ever correct? — Under V2A25 + bonus b≈0.25, deficit ≤1.2× 🎮.
20. What's an act worth skipping? — b·total per unused act; Kelly framing says dump early only with margin in hand.

**Open [playtest/measure in-game] 🎮:**
21. Does COMBO *feel* legible mid-act (running total vs a product)?
22. Real meld-count UI — do players need row/col meld indicators for COMBO?
23. Does the unused-act bonus create degenerate "always dump act 1" play at b≥0.5?
24. Does undo-anytime neuter dump risk (the risk even play is priced against)?
25. Is the node 6–8 sag a booster-pacing bug or a q(k)-shape need?
26. Do Burning cascades break the static prop model (S-tier props hiding)?
27. Are 3 acts right at 40+ cards, or should acts scale with deck?
28. Entrance persistence as a 4th policy — worth modeling/playing?
29. Where should the victory-lap feel start (nodes 9–12 rising is currently emergent)?
30. Per-show tension: does a flat 1.1–1.4 margin FEEL tense or grindy?
31. Should boss ×2 also scale with q, or stay a flat jump?
32. Lap 2+ (2.5^lap): what compounding income justifies it — or is endless meant to wall?
33. Does luck()-gated booster rarity interact with the ~2-of-3 pacing assumption?
34. GSP tier boundaries (25/10/3) — do they match perceived value?
35. mult_score UI under COMBO — what number does the player watch?
36. Should high-card floor removal ship as a feel toggle despite §4?
37. Booster take-all vs pick-1: does agency change the required goal slope?
38. Map length 12 vs actual generated depth distribution (unmeasured).
39. BigNumber gutters vs int totals — overflow behavior under V0 late laps?
40. Fame double-duty (luck + score records): does overscore banking distort luck pacing?

## 14. Uncertainties & confidence

**High [measured]:** the four V0 diagnoses; concentration ratios; act-payout exponent
≈2.4; overscore wall math; w=0.5 out-of-band / w=0.25 in-band; floor-removal backfiring;
spread-widening booster sag; GSP ordering at mid policy.

**Medium [modeled, not played]:** the degraded-arrangement model (linear mix of oracle
and random — real legality-constrained arranging is neither); persona definitions
(skilled = mid/f0.75, average = even/f0.5 — arbitrary until bracketed by real players);
GSP tier boundaries; node 6–8 sag attribution (booster pacing vs q shape); 52-card
conclusions (two policies tested).

**Low / needs work:** prop cascade dynamics (hoop/knife/ball/fire interactions, Burning
stacking — the sim's static +rank model could hide a large term; measure in-game);
expected mods-per-booster (calibrate against booster_template luck rolls);
"harder to organize with more cards" under real move legality (solitaire-solver sim
extension — expensive — or playtest observation); generated-map depth distribution;
whether undo-anytime restores the dump risk the model prices in; deck *composition*
variance (dupes vs spread) as its own axis beyond size; fun.

---

## 15. FINAL REPORT — the settled design ⭐ (2026-07-17)

Every owner ruling incorporated; every number below is 🧪 from
`py tools/scoring_sim.py --final --q 0.35` (capacity arrangement model, coarse classes).
No game code has been changed yet — this section IS the implementation spec.

### 15a. Scoring format ✅ decided

```
act payout = row_total × col_total × combo
combo      = 1.0 + 0.1 × U          (resets every act)
U          = distinct meld CLASSES scored this act
             + distinct mod effects on their FIRST activation this act
```

- **Meld class** = archetype + size + copy-count. Pair ≠ trips ≠ quad; `2× quad` is its
  own class distinct from `quad`; flush variants (full flush / straight flush / flush
  house) are their own classes. Rank and suit do NOT differentiate (pair of 2s = pair
  of 3s). Duplicate-class melds still score their base into the totals — they simply
  don't raise U.
- **ScoreModel hand values, prop values, gutter routing: unchanged.** The natural
  N-scaling of R×C is accepted; the goal curve prices it in (§15b).
- **Dump-as-endgame is embraced** (owner ruling): goals are calibrated against the BEST
  policy at each expected deck size, so mass-dumping a big deck is the intended late
  power fantasy the curve already expects. Measured guard-rails at the start deck:
  with arrangement capacity ~6–9 cards/act, dump vs even concentration is 1.0–1.3 —
  a real choice; the combo widens it only ~+0.13. **Fallback lever if playtest shows
  dump crushing everything anyway:** duplicate-CLASS melds score ×δ (δ a settings
  float, default 1.0 = off) — measured effect exists but is mild (§4a), which is why
  it is the fallback, not the design.

### 15b. Goal curve ✅ decided

```
goal(node) = G0 × (N̂(node) / N0)^ALPHA × difficulty × BOSS_MULT^is_boss × LAP_MULT^lap
```

- **N̂(node) comes from the map structure**:
  `N̂ = N0 + BOOSTER_YIELD × boosters_on_path(node)`, where `boosters_on_path` = the
  number of booster-role nodes on the path from the lap origin to this node (owner
  principle: goals scale with *opportunities* to grow, not actual purchases — skipping
  boosters leaves you under the curve, that is the pressure). Branches with more
  booster nodes automatically get higher goals = risk/reward routing for free.
- **Calibrated constants** (start deck 20 = ranks 1–5 × 4 suits, no modifiers; dupes
  boosters, 5 cards each, ~1 per 3 nodes): `N0 = 20`, `G0 ≈ 130`, `ALPHA ≈ 4.2`
  (log-fit of the table below; steeper than the raw payout exponent 2.4 because par
  play = best-policy dump under fixed arrangement capacity). Re-fit G0/ALPHA with one
  `--final` run whenever booster content or composition rules change; the baked table
  is the authority, the power law is the interpolator.
- **difficulty** is the adjustable float the owner asked for (default 1.0) — the
  q-dial in multiplicative form; ±15% on goals ≈ one persona band.
- **Overscore system: retired** (see §8c′ for the research consensus). `record_win`
  banks fame only; `overscore_ratio_sum` and the `OVERSCORE_*` consts are DELETED
  (fully removed 2026-07-17, owner-approved save break — old saves simply drop the
  unknown property on load). Measured rationale: on top of a calibrated curve, any
  overscore tax makes skilled play self-defeating; punishing overperformance breeds
  sandbagging.
- **Each lap raises overall difficulty** — owner ruling: the `LAP_MULT^lap` term is a
  requirement, not incidental. Endless laps are the intended pressure on players far
  ahead of the curve; per-player difficulty beyond that ships as opt-in tiers of the
  `difficulty` float (Stakes-style), never automatic in-run goal adjustment.
- **Monotone clamp:** `goal(k) = max(goal(k), goal(k−1))` along a path — a spread
  extension can weaken par play; the ladder must never descend.

Calibrated table (q=0.35, dupes schedule) + full-run validation:

| Node | N̂ | Goal | Skilled (cap 9) show-win | Skilled no-booster |
|---|---|---|---|---|
| 0–2 | 20 | 132 | 83–87% | 83–87% |
| 3–5 | 25 | 278 | 75–82% | 0–8% (dead) |
| 6–8 | 30 | 634 | 77–86% | — |
| 9–11 | 35 | 1,358 | 71–74% | — |
| 12 | 40 | 2,444 | 60% | — |

Flat skilled win-band across the run (no sag, no wall); average players (cap 5) sit
~45–64% per show and lose runs; upgrades are mandatory by node 3. Per-run skilled ≈ 4%
at this difficulty — `difficulty` is THE dial to move that toward the 25–45% comfort
band during playtest.

### 15c. Code & architecture changes ✅ implemented 2026-07-17 (see SCORING_IMPL_PLAN.md)

All eight items below landed 2026-07-17 (items 1–6 ✅ code, 7 ✅ tests incl. the new
`Tests/Engine/test_combo.gd` suite, 8 ✅ sim re-checked). One naming deviation: the
20-card start deck is `deck14` in `Decks/deck.gd` (`deck12` was already the
firework-access deck).

**1. `Scripts/scoring.gd` — class key (read-only addition, no scoring change):** ✅
`static func class_key(r: Result) -> String` from `r.types` + `r.copy_size` +
`r.copies_count`: archetype word + size + copies, FLUSH/ALL_SAME_SUIT flags appended so
flush variants stay distinct (e.g. `"XKIND:4x1"`, `"XKIND:4x2"`, `"STRAIGHT:5x1:FF"`).

**2. `Scripts/game_data.gd` — U lives on the board state:** ✅
`@export_storage var combo_classes : Array[String]` (a set; Array for serialization).
On GameData so **undo snapshots and saves carry it automatically** (same reason
`submits_used` lives there). `apply_act_score()` becomes
`mult_score = int(row_total * col_total * (1.0 + COMBO_STEP * combo_classes.size()))`
and clears `combo_classes` alongside the gutters. `COMBO_STEP = 0.1` as a const first;
promote to settings only if playtest wants it live.

**3. `Levels/game.gd` — collecting U:** ✅
- `score_line()`: after `add_line_score`, if the Result beats a lone high card:
  derive `Scoring.class_key(result)`, append to `state.combo_classes` if new, emit a
  `combo_changed` signal for the view pop.
- Mods: at the single `run_all_mods` dispatch point, when a mod handler actually fires,
  add its identity key (`mod.get_script().resource_path`, or an explicit
  `combo_key()` on CardModifier) the first time per act. Prop effects likewise, at
  their `add_line_score` seam callers.
- Fallback lever: if δ < 1.0 and the class was already seen this act, scale the line's
  banked score by δ in `score_line`.

**4. `Scripts/run_manager.gd` — goal authority rework:** ✅
`goal_for(progress, lap, is_boss)` → `goal_for(boosters_on_path, lap, is_boss)`
implementing §15b; consts `N0/G0/ALPHA/BOOSTER_YIELD` replace
`BASE_GOAL/GOAL_GROWTH_PER_STEP/OVERSCORE_*`; `difficulty` lives in
`player_settings.gd` via SettingsManager (project convention). `overscore_ratio_sum`
DELETED outright 2026-07-17 (owner-approved save break; every balance const later
moved to player_settings.gd too, §15d′).

**5. `Scripts/Map/map_node_roles.gd` — map-driven N̂:** ✅
Where it bakes `goal_for` per node today, first compute `boosters_on_path(n)` = count
of booster-role nodes along the traversal it already walks for depth, taking the
max-booster path on convergent branches so goals never undershoot a route; bake into
`n.meta` beside the goal, with the monotone clamp applied per path.

**6. UI (`game_view.gd` / play area):** ✅ a combo label beside the act score
(`"COMBO x%.1f"`, string via `TRANSLATION.find` + `Locale/localization.csv`), pulsing
on `combo_changed`; the mult display reads `R × C × combo`.

**7. Tests (TestSuite conventions):** ✅ class-key derivation table; `apply_act_score`
with combo incl. reset; undo across an act restores the combo set; goal monotonicity
along baked map paths; SECTION 8 leaderboard untouched (ScoreModel unchanged).

**8. Sim parity:** ✅ `tools/scoring_sim.py --final` is the calibration oracle — re-run
and re-fit G0/ALPHA when deck/booster content changes; `--baseline` must keep
reproducing §3 (combo is off in baseline mode).

### 15d′. Knob centralization + additive test variant (owner request 2026-07-17)

- **Every balance knob now lives in `Scripts/player_settings.gd`** ("Balance —" groups,
  live via SettingsManager): `combo_step`, `duplicate_class_scale`, `score_additive`,
  `difficulty`, `goal_g0`, `goal_alpha`, `goal_n0`, `booster_yield`, `boss_mult`,
  `lap_mult`, `luck_cap`, `fame_half`. RunManager/GameData read them live; the old
  consts are commented in place with pointers.
- **`score_additive` (ships OFF):** act payout = `(R + C) × (1 + 0.1·U)` instead of
  `(R × C) × combo`. Priced via `--final --q 0.35 --additive` (same sim build as the
  current `--final` run): fit `g0 ≈ 43, alpha ≈ 0.48` vs the multiplicative run's
  `g0 ≈ 140, alpha ≈ 2.03` on that build. Key structural findings: par policy flips to
  **even** play at small decks (the dump advantage collapses without the cross-product),
  returning to dump at N≥35; payout becomes **capacity-limited, not deck-limited**
  (alpha < 1: bigger decks barely raise scores because acts cap at ~7 arranged cards),
  so boosters almost stop raising goals and combo becomes the main scaling lever; the
  one-sided-act-pays-0 rule disappears; low-capacity (cap-5) players fall much further
  below par (6–20% show-win at start vs 44–65% multiplicative). To playtest it, set
  `score_additive = true` AND retune `goal_g0`/`goal_alpha` toward the additive fit.

### 15d. What stays open 🎮 (playtest, not decidable in the sim)

Arrangement capacity reality (is a real player ~cap 6, 9, or 12? — this decides where
in the 1.0–1.6 concentration range the game actually sits); `difficulty` default;
COMBO_STEP 0.1 vs 0.2 feel; how generous mod-activation U is in practice (sim modeled
meld classes only); Burning/prop cascades as a combo source; the δ fallback trigger
("is dump crushing?" → δ 0.7–0.9); spread-extension boosters as deliberate archetype
pivots (they weaken collision decks short-term — a real decision, priced by the
monotone clamp).

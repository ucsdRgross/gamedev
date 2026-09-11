# The board plan — test plan

## Design provenance and gap protocol — COPY THIS BLOCK INTO ANYTHING DERIVED FROM THIS DOCUMENT

Derived from: `solatro/design/board-plan/DESIGN.md`, version 1, confirmed after round 4. Every step
in `PLAN.md` cites the design node IDs it implements.

If you are executing this and you reach a decision the design does not cover:
1. Reversible and clearly within intent → do it, and append one line to `ASSUMPTIONS.md` citing the
   node you were working on. Never silently.
2. Otherwise — two defensible choices differ in observable behaviour, or the choice is expensive to
   reverse, or it is an owner call (balance, look, scope) → **park that thread, file a gap, keep
   working on unaffected threads, and tell the owner.**
3. The design contradicts itself or the code → always a gap, highest priority.
4. ⚠ **Two documents disagreeing is NOT automatically (3).** If both are restating the same answer,
   go read that answer — the conflict is a documentation bug to fix against the source, not a
   decision to escalate. Quote the note in the gap and say why it does not settle the question; if
   you cannot, it was never a gap.
5. ⚠⚠ **THE CODE BEING BROKEN IS NOT A GAP — FIX IT.** If the design says what should happen and the
   code does not do it, that is a BUG, and the only open question is *how* to fix it, which is
   yours. Filing it spends an owner round to be told "yes, fix the bug". Measured: one run filed
   ~50 gaps and a large share were this. **Before filing anything, ask in order:** does the design
   already answer it (→ fix the code); would any defensible choice be invisible in the product
   (→ assume it, log one line); would the owner recognise this as a decision they want (→ only now,
   a gap). A gap asks for a RULING, never for permission — if you are filing to be told it is fine
   to proceed, write the assumption instead.

File gaps at `solatro/design/board-plan/gaps/GAP-NNN.md` using the template in
`solatro/design/board-plan/DESIGN.md` §21. Write the options in the questionnaire grammar; they
become the next round's questions unchanged.

Do not resolve a gap by picking an answer. Do not proceed on the parked thread. Do not delete a gap
— it is closed by a new design version.

This block, unchanged, goes into every document derived from this one.

---

## How to read this

- **Every row cites the design node it proves and the plan step it gates.**
- ⚠ **The planned tests are not optional.** You may ADD lower-level tests for details the plan could
  not foresee — that is expected and welcome. You may **not** decide a planned test is unnecessary.
  Dropping one is a gap, not a judgement call.
- **Fixtures are specified.** Where a row names data, use that data. If the plan does not fix the
  data, invented data tests whatever it happened to make true.
- **`⚑gate`** marks a self-checking acceptance gate — one that cannot be talked past.
- **`👁`** marks a by-eye verification a human signs off (`/fx-verify`). **No green test is evidence
  about pixels.**
- Follow `ARCHITECTURE_REVIEW.md` §7: TestSuite pattern, never `Decks/deck.gd` in a test (use
  `TestDecks`), `await` every coroutine test, compare failure SETS not check totals.
- ⚠ **Prove every new assertion RED before you make it green.** A test that never failed has not
  been shown to test anything (`.claude/memory/tests-that-prove-nothing.md`).

**Standing fixture — `PLAN_DECK`.** Add to `Tests/Support/test_decks.gd`: **20 cards, four suits ×
ranks 1–5, `TypePaper`, no skills, no stamps** — i.e. `deck14`'s shape, frozen here so a change to
the shipped deck cannot silently rewrite these expectations. Where a row needs talents or hats it
says so and names its own variant.

---

## Suite `BOARD PLAN` — the deal (`Tests/Engine/test_board_plan.gd`)

| id | Test | Fixture | Proves | Gates |
|---|---|---|---|---|
| **TP-01** ⚑gate | Every cell of a 5×5 grid is marked | `PLAN_DECK`, 1 grid | `Q1`=(b), chart A | S4 |
| **TP-02** ⚑gate | With 20 cards over 25 cells, exactly 20 cards appear once and 5 appear twice — **no card appears three times** | `PLAN_DECK`, 1 grid | `Q1`=(b), `Q102`=(a), `Q108`=(a) | S4 |
| **TP-03** ⚑gate | No card is marked twice while any card is unmarked | a 30-card deck, 1 grid (25 cells) — assert 25 distinct cards, 0 repeats | `Q108`=(a) | S4 |
| **TP-04** ⚑gate | Across TWO grids, 50 cells draw 50 distinct cards from a 52-card deck | 52-card deck, 2 grids | `Q9`, `Q109`=(a) | S4 |
| **TP-05** ⚑gate | Each of the 5 stocks contributes exactly 5 of a 25-cell board's marks | `PLAN_DECK`, 1 grid, stocks dealt round-robin | `Q93`=(b) | S4 |
| **TP-06** | 26 cells over 5 stocks: stocks 0 contributes 6, stocks 1–4 contribute 5 | ragged grid, one extra cell | `Q93`=(b) + pre-authorisation 1 | S4 |
| **TP-07** ⚑gate | **Determinism.** Two deals with the same `plan_seed` are identical cell for cell; two with different seeds are not | `PLAN_DECK` | `Q8`=(a), `DESIGN.md` §1k | S4 |
| **TP-08** ⚑gate | **`Array.shuffle()` is not called anywhere on the deal path.** Assert by seeding the GLOBAL rng identically, dealing twice with different `plan_seed`, and requiring the two deals to differ | `PLAN_DECK` | `DESIGN.md` §1m | S4 |
| **TP-09** | The cell walk is shuffled: over 200 seeded deals, the cell that receives the first mark is not the same cell more than chance allows | `PLAN_DECK` | `Q99`=(a) | S4 |
| **TP-10** | Two copies of one card MAY land in one row — assert it is not rejected, by finding at least one such deal in 200 seeds | `PLAN_DECK` | `Q101`=(a) | S4 |
| **TP-11** ⚑gate | A mark copies `rank`, `suit`, `skill`, `stamp` and **never `statuses`** | a deck whose cards carry a Burning status | `Q4`=(b), `Q5`=(a) | S4 |
| **TP-12** ⚑gate | A mark's modifier backrefs point at the MARK, not at the source card | `PLAN_DECK` with skills | `ARCHITECTURE_REVIEW.md` §6 | S4 |
| **TP-13** | A card minted mid-show gets no mark; the discard is invisible to the plan | `PLAN_DECK` + an effect that mints | `Q11`=(a), `Q12`=(a) | S4 |
| **TP-14** | A grid added mid-show deals its own marks and still avoids cards used anywhere | `PLAN_DECK`, 1 grid then 2 | `Q10`=(a), `Q109`=(a) | S4 |
| **TP-15** | A cell added to a ragged grid takes an unused mark; when none is left, it repeats | 25-card deck, then a 26th cell | `Q78`, `Q110`=(a) | S4 |
| **TP-16** ⚑gate | `validate()` I6 fails a mark naming a card outside the deck, and PASSES the same mark with `granted = true` | hand-built state | `Q61`=(b), `Q121`=(a) | S2 |
| **TP-17** ⚑gate | A dealt plan survives `duplicate_state()`, `pack_scores()`/`unpack_scores()` and a save round-trip, cell for cell | `PLAN_DECK` | `DESIGN.md` §1k | S4 |
| **TP-18** ⚑gate | A save written with no `plan_seed` resumes as a plan-less board and plays | a pre-feature snapshot | pre-authorisation 12 | S4 |

---

## Suite `MARK MATCH` — matching and the economy (`Tests/Engine/test_mark_match.gd`)

| id | Test | Fixture | Proves | Gates |
|---|---|---|---|---|
| **TP-20** ⚑gate | Each property is detected independently: a 5-of-Hoops on a mark of 5-of-Knives returns `RANK` only; on 3-of-Hoops returns `SUIT` only; on 5-of-Hoops returns both | hand-placed marks | `QR3`=(a), `Q16`=(a) | S5 |
| **TP-21** ⚑gate | A talent match needs **the same skill script**; two different skills return no `TALENT` | two `CardModifierSkill` subclasses | `Q34`=(a) | S5 |
| **TP-22** ⚑gate | A hat match needs **the same stamp script** | two stamps | `Q37`=(a) | S5 |
| **TP-23** ⚑gate | **The match is LIVE.** Change a placed card's suit through a modifier — with no `revision` bump — and `matches_at` changes on the next call | one card, one mark | `Q13`=(b), pre-authorisation 6 | S5 |
| **TP-24** | Every card in a 3-deep stack is tested, not only height 0 | 3 matching cards in one cell | `Q15`=(b) | S5 |
| **TP-25** | A card placed by an EFFECT matches identically to one the player placed | an effect that places | `Q14`=(a) | S5 |
| **TP-26** | A non-matching placement leaves the mark intact and matchable after the card leaves | place, remove, place a matcher | `Q18`=(a) | S5 |
| **TP-27** ⚑gate | A mark pays **every time** a matching card lands — three land-remove-land cycles pay three times | one cell | `Q20`=(a) | S5 |
| **TP-30** ⚑gate | **`(hand + flats) × M`.** A row scoring a pair of 5s with one rank match of 7 and no mults banks `hand + 7` | fixed 5-card row | `Q104`=(d), `Q21`=(a), `Q22`=(a) | S6 |
| **TP-31** ⚑gate | **`M == 0` never multiplies.** The same row with zero mult bonuses banks `hand + flats`, NOT zero | same row | `Q122` | S6 |
| **TP-32** ⚑gate | **Two ×2 marks make ×4.** Two mark effects each contributing `+2` give `M = 4` and the line banks `(hand + flats) × 4` | two marked cells in one row | `Q122`, `Q48`=(b) | S6 |
| **TP-33** ⚑gate | **`ScoreModel` is untouched.** `test_scoring.gd` SECTION 8's hand leaderboard is byte-identical to `main` | the existing suite | `Q104`=(d), `PLAN.md` §1.5 | S6 |
| **TP-34** ⚑gate | A full flush's score is unchanged by any bonus — the flush double multiplies only the hand | a 5-card flush with one rank match | `Q104`=(d) | S6 |
| **TP-35** | The Ace pays **10**; a rank with no integer value pays the flat fallback; a fractional rank rounds **up** | Ace, `HalfStepRank`, rank 2.5 | `Q26`, `Q27` | S6 |
| **TP-36** ⚑gate | Bonuses come from `result.meld`, not `section.cards` — a matching card in the line but NOT in the meld pays nothing | a 5-card row whose best meld is 3 cards | `Q25` | S6 |
| **TP-37** | A card in a row, a column and a diagonal pays its rank bonus into **each** line | a corner cell completing three lines | `Q23`=(a) | S6 |
| **TP-38** | A match registers no combo class | one match, `combo_classes` unchanged | `Q76`=(c) | S6 |
| **TP-39** | A leniency rule loosens the match; with no implementer the dispatch count is **zero** | one modifier implementing `on_mark_ranks_allow` | `Q41`=(a), `ARCHITECTURE_REVIEW.md` §3c | S5 |

---

## Suite `MARK MATCH` — the suit rule and marks that act

| id | Test | Fixture | Proves | Gates |
|---|---|---|---|---|
| **TP-40** ⚑gate | **A suit effect does NOT fire without a suit match** — an untalented Hoop scoring on a Knife mark spawns zero props | one row, one mark | `Q87` | S7 |
| **TP-41** ⚑gate | **It DOES fire on a suit match, talented or not** — a TALENTED Hoop on a Hoop mark spawns its props | talented card | `Q87`, `Q30`=(b) | S7 |
| **TP-42** ⚑gate | **The talent suppression is retired** — a talented card on a matching suit mark is not suppressed | talented card | `Q30`=(b), `PLAN.md` §1.6 | S7 |
| **TP-43** | A matched suit fires **once per meld membership**, as suit effects do today | a card in a row and a column | pre-authorisation 7 | S7 |
| **TP-44** ⚑gate | **A mark is never spotlit** — an uncovered mark of a card carrying a skill answers no broadcast hook | a mark of a `SkillExtraPoint` card | `Q59`=(a) | S8 |
| **TP-45** | A mark blocks nothing; the card under it — there is none — and the spotlight rule are unaffected | one mark | `Q60`=(a) | S8 |
| **TP-46** ⚑gate | `on_mark_hit` reaches BOTH the mark's modifiers and the placed card's | a mark and a card each implementing it | `Q47`=(a) | S9 |
| **TP-47** ⚑gate | `on_mark_covered` fires for a NON-matching cover; `on_mark_hit` does not | one mismatch | `Q46`, `Q51`=(a) | S9 |
| **TP-48** | `level` is 1 on a match and 0 on a plain cover, and never any other value | both cases | `Q50`=(c) | S9 |
| **TP-49** | A mark effect fires again on every re-score of a line through its cell | force two scorings | `Q52`=(b), `Q107`=(a) | S9 |
| **TP-50** ⚑gate | A mark firing charges `note_processing` and is bounded by the runaway guard — a deliberately looping mark effect trips `act_overrun` and does **not** hang | a looping mark | `Q57`=(a) | S9 |
| **TP-51** | A mark firing registers a combo class from its COPIED modifier, not from `TypeGridCell` | one firing | `Q54`=(a), pre-authorisation 16 | S9 |
| **TP-52** | `reroll_mark`, `swap_marks` and `grant_mark` each leave `validate()` clean | each API call | `QR5`=(c), `Q53`=(a) | S10 |
| **TP-53** ⚑gate | **Undo restores the mark AND un-banks the bonus** — board and score are bit-identical to before the placement | place a matcher, undo | `Q62`=(a) | S9 |
| **TP-54** ⚑gate | A quit mid-cascade replays the placement and reproduces the same board and score | the pending-action path | `DESIGN.md` §1k | S9 |

---

## Suite `PLAN VISUALS` (`Tests/UI/test_plan_visuals.gd`) — and the by-eye gates

| id | Test | Proves | Gates |
|---|---|---|---|
| **TP-60** | An empty marked cell binds its mark into the slot control `_bind_stack` already creates — **no new node is added to the tree** | `PLAN.md` §2 | S11 |
| **TP-61** ⚑gate | **`modulate` is not written by any mark code path.** Assert the cell control's `modulate` is unchanged while a mark is drawn | `PLAN.md` §1.10 | S11 |
| **TP-62** | A covered mark still exists in the data and is reachable through inspection | `Q19` | S11 |
| **TP-63** | Holding a card sets the match highlight on exactly the cells `matches_at` reports non-zero for | `Q66`=(a) | S12 |
| **TP-64** | The highlight writes the ELEMENT outlines, not a whole-card tint | `Q67`, `Q68` | S12 |
| **TP-65** | A card matching nothing produces no popup and no alert | `Q65`=(a) | S12 |
| **TP-66** ⚑gate | The layer view refuses input: a placement attempted while it is open changes nothing | `Q115`=(a) | S13 |
| **TP-67** | The layer view opens in BOTH the focused and the overview modes | `Q116`=(b) | S13 |
| **TP-68** | The layer toggle is reachable by keyboard, mouse and controller | `Q117`=(c), `START_HERE.md` rule 10 | S13 |
| **TP-69** | The layer view closes on any board mutation | pre-authorisation 17 | S13 |
| **TP-70** | The opening reveal is a no-op headless (`view == null`) and the board is dealt regardless | pre-authorisation 5 | S11 |
| **TP-71** 👁 | **The mark reads as grey, faded and ghostly at full card size in the cell frame**, and all four properties are legible | `Q63`=(d), `Q112` | S11 |
| **TP-72** 👁 | **A realized card's art and pips take their activated outlines**, distinguishable from the focus highlight and from the scoring beam on the same cell | `Q64` | S12 |
| **TP-73** 👁 | **The match highlight is distinguishable at overview zoom** across three grids | `Q66`=(a), `Q116`=(b) | S12 |
| **TP-74** 👁 | **The opening deal reads as a slot machine** and is skippable | `Q69`=(a) | S11 |
| **TP-75** 👁 | The palette-swap snapshot still passes with marks on the board | `ARCHITECTURE_REVIEW.md` §4i | S11 |

---

## The balance gate

| id | Test | Proves | Gates |
|---|---|---|---|
| **TP-80** ⚑gate | `Tools/scoring_parity.gd --parity` still reports **0 score mismatches** between the Python sim and the engine, with marks and matches modelled in both | `Q120`=(c) | S15 |
| **TP-81** ⚑gate | The refitted curve is winnable at **every** node for par play, and the run-win rates land in a sane band | `Q75`=(a), `Q120`=(c) | S15 |
| **TP-82** | The measured score ladder no longer PEAKS at node 3 — a bigger deck raises the ceiling | `GAP-041` | S15 |

---

## Deliberately NOT tested, and why

- **The look of the grey itself** beyond TP-71 — it is a palette role and a knob, tuned by eye
  against the running game, not asserted.
- **The exact tuning values** of `plan_talent_mult` and friends — they are knobs (`PLAN.md` §1.11),
  and a test pinning a knob's default is a test of the default, not of the mechanic.
- **Ragged-grid geometry beyond TP-06 and TP-15** — `Q78` keeps non-square grids to tests, and the
  grid's own shape is anti-scope.
- **Cross-run seed stability** — the map regenerates per run, so there is nothing stable to assert.
- **The Entrance's per-slot stocks themselves** — the sidebar design owns them and runs first; these
  tests consume them and do not re-prove them.

## Every design node has a claimant

Chart A → TP-01…TP-18 · chart B → TP-20…TP-27, TP-36…TP-39 · chart C → TP-30…TP-37, TP-80…TP-82 ·
chart D → TP-46…TP-52 · chart E → TP-16, TP-44, TP-45, TP-53, TP-54 · chart F → TP-60…TP-75.

⚠ A node no test proves is a behaviour that can regress silently. If you find one, that is a defect
in this document — say so.

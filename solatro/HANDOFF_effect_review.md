# HANDOFF — effect review

**Goal:** every candidate card effect for the 5×5-grid game reviewed by the owner, one question
each with three variants plus reject, and the rulings exported to a single CSV. Done = the owner has
answered all questions and `EFFECTS.csv` carries an approved-or-rejected row for every one.

**State:** two things are open. **S9**: the owner is answering (121 answered on `main`). **S15,
the card index (family AE)**, is half written on branch `card-index`: 223 of 439 concepts are
written, pair-reviewed, fixed and committed (classes AE1, AE2, AE3, AE4, AE8), plus the 10
structural questions of AE11; classes AE5, AE6, AE7, AE9 and AE10 (216 concepts) are not written.
The questionnaire on that branch renders 1,781 live questions, 0 errors, 0 warnings, no existing
id moved.
A session on another machine needs `card-index` pushed: it was created local-only, in a worktree
beside the main checkout, and the owner pushes it.

**Entry docs:** `solatro/design/effect-review/build/GAME_BRIEF.md` (the rulebook every effect must
fit — read it before judging anything) · `solatro/design/effect-review/build/REVIEW.md` (how to
change the build without moving an answered id) · `designloop/README.md` (the questionnaire tool) ·
`.claude/skills/flowchart-design/SKILL.md` §5 (question grammar)

## How to run it

```
npm --prefix designloop start
```
→ `http://localhost:5273/web/question.html?key=solatro/effect-review`

```
npm --prefix designloop run check -- solatro/effect-review    # must be 0 errors, 0 warnings
py solatro/design/effect-review/build/render.py               # rebuild DESIGN.md from the build data
py solatro/design/effect-review/export_csv.py                 # rebuild EFFECTS.csv from answers
```

⚠ **Never hand-edit `DESIGN.md`.** It is generated. Edit the data under `build/` and re-render, or
the next render silently discards the edit.

## Where everything lives

| Path | What |
|---|---|
| `solatro/design/effect-review/DESIGN.md` | the questionnaire — GENERATED, do not edit |
| `solatro/design/effect-review/EFFECTS.csv` | the deliverable, one row per question |
| `solatro/design/effect-review/DROPPED.csv` | all 1,160 drops, with reason and fold-target |
| `solatro/design/effect-review/export_csv.py` | answers → CSV; reads only its own directory |
| `solatro/design/effect-review/build/` | the whole reproducible pipeline (below) |
| `build/taxonomy_data.py` | **the source of truth for families and classes.** Render order comes from here; a class not in this file sorts as unclassified |
| `build/render.py` | assembles header + questions + footer into `DESIGN.md` |
| `build/corpus.tsv` | 2,086 deduped mined effects, ids `E0001`–`E2086` |
| `build/mine_*.tsv` | the five raw mining outputs, pre-dedupe |
| `build/decisions/d*.py` | keep/drop rulings **and** variants, written inline (`DROPS` + `KEEPS`) |
| `build/generated/g*.py` | effects written from scratch, ids `G0001`–`G0483`. A module may declare `SOURCE` to cite the game it came from |
| `build/SOURCES.md` | **the register of every source mined, skipped or outstanding.** Update it whenever a source is added |
| `build/variants/v*.py` | variants for batch 1, which was tagged separately in `batches/tagged01.tsv` |
| `build/GAME_BRIEF.md` | the rules brief every mining subagent must be given |
| `build/TAXONOMY_CODES.md` | the 226 class codes, regenerate with `build_taxonomy_page.py` |
| `build/levels.py`, `build/levels/l<FAM>.py` | the level-2 pass: one row per question (verdict, level 2, flag reason); `render.py` draws the level 2 and the ⚑ flag from it |
| `build/generated/g029.py` | family AC, one row per answered effect — **the record for AC rows; edit it directly** |
| `build/generated/g030.py` | family AD, the effects the design review proposed — the record for AD rows; its level rows (`levels/lAD.py`) are keyed by qid, and a new AD row renumbers the AD rows after it, so rewrite `lAD.py` after rendering |
| `build/fixkit.py`, `build/retired_questions.py` | `set_options`, `retire`, `patch`, `verify`; every retired question and why, keyed by eid |
| `build/mine_mods/` | **S13 working set**: the mod-wiki crawl in chunks, per-chunk candidate TSVs, `new_draft.tsv` (the judged keep-list), the subagent briefs, the dedupe groups |

## Tasks

```yaml
- id: S1
  description: Mine every text doc in the repo plus the Balatro and Cryptid wikis.
  status: done

- id: S2
  description: Deduplicate the mined corpus mechanically.
  status: done

- id: S3
  description: Build the design-space taxonomy and get the owner to review it before writing questions.
  status: done

- id: S4
  description: Judge all 2,086 corpus rows keep/drop, retag to the taxonomy, rewrite survivors as grid-native mechanics, and write three variants each.
  status: done

- id: S5
  description: Generate effects for taxonomy classes the corpus left empty, excluding family N.
  status: done

- id: S6
  description: Audit every source document for content the mining pass missed.
  status: done

- id: S7
  description: Ship the exporter and the drop ledger, and prove every answer branch resolves.
  status: done

- id: S8
  description: Mine eight external games for the spatial, height, class-synergy and prop families, which Balatro and Cryptid could not feed because neither has a board.
  status: done

- id: S10
  description: Extend the reference-game pass to every game worth mining, and register the full source list.
  status: done

- id: S11
  description: Coverage depth - reconsider the declined sources, fill the 35 one-or-two-effect classes, and deepen family Q.
  status: done

- id: S12
  description: >
    Re-mine the corpus against the GRID versions of DESIGN_DOC.md,
    DESIGN_RECOMMENDATIONS.md and DESIGN_REFERENCES.md, which replaced the pre-grid ones this
    corpus was mined from. 228 questions use acts, act payouts, Submit or patience; none of those
    exist. 7 of the 28 answered questions are affected.
  files_touched: [solatro/design/effect-review/build/corpus.tsv, solatro/design/effect-review/build/decisions, solatro/design/effect-review/build/generated]
  verification_command: 'npm --prefix designloop run check -- solatro/effect-review'
  verification_kind: manual
  status: pending
  evidence: ''
  notes: >
    ✅ UNBLOCKED. The `poker-patience` branch was merged into `main` (merge commit `ced07dbc`), so
    the GRID versions of DESIGN_DOC.md, DESIGN_RECOMMENDATIONS.md and DESIGN_REFERENCES.md are now
    the ones on disk and the re-mine will read them. The pre-grid originals are under
    `solatro/archive/`. This was the last thing standing in front of S12; the work itself has not
    started.
    Two decisions the owner has to make before this runs, because they change the deliverable:
    (1) an affected question that has ALREADY been answered -- re-ask it, or carry the ruling
    across if the mechanic survives the translation intact? (2) a question whose mechanic WAS an
    act or a Submit and has no grid analogue -- drop it to DROPPED.csv, or restate it as the
    nearest grid mechanic and let the owner reject it there?
    The rules from the opening prompt still bind: never hand-edit DESIGN.md, re-render with
    build/render.py, keep the check at 0 errors and 0 warnings, generate nothing for family N.
    build/GAME_BRIEF.md is already rewritten for the grid economy -- it is the brief any mining
    pass must be given, and it is the model for what the restated questions should sound like.

- id: S13
  description: >
    Retire the `rule` slot (owner ruling: the rules deck is a deck, not an effect), mine every
    content mod on balatromods.miraheze.org for effects the questionnaire lacks, and remove
    duplicate questions.
  status: done

- id: S14
  description: >
    The level-2 pass. Every live question read for uniqueness and fun; every matchable effect
    (skill, stamp, suit, rank) given its form "when hitting its own mark"; duplicates retired in
    place, including a level 2 that equals another effect's level 1; new mark-hitting effects in
    family AB; the level 2 of every effect the owner already ruled on asked in family AC. Opus 5.5
    writes, a Fable pair reviewer reads each family before it lands.
  files_touched: [solatro/design/effect-review/build/levels.py, solatro/design/effect-review/build/levels, solatro/design/effect-review/build/render.py, solatro/design/effect-review/export_csv.py, solatro/design/effect-review/build/taxonomy_data.py, solatro/design/effect-review/build/GAME_BRIEF.md, solatro/design/effect-review/build/generated, solatro/design/effect-review/build/retired_questions.py, solatro/design/effect-review/build/header.md]
  verification_command: 'py solatro/design/effect-review/build/levels.py stat && py -c "import sys; sys.path.insert(0, 'solatro/design/effect-review/build'); import fixkit; fixkit.verify()" && npm --prefix designloop run check -- solatro/effect-review'
  verification_kind: manual
  status: in_progress
  evidence: >
    1,548 live, 278 retired (195 this round), 0 errors, 0 warnings, order unchanged Q0001-Q1509.
    Level rows cover every live question in A-AB (`levels.py stat`); 196 had options rewritten, 210
    carry a flag; family AB 19 live (Q1679-Q1699, two retired), family AC 98. Every family read by a
    Fable pair reviewer and the findings applied, then a final review of the round.
  notes: >
    Owner rulings are in `build/GAME_BRIEF.md` § Every matchable effect has two levels. The owner
    answered "go" to: level 2 written once per effect as a change true of all three options, per
    option only where the options differ in mechanism; answered effects get their level 2 in a
    last-sorting family (AC) so no recorded answer changes meaning; clear duplicates among
    unanswered questions retired in place naming the twin, anything touching an answered question
    asked instead; rank's level 2 is the rank-match points bonus. Owner, on starting: "you and
    reviewer will need to review every single effect and consider its uniqueness and funness" and
    "feel free to add any random ideas you have that fits the poker square mark hitting gameplay
    loop". The engine gives every property level 2 on any match: `design/board-plan/gaps/GAP-007.md`.
    Branch `effect-levels`, in its own worktree because another session holds the base branch;
    merge back into `combine-sidebar-boardplan` when done. ⚠ `answers.json` belongs to the owner's
    checkout: before merging, re-read it and move any question answered since into family AC.

- id: S15
  description: >
    The card index, family AE. Recognisable cards from everywhere (Arthur Lloyd's Human Card Index
    and everyday cards, card/board/dice/casino games, Stacklands, Dungeons & Degenerate Gamblers)
    kept by NAME and idea only, each given an effect that fits the grid, or offered as a rename of
    a live effect ("Renames Qnnnn (Old Name): ..."). One question per concept, a level 2 for every
    skill, stamp, suit and rank. Opus writes a batch, a Fable pair reviewer returns a fix list, the
    overseer applies it.
  files_touched: [solatro/design/effect-review/build/mine_cardindex, solatro/design/effect-review/build/generated, solatro/design/effect-review/build/levels/lAE.py, solatro/design/effect-review/build/taxonomy_data.py, solatro/design/effect-review/build/SOURCES.md, solatro/design/effect-review/DESIGN.md]
  verification_command: 'py solatro/design/effect-review/build/mine_cardindex/levels_ae.py && py -c "import sys; sys.path.insert(0, ''solatro/design/effect-review/build''); import fixkit; fixkit.verify()" && npm --prefix designloop run check -- solatro/effect-review'
  verification_kind: manual
  status: in_progress
  evidence: >
    233 AE rows in levels/lAE.py, v2 name check clean; fixkit.verify: order unchanged
    Q0001-Q1509; designloop check: 1,781 live, 278 retired, 0 errors, 0 warnings. Commits
    959c1702, f8167f17, ecd1f459, 1cfcbe00, 97d30d55, d61f3c2d, b9342f89 on `card-index`.
  notes: >
    Owner rulings, verbatim: "add to designloop questionnaire, thats why a rename is allowed in the
    first place." "cards will have suit and rank, a catan wood card for example would have wood as
    the talent, or have it as card type, since cards need to be modifiable in general and still
    participate in melds." "wide pool is good, just dont have references be specific to lore of
    other games, should be stuff most people are familiar with or they will be unable to get the
    reference." "due to possible duplicate names for different effects, we dont want to lose
    effects due to naming, so allow duplicate names but just mark it with v2 or something like
    that." Braindump lines the family must carry as written: "Scary clown, kills/discards a card on
    board left alone for too long and takes its place, global" (CI0438); "Table flip, cards
    surrounding switch to opposite positions" (CI0245); "Stacking token type cards doesnt create a
    stack but combines ranks into one card since theoretically fungible" (CI1103 Fungible);
    "Talent packs could instead become packs towards a specific existing theme such as a catan
    themed pack" (CI1101); the minigames are "likely out of scope since scope creep" (CI1105-1109,
    flagged). Branch `card-index` is based on `effect-levels`; merging `main` conflicts in
    `solatro/Cards/card_visual.gd`, which is not this stream's file.

- id: S9
  description: Owner answers the questionnaire; export the final CSV.
  files_touched: [solatro/design/effect-review/EFFECTS.csv]
  verification_command: 'py solatro/design/effect-review/export_csv.py'
  verification_kind: manual
  status: pending
  evidence: ''
  notes: 'Nothing blocks this. Run the export at any point for a partial picture; unanswered questions come out as `unanswered` rather than being dropped.'
```

## Verified vs assumed

- **1,781 live questions, 278 retired, 0 errors, 0 warnings, 0 dag-audit defects** on
  `card-index` — verified, `npm --prefix designloop run check -- solatro/effect-review`
  (1,548 before family AE).
- **Every reviewed AE batch had its fix list applied** — verified by construction, one commit per
  batch. **The 216 unwritten concepts** — nothing exists for them but their keep-list rows.
- **`header.md` still says 1,548 and does not mention family AE** — known, left for the S15 close.
- **No class outside family N and feel-only W sits below four effects** — verified by counting
  keepers per class off the rendered document.
- **Nineteen pairs of live effects share a name** — measured by grep; renaming waits for the final effects.
- **The question screen renders and is answerable** — verified by eye in a browser: header, three
  variants, reject, the recommendation marked for Enter, and the free-text box all present.
- **The pipeline is machine-independent** — verified, zero absolute paths remain under `build/`,
  and `render.py` + `export_csv.py` both run from the repo copy.
- **Every corpus row is accounted for** — verified, 926 + 1,160 = 2,086.
- **Owner rulings applied** — verified by construction: variants differ per effect rather than by a
  fixed axis; family N generates nothing; the recommended answer is never `(d)`; an upgrade is
  ordered directly after the effect it upgrades (11 such pairs).
- **The Solatro test suite has not been run** — **assumed irrelevant, not checked.** This stream
  touches no game code, only `solatro/design/effect-review/` and one new handoff file.
- **Balance of any effect** — **assumed nothing.** Numbers in the options exist to make the three
  variants distinguishable; rarity and tuning are a later pass against `solatro/Tools/scoring_sim.py`.

## Open bugs

None known in the pipeline. Two judgement calls the owner may want to revisit:

1. **747 DUPLICATE drops** are the largest single judgement surface, and the design docs restate the
   catalogue under historical names constantly. `DROPPED.csv` sorts by reason so the DUPLICATE block
   can be scanned; each row names the id it was folded into.
2. **`G0142` The Overhead Show** was classed `C6` (grid shape) rather than treated as family N. It
   is a play zone above the grid, not a camera move — but it is the one call on that boundary.
3. ⚠ **The discard pile: the brief and the code disagree.** `build/GAME_BRIEF.md` says the discard
   pile "persists to the next show"; `solatro/Levels/game.gd` (`returned.append_array(state.discard_deck)`)
   returns it to the run deck at show end. Owner ruling needed; family AE writes "to the discard
   pile" as out for this show only (`mine_cardindex/WRITE_PROMPT.md` § Code facts).
4. **`card-index` lacks the three answers on `main`** (121 answered there). Before the S15 close,
   `git show main:solatro/design/effect-review/answers.json` and regenerate `_live_index.tsv`
   with `mine_cardindex/live_index.py`; an AE rename must not target a question since rejected.
5. **One live effect is offered to two AE names** in places (Q0336 by Jumping Jack, and Double Jump
   will want it; Q0681 was avoided for Permission Slip). The final review must list every Qnnnn
   named by more than one "Renames" option.
6. TOOLING (this session): `doc_check.py` flags `taxonomy_data.py` lines for class codes Q2-Q8,
   a standing false alarm. Reviewers: every one of the eight pair reviews found new options that
   were a live effect under a new name (caught, 2-5 per batch); one reviewer's code claim (Undo
   unlimited) was corrected by the next (capped at 25). Proposed, not built: a script that applies
   a reviewer's `eid field = text` fix list through `patch_ae.py`, since the overseer hand-wrote
   that script five times.

## Next up — S15, the card index

Everything lives in `solatro/design/effect-review/build/mine_cardindex/`:
`concepts.py` (the keep-list: eid, name, class, sources, steer; and every drop with its reason),
`WRITE_PROMPT.md` (the writer's brief, grown by each review: shapes that do nothing, shapes used
up, code facts), `REVIEW_PROMPT.md` (the reviewer's brief and its fix-list format), `patch_ae.py`
(apply fixes by eid), `levels_ae.py` (the v2 name check, and `levels/lAE.py` rebuilt from each
module's `LEVEL2` and `FLAGS`), `live_index.py` (every live question with the owner's ruling, for
finding rename targets), and the mining records.

**One batch = one loop:** a general-purpose Opus subagent writes the module from `WRITE_PROMPT.md`;
`py build/mine_cardindex/levels_ae.py` must pass; a `pair-reviewer` subagent reads it against
`REVIEW_PROMPT.md` and returns a numbered fix list; the overseer applies it with `patch_ae.py`,
runs `levels_ae.py` then `render.py`, and commits the module, `DESIGN.md` and `levels/lAE.py`.
A review runs while the next batch is written; never two writers on the same class at once.

| Batch | Concepts | Module, `SOURCE` | Notes for the writer's task message |
|---|---|---|---|
| AE5 tarot | CI0501-CI0524 | module `g039`, "tarot and fortune" | most arcana names are live already (Balatro): the row is `<Name> v2` with its own effect built from the card's picture, and a rename only to a live effect under a DIFFERENT name; Cups, Wands, Swords, Coins are suit rows (`"SUIT"`) |
| AE6 board games 1 | CI0601-CI0629 | module `g040`, "board games" | no money: rent, tax and mortgage in points, cards or combo; House and Hotel are a pair; the Clue weapons do what the OBJECT does; Top Hat is a stamp |
| AE6 board games 2 | CI0630-CI0658 | module `g041`, "board games" | Bomb and Epidemic sit beside Exploding Kitten (g036); Spy and Werewolf beside Cheat |
| AE7 pieces | CI0701-CI0730 | module `g042`, "tiles, dice and pieces" | the chess pieces are live (Pawn, Knight, Rook, Bishop, Queen): v2 with a new effect, never a same-name rename; Double Jump wants Q0336, which Jumping Jack already offers; dice and coins must be seeded; Heads or Tails sits beside The Coin Flip (CI1106) |
| AE9 resources | CI0901-CI0927 | module `g043`, "resources and tokens" | the owner's ruling: a resource is a type (Wood, Brick, Stone) or a talent (Wheat), with suit and rank kept; Fungible (CI1103) is the merge rule they share; Stone, Glass, Gold and Iron types are live; Coin is a counter, never currency |
| AE10 village 1 | CI1001-CI1037 | module `g044`, "Stacklands" | villagers, buildings, Idea (a recipe: two cards stacked make a third); House is `House v2` (CI0609 holds House) |
| AE10 village 2 | CI1038-CI1077 | module `g045`, "Stacklands" | beasts and weather are hazards with a counterplay; equipment is the stamp slot; Ghost must agree with the owner's ghost card (a card that leaves at show end) |

**The close, once every batch is in:** one pair review of the whole family for cross-batch repeats
and a Qnnnn offered by two renames; `build/header.md` (the counts, and a paragraph on family AE
under "What changed"); `py build/build_taxonomy_page.py`; `py export_csv.py`;
`status.agent.json`; `py .claude/tools/doc_check.py`; Open bugs 4 and 5 above; then ask the owner
how `card-index` should land (it carries `effect-levels`).

Owner rulings from reading round 2 (recorded in `build/GAME_BRIEF.md`): fame is not spendable (a
cost paid in fame is a skipped reward); a property's level 2 is unlocked by its own match only,
unless an effect says otherwise (`design/board-plan/gaps/GAP-007.md`, dispatch change not yet
built); a second pass gave a level 2 to every skill, stamp and rank but Q0226, Q0935, Q1408, Q1409 and
Q1494, and a Fable review of that pass is applied.
Shared effect names (nineteen pairs, e.g. The Dead End Q1397/Q1477) wait until the effects are final:
names are sort keys, and the owner will rename against the final set.

Owner rulings on the whole-game questions are in `build/GAME_BRIEF.md`: a bonus with no line goes
to special; a fake is a ghost card, which leaves the deck when its show ends; a token is any card,
and the effect decides whether a card it creates stays; a step is flat points, tuned per effect.
Every effect that creates a card now says whether it stays or is a ghost, in its description.

## S13 and S14

Both are done; their task rows and `build/SOURCES.md` wave 6 hold what remains. The S13 working
set is `build/mine_mods/`.

Then **S9 — the owner answers.** S12 (re-mining the pre-grid corpus) is superseded in practice:
the architecture review recorded in `header.md` re-read every question against the grid.

## Provenance

**IMPLEMENTED-BY (the Phase 10 documentation rewrite this stream now depends on): Claude Opus 5**
— `solatro/design/poker-patience/PLAN.md` §2 Phase 10, steps S40, S41 and S44, on the
`poker-patience` branch.

**IMPLEMENTED-BY (S15, the card index):** overseer Claude Opus 5.5 (the keep-list, class AE11,
the tools, every fix applied); writers Claude Opus 5.5 as general-purpose subagents, one per batch;
mining and one fix-application pass Claude Sonnet 5.5; every review the `pair-reviewer` agent
(Fable). No game code was written.

## Opening prompt for the next agent

> Continue S15, the card index (family AE of the effect review), on branch `card-index`. Read
> `solatro/HANDOFF_effect_review.md` — "Next up — S15" is the resumption point — then
> `solatro/design/effect-review/build/mine_cardindex/WRITE_PROMPT.md` and `REVIEW_PROMPT.md`, and
> `build/GAME_BRIEF.md`. Run the S15 verification command first; it must pass before anything is
> written. Then work the batch table top to bottom (AE5 first), one writer and one reviewer at a
> time, and finish with the close. Not negotiable: never hand-edit `DESIGN.md`; never rename or
> delete an existing effect (the question id is positional); a name a live effect holds carries
> ` v2`; every card keeps a suit and a rank; references a general audience recognises; commit one
> batch per commit on `card-index`, never on `main`; no Godot is needed and none may be run. On a
> machine without the `py` launcher use `python3`.

## References

- Family AE sources: `build/SOURCES.md` wave 7 (Genii Magicpedia's Arthur Lloyd page, the Stacklands
  Fandom Cardopedia, the Degenerate Gamblers wiki's Cards page)
- Question grammar: `.claude/skills/flowchart-design/SKILL.md` §5 and
  `designloop/design/designloop/PLAN.md` §5 (normative)
- `answers.json` contract: `designloop/design/designloop/PLAN.md` §4.3
- Mined wikis: balatrowiki.org (Jokers, Card modifiers, Stakes, Blinds and Antes, Tags, Challenge
  Decks) and balatromods.miraheze.org (Cryptid Jokers, Decks, Sleeves, Challenges, Card Modifiers,
  Poker Hands, Stakes, Boss Blinds, Tags; Pokermon Challenges)
- Reference games for S8: [Concrete Jungle](https://store.steampowered.com/app/400160/Concrete_Jungle/) ·
  [Luck be a Landlord wiki](https://luck-be-a-landlord.fandom.com/wiki/Synergies) ·
  [Backpack Battles wiki](https://backpack-battles.fandom.com/wiki/Game_Mechanics) ·
  [Ballionaire](https://ballionaire.net/) ·
  [Santorini rules](https://officialgamerules.org/game-rules/santorini-rules/) ·
  [Cascadia rules](https://officialgamerules.org/game-rules/cascadia/)

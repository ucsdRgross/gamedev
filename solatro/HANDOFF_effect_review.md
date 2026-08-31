# HANDOFF — effect review

**Goal:** every candidate card effect for the 5×5-grid game reviewed by the owner, one question
each with three variants plus reject, and the rulings exported to a single CSV. Done = the owner has
answered all questions and `EFFECTS.csv` carries an approved-or-rejected row for every one.

**State:** the questionnaire is **built, live and answerable** — 1,409 questions, 0 parser errors,
0 warnings. The owner has answered **none** yet; `answers.json` does not exist. Every source is
mined and folded in: nine repo documents, two reference wikis, and thirty-six external games
registered in `build/SOURCES.md`. Every repo
source has been line-audited for content the mining pass missed. **Every taxonomy class outside
family N and the deliberately-excluded feel-only family W now carries at least four effects.**
**All build tasks are done — the only pending task is the owner answering (S9).**

**Entry docs:** `solatro/START_HERE.md` · `solatro/design/effect-review/DESIGN.md` ·
`designloop/README.md` (the questionnaire tool) · `.claude/skills/flowchart-design/SKILL.md` §5
(question grammar)

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

## Tasks

```yaml
- id: S1
  description: Mine every text doc in the repo plus the Balatro and Cryptid wikis.
  files_touched: [solatro/design/effect-review/build/mine_catalog.tsv, solatro/design/effect-review/build/mine_designdocs.tsv, solatro/design/effect-review/build/mine_braindump.tsv, solatro/design/effect-review/build/mine_balatro.tsv, solatro/design/effect-review/build/mine_cryptid.tsv]
  verification_command: 'wc -l solatro/design/effect-review/build/mine_*.tsv'
  verification_kind: manual
  status: done
  evidence: '2,234 rows: catalog 378, designdocs 758, braindump 459, balatro 249, cryptid 390.'
  notes: 'Five parallel sonnet subagents. Parallel spawning later hit a session rate limit; see S4 notes.'

- id: S2
  description: Deduplicate the mined corpus mechanically.
  files_touched: [solatro/design/effect-review/build/corpus.tsv, solatro/design/effect-review/build/dupes.tsv]
  verification_command: 'py solatro/design/effect-review/build/consolidate.py'
  verification_kind: manual
  status: done
  evidence: '2,234 loaded -> 2,086 survivors, 148 folded. Every fold recorded in dupes.tsv.'
  notes: 'Union-find over name equality plus jaccard on content words. Conservative on purpose.'

- id: S3
  description: Build the design-space taxonomy and get the owner to review it before writing questions.
  files_touched: [solatro/design/effect-review/build/taxonomy_data.py]
  verification_command: 'py -c "import sys;sys.path.insert(0,''solatro/design/effect-review/build'');from taxonomy_data import FAMILIES;print(len(FAMILIES),sum(len(f[3]) for f in FAMILIES))"'
  verification_kind: manual
  status: done
  evidence: '24 families, 226 classes. Started at 23/208; the owner review and a later self-audit added 18 classes and family X.'
  notes: 'Owner excluded family N (view/camera/UI) from question generation. The 10 N classes are kept in the taxonomy so the hole stays visible, and must NOT be filled.'

- id: S4
  description: Judge all 2,086 corpus rows keep/drop, retag to the taxonomy, rewrite survivors as grid-native mechanics, and write three variants each.
  files_touched: [solatro/design/effect-review/build/decisions, solatro/design/effect-review/build/variants, solatro/design/effect-review/build/batches]
  verification_command: 'py solatro/design/effect-review/build/render.py'
  verification_kind: manual
  status: done
  evidence: '926 kept, 1,160 dropped (747 DUPLICATE, 130 NO_MECHANIC, 119 RESKIN, 113 ALREADY_A_RULE, 51 NOT_APPLICABLE). All 2,086 accounted for.'
  notes: 'Batch 1 (261 rows) was tagged by a sonnet subagent into batches/tagged01.tsv; the rest was done inline after eight parallel subagents died to a rate limit. Inline turned out faster than serial subagents anyway.'

- id: S5
  description: Generate effects for taxonomy classes the corpus left empty, excluding family N.
  files_touched: [solatro/design/effect-review/build/generated]
  verification_command: 'py solatro/design/effect-review/build/render.py'
  verification_kind: manual
  status: done
  evidence: '143 generated effects, G0001-G0143. 216 of 226 classes now represented; the 10 absent are exactly family N.'
  notes: 'g001/g002 fill classes empty after the corpus pass. g003/g004 fill 18 classes the taxonomy itself had failed to name. g005 recovers 10 from gam draft.txt. g006 recovers 2 from DESIGN_REFERENCES.md.'

- id: S6
  description: Audit every source document for content the mining pass missed.
  files_touched: [solatro/design/effect-review/build/audit_refs.py]
  verification_command: 'py solatro/design/effect-review/build/audit_refs.py'
  verification_kind: manual
  status: done
  evidence: '`gam draft.txt` 10 real misses, recovered into g005. `DESIGN_REFERENCES.md` 391 mechanic proposals, 2 misses, recovered into g006. The curated pre-grid sheet 25 of 25. The random-effects sheet, `DESIGN_DOC.md` and `DESIGN_RECOMMENDATIONS.md` clean. `todo.md` and `pokerpatience.txt` correctly skipped as engineering and layout.'
  notes: 'The one real failure mode was section-level skipping on the braindump, which interleaves mechanics with reference prose line by line. audit_refs.py works off the reference doc''s own hook tags (`Skill`, `Naming`, `Visual`); naive token overlap gave 167 false positives because the miner was told to strip the history that makes up most of each row.'

- id: S7
  description: Ship the exporter and the drop ledger, and prove every answer branch resolves.
  files_touched: [solatro/design/effect-review/export_csv.py, solatro/design/effect-review/DROPPED.csv]
  verification_command: 'py solatro/design/effect-review/export_csv.py'
  verification_kind: manual
  status: done
  evidence: 'Tested against a synthetic answers.json covering chosen / rejected / override / defaulted / not_relevant / note-plus-choice / inactive. All seven resolved correctly.'
  notes: 'Follows the answers.json contract in designloop/design/designloop/PLAN.md §4.3. Set EFFECT_REVIEW_DIR to point it at a test copy.'

- id: S8
  description: Mine eight external games for the spatial, height, class-synergy and prop families, which Balatro and Cryptid could not feed because neither has a board.
  files_touched: [solatro/design/effect-review/build/generated/g007.py, solatro/design/effect-review/build/generated/g008.py, solatro/design/effect-review/build/generated/g009.py, solatro/design/effect-review/build/generated/g010.py]
  verification_command: 'npm --prefix designloop run check -- solatro/effect-review'
  verification_kind: manual
  status: done
  evidence: '55 effects added, G0144-G0198. 1,124 questions, 0 errors, 0 warnings, 0 dag-audit defects.'

  notes: 'Written straight as generated effects rather than mined to a TSV first: these are mechanic SHAPES translated to this game, not card lists to dedupe, so the corpus/dedupe path would have added nothing. Generated modules may now declare SOURCE so each cites its game. Santorini and the Zachtronics collection carry the most weight - god powers are rule-breakers on a 5x5 grid with height, and each Zachtronics game is a different stacking or foundation ruleset.'

- id: S10
  description: Extend the reference-game pass to every game worth mining, and register the full source list.
  files_touched: [solatro/design/effect-review/build/SOURCES.md, solatro/design/effect-review/build/generated/g011.py, solatro/design/effect-review/build/generated/g012.py, solatro/design/effect-review/build/generated/g013.py, solatro/design/effect-review/build/generated/g014.py]
  verification_command: 'npm --prefix designloop run check -- solatro/effect-review'
  verification_kind: manual
  status: done
  evidence: '53 more effects, G0199-G0251. 1,177 questions, 0 errors, 0 warnings, 0 dag-audit defects. build/SOURCES.md registers all 25 external sources plus the 9 repo documents, and names what was deliberately skipped and why.'
  notes: 'The wave-2 list of eight was not principled - it was where the first search landed. Open-Face Chinese Poker should have been first and was missed entirely: it deals cards irrevocably into rows scored as poker hands, and brings fouling (a validity constraint ACROSS lines) and positional royalties (the same hand worth more in a harder line), neither of which this game had. The stopping test is now written down in SOURCES.md: mine a source only if it fills a taxonomy class that is empty or thin.'

- id: S11
  description: Coverage depth - reconsider the declined sources, fill the 35 one-or-two-effect classes, and deepen family Q.
  files_touched: [solatro/design/effect-review/build/SOURCES.md, solatro/design/effect-review/build/generated/g015.py, solatro/design/effect-review/build/generated/g016.py, solatro/design/effect-review/build/generated/g017.py, solatro/design/effect-review/build/generated/g018.py, solatro/design/effect-review/build/generated/g019.py, solatro/design/effect-review/build/generated/g020.py]
  verification_command: 'npm --prefix designloop run check -- solatro/effect-review'
  verification_kind: manual
  status: done
  evidence: '232 effects added, G0252-G0483. 1,409 questions, 0 errors, 0 warnings, 0 dag-audit defects. Every class outside family N and feel-only W is at 4 or more; the minimum was 1. Family Q 24 -> 63, X 18 -> 35, V 29 -> 45, T 32 -> 45.'
  notes: 'Three of the four declined categories were overturned - Netrunner/Magic/Hearthstone, Peglin/Dicey Dungeons/Astrea, and the Slay the Spire family. Each was declined on the games COMBAT loop; the material that passes the stopping rule comes from the layers around it. Family N stays declined by owner ruling. SOURCES.md carries the re-test in full.'

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

- **1,409 questions, 0 errors, 0 warnings, 0 dag-audit defects** — verified,
  `npm --prefix designloop run check -- solatro/effect-review`.
- **No class outside family N and feel-only W sits below four effects** — verified by counting
  keepers per class off the rendered document.
- **No two live effects share a name** — verified; fourteen wave-4 collisions were renamed.
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

3. **Nine pre-wave-4 name collisions remain**, ignoring a leading "The": Canvas, Cascade, Double
   Billing, Fourth Wall, Negative, Ox, Second Sight, Showman, Understudy. Each pair sits in a
   different class with a different mechanic, so nothing is duplicated — only the names read alike
   when scanning. Wave 4 has none; its fourteen were renamed as they were found.

## Files touched

```
solatro/HANDOFF_effect_review.md            new
solatro/design/effect-review/               new directory
  meta.json, DESIGN.md, EFFECTS.csv, DROPPED.csv, export_csv.py, ui_meta.json
  build/                                    new — 20 files + 4 subdirectories (20 generated modules)
```
No game code, no tests, no vendored addon touched.

## Next up

**S9 — the owner answers.** It is the only task left. Nothing blocks it, no further mining is
required, and the build side is finished: every class outside family N and feel-only W offers at
least four choices, so no class forces a decision the owner has no alternatives within.

Per-family totals at 1,409 questions:
`G 94` · `S 92` · `A 86` · `I 82` · `C 80` · `P 77` · `D 73` · `E 69` · `L 67` · `B 65` · `Q 63` ·
`H 59` · `K 58` · `F 58` · `U 57` · `R 53` · `O 52` · `M 50` · `J 47` · `T 45` · `V 45` · `X 35` ·
`W 2` · `N 0`.

If more depth is ever wanted, the honest remaining thin spots are `W` (2, excluded on purpose) and
the classes still in single figures inside otherwise-large families — but the taxonomy no longer has
a hole, and further generation would be padding rather than coverage.

## Opening prompt for the next agent

> Read `solatro/HANDOFF_effect_review.md`, then `solatro/design/effect-review/build/GAME_BRIEF.md`.
>
> The effect-review questionnaire is **finished on the build side** — 1,409 questions, 0 parser
> errors, 0 warnings, and every taxonomy class outside family N (excluded by owner ruling) and
> feel-only family W carries at least four effects. The owner has answered none of it yet.
>
> The only remaining task is **S9: the owner answers**, then
> `py solatro/design/effect-review/export_csv.py` rebuilds `EFFECTS.csv`. Run the export at any
> point for a partial picture; unanswered questions export as `unanswered` rather than being dropped.
>
> **If you are asked to add more effects anyway, the rules are not negotiable:**
> - Never hand-edit `DESIGN.md`. It is generated by `build/render.py` from the data under `build/`.
> - Add new effects as the next numbered `build/generated/g*.py`, declaring `SOURCE` for provenance.
> - Re-render with `py solatro/design/effect-review/build/render.py`, then verify with
>   `npm --prefix designloop run check -- solatro/effect-review`. **It must stay 0 errors, 0 warnings.**
> - Generate nothing for family **N** (view, camera, UI). The owner excluded it; its 10 classes stay
>   in the taxonomy so the hole remains visible.
> - Every effect must fit one card slot — suit, rank, type, stamp, skill, consumable, rule or status.
> - Three variants per effect that differ in a way worth choosing between, plus reject. The
>   recommended answer is never reject.
> - No two live effects may share a name; check before rendering.
> - Update `build/SOURCES.md` whenever a source is added, mined or declined, and update this handoff
>   before the session ends.
>
> Do not spawn parallel subagents — a previous session lost eight to a rate limit and inline work
> proved faster anyway.

## References

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

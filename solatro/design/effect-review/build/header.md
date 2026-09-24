# Effect review — every candidate effect, three variants each

**This is not a feature design.** It is a content-selection round. Every question is one
candidate effect, and every answer is a ruling on whether that effect enters the game and in
which form. Nothing here specifies how anything is built.

**1,527 live questions, plus 270 retired in place.** There is no branching: every question is
independent, so the count you see is the count you answer. Rejecting is one keystroke.

## ⚠ What changed since your round-1 answers

**Every matchable effect now shows its level 2 — its form "when hitting its own mark".** Your
rulings (`build/GAME_BRIEF.md`, "Every matchable effect has two levels"): a match is same kind to
same kind, and a property's level 2 is unlocked by its own match only; a suit or rank is plain at
level 1 and its effect is the level-2 addition; a skill's or stamp's level 2 is its own effect in
the same class and file; a talent match always pays the flat mult as well. Every question was
re-read for its level 2, its uniqueness and its fun, and each family was read a second time by a
pair reviewer before you see it.

- **Where the level 2 is.** In the question's head when it is true of all three options, inside each
  option when the options differ. A suit or rank says "level 1 is the plain suit; each option is its
  level 2". Type, consumable, status, hazard and structure have none: they never sit on a mark.
  Every skill, stamp and rank has one except three: two feel-only effects (Q1408, Q1409) and a
  card that is never placed (Q1494). A rule or hazard carried by a skill gets a looser form, or
  relief, while its card sits on its own mark, so there is a reason to aim it.
- **Your recorded answers still mean what you chose.** Q0011 and Q0047 are still the only answered
  questions that are retired. Nothing you answered was edited; its level 2 is asked in family AC.
- **187 more questions are retired in place**, each naming why: duplicates and twins (where one
  effect's level 2 was another's level 1 — the Queen is now the Rook's and the Bishop's level 2),
  premises the game does not have (shops, gold, selling, the rules deck, stickers), and effects that
  are already rules (undo, straights wrapping through the Ace, talent no longer suppressing a suit).
  A retired question still renders as a one-line note because the question id is positional.
- **196 had options rewritten** — a shop or gold clause taken out where the effect survives without
  it, an "inspection" downside replaced, an effect that fired at show start (when the card is still
  in the deck) moved to when it is placed, a second-grid option made to work on one grid.
- **Ten changed slot** to the one their mechanic needs (a boss filed as a skill is now a hazard, a
  mark rule that carries a hat is now a stamp); the class is kept, so no id moved. **Four defaults
  moved** to the form a board-plan ruling already names.
- **210 carry a ⚑ pair-review flag**, saying in one line why the effect may not be worth a slot: it
  only costs you (a hazard filed as a skill), it needs a second grid, it does not say what it does,
  it depends on another question entering, or it overlaps one of your own answers. The flag is
  advice; the answer is yours.
- **Your rulings this round:** fame is not spendable, so an option that bought something with fame
  now skips a reward instead (fame can still be lost as a penalty); and a property's level 2 is
  unlocked by its own match only, unless an effect says otherwise.
- **Family AB is new — 19 live effects written around the mark-hitting loop itself** (two more were
  retired at birth as twins of family Y): streaks and relays of hits, cards built to be realised,
  plans that answer back, and called and bounced hits.
- **Family AC is new — the level 2 of each effect you had already ruled on**, one question each, so
  no recorded answer changed meaning. Its (d) is not a reject: it keeps the effect with no level 2.
  Its heading says which answered effects are not asked, and why.

**Reading the older effects.** They were mined against a board that is gone and re-expressed on this
one; the rows use this vocabulary:

| was | is now |
|---|---|
| a trigger "each act" | **each placement** |
| a budget "once per act" | **once per Entrance refill** (five cards; four to eight a show) |
| a round / a blind / an ante | a **show** / a **level** / a **lap** |
| a discard budget | **discard events**: effects discard cards from the board into a pile that persists |
| the tableau, the upper/lower zone | the **grid**, the **Entrance** |

Families Y (the board plan's marks), Z (solitaires re-expressed on the grid) and AA (Balatro content
mods and four solitaire-likes) were new in round 1; `build/SOURCES.md` says what each source yielded,
and `build/_verdicts.tsv` holds the round-1 architecture review, one verdict per question.

---

## 0. How to review this document

**Every question is one effect.** The three lettered options are three versions of the *same*
effect — sometimes three strengths, sometimes three mechanisms, sometimes three scopes,
whichever fork was worth putting to you for that particular idea. Pick the one you want.

- **(a) (b) (c)** — the three versions. Pick one and that version enters the CSV as approved.
- **(d) reject** — the effect does not enter the game in any form.
- **Write your own** — the free-text box is on every question, always. If none of the three is
  right, type the version you want; your words go into the CSV verbatim as the approved effect,
  not a paraphrase of them.

**One option is always marked as the recommendation, and it is never (d).** Enter presses whatever
is marked, so holding Enter approves rather than rejects. The mark moves to *use what I wrote* the
moment you type, so Enter can never discard what you wrote. Accepting the recommendation without
moving the mark is recorded as its own state — being shown what Enter does is not the same as
choosing it.

**Answers are revisitable.** Go back to any earlier question and change it; nothing is lost.

### What each question header tells you

```
**Name** — slot, class code, provenance. One line saying what the effect is.
```

- **slot** — where the effect lives on a card: `suit`, `rank`, `type`, `stamp`, `skill`,
  `consumable`, or `status` — or one of two things that are not a card: `hazard`, a level
  modifier (boss, town, difficulty), and `structure`, a run-shaped idea (map, deck preset, quest,
  minigame, meta-progression) kept so you can rule on it. There is no `rule` slot: the rules deck
  is a deck, not an effect, so a "changes a default" idea is asked as a skill. There is no
  currency and no shop, so shop and gold questions are retired in place.
- **class code** — its cell in the design-space taxonomy (`C4`, `H6`, `P3`…). Two effects sharing
  a class code are competing for the same design space, which is why they are next to each other.
- **provenance** — the document or wiki it was mined from, or `generated` if it was written to
  fill a class the corpus left empty.
- **Level 2, on its own mark** — what the effect adds while its card sits on a mark it matches on
  its own property. Choosing an option approves both levels; to change only the level 2, write your
  own.
- **⚑ pair review** — a one-line reason the effect may not earn a slot.

### The order

Grouped by family, then by class within the family. **An upgrade sits directly after the effect
it upgrades** — 11 questions are positioned that way, so when you see a stronger or less
restricted version of the question you just answered, you are being asked to price the pair.

---

## 1. What was mined, and what happened to it

**2,234 candidate effects** were extracted from every text document in the repo and from the
Balatro and Cryptid reference wikis:

| Source | Extracted |
|---|---|
| `CARD_CATALOG.csv` | 378 |
| `DESIGN_DOC.md`, `DESIGN_RECOMMENDATIONS.md`, `DESIGN_REFERENCES.md` | 758 |
| the braindump, the random-effects sheet, the curated pre-grid sheet, `todo.md`, `pokerpatience.txt` | 459 |
| balatrowiki.org — jokers, modifiers, stakes, blinds, tags, challenges | 249 |
| Cryptid and Pokermon mod wikis | 390 |

148 were folded as exact restatements, leaving 2,086 to judge. **1,160 were dropped:**

| Reason | Dropped |
|---|---|
| `DUPLICATE` — the same design space as an effect already asked about | 747 |
| `NO_MECHANIC` — art direction, naming, engineering, or a taxonomy heading | 130 |
| `RESKIN` — a numeric or suit reskin of a more general effect | 119 |
| `ALREADY_A_RULE` — restates a rule the game already has | 113 |
| `NOT_APPLICABLE` — needs a held hand, discards per round, or blinds | 51 |

**926 survived and were rewritten as grid-native mechanics** — foreign vocabulary translated, and
reach expressed in this game's four-dimensional coordinate wherever the effect could carry it.
**131 more were written from scratch**: 69 to fill taxonomy classes the corpus left empty, 62
for eighteen classes the taxonomy itself had failed to name — progress-relative scoring, placement
order, deck-composition reads, slot topology, in-run quests, and the whole of family X below.

**One hundred and eight more were mined from external games** whose designs cover ground Balatro and
Cryptid structurally cannot: Santorini (a 5×5 grid you build height on, whose god powers are
explicit rule-breakers), the Zachtronics Solitaire Collection and Hempuli's *A Solitaire Mystery*
(both cited in your own braindump), Concrete Jungle, Luck be a Landlord, Backpack Battles,
Ballionaire and the tile-placement board games; then Open-Face Chinese Poker and the poker variant
family, Teamfight Tactics, Super Auto Pets, the solitaire-variant literature, mahjong hand
catalogues, incremental games, Blue Prince, Inscryption, Loop Hero, Monster Train, Baba Is You,
Photosynthesis, 2048 and the match-3 line. Neither reference wiki has a board, so the grid, height,
class-synergy and prop families got almost nothing from them; these do. **Every source considered,
mined or deliberately skipped, is registered in `build/SOURCES.md`.**

**Thirty-three more were mined from Solitaire Network** (solitairenetwork.com), whose eighty-two
solitaires were read one rules page at a time. Most of what a classic solitaire does — foundations,
free cells, redeals, pair removal — the corpus already held from the solitaire literature and the
two solitaire collections above; what survived is the mechanics none of those carried: the Yukon
move, the supermove bound, the Osmosis row rule, the Cruel unshuffled redeal, the sandwich of Royal
Marriage, the sliding rows of Slide and Poker Slide, the shrinking rows of Germaine and Air Lock,
Bowling's monotone frame and strike, Cribbage Square's shared starter, and the clock-face targets of
Grandfather's Clock. They are family Z, at the end of the document.

**Ten more were recovered by re-reading the braindump by hand.** The mining pass skipped that
file's art-direction and circus-history sections wholesale, and mechanics had been written
parenthetically inside them. Those ten carry their braindump line number in the question text.

**Every source was then line-audited.** `DESIGN_REFERENCES.md` was checked row by row against its
own hook tags — 50 rows propose only a name or a visual and are correctly absent; of the 391 that
propose a mechanic, all but two were already present. the curated pre-grid sheet is complete at
25 of 25. The random-effects sheet, `DESIGN_DOC.md` and `DESIGN_RECOMMENDATIONS.md` came back
clean. `todo.md` and `pokerpatience.txt` are engineering and layout backlog and were correctly
skipped wholesale.

Every drop is recorded with its reason and, for duplicates, the id of the effect it was folded
into — so any category can be resurfaced if you disagree with a call.

## 2. The design space this covers

The taxonomy behind the class codes is **24 families, 226 classes**, crossed with six structural
axes (slot, trigger, scope, duration, valence, agency). **216 of the 226 classes are represented
here.** The 10 that are not are exactly family N — view, camera and UI — **excluded by your
ruling**; the taxonomy still carries them so the hole stays visible.

The taxonomy was audited once the corpus pass was finished, and it had a bias worth naming: built
from the engine's hook surface and from Balatro, it described **effects that fire and add**, and
had almost no vocabulary for effects that *read state* or that key off *absence*. Eighteen classes
were added to correct it, including a new **family X — absence, failure and the unplayed**, which is
the mirror of every other family in the document.

---

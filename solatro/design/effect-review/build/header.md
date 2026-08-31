# Effect review — every candidate effect, three variants each

**This is not a feature design.** It is a content-selection round. Every question is one
candidate effect, and every answer is a ruling on whether that effect enters the game and in
which form. Nothing here specifies how anything is built.

**1,177 questions.** There is no branching: every question is independent, so the count you see is
the count you answer. Rejecting is one keystroke.

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
  `consumable`, `rule`, or `status`. Every effect here fits one of them; that was the filter for
  getting in at all.
- **class code** — its cell in the design-space taxonomy (`C4`, `H6`, `P3`…). Two effects sharing
  a class code are competing for the same design space, which is why they are next to each other.
- **provenance** — the document or wiki it was mined from, or `generated` if it was written to
  fill a class the corpus left empty.

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

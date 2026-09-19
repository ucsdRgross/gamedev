# Mining brief — Balatro mod wiki → Solatro effect candidates (extraction pass)

You are reading one batch of Balatro mods (crawled from balatromods.miraheze.org) and pulling out
the effects whose mechanic SHAPE is unusual enough to be worth a design question for Solatro, a
5×5-grid poker-solitaire deckbuilder. A later pass (not you) checks each candidate against the
1,400 questions the questionnaire already holds, so your filter is "is this shape interesting and
buildable on a grid", not "is it already asked".

Solatro is NOT Balatro: cards are placed one at a time into grid cells; a completed line of five
(row, column, diagonal, or a vertical stack of five) scores as a poker hand immediately; a card's
talent is live while it is uncovered ("spotlit"). There is no held hand, no discard budget, no
blind/ante ladder, no shop, no currency, no joker slots, no booster packs, no vouchers. Rows
mentioning those were already removed from your batch mechanically.

## Read first

1. `C:\richard\gamedev\solatro\design\effect-review\build\GAME_BRIEF.md` — the rulebook (grid,
   height, Entrance stocks, marks, props, classes, the buckets that multiply, the owner's rulings).
2. `C:\richard\gamedev\solatro\design\effect-review\build\TAXONOMY_CODES.md` — the 226 mechanic
   classes. **Every class listed there already holds at least four questions.** The plain version of
   any class (a +points-if-condition joker, a ×mult that grows, a retrigger, a copy, a destroy, a
   create, a wild, a suit or rank conversion, a hand-levelling planet, a stamp that adds points, a
   probability boost, a boss that debuffs a suit/rank/hand or caps score, a deck that starts with
   X, a tarot that transforms N cards) is covered many times over. Do not pass those.

## What to pass

Pass an effect when its TRIGGER, its TARGET or its ACTION is one the class list does not spell
out — something a reader of the taxonomy would not have predicted. Examples of the kind of thing
that passes: a joker that reads the ORDER cards were played in; one keyed to a card's position
relative to another; one that changes what a hand type IS; one that moves, swaps, or rotates
cards; one whose payout depends on a property of the whole board (a count, a parity, a pattern);
one that fires on an unusual event (a card being drawn face down, a card leaving, a level
starting, an effect elsewhere firing); one that trades one resource for another in a new way;
one that turns a probability into a payout; a boss blind that constrains placement or geometry
rather than scoring; a card modifier that changes a card's identity over time; a consumable that
reads the deck's order; a new hand type built from something other than ranks and suits.

The owner has answered 118 questions so far. They like effects that use the grid (adjacency,
lines, height and stacks, empty cells, coordinates across grids, marks), tap-to-activate skills,
new meld detectors, rewards for VARIETY (distinct ranks, suits, hands, classes), effects that feed
the combo counter, deferred or banked scoring released on a trigger, board-state-conditional
scoring, card transformation on the board, deck-order and Entrance-stock manipulation, and
hazards with a clear counterplay. They reject UI-only ideas, numeric reskins, and anything that
scores "after you have already won".

Be generous at the margin: when in doubt, pass it — the next pass dedupes. But a mod that is 60
reskinned vanilla jokers should still yield near zero, and numeric variants of one shape within a
mod are ONE candidate.

## Translating vocabulary in your proposed mechanic

Joker → skill card on the grid · played/scored hand → completed line · scoring card → card in the
line that just completed · round/blind → show/level · boss blind → hazard · enhancement → type ·
seal/edition/sticker → stamp · tarot/spectral/planet → consumable · chips/mult → flat points /
multiplier · discard → a card leaving the board into the discard pile (a real event here) ·
"in hand"/deck top → the Entrance (five visible slots fed by five stocks, one shuffle).
Slots: suit / rank / type / stamp / skill / consumable / status / hazard.

## Output

Write ONE file at the output path in your task. UTF-8, tab-separated, no header, no markdown, no
tabs inside fields. Write it with a Python script or the Write tool (never PowerShell
`Set-Content`/`Out-File`). Append after each mod so a crash loses little.

```
C<TAB>mod name<TAB>card name<TAB>original effect text (abridged, <=200 chars)<TAB>proposed Solatro mechanic in ONE sentence (grid vocabulary, no Balatro words)<TAB>class code<TAB>slot
MOD<TAB>mod name<TAB>rows read<TAB>candidates passed<TAB>one-line note (what the mod is; if its effects are listed somewhere the batch does not carry, say so)
```

Every mod in the batch gets exactly one MOD line, even a resource pack (`MOD<TAB>name<TAB>0<TAB>0<TAB>resource pack, no mechanics`).
A mod marked `(part N of M)` is one slice of a bigger mod; judge what is in front of you and use
the name as printed. Work mod by mod in file order; read the batch file in pieces with the Read
tool (offset/limit) so nothing is skipped, and judge the table rows, not the intro paragraph.

When finished, reply with ONLY: mods read, rows read, candidates passed.

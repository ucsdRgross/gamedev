# -*- coding: utf-8 -*-
"""Questions whose whole premise is architecture that no longer exists.

⚠ RETIRED IN PLACE, NEVER DELETED. The question id is POSITIONAL (`render.py` numbers by
walking the sorted rows), so removing a row would renumber every question after it and
repoint every recorded answer at a different effect. A retired row still renders — as an
italic one-liner with no options — so the id it holds stays nailed down.

These are not effects the owner rejected. They are effects whose referent went away: the
three-act show, the Submit button, the upper/lower tableau. Asking about them spends a
review slot on a mechanic that cannot be built.
"""

RETIRED = {
    # --- the 1-of-3 act structure -------------------------------------------------------
    "E0047": "Retired with the act structure: there is no final act. A show runs until the "
             "player presses End, so an effect keyed to a known-in-advance last scoring pass "
             "has no referent.",
    "E0050": "Retired with the act structure: there is no first act, only a first placement, "
             "which every effect can already name.",
    "E0149": "Retired with the act structure: there is no second act.",
    "E0552": "Retired with the act structure: a card type keyed to being played in a "
             "particular act has nothing to key on.",
    "E0692": "Retired with the act structure: a per-act rising multiplier needs acts to rise "
             "across. The combo multiplier already rises across a whole show.",
    "E1228": "Retired with the act structure: a final-act multiplier has no final act.",
    "E1229": "Retired with the act structure: a card type that appears only in the final act.",
    "E1234": "Retired with the act structure: a card type that appears only in the first act.",
    "E1432": "Retired with the act structure: a card type that appears only in the second act.",
    "E1356": "Retired with the act structure: a per-act injury roll.",
    "E1212": "Retired with the act structure: an Entrance step BETWEEN acts. The Entrance now "
             "refills on its own condition, which the Entrance design owns.",
    "E0380": "Retired with the act structure: 'a match is 3 submits'. A show has no act count.",
    "E1073": "Retired with the act structure: mapping 3 submits onto 3 performance acts.",

    # --- the Submit button ----------------------------------------------------------------
    "E1062": "Retired with Submit: scoring is continuous now. Every completed line scores the "
             "instant a placement completes it, so there is no whole-board scoring moment to "
             "redesign.",
    "E1342": "Retired with Submit: 'there is no submit slot, the whole board scores' is now "
             "simply true, so it is a description of the game rather than a proposal.",
    "E1430": "Retired with Submit: there is no submit at which to score the Entrance's cards.",
    "E1459": "Retired with Submit: nothing clears and cascades the board at a Submit.",
    "E1418": "Retired with Submit: the rules deck no longer defines a submit behaviour, and "
             "what it does define is the line detector, which is a separate question.",
    "E1197": "Retired with Submit: 'draw through the deck, then submit' is the retired loop. "
             "The live loop is draw to the Entrance, place, score on completion.",
    "G0388": "Retired with Submit: an effect that changes what Submit means has no button to "
             "change.",

    # --- the upper/lower tableau ----------------------------------------------------------
    "E1136": "Retired with the tableau: Canfield-style stacking rules described the pre-grid "
             "board. Stack legality on the grid is the poker-patience design's own question.",

    "G0227": 'Superseded by the board plan (design/board-plan): every cell assigned a card at show start, and a card matching its cell scores extra, IS the plan.',  # Q0170

    "G0195": 'Superseded by the board plan (design/board-plan): a cell whose printed requirement only a matching card satisfies is a mark; the refuse-a-mismatch form is asked as family Y13 (Dress Code, as a mark).',  # Q0171

    "E1208": 'Superseded by the board plan (design/board-plan): a cell that raises the rank of what lands on it is asked as family Y13 (The Ranked Floor, as a mark).',  # Q0165

    "G0366": 'Duplicate of the Short Ring (sub-length diagonals score as lines). Asked there.',  # Q0159

    "G0369": 'Duplicate of Rows spanning multiple grids (a row running across grids at the same y). Asked there.',  # Q0186

    "E0894": 'Duplicate of The Awkward Shape (a card occupying several cells). Asked there.',  # Q0208

    "G0142": 'Duplicate of the Entrance itself: a strip of cells above the grid is what the Entrance already is.',  # Q0181

    "E0655": 'A map idea (DESIGN_DOC Map v1, Minesweeper) that replaces the grid and Entrance outright. Its board form is asked as Minesweeper bomb-prefilled grid, and its hidden-board form as family Y11.',  # Q0173

    "G0378": 'Duplicate of Deja Vu card (a card remembering its cell and returning when it is empty). Asked there.',  # Q0372

    "E1886": "Retired with the held hand: selecting any number of cards to score together is Balatro's hand-play, which this game does not have. Its long-line form is asked as The Six-Card Line and Rows spanning multiple grids.",  # Q0149

    "G0165": 'Duplicate of Cribbage phase-1 stack-to-31 (a running total across placements scoring at named totals). Asked there.',  # Q0105

    "G0289": 'Duplicate of Rehearsal Hall (two, four and six cards of one class unlock escalating tiers). Asked there.',  # Q0997

    "E0684": 'Contradicts a standing owner ruling: overscore is retired, because punishing overperformance breeds sandbagging. If in-run responsiveness is wanted, scale REWARDS, never goals (ARCHITECTURE_REVIEW 3b).',  # Q1107

    "G0173": 'Duplicate of Maximized (every card counts as one of only two ranks). Asked there.',  # Q1342

    "M0020": "Duplicate of The Quoted Fee (the show's goal set from what the plan would score). A goal is set by the level, so the question is asked there.",  # Q1426

    "E0757": 'Retired by owner ruling: the rules deck is a deck, not an effect, so a question about adding, editing, moving or reading rule cards has no effect to rule on.',  # Q0137

    "E1584": 'Retired: there is no currency and no shop. Premise is cards arriving rented from a shop, paid in gold every show and bought out for a lump sum; a run-external shop/economy structure the game has no currency for.',  # Q0672

    "G0214": 'Retired: there is no currency and no shop. Premise is banked currency earning interest, requiring a persistent held/spendable currency distinct from score; points bank instantly and are not held as wealth.',  # Q0679

    "G0333": 'Retired: there is no currency and no shop. Whole premise is a shop resale mechanism, cards reappearing in a later shop at a price; a run-external shop structure, not a card talent.',  # Q0691

    "E0432": 'Retired: there is no currency and no shop. Whole premise is how shop prices are paid; the shop is a run-external structure where no card is on the grid or spotlit.',  # Q0694

    "E0434": "Retired: there is no currency and no shop. Whole premise is the run's overall currency system (cards replacing gold); a global economic structure, not a talent any one card performs.",  # Q0695

    "E1654": 'Retired: there is no currency and no shop. Mechanic requires capping points against a second currency (gold, then fame); collapses to nonsense if gold becomes points, and the game has no second currency to compare against.',  # Q0704

    "E1601": 'Retired: there is no currency and no shop. Whole premise is shop price escalation from purchases; a run-external shop structure, not something a spotlit card does.',  # Q0710

    "E0524": 'Retired: there is no currency and no shop. Whole premise is the cost of rerolling shop offers; the shop is a run-external structure outside any show, where no card is spotlit.',  # Q0726

    "E1838": 'Retired: there is no currency and no shop. Whole premise is shop stock visibility and pricing; the shop is a run-external structure, not a card talent.',  # Q0853

    "E0410": 'Retired by owner ruling: the rules deck is a deck, not an effect, so a question about adding, editing, moving or reading rule cards has no effect to rule on.',  # Q0889

    "E0489": 'Retired by owner ruling: the rules deck is a deck, not an effect, so a question about adding, editing, moving or reading rule cards has no effect to rule on.',  # Q0890

    "E0704": 'Retired by owner ruling: the rules deck is a deck, not an effect, so a question about adding, editing, moving or reading rule cards has no effect to rule on.',  # Q0891

    "G0245": 'Retired by owner ruling: the rules deck is a deck, not an effect, so a question about adding, editing, moving or reading rule cards has no effect to rule on.',  # Q0892

    "E0503": "Retired: there is no currency and no shop. Doubles run-structure parameters (the show goal, shop packs, starting slots) alongside cards, which a single card's talent cannot carry.",  # Q0909

    "E0681": 'Retired: there is no currency and no shop. Premise is shop pricing and town access rules plus a fixed six-class deck preset -- economy and run-structure, not a card talent.',  # Q0917

    "E0742": 'Retired by owner ruling: the rules deck is a deck, not an effect, so a question about adding, editing, moving or reading rule cards has no effect to rule on.',  # Q0919

    "E0421": 'Retired: there is no currency and no shop. Premise is turning shop UI controls into cards, a shop/economy and interface concern, not a board talent.',  # Q0924

    "G0166": 'Retired by owner ruling: the rules deck is a deck, not an effect, so a question about adding, editing, moving or reading rule cards has no effect to rule on.',  # Q0928

    "E0101": 'Retired by owner ruling: the rules deck is a deck, not an effect, so a question about adding, editing, moving or reading rule cards has no effect to rule on.',  # Q0929

    "E0740": 'Retired by owner ruling: the rules deck is a deck, not an effect, so a question about adding, editing, moving or reading rule cards has no effect to rule on.',  # Q0930

    "G0032": 'Retired by owner ruling: the rules deck is a deck, not an effect, so a question about adding, editing, moving or reading rule cards has no effect to rule on.',  # Q0933

    "G0459": 'Retired by owner ruling: the rules deck is a deck, not an effect, so a question about adding, editing, moving or reading rule cards has no effect to rule on.',  # Q0934

    "G0036": 'Retired by owner ruling: the rules deck is a deck, not an effect, so a question about adding, editing, moving or reading rule cards has no effect to rule on.',  # Q0937

    "G0034": 'Retired by owner ruling: the rules deck is a deck, not an effect, so a question about adding, editing, moving or reading rule cards has no effect to rule on.',  # Q0939


    "G0209": "Raises the next show's goal for scoring well, directly against the standing overscore ruling, and is a run-structure goal mechanism besides.",  # Q1112

    "E1024": "Retired: there is no currency and no shop. Premise is a rival's gold-draining offer affecting future rival shows -- economy and run-structure.",  # Q1129

    "E0956": 'Retired: there is no currency and no shop. Premise is bidding gold for map-node picks -- economy and map structure.',  # Q1145


    "E1752": 'Retired: there is no currency and no shop. Premise is shop appearance odds and slot counts -- shop/economy.',  # Q1173

    "E0408": 'Retired: there is no currency and no shop. Premise is a map pack node and its pick rules -- map/shop structure.',  # Q1174



    "E1312": 'Retired: there is no currency and no shop. Premise is a map offer of a single high-rarity card -- map/shop structure.',  # Q1180

    "E1992": 'Retired: there is no currency and no shop. Premise is buying shop upgrades and their tiers -- shop/economy.',  # Q1182

    "E1668": 'Retired: there is no currency and no shop. Premise is card duplicate availability in shops and packs -- shop structure.',  # Q1183

    "E0772": 'Retired: there is no currency and no shop. Premise is which suits are obtainable only from shop packs -- shop structure.',  # Q1184

    "E0787": "Retired: there is no currency and no shop. Premise is tips raising the next map node's offer rarity -- economy/map structure.",  # Q1185

    "E0796": 'Retired: there is no currency and no shop. Premise is how shop packs are opened and rerolled -- shop structure.',  # Q1186

    "E0811": 'Retired: there is no currency and no shop. Premise is a between-towns hiring pool of discounted cards -- shop/town structure.',  # Q1188


    "E0895": 'Retired: there is no currency and no shop. Premise is trading cards with a town -- town/economy structure.',  # Q1192

    "E0947": 'Retired: there is no currency and no shop. Premise is buying a cheap fake card from a shop -- shop/economy.',  # Q1193

    "E1484": 'Retired by owner ruling: the rules deck is a deck, not an effect, so a question about adding, editing, moving or reading rule cards has no effect to rule on.',  # Q1196

    "E1486": 'Retired: there is no currency and no shop. Premise is shop pack result odds -- shop structure.',  # Q1197


    "E0598": 'Retired: there is no currency and no shop. Premise is run-behaviour-triggered strike/tax events, including deck-cutting and a tax economy -- run structure.',  # Q1202

    "E0818": 'Retired: there is no currency and no shop. Premise is a one-time fame gain costing all held gold -- meta currency/economy.',  # Q1206

    "G0334": 'Retired by owner ruling: the rules deck is a deck, not an effect, so a question about adding, editing, moving or reading rule cards has no effect to rule on.',  # Q1236

    "G0353": "Retired: there is no currency and no shop. Premise is shop and pack offer weighting based on last show's play -- shop/economy structure.",  # Q1245

    "E0438": 'Retired: there is no currency and no shop. Premise is a prestige-spending meta-shop -- meta currency and shop structure.',  # Q1247

    "G0449": 'Retired: there is no currency and no shop. Premise is a second currency spendable only between runs -- meta currency.',  # Q1252

    "E0393": 'Retired by owner ruling: the rules deck is a deck, not an effect, so a question about adding, editing, moving or reading rule cards has no effect to rule on.',  # Q1255

    "E1514": 'Retired: there is no currency and no shop. Premise is a difficulty-stake mode making shop cards unsellable -- run-mode selection and shop/economy.',  # Q1256

    "E0982": 'Retired by owner ruling: the rules deck is a deck, not an effect, so a question about adding, editing, moving or reading rule cards has no effect to rule on.',  # Q1269

    "G0018": 'Duplicate of Q0421 (The Death Rattle): the same trigger, target and action; the owner rules on it there.',  # Q0633

    "G0170": 'Duplicate of Q0490 (Sawing in Half): the same trigger, target and action; the owner rules on it there.',  # Q0491

    "E0760": 'Duplicate of Q0588 (The Charge Bank): the same trigger, target and action; the owner rules on it there.',  # Q0592

    "G0430": 'Duplicate of Q1058 (The Orphaned Prop): the same trigger, target and action; the owner rules on it there.',  # Q1076

    "G0477": 'Duplicate of Q0999 (One Ring at a Time): the same trigger, target and action; the owner rules on it there.',  # Q1002

    "G0423": 'Duplicate of Q1053 (Curtain Call): the same trigger, target and action; the owner rules on it there.',  # Q1059

    "G0397": 'Duplicate of Q1380 (The Bench): the same trigger, target and action; the owner rules on it there.',  # Q1381

    "G0400": 'Duplicate of Q1380 (The Bench): the same trigger, target and action; the owner rules on it there.',  # Q1385

    "E1063": 'Duplicate of Q1364 (The Wildcard): the same trigger, target and action; the owner rules on it there.',  # Q1365

    "E0822": 'Duplicate of Q1264 (Seasonal crown): the same trigger, target and action; the owner rules on it there.',  # Q1265

    "G0114": 'Duplicate of Q1324 (The Conflicting Notes): the same trigger, target and action; the owner rules on it there.',  # Q1325
}

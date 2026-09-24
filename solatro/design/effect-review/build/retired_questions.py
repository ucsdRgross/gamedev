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

    "E0254": 'Retired: already a rule. Straights already wrap through the Ace, so (a) restates the game, and its every-rank-shifts variant (c) is Q0110 (Shortcut), which the owner ruled on.',  # Q0122

    "G0207": 'Duplicate of Q0123 (Canasta rank-based wildcards): one named rank is wild in every meld; the owner rules on it there.',  # Q0125

    "E0678": "Duplicate of Q0114 (The Blacklisted Hand): a line already scores exactly one hand, and repeats scoring less is the owner's own wording there.",  # Q0133

    "E0205": 'Duplicate of Q0132 (Lowball): each line scores its worst hand; straights already read regardless of order; the owner rules on it there.',  # Q0135

    "E0352": "Merged into Q0138 (Sword Swallower): four columns of perfect descents is that effect's level 2; the owner rules on it there.",  # Q0141

    "E0361": "Duplicate of Q0136 (Dead Man's Hand): a jackpot for one specific rank combination, reseeded per run; the owner rules on it there.",  # Q0142

    "G0230": 'Duplicate of Q0144 (The Episode Rules): name hand types that score double for the run; the owner rules on it there.',  # Q0145

    "G0001": "Duplicate of Q0155 (The Short Ring): diagonals already score, so (a) restates the game and (c) is Q0155's short diagonals; the owner rules on it there.",  # Q0154

    "G0186": "Merged into Q0229 (The Long Reach): the whole grid counting as adjacent is that effect's level 2; the owner rules on it there.",  # Q0231

    "E0122": 'Retired: OG Placer is a shipped rule card, and the rules deck is a deck, not an effect. Its (a) is the default placement rule the game already plays.',  # Q0239

    "E0121": 'Retired: OG Grabber is a shipped rule card, and the rules deck is a deck, not an effect. Its (a) is the default grab rule the game already plays.',  # Q0244

    "G0263": 'Duplicate of Q0252 (The Backlift): an extra step for each card stacked above it; the owner rules on it there.',  # Q0259

    "E0107": 'Duplicate of Q0284 (Hungry Hippo): eats the cards placed on it for their rank; the owner rules on it there.',  # Q0285

    "E0151": "Merged into Q0282 (Edith's Bayonet): consuming any card, not only its own suit, is that effect's level 2; the owner rules on it there.",  # Q0286

    "E0075": "Merged into Q0309 (The Leotard): moving any card anywhere is that effect's level 2; the owner rules on it there.",  # Q0318

    "E1151": 'Duplicate of Q0314 (Walking Through the Wall): stepping over an occupied cell into the one beyond, chaining as its level 2; the owner rules on it there.',  # Q0336

    "E0306": "Merged into Q0345 (The Rook) and Q0339 (The Bishop): each takes the other's lines as its level 2, which is the queen; the owner rules on it there.",  # Q0346

    "G0374": 'Duplicate of Q0347 (Cards bounce/swap between grids): swapping a card with the same cell in another grid; the owner rules on it there.',  # Q0350

    "E2041": 'Retired: already a rule. Placed cards are already immovable, so (a) restates the game; (c) loosens it and (b) needs a drawback pack that does not exist.',  # Q0355

    "G0237": 'Duplicate of Q0358 (Boss: adjacency-only placement): cards may only go next to cards already down, which is a hazard; the owner rules on it there.',  # Q0364

    "E0841": 'Duplicate of Q0357 (The Light and Heavy Chest): light when you move it, immovable to effects; the owner rules on it there.',  # Q0381

    "G0280": "Merged into Q0419 (The Voice From The Wings): working from the discard is that effect's level 2; the owner rules on it there.",  # Q0422

    "G0386": 'Duplicate of Q0424 (Blue Joker): paid by the cards still in the deck; the owner rules on it there.',  # Q0425

    "E0793": 'Duplicate of Q0459 (The Kite): send a card out of play and it returns stronger for the time away; the owner rules on it there.',  # Q0457

    "E0310": 'Duplicate of Q0454 (Milk Can): put grid cards out of play and bring them back later; the owner rules on it there.',  # Q0460

    "E0091": "Merged into Q0472 (Slapstick): a free swap of any two adjacent ranks once per turn is that effect's level 2; the owner rules on it there.",  # Q0473

    "E1846": "Retired: there is no currency and no shop. Its premise is randomising a shop's values.",  # Q0479

    "G0169": 'Duplicate of Q0294 (The Merge): two equal ranks side by side become one card of the next rank up; the owner rules on it there.',  # Q0487

    "E1940": 'Retired: there is no currency and no shop. Its premise is recovering sold cards; recovering destroyed ones is Q0511 (The Hologram Tour).',  # Q0508

    "E0066": 'Retired: there is no currency and no shop. A money token whose value is trade at a shop.',  # Q0518

    "E0362": 'Retired: there is no currency and no shop. A token whose value is double trade at a shop.',  # Q0525

    "E0173": 'Retired by owner ruling: the rules deck is a deck, not an effect, so a question about adding, editing, moving or reading rule cards has no effect to rule on. A boss disabling your rule cards is a rules-deck mechanism.',  # Q0543

    "E0214": "Merged into Q0565 (Amber Acorn): choosing the resolution order yourself is that effect's level 2; the owner rules on it there.",  # Q0569

    "E0057": 'Retired by owner ruling: the rules deck is a deck, not an effect, so a question about adding, editing, moving or reading rule cards has no effect to rule on.',  # Q0573

    "E0172": 'Retired by owner ruling: the rules deck is a deck, not an effect, so a question about adding, editing, moving or reading rule cards has no effect to rule on.',  # Q0574

    "E0279": 'Retired by owner ruling: the rules deck is a deck, not an effect, so a question about adding, editing, moving or reading rule cards has no effect to rule on.',  # Q0577

    "E0331": 'Retired by owner ruling: the rules deck is a deck, not an effect, so a question about adding, editing, moving or reading rule cards has no effect to rule on.',  # Q0578

    "G0089": 'Retired by owner ruling: the rules deck is a deck, not an effect, so a question about adding, editing, moving or reading rule cards has no effect to rule on.',  # Q0583

    "G0016": 'Duplicate of Q0631 (The Exhausted Card): fires once at several times strength, then is gone for the show or the run; the owner rules on it there.',  # Q0632

    "G0020": "Merged into Q0636 (The Running Gag): a counter surviving the end of the run is that effect's level 2; the owner rules on it there.",  # Q0639

    "G0473": 'Duplicate of Q0636 (The Running Gag), whose level 2 keeps a counter across runs; the owner rules on it there.',  # Q0640

    "E0487": 'Retired: already a rule. Statuses exist (Burning, Juggling, Exhausted); this describes how they are stored, not an effect.',  # Q0646

    "E0104": "Merged into Q0658 (Iron Body): the first hit prevented, paid out as tokens, is that effect's level 2; the owner rules on it there.",  # Q0659

    "E1971": 'Duplicate of Q0663 (The Cleansing Pass): a consumable that strips statuses from your cards; the owner rules on it there.',  # Q0661

    "E1784": 'Retired: there is no currency and no shop. Retriggers pay gold.',  # Q0667

    "E1545": 'Retired: there is no currency and no shop. It earns gold.',  # Q0668

    "E1862": 'Retired: there is no currency and no shop. It earns gold.',  # Q0669

    "E0065": 'Retired: there is no currency and no shop. A suit whose cards are currency at a shop.',  # Q0670

    "E0657": 'Retired: there is no currency and no shop. It steals gold from the town.',  # Q0671

    "E2006": 'Retired: there is no currency and no shop. A difficulty that takes gold.',  # Q0674

    "E0330": 'Retired: there is no currency and no shop. It pays gold tokens for a cut of payouts.',  # Q0675

    "E1803": 'Retired: there is no currency and no shop. Interest on gold.',  # Q0677

    "E1563": 'Retired: there is no currency and no shop. It doubles gold.',  # Q0678

    "E1657": 'Retired: there is no currency and no shop. It earns gold.',  # Q0680

    "E1564": 'Retired: there is no currency and no shop. Its value is a sale price.',  # Q0683

    "E1578": 'Retired: there is no currency and no shop. Its value is sale prices.',  # Q0685

    "E0839": 'Retired: there is no currency and no shop. A map node that sells for gold.',  # Q0686

    "E0988": 'Retired: there is no currency and no shop. It pays when sold.',  # Q0688

    "E1509": 'Retired: there is no currency and no shop. Free shop items.',  # Q0689

    "G0332": "Retired: there is no currency and no shop. It sets a shop's stock.",  # Q0692

    "E0426": 'Retired: there is no currency and no shop. An economy paid in gold.',  # Q0693

    "E0586": 'Retired: there is no currency and no shop. A second currency.',  # Q0697

    "E0650": 'Retired: there is no currency and no shop. It earns the second currency, heat.',  # Q0698

    "E1550": 'Retired: there is no currency and no shop. Debt against gold.',  # Q0701

    "E1813": 'Retired: there is no currency and no shop. Debt against gold.',  # Q0702

    "E2043": 'Retired: there is no currency and no shop. A goal set by gold held.',  # Q0707

    "E1703": 'Retired: there is no currency and no shop. It takes gold.',  # Q0709

    "E1998": 'Retired: there is no currency and no shop. It sets sale prices.',  # Q0711

    "G0354": 'Retired: there is no currency and no shop. Haggling in a shop.',  # Q0712

    "G0355": 'Retired: there is no currency and no shop. It sets shop prices.',  # Q0713

    "E1839": 'Duplicate of Q0420 (The Comedic Drop): give this card up mid-show for points now; its fraction-of-the-goal variant is the same trade; the owner rules on it there.',  # Q0684

    "E0643": 'Duplicate of Q0766 (The Ground Rent): a card spent as a resource instead of scored, paying for cued effects; the owner rules on it there.',  # Q0696

    "E1554": 'Retired: there is no currency and no shop. It earns gold.',  # Q0716

    "E0060": 'Retired: already a rule. Undo is a button with a capped history (Game.undo_cap) that rewinds the board with the deck order unchanged. One free undo per turn is what the button already gives.',  # Q0721

    "E0231": 'Retired: already a rule. Undo is a button with a capped history (Game.undo_cap) that rewinds the board with the deck order unchanged. More free undos is what the button already gives; debuffs rewind with it.',  # Q0722

    "G0132": 'Retired: already a rule. Undo is a button with a capped history (Game.undo_cap) that rewinds the board with the deck order unchanged. Undos do not accrue, so there is nothing to account for.',  # Q0724

    "E1570": 'Retired: there is no currency and no shop. It grows on shop rerolls.',  # Q0727

    "G0316": 'Duplicate of Q0413 (Lucky Streak): a random outcome rolled twice and the better kept; the owner rules on it there.',  # Q0728

    "E0004": "Duplicate of Q0059, which the owner wrote: a patience total that runs down and ends the show; the owner's version stands.",  # Q0734

    "G0363": "Duplicate of Q0059, which the owner wrote: patience drops per Entrance refill and a scored meld restores it; the owner's version stands.",  # Q0737

    "G0148": "Merged into Q0253 (The Forge): placing two Entrance cards in one turn, into different cells, is that effect's level 2; the owner rules on it there.",  # Q0749

    "G0167": 'Retired: already a rule. Undo is a button with a capped history (Game.undo_cap) that rewinds the board with the deck order unchanged. Rewinding the grid with the deck order unchanged is the button.',  # Q0758

    "E1255": 'Duplicate of Q0128 (Burnt Joker): the hand type chosen at random, by you, or the least-played is enhanced; the owner rules on it there.',  # Q0143

    "E1449": "Duplicate of Q0030 (The Clock Hang), which the owner wrote: a card placed past the grid's edge as if the grid were one larger; the owner's version stands.",  # Q0176
}

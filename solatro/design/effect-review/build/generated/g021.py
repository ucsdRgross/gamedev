# -*- coding: utf-8 -*-
# Family Y - the board plan. Design space that did not exist when this corpus was mined:
# the deck now deals every cell a MARK, and placing a card that agrees with its mark pays.
# Rows: (eid, name, cls, slot, mechanic, a, b, c, default)
#
# The rules these are written against, all settled in design/board-plan/DESIGN.md:
#   - four matchable properties, independent and additive: rank, suit, talent, hat
#   - a rank match pays FLAT points; a talent or hat match pays a MULT
#   - bonus mults SUM, and a sum of 0 never multiplies
#   - a suit effect fires ONLY when its suit mark is matched
#   - a mark is never a card: it completes no line and scores nothing
#   - the plan is dealt once per show from the deck, evenly across the Entrance stocks
SOURCE = "design/board-plan"

ROWS = [

# ---------------------------------------------------------------- Y1 matching a mark ---
("M0001", "The Understudy", "Y1", "skill",
 "Pays for being second best.",
 "When this card is placed on a mark it does NOT match, it still pays the rank bonus of whatever the mark wanted",
 "When this card is placed on a mark it does not match, it pays half the rank bonus the mark wanted",
 "When this card is placed on a mark it does not match, it pays the talent mult the mark wanted instead of the rank bonus",
 "c"),

("M0002", "Chalk Dust", "Y1", "stamp",
 "The mark pays twice for the card wearing it.",
 "Every property this card matches pays double",
 "The first property this card matches each show pays double",
 "Every property this card matches pays double, but a miss on any property destroys this stamp",
 "a"),

("M0003", "The Perfectionist", "Y1", "skill",
 "All four, or nothing.",
 "Pays a large mult when this card matches every property its mark prints, and nothing at all otherwise",
 "Pays a large mult when this card matches every property its mark prints, and its ordinary bonuses otherwise",
 "Pays a growing mult for each consecutive full match you land this show",
 "a"),

("M0004", "The Double Take", "Y1", "skill",
 "One card, two marks.",
 "Cue when placed: this card is also compared against the uncovered marks of the four cells beside it; a neighbour's match holds while that cell stays empty",
 "Cue when placed: this card is also compared against the uncovered mark of the cell one row up",
 "Cue when placed: this card is also compared against any one uncovered mark you choose in its row",
 "a"),

("M0005", "The Rank Outsider", "Y1", "rank",
 "Its number is whatever the plan asked for.",
 "This card counts as the rank of whatever mark it is placed on, for matching and for melding alike",
 "This card counts as the rank of whatever mark it is placed on, for matching only - its meld rank is unchanged",
 "This card counts as the rank of whatever mark it is placed on, and permanently becomes that rank",
 "a"),

("M0006", "Hitting It Cold", "Y1", "skill",
 "The first one is the one that counts.",
 "The first mark you match each show pays triple",
 "The first mark you match each show pays triple, and every later match that show pays nothing extra",
 "The first mark you match in each grid pays triple",
 "a"),

("M0007", "The Suit Case", "Y1", "stamp",
 "A suit that carries its own permission.",
 "The wearer's suit effect fires whether or not its mark agrees on suit",
 "The wearer's suit effect fires whether or not its mark agrees, at half strength",
 "The wearer's suit effect fires on ANY match, not only a suit match",
 "c"),

("M0008", "The Standing Ovation", "Y1", "skill",
 "Matching feeds the multiplier.",
 "Each property matched anywhere on the board this show adds to this card's mult, permanently",
 "Each property matched in this card's own lines adds to its mult for the rest of the show",
 "Each FULL match anywhere on the board adds to this card's mult, permanently",
 "b"),

# ------------------------------------------------------------ Y2 mark-borne effects ---
("M0009", "The Springboard", "Y2", "skill",
 "A mark that throws whatever lands on it.",
 "As a mark: the card placed on this cell scores as if it were one rank higher",
 "As a mark: the card placed on this cell scores as if it were one rank higher, and two higher if it matched",
 "As a mark: the card placed on this cell is moved one row up after scoring, stacking if that cell is occupied",
 "b"),

("M0010", "The Stand-In", "Y2", "stamp",
 "The mark performs instead of the card.",
 "As a mark: when any card covers this cell, the wearer's skill fires as though the wearer had been placed there",
 "As a mark: when a MATCHING card covers this cell, the wearer's skill fires as though the wearer had been placed there",
 "As a mark: when any card covers this cell, the wearer's skill fires and the mark is spent",
 "b"),

("M0011", "The Trapdoor", "Y2", "skill",
 "A mark that takes what you give it.",
 "As a mark: the first card placed on this cell is discarded instead, and the mark remains",
 "As a mark: the first card placed on this cell is returned to the Entrance instead, and the mark remains",
 "As a mark: a card placed on this cell that does not match it is discarded instead",
 "c"),

("M0012", "The Amplifier", "Y2", "stamp",
 "A mark that doubles the line.",
 "As a mark: every line through this cell adds +2 to its bonus mult for as long as any card sits on it",
 "As a mark: +2 while any card sits on it, +3 while a matching one does",
 "As a mark: the first line through this cell each show adds +2 to its bonus mult",
 "a"),

("M0013", "The Contract", "Y2", "skill",
 "A promise the board holds you to.",
 "As a mark: if this cell is still unmatched when you press End, the show scores nothing",
 "As a mark: if this cell is still unmatched when you press End, the show's score is halved",
 "As a mark: if this cell IS matched by the time you press End, the show's score is doubled",
 "c"),

("M0014", "The Second Billing", "Y2", "skill",
 "Its stronger form only on its own mark.",
 "This card's skill reaches level 2 when it matches its mark on ANY property, not only on talent",
 "This card's skill fires only at level 2: placed on a mark it does not match, it does nothing",
 "This card's skill reaches level 2 on any mark at all, matched or not",
 "a"),

("M0015", "The Reserved Cell", "Y2", "stamp",
 "A mark nothing can cover.",
 "As a mark: no card may be placed on this cell until every other cell of its row and column holds a card",
 "As a mark: no card may be placed on this cell unless it matches the mark",
 "As a mark: no card may be placed on this cell until a line through it is otherwise complete",
 "b"),

("M0016", "The Chorus Line", "Y2", "skill",
 "Marks that perform in concert.",
 "When two cards hit marks in the same line within one Entrance refill, both match bonuses pay again",
 "When three do, all three pay again, and the line, if complete, scores again",
 "As (a), and each further hit in that line that refill grows the bonus a step",
 "a"),

# ------------------------------------------------------------- Y3 reading the plan ---
("M0017", "The Route Book", "Y3", "skill",
 "Scores for what the plan asked for, not for what you did.",
 "At show end, pays for every property of the plan still uncovered: the marks you never overwrote",
 "At show end, pays for every property of the plan you DID match",
 "At show end, pays for every property of the plan you did NOT match",
 "b"),

("M0018", "The Casting Call", "Y3", "consumable",
 "Reads the board before you play it.",
 "Consumable: name a rank; every uncovered mark of that rank counts as matching any suit this show",
 "Consumable: name a rank; every mark of that rank pays double when matched this show",
 "Consumable: name a rank; every mark of that rank is re-dealt to a card of your choosing",
 "b"),

("M0019", "The Typecast", "Y3", "skill",
 "Rewards hitting a plan that repeats itself.",
 "Gains a permanent mult each time a mark sharing its suit is matched",
 "Gains a permanent mult each time a mark that is an exact copy of this card is matched",
 "Gains a mult each show for the largest number of matched marks that share one suit",
 "a"),

("M0020", "The Bill Poster", "Y3", "rule",
 "The plan itself is a goal.",
 "Rule: the show's goal is set from what the plan would score if every mark were matched",
 "Rule: the show's goal is reduced by a fraction of what the plan would score if fully matched",
 "Rule: beating what the plan would have scored pays a bonus at show end",
 "c"),

("M0021", "The Reader", "Y3", "skill",
 "Pays for lines the plan already made.",
 "When a line completes, pays extra if the marks under it would have made the same hand type",
 "When a line completes, pays extra if the marks under it would have made ANY scoring hand",
 "When a line completes, pays extra if the marks under it would have made a BETTER hand than you did",
 "a"),

("M0022", "The Dead Spot", "Y3", "skill",
 "Finds the plan's worst cell: the uncovered mark that shares neither rank nor suit with any other mark in its lines.",
 "Cue: names the cell whose mark contributes least to any line, and pays for covering it with anything",
 "Cue: names the cell whose mark contributes least, and destroys that mark",
 "Cue: names the cell whose mark contributes least, and re-deals it",
 "c"),

# ------------------------------------------------------------ Y4 changing the plan ---
("M0023", "The Rewrite", "Y4", "consumable",
 "Redraws one cell of the plan.",
 "Consumable: re-deal the mark of any one cell from the deck",
 "Consumable: re-deal the marks of any one line from the deck",
 "Consumable: set the mark of any one empty cell to a card of your choosing from the deck",
 "c"),

("M0024", "The Swap", "Y4", "consumable",
 "Two marks change places.",
 "Consumable: exchange the marks of any two empty cells",
 "Consumable: exchange the marks of any two cells, covered or not",
 "Consumable: exchange the marks of any two cells in the same line, and it is not spent the first time",
 "a"),

("M0025", "The Booking", "Y4", "skill",
 "Marks itself onto the board.",
 "At show start, this card's own mark is placed on a cell you choose instead of a random one",
 "At show start, this card is marked onto three cells instead of one",
 "At show start, this card's mark is placed on the cell that already has the most lines through it",
 "a"),

("M0026", "The Cancelled Date", "Y4", "skill",
 "Destroys the plan for profit.",
 "Cue once per Entrance refill: destroy any unmatched mark and gain flat points equal to its rank",
 "Cue once per Entrance refill: destroy any unmatched mark and gain a permanent mult",
 "Cue once per Entrance refill: destroy every unmatched mark in one line and gain a large one-off score",
 "b"),

("M0027", "The Rolling Call", "Y4", "skill",
 "The plan grows as you play.",
 "Every time you match a mark, one uncovered mark of your choice is re-dealt from the deck",
 "Every time you match a mark, the NEXT card in the Entrance is marked onto an empty cell",
 "Every time you fail to match, one uncovered mark of your choice is re-dealt from the deck",
 "b"),

("M0028", "The Standing Set", "Y4", "skill",
 "The plan outlives the show.",
 "The plan is not re-dealt between shows; the same marks stand until they are matched",
 "Marks you matched stay matched across shows and pay a smaller bonus each time",
 "The plan is re-dealt each show, but any mark you covered but never matched is dealt again to the same cell",
 "c"),

# --------------------------------------------------------------- Y5 lenient matching ---
("M0029", "The Near Enough", "Y5", "skill",
 "One step off still counts.",
 "A rank one away from the mark's rank counts as a rank match, at half the bonus",
 "A rank one away from the mark's rank counts as a full rank match",
 "A rank one away counts, and a rank two away counts at half",
 "a"),

("M0030", "The Quick Change", "Y5", "stamp",
 "Wears whatever the mark is wearing.",
 "This card counts as matching the rank of any mark it is placed on",
 "This card counts as matching the rank and suit of any mark it is placed on",
 "This card counts as matching whichever single property you name when you place it, other than the hat",
 "c"),

("M0031", "The Loose Blocking", "Y5", "skill",
 "The mark does not have to be underneath.",
 "A card matches the mark of any cell orthogonally adjacent to the one it is placed in, if its own is unmatched",
 "A card also matches the uncovered marks of the cells beside it, on suit only",
 "A card matches the mark of any cell in its own line, once per line per show",
 "c"),

("M0032", "The Colour Match", "Y5", "skill",
 "Near enough, for a suit.",
 "A card matches a mark's suit if both suits travel the same way: Hoops and Knives cross the row; Balls, Fire and Fireworks travel the column",
 "A card always matches a mark's suit, and every suit effect fires at half strength",
 "A card matches a mark's suit if either card carries no talent",
 "a"),

# ------------------------------------------------------------------ Y6 the unrealized ---
("M0033", "The Empty House", "Y6", "skill",
 "Pays for the plan you ignored.",
 "At show end, pays a large amount for every mark that was never covered and whose card was never drawn",
 "At show end, pays a large amount for every mark that was covered but never matched",
 "At show end, pays for every mark whose card left it again",
 "b"),

("M0034", "The Missed Cue", "Y6", "skill",
 "Grows on failure.",
 "Gains a mult for the show for each card placed on a mark it matches nothing of; the next hit spends it into that hit's lines and resets it",
 "Gains a permanent mult every time a mark is destroyed unmatched",
 "Gains a permanent mult for each show that ends with more than half the plan unmatched",
 "a"),

("M0035", "The Cut Number", "Y6", "skill",
 "Unmatched marks cost something.",
 "Every mark left unmatched at show end reduces the score by its rank",
 "Every mark left unmatched at show end reduces the score by a fixed amount",
 "A show ending with any unmatched mark pays no rank bonuses at End",
 "a"),

("M0036", "The Dark Cell", "Y6", "skill",
 "A cell the plan lost.",
 "A cell whose mark has been destroyed or withheld by an effect pays double for the card placed there, since nothing is planned for it",
 "A cell whose mark has been destroyed or withheld by an effect scores nothing for the card placed there",
 "A cell whose mark has been destroyed or withheld takes the mark of the cell that scored most this show",
 "a"),

]

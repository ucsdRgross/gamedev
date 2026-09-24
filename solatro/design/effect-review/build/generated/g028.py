# -*- coding: utf-8 -*-

# Family AB: effects where aiming a card at the cell whose mark agrees with it is the decision,
# checked against family Y so none restates a mark effect. (eid, name, cls, slot, mechanic, a, b, c, default)
SOURCE = "the level-2 pass"
ROWS = [

# ---- AB1 Aim: which cell a card wants, and chains of hits ----
("MK0001", "The Bullseye Streak", "AB1", "skill", "Consecutive hits build a streak that the next line cashes.",
 "Each placement that lands a card on a mark it matches adds +1 to a streak; the next line to score adds the streak to its multiplier and spends it, and a miss resets it",
 "As (a), but the streak survives one miss before it resets",
 "As (a), but the streak is not cashed until it breaks, and then it pays its square as flat points",
 "a"),

("MK0002", "The Echo Mark", "AB1", "skill", "A hit copies its mark to a second cell, making a new target.",
 "When a card hits its mark, that mark is copied onto the mirrored cell across the grid's centre, if it is empty",
 "When a card hits its mark, that mark is copied onto an empty cell beside it of your choice",
 "When a card hits its mark, that mark is copied onto the next empty cell in its row",
 "b"),

("MK0003", "The Relay Hit", "AB1", "skill", "Hits in one line pass their bonus down the line.",
 "When a card hits its mark, the next card to hit a mark in the same line pays the first card's match bonus as well as its own",
 "As (a), but the relay passes along every line through the first card's cell",
 "As (a), and the relay keeps passing, growing by one step each time, until a card in that line misses",
 "a"),

("MK0004", "The Full Set", "AB1", "skill", "A line where every card hit its mark scores one hand higher.",
 "A completed line in which every card sits on a mark it matches scores as the next hand up the ladder",
 "A completed line in which every card sits on a mark it matches scores double",
 "A completed line in which every card matches its mark on the SAME property scores as the next hand up",
 "a"),

("MK0005", "The Hot Hand", "AB1", "skill", "Three hits in a row make the next card match anything.",
 "After three placements in a row that each land on a mark they match, the next card placed counts as matching any mark",
 "After three hits in a row, the next card placed counts as matching any mark on one property you name",
 "After three hits in a row, every card placed counts as matching its mark until a card is placed on a mark it matches on none of its own properties",
 "a"),

("MK0006", "The Triangulation", "AB1", "skill", "Hits that form a shape fire their marks again.",
 "When three hits form an L of three cells, all three marks fire their match bonuses again",
 "When three hits sit in one line with gaps between them, all three marks fire again",
 "When four hits form a two-by-two square, all four marks fire again and the square scores as the best four-card flush or straight it holds, else High Card",
 "a"),

# ---- AB2 Level 2 is the point: modest at level 1, built to be realised ----
("MK0007", "The Late Bloomer", "AB2", "skill", "Nothing at level 1, a lot at level 2.",
 "Does nothing at level 1; at level 2 it pays a large multiplier and shares its flat talent mult with every card in its lines",
 "Pays a small flat bonus at level 1; at level 2 it pays a large multiplier",
 "Does nothing at level 1, and gains a step for each show it misses its mark; at level 2 it pays a multiplier of that size and resets",
 "a"),

("MK0008", "The Contagious Talent", "AB2", "skill", "Level 2 spreads to the cards around it.",
 "While it is at level 2, cards in its lines that hit their own marks on ANY property fire their level 2, not only on the matching property",
 "While it is at level 2, the cards beside it that hit their own marks fire their level 2 on any property",
 "While it is at level 2, every card placed during that Entrance refill fires its level 2 on any property it matches",
 "a"),

("MK0009", "The Chosen Property", "AB2", "stamp", "You pick which property unlocks the wearer's level 2.",
 "When placed, name one property - rank, suit, talent or hat; a match on it unlocks the wearer's level 2",
 "When placed, name two properties; a match on either unlocks the wearer's level 2",
 "When placed, a match on ANY property unlocks the wearer's level 2",
 "a"),

("MK0010", "The Second Nature", "AB2", "skill", "Once realised, it stays realised.",
 "Once it has reached level 2 this show, it keeps level 2 for the rest of the show even after it leaves its mark",
 "Once it has reached level 2, it keeps level 2 until it next scores off its mark",
 "Once it has reached level 2 in three shows, it is at level 2 permanently wherever it sits",
 "a"),

# ---- AB3 The plan answers back: hits and misses rewrite, reveal and move marks ----
("MK0011", "The Makeover", "AB3", "skill", "A miss rewrites the mark to agree with you.",
 "When this card is placed on a mark it matches nothing of, the mark is rewritten to a copy of it, and this card counts as hitting it on one property you choose",
 "When any card is placed on a mark it matches nothing of, the mark is rewritten to agree with it on one property you choose, and that card counts as hitting it on that property",
 "When this card misses, the mark takes its rank only, and the next card stacked on it pays a rank match",
 "b"),

("MK0012", "The Ripple", "AB3", "skill", "A hit re-deals the marks beside it toward what is coming.",
 "When a card hits its mark, the uncovered marks beside it are re-dealt from the cards now in the Entrance",
 "When a card hits its mark, one uncovered mark beside it of your choice is re-dealt from the Entrance",
 "When a card hits its mark, the uncovered marks beside it are re-dealt from the top card of each stock",
 "b"),

("MK0013", "The Afterimage", "AB3", "skill", "A card that leaves a hit behind leaves its likeness.",
 "When a card leaves a cell whose mark it matched, the mark becomes a copy of that card",
 "When a card leaves a matched cell, the mark becomes a copy of it and pays double to the next card that hits it",
 "When a card leaves a matched cell, the marks of the cells beside it become copies of it",
 "a"),

("MK0014", "The Encore Plan", "AB3", "structure", "What you hit comes back.",
 "Every mark you hit this show is dealt to the same cell again next show",
 "Every mark you hit this show is dealt to the same cell again next show, and pays double when hit again",
 "Every mark you missed this show is dealt to the same cell again next show, so a plan left unfinished waits for you",
 "a"),

("MK0015", "The Inheritance", "AB3", "skill", "A hit passes to whatever covers it.",
 "A card stacked on a card that hit its mark counts as matching the same properties",
 "A card stacked on a card that hit its mark counts as matching them, and the covered card keeps its own hit too",
 "A card stacked on a hit counts as matching its mark on every property, but the covered card's hit is lost",
 "a"),

("MK0016", "The Anchor", "AB3", "stamp", "A hit it never leaves.",
 "The wearer can never be moved off its cell",
 "Once the wearer hits its mark it cannot be moved, and its mark cannot be rerolled or swapped",
 "The whole stack on the wearer's cell is fixed",
 "b"),

("MK0017", "The Moving Target", "AB3", "hazard", "The plan will not hold still.",
 "Level: after each Entrance refill every uncovered mark shifts one cell in a direction shown one refill ahead, wrapping at the edge; a mark that would land under a card stays",
 "Level: after each Entrance refill the uncovered marks rotate one cell around the grid's edge",
 "Level: after each Entrance refill one uncovered mark swaps with a covered one, and the swap is shown in advance",
 "a"),

("MK0018", "The False Marks", "AB3", "hazard", "Some marks are lying.",
 "Level: two marks per grid are false; hitting one pays nothing and reveals it",
 "Level: two marks per grid are false; hitting one costs its match bonus instead of paying it",
 "Level: two marks per grid are false, and a false mark shows its truth only when a card beside it hits",
 "c"),

# ---- AB4 Called and bounced hits ----
("MK0019", "The Call", "AB4", "skill", "Name a cell; the next hit there pays big.",
 "Cue: name an empty cell; the next card to hit its mark there pays its match bonus three times",
 "Cue: name an empty cell and the property it must hit on; a hit on that property there pays three times, and any other card placed there pays no match bonus",
 "Before each Entrance refill, name a cell; a hit there during that refill pays triple; a refill that leaves it empty drops the triple to double until a call lands",
 "a"),

("MK0020", "The Herding Hat", "AB4", "stamp", "Misses herd the marks.",
 "When the wearer is placed on a mark it matches nothing of, that mark is shoved one cell in a direction you choose, swapping with the mark there",
 "When the wearer misses, the mark it covered swaps with the mark of any empty cell in its lines",
 "When the wearer misses, the mark it covered is shoved one cell toward the nearest card that matches it, swapping with the mark there",
 "a"),

("MK0021", "The Ricochet", "AB4", "skill", "A hit on the edge bounces to the far end.",
 "When a card hits its mark on an edge cell that is not a corner, the card at the other end of the line that cell ends pays its match bonus again, if it too sits on a mark it matches",
 "When a card hits its mark on an edge cell that is not a corner, the card at the other end of the line that cell ends pays its match bonus, whether or not it matches",
 "When a card hits its mark on a corner cell, the cards at the far ends of both its lines pay their match bonuses again, if they sit on marks they match",
 "a"),
]

# -*- coding: utf-8 -*-
# Family AA, part 4: the rescan of rows the money/shop/hand filter dropped in wave 6 (SOURCES.md).
# Rows: (eid, name, cls, slot, mechanic, a, b, c, default)
SOURCE = "Balatro mod wiki"

ROWS = [

("BM0166", "The Scapegoat", "AA4", "skill",
 "A leaving card's number goes to someone still on stage.",
 "When a card leaves the board, its rank is added to a random card still on the board",
 "When a card leaves the board, its rank is added to the card that has scored least this show",
 "When a card leaves the board, its rank is added to this card",
 "a"),

("BM0167", "The Wings", "AA4", "skill",
 "The ends of the Entrance perform from the wings.",
 "The cards in the leftmost and rightmost Entrance slots score alongside every line that completes",
 "The card in the leftmost Entrance slot scores alongside every line that completes, then is discarded",
 "The cards in the leftmost and rightmost Entrance slots count as members of every row for melds",
 "a"),

("BM0168", "The Wildfire", "AA5", "skill",
 "A bonus that spreads down the row.",
 "At each show end, this card's bonus is copied onto its left neighbour, which passes it on the show after",
 "At each show end, this card's bonus is copied onto every orthogonal neighbour",
 "At each line completion, this card's bonus is copied onto its left neighbour, and this card's own bonus resets",
 "a"),

("BM0169", "The Checkerboard", "AA7", "hazard",
 "Half the board is awake at a time.",
 "Hazard: cards on even cells are live for one line completion, cards on odd cells for the next, alternating",
 "Hazard: cards on even cells are live during odd-numbered Entrance refills, cards on odd cells during even ones",
 "Hazard: only cards on cells matching the colour of the last placed cell are live",
 "a"),
]

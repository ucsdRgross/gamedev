# -*- coding: utf-8 -*-
# Mined from Open-Face Chinese Poker, Chinese Poker, and the poker variant
# family. This game IS a poker game and no poker variant had been mined. OFC in
# particular deals cards one at a time into rows that are scored as poker hands
# and CANNOT be moved once placed - this game's own loop, with decades of play
# behind it.
SOURCE = "Open-Face Chinese Poker and poker variants"
ROWS = [

("G0199","Fouling","B3","rule","Lines must be ordered by strength, or nothing scores.",
 "Rule: each line must score at least as high as the line above it; break the order and the whole grid scores nothing",
 "Rule: each line must beat the line above it; break the order and only the offending line scores nothing",
 "Rule: each line must beat the line above it; break the order and the grid scores, but pays a penalty larger than the best line was worth",
 "c"),

("G0200","Positional Royalties","A14","rule","The same hand is worth more where it is harder.",
 "Rule: a hand pays more in lines where the ordering rule makes it harder to achieve, so a flush in the middle beats a flush at the back",
 "Rule: a hand pays more the closer its line is to the centre of the grid, whatever the ordering rule",
 "Rule: each line carries a printed multiplier fixed at show start, so which line you build a hand in is a decision",
 "a"),

("G0201","The Scoop","A13","rule","Taking every line pays more than the sum.",
 "Rule: scoring every line of a grid pays a large bonus on top of the individual lines",
 "Rule: scoring every line of every grid pays a large bonus",
 "Rule: scoring every line pays a bonus scaling with how many lines the grid has",
 "a"),

("G0202","Fantasyland","S6","rule","A strong result changes how the next show is dealt.",
 "Rule: a strong enough hand in a named line means the next show deals its whole Entrance at once instead of five at a time",
 "Rule: a strong enough hand in a named line means the next show starts with a card already placed where you want it",
 "Rule: a strong enough hand means the next show deals the whole Entrance at once, and staying in it requires repeating the feat",
 "c"),

("G0203","Uneven Rows","C6","rule","The lines are not the same length.",
 "Rule: a grid's lines have different lengths - three, five, five - and a short line is scored on its own smaller hand table",
 "Rule: a grid's lines have different lengths, and a short line pays proportionally more per card",
 "Rule: a grid's lines have different lengths, and you choose the shape before the show starts",
 "b"),

("G0204","Lowball","B7","rule","The worst hand wins.",
 "Rule: lines are scored on the WORST poker hand they contain rather than the best",
 "Rule: lines are scored on the worst hand, and the ace counts low",
 "Rule: one line per grid, named at show start, is scored on its worst hand while the rest score normally",
 "c"),

("G0205","Badugi","B1","rule","A hand made entirely of differences.",
 "A new hand: four cards with no two sharing a rank and no two sharing a suit",
 "A new hand: a full line with no two cards sharing a rank and no two sharing a suit",
 "A new hand: four cards sharing neither rank nor suit, ranked by how low its highest card is",
 "b"),

("G0206","The Pineapple","F5","rule","Draw more than you can keep.",
 "Rule: the Entrance deals more cards than you may place, and the remainder are discarded at the end of the turn",
 "Rule: the Entrance deals more cards than you may place, and the remainder carry into the next Entrance",
 "Rule: the Entrance deals more than you may place, and you choose which to discard before seeing where they would fit",
 "a"),

("G0207","Deuces Wild","B5","rule","One rank is designated wild for the show.",
 "Rule: one rank named at show start is wild in every meld",
 "Rule: one rank is wild, and it changes each act",
 "Rule: one rank is wild, and any line using a wild pays three quarters",
 "c"),

("G0208","The Bring-In","R4","rule","The first placement is forced.",
 "Rule: the first card of each show must be placed in a cell the show names, not one you choose",
 "Rule: the first card of each act must be placed in a named cell",
 "Rule: the first card of each show is placed for you, and you are shown where before you see the card",
 "c"),

("G0209","The Kill Pot","R6","rule","Winning big makes the next one harder.",
 "Rule: a show won by more than double its goal raises the next show's goal by half again",
 "Rule: a show won by more than double raises the next goal, and also doubles the next reward",
 "Rule: after any show won by more than double, the following show is a boss regardless of the route",
 "b"),

("G0210","The Showdown Order","H8","rule","Lines resolve strongest first.",
 "Rule: completed lines resolve in order of the strength of the hand they made, strongest first",
 "Rule: completed lines resolve weakest first, so the strongest benefits from everything the others triggered",
 "Rule: completed lines resolve in an order you choose each act",
 "b"),
]

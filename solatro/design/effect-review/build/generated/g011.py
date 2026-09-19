# -*- coding: utf-8 -*-
# Mined from Open-Face Chinese Poker, Chinese Poker, and the poker variant
# family. This game IS a poker game and no poker variant had been mined. OFC in
# particular deals cards one at a time into rows that are scored as poker hands
# and CANNOT be moved once placed - this game's own loop, with decades of play
# behind it.
SOURCE = "Open-Face Chinese Poker and poker variants"
ROWS = [

("G0199","Fouling","B3","skill","Lines must be ordered by strength, or nothing scores.",
 "Each line must score at least as high as the line above it; break the order and the whole grid scores nothing",
 "Each line must beat the line above it; break the order and only the offending line scores nothing",
 "Each line must beat the line above it; break the order and the grid scores, but pays a penalty larger than the best line was worth",
 "c"),

("G0200","Positional Royalties","A14","skill","The same hand is worth more where it is harder.",
 "A hand pays more in lines where the ordering rule makes it harder to achieve, so a flush in the middle beats a flush at the back",
 "A hand pays more the closer its line is to the centre of the grid, whatever the ordering rule",
 "Each line carries a printed multiplier fixed at show start, so which line you build a hand in is a decision",
 "a"),

("G0201","The Scoop","A13","skill","Taking every line pays more than the sum.",
 "Scoring every line of a grid pays a large bonus on top of the individual lines",
 "Scoring every line of every grid pays a large bonus",
 "Scoring every line pays a bonus scaling with how many lines the grid has",
 "a"),

("G0202","Fantasyland","S6","skill","A strong result changes how the next show is dealt.",
 "A strong enough hand in a named line means the next show deals ten cards into the Entrance instead of five",
 "A strong enough hand in a named line means the next show starts with a card already placed where you want it",
 "A strong enough hand means the next show deals ten cards into the Entrance, and staying in it requires repeating the feat",
 "c"),

("G0203","Uneven Rows","C6","skill","The lines are not the same length.",
 "A grid's lines have different lengths - three, five, five - and a short line is scored on its own smaller hand table",
 "A grid's lines have different lengths, and a short line pays proportionally more per card",
 "A grid's lines have different lengths, and you choose the shape before the show starts",
 "b"),

("G0204","Lowball","B7","skill","The worst hand wins.",
 "Lines are scored on the WORST poker hand they contain rather than the best",
 "Lines are scored on the worst hand, and the ace counts low",
 "One line per grid, named at show start, is scored on its worst hand while the rest score normally",
 "c"),

("G0205","Badugi","B1","skill","A hand made entirely of differences.",
 "A new hand: four cards with no two sharing a rank and no two sharing a suit",
 "A new hand: a full line with no two cards sharing a rank and no two sharing a suit",
 "A new hand: four cards sharing neither rank nor suit, ranked by how low its highest card is",
 "b"),

("G0206","The Pineapple","F5","skill","Draw more than you can keep.",
 "The Entrance deals more cards than you may place, and the remainder are discarded at the end of the turn",
 "The Entrance deals more cards than you may place, and the remainder carry into the next Entrance",
 "The Entrance deals more than you may place, and you choose which to discard before seeing where they would fit",
 "a"),

("G0207","Deuces Wild","B5","skill","One rank is designated wild for the show.",
 "One rank named at show start is wild in every meld",
 "One rank is wild, and it changes each placement",
 "One rank is wild, and any line using a wild pays three quarters",
 "c"),

("G0208","The Bring-In","R4","skill","The first placement is forced.",
 "The first card of each show must be placed in a cell the show names, not one you choose",
 "The first card of each Entrance refill must be placed in a named cell",
 "The first card of each show is placed for you, and you are shown where before you see the card",
 "c"),

("G0209","The Kill Pot","R6","skill","Winning big makes the next one harder.",
 "A show won by more than double its goal raises the next show's goal by half again",
 "A show won by more than double raises the next goal, and also doubles the next reward",
 "After any show won by more than double, the following show is a boss regardless of the route",
 "b"),

("G0210","The Showdown Order","H8","skill","Lines resolve strongest first.",
 "Completed lines resolve in order of the strength of the hand they made, strongest first",
 "Completed lines resolve weakest first, so the strongest benefits from everything the others triggered",
 "Completed lines resolve in an order you choose each placement",
 "b"),
]

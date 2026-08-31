# -*- coding: utf-8 -*-
# Mined from Santorini. A 5x5 grid where you BUILD HEIGHT, and where the god
# powers are explicit rule-breakers that alter movement, building or the win
# condition - the closest published analogue to this game's rules deck sitting
# on top of its own board shape.
SOURCE = "Santorini"
ROWS = [

("G0144","The Displacer","E2","skill","Swaps with what it would have pushed out.",
 "Placing this card onto an occupied cell swaps the two rather than stacking",
 "Placing this card onto an occupied cell swaps the two, and the displaced card keeps this one's stamp",
 "Placing this card onto an occupied cell swaps them, and both count as newly placed for line-completion purposes",
 "c"),

("G0145","The Second Step","E1","skill","Moves twice, but never back.",
 "Cue: move this card twice in one action, and it may not return to the cell it started in",
 "Cue: move this card twice in one action with no restriction on where it ends",
 "Cue: move this card any number of times in one action, so long as each cell is one it has not occupied this act",
 "c"),

("G0146","The Vigil","H4","skill","Your last move dictates what others may do.",
 "If this card rose in height last turn, no other card may rise in height this turn",
 "If this card rose in height last turn, no OPPOSING effect may raise a card this turn",
 "Whatever this card did last turn, no other card may do this turn",
 "c"),

("G0147","The Dome","D10","skill","Seals a cell against any further height.",
 "Cue: seal a cell at its current height so nothing may ever be stacked on it again",
 "Cue: seal a cell at its current height for the rest of the show only",
 "Cue: seal a cell, and every sealed cell on the grid raises this card's score",
 "c"),

("G0148","The Double Harvest","K7","skill","Two placements, never the same cell.",
 "Cue: place two Entrance cards this turn instead of one, into different cells",
 "Cue: place two Entrance cards this turn into different cells, and only the second may complete a line",
 "Cue: place two Entrance cards into different cells, and a bonus if they land in different grids",
 "c"),

("G0149","The Forge","D3","skill","Two placements, both onto the same cell.",
 "Cue: place two Entrance cards this turn onto the SAME cell, building height two at once",
 "Cue: place two Entrance cards onto the same cell, and the pair scores as a single card of their summed rank",
 "Cue: place any number of Entrance cards onto one cell this turn, at one patience each",
 "a"),

("G0150","The Messenger","E1","skill","Unlimited movement, so long as height never changes.",
 "Cue: move this card any distance across cells of the same height, as many times as you like",
 "Cue: move every card of your choosing any distance, so long as none of them changes height",
 "Cue: move this card any distance at the same height, and it scores per cell crossed",
 "b"),

("G0151","The Bull","E2","skill","Pushes rather than swaps.",
 "Placing this card onto an occupied cell pushes that card one further in the same direction; it is destroyed if there is no room",
 "Placing this card onto an occupied cell pushes that card one further; if there is no room the placement is illegal",
 "Placing this card pushes the whole line of cards beyond it along by one, like a shove",
 "c"),

("G0152","The Fall","U2","skill","Win by dropping, not by climbing.",
 "Alternate win: move a card down two or more levels of height in one action",
 "Alternate win: move a card down from the top of the tallest stack to the floor in one action",
 "Alternate win: end a show having dropped more total height than you built",
 "b"),

("G0153","The Long Count","U2","rule","Win on the board's state, not on your own.",
 "Alternate win: the show is won the moment a set number of sealed cells exist anywhere, whoever made them",
 "Alternate win: the show is won when a set number of sealed cells exist, and hazards that seal cells count toward it",
 "Alternate win: the show is won when every grid holds at least one sealed cell",
 "b"),

("G0154","The Forethought","K8","skill","Acts on both sides of its own move.",
 "Cue: this card acts once before it moves and once after, at the cost of never being able to gain height that turn",
 "Cue: this card acts before and after it moves, with no cost",
 "Cue: choose per turn whether this card acts before moving, after, or both at the cost of its height",
 "c"),

("G0155","The Line of Sight","E5","skill","Clears what is directly beyond.",
 "Moving this card into a cell destroys whatever sits in the next cell along the same direction",
 "Moving this card into a cell destroys whatever sits in the next cell along, and this card gains its rank",
 "Moving this card into a cell pushes everything in that direction one cell, destroying only what falls off the grid",
 "c"),
]

# -*- coding: utf-8 -*-
# Mined from the solitaire variant literature at large (the Morehead and
# Mott-Smith classification, and named variants: Spider, Gaps, Stalactites,
# Moojub, Mrs. Mop, Virginia Reel), plus mahjong hand catalogues and the
# incremental-game scaling tradition.
SOURCE = "solitaire families, mahjong and incremental games"
ROWS = [

# --- solitaire structural families -------------------------------------------
("G0223","The Packer","D1","skill","Build downward in alternating colour.",
 "Stacks build one rank down in alternating colour, and a whole ordered run moves as one",
 "Stacks build one rank down in alternating colour, and only single cards move",
 "Stacks build one rank down in any colour but the same one, and a whole run moves as one",
 "a"),

("G0224","The Spider Rule","B2","skill","Build loosely, but only clear strictly.",
 "Stacks build one rank down regardless of suit, but a run is only removed and scored when it is entirely one suit",
 "Stacks build one rank down regardless of suit, and a run of any suits may be removed and scored at a lower rate",
 "Stacks build loosely, and a same-suit run scores double what a mixed one does",
 "a"),

("G0225","The Gap","X4","skill","The empty cells are the thing you move.",
 "You do not move cards, you move the gaps: a gap is filled by the card that continues the run to its left",
 "You move gaps rather than cards, and a gap at the start of a line may be filled by any card",
 "You move gaps rather than cards, and a gap that cannot be legally filled is sealed for the rest of the show",
 "c"),

("G0226","Stalactites","D5","skill","Lines grow downward from a fixed top.",
 "Lines build downward from a fixed card at the top rather than upward from the floor",
 "Lines build downward from a fixed top, and the fixed card may never be moved",
 "Half the lines build downward from a fixed top and half upward from the floor",
 "c"),

("G0227","The Fixed Positions","C4","rule","Every cell wants a particular rank.",
 "Rule: each cell of the grid is assigned a rank at show start, and a card matching its cell scores extra",
 "Rule: each cell is assigned a rank, and a card not matching its cell cannot be placed there at all",
 "Rule: each cell is assigned a rank, and matching cards may be swapped freely with each other",
 "a"),

("G0228","Everything Face Up","M1","skill","Nothing is hidden; the difficulty is the puzzle.",
 "The whole deck is visible from the start, so the show is pure planning with no unknowns",
 "The whole deck is visible but its order is not, so you know what is coming but not when",
 "The whole deck is visible for the show's first placement only, then hidden again",
 "c"),

("G0229","The Redeal","F8","skill","Gather what is left and lay it out again.",
 "When no legal move remains, you may gather the unplayed cards, shuffle and lay them out again, a limited number of times",
 "When no legal move remains you may redeal without shuffling, preserving the order",
 "You may redeal at any time, not only when stuck, but each redeal costs an Entrance card, discarded",
 "c"),

# --- mahjong ------------------------------------------------------------------
("G0230","The Hand Card","B9","skill","A published list of which hands are worth playing this run.",
 "The first time this card is spotlit, name a list of hands that score, for the rest of the run; hands not on the list score nothing",
 "The first time this card is spotlit, name a list of hands that score double, for the rest of the run; everything else scores normally",
 "The first time this card is spotlit, name a list of hands; completing every hand on the list wins the run outright",
 "b"),

("G0231","Concealed Versus Exposed","M2","skill","A hand built in the open is worth less.",
 "A line built entirely from face-down cards pays more than the same line built face up",
 "A line built entirely face down pays double, and revealing any card of it forfeits the bonus",
 "A line built face down pays more, and you choose per card whether to place it face up or down",
 "c"),

("G0232","The Pure Hand","B1","skill","A whole grid in one suit.",
 "A new hand: an entire grid of one suit scores enormously",
 "A new hand: an entire grid of one suit, or of one suit plus one named exception, scores enormously",
 "A new hand: an entire grid using only two suits scores enormously, and one suit scores more again",
 "c"),

# --- incremental games --------------------------------------------------------
("G0233","The Prestige Layer","T4","structure","Reset the run to make the next one faster.",
 "You may end a run early to convert its score into a permanent multiplier on every future run",
 "You may end a run early for a permanent multiplier, and the multiplier scales with how far you got",
 "You may end a run early for a permanent multiplier, and each reset makes the next reset worth more",
 "c"),

("G0234","The Softcap","A11","skill","Growth slows rather than stopping.",
 "Past a threshold, additional score is added at a reducing rate rather than being capped outright",
 "Past a threshold, additional score is added at a reducing rate, and a second threshold caps it hard",
 "Past a threshold, additional multiplier converts to flat points instead of being reduced",
 "c"),

("G0235","Breaking Infinity","A4","skill","The ceiling itself becomes a thing you remove.",
 "Score is capped until an effect removes the cap, after which higher operators become available",
 "Score is capped until an effect removes the cap; removing it also raises every goal to match",
 "Score is capped, and each cap broken permanently unlocks the next operator tier for the rest of the run",
 "c"),

("G0236","The Automation","K7","skill","Something you used to do by hand starts doing itself.",
 "An action you have performed enough times becomes automatic for the rest of the run",
 "An action performed enough times becomes automatic for the rest of the run, and you may switch it off",
 "An action performed enough times becomes automatic permanently for the rest of the run, even if this card is later removed from play",
 "b"),
]

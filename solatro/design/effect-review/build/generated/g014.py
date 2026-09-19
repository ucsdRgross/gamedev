# -*- coding: utf-8 -*-
# The tier-3 list that was named and then skipped: Blue Prince, Inscryption,
# Loop Hero, Monster Train, Baba Is You (directly rather than via Hempuli),
# Photosynthesis, 2048/Threes, and the match-3 RPG line.
SOURCE = "Blue Prince, Inscryption, Loop Hero, Monster Train and others"
ROWS = [

# --- Blue Prince --------------------------------------------------------------
("G0237","The Floor Plan","E8","skill","Every placement must connect to what is already down.",
 "A card may only be placed adjacent to a card already on the grid, and a placement that closes off empty cells wastes them for the show",
 "A card may only be placed adjacent to one already down, with no penalty for closing cells off",
 "A card may only be placed adjacent to one already down, and cells it closes off are scored as if empty at show end",
 "a"),
("G0238","The Dead End","X4","skill","Cutting the board off has a cost.",
 "Any empty cell that no Entrance card can legally be placed in when the Entrance refills is destroyed and counts against the show",
 "Any empty cell no Entrance card can legally reach at a refill is destroyed, but pays a small consolation",
 "Any empty cell no Entrance card can legally reach at a refill is sealed rather than destroyed, and sealing enough cells triggers a bonus",
 "a"),

# --- Inscryption --------------------------------------------------------------
("G0239","The Sacrifice","L10","skill","Cards are the currency for playing cards.",
 "Placing a card costs you another card already on the grid, destroyed to pay for it",
 "Placing a card of high rank costs another card on the grid; low ranks are free",
 "Placing a card costs another card, and the cost may be paid from the Entrance instead of the grid",
 "b"),
("G0240","The Fourth Wall","O6","skill","A card that knows what it is.",
 "This card can be removed from the grid and physically re-placed elsewhere in the run's interface, changing what it affects",
 "This card announces the hidden rule that is currently working against you",
 "This card can read one other card's hidden text aloud, permanently revealing it for the run",
 "b"),

# --- Loop Hero ----------------------------------------------------------------
("G0241","Place Your Own Threats","R2","structure","The hazards are cards you chose to put down.",
 "You place the hazard cards yourself; each one raises the show's difficulty and its reward together",
 "You place hazard cards yourself, and may remove one per Entrance refill at a cost",
 "You place hazard cards yourself, and adjacent hazards combine into worse ones that pay more",
 "c"),
("G0242","Terrain Combinations","C10","skill","Two placed hazards make a third thing.",
 "Two specific hazard cards placed adjacent transform into a stronger single hazard with a larger reward",
 "Two specific hazards placed adjacent cancel each other out",
 "Two hazards placed adjacent combine, and the combination is different for each pair",
 "c"),

# --- Monster Train ------------------------------------------------------------
("G0243","The Floors","C6","skill","The grid is stacked into levels that resolve in order.",
 "A grid's stack heights act as floors that resolve bottom to top, and a threat that survives one floor rises to the next",
 "A grid's stack heights act as floors that resolve bottom to top, and a threat stopped on a floor is destroyed there",
 "A grid's stack heights act as floors, and you choose the order they resolve in each show",
 "a"),
("G0244","The Last Line","U2","hazard","One cell must never be reached.",
 "Alternate loss: a named cell must never be occupied by a hazard; if it is, the show ends immediately",
 "Alternate loss: a named cell must never be occupied by a hazard, and defending it successfully pays a bonus each placement",
 "Alternate loss: a named cell must never be reached, and its location moves each placement",
 "b"),

# --- Baba Is You --------------------------------------------------------------
("G0245","Rules As Objects","O1","skill","The rules are cards on the board you can move.",
 "Rule cards sit on the grid as movable objects; moving one out of position switches its rule off",
 "Rule cards sit on the grid and may be moved, and moving one to a different line re-targets what it applies to",
 "Rule cards sit on the grid as objects; they may be moved, destroyed, and rebuilt from parts",
 "c"),
("G0246","The Rewritten Noun","V2","skill","Changes what a card counts AS, globally.",
 "Cue: name a suit and a second suit; for the rest of the show every card of the first counts as the second",
 "Cue: name a rank and a second rank; for the rest of the show every card of the first counts as the second",
 "Cue: name any two card properties and swap them across the whole board for the rest of the show",
 "c"),

# --- Photosynthesis -----------------------------------------------------------
("G0247","The Shadow","D6","skill","Tall cards suppress what stands behind them.",
 "A card casts a shadow across cells behind it proportional to its height, and shadowed cards score nothing",
 "A card casts a shadow proportional to its height, and shadowed cards score half",
 "A card casts a shadow proportional to its height, and the direction the shadow falls rotates each placement",
 "c"),

# --- 2048 / Threes ------------------------------------------------------------
("G0248","The Merge","D8","skill","Two equal cards become the next one up.",
 "Two cards of equal rank pushed together merge into one of the next rank up",
 "Two cards of equal rank pushed together merge into one of double the rank",
 "Two cards of equal rank merge into the next rank up, and a merge that creates the highest rank scores enormously",
 "c"),
("G0249","The Slide","E4","skill","Everything moves at once, in one direction.",
 "An action slides every card on the grid in one direction until it hits something, and merges happen where equals meet",
 "An action slides every card in one direction, with no merging",
 "An action slides one line in one direction rather than the whole grid",
 "a"),

# --- match-3 RPG --------------------------------------------------------------
("G0250","Clears Feed A Resource","A10","skill","A completed line pays fuel, not points.",
 "A completed line pays a resource rather than score, and the resource is what powers your effects",
 "A completed line pays both score and a resource, at a reduced rate for each",
 "A completed line pays a resource whose kind is set by the line's dominant suit",
 "c"),
("G0251","The Cascade","C3","skill","A clear collapses the board and can clear again.",
 "A completed line clears and everything above falls in; a line completed by the fall scores again at a rising multiplier",
 "A completed line clears and everything above falls in, but a chain reaction scores at flat value",
 "A completed line clears and the board collapses; chains are capped at three to keep it bounded",
 "a"),
]

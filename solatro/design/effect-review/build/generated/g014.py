# -*- coding: utf-8 -*-
# The tier-3 list that was named and then skipped: Blue Prince, Inscryption,
# Loop Hero, Monster Train, Baba Is You (directly rather than via Hempuli),
# Photosynthesis, 2048/Threes, and the match-3 RPG line.
SOURCE = "Blue Prince, Inscryption, Loop Hero, Monster Train and others"
ROWS = [

# --- Blue Prince --------------------------------------------------------------
("G0237","The Floor Plan","E8","rule","Every placement must connect to what is already down.",
 "Rule: a card may only be placed adjacent to a card already on the grid, and a placement that closes off empty cells wastes them for the show",
 "Rule: a card may only be placed adjacent to one already down, with no penalty for closing cells off",
 "Rule: a card may only be placed adjacent to one already down, and cells it closes off are scored as if empty at show end",
 "a"),
("G0238","The Dead End","X4","rule","Cutting the board off has a cost.",
 "Rule: any cell made unreachable by your own placements is destroyed and counts against the show",
 "Rule: any cell made unreachable is destroyed, but pays a small consolation",
 "Rule: any cell made unreachable is sealed rather than destroyed, and sealing enough cells triggers a bonus",
 "a"),

# --- Inscryption --------------------------------------------------------------
("G0239","The Sacrifice","L10","rule","Cards are the currency for playing cards.",
 "Rule: placing a card costs you another card already on the grid, destroyed to pay for it",
 "Rule: placing a card of high rank costs another card on the grid; low ranks are free",
 "Rule: placing a card costs another card, and the cost may be paid from the Entrance instead of the grid",
 "b"),
("G0240","The Fourth Wall","O6","skill","A card that knows what it is.",
 "This card can be removed from the grid and physically re-placed elsewhere in the run's interface, changing what it affects",
 "This card announces the hidden rule that is currently working against you",
 "This card can read one other card's hidden text aloud, permanently revealing it for the run",
 "b"),

# --- Loop Hero ----------------------------------------------------------------
("G0241","Place Your Own Threats","R2","rule","The hazards are cards you chose to put down.",
 "Rule: you place the hazard cards yourself; each one raises the show's difficulty and its reward together",
 "Rule: you place hazard cards yourself, and may remove one per act at a cost",
 "Rule: you place hazard cards yourself, and adjacent hazards combine into worse ones that pay more",
 "c"),
("G0242","Terrain Combinations","C10","rule","Two placed hazards make a third thing.",
 "Rule: two specific hazard cards placed adjacent transform into a stronger single hazard with a larger reward",
 "Rule: two specific hazards placed adjacent cancel each other out",
 "Rule: two hazards placed adjacent combine, and the combination is different for each pair",
 "c"),

# --- Monster Train ------------------------------------------------------------
("G0243","The Floors","C6","rule","The grid is stacked into levels that resolve in order.",
 "Rule: a grid is divided into floors that resolve bottom to top, and a threat that survives one floor rises to the next",
 "Rule: a grid is divided into floors that resolve bottom to top, and a threat stopped on a floor is destroyed there",
 "Rule: a grid is divided into floors, and you choose the order they resolve in each act",
 "a"),
("G0244","The Last Line","U2","rule","One cell must never be reached.",
 "Alternate loss: a named cell must never be occupied by a hazard; if it is, the show ends immediately",
 "Alternate loss: a named cell must never be occupied by a hazard, and defending it successfully pays a bonus each act",
 "Alternate loss: a named cell must never be reached, and its location moves each act",
 "b"),

# --- Baba Is You --------------------------------------------------------------
("G0245","Rules As Objects","O1","rule","The rules are cards on the board you can move.",
 "Rule: rule cards sit on the grid as movable objects; moving one out of position switches its rule off",
 "Rule: rule cards sit on the grid and may be moved, and moving one to a different line re-targets what it applies to",
 "Rule: rule cards sit on the grid as objects; they may be moved, destroyed, and rebuilt from parts",
 "c"),
("G0246","The Rewritten Noun","V2","skill","Changes what a card counts AS, globally.",
 "Cue: name a suit and a second suit; for the rest of the show every card of the first counts as the second",
 "Cue: name a rank and a second rank; for the rest of the show every card of the first counts as the second",
 "Cue: name any two card properties and swap them across the whole board for the rest of the show",
 "c"),

# --- Photosynthesis -----------------------------------------------------------
("G0247","The Shadow","D6","rule","Tall cards suppress what stands behind them.",
 "Rule: a card casts a shadow across cells behind it proportional to its height, and shadowed cards score nothing",
 "Rule: a card casts a shadow proportional to its height, and shadowed cards score half",
 "Rule: a card casts a shadow proportional to its height, and the direction the shadow falls rotates each act",
 "c"),

# --- 2048 / Threes ------------------------------------------------------------
("G0248","The Merge","D8","rule","Two equal cards become the next one up.",
 "Rule: two cards of equal rank pushed together merge into one of the next rank up",
 "Rule: two cards of equal rank pushed together merge into one of double the rank",
 "Rule: two cards of equal rank merge into the next rank up, and a merge that creates the highest rank scores enormously",
 "c"),
("G0249","The Slide","E4","rule","Everything moves at once, in one direction.",
 "Rule: an action slides every card on the grid in one direction until it hits something, and merges happen where equals meet",
 "Rule: an action slides every card in one direction, with no merging",
 "Rule: an action slides one line in one direction rather than the whole grid",
 "a"),

# --- match-3 RPG --------------------------------------------------------------
("G0250","Clears Feed A Resource","A10","rule","A completed line pays fuel, not points.",
 "Rule: a completed line pays a resource rather than score, and the resource is what powers your effects",
 "Rule: a completed line pays both score and a resource, at a reduced rate for each",
 "Rule: a completed line pays a resource whose kind is set by the line's dominant suit",
 "c"),
("G0251","The Cascade","C3","rule","A clear collapses the board and can clear again.",
 "Rule: a completed line clears and everything above falls in; a line completed by the fall scores again at a rising multiplier",
 "Rule: a completed line clears and everything above falls in, but a chain reaction scores at flat value",
 "Rule: a completed line clears and the board collapses; chains are capped at three to keep it bounded",
 "a"),
]

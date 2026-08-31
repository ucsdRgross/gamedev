# -*- coding: utf-8 -*-
# The last two recovered by the source audit, both from DESIGN_REFERENCES.md.
# Everything else in that document's 391 mechanic proposals was already present.
ROWS = [

("G0142","The Overhead Show","C6","rule",
 "A play zone above the grid, not just a camera move. (DESIGN_REFERENCES.md A11, Fuerza Bruta)",
 "A strip of cells sits above the grid; cards placed there score into every column at once but can never form a line of their own",
 "A strip of cells sits above the grid and forms its own line, scoring separately from the grid below",
 "A strip of cells sits above the grid that only cards already scored once may enter, and they score again from up there",
 "c"),

("G0143","The Bonded Troupe","P6","rule",
 "Cards trained together take a shared tag. (DESIGN_REFERENCES.md F6, the Academy family)",
 "Between runs, several Common cards may be trained together; they gain a shared group tag and score a bonus whenever two of them are on the board",
 "Between runs, several Commons may be trained together into one merged card of their summed rank",
 "Between runs, several Commons gain a shared tag, and the bonus scales with how many of the troupe are on the board at once",
 "c"),
]

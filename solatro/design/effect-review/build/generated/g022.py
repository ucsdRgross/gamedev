# -*- coding: utf-8 -*-
# Family Y, the LEVEL side of the board plan. g021.py covers what a CARD does about marks;
# this covers what a LEVEL does to the plan, which is where the mechanic changes most and
# where the taxonomy was thinnest (C5 "prefilled cells" holds 4 questions at coverage "none",
# and every cell is prefilled by default now).
#
# The seam these are written against is already decided in design/board-plan/:
#   Q53=(a)  a level or blind MAY grant marks of cards that are not in your deck
#   Q121=(a) which is why a mark carries a `granted` flag - the deck-membership invariant
#            exempts it, and that flag exists FOR level design
#   Q77=(a)  level-granted plans are out of scope for board-plan and deferred to here
#
# Rows: (eid, name, cls, slot, mechanic, a, b, c, default)
SOURCE = "design/board-plan"

ROWS = [

# ------------------------------------------------------------- Y7 whose plan is it ---
("M0037", "The Guest Director", "Y7", "rule",
 "Someone else blocks the show.",
 "Level: one line of the grid is marked by the level instead of by your deck",
 "Level: half the grid is marked by the level instead of by your deck, in a scattered pattern",
 "Level: the whole grid is marked by the level and your deck marks nothing",
 "a"),

("M0038", "The House Deck", "Y7", "rule",
 "Marks of cards you have never owned.",
 "Level: the marks are drawn from a fixed house deck rather than from yours, and matching them still pays normally",
 "Level: the marks are drawn from a house deck, and matching one adds that card to your deck for the run",
 "Level: the marks are drawn from a house deck one rank above anything you own",
 "b"),

("M0039", "The Rewritten Bill", "Y7", "rule",
 "The plan changes under you.",
 "Level: every fifth placement, one unmatched mark is re-dealt somewhere else",
 "Level: every fifth placement, one unmatched mark is re-dealt to a different card",
 "Level: every placement, the two lowest-value unmatched marks swap cells",
 "a"),

("M0040", "The Split Bill", "Y7", "rule",
 "Two plans, one board.",
 "Level: with more than one grid, one grid is marked by your deck and the rest by the level",
 "Level: with more than one grid, each grid is marked from a different half of your deck",
 "Level: one grid is marked and the others are left blank",
 "a"),

# ------------------------------------------------------------- Y8 the hostile plan ---
("M0041", "The Bad Notice", "Y8", "rule",
 "Marks you are punished for hitting.",
 "Level: some cells carry a marked card that scores NEGATIVE when matched, shown before you commit",
 "Level: some cells carry a mark that scores nothing when matched and pays double when deliberately missed",
 "Level: some cells carry a mark that, when matched, disables that card's own effect for the show",
 "a"),

("M0042", "The Fading Chalk", "Y8", "rule",
 "The plan expires.",
 "Level: a mark that has not been matched within a fixed number of placements disappears",
 "Level: a mark that has not been matched within a fixed number of placements becomes a hazard cell",
 "Level: the whole plan fades one cell at a time, oldest first, from the show's midpoint",
 "a"),

("M0043", "The Rent Book", "Y8", "rule",
 "The plan costs to use.",
 "Level: matching a mark costs gold equal to its rank, and you may decline to match",
 "Level: matching a mark costs a placement's worth of Entrance refill",
 "Level: the first match each show is free and every later one costs gold",
 "c"),

("M0044", "The Understudy Riot", "Y8", "rule",
 "Ignore the plan and it acts on its own.",
 "Level: any cell whose mark you cover with a non-matching card places that mark's card onto the grid for you, somewhere else",
 "Level: any mark still unmatched at show end is placed onto the board and scores against you",
 "Level: covering a mark with a non-matching card discards a card from the Entrance",
 "a"),

("M0045", "The Poisoned Plan", "Y8", "rule",
 "The plan carries a status.",
 "Level: every mark of one named suit applies Burning to whatever covers it",
 "Level: every mark applies its own card's statuses to whatever covers it",
 "Level: one cell's mark applies a status of the level's choosing, and it is visible",
 "c"),

# -------------------------------------------------------------- Y9 the given plan ---
("M0046", "The Kind House", "Y9", "rule",
 "The level hands you a good board.",
 "Level: the plan is dealt so that at least one line already forms a scoring hand if fully matched",
 "Level: the plan is dealt so that every line forms at least a pair if fully matched",
 "Level: the plan is dealt from your best cards rather than at random",
 "a"),

("M0047", "The Solved Row", "Y9", "rule",
 "Part of the plan comes already done.",
 "Level: one line of the grid starts with its cards already placed and already matched",
 "Level: one line starts with its cards already placed but unmatched, so you may improve on it",
 "Level: one cell starts already matched, chosen at random",
 "b"),

("M0048", "The Standing Invitation", "Y9", "rule",
 "Matching is worth more here.",
 "Level: every property matched pays double for the whole show",
 "Level: every FULL match pays double for the whole show",
 "Level: the mults from talent and hat matches are doubled, and flat rank bonuses are not",
 "b"),

("M0049", "The Open Rehearsal", "Y9", "rule",
 "The plan is negotiable.",
 "Level: before the first placement, you may re-deal any three cells of the plan",
 "Level: before the first placement, you may swap any two marks, twice",
 "Level: once per show you may re-deal one cell of the plan, at any time",
 "c"),

# ------------------------------------------------------ Y10 levels that read the plan ---
("M0050", "The Quoted Fee", "Y10", "rule",
 "The goal is set from your own plan.",
 "Level: the show's goal is a fraction of what the plan would score if every mark were matched",
 "Level: the show's goal is set from what the plan's best single line would score",
 "Level: the show's goal is fixed, but beating what the plan would have scored pays a bonus",
 "a"),

("M0051", "The Banned Number", "Y10", "rule",
 "Your own plan tells the level what to forbid.",
 "Level: the hand type the plan would most often make scores nothing this show",
 "Level: the suit that appears most often in the plan scores nothing this show",
 "Level: the rank that appears most often in the plan cannot be placed at all",
 "b"),

("M0052", "The Critic", "Y10", "rule",
 "Judged against the plan rather than against a number.",
 "Level: the show is won by matching a stated fraction of the plan, and the score does not matter",
 "Level: the show is won by beating what the plan would have scored, whatever that number is",
 "Level: the show is won normally, but failing to match half the plan halves the reward",
 "b"),

("M0053", "The Typecaster", "Y10", "rule",
 "The plan decides what the level rewards.",
 "Level: whichever suit the plan carries most of pays double when matched",
 "Level: whichever suit the plan carries LEAST of pays triple when matched",
 "Level: the level names one property at show start and only that property pays",
 "b"),

# ------------------------------------------------------------- Y11 hiding the plan ---
("M0054", "The Closed Rehearsal", "Y11", "rule",
 "A plan you cannot read.",
 "Level: every mark is face down and is revealed only when a card is placed on it",
 "Level: every mark is face down and is revealed when a card is placed in an adjacent cell",
 "Level: marks are face down until the first line scores, then all reveal at once",
 "b"),

("M0055", "The Partial Bill", "Y11", "rule",
 "Half the plan is legible.",
 "Level: a mark shows its rank but not its suit",
 "Level: a mark shows its suit but not its rank",
 "Level: a mark shows only whether it carries a talent or a hat, not which",
 "a"),

("M0056", "The Dark Grid", "Y11", "rule",
 "One board goes unplanned.",
 "Level: with more than one grid, one grid carries no marks at all",
 "Level: with more than one grid, one grid's marks are hidden until you commit the Entrance to it",
 "Level: one grid's marks are shown only in the layer view, never on the board",
 "b"),

("M0057", "The Fogged Plan", "Y11", "rule",
 "Reading it costs something.",
 "Level: the layer view may be opened a fixed number of times per show",
 "Level: opening the layer view costs a placement",
 "Level: the layer view shows only the row your Entrance is committed toward",
 "a"),

# -------------------------------------------------------- Y12 the plan as objective ---
("M0058", "The Full House Call", "Y12", "rule",
 "A quest stated in marks.",
 "Objective: match every mark in any one line to win a permanent reward",
 "Objective: match every mark in any one line, and the reward grows with the line's length",
 "Objective: match every mark in a row AND the column that crosses it",
 "a"),

("M0059", "The Long Run", "Y12", "rule",
 "A quest across shows.",
 "Objective: match a stated number of marks across the whole run, counted between shows",
 "Objective: match at least one mark in every show of the run",
 "Objective: complete a show having matched every property at least once",
 "b"),

("M0060", "The Understudy's Night", "Y12", "rule",
 "The boss condition is the plan.",
 "Boss: the show is beaten only by matching a stated fraction of the plan, whatever you score",
 "Boss: the show is beaten normally, but every unmatched mark subtracts from the total",
 "Boss: the show is beaten by matching every mark of one named property",
 "a"),

("M0061", "The Cold Reading", "Y12", "rule",
 "A quest you are not told about.",
 "Objective: an unstated pattern of matches pays out when you happen to complete it",
 "Objective: an unstated pattern, with a hint shown after the third match",
 "Objective: an unstated pattern that is revealed the moment it becomes impossible",
 "c"),

# ------------------------------------------- Y13 six shipped blinds, re-expressed ---
# ⚠ These are the OVERLAP questions. Each names a blind that already ships in `blinds.csv`
# and asks whether the mark mechanic should absorb it. Answering (a) keeps a bespoke cell
# rule; (b) or (c) folds it into one mechanic with several skins.

("M0062", "Dress Code, as a mark", "Y13", "rule",
 "Ships in levels.csv: some cells demand a named suit and refuse anything else. A mark already IS a cell asking for a suit.",
 "Keep it bespoke: a demanding cell stays its own rule, separate from marks",
 "Fold it in: a demanding cell is a mark that REFUSES anything not matching its suit",
 "Fold it in, and generalise: a mark may refuse on any one of its four properties, not only suit",
 "c"),

("M0063", "The Dye Vat, as a mark", "Y13", "rule",
 "Ships in levels.csv: some cells convert whatever is placed on them to a named suit.",
 "Keep it bespoke: a converting cell stays its own rule",
 "Fold it in: a converting cell is a mark that rewrites what covers it to its own suit",
 "Fold it in, and generalise: a mark may rewrite any one property of what covers it",
 "b"),

("M0064", "The Ranked Floor, as a mark", "Y13", "rule",
 "Ships in levels.csv: scattered cells add or subtract from the rank of whatever is placed on them, shown before you commit.",
 "Keep it bespoke: a rank-shifting cell stays its own rule",
 "Fold it in: the shift is the mark's own rank bonus, applied whether or not the card matches",
 "Fold it in as the mirror: a mark you MISS applies its rank as a penalty instead of a bonus",
 "b"),

("M0065", "The Sealed Envelope, as a mark", "Y13", "rule",
 "Ships in levels.csv: one card starts face down somewhere in a grid and is revealed when a card is placed beside it.",
 "Keep it bespoke: the envelope stays a placed card, not a mark",
 "Fold it in: the envelope is a face-down mark revealed by an adjacent placement",
 "Fold it in, and pay for it: a face-down mark pays double when matched blind",
 "b"),

("M0066", "The Understudy Fills In, as a mark", "Y13", "rule",
 "Ships in levels.csv: any grid you place nothing into during a refill has a random card placed in it for you.",
 "Keep it bespoke: the random placement stays unrelated to the plan",
 "Fold it in: the card placed for you is the one the plan marked for that cell",
 "Fold it in: the card placed for you is the plan's mark, and it counts as matched",
 "b"),

("M0067", "Sight Unseen, as a mark", "Y13", "rule",
 "Ships in levels.csv: every card is face down in the Entrance and only turns face up once placed. The plan is the mirror of this - the board is legible while the hand is not.",
 "Keep it bespoke: the Entrance blindfold has nothing to do with the plan",
 "Pair them: the Entrance is blind AND the plan is fully visible, so the plan is the only information you have",
 "Invert it: the Entrance is visible and the plan is blind",
 "b"),

]

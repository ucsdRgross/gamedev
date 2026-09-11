# -*- coding: utf-8 -*-
"""Questions whose whole premise is architecture that no longer exists.

⚠ RETIRED IN PLACE, NEVER DELETED. The question id is POSITIONAL (`render.py` numbers by
walking the sorted rows), so removing a row would renumber every question after it and
repoint every recorded answer at a different effect. A retired row still renders — as an
italic one-liner with no options — so the id it holds stays nailed down.

These are not effects the owner rejected. They are effects whose referent went away: the
three-act show, the Submit button, the upper/lower tableau. Asking about them spends a
review slot on a mechanic that cannot be built.
"""

RETIRED = {
    # --- the 1-of-3 act structure -------------------------------------------------------
    "E0047": "Retired with the act structure: there is no final act. A show runs until the "
             "player presses End, so an effect keyed to a known-in-advance last scoring pass "
             "has no referent.",
    "E0050": "Retired with the act structure: there is no first act, only a first placement, "
             "which every effect can already name.",
    "E0149": "Retired with the act structure: there is no second act.",
    "E0552": "Retired with the act structure: a card type keyed to being played in a "
             "particular act has nothing to key on.",
    "E0692": "Retired with the act structure: a per-act rising multiplier needs acts to rise "
             "across. The combo multiplier already rises across a whole show.",
    "E1228": "Retired with the act structure: a final-act multiplier has no final act.",
    "E1229": "Retired with the act structure: a card type that appears only in the final act.",
    "E1234": "Retired with the act structure: a card type that appears only in the first act.",
    "E1432": "Retired with the act structure: a card type that appears only in the second act.",
    "E1356": "Retired with the act structure: a per-act injury roll.",
    "E1212": "Retired with the act structure: an Entrance step BETWEEN acts. The Entrance now "
             "refills on its own condition, which the Entrance design owns.",
    "E0380": "Retired with the act structure: 'a match is 3 submits'. A show has no act count.",
    "E1073": "Retired with the act structure: mapping 3 submits onto 3 performance acts.",

    # --- the Submit button ----------------------------------------------------------------
    "E1062": "Retired with Submit: scoring is continuous now. Every completed line scores the "
             "instant a placement completes it, so there is no whole-board scoring moment to "
             "redesign.",
    "E1342": "Retired with Submit: 'there is no submit slot, the whole board scores' is now "
             "simply true, so it is a description of the game rather than a proposal.",
    "E1430": "Retired with Submit: there is no submit at which to score the Entrance's cards.",
    "E1459": "Retired with Submit: nothing clears and cascades the board at a Submit.",
    "E1418": "Retired with Submit: the rules deck no longer defines a submit behaviour, and "
             "what it does define is the line detector, which is a separate question.",
    "E1197": "Retired with Submit: 'draw through the deck, then submit' is the retired loop. "
             "The live loop is draw to the Entrance, place, score on completion.",
    "G0388": "Retired with Submit: an effect that changes what Submit means has no button to "
             "change.",

    # --- the upper/lower tableau ----------------------------------------------------------
    "E1136": "Retired with the tableau: Canfield-style stacking rules described the pre-grid "
             "board. Stack legality on the grid is the poker-patience design's own question.",

    "G0227": 'Superseded by the board plan (design/board-plan): every cell assigned a card at show start, and a card matching its cell scores extra, IS the plan.',  # Q0170

    "G0195": 'Superseded by the board plan (design/board-plan): a cell whose printed requirement only a matching card satisfies is a mark; the refuse-a-mismatch form is asked as family Y13 (Dress Code, as a mark).',  # Q0171

    "E1208": 'Superseded by the board plan (design/board-plan): a cell that raises the rank of what lands on it is asked as family Y13 (The Ranked Floor, as a mark).',  # Q0165

    "G0366": 'Duplicate of the Short Ring (sub-length diagonals score as lines). Asked there.',  # Q0159

    "G0369": 'Duplicate of Rows spanning multiple grids (a row running across grids at the same y). Asked there.',  # Q0186

    "E0894": 'Duplicate of The Awkward Shape (a card occupying several cells). Asked there.',  # Q0208

    "G0142": 'Duplicate of the Entrance itself: a strip of cells above the grid is what the Entrance already is.',  # Q0181

    "E0655": 'A map idea (DESIGN_DOC Map v1, Minesweeper) that replaces the grid and Entrance outright. Its board form is asked as Minesweeper bomb-prefilled grid, and its hidden-board form as family Y11.',  # Q0173

    "G0378": 'Duplicate of Deja Vu card (a card remembering its cell and returning when it is empty). Asked there.',  # Q0372

    "E1886": "Retired with the held hand: selecting any number of cards to score together is Balatro's hand-play, which this game does not have. Its long-line form is asked as The Six-Card Line and Rows spanning multiple grids.",  # Q0149

    "G0165": 'Duplicate of Cribbage phase-1 stack-to-31 (a running total across placements scoring at named totals). Asked there.',  # Q0105

    "G0289": 'Duplicate of Rehearsal Hall (two, four and six cards of one class unlock escalating tiers). Asked there.',  # Q0997

    "E0684": 'Contradicts a standing owner ruling: overscore is retired, because punishing overperformance breeds sandbagging. If in-run responsiveness is wanted, scale REWARDS, never goals (ARCHITECTURE_REVIEW 3b).',  # Q1107

    "G0173": 'Duplicate of Maximized (every card counts as one of only two ranks). Asked there.',  # Q1342

    "M0020": "Duplicate of The Quoted Fee (the show's goal set from what the plan would score). A goal is set by the level, so the question is asked there.",  # Q1426
}

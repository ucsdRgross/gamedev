# -*- coding: utf-8 -*-
# Mined from The Zachtronics Solitaire Collection - Shenzhen, Sigmar's Garden,
# Kabufuda, Cluj, Proletariat's Patience, Fortune's Foundation, Sawayama,
# Cribbage Solitaire. Cited in the braindump as a direct inspiration. Each is a
# different STACKING or FOUNDATION ruleset, which is exactly the D and B space.
SOURCE = "Zachtronics Solitaire Collection"
ROWS = [

("G0156","The Dragon Collapse","P5","skill","Collect a set, and it seals a slot.",
 "When all four cards of a named group are uncovered at once, they collapse into one cell which is then permanently sealed",
 "When all four of a named group are uncovered, they collapse and are removed from the run entirely, paying their summed rank",
 "When all four of a named group are uncovered, they collapse into one card carrying all four of their skills",
 "c"),

("G0157","The Free Edge","D6","skill","Playable only if something is open beside it.",
 "A card may only be picked up if at least one of its horizontal neighbours is empty",
 "A card may only be picked up if it is uncovered AND has a free edge, so a card walled in on both sides is stuck",
 "A card with a free edge counts as spotlit whether or not it is covered",
 "b"),

("G0158","The Metal Chain","U4","skill","A sequence that must be consumed in order.",
 "A named chain of ranks may only be scored in strict ascending order, and skipping one locks the rest",
 "A named chain must be scored in order, and completing the whole chain pays enormously",
 "A named chain must be scored in order; the chain is reseeded each show and its order is shown up front",
 "b"),

("G0159","The Salt","B5","rank","Matches its own kind, or anything.",
 "This card melds either with another of its own kind or with any card at all, your choice at scoring",
 "This card melds with any card at all, but never with another of its own kind",
 "This card melds with anything, and every one used in a meld makes the next one in the deck stricter",
 "a"),

("G0160","The Unlocked Cell","I2","skill","Capacity is a reward, not a starting stat.",
 "Completing a set of four permanently unlocks one extra free cell for the rest of the run",
 "Completing a set of four unlocks an extra free cell for the rest of the show only",
 "Every set of four completed unlocks a cell, and every card lost locks one again",
 "a"),

("G0161","The Sanctioned Cheat","K7","skill","You may break placement legality, carefully.",
 "You may place a card anywhere regardless of legality a limited number of times per show",
 "You may place a card anywhere regardless of legality at any time, but each cheat permanently raises the show's goal",
 "You may cheat once per show, and the cheated card is marked and scores nothing",
 "b"),

("G0162","Two Rulebooks","O2","skill","Different parts of the board build differently.",
 "Some columns build by suit and others by alternating colour, marked before you place",
 "Rows build by one rule and columns by another, so a card must satisfy both to score in both",
 "Each grid uses its own stacking rule, drawn at show start",
 "b"),

("G0163","Foundations From Both Ends","B4","skill","Two foundations growing toward each other.",
 "A line may be built from its low end upward or its high end downward, and it scores when the two meet",
 "A line is built from both ends toward the middle, and the card that closes the gap scores double",
 "Two foundations run in opposite directions and a card may join either; completing both pays enormously",
 "b"),

("G0164","The Recall","D2","skill","Cards may come back off the foundation.",
 "A card that has already scored may be taken back off its line and replayed elsewhere",
 "A card that has already scored may be taken back once per show",
 "A scored card may be taken back, but its line then scores nothing for the rest of the show",
 "c"),

("G0165","The Running Count","B1","rule","Score by a running total, cribbage style.",
 "Rule: placements build a running total, and hitting named totals exactly scores along the way",
 "Rule: placements build a running total per line rather than per show",
 "Rule: placements build a running total, and going over resets it to zero and costs a placement",
 "a"),
]

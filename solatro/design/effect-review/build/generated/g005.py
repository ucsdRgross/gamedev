# -*- coding: utf-8 -*-
# Recovered from `gam draft.txt`: mechanics stated parenthetically INSIDE the art
# direction and circus-history sections, which the mining pass skipped wholesale.
# Line numbers are the braindump's own.
ROWS = [

("G0132","The Ledger of Undos","K2","rule","Undo accrual has to account for its own rewinding. (line 807)",
 "Undos accrue every few turns; undoing rewinds the turn counter, and the game tracks what you already banked so a rewind cannot mint you a second one",
 "Undos accrue every few turns, and rewinding past the point one was earned takes it back again",
 "Undos accrue per turn and are banked permanently the moment they are earned, so rewinding never touches them",
 "a"),

("G0133","The Negative","A8","status","Props under it subtract score and add combo. (line 821)",
 "A card at negative rank spawns props that subtract score instead of adding it, and each one still raises the act's combo",
 "A card at negative rank spawns props that subtract score, and they raise the combo by double",
 "A card at negative rank subtracts score itself and raises the combo, but its props behave normally",
 "a"),

("G0134","This Season's Trend","B9","rule","Certain abilities, not hands, pay extra this run. (line 835)",
 "Each run, a few named abilities are trending and score extra whenever they fire",
 "Each run, a few abilities are trending; the trend rotates every town",
 "Each run a few abilities trend, and using a trending ability enough times makes it trend permanently for your profile",
 "b"),

("G0135","The Loose Card","K1","rule","Discard whatever is connected to nothing. (line 845)",
 "Any card with no connection to anything else in its column may be discarded freely, and the column closes up behind it",
 "Any card with no connection to anything else in its column may be discarded freely, and a replacement is drawn onto that column",
 "Any card that is part of no potential meld at all may be discarded freely, whatever its column",
 "c"),

("G0136","The Witch's Gold","G11","skill","Tokens that pay out by detonating. (line 901)",
 "Spawns gold tokens that explode at the end of the act, paying out and destroying whatever cell they sat in",
 "Spawns gold tokens that explode at the end of the act, paying out and damaging their neighbours",
 "Spawns gold tokens that explode at act end unless you have spent them first, so holding them is the gamble",
 "c"),

("G0137","The Dead List","G10","rule","Destroyed cards get a zone of their own. (lines 905, 995)",
 "Rule: destroyed cards go to a dead list rather than vanishing, and effects may reach into it",
 "Rule: destroyed cards go to a dead list you can see but never reach into",
 "Rule: destroyed cards go to a dead list, and one card may be recovered from it per tour at a fame cost",
 "a"),

("G0138","Sleight of Hand","E9","skill","The card does not land where you put it. (line 937)",
 "Cards you place have a chance to land in a different cell than the one you chose, and you are shown where after the fact",
 "Cards you place always land one cell off in a direction this card names, so the offset is learnable",
 "Cards you place land where you chose, but this card silently swaps two already-placed cards each act",
 "b"),

("G0139","The Tire Trick","D4","skill","Hidden in the stack, gone when it is taken apart. (line 975)",
 "While buried, this card is safe from everything; dismantling the stack removes it from play, and rebuilding the stack brings it back",
 "While buried, this card is safe from everything; dismantling the stack destroys it permanently",
 "While buried it is safe and scores nothing; dismantling the stack removes it, and it returns with a bonus when the stack is rebuilt to the same height",
 "c"),

("G0140","The Signed Card","G1","stamp","Every card the game creates comes out as this one. (line 988)",
 "Name a card: the next card any effect creates is that card instead of what it would have made",
 "Name a card: every card any effect creates is that card instead, for the rest of the show",
 "Name a card: when it leaves the board, the next card created anywhere is it, returning",
 "c"),

("G0141","The Triple Somersault","P10","skill","A partner has to catch what goes blind. (line 1092)",
 "A three-stage effect where the middle stage resolves hidden from you, and a partner card must be on the board to complete it or the whole thing fails",
 "A three-stage effect whose middle stage is hidden; without a partner card it completes anyway at a third of its value",
 "A three-stage effect where the middle stage is hidden and the partner must be in the same line, paying enormously if it lands",
 "a"),
]

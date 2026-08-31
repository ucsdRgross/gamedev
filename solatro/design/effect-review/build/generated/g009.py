# -*- coding: utf-8 -*-
# Mined from Hempuli's "A Solitaire Mystery" - 30 solitaires that reimplement
# other games in solitaire form. Cited in the braindump. Hempuli also wrote Baba
# Is You, and Babataire is that idea applied to cards, which is the closest
# published version of this game's rules deck.
SOURCE = "A Solitaire Mystery (Hempuli)"
ROWS = [

("G0166","Babataire","O6","rule","The cards on the board spell the rules.",
 "Rule: rule cards are placed on the grid as readable statements, and rearranging them rewrites what the rules say",
 "Rule: rule cards are placed on the grid and readable, but may not be rearranged once placed",
 "Rule: rule cards sit on the grid as statements, and breaking a statement apart disables that rule until it is reassembled",
 "c"),

("G0167","Time Travel Solitaire","K8","rule","Rewind the board and keep what you learned.",
 "Rule: rewind the grid to an earlier state at will; the deck order is unchanged, so what you saw still holds",
 "Rule: rewind the grid to an earlier state, and the deck reshuffles so knowledge does not carry",
 "Rule: rewind the grid to an earlier state a limited number of times, keeping any cards you gained since",
 "a"),

("G0168","Fork Solitaire","U2","rule","The board branches and you play both.",
 "Rule: at a chosen moment the board forks into two states; you play both and keep the higher score",
 "Rule: at a chosen moment the board forks; you play both and keep the SUM of the two",
 "Rule: the board forks and you play both, but any card destroyed in either branch is destroyed in both",
 "c"),

("G0169","Transmutation Solitaire","G6","rule","Cards become other cards by rule.",
 "Rule: two cards of the same rank placed adjacent transmute into one card of the next rank up",
 "Rule: two cards of the same suit placed adjacent transmute into one card of a different suit",
 "Rule: any two adjacent cards may be transmuted into one whose rank is their sum, at the cost of an act",
 "a"),

("G0170","Tear Solitaire","G7","skill","A card can be torn in two.",
 "Cue: tear one card into two cards of half its rank, placed in different cells",
 "Cue: tear one card into two, one keeping the rank and one keeping the suit",
 "Cue: tear one card into two halves that must be placed in the same line, and reuniting them later restores the original at +2 rank",
 "c"),

("G0171","Limited Move Solitaire","K7","rule","A budget of moves for the whole show.",
 "Rule: the show allows a fixed number of moves in total, and running out ends it",
 "Rule: the show allows a fixed number of moves, and unused moves convert to score at the end",
 "Rule: the show allows a fixed number of moves; each line completed refunds one",
 "c"),

("G0172","Hanoi Solitaire","D1","rule","Only smaller on larger, ever.",
 "Rule: a card may only be stacked on a card of strictly higher rank",
 "Rule: a card may only be stacked on a card of strictly higher rank, and a full descending stack scores as its own meld",
 "Rule: a card may only be stacked on a higher rank, and moving a stack moves only its top card",
 "b"),

("G0173","Binary Solitaire","V3","rule","Only two values exist.",
 "Rule: every card counts as one of only two ranks",
 "Rule: every card counts as one of only two ranks and one of only two suits",
 "Rule: every card counts as one of two ranks, and which two is rerolled each show",
 "a"),

("G0174","Murder Mystery Solitaire","M4","rule","Deduce the fact the board is hiding.",
 "Rule: one hidden fact about the deck is deducible from what you have seen; naming it correctly pays enormously and naming it wrongly costs the show",
 "Rule: one hidden fact is deducible; naming it correctly pays, and a wrong guess costs only an act",
 "Rule: one hidden fact is deducible, and each act reveals one further clue whether you want it or not",
 "b"),

("G0175","Tap Solitaire","I1","rule","Tapping is the only verb.",
 "Rule: a show where cards are never placed, only cued, and scoring comes entirely from what the cues trigger",
 "Rule: a show where placement is free but every card must also be cued once before it can score",
 "Rule: a show where you may either place or cue each turn, never both",
 "c"),

("G0176","Eldritch Invasion","R3","rule","Something is arriving whether you are ready or not.",
 "Rule: an invading force adds one hostile card to the grid each turn, from a fixed edge",
 "Rule: an invading force adds one hostile card each turn from an edge that changes",
 "Rule: an invading force adds cards at an accelerating rate, and clearing a line pushes it back a turn",
 "c"),

("G0177","Garden Solitaire","I4","rule","Cards grow where you plant them.",
 "Rule: a card left in place gains rank each turn it is not disturbed, and is harvested when its line completes",
 "Rule: a card left in place gains rank each turn, and loses it all if moved",
 "Rule: a card left in place gains rank, and a card adjacent to two grown cards grows twice as fast",
 "c"),

("G0178","Cheatdeck Solitaire","F8","rule","The deck is not honest.",
 "Rule: the deck quietly favours cards you do not need, and an effect can expose and correct it",
 "Rule: the deck quietly favours cards you DO need, and the show's goal rises to compensate",
 "Rule: the deck is stacked against you in a way stated up front, so it is a constraint rather than a trick",
 "c"),
]

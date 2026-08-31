# -*- coding: utf-8 -*-
# Mined from Teamfight Tactics and Super Auto Pets. TFT is the reference for
# class-tier synergy, run-permanent choice offers and the interest economy.
# Super Auto Pets is the reference for a LINE whose abilities resolve in stat
# order rather than position order - a resolution rule this game does not have.
SOURCE = "Teamfight Tactics and Super Auto Pets"
ROWS = [

# --- TFT ---------------------------------------------------------------------
("G0211","The Trait Tier","P7","rule","Enough of a class turns a threshold on.",
 "Rule: fielding a threshold number of one class activates a tier bonus for every card of that class, with higher thresholds giving stronger tiers",
 "Rule: fielding a threshold number of one class activates a tier bonus for that class, and only the highest tier reached applies",
 "Rule: class tiers activate at thresholds, and a class one card short of a tier shows how close it is",
 "c"),

("G0212","The Augment Offer","K11","rule","Three permanent choices at fixed points in the run.",
 "Rule: at three fixed points in the run you are offered three run-permanent effects and must take one",
 "Rule: at three fixed points you are offered three run-permanent effects and must take one, with a reroll available for gold",
 "Rule: at three fixed points you are offered three, must take one, and the two refused are removed from the pool for the rest of the run",
 "b"),

("G0213","The Carousel","S5","rule","A shared draft you physically move through.",
 "Rule: at intervals, a rotating ring of cards is offered and you take one by moving to it, with earlier picks going to whoever is furthest behind",
 "Rule: at intervals, a ring of cards is offered and picks go in score order, best first",
 "Rule: at intervals a ring of cards is offered, each carrying an attached stamp, and you take the pair together",
 "c"),

("G0214","Interest","J3","rule","Held gold earns a return each show.",
 "Rule: you earn one gold per fixed amount banked at each show's end, capped",
 "Rule: you earn one gold per fixed amount banked, uncapped",
 "Rule: you earn interest on banked gold, and the cap rises each time you finish a show without spending",
 "a"),

("G0215","The Streak","I4","rule","Winning or losing in a row both pay.",
 "Rule: consecutive wins pay a rising bonus, and so do consecutive losses, so committing to either is a strategy",
 "Rule: consecutive wins pay a rising bonus; losses pay nothing",
 "Rule: consecutive wins pay a rising bonus and consecutive losses pay a larger one, so a deliberate slump is a real line of play",
 "c"),

("G0216","Three Of A Kind Merges","G3","rule","Copies combine into something stronger.",
 "Rule: three copies of the same card merge automatically into one stronger version, and three of those merge again",
 "Rule: three copies merge into one stronger version, once only, with no second tier",
 "Rule: three copies merge into one stronger version, and you choose when rather than it happening automatically",
 "a"),

("G0217","The Shared Pool","F8","rule","Taking a card denies it to everything else.",
 "Rule: the card pool is finite and shared with the run's rivals, so taking a card removes it from what they can draw",
 "Rule: the pool is finite and shared, and you can see how much of each card is left",
 "Rule: the pool is finite; cards you destroy return to it, and cards you keep do not",
 "b"),

("G0218","Front And Back","C13","rule","The row a card sits in decides what it does.",
 "Rule: cards in the grid's front rows take hazards first and cards in the back rows score more, so placement is a risk trade",
 "Rule: cards in the front rows take hazards first; back rows are otherwise identical",
 "Rule: front rows take hazards first and score less; the boundary between front and back moves each act",
 "a"),

# --- Super Auto Pets ---------------------------------------------------------
("G0219","Resolution By Rank","H8","rule","Effects fire in rank order, not board order.",
 "Rule: when several effects trigger at once, they resolve in descending rank order rather than by position",
 "Rule: when several effects trigger at once they resolve in descending rank order, ties broken by which was placed first",
 "Rule: when several effects trigger at once, they resolve in ascending rank order, so the smallest card acts first",
 "b"),

("G0220","The Faint Trigger","X1","rule","Dying is a trigger like any other.",
 "Rule: a destroyed card fires a faint effect if it has one, resolving after the destruction",
 "Rule: a destroyed card fires a faint effect, and faint effects resolve before anything else that turn",
 "Rule: a destroyed card fires a faint effect, and a card destroyed by your own effects fires it twice",
 "c"),

("G0221","The Advancing Line","E4","rule","A gap in the line closes toward one end.",
 "Rule: when a card leaves a line, everything behind it shifts one step to close the gap",
 "Rule: when a card leaves a line, everything behind it shifts to close the gap, and each card that moves triggers",
 "Rule: when a card leaves a line, the gap stays open and can only be filled from the Entrance",
 "b"),

("G0222","Head To Head","U5","rule","Your line is matched against theirs, position by position.",
 "Rule: in a rival show, your line is compared to theirs card by card from one end, and the winner of each pairing scores",
 "Rule: in a rival show, your whole line's total is compared to theirs, not card by card",
 "Rule: in a rival show, your line is compared card by card, and a card that beats its opposite carries the surplus to the next pairing",
 "c"),
]

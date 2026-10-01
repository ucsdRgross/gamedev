# -*- coding: utf-8 -*-
# Family AE, Trading-card tropes. (eid, name, cls, slot, mechanic, a, b, c, default)
SOURCE = 'trading card games'
ROWS = [

('CI0801', 'Booster Pack', 'AE8', 'consumable',
 'A sealed pack of random cards, torn open to see what you got.',
 'Renames Q1195 (The Showbag): Consumable pack: four random Commons, one of them guaranteed to be a class you name',
 'Consumable: tear it open at an Entrance refill: five random cards are dealt beside the Entrance as five extra slots, ghosts that leave when the show ends, and one of them, your choice, stays in your deck',
 'Consumable: tear it open over an empty row or column: five random ghost cards are dealt into it in order and score as the hand they make, and they leave when the show ends',
 'b'),

('CI0802', 'Holographic', 'AE8', 'stamp',
 'The shiny foil version, whose picture changes as you tilt it.',
 "Tilt it and the picture changes: for melds the wearer is its printed card in rows, and in every other line it is the card its cell's mark was copied from",
 'As (a), the second picture being a card of your deck you choose when the hat is put on, whatever mark it sits on',
 'As (a), and in those other lines the wearer fires the talent of the card its mark was copied from instead of its own',
 'a'),

('CI0803', 'First Edition', 'AE8', 'stamp',
 'The first printing, the one collectors pay more for.',
 "The first time each show the wearer's talent fires, it fires at level 2, wherever the wearer sits",
 'As (a), for its first firing of each Entrance refill',
 'As (a), for its first firing in a line of each kind, row, column, diagonal and stack, each show',
 'a'),

('CI0804', 'Mint Condition', 'AE8', 'skill',
 'Never played with, never marked: worth the most until the first scuff.',
 'While no effect has moved, covered, stacked on, debuffed or changed it this run it is mint, and every line it scores in pays double into its bucket; the first effect that touches it ends this for the run',
 'As (a), but it is mint again at each show start',
 'As (a), paying triple and graded down a step at a time: the first touch drops it to double and the second to nothing',
 'b'),

('CI0805', 'Card Sleeve', 'AE8', 'stamp',
 'A clear sleeve that keeps a card exactly as it is.',
 'Renames Q0658 (Iron Body): Immune to the first destruction or debuff that targets it each show',
 "The sleeve takes the hit: each move, change, debuff or removal an effect or hazard aims at the wearer is spent on the sleeve instead and pays the wearer's rank into the special bucket, up to three a show",
 "The sleeve keeps what is inside as it is now: any change an effect makes to the wearer's rank or suit for the show is kept for the run",
 'a'),

('CI0806', 'Tap', 'AE8', 'skill',
 'Turn a card sideways to use it; it stays used until it is straightened. Tap is your own word for a cue; this one taps a card that has none.',
 'Cue at an Entrance refill, before you place: tap one card on its grid: it pays its rank into the bucket you choose and is Exhausted, scoring nothing, until the next Entrance refill',
 'As (a), tapping for the talent instead: the tapped card fires its talent once more now',
 'The untap step: at each Entrance refill every Exhausted card on its grid is straightened and is no longer Exhausted',
 'a'),

('CI0807', 'Mulligan', 'AE8', 'skill',
 'Throw back a bad opening hand and draw again, one card short.',
 'Renames Q0729 (The Second Roll): Cue once per show: discard any number of entrance cards and refill only those slots',
 'Cue, before the first placement of a show: throw the opening Entrance back to the bottoms of its stocks and deal again with one slot left empty, as many times as you like, one more slot empty each time',
 'As (b), dealt in full each time, after which you send one card of the new Entrance to the bottom of its stock for each mulligan taken',
 'b'),

('CI0808', 'Graveyard', 'AE8', 'skill',
 'The pile where used-up cards go, and which some cards can reach back into.',
 'Renames Q0510 (The Dead List): Destroyed cards go to a dead list rather than vanishing, and effects may reach into it',
 'Every line through its cell pays a step into its bucket for each card in the discard pile',
 'As (b), and cue once per show: dig one card of the discard pile you choose up to the top of the stock you choose',
 'a'),

('CI0809', 'Counterspell', 'AE8', 'skill',
 'The answer held back in hand: it cancels a spell as it is cast.',
 'Renames Q0544 (The Calm Voice): Once per run, negate a disaster or boss effect, and the next boss effect of the same kind is negated too',
 'While it waits in the Entrance this refill you may spend it to counter an effect or hazard as it fires: that does nothing this time, and this card goes to the discard pile, back in the deck next show',
 'As (b), and it replaces itself: its slot turns up the next card of its stock at once',
 'b'),

('CI0810', 'Trap Card v2', 'AE8', 'skill',
 'Set face down, it springs the moment something moves beside it.',
 'Renames Q0139 (The Secret): Place this card face down naming a condition; when the condition is met the card flips and its effect fires unprompted',
 "Set face down, it counts as a blank for melds until another card is placed orthogonally next to it, when it springs: it turns up as a copy of that card's rank and suit for the show",
 "As (b), taking that card's talent for the show as well",
 'a'),

('CI0811', 'Energy', 'AE8', 'skill',
 'A card tucked under another to power what it does.',
 "It is attached, not placed: it goes beneath any card on its grid, lifting that card one height, and works though covered: each time the card above it fires its talent, it fires once more for every Energy beneath it, and the lifted card's lines are read at its new height",
 "As (a), powering the cue instead: a card's cue may be used once more each Entrance refill for every Energy beneath it",
 'As (a), but the power is spent: each extra firing sends one Energy from beneath the card to the discard pile, and the card drops one height',
 'a'),

('CI0812', 'Evolution', 'AE8', 'skill',
 'Laid on top of its lesser form, a card becomes the stronger one.',
 'Any card on its grid may evolve: placed on top of a card of its own suit ranked one below it, whatever the stacking rules say, its talent is at level 2 for as long as it stays there, as if it sat on a mark it matched',
 'As (a), the lesser form needing only the rank one below, in any suit',
 'As (a), and a stack of three stages scores as a line at once, without waiting for five',
 'a'),

('CI0813', 'Non-Fungible Card', 'AE8', 'skill',
 'One of a kind, it says, and worth a little less every time anyone looks.',
 'While no other card on its grid shares its rank it is one of a kind: each line through its cell pays its rank again into the special bucket, and each such payout costs it 1 rank for the show, to no lower than 1',
 'As (a), holding its value: it loses no rank, but no effect can copy it, raise it or stack a card on it',
 'As (a), and you may sell before it falls further: cue once per show to send it to the discard pile, its cell empty again, paying its rank three times into the special bucket',
 'a'),
]

# eid -> level 2: a str, a 3-tuple, "SUIT", "RANK", or None
LEVEL2 = {
 'CI0801': None,
 'CI0802': 'Each line takes whichever of its two pictures makes the better hand',
 'CI0803': 'The first firing each show of every talent in its lines is at level 2 too',
 'CI0804': 'While it is mint, every card in its lines that no effect has touched this show is mint too',
 'CI0805': ('A hit it prevents mints two rank-1 token cards, which are ghosts', 'The sleeve also covers the cards orthogonally next to the wearer, each hit it takes for them paying their rank', 'It also keeps a talent or hat an effect lends the wearer for the show'),
 'CI0806': ('A card tapped in its lines untaps the moment a line through it completes, and scores in it', 'A card tapped in its lines untaps the moment a line through it completes, and scores in it', 'It also straightens the Exhausted card you choose each time a line through its cell scores'),
 'CI0807': ('The discarded cards go to the bottom of their stocks instead of the discard pile', 'The first mulligan of each show is free: the Entrance is dealt in full', 'The first mulligan of each show sends no card back'),
 'CI0808': ('Once per show while it sits on its own mark, return one card from the dead list to the Entrance slot you choose', 'Lines through its cell pay the step into the bucket you choose', 'The dug card may go straight into an empty Entrance slot instead'),
 'CI0809': ('It negates two', 'Placed on a mark it matches instead, it counters once from the grid, and stays where it is', 'Placed on a mark it matches instead, it counters once from the grid, and stays where it is'),
 'CI0810': ('When it flips, it fires once more for each card in its lines that sits on its own matching mark', 'It may spring again: each later card placed next to it may replace what it copies, your choice', 'It may spring again: each later card placed next to it may replace what it copies, your choice'),
 'CI0811': 'Attached on a mark it matches, it powers the cards orthogonally next to its stack as well',
 'CI0812': 'Once per Entrance refill an evolved stack in its lines may move to an empty cell whose mark its top card matches, every complete line it lands in scoring',
 'CI0813': 'It counts as one of a kind while no other card in its lines shares its rank, whatever the rest of the grid holds',
}

# eid -> the flag the owner sees
FLAGS = {
 'CI0805': 'Protection is well covered live (Iron Body, Kuroko, The Mime, Digital), so the rename is the recommendation; (c) is The Sweet Tooth on one card',
 'CI0809': "Nope, Defuse and Counterspell all cancel, split by where they act from: the grid by cue, a consumable, the Entrance; its window is its own refill, since the Entrance refills only when every slot is empty; (a) carries The Calm Voice's own level 2, which is a count",
 'CI0812': 'the default stacking rule already allows a card one rank apart on a different suit, so (b) is that rule plus the unlock; (a) is the stack the default forbids',
 'CI0811': 'lifting the powered card takes it out of its height-0 lines, so the power reaches only talents that fire off something other than those lines; the alternative is the shared cell of The Contortionist (Q0296), which is then a near-duplicate',
}

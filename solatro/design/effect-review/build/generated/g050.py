# -*- coding: utf-8 -*-
# Family AE, packs, minigames and the prop trunk. (eid, name, cls, slot, mechanic, a, b, c, default)
SOURCE = 'the braindump'
ROWS = [

('CI1101', 'Themed Talent Packs', 'AE11', 'structure',
 'A talent pack drawn from one source only: a board-game pack, a casino pack, a village pack.',
 'Each class of this family is a talent pack: a pack node names its theme, and its cards and rerolls come only from that class',
 'As (a), and a pack node shows its theme on the map before you travel, so a route can be planned toward the theme you are building',
 'Each pack deals from two named classes, and a card from the class you already hold most of is more likely',
 'b'),

('CI1102', 'The Prop Trunk', 'AE11', 'structure',
 'Why a circus deck holds a Powder Keg: the frame for the cards from everywhere.',
 "They are props: every card of this family is billed as a prop pulled from the troupe's trunk, and keeps its real-world name",
 'They are the Human Card Index act: a performer who produces any card called for, so each card is billed by its real-world name and the act is the reason it is here',
 'No frame: the cards carry their real-world names, and the circus is only the stage they are played on',
 'b'),

('CI1103', 'Fungible', 'AE11', 'type',
 'Identical tokens are one pile: a fungible card placed onto its twin merges instead of stacking.',
 "A fungible card placed onto a fungible card of the same name merges into it: one card, the ranks summed, capped at King, keeping the lower card's suit",
 'As (a), but the merged rank may pass King; past King it counts as a King and pays the excess as flat points into the special bucket each time it scores',
 'As (a), and the merged card remembers how many cards made it, and counts as a stack of that height for a height line',
 'a'),

('CI1110', 'Charge-back', 'AE11', 'structure',
 'May an effect take points back out of a bucket? Credit Card, Pawn Ticket and Racing Form in this family charge one.',
 'Yes, floored at 0: a charge that would take a bucket below 0 empties it, and an empty bucket adds nothing to the product',
 'Yes, but only the points that effect itself paid in: a charge can undo its own payout and never touch another line',
 'No: a cost is paid in something else, a card to the discard pile, a skipped refill or a lost combo step, and the charging options are rewritten to it',
 'a'),

('CI1104', 'Anything Goes', 'AE11', 'structure',
 'A hand of every card you can think of: the Uno card played in the poker game.',
 'A starting deck of 52 cards drawn at random from this family, each dealt a random suit and rank',
 'The standard 52, where every card also carries a random talent from this family',
 'The standard 52, and after every show one card of it is swapped for a random card of this family',
 'b'),

('CI1105', 'The Dice Tray', 'AE11', 'structure',
 'An effect that rolls throws real dice across the screen; more cards add dice and new faces.',
 'An effect that rolls throws a die onto a tray beside the grid and reads its face; a card may add a die, or replace a face with one that fires an effect',
 'As (a), but the dice are thrown over the grid, and each die also fires the card it stops on',
 'A tray of five dice rolled at every Entrance refill and read as a poker hand of its own into the special bucket; cards add faces and re-rolls',
 'a'),

('CI1106', 'The Coin Flip', 'AE11', 'structure',
 'Every effect with odds flips a real coin; cards change the coin.',
 'An effect with a chance flips a coin on screen; a card may add a two-headed coin, a weighted coin, or a coin whose faces fire effects',
 'As (a), and a flip may be called before it lands: a right call pays a step into the special bucket',
 'As (a), with several coins flipped at once when several chances fire together, so a lucky run lands as one shower',
 'a'),

('CI1107', 'The Prize Wheel', 'AE11', 'structure',
 'A wheel spun on screen; cards add wedges.',
 'An effect that spins turns a prize wheel whose wedges are effects; a card adds a wedge, and a card may remove one',
 'As (a), and a wedge may be widened by playing its card again, so a wheel can be built to land where you want',
 'The wheel spins once per show, after the first line of each kind; its wedges are the talents of the cards on the grid',
 'b'),

('CI1108', 'The Pachinko Board', 'AE11', 'structure',
 'A ball dropped through pins into buckets; cards add pins and buckets.',
 'A pachinko board beside the grid: an effect that drops a ball sends it through the pins into a bucket, and each bucket is an effect; cards add pins and buckets',
 'The grid is the board: a ball dropped at the top of a column bounces off the cards it hits, firing each, and lands in a bucket under a column',
 'As (b), but the buckets are the three scoring buckets: a ball landing under a column pays the card it last touched into that bucket',
 'b'),

('CI1109', 'The Blackjack Table', 'AE11', 'structure',
 'A blackjack side game dealt from your own deck.',
 'A table beside the grid deals blackjack from your own stocks once per show; a win pays into the special bucket, and the cards used go back to their stocks',
 'As (a), but the cards you hit with are spent from the Entrance, so the side game competes with the grid for cards',
 'Blackjack is a line: a line whose ranks sum to exactly 21 pays as a blackjack, and a line past 21 busts and pays nothing',
 'a'),
]

# eid -> level 2: a str, a 3-tuple, "SUIT", "RANK", or None
LEVEL2 = {
 'CI1101': None,
 'CI1102': None,
 'CI1103': None,
 'CI1110': None,
 'CI1104': None,
 'CI1105': None,
 'CI1106': None,
 'CI1107': None,
 'CI1108': None,
 'CI1109': None,
}

# eid -> the flag the owner sees
FLAGS = {
 'CI1105': 'the braindump says the minigames are likely out of scope: scope creep',
 'CI1106': 'the braindump says the minigames are likely out of scope: scope creep',
 'CI1107': 'the braindump says the minigames are likely out of scope: scope creep',
 'CI1108': 'the braindump says the minigames are likely out of scope: scope creep',
 'CI1109': 'the braindump says the minigames are likely out of scope: scope creep; (c) overlaps Twenty-One in class AE4',
 'CI1103': 'Ore, Coin, Poker Chip, Sand, Stick and Wood (b) merge as Fungible says, so rejecting this leaves six rows without a merge rule',
}

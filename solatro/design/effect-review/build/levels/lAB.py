# -*- coding: utf-8 -*-
# Family AB: (qid, eid, verdict, level2, why) - schema in ../levels.py

ROWS = [
('Q1679', 'MK0001', 'REWORK', 'A miss in its own lines does not reset the streak', ''),
('Q1680', 'MK0002', 'OK', ('It is also copied onto the cell mirrored across its row', 'The mark is copied to two cells instead of one', 'The mark is copied to two cells instead of one'), ''),
('Q1681', 'MK0004', 'OK', 'One card of the line may miss', ''),
('Q1682', 'MK0005', 'REWORK', 'Two hits in a row are enough', '(c) could never end: no card can miss while every card counts as matching'),
('Q1683', 'MK0003', 'OK', "The relay also passes the first card's level 2 to the second card for that scoring", ''),
('Q1684', 'MK0006', 'REWORK', 'Diagonal shapes count too', 'no four-card hand exists unless Q0108 supplies one'),
('Q1685', 'MK0009', 'REWORK', ('The named property may be changed at each refill', 'The wearer may name three properties', "The wearer's level 2 lasts until the next refill, even after it leaves its mark"), 'it is a rule about level 2 itself; absorbs Q1422'),
('Q1686', 'MK0008', 'OK', 'Its options are its level 2; at level 1 it does nothing', ''),
('Q1687', 'MK0007', 'OK', 'Its options give both levels', ''),
('Q1688', 'MK0010', 'WEAK', 'Its options are its level 2; at level 1 it does nothing', 'fires only when another effect moves or stacks a card'),
('Q1689', 'MK0013', 'WEAK', ('The likeness is also left on the cells beside it', 'The likeness is also left on the cells beside it', 'The next hit on each likeness pays double'), 'fires only when another effect moves or stacks a card'),
('Q1690', 'MK0016', 'WEAK', ('Its mark cannot be rerolled, swapped or moved, and every line through its cell adds +1 to the multiplier', 'Its lines add +1 to the multiplier', 'Each card in the stack adds +1 to the multiplier of the lines through it'), 'level 1 fires only when another effect moves a card or a mark; the +1 multiplier is the part that works alone'),
('Q1691', 'MK0014', 'DUP', None, 'Q1436'),
('Q1692', 'MK0018', 'DUP', None, 'Q1450'),
('Q1693', 'MK0015', 'WEAK', 'The inherited hit also carries level 2', 'fires only when another effect moves or stacks a card'),
('Q1694', 'MK0011', 'REWORK', ('It counts as hitting on two properties', 'It agrees on two properties', "The next card stacked on it pays the rank match and this card's talent mult"), '(a) left a rewritten mark under a card that nothing moves'),
('Q1695', 'MK0017', 'REWORK', None, ''),
('Q1696', 'MK0012', 'OK', ('The diagonal neighbours are re-dealt too', 'It re-deals two cells of your choice', 'The diagonal neighbours are re-dealt too'), ''),
('Q1697', 'MK0019', 'OK', "The called cell's mark is re-dealt from the top card of a stock you choose, so the call is one you can make good", ''),
('Q1698', 'MK0020', 'OK', 'Cards in its lines that miss shove their marks as the wearer would', ''),
('Q1699', 'MK0021', 'OK', 'A hit anywhere in a line through its cell pays both ends of that line', ''),
]

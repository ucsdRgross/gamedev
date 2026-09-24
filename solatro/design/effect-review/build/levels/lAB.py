# -*- coding: utf-8 -*-
# Family AB: (qid, eid, verdict, level2, why) - schema in ../levels.py

ROWS = [
('Q1679', 'MK0001', 'OK', 'A miss in its own lines does not reset the streak', ''),
('Q1680', 'MK0002', 'OK', 'The mark is copied to two cells instead of one', ''),
('Q1681', 'MK0004', 'OK', 'One card of the line may miss', ''),
('Q1682', 'MK0005', 'OK', 'Two hits in a row are enough', ''),
('Q1683', 'MK0003', 'OK', "The relay also pays the first card's talent mult", ''),
('Q1684', 'MK0006', 'OK', 'Diagonal shapes count too', ''),
('Q1685', 'MK0009', 'OK', 'NONE', 'it is a rule about level 2 itself'),
('Q1686', 'MK0008', 'OK', 'NONE', 'it is a rule about level 2 itself'),
('Q1687', 'MK0007', 'OK', 'NONE', 'its options are written as its two levels'),
('Q1688', 'MK0010', 'OK', 'NONE', 'it is a rule about level 2 itself'),
('Q1689', 'MK0013', 'OK', ('The likeness is also left on the cells beside it', 'The likeness is also left on the cells beside it', 'The next hit on each likeness pays double'), ''),
('Q1690', 'MK0016', 'OK', ('Its lines add +2 instead of +1', 'Its lines add +1 to the multiplier', 'Each card in the stack adds +2 instead of +1'), ''),
('Q1691', 'MK0014', 'OK', None, ''),
('Q1692', 'MK0018', 'OK', None, ''),
('Q1693', 'MK0015', 'OK', 'The inherited hit also carries level 2', ''),
('Q1694', 'MK0011', 'OK', 'A rewritten mark counts as hit at once', ''),
('Q1695', 'MK0017', 'OK', None, ''),
('Q1696', 'MK0012', 'OK', ('The diagonal neighbours are re-dealt too', 'It re-deals two cells of your choice', 'The diagonal neighbours are re-dealt too'), ''),
]

# -*- coding: utf-8 -*-

# Family AD: new effects proposed by the design review. (eid, name, cls, slot, mechanic, a, b, c, default)
SOURCE = "the design review"
ROWS = [

('ND0001',
 'The Four Corners',
 'AD1',
 'skill',
 'The X of the grid is a line.',
 'When the four corner cells and the centre are all filled, they score as a line into the special bucket',
 'The four corners alone score as a four-card hand into the special bucket',
 'The X scores as a line into the special bucket, and each corner card counts as adjacent to the other three',
 'a'),

('ND0002',
 'The Crossing',
 'AD1',
 'skill',
 'A matched card is a hub.',
 'When a card sits on a mark it matches, its row and column together pay a second hand, the best five of their nine cards, into the special bucket',
 'When a card sits on a mark it matches, the best five of its row and column pay a second hand into the bucket of your choice',
 'When a card sits on a mark it matches and both its row and column are complete, the best five of their nine cards pay a second hand into the special bucket',
 'a'),

('ND0003',
 'The Full Bill',
 'AD1',
 'skill',
 'Breadth across the geometry.',
 '+1 combo the first time each show a line of each kind scores - row, column, diagonal, height - and +2 more when all four have',
 '+1 combo per kind, and the +2 fires again each Entrance refill in which all four kinds score',
 '+1 combo per kind; while any kind has not scored this show, lines of that kind pay double',
 'c'),
]

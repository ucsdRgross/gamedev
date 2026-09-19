# -*- coding: utf-8 -*-
"""Condense the crawled wiki pages into per-mod effect text and split into subagent chunks.
Keeps: page title, section headings, table rows with a description-length cell, and short prose
lines that describe a mechanic. Drops: infobox rows, nav, cost/rarity-only rows, external-link lists
(those are handled by the README pass and appended as `## README` sections)."""
import io, os, re, json, glob
SCR = os.path.dirname(os.path.abspath(__file__))
PAGES = os.path.join(SCR, 'wiki', 'pages')
plan = json.load(open(os.path.join(SCR, 'wiki', 'plan.json')))
SKIP_MODS = {'Cryptid', 'Cryptlib', 'Cryptposting', 'Steamodded', 'Lovely', 'Balatro Mod Manager',
             'DebugPlus', 'DebugPlusPlus', 'Talisman', 'Multiplayer', 'JokerDisplay', 'ModMenuinOptions'}
INFOBOX = re.compile(r'^(Author\(s\)|Source|Creation Date|Version|Dependencies|Mod ID|Prefix|Discord|Download|'
                     r'Last Updated|Requires|Conflicts|Category|Categories|Links?|Website|Contributors?)\b', re.I)

def slug(t): return re.sub(r'[^A-Za-z0-9._-]+', '_', t)
# rows that cannot be built here whatever their trigger: money, shops, held hand, tags
DEAD = re.compile(r'\$\s?-?\d|\bsell\b|sold|sell value|\bshop\b|reroll|booster|voucher|held in hand|'
                  r'\bin hand\b|hand size|joker slot|consumable slot|\binterest\b|\bmoney\b|\bbuy\b|'
                  r'purchas|\bcost\b|\btag\b|\btags\b|skip(ped|ping)? (a |the )?blind|dollars|\bwallet\b|\bdebt\b', re.I)

def condense(text):
    out = []
    for line in text.split('\n'):
        s = line.strip()
        if not s: continue
        if s.startswith('# ') or s.startswith('## '):
            if 'External links' in s: break
            out.append(s); continue
        if s.startswith('|'):
            cells = [c.strip() for c in s[1:].split('|')]
            if any(len(c) >= 25 for c in cells):
                # drop pure cost/rarity/unlock cells to save space
                keep = [c for c in cells if not re.fullmatch(r'\$?-?\d+|Common|Uncommon|Rare|Legendary|Exotic|Epic|'
                                                             r'[+X^]?[cm$!#\[\]/\w]{1,6}', c)]
                out.append('| ' + ' | '.join(keep))
            continue
        if INFOBOX.match(s): continue
        if len(s) >= 30 and not s.startswith('http'):
            out.append(s)
    return '\n'.join(out)

mods = []
for m, info in plan.items():
    if m in SKIP_MODS: continue
    parts = []
    for pg in info['pages']:
        fn = os.path.join(PAGES, slug(pg) + '.txt')
        if not os.path.exists(fn): continue
        t = io.open(fn, encoding='utf-8').read()
        c = condense(t)
        if c.count('\n') >= 1: parts.append(c)
    readme = os.path.join(SCR, 'wiki', 'readme', slug(m) + '.txt')
    if os.path.exists(readme):
        parts.append('## README (from the mod\'s own repository)\n' + io.open(readme, encoding='utf-8').read())
    seen = set(); kept = []
    for l in '\n'.join(parts).split('\n'):
        if l.startswith('|'):
            if DEAD.search(l): continue
            key = re.sub(r'\(Currently[^)]*\)', '', l).strip().lower()
            if key in seen: continue
            seen.add(key)
        kept.append(l)
    body = '\n'.join(kept)
    rows = sum(1 for l in body.split('\n') if l.startswith('|'))
    mods.append((m, rows, body))

json.dump({m: r for m, r, b in mods}, open(os.path.join(SCR, 'wiki', 'rows_per_mod.json'), 'w'), indent=0)
total = sum(len(b) for _, _, b in mods)
print('mods', len(mods), 'total chars', total)
LIMIT = 90000
chunks, cur, size = [], [], 0
def split_body(m, b):
    if len(b) <= LIMIT: return [(m, b)]
    parts, buf = [], []
    for line in b.splitlines():
        buf.append(line)
        if sum(len(x) + 1 for x in buf) > LIMIT:
            parts.append(buf); buf = []
    if buf: parts.append(buf)
    return [(m + ' (part %d of %d)' % (i + 1, len(parts)), chr(10).join(p)) for i, p in enumerate(parts)]
for m, r, b in mods:
    for mm, bb in split_body(m, b):
        if size + len(bb) > LIMIT and cur:
            chunks.append(cur); cur, size = [], 0
        cur.append((mm, bb)); size += len(bb)
if cur: chunks.append(cur)
os.makedirs(os.path.join(SCR, 'chunks'), exist_ok=True)
for f in glob.glob(os.path.join(SCR, 'chunks', '*.txt')): os.remove(f)
for i, ch in enumerate(chunks, 1):
    io.open(os.path.join(SCR, 'chunks', 'chunk%02d.txt' % i), 'w', encoding='utf-8').write(
        '\n\n'.join('=' * 20 + ' MOD: ' + m + ' ' + '=' * 20 + '\n' + b for m, b in ch))
    print('chunk%02d' % i, len(ch), 'mods', sum(len(b) for _, b in ch), 'chars')

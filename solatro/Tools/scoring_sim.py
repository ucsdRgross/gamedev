"""Solatro scoring & goal-math simulation harness.

TWO MODELS LIVE HERE, and only one of them is the shipped game.

  * THE GRID MODEL (--grid-goals) is the live one: the poker-patience economy of
    PLAN.md 1.6 -- grids of cells, a placement scoring every complete line through
    it, three buckets per grid multiplied together, and one show-wide combo applied
    at display time. Its section carries its own simplifications banner.
  * THE TABLEAU MODEL (everything else) is RETIRED. It ports the old
    Scripts/scoring.gd act economy: rows and columns summed into an act payout of
    R x C, boards built by an arrangement oracle, submits. Game.apply_act_score()
    has no caller in product code any more. It is kept for the calibration history
    it produced, and every one of its entry points prints a RETIRED banner first.
    A goal curve fitted with it is a curve fitted to a game nobody plays.

The ScoreModel/PokerHands port at the top is shared: line evaluation did not change
with the board, and both models call score_line.

CLI (all runs are deterministically seeded; paired seeds across settings):
  py scoring_sim.py --grid-goals          LIVE: grid goal ladder, curve fit, run validation
  py scoring_sim.py --grid-show 20        LIVE: one show at N cards, board and buckets dumped
  py scoring_sim.py --baseline            RETIRED tableau: the plan-2 baseline tables
  py scoring_sim.py --ofat all            RETIRED tableau: one-factor-at-a-time sweeps
  py scoring_sim.py --lhs 300             RETIRED tableau: Latin-hypercube sample
  py scoring_sim.py --run-sim V2A         RETIRED tableau: full 12-node run simulation
  py scoring_sim.py --final               RETIRED tableau: the fit that produced 130 / 4.2
Options: --trials N, --q Q (the difficulty quantile), --skill F, --csv out.csv, --seed S
"""
import argparse
import csv
import math
import os
import random
import statistics as st
import sys
from collections import Counter

# ============================================================================
# ScoreModel port — MUST mirror Scripts/scoring.gd ScoreModel exactly.
# ============================================================================
HIGH_CARD_SCORE = 1
STRAIGHT_PER_CARD = 2
FLUSH_PER_CARD = 2
FULL_FLUSH_MULT = 2
MULTI_FLUSH_COPY_MULT = 2
HOUSE_MULT = 1.5
ESC_STEP = 0.5
MIN_FLUSH_CARDS = 5
WRAP_TOP = 13.0


def house_base(s):
    t, p = 3 * s, 2 * s
    return int((t * (t - 1) + p * (p - 1)) * HOUSE_MULT)


def straight_len_esc(n):
    return 1.0 + ESC_STEP * max(0.0, n / WRAP_TOP - 1.0)


def base_per_copy(types, n):
    if 'HOUSE' in types:
        return house_base(int(n / 5.0))
    if 'STRAIGHT' in types:
        return int(STRAIGHT_PER_CARD * n * straight_len_esc(n))
    if 'XKIND' in types:
        return n * (n - 1)
    if 'FLUSH' in types:
        return FLUSH_PER_CARD * n
    return HIGH_CARD_SCORE


def copy_escalation(types, m):
    if m <= 1:
        return 1.0
    if 'XKIND' in types:
        return 1.0 + ESC_STEP * max(0, m - 2)
    return 1.0 + ESC_STEP * (m - 1)


def final_score(types, m, n):
    base = base_per_copy(types, n)
    has_struct = ('XKIND' in types) or ('STRAIGHT' in types) or ('HOUSE' in types)
    if 'FLUSH' in types and not has_struct:
        return m * base
    plain = int(base * m * copy_escalation(types, m))
    if 'ALLSUIT' in types:
        return plain * FULL_FLUSH_MULT
    if 'FLUSH' in types and 'MULTI' in types:
        return max(plain, m * base * MULTI_FLUSH_COPY_MULT)
    return plain


# ============================================================================
# Line evaluator — best single Result per row/column (mirrors PokerHands).
# Card = (rank:int, suit:int, is_skill:bool, is_prop:bool)
# ============================================================================
def all_same_suit(cards):
    return len(set(s for _, s in cards)) == 1


def bmax(a, b):
    """max by score only (tags are not comparable across archetypes)."""
    return b if b[0] > a[0] else a


def eval_sets_houses(cards):
    """Returns (score, tag). tag identifies the winning meld for uniqueness counting:
    single sets carry their rank (pair of 2s != pair of 3s); multi-sets and houses
    are identified by (archetype, size, copies)."""
    best = (0, None)
    clusters = sorted(Counter(r for r, _ in cards).values(), reverse=True)
    clusters = [c for c in clusters if c >= 2]
    if not clusters:
        return best
    by_rank = {}
    for r, s in cards:
        by_rank.setdefault(r, []).append((r, s))
    big_rank = max(by_rank, key=lambda r: len(by_rank[r]))
    big = by_rank[big_rank]
    bn = len(big)
    if bn >= 2:
        sc = final_score(['XKIND'], 1, bn)
        if bn >= MIN_FLUSH_CARDS and all_same_suit(big):
            sc = max(sc, final_score(['XKIND', 'FLUSH', 'ALLSUIT'], 1, bn))
        best = bmax(best, (sc, ('XKIND', bn, 1, big_rank)))
    for cand in sorted(set(clusters)):
        copies = [c for c in clusters if c >= cand]
        m = len(copies)
        if m < 2:
            continue
        best = bmax(best, (final_score(['XKIND', 'MULTI'], m, cand),
                          ('XKIND', cand, m, None)))
    maxc = clusters[0]
    for s in range(1, maxc // 3 + 1):
        tn, pn = 3 * s, 2 * s
        work = sorted(clusters, reverse=True)
        houses = 0
        while True:
            work.sort(reverse=True)
            ti = max(range(len(work)), key=lambda i: work[i])
            if work[ti] < tn:
                break
            pi = None
            for i in range(len(work)):
                if i == ti or work[i] < pn:
                    continue
                if pi is None or work[i] < work[pi]:
                    pi = i
            if pi is None:
                break
            work[ti] -= tn
            work[pi] -= pn
            houses += 1
        if houses >= 1:
            best = bmax(best, (final_score(
                ['HOUSE'] + (['MULTI'] if houses > 1 else []), houses, 5 * s),
                ('HOUSE', 5 * s, houses, None)))
    return best


def eval_straights(cards):
    """Returns (score, tag); tag = ('STRAIGHT', length, copies, None)."""
    if len(cards) < 5:
        return (0, None)
    counts = Counter(r for r, _ in cards)
    if len(counts) < 5:
        return (0, None)
    runs = []
    rem = dict(counts)
    while True:
        best_len = 0
        for start in list(rem):
            if rem.get(start, 0) == 0:
                continue
            l, pos, r2 = 0, start, dict(rem)
            while r2.get(pos, 0) > 0:
                r2[pos] -= 1
                l += 1
                pos = 1 if pos == int(WRAP_TOP) else pos + 1
            best_len = max(best_len, l)
        if best_len < 5:
            break
        for start in list(rem):
            l, pos, r2 = 0, start, dict(rem)
            path = []
            while r2.get(pos, 0) > 0:
                r2[pos] -= 1
                l += 1
                path.append(pos)
                pos = 1 if pos == int(WRAP_TOP) else pos + 1
            if l == best_len:
                for p in path:
                    rem[p] -= 1
                runs.append(best_len)
                break
    if not runs:
        return (0, None)
    best = (0, None)
    for cand in sorted(set(runs)):
        if cand < 5:
            continue
        m = len([r for r in runs if r >= cand])
        types = ['STRAIGHT'] + (['MULTI'] if m > 1 else [])
        best = bmax(best, (final_score(types, m, cand), ('STRAIGHT', cand, m, None)))
    return best


def eval_flushes(cards):
    """Returns (score, tag); single flush tags carry the suit (flush of hearts !=
    flush of spades), multi-flushes are identified by (size, copies)."""
    suits = {}
    for r, s in cards:
        suits.setdefault(s, []).append((r, s))
    sized = sorted(((len(v), suit) for suit, v in suits.items() if len(v) >= 5),
                   reverse=True)
    if not sized:
        return (0, None)
    groups = [n for n, _ in sized]
    best = (final_score(['FLUSH'], 1, groups[0]), ('FLUSH', groups[0], 1, sized[0][1]))
    if len(groups) >= 2:
        for cand in sorted(set(groups)):
            m = len([g for g in groups if g >= cand])
            if m >= 2:
                best = bmax(best, (final_score(['FLUSH', 'MULTI'], m, cand),
                                   ('FLUSH', cand, m, None)))
    return best


def score_line(cards, high_card_floor=True):
    """Best single hand for a line -> (score, tag). tag is None for high-card lines.
    high_card_floor=False: a meldless line pays 0."""
    if not cards:
        return (0, None)
    meld = bmax(bmax(eval_sets_houses(cards), eval_straights(cards)),
                eval_flushes(cards))
    if meld[0] > 0:
        return meld
    return ((HIGH_CARD_SCORE, None) if high_card_floor else (0, None))


# ============================================================================
# Decks
# ============================================================================
def make_deck(size=24, spread=4, skills=8, props=0):
    """Parametric deck: ranks 1..spread cycled over 4 suits until `size` cards,
    with `skills` ExtraPoint cards and `props` prop-source cards flagged on the
    first cards of the cycle (rank-diverse). deck11 = make_deck(24, 4, 8, 0) with
    skills pinned to ranks 2-3 like the real deck."""
    cards = []
    i = 0
    while len(cards) < size:
        rank = (i % spread) + 1
        suit = (i // spread) % 4
        cards.append([rank, suit, False, False])
        i += 1
    for k in range(min(skills, len(cards))):
        cards[(k * 3) % len(cards)][2] = True
    for k in range(min(props, len(cards))):
        # spread prop flags over the deck, offset so they don't all overlap skills
        cards[(k * 5 + 1) % len(cards)][3] = True
    return [tuple(c) for c in cards]


def deck11():
    """The real starting deck: per suit, plain ranks 1-4 + ExtraPoint ranks 2-3 (24 cards)."""
    out = []
    for suit in range(4):
        for rank in (1, 2, 3, 4):
            out.append((rank, suit, False, False))
        for rank in (2, 3):
            out.append((rank, suit, True, False))
    return out


def deck52():
    return [(r, s, False, False) for s in range(4) for r in range(1, 14)]


# ============================================================================
# Board building / arrangements
# ============================================================================
N_COLS = 6
USED_COLS = 5  # Next deals into 5 paired columns round-robin


def deal_random(chunk, n_cols=N_COLS):
    cols = [[] for _ in range(n_cols)]
    for i, card in enumerate(chunk):
        cols[i % USED_COLS].append(card)
    return cols


def arrange_rank_rows(chunk, n_cols=N_COLS):
    cards = sorted(chunk, key=lambda c: (c[0], c[1]))
    rows = [cards[i:i + n_cols] for i in range(0, len(cards), n_cols)]
    cols = [[] for _ in range(n_cols)]
    for row in rows:
        for j, card in enumerate(row):
            cols[j].append(card)
    return cols


def arrange_suit_cols(chunk, n_cols=N_COLS):
    cards = sorted(chunk, key=lambda c: (c[1], c[0]))
    bysuit = {}
    for c in cards:
        bysuit.setdefault(c[1], []).append(c)
    cols = [[] for _ in range(n_cols)]
    i = 0
    for s in sorted(bysuit):
        cols[i % n_cols].extend(bysuit[s])
        i += 1
    return cols


def arrange_degraded(chunk, f, rng, n_cols=N_COLS):
    """Skill model: fraction f of the cards get the oracle rank-rows treatment,
    the rest are dealt randomly on top (imperfect organization)."""
    chunk = list(chunk)
    rng.shuffle(chunk)
    k = int(round(f * len(chunk)))
    cols = arrange_rank_rows(chunk[:k], n_cols) if k else [[] for _ in range(n_cols)]
    for i, card in enumerate(chunk[k:]):
        cols[i % USED_COLS].append(card)
    return cols


def build_board(chunk, arrange, rng, degrade_f=0.6):
    if arrange == 'random':
        return deal_random(chunk)
    if arrange == 'ranks':
        return arrange_rank_rows(chunk)
    if arrange == 'suits':
        return arrange_suit_cols(chunk)
    if arrange == 'degraded':
        return arrange_degraded(chunk, degrade_f, rng)
    if arrange == 'capacity':
 # Fixed arrangement budget (owner model 2026-07-17): the player can ideally
        # place ~degrade_f CARDS per act; the rest fall as dealt. A small act is fully
        # arranged, a dump is mostly chaos — bigger boards are inherently harder.
        return arrange_degraded(chunk, min(1.0, degrade_f / max(len(chunk), 1)), rng)
    raise ValueError(arrange)


# ============================================================================
# Scoring a board under a variant
# ============================================================================
class Variant:
    """A full parameter set. combine: V0 (row*col, current), V2A (combo-mult),
    V7 (row*col with re-anchored goals — same combine as V0)."""

    def __init__(self, combine='V0', w_r=0.5, w_c=0.5, high_card_floor=True,
                 act_bonus=0.0, overscore_cap=None, overscore_exp=1.5, name=None,
                 combo_mode=None, combo_u=0.25, combo_k=10):
        self.combine = combine
        self.w_r = w_r
        self.w_c = w_c
        self.high_card_floor = high_card_floor
        self.act_bonus = act_bonus
        self.overscore_cap = overscore_cap  # None = uncapped (current behavior)
        self.overscore_exp = overscore_exp
        # Uniqueness combo bonus: U = distinct meld identities on the board this act
        # (duplicates still score base, they just don't raise U). Attachment points:
        #   'mult' payout*(1+u*U) | 'flat' payout+k*U | 'row' (R+k*U)*C | 'col' R*(C+k*U)
        self.combo_mode = combo_mode
        self.combo_u = combo_u
        self.combo_k = combo_k
        self.combo_stack_u = 0.0  # dedup hybrid: also multiply payout by (1+this*U)
        # Identity granularity for U:
        #   'fine'   pair of 2s != pair of 3s (rank/suit in the identity)
        #   'coarse' any pair is "a pair" — (archetype, size, copies)
        #   'class'  hand classes — (archetype, size): quad-of-1s == 2x quad == "quads"
        #   'arch'   archetype only: set / straight / flush / house (U caps at 4)
        self.combo_sig = 'fine'
        self.name = name or combine

    def payout(self, rt, ct, row_melds, col_melds, uniques=0):
        if self.combo_mode == 'row':
            rt = rt + self.combo_k * uniques
        elif self.combo_mode == 'col':
            ct = ct + self.combo_k * uniques
        if self.combine == 'V2A':
            pay = int((rt + ct) * (1.0 + self.w_r * row_melds)
                      * (1.0 + self.w_c * col_melds))
        else:
            pay = rt * ct  # V0 and V7
        if self.combo_mode == 'mult':
            pay = int(pay * (1.0 + self.combo_u * uniques))
        elif self.combo_mode == 'flat':
            pay = pay + self.combo_k * uniques
        if self.combo_stack_u > 0.0:
            pay = int(pay * (1.0 + self.combo_stack_u * uniques))
        return pay


V0 = Variant('V0')
V2A = Variant('V2A')
V7 = Variant('V7', name='V7')
# Finalists calibrated by the Stage 1-3 sweeps:
# w=0.5 measured concentration 2.6x (out of band); w=0.25 lands in [1.3, 1.8].
# Both finalists defang overscore: per-show ratio cap 1.0, exponent 1.0.
V2A25 = Variant('V2A', w_r=0.25, w_c=0.25, overscore_cap=1.0, overscore_exp=1.0,
                name='V2A25')
V0CAP = Variant('V0', overscore_cap=1.0, overscore_exp=1.0, name='V0CAP')
VARIANTS = {'V0': V0, 'V2A': V2A, 'V7': V7, 'V2A25': V2A25, 'V0CAP': V0CAP}


def score_board(cols, variant):
    """One act: rows then cols (+ static prop model), returns
    (row_total, col_total, row_melds, col_melds, payout, flat, uniques)."""
    hcf = variant.high_card_floor
    # 'dedup' combo mode: a repeated meld identity scores base * combo_u (0 = repeats
    # are worthless, 0.5 = half) — the punishing twin of the reward attachments.
    dedup = variant.combo_mode == 'dedup'
    sig_len = {'fine': 4, 'coarse': 3, 'class': 2, 'arch': 1}[variant.combo_sig]
    seen = set()

    def norm(tag):
        return tag[:sig_len] if tag is not None else tag

    def line_value(sc, tag):
        tag = norm(tag)
        if not dedup or tag is None or sc <= HIGH_CARD_SCORE:
            return sc
        if tag in seen:
            return int(sc * variant.combo_u)
        return sc

    tags = []
    n_rows = max((len(c) for c in cols), default=0)
    row_total, row_melds = 0, 0
    for r in range(n_rows):
        row = [(c[r][0], c[r][1]) for c in cols if len(c) > r]
        if not row:
            continue
        sc, tag = score_line(row, hcf)
        row_total += line_value(sc, tag)
        if sc > HIGH_CARD_SCORE:
            row_melds += 1
            tags.append(norm(tag))
            seen.add(norm(tag))
    col_total, col_melds = 0, 0
    for c in cols:
        if not c:
            continue
        sc, tag = score_line([(x[0], x[1]) for x in c], hcf)
        col_total += line_value(sc, tag)
        if sc > HIGH_CARD_SCORE:
            col_melds += 1
            tags.append(norm(tag))
            seen.add(norm(tag))
    # static prop model: each prop-source card adds `rank` points to its row gutter
    for ci, c in enumerate(cols):
        for ri, card in enumerate(c):
            if card[3]:
                row_total += card[0]
    uniques = len(set(tags))
    payout = variant.payout(row_total, col_total, row_melds, col_melds, uniques)
    flat = sum(10 for c in cols if c and c[-1][2])  # topmost ExtraPoint
    return row_total, col_total, row_melds, col_melds, payout, flat, uniques


def play_show(deck, policy, arrange, variant, rng, degrade_f=0.6):
    """One 3-act show. policy = cards per act. Returns (total, act_payouts)."""
    total, idx, payouts = 0, 0, []
    uniques_per_act = []
    unused = 0
    for n in policy:
        n = min(n, len(deck) - idx)
        if n <= 0:
            payouts.append(0)
            unused += 1  # an act with no performed cards
            continue
        chunk = deck[idx:idx + n]
        idx += n
        cols = build_board(chunk, arrange, rng, degrade_f)
        rt, ct, rm, cm, pay, flat, uniq = score_board(cols, variant)
        uniques_per_act.append(uniq)
        total += pay + flat
        payouts.append(pay)  # act payout excl. the flat ExtraPoint (plan-2 convention)
    if variant.act_bonus > 0.0 and unused > 0:
        total = int(total * (1.0 + variant.act_bonus * unused))
    return total, payouts, uniques_per_act


_RETIRED_SEEN = set()


def retired_banner(flag):
    """Printed once per entry point by every RETIRED TABLEAU report. It is the only
    thing standing between a reader and a goal curve fitted to a game that no longer
    exists -- see this file's own docstring."""
    if flag in _RETIRED_SEEN:
        return
    _RETIRED_SEEN.add(flag)
    print("!" * 78)
    print("!! %s MODELS THE RETIRED TABLEAU (acts, submits, an R x C act payout)." % flag)
    print("!! The shipped game is the grid economy. Use --grid-goals to fit the curve.")
    print("!" * 78)


# ============================================================================
# Experiment engine — paired seeds: trial t always shuffles with Random(seed+t)
# ============================================================================
BASE_SEED = 42


def shuffled(deckf, trial, seed=BASE_SEED):
    rng = random.Random(seed * 1000003 + trial)
    deck = list(deckf())
    rng.shuffle(deck)
    return deck, rng


def sim_shows(deckf, policy, arrange, variant, trials, degrade_f=0.6, seed=BASE_SEED):
    totals, act1s = [], []
    for t in range(trials):
        deck, rng = shuffled(deckf, t, seed)
        total, payouts, _uniqs = play_show(deck, policy, arrange, variant, rng, degrade_f)
        totals.append(total)
        act1s.append(payouts[0] if payouts else 0)
    return totals, act1s


def pct(v, p):
    s = sorted(v)
    return s[min(len(s) - 1, int(p * len(s)))]


def summarize(totals):
    return dict(mean=st.mean(totals), med=st.median(totals),
                p10=pct(totals, 0.10), p15=pct(totals, 0.15),
                p50=pct(totals, 0.50), p90=pct(totals, 0.90))


def policies_for(size):
    """even / mid / dump policies scaled to deck size."""
    third = size // 3
    return {
        'even': [third, third, size - 2 * third],
        'mid': [size // 2, third, size - size // 2 - third],
        'dump': [size - 4, 4, 0],
    }


# ============================================================================
# CSV
# ============================================================================
class CsvOut:
    def __init__(self, path):
        self.path = path
        self.rows = []

    def add(self, **kw):
        self.rows.append(kw)

    def flush(self):
        if not self.path or not self.rows:
            return
        keys = []
        for r in self.rows:
            for k in r:
                if k not in keys:
                    keys.append(k)
        new = not os.path.exists(self.path)
        with open(self.path, 'a', newline='') as f:
            w = csv.DictWriter(f, fieldnames=keys)
            if new:
                w.writeheader()
            w.writerows(self.rows)
        print("wrote %d rows -> %s" % (len(self.rows), self.path))


# ============================================================================
# Stages
# ============================================================================
def run_baseline(trials, out):
    """Reproduce the plan-2 baseline table (V0, real deck11 / deck52)."""
    retired_banner('--baseline')
    print("=== BASELINE (V0, must match SCORING_MATH_PLAN.md 2 within MC noise) ===")
    cells = [
        ('deck11 8/8/8 random', deck11, [8, 8, 8], 'random'),
        ('deck11 8/8/8 ranks', deck11, [8, 8, 8], 'ranks'),
        ('deck11 20/4/0 random', deck11, [20, 4, 0], 'random'),
        ('deck11 20/4/0 suits', deck11, [20, 4, 0], 'suits'),
        ('deck52 17/17/18 suits', deck52, [17, 17, 18], 'suits'),
    ]
    for name, df, pol, arr in cells:
        totals, act1s = sim_shows(df, pol, arr, V0, trials)
        s = summarize(totals)
        print("%-26s total mean=%7.0f p10=%7.0f p90=%8.0f | act1=%7.0f"
              % (name, s['mean'], s['p10'], s['p90'], st.mean(act1s)))
        out.add(stage='baseline', cell=name, **{k: round(v, 1) for k, v in s.items()},
                act1=round(st.mean(act1s), 1))
    print("\n--- act payout vs board size (deck11, random, 1 act) ---")
    prev = None
    for n in (8, 12, 16, 20, 24):
        _, act1s = sim_shows(deck11, [n], 'random', V0, trials)
        m = st.mean(act1s)
        exp = (math.log(m / prev[1]) / math.log(n / prev[0])) if prev else float('nan')
        print("  %2d cards: pay=%7.0f   local exponent=%.2f" % (n, m, exp))
        out.add(stage='baseline_exponent', cards=n, pay=round(m, 1),
                exponent=round(exp, 2) if prev else '')
        prev = (n, m)


def concentration(deckf, variant, trials, arrange='degraded', degrade_f=0.6):
    size = len(deckf())
    pols = policies_for(size)
    ev, _ = sim_shows(deckf, pols['even'], arrange, variant, trials, degrade_f)
    du, _ = sim_shows(deckf, pols['dump'], arrange, variant, trials, degrade_f)
    return st.mean(du) / max(st.mean(ev), 1e-9), st.mean(ev), st.mean(du)


def run_ofat(which, trials, out):
    """Stage 1: sweep each variable alone around the reference point
    (deck11-equivalent 24/4, degraded f=0.6, mid policy, V0)."""
    retired_banner('--ofat')
    ref = dict(size=24, spread=4, skills=8, props=0, policy='mid',
               arrange='degraded', f=0.6)

    def cell(variant, **over):
        p = dict(ref)
        p.update(over)
        df = (lambda: make_deck(p['size'], p['spread'], p['skills'], p['props']))
        pol = policies_for(p['size'])[p['policy']]
        totals, _ = sim_shows(df, pol, p['arrange'], variant, trials, p['f'])
        return summarize(totals)

    sweeps = {
        'deck_size': [('size', v) for v in (16, 24, 32, 40, 52)],
        'rank_spread': [('spread', v) for v in (4, 5, 8, 13)],
        'policy': [('policy', v) for v in ('even', 'mid', 'dump')],
        'arrange': [('arrange', v) for v in ('random', 'degraded', 'ranks', 'suits')],
        'degrade_f': [('f', v) for v in (0.2, 0.4, 0.6, 0.8, 1.0)],
        'props': [('props', v) for v in (0, 2, 4, 8)],
    }
    combos = {'combine': [V0, V2A], 'w': [Variant('V2A', w_r=w, w_c=w, name='V2A w=%.2f' % w)
                                          for w in (0.25, 0.5, 0.75)],
              'floor': [Variant('V0', high_card_floor=b, name='V0 floor=%s' % b)
                        for b in (True, False)] +
                       [Variant('V2A', high_card_floor=b, name='V2A floor=%s' % b)
                        for b in (True, False)]}
    names = list(sweeps) + list(combos) if which == 'all' else [which]
    for name in names:
        print("\n=== OFAT: %s ===" % name)
        if name in sweeps:
            for key, val in sweeps[name]:
                for variant in (V0, V2A):
                    s = cell(variant, **{key: val})
                    print("  %s=%-9s %-4s mean=%8.0f med=%7.0f p15=%7.0f p90=%8.0f"
                          % (key, val, variant.name, s['mean'], s['med'], s['p15'], s['p90']))
                    out.add(stage='ofat', sweep=name, value=val, variant=variant.name,
                            **{k: round(v, 1) for k, v in s.items()})
        elif name in combos:
            for variant in combos[name]:
                s = cell(variant)
                conc, ev, du = concentration(
                    lambda: make_deck(24, 4, 8, 0), variant, trials)
                print("  %-16s mean=%8.0f p15=%7.0f | concentration=%.2fx (even %0.0f dump %0.0f)"
                      % (variant.name, s['mean'], s['p15'], conc, ev, du))
                out.add(stage='ofat', sweep=name, variant=variant.name,
                        concentration=round(conc, 2),
                        **{k: round(v, 1) for k, v in s.items()})


def run_grid(spec, trials, out):
    """Stage 2: pairwise grid. spec examples: deck,combine | w,floor | size,spread"""
    retired_banner('--grid')
    a, b = spec.split(',')
    print("\n=== GRID: %s x %s ===" % (a, b))
    if {a, b} == {'deck', 'combine'} or {a, b} == {'size', 'combine'}:
        for size in (16, 24, 32, 40, 52):
            for variant in (V0, V2A):
                df = (lambda s=size: make_deck(s, 4 if s <= 32 else 13, 8, 0))
                conc, ev, du = concentration(df, variant, trials)
                print("  size=%2d %-4s even=%8.0f dump=%8.0f conc=%.2fx"
                      % (size, variant.name, ev, du, conc))
                out.add(stage='grid', grid=spec, size=size, variant=variant.name,
                        even=round(ev, 1), dump=round(du, 1), conc=round(conc, 2))
    elif {a, b} == {'w', 'floor'}:
        for w in (0.25, 0.5, 0.75):
            for floor in (True, False):
                v = Variant('V2A', w_r=w, w_c=w, high_card_floor=floor,
                            name='V2A w=%.2f floor=%s' % (w, floor))
                conc, ev, du = concentration(lambda: make_deck(24, 4, 8, 0), v, trials)
                print("  w=%.2f floor=%-5s even=%8.0f dump=%8.0f conc=%.2fx"
                      % (w, floor, ev, du, conc))
                out.add(stage='grid', grid=spec, w=w, floor=floor,
                        even=round(ev, 1), dump=round(du, 1), conc=round(conc, 2))
    elif {a, b} == {'size', 'spread'}:
        for size in (16, 24, 32, 52):
            for spread in (4, 5, 8, 13):
                df = (lambda s=size, sp=spread: make_deck(s, sp, 8, 0))
                # organization-difficulty proxy: oracle/random ratio
                pol = policies_for(size)['mid']
                t_or, _ = sim_shows(df, pol, 'ranks', V0, trials)
                t_rd, _ = sim_shows(df, pol, 'random', V0, trials)
                ratio = st.mean(t_or) / max(st.mean(t_rd), 1e-9)
                print("  size=%2d spread=1-%2d random=%8.0f oracle=%8.0f ratio=%.2fx"
                      % (size, spread, st.mean(t_rd), st.mean(t_or), ratio))
                out.add(stage='grid', grid=spec, size=size, spread=spread,
                        random=round(st.mean(t_rd), 1), oracle=round(st.mean(t_or), 1),
                        org_ratio=round(ratio, 2))
    else:
        print("unknown grid spec: %s" % spec)


def run_lhs(n, trials, out):
    """Stage 3: Latin-hypercube over the surviving box (V2A parameters + deck),
    scored against the acceptance bands (concentration + legibility + growth)."""
    retired_banner('--lhs')
    print("\n=== LHS: %d samples ===" % n)
    rng = random.Random(BASE_SEED)
    axes = {
        'w': (0.15, 0.9),
        'size': (16, 52),
        'spread': (4, 13),
        'floor': (0, 1),
        'act_bonus': (0.0, 0.5),
    }
    # latin hypercube: one stratified sample per axis
    strata = {k: [lo + (hi - lo) * (i + rng.random()) / n for i in range(n)]
              for k, (lo, hi) in axes.items()}
    for k in strata:
        rng.shuffle(strata[k])
    passing = []
    for i in range(n):
        w = strata['w'][i]
        size = int(round(strata['size'][i]))
        spread = max(4, min(13, int(round(strata['spread'][i]))))
        floor = strata['floor'][i] >= 0.5
        b = strata['act_bonus'][i]
        v = Variant('V2A', w_r=w, w_c=w, high_card_floor=floor, act_bonus=b,
                    name='lhs%d' % i)
        df = (lambda s=size, sp=spread: make_deck(s, sp, 8, 0))
        conc, ev, du = concentration(df, v, max(200, trials // 5))
        # bands: concentration in [1.3, 1.8]; act payouts <= 5 digits; positive growth
        digits_ok = du < 99999
        ok = 1.3 <= conc <= 1.8 and digits_ok
        out.add(stage='lhs', i=i, w=round(w, 3), size=size, spread=spread,
                floor=floor, act_bonus=round(b, 3), conc=round(conc, 2),
                even=round(ev, 1), dump=round(du, 1), passes=ok)
        if ok:
            passing.append((conc, w, size, spread, floor, b))
    print("  %d/%d pass the concentration+legibility bands" % (len(passing), n))
    for conc, w, size, spread, floor, b in sorted(passing)[:12]:
        print("    conc=%.2f w=%.2f size=%d spread=1-%d floor=%s b=%.2f"
              % (conc, w, size, spread, floor, b))
    return passing


# ---------------------------------------------------------------------------
# Goal curves + full-run simulation
# ---------------------------------------------------------------------------
def expected_deck_size(k, start=24):
    """Booster cadence: ~1 booster per 3 nodes, 5 cards each, take-all."""
    return start + 5 * (k // 3)


BOOSTER_MODE = 'standard'  # 'standard': spread widens to 1-13 past 32 cards; 'dupes': stays
OVERSCORE_RATE = 0.25      # run_manager.gd OVERSCORE_RATE; --no-overscore sets 0


def spread_at(size, spread=4):
    if BOOSTER_MODE == 'dupes':
        return spread
    return spread if size <= 32 else 13


def deck_at_node(k, start=24, spread=4):
    size = expected_deck_size(k, start)
    sp = spread_at(size, spread)
    return lambda: make_deck(size, sp, 8, 0)


def goal_table(variant, q, trials, nodes=range(13), start=24, spread=4):
    """Quantile-calibrated goals: Q_q of the AVERAGE policy distribution at N-hat(k)."""
    goals = {}
    for k in nodes:
        df = deck_at_node(k, start, spread)
        size = expected_deck_size(k, start)
        pol = policies_for(size)['even']
        totals, _ = sim_shows(df, pol, 'degraded', variant, trials, degrade_f=0.5)
        goals[k] = max(1, int(pct(totals, q)))
    return goals


def run_goals(variant_name, q, trials, out):
    retired_banner('--goals')
    v = VARIANTS[variant_name]
    print("\n=== GOAL QUANTILE TABLE: %s q=%.2f (average policy, degraded f=0.5) ===" % (v.name, q))
    goals = goal_table(v, q, trials)
    cur = {k: int(100 * 1.15 ** k) for k in goals}
    for k in goals:
        print("  node %2d: N=%2d  goal=%7d   (current formula: %d)"
              % (k, expected_deck_size(k), goals[k], cur[k]))
        out.add(stage='goals', variant=v.name, q=q, node=k,
                deck=expected_deck_size(k), goal=goals[k], current=cur[k])
    return goals


def run_full(variant_name, q, trials, out):
    """Stage 4: 12-node runs. Personas: skilled-casual (mid policy, f=0.75) vs
    average (even, f=0.5) vs no-booster skilled. Goals = quantile table."""
    retired_banner('--run-sim')
    v = VARIANTS[variant_name]
    print("\n=== FULL RUN: %s q=%.2f ===" % (v.name, q))
    goals = goal_table(v, q, max(400, trials // 4))
    personas = {
        'skilled': dict(policy='mid', f=0.75, boosters=True),
        'average': dict(policy='even', f=0.5, boosters=True),
        'skilled-no-booster': dict(policy='mid', f=0.75, boosters=False),
    }
    for pname, p in personas.items():
        win_nodes, margins = [], [[] for _ in range(13)]
        wins_by_node = [0] * 13
        plays_by_node = [0] * 13
        for t in range(trials):
            over_sum = 0.0
            for k in range(13):
                size = expected_deck_size(k) if p['boosters'] else 24
                sp = spread_at(size)
                deck, rng = shuffled(lambda s=size, spx=sp: make_deck(s, spx, 8, 0),
                                     t * 13 + k)
                pol = policies_for(size)[p['policy']]
                total, _, _u = play_show(deck, pol, 'degraded', v, rng, p['f'])
                # overscore inflation (defanged when the variant says so)
                mult = (1.0 + OVERSCORE_RATE * over_sum) ** v.overscore_exp
                goal = int(goals[k] * mult)
                plays_by_node[k] += 1
                margins[k].append(total / max(goal, 1))
                if total < goal:
                    win_nodes.append(k)
                    break
                wins_by_node[k] += 1
                ratio = (total - goal) / max(goal, 1)
                if v.overscore_cap is not None:
                    ratio = min(ratio, v.overscore_cap)
                over_sum += ratio
            else:
                win_nodes.append(13)
        run_win = sum(1 for w in win_nodes if w >= 13) / trials
        print("  %-20s run-win=%5.1f%%  median loss node=%s" %
              (pname, 100 * run_win, st.median(win_nodes)))
        for k in range(13):
            if plays_by_node[k] == 0:
                break
            wr = wins_by_node[k] / plays_by_node[k]
            med_margin = st.median(margins[k]) if margins[k] else 0
            print("    node %2d: show-win=%5.1f%% median margin=%.2f goal=%d"
                  % (k, 100 * wr, med_margin, goals[k]))
            out.add(stage='fullrun', variant=v.name, q=q, persona=pname, node=k,
                    show_win=round(wr, 3), margin=round(med_margin, 2),
                    goal=goals[k], run_win=round(run_win, 3))


def run_combo(trials, out):
    """Uniqueness combo-bonus experiment (owner design 2026-07-17): U = distinct meld
    identities on one board; duplicates still score base but don't raise U. Compares
    attachment points on the proposed 20-card starting deck (ranks 1-5 x 4 suits, no
    modifiers): none / mult (payout x (1+u*U)) / flat (+k*U) / row ((R+k*U) x C) /
    col (R x (C+k*U))."""
    retired_banner('--combo')
    deckf = lambda: make_deck(20, 5, 0, 0)
    pols = policies_for(20)
    print("=== UNIQUENESS COMBO (deck 20, ranks 1-5 x 4 suits, degraded f=0.6) ===")
    print("policies: even %s  mid %s  dump %s" % (pols['even'], pols['mid'], pols['dump']))
    settings = [Variant('V0', name='none')]
    for u in (0.25, 0.5, 1.0):
        settings.append(Variant('V0', combo_mode='mult', combo_u=u, name='mult u=%.2f' % u))
    for k in (10, 25):
        settings.append(Variant('V0', combo_mode='flat', combo_k=k, name='flat k=%d' % k))
    for k in (5, 10):
        settings.append(Variant('V0', combo_mode='row', combo_k=k, name='row  k=%d' % k))
    for k in (5, 10):
        settings.append(Variant('V0', combo_mode='col', combo_k=k, name='col  k=%d' % k))
    for f in (0.5, 0.0):
        settings.append(Variant('V0', combo_mode='dedup', combo_u=f,
                                name='dedup f=%.1f' % f))
    # reward + punish together: dedup pricing with the per-act combo multiplier on top
    hybrid = Variant('V0', combo_mode='dedup', combo_u=0.5, name='dedup+mult')
    hybrid.combo_stack_u = 0.25
    settings.append(hybrid)
    for name, kw in (('C-mult u=.25', dict(combo_mode='mult', combo_u=0.25)),
                     ('C-dedup f=.5', dict(combo_mode='dedup', combo_u=0.5)),
                     ('C-dedup f=0', dict(combo_mode='dedup', combo_u=0.0)),
                     ('C-row k=10', dict(combo_mode='row', combo_k=10))):
        cv = Variant('V0', name=name, **kw)
        cv.combo_sig = 'coarse'
        settings.append(cv)
    ch = Variant('V0', combo_mode='dedup', combo_u=0.5, name='C-dedup+mult')
    ch.combo_sig = 'coarse'
    ch.combo_stack_u = 0.25
    settings.append(ch)
    for v in settings:
        means = {}
        ustats = {}
        for pname, pol in pols.items():
            totals = []
            show_us = []
            for t in range(trials):
                deck, rng = shuffled(deckf, t)
                total, _pays, uniqs = play_show(deck, pol, 'degraded', v, rng, 0.6)
                totals.append(total)
                show_us.append(sum(uniqs))
            means[pname] = st.mean(totals)
            ustats[pname] = st.mean(show_us)
        conc = means['dump'] / max(means['even'], 1e-9)
        print("  %-12s even=%7.0f mid=%7.0f dump=%7.0f conc=%.2fx | "
              "sum-U/show: even %.1f dump %.1f"
              % (v.name, means['even'], means['mid'], means['dump'], conc,
                 ustats['even'], ustats['dump']))
        out.add(stage='combo', mode=v.name, even=round(means['even'], 1),
                mid=round(means['mid'], 1), dump=round(means['dump'], 1),
                conc=round(conc, 2), u_even=round(ustats['even'], 2),
                u_dump=round(ustats['dump'], 2))


def run_capacity(trials, out):
    """Owner combo spec under the fixed-arrangement-capacity model: payout =
    (R x C) x (1 + 0.1 * U), U = unique meld classes (coarse identity), reset per
    act; capacity C cards ideally arranged per act, the rest random."""
    retired_banner('--capacity')
    print("=== CAPACITY MODEL x FLOAT COMBO (deck ranks 1-5, dupes; coarse classes) ===")
    for size in (20, 32, 44):
        deckf = (lambda s=size: make_deck(s, 5, 0, 0))
        pols = policies_for(size)
        for cap in (6, 9, 12):
            for u in (0.0, 0.1, 0.2):
                v = Variant('V0', name='cap')
                if u > 0.0:
                    v.combo_mode = 'mult'
                    v.combo_u = u
                v.combo_sig = 'coarse'
                means = {}
                for pname, pol in pols.items():
                    totals = []
                    for t in range(trials):
                        deck, rng = shuffled(deckf, t)
                        total, _p, _uq = play_show(deck, pol, 'capacity', v, rng, cap)
                        totals.append(total)
                    means[pname] = st.mean(totals)
                conc = means['dump'] / max(means['even'], 1e-9)
                print("  deck=%2d cap=%2d combo=+%.1f/U  even=%7.0f mid=%7.0f "
                      "dump=%7.0f  conc=%.2fx"
                      % (size, cap, u, means['even'], means['mid'], means['dump'], conc))
                out.add(stage='capacity', size=size, cap=cap, u=u,
                        even=round(means['even'], 1), mid=round(means['mid'], 1),
                        dump=round(means['dump'], 1), conc=round(conc, 2))
        print()


def run_crossover(trials, out):
    """At what deck size / combo strength does EVEN play beat the dump? For a flat
    combo (+k*U per act) the k->inf concentration limit is sum-U(dump)/sum-U(even);
    for a multiplier (pay*(1+u*U)) the u->inf limit is sum(pay*U)d / sum(pay*U)e.
    Scans identity granularity x deck size, plus finite strengths."""
    retired_banner('--crossover')
    print("=== COMBO CROSSOVER: when does even play win? (degraded f=0.6, dupes decks) ===")
    for size in (20, 32, 44):
        deckf = (lambda s=size: make_deck(s, 5, 0, 0))
        pols = policies_for(size)
        for sig in ('coarse', 'class', 'arch'):
            v = Variant('V0', name='probe')
            v.combo_sig = sig
            data = {}
            for pname in ('even', 'dump'):
                pays_u = []
                for t in range(trials):
                    deck, rng = shuffled(deckf, t)
                    total, pays, uniqs = play_show(deck, pols[pname], 'degraded',
                                                   v, rng, 0.6)
                    pays_u.append((pays, uniqs))
                data[pname] = pays_u
            base = {p: st.mean(sum(pays) for pays, _u in data[p]) for p in data}
            sum_u = {p: st.mean(sum(u) for _p2, u in data[p]) for p in data}
            pay_u = {p: st.mean(sum(pa * uu for pa, uu in zip(pays, u))
                                for pays, u in data[p]) for p in data}
            flat_inf = sum_u['dump'] / max(sum_u['even'], 1e-9)
            mult_inf = pay_u['dump'] / max(pay_u['even'], 1e-9)

            def conc_flat(k):
                e = base['even'] + k * sum_u['even']
                d = base['dump'] + k * sum_u['dump']
                return d / max(e, 1e-9)

            def conc_mult(u):
                e = base['even'] + u * pay_u['even']
                d = base['dump'] + u * pay_u['dump']
                return d / max(e, 1e-9)

            print("  deck=%2d sig=%-6s U/show even=%4.1f dump=%4.1f | "
                  "flat: conc k=25 %.2f k=100 %.2f k->inf %.2f | "
                  "mult: u=1 %.2f u=4 %.2f u->inf %.2f"
                  % (size, sig, sum_u['even'], sum_u['dump'],
                     conc_flat(25), conc_flat(100), flat_inf,
                     conc_mult(1), conc_mult(4), mult_inf))
            out.add(stage='crossover', size=size, sig=sig,
                    u_even=round(sum_u['even'], 2), u_dump=round(sum_u['dump'], 2),
                    flat_k25=round(conc_flat(25), 2), flat_k100=round(conc_flat(100), 2),
                    flat_inf=round(flat_inf, 2), mult_u1=round(conc_mult(1), 2),
                    mult_inf=round(mult_inf, 2))


FINAL_START = 20
FINAL_COMBO_U = 0.1


def final_spread(size):
    """Spread-extension schedule (owner: dupes fine, extensions as desired):
    ranks 1-5 to 25 cards, 1-8 to 40, 1-13 beyond. Extending EARLY keeps random
    collision density (and thus the dump baseline) from spiking mid-lap."""
    return 5 if size <= 25 else (8 if size <= 40 else 13)


def final_variant():
    v = Variant('V0', combo_mode='mult', combo_u=FINAL_COMBO_U, name='FINAL')
    v.combo_sig = 'coarse'
    return v


def run_final(q, trials, out):
    """FINAL calibration (owner rulings 2026-07-17): payout = R x C x (1 + 0.1*U),
    coarse classes, capacity arrangement, dump-as-endgame priced in: the goal at
    each node is Q_q of the PAR persona playing its BEST policy at N-hat(k).
    Difficulty is the float q. Then full-run validation for three personas."""
    retired_banner('--final')
    v = final_variant()
    nhat = lambda k: FINAL_START + 5 * (k // 3)

    def best_policy(size, cap, probe_trials=300):
        pols = policies_for(size)
        deckf = (lambda s=size: make_deck(s, final_spread(s), 0, 0))
        best, best_mean = None, -1.0
        for pname, pol in pols.items():
            tot = []
            for t in range(probe_trials):
                deck, rng = shuffled(deckf, t)
                total, _p, _u = play_show(deck, pol, 'capacity', v, rng, cap)
                tot.append(total)
            m = st.mean(tot)
            if m > best_mean:
                best, best_mean = pname, m
        return best

    print("=== FINAL GOAL TABLE (q=%.2f, par = cap-7 player, best policy) ===" % q)
    goals = {}
    for k in range(13):
        size = nhat(k)
        pol_name = best_policy(size, 7)
        deckf = (lambda s=size: make_deck(s, final_spread(s), 0, 0))
        pol = policies_for(size)[pol_name]
        totals = []
        for t in range(trials):
            deck, rng = shuffled(deckf, t)
            total, _p, _u = play_show(deck, pol, 'capacity', v, rng, 7)
            totals.append(total)
        goals[k] = max(1, int(pct(totals, q)))
        # monotone clamp: a spread extension can weaken par play (fewer collisions);
        # the goal ladder must still never descend
        if k > 0:
            goals[k] = max(goals[k], goals[k - 1])
        print("  node %2d: N=%2d spread=1-%-2d par-policy=%-4s goal=%6d"
              % (k, size, final_spread(size), pol_name, goals[k]))
        out.add(stage='final_goals', q=q, node=k, deck=size,
                spread=final_spread(size), policy=pol_name, goal=goals[k])
    # log-linear fit of goal vs N-hat for the runtime interpolator
    xs = [math.log(nhat(k) / float(FINAL_START)) for k in goals]
    ys = [math.log(goals[k]) for k in goals]
    n = len(xs)
    sx, sy = sum(xs), sum(ys)
    sxx = sum(x * x for x in xs)
    sxy = sum(x * y for x, y in zip(xs, ys))
    alpha = (n * sxy - sx * sy) / max(n * sxx - sx * sx, 1e-9)
    g0 = math.exp((sy - alpha * sx) / n)
    print("  fit: goal(N) ~= %.0f * (N/%d)^%.2f" % (g0, FINAL_START, alpha))
    out.add(stage='final_fit', q=q, g0=round(g0, 1), alpha=round(alpha, 2))

    print("\n=== FULL-RUN VALIDATION (13 nodes, goals above) ===")
    personas = {
        'skilled (cap 9)': dict(cap=9, boosters=True),
        'average (cap 5)': dict(cap=5, boosters=True),
        'skilled-no-booster': dict(cap=9, boosters=False),
    }
    for pname, p in personas.items():
        pol_cache = {}
        wins_by_node = [0] * 13
        plays_by_node = [0] * 13
        run_wins = 0
        for t in range(max(300, trials // 3)):
            for k in range(13):
                size = nhat(k) if p['boosters'] else FINAL_START
                if (size, p['cap']) not in pol_cache:
                    pol_cache[(size, p['cap'])] = best_policy(size, p['cap'], 200)
                pol = policies_for(size)[pol_cache[(size, p['cap'])]]
                deck, rng = shuffled(
                    (lambda s=size: make_deck(s, final_spread(s), 0, 0)), t * 13 + k)
                total, _pp, _u = play_show(deck, pol, 'capacity', v, rng, p['cap'])
                plays_by_node[k] += 1
                if total < goals[k]:
                    break
                wins_by_node[k] += 1
            else:
                run_wins += 1
        n_runs = max(300, trials // 3)
        print("  %-20s run-win=%5.1f%%" % (pname, 100.0 * run_wins / n_runs))
        for k in range(13):
            if plays_by_node[k] == 0:
                break
            wr = wins_by_node[k] / plays_by_node[k]
            print("    node %2d: show-win=%5.1f%%  goal=%d" % (k, 100 * wr, goals[k]))
            out.add(stage='final_run', q=q, persona=pname, node=k,
                    show_win=round(wr, 3), goal=goals[k])
    return goals


def run_gsp(trials, out):
    """Mod leverage in Goal Share Points: median delta(total) / goal at nodes
    {0,5,8,12}, under even-degraded and dump-arranged play, per variant."""
    retired_banner('--gsp')
    print("\n=== GSP MOD LEVERAGE (median delta-total / goal) ===")
    # each mod = the SAME base deck + one appended card (true marginal addition)
    def mod_card(name, spread):
        r = spread // 2 + 1
        if name == 'blank_card':
            return (r, 0, False, False)
        if name == 'flat_+10':
            return (r, 0, True, False)
        return (r, 0, False, True)  # gutter_prop

    for v in (V0, V2A):
        goals = goal_table(v, 0.6, max(400, trials // 4), nodes=[0, 5, 8, 12])
        for k in (0, 5, 8, 12):
            size = expected_deck_size(k)
            sp = 4 if size <= 32 else 13
            base_deck = make_deck(size, sp, 8, 0)
            base_df = lambda bd=base_deck: list(bd)
            pol = policies_for(size)['mid']
            base, _ = sim_shows(base_df, pol, 'degraded', v, trials)
            for mname in ('blank_card', 'flat_+10', 'gutter_prop'):
                mod_deck = base_deck + [mod_card(mname, sp)]
                mod_df = (lambda md=mod_deck: list(md))
                # size the policy to the MOD deck so the added card actually gets played
                mod_pol = policies_for(size + 1)['mid']
                modt, _ = sim_shows(mod_df, mod_pol, 'degraded', v, trials)
                dmed = st.median(sorted(m - b for m, b in zip(modt, base)))
                gsp = 100.0 * dmed / goals[k]
                tier = ('S' if gsp >= 25 else 'A' if gsp >= 10 else
                        'B' if gsp >= 3 else 'C')
                print("  %-4s node %2d %-12s d-median=%7.0f  GSP=%6.1f%%  tier %s"
                      % (v.name, k, mname, dmed, gsp, tier))
                out.add(stage='gsp', variant=v.name, node=k, mod=mname,
                        delta_median=round(dmed, 1), gsp_pct=round(gsp, 1), tier=tier)


# ============================================================================
# GRID MODEL — the live game. Port of the poker-patience economy (PLAN.md 1.6).
#
# Everything ABOVE this banner models the RETIRED TABLEAU: acts, a submit, an
# R x C act payout, an additive score option. None of it is the shipped game —
# Game.apply_act_score() has no caller in product code any more. It is kept for
# the calibration history it produced and is fenced off by retired_banner().
#
# What the live game is, and what this section ports, function by function:
#   * The board is `grid_count` grids of GRID_W x GRID_H cells (SkillGridAllotment).
#   * A placement scores every COMPLETE line through the placed cell, in
#     ROW/COL/DIAG/HEIGHT_V order (SkillLineDetector).
#   * A line banks into one of its grid's three buckets: row, col, special
#     (every diagonal and every vertical stack shares `special`).
#   * grid_score = the PRODUCT of that grid's buckets whose value is > 0, and 0
#     when none is; board_total sums it over grids (GameData.grid_score).
#   * displayed = board_total * combo, live, with combo = 1 + 1.0 * firsts
#     + 0.5 * repeats, never reset (GameData.combo_mult / live_total).
#
# SIMPLIFICATIONS, decided for the grid model rather than inherited (S38):
#   * KEPT, restated: no card effects at all. Props, statuses and stamps are out,
#     so the tableau's static rank-weighted gutter model is DROPPED rather than
#     carried over — it modelled a prop yield that banked into a row gutter that
#     no longer exists.
#   * CONSEQUENCE, and it is the whole shape of the model: stacking is
#     EFFECT-ONLY (TypeGridCell answers only for an empty cell), so with no
#     effects every card sits at height 0. HEIGHT_V therefore never reaches a
#     scoring height and no raised row/col/diag ever completes. The port still
#     enumerates and tests them, so a later effect model gets them for free.
#   * DROPPED: the arrangement oracle. The grid game has no act and no
#     rearrangement — the player places one held card into one empty cell, and
#     skill is WHICH one. `skill` below replaces `degrade_f`.
#   * KEPT: Entrance persistence across shows is not modelled; each show plays a
#     fresh shuffle of the whole deck.
#   * APPROXIMATION: a combo class key here is (archetype, copy_size,
#     copies_count), which is Scoring.class_key WITHOUT its :FF / :MF flush
#     suffixes, so in principle it merges "quads" with "quad flush" and the combo
#     it reports is a lower bound. MEASURED over the 1200 engine-evaluated lines
#     of the parity dump it merges nothing at all -- 9 distinct classes either
#     way -- because a flush suffix needs a five-card same-suit structure that
#     these spreads almost never deal. --parity reports both counts.
# ============================================================================
GRID_W = 5                      # GridData.grid_width
GRID_H = 5                      # GridData.grid_height
HEIGHT_SCORE_INTERVAL = 5       # LineGeometry.HEIGHT_SCORE_INTERVAL
ENTRANCE_SLOTS = 5              # Deck._build_rules1: five upper adders
GRID_CARDS_PER_UNLOCK = 52      # PlayerSettings.grid_cards_per_unlock
GRID_MAX_COUNT = 3              # PlayerSettings.grid_max_count
COMBO_UNIQUE_STEP = 1.0         # PlayerSettings.combo_unique_step
COMBO_REPEAT_STEP = 0.5         # PlayerSettings.combo_repeat_step
COMBO_CAP = 0.0                 # PlayerSettings.combo_cap; 0.0 means no cap
GOAL_N0 = 20                    # PlayerSettings.goal_n0 == the deck14 start deck
BOOSTER_YIELD = 5               # PlayerSettings.booster_yield
NODES_PER_BOOSTER = 3           # booster cadence, unchanged from expected_deck_size

ROW, COL, DIAG, HEIGHT_V = 'ROW', 'COL', 'DIAG', 'HEIGHT_V'
# SkillLineDetector._SCORED_KINDS, in its order: one placement completing several
# lines scores them rows-first, and that order decides which meld is a class FIRST.
SCORED_KINDS = (ROW, COL, DIAG, HEIGHT_V)
# LineGeometry._DIAG_DIRECTIONS, verbatim.
DIAG_DIRECTIONS = ((1, 1, 0), (1, -1, 0),
                   (1, 0, 1), (-1, 0, 1), (0, 1, 1), (0, -1, 1),
                   (1, 1, 1), (1, -1, 1), (-1, 1, 1), (-1, -1, 1))


def target_grid_count(deck_size, per_unlock=GRID_CARDS_PER_UNLOCK, max_count=GRID_MAX_COUNT):
    """SkillGridAllotment.target_grid_count: ceil(deck / per_unlock), clamped to
    [1, max_count]. Evaluated ONCE at game start against the deck just dealt."""
    d = max(per_unlock, 1)
    raw = (max(deck_size, 0) + d - 1) // d
    return min(max(raw, 1), max_count)


def height_line_scores(h):
    """LineGeometry.height_line_scores: a vertical run ending at 0-based height h
    pays only at a multiple of HEIGHT_SCORE_INTERVAL cards."""
    return (h + 1) % HEIGHT_SCORE_INTERVAL == 0


def _in_grid(w, h, x, y):
    return 0 <= x < w and 0 <= y < h


def lines_through(w, h, x, y, z=0):
    """LineGeometry.lines_through, ported: every line of every kind running through
    cell (x, y, z) of a w x h grid, as (kind, ((x, y, z), ...)). Says nothing about
    completeness — that is the caller's question, exactly as in the engine."""
    if not _in_grid(w, h, x, y) or z < 0:
        return []
    out = [(ROW, tuple((xi, y, z) for xi in range(w))),
           (COL, tuple((x, yi, z) for yi in range(h))),
           (HEIGHT_V, tuple((x, y, hi) for hi in range(z + 1)))]
    for dx, dy, dz in DIAG_DIRECTIONS:
        if dx != 0 and dy != 0:
            length = min(w, h)
        elif dx != 0:
            length = w
        else:
            length = h
        back = 0
        while _in_grid(w, h, x - (back + 1) * dx, y - (back + 1) * dy):
            back += 1
        x0, y0 = x - back * dx, y - back * dy
        run = 0
        while _in_grid(w, h, x0 + run * dx, y0 + run * dy):
            run += 1
        if run < length:
            continue
        z0 = z - back * dz
        if dz == 1 and z0 < 0:
            continue
        out.append((DIAG, tuple((x0 + i * dx, y0 + i * dy, z0 + i * dz)
                                for i in range(length))))
    return out


def flat_lines(w=GRID_W, h=GRID_H):
    """Every line a FLAT board (no stacking, so every card at height 0) can ever
    complete, deduplicated, in SCORED_KINDS order. Derived by walking
    lines_through over every cell rather than hand-listed, so the geometry stays
    the engine's. On 5x5 this is 5 rows, 5 columns and the 2 flat diagonals; the
    HEIGHT_V run of one card never reaches a scoring height and drops out here."""
    seen, out = set(), []
    for kind in SCORED_KINDS:
        for y in range(h):
            for x in range(w):
                for k, cells in lines_through(w, h, x, y, 0):
                    if k != kind or cells in seen:
                        continue
                    if any(c[2] != 0 for c in cells):
                        continue        # a climb needs a stack; nothing builds one
                    if k == HEIGHT_V and not height_line_scores(cells[-1][2]):
                        continue
                    seen.add(cells)
                    out.append((k, cells))
    return out


_LINE_SCORE_CACHE = {}


def score_line_cached(cards):
    """score_line over a canonical key. A line is re-evaluated from scratch by
    every candidate placement the player policy probes, and the same five cards
    recur constantly, so the memo is what makes the policy affordable."""
    key = tuple(sorted(cards))
    hit = _LINE_SCORE_CACHE.get(key)
    if hit is None:
        hit = score_line(list(key), True)
        _LINE_SCORE_CACHE[key] = hit
    return hit


def combo_key(tag):
    """Scoring.class_key at (archetype, copy_size, copies_count) granularity —
    see the APPROXIMATION note in this section's banner. None (a high card) never
    registers, mirroring Game.score_line's `counts_for_combo`."""
    return None if tag is None else tag[:3]


class GridBoard:
    """The live board: `n` grids of w x h flat cells, their three buckets each,
    and the show-wide combo. Line membership and per-line fill counts are kept
    incrementally so a candidate placement costs a handful of integer reads."""

    def __init__(self, n, w=GRID_W, h=GRID_H):
        self.n, self.w, self.h = n, w, h
        self.size = w * h
        self.cells = [[None] * self.size for _ in range(n)]
        self.lines = flat_lines(w, h)
        self.line_cells = [tuple(c[1] * w + c[0] for c in cells)
                           for _kind, cells in self.lines]
        self.line_kind = [kind for kind, _cells in self.lines]
        self.cell_lines = [[] for _ in range(self.size)]
        for li, idxs in enumerate(self.line_cells):
            for ci in idxs:
                self.cell_lines[ci].append(li)
        self.filled = [[0] * len(self.lines) for _ in range(n)]
        self.row_term = [0.0] * n
        self.col_term = [0.0] * n
        self.special_term = [0.0] * n
        self.classes = set()
        self.repeats = 0
        self.committed = -1
        self.placed = 0

    def combo_mult(self):
        """GameData.combo_mult."""
        mult = 1.0 + COMBO_UNIQUE_STEP * len(self.classes) + COMBO_REPEAT_STEP * self.repeats
        return min(mult, COMBO_CAP) if COMBO_CAP > 0.0 else mult

    def grid_score(self, g):
        """GameData.grid_score: the product of the terms that are > 0, 0 when none is.
        A term that has not scored ADDS 0 — it never multiplies by 0."""
        product = 0.0
        for term in (self.row_term[g], self.col_term[g], self.special_term[g]):
            if term <= 0.0:
                continue
            product = term if product == 0.0 else product * term
        return product

    def board_total(self):
        return sum(self.grid_score(g) for g in range(self.n))

    def live_total(self):
        """GameData.live_total: the whole board's total times the combo, derived
        on demand. The multiply is at DISPLAY time, not at banking time."""
        return int(self.board_total() * self.combo_mult())

    def grid_full(self, g):
        return None not in self.cells[g]

    def empty_cells(self, g):
        return [i for i, c in enumerate(self.cells[g]) if c is None]

    def _completed_by(self, g, ci, card):
        """Every line through cell `ci` that placing `card` completes, as
        (kind, score, tag), in SCORED_KINDS order. Reads only, mutates nothing."""
        out = []
        cells = self.cells[g]
        for kind in SCORED_KINDS:
            for li in self.cell_lines[ci]:
                if self.line_kind[li] != kind:
                    continue
                idxs = self.line_cells[li]
                if self.filled[g][li] != len(idxs) - 1:
                    continue
                line = [(card[0], card[1]) if i == ci else (cells[i][0], cells[i][1])
                        for i in idxs]
                sc, tag = score_line_cached(line)
                out.append((kind, sc, tag))
        return out

    def probe(self, g, ci, card):
        """What the board would DISPLAY after this placement, plus a shaping term
        for the lines it advances without completing. Pure — the policy calls this
        once per (held card, empty cell) pair and never commits anything."""
        row_t, col_t, spec_t = self.row_term[g], self.col_term[g], self.special_term[g]
        firsts, repeats = 0, 0
        seen = None
        for kind, sc, tag in self._completed_by(g, ci, card):
            if kind == ROW:
                row_t += sc
            elif kind == COL:
                col_t += sc
            else:
                spec_t += sc
            key = combo_key(tag)
            if key is None:
                continue
            if seen is None:
                seen = set(self.classes)
            if key in seen:
                repeats += 1
            else:
                seen.add(key)
                firsts += 1
        product = 0.0
        for term in (row_t, col_t, spec_t):
            if term <= 0.0:
                continue
            product = term if product == 0.0 else product * term
        total = product + sum(self.grid_score(o) for o in range(self.n) if o != g)
        mult = 1.0 + COMBO_UNIQUE_STEP * (len(self.classes) + firsts) \
            + COMBO_REPEAT_STEP * (self.repeats + repeats)
        if COMBO_CAP > 0.0:
            mult = min(mult, COMBO_CAP)
        shape = 0
        for li in self.cell_lines[ci]:
            after = self.filled[g][li] + 1
            if after < len(self.line_cells[li]):
                shape += after * after
        return int(total * mult), shape

    def place(self, g, ci, card):
        """Board.place_in_cell plus the SkillLineDetector pass it broadcasts to.
        THERE IS NO LINE-SCORED MEMORY: completeness is re-asked every time, so
        this stays correct if an effect model ever re-empties and refills a line."""
        self.cells[g][ci] = card
        self.placed += 1
        completed = []
        for kind in SCORED_KINDS:
            for li in self.cell_lines[ci]:
                if self.line_kind[li] != kind:
                    continue
                self.filled[g][li] += 1
                idxs = self.line_cells[li]
                if self.filled[g][li] != len(idxs):
                    continue
                line = [(self.cells[g][i][0], self.cells[g][i][1]) for i in idxs]
                completed.append((kind, score_line_cached(line)))
        for kind, (sc, tag) in completed:
            if kind == ROW:
                self.row_term[g] += sc
            elif kind == COL:
                self.col_term[g] += sc
            else:
                self.special_term[g] += sc
            key = combo_key(tag)
            if key is None:
                continue
            if key in self.classes:
                self.repeats += 1
            else:
                self.classes.add(key)


def choose_placement(board, held, rng, skill):
    """The player. With probability `skill` the placement is the one that leaves
    the board displaying the most (ties broken toward the cell that advances the
    most-nearly-complete lines); otherwise it is a uniformly random legal cell
    with a random held card — the same 'a fraction f of decisions are ideal'
    skill model the tableau sim used, moved from arrangement to placement.

    ⚠ Greedy on DISPLAYED total, not on the line's own score, is the whole point:
    under a product economy the second bucket of a grid is worth far more than
    the first, and a policy that maximised banked points would never see that."""
    targets = ([board.committed] if board.committed != -1
               else [g for g in range(board.n)])
    cand = [(g, ci) for g in targets for ci in board.empty_cells(g)]
    if not cand:
        return None
    if rng.random() >= skill:
        g, ci = cand[rng.randrange(len(cand))]
        return rng.randrange(len(held)), g, ci
    best, best_key = None, None
    for hi, card in enumerate(held):
        for g, ci in cand:
            key = board.probe(g, ci, card)
            if best_key is None or key > best_key:
                best, best_key = (hi, g, ci), key
    return best


def play_grid_show(deck, rng, skill, n_grids=None):
    """One show: deal five into the Entrance, place until it is empty, refill,
    repeat until the deck runs dry or no legal placement remains. Returns the
    displayed total at End Show.

    ⚠ TWO ENGINE RULES DECIDE THE SHAPE OF THIS LOOP, and both bind hard:
      * the Entrance refills only when EVERY slot is empty (Game._entrance_is_empty),
        so the player commits five cards before seeing the next five;
      * the first placement COMMITS a grid and no other grid accepts a card until
        the committed one has no legal placement left (Game.place_card_in_grid),
        which with no effects means until it is full."""
    n = target_grid_count(len(deck)) if n_grids is None else n_grids
    board = GridBoard(n)
    held, idx = [], 0
    while True:
        if not held:
            take = min(ENTRANCE_SLOTS, len(deck) - idx)
            if take <= 0:
                break
            held = list(deck[idx:idx + take])
            idx += take
        pick = choose_placement(board, held, rng, skill)
        if pick is None:
            if board.committed != -1:
                board.committed = -1        # the commitment lifts; try the other grids
                continue
            break
        hi, g, ci = pick
        board.place(g, ci, held.pop(hi))
        if board.committed == -1:
            board.committed = g
        if board.grid_full(board.committed):
            board.committed = -1
    return board.live_total(), board


# ---------------------------------------------------------------------------
# Goal curve, refitted against the grid model (S39)
# ---------------------------------------------------------------------------
def nhat(k, start=GOAL_N0):
    """RunManager.goal_for's N-hat at node k, under the sim's booster cadence."""
    return start + BOOSTER_YIELD * (k // NODES_PER_BOOSTER)


# How a booster's five cards relate to the ranks already in the deck. 'schedule'
# inherits the tableau sim's final_spread (1-5 to 25 cards, 1-8 to 40, 1-13 beyond);
# 'fixed' keeps the start deck's 1-5 and lets boosters duplicate it. ⚠ NOT a
# cosmetic switch: rank density is what makes melds, so this dominates the ladder.
GRID_SPREAD_MODE = 'schedule'


def grid_spread(size):
    return 5 if GRID_SPREAD_MODE == 'fixed' else final_spread(size)


def grid_deck(size):
    """The run deck at `size` cards. deck14 (the 20-card start deck) is exactly
    make_deck(20, 5, 0, 0); boosters follow GRID_SPREAD_MODE."""
    return make_deck(size, grid_spread(size), 0, 0)


def grid_show_totals(size, trials, skill, seed_off=0):
    """(displayed totals, cards actually placed) over `trials` shows at `size`.
    The placed count is reported because it is the finding: past board capacity
    the deck keeps growing and the show cannot use the extra cards."""
    deckf = (lambda s=size: grid_deck(s))
    totals, placed = [], []
    for t in range(trials):
        deck, rng = shuffled(deckf, seed_off + t)
        total, board = play_grid_show(deck, rng, skill)
        totals.append(total)
        placed.append(board.placed)
    return totals, placed


def fit_power(nodes, goals, start=GOAL_N0):
    """Least squares in log space for goal(N) = g0 * (N / start) ^ alpha — the
    exact shape RunManager.goal_for evaluates. Returns (g0, alpha, r2, worst),
    where `worst` is the largest relative error the fitted curve makes against
    the table it was fitted to. ⚠ READ `worst`: two constants can only carry a
    curve that IS a power law, and a bad `worst` is the model saying it is not."""
    xs = [math.log(nhat(k, start) / float(start)) for k in nodes]
    ys = [math.log(goals[k]) for k in nodes]
    n = len(xs)
    sx, sy = sum(xs), sum(ys)
    sxx = sum(x * x for x in xs)
    sxy = sum(x * y for x, y in zip(xs, ys))
    alpha = (n * sxy - sx * sy) / max(n * sxx - sx * sx, 1e-9)
    g0 = math.exp((sy - alpha * sx) / n)
    ybar = sy / n
    ss_res = sum((y - (math.log(g0) + alpha * x)) ** 2 for x, y in zip(xs, ys))
    ss_tot = sum((y - ybar) ** 2 for y in ys)
    r2 = 1.0 - ss_res / ss_tot if ss_tot > 1e-12 else 1.0
    worst = max(abs(g0 * math.exp(alpha * x) - goals[k]) / float(goals[k])
                for x, k in zip(xs, nodes))
    return g0, alpha, r2, worst


def fit_power_minimax(nodes, goals, start=GOAL_N0, steps=4000, amax=10.0):
    """The BEST two constants that exist for this ladder, under the objective the
    goal curve actually has: keep every node inside a band. Minimises the largest
    relative error instead of the sum of squares, so one plateau cannot buy an
    unreachable node. For a fixed alpha the optimal log g0 is the midpoint of
    (y - alpha*x), which makes the search a scan over alpha alone.

    ⚠ ITS `worst` IS THE VERDICT ON THE SHAPE. Least squares can be dragged; this
    cannot. If the minimax error is still large, no g0/alpha pair can carry the
    ladder and the curve needs a different DRIVER, not different constants."""
    xs = [math.log(nhat(k, start) / float(start)) for k in nodes]
    ys = [math.log(goals[k]) for k in nodes]
    best = None
    for i in range(steps + 1):
        alpha = amax * i / steps
        res = [y - alpha * x for x, y in zip(xs, ys)]
        half = (max(res) - min(res)) / 2.0
        if best is None or half < best[0]:
            best = (half, alpha, (max(res) + min(res)) / 2.0)
    half, alpha, log_g0 = best
    return math.exp(log_g0), alpha, math.exp(half) - 1.0


PAR_SKILL = 0.9
PERSONAS = (('skilled', 1.0), ('par', PAR_SKILL), ('average', 0.7))


def run_grid_goals(q, trials, skill, out, nodes=13):
    """S39. The goal at node k is the q-quantile of the PAR player's displayed
    total at N-hat(k); the two shipped constants are then the log-linear fit of
    that ladder. Difficulty stays the float q, exactly as in the tableau fit."""
    print("=== GRID GOAL TABLE (q=%.2f, par skill=%.2f, %d trials/node) ==="
          % (q, skill, trials))
    print("  spread mode: %s" % GRID_SPREAD_MODE)
    print("    N  ranks  grids  cells  placed  median      goal   (shipped 130*(N/20)^4.2)")
    goals, ks = {}, list(range(nodes))
    for k in ks:
        size = nhat(k)
        totals, placed = grid_show_totals(size, trials, skill, seed_off=k * 100003)
        goals[k] = max(1, int(pct(totals, q)))
        if k > 0:
            goals[k] = max(goals[k], goals[k - 1])   # the ladder never descends
        n_g = target_grid_count(size)
        cells = n_g * GRID_W * GRID_H
        med_placed = st.median(placed)
        shipped = 130.0 * (size / 20.0) ** 4.2
        print("  %3d   1-%-2d   %3d   %4d   %5.1f  %8d  %8d   %12.0f"
              % (size, grid_spread(size), n_g, cells, med_placed,
                 int(st.median(totals)), goals[k], shipped))
        out.add(stage='grid_goals', q=q, skill=skill, node=k, deck=size,
                spread=grid_spread(size), grids=n_g, cells=cells, placed=med_placed,
                median=int(st.median(totals)), goal=goals[k], shipped=int(shipped))
    g0, alpha, r2, worst = fit_power(ks, goals)
    mg0, malpha, mworst = fit_power_minimax(ks, goals)
    print("\n  LEAST SQUARES: goal(N) = %.1f * (N/%d)^%.2f  R2(log)=%.4f  worst %.0f%% out"
          % (g0, GOAL_N0, alpha, r2, 100 * worst))
    print("  MINIMAX:       goal(N) = %.1f * (N/%d)^%.2f  worst %.0f%% out"
          % (mg0, GOAL_N0, malpha, 100 * mworst))
    print("  shipped:       goal(N) = 130.0 * (N/20)^4.20")
    print("  ladder span: node 0 goal %d -> node %d goal %d  (x%.1f over the run)"
          % (goals[ks[0]], ks[-1], goals[ks[-1]], goals[ks[-1]] / float(goals[ks[0]])))
    out.add(stage='grid_fit', q=q, skill=skill, g0=round(g0, 1),
            alpha=round(alpha, 3), r2=round(r2, 4), worst=round(worst, 4),
            minimax_g0=round(mg0, 1), minimax_alpha=round(malpha, 3),
            minimax_worst=round(mworst, 4))
    print("\n=== FULL-RUN VALIDATION (%d nodes, the goals above) ===" % nodes)
    for pname, psk in PERSONAS:
        wins = [0] * nodes
        plays = [0] * nodes
        runs = max(200, trials // 2)
        run_wins = 0
        for t in range(runs):
            for k in ks:
                deck, rng = shuffled((lambda s=nhat(k): grid_deck(s)), t * 97 + k)
                total, _b = play_grid_show(deck, rng, psk)
                plays[k] += 1
                if total < goals[k]:
                    break
                wins[k] += 1
            else:
                run_wins += 1
        print("  %-10s (skill %.2f)  run-win=%5.1f%%" % (pname, psk, 100.0 * run_wins / runs))
        for k in ks:
            if plays[k] == 0:
                break
            print("    node %2d: show-win=%5.1f%%  goal=%d"
                  % (k, 100.0 * wins[k] / plays[k], goals[k]))
            out.add(stage='grid_run', q=q, persona=pname, skill=psk, node=k,
                    show_win=round(wins[k] / plays[k], 3), goal=goals[k])
    return goals, (g0, alpha, r2, worst)


def run_grid_show(size, skill, trial=0):
    """One show, printed cell by cell: what the board looks like at End Show, what
    each of its buckets holds, and how the displayed number is built from them.
    The instrument for checking the port by eye against a real board."""
    deck, rng = shuffled((lambda s=size: grid_deck(s)), trial)
    total, board = play_grid_show(deck, rng, skill)
    print("=== ONE GRID SHOW: N=%d cards, %d grid(s), skill=%.2f, seed trial %d ==="
          % (size, board.n, skill, trial))
    ranks = "0123456789TJQK"
    suits = "hkbf"
    for g in range(board.n):
        print("  grid %d:" % g)
        for y in range(board.h):
            cells = []
            for x in range(board.w):
                card = board.cells[g][y * board.w + x]
                cells.append(".." if card is None else ranks[card[0]] + suits[card[1]])
            print("    " + " ".join(cells))
        print("    row=%.0f  col=%.0f  special=%.0f   -> grid_score=%.0f"
              % (board.row_term[g], board.col_term[g], board.special_term[g],
                 board.grid_score(g)))
    print("  placed %d of %d cards (%d cells on the board)"
          % (board.placed, size, board.n * board.size))
    print("  combo = 1 + %.1f*%d firsts + %.1f*%d repeats = %.1f"
          % (COMBO_UNIQUE_STEP, len(board.classes), COMBO_REPEAT_STEP,
             board.repeats, board.combo_mult()))
    print("  board_total %.0f x combo %.1f = DISPLAYED %d"
          % (board.board_total(), board.combo_mult(), total))
    return total, board



# ---------------------------------------------------------------------------
# Parity gate — the port asserted against the engine, not against itself
# ---------------------------------------------------------------------------
def sim_class_key(tag, cards):
    """Scoring.class_key, rebuilt from a sim tag plus the line it came from. The
    engine's key carries the flush family (:FF / :MF); the tag does not, so the
    suffix is re-derived here from the winning meld's own cards. Used ONLY by the
    parity gate — combo_key stays the coarser key the board actually counts with,
    and the gate reports the gap between the two."""
    if tag is None:
        return 'HIGH:1x1'   # Scoring.class_key's default arch, copy_size 1, one copy
    arch, size, copies = tag[0], tag[1], tag[2]
    name = {'XKIND': 'XKIND', 'STRAIGHT': 'STRAIGHT', 'FLUSH': 'FLUSH',
            'HOUSE': 'HOUSE'}[arch]
    return "%s:%dx%d" % (name, size, copies)


def run_parity(path):
    """Assert the Python port against `Tools/scoring_parity.gd`'s engine dump.
    Checks every five-card line's SCORE, the grid_score product rule including
    every zero pattern, and combo_mult. Returns a non-zero count of mismatches.

    ⚠ THE SCORE IS THE ASSERTION. Class keys are reported as a spread, not failed
    on: combo_key is documented as the coarser (archetype, size, copies) key, so a
    difference in the flush suffix is the known approximation, not a defect."""
    import json
    with open(path, encoding='utf-8') as handle:
        dump = json.load(handle)
    bad = 0
    checked = 0
    key_coarser = 0
    for row in dump['lines']:
        cards = [(int(r), int(su)) for r, su in row['cards']]
        sc, tag = score_line(cards, True)
        checked += 1
        if sc != row['score']:
            bad += 1
            if bad <= 12:
                print("  [FAIL] line %s: engine %d, sim %d (tag %s)"
                      % (cards, row['score'], sc, tag))
        engine_key = row['class_key']
        if engine_key and not engine_key.startswith(sim_class_key(tag, cards)):
            key_coarser += 1
    print("  lines: %d checked, %d score mismatches" % (checked, bad))
    sim_keys = set()
    for row in dump['lines']:
        cards = [(int(r), int(su)) for r, su in row['cards']]
        sim_keys.add(combo_key(score_line(cards, True)[1]))
    eng_keys = set(row['class_key'] for row in dump['lines'])
    print("  class keys: %d of %d differ beyond the documented :FF/:MF suffix"
          % (key_coarser, checked))
    print("  combo granularity: %d distinct sim classes vs %d engine classes"
          % (len(sim_keys), len(eng_keys)))
    for row in dump['grid_score']:
        r, c, sp = [float(v) for v in row['terms']]
        board = GridBoard(1)
        board.row_term[0], board.col_term[0], board.special_term[0] = r, c, sp
        got = board.grid_score(0)
        checked += 1
        if abs(got - row['grid_score']) > 1e-6:
            bad += 1
            print("  [FAIL] grid_score%s: engine %s, sim %s"
                  % (row['terms'], row['grid_score'], got))
    for row in dump['combo']:
        board = GridBoard(1)
        board.classes = set(range(int(row['firsts'])))
        board.repeats = int(row['repeats'])
        got = board.combo_mult()
        checked += 1
        if abs(got - row['mult']) > 1e-9:
            bad += 1
            print("  [FAIL] combo_mult(firsts=%s, repeats=%s): engine %s, sim %s"
                  % (row['firsts'], row['repeats'], row['mult'], got))
    print("=== PARITY: %d checks, %d MISMATCHES ===" % (checked, bad))
    return bad



# ============================================================================
def main():
    global BASE_SEED
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--baseline', action='store_true')
    ap.add_argument('--ofat', metavar='VAR')
    ap.add_argument('--grid', metavar='A,B')
    ap.add_argument('--lhs', type=int, metavar='N')
    ap.add_argument('--run-sim', metavar='VARIANT', choices=list(VARIANTS))
    ap.add_argument('--gsp', action='store_true')
    ap.add_argument('--combo', action='store_true',
                    help='uniqueness combo-bonus attachment comparison (deck 1-5 x 4)')
    ap.add_argument('--crossover', action='store_true',
                    help='combo strength/granularity at which even play beats the dump')
    ap.add_argument('--capacity', action='store_true',
                    help='fixed arrangement budget per act x float combo multiplier')
    ap.add_argument('--final', action='store_true',
                    help='RETIRED tableau: the calibration that produced 130 / 4.2')
    ap.add_argument('--grid-goals', action='store_true',
                    help='LIVE grid model: goal ladder, curve fit and run validation (S39)')
    ap.add_argument('--grid-show', type=int, metavar='N',
                    help='LIVE grid model: play one show at N deck cards and dump the board')
    ap.add_argument('--parity', metavar='JSON',
                    help="assert the port against Tools/scoring_parity.gd's engine dump")
    ap.add_argument('--spread', choices=['schedule', 'fixed'], default='schedule',
                    help='grid model: boosters widen the rank spread, or duplicate 1-5')
    ap.add_argument('--skill', type=float, default=PAR_SKILL,
                    help='grid model: fraction of placements chosen ideally (par %.2f)'
                         % PAR_SKILL)
    ap.add_argument('--goals', metavar='VARIANT', choices=list(VARIANTS))
    ap.add_argument('--q', type=float, default=0.6)
    ap.add_argument('--no-overscore', action='store_true',
                    help='drop goal inflation from overscoring entirely')
    ap.add_argument('--booster', choices=['standard', 'dupes'], default='standard',
                    help='booster cards widen the rank spread (standard) or duplicate it (dupes)')
    ap.add_argument('--all', action='store_true')
    ap.add_argument('--trials', type=int, default=2000)
    ap.add_argument('--seed', type=int, default=BASE_SEED)
    ap.add_argument('--csv', metavar='PATH')
    global BOOSTER_MODE, OVERSCORE_RATE, GRID_SPREAD_MODE
    args = ap.parse_args()
    GRID_SPREAD_MODE = args.spread
    BASE_SEED = args.seed
    BOOSTER_MODE = args.booster
    if args.no_overscore:
        OVERSCORE_RATE = 0.0
    out = CsvOut(args.csv)
    ran = False
    if args.baseline or args.all:
        run_baseline(args.trials, out)
        ran = True
    if args.ofat:
        run_ofat(args.ofat, args.trials, out)
        ran = True
    if args.grid:
        run_grid(args.grid, args.trials, out)
        ran = True
    if args.lhs:
        run_lhs(args.lhs, args.trials, out)
        ran = True
    if args.gsp or args.all:
        run_gsp(args.trials, out)
        ran = True
    if args.combo:
        run_combo(args.trials, out)
        ran = True
    if args.crossover:
        run_crossover(args.trials, out)
        ran = True
    if args.capacity:
        run_capacity(args.trials, out)
        ran = True
    if args.final:
        run_final(args.q, args.trials, out)
        ran = True
    if args.parity:
        if run_parity(args.parity):
            return 1
        ran = True
    if args.grid_show is not None:
        run_grid_show(args.grid_show, args.skill)
        ran = True
    if args.grid_goals:
        run_grid_goals(args.q, args.trials, args.skill, out)
        ran = True
    if args.goals:
        run_goals(args.goals, args.q, args.trials, out)
        ran = True
    if args.all:
        for vn in ('V0', 'V2A'):
            run_goals(vn, args.q, args.trials, out)
    if args.run_sim:
        run_full(args.run_sim, args.q, args.trials, out)
        ran = True
    if not ran and not args.all:
        ap.print_help()
        return 1
    out.flush()
    return 0


if __name__ == '__main__':
    sys.exit(main())

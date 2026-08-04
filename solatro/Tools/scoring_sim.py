"""Solatro scoring & goal-math simulation harness (SCORING_MATH_PLAN.md companion).

Exact Python port of Scripts/scoring.gd ScoreModel + the three hand handlers
(sets/houses, straights, flushes), plus a Monte Carlo of shows and full runs.
Used to bake the balance tables in SCORING_MATH_PLAN.md and to sweep variants.

DOCUMENTED SIMPLIFICATIONS (vs the real game — see SCORING_MATH_PLAN.md §Uncertainties):
  * Arrangement is not legality-constrained: 'ranks'/'suits' are oracle upper bounds,
    'random' is the deal pattern lower bound, 'degraded' mixes the two by a skill
    fraction f (sorts f of the cards ideally, deals the rest randomly).
  * Props are modeled as STATIC rank-weighted gutter points (one pass, no ticks,
    no Burning cascades): a prop-source card on the board adds `rank` points into
    its row gutter. Real prop yield is dynamic and measured in-game.
  * Entrance persistence (holding cards upstairs across acts) is not modeled;
    each act plays a fresh chunk of the deck.
  * ExtraPoint skill (+10) fires once per act per card when topmost (approximated
    as: topmost card of a column that is a skill card).

CLI (all runs are deterministically seeded; paired seeds across settings):
  py scoring_sim.py --baseline            reproduce the plan-2 baseline tables
  py scoring_sim.py --ofat all            Stage 1: one-factor-at-a-time sweeps
  py scoring_sim.py --grid deck,combine   Stage 2: pairwise grid
  py scoring_sim.py --lhs 300             Stage 3: Latin-hypercube sample
  py scoring_sim.py --run-sim V2A         Stage 4: full 12-node run simulation
  py scoring_sim.py --gsp                 mod-leverage table (Goal Share Points)
  py scoring_sim.py --goals V2A --q 0.6   goal quantile table for a variant
  py scoring_sim.py --all                 baseline + gsp + goals for all variants
Options: --trials N (default 2000), --csv out.csv (append rows), --seed S
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
        elif self.combine == 'SUM':
            pay = rt + ct  # additive test variant (owner 2026-07-17): combo multiplies the sum
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
# Finalists calibrated by the Stage 1-3 sweeps (see SCORING_MATH_PLAN.md):
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


def final_variant(additive=False):
    v = Variant('SUM' if additive else 'V0', combo_mode='mult', combo_u=FINAL_COMBO_U,
                name='FINAL-ADD' if additive else 'FINAL')
    v.combo_sig = 'coarse'
    return v


def run_final(q, trials, out, additive=False):
    """FINAL calibration (owner rulings 2026-07-17): payout = R x C x (1 + 0.1*U),
    coarse classes, capacity arrangement, dump-as-endgame priced in: the goal at
    each node is Q_q of the PAR persona playing its BEST policy at N-hat(k).
    Difficulty is the float q. Then full-run validation for three personas.
    additive=True prices the (R + C) x combo test variant instead (score_additive)."""
    v = final_variant(additive)
    if additive:
        print("(ADDITIVE variant: payout = (R + C) x (1 + 0.1*U))")
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
                    help='FINAL calibration: goal table + fit + full-run validation')
    ap.add_argument('--additive', action='store_true',
                    help='with --final: price the (R+C) x combo test variant (score_additive)')
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
    global BOOSTER_MODE, OVERSCORE_RATE
    args = ap.parse_args()
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
        run_final(args.q, args.trials, out, args.additive)
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

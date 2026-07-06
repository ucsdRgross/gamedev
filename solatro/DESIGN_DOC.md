# SOLATRO — Organized Design Document

Compiled 2026-07-05 from the raw idea-dump notes ("gam draf 17"), cross-referenced against
the implementation (`solatro/`, see `ARCHITECTURE_REVIEW.md`) and the map addon
(`worldgen/addons/worldgen/`). The source notes are chronological (oldest → newest) with
superseded ideas never deleted; this document preserves that history as **mini-timelines**
per topic, always ending with the **LATEST** state. Everything in the original notes is
represented somewhere in this doc, including abandoned ideas (§22).

**Status legend** used throughout:

| Tag | Meaning |
|---|---|
| ✅ IMPLEMENTED | Exists in code today |
| 🔨 PARTIAL | Started/stubbed in code |
| 📋 DESIGNED | Settled design, not yet built |
| 💭 SKETCH | Raw idea, not yet committed to |
| ❌ ABANDONED | Explicitly vetoed or superseded |
| ⚠️ SUMMARY-ONLY | Appeared only in the appended auto-summary, not user-authored (see §23) |

---

## 1. Identity, Title & Inspirations

**Working title:** Solatro (styled "Soltāro" once in notes).

**Title candidates brainstormed (all still on the table):** Patience-mania, Tableau-mania,
Circus Solitaire, Cardaganza, The Greatest Deck Show, Cardshow, Showitaire,
"The Greatest Show in Circustaire" (word-salad riff on *The Greatest Show on Earth*).

**Elevator pitch (latest):** *Balatro, but the hand-play is solitaire.* A circus-themed
solitaire deckbuilder where you are the **Ringmaster** arranging **performers** (cards)
in **The Ring** to excite the audience (score), touring city to city on a generated
world map.

**Stated references:**
- Balatro — jokers, consumables, decks, unlocks, boss-blind philosophy, community management
  (dev linked their Discord in-game; GDC talk "Balatro — Turning Low Resolution" noted).
- Zachtronics Solitaire Collection & Hempuli's solitaire mystery — solitaire mechanics depth.
- Deadman Wonderland (map inspiration v1), FTL / Slay the Spire (map), TFT set 16 (quests),
  One Step From Eden (biome worlds), Umamusume (fame gates), Vampire Survivors (prestige,
  ban lists), Mewgenics (debuffs, route unlock caution), Inscryption act 2 (crunchy audio),
  Steel Ball Run (world-tour race framing), Titanium Court (static stylized art),
  "The Secret to good 2D Graphics for your Games" (YouTube).

**Music mood-board:** Stranger Things Theme (C418 remix), Void Stranger OST — *Void
Symphony*, Neon Nightlife (Disconauts).

**Design-philosophy one-liners scattered through the notes (collected):**
- *"Scoring is the most important aspect — it contextualizes what all cards are trying
  to do"* (→ §5).
- *"The game needs to yak-shave: the player goes in trying to pull off one strategy but
  finds themselves wanting to try a surprising new strategy that shows up instead."*
- *Flexibility is part of a card's budget* — exponential power/cost curve (→ §16).
- *Don't multiply the number of progression systems; any single system can go
  infinitely deep* (→ §19).
- *Secrets drive engagement even without answers* (→ §19).

---

## 2. Core Game Loop

**Timeline:**
1. **v1 — Deck-click drops:** Playfield where every click of the deck drops new cards
   down; a limited count of rounds/clicks; **score slots on the right** score whatever you
   place on them and double as free spaces between deck clicks. Incoming cards could be
   **mulliganed** (click + discard button) and **rearranged** before dropping. Everything
   else lifted from Balatro (jokers, consumables). ❌ superseded by v2.
2. **v2 — Whole-board submit (LATEST, ✅ implemented):** No special submit slot. You
   continuously draw through the deck like real solitaire, building the board; pressing
   **Submit** evaluates the *entire board state*. Submit scores everything and clears the
   board, with upper-zone (Entrance) cards dropping down to seed the next board state
   without being wiped. Match ends when the deck runs out or the required score is reached.
   Cards enter play by dropping on their own from the input row — they cannot be dragged
   down manually.
3. **Refinements:** 3 submits per match as a nod to a 3-act performance 💭; each act (or
   only the final act) could carry an increasing score multiplier 💭.

**Implementation state:** `Game`/`GameData` with draw deck, discard, upper zone (Entrance)
and lower zone (Ring); `TypeInput.on_next` drops upper stacks into the Ring and refills
from the deck; `SkillScorerCascadeLower` performs the whole-board evaluation. ✅

Different starting decks influence both your card pool **and the rules you play under**
(see Rule Deck, §8); the very early note "combine and pick up decks" 💭 was never developed
further.

---

## 3. Board & Zones

- 5-column board — width chosen deliberately so a full row is a 5-card poker hand. ✅
- Two zones. Original names upper/lower play zones → **LATEST circus names: the "Grand
  Entrance" (upper, where drawn cards wait) and "The Ring" (lower, where you build)**. 📋
  (code still says upper/lower).
- Column count is **not hardcoded**: rule cards (`SkillAdderInputUpper/Lower`, `ZoneAdder`)
  each add one input/board column at game creation, so effects can add/remove columns and
  all logic must respect "not guaranteed 5 columns". ✅ (The note resolved its own
  immutability worry: the immutable rule is "zones exist"; the *count* is 5 separate
  +1-column rule cards.)
- Duplicate rule cards use their **rank as identifier** (zone adder #1 has rank 1, #5 has
  rank 5, etc.). 📋
- **Null cards** that take up space; highlighted when selected so hovering over null space
  reads clearly. 💭
- UI details: when holding a stack over a zone, the zone's control should **expand**,
  shifting stacked cards down to show the insertion point; controls are narrower than the
  card art so clicks can pass through to the board for dragging. 💭
- Board state is an array (early architecture note). ✅ (`GameData` arrays; a card's
  location is a `Vector3i`.)

---

## 4. Stacking & Movement Rules

**Timeline:**
1. Early: you can pick up a stack from anywhere, but an **illegal stack can only be placed
   on the submission spot**. ❌ (submission spot itself was removed in loop v2).
2. Later: **only legal stacks can be picked up** — "moving stacks becomes more difficult
   with time". ✅ LATEST.
3. Legal stack definition (for now): **ascending OR descending runs; cannot stack same
   suit**. ✅ (`SkillGrabberOgLower` / `SkillPlacerOgLower`).

**Modifier-driven legality (LATEST architecture, ✅):** stacking legality is decided by a
resolver pass, not hardcoded — all cards' allow/deny effects are gathered into a
whitelist + blacklist (blacklist wins over whitelist). Implemented as rule cards answering
`on_can_grab_stack` / `on_can_place_stack`, with `PipComparator` handling rank/suit
comparisons (every comparison first polls mods before numeric fallback).

Related sketches: card ability "any card can be placed on this card" 💭 (explicit TODO:
stacking rules must be modifiable by abilities — the resolver enables this); **cards that
can resist being moved** 💭; elemental card types with custom movement (always on top /
bottom of a stack) 💭 → partially realized as Heavy/Light types (§14).

---

## 5. Scoring

The notes call scoring "the most important aspect of the game as it contextualizes what
all cards are trying to do."

**Timeline:**
1. **v1 — Cribbage-style:** face cards all count 10; 2 points per 15-sum, 2 per 31-sum,
   2 pair, 6 triple, 12 quad, 3–7 points for runs of 3–7. ❌ — "15s too hard to see;
   should be an ability, not default." (Survives as a possible ability/pip idea.)
2. **v2 — Dual-axis (LATEST core, ✅):** base scoring is **vertical runs** (with a minimum
   size) per column plus **horizontal poker hands** per row. Evaluation order: top-down,
   one row at a time — poker hands first, with runs calculated simultaneously per column
   as each row resolves. Results return the list of scored cards, which then run through
   the card-effect loop; scored cards are elevated/rise up.
   - Refined once more to: **all row scoring first**, then all 5 lanes (columns) scored
     simultaneously at that row.
   - Aggregation idea: **all vertical scores are multiplied with all horizontal scores**
     at the end (row total × column total). 📋
   - Score displays distinguish axes: `-2-` for row points, `|1|` for column points. 📋
   - "Only the first scored poker hand actually scores, ignoring later poker hands" —
     ✅ (`SkillEvalPokerBest` picks the best/first result).
   - Open TODO from notes: check whether scoring should also scan the draw deck and
     discard pile 💭; "every 5 rows make row red / increase points by layer" 💭 → later
     matured into Performance Rings (below).
3. **v3 — Combo/damage recontextualization (LATEST thinking, 📋 not built):** points
   reframed as *damage against an antagonist* (Slay-the-Spire/TCG enemy-health framing).
   Row and column scorers become a **combo system**: combo increments by 1 for each
   *unique effect triggered*; flat points come from card effects ("cards are ammo"),
   with row-combo and col-combo multiplied into the flat points. Rewards triggering many
   effects in a deliberate order. A separate early note — a **uniqueness multiplier** that
   grows with every unique effect triggered — is the same idea in embryo.
4. **Circus framing (LATEST theme):** scoring = exciting the audience; cheering scales
   with score; **overscoring pays out tips**; required score = fame the show must earn.

**Performance Rings** 📋: score zones by board depth — First Ring = first 5×5 rows at 1×,
rows 6–10 = 2×, rows 11–15 = 3×, and so on; enables effects keyed to reaching outer rings.

**Trigger order (card effects):** field effects first → deck top-down (cards about to be
drawn first; actual order invisible to player) → board left-to-right, top-to-bottom
(including the input row at top) → discard pile top-down (recent discards first). 📋

**Big numbers:** planned from the start ("big numbers are funner") with an infinite number
class — ✅ `BigNumber` exists. Yu-Gi-Oh logic: never single digits; bigger numbers are
always cooler — rebalance base values upward accordingly. 📋

**Avalanche** (card idea filed here): after scoring, all cards on board "attack the
scoreboard," reducing the goal score by the number of cards. An early prototype of
alternative goal-manipulation effects. 💭

---

## 6. Card Anatomy & Pips

**Immutable rules (the engine contract, ✅ all implemented):**
- A card has: **suit, rank** (the pips), a **stamp slot**, a **skill slot**, and a
  **card type**.
- Cards can have 1 parent and 1 child card — a stack.
- There exists a board with 2 zones, a draw deck, a discard deck, and a rule-set deck.
- On game creation the rule-set deck is parsed to decide board layout.
- Scoring UI itself is *not* card-implemented (an "alt win con by manipulating the UI"
  was considered and shelved — only acceptable if the manipulation is
  duplicate-or-remove, which has no good design yet ❌).

**Vocabulary timeline:** "Seals" → renamed **Stamps** ✅. "Card materials" → became
**Types** ✅. Later circus-theme riff: stamp could be diegetic **hat** (or general
equipment — shoes, costume) 💭, connecting to the Costume Designer class (§11).

**Pip architecture (✅ implemented as designed):**
- A **pip resolver/comparator class** (`PipComparator`) determines all interactions
  between pips; every rank/suit comparison funnels through it; mods get asked first
  (`on_compare_ranks/suits`) with numeric fallback.
- Each pip gets its own class for visuals (`PipSuitStandard`, `PipRankNumeral` ✅).
- Design Q&A from the notes, resolved: *can pips have abilities outside the resolver?* →
  Yes, for new scoring methods: each pip class can register static scoring methods as
  defaults for that pip. Pip effects are permanently active (unlike skills).
- **Wild pip** 💭: wild is its own pip class that tracks the previous pip inside itself;
  e.g. randomly chooses itself from pips present on the board/row/column; must update on
  every board change; cycling visuals. Notes' own verdict: worrying about exotic pips is
  premature — the resolver covering stacking + scoring is enough for now.
- **Status array** 📋: add a status dictionary to CardData (effect name → value, e.g.
  a number) processed by rule cards per effect — the general mechanism for debuffs (§20).

**Determinism:** everything must be deterministic; implement an own RNG so the engine
can't change it; seed offsets must themselves be random per-seed (or use a proper
generator) — ref: "Correlated randomness in Slay the Spire 2" (Andy Tockman). 📋
(The worldgen addon already runs fully seeded ✅ on the map side.)

---

## 7. The Spotlight System (card activation)

**Timeline:**
1. Earliest form: "all revealed cards do their abilities."
2. TODO-era: abilities must be **visible to trigger**; a stamp lets a card **trigger even
   when hidden**; **deck triggers** exist and visually surface on top of the deck slot as
   they fire; an activate-condition function per active card tracks when it can activate.
3. **LATEST — "Spotlight" rebrand 📋:** *Active* is rebranded **Spotlight/Focus**: cards
   that are unblocked are "in the spotlight." Descriptions get an icon/text so it's clear
   which conditions need spotlight and which don't (e.g. on-Next effects). This makes the
   always-active stamp less crucial.

**Implementation state:** `CardModifier.is_active()` exists with `StampGlobal` /
`StampRevealing` overrides 🔨 — but the base "active while topmost/unblocked" rule was
never implemented (ARCHITECTURE_REVIEW N5), so ordinary cards' skills are currently inert.
This is the top design-blocking bug.

**Presentation of activation:**
- Cards with skills idly move and **peek over** the card blocking them; blocked active
  cards shift the row below so at least their upper art half shows. 💭
- **Literal spotlight** beams on triggering cards instead of generic glow; possibly dim
  the whole screen during submit. 💭
- Eye stamp (trigger-while-hidden) shows a **miniature of the skill art** inside the stamp. 💭
- QOL "show all active abilities" button: a half-open-eye toggle that pushes stacks apart
  so every spotlit card is fully visible (disabled while holding a stack) — or simpler,
  particle glow / hover motion on active cards. 💭
- QOL "compress board" button: flavorless efficiency view — art stripped to pips + ability
  names in bright white (dim when inactive); picking up a stack becomes a stiff column. 💭

---

## 8. The Rule Deck ("Everything is a card")

The biggest architecture idea in the notes, and it shipped. ✅

**Core concept:** a normally **hidden "Rules Deck"** holds cards that define the default
ruleset — default stacking rules, default scoring rules, input/zone counts, even the
draw-on-Next behavior are each their own card. Changing the rules = changing cards in the
rules deck. Names considered: **The Universal / Fundamental / Rule Deck**.

**Everything that falls out of it (notes' own derivations):**
- A metagame where the player **modifies the ruleset deck during a run** — adding their
  own cards or removing defaults. 📋
- **Boss/negative effects are just temporary cards** added to the rules deck, defined to
  destroy themselves after the game. 📋
- Voucher-type effects go in the **main** deck instead (they're player-side). 💭
- "Baba Is You type nonsense": even *what is visible* from the ruleset deck is defined by
  card effects — a **"Label/Evident" card** announces its effect on the board while the
  deck stays hidden. 💭
- Rule cards get **random suit and rank** in case a player ever extracts them into play. 💭
  Later formalized: rules cards are *not special* — they have a card type whose skill is
  "always global spotlight," and other types can define "return to deck X when Y." 📋
- The Universal deck goes **last in all mod order**, probably. 💭
- Even input slots are cards: `TypeInput` implements "on turn start pass child cards to
  same column, then take random card from deck" ✅.
- **Game laws** are viewable as plain text (a "?" button, top right, grayed out with a
  "you cannot see this yet" hover until unlocked) before the player gains access to the
  rule deck itself 📋 — needed so prop-card abilities can be explained. **Prop cards** =
  cards without feats/skills.
- "Eye of God"-type unlock (prestige) grants **true vision**: seeing all decks and true
  descriptions (§19, §14).
- A deck variant where the **rule deck is empty and all rules live in the main deck**
  (rules get drawn and played like cards!). 💭
- Per-scenario rule decks: **game rules determine what Next and Submit do**; different
  scenarios swap rule decks; edits are permanent for the run. Requires the game class to
  be very flexible. 📋
- **Level rules** deliberation: replace the rule deck with a per-level deck? Resolved NO —
  score goals etc. live outside the rule deck, and making the rule deck build the whole UI
  is scope creep; shops etc. are hardcoded levels. ❌
- Idea: a card that force-triggers a linked on-trigger card whenever tapped (via
  stacking) — notes' own verdict: probably too hard to implement well. 💭
- A "rulesets card pack" unlock letting players build custom rule decks — up to
  re-implementing default solitaire. Notes' own verdict: **design scope creep**; the rule
  deck is better understood as "a way to make certain cards into global effects." ❌
- **VETOED:** making every deck its own playable solitaire board (play the rule deck to
  reorder rules, cover rules, extract cards). Rejected as extremely messy — the player has
  no control over layout in side games, leading to unsolvable boards. ❌

---

## 9. Circus Theme & Vocabulary

The theme pivot arrives mid-notes and becomes the LATEST identity: 📋

| Mechanical term | Circus term (LATEST) |
|---|---|
| Upper zone | **Grand Entrance** |
| Lower zone / play area | **The Ring** |
| Cards | **Performers** |
| Skills | **Feats** |
| Cards without feats | **Prop cards** |
| Scoring | **Exciting the audience** (cheering audio scales with score) |
| Overscore bonus | **Tips** |
| Player | **The Ringmaster** |
| Game laws / rules | **Conventions** (maybe) |
| Active state | **Spotlight** |
| Tap (right-click activate) | **Cue** |
| Booster/expansion packs | **Attraction packs** → LATEST: **Talent packs** |
| Card preview panel | **Presentation stage** (text scrolls, card doesn't) |
| Meta shop | **Carnival** |
| Main menu | Traveling troupe motif |
| Runs/levels | **Shows** at towns/cities on tour |

Reference dumped in notes: Wikipedia's *List of circus skills*. Open theme questions:
should Aces be "the actual performers"? Should rank cap at 10 instead of face cards? 💭

---

## 10. Suits

- **Implemented today:** 4 standard suits (`PipSuitStandard`, palette-shader colored) ✅.
- **Circus suit roster (LATEST plan 📋):** clowns, background dancers, flames, juggling
  balls, hoops, nails/knives — plus special suits: **fireworks** (directly adds points to
  its column based on rank) and **electric** (buffs cards connected/chained in a certain
  way) 💭.

**Suit projectile mechanics (the flagship scoring-flavor idea, 📋):** scored basic cards
summon objects of their suit, sized by rank, at their row/column, which physically move
across the board and interact with other cards:

**Timeline:**
1. v1: knives and hoops fly horizontally across their scored row; balls and fire drop
   down columns. Gain mult for every hoop that passes *through* an animal or acrobat,
   every knife that *misses* a stuntsman, every ball that *hits* a juggler or animal;
   fire *buffs* the cards it passes through.
2. **v2 (LATEST "better balance"):** horizontal projectile is randomly chosen — **knives
   reward hitting non-feat (prop) cards, hoops reward hitting feat cards; balls buff feat
   cards, fire buffs non-feat cards**, with balls/fire spreading their buffs as evenly
   across the column as possible. Fire is dynamic; balls need a juggle animation (circle
   above the card).
3. Consequences noted: most feat cards should be *alive* in some way and somewhat
   individualized; cards dynamically **jump up through hoops and duck under knives**.

---

## 11. Classes, Groups & Leader Cards

**Leader/Champion cards 📋:** start the game already on the board in a free slot (or in
the Entrance) and **don't leave on submit**. Different starting decks ship different
leaders to incentivize different builds. Cards belong to **groups/classes**, and leaders
boost their group.

**The Ringmaster (example leader spec):** no suit or rank; type = "starts the game in the
Entrance" (typical for leaders); stamp = "can always be picked up"; can be placed anywhere
as long as no cards are on top; skill = remains on board after submission (notes muse:
maybe swap which is the skill and which is the stamp). Optional flavor debuffs for
leaders: fear of fire/knives — cannot be placed on fire/knife cards. 💭

**Class list (LATEST, each mapping to a mechanical identity):** 📋

| Class | Mechanical focus |
|---|---|
| Magician | Card creation and deletion |
| Acrobat | Card movement |
| Animal Trainer | Stacking focus — eating cards, cards auto-moving through the field |
| Clown | Pip manipulation |
| Dancer / trick artist | Specific formation focus |
| Escape Artist / Stuntsman | Negative-effects focus |
| Fortune Teller | Deck manipulation |
| Special Effects (fireworks) | Points/combo manipulation |
| Concessions / Food | Positive-effects focus |
| Costume Designer | Equipment/clothing/stamp focus |
| Producer / Manager | Token cards — gold/money cards and basic cards |

This maps 1:1 onto the earlier abstract **skill taxonomy** (pre-theme): new ways to score;
repositioning; amplifying existing points; changing game rules; deck manipulation;
getting rid of unwanted cards; changing how other skills work; effects persisting to next
game (?); creating mini-games (?); creating temporary cards; cards that come at a price.

**Act types** 📋 (deck-position-controlling card types):
- **First Act:** shows up alone, before any other cards.
- **Second Act:** shows up alone after half the deck is drawn.
- **Final Act:** shows up after all other cards are drawn. Possibly carries an extra
  multiplier (or each act's multiplier increases). 💭

Related early note: "some way to guarantee that new cards you choose show up first or
sooner" — Act types are the eventual answer. Also: clicking a card on the (old) map made
it the first card to appear next match — same need, older answer. ❌ (superseded)

---

## 12. Tapping / Cues & Charges

- Card tapping on **right-click** ("Cue" in circus terms). Visual: tappable cards add a
  **glowing halo border**; spent = border removed. Can't rotate the card (no space);
  dimming considered but halo preferred. 📋
- **Halo charge display:** the halo doesn't change size but gains black divider lines by
  remaining uses — 1 tap left `|_._._._._|`, 2 `|_._.|._._|`, 3 `|_._|_._|_._|`. 📋
- **Shared charge system** 📋: all effects use one charge system where applicable, so
  anything with charges can gain/lose them from any source. Example: an acrobatic card
  with 1 charge, triggerable by tap — unused charges auto-spend on Next.
- "Once active, stays active for the rest of the game and can never toggle again" as an
  effect archetype (paired with the "+1 reroll per game; repeated actions won't repeat
  results" card idea). 💭
- Buttons themselves should be cards — shops use the game board; "reroll shop" is a
  tappable card (see Exchange Voucher, §16). 💭
- Info access: reading full card descriptions requires holding a button or an info toggle
  (left/right click are taken; middle-click for mouse users) — also applies inside deck
  view for card packs. 💭

---

## 13. Special Decks & Variants

- **Magic deck:** each suit is an element; cast spells by submitting elemental
  combinations. 💭 (pre-theme; elements later echo in Earth/Air/Water/Fire materials)
- **Survivor deck:** suits are food, water, sword, etc. 💭 (pre-theme)
- **Double Everything deck:** ranks doubled (doubling deck size), double initial slots,
  double score required, card packs doubled. 💭
- **Rules-in-hand deck:** rule deck empty; all rules shuffled into the main deck. 💭
- **Custom deck as the final unlockable deck.** 💭
- Deck unlocks double as Balatro-style **gimmick runs** (one system instead of two tabs). 📋

---

## 14. THE CARD CATALOG (spreadsheet)

Rarity note: the notes only define the rarity *system* (§18), not per-card assignments —
rarity below is given only where the notes imply it. "Era" = early / mid / late position
in the notes (proxy for design recency).

### 14.1 Skills / Feats (player-facing cards)

| Name | Class/Tags | Ability (latest wording) | Rarity | Status | Era / notes |
|---|---|---|---|---|---|
| Extra Point | scoring | Gain extra points per score (currently +10 total on score) | Common | ✅ | Implemented; deck5 tester |
| Echoing Trigger | combo | ALL triggers repeat once (once per card per scoring pass) | — | ✅ | Implemented |
| Hungry Hippo | Animal Trainer | Consumes cards dropped on it, adds their rank to its own, cap 13 total; returns them at game end | — | 🔨 | Implemented but gutted (`on_card_dropped_on` commented out); "clicking on cards modified by abilities" was its TODO |
| Sin of Gluttony | Animal Trainer | Hippo "on crack": no value cap, can be fed from anywhere including decks, **permanently** consumes | Rare+ | 📋 | Mid; explicit hippo upgrade — power-sort rarity example |
| Frankenstein | Magician | On submit, merges with the card above and below into a 3-card merged stack that stays in the zone after scoring | — | 📋 | Early |
| Sliced Bread | scoring | On submission, if a same-suit card is later down the stack, gain a point per card in between | — | 📋 | Early |
| Gold card | Producer, token | Money-token card; heavy — always sinks to the bottom of the deck | Common | 📋 | Early; ties into cards-as-currency (§16) |
| Exchange Voucher | utility | Usable from the deck; swap it with any card on screen | — | 📋 | Mid; origin of "all buttons are cards" |
| Eye of God | god-cycle | See all decks (incl. rule deck) and true descriptions | Legendary? | 📋 | Mid; also a prestige unlock as "true vision" |
| Hand of God | god-cycle | Move cards to any location on board; reorder cards inside a deck | Legendary? | 📋 | Mid |
| Foot of God | god-cycle | Switch locations with any card on screen | Legendary? | 📋 | Mid; alt naming: Third Eye / Third Hand / Third Foot |
| Mystery Box | random | On game start, becomes a random skill | — | 📋 | Late |
| Pandora('s) Box | random | On game start becomes a random skill; on game end resets to Pandora Box | — | 📋 | Late |
| Utter Chaos | random | Becomes a random skill on every Next | — | 📋 | Late; the three form a power-sorted chain |
| HONK | Clown, joke | On cue (tap): makes a honk noise. Unlimited uses | Common | 📋 | Late; pure-flavor tap tutorializer |
| Avalanche | alt-scoring | After scoring, all cards on board attack the scoreboard: goal score reduced by card count | — | 💭 | Mid |
| Storyteller | persistence | Preserve some points into the next game | — | 💭 | Late; relates to "scoring done outside main game carries over" |
| Presentation | formation | Moving cards in ascending order gives multiplier points | — | 💭 | Late |
| Cheat Day | deck buff | Cards remaining in deck get rank-up (reward for winning early with cards to spare) | — | 💭 | Late; "win fast rewards should be card effects" |
| Press Bribery / Memory Wipe | tour, insurance | Extra life: on failing a city, keep going as if you won; maybe straight-up win if saved to the end | Rare+ | 💭 | Late |
| Common (chain) | economy | Doubles chances of Rares appearing | Common | 💭 | Late |
| Rare (chain) | economy | Doubles chances of Epics appearing | Rare | 💭 | Late |
| Epic (chain) | economy | Doubles chances of Legendaries appearing | Epic | 💭 | Late |
| Spiderweb | formation | 1 point per card diagonal to this card, in a cross/X shape | — | 💭 | Mid ("Card ideas" list) |
| Poker Crown (unnamed) | scoring | When scored, this card and the 4 above it are scored as a poker hand | — | 💭 | Mid |
| Column Poker (unnamed) | scoring | Every 5 cards per column is scored as a poker hand | — | 💭 | Mid |
| Genie's Wish | event/consumable | "Make a wish": choose a card to create a copy of in your hand | — | 💭 | Late; framed as a scenario |
| Discard Joker (unnamed) | discard engine | Allows discarding 1 entrance card per turn (upgradable: more discards, more per discard) | — | 💭 | Late (§17 discards essay) |
| Acrobat (unnamed example) | Acrobat, charges | 1 charge; trigger by cue, or auto-spends on Next if unused | — | 💭 | Late; charge-system exemplar |
| Reroll Blessing (unnamed) | meta | +1 reroll per game; "repeated actions will not have the same results" for the rest of the game | — | 💭 | Late |
| Ringmaster | Leader | No suit/rank; starts in Entrance; always grabbable; place anywhere uncovered; survives submission | Unique | 📋 | Late; leader template (§11) |
| Label / Evident | Rule card | Announces its rule-deck effect on the board even while the rule deck is hidden | — | 💭 | Mid (§8) |

### 14.2 Stamps (Seals → Stamps → possibly "Hats"/equipment)

| Name | Effect | Status | Notes |
|---|---|---|---|
| Double Trigger | Card's effects trigger twice | ✅ `StampDoubleTrigger` | From the original Seals list |
| Revealing ("Eye") | Triggers even when hidden/covered | ✅ `StampRevealing` | Visual: mini skill-art inside an eye stamp 💭; the "trigger even when hidden" seal |
| Global | Active from anywhere (incl. decks) | ✅ `StampGlobal` | Descendant of "trigger when in deck" seal |
| Money on Trigger | Gain money (gold cards?) whenever the card triggers | 📋 | From the Seals list; unbuilt |
| Maximum Effort / Exhaust | Double points (or flat points) from this card on score; only refreshes if the card is NOT played/scored next show | 📋 | Late; "kind of like a glass card" |
| Always-grabbable (unnamed) | This card can always be picked up regardless of stack legality | 💭 | Ringmaster's stamp |

### 14.3 Types (materials, deck behavior, structural)

| Name | Effect | Status | Notes |
|---|---|---|---|
| Paper | Default/basic material | ✅ `TypePaper` | |
| Stone | (stub) | 🔨 `TypeStone` (gutted) | |
| Heavy | Sinks to bottom of deck after shuffling | ✅ `TypeHeavy` | Gold cards use this |
| Light | Rises to top of deck | 📋 | Counterpart never built |
| Earth / Air / Water / Fire | Elemental materials with custom movement (top/bottom of stack etc.) | 💭 | Early materials list; echoed by "elemental cards that move around" TODO |
| Input | Zone-header type: on Next, drops its stack to the paired lower column, then draws | ✅ `TypeInput` | The "even input slots are cards" principle |
| Booster / Talent pack | Card-pack generation on the map | ✅ `BoosterTemplate`, `TypeBoosterBasic` | |
| First / Second / Final Act | Deck-position control (§11) | 📋 | |
| Leader | Starts on board / in Entrance; group-boosting | 📋 | §11 |
| Immovable (unnamed) | Resists being moved | 💭 | |

### 14.4 Rule cards (the hidden deck)

| Name | Rule provided | Status |
|---|---|---|
| Input Adder (upper) ×N | +1 Entrance input column each | ✅ `SkillAdderInputUpper` |
| Zone Adder (lower) ×N | +1 Ring column each | ✅ `SkillAdderInputLower` / `ZoneAdder` |
| OG Grabber | Default grab legality (asc/desc, no same suit) | ✅ `SkillGrabberOgLower` |
| OG Placer | Default placement legality | ✅ `SkillPlacerOgLower` |
| Cascade Scorer | The whole-board row/column scoring pass | ✅ `SkillScorerCascadeLower` |
| Poker Evaluator | Best-poker-hand evaluation per line | ✅ `SkillEvalPokerBest` |
| Boss/hazard rules | Temporary negative rule cards, self-destruct after game | 📋 |
| Ruleset defaults (stacking/scoring/etc.) as swappable cards | | ✅ pattern established |

### 14.5 ⚠️ Summary-only cards (invented by the appended auto-summary, not user-authored — adopt or reject deliberately)

| Name | Claimed effect |
|---|---|
| Helium Card | Named version of the Light material (rises during Next) |
| The Acrobat | Grabbable even when covered |
| The Anarchist | Disables all other Rule cards while in the Ring |
| Ghost Card | Doesn't block Spotlight for cards beneath it |
| Searing Knife | On score, burns its column — locked for 2 turns |
| Sliced Reality | Splits a column into two / merges two into one |
| Tappable Clown | 3 taps: randomize adjacent cards |
| Symmetrical Show (rule) | Poker hands also evaluated vertically — *this one IS user-authored* ("ability where poker hands are also considered vertically") |
| Wildcard Pip | Adopts rank/suit of the card below — near-duplicate of the user's wild pip (§6) |

---

## 15. Map & World Structure

**Timeline:**
1. **v1 — Minesweeper board ❌:** Deadman Wonderland-inspired (collect number cards, then
   face the boss face-cards). Full deck laid out face-down; can only click a card adjacent
   to a revealed one; clicking = battle for the card + reveals neighbors; win by uncovering
   all. Locations marked by single collectible special cards; suit/rank = difficulty/type;
   special squares (e.g. all 7s are shops); square layout with probability rings (higher
   ranks likelier in the middle). Clicking a map card made it the first card dropped next
   match.
2. **v2 — Triangle map ❌ (superseded but ✅ built — `triangle_map.gd`):** choose from the
   next 3 card options; picking moves you up a tier; play a match; repeat, always keeping
   the triangle shape. Moving left permanently loses the right lanes, middle loses both
   outer lanes. Every few rows a **boss phase**, drawable as terrain; fights maybe only at
   boss phases; render 2D→3D tilted viewport. Later additions: triangle can have **holes**;
   nodes should contain **card packs**, not just single cards. Critique that killed it:
   players can dodge hazards too freely; would need artificial funnels (mountains/forests).
3. **v3 — Biome tour sketches 💭:** "level/act/world" structure à la One Step From Eden —
   traveling through biomes, each biome affecting map generation; Umamusume-style **fame
   gates** every ~10 levels; "going on tour" theme with **fog of war** on further choices;
   negative weather effects ("the show must go on").
4. **v4 — FTL constellation world tour (LATEST 📋, map tech ✅ via worldgen addon):**
   go back to FTL roots — a constellation/DAG map over a world, **no backtracking**;
   thematic: touring the world city to city building **fame**; cities in crazy locations;
   environmental hazards; surprise weather en route. Players open by **planning their
   tour** (choosing cities); beginners plan small tours, veterans longer routes.
   Steel Ball Run framing: cross the map building fame before the final city.
   - Small towns vs big cities have different score requirements.
   - **Overscoring ramps future requirements** — player balances declaring big
     (fame wagering) vs the risk of failing the declared score.
   - Total fame improves rarity odds of card offers.
   - Finishing the final city wins and unlocks **endless mode** (repeat the final city
     until you lose, guaranteed repeating choices between shows).
   - Alternatives mused: no final city, circle the map; or must return to start; visited
     points become revisitable after enough time passes. 💭
   - **Hype mechanic:** voluntarily double the fame required for the next show for better
     goodies. 📋

**Implementation state:** the `worldgen` addon generates the seeded heightmap world
(Landmass → Tectonics → Peaks&Valleys → Erosion → Rivers → Graph) with an interactive DAG
overlay (`WorldGraphOverlay` / `WorldGraphNode`), ferry edges, start/end nodes, threaded
loading, and JSON baking. ✅ The Solatro-side hookup (nodes = towns/packs/events, fame,
fog of war) is not yet wired. 📋

**Map content & UX notes (all still current 📋/💭):**
- Nodes offer **card packs** or occasionally rarer **single cards**; card packs show at
  least 1 guaranteed card in the map preview; **disaster card packs** can appear on the
  board to choose from.
- Clicking a map node shows a preview + a separate confirm-travel button.
- Unlock more biomes / extended routes with meta progress (notes flag this as "Mewgenics
  system, which is not good... maybe OK since endless mode exists as the maximizer"). 💭
- **Multithread pre-generate maps** with random seeds at game start, before the player
  presses play, one per map size. (Addon already threads generation ✅.)
- Procedural pixel visuals: wave-function collapse / min-conflicts to fill biomes
  (villages pre-seeded); extrude-2D shader + heightmap for a topographic miniature-model
  look; slopes by cutting one pixel ring per layer. 💭 (Addon took the
  heightmap-colorizer road instead ✅.)
- Choose-cards screen: Star-Wars-scroll motion — cards scroll down as you pick, new ones
  appear on top. 💭

---

## 16. Economy & Shop

- **Cards ARE the currency** — no abstract gold; trading in cards. 📋 Gold cards are
  token cards (heavy, sink to deck bottom) minted by Producer-class effects / money-on-
  trigger stamps.
- **Shop design 📋:** shop shows purchasable cards on top; **cost is a stack of cards at
  the bottom**, randomly chosen from your deck to be equivalent to the price — so buying
  doubles as **deck thinning**, while map card packs add cards. Shops also sell packs.
  Reroll/refresh costs increase per use.
- **Mana cards** (MTG-style): any card can be a resource instead of a mana bar. 💭
- Shops should be built out of the game board itself; every button is a card (reroll =
  tappable card; Exchange Voucher pattern). 💭
- **Carnival = the meta shop** (§19). Spending prestige to improve odds also raises the
  score required per show — "with more attractions, more people are gonna show up!" 📋

**Pricing philosophy:** card power/cost must sit on an **exponential curve** — stronger
cards priced *cheaper than linear scaling would suggest*, because high cost = low
flexibility, and flexibility is part of a card's budget; cheap cards must stay weak since
they're maximally flexible. 📋

---

## 17. Turn Resources: Discards, Undo, Rerolls

- **Discards essay (LATEST 📋):** discards are a lot of fun — make them a main method of
  building the board. Repeatedly discard cards in the Entrance until you get what you
  want, then let them drop. Probably an obtainable upgrade chain (more discards, more
  cards per discard); the game (or a joker) starts you at 1 discard/turn. Enables
  gambling for a better entrance hand and a direct route to feed the discard pile.
- **1 free undo per turn**, not carrying over, baked in by default. 📋 (undo system ✅
  exists via state snapshots.)
- **+1 reroll per game** effect; "repeated actions will not have the same results." 💭
- Cards **cannot retire** (be sold/removed?) until scored or their ability has activated —
  more likely: until an ability activation; no condition if no ability. 💭

---

## 18. Rarity, Card Packs & Collection

- **Card spreadsheet plan:** title, rarity, cost-in-cards, description, tags. (This
  document's §14 is that spreadsheet's first draft.)
- Rarity visuals: different borders per rarity; different shines; maybe holographic
  effects. 💭
- **Power-sort rarity 📋:** create many common base effects, then better versions of each
  effect as separate cards; rarity is determined by how far the effect climbed
  (Hippo → Sin of Gluttony; Mystery Box → Pandora Box → Utter Chaos; Common→Rare→Epic
  chain cards).
- **Talent packs (boosters):** instead of pick-1, you **mulligan the results** arena-style;
  pack contents previewable so you know what you're mulliganing toward; mulligan count is
  upgradable; a card effect can grant entrance-mulligans on cue. Results can be upgraded —
  bonus types and stamps on top (needs its own viewer). If you've never seen an effect,
  the viewer shows a **question mark** for it. 📋
- Pack opening shows all possible pack contents in the background — maybe slot-machine
  styled; results always seed-fixed. 💭
- **Secret melds** to discover — implies cards with secret on-add-to-deck effects that add
  new rules. 💭

---

## 19. Meta Progression

The notes' retention essay: progression systems (levels, equipment, prestige, unlocks)
work outside monetization; slow-drip them; don't multiply the *number* of systems beyond
what a player tracks, but any single system can go infinitely deep; add QOL to skip
time-consuming old mechanics as new ones appear (gacha pattern).

**Planned systems (all 📋 unless noted):**
1. **Card unlocks** — dual system: (a) specific in-game actions unlock specific cards;
   (b) a threshold/achievement-pass track (e.g. "play 20 unique cards", "win 5 games" all
   feed one bar, order-independent) unlocking commons via generic progress while rare
   cards unlock by playing specific genres/archetypes.
2. **Prestige (Vampire Survivors-style)** — wins grant currency spent in the **Carnival**
   meta-shop: manipulate odds of cards/events on the map (letting players shape the map),
   more starting cards/rerolls/undos, start-with-card options; unlock **true vision**
   (see rule deck + true descriptions); maybe buy guaranteed-appearing cards or new packs;
   a super-expensive full reset of unlocks for meta-levels; unlock the custom deck editor.
   Caveat: spending raises per-show score requirements (§16).
3. **Deck unlocks** — as Balatro, merged with gimmick-run concepts (§13).
4. **Ascensions** — Balatro/StS-style; overlap warning with prestige debuff-for-points;
   resolution: each ascension adds a chosen negative card into the deck or rules deck —
   a good home for boss-fight environmental-hazard cards made permanent.
5. **Community, lore & secrets** — skeptical about cosmetics/campaign ("what would the
   story even be for such an abstract game? like writing a campaign for Tetris") but:
   wins/actions unlock lore scraps full of drama and romance 💭; cosmetics = background
   variety 💭; **secrets and mysteries drive engagement even without answers** — include
   them. 📋
6. **Event-recycled prestige:** an in-run event granting *temporary* prestige points to
   allocate, reusing the meta system mid-run. 💭
7. **Retire button** in settings to end a run early ✅-adjacent (trivial); "cards cannot
   retire until..." rule in §17.
8. **Persistence hooks:** scoring done outside the main game carries into the next game;
   Storyteller card preserves points between games. 💭

---

## 20. Difficulty, Bosses & Win Conditions

**The optimization essay (LATEST design position):** deckbuilders facing an
ever-increasing number push players to hyper-focus on number-go-up; the most fun part is
paradoxically *before* the deck is optimized (narrow wins, skill = narrowly avoiding
losing); an optimized deck plays itself. Explorations:
- Alt win cons tied to formations? Rejected: they don't scale, and a crafted deck
  guarantees the formation every time. ❌
- Resolution: **this is what Balatro boss blinds are for** — negative effects that test
  deck *resilience* and punish hyperfocus (same role as StS enemy gimmicks). ✅ as design
  direction: **towns with cases/hazards** — Knifetown is unimpressed by knife scoring
  (knives score 0 there), same for Firetown/Juggletown/Hooptown; performing at a volcano
  adds lava hazards. Boss effects = temporary rule-deck cards (§8).
- Map must limit hazard-dodging (a triangle-map flaw that motivated the FTL map, §15).

**Other difficulty levers:**
- Score goal increments per match (currently ×1.1 per layer ✅, tune later).
- Fame wagering / Hype (§15) — self-selected difficulty for reward.
- Progress gates behind occasional **extreme high scores** that demand luck or
  complicated cards — pushing players toward dynamic, animated decks; maybe rewards
  larger maps. 💭
- **Quests** (TFT set 16): extremely random conditions causing permanent effects;
  emphasis on "unlocking"; effects that upgrade themselves into better versions when
  conditions are met. Notes' own question: is this actually different from effects in
  general? 💭
- Debuffs, Mewgenics-style 💭: cards can catch statuses — **Exhausted** (lose a rank at
  round end if it appeared on board), Cancer?, Parasites!? Implemented via the status
  array (§6). Win-fast rewards should be card effects (extra gold cards, buff remaining
  deck — Cheat Day) rather than systemic, to avoid rewarding min-maxing too hard.

---

## 21. Events & Encounters

- **Genie scenario:** make a wish — e.g. choose a card to copy into your hand. 💭
- **History-driven events:** triggered by run behavior — sacrificing too many talents →
  **union strike**; hoarding too many cards → **tax evasion** (lose a portion of basic
  cards). 💭
- **Mini-game events:** score is not the goal; alternate-win-con puzzles ("trigger 5
  times to win"). Encounters as mini solitaire games somehow. 💭
- **Forbidden-solitaire variant** (click cards to send to hand) as an event mode. 💭
- Events can grant temporary prestige points (§19). 💭

---

## 22. Presentation, Art Direction & Juice

**Art direction timeline:**
1. Early: 3D-ish motion, hovering cards.
2. **LATEST (post-Titanium Court):** stylized **static** look; hovering animation removed
   except side-to-side; 3D motion reserved for special cases; picking up a stack is
   static too; compensate with **heavy SFX**. 📋

**Visual ideas (all 💭/📋):**
- Dot-art starfield background with flow; card art reused as background elements;
  background shows every in-play card's art launched fruit-ninja style from cannons at
  the screen edges, some with spin.
- At round end, discarded board **swirls into the score numbers** as they tally.
- On game end, cards from everywhere **tornado into the main deck**.
- When attacking/scoring, all cards rise up and begin hovering; scored cards rise;
  triggered effects do a little **hop-n-shake**; triggered effects show their parent card
  in the preview; when an effect plays, its **art pops up in the background** like it's
  being performed.
- Screen shake on score; as bigger scores land, the screen shifts toward the cards, away
  from the buttons.
- Goofy travel animations (spin/bounce across screen) for ability cards; cards slot into
  place like folders into a cabinet; smoother = more satisfying; **the cards are alive**.
- Crunchy sounds (Inscryption act 2 benchmark); cards slightly attracted to the cursor;
  party effects; literal spotlights + screen dim on submit (§7).
- Card-pack opening slot machine (§18). Rarity borders/shines/holo (§18).
- Choose-card screen Star-Wars scroll (§15).

**Technical/pipeline notes:** data layer populates both UI and card layer ✅ (that *is*
the architecture); a static texture class holding all images + their h/v frames in one
file 📋; card **node-parenting was removed** (tween/inheritance headaches) ✅; `on 
data_selected` needs override handling 📋; reuse the heck out of card art 📋.

---

## 23. The Appended Summary & Research Appendix

The notes end with an auto-generated summary the author disclaims. Assessment:
- Its "Vision / Gameplay / Architecture" sections are broadly accurate but add nothing
  beyond what §1–§8 already cover from primary notes.
- Its "Ultimate Effect Repertoire" **invents several cards** never present in the user's
  notes — cataloged in §14.5 with a ⚠️ flag so they can be adopted or rejected on purpose
  rather than laundered in as if original.
- Its final **Seed Systems / Pool Systems / Unlock Systems** research (PRNG streams,
  predetermined item queues, hierarchical pools, anti-repeat arrays, act-based rarity
  escalation, weight decay, ban lists, roll-first-then-discard unlock filtering, etc.)
  is genuinely useful reference material for §6 determinism, §18 rarity, and §19 unlocks —
  keep it as an appendix in the original file; the actionable takeaways for Solatro:
  1. Independent RNG streams per subsystem (map, shops, packs, in-match shuffles).
  2. Predetermined item queues make seeds shareable/speedrunnable (Balatro precedent).
  3. Roll-first-then-discard keeps shared seeds stable across different unlock profiles.
  4. Anti-repeat + dynamic weight decay keep offer variety fresh (Hades precedent).

---

## 24. Abandoned / Vetoed Ideas Registry

| Idea | Era | Why dropped |
|---|---|---|
| Cribbage scoring (15s/31s, face=10) | Early | "15s too hard to see" → demoted to potential ability/pip |
| Deck-click drop loop with right-side score slots | Early | Superseded by whole-board submit |
| Submission spot for illegal stacks | Early | Zone removed with loop v2 |
| Minesweeper/Deadman Wonderland map | Early | Superseded by triangle, then FTL map |
| Triangle map (built!) | Mid | Too easy to dodge hazards; superseded by FTL/StS worldgen map |
| Map-card click seeds first drop of next match | Early | Loop changed; Act types cover the need |
| Every deck playable as its own solitaire board | Mid | "Extremely messy"; unsolvable side-boards |
| Custom rule decks up to re-implementing real solitaire | Mid | Scope creep; rule deck = global-effects vehicle instead |
| Level deck replacing rule deck | Late | Score goals live outside rules; UI-from-cards is scope creep; hardcode shop/levels |
| Scoring UI implemented as cards / UI-manipulation win con | Mid | No good duplicate/remove design |
| Formation-based alt win cons | Late | Don't scale; guaranteed once deck is crafted; boss-blind-style resilience tests instead |
| Card node-parenting (engine) | Mid | Inheritance/tween headaches; removed in code |
| 3D hover-heavy card motion | Late | Static stylized + SFX direction chosen |
| 15s as default scoring | Early | See cribbage row |
| Mana bar | Late | Mana *cards* / any-card-as-resource instead |

---

## 25. Cross-Reference: Notes → Code Reality Check

### 25.1 The prototype TODO list from the notes, tracked

| TODO item (notes) | Status |
|---|---|
| Menu + settings — copy Balatro's for now | 🔨 menu exists |
| Map: choose cards to add to deck (Star-Wars-scroll pick UI) | 🔨 map/choice viewer exist; scroll motion 💭 |
| Return from end of match to map | ✅ |
| Increment total score needed per match; games-won tracker on map | ✅ goal scales ×1.1/layer; tracker 💭 |
| Infinite number class | ✅ `BigNumber` |
| Deck viewer on deck hover — dynamically create temp cards while scrolling (don't keep massive decks loaded) | ✅ `deck_viewer.gd` |
| Future-cards viewer — above the insert slots (preferred) rather than in deck viewer | 📋 |
| Deck viewer sorter | 📋 |
| Deck viewer must show **effect order** even when the deck is randomized — an effect-viewer for skills only (could itself be a skill) | 💭 |
| Deck Maker — create/save decks for testing | ✅ `deck_builder.gd` |
| Save ability | ❌ not yet (`PlayerSave` never written to disk — review N10) |
| Hidden-trigger stamp; deck triggers surfacing on the deck slot | 🔨 `StampRevealing`/`StampGlobal` exist; deck-slot visuals 📋 |
| Only first poker hand scores | ✅ |
| "Any card can be placed on this card" ability; Hippo card; elemental movement types | 🔨 resolver supports it; Hippo gutted; elementals 💭 |
| Every 5 rows red / increase points by layer | 💭 → matured into Performance Rings (§5) |
| Check scoring in deck and discard | 💭 |
| Add all cards to map | 🔨 map offers exist |

### 25.2 Where the dream and the build currently disagree (from `ARCHITECTURE_REVIEW.md`)
- **Spotlight default ("active while unblocked") is unimplemented (N5)** — most non-rule
  card skills are inert today. This blocks nearly all of §14.1.
- Rule-deck-driven layout, input-as-cards, resolver-based legality, whole-board cascade
  scoring, BigNumber, undo, deck/choice viewers, booster templates: ✅ all real.
- Triangle map is built but the design has moved to the worldgen FTL map — porting the
  map screen is the biggest open integration task.
- Deterministic RNG streams (§6/§23) not yet implemented on the game side.
- Card-pack mulligan flow, shop, economy, meta progression, leaders, acts, suit
  projectiles, circus renames: not started.

# Taxonomy codes — tag every effect with EXACTLY ONE of these


## A — Scoring — the number itself

- `A1` **Flat point add** — adds chips to the line or the total
- `A2` **Additive mult** — +mult; the game already grants +1 per triggered effect by default
- `A3` **Multiplicative mult** — ×mult
- `A4` **Higher operators** — ^mult, tetration, e-notation — a whole tier the corpus never reaches for
- `A5` **Retrigger** — re-score a card, a line, or a whole hand
- `A6` **Score redirect** — points earned by one line are banked to a different line or label
- `A7` **Scoring gate** — only the first hand scores; or only if a condition holds
- `A8` **Negative scoring** — negative ranks and negative props actually subtract
- `A9` **Deferred payout** — score is held and paid on a later trigger
- `A10` **Score conversion** — points become gold, fame, heat, or charges
- `A11` **Floor / ceiling / rounding** — clamp, round, or truncate a line's score
- `A12` **Combo-counter manipulation** — the +1-per-unique-effect combo is itself a target
- `A13` **Comparative scoring** — the highest- or lowest-scoring line this show gets something

## B — Melds — what counts as a hand

- `B1` **New meld types** — mahjong triplets, cribbage 15s, marriages, blackjack 21, sudoku, tetris shapes
- `B2` **Meld leniency** — wilds, gap-tolerant straights, 4-card flushes
- `B3` **Meld denial** — this hand type scores nothing — the boss-blind shape
- `B4` **Rank wrap / equivalence** — K-A-2 straights; roman numerals wrapping at 12
- `B5` **Suit equivalence** — wild suits, two-suit cards, colour-only matching
- `B6` **Hand levelling** — a hand type permanently gets better over the run
- `B7` **Hand-selection rule** — score every hand, vs best hand, vs first hand only
- `B8` **Secret melds** — hands the player has to discover
- `B9` **Per-run meld set** — American-mahjong style: which hands are worth playing changes each run
- `B10` **Line-length redefinition** — lines longer than 5; lines that run across grids

## C — Grid geometry & lines

- `C1` **Which lines score** — rows, columns, the two long diagonals, height columns, height diagonals
- `C2` **Extra lines granted** — short diagonals, knight-shapes, rings, the border
- `C3` **Re-score on disturbance** — removing and re-adding a card re-fires its line
- `C4` **Cell modifiers** — an empty cell that alters the next card placed on it — the mancala idea
- `C5` **Prefilled cells** — hazards, holes, bombs, blocked slots the grid starts with
- `C6` **Grid shape change** — non-5×5 rings, grids with holes, grids that grow
- `C7` **Cross-grid lines** — a row that runs through every grid at the same y
- `C8` **Grid count manipulation** — unlock an extra grid, lose one, merge two
- `C9` **Commitment rules** — which grid the entrance feeds, and when you may switch
- `C10` **Adjacency effects** — a card reads its orthogonal and diagonal neighbours
- `C11` **Region / shape effects** — scores per card in a cross, donut, plus, or 3×3 around it
- `C12` **Coordinate effects** — effects keyed to literal x, y, grid index, or height
- `C13` **Parity & pattern** — checkerboard, every 5th row, edge vs centre, corners

## D — Height — the fourth coordinate

- `D1` **Stacking legality** — what may be placed on what
- `D2` **Pickup legality** — which stacks may be lifted, and from where
- `D3` **Height-line scoring** — five aligned at the same height, or five in one x,y column
- `D4` **Compaction** — what happens to the cards above when one is removed
- `D5` **Position-in-stack rules** — must be top, must be bottom, must be buried
- `D6` **Active while covered** — blocks_spotlight — cards that WANT to be buried
- `D7` **Consumption** — eat the card above and gain its rank
- `D8` **Merge / fuse** — two or three cards become one
- `D9` **Stack as one card** — the whole column is treated as a single entity for a rule
- `D10` **Height caps** — a ceiling on stack height, and effects that raise or lower it

## E — Movement & repositioning

- `E1` **Self-move** — the card relocates itself on a trigger
- `E2` **Move another card** — push, pull, swap, teleport
- `E3` **Board transforms** — rotate, flip, mirror, scramble, shift a whole row or column
- `E4` **Gravity rules** — floats up, sinks down, slides until blocked
- `E5` **Patterned movement** — chess pieces, checkers hops, knight jumps
- `E6` **Cross-grid movement** — move five left and land in the same cell of the next grid
- `E7` **Anchoring** — this card cannot be moved
- `E8` **Placement restriction** — must touch an existing card; one card per column per refresh
- `E9` **Mid-flight interception** — a card changes destination while it is travelling
- `E10` **Position memory** — remembers a slot and returns to it when it opens

## F — Deck, draw & order

- `F1` **Deck position control** — heavy sinks, light rises, First / Second / Final Act
- `F2` **Tutor / search** — pull a specific card out of the deck
- `F3` **Peek** — see the next N cards
- `F4` **Deck ordering** — sort or reorder the undrawn pile
- `F5` **Entrance manipulation** — mulligan, discard, reorder, force a refill
- `F6` **Entrance size** — more or fewer input slots
- `F7` **Discard recursion** — pull cards back out of the discard pile
- `F8` **Shuffle control** — reseed, or make repeated actions stop repeating
- `F9` **Fires from the deck** — triggers while still undrawn
- `F10` **Fires from the discard** — triggers after it is gone
- `F11` **Deck-size scaling** — strength depends on how many cards remain

## G — Creation, destruction & transformation

- `G1` **Create a card** — into the deck, the entrance, or the grid
- `G2` **Create a temporary card** — expires after N shows or on a condition
- `G3` **Copy another card** — clone its pips, its skill, or the whole card
- `G4` **Destroy / exhaust** — remove from the board, the deck, or the run
- `G5` **Transform a slot** — overwrite a card's suit, rank, type, stamp, or skill
- `G6` **Randomize** — reroll one or more of a card's slots
- `G7` **Split** — one card becomes two
- `G8` **Self-upgrade** — improves itself permanently when a condition is met
- `G9` **Conditional metamorphosis** — becomes a different card entirely on a trigger
- `G10` **Graveyard recovery** — retrieve something that was destroyed
- `G11` **Token generation** — gold cards, blanks, basics

## H — Meta-effects — modifying other effects

- `H1` **Copy a skill** — borrow another card's talent
- `H2` **Retrigger a skill** — fire another card's talent again
- `H3` **Amplify another effect** — fire stacks multiply the props a card spawns
- `H4` **Suppress an effect** — turn another card off
- `H5` **Redirect a target** — the other card's effect lands somewhere else
- `H6` **Rewrite a trigger** — turn an on-score effect into an on-place effect
- `H7` **Count other effects** — the uniqueness multiplier; N distinct effects this show
- `H8` **Resolution order** — force this card to resolve first, or last
- `H9` **Read or edit the rules deck** — a card that reaches into the hidden defaults

## I — State, charges & persistence

- `I1` **Charges** — limited uses, spent by tapping
- `I2` **Charge economy** — effects that grant, steal, or share charges across cards
- `I3` **Cooldowns** — once per line, once per act, once per show
- `I4` **Growth** — gets stronger each time a condition is met
- `I5` **Decay** — gets weaker, or breaks, with use
- `I6` **One-shot / exhaust** — fires once and is spent
- `I7` **Carries to next show** — state survives the match boundary
- `I8` **Carries to next run** — state survives the run boundary
- `I9` **Latching** — once switched on it can never be switched off
- `I10` **Apply a status** — burning, juggling, wet, frozen, injured, marked
- `I11` **Status spread** — fire spreads along a row; a hurricane walks the grid
- `I12` **Cleanse / immunity** — remove a status, or refuse to receive one

## J — Economy & resources

- `J1` **Gold generation** — earn currency from play
- `J2` **Costs & taxes** — an effect that charges you to use it
- `J3` **Interest** — compounding on held currency
- `J4` **Selling** — liquidate a card for value
- `J5` **Shop manipulation** — reroll cost, stock size, rarity odds
- `J6` **Cards as currency** — pay with cards rather than gold
- `J7` **Second currency** — fame, heat, prestige — earned and spent separately
- `J8` **Debt** — go negative and owe it back
- `J9` **Price setting** — change what another card costs

## K — Turn resources & flow

- `K1` **Discards** — how many, and how strong each one is
- `K2` **Undo** — how many, and what may not be undone
- `K3` **Rerolls** — of the entrance, the shop, or a random result
- `K4` **Acts / submits** — how many scoring passes the show gets
- `K5` **Patience clock** — the audience's attention drains per action and forces a drop at zero
- `K6` **Time / tempo** — state that advances one step per player action — the clockwork rank
- `K7` **Free actions** — a placement that consumes nothing
- `K8` **Phase manipulation** — reorder or skip a phase of the turn
- `K9` **End early** — stop the show now and keep what you have

## L — Risk, gambling & failure

- `L1` **Coin flip** — 1-in-N chance of a bigger payout
- `L2` **Odds manipulation** — improve every probability roll
- `L3` **Injury stacks** — failure accumulates and escalates toward a permanent loss
- `L4` **Permanent retirement** — a card can be lost from the run for good
- `L5` **Insurance** — prevent one loss
- `L6` **Double or nothing** — stake what you have on one more roll
- `L7` **Declared bets** — commit to hitting exactly N melds before the show starts
- `L8` **Crit chance** — a chance for any trigger to pay extra
- `L9` **Cursed cards** — a strong effect with a standing price
- `L10` **Sacrifice** — destroy something of yours to pay for it

## M — Information & visibility

- `M1` **Reveal** — see the rules deck, the deck order, or true descriptions
- `M2` **Conceal** — hide cards, hide the board, fog
- `M3` **Face-down play** — the flip is implemented; almost nothing uses it
- `M4` **Prediction** — name an outcome now, get paid if it happens later
- `M5` **Marked cards** — always know where one specific card is
- `M6` **Misinformation** — the displayed value is not the real value
- `M7` **Inspection as a cost** — looking at something costs an action or a resource

## N — View, camera & UI

- `N1` **Zoom control** — force the zoomed-out view, or lock the player into one grid
- `N2` **Pan restriction / grant** — which grids you are allowed to look at
- `N3` **View transforms** — flip the board vertically, mirror it, rotate it — for show or for real
- `N4` **Abstraction mode** — strip the art and show only pips and effect names
- `N5` **Obscuring** — darkness, fog, spotlight-only visibility
- `N6` **Score-label manipulation** — hide totals, show them late, add or remove labels
- `N7` **HUD manipulation** — hide the goal, the deck count, or the combo counter
- `N8` **Display / logic divergence** — where a card LOOKS is not where it IS
- `N9` **Frame effects** — the screen is a picture on a wall; the frame itself can carry rules
- `N10` **Input remapping** — a card that changes what a button does

## O — The rule deck

- `O1` **Add / remove a rule card** — mid-run edits to the hidden deck
- `O2` **Change stacking defaults** — rewrite what a legal build is
- `O3` **Change scoring defaults** — rewrite how a line resolves
- `O4` **Change board layout** — zone count, entrance count, grid count
- `O5` **Change what the buttons do** — redefine Submit and Next
- `O6` **Rule visibility** — make a hidden rule announce itself, or hide a visible one
- `O7` **Grid-local rules** — a rule that applies to one grid only
- `O8` **Venue rules** — town and boss rules delivered as rule cards

## P — Class, group & set synergy

- `P1` **Class-count scaling** — N Clowns on the board makes something happen
- `P2` **Leader / champion** — a card that boosts its own class
- `P3` **Cross-class interaction** — Clowns buff Dancers; Animals flinch from Knives
- `P4` **Class exclusion** — two classes cannot share a grid
- `P5` **Set collection** — collect all N of a named set for a bonus
- `P6` **Class conversion** — make a card count as a different class
- `P7` **Tier thresholds** — autochess-style 2 / 4 / 6 breakpoints
- `P8` **Grid-local class synergy** — the class bonus counts only within one grid
- `P9` **Class-restricted cells** — only an Acrobat may be placed here
- `P10` **Named rivalries** — two specific cards that care about each other

## Q — Props — the spawned objects

- `Q1` **Spawn count / rate** — how many props, and from what
- `Q2` **Travel path** — row sweep, column drop, arc, chain-hop, mancala walk
- `Q3` **Prop-on-card** — score it, buff it, damage it, apply a status
- `Q4` **Prop-on-prop** — props that collide, merge, or deflect each other
- `Q5` **Persistence** — a prop that survives its line, or loops the grid
- `Q6` **Redirection** — deflect an incoming prop
- `Q7` **Cross-grid travel** — a prop that leaves its grid and enters the next
- `Q8` **Inheritance** — props inherit their spawner's statuses

## R — Hazards, bosses & adversity

- `R1` **Suit / rank / class debuff** — this suit scores nothing here
- `R2` **Board attrition** — cards eaten, burned, or stolen over time
- `R3` **Escalating timer** — a threat that grows each turn until it is answered
- `R4` **Forced actions** — you must place here; you must discard
- `R5` **Requirement gates** — you must play a specific hand to progress
- `R6` **Goal manipulation** — the score you need moves mid-show
- `R7` **Area hazards** — donut, expanding snake, walking storm
- `R8` **Boss randomisation** — which boss, and with what modifier
- `R9` **Counterplay cards** — the extinguisher, the umbrella, the net

## S — Map & run structure

- `S1` **Node reveal** — see further ahead through the fog
- `S2` **Route manipulation** — extra choices, backtracking, skipping
- `S3` **Node conversion** — turn a show into a shop
- `S4` **Biome / town effects** — where you play changes how you play
- `S5` **Reward manipulation** — better packs, guaranteed rarities
- `S6` **Between-show effects** — repair, upgrade, tax
- `S7` **Extra life** — survive one failed city
- `S8` **Run length** — a longer tour, more shows
- `S9` **Hype / stakes** — raise the goal yourself for a better reward

## T — Cross-show & meta

- `T1` **Carry score forward** — banked points survive into the next show
- `T2` **Carry card state forward** — a card remembers what it did
- `T3` **Unlocks as effects** — doing X permanently adds Y to the pool
- `T4` **Prestige currency** — meta points spent between runs
- `T5` **Ascension / stake modifiers** — opt-in difficulty that changes rules
- `T6` **Once per profile** — an effect usable once, ever

## U — Minigames & alternate win conditions

- `U1` **Trigger a minigame** — fishing, connect-4, wordle, a duel
- `U2` **Alternate win condition** — win by something other than the score bar
- `U3` **Puzzle objectives** — trigger five times; build this exact formation
- `U4` **Quest chains** — objective B only unlocks after objective A
- `U5` **Duel / one-upmanship** — an alternating call-and-response contest

## V — Identity & the resolver

- `V1` **Rank comparison override** — blank always stacks; wild always matches
- `V2` **Suit comparison override** — counts as every suit, or as none
- `V3` **Rank scale change** — negatives, decimals, 1–99, roman wrap at 12
- `V4` **Suit-set change** — five suits, two-suit cards, colour-only
- `V5` **Non-transitive comparison** — rock-paper-scissors stacking legality
- `V6` **Board-derived identity** — this card's suit is whatever its neighbour's is
- `V7` **Rank arithmetic** — halves, doubles, sums of adjacent ranks

## W — Feel-only

- `W1` **Sound / visual only** — HONK; no mechanical consequence
- `W2` **Presentation change** — alters the background, the music, or the card art

# SOLATRO — Claude's Recommendations & Expansion Ideas

Companion to `DESIGN_DOC.md` (the organized record of your ideas). Everything in THIS file
is my interpretation, recommendation, or invention — kept separate on purpose so it never
contaminates the record of what you actually designed. Written 2026-07-05 against the
code of that date — implementation-status remarks (e.g. "fix N5 spotlight", "wire the
worldgen map", §12 build-order steps 1–3) are OUTDATED: spotlight, the worldgen map/run
layer, suit props, and the combo scoring formula have since shipped (see
ARCHITECTURE_REVIEW.md). The design proposals themselves remain live material.

---

## 1. How I read your design (what the game actually is)

Three pillars carry this game, and they're all already in your notes:

1. **Spatial deckbuilding.** Balatro's genius is "poker hand + modifiers"; your genius is
   that *position* matters — rows, columns, stacks, covering. No Balatro-like has this.
   Every card you add should ask the player a *placement* question, not just a
   *selection* question. The spiderweb card, performance rings, suit projectiles, and
   formation classes are the best ideas in the notes for exactly this reason.
2. **"Everything is a card."** The rule deck isn't just architecture elegance — it's the
   endgame content engine (boss debuffs, ascensions, secret melds, Baba-Is-You unlocks
   all reuse it). It's built. Lean on it.
3. **The tour fantasy.** The circus theme solves the "campaign for Tetris" problem you
   worried about: a *route* is a story. Fame, weather, towns that hate knives — the map
   IS the narrative layer, and the worldgen addon already renders it.

**What I'd cut or defer (your own retention essay says don't multiply systems):**
- Defer: quests (TFT), event-recycled prestige, lore scraps, cosmetics, the
  empty-rule-deck variant, mana cards. All fine ideas; none needed for the core loop.
- Cut: the rarity-chain cards (Common card doubles Rare chances, etc.) — they're
  Balatro's Hanging Chad problem: dead cards that only touch the meta layer, and they
  fight your "cards are the currency" economy. Fold luck manipulation into the Fortune
  Teller class instead, where it has a face.
- Decide deliberately on the ⚠️ summary-invented cards: I'd **adopt** Ghost Card
  (spotlight-passthrough is a great stamp, see §5), The Acrobat (grab-while-covered),
  and Searing Knife (column hazards enable town/boss content); **reject** The Anarchist
  (silencing the rule deck breaks the one system everything runs on — make it a boss
  effect, not a player card) and Sliced Reality (column count changes are already
  ZoneAdder's job).

---

## 2. Resolving your open design questions

### 2.1 Scoring: adopt the combo reframe, keep the dual axes
Your v3 "damage against an antagonist" instinct is right — but don't throw away row×col.
Concrete proposal:

```
show score = Σ (card effect points)  ×  (1 + row combo)  ×  (1 + col combo)
row combo  = # of unique row melds scored this submit
col combo  = # of unique runs scored this submit
```

- Poker hands and runs stop being the *points* and become the *multiplier*. Card effects
  ("ammo") are the points. This makes every added skill card visibly matter, makes
  boards without effects score honestly low, and preserves the -2- / |1| axis identity.
- **The audience IS the antagonist.** Don't add an enemy with HP — the goal score already
  is one. Rename goal to "Fame needed"; overscore = tips; the crowd cheers per combo
  increment. You get the StS feel with zero new systems.
- Performance Rings then slot in cleanly as *depth multipliers on the col combo* —
  rewarding tall play, which is the riskiest spatial behavior (covering your own cards).
  That's good design tension with the Spotlight system: deep columns = big combo but
  more covered (inactive) skills. This tension is the game. Protect it.

### 2.2 Alt win cons: you already solved it — formalize "The Booking"
Your fame-wager idea (declare a score, lose if you miss) is the alternative to bigger
numbers: **make declarations the win condition.** A tour is won by *fulfilling bookings*,
not by max score. Bookings are contracts: "score X with no knife melds," "win in 2
submits," "trigger 12 unique feats." That's your mini-game events, Balatro boss blinds,
and the optimization-essay answer unified into one diegetic object — a **contract card**
that sits in the rule deck for the show. Endless mode = increasingly absurd bookings.

### 2.3 Spotlight: fix N5 before designing any more cards
Every skill you design is dead until "active while unblocked" is implemented
(ARCHITECTURE_REVIEW N5). It also changes how cards *feel* to design — you'll discover
that "covered" is a resource (things you deliberately hide vs. showcase). Do it first;
re-evaluate the whole §14 catalog after playing with it for a week.

### 2.4 Suits: 4 + specials, not 6
Six base suits break poker-hand math (flush odds, deck size) and multiply art costs.
Recommendation:
- **4 base suits = Knives, Hoops, Balls, Flames** (they map 1:1 to your projectile
  mechanics and to spades/rings/clubs/hearts visual archetypes).
- **Clowns and Dancers become classes** (they already are, in your leader list).
- **Fireworks and Electric become special suits** — appearing only via packs/effects,
  like Balatro's stone/wild enhancements. Rare suits printed on cards feel like loot.

---

## 3. New content: SUITS & PIPS (with historical sourcing)

Ranks first — this is cheap flavor with real mechanical hooks:

| Pip | Effect | Historical source | Why it's fun |
|---|---|---|---|
| **The Joey** (Jack) | Face rename | Joseph Grimaldi, the father of modern clowning — clowns are still called "Joeys" | Faces stop being abstract royalty and become troupe roles; unlocks "Joey synergy" clown cards |
| **The Ringmistress** (Queen) | Face rename | Women ran major circuses (Mollie Bailey owned her own circus; Agnes Lake) | Same |
| **The Impresario** (King) | Face rename | James A. Bailey, the logistics genius behind Barnum's name | Same |
| **The Headliner** (Ace) | Face rename; counts high OR low in runs (real solitaire ace rule) | Top billing on circus posters | Your "Aces are the actual performers?" note, answered: yes — and the high/low duality is a real spatial decision |
| **Harlequin pip** | Dual-suit: counts as two suits at once | Arlecchino's diamond-patterned motley — the actual visual ancestor of "harlequin" playing-card backs | `MultiSuit` is already stubbed (commented) in `pip_comparator.gd`! Cheap to revive; dual-suit cards are placement puzzles |
| **The Gaff** | Wild pip that *pretends*: shows a fixed rank/suit until scored, then reveals its true random value | "Gaff" = sideshow term for a faked exhibit (Fiji Mermaid, Cardiff Giant) | Your wild pip + slot-machine dopamine; the reveal moment is pure variable-ratio reward |
| **Half-step rank** | Rank 5½ etc. — stacks between 5 and 6, never melds | `HalfStepRank` is already stubbed in your code; flavor: the sideshow "in-between" acts | Gluey utility card for runs; interesting cost (it can't score poker) |
| **The Fifteen** | This card also melds with any neighbors summing to 15 (cribbage rule, per your abandoned v1 scoring) | Cribbage — invented by Sir John Suckling, 17th-c. poet & card sharp | Resurrects your abandoned idea as a rare pip instead of a default rule — exactly what the note "should be an ability, not default" asked for |
| **Roman numeral rank** | Cosmetic rank skin; melds normally | Circus Maximus, Rome — the original "circus" | Cheap cosmetic rarity tier (§18 shines) |
| **The Blank** | No rank, no suit; stacks on anything, anything stacks on it; scores 0 | The blank "stock" cards printed in real decks; also sideshow "blow-off" mystery tents | Free spatial glue with zero score — pure positional tool, teaches players position ≠ points |

---

## 4. New content: TYPES (materials)

Types are your material/physics layer. Circus history is FULL of materials:

| Type | Effect | Historical source | Why it's fun |
|---|---|---|---|
| **Canvas** | Sturdy default for circus-born cards (upgrade of Paper) | The big top itself; canvas bosses & roustabouts | Establishes a material progression Paper → Canvas |
| **Sawdust** | When discarded, leaves a "sawdust" marker on its board slot; next card placed there gets +points | The sawdust ring — Astley's original 42-ft horse ring | Makes *discarding* spatial; supports your discard-engine essay |
| **Rosin** | Sticky: cards placed on it cannot be picked up again (but score +1 ring deeper) | Rosinback horses — bareback horses dusted with rosin so riders stick | Your "cards that resist being moved" note, given a reason to exist: commitment for reward |
| **Tintype** | Photograph card: on acquisition, permanently copies the pips of the card it was created from | Tintype photography — the era's cheap souvenir portraits at fairs | Duplication with lineage; collectors will chase "photo of a photo" chains |
| **Lithograph** | Poster card: while in the Entrance (not the Ring), broadcasts its skill globally | Strobridge litho posters — the ads WERE the show for most towns | A type that wants to be NOT played — inverts the whole game's incentive for one card |
| **Glass** | Double points when scored; shatters (destroyed) after 3 scores | Magic-lantern glass slides; also your "kind of like glass card" Exhaust note | Balatro-proven risk/reward; timer creates "last show for this card" drama |
| **Wax** | Melts near Flames: rank slowly decreases each show it shares a column with a Flame card | Barnum's American Museum waxworks (burned down — twice) | Environmental storytelling through mechanics; anti-synergy as flavor |
| **Ticket Stub** | Consumed as currency at shops for a discount; worthless in the Ring | "Annie Oakley" = circus slang for a punched free ticket (her card-shooting act) | Cards-as-currency gets small denominations; the slang is a free legendary-card name |
| **Flash** | Scores triple but only ever once per show, the first time it would score | Juggling slang: a "flash" = throwing all props once without sustaining | Rewards choreographing WHEN a card enters scoring — timing skill |

---

## 5. New content: STAMPS (equipment / "hats")

Your hat/equipment instinct is right — stamps as *costume pieces* reads instantly:

| Stamp | Effect | Historical source | Why it's fun |
|---|---|---|---|
| **Spangle** | +1 combo when this card is part of any meld | Sequined costumes — "sawdust and spangles" is the classic circus memoir title | Simple combo glue every build wants; the common-tier workhorse |
| **Greasepaint** | This card counts as a Clown (class) in addition to its own class | Clown white greasepaint; Auguste/whiteface traditions | Class-splashing enabler — the "tribal" tool every archetype system needs |
| **Top Billing** | This card always scores first in its meld (trigger-order control) | Poster billing order wars — stars fought over letter size | Trigger order is invisible depth; this stamp makes it player-facing |
| **Understudy** | If the card above it in the stack is destroyed/consumed, this card copies its skill | Theatre understudies | Turns destruction effects (Gluttony, Glass) into setup plays |
| **Lloyd's Policy** | The first time this card would be destroyed or debuffed, prevent it | Performers famously insured body parts with Lloyd's of London (Leitzel's arms, dancers' legs) | Insurance against your own Mewgenics-style debuff system; diegetic and funny |
| **Ghost Light** | Does not block the Spotlight of cards beneath it | The theatre "ghost light" left burning on empty stages (adopting the summary's Ghost Card as a stamp) | Lets players build tall without killing their own engines — the counterweight the Performance Rings tension needs |
| **The Encore** | If this card's skill triggered this show, 50% chance it triggers once more at show end | Audiences demanding encores; Leitzel's 100+ one-arm planges as the crowd counted along | End-of-round lottery tick — the Balatro "Lucky card" dopamine slot |
| **Contract Ink** | +X points per show it's played; leaves the troupe (deck) if benched two shows in a row | Circus performer contracts, jumping between rival shows | A card that demands attention — anti-autopilot pressure your optimization essay wants |
| **Brass Check** | On trigger, mint a Gold card to the top of the deck | Brass checks/tokens used as circus & carnival money | Your "money on trigger" seal, themed |

---

## 6. New content: SKILLS / FEATS (the big table)

Rarity uses your power-sort principle (chains listed together). "Class" uses your §11 list.

### Producer / Manager (economy)

| Card | Rarity | Effect | Historical source | Why it's fun |
|---|---|---|---|---|
| **The Egress** | Uncommon | Cue: send any card on the board straight to the discard, gain 1 Ticket Stub | Barnum's "This Way to the Egress" sign — crowds followed it expecting an exhibit and found themselves outside | Targeted removal + economy trickle; the joke lands every time it's used |
| **Humbug** | Rare | Counts as a copy of the most valuable card in the same row while covered; reveals as junk (rank 2) when spotlit | "The Prince of Humbugs" — Barnum's own title; the Fiji Mermaid | Inverts spotlight: a card you WANT covered. Placement puzzle + comedy |
| **White Elephant** | Rare | Huge points when scored, but each show it stays in your deck, eat 1 Gold card | The Barnum–Forepaugh "White Elephant War" of 1884 (Forepaugh's was painted) | A cost-over-time bomb; "when do I finally dump it" is a real decision |
| **The Red Wagon** | Epic | All Gold cards in the deck count toward every column run as wildcards while this is spotlit | The "red wagon" = the circus office/ticket wagon, i.e. where the money lives | Makes a money-hoard build suddenly a scoring build — the pivot moment your yak-shave note wants |
| **Pink Lemonade** | Common | When a Flames card and a Concessions card score in the same row, +bonus and draw 1 | Legend: circus lemonade turned pink when a performer's red tights were washed in the water barrel — and it sold better | Teaches cross-class rows; great early "aha" card |

### Magician (creation/deletion)

| Card | Rarity | Effect | Historical source | Why it's fun |
|---|---|---|---|---|
| **Metamorphosis** | Rare | Cue: swap this card with any card in the draw deck (seen or unseen) | Houdini's substitution-trunk act with Bess | Controlled gamble; deck manipulation with a body |
| **The Bullet Catch** | Legendary | Score = 10× rank when scored in the Spotlight; 1-in-13 chance it is destroyed instead | The trick that killed Chung Ling Soo (1918) — magic's most fatal illusion | The purest near-miss thrill in the whole design; players will tell stories about the time it fired |
| **Sawing in Half** | Uncommon | Cue: split a card into two cards of half rank (rounded up/down), same suit | Golden-age stage illusion (P.T. Selbit, 1921) | Rank arithmetic as a tool: fabricate runs on demand |
| **Misdirection** | Uncommon | While spotlit, the leftmost covered card in each adjacent column is also spotlit | Sleight-of-hand fundamentals | Spatial aura — placement of ONE card re-lights the board |

### Clown (pip manipulation)

| Card | Rarity | Effect | Historical source | Why it's fun |
|---|---|---|---|---|
| **Clown Car** | Epic | On Next: draw an extra card into this card's column, +1 more per Clown scored last submit | Lou Jacobs's midget-car gag, Ringling 1950s | Escalating tempo engine — the board literally overflows with clowns |
| **Slapstick** | Common | Cue: swap the ranks of this card and one adjacent card | The literal slap-stick (battacio) of commedia dell'arte | Cheap, tactile, always-useful pip fixer |
| **Custard Pie** | Uncommon | Throw (cue): target card's suit becomes Balls; if that completes a flush row, +mult | Silent-film & circus pie fights | Suit fixing with a payoff condition — feels like aiming |
| **Weary Willie** | Rare | Gains +1 rank permanently every time one of your cards is destroyed or a show is failed | Emmett Kelly's sad-tramp clown who famously "helped" at the 1944 Hartford fire | A loss-compensator that makes bad runs produce a souvenir — Kelly grew from the Depression |

### Acrobat (movement)

| Card | Rarity | Effect | Historical source | Why it's fun |
|---|---|---|---|---|
| **The Leotard** | Uncommon | Cue: move this card and everything above it to any column (legal or not) | Jules Léotard — invented the flying trapeze AND the garment | Stack teleport; breaks the placement rules the way trapeze breaks gravity |
| **Blondin's Crossing** | Rare | Once per show: move an entire row one column left or right, wrapping | Charles Blondin crossing Niagara on a tightrope (once carrying his manager) | Whole-board shift = the biggest single spatial verb in the game |
| **The Triple** | Epic | If this card ends a run of exactly 3 that was assembled this turn, score it 3× | The triple somersault, "salto mortale" — the trick that killed trapezists for decades until Codona mastered it | Rewards constructing, not just having, formations — turn-scoped skill expression |
| **Human Cannonball** | Rare | Cue: fire the bottom card of any column to the top of another column | Zazel (Rossa Richter, 1877), first human cannonball; later the Zacchini family | Reaching the UNREACHABLE card (bottom of stack) is the solitaire fantasy |

### Animal Trainer (stacking/eating)

| Card | Rarity | Effect | Historical source | Why it's fun |
|---|---|---|---|---|
| **Jumbo** | Epic | Heavy. Cards cannot be placed on Jumbo; Jumbo can be placed on anything; +points per card beneath it when scored | Barnum's Jumbo — the elephant so famous he's why "jumbo" means big | A column-capper with weight you can FEEL; ends columns deliberately |
| **Flea Circus** | Common | Scores as if it were 5 cards of rank 1 for combo-counting purposes | Victorian flea circuses (real fleas, real harnesses) | Tiny card, huge combo — the joke is the mechanic |
| **Liberty Horses** | Uncommon | On Next, all Horse... all Animal-tagged cards in the Entrance rearrange themselves into ascending order | "Liberty" acts — riderless horses performing formations on voice cue | Auto-sorting is deeply satisfying; your goofy-travel animations get a showcase |
| **Mabel's Tigers** | Rare | Consumes the card it's dropped on (like Gluttony) but ONLY prop cards; +rank each meal | Mabel Stark, the great tiger trainer — worked big cats into her 70s | A curved Gluttony: eats your chaff, thins the deck, respects feats |

### Escape Artist / Stuntsman (negatives, insurance)

| Card | Rarity | Effect | Historical source | Why it's fun |
|---|---|---|---|---|
| **Straitjacket** | Common | Starts each show unable to be moved; frees itself (and +points) when its column scores | Houdini's upside-down straitjacket escapes, performed publicly for free crowds | A self-solving problem — the escape IS the payoff |
| **Milk Can** | Uncommon | Place a card inside (cue); it's out of play; retrieve it any later turn | Houdini's "Failure Means a Drowning Death" milk-can escape | Pocket dimension = tempo tool; holding a combo piece for the perfect turn |
| **Wall of Death** | Rare | Adjacent columns score +mult but cards there take 1 Exhaust debuff per show | Motordrome "Wall of Death" riders | Aura with a cost — placement decides who pays it |
| **The Séance Buster** | Rare | Reveals all Gaff/Humbug/fake cards on the board; +points per fake revealed | Late-life Houdini's crusade exposing fraudulent mediums | Counterplay card that makes fakes a real subgame; history's best rivalry (Houdini vs. spiritualism) |

### Fortune Teller (deck manipulation)

| Card | Rarity | Effect | Historical source | Why it's fun |
|---|---|---|---|---|
| **The Tarot Reading** | Uncommon | Cue: look at the top 5 cards of the deck, reorder them | Tarot's carnival fortune-telling tradition (and a wink at Balatro's tarots) | The scry effect every deck game needs; yours is spatially loaded (order = column landing) |
| **Madame Zora's Eye** | Rare | The next-drawn card is always visible above the deck slot | Boardwalk/midway fortune-teller booths (and the Zoltar machine lineage) | Permanent information changes every Next decision; quiet, powerful, beloved |
| **The Major Arcana** | Legendary (series) | 22 unique one-shot consumables (The Tower: destroy a column; The Wheel: reroll a row's ranks; The Hanged Man: flip a stack's order...) | The tarot's trump cards — "trionfi," the historical ancestor of trump suits AND possibly of the Joker | A collectible sub-set = long-term chase content; each is a spatial verb |

### Special Effects (points/combo)

| Card | Rarity | Effect | Historical source | Why it's fun |
|---|---|---|---|---|
| **Calliope** | Uncommon | +combo for every DIFFERENT class that scored this submit | The steam calliope — heard miles before the circus arrived | Directly rewards the rainbow board; the anti-hyperfocus card your essay asked for |
| **Grand Spec** | Epic | If all columns scored this submit, double the show's combo | The "spec" (spectacle) — the whole company's opening parade | The "perfect show" fantasy button |
| **Drumroll** | Common | The last meld scored this submit gets +mult | Every circus trick ever | Trigger-order matters again; pairs with Top Billing |

### Concessions (positive effects)

| Card | Rarity | Effect | Historical source | Why it's fun |
|---|---|---|---|---|
| **Fairy Floss** | Common | When scored, sweeten adjacent cards: +1 rank this show | Cotton candy — co-invented by a DENTIST (William Morrison, 1897) | Adjacency buff = placement puzzle; the dentist fact belongs in the flavor text |
| **The Grease Joint** | Uncommon | At show start, feed the bottom card of the deck to the discard; draw 1 | Circus cookhouse/grease joint slang | Deck-bottom filtering — a slot no other effect touches |
| **Peanut Pitch** | Common | Cue (3 charges): +points to any one card, thrown from anywhere | Peanut butchers working the stands | Your charge system's tutorial card |

---

## 7. LEADERS (historical roster)

One per class, per your leaders-define-decks plan. Each gets the leader chassis (starts
on board, survives submits) plus a signature:

| Leader | Class | Signature | Source |
|---|---|---|---|
| **The Equestrian** (Philip Astley) | Ringmaster archetype | Ring-based: melds scored in the First Ring (5×5) get +mult — he standardized the 42-ft ring | Astley, 1768, London — the actual founder of the modern circus |
| **The Showman** (P.T. Barnum) | Producer | Shops offer 1 extra card; all Gaff/Humbug cards cost nothing | Barnum — museums, hoaxes, "the Greatest Show on Earth" |
| **The Escapologist** (Houdini) | Escape Artist | Your free undo becomes 2; debuffs expire 1 show sooner | Harry Houdini |
| **The Joey** (Grimaldi) | Clown | Once per turn, free Slapstick (swap adjacent ranks) | Joseph Grimaldi, Regency London's superstar clown |
| **The Aerialist** (Lillian Leitzel) | Acrobat | Re-scores the topmost meld once per submit (her endless planges); Glass-fragile: destroyed if her column ever fails to score | Leitzel — Ringling's biggest star; died in a rigging failure, 1931. The fragility is the history |
| **The Tiger Queen** (Mabel Stark) | Animal Trainer | Consumption effects have no cap | Mabel Stark |
| **The Sibyl** (Madame Zora archetype) | Fortune Teller | Top of deck always revealed; first reroll each shop is free | Midway mitt-camp tradition |
| **The Cannon King** (Ildebrando Zacchini) | Special Effects | Fireworks-suit cards may score from the Entrance | The Zacchini family, human-cannonball dynasty |
| **The Sweet Tooth** (Wm. Morrison) | Concessions | All +rank buffs are permanent instead of per-show | The cotton-candy dentist |
| **The Costumier** (unnamed) | Costume Designer | Cards may hold 2 stamps | Wardrobe mistresses of the great shows |
| **The Sharpshooter** (Annie Oakley) | Dancer/Precision (formation) | Exact-rank effects: choose a rank each show; that rank scores double | Annie Oakley shot holes through playing cards — free tickets are still called "Annie Oakleys" |

---

## 8. TOWNS, BOSSES & HAZARDS (the map layer)

Your Knifetown/Firetown resistance idea, extended with real circus adversities — each is a
temporary rule card (§8 of the design doc), exactly as you planned:

| Encounter | Rule effect | Source |
|---|---|---|
| **Hey Rube!** (boss) | Townspeople brawl: each submit, the rightmost column is "attacked" — cards there are debuffed unless a Stuntsman/Strongman guards it | "Hey Rube!" — the historical rallying cry when a circus fought locals |
| **Blowdown** (weather boss) | Storm: at show start and each Next, a random Entrance card is discarded. "The show must go on" | Tent blowdowns — the traveling show's most feared weather event |
| **Mud Show** | Movement tax: picking up any stack costs 1 discard | Slang for small circuses slogging unpaved roads |
| **The Fire Marshal** | Flames-suit cards cannot score; Flames in deck become Wax | Post-1944 Hartford fire regulations reshaped tenting forever |
| **Temperance Town** | Concessions class disabled; shop prices doubled | Dry towns on the historical routes |
| **John Robinson** (elite) | Shortened show: 2 submits instead of 3 | "John Robinson" was the code for "cut the show short" |
| **Lot Lice** | Your first submit each show scores 0 fame (they watched free) | Slang for townsfolk who watched setup without paying |
| **The Rival Show** (recurring boss) | A rival circus plays your town first: goal score pre-raised, but beat it and steal one of THEIR cards | Circus wars — Barnum vs. Forepaugh, Ringling vs. everyone |
| **Railroad Jump** (route hazard) | Long map edges cost a card from your deck (left on the platform) | The brutal overnight railroad jumps of the golden age |

**Map-layer systems to add onto the worldgen graph:**
- **The Route Book**: your run summary/planning UI, named after the actual route books
  circuses published each season. Pre-run, you trace your intended path (your
  "plan the tour" note); deviations cost fame.
- **The Advance Man**: a map consumable/skill that reveals fog-of-war nodes ahead —
  billposters historically traveled weeks ahead of the show.
- **Paper the House**: consumable — auto-pass a town's fame check but gain 0 tips
  (giving away free tickets to look popular). Perfect "skip button with a cost."
- **Straw House**: overscore reward name (a sold-out show where straw was laid for extra
  seating) — when tips exceed X, next node's offers get +1 rarity.
- **Winter Quarters**: THE name for your Carnival meta-hub (Baraboo/Sarasota tradition —
  where circuses rebuilt, trained new acts, and planned routes). Prestige spending =
  literally preparing next season's show.

---

## 9. EVENTS (map nodes, from history)

| Event | Choice offered | Source |
|---|---|---|
| **The White Elephant War** | A rival gifts you a White Elephant card: huge points, drains gold. Take it or insult them (next Rival Show is harder) | Barnum vs. Forepaugh, 1884 |
| **The Egress** | A mysterious sign. Follow it: skip this node entirely (no reward, no risk) | Barnum's museum sign |
| **First of May** | A rookie joins: gain a random Common with a hidden growth condition (upgrades if it scores 10 times) | "First of May" = circus slang for a first-season performer |
| **Cutting Up Jackpots** | Old troupers swap tall tales: reroll any one card in your deck into another of the same class | Slang for swapping exaggerated war stories |
| **Cherry Pie** | Extra work for extra pay: take a debuff card for this show, gain gold cards | Slang for extra paid work crew jobs |
| **The Museum of Humbugs** | Buy a Gaff card cheap — it MIGHT be real (small chance it's actually a Legendary) | The Fiji Mermaid, the Cardiff Giant, and a sucker born every minute |
| **Séance Night** | Houdini-style challenge: expose the fake (pick the Gaff out of 3 face-down cards) for a reward | Houdini vs. the spiritualists |
| **The Pie Car** | Rest node: heal one debuff, or gamble at the crew's card game (Three-Card Monte — obviously rigged, tiny chance of big win) | The circus train's diner/social car; monte throwers |

---

## 10. SECRETS & MYSTERIES (engagement without answers)

Your note says secrets drive engagement even without answers. Circus and card history is
generous here:

- **The Erdnase Cipher**: S.W. Erdnase wrote card-handling's bible (*The Expert at the
  Card Table*, 1902) and his true identity is STILL unknown. In-game: a card author
  signature that appears on random cards across many runs; collecting/scoring all of
  them unlocks... something. Never fully explain it. The community will do the rest.
- **The 42-Foot Ring**: Astley's ring is 42 feet because of horse physics. Hide 42
  everywhere — a secret meld triggers when row+column scores total exactly 42.
- **Secret melds** (your idea, concretized): "The Three Rings" — score three separate
  5-card rings (rows) in one submit → permanently unlock a third zone rule card.
  "Sword Swallower" — a column that's one perfect descending run deck-to-floor.
- **The Ghost Show**: after midnight (real system clock), the menu troupe wagon lights
  are off and one secret card can only be found then. (Spook shows — midnight horror
  performances in circus tents — are real history.)

---

## 11. Why this direction is more fun / more addictive (the reasoning)

Mapped to specific psychological hooks, because "addictive" should be engineered, not
hoped for:

1. **Variable-ratio rewards** (the strongest reinforcement schedule known): pack
   mulligans, The Encore, Bullet Catch, Gaff reveals, Museum of Humbugs. Your
   slot-machine pack-opening note is exactly right — lean into near-miss presentation
   (show what you ALMOST pulled).
2. **Near-miss + loss-aversion**: fame wagers/Bookings make failure *specific* ("missed
   by 40") rather than vague. Balatro's "one hand left" panic is its best moment; The
   Booking manufactures it every show.
3. **Spatial mastery = skill expression**: unlike Balatro, a skilled Solatro player wins
   boards a weak player loses *with the identical deck*. That's replay depth no amount
   of content buys, and it's why effects should keep referencing position (adjacency,
   rings, columns, covered/spotlit) rather than raw math.
4. **The pivot ("yak shave") loop**: your note that players should get seduced into new
   strategies mid-run is served by: leaders (identity), Greasepaint (class splash),
   The Red Wagon (economy→scoring pivot), and Calliope (rainbow reward). Every run
   should offer one "wait, what if I..." card by mid-tour.
5. **Collection & completion**: the Major Arcana series, the banner-line of unlocked
   leaders, route-book stamps per finished tour, the achievement-pass unlock track you
   already designed. Completion pressure retains players between runs.
6. **Narrative scaffolding for free**: every card above ships with a true story. Flavor
   text with real history ("the trick that killed Chung Ling Soo") gives the game the
   "lore" your notes wanted without writing a campaign — the circus already wrote it.
7. **Session shape**: shows are short (3 submits), tours are medium (one sitting), the
   route book & Winter Quarters are long. Three interlocking loops = the "one more"
   ladder every roguelite retention curve needs.

---

## 12. Build order (grounded in the current code)

1. **Fix N5 (spotlight-while-unblocked)** + B10/E1 snapshot iteration. Nothing in §6 is
   testable until skills on ordinary cards fire. (~days)
2. **Adopt the scoring formula (§2.1)** in `SkillScorerCascadeLower`/`ScoreModel` —
   effects-as-points, melds-as-combo. Retune deck1 around it. (~days)
3. **Wire the worldgen map**: nodes → {town, shop, event, pack}; fame goal per node;
   replace `triangle_map.gd` screen. The addon's `graph.json` bake + overlay API is
   ready for this. (~1–2 weeks)
4. **Ship the "First Season" card set**: ~40 cards — 4 base suits renamed, 4 classes
   (Producer, Clown, Acrobat, Fortune Teller), 2 leaders (Showman, Joey), 6 stamps,
   4 types, 3 town bosses (Hey Rube, Blowdown, John Robinson). Small enough to balance,
   big enough to find archetypes.
5. **Economy pass**: cards-as-currency shop with the stack-payment UI, Ticket Stubs,
   Gold minting. (This is where the game becomes a deck*builder* rather than a puzzle.)
6. **Then and only then**: meta layer (Winter Quarters, unlock pass, ascension cards),
   deterministic RNG streams (before any seed-sharing feature), secrets.

Rationale for the order: each step makes the previous step's content *testable in
context* (skills need spotlight; map needs scoring; economy needs map nodes; meta needs
economy). It also front-loads the two things no other game has — spatial scoring and the
rule deck — and defers everything Balatro already proved (shops, unlocks) to when clones
of proven systems are cheap to add.

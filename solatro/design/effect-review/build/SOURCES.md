# Every source mined for the effect review

The complete register. A source is listed here whether it produced effects, produced none, or is
still outstanding — so the question "did we look at X" always has an answer.

**The test for whether a source is worth mining:** does it have a mechanic class this game's
taxonomy has **empty or thin**? A source that only restates scoring effects already in the corpus
earns nothing, which is why the two Balatro wikis survived at roughly 15% while the board games
survive at nearly 100%.

## Repo documents — wave 0

| Source | Rows mined | Outcome |
|---|---|---|
| `CARD_CATALOG.csv` | 378 | the owner's own catalogue; highest keep rate of any source |
| `DESIGN_DOC.md` | 258 | the organised design record |
| `DESIGN_RECOMMENDATIONS.md` | 112 | prior proposals |
| `DESIGN_REFERENCES.md` | 388 | historical compendium with explicit game-hook tags |
| the braindump (`gam draft.txt`) | 334 | raw idea dump; **10 misses recovered on audit** |
| the random-effects sheet | 67 | a Discord dump, read cell by cell |
| the curated pre-grid sheet | 25 | complete, 25 of 25 |
| `todo.md` | 14 | engineering backlog; correctly skipped wholesale |
| `pokerpatience.txt` | 19 | the grid overhaul brief; layout and process |

## Card-game references — wave 1

| Source | Outcome |
|---|---|
| Balatro — jokers, card modifiers, stakes, blinds and antes, tags, challenge decks | 249 mined, ~15% survived; the rest were numeric reskins or needed a held hand |
| Cryptid (Balatro mod) — jokers, decks, sleeves, challenges, card modifiers, poker hands, stakes, boss blinds, tags | 390 mined; contributed the higher-operator tier (`^Mult` and up) |
| Pokermon (Balatro mod) — challenges | folded into the Cryptid pass |

## Games with a board — wave 2

Neither Balatro nor Cryptid has a grid, so the C, D, P and Q families got almost nothing from them.
These were mined to fix that. **55 effects, `G0144`–`G0198`.**

| Source | What it was mined for |
|---|---|
| **Santorini** | a 5×5 grid you build height on, whose god powers are explicit rule-breakers altering movement, building or the win condition |
| **The Zachtronics Solitaire Collection** — Shenzhen, Sigmar's Garden, Proletariat's Patience, Kabufuda, Cluj, Cribbage Solitaire, Sawayama, Fortune's Foundation | eight distinct stacking and foundation rulesets; cited in the braindump |
| **A Solitaire Mystery** (Hempuli) — 30 solitaires incl. Babataire, Time Travel, Fork, Transmutation, Tear, Limited Move, Hanoi, Binary, Murder Mystery, Tap, Eldritch Invasion, Garden, Cheatdeck | rule mutation and reimplementation; cited in the braindump; Hempuli also wrote Baba Is You |
| **Concrete Jungle** | adjacency arithmetic and column-threshold clearing — the closest published game to this one's loop |
| **Luck be a Landlord** | symbol-to-symbol synergy on a grid |
| **Backpack Battles / Backpack Hero** | multi-cell shapes, rotation, and placement setting activation order |
| **Ballionaire** | prop chains — transformers, holders, movers, grouping bonuses |
| **Sagrada, Cascadia, Calico** | cells carrying placement constraints; connected-region scoring |

## Wave 3

**`G0199` onward.** Ranked by the test above.

| Source | The empty or thin class it fills |
|---|---|
| **Open-Face Chinese Poker / Chinese Poker** | cards placed irrevocably into rows scored as poker hands — this game's own loop. Brings **fouling** (a global validity constraint across lines) and **positional royalties** (the same hand worth more in a harder line), neither of which exists here |
| **Poker variants** — lowball, badugi, pineapple, stud, draw, wild designations | B-family; the game is a poker game and no poker variant had been mined |
| **Teamfight Tactics** | trait tiers, run-permanent augments offered at fixed points, shared draft, interest and streak economy, three-copies-merge, hex positioning |
| **Super Auto Pets** | a line where abilities resolve **in stat order rather than position order**, and faint triggers |
| **Solitaire families** (Morehead & Mott-Smith taxonomy; builders / packers / non-builders, reserved vs simple; Spider, Gaps, Stalactites, Moojub, Mrs. Mop, Virginia Reel) | D and B at scale — hundreds of documented stacking and foundation rules |
| **Mahjong** — hand catalogues, American mahjong's per-run card | per-run meld sets, which the braindump explicitly asks for |
| **Idle and incremental games** — Antimatter Dimensions, Universal Paperclips, Cookie Clicker | A4 higher operators, prestige layers, soft and hard caps |
| **Blue Prince** | draw-and-place where each piece must connect, and a dead end wastes the board |
| **Inscryption** | sacrifice as a cost, and rule-breaking as narrative |
| **Loop Hero** | you place the threats you then face |
| **Monster Train** | multiple floors with per-floor placement and ascending threats |
| **Baba Is You** | rules as movable objects, mined directly rather than via Hempuli |
| **Photosynthesis** | height that casts shadows and suppresses neighbours |
| **2048 / Threes** | merging equal values into the next tier |
| **Puzzle Quest / match-3 RPG** | line clears that feed a resource rather than scoring directly |

## Wave 4 — the three declines that were overturned

**`G0252` onward.** Every source below had been declined once. Re-tested against the stopping rule
at the top of this file, all three passed: each owns a mechanic class the taxonomy had at one or two
effects. The declines were made on the games' combat loops; the material that survives comes from
the layers around them.

| Source | The thin class it fills | Why the first decline was wrong |
|---|---|---|
| **Netrunner** | `M3` face-down play, `M5` marked cards, `M7` inspection as a cost | it is the one widely-played game whose core loop is hidden information *priced as a cost*. The decline read "opponent interaction", but installing face down, paying to turn face up, and paying to look are all one-sided |
| **Magic: the Gathering** | `H6` rewrite a trigger, `K6` time / tempo, `F2`/`F3`/`F4` the tutor–scry–reorder line, `K10` spatial cost | replacement effects ("instead of") and sagas that advance one chapter per action are structural, not opponent-facing |
| **Hearthstone** | `F10` fires from the discard, `U4` quest chains, `J8` debt | deathrattle, questlines and overload are all single-player shapes |
| **Peglin** | family `Q` at large — `Q1` spawn rate, `Q2` travel path, `Q3` prop-on-card, `Q4` prop-on-prop — and `L8` crit chance | the decline read "without a persistent board", but this game HAS one that projectiles cross. `PropData` already carries a mutable route, a per-prop speed and a pass-negate; `PropSpawner` carries batch size, interval and a live cap. Peglin is a whole game about one projectile crossing a field of things that alter it |
| **Dicey Dungeons** | `K3` rerolls, `H10` slot topology, `B9` per-run meld set | slotted equipment with value requirements, and a rulebook that changes per run |
| **Astrea: Six-Sided Oracles** | `S9` hype / stakes, `L6` double or nothing, `I12` cleanse | purification is push-your-luck where overshooting is the punishment — the shape `S9` needed |
| **Vault of the Void** | `L4` permanent retirement, `J5` shop manipulation, `T2` carry card state | banishing a card from the run for good, and rebuilding the deck between fights with full knowledge |
| **Wildfrost** | `K6` time / tempo, `L3` injury stacks, `I11` status spread | every unit carries a counter that ticks on each action and fires at zero — a trigger model this game did not have |
| **Monster Sanctuary** | `H7` count other effects | the score is the combo chain, not the hit |
| **Griftlands** | `P10` named rivalries, `J9` price setting, `T3` unlocks as effects | relationships and grudges persist across the whole run |
| **Slay the Spire** | `S5`, `S6`, `I6`, `K8`, `R4` | the rest-site choice, the boss relic trade and the curse that occupies a slot are all outside combat |

Two of the wave-4 modules cite no game. `g018.py` and `g020.py` are written straight against the
taxonomy — the classes no source reached, and the last classes sitting at three. `g019.py` is
written against the prop code itself (`Cards/Props/prop_data.gd`, `prop_spawner.gd`,
`prop_modifier.gd`), whose fields are the levers family Q was not using.


## Wave 6 — the Balatro mod wiki, and four sources the owner named

**`BM0001` onward, rendered as family AA.** Every mod on balatromods.miraheze.org's `Category:Mods`
(466 pages; resource packs, texture packs and tooling skipped; Cryptid and Pokermon skipped because
wave 1 mined them) was crawled through the MediaWiki API — the main page plus every index subpage
(`/Jokers`, `/Decks`, `/Boss Blinds`, `/Card Modifiers`, consumable pages, `/Poker Hands`, `/Stakes`,
`/Tags`, `/Challenges`…), and the README of any thin mod whose page linked to its repository for the
effect list. 290 mods, 1,352 pages, ~19,000 effect rows. Rows naming money, shops, sell values,
rerolls, boosters, vouchers or a held hand were removed mechanically (30%); the rest were read row by
row by subagents against `mine_mods/MINE_PROMPT.md`, which passes an effect only when its trigger,
target or action is one the taxonomy does not spell out. ~940 candidates came back; each was judged
against the whole questionnaire by hand, and about one in six was a new shape. The rest were
numeric reskins of vanilla jokers, or duplicates of questions already here (Bottom Deal, The Running
Order, Non Verisimile, Obelisk, The Costume Fitting and the Ceremonial Dagger were the commonest
twins). Yield was highest from the big original mods — Entropy, Balatrhodes Island, Highest
Priestess, Maximus, Lapsem's Mod, Ortalab, The Binding of Jimbo — and near zero from crossover
packs. The per-mod ledger is `mine_mods/chunkNN.out.tsv`; the keep-list is `mine_mods/new_draft.tsv`.

| Source | Outcome |
|---|---|
| **A Solitaire Mystery** — the full rules transcription (GameFAQs guide 82166; the site refuses scripted fetches, read it in a browser) | wave 2 had this game from the braindump only. The transcription adds twelve shapes: the two-move lock, the chaos swap, the parity build, a stack that counts as one card of its height, the orbit phase gate, the circuit, the ambiguous card, the locked column, the river with its suit-ratio loss, the loan from tomorrow, the garden plot, and the binary group |
| **Zachtronics Solitaire Collection** — the in-game rule screens on zachtronics.com/solitaire-rules (images, read by eye) | re-read in full; every rule already had a question from wave 2 (the free edge, the sanctioned cheat, the dragon collapse, foundations from both ends, the one-use pocket, the glued run) |
| **Dungeons & Degenerate Gamblers** — degenerategamblers.miraheze.org, the Cards / Effects / Encounters / Decks index pages (328 pages crawled to `mine_mods/extra/`) | a blackjack deckbuilder: value + suit, on-play / on-stand / on-tie / on-discard / exploit triggers; chips, HP and shield ignored |
| **Combolands** (Crux Games) — no official wiki; combolands.site, combolands.wiki, combolandsguide.wiki and the Steam guides they cite | a roguelike grid citybuilder: buildings are cards, placement against terrain and tagged neighbours fires score chains; adjacent vs range targeting; "when triggered" buildings need another building to fire them; walls score only when an enclosure is fully closed; railways make everything they touch adjacent. Four shapes added: the crop cycle, the production line, the enclosure, the rail line |
| **Zoominoes** (Starlight Games) — no wiki; Steam page and launch reviews | a tile roguelike: animal tiles carry a value, one of four colours and a land/sky/sea type; a tile may only be placed adjacent to one sharing its colour or type; chains multiply; snacks upgrade tiles, souvenirs are passive modifiers. Its rare abilities (play the whole hand at once, cover the ring of cells around a tile, buff the undrawn deck) already have questions; the connection rule is added as The Kinship Rule |

## Deliberately not mined

| Source | Why |
|---|---|
| Family N material anywhere — view, camera, HUD, frame | excluded by owner ruling; the 10 classes stay in the taxonomy so the hole is visible |
| Feel-only material for `W1` and `W2` | family W exists to be excluded deliberately rather than forgotten; its two entries are enough to make the exclusion a decision the owner takes |

## Wave 5 — Solitaire Network

**`SN0001`–`SN0033`, rendered as family Z.** Every game on solitairenetwork.com, read from its own
rules page; the rules as read are the mining record `mine_solitairenetwork.tsv`, one row per game.
The site's genre is one the corpus already covered twice (the solitaire literature and the two
solitaire collections above), so the survival rate is low by design: what is listed as *folded*
restates a question that already exists, named here so the fold can be checked.

| Game | Outcome |
|---|---|
| Klondike Flip-3 | **The Flip-Three**; unlimited redeals fold into The Redeal |
| Klondike Flip-1 | one pass through the stock is this game's default deck; nothing to add |
| Double Klondike | the second lap of a foundation folds into rank-wrap (B4); "nothing builds on an ace" is **The Dead End** |
| Klondike Garden, Flower Garden, Tri-Peaks Garden | an open reserve any card of which may be played IS the Entrance (F6); the unplayed-reserve bonus folds into Blue Joker |
| Canfield, Double Canfield, Double Canfield 40 | **The Dealt Base**; the face-down reserve pile folds into face-down play (M3) |
| Eight Off, FreeCell, Sea Towers, Squadron, Penguin | free cells fold into Free Cell reserve slots; the supermove bound is **The Supermove**; Penguin's beak is The Dealt Base (b) |
| La Belle Lucie | the free move after the last redeal folds into the La Belle Lucie merci rule; empty fans staying empty is **The Emptied Fan** |
| Cruel | **The Cruel Redeal** — the redeal that does not shuffle |
| Baker's Dozen, Bristol | kings sinking to the bottom on the deal fold into the sink types (D5); Bristol's three waste piles are the Entrance stocks |
| Box Fan, Beleaguered Castle, Fortress, Single Rail, Rank and File, Josephine, Forty Thieves, Thieves of Egypt, Australian Patience, Double Australian Patience | build-down variants of rules already asked (The Packer, Klondike empty-space king rule, The Redeal, reveal-on-move); nothing new |
| Fortress, Shamrocks, Golf, Tri-Peaks, Black Hole, Eliminator | build up-or-down in any suit is **The Golf Rule**; Eliminator's self-seeded foundations are its option (c); Shamrocks' three-card cap folds into The Rigging Loft |
| Four Captives | the aces buried in the reserve are **The Captives**; "only whole runs move, never the top card alone" folded into The Yukon Move |
| Yukon, Scorpion, Simple Scorpion, Double Scorpion, Kansas | moving an unordered pile is **The Yukon Move**; in-place king-headed runs paying per card is **The Scorpion Count**; Kansas's up-and-down foundations fold into Foundations From Both Ends |
| Spider, Spider 1-Suit, Spider 2-Suits, Spider Relaxed, Spider Easy, Spiderette, Will O' the Wisp | the build-loose-clear-strict rule folds into The Spider Rule; dealing a card onto every column is **The Spider Deal**; refusing to deal while a column is empty is **The Refill Gate**; a deck of two suits is **The Two-Suit Deck** |
| Land of Nod | runs that cannot be split once formed is **The Glued Run** |
| Pyramid, Pyramid 2, Pyramid 3, Baroness, Double Baroness | pairs adding to thirteen fold into the Pyramid pair-removal rule; Pyramid 3's reserves that open as free cells fold into The Unlocked Cell |
| Fourteens | a numeric reskin of pairs adding to thirteen |
| Nestor, Air Lock | adjacent same-rank pairs removed together is **The Air Lock**; Air Lock's last-eight-pairs bonus is its option (c) |
| Achilles, Germaine, Germaine 2-Move | near-rank pairs are The Air Lock (b); the interior gap that must be closed is **The Forced Fill**, with 2-Move as its option (b); the row that loses its end cell is **The Shrinking Row**; the last card's rank at the end is **The Final Bow** |
| Osmosis, Osmosis Peek | **The Osmosis Rule**; Peek's face-up reserves fold into reveal (M1) |
| Tam O'Shanter | deal-to-every-column and gather-and-redeal, both already asked |
| Blue Bonnet | **The Blue Bonnet** — one move per deal |
| Royal Marriage | **The Sandwich** and **The Royal Marriage** objective |
| Accordion | folds into the Accordion pile-combining rule |
| Calculation | folds into Calculation Solitaire looping stacks |
| Colorado, Sir Tommy, Strategy | place freely, score only from the top of a pile; Strategy's "nothing scores until the deck is out" is **The Strategy Rule**; the rest folds into position-in-stack rules (D5) |
| Aces Up, Aces Up Relaxed | **The Aces Up Cull**; Relaxed's single-use reserve is **The One-Use Pocket** |
| Gaps, Unlimited Gaps, Free Parking | fold into The Gap; Free Parking's fill-from-either-side is a leniency of it |
| Grandfather's Clock | **The Clock Face** |
| Bowling | **The Ten Pins** and **The Strike** |
| Poker Square | the game itself, 5×5 with every row and column a poker hand; its four discard cells fold into The Mulligan (K1) |
| Blackjack Square | folds into the Blackjack bust rule |
| Cribbage Square | cribbage counting is already asked; the starter shared by every hand is **The Starter** |
| Slide, Super Slide | **The Slider**, with Super Slide's both-axis push as option (b); the escalating set payout is **The Rising Set** |
| Poker Slide | **The Dealt-Full Grid**; its single-use reserves are The One-Use Pocket (c) |
| Mahjong (30 layouts, one ruleset) | the block rule folds into The Free Edge; flowers and seasons matching any of their kind fold into The Salt; timed scoring folds into K6; the hint budget is family N material |
| Site-wide: winnable shuffles | **The Winnable Shuffle** |

## Candidate sources — not yet mined

Curated rule collections that could feed another wave, found by asking which game TYPES carry
mechanics a 5×5 card grid can absorb, then checking that each site actually exists and carries
rules per game. Ranked by the stopping rule at the top of this file against the classes that
currently hold three questions or fewer: `B10` line-length, `C2` extra lines, `C5` prefilled
cells, `C7` cross-grid lines, `C11` region and shape, `E10` position memory, `O5` the buttons.

### First pick — a thin class, rules verified, mechanics the corpus lacks

| Source | What it holds | The thin class it fills |
|---|---|---|
| **Bingo pattern guides** — [bingocardcreator.com/blog/bingo-patterns](https://www.bingocardcreator.com/blog/bingo-patterns/), [bingomania.com/blog/bingo-patterns-the-different-way](https://bingomania.com/blog/bingo-patterns-the-different-way) | thirty-plus named shapes on a 5×5 card with a free centre: four corners, frame, plus, X, diamond, letters, "crazy" patterns that count in any rotation, coverall | `C11` region and shape, `C2` extra lines — a catalogue of 5×5 scoring shapes beyond rows, columns and diagonals, which is exactly this board |
| **Variant sudoku constraints** — [eev.ee/fyi/variant-sudoku](https://eev.ee/fyi/variant-sudoku/) (one page, ~45 constraints, verified), [sudokuvariants.com](https://sudokuvariants.com/), [logic-masters.de beginner's guide](https://logic-masters.de/Raetselportal/Raetsel/zeigen.php?chlang=en&id=000GOJ) | thermometers, arrows, killer cages, sandwich clues, renban, whispers, kropki dots, XV pairs, anti-knight, fortress, entropic and modular lines, region sums, fog | `C11`, `C13` parity and pattern, `C4` cell modifiers — every constraint is a line or cage rule stated in one sentence, and the board plan's marks are the natural carrier for cage and dot clues |
| **Simon Tatham's Portable Puzzle Collection** — [chiark.greenend.org.uk/~sgtatham/puzzles](https://www.chiark.greenend.org.uk/~sgtatham/puzzles/) | 40 grid puzzles, each with a manual: Light Up, Tents, Bridges, Galaxies, Filling, Range, Slant, Same Game, Flood, Pegs, Signpost, Singles, Unruly, Magnets, Undead | `C11`, `C5` prefilled cells (clue cells), `M` information — puzzle rules are placement constraints keyed to visible clues, the shape `C5` has three questions for |
| **Nikoli puzzle types** — [nikoli.co.jp/en/puzzles](https://www.nikoli.co.jp/en/puzzles/) (50+ types, rules on each type's own page, verified on Akari) | Akari, Slitherlink, Nurikabe, Heyawake, Masyu, Hitori, Kakuro, Shakashaka, Fillomino, Yajilin, Ripple Effect | as above, and the source Tatham's collection largely derives from |
| **pagat.com fishing games** — [pagat.com/fishing](https://www.pagat.com/fishing/) (~40 games with full rules) | capture by matching a card, by summing to a target (Escoba, Casino builds), by taking a sequence (Tablić, Cuarenta), sweeps that clear the table, Go-Stop | family `Z5` removal and `G4` destroy — the corpus has pairs-to-thirteen and same-rank pairs; it has no capture-by-sum, no build-then-capture, and no sweep bonus |
| **Hanafuda yaku (Koi-Koi)** — [fudawiki.org/en/hanafuda/games/koi-koi](https://fudawiki.org/en/hanafuda/games/koi-koi) (verified; other hanafuda games on the same wiki), [en.wikipedia.org/wiki/Koi-Koi](https://en.wikipedia.org/wiki/Koi-Koi) | a set-collection catalogue keyed to card CLASS rather than rank: three lights, boar-deer-butterfly, the sake cup with moon or blossom, volume yaku that grow one point per extra card | `B1` new meld types and `P` class synergy — melds defined over the game's eleven classes instead of over ranks and suits; the koi-koi double-or-nothing is already `L6` |
| **Clubhouse Games: 51 Worldwide Classics** — [en.wikipedia.org/wiki/Clubhouse_Games:_51_Worldwide_Classics](https://en.wikipedia.org/wiki/Clubhouse_Games:_51_Worldwide_Classics) (the list; rules per game are on pagat or Wikipedia) | a curated checklist: Mancala, Dots and Boxes, Hit and Blow, Nine Men's Morris, Hex, Gomoku, Renegade, 6-Ball Puzzle, Hanafuda, Sevens, Speed | a checklist rather than a source — Nine Men's Morris (a line of three removes a piece) is `C10` adjacency with a bite, Hit and Blow is `M4` prediction, Dots and Boxes is claiming cells by closing them |

### Second pick — partial overlap with what is already mined, still worth a pass

| Source | What it holds | Why it is second |
|---|---|---|
| **Dice game rules** — [dicegamedepot.com](https://www.dicegamedepot.com/dice-games-free-rules-farkle-yahtzee-more/) (30 games, verified), [en.wikipedia.org/wiki/List_of_dice_games](https://en.wikipedia.org/wiki/List_of_dice_games) (~100 names) | Yahtzee's score-each-category-once sheet, Farkle and Pig push-your-luck, Shut the Box (cover numbers that sum to the roll), Ship-Captain-and-Crew (collect in order), Crag, Beetle | `A7` scoring gate (each hand type pays once per show) and `B9` per-run meld set are the fits; push-your-luck is family `L`, already deep |
| **Roll-and-write / flip-and-write** — [play.nobleknight.com/roll-and-write-games-the-right-way](https://play.nobleknight.com/roll-and-write-games-the-right-way/) (nine games described); rulebooks are per game, not on one site | Welcome To (numbers entered in ascending order along a street), Cartographers (draw a flipped shape onto a map, seasonal scoring cards), Railroad Ink (connect edges), Ganz Schön Clever (the die you skip goes to others), Rolling Realms | the genre IS place-a-value-into-a-grid-under-constraints; `C5`, `C9` commitment and `B9` per-run scoring cards are the fits, but no single site carries the rules |
| **pagat.com invented solitaires** — [pagat.com/solitaire/card.html](https://www.pagat.com/solitaire/card.html) (48 one-player games with rules, verified) | Diamond Heist (a magic square — rows and columns must sum equal), Spiralling Shape, Boardwalk, Elemental (four-card block removal), Repeat Poker, Drop Down Solitaire Poker, Bowling (Sackson) | small, curated, and already half poker-square shaped; `C13` parity and pattern gets the magic square |
| **pagat.com domino games** — [pagat.com/domino](https://www.pagat.com/domino/), [en.wikipedia.org/wiki/List_of_domino_games](https://en.wikipedia.org/wiki/List_of_domino_games) | matching ends, All Fives (score when the layout's open ends sum to a multiple of five), Matador (ends must sum to seven), spinners that open new arms, Bergen (equal ends), Mexican Train | `B1` and threshold scoring on the OPEN ENDS of a layout rather than on completed lines — a shape nothing in the corpus has |
| **Mancala family** — [en.wikipedia.org/wiki/List_of_mancala_games](https://en.wikipedia.org/wiki/List_of_mancala_games); rules per game in Ludii | sowing one seed per pit along a track, relay sowing, capture when the last seed lands in an occupied or empty pit, multi-lap | `E5` patterned movement and family `Q` — a sow is a prop that drops one thing per cell as it travels |
| **Tile-matching video games** — [en.wikipedia.org/wiki/Tile-matching_video_game](https://en.wikipedia.org/wiki/Tile-matching_video_game) | swap-adjacent match-3, falling blocks, advancing blocks, chain reactions scored higher, merge, limited-move levels, hybrid battle (Puzzle Quest) | `C3` re-score on disturbance and cascades; 2048 and match-3 were mined in wave 3, so only the swap and advancing-block shapes are new |
| **Ludii game library** — [ludii.games/library.php](https://ludii.games/library.php) (1,700+ traditional games; categories Hunt, Race, Escape, Fill, Reach, Score, Sow, Space, War, Puzzle) | peg solitaire, hunt games, fill games (cover the board), reach games, single-player puzzles across cultures | volume is huge and rules are in ludeme form; mine by category (Fill, Puzzle, Sow), not by game |

### Third pick — large solitaire catalogues, low expected yield after three solitaire waves

| Source | What it holds | Why it is third |
|---|---|---|
| **BVS Solitaire rules index** — [bvssolitaire.com/rules](https://www.bvssolitaire.com/rules/) (570 games, one rules page each, verified; also a solitaire-types page) | the broadest single-site rules index found | use the types page as the stopping-rule check first; Solitaire Network survived at 33 of 82 only because of its originals |
| **Pretty Good Solitaire** — [goodsol.com/pgs/games.html](https://www.goodsol.com/pgs/games.html) (1,080 games listed, verified; rules live in the app's help, not on the site) | the largest catalogue, with many Goodsol originals | rules are not web-readable; the list is only useful to spot originals |
| **PySolFC** — [pysolfc.sourceforge.io](https://pysolfc.sourceforge.io/) (1,200+ games; rules shipped in the app's docs, index verified) | hanafuda, tarock, ganjifa, matrix, mahjongg, hex-a-deck and Ishido-type tile games alongside card solitaires | the non-card decks (matrix, hex-a-deck, Ishido) are the part worth reading |
| **Wikipedia list of patience games** — [en.wikipedia.org/wiki/List_of_patience_games](https://en.wikipedia.org/wiki/List_of_patience_games) (~300 games, with the closed / half-open / open taxonomy) | the classification itself: simple and reserved builders, packers, blockades, planners, spiders, non-builders | the taxonomy was already used in wave 3; the list is a checklist, not a source |
| **pagat.com competitive patiences** — [pagat.com/patience](https://www.pagat.com/patience/) (13 games) | Russian Bank, Spite and Malice, Nerts, Kings Corners, Card Cricket | two-player shapes; Spite and Malice is already in the corpus |

### Looked at and not usable

| Source | Why |
|---|---|
| BoardGameGeek mechanic and family pages | refuse automated fetches; use the game rulebooks instead |
| Wizard of Odds video-poker paytables | the tables index no longer resolves; the poker-variant family was mined in wave 3 anyway |
| Masters of Traditional Games rules pages, GNOME Aisleriot manual | addresses did not resolve when checked |
| puzz.link rules list | rendered by script; Tatham and Nikoli cover the same types with readable pages |
| Solitaire Laboratory | win-rate analysis and bibliography, not rules |
| Word games, trivia, dexterity and sports minigames | no rank, suit or grid to translate |

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

## Deliberately not mined

| Source | Why |
|---|---|
| Family N material anywhere — view, camera, HUD, frame | excluded by owner ruling; the 10 classes stay in the taxonomy so the hole is visible |
| Feel-only material for `W1` and `W2` | family W exists to be excluded deliberately rather than forgotten; its two entries are enough to make the exclusion a decision the owner takes |

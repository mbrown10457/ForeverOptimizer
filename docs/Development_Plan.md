# Forever Optimizer

> Vanilla-style WoW | Character Optimization Suite | Consolidated development plan

## Project context

- Goal: a personal-use character optimization suite, with potential limited distribution to friends.
- Platform: macOS; Forever appears to be a new/custom client, but exact addon API and interface version are unverified.
- Potential first characters: Hunter or Warlock for efficient pet-assisted leveling; Priest later.
- Currently under active development: quest tracker, Auction House price checker, XP/item-drop tracker.
## Design principles

- One shared core with modular, independently enabled addons.
- Collect raw observations separately from derived analytics and recommendations.
- Use measured player-specific performance; track sample size, level, build, equipment, and uncertainty.
- Avoid protected gameplay automation; recommendations and user-triggered actions only.
- Keep in-game collection lightweight; use optional offline analysis for complex reporting.
## Proposed modules

### ForeverCore

Event manager, character profiles, session manager, SavedVariables storage, analytics interfaces.

### ForeverQuest

Quest tracker, quest-drop estimates, quest efficiency, route planning.

### ForeverEconomy

AH scans, price history, gold/hour, inventory recommendations, crafting profitability.

### ForeverGrinding

XP/loot tracking, mob statistics, kill times, downtime, farming comparisons.

### ForeverCharacter

Gear evaluation, training/mount budget, consumables, profession and progression planning.

### ForeverClasses

Hunter, Warlock, Priest-specific efficiency and resource trackers.

### ForeverDashboard

Overview, session history, leveling, economy, character views.

## Feature backlog and priority


| Priority | Feature | Purpose |
| --- | --- | --- |
| P0 | Shared core and persistent character/session profiles | Foundation for all cross-module analytics. |
| P0 | Gold/hour and net-profit accounting | Vendor proceeds, AH estimated realization, fees, consumables, repairs. |
| P0 | Combat and downtime analyzer | Kill time, between-kill time, damage taken, deaths, recovery. |
| P0 | Mob intelligence database | Observed XP, drops, time to kill, location, sample size. |
| P1 | Smart inventory manager | Vendor/auction/retain recommendations and value per bag slot. |
| P1 | Training and mount savings planner | Forecast training obligations, mount savings, discretionary spending. |
| P1 | Adaptive questing and grinding | Compare quests, mobs, zones, dungeons using normalized XP/hr and gold/hr. |
| P1 | Class-specific trackers | Hunter pet/ammo; Warlock shards/Life Tap; Priest wand/mana. |
| P1 | Session intelligence | Session XP, net gold, deaths, quest count, comparisons. |
| P2 | Gear upgrade evaluator | Class/build/level-specific stat and damage models. |
| P2 | Profession profitability | Gathering, recipe inputs, fees, sell-through assumptions. |
| P2 | Dungeon efficiency | XP/hr, net gold/hr, run duration, repair expense. |
| P2 | Gathering routes and spawn observations | Observed nodes and spawns; uncertainty-aware estimates. |
| P2 | Travel and hearthstone planner | Time cost of walking, flight paths, hearthstone. |
| P2 | Reputation and alt/bank tracking | Reputation/hour and cross-character item visibility. |
| P3 | Auction opportunity detection | Price anomalies, flips, market history, expected net margin. |
| P3 | Consumable ROI and death-cost analysis | Measure speed gain against expenditure and risk. |

## Class-specific design

### Hunter

- Pet damage contribution, uptime, happiness, loyalty and food compatibility
- Ammo remaining and pet training planning
- Aspect state and Auto Shot timing/clipping estimates
### Warlock

- Soul shard inventory and consumption
- Life Tap health/mana tradeoffs and Drain Life recovery
- Damage-over-time efficiency and demon contribution
### Priest

- Wand versus spell efficiency
- Spirit Tap and mana regeneration timing
- Healing/damage per mana and buff uptime
## Metrics and formulas

- XP/hour = XP gained / active elapsed hours; report both gross session and combat-focused rates.
- Net gold/hour = (realized vendor + realized AH proceeds + other income - repairs - consumables - training - AH fees) / elapsed hours. Report unrealized loot valuation separately.
- Kills/hour = kills / elapsed hours; encounter duration and inter-kill downtime should be separate.
- Observed quest-item drop rate = successful drops / eligible kills; expected additional kills = items remaining / observed rate, with wide uncertainty for small samples.
- Location rankings should use character-level normalization, sample-size thresholds, confidence indicators, and user-selected XP/gold/safety weights.
## Illustrative dashboards

### Progression

Level 24 -> 40; current gold 18g; mount target 100g; profession and weapon skill goals; forecast time to next level and mount. These are examples, not verified Forever mechanics.

### Farming comparison

Example: Westfall 17,500 XP/hr and 2.1g/hr; Redridge 21,000 XP/hr and 1.8g/hr; Duskwood 19,500 XP/hr and 3.4g/hr. Values are fictional; rank using chosen objectives and risk.

### Session summary

Track duration, XP, levels, gross and net gold, kills, deaths, quests, kill time, downtime, and changes versus comparable sessions.

## Suggested data model

- CharacterProfile: realm, character ID/name, class, level, build, professions, equipment snapshot.
- Encounter: timestamp, mob identifier, level, zone, duration, XP, damage, resource usage, pet contribution.
- LootEvent: item identifier, quantity, vendor value, observed AH snapshot, source encounter.
- QuestEvent: quest identifier, status, reward, travel/kill time, item progress.
- Session: start/end, zone segments, income/expense ledger, deaths, XP and objectives.
- PriceSnapshot: item, scan time, observed listing price, stack size, market sample size.
## macOS and client feasibility

- First verify client build/interface version, addon directory structure, .toc format, Lua version, event payloads, combat log, quest API, AH API, and SavedVariables behavior.
- Native WoW addons run sandboxed Lua and generally cannot open arbitrary files, issue HTTP requests, or invoke local Python.
- Use SavedVariables as persistent data; an optional Python/SQLite pipeline can ingest saved snapshots after logout or UI reload.
- Some features may be impossible or require manual observations depending on Forever client API and server rules.
- Test memory footprint, event rates, SavedVariables growth, and behavior after disconnects/reloads.
## Phased roadmap

### Phase 1 — Foundation

Inventory existing three addons; establish event adapters, data schema, profile/session storage, migrations.

### Phase 2 — Measurement

Gold/hour, combat metrics, downtime, mob observations, reliable sample counts.

### Phase 3 — Progression

Inventory, training/mount planner, gear and professions.

### Phase 4 — Recommendations

Farming and leveling comparisons, confidence-aware decision engine.

### Phase 5 — Class modules

Hunter and Warlock first; Priest when character is created.

### Phase 6 — Dashboard and export

Session comparisons, configurable objectives, offline analytics and small-group packaging.

## Immediate next steps

1. Identify actual Forever client and addon API with a minimal test addon.
1. Document what each of the three in-progress addons already collects and persists.
1. Define stable shared schemas and versioned SavedVariables migrations.
1. Implement a session ledger and standardized timestamps/zone/character context.
1. Build a thin overview dashboard and validate measured metrics before introducing recommendations.

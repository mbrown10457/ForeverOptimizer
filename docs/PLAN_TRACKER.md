# Plan tracker

Maps every element of `Development_Plan.md` to where it lives and how far along it is. Update this when something ships or gets verified in game.

Status key: **done** = implemented and exercised by `test/run.lua`; **partial** = implemented with a stated gap; **blocked** = waits on the real client; **n/a** = not observable on a 12.x client without the combat log.

## Design principles

| Principle | Status | Where / notes |
|---|---|---|
| One shared core, modular, independently enabled | done | `Core/EventManager.lua`; `/fo module on|off <name>` (Core and the HUD shell can't be disabled) |
| Raw observations separate from derived analytics | done | Raw: `mobs.encounters`, `loot.log`, `prices.prices`, `quests`, `farming.*`, `sessions.list`. Derived at report time in `AnalyticsEngine`, `MobDatabase:Metrics`, `QuestEfficiency:Estimate` |
| Measured, player-specific; track sample size, level, build, equipment, uncertainty | partial | Sample sizes on every estimate; player level on sessions and encounters; equipment snapshot + build in `CharacterProfile` (build only if the client exposes a talent/spec API). Encounters aren't yet filtered by equipment snapshot when comparing |
| No protected automation | done | Only user-triggered actions; auto-sell uses the unprotected `UseContainerItem` and can be turned off |
| Lightweight in game, offline analysis optional | done | Capped logs everywhere (`/fo dbstats` to watch size); `scripts/fo_sqlite.py` ingests SavedVariables into SQLite |

## Modules

| Plan | Built as | Status |
|---|---|---|
| ForeverCore: events, profiles, sessions, storage, analytics | `Core/` 8 files incl. `Verify.lua` | done |
| ForeverQuest: tracker, drop estimates, efficiency, routes | `Quest/` 3 files | done |
| ForeverEconomy: AH, history, gold/hr, inventory, crafting | `Economy/` 5 files | done |
| ForeverGrinding: XP/loot, mobs, kill times, downtime, farming | `Grinding/` 5 files | done |
| ForeverCharacter: gear, training, consumables, progression | `Character/` 4 files | done |
| ForeverClasses: Hunter, Warlock, Priest | `Classes/` 3 files | partial (see class table) |
| ForeverDashboard: overview, session history, leveling, economy, character | `Dashboard/` 5 tabs | done |

## Feature backlog

| P | Feature | Status | Where | Gap / verify |
|---|---|---|---|---|
| P0 | Shared core, persistent profiles | done | `Core/*`, `/fo me`, `/fo dbstats`, migrations v2 | |
| P0 | Gold/hour and net profit | done | `/fo gold`, `SessionManager` ledger | AH deposits land in "AH spend"; realized AH sales arrive as "mail in" |
| P0 | Combat and downtime analyzer | partial | `/fo downtime`, `/fo deaths`, encounters with `dur`, `hpLoss`, `manaLoss` | Damage taken is unobservable in combat; we record health/mana deficit when combat ends (solo fights only for per-mob averages) |
| P0 | Mob intelligence database | done | `/fo mobs`, `/fo mob`, raw `encounters` | |
| P1 | Smart inventory manager | done | `/fo bags`, `bags worst`, value per slot, auto-sell | |
| P1 | Training and mount savings | done | `/fo plan`, `skip`, `proftrain`, `goal` | Default mount prices are 1.12 base; adjust with `/fo goal` |
| P1 | Adaptive questing and grinding | done | `/fo zones`, `/fo objective`, `/fo recommend`, `/fo estimate`, `/fo levels`, `/fo questxp` | Confidence labels; low-confidence rows are down-weighted 20% |
| P1 | Class-specific trackers | partial | `Classes/*` | See class table |
| P1 | Session intelligence | done | `/fo session`, `/fo history`, History tab, `questsDone` | |
| P2 | Gear upgrade evaluator | partial | tooltip line, `/fo gear`, `/fo weights` | Simple linear stat weights; no damage model, no proc/set logic |
| P2 | Profession profitability | done | `/fo craft`, `craft skillup`, `craft sellthrough` | AH deposit fee not modelled; needs `C_TradeSkillUI` (verify) |
| P2 | Dungeon efficiency | done | `/fo dungeons` | Repairs within 10 min of leaving are attributed to the run |
| P2 | Gathering routes and spawns | done | `/fo nodes`, `route`, `respawn`, `rares`, `competition` | Confirmed vs upper-bound respawns; patrols can still fool it |
| P2 | Travel and hearthstone planner | partial | `/fo hearth`, `/fo legs`, flight spend | No flight-path graph; recommendations come from your recorded legs only |
| P2 | Reputation and alt/bank tracking | done | `/fo rep` (rep/hr, sources), `/fo find`, `/fo mats`, `/fo bank` | |
| P3 | Auction opportunity detection | done | `/fo flips`, `/fo movers`, `/fo watch` | Relist margin assumes sale at 7-day average |
| P3 | Consumable ROI and death cost | done | `/fo consumables`, death cost in `/fo downtime` | Repairs-per-death is an approximation |

## Class-specific design

| Item | Status | Notes |
|---|---|---|
| Hunter: pet damage contribution, uptime | n/a / partial | No combat log; pet presence shown. Uptime could be added from `UnitExists("pet")` per tick |
| Hunter: happiness, loyalty, food compatibility | partial | Happiness and food types shown when the client has the classic pet API (verify) |
| Hunter: ammo remaining, pet training planning | partial | Ammo count + low warning. Pet training points not read yet |
| Hunter: aspect state | done | Current aspect on HUD |
| Hunter: Auto Shot timing / clipping | n/a | Needs combat log or cast timing not exposed |
| Warlock: shard inventory and consumption | done | Count, low/high warnings |
| Warlock: Life Tap / Drain Life tradeoffs | partial | Casts per kill counted; health/mana tradeoff math not yet |
| Warlock: DoT efficiency, demon contribution | n/a | No combat log |
| Priest: wand vs spell | partial | Wand share counted from "Shoot" casts; no damage comparison |
| Priest: Spirit Tap / regen timing | partial | Drink share and mana shown; no per-fight regen model |
| Priest: healing/damage per mana, buff uptime | n/a / planned | Per-mana needs combat log; buff uptime could use aura scan |

## Metrics and formulas

| Formula | Status | Where |
|---|---|---|
| XP/hour gross and combat-focused | done | `Stats().xph` (wall) and `xphProd` (fighting) |
| Net gold/hour with unrealized loot separate | done | `/fo gold`: net vs effective |
| Kills/hour; encounter duration and inter-kill gap separate | done | `MobDatabase:ZoneKillTiming`, `/fo estimate` |
| Quest drop rate with wide small-sample uncertainty | done | Wilson 95% interval in `/fo drops`; confidence tag |
| Location rankings: level-normalized, thresholds, confidence, user weights | done | `levelsPerHour`, `ZoneRows` confidence, `/fo objective xp|gold|safe|balanced|custom` |

## Dashboards

| View | Status | Where |
|---|---|---|
| Progression (level, gold, mount target, skills, forecasts) | partial | Character tab + `/fo plan`, `/fo eta`, `/fo skills` (skills only if the client has skill lines) |
| Farming comparison | done | `/fo zones` with objective weights |
| Session summary with comparison to comparable sessions | done | History tab, `/fo history` |

## Data model

| Entity | Status | Where |
|---|---|---|
| CharacterProfile (realm, name, class, level, build, professions, equipment) | done | `chars.<key>.profile` |
| Encounter (timestamp, mob, level, zone, duration, XP, damage, resources, pet) | partial | `account.mobs.encounters`; damage/resources = post-fight deficits; no pet share |
| LootEvent (item, qty, vendor value, AH snapshot, source) | done | `account.loot.log` |
| QuestEvent (id, status, reward, travel/kill time, progress) | done | `account.quests.quests` (+ `questeff.history` for drop rates) |
| Session (start/end, zone segments, ledger, deaths, XP, objectives) | done | `account.sessions.list` |
| PriceSnapshot (item, time, price, stack, sample size) | done | `account.prices.prices` + `daily` |

## Feasibility checklist (plan section "macOS and client feasibility")

All of these are probed by `/fo verify` and the result is saved to `account.verify.last`.

| Item | Status |
|---|---|
| Client build / interface version | partial: wago.tools shows Forever as product `wowf`, build 1.60.1.70707 (Interface 16001); `/fo verify` confirms in game |
| Addon directory, TOC format | blocked: `scripts/install.sh` tries `_forever_` then `_camelot_` |
| Lua version, event payloads | blocked: verify prints `_VERSION`; payload shapes assumed from 12.x |
| Combat log | designed around; verify confirms it's refused |
| Quest API, AH API, trade skill API | blocked: verify reports retail vs classic shape |
| SavedVariables behavior | versioned root with migrations; `/fo dbstats` for growth |
| Memory, event rates, disconnect/reload behavior | blocked: watch `/fo dbstats` and `/fo errors` (persistent error log, `account.errors.log`) over the first sessions |

## Phased roadmap

| Phase | Status |
|---|---|
| 1 Foundation | done (event adapters, schema, profiles, sessions, migrations) |
| 2 Measurement | done pending in-game verification |
| 3 Progression | done |
| 4 Recommendations | done at first-draft quality (`recommend`, `estimate`, `objective`) |
| 5 Class modules | partial (see class table); Priest ships but only activates on a Priest |
| 6 Dashboard and export | done: five tabs, `scripts/fo_sqlite.py`, `scripts/package.sh` |

## Added after the plan (2026-10-31)

| Item | Where | Status |
|---|---|---|
| Persistent Lua error log with stacks, dedupe, `/fo errors [n\|clear]`, SQLite export | `FO.Try` / `FO:Error` in `Core/Init.lua`, persistence in `Core/DataStorage.lua` | done |
| Client item seed (19,267 items from the `wowf` 1.60.1.70707 ItemSparse/Item tables) with Util fallbacks and `/fo seed` | `Data/Items.lua`, `Core/SeedData.lua`, `scripts/build_seed.py` | done; creature and quest POI tables in the client are near-empty, so mobs and quests stay learned, not seeded |
| Git repository with tagged releases | repo root | done (v0.4.0, v0.5.0, v0.6.0) |
| World map overlay: player and cursor coordinates, pins for recorded herb/ore nodes, rare sightings and tracked spawn points with respawn estimate; `/fo map`, `/fo coords`, HUD position line | `Dashboard/MapOverlay.lua` + `.xml` (map data-provider API) | done; degrades to coordinates only if the client lacks `WorldMapFrame:AddDataProvider`, which `/fo map` reports |

## Immediate next steps (from the plan)

1. Identify the client API with a minimal test addon → `/fo verify` on Nov 3.
2. Document what the three in-progress addons collected → superseded; this tracker and the README cover the unified addon.
3. Stable schemas and versioned migrations → `FO.migrations` in `Core/DataStorage.lua`.
4. Session ledger with timestamps/zone/character context → `SessionManager`.
5. Thin overview dashboard, validate metrics before recommendations → HUD exists; validation is the first week of real play.

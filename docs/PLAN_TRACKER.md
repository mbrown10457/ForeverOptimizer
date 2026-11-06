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
| ForeverClasses: Hunter, Warlock, Priest, Shaman | `Classes/` 4 files | partial (see class table) |
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
| Quest reader: quest, progress, reward and gossip text spoken through C_VoiceChat.SpeakText; voice/rate/volume settings | done (v0.16.0; verified live: client chat-TTS wrapper path) | `/fo tts`, `Quest/QuestReader.lua` |
| Item advisor: vendor vs disenchant (classic result table, expected value and range from scanned mat prices, Enchanting skill gate) vs auction, bag sweep, tooltip line | done (v0.17.0; needs a live AH scan to price) | `/fo advise`, `Economy/ItemAdvisor.lua` |
| Minimap node icons: herb/ore pins on the minimap by yards and zoom radius, rotation aware, tooltip | done (v0.18.0; placement unverified live) | `/fo minimap`, `Dashboard/MinimapNodes.lua` |
| Node seed: 19,453 Wowhead spawn points via GatherLite (MIT) on world map, minimap and gathering route; scripts/build_nodes.py | done (v0.19.0) | `/fo map seed`, `Data/Nodes.lua` |
| Guide auto-skip: unavailable quests (QuestieDB exclusive/chain/prerequisite) and log-missing steps skipped with reasons; /fo guide sync, why, autoskip | done (v0.19.1) | `/fo guide sync`, `Quest/Guide.lua` |
| Node layers split by profession: off/mine/all per herbs and ores, world-map buttons, seed off by default, nearest 300, skill gate | done (v0.19.2) | `/fo map herb|ore`, `Dashboard/MapOverlay.lua` |
| Map node icons (gathered item's icon per herb/ore pin), `/fo route herb|ore` restored (the quest route command had shadowed it), guide do-quest steps use the router's densest patch | done (v0.15.0) | `Dashboard/MapOverlay.lua`, `Quest/Guide.lua` |
| Auto Shot timer bar: weapon-speed cycle, aim window, moving warning, cast pause and restart, secret ids via cast GUID, wand Shoot | done (v0.14.0; events unverified live) | `/fo shotbar`, `Classes/AutoShot.lua` |
| Quest router: objective patches from QuestieDB spawns plus recorded ticks, shared patches merged, turn-ins after their objectives, pickups folded in, nearest-neighbour + 2-opt, follow mode with live replanning, map pins and Route tab | done (v0.13.0; patch sizes and arrival radius unverified live) | `/fo route`, `Quest/QuestRoutePlanner.lua` |
| Combat events without a combat log | done (UNIT_COMBAT feed, v0.12.0) | `Core/CombatFeed.lua`: hits, heals, misses, casts and deaths attributed by last cast per school, DoT duration, pet target; estimates, group damage on your target counts as yours |
| Hunter: pet damage contribution, uptime | done (combat log) | Pet share of damage on HUD from CombatStats; falls back to pet presence if the log is refused |
| Hunter: happiness, loyalty, food compatibility | partial | Happiness and food types shown when the client has the classic pet API (verify) |
| Hunter: ammo remaining, pet training planning | partial | Ammo count + low warning. Pet training points not read yet |
| Hunter: aspect state | done | Current aspect on HUD |
| Hunter: Auto Shot timing / clipping | done (combat log) | Shot gaps vs ranged speed from cast-success/range-damage events; `/fo autoshot`, HUD line |
| Warlock: shard inventory and consumption | done | Count, low/high warnings |
| Warlock: Life Tap / Drain Life tradeoffs | partial | Casts per kill counted; health/mana tradeoff math not yet |
| Shaman: shield charges, weapon imbue timers, totems down, shocks/bolts/heals per kill, drink share; alerts for no shield or imbue at combat start and imbue about to expire | done | `/fo shaman`; Shaman HUD tab; Enhancement build reordered to reach Flurry at 15 points and Stormstrike at 30 |
| Leveling guide: step-by-step route window and HUD tab, auto-advance from the quest log, class- and race-filtered steps, per-character progress; Orc & Troll 1-20 and Tauren 1-20 routes generated from QuestieDB with class quests for all six Horde classes | done (route order is a first draft) | `/fo guide`; `scripts/build_routes.py`, `scripts/routes/*.txt`, `Data/Routes.lua`; docs/Leveling_Guide.md |
| Direction arrow: TomTom-style arrow with yards, colour by heading, arrival callback; driven by the guide, `/fo next`, `/fo route`, `/fo arrow` | done (world-space bearing is a live check) | `/fo arrow`; `Dashboard/Arrow.lua` |
| Warlock: DoT efficiency, demon contribution | done (combat log) | Ticks delivered vs lost to early refresh/death per DoT, demon damage share, mana spent vs gained; `/fo dots` |
| Priest: wand vs spell | done (combat log) | Wand share by damage when the log is live; by casts otherwise |
| Priest: Spirit Tap / regen timing | partial | Drink share and mana shown; no per-fight regen model |
| Priest: healing/damage per mana, buff uptime | done / planned | Heal per mana with overheal and damage per mana from CombatStats (`/fo heals`); buff uptime still planned |

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
| Client build / interface version | done: installed client is `wowf` 1.60.1.70707 in `_forever_` (build info + gx.log); Interface 16001 |
| Addon directory, TOC format | done: `_forever_/Interface/AddOns` created and populated; "Camelot" is the internal flavour name |
| Lua version, event payloads | blocked: verify prints `_VERSION`; payload shapes assumed from 12.x |
| Combat log | events present with HasRestrictions (same as mainline 12.1.5); runtime state from `C_CombatLog.IsCombatLogRestricted`; adapter handles both |
| Quest API, AH API, trade skill API | done from client docs: retail `C_AuctionHouse`, `C_QuestLog.GetNextWaypoint`, retail `C_TradeSkillUI` (`docs/Forever_API_Notes.md`) |
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
| Group DPS/HPS meter: per-player damage and healing for fight / last fight / session, pets credited to owners, no cross-player sync | `Grinding/Meter.lua`, `/fo dps`, `/fo hps`, `/fo meter`, HUD "Meter" tab | built 2026-11-02 against the stub; needs the live combat log |
| In-game manual: Help HUD tab (commands by area, paged) and a scrollable manual window built from the live command registry, HUD tabs and buttons; `/fo manual` | `Dashboard/Help.lua` | built 2026-11-02 against the stub |
| Rune discovery log: seed Engrave spells and rune abilities diffed against the spellbook on change; announced, flashed, noted, saved with level/zone/position; `/fo runes` | `Character/Runes.lua` | built 2026-11-02 against the stub |
| Post-session collect (Mac `scripts/collect.sh`, Windows `scripts/collect.ps1`) and `scripts/summarize.py`; nightly launchd backup (`scripts/backup.sh`, `backup-install.sh`) | `scripts/` | built 2026-11-02; collect needs a real SavedVariables file to prove the summary |
| HUD button rows: each tab declares buttons (`RegisterTab(name, order, fn, controls)`), drawn under the tabs, driving the same commands; `/fo hud list`, `/fo hud click <label>` | `Dashboard/Overview.lua` plus controls in Meter, Leveling, Economy, Character, History | built 2026-11-02 against the stub |
| Combat log adapter built optimistically for the 1.60 client, with graceful refusal; CombatStats (damage by spell/source, pet share, damage taken, fight timing, heals and overheal, mana per spell, DoT efficiency, Auto Shot clipping); class modules upgraded; MobDatabase gets precise kill time and damage taken | `Core/CombatLog.lua`, `Grinding/CombatStats.lua`, `Classes/*` | done pending in-game confirmation that the log is allowed; falls back to chat/loot paths otherwise |
| Rotation optimizer: spell and talent seeds from the client tables, hand-authored rotations and builds for all nine classes validated against the seed, `/fo rotation`, `/fo build`, `/fo spell` | `scripts/build_spells.py`, `Data/Spells.lua`, `Data/Talents.lua`, `Data/Rotations.lua`, `Character/Rotation.lua` | done; rotations are first drafts to tune against measured data |
| Auto-updating data: daily workflow regenerates seeds on a new client build, validates, commits or opens an issue; CI on push; release zip on tag | `.github/workflows/*.yml`, `scripts/check_build.py`, `test/validate_data.lua` | done, untested until the repo has run its first Actions job |
| First-hour checklist, session notes, alerts (rare, respawn window, bags, ammo, shards) with per-kind toggles, key bindings | `Core/Checklist.lua`, `Core/Alerts.lua`, `Core/SessionManager.lua`, `Bindings.xml` | done |
| Quest database: live QuestieDB adapter (optional dependency) for quest facts, availability rules and spawn coordinates; nearby pickups, quest facts, route fallbacks, map pins; recorded positions win | `Quest/QuestDatabase.lua`, `Quest/QuestRoutePlanner.lua`, `Dashboard/MapOverlay.lua` | done against QuestieDB's documented API; unverified until both addons run on the real client |
| World map overlay: player and cursor coordinates, pins for recorded herb/ore nodes, rare sightings and tracked spawn points with respawn estimate; `/fo map`, `/fo coords`, HUD position line | `Dashboard/MapOverlay.lua` + `.xml` (map data-provider API) | done; degrades to coordinates only if the client lacks `WorldMapFrame:AddDataProvider`, which `/fo map` reports |
| Unexplored map art: every exploration overlay of every map seeded from the client's WorldMapOverlay tables (`scripts/build_mapoverlays.py`, 45 maps, 579 overlays); the ones `C_MapExplorationInfo` does not report are tiled onto a full-canvas pin, tinted darker; map button, `/fo map reveal`, `/fo map tint`, key binding | `Data/MapOverlays.lua`, `Dashboard/MapOverlay.lua` | done offline (harness checks tile counts against the seed); live check: pin level and the explored-texture keys on the real client |
| Add-in catalog: every module with status, commands and file, architecture layers, module contract, open slots, filters; markdown export and an issue template for proposals | `docs/addins.html`, `docs/FEATURES.md`, `scripts/build_features.js`, `.github/ISSUE_TEMPLATE/add-in.yml` | done 2026-11-02 |
| Review fixes (2026-11-02): amounts-hidden detection over a sliding window of amount-bearing events; zero-stack auctions no longer divide by zero; auction API guarded; migrations run on a staged copy and roll back on failure with `FO.migrationFailed` and a newer-file warning; combat log handler has a fixed closure (`FO.TryCall`); CI runs the harness on Lua 5.1 and 5.4; seed bot opens a pull request instead of pushing to main | `Core/CombatLog.lua`, `Core/DataStorage.lua`, `Core/Init.lua`, `Economy/AuctionHouseScanner.lua`, `.github/workflows/*` | done, v0.9.7 |

## Immediate next steps (from the plan)

1. Identify the client API with a minimal test addon → `/fo verify` on Nov 3.
2. Document what the three in-progress addons collected → superseded; this tracker and the README cover the unified addon.
3. Stable schemas and versioned migrations → `FO.migrations` in `Core/DataStorage.lua`.
4. Session ledger with timestamps/zone/character context → `SessionManager`.
5. Thin overview dashboard, validate metrics before recommendations → HUD exists; validation is the first week of real play.

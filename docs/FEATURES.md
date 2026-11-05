# ForeverOptimizer add-ins (v0.17.0)

Generated from `docs/addins.html` by `scripts/build_features.js`. The browsable version with filters and the architecture diagram is at https://mbrown10457.github.io/ForeverOptimizer/addins.html.

Status: **ready** = built and exercised by the offline harness; **live check** = built, needs the real client to confirm an API; **partial** = works with a stated gap; **open slot** = wanted, not built. Propose one: https://github.com/mbrown10457/ForeverOptimizer/issues/new?template=add-in.yml

## Core

| Add-in | Status | What it does | Commands | Where |
|---|---|---|---|---|
| Session ledger | ready | Every play session with zone segments, activity (quest, grind, dungeon) detected from what you do, XP, gold in and out, deaths and your own timestamped notes. Comparable sessions are matched by level and activity. | `/fo session`, `/fo note`, `/fo history` | `Core/SessionManager.lua`; HUD: History |
| Alerts | ready | Rare spawn seen, respawn window opening, bags nearly full, ammo low, soul shards low or high. Chat line, sound and a centre-screen flash, each switchable. | `/fo alerts` | `Core/Alerts.lua`; HUD: Overview buttons |
| First-hour checklist | ready | The visits and commands that seed every other module on a fresh character, ticked off as you do them. | `/fo checklist` | `Core/Checklist.lua` |
| Client verify | ready | Probes every client API the addon depends on and saves the result, so the first login tells us exactly which modules are degraded. | `/fo verify` | `Core/Verify.lua` |
| Error log | ready | Every handler runs inside FO.Try. Lua errors are deduplicated, kept with stacks, printed a few times, and saved so they can be read from the file after a crash. | `/fo errors` | `Core/Init.lua, Core/DataStorage.lua` |
| Combat log adapter | live check | Normalizes COMBAT_LOG_EVENT_UNFILTERED into FO_CL_DAMAGE, HEAL, CAST and the rest, with mine/pet/party flags, so add-ins never parse the raw payload. *Gap: Built for the 1.60 client; refuses cleanly if the log is restricted.* | `/fo combatlog` | `Core/CombatLog.lua` |
| Combat feed (no combat log) | live check | Forever has no combat log, so UNIT_COMBAT (every hit, heal and miss on you, your pet, your target and nameplates, with amount and school) is turned into the same FO_CL_* events: attributed to your last cast of that school, a running DoT, Melee, or your pet; duplicates through a second unit token dropped; deaths from the XP chat line. Meter, combat stats, rotation and class tabs run on it as estimates. | `/fo combatfeed` | `Core/CombatFeed.lua` |
| Data storage | ready | Versioned saved-variables root with migrations, per-module namespaces, size caps and a per-namespace size report. | `/fo dbstats`, `/fo wipe` | `Core/DataStorage.lua` |
| Character profile | ready | Realm, class, level, professions, equipment snapshot and build, stamped onto sessions and encounters so numbers can be compared like with like. | `/fo me`, `/fo skills` | `Core/CharacterProfile.lua` |
| Analytics engine | ready | Zone and activity rankings near your level, normalized to levels per hour, scored by your objective weights (XP, gold, safety) with confidence labels. The adaptive leveling recommendation lives here. | `/fo objective`, `/fo estimate`, `/fo recommend`, `/fo zones` | `Core/AnalyticsEngine.lua`; HUD: Leveling |
| Client seeds | ready | 19,267 items plus every class spell and talent read from the client's own tables, rebuilt automatically when the game patches. Mobs and quests are learned, not seeded, because the client ships those tables empty. | `/fo seed`, `/fo spell` | `Core/SeedData.lua, Data/*.lua` |

## Grinding

| Add-in | Status | What it does | Commands | Where |
|---|---|---|---|---|
| XP tracker | ready | XP per hour by activity for each level you have played, wall-clock and fighting-only. | `/fo levels` | `Grinding/XPTracker.lua`; HUD: Overview |
| Mob database | ready | Every mob you fight: XP, gold and drop rates per kill, kill time, damage taken, deaths. Ranked tables by XP, gold, kills or safety, here or anywhere. | `/fo mobs`, `/fo mob` | `Grinding/MobDatabase.lua` |
| Combat stats | live check | Damage by spell and source, pet share, healing with overheal, mana per spell, DoT ticks delivered versus lost, Auto Shot and wand clipping. *Gap: Needs the live combat log; falls back to cast counts.* | `/fo combat`, `/fo heals`, `/fo dots`, `/fo autoshot` | `Grinding/CombatStats.lua`; HUD: Class tab |
| Group meter | live check | Damage and healing per player for the current fight, last fight or session, pets credited to owners, personal spell breakdown. No cross-player sync; it sees what your client sees. *Gap: Needs the live combat log.* | `/fo dps`, `/fo hps`, `/fo meter` | `Grinding/Meter.lua`; HUD: Meter |
| Farming efficiency | ready | Herb and ore nodes with positions, respawn intervals (confirmed versus upper bound), rare sightings, and how many other players were around. | `/fo nodes`, `/fo respawn`, `/fo rares`, `/fo competition` | `Grinding/FarmingEfficiency.lua`; HUD: Map pins |
| Downtime analyzer | ready | Where non-fighting time goes: eating, travel, corpse runs, vendoring. Death cost in repairs and minutes. Travel legs between zones. | `/fo downtime`, `/fo deaths`, `/fo legs` | `Grinding/DowntimeAnalyzer.lua` |
| Loot tracker | ready | Raw loot log with vendor value and auction snapshot per item, the source of unrealized loot value in the gold report. | `/fo gold` | `Grinding/LootTracker.lua` |

## Quest

| Add-in | Status | What it does | Commands | Where |
|---|---|---|---|---|
| Quest tracker | ready | Records where you accepted each quest, where each objective ticked and where you turned it in. Those positions feed the route planner and the map. | `/fo quests`, `/fo quest`, `/fo autotrack` | `Quest/QuestTracker.lua` |
| Quest efficiency | ready | Drop odds per objective from your kills with a 95% Wilson interval, kills and minutes to finish, and quest XP per hour against reward size. Rates are kept per objective for alts and friends. | `/fo drops`, `/fo questxp` | `Quest/QuestEfficiency.lua` |
| Quest router | ready | Turns the quest log into an ordered loop on the current map: unfinished objectives' spawn points and the spots where they ticked for you grouped into patches, patches shared by several quests merged into one stop, turn-ins placed only after their objectives and merged per finisher, pickups folded in on request. Nearest-neighbour under those rules, then 2-opt. Follow mode replans on every quest log change and walks the arrow through the loop; numbered stops on the world map and a Route HUD tab. Group, dungeon and raid quests stay out unless asked. The leveling guide's do-quest steps point at the same densest patch. *Gap: Patches come from spawn data, not live mobs; escort and event objectives route to their trigger point when the database has one.* | `/fo next`, `/fo route` | `Quest/QuestRoutePlanner.lua`; HUD: Route |
| Quest database adapter | live check | Reads QuestieDB live for quest facts, prerequisites, chains, race and class rules and spawn positions. Lists what you can pick up on this map, nearest first. *Gap: Optional dependency; without it the quest modules use recorded positions and the baked route data.* | `/fo nearby`, `/fo questinfo`, `/fo qdb` | `Quest/QuestDatabase.lua`; HUD: Map pins |
| Quest reader | live check | Reads quest text aloud through the client's text-to-speech engine (C_VoiceChat.SpeakText): title, description and objectives on open, progress and reward text at turn-in, NPC gossip. Closing the window stops it. Voice, rate and volume are settable; /fo tts again repeats. *Gap: Needs the live client to confirm C_VoiceChat.SpeakText speaks without voice chat enabled.* | `/fo tts` | `Quest/QuestReader.lua` |
| Leveling guide | ready | Step-by-step route window: accept, do and turn in this quest, go here, set hearth, train, reach a level. Advances from the quest log and the arrow's arrival, hides other classes' and races' steps, saves progress per character. Routes are text specs baked with QuestieDB names and coordinates (scripts/build_routes.py), with a shared Barrens section spliced in. Ships Orc & Troll 1-20 and Tauren 1-20 with the class quests for all six Horde classes: hunter pet, warlock Voidwalker, shaman totems, warrior Defensive Stance, priest Hex of Weakness, druid Bear Form and Cure Poison. *Gap: Step order is a first draft from the database, not a measured run.* | `/fo guide` | `Quest/Guide.lua`; HUD: Guide |

## Economy

| Add-in | Status | What it does | Commands | Where |
|---|---|---|---|---|
| Auction scanner | live check | Full scan when the auction house is open, on demand or automatically, feeding price history. *Gap: Retail C_AuctionHouse API assumed from client docs.* | `/fo scan`, `/fo autoscan`, `/fo ahstats` | `Economy/AuctionHouseScanner.lua`; HUD: Economy buttons |
| Item advisor | live check | Vendor, disenchant or auction? /fo advise <item> compares the vendor price, the lowest scanned auction listing net of the cut, and the expected value and range of disenchanting from the classic result table (dust / essence / shard by quality and item level, armour favours dust, weapons essence) priced from your scans. Sure money wins unless an alternative beats it by the margin; soulbound skips the auction; disenchant is only recommended at sufficient Enchanting skill. /fo advise bags sweeps the bags; a tooltip line shows the summary on hover. *Gap: Result table is the classic one; Forever may have retuned drop rates. Mats and items are unpriced until an AH scan.* | `/fo advise` | `Economy/ItemAdvisor.lua` |
| Price history | ready | Latest, 7-day and 30-day price per item, movers against their average, flips below vendor or far below average, and price watches that alert. | `/fo price`, `/fo movers`, `/fo flips`, `/fo watch`, `/fo unwatch` | `Economy/PriceHistory.lua` |
| Gold per hour | ready | Net gold per hour from the session ledger, effective rate with unrealized loot, repairs attributed to dungeon runs, dungeon versus open world. | `/fo gold`, `/fo dungeons` | `Economy/GoldPerHour.lua`; HUD: Economy |
| Inventory optimizer | ready | Classifies every bag slot as trash, auction, material, quest or keep by value per slot, sells trash on demand or automatically, and finds items and materials across all your characters and bank. | `/fo bags`, `/fo find`, `/fo mats`, `/fo bank` | `Economy/InventoryOptimizer.lua`; HUD: Economy buttons |
| Profession profit | live check | Craft margin per recipe from price history, cheapest skill-up path, and a sell-through factor. *Gap: Needs C_TradeSkillUI on the live client; deposit fee not modelled.* | `/fo craft` | `Economy/ProfessionProfit.lua` |

## Character

| Add-in | Status | What it does | Commands | Where |
|---|---|---|---|---|
| Gear evaluator | partial | Upgrade score against what you wear, as a tooltip line and a command, from editable stat weights per class. *Gap: Linear weights only; no damage model, procs or sets.* | `/fo gear`, `/fo weights` | `Character/GearEvaluator.lua` |
| Training planner | ready | Training costs ahead by level, ranks that are cheap to skip, profession training not yet learned, and savings goals such as the mount. | `/fo plan`, `/fo skip`, `/fo proftrain`, `/fo goal` | `Character/TrainingPlanner.lua`; HUD: Character |
| Consumable tracker | ready | Spend on food, drink, potions and buffs against the XP and kill rate while buffed versus not. | `/fo consumables` | `Character/ConsumableTracker.lua` |
| Progression planner | partial | Time to level from your recent rate, reputation sources and kills to next standing, hearth and travel suggestions from recorded legs. *Gap: No flight-path graph yet.* | `/fo eta`, `/fo rep`, `/fo hearth` | `Character/ProgressionPlanner.lua`; HUD: Character |
| Rotation optimizer | ready | Leveling priority for all nine classes with damage per mana from the seed and your measured numbers, talent builds checked against your points level by level, spell lookup with ranks and costs. *Gap: Rotations are first drafts to tune against real data.* | `/fo rotation`, `/fo build`, `/fo spell` | `Character/Rotation.lua, Data/Rotations.lua`; HUD: Character buttons |
| Rune discovery | live check | Diffs every Engrave spell and rune ability for your class against the spellbook. A new one is announced, flashed, noted and saved with level, zone and position. *Gap: Nobody knows yet how Forever hands runes out.* | `/fo runes` | `Character/Runes.lua` |

## Classes

| Add-in | Status | What it does | Commands | Where |
|---|---|---|---|---|
| Hunter | partial | Pet damage share and uptime, aspect, ammo remaining, happiness and food, Auto Shot clipping. *Gap: Pet training points not read yet.* | `/fo hunter` | `Classes/Hunter.lua`; HUD: Hunter |
| Auto Shot timer | live check | A bar from one Auto Shot to the next from the weapon speed, the last half second marked as the aim window and red while you move through it; casts pause the cycle and restart it when they land. Secret spell ids are read from the cast GUID. Wand Shoot gets the same bar. *Gap: Needs the live client to confirm START/STOP_AUTOREPEAT_SPELL and UNIT_SPELLCAST_SUCCEEDED carry readable data for Auto Shot.* | `/fo shotbar` | `Classes/AutoShot.lua` |
| Warlock | partial | Shard count with low and high warnings, demon damage share, DoT efficiency, mana spent versus Life Tapped. *Gap: Life Tap versus Drain Life trade-off math not built.* | `/fo warlock` | `Classes/Warlock.lua`; HUD: Warlock |
| Priest | partial | Wand versus spell share, drink share, heal per mana with overheal. *Gap: No buff uptime or per-fight regen model.* | `/fo priest` | `Classes/Priest.lua`; HUD: Priest |
| Shaman | live check | Shield charges, weapon imbue time left, totems down with time left, shocks, bolts and heals per kill, drink share, melee share and heal per mana from the combat log. Warns when a fight starts without a shield or an imbue and when the imbue has two minutes left. *Gap: Totem names, imbue timers and shield charges are read from client APIs the harness only stubs.* | `/fo shaman` | `Classes/Shaman.lua`; HUD: Shaman |

## Dashboard

| Add-in | Status | What it does | Commands | Where |
|---|---|---|---|---|
| HUD | ready | Movable frame with tabs and a button row per tab. Every button drives a command, so macros and key binds can click them too. | `/fo show`, `/fo hide`, `/fo toggle`, `/fo lock`, `/fo scale`, `/fo tab`, `/fo hud` | `Dashboard/Overview.lua`; HUD: Overview |
| Leveling, Economy, Character, History tabs | ready | Objective presets, quest or grind override, scan and autosell toggles, build switching, paged session history with comparison. | `/fo history` | `Dashboard/*.lua` |
| Direction arrow | live check | TomTom-style arrow with yards left, green when you face the target, red behind you; arrival fires the guide forward. Driven by the guide, /fo next, /fo route or /fo arrow <x> <y>. *Gap: Bearing to a target on another map needs C_Map.GetWorldPosFromMapPos; same-map works from the map's world size.* | `/fo arrow` | `Dashboard/Arrow.lua` |
| World map overlay | live check | Player and cursor coordinates, pins for recorded herb and ore nodes drawn with the gathered item's icon, rares, tracked spawn points with respawn estimate, available quests, objectives and turn-ins. Unexplored parts of the zone drawn from the client's own overlay art (seeded for 45 maps) and tinted darker; a map button, /fo map reveal and a key binding switch between full and explored-only. *Gap: Degrades to coordinates only if the client lacks the map data-provider API.* | `/fo map`, `/fo coords` | `Dashboard/MapOverlay.lua` |
| Help and manual | ready | Commands by area on a HUD tab and a scrollable manual window, both built from the live command registry so they cannot drift. | `/fo help`, `/fo manual` | `Dashboard/Help.lua`; HUD: Help |

## Tooling

| Add-in | Status | What it does | Commands | Where |
|---|---|---|---|---|
| Installers | ready | One command on Mac or Windows finds the game folder, fetches the latest release and QuestieDB with checksum, and installs both. |  | `scripts/install.sh, scripts/install-windows.ps1` |
| Collect and summarize | ready | After a session, zips the saved file and the game log; the Mac side converts to JSON and prints verify results, errors, sessions, notes, checklist and runes. |  | `scripts/collect.*, scripts/summarize.py` |
| SQLite export | ready | Loads the saved file into SQLite tables for offline analysis in any tool. |  | `scripts/fo_sqlite.py, scripts/savedvars_to_json.py` |
| Nightly backup | ready | launchd agent copies the saved files nightly and at login, keeps 30 days. |  | `scripts/backup.sh, scripts/backup-install.sh` |
| Test harness | ready | A fake WoW client in Lua: frames, events, combat log, spellbook, units, chat capture. Every module is loaded, every command smoke-run, 313 checks. |  | `test/run.lua, test/wowstub.lua` |
| CI, releases, seed updates | ready | Syntax check and harness on every push, zip release on tag, a daily job that rebuilds the item and spell seeds when the client build changes and opens an issue if validation fails. |  | `.github/workflows/*.yml` |
| HUD mockup generator | ready | Drives the harness, dumps every tab, button and command output, and renders the mockup page on GitHub Pages from real addon text. |  | `scripts/mock/` |

## Open slots

| Add-in | Status | What it does | Commands | Where |
|---|---|---|---|---|
| Routes 20 to 60 | open slot | The guide covers Orc, Troll and Tauren 1 to 20. Next: Stonetalon and Ashenvale 20 to 30, the Undead start in Tirisfal, and a generated route from QuestieDB level bands and chains weighted by measured drop rates and kill times. |  |  |
| Shared data pool | open slot | A watcher outside the game pushes the shareable parts of each player's file (nodes, rares, spawns, mob stats, prices) to a data repo; an Action merges them into Data/Shared.lua that the installer fetches and the addon merges on load. |  |  |
| More class trackers | open slot | Rotations and builds exist for all nine classes; live trackers exist for four. Mage, Rogue, Warrior, Paladin and Druid each need a status line and the class-specific numbers that matter when leveling. |  |  |
| Minimap pins | open slot | The world map has pins; the minimap does not. Nodes, rares and quest targets within range on the minimap. |  |  |
| Duo quest sync | open slot | Addon-to-addon messages between grouped players: who still needs which collection drop, whose turn-in is where, shared kill counts. |  |  |
| Offline session report | open slot | A rendered HTML report from the saved file: sessions, zones, gold, deaths, with charts, for sharing after a night of play. |  |  |
| Mob names from the database | open slot | Encounters are keyed by NPC id; QuestieDB has the names and levels. Fill them in so a mob is readable before you have fought it. |  |  |
| Flight-path graph | open slot | Travel planner knows your recorded legs only. A flight-path graph with costs and times would let it answer where to hearth and when to fly. |  |  |
| Damage-model gear evaluator | open slot | Replace linear stat weights with a per-class damage or healing model so upgrades are scored in DPS or HPS. |  |  |
| Hunter pet training | open slot | Training points, learned skills, next rank available from the stable or wild pets, happiness and loyalty forecast. |  |  |
| Buff and debuff uptime | open slot | Per-fight uptime of your own buffs, Hunter's Mark, curses and Power Word: Fortitude, from aura events in the combat log. |  |  |
| Your idea | open slot | Anything that turns something you can observe in game into a number that changes how you play. Open a proposal with the button at the top. |  |  |

Totals: 34 ready, 14 live check, 5 partial, 12 open slots.

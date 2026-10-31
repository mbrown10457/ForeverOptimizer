# ForeverOptimizer

One World of Warcraft: Forever addon that learns from your own play: leveling, gold, mobs, quests, auction house, inventory, gear, training, downtime. Mainline 12.1.5 client API with Midnight's addon restrictions; no combat log.

```
ForeverOptimizer/
  Core/        Init, Util, EventManager, DataStorage, CharacterProfile, SessionManager, AnalyticsEngine
  Grinding/    XPTracker, LootTracker, MobDatabase, FarmingEfficiency, DowntimeAnalyzer
  Quest/       QuestTracker, QuestEfficiency, QuestRoutePlanner
  Economy/     PriceHistory, AuctionHouseScanner, GoldPerHour, InventoryOptimizer, ProfessionProfit
  Character/   GearEvaluator, TrainingPlanner, ConsumableTracker, ProgressionPlanner
  Classes/     Hunter, Warlock, Priest
  Dashboard/   Overview (HUD + tabs), Leveling, Economy, Character
```

## Install

1. Launch WoW Forever once so the client creates its `_forever_/Interface` folder.
2. `scripts/install.sh` symlinks `ForeverOptimizer/` into `Interface/AddOns`. Pass the path if auto-detect fails.
3. In game: `/reload`, then `/fo help`. If it shows as out of date, tick "Load out of date AddOns" and note the real Interface number.
4. Install BugSack + BugGrabber from CurseForge (Forever profile) to capture Lua errors.

## Commands

Everything is `/fo <command>`. `/fo help` lists them grouped by area. Highlights:

| Area | Commands |
|---|---|
| Session | `session`, `session reset`, `session pause`, `estimate`, `recommend`, `zones`, `objective`, `levels`, `history` |
| Grinding | `mobs [xp\|gold\|kills\|safe] [here]`, `mob <id\|name>`, `respawn`, `nodes`, `route [herb\|ore]`, `rares`, `competition`, `downtime`, `deaths`, `legs` |
| Quest | `quests`, `quest <id>`, `next`, `route`, `drops`, `questxp`, `autotrack` |
| Economy | `gold`, `dungeons`, `scan`, `autoscan`, `ahstats`, `price <item>`, `movers`, `flips`, `watch`, `unwatch`, `bags [...]`, `find <item>`, `mats`, `bank`, `craft [...]` |
| Character | `plan [level]`, `skip`, `proftrain`, `goal`, `gear <link>`, `weights`, `consumables`, `rep [faction]`, `hearth`, `eta [level]`, `me`, `skills` |
| Classes | `hunter`, `warlock`, `priest` |
| HUD | `show`, `hide`, `toggle`, `tab <name>`, `scale <n>`, `lock` |
| Setup | `verify`, `module [on\|off <name>]`, `dbstats`, `wipe <namespace\|all> confirm` |

## How it works

- **SessionManager** decides every second what you're doing (quest / grind / dungeon / travel / rest / town / dead / idle) and attributes XP, kills and gold to it. Everything else reads from that one session or listens to its `FO_*` messages.
- **Kills** come from the "X dies, you gain N experience" chat line; **drops** from the loot window and its source GUIDs. The combat log is never registered because 12.x refuses it.
- **Prices** come from full AH scans, passive browsing, and vendor windows. `Util.ItemValue` (what you could get) and `Util.ItemCost` (what it costs you) are the two numbers every module uses.
- **Respawn timers** are only called "confirmed" when you stayed in range of the kill spot and saw the replacement appear. Otherwise they're reported as upper bounds.
- **Secret values**: every number from the API goes through `Util.Num`, which returns nil for secrets so nothing throws in combat or instances. Numbers may read `--` until the restriction lifts.

## Out-of-game analysis

SavedVariables are plain Lua, written on logout or `/reload`:

```
/Applications/World of Warcraft/_forever_/WTF/Account/<ACCOUNT>/SavedVariables/ForeverOptimizer.lua
```

`scripts/savedvars_to_json.py <file> --var ForeverOptimizerDB -o fo.json` converts it with no Lua runtime. `scripts/fo_sqlite.py <file> -o fo.sqlite` goes further and upserts sessions, zone segments, dungeons, mobs, drops, encounters, loot, prices, quests, nodes, respawns and verify results into SQLite, so history outlives the in-game caps. Everything lives under `account.<namespace>` and `chars.<Name-Realm>.<namespace>`.

`scripts/package.sh` zips the addon into `dist/` for friends.

## Tests

`lua test/run.lua` loads the TOC in order inside a stubbed WoW client and drives login, combat, loot, quests, death, rest, travel, a dungeon run, trainer, vendor, bank, gear comparison, every slash command and every HUD tab. `brew install lua` once. Add `-v` to see chat output.

## Plan and tracking

`docs/Development_Plan.md` is the plan; `docs/PLAN_TRACKER.md` maps every item in it to a module, a command and a status. Update the tracker when something ships or gets verified.

## Verify on first real launch

Run `/fo verify` first. It probes every API below and saves the result.

- TOC Interface number (we ship `120105, 16001`) and the `_forever_` folder name.
- Retail commodity/item AH API vs classic list AH. Only `Economy/AuctionHouseScanner.lua` depends on it.
- `C_QuestLog.GetNextWaypoint` for vanilla quests. If it returns nothing, QuestPath falls back to recorded points.
- `C_TradeSkillUI` recipe schematics and `GetItemStats` stat keys on this client.
- Which values are secret in open-world combat, and whether `UNIT_SPELLCAST_SENT` still carries the node name for gathering.

## Conventions

Lua 5.1. No `goto`, no integer division, no `#` on tables with holes. Modules register with `FO:NewModule(name, def)`; see `Core/Init.lua` for the def shape. Never do arithmetic on an API value without `U.Num` first.

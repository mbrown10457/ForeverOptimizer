# ForeverOptimizer

One World of Warcraft: Forever addon that learns from your own play: leveling, gold, mobs, quests, auction house, inventory, gear, training, downtime. Written for the Forever client (product `wowf`, build 1.60.1.x, modern engine) and defensive about Midnight-era addon restrictions: no combat log, every API number checked for secret values.

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
4. Lua errors inside the addon are caught and saved; `/fo errors` lists them and `/fo errors <n>` shows the stack. BugSack + BugGrabber are still useful for errors in other addons or Blizzard code.

### Windows

The addon is the same on both platforms; only the helper scripts differ.

- **Just playing:** extract `dist/ForeverOptimizer-<version>.zip` (made by `scripts/package.sh`) into `C:\Program Files (x86)\World of Warcraft\_forever_\Interface\AddOns\`. The zip carries an `INSTALL.txt` with the same steps for both operating systems.
- **Working from the repo:** `powershell -ExecutionPolicy Bypass -File scripts\install.ps1` copies the addon into AddOns (it finds the game via the registry and the usual folders, or takes `-AddOns <path>`). Add `-Link` for a directory junction so the game loads the repo copy directly, the Windows equivalent of the Mac symlink.
- **Offline tools** (`savedvars_to_json.py`, `fo_sqlite.py`, `build_seed.py`) are plain Python 3 and run unchanged. The saved data is at `...\_forever_\WTF\Account\<ACCOUNT>\SavedVariables\ForeverOptimizerDB.lua`.

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
| Combat log | `combat`, `dots`, `heals`, `autoshot`, `combatlog` (only when the client allows the log) |
| Rotation | `rotation [check\|CLASS]`, `build [list\|<n>\|use <n>]`, `spell <name>` |
| Quests | `nearby [all]`, `questinfo <id\|name>`, `qdb`, `route all` (quest database via QuestieDB, optional) |
| Map | `map [nodes\|rares\|spawns\|coords on\|off]`, `map minseen <n>`, `map refresh`, `coords` |
| Setup | `verify`, `errors [n\|clear]`, `seed [id\|name]`, `module [on\|off <name>]`, `dbstats`, `wipe <namespace\|all> confirm` |

## How it works

- **SessionManager** decides every second what you're doing (quest / grind / dungeon / travel / rest / town / dead / idle) and attributes XP, kills and gold to it. Everything else reads from that one session or listens to its `FO_*` messages.
- **Kills** come from the "X dies, you gain N experience" chat line; **drops** from the loot window and its source GUIDs. The combat log is never relied on: 12.x refuses it, and whether Forever's 1.60 client does is one of the first things `/fo verify` reports.
- **Combat log, optimistically.** `Core/CombatLog.lua` tries to register the combat log in a protected call. If the client allows it, `Grinding/CombatStats.lua` measures damage by spell and by source (you vs pet), damage taken, fight lengths, healing with overheal, mana spent per spell (cost read at cast time), DoT efficiency (ticks delivered vs lost to early refresh or the target dying), and Auto Shot / wand clipping. The class modules show pet share, clipping, DoT efficiency and heal-per-mana lines, and MobDatabase gets precise kill times and damage taken per fight. If the client refuses the log, or hides amounts as secret values, every consumer falls back to the chat-line and loot-window paths and `/fo combatlog` says why.
- **Rotation optimizer.** `Data/Spells.lua` and `Data/Talents.lua` are generated from the client's own spell and talent tables (every class spell with ranks, learn levels, costs, cast times, cooldowns, durations and base points; every talent with tab, tier, column, ranks and prerequisites). `Data/Rotations.lua` holds hand-authored leveling priorities and talent builds for all nine classes, written against Forever's trees, which include rune-style "Engrave" abilities and reworked talents. `/fo rotation` prints the priority list for the spells you actually know, with measured damage or healing per cast and per mana from the combat log where there are enough casts, estimates from the seed otherwise, plus ranks you can train now and abilities still ahead of you. `/fo build` compares a build to your live talent points and names the next points to spend. Every name is validated against the seed at load, in the harness, and in CI.
- **Item seed**: `Data/Items.lua` carries every item in the Forever client (name, vendor sell and buy price, quality, class, levels, stack size, bind type), generated from the client's own data tables on wago.tools by `scripts/build_seed.py`. Item helpers fall back to it when the client cache is cold, so bag values and vendor costs are right from the first minute. Live data always overrides it. `/fo seed <id|name>` looks items up; rerun the script when the client build changes.
- **Quest database, optional.** Install [QuestieDB](https://www.curseforge.com/wow/addons/questiedb) (the database Questie itself reads; it has a Forever flavour) and ForeverOptimizer queries it live through its public API: quest names, levels, givers, finishers, objectives, prerequisites and chains, and NPC/object spawn coordinates. Nothing from it is copied into this addon, and its own notes say many Forever quest givers still lack coordinates, so your recorded accept, objective and turn-in positions always count too and win where they exist. With it installed: `/fo nearby` lists quests you can pick up on the current map, nearest first, after checking level window, race, class, prerequisites, chains and completion; `/fo questinfo` prints a quest's facts; `/fo route all` adds pickups to the objective route; the route planner falls back to database objective and turn-in locations; and the world map shows available-quest, objective and turn-in pins. Without it, the quest modules work from recorded data alone and `/fo qdb` says so.
- **World map overlay**: the open map shows your coordinates and the cursor's in its bottom-left corner, and pins every herb and ore node you have gathered (green and yellow), every rare you have seen (red), quest givers, objectives and turn-ins when QuestieDB is installed, and optionally the spawn points of mobs you track with their respawn estimate (gray). Pins come from your own records, so a zone fills in as you play it; hover a pin for how often and how recently it was seen. `/fo map` toggles layers. The HUD Overview also carries a position line and `/fo coords` prints it to chat.
- **Errors** inside any handler, tick or command are caught by `FO.Try`, printed at most three times, and saved with a stack to `account.errors.log`. `/fo errors` lists them in game; `scripts/fo_sqlite.py` exports them.
- **Prices** come from full AH scans, passive browsing, and vendor windows. `Util.ItemValue` (what you could get) and `Util.ItemCost` (what it costs you) are the two numbers every module uses.
- **Respawn timers** are only called "confirmed" when you stayed in range of the kill spot and saw the replacement appear. Otherwise they're reported as upper bounds.
- **Secret values**: every number from the API goes through `Util.Num`, which returns nil for secrets so nothing throws in combat or instances. Numbers may read `--` until the restriction lifts.

## Out-of-game analysis

The SavedVariables file is written on logout or `/reload`:

| | Path |
|---|---|
| macOS | `/Applications/World of Warcraft/_forever_/WTF/Account/<ACCOUNT>/SavedVariables/ForeverOptimizerDB.lua` |
| Windows | `C:\Program Files (x86)\World of Warcraft\_forever_\WTF\Account\<ACCOUNT>\SavedVariables\ForeverOptimizerDB.lua` |


`scripts/savedvars_to_json.py <file> --var ForeverOptimizerDB -o fo.json` converts it with no Lua runtime. `scripts/fo_sqlite.py <file> -o fo.sqlite` goes further and upserts sessions, zone segments, dungeons, mobs, drops, encounters, loot, prices, quests, nodes, respawns, verify results and the saved error log into SQLite, so history outlives the in-game caps. Everything lives under `account.<namespace>` and `chars.<Name-Realm>.<namespace>`.

`scripts/package.sh` zips the addon plus `INSTALL.txt` into `dist/` for friends on either platform.

## Keeping the data current

The seeds are regenerated from the client's tables, so numbers, ranks, levels and talent trees follow patches without hand edits. `scripts/check_build.py` reports whether wago.tools lists a newer Forever build than `ForeverOptimizer/Data/BUILD`; `scripts/build_seed.py` and `scripts/build_spells.py` rebuild the seeds for a build. The `seed-update` GitHub Actions workflow runs daily: when a new client build appears it regenerates the seeds, runs the harness and the rotation validator, commits to main if everything passes, and opens an issue with the validator output if a patch renamed or removed something the hand-authored rotations or builds reference. The `ci` workflow runs the harness on every push and the `release` workflow attaches the zip to a GitHub Release on every `v*` tag.

## Tests

`lua test/run.lua` loads the TOC in order inside a stubbed WoW client and drives login, combat, loot, quests, death, rest, travel, a dungeon run, trainer, vendor, bank, gear comparison, every slash command and every HUD tab. `brew install lua` once. Add `-v` to see chat output.

## Plan and tracking

`docs/Development_Plan.md` is the plan; `docs/PLAN_TRACKER.md` maps every item in it to a module, a command and a status. Update the tracker when something ships or gets verified.

## Verify on first real launch

Run `/fo verify` first. It probes every API below and saves the result.

- TOC Interface number. wago.tools lists Forever as product `wowf`, version 1.60.1 (build 70707 on 2026-10-30), which maps to Interface `16001`; we ship `120105, 16001` so either client answers. The folder is `_forever_`.
- Whether the Midnight-era restrictions (combat log refused, secret values in combat) apply to the 1.60 client at all. Everything is written to work either way; if they don't apply, the class modules can be upgraded to real combat-log data.
- Retail commodity/item AH API vs classic list AH. Only `Economy/AuctionHouseScanner.lua` depends on it.
- `C_QuestLog.GetNextWaypoint` for vanilla quests. If it returns nothing, QuestPath falls back to recorded points.
- `C_TradeSkillUI` recipe schematics and `GetItemStats` stat keys on this client.
- Which values are secret in open-world combat, and whether `UNIT_SPELLCAST_SENT` still carries the node name for gathering.

## Conventions

Lua 5.1. No `goto`, no integer division, no `#` on tables with holes. Modules register with `FO:NewModule(name, def)`; see `Core/Init.lua` for the def shape. Never do arithmetic on an API value without `U.Num` first.

# ForeverOptimizer

[![latest release](https://img.shields.io/github/v/release/mbrown10457/ForeverOptimizer?label=release)](https://github.com/mbrown10457/ForeverOptimizer/releases/latest) [![ci](https://github.com/mbrown10457/ForeverOptimizer/actions/workflows/ci.yml/badge.svg)](https://github.com/mbrown10457/ForeverOptimizer/actions/workflows/ci.yml)

One World of Warcraft: Forever addon that learns from your own play: leveling, gold, mobs, quests, auction house, inventory, gear, training, downtime. Written for the Forever client (product `wowf`, build 1.60.1.x, modern engine) and defensive about Midnight-era addon restrictions: no combat log, every API number checked for secret values.

```
ForeverOptimizer/
  Core/        Init, Util, SeedData, EventManager, Alerts, DataStorage, CharacterProfile, SessionManager,
               CombatLog, CombatFeed (UNIT_COMBAT stand-in for the missing combat log), AnalyticsEngine, Verify, Checklist
  Data/        Items, Spells, Talents, MapOverlays, Rotations, Routes, Nodes (generated seeds; scripts/build_*.py)
  Grinding/    XPTracker, LootTracker, MobDatabase, CombatStats, Meter, FarmingEfficiency, DowntimeAnalyzer
  Quest/       QuestTracker, QuestDatabase (QuestieDB adapter), QuestEfficiency, QuestRoutePlanner (quest router), Guide (leveling guide)
  Economy/     PriceHistory, AuctionHouseScanner, GoldPerHour, InventoryOptimizer, ItemAdvisor (vendor / disenchant / auction), ProfessionProfit
  Character/   GearEvaluator, TrainingPlanner, ConsumableTracker, ProgressionPlanner, Rotation, Runes
  Classes/     Hunter, AutoShot (timer bar), Warlock, Priest, Shaman
  Dashboard/   Overview (HUD + tabs; the class module gets its own tab), Leveling, Economy, Character, History, Help, MinimapNodes,
               Arrow (direction arrow), MapOverlay (world map pins, route stops, unexplored art)
```

## Install

1. Launch WoW Forever once so the client creates its `_forever_/Interface` folder.
2. `scripts/install.sh` symlinks `ForeverOptimizer/` into `Interface/AddOns` and, if `scripts/get_questiedb.sh` has staged it, installs QuestieDB next to it. Pass the path if auto-detect fails.
3. In game: `/reload`, then `/fo help`. If it shows as out of date, tick "Load out of date AddOns" and note the real Interface number.
4. Lua errors inside the addon are caught and saved; `/fo errors` lists them and `/fo errors <n>` shows the stack. BugSack + BugGrabber are still useful for errors in other addons or Blizzard code.

### Windows

The addon is the same on both platforms; only the helper scripts differ.

- **Just playing (one command):** see [WINDOWS_README.md](WINDOWS_README.md). In PowerShell, `irm https://raw.githubusercontent.com/mbrown10457/ForeverOptimizer/main/scripts/install-windows.ps1 | iex` finds the game, downloads the latest release and QuestieDB, verifies the QuestieDB checksum and installs both. Re-run to update.
- **By hand:** extract `dist/ForeverOptimizer-<version>.zip` (made by `scripts/package.sh`, attached to every GitHub release) into `C:\Program Files (x86)\World of Warcraft\_forever_\Interface\AddOns\`. The zip carries an `INSTALL.txt` with the same steps for both operating systems.
- **Working from the repo:** `powershell -ExecutionPolicy Bypass -File scripts\install.ps1` copies the addon into AddOns (it finds the game via the registry and the usual folders, or takes `-AddOns <path>`). Add `-Link` for a directory junction so the game loads the repo copy directly, the Windows equivalent of the Mac symlink.
- **Offline tools** (`savedvars_to_json.py`, `fo_sqlite.py`, `build_seed.py`) are plain Python 3 and run unchanged. The saved data is at `...\_forever_\WTF\Account\<ACCOUNT>\SavedVariables\ForeverOptimizer.lua`.

## What it looks like

The full add-in catalog with architecture and open slots is at [mbrown10457.github.io/ForeverOptimizer/addins.html](https://mbrown10457.github.io/ForeverOptimizer/addins.html) (`docs/FEATURES.md` is the same list as a table; regenerate with `node scripts/build_features.js docs/addins.html docs/FEATURES.md`). Propose a new one with the **Add-in proposal** issue template.

[mbrown10457.github.io/ForeverOptimizer/mockup.html](https://mbrown10457.github.io/ForeverOptimizer/mockup.html) (source: `docs/mockup.html`) is an interactive mock of the addon in game: the HUD with every tab and its buttons, the world map pins, and the chat output of the day-one commands. Open it in a browser. The text is produced by the addon's own code run through the test harness (`scripts/mock/dump_ui.lua`), with sample session numbers; regenerate it after UI changes with:

```
lua scripts/mock/dump_ui.lua > /tmp/ui_dump.txt && python3 scripts/mock/build_mock.py /tmp/ui_dump.txt scripts/mock/template.html docs/mockup.html
```

## After a session: send the data

- **Mac:** `scripts/collect.sh` copies every account's `ForeverOptimizer.lua`, converts it to JSON, prints the launch-day summary (`scripts/summarize.py`: verify results, saved errors, sessions with notes, checklist, runes) and zips it under `dist/collect/`.
- **Windows:** the collect line in [WINDOWS_README.md](WINDOWS_README.md) zips the same data to the Desktop.
- **Nightly backup (Mac):** `scripts/backup-install.sh` installs a launchd agent that copies the SavedVariables to `~/Backups/ForeverOptimizer/<date>/` at 04:30 and at login, keeping 30 days. `status` and `remove` are the other verbs. Plain user paths, no extra permissions.

## Commands

Everything is `/fo <command>`. `/fo help` lists them grouped by area. Highlights:

| Area | Commands |
|---|---|
| Session | `session`, `session reset`, `session pause`, `note <text>`, `estimate`, `recommend`, `zones`, `objective`, `levels`, `history` |
| Grinding | `mobs [xp\|gold\|kills\|safe] [here]`, `mob <id\|name>`, `respawn`, `nodes`, `route [herb\|ore]`, `rares`, `competition`, `downtime`, `deaths`, `legs` |
| Quest | `quests`, `quest <id>`, `next`, `route [all\|follow [all]\|stop\|skip\|group\|show]`, `drops`, `questxp`, `autotrack`, `tts [on\|off\|again\|voice <n>\|rate\|volume\|gossip\|objectives\|test]` |
| Economy | `gold`, `dungeons`, `scan`, `autoscan`, `ahstats`, `price <item>`, `movers`, `flips`, `watch`, `unwatch`, `bags [...]`, `advise [<item>|bags|tooltip|margin <pct>]`, `find <item>`, `mats`, `bank`, `craft [...]` |
| Character | `plan [level]`, `skip`, `proftrain`, `goal`, `gear <link>`, `weights`, `consumables`, `rep [faction]`, `hearth`, `eta [level]`, `me`, `skills` |
| Classes | `hunter`, `shotbar [on\|off\|lock\|always\|scale\|width\|aim\|wand\|test]`, `warlock`, `priest`, `shaman` |
| HUD | `show`, `hide`, `toggle`, `tab <name>`, `scale <n>`, `lock` |
| Combat log | `combat`, `dots`, `heals`, `autoshot`, `combatlog`, `combatfeed` (Forever has no combat log: a UNIT_COMBAT feed estimates the same numbers) |
| Group meter | `dps [fight\|last\|session]`, `hps [...]`, `meter [reset\|rows <n>\|mode dps\|hps]` — damage and healing per player, pets credited to their owner, plus a Meter tab on the HUD (estimated from hits on your target on Forever) |
| Runes | `runes` — engravings and rune abilities learned, with level, zone and position; each new one is announced, flashed and stamped into the session notes |
| Help | `manual` — opens the in-game manual window; the HUD's Help tab pages through every command by area and has a Window button for the same |
| HUD buttons | `hud list`, `hud click <button>` — every HUD tab has a row of buttons under the tabs (Meter: Fight / Last / Session, DPS / HPS, Mine; Overview: Pause, Reset, Lock, Sound, Flash; Leveling: objective and forced activity; Economy: Scan AH, Autoscan, Autosell, Sell trash; Character: builds; History: Newer / Older / Report). The command form exists for macros and key binds. |
| Rotation | `rotation [check\|CLASS]`, `build [list\|<n>\|use <n>]`, `spell <name>` |
| Quests | `nearby [all]`, `questinfo <id\|name>`, `qdb`, `route all` (quest database via QuestieDB, optional) |
| Guide | `guide [list\|use <n>\|skip\|back\|goto <n>\|reset\|show\|hide\|arrow on\|off]` — step-by-step leveling route with its own window and HUD tab; `arrow [<x> <y> [label]\|clear\|on\|off\|lock\|arrive <yards>\|scale <n>]` — the direction arrow |
| Map | `map reveal\|tint [on\|off]`, `map [nodes\|rares\|spawns\|coords on\|off]`, `map seed [herb\|ore] on\|off`, `map minseen <n>`, `map refresh`, `coords`, `minimap [on\|off\|herb\|ore\|seed on\|off\|size <n>\|minseen <n>]` |
| Setup | `checklist [reset]`, `alerts [...]`, `verify`, `errors [n\|clear]`, `seed [id\|name]`, `module [on\|off <name>]`, `dbstats`, `wipe <namespace\|all> confirm` |

## How it works

- **SessionManager** decides every second what you're doing (quest / grind / dungeon / travel / rest / town / dead / idle) and attributes XP, kills and gold to it. Everything else reads from that one session or listens to its `FO_*` messages.
- **Kills** come from the "X dies, you gain N experience" chat line; **drops** from the loot window and its source GUIDs. The combat log is never relied on: 12.x refuses it, and whether Forever's 1.60 client does is one of the first things `/fo verify` reports.
- **Combat log, optimistically.** `Core/CombatLog.lua` tries to register the combat log in a protected call. If the client allows it, `Grinding/CombatStats.lua` measures damage by spell and by source (you vs pet), damage taken, fight lengths, healing with overheal, mana spent per spell (cost read at cast time), DoT efficiency (ticks delivered vs lost to early refresh or the target dying), and Auto Shot / wand clipping. The class modules show pet share, clipping, DoT efficiency and heal-per-mana lines, and MobDatabase gets precise kill times and damage taken per fight. Forever's client has no combat log at all (registering the event is a forbidden action), so `Core/CombatFeed.lua` stands in: `UNIT_COMBAT` reports every hit, heal and miss on you, your pet, your target and nearby nameplates with an amount and a school but no source or spell, and the feed attributes each one (your last cast of that school, a running DoT, or Melee; your pet when it is on that mob and you cast nothing physical) and emits the same normalized events. The meter, combat stats, rotation measurements and class tabs then work as estimates: solo numbers are close, in a group the damage others do to your target is counted as yours. `/fo combatlog` and `/fo combatfeed` say which path is live.
- **Rotation optimizer.** `Data/Spells.lua` and `Data/Talents.lua` are generated from the client's own spell and talent tables (every class spell with ranks, learn levels, costs, cast times, cooldowns, durations and base points; every talent with tab, tier, column, ranks and prerequisites). `Data/Rotations.lua` holds hand-authored leveling priorities and talent builds for all nine classes, written against Forever's trees, which include rune-style "Engrave" abilities and reworked talents. `/fo rotation` prints the priority list for the spells you actually know, with measured damage or healing per cast and per mana from the combat log where there are enough casts, estimates from the seed otherwise, plus ranks you can train now and abilities still ahead of you. `/fo build` compares a build to your live talent points and names the next points to spend. Every name is validated against the seed at load, in the harness, and in CI.
- **Item seed**: `Data/Items.lua` carries every item in the Forever client (name, vendor sell and buy price, quality, class, levels, stack size, bind type), generated from the client's own data tables on wago.tools by `scripts/build_seed.py`. Item helpers fall back to it when the client cache is cold, so bag values and vendor costs are right from the first minute. Live data always overrides it. `/fo seed <id|name>` looks items up; rerun the script when the client build changes.
- **Quest database, optional.** Install [QuestieDB](https://www.curseforge.com/wow/addons/questiedb) (the database Questie itself reads; it has a Forever flavour) and ForeverOptimizer queries it live through its public API: quest names, levels, givers, finishers, objectives, prerequisites and chains, and NPC/object spawn coordinates. Nothing from it is copied into this addon except the baked route data, and your recorded accept, objective and turn-in positions always count too and win where they exist. With it installed: `/fo nearby` lists quests you can pick up on the current map, nearest first, after checking level window, race, class, prerequisites, chains and completion; `/fo questinfo` prints a quest's facts; `/fo route all` adds pickups to the quest loop; the router builds its objective patches and turn-in stops from the database; and the world map shows available-quest, objective and turn-in pins. Without it, the quest modules work from recorded data alone and `/fo qdb` says so.
- **World map overlay**: the open map shows your coordinates and the cursor's in its bottom-left corner, and pins every herb and ore node you have gathered with the gathered item's own icon (Peacebloom, Copper Ore; a generic herb or pick icon when the item is unknown), every rare you have seen (red), quest givers, objectives and turn-ins when QuestieDB is installed, and optionally the spawn points of mobs you track with their respawn estimate (gray). Pins come from your own records, so a zone fills in as you play it; hover a pin for how often and how recently it was seen. `/fo map` toggles layers. The map also shows the parts of the zone you have not explored yet, drawn from the client's own map art (`Data/MapOverlays.lua` lists every exploration overlay of every map; the client says which are already revealed) and tinted darker so you can still tell where you have been. The button in the map's bottom-right corner, `/fo map reveal` and a key binding switch between the full map and the explored-only map; `/fo map tint off` draws the unexplored parts at full brightness. The HUD Overview also carries a position line and `/fo coords` prints it to chat.
- **Node seed.** `Data/Nodes.lua` carries 19,453 herb and ore spawn points for 50 node types on 41 maps, the new Forever zones included, built by `scripts/build_nodes.py` from [GatherLite](https://github.com/Wuild/GatherLite)'s Forever database (MIT, see `Data/NODES_LICENSE.txt`), which is itself scraped from [Wowhead's Forever maps](https://www.wowhead.com/forever/). They draw on the world map and minimap as smaller, dimmer pins under your own sightings, with the same item icons, and hover shows the skill needed; a seeded point within a few yards of a node you gathered yourself gives way to your record. `/fo route herb|ore` plans through them too, so a gathering loop works in a zone you have never farmed. `/fo map seed off`, `map seed herb|ore off` and `/fo minimap seed off` hide them.
- **Minimap node icons.** The same herb and ore nodes, with the same item icons, on the minimap: placed by yards from you against the minimap's zoom radius, indoors or out, and turned with the minimap when it rotates. Hover one for the name, how often it was seen and how far away it is. `/fo minimap off`, `herb off`, `ore off`, `size <px>`.
- **Leveling guide.** `/fo guide` follows a route from `Data/Routes.lua` (generated by `scripts/build_routes.py` from the text specs in `scripts/routes/`, with quest titles, givers and coordinates baked in from QuestieDB so nobody needs it installed): accept, do and turn in this quest, go here, set your hearth, train, reach a level. Quest steps complete themselves from the quest log, travel steps when the arrow arrives, the rest on Skip or when the trainer or hearth event happens; steps for other classes are hidden; a step you cannot do yet says why and waits. Progress is per character. Two routes ship: Orc & Troll 1 to 20 (Durotar through the Barrens) and Tauren 1 to 20 (Mulgore and Thunder Bluff through the Barrens), with the class quests for every Horde class on them: hunter pet, warlock Voidwalker, shaman totems, warrior Defensive Stance, priest Hex of Weakness, druid Bear Form and Cure Poison. Race-specific quests (the Orc and Troll class parchments) show only to that race. [docs/Leveling_Guide.md](docs/Leveling_Guide.md) has the step format.
- **Vendor, disenchant or auction?** `/fo advise <item>` (shift-click it) puts the three side by side: the vendor's price, the lowest auction listing from your own scans net of the 5% cut, and what disenchanting would yield. The disenchant figure uses the classic result table by quality and item level (dust, essence or shard; armour favours dust, weapons favour essence; blues give a shard, purples shards or a Nexus Crystal), each material priced from the same scans, shown as an expected value and a low-to-high range with the chance of each result. Sure money wins unless an alternative beats it by a margin (default 10%), soulbound items skip the auction, and disenchanting is only recommended when this character's Enchanting is high enough; otherwise the note says what an enchanter would get. `/fo advise bags` sweeps everything green or better in your bags, and every item tooltip carries a one-line `FO: vendor | AH | DE -> call` summary (`/fo advise tooltip` turns it off).
- **Quest reader.** Quest text read aloud through the client's own text-to-speech engine, the one chat TTS uses: title, description and objectives when a quest window opens, the progress and reward text at the turn-in, NPC gossip too. Closing the window stops the voice. `/fo tts voice` lists the installed system voices, `rate` and `volume` tune it, `again` repeats the last text, `off` silences it.
- **Quest router.** `/fo route` turns the quest log into an ordered loop on the current map: every unfinished objective's spawn points (from QuestieDB) and the spots where it ticked for you are grouped into patches, patches shared by several quests become one stop, each turn-in is placed only after that quest's patches, and quests sharing a finisher share the stop. `route all` adds pickups available on the map (a pickup's objectives join existing patches, delivery quests get their turn-in queued behind it). Order is nearest-neighbour under those rules, then 2-opt. `route follow` keeps it live: every quest log change replans and the arrow advances; at an objective patch the arrow holds the spot until the objective ticks off, `route skip` jumps a stop, `route stop` hands the arrow back to the guide. Group, dungeon and raid quests stay out unless `route group` lets them in. Numbered stops show on the world map and in the Route HUD tab.
- **Direction arrow.** A TomTom-style arrow with yards left, green when you face the target, red when it is behind you. The guide, `/fo next`, `/fo route` and `/fo arrow <x> <y>` all drive it; it uses the client's world-space conversion when present so a target on another map still points the right way. Right-click clears it.
- **First-hour checklist.** `/fo checklist` lists the ten one-time visits and commands that seed every data layer (verify, errors, combat log, quest database, map, vendor, trainer, AH scan, bank, profession window) and ticks them off per character as they happen.
- **Auto Shot timer.** A bar that fills from one Auto Shot to the next using the weapon speed, with the last half second marked as the aim window and turned red while you are moving through it. A cast such as Aimed Shot or Multi-Shot pauses the cycle and restarts it when the cast lands. Shows while auto-repeat is on (`/fo shotbar always` keeps it up), drag to move, `/fo shotbar lock | scale | width | aim | test`. Wand Shoot gets the same bar on casters (`/fo shotbar wand off` to disable).
- **Alerts.** A sound, one chat line and a few seconds of centre-screen text (the client's error frame; `/fo alerts flash off` to keep it chat-only) for a rare's nameplate, a tracked respawn window opening while you're within 150 yards of the kill spot, bags running low, Hunter ammo or Warlock shards under a threshold. `/fo alerts` toggles each kind, the sound, and the thresholds; identical alerts are throttled.
- **Session notes.** `/fo note <text>` stamps a note with time, level, zone and activity into the current session; it is archived with the session and exported to SQLite.
- **Key bindings.** Toggle HUD, waypoint to the next quest target, list nearby quests, toggle the unexplored map art, toggle the leveling guide window and skip a guide step, under ForeverOptimizer in the game's key bindings panel.
- **Errors** inside any handler, tick or command are caught by `FO.Try`, printed at most three times, and saved with a stack to `account.errors.log`. `/fo errors` lists them in game; `scripts/fo_sqlite.py` exports them.
- **Prices** come from full AH scans, passive browsing, and vendor windows. `Util.ItemValue` (what you could get) and `Util.ItemCost` (what it costs you) are the two numbers every module uses.
- **Respawn timers** are only called "confirmed" when you stayed in range of the kill spot and saw the replacement appear. Otherwise they're reported as upper bounds.
- **Secret values**: every number from the API goes through `Util.Num`, which returns nil for secrets so nothing throws in combat or instances. Numbers may read `--` until the restriction lifts.

## Out-of-game analysis

The SavedVariables file is written on logout or `/reload`:

| | Path |
|---|---|
| macOS | `/Applications/World of Warcraft/_forever_/WTF/Account/<ACCOUNT>/SavedVariables/ForeverOptimizer.lua` |
| Windows | `C:\Program Files (x86)\World of Warcraft\_forever_\WTF\Account\<ACCOUNT>\SavedVariables\ForeverOptimizer.lua` |


`scripts/savedvars_to_json.py <file> --var ForeverOptimizerDB -o fo.json` converts it with no Lua runtime. `scripts/fo_sqlite.py <file> -o fo.sqlite` goes further and upserts sessions, zone segments, dungeons, mobs, drops, encounters, loot, prices, quests, nodes, respawns, verify results and the saved error log into SQLite, so history outlives the in-game caps. Everything lives under `account.<namespace>` and `chars.<Name-Realm>.<namespace>`.

`scripts/package.sh` zips the addon plus `INSTALL.txt` into `dist/` for friends on either platform.

## Keeping the data current

The seeds are regenerated from the client's tables, so numbers, ranks, levels and talent trees follow patches without hand edits. `scripts/check_build.py` reports whether wago.tools lists a newer Forever build than `ForeverOptimizer/Data/BUILD`; `scripts/build_seed.py` and `scripts/build_spells.py` rebuild the seeds for a build. The `seed-update` GitHub Actions workflow runs daily: when a new client build appears it regenerates the seeds, runs the harness and the rotation validator, commits to main if everything passes, and opens an issue with the validator output if a patch renamed or removed something the hand-authored rotations or builds reference. The `ci` workflow runs the harness on every push and the `release` workflow attaches the zip to a GitHub Release on every `v*` tag.
- Node seed: `python3 -I scripts/build_nodes.py <GatherLite checkout> --commit <sha> --date <date>` reads GatherLite's `plugins/database/data/forever.lua`, `scripts/nodes.lua` and `LICENSE` and rewrites `Data/Nodes.lua`.

## Tests

`lua test/run.lua` loads the TOC in order inside a stubbed WoW client and drives login, combat, loot, quests, death, rest, travel, a dungeon run, trainer, vendor, bank, gear comparison, every slash command and every HUD tab. `brew install lua` once. Add `-v` to see chat output.

## Plan and tracking

`docs/Development_Plan.md` is the plan; `docs/PLAN_TRACKER.md` maps every item in it to a module, a command and a status. Update the tracker when something ships or gets verified.

## Verify on first real launch

Run `/fo verify` first. It probes every API below and saves the result. Most of the list was already answered from the installed client's own API documentation (see `docs/Forever_API_Notes.md`): retail auction house API, `GetNextWaypoint`, `C_Item.GetItemStats`, retail `C_TradeSkillUI`, unrestricted nameplate events, namespaced pet happiness and classic-style talents. What remains is behaviour, not presence.

- The installed client is product `wowf`, build `1.60.1.70707`, in `_forever_`, Interface `16001`; we ship `120105, 16001`.
- Whether the combat log is restricted in the open world. The events exist with `HasRestrictions`, exactly as on mainline 12.1.5, and `C_CombatLog.IsCombatLogRestricted()` says which way it is at runtime. The combat log layer works either way.
- Whether health and power read as secret values outside instances. The secret-value system is present; every number already passes through `U.Num`.
- Which Forever experience preset is active (Classic or Enhanced), printed by verify.
- Retail commodity/item AH API vs classic list AH. Only `Economy/AuctionHouseScanner.lua` depends on it.
- `C_QuestLog.GetNextWaypoint` for vanilla quests. If it returns nothing, QuestPath falls back to recorded points.
- `C_TradeSkillUI` recipe schematics and `GetItemStats` stat keys on this client.
- Which values are secret in open-world combat, and whether `UNIT_SPELLCAST_SENT` still carries the node name for gathering.

## Conventions

Lua 5.1. No `goto`, no integer division, no `#` on tables with holes. Modules register with `FO:NewModule(name, def)`; see `Core/Init.lua` for the def shape. Never do arithmetic on an API value without `U.Num` first.

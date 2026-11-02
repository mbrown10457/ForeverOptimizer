# Forever client API notes (build 1.60.1.70707)

Source: the client's own `Blizzard_APIDocumentationGenerated` files for the installed build, fetched by
file ID from wago.tools on 2026-11-02 (643 of 686 documentation files exist in this build). Names only
are indexed in `forever_api_index.txt`. Everything below is from documentation, not from running the
client; `/fo verify` confirms behaviour on launch day.

## What the install told us

- Product `wowf`, version `1.60.1.70707`, installed to `/Applications/World of Warcraft/_forever_`.
- The graphics log identifies the binary as "World of Warcraft Retail ARM64 1.60.1.70707": the modern
  engine, so modern namespaced APIs, not the 1.12-era globals.
- The build key in `.build.info` matches the wago.tools build the item, spell and talent seeds came from.

## Answers to the verify list

| Question | Answer from the docs |
|---|---|
| Auction house API | Retail `C_AuctionHouse`: `ReplicateItems`, browse/commodity searches, `GetReplicateItemInfo`, events `REPLICATE_ITEM_LIST_UPDATE`, `AUCTION_HOUSE_BROWSE_RESULTS_UPDATED`, `COMMODITY_SEARCH_RESULTS_UPDATED`. The Classic AH constants file is absent. Our scanner's retail path applies. |
| Quest waypoints | `C_QuestLog.GetNextWaypoint`, `GetNextWaypointForMap`, `GetQuestsOnMap`, `IsQuestFlaggedCompleted`, `GetQuestObjectives` all present. |
| Item stats and info | `C_Item.GetItemStats`, `GetItemInfo`, `GetItemInfoInstant`, `GetItemCount`, `RequestLoadItemDataByID` present. |
| Map | `C_Map.GetPlayerMapPosition`, `GetBestMapForUnit`, `GetMapWorldSize`, `SetUserWaypoint`, `CanSetUserWaypointOnMap` present. |
| Trade skills | Retail `C_TradeSkillUI`: `GetRecipeInfo`, `GetRecipeSchematic`, `GetBaseProfessionInfo`, `GetChildProfessionInfos`. |
| Nameplates | `NAME_PLATE_UNIT_ADDED` / `REMOVED` present (C_NamePlateManager) and **not** flagged restricted. `C_NamePlate.GetNamePlateForUnit` present. Respawn confirmation can work. |
| Combat log | `COMBAT_LOG_EVENT_UNFILTERED` and `COMBAT_LOG_EVENT` exist but carry `HasRestrictions = true`, identical to mainline 12.1.5. `C_CombatLog.IsCombatLogRestricted()` reports the live state. Whether the restriction is active in Forever's open world is a server/ruleset decision the docs cannot show. The adapter registers in a pcall and reports both. |
| Secret values | The secret-value system is present: `C_Secrets.HasSecretRestrictions`, `ShouldUnitHealthMaxBeSecret`, `ShouldUnitPowerBeSecret`, and `UnitHealth`, `UnitHealthPercent`, `UnitHealthMissing` are marked as returning secrets. Every number already passes through `U.Num`. |
| Restricted events | Only seven events carry `HasRestrictions`: the four combat-log events, `MINIMAP_PING`, `UNIT_PING_PIN_ADDED`, `UNIT_PING_PIN_REMOVED`. Every event the addon relies on (XP gain chat, loot, spellcast, merchant, trainer, bank, trade skill, taxi, quest accepted/turned in, pet, bags, XP, money, zone, death) is unrestricted. |
| Addon restrictions | `C_RestrictedActions.IsAddOnRestrictionActive`, `GetAddOnRestrictionState`, event `ADDON_RESTRICTION_STATE_CHANGED`. |
| Pet happiness | Present, namespaced: `C_PetInfo.GetPetHappiness` (happiness, damage %, loyalty rate), `GetPetLoyalty`, `GetPetTrainingPoints`, `GetPetFoodTypes`. Hunter module reads either form. |
| Talents | Classic-style trees. `C_SpecializationInfo.GetTalentInfo({ specializationIndex, talentIndex })` returns `{ name, tier, column, rank, maxRank, spellID }`. A `CamelotCombat` trait config type exists. Retail `C_ClassTalents` loadout functions are also documented but describe the retail tree system. Rotation module tries the namespaced form, then the legacy globals. |
| Skill lines | `C_SkillInfo.GetNumSkillLines`, `GetSkillLineInfo`, `GetSkillLineInfoByID`. |
| Reputation | `C_Reputation.GetNumFactions`, `GetFactionDataByIndex`, `GetWatchedFactionData`. |
| Game rules | `C_GameRules.GetForeverExperiencePreset()` returns `Classic` (0) or `Enhanced` (1): Forever ships two experience presets. `IsHardcoreActive`, `IsSelfFoundAllowed`, `AccountHasSDEnabled` also exist. Worth printing in `/fo verify`. |
| Engraving / runes | No `C_Engraving` documentation in this build, although rune abilities exist in the spell table as "Engrave <slot> - <ability>". Rune state is read from the spellbook, not an engraving API. |

## Constants that name the flavour

`LevelConstsExposed_Camelot`, `QuestLogConstsMainlineCamelot`, `PetConsts_Camelot`, `LootConsts_Camelot`
and `TraitConfigType.CamelotCombat` exist: "Camelot" is the internal name for Forever, which is why the
install script also accepts a `_camelot_` folder.

## Still only answerable in game

- Whether `C_CombatLog.IsCombatLogRestricted()` is false in the open world.
- Whether health and power read as secrets outside instances.
- Whether the world-map data-provider API accepts our XML pin template (Blizzard_MapCanvas ships in every client, so it very likely does).
- Whether QuestieDB's Forever data loads under the client's game-type selection.

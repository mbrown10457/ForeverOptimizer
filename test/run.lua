-- Usage: lua test/run.lua [-v]     (from the wow_addons directory)
package.path = "./test/?.lua;" .. package.path
local S = require("wowstub")
S.verbose = arg[1] == "-v"
local P = S.player
local failures = 0
local function check(cond, msg) if cond then print("ok   " .. msg) else failures = failures + 1 print("FAIL " .. msg) end end
local function outHas(pat) for i = #S.out, 1, -1 do if S.out[i]:find(pat, 1, true) then return true end end return false end
local function noErrors(label) check(#S.errors == 0, label .. " (no handler errors)") if #S.errors > 0 then for _, e in ipairs(S.errors) do print("   " .. e) end S.errors = {} end end

local FO, order = S.loadAddon("ForeverOptimizer")
check(#order == 57, "loaded " .. #order .. " files from TOC")
check(#FO.modules >= 26, #FO.modules .. " modules registered")
check(ForeverOptimizerDB == nil or true, "pre-login")

S.fire("ADDON_LOADED", "ForeverOptimizer")
S.fire("PLAYER_LOGIN")
noErrors("login")
check(FO.state.enabled, "enabled")
check(ForeverOptimizerDB and ForeverOptimizerDB.account.sessions, "SavedVariables initialised")
check(FO.Player.class == "HUNTER" and FO.Player.level == 23, "character profile read")
check(FO.Session:Live() ~= nil, "session started")
check(S.registered.COMBAT_LOG_EVENT_UNFILTERED == true, "combat log requested (optimistic path)")

-- Pricing: vendor scan + fake AH observation
S.fire("MERCHANT_SHOW") S.advance(1)
local PH = FO:GetModule("Economy.PriceHistory")
check(PH.db.vendor[117] and PH.db.vendor[117].price == 25, "vendor buy price captured")
PH:Observe(2589, "Linen Cloth", 150, 400, 12)
PH:Observe(3182, "Spider's Silk", 9000, 20, 4)
check(FO.Util.AHPrice(2589) == 150, "AH price readable through Util")
local v, src = FO.Util.ItemValue(3182)
check(src == "ah" and v == 8550, "item value prefers AH net of cut (" .. tostring(v) .. ")")
S.repairCost = 4000 RepairAllItems() P.money = P.money - 0 S.fire("PLAYER_MONEY")
S.fire("MERCHANT_CLOSED")
local st = FO.Session:Stats()
check(st.repairs == 4000, "repair attributed (" .. st.repairs .. ")")

-- Combat: target, fight, kill line, xp, loot
S.units = { target = { name = "Bloodscalp Warrior", guid = "Creature-0-1-2-3-595-0000ABCD", hostile = true, level = 24, ctype = "Humanoid", cls = "normal" } }
S.fire("PLAYER_TARGET_CHANGED")
S.inCombat = true S.fire("PLAYER_REGEN_DISABLED")
S.advance(12)
S.fire("CHAT_MSG_COMBAT_XP_GAIN", "Bloodscalp Warrior dies, you gain 180 experience.")
P.xp = P.xp + 180 S.fire("PLAYER_XP_UPDATE", "player")
S.hp = 650 S.inCombat = false S.fire("PLAYER_REGEN_ENABLED") S.hp = 1000
S.loot = { { name = "Linen Cloth", qty = 3, quality = 1, itemID = 2589, guid = "Creature-0-1-2-3-595-0000ABCD" },
           { name = "Spider's Silk", qty = 1, quality = 2, itemID = 3182, guid = "Creature-0-1-2-3-595-0000ABCD" },
           { name = "12 Silver, 5 Copper", qty = 1, quality = 1, guid = "Creature-0-1-2-3-595-0000ABCD" } }
S.fire("LOOT_OPENED")
S.fire("CHAT_MSG_MONEY", "You loot 12 Silver, 5 Copper")
P.money = P.money + 1205 S.fire("PLAYER_MONEY")
noErrors("combat/loot")
st = FO.Session:Stats()
check(st.kills == 1 and st.xp == 180, "kill + xp recorded")
check(st.lootGold == 1205, "loot coin parsed (" .. st.lootGold .. ")")
check(st.ahEst == 8976 and st.items == 2, "AH estimate from loot: 3x linen@142 + silk@8550 (" .. st.ahEst .. ")")
local MD = FO:GetModule("Grinding.MobDatabase")
local m = MD.db.mobs[595]
check(m and m.kills == 1 and m.xp == 180 and m.looted == 1 and m.drops[2589].count == 3, "mob database row")
check(m and m.killN == 1 and m.killTime >= 11 and m.killTime <= 13, "time-to-kill measured (" .. tostring(m and m.killTime) .. ")")
check(m and m.level == 24 and m.type == "Humanoid", "mob level/type noted")
check(#MD.db.encounters == 1 and MD.db.encounters[1].dur and MD.db.encounters[1].hpLoss == 0.35 and MD.db.encounters[1].plvl == 23, "encounter log row with post-fight hp loss")
check(m.hpN == 1 and math.abs(m.hpLoss - 0.35) < 0.001, "mob hp-loss aggregate")
local LT = FO:GetModule("Grinding.LootTracker")
check(#LT.db.log == 2 and LT.db.log[2].ah == 9000, "raw loot log")
check(st.activity == "grind", "activity = grind (" .. st.activity .. ")")

-- Several more kills for cadence
for i = 1, 6 do
    S.units.target.guid = "Creature-0-1-2-3-595-0000AB" .. i
    S.fire("PLAYER_TARGET_CHANGED") S.inCombat = true S.fire("PLAYER_REGEN_DISABLED") S.advance(10)
    S.fire("CHAT_MSG_COMBAT_XP_GAIN", "Bloodscalp Warrior dies, you gain 180 experience.")
    P.xp = P.xp + 180 S.fire("PLAYER_XP_UPDATE", "player") S.inCombat = false S.fire("PLAYER_REGEN_ENABLED") S.advance(8)
end
local XT = FO:GetModule("Grinding.XPTracker")
local gap, n = XT:InterKillGap()
check(gap and gap >= 17 and gap <= 19 and n >= 5, "inter-kill gap " .. tostring(gap) .. " over " .. n)
local E = FO.Analytics:Estimate()
check(E and E.killsPerHour and E.xpPerHour and math.abs(E.xpPerKill - 180) < 1, "unified estimate: " .. string.format("%.0f k/hr %.0f xp/hr", E.killsPerHour, E.xpPerHour))

-- Respawn: kill at a point, stay, nameplate appears -> confirmed
local FE = FO:GetModule("Grinding.FarmingEfficiency")
S.units.target.guid = "Creature-0-1-2-3-595-0000AC01"
S.fire("PLAYER_TARGET_CHANGED") S.inCombat = true S.fire("PLAYER_REGEN_DISABLED") S.advance(5)
S.fire("CHAT_MSG_COMBAT_XP_GAIN", "Bloodscalp Warrior dies, you gain 180 experience.") S.inCombat = false S.fire("PLAYER_REGEN_ENABLED")
S.advance(10)
S.units.target = { name = "Bloodscalp Warrior", guid = "Creature-0-1-2-3-595-0000AC09", hostile = true, level = 24 }
S.fire("PLAYER_TARGET_CHANGED")  -- a different mob nearby: must NOT count as a respawn
check(FE:RespawnEstimate(595) == nil, "targeting another mob nearby is not a respawn")
S.advance(290)
S.units.nameplate1 = { name = "Bloodscalp Warrior", guid = "Creature-0-1-2-3-595-0000AC02", hostile = true, level = 24 }
S.fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
local est, kind = FE:RespawnEstimate(595)
check(est and kind == "confirmed" and est >= 299 and est <= 301, "respawn confirmed at " .. tostring(est) .. "s (" .. tostring(kind) .. ")")

-- Quest objective tick + drop estimate (kill, then the objective ticks a few seconds later)
S.fire("QUEST_ACCEPTED", 103)
S.fire("CHAT_MSG_COMBAT_XP_GAIN", "Bloodscalp Warrior dies, you gain 180 experience.") S.advance(3)
S.quests[1].objectives[1].numFulfilled = 3
S.fire("UNIT_QUEST_LOG_CHANGED", "player") S.advance(1)
local QT = FO:GetModule("Quest.QuestTracker")
check(#QT.db.quests[101].objectives[1].points == 1, "objective point recorded")
local QE = FO:GetModule("Quest.QuestEfficiency")
local rows = QE:ActiveEstimates()
check(#rows >= 1 and rows[1].sources["Bloodscalp Warrior"], "drop source learned from last kill")
local lo, hi = QE.Wilson(6, 30)
check(lo > 0.09 and lo < 0.10 and hi > 0.37 and hi < 0.39, string.format("Wilson 6/30 -> [%.3f, %.3f]", lo, hi))
st = FO.Session:Stats()
check(st.activity == "quest", "activity flips to quest after tick (" .. st.activity .. ")")
S.fire("QUEST_TURNED_IN", 101, 1150, 2500) P.xp = P.xp + 1150 S.fire("PLAYER_XP_UPDATE", "player") P.money = P.money + 2500 S.fire("PLAYER_MONEY")
st = FO.Session:Stats()
check(st.questXP == 1150 and st.questGold == 2500 and st.questsDone == 1, "quest reward attributed + quests done")
S.fire("TAXIMAP_OPENED") P.money = P.money - 300 S.fire("PLAYER_MONEY") S.fire("TAXIMAP_CLOSED")
check(FO.Session:Stats().taxi == 300, "flight cost attributed")
check(QT.db.quests[101].turnin and QT.db.quests[101].timesDone == 1, "turn-in recorded")

-- Rep from a kill (well after the turn-in)
S.advance(30)
S.fire("CHAT_MSG_COMBAT_XP_GAIN", "Bloodscalp Warrior dies, you gain 180 experience.")
S.fire("CHAT_MSG_COMBAT_FACTION_CHANGE", "Reputation with Booty Bay increased by 5.")
local PP = FO:GetModule("Character.ProgressionPlanner")
check(PP.db.rep["Booty Bay"] and PP.db.rep["Booty Bay"].mobs["Bloodscalp Warrior"].total == 5, "rep attributed to mob")

-- Gathering node
S.fire("UNIT_SPELLCAST_SENT", "player", "Copper Vein", "cast-1", 2575)
S.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-1", 2575)
check(FE.db.nodes["Copper Vein"] and #FE.db.nodes["Copper Vein"].points == 1, "mining node recorded")

-- Death and corpse run
S.fire("PLAYER_DEAD") P.dead = true S.advance(90) P.dead = false S.fire("PLAYER_UNGHOST")
st = FO.Session:Stats()
check(st.deaths == 1 and st.deathTime >= 89, "death + corpse run time (" .. st.deathTime .. ")")
check(m.deaths == 1, "death attributed to last hostile")

-- Rest / travel detection
S.eating = true S.advance(20) st = FO.Session:Stats() check(st.by.rest.t >= 15, "rest detected while eating") S.eating = false
P.speed = 7 S.advance(40) st = FO.Session:Stats() check(st.by.travel.t >= 20, "travel detected while moving (" .. st.by.travel.t .. ")") P.speed = 0

-- Dungeon enter/leave
P.inInstance = true S.fire("ZONE_CHANGED_NEW_AREA") S.advance(130)
S.fire("CHAT_MSG_COMBAT_XP_GAIN", "Defias Pillager dies, you gain 300 experience.") P.xp = P.xp + 300 S.fire("PLAYER_XP_UPDATE", "player")
check(FO.Session:Live().dungeon and FO.Session:Live().dungeon.xp == 300, "dungeon run live")
P.inInstance = false S.fire("ZONE_CHANGED_NEW_AREA")
check(#FO.Session.db.dungeons == 1 and FO.Session.db.dungeons[1].kills == 1, "dungeon run archived")

-- Trainer, bags, bank, consumables
S.fire("TRAINER_SHOW") S.advance(1)
local TP = FO:GetModule("Character.TrainingPlanner")
check(FO.Util.Count(TP.cdb.skills) == 3 and TP.cdb.skills["Aspect of the Hawk|Rank 1"].learned, "trainer services captured")
S.fire("TRAINER_CLOSED")
local IO = FO:GetModule("Economy.InventoryOptimizer")
table.insert(S.bags, { itemID = 3300, count = 1, quality = 0 }) -- another gray drop since the last vendor visit
S.sold = nil
local cats = IO:Scan()
check(cats.trash and #cats.trash == 1 and cats.auction and #cats.auction == 1, "bag classification (trash + auction)")
S.fire("MERCHANT_SHOW") S.advance(1)
check(S.sold == 1, "auto-sold trash at vendor")
S.fire("MERCHANT_CLOSED")
S.fire("BANKFRAME_OPENED") S.advance(1) S.fire("BANKFRAME_CLOSED")
check(IO.cdb.bankAt > 0, "bank snapshot taken")
table.remove(S.bags, 2) -- eat jerky stack (index shifted after sale)
S.fire("BAG_UPDATE_DELAYED") S.advance(2)
st = FO.Session:Stats()
check(st.consumables > 0, "consumable use costed (" .. st.consumables .. ")")

-- Gear
S.equipped = { [16] = "|cffffffff|Hitem:2092::::::::23:::::|h[Worn Dagger]|h|r" }
local GE = FO:GetModule("Character.GearEvaluator")
local c = GE:Compare("|cffffffff|Hitem:1515::::::::23:::::|h[Rough Boomstick]|h|r")
check(c and c.delta > 0, "gear compare finds upgrade")
noErrors("features")

-- Every slash command, with and without args
local cmds = {}
for _, sub in ipairs(FO.commandOrder) do cmds[#cmds + 1] = sub end
for _, sub in ipairs(cmds) do
    SlashCmdList.FOREVEROPTIMIZER(sub)
    if sub ~= "wipe" then SlashCmdList.FOREVEROPTIMIZER(sub .. " 595") SlashCmdList.FOREVEROPTIMIZER(sub .. " report") end
end
SlashCmdList.FOREVEROPTIMIZER("mob Bloodscalp Warrior")
SlashCmdList.FOREVEROPTIMIZER("price Linen")
SlashCmdList.FOREVEROPTIMIZER("watch Linen 1g")
SlashCmdList.FOREVEROPTIMIZER("goal add test 50g 30")
SlashCmdList.FOREVEROPTIMIZER("gear |cffffffff|Hitem:1515::::::::23:::::|h[Rough Boomstick]|h|r")
SlashCmdList.FOREVEROPTIMIZER("tab Economy")
SlashCmdList.FOREVEROPTIMIZER("bags trash")
SlashCmdList.FOREVEROPTIMIZER("find Linen")
SlashCmdList.FOREVEROPTIMIZER("route ore") check(outHas("Route on") and outHas("Copper Vein"), "/fo route ore reaches the gathering router")
SlashCmdList.FOREVEROPTIMIZER("respawn 595")
SlashCmdList.FOREVEROPTIMIZER("objective gold") SlashCmdList.FOREVEROPTIMIZER("zones") SlashCmdList.FOREVEROPTIMIZER("objective custom 1 2 3") SlashCmdList.FOREVEROPTIMIZER("objective balanced")
SlashCmdList.FOREVEROPTIMIZER("module off Classes.Priest") SlashCmdList.FOREVEROPTIMIZER("module on priest") SlashCmdList.FOREVEROPTIMIZER("module off Core.Verify")
SlashCmdList.FOREVEROPTIMIZER("bags worst 3") SlashCmdList.FOREVEROPTIMIZER("craft sellthrough 0.8") SlashCmdList.FOREVEROPTIMIZER("history 5") SlashCmdList.FOREVEROPTIMIZER("flips")
SlashCmdList.FOREVEROPTIMIZER("verify")
local VM = FO:GetModule("Core.Verify")
check(VM.db.last and #VM.db.last.checks > 20 and VM.db.last.toc == "16001", "verify ran and saved " .. tostring(VM.db.last and #VM.db.last.checks) .. " checks")
check(outHas("TOC interface matches"), "verify printed interface check")
check(FO.root.account.modules.disabled["Classes.Priest"] == nil and FO.root.account.modules.disabled["Core.Verify"] == nil, "module toggles respect core protection and re-enable")
check(FO.root.version == 3 and type(FO.root.account.errors.log) == "table", "db migrated to v3 (errors namespace)")

-- Error capture: a throwing command is printed, deduped, and persisted with a stack
FO:RegisterCommand("boom", function() error("kaboom test") end, "test only")
for _ = 1, 5 do SlashCmdList.FOREVEROPTIMIZER("boom") end
local elog = FO.root.account.errors.log
check(#FO.errors >= 1 and FO.errorIndex["/fo boom|" .. FO.errors[#FO.errors].msg].count == 5, "error deduped to one entry with count 5")
check(#elog >= 1 and elog[#elog].count == 5 and elog[#elog].where == "/fo boom" and elog[#elog].stack ~= "" and elog[#elog].char == FO.charKey, "error persisted to account.errors.log with stack")
check(outHas("further repeats of this error are silent"), "error printing capped")
SlashCmdList.FOREVEROPTIMIZER("errors") check(outHas("distinct errors saved"), "/fo errors lists")
SlashCmdList.FOREVEROPTIMIZER("errors 1") check(outHas("kaboom test"), "/fo errors <n> shows detail")
local badHandler = function() error("handler boom") end
FO:On("FO_TEST_MSG", badHandler) FO:Fire("FO_TEST_MSG")
check(FO.errorIndex["FO_TEST_MSG handler|" .. FO.errors[#FO.errors].msg] ~= nil, "message handler error captured")
S.errors = {} -- the errors above were intentional

-- Client item seed: unknown-to-client items resolve by name/price/class, live data wins
check(FO.Seed.itemCount > 19000 and FO.Seed.build:match("^1%.60%."), "item seed loaded (" .. FO.Seed.itemCount .. " items, build " .. FO.Seed.build .. ")")
check(FO.Util.ItemName(4306) == "Silk Cloth" and FO.Util.VendorSell(4306) == 150, "seed supplies name and sell price for an uncached item")
check(select(1, FO.Util.ItemInstant(4306)) == 7 and FO.Util.VendorBuy(929) == 300, "seed supplies class and vendor buy price")
check(FO.Util.VendorSell(2770) == 15, "client item cache overrides seed sell price")
SlashCmdList.FOREVEROPTIMIZER("seed Silk Cloth") check(outHas("4306 Silk Cloth"), "/fo seed name lookup")
SlashCmdList.FOREVEROPTIMIZER("seed 6948") check(outHas("Hearthstone"), "/fo seed id lookup")

-- World map overlay: pins for recorded nodes on the displayed map, coordinates text
local MapM, FEm = FO:GetModule("Dashboard.Map"), FO:GetModule("Grinding.FarmingEfficiency")
check(MapM.available == true and MapM.provider ~= nil, "map data provider registered")
local nodeMap
for _, node in pairs(FEm.db.nodes) do for _, pt in ipairs(node.points) do nodeMap = nodeMap or pt[1] end end
check(nodeMap ~= nil, "harness recorded gathering nodes to pin")
S.worldMap.mapID = nodeMap
WorldMapFrame:Show()
local firstNodePin for _, p in ipairs(WorldMapFrame.pins) do if p.template == "FOMapPinTemplate" then firstNodePin = p break end end
check(firstNodePin and firstNodePin.x, "node pins placed on map open (" .. #WorldMapFrame.pins .. ")")
local orePin for _, p in ipairs(WorldMapFrame.pins) do if p.data and p.data.kind == "ore" then orePin = p break end end
check(orePin and orePin.data.icon == "icon" and MapM:NodeIcon("Copper Vein", "ore") == "icon", "ore node pin carries Copper Ore's item icon")
check(MapM:NodeIcon("Unknown Flower", "herb") == "Interface\\Icons\\Trade_Herbalism", "unknown herb falls back to the generic herb icon")
firstNodePin:OnMouseEnter() firstNodePin:OnMouseLeave()
S.mapUpdate()
check(MapM.coordText and MapM.coordText:IsShown(), "coordinate text shown while map open")
SlashCmdList.FOREVEROPTIMIZER("map") check(outHas("world map overlay: pins") and outHas("this map"), "/fo map status")
SlashCmdList.FOREVEROPTIMIZER("map nodes off") SlashCmdList.FOREVEROPTIMIZER("map refresh")
local nodePins = 0 for _, p in ipairs(WorldMapFrame.pins) do if p.data and (p.data.kind == "herb" or p.data.kind == "ore") then nodePins = nodePins + 1 end end
check(nodePins == 0, "nodes layer off removes node pins")
SlashCmdList.FOREVEROPTIMIZER("map nodes on") SlashCmdList.FOREVEROPTIMIZER("map spawns on") SlashCmdList.FOREVEROPTIMIZER("map refresh")
check(#WorldMapFrame.pins > 0, "layers back on restores pins")
WorldMapFrame:Hide()

-- Unexplored map art: every overlay of the seed that the client has not revealed is drawn, tiled 256x256
local MAPM = FO:GetModule("Dashboard.Map")
local durotar = FO.Seed.mapOverlays[1411]
local durotarTiles = 0 for _, o in ipairs(durotar) do durotarTiles = durotarTiles + #o[5] end
check(durotarTiles > 10 and FO.Seed.mapOverlayBuild == FO.Seed.spellBuild, "map overlay seed loaded for the same client build (" .. durotarTiles .. " Durotar tiles)")
S.worldMap.mapID = 1411
S.explored = { { textureWidth = durotar[1][1], textureHeight = durotar[1][2], offsetX = durotar[1][3], offsetY = durotar[1][4] } }
WorldMapFrame:Show()
check(MAPM.revealProvider and MAPM.revealProvider.pin and MAPM.revealProvider.pin.template == "FOMapRevealPinTemplate", "reveal pin acquired on the map")
check(MAPM.revealCount == durotarTiles - #durotar[1][5], "unexplored pieces drawn = seed tiles minus the explored overlay (" .. tostring(MAPM.revealCount) .. ")")
local revealPin = MAPM.revealProvider.pin
check(revealPin.used == MAPM.revealCount and #revealPin.textures >= revealPin.used, "one pooled texture per piece")
local texAfterFirst = S.textures or 0
S.explored = {}
MAPM.revealProvider:OnEvent("MAP_EXPLORATION_UPDATED")
check(MAPM.revealCount == durotarTiles and revealPin.used == durotarTiles and (S.textures or 0) == texAfterFirst + math.max(0, durotarTiles - #revealPin.textures),
      "exploration update redraws from the pool, creating textures only past the pool size")
SlashCmdList.FOREVEROPTIMIZER("map reveal off")
check(MAPM.db.settings.reveal == false and MAPM.revealCount == 0 and revealPin.used == 0, "/fo map reveal off clears the art")
check(MAPM.revealButton and MAPM.revealButton:GetText() == "Full map", "map button offers the full map when hidden")
ForeverOptimizer_ToggleReveal()
check(MAPM.db.settings.reveal == true and MAPM.revealCount == durotarTiles and MAPM.revealButton:GetText() == "Explored only", "binding toggles it back on and the button flips")
SlashCmdList.FOREVEROPTIMIZER("map tint off") SlashCmdList.FOREVEROPTIMIZER("map tint on")
check(outHas("unexplored tint") and MAPM.db.settings.revealTint == true, "/fo map tint toggles")
S.worldMap.mapID = 9999
MAPM.revealProvider:OnMapChanged()
check(MAPM.revealCount == 0, "maps without overlay data draw nothing")
SlashCmdList.FOREVEROPTIMIZER("map") check(outHas("unexplored art"), "/fo map reports the reveal state")
WorldMapFrame:Hide()
S.worldMap.mapID = nil
check(not MapM.coordText:IsShown(), "coordinate text hidden with map")
SlashCmdList.FOREVEROPTIMIZER("coords") check(outHas("(map "), "/fo coords prints position")
noErrors("map overlay")

-- Combat log (optimistic path): damage split, auto-shot clipping, DoT efficiency, heals, fight timing
local CLm, CSm = FO.CombatLog, FO.CombatStats
check(CLm.registered and CLm.available, "combat log registered on this client")
S.units.pet = { name = "Wolf", guid = "Pet-0-1-2-3-4-0000PET1" }
S.fire("UNIT_PET", "player")
local me  = { guid = "Player-1-ABC", name = "Mikeo", flags = 0x511 }
local pet = { guid = "Pet-0-1-2-3-4-0000PET1", name = "Wolf", flags = 0x1111 }
local mob = { guid = "Creature-0-1-2-3-595-0000CL01", name = "Bloodscalp Warrior", flags = 0xA48 }
local mob2 = { guid = "Creature-0-1-2-3-595-0000CL02", name = "Bloodscalp Warrior", flags = 0xA48 }
S.spellCost[2060], S.spellCost[1978] = 100, 30
CSm:Reset()
S.inCombat = true S.fire("PLAYER_REGEN_DISABLED")
local function shot(crit) S.cl("SPELL_CAST_SUCCESS", me, mob, 75, "Auto Shot", 1) S.cl("RANGE_DAMAGE", me, mob, 75, "Auto Shot", 1, crit and 120 or 100, 0, 1, 0, 0, 0, crit or false) end
shot() S.advance(2) shot(true) S.advance(2) shot() S.advance(3) shot()          -- gaps 2, 2, 3 at speed 2.0 -> 1.0s clipped
S.cl("SWING_DAMAGE", pet, mob, 60, 0, 1, 0, 0, 0, false) S.cl("SWING_DAMAGE", pet, mob, 60, 0, 1, 0, 0, 0, false)
S.cl("SWING_DAMAGE", mob, me, 40, 0, 1, 0, 0, 0, false)
S.cl("SPELL_CAST_SUCCESS", me, mob, 1978, "Serpent Sting", 8) S.cl("SPELL_AURA_APPLIED", me, mob, 1978, "Serpent Sting", 8, "DEBUFF")
for _ = 1, 3 do S.advance(3) S.cl("SPELL_PERIODIC_DAMAGE", me, mob, 1978, "Serpent Sting", 8, 20, 0, 8, 0, 0, 0, false) end
S.cl("SPELL_AURA_REMOVED", me, mob, 1978, "Serpent Sting", 8, "DEBUFF")
S.cl("SPELL_CAST_SUCCESS", me, me, 2060, "Lesser Heal", 2) S.cl("SPELL_HEAL", me, me, 2060, "Lesser Heal", 2, 150, 50, 0, false)
S.cl("UNIT_DIED", { guid = "", flags = 0 }, mob)
-- second target: DoT applied, one tick, target dies -> 2 ticks lost
S.cl("SPELL_CAST_SUCCESS", me, mob2, 1978, "Serpent Sting", 8) S.cl("SPELL_AURA_APPLIED", me, mob2, 1978, "Serpent Sting", 8, "DEBUFF")
S.advance(3) S.cl("SPELL_PERIODIC_DAMAGE", me, mob2, 1978, "Serpent Sting", 8, 20, 0, 8, 0, 0, 0, false)
S.cl("SWING_DAMAGE", me, mob2, 30, 0, 1, 0, 0, 0, false) S.advance(1)
S.cl("UNIT_DIED", { guid = "", flags = 0 }, mob2)
S.inCombat = false S.fire("PLAYER_REGEN_ENABLED")
local c = CSm:Stats()
check(c.dmgPlayer == 420 + 60 + 20 + 30 and c.dmgPet == 120, "damage split player/pet (" .. c.dmgPlayer .. "/" .. c.dmgPet .. ")")
check(c.petShare and math.abs(c.petShare - 120 / 650) < 0.001, "pet damage share")
local a = c.autos["Auto Shot"]
check(a and a.shots == 4 and math.abs(a.clipped - 1.0) < 0.01 and a.speed == 2.0, "auto shot clipping 1.0s over 4 shots")
local d = c.dots[1]
check(d and d.name == "Serpent Sting" and d.applied == 2 and d.ticks == 4 and d.maxTicks == 3 and d.truncated == 1 and d.wasted == 2 and math.abs(d.efficiency - 4 / 6) < 0.01, "DoT efficiency 4 of 6 ticks")
check(d.perMana and math.abs(d.perMana - 80 / 60) < 0.01, "DoT damage per mana from cast cost")
local h = c.heals[1]
check(h and h.total == 150 and h.over == 50 and math.abs(h.overPct - 0.25) < 0.01 and h.perMana == 1.5, "heal with overheal and heal per mana")
check(c.fights == 2 and c.taken == 40, "two fights closed by UNIT_DIED, damage taken counted")
local mobRec = FO:GetModule("Grinding.MobDatabase").db.mobs[595]
check(mobRec and mobRec.clN == 2 and mobRec.takenN == 1 and mobRec.taken == 40 and mobRec.clTime > 16, "MobDatabase received FO_FIGHT timing and damage taken (" .. tostring(mobRec and mobRec.clN) .. "/" .. tostring(mobRec and mobRec.takenN) .. "/" .. tostring(mobRec and mobRec.taken) .. "/" .. tostring(mobRec and mobRec.clTime) .. ")")
local hl = table.concat(FO.Classes.HUNTER:Lines(), "\n")
check(hl:find("Pet damage 18%%") and hl:find("Auto Shot 4"), "hunter HUD lines show pet share and clipping")

-- Auto Shot timer bar: shots, aim window, secret ids via cast guid, casts pausing and restarting the cycle
local ASm = FO.AutoShot
check(ASm.ready and ASm.speed == 2.0, "auto shot bar built for a hunter with the weapon speed (" .. tostring(ASm.speed) .. ")")
local shots0 = ASm.shots
S.fire("START_AUTOREPEAT_SPELL")
check(ASm.active, "auto-repeat on activates the bar")
S.advance(1)
S.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-3-4379-0-13-75-000152C1B2", 75)
check(ASm.shots == shots0 + 1 and ASm.lastShot == S.clock, "a shot restarts the timer")
S.advance(1)
check(ASm:Remaining() and math.abs(ASm:Remaining() - 1.0) < 0.01 and not ASm:InAimWindow(), "one second in: one second left, not yet aiming")
S.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-3-4379-0-13-75-000152C1B3", "SECRET")
check(ASm.shots == shots0 + 2 and ASm.secret == 0, "secret spell id read from the cast guid")
S.advance(2) P.speed = 7 S.mapUpdate()
check(ASm:Remaining() == 0 and hl ~= nil, "cycle elapsed: ready")
S.fire("UNIT_SPELLCAST_START", "player", "Cast-3-4379-0-13-19434-000152C1B4", 19434)
check(ASm.casting and ASm.casting.id == 19434, "a cast pauses the cycle")
S.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-3-4379-0-13-19434-000152C1B4", 19434)
S.fire("UNIT_SPELLCAST_STOP", "player", "Cast-3-4379-0-13-19434-000152C1B4")
check(not ASm.casting and ASm.lastShot == S.clock and ASm.resets == 1, "a landed cast restarts the cycle")
S.fire("UNIT_SPELLCAST_START", "player", "Cast-3-4379-0-13-19434-000152C1B5", 19434)
S.fire("UNIT_SPELLCAST_INTERRUPTED", "player", "Cast-3-4379-0-13-19434-000152C1B5")
check(not ASm.casting and ASm.resets == 1, "an interrupted cast leaves the cycle alone")
S.fire("STOP_AUTOREPEAT_SPELL")
check(not ASm.active, "auto-repeat off")
SlashCmdList.FOREVEROPTIMIZER("shotbar") check(outHas("speed 2.00 s") and outHas("2 shots"), "/fo shotbar status")
SlashCmdList.FOREVEROPTIMIZER("shotbar test") check(outHas("showing the bar"), "/fo shotbar test")
P.speed = 0
noErrors("auto shot bar")
for _, cmd in ipairs({ "combat", "dots", "heals", "autoshot", "combatlog" }) do SlashCmdList.FOREVEROPTIMIZER(cmd) end
check(outHas("Serpent Sting") and outHas("Lesser Heal") and outHas("clipped") and outHas("combat log: live"), "combat commands print")
SlashCmdList.FOREVEROPTIMIZER("mob 595") check(outHas("combat log:"), "/fo mob shows combat-log timing")

-- Group meter: party member and party pet credited to the owner, self-damage excluded, fight vs session
local MT = FO.Meter
MT:Reset()
S.units.party1 = { name = "Grok", guid = "Player-1-DEF" }
S.units.party1pet = { name = "Voidwalker", guid = "Pet-0-1-2-3-4-0000VW01" }
S.fire("GROUP_ROSTER_UPDATE")
local ally = { guid = "Player-1-DEF", name = "Grok", flags = 0x512 }
local vw = { guid = "Pet-0-1-2-3-4-0000VW01", name = "Voidwalker", flags = 0x1112 }
local mob3 = { guid = "Creature-0-1-2-3-595-0000CL03", name = "Bloodscalp Warrior", flags = 0xA48 }
S.cl("SPELL_DAMAGE", me, mob3, 3044, "Arcane Shot", 64, 100, 0, 64, 0, 0, 0, false)
S.cl("SWING_DAMAGE", pet, mob3, 50, 0, 1, 0, 0, 0, false)
S.cl("SPELL_DAMAGE", ally, mob3, 686, "Shadow Bolt", 32, 200, 0, 32, 0, 0, 0, false)
S.cl("SWING_DAMAGE", vw, mob3, 40, 0, 1, 0, 0, 0, false)
S.cl("SPELL_DAMAGE", ally, ally, 1454, "Life Tap", 32, 60, 0, 32, 0, 0, 0, false)
S.cl("SPELL_HEAL", ally, me, 755, "Health Funnel", 32, 80, 30, 0, false)
S.advance(4)
S.cl("SWING_DAMAGE", me, mob3, 50, 0, 1, 0, 0, 0, false)
local mrows = MT:Table(MT.cur, "dmg")
check(#mrows == 2 and mrows[1].name == "Grok" and mrows[1].value == 240 and mrows[1].pet == 40 and mrows[2].value == 200 and mrows[2].pet == 50, "meter credits the party pet to its owner and ignores Life Tap (" .. tostring(mrows[1] and mrows[1].value) .. "/" .. tostring(mrows[2] and mrows[2].value) .. ")")
local hrows = MT:Table(MT.cur, "heal")
check(#hrows == 1 and hrows[1].value == 50 and hrows[1].over == 30, "meter counts effective healing and overheal")
S.advance(10) MT:OnTick(GetTime())
check(MT.last and MT.last.dmg == 440 and MT.cur.start == nil and MT.fights == 1, "fight segment closes after the gap")
local ml = table.concat(MT:Lines(), "\n")
check(ml:find("DPS") and ml:find("last fight") and ml:find("Grok") and ml:find("pet"), "meter HUD lines show the last fight with pet share while idle")
S.cl("SWING_DAMAGE", me, mob3, 50, 0, 1, 0, 0, 0, false)
check(MT.cur.dmg == 50 and MT.total.dmg == 490, "new fight starts; session total keeps accumulating")
for _, cmd in ipairs({ "dps", "hps last", "dps session", "meter" }) do SlashCmdList.FOREVEROPTIMIZER(cmd) end
check(outHas("Grok") and outHas("meter: combat log live"), "/fo dps, hps and meter print")
S.units.party1, S.units.party1pet = nil, nil

-- HUD buttons: per-tab control rows that drive the same code as the commands
local DB = FO.Dashboard
DB:SelectTab("Meter")
local labels = {}
for _, c in ipairs(DB:Controls()) do labels[#labels + 1] = c.label end
check(table.concat(labels, ",") == "Fight,Last,Session,DPS,HPS,Mine", "Meter tab has scope, mode and Mine buttons (" .. table.concat(labels, ",") .. ")")
DB:ClickControl("Session") DB:ClickControl("HPS")
check(FO.Meter.view.scope == "session" and FO.Meter.db.mode == "hps" and table.concat(FO.Meter:Lines(), "\n"):find("HPS|r session"), "meter buttons switch scope and mode")
DB:ClickControl("DPS") DB:ClickControl("Mine")
check(FO.Meter.view.mine and table.concat(FO.Meter:Lines(), "\n"):find("Arcane Shot"), "Mine button shows my spell breakdown")
DB:ClickControl("Mine") DB:ClickControl("Fight")
DB:SelectTab("Leveling") DB:ClickControl("Gold")
check(FO.Analytics.db.objective == "gold", "Leveling Gold button sets the objective") DB:ClickControl("Balanced")
DB:SelectTab("Overview") DB:ClickControl("Pause")
check(FO.Session:Stats().paused, "Overview Pause button pauses the session")
DB:ClickControl("Resume") check(not FO.Session:Stats().paused, "Resume button resumes")
DB:ClickControl("Flash") check(FO.Alerts.db.settings.flash == false, "Flash button toggles the alert flash") DB:ClickControl("Flash")
check(DB:ClickControl("Nope") == false, "unknown button is refused")
DB:SelectTab("Character") check(#DB:Controls() == 2 and DB:Controls()[1].label == "Beast", "Character tab lists the builds as buttons")
DB:ClickControl("Marksmanship") check(FO.Rotation.db.build.HUNTER == 2, "build button activates a build") DB:ClickControl("Beast")
SlashCmdList.FOREVEROPTIMIZER("hud list") check(outHas("Character tab buttons"), "/fo hud list prints the buttons")
SlashCmdList.FOREVEROPTIMIZER("hud click beast") check(outHas("active build set to 1"), "/fo hud click presses a button by name")
noErrors("HUD controls")

-- Help tab and manual window
DB:SelectTab("Help")
labels = {}
for _, c in ipairs(DB:Controls()) do labels[#labels + 1] = c.label end
check(table.concat(labels, ",") == "Core,HUD,Grind,Quest,Econ,Char,Class,<,>,Window", "Help tab buttons (" .. table.concat(labels, ",") .. ")")
local help = table.concat(FO.Help:Lines(), "\n")
check(help:find("Setup and session") and help:find("errors") and help:find("/fo <cmd>", 1, true), "Help tab lists Core commands with syntax")
DB:ClickControl("Grind") help = table.concat(FO.Help:Lines(), "\n")
check(help:find("Grinding and combat") and (help:find("dps") or help:find("mobs")), "Help Grind area lists grinding commands")
DB:ClickControl(">") check(FO.Help.page == 2 and table.concat(FO.Help:Lines(), "\n"):find("page 2/"), "Help pages forward")
DB:ClickControl("<") check(FO.Help.page == 1, "Help pages back")
if FO.Help:IsOpen() then FO.Help:Toggle() end   -- the command smoke test above already opened it once
DB:ClickControl("Window") check(FO.Help:IsOpen(), "Window button opens the manual")
local text = FO.Help:Text()
check(text:find("/fo dps", 1, true) and text:find("Meter|r  buttons: Fight, Last, Session, DPS, HPS, Mine", 1, true) and text:find("Help|r  buttons:", 1, true), "manual text carries every command and each tab's buttons")
SlashCmdList.FOREVEROPTIMIZER("manual") check(not FO.Help:IsOpen(), "/fo manual toggles the window closed")
DB:SelectTab("Overview")
noErrors("help")

-- Rune discovery: a new Engrave spell in the book is announced, noted and saved with position
local RU = FO.Runes
check(RU and RU.cdb and next(RU.cdb.learned) == nil, "no runes known at login")
S.knownSpells[410110] = true
S.fire("SPELLS_CHANGED")
local rec = RU.cdb.learned[410110]
check(rec and rec.name == "Engrave Chest - Beast Mastery" and rec.level == 23 and rec.x and outHas("rune learned:"), "new engraving announced and recorded with position")
local lastNote = FO.Session:Live() and FO.Session:Live().notes[#FO.Session:Live().notes]
check(lastNote and lastNote.text == "rune: Engrave Chest - Beast Mastery", "rune stamped into the session notes")
S.fire("SPELLS_CHANGED") check(RU:Scan(true) == 0, "known rune is not announced twice")
SlashCmdList.FOREVEROPTIMIZER("runes") check(outHas("1 learned") and outHas("not yet"), "/fo runes lists learned and missing engravings")
S.knownSpells[410110] = nil
noErrors("runes")
noErrors("combat log")

-- Rotation optimizer: hand-authored data validates against the client seed, priorities render, builds check
local RM = FO.Rotation
local report = RM:ValidateAll()
local errs, warns = {}, 0
for _, r in ipairs(report) do if r.warning then warns = warns + 1 else errs[#errs + 1] = r.class .. ": " .. r.line end end
check(#errs == 0, "rotation/build names all exist in the seed (" .. warns .. " optional rune abilities absent)")
for _, e in ipairs(errs) do print("   " .. e) end
check(FO.Seed.spellCount > 2000 and #FO.Seed.talents > 400, "spell and talent seeds loaded (" .. FO.Seed.spellCount .. " spells, " .. #FO.Seed.talents .. " talents)")
local known = RM:Known("HUNTER", "Serpent Sting")
check(known and known.id == 1978, "known rank resolved from spellbook")
check(RM:Trainable("HUNTER", "Serpent Sting", 23) ~= nil, "higher Serpent Sting rank flagged trainable at 23")
local est = RM:Estimate(FO.Seed.spells[1978])
check(est.ticks == 5 and est.cost == 15 and est.dpm and est.dpm > 0, "estimate derives ticks from duration/period and dmg per mana")
local m = RM:Measured("Auto Shot")
check(m == nil or m.dmgPerCast, "measured lookup tolerates few casts")
SlashCmdList.FOREVEROPTIMIZER("rotation")
check(outHas("Serpent Sting r1") and outHas("Auto Shot") and outHas("upgrades at the trainer"), "/fo rotation prints priorities and trainer upgrades")
SlashCmdList.FOREVEROPTIMIZER("rotation check") check(outHas("optional runes absent") or outHas("all spells and talents found"), "/fo rotation check reports")
SlashCmdList.FOREVEROPTIMIZER("build") check(outHas("Beast Mastery leveling") and outHas("next points"), "/fo build shows plan vs live talents")
SlashCmdList.FOREVEROPTIMIZER("build list") SlashCmdList.FOREVEROPTIMIZER("build use 2") SlashCmdList.FOREVEROPTIMIZER("build")
check(outHas("Marksmanship leveling"), "/fo build use switches builds")
SlashCmdList.FOREVEROPTIMIZER("rotation WARLOCK") check(outHas("WARLOCK rotation"), "/fo rotation <class> works for other classes")
SlashCmdList.FOREVEROPTIMIZER("spell Serpent Sting") check(outHas("known"), "/fo spell lists ranks with known flag")
local bad = RM:ValidateBuild("HUNTER", { name = "bad", talents = { { "Intimidation", 1 }, { "Nope", 1 }, { "Endurance Training", 9 } } })
check(#bad == 3, "build validation catches tier gate, unknown talent, over-max rank (" .. #bad .. ")")
noErrors("rotation optimizer")

-- Quest database (QuestieDB adapter): availability rules, nearest givers, objective targets, map pins, route fallback
local QDBm = FO.QuestDB
check(QDBm.available == true, "QuestieDB adapter connected (" .. tostring(QDBm.reason) .. ")")
local avail = QDBm:AvailableOnMap(S.pos.map, S.pos.x, S.pos.y)
local names = {} for _, r in ipairs(avail) do names[#names + 1] = r.name end
check(#avail == 1 and avail[1].id == 201 and avail[1].giver == "Nimboya", "only the truly available quest is offered (" .. table.concat(names, ", ") .. ")")
check(select(2, QDBm:Available(QDBm:Quest(203))) == "prerequisite" and select(2, QDBm:Available(QDBm:Quest(204))) == "completed" and select(2, QDBm:Available(QDBm:Quest(202))) == "level" and select(2, QDBm:Available(QDBm:Quest(205))) == "race", "availability reasons: prerequisite, completed, level, race")
local targets = QDBm:ObjectiveTargets(101, S.pos.map)
check(#targets == 4 and targets[1].kind == "creature" and targets[3].kind == "item", "objective targets from creature spawns and item drop sources (" .. #targets .. ")")
local RPm = FO:GetModule("Quest.QuestRoutePlanner")
local wm, wx, wy, wsrc = RPm:NextWaypoint(102)
check(wm == S.pos.map and wx and math.abs(wx - 0.30) < 0.001 and wsrc and wsrc:find("database"), "route planner falls back to database objective (" .. tostring(wsrc) .. ")")
S.completeInLog = { [102] = true }
local fm, fx, fy, fsrc = RPm:NextWaypoint(102)
check(fm == S.pos.map and math.abs(fx - 0.40) < 0.001 and fsrc == "turn-in (database)", "complete quest routes to database finisher (" .. tostring(fsrc) .. ")")
local rm, rx, ry, rsrc = RPm:NextWaypoint(101)
check(rsrc == "recorded" or rsrc == "turn-in", "your own recorded quest positions still win over the database (" .. tostring(rsrc) .. ")")
S.completeInLog = nil
SlashCmdList.FOREVEROPTIMIZER("nearby") check(outHas("Welcome to the Jungle"), "/fo nearby lists pickups")
SlashCmdList.FOREVEROPTIMIZER("questinfo 101") check(outHas("Bloodscalp Ears (101)") and outHas("starts: Nimboya"), "/fo questinfo prints quest facts")
SlashCmdList.FOREVEROPTIMIZER("questinfo Chained") check(outHas("not available: prerequisite"), "/fo questinfo by name with availability reason")
SlashCmdList.FOREVEROPTIMIZER("qdb") check(outHas("quest database: QuestieDB"), "/fo qdb status")
S.worldMap.mapID = S.pos.map
WorldMapFrame:Show()
local kinds = {} for _, p in ipairs(WorldMapFrame.pins) do if p.data then kinds[p.data.kind] = (kinds[p.data.kind] or 0) + 1 end end
check((kinds.quest or 0) == 1 and (kinds.objective or 0) >= 4, "map shows quest giver and objective pins (quest " .. tostring(kinds.quest) .. ", objective " .. tostring(kinds.objective) .. ")")
WorldMapFrame:Hide()
SlashCmdList.FOREVEROPTIMIZER("route all") check(outHas("Welcome to the Jungle from Nimboya"), "/fo route all includes pickups")
noErrors("quest database")

-- Quest router: objective patches, precedence, 2-opt, follow mode, map pins
local RT = FO.Router
local plan, perr = RT:Plan()
check(plan ~= nil, "router plans a loop (" .. tostring(perr) .. ")")
local function idx(kind, qid) for i, st in ipairs(plan.stops) do if st.kind == kind and (not qid or st.quests[qid]) then return i end end end
check(#plan.stops == 4 and idx("objective", 101) and idx("objective", 102) and idx("turnin", 101) and idx("turnin", 102),
      "two objective patches and two turn-ins (" .. #plan.stops .. " stops)")
check(idx("turnin", 101) > idx("objective", 101) and idx("turnin", 102) > idx("objective", 102), "turn-ins come after their objective patches")
local ears = plan.stops[idx("objective", 101)]
check(ears.recorded == 1 and ears.label:find("x9", 1, true), "patch where the objective ticked for you wins and shows kills left (" .. ears.label .. ")")
check(plan.stops[1].leg == 0 and plan.total > 1500 and plan.total < 1900, string.format("nearest-first order with legs (%.0f yd)", plan.total))
check(plan.stops[idx("objective", 102)].label:find("Crystal", 1, true) ~= nil, "object objective matched to its spawn (" .. plan.stops[idx("objective", 102)].label .. ")")
S.worldMap.mapID = S.pos.map WorldMapFrame:Show()
local routePins = 0 for _, p in ipairs(WorldMapFrame.pins) do if p.data and p.data.kind == "route" then routePins = routePins + 1 end end
check(routePins == 4, "map shows numbered route stops (" .. routePins .. ")")
WorldMapFrame:Hide()
SlashCmdList.FOREVEROPTIMIZER("route follow")
-- stop 1 is the patch under the player's feet: the arrow arrives at once and stays on it as "here:"
check(RT.following and FO.Arrow.target and FO.Arrow.target.label:sub(1, 6) == "here: " and FO.Arrow.target.arrive == 0 and outHas("at stop 1:"),
      "follow mode arrives at stop 1 and holds the patch (" .. tostring(FO.Arrow.target and FO.Arrow.target.label) .. ")")
local firstKey = RT.current.key
S.quests[2].objectives[1].finished = true S.quests[2].objectives[1].numFulfilled = 10
S.completeInLog = { [102] = true }
S.fire("QUEST_LOG_UPDATE") S.advance(1)
check(#RT.plan.stops == 3 and not idx("objective", 102) == false, "replan drops the finished objective patch (" .. #RT.plan.stops .. " stops)")
local hasCrystal = false for _, st in ipairs(RT.plan.stops) do if st.kind == "objective" and st.quests[102] then hasCrystal = true end end
check(not hasCrystal, "completed quest keeps only its turn-in")
S.questTags = { [101] = { tagID = 81 } }
S.fire("QUEST_LOG_UPDATE") S.advance(1)
check(#RT.plan.stops == 1 and #RT.plan.skipped == 1 and RT.plan.skipped[1].why == "dungeon", "dungeon quest leaves the loop (" .. tostring(RT.plan.skipped[1] and RT.plan.skipped[1].why) .. ")")
SlashCmdList.FOREVEROPTIMIZER("route group") S.flush()
check(#RT.plan.stops == 3 and outHas("join the route"), "/fo route group brings it back")
SlashCmdList.FOREVEROPTIMIZER("route skip")
check(RT.current and RT.current.key ~= firstKey, "/fo route skip moves to the next stop")
SlashCmdList.FOREVEROPTIMIZER("route stop")
check(not RT.following and FO.Arrow.target == nil, "/fo route stop clears the arrow")
S.questTags = nil S.completeInLog = nil
S.quests[2].objectives[1].finished = false S.quests[2].objectives[1].numFulfilled = 0
QT.db.quests[102].objectives[1].points = {}   -- the fake tick above recorded a point under the player; later arrow tests expect the database spot
SlashCmdList.FOREVEROPTIMIZER("route group")
local lines = RT:Lines()
check(#lines >= 2 and lines[1]:find("stops", 1, true), "Route HUD tab lists the plan")
local solo = RT:Plan({ only = { [101] = true } })
check(solo and #solo.stops == 2 and solo.stops[1].kind == "objective" and solo.stops[1].quests[101] and RT.plan ~= solo, "single-quest plan (guide steps) is separate and quiet")
noErrors("quest router")

-- Quest reader: text-to-speech on quest and gossip windows
local RD = FO.Reader
check(RD.available, "quest reader connected to C_VoiceChat (" .. tostring(RD.reason) .. ")")
local n0 = #S.tts.spoken
S.fire("QUEST_DETAIL")
local sp = S.tts.spoken[#S.tts.spoken]
check(#S.tts.spoken == n0 + 1 and sp.text == "Bloodscalp Ears. The Bloodscalp trolls raid our camp. Bring me 12 ears. Objectives: Bloodscalp Ear (0/12)" and sp.dest == 1 and sp.volume == 100,
      "quest detail read as title, cleaned description and objectives (" .. tostring(sp and sp.text) .. ")")
S.fire("QUEST_PROGRESS") check(S.tts.spoken[#S.tts.spoken].text == "Bloodscalp Ears. Do you have the ears?", "progress text read")
S.fire("QUEST_COMPLETE") check(S.tts.spoken[#S.tts.spoken].text:find("Well done", 1, true) ~= nil, "reward text read")
local stops = S.tts.stopped
S.fire("QUEST_FINISHED") check(S.tts.stopped == stops + 1, "closing the quest window stops the voice")
S.fire("GOSSIP_SHOW") check(S.tts.spoken[#S.tts.spoken].text == "What can I do for you?", "gossip read")
SlashCmdList.FOREVEROPTIMIZER("tts gossip off") S.fire("GOSSIP_SHOW") check(S.tts.spoken[#S.tts.spoken].text == "What can I do for you?" and #S.tts.spoken == n0 + 4, "gossip off skips gossip")
SlashCmdList.FOREVEROPTIMIZER("tts voice 1") check(RD.db.voice == 1 and S.tts.spoken[#S.tts.spoken].voice == 1 and outHas("voice 1: Daniel"), "/fo tts voice picks a voice and previews it")
SlashCmdList.FOREVEROPTIMIZER("tts rate 3") check(RD.db.rate == 3 and S.tts.spoken[#S.tts.spoken].rate == 3, "/fo tts rate")
SlashCmdList.FOREVEROPTIMIZER("tts off") S.fire("QUEST_DETAIL") check(#S.tts.spoken == n0 + 6, "tts off reads nothing")
SlashCmdList.FOREVEROPTIMIZER("tts again") check(#S.tts.spoken == n0 + 7, "/fo tts again repeats the last text even when off")
SlashCmdList.FOREVEROPTIMIZER("tts on") SlashCmdList.FOREVEROPTIMIZER("tts gossip on")
SlashCmdList.FOREVEROPTIMIZER("tts") check(outHas("quest reader: on, voice Daniel (2 available)"), "/fo tts status")
noErrors("quest reader")

-- Checklist, notes, alerts, bindings
local CLk = FO:GetModule("Core.Checklist")
local doneN = CLk:Progress()
check(CLk.cdb.done.vendor and CLk.cdb.done.trainer and CLk.cdb.done.bank and CLk.cdb.done.verify and CLk.cdb.done.map and CLk.cdb.done.qdb and CLk.cdb.done.combatlog and CLk.cdb.done.errors, "checklist ticked itself off from events and commands (" .. doneN .. "/10)")
SlashCmdList.FOREVEROPTIMIZER("checklist") check(outHas("first-hour checklist, " .. doneN .. "/10"), "/fo checklist prints progress")
SlashCmdList.FOREVEROPTIMIZER("note switched to the cave at the north end")
SlashCmdList.FOREVEROPTIMIZER("note") check(outHas("switched to the cave"), "/fo note stamps and lists session notes")
local soundsBefore = #S.sounds
check(FO:Alert("custom", "ping %d", 1) == true and #S.sounds == soundsBefore + 1, "alert prints and plays a sound")
check(FO:Alert("custom", "ping %d", 1) == false, "identical alert throttled")
SlashCmdList.FOREVEROPTIMIZER("alerts sound off") check(FO:Alert("custom", "quiet") == true and #S.sounds == soundsBefore + 1, "alerts sound off mutes the sound")
SlashCmdList.FOREVEROPTIMIZER("alerts rare off") check(FO:Alert("rare", "a rare") == false, "disabled kind is silent")
SlashCmdList.FOREVEROPTIMIZER("alerts rare on") SlashCmdList.FOREVEROPTIMIZER("alerts sound on") SlashCmdList.FOREVEROPTIMIZER("alerts")
check(outHas("alerts: sound on | flash on"), "/fo alerts prints settings")
local flashesBefore = #S.flashes
FO:Alert("custom", "|cffff6060flash me|r now") check(#S.flashes == flashesBefore + 1 and S.flashes[#S.flashes] == "flash me now", "alert flashes plain text in UIErrorsFrame")
SlashCmdList.FOREVEROPTIMIZER("alerts flash off") FO:Alert("custom", "no flash") check(#S.flashes == flashesBefore + 1, "alerts flash off skips the error frame")
SlashCmdList.FOREVEROPTIMIZER("alerts flash on")
-- respawn window alert: a confirmed estimate elapses while we stand at the kill spot
local FEa = FO:GetModule("Grinding.FarmingEfficiency")
FEa.db.spawns[777] = { name = "Test Boar", points = { { S.pos.map, S.pos.x, S.pos.y, confirmed = { 30 }, bounds = {}, lastKill = S.clock - 31 } } }
local fired = #FO.Alerts.fired
S.clock = S.clock + (5 - S.clock % 5) S.advance(5)
check(#FO.Alerts.fired > fired and FO.Alerts.fired[#FO.Alerts.fired].text:find("Test Boar should be back"), "respawn window alert fires once the estimate elapses nearby")
check(type(ForeverOptimizer_ToggleHUD) == "function" and BINDING_NAME_FOREVEROPTIMIZER_TOGGLE ~= nil, "key binding globals defined")
ForeverOptimizer_ToggleHUD() ForeverOptimizer_ToggleHUD()
noErrors("checklist/notes/alerts")
noErrors("all " .. #cmds .. " slash commands")

-- Dashboard tabs render
for _, name in ipairs({ "Overview", "Hunter", "Leveling", "Economy", "Character", "History" }) do FO.Dashboard:SelectTab(name) S.advance(1) end
do
    local tabs
    for i = 1, 20 do local n, v = debug.getupvalue(FO.Dashboard.SelectTab, i) if n == "tabs" then tabs = v end end
    local ov, hu = table.concat(tabs.Overview.fn(), "\n"), tabs.Hunter and table.concat(tabs.Hunter.fn(), "\n") or ""
    check(tabs.Hunter and hu:find("Ammo") and not ov:find("Ammo"), "class lines live on the Hunter tab, not Overview")
end
noErrors("dashboard tabs")

-- Review fixes: amounts-hidden ratio, zero-stack auctions, staged migrations
do
    local CLx = FO.CombatLog
    local c0, a0 = CLx.count, CLx.amountEvents
    local m3 = { guid = "Creature-0-1-2-3-595-0000CL03", name = "Durotar Tiger", flags = 0xA48 }
    for _ = 1, 50 do
        S.cl("SPELL_CAST_SUCCESS", me, m3, 75, "Auto Shot", 1)                  -- no amount: must not dilute the ratio
        S.cl("RANGE_DAMAGE", me, m3, 75, "Auto Shot", 1, "SECRET", 0, 1, 0, 0, 0, false)
    end
    check(CLx.amountsHidden == true, "combat log reports amounts hidden when amount-bearing events are secret, casts in between")
    check(not CSm:Available(), "combat stats fall back once amounts are hidden")
    for _ = 1, 400 do S.cl("RANGE_DAMAGE", me, m3, 75, "Auto Shot", 1, 90, 0, 1, 0, 0, 0, false) end
    check(CLx.amountsHidden == false, "amounts-hidden flag clears when readable amounts dominate again")
    check(CLx.count - c0 == 500 and CLx.amountEvents - a0 == 450, "event and amount-event counters (" .. (CLx.count - c0) .. "/" .. (CLx.amountEvents - a0) .. ")")

    local AS, PH = FO:GetModule("Economy.AuctionHouseScanner"), FO:GetModule("Economy.PriceHistory")
    S.ahItems = { { name = "Linen Cloth", count = 0, buyout = 500, itemID = 2589 }, { name = "Linen Cloth", count = 20, buyout = 8000, itemID = 2589 } }
    FO.state.frames.auction = true
    AS:StartFullScan()
    S.fire("REPLICATE_ITEM_LIST_UPDATE")
    local latest = PH:Latest(2589)
    check(latest and latest.min == 400, "zero-stack auction counts as one item, no infinite unit price (min " .. tostring(latest and latest.min) .. ")")
    check(outHas("scan done: 2 auctions"), "replicate scan completes on the stubbed auction house")
    FO.state.frames.auction = false
    S.ahItems = {}

    local keepDB, keepMig = ForeverOptimizerDB, FO.migrations[2]
    FO.migrations[2] = function(root) root.account.modules = { disabled = {} } error("boom") end
    ForeverOptimizerDB = { version = 1, account = { loot = { log = { "x" } } }, chars = {} }
    FO:InitStorage()
    check(ForeverOptimizerDB.version == 1 and ForeverOptimizerDB.account.modules == nil, "failed migration leaves the saved table untouched")
    check(FO.migrationFailed and FO.migrationFailed.version == 2 and ForeverOptimizerDB.migrationFailed, "failed migration recorded in memory and in the file")
    check(outHas("migration to v2 failed"), "failed migration announced")
    S.errors = {}   -- the migration error above was intentional
    FO.migrations[2] = keepMig
    ForeverOptimizerDB = { version = 1, account = {}, chars = {} }
    FO:InitStorage()
    check(ForeverOptimizerDB.version == 3 and ForeverOptimizerDB.account.modules and ForeverOptimizerDB.migrationFailed == nil and FO.migrationFailed == nil, "clean migration v1 -> v3 on a fresh file")
    ForeverOptimizerDB = { version = 99, account = {}, chars = {} }
    FO:InitStorage()
    check(outHas("newer addon version") and FO.dbNewer == 99, "file from a newer addon version is announced, not migrated")
    FO.dbNewer = nil
    ForeverOptimizerDB = keepDB
    FO:InitStorage()
end

-- Logout archives
S.fire("PLAYER_LOGOUT")
check(#FO.Session.db.list == 1 and FO.Session.db.list[1].kills >= 8, "session archived on logout")
noErrors("logout")


-- Direction arrow: bearing, distance, colour band, arrival; the route planner feeds it
local AR = FO.Arrow
SlashCmdList.FOREVEROPTIMIZER("arrow 50 50 test target")
check(AR.target and AR.target.label == "test target" and math.abs(AR.target.x - 0.5) < 0.001, "/fo arrow sets a target on the current map")
S.facing = 0
S.mapUpdate()
check(AR.yards and math.abs(AR.yards - 600) < 1, "arrow distance in yards from the map's world size (" .. tostring(AR.yards) .. ")")
check(AR.heading and math.abs(AR.heading + math.pi / 2) < 0.01, "target due east, facing north: arrow points right (" .. tostring(AR.heading) .. ")")
S.facing = -math.pi / 2
S.mapUpdate()
check(AR.heading and math.abs(AR.heading) < 0.01, "facing the target: arrow points straight up")
S.pos.x = 0.499
S.mapUpdate()
check(AR.target == nil and outHas("arrived: test target"), "arrival inside the radius clears the arrow and says so")
S.pos.x = 0.40
SlashCmdList.FOREVEROPTIMIZER("next 102")
check(AR.target ~= nil, "/fo next drives the arrow too (" .. tostring(AR.target and AR.target.label) .. ")")
SlashCmdList.FOREVEROPTIMIZER("arrow off") check(AR.target ~= nil, "arrow off keeps the target")
SlashCmdList.FOREVEROPTIMIZER("arrow on")
noErrors("arrow")

-- Leveling guide: route pick, auto-advance from the quest log, class filter, skip/back/goto, travel steps via the arrow
local GD = FO.Guide
check(GD.route == nil, "no route auto-picked for a level 23 character (routes end at 20)")
P.level = 1
check(GD:PickRoute() and GD:PickRoute().key == "orc-troll-1-20", "a level 1 Orc gets the Orc & Troll route")
P.level = 23
SlashCmdList.FOREVEROPTIMIZER("guide use 1")
check(GD.route and GD.route.key == "orc-troll-1-20", "/fo guide use 1 activates the route (" .. tostring(GD.route and GD.route.key) .. ")")
check(GD.index == 1 and GD.current and GD.current[1] == "A" and GD.current[2] == 4641, "guide starts at step 1: accept Your Place In The World")
GD:PointArrow(true)
check(AR.target and AR.target.label == "Accept: Kaltunk", "guide arrow points at the quest giver (" .. tostring(AR.target and AR.target.label) .. ")")
S.quests[#S.quests + 1] = { questID = 4641, title = "Your Place In The World", level = 1, objectives = {} }
S.fire("QUEST_ACCEPTED", 4641) S.advance(1)
check(GD.index == 2 and GD.current[1] == "T", "accepting the quest advances to its turn-in step (" .. GD.index .. ")")
check(AR.target and AR.target.label == "Turn in: Gornek", "arrow moves to the turn-in NPC (" .. tostring(AR.target and AR.target.label) .. ")")
S.qdb.completed[4641] = true
table.remove(S.quests)
S.fire("QUEST_TURNED_IN", 4641, 100, 0) S.advance(1)
check(GD.index == 3 and GD.current[2] == 788, "turning in advances to the next accept (step " .. GD.index .. ")")
SlashCmdList.FOREVEROPTIMIZER("guide skip")
check(GD.index == 4, "skip moves on (" .. GD.index .. ")")
SlashCmdList.FOREVEROPTIMIZER("guide skip")
check(GD.index == 5 and GD.current.class == "HUNTER", "hunter-only step shown to a hunter (" .. GD.index .. ")")
SlashCmdList.FOREVEROPTIMIZER("guide skip")
check(GD.index == 14 and GD.current[1] == "T", "Troll, warlock, shaman, warrior and priest steps skipped for an Orc hunter (" .. GD.index .. ")")
SlashCmdList.FOREVEROPTIMIZER("guide")
check(outHas("not in your log"), "a turn-in you never accepted is flagged, not auto-skipped")
SlashCmdList.FOREVEROPTIMIZER("guide back")
check(GD.index == 5, "back returns to the previous applicable step (" .. GD.index .. ")")
FO.Player.race = "Troll"
SlashCmdList.FOREVEROPTIMIZER("guide goto 5")
check(GD.index == 6 and GD.current[2] == 3082, "a Troll hunter gets the Troll class quest, not the Orc one (" .. GD.index .. ")")
FO.Player.race = "Tauren" P.level = 1
check(GD:PickRoute() and GD:PickRoute().key == "tauren-1-20", "a level 1 Tauren gets the Tauren route")
FO.Player.race = "Orc" P.level = 23
local shared = 0
for _, r in ipairs(FO.Routes) do for _, st in ipairs(r.steps) do if st[1] == "A" and st[2] == 844 then shared = shared + 1 end end end
check(#FO.Routes == 2 and shared == 2, "both routes include the shared Barrens section (" .. shared .. ")")
SlashCmdList.FOREVEROPTIMIZER("guide goto 34")
check(GD.index == 35 and GD.current[1] == "A", "a level step already met is passed automatically (" .. GD.index .. ")")
SlashCmdList.FOREVEROPTIMIZER("guide goto 71")
check(GD.current[1] == "GOTO" and AR.target and AR.target.label == "Go to: Razor Hill", "travel step points the arrow (" .. tostring(AR.target and AR.target.label) .. ")")
S.pos.map, S.pos.x, S.pos.y = 1411, 0.520, 0.435
S.mapUpdate()
check(GD.index == 72, "arriving completes the travel step (" .. GD.index .. ")")
S.pos.map, S.pos.x, S.pos.y = 1434, 0.40, 0.50
SlashCmdList.FOREVEROPTIMIZER("guide list") check(outHas("Orc & Troll 1-20") and outHas("(active)"), "/fo guide list names the active route")
SlashCmdList.FOREVEROPTIMIZER("tab Guide")
SlashCmdList.FOREVEROPTIMIZER("hud click Arrow")
check(AR.target ~= nil, "HUD Guide tab buttons work")
SlashCmdList.FOREVEROPTIMIZER("tab Overview")
noErrors("leveling guide")

-- Item advisor: vendor, disenchant or auction
local IA = FO:GetModule("Economy.ItemAdvisor")
S.items[2244] = { name = "Krol Blade", quality = 3, sell = 2000, class = 2, sub = 7, stack = 1, equip = "INVTYPE_WEAPON", ilvl = 37 }
PH:Observe(10940, "Strange Dust", 1200, 300, 9)            -- 1140 net
PH:Observe(10998, "Lesser Astral Essence", 5000, 40, 3)    -- 4750 net
PH:Observe(10978, "Small Glimmering Shard", 20000, 5, 2)   -- 19000 net
local a = IA:Assess(9797)
check(a and a.de and #a.de.outcomes == 3 and a.de.outcomes[1].itemID == 10940 and a.de.outcomes[1].p == 0.75 and a.de.outcomes[1].lo == 4 and a.de.outcomes[1].hi == 6,
      "green armour ilvl 22 disenchants to Strange Dust x4-6 at 75%")
check(a.de.expected == 6650 and a.de.lo == 4560 and a.de.hi == 19000, "expected " .. tostring(a.de.expected) .. ", range " .. tostring(a.de.lo) .. "-" .. tostring(a.de.hi))
check(a.de.need == 25 and a.de.skill == nil and not a.de.can, "needs Enchanting 25; this hunter has none")
check(a.best == "vendor" and a.why:find("enchanter", 1, true) and a.why:find("no auction data", 1, true), "without scans or a skill the call is vendor, with the enchanter note (" .. a.why .. ")")
PH:Observe(9797, "Elegant Robes", 9000, 2, 2)
a = IA:Assess(9797)
check(a.best == "auction" and a.ah and a.ah.net == 8550 and a.bestValue == 8550, "a scanned listing above vendor and mats makes it auction")
a = IA:Assess(9797, { bound = true })
check(a.best == "vendor" and a.bound and a.why:find("soulbound", 1, true), "soulbound removes the auction option")
local oldProf = GetProfessionInfo
GetProfessionInfo = function(i) if i == 1 then return "Enchanting", nil, 60, 150, nil, nil, 333 end return "Engineering", nil, 60, 150, nil, nil, 202 end
S.fire("SKILL_LINES_CHANGED")
check(IA:EnchantSkill() == 60, "Enchanting rank read from the profession list")
a = IA:Assess(9797, { bound = true })
check(a.de.can and a.best == "disenchant" and a.bestValue == 6650, "soulbound green goes to the disenchanter at skill 60")
a = IA:Assess(2244)
check(a.de and #a.de.outcomes == 1 and a.de.outcomes[1].itemID == 11139 and a.de.outcomes[1].p == 1 and a.de.need == 100 and not a.de.can, "blue ilvl 37 weapon: one Large Glowing Shard, needs Enchanting 100")
check(not a.de.priced and a.de.expected == 0 and a.why:find("unpriced until an AH scan", 1, true), "an unscanned shard is reported as unpriced, not as vendor copper")
local o = IA:Outcomes(2, 15, 2, 22)
check(o[1].itemID == 10998 and o[1].p == 0.75, "green weapons favour the essence")
o = IA:Outcomes(4, 1, 4, 58)
check(o[1].itemID == 20725 and o[1].lo == 1 and o[1].hi == 1, "epic ilvl 58 armour: a Nexus Crystal")
check(IA:Outcomes(2, 20, 2, 30) == nil and IA:Outcomes(7, 5, 2, 30) == nil and IA:Outcomes(4, 1, 1, 30) == nil, "fishing poles, trade goods and whites do not disenchant")
a = IA:Assess(2589)
check(a and not a.de and a.deReason, "Linen Cloth: vendor or auction only (" .. tostring(a.deReason) .. ")")
SlashCmdList.FOREVEROPTIMIZER("advise |cffffffff|Hitem:9797::::::::23:::::|h[Elegant Robes]|h|r")
check(outHas("Strange Dust") and outHas("Lesser Astral Essence") and outHas("needs Enchanting 25 (you: 60)"), "/fo advise <link> prints the three options and the result table")
SlashCmdList.FOREVEROPTIMIZER("advise bronze mace")
check(outHas("Bronze Mace (green, ilvl 22") and outHas("Lesser Astral Essence") and outHas("vendor      8s 98c"), "/fo advise by name resolves an unscanned item through the seed (weapon, ilvl and sell price)")
table.insert(S.bags, { itemID = 9797, count = 1, quality = 2 })
table.insert(S.bags, { itemID = 2244, count = 1, quality = 3 })
SlashCmdList.FOREVEROPTIMIZER("advise bags")
check(outHas("Bags, green and better (3)") and outHas("Elegant Robes") and outHas("Krol Blade") and outHas("DE ?*") and outHas("this character cannot disenchant it"), "/fo advise bags sweeps greens and blues with the enchanter and unpriced footnotes")
GameTooltip.GetItem = function() return "Elegant Robes", "|cffffffff|Hitem:9797::::::::23:::::|h[Elegant Robes]|h|r" end
GameTooltip.AddLine = function(self, line) self.lines = self.lines or {} self.lines[#self.lines + 1] = line end
for _, fn in ipairs(S.tooltipFns) do fn(GameTooltip) end
local ttLine
for _, l in ipairs(GameTooltip.lines or {}) do if l:find("FO: vendor", 1, true) then ttLine = l end end
check(ttLine and ttLine:find("DE ~66s 50c", 1, true) and ttLine:find("auction", 1, true), "tooltip line carries vendor, AH and DE figures with the call (" .. tostring(ttLine) .. ")")
SlashCmdList.FOREVEROPTIMIZER("advise tooltip") check(IA.db.settings.tooltip == false, "advise tooltip toggles off")
SlashCmdList.FOREVEROPTIMIZER("advise tooltip") SlashCmdList.FOREVEROPTIMIZER("advise margin 25") check(IA.db.settings.margin == 25, "advise margin set")
SlashCmdList.FOREVEROPTIMIZER("advise margin 10")
GetProfessionInfo = oldProf S.fire("SKILL_LINES_CHANGED")
table.remove(S.bags) table.remove(S.bags)
noErrors("item advisor")

-- Module disable is honoured on the next load
ForeverOptimizerDB.account.modules.disabled["Classes.Warlock"] = true
S.frames, S.registered, S.tickers, S.timers = nil, {}, {}, {}
local FO2 = S.loadAddon("ForeverOptimizer")
S.fire("ADDON_LOADED", "ForeverOptimizer") S.fire("PLAYER_LOGIN")
check(FO2:GetModule("Classes.Warlock").disabled == true and FO2:GetModule("Classes.Warlock").db == nil, "disabled module skipped on load")
check(FO2.state.disabledCount == 1, "disabled count reported")
noErrors("second load")

-- Third load with the combat log refused (12.x behaviour): everything degrades, nothing errors
ForeverOptimizerDB.account.modules.disabled["Classes.Warlock"] = nil
S.combatLogAllowed = false
S.frames, S.registered, S.tickers, S.timers = nil, {}, {}, {}
local FO3 = S.loadAddon("ForeverOptimizer")
S.fire("ADDON_LOADED", "ForeverOptimizer") S.fire("PLAYER_LOGIN")
check(FO3.CombatLog.registered == false and FO3.CombatLog.estimated == true and FO3.CombatFeed.active, "combat log refused, UNIT_COMBAT feed stands in")
check(#FO3.Classes.HUNTER:Lines() >= 3, "hunter lines still render without the log")

-- The feed: hits on the target become damage events with the last cast's name; duplicates
-- through a second unit token are dropped; hits on the player are damage taken; heals are
-- mine when solo; the XP chat line closes the fight.
S.units.target = { name = "Mottled Boar", guid = "Creature-0-1-2-3-3098-0000BOAR", hostile = true, level = 2 }
S.units.nameplate1 = S.units.target
S.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-1", 3044)            -- Arcane Shot, arcane school 64
S.fire("UNIT_COMBAT", "target", "WOUND", "", 42, 64)
S.fire("UNIT_COMBAT", "nameplate1", "WOUND", "", 42, 64)                 -- same hit, other token
S.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-2", 75)              -- Auto Shot, physical
S.fire("UNIT_COMBAT", "target", "WOUND", "CRITICAL", 10, 1)
S.advance(3)
S.fire("UNIT_COMBAT", "target", "WOUND", "", 9, 1)                       -- no recent physical cast: Melee
S.fire("UNIT_COMBAT", "target", "DODGE", "", 0, 1)
S.fire("UNIT_COMBAT", "player", "WOUND", "", 7, 1)
S.fire("UNIT_COMBAT", "player", "HEAL", "", 20, 2)
local MT3, CS3 = FO3.Meter, FO3.CombatStats
check(FO3.CombatFeed.dropped == 1 and MT3.cur.dmg == 61 and MT3.cur.heal == 20, "feed: 61 damage and 20 healing on the meter, duplicate token dropped (" .. tostring(MT3.cur.dmg) .. "/" .. tostring(MT3.cur.heal) .. ")")
local bs = CS3.s.bySpell
check(bs["Arcane Shot"] and bs["Arcane Shot"].total == 42 and bs["Auto Shot"] and bs["Auto Shot"].crit == 1 and bs["Melee"] and bs["Melee"].total == 9, "feed: damage attributed to Arcane Shot, Auto Shot (crit) and Melee")
check(CS3.s.taken.total == 7 and CS3.s.misses["Melee"] and CS3.s.misses["Melee"].n == 1 and CS3.s.heal["Heal"] and CS3.s.heal["Heal"].total == 20, "feed: damage taken, dodge and heal recorded")
check(CS3.s.mana["Arcane Shot"] and CS3.s.mana["Arcane Shot"].casts == 1, "feed: casts counted for mana per spell")
local fightsBefore = CS3.s.fights
S.fire("CHAT_MSG_COMBAT_XP_GAIN", "Mottled Boar dies, you gain 45 experience.")
check(CS3.s.fights == fightsBefore + 1, "feed: XP line closes the fight (" .. tostring(CS3.s.fights) .. ")")
SlashCmdList.FOREVEROPTIMIZER("combatlog") check(outHas("estimated from UNIT_COMBAT"), "combatlog reports the estimate")
SlashCmdList.FOREVEROPTIMIZER("combatfeed") check(outHas("school 64: Arcane Shot"), "combatfeed shows the attribution state")
S.fire("UNIT_COMBAT", "target", "WOUND", "SECRET", "SECRET", 1)            -- 12.x: amount and descriptor secret in combat
S.fire("UNIT_COMBAT", "target", "WOUND", "SECRET", "SECRET", 1)            -- cannot be told apart: dropped as a duplicate, no error
check(FO3.CombatFeed.secret.hostile == 1 and FO3.CombatFeed.readable.hostile == 3 and MT3.hidden == 1, "feed: secret amounts counted, never compared (" .. FO3.CombatFeed.secret.hostile .. "/" .. FO3.CombatFeed.readable.hostile .. "/" .. MT3.hidden .. ")")
SlashCmdList.FOREVEROPTIMIZER("combatfeed") check(outHas("on hostiles 3 / 1"), "combatfeed reports readable vs secret amounts")
S.units.nameplate1 = nil
noErrors("third load (no combat log)")

-- Fourth load as a shaman: shield, imbue, totems and per-kill counts come from the client
S.combatLogAllowed = true
S.player.class = { "Shaman", "SHAMAN" }
S.frames, S.registered, S.tickers, S.timers = nil, {}, {}, {}
local FO4 = S.loadAddon("ForeverOptimizer")
S.fire("ADDON_LOADED", "ForeverOptimizer") S.fire("PLAYER_LOGIN")
check(FO4.Player.class == "SHAMAN" and FO4.Classes.SHAMAN, "shaman module active for a shaman")
S.auras = {}
S.imbue = { main = nil }
S.totems = {}
SlashCmdList.FOREVEROPTIMIZER("shaman")
check(outHas("No shield up") and outHas("No weapon imbue") and outHas("No totems down"), "/fo shaman reports the three gaps")
S.fire("PLAYER_REGEN_DISABLED")
check(outHas("no shield up: Lightning Shield") and outHas("no weapon imbue: Rockbiter"), "combat start without shield or imbue alerts")
S.auras = { { name = "Lightning Shield", applications = 3 } }
S.imbue = { main = 90 * 1000, off = 1500 * 1000 }
S.totems = { { name = "Searing Totem", start = S.clock, duration = 60 }, { name = "Strength of Earth Totem", start = S.clock, duration = 120 } }
S.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-1", 8042)   -- Earth Shock (name via C_Spell stub)
SlashCmdList.FOREVEROPTIMIZER("shaman")
check(outHas("Lightning Shield x3") and outHas("Imbue 01:30 left") and outHas("LOW") and outHas("off-hand 25:00"), "shield charges and imbue timers read")
check(outHas("Totems Searing 01:00, Strength of Earth 02:00"), "totems listed by slot with time left")
check(#FO4.Classes.SHAMAN:Lines() >= 4, "shaman tab renders")
SlashCmdList.FOREVEROPTIMIZER("rotation") check(outHas("Rockbiter Weapon") and outHas("Stormstrike"), "/fo rotation prints the shaman priority with Stormstrike optional")
SlashCmdList.FOREVEROPTIMIZER("build") check(outHas("Enhancement leveling"), "/fo build picks the shaman build")
SlashCmdList.FOREVEROPTIMIZER("guide goto 5")
check(FO4.Guide.index == 9 and FO4.Guide.current.class == "SHAMAN" and FO4.Guide.current.race == "Orc", "an Orc shaman sees the Orc shaman class step (" .. FO4.Guide.index .. ")")
noErrors("fourth load (shaman)")

print(string.format("\n%d failures, %d chat lines", failures, #S.out))
os.exit(failures == 0 and 0 or 1)

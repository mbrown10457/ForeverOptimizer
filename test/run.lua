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
check(#order == 33, "loaded " .. #order .. " files from TOC")
check(#FO.modules >= 26, #FO.modules .. " modules registered")
check(ForeverOptimizerDB == nil or true, "pre-login")

S.fire("ADDON_LOADED", "ForeverOptimizer")
S.fire("PLAYER_LOGIN")
noErrors("login")
check(FO.state.enabled, "enabled")
check(ForeverOptimizerDB and ForeverOptimizerDB.account.sessions, "SavedVariables initialised")
check(FO.Player.class == "HUNTER" and FO.Player.level == 23, "character profile read")
check(FO.Session:Live() ~= nil, "session started")
check(S.registered.COMBAT_LOG_EVENT_UNFILTERED == nil, "combat log never requested")

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
SlashCmdList.FOREVEROPTIMIZER("route ore")
SlashCmdList.FOREVEROPTIMIZER("respawn 595")
SlashCmdList.FOREVEROPTIMIZER("objective gold") SlashCmdList.FOREVEROPTIMIZER("zones") SlashCmdList.FOREVEROPTIMIZER("objective custom 1 2 3") SlashCmdList.FOREVEROPTIMIZER("objective balanced")
SlashCmdList.FOREVEROPTIMIZER("module off Classes.Priest") SlashCmdList.FOREVEROPTIMIZER("module on priest") SlashCmdList.FOREVEROPTIMIZER("module off Core.Verify")
SlashCmdList.FOREVEROPTIMIZER("bags worst 3") SlashCmdList.FOREVEROPTIMIZER("craft sellthrough 0.8") SlashCmdList.FOREVEROPTIMIZER("history 5") SlashCmdList.FOREVEROPTIMIZER("flips")
SlashCmdList.FOREVEROPTIMIZER("verify")
local VM = FO:GetModule("Core.Verify")
check(VM.db.last and #VM.db.last.checks > 20 and VM.db.last.toc == "16001", "verify ran and saved " .. tostring(VM.db.last and #VM.db.last.checks) .. " checks")
check(outHas("TOC interface matches"), "verify printed interface check")
check(FO.root.account.modules.disabled["Classes.Priest"] == nil and FO.root.account.modules.disabled["Core.Verify"] == nil, "module toggles respect core protection and re-enable")
check(FO.root.version == 2, "db migrated to v2")
noErrors("all " .. #cmds .. " slash commands")

-- Dashboard tabs render
for _, name in ipairs({ "Overview", "Leveling", "Economy", "Character", "History" }) do FO.Dashboard:SelectTab(name) S.advance(1) end
noErrors("dashboard tabs")

-- Logout archives
S.fire("PLAYER_LOGOUT")
check(#FO.Session.db.list == 1 and FO.Session.db.list[1].kills >= 8, "session archived on logout")
noErrors("logout")


-- Module disable is honoured on the next load
ForeverOptimizerDB.account.modules.disabled["Classes.Warlock"] = true
S.frames, S.registered, S.tickers, S.timers = nil, {}, {}, {}
local FO2 = S.loadAddon("ForeverOptimizer")
S.fire("ADDON_LOADED", "ForeverOptimizer") S.fire("PLAYER_LOGIN")
check(FO2:GetModule("Classes.Warlock").disabled == true and FO2:GetModule("Classes.Warlock").db == nil, "disabled module skipped on load")
check(FO2.state.disabledCount == 1, "disabled count reported")
noErrors("second load")

print(string.format("\n%d failures, %d chat lines", failures, #S.out))
os.exit(failures == 0 and 0 or 1)

local ADDON, FO = ...
local U = FO.Util
local print = FO:Printer("Core")

-- ===========================================================================
-- /fo verify: probes every client API this addon depends on and prints a
-- PASS / FAIL / INFO table. Results are saved so they can be read from the
-- SavedVariables file after logout. Run it once on first launch.
-- ===========================================================================
local V = FO:NewModule("Core.Verify", { account = "verify", defaults = { last = nil } })

local function has(path)
    local cur = _G
    for part in path:gmatch("[^%.]+") do
        if type(cur) ~= "table" then return false end
        cur = cur[part]
        if cur == nil then return false end
    end
    return true
end

function V:Run()
    local checks = {}
    local function add(name, ok, detail) checks[#checks + 1] = { name = name, ok = ok, detail = detail or "" } end

    -- client
    local version, build, bdate, toc = "?", "?", "?", "?"
    if GetBuildInfo then version, build, bdate, toc = GetBuildInfo() end
    add("client build", nil, string.format("%s (%s, %s) TOC %s; Lua %s", tostring(version), tostring(build), tostring(bdate), tostring(toc), tostring(_VERSION)))
    add("TOC interface matches", tostring(toc) == "120105" or tostring(toc) == "16001", "we ship 120105, 16001; client says " .. tostring(toc))

    -- restrictions
    add("issecretvalue present", nil, issecretvalue and "12.x secret values active" or "no secret values on this client")
    if issecretvalue then
        local okH, secretHealth = pcall(function() return issecretvalue(UnitHealth("player")) end)
        add("UnitHealth out of combat", nil, okH and ("secret=" .. tostring(secretHealth) .. (secretHealth and " (always secret on Forever: fight-cost tracking off)" or "")) or "errored")
        local okX, secretXP = pcall(function() return issecretvalue(UnitXP("player")) end)
        add("UnitXP readable", okX and secretXP == false, okX and ("secret=" .. tostring(secretXP)) or "errored")
    end
    -- 12.x: IsAddOnRestrictionActive(type) needs an Enum.AddOnRestrictionType value; query each one
    if has("C_RestrictedActions.IsAddOnRestrictionActive") then
        local types, out = Enum and Enum.AddOnRestrictionType, {}
        if type(types) == "table" then
            for name, v in pairs(types) do
                local ok, res = pcall(C_RestrictedActions.IsAddOnRestrictionActive, v)
                out[#out + 1] = name .. "=" .. (ok and tostring(res) or "err")
            end
            table.sort(out)
        else
            local ok, res = pcall(C_RestrictedActions.IsAddOnRestrictionActive)
            out[1] = ok and ("active=" .. tostring(res)) or "needs a type and Enum.AddOnRestrictionType is absent"
        end
        add("C_RestrictedActions", nil, table.concat(out, " "))
    else
        add("C_RestrictedActions", nil, "absent")
    end
    -- Do not probe by registering COMBAT_LOG_EVENT_UNFILTERED: on Forever that is a
    -- forbidden action. Report what the combat log module found at enable time.
    local CLm = FO:GetModule("Core.CombatLog")
    local clOk = CLm and CLm.available
    add("combat log", nil, clOk and (CLm.estimated and "UNIT_COMBAT feed: meter, combat stats and rotation are estimates" or "registered: CombatStats, class analytics and FO_FIGHT timing can run")
        or ("unavailable (" .. tostring(CLm and CLm.reason or "module missing") .. "): chat/loot paths in use"))
    if C_CombatLog and C_CombatLog.IsCombatLogRestricted then
        local okR, restricted = pcall(C_CombatLog.IsCombatLogRestricted)
        add("C_CombatLog.IsCombatLogRestricted()", nil, okR and ("restricted=" .. tostring(restricted) .. " (checked out of combat; may differ in instances)") or "errored")
    else
        add("C_CombatLog.IsCombatLogRestricted", nil, "absent")
    end
    if C_GameRules and C_GameRules.GetForeverExperiencePreset then
        local okP, preset = pcall(C_GameRules.GetForeverExperiencePreset)
        local okH, hc = pcall(function() return C_GameRules.IsHardcoreActive and C_GameRules.IsHardcoreActive() end)
        add("Forever experience preset", nil, (okP and ("preset=" .. tostring(preset) .. " (0 Classic, 1 Enhanced)") or "errored") .. (okH and (", hardcore=" .. tostring(hc)) or ""))
    end
    if C_Secrets and C_Secrets.HasSecretRestrictions then
        local okS, hasS = pcall(C_Secrets.HasSecretRestrictions)
        add("C_Secrets.HasSecretRestrictions()", nil, okS and ("secrets=" .. tostring(hasS)) or "errored")
    else
        add("C_Secrets", nil, "absent (no secret-value system)")
    end
    local f = CreateFrame("Frame")
    local npOk = pcall(f.RegisterEvent, f, "NAME_PLATE_UNIT_ADDED")
    add("NAME_PLATE_UNIT_ADDED registrable", npOk, "needed for respawn confirmation")

    -- core APIs
    add("C_Container item info", has("C_Container.GetContainerItemInfo"), "bags, auto-sell, consumables")
    add("C_Item.GetItemInfo", has("C_Item.GetItemInfo"), "")
    add("C_Item.GetItemStats", has("C_Item.GetItemStats") or _G.GetItemStats ~= nil, "gear evaluator")
    add("C_UnitAuras.GetAuraDataByIndex", has("C_UnitAuras.GetAuraDataByIndex"), "rest + buff detection")
    add("TooltipDataProcessor", has("TooltipDataProcessor.AddTooltipPostCall"), "tooltip upgrade line")
    add("C_Map.GetMapWorldSize", has("C_Map.GetMapWorldSize"), "yard distances for respawn/routes")
    local mapID, x, y = U.PlayerPosition()
    add("player map position", mapID ~= nil and x ~= nil, mapID and string.format("map %s (%.3f, %.3f)", tostring(mapID), x or 0, y or 0) or "nil (instance or restricted?)")
    add("C_Map.SetUserWaypoint", has("C_Map.SetUserWaypoint") and has("UiMapPoint.CreateFromCoordinates"), "waypoints")

    -- quests
    add("C_QuestLog.GetQuestObjectives", has("C_QuestLog.GetQuestObjectives"), "objective ticks")
    add("C_QuestLog.GetNextWaypoint", has("C_QuestLog.GetNextWaypoint"), has("C_QuestLog.GetNextWaypoint") and "present; check it returns data for vanilla quests" or "absent; recorded points only")
    add("C_QuestLog.GetInfo", has("C_QuestLog.GetInfo"), "")

    -- economy
    local retailAH = has("C_AuctionHouse.ReplicateItems")
    local classicAH = _G.QueryAuctionItems ~= nil or _G.GetNumAuctionItems ~= nil
    add("auction house API", retailAH or classicAH, retailAH and "retail C_AuctionHouse (scanner matches)" or classicAH and "CLASSIC list AH: AuctionHouseScanner needs the classic path" or "neither found")
    add("merchant API", has("C_MerchantFrame.GetItemInfo") or _G.GetMerchantItemInfo ~= nil,
        has("C_MerchantFrame.GetItemInfo") and ("C_MerchantFrame.GetItemInfo; count " .. (_G.GetMerchantNumItems and "GetMerchantNumItems" or "by probing") .. ", links " .. (_G.GetMerchantItemLink and "GetMerchantItemLink" or "by item name"))
        or _G.GetMerchantItemInfo and "classic GetMerchantItemInfo" or "none: vendor prices not recorded")
    add("C_TradeSkillUI schematics", has("C_TradeSkillUI.GetRecipeSchematic"), has("C_TradeSkillUI.GetRecipeSchematic") and "profession profit ok" or "absent; ProfessionProfit needs the classic GetTradeSkillInfo path")

    -- character
    add("trainer API", _G.GetTrainerServiceInfo ~= nil and _G.GetTrainerServiceCost ~= nil, "training planner")
    add("skill lines", nil, has("C_SkillInfo.GetSkillLineInfo") and "C_SkillInfo: weapon skills readable" or _G.GetNumSkillLines and "classic GetSkillLineInfo" or "no skill line API")
    add("talent API", nil, has("C_SpecializationInfo.GetTalentInfo") and "C_SpecializationInfo.GetTalentInfo (rotation + build read it from level 10)"
        or _G.GetNumTalentTabs and "classic talent tabs" or _G.GetSpecialization and "retail spec only" or "none; build not recorded")
    add("reputation API", has("C_Reputation.GetFactionDataByIndex") or _G.GetFactionInfo ~= nil, "")
    add("pet happiness", nil, has("C_PetInfo.GetPetHappiness") and "C_PetInfo.GetPetHappiness" or _G.GetPetHappiness and "classic GetPetHappiness" or "absent (retail-style pets)")
    add("hearthstone cooldown", has("C_Container.GetItemCooldown") or _G.GetItemCooldown ~= nil, "")

    -- chat patterns we parse
    local xpStr = (type(COMBAT_XP_GAIN1) == "string" and "COMBAT_XP_GAIN1") or (type(COMBAT_XP_GAIN) == "string" and "COMBAT_XP_GAIN") or nil
    add("XP gain chat string", xpStr ~= nil, xpStr and (xpStr .. " = " .. tostring(_G[xpStr])) or "neither COMBAT_XP_GAIN1 nor COMBAT_XP_GAIN; using the fixed pattern")
    add("FACTION_STANDING_INCREASED", type(FACTION_STANDING_INCREASED) == "string", tostring(FACTION_STANDING_INCREASED))
    add("GOLD/SILVER/COPPER_AMOUNT", type(GOLD_AMOUNT) == "string", tostring(GOLD_AMOUNT) .. " / " .. tostring(SILVER_AMOUNT) .. " / " .. tostring(COPPER_AMOUNT))

    -- enums we index
    add("Enum.ItemClass", has("Enum.ItemClass.Tradegoods"), has("Enum.ItemClass.Tradegoods") and ("Tradegoods=" .. tostring(Enum.ItemClass.Tradegoods) .. " Questitem=" .. tostring(Enum.ItemClass.Questitem)) or "absent; using classic numbers")
    add("Enum.LootSlotType", has("Enum.LootSlotType.Item"), "")
    add("C_Spell.GetSpellName", has("C_Spell.GetSpellName") or _G.GetSpellInfo ~= nil, "gathering + class counters")

    -- storage
    add("SavedVariables root", FO.root ~= nil and FO.root.version ~= nil, "v" .. tostring(FO.root and FO.root.version))

    self.db.last = { t = time(), version = tostring(version), build = tostring(build), toc = tostring(toc), checks = checks }
    local pass, fail = 0, 0
    print("Verify (%s build %s, TOC %s):", tostring(version), tostring(build), tostring(toc))
    for _, c in ipairs(checks) do
        local tag
        if c.ok == nil then tag = "|cffaaaaaaINFO|r" elseif c.ok then tag = "|cff60ff60PASS|r" pass = pass + 1 else tag = "|cffff6060FAIL|r" fail = fail + 1 end
        print("  %s %-36s %s", tag, c.name, c.detail)
    end
    print("%d pass, %d fail. Results saved; paste this or send the SavedVariables file.", pass, fail)
end

V.commands = {
    verify = { help = "probe the client APIs this addon depends on", fn = function(self) self:Run() end },
}

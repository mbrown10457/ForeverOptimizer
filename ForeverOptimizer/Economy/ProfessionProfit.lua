local ADDON, FO = ...
local U = FO.Util
local print = FO:Printer("Economy")

-- ===========================================================================
-- Profession profit: records recipes whenever a profession window is open,
-- then prices reagents (AH or vendor buy) against output value (AH net of
-- cut or vendor sell). Also finds the cheapest guaranteed skill-ups.
-- ===========================================================================
local PR = FO:NewModule("Economy.ProfessionProfit", {
    account = "recipes",
    defaults = { professions = {}, settings = { sellThrough = 1.0 } },   -- sellThrough: fraction of AH-valued output you expect to actually sell   -- [prof][recipeID] = { name, output, qmin, qmax, learned, difficulty, reagents = {{id,qty}}, t }
})

local TS = C_TradeSkillUI
local BASIC = Enum and Enum.CraftingReagentType and Enum.CraftingReagentType.Basic
local DIFF = { [0] = "orange", [1] = "yellow", [2] = "green", [3] = "gray" }

local function ProfessionName()
    if not TS then return nil end
    if TS.GetBaseProfessionInfo then
        local ok, info = pcall(TS.GetBaseProfessionInfo)
        if ok and info and info.professionName then return U.Str(info.professionName) end
    end
    if TS.GetTradeSkillLine then
        local ok, _, name = pcall(TS.GetTradeSkillLine)
        if ok and name then return U.Str(name) end
    end
    return nil
end

function PR:Capture()
    if not TS or not TS.GetAllRecipeIDs then return end
    local prof = ProfessionName()
    if not prof then return end
    local ids = TS.GetAllRecipeIDs()
    if not ids then return end
    local book = self.db.professions[prof] or {}
    self.db.professions[prof] = book
    local n, now = 0, time()
    for _, recipeID in ipairs(ids) do
        local info = TS.GetRecipeInfo and TS.GetRecipeInfo(recipeID)
        local okS, sch = pcall(TS.GetRecipeSchematic, recipeID, false)
        if info and okS and sch and sch.outputItemID then
            local reagents = {}
            for _, slot in ipairs(sch.reagentSlotSchematics or {}) do
                local isBasic = (BASIC == nil) or (slot.reagentType == BASIC)
                local r = slot.reagents and slot.reagents[1]
                if isBasic and r and r.itemID then reagents[#reagents + 1] = { id = U.Num(r.itemID), qty = U.Num(slot.quantityRequired) or 1 } end
            end
            book[recipeID] = { name = U.Str(info.name) or U.Str(sch.name) or ("recipe " .. recipeID), output = U.Num(sch.outputItemID),
                               qmin = U.Num(sch.quantityMin) or 1, qmax = U.Num(sch.quantityMax) or 1, learned = info.learned == true,
                               difficulty = U.Num(info.relativeDifficulty), reagents = reagents, t = now }
            n = n + 1
        end
    end
    print("%s: %d recipes recorded.", prof, n)
end

local function Evaluate(rec)
    local cost, unknown = 0, 0
    for _, r in ipairs(rec.reagents) do
        local c = U.ItemCost(r.id)
        if c then cost = cost + c * r.qty else unknown = unknown + 1 end
    end
    local unitValue, vsrc = U.ItemValue(rec.output)
    if vsrc == "ah" then unitValue = unitValue * (PR.db.settings.sellThrough or 1) end
    local value = unitValue * (rec.qmin + rec.qmax) / 2
    return cost, value, value - cost, unknown, vsrc
end

function PR:ResolveProf(arg)
    if arg and arg ~= "" then
        for name in pairs(self.db.professions) do if name:lower():find(arg:lower(), 1, true) then return name end end
        return nil
    end
    return (U.Keys(self.db.professions))[1]
end

function PR:Report(arg, onlyLearned)
    local prof = self:ResolveProf(arg)
    if not prof then print("no professions recorded. Open a profession window first.") return end
    local rows = {}
    for _, rec in pairs(self.db.professions[prof]) do
        if not onlyLearned or rec.learned then
            local cost, value, margin, unknown, vsrc = Evaluate(rec)
            if unknown == 0 and value > 0 then rows[#rows + 1] = { rec = rec, cost = cost, value = value, margin = margin, vsrc = vsrc, pct = cost > 0 and margin / cost * 100 or 0 } end
        end
    end
    table.sort(rows, function(a, b) return a.margin > b.margin end)
    print("%s: margins (%d priced recipes; value = AH net of %d%% cut, or vendor):", prof, #rows, U.AH_CUT * 100)
    for i = 1, math.min(15, #rows) do
        local r = rows[i]
        print("  %-30s cost %-9s value %-9s %s%s|r (%+.0f%%)%s", U.Trunc(r.rec.name, 30), U.FormatMoney(r.cost), U.FormatMoney(r.value),
              r.margin >= 0 and "|cff60ff60" or "|cffff6060", U.FormatMoney(r.margin), r.pct, r.vsrc == "vendor" and " (vendor)" or "")
    end
    if #rows > 15 then print("  ... worst: %s at %s", rows[#rows].rec.name, U.FormatMoney(rows[#rows].margin)) end
end

function PR:SkillUp(arg)
    local prof = self:ResolveProf(arg)
    if not prof then print("no profession recorded.") return end
    local rows = {}
    for _, rec in pairs(self.db.professions[prof]) do
        if rec.learned and rec.difficulty and rec.difficulty <= 1 then
            local cost, value, _, unknown = Evaluate(rec)
            if unknown == 0 then
                local chance = rec.difficulty == 0 and 1.0 or 0.6
                rows[#rows + 1] = { rec = rec, cost = cost, net = cost - value, perPoint = (cost - value) / chance }
            end
        end
    end
    table.sort(rows, function(a, b) return a.perPoint < b.perPoint end)
    print("%s: cheapest skill-ups (net cost per point after selling the output):", prof)
    for i = 1, math.min(10, #rows) do
        local r = rows[i]
        print("  %-30s %-7s cost %-9s net %-9s per point %s", U.Trunc(r.rec.name, 30), DIFF[r.rec.difficulty] or "?", U.FormatMoney(r.cost), U.FormatMoney(r.net), U.FormatMoney(r.perPoint))
    end
end

function PR:Detail(arg)
    local needle = (arg or ""):lower()
    for prof, book in pairs(self.db.professions) do
        for _, rec in pairs(book) do
            if rec.name:lower():find(needle, 1, true) then
                local _, _, margin, unknown = Evaluate(rec)
                print("%s [%s] -> %s x%g-%g  margin %s", rec.name, prof, U.ItemName(rec.output), rec.qmin, rec.qmax, U.FormatMoney(margin))
                for _, r in ipairs(rec.reagents) do
                    local c, src = U.ItemCost(r.id)
                    print("  %2d x %-28s %s%s", r.qty, U.Trunc(U.ItemName(r.id), 28), c and U.FormatMoney(c) or "unknown", src and (" (" .. src .. ")") or "")
                end
                if unknown > 0 then print("  %d reagent(s) unpriced: visit a vendor that sells them or /fo scan.", unknown) end
                return
            end
        end
    end
    print("no recipe matching '%s'", arg)
end

PR.events = {
    TRADE_SKILL_SHOW = function(self) C_Timer.After(1, function() self:Capture() end) end,
}
function PR:OnInit() self.events.TRADE_SKILL_LIST_UPDATE = U.Debounce(2, function() self:Capture() end) end

PR.commands = {
    craft = { help = "[prof] | all [prof] | skillup [prof] | info <recipe> | capture | sellthrough <0-1>", fn = function(self, arg)
        local sub, rest = U.SplitCmd(arg)
        if sub == "all" then self:Report(rest, false)
        elseif sub == "skillup" then self:SkillUp(rest)
        elseif sub == "info" then self:Detail(rest)
        elseif sub == "capture" then self:Capture()
        elseif sub == "sellthrough" then
            local f = tonumber(rest)
            if f and f > 0 and f <= 1 then self.db.settings.sellThrough = f end
            print("sell-through assumption for AH-valued output: %.0f%%", (self.db.settings.sellThrough or 1) * 100)
        else self:Report(arg, true) end
    end },
}

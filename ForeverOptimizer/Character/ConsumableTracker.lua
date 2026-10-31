local ADDON, FO = ...
local U = FO.Util
local print = FO:Printer("Character")

-- ===========================================================================
-- What consumables cost you and whether they pay off. Consumption is
-- detected as consumable-class stacks shrinking while no town window is
-- open. "Buffed" time is when a buff matching the patterns is up; xp/hr and
-- gold/hr are split by that flag so you can see the uplift against the cost.
-- ===========================================================================
local CT = FO:NewModule("Character.ConsumableTracker", {
    account = "consumables",
    defaults = { used = {}, settings = { buffPatterns = { "Well Fed", "Elixir", "Scroll of", "Blessing of", "Mark of the Wild", "Power Word: Fortitude", "Arcane Intellect" } } },
})

local ItemClass = Enum and Enum.ItemClass or {}
local CLASS_CONSUMABLE = ItemClass.Consumable or 0
local C = C_Container
local NUM_BAGS = NUM_BAG_SLOTS or 4
local snapshot = nil
local buffed = false
local acc = { buffed = { t = 0, xp = 0, gold = 0 }, plain = { t = 0, xp = 0, gold = 0 } }

local function CountConsumables()
    local counts = {}
    for bag = 0, NUM_BAGS do
        local n = C and C.GetContainerNumSlots and U.Num(C.GetContainerNumSlots(bag)) or 0
        for slot = 1, n do
            local info = C.GetContainerItemInfo and C.GetContainerItemInfo(bag, slot)
            local itemID = info and U.Num(info.itemID)
            if itemID then
                local classID = U.ItemInstant(itemID)
                if classID == CLASS_CONSUMABLE then counts[itemID] = (counts[itemID] or 0) + (U.Num(info.stackCount) or 1) end
            end
        end
    end
    return counts
end

function CT:Diff()
    local now = CountConsumables()
    if snapshot and not FO:AnyTownFrame() then
        for itemID, had in pairs(snapshot) do
            local have = now[itemID] or 0
            if have < had then
                local used = had - have
                local cost = U.ItemCost(itemID) or U.VendorSell(itemID) * 4 -- unknown: vendor markup guess
                local u = self.db.used[itemID]
                if not u then u = { n = 0, cost = 0 } self.db.used[itemID] = u end
                u.n, u.cost = u.n + used, u.cost + cost * used
                local live = FO.Session:Live()
                if live then live.consumables = live.consumables + cost * used end
                FO:Fire("FO_CONSUMED", itemID, used, cost)
            end
        end
    end
    snapshot = now
end

local function IsBuffed()
    for _, name in ipairs(U.PlayerBuffNames()) do
        for _, p in ipairs(CT.db.settings.buffPatterns) do if name:find(p, 1, true) then return true end end
    end
    return false
end

function CT:OnTick(now)
    if math.floor(now) % 5 == 0 then buffed = IsBuffed() end
    local a = FO.Session:Activity()
    if FO.Session.PRODUCTIVE[a] then
        local b = buffed and acc.buffed or acc.plain
        b.t = b.t + 1
    end
end

CT.messages = {
    FO_XP = function(self, delta) local b = buffed and acc.buffed or acc.plain b.xp = b.xp + delta end,
    FO_MONEY = function(self, delta, ctx) if ctx == "loot" or ctx == "sale" then local b = buffed and acc.buffed or acc.plain b.gold = b.gold + delta end end,
}

function CT:OnEnable()
    snapshot = CountConsumables()
    FO:RegisterEvent("BAG_UPDATE_DELAYED", U.Debounce(1.5, function() self:Diff() end))
end

CT.commands = {
    consumables = { help = "consumable spend and buffed vs unbuffed rates", fn = function(self)
        local st = FO.Session:Stats()
        print("Consumables this session: %s (%s/hr). Lifetime:", U.FormatMoney(st.consumables), U.FormatMoney(st.consumables / math.max(st.elapsed, 60) * 3600))
        local rows = {}
        for id, u in pairs(self.db.used) do rows[#rows + 1] = { id = id, n = u.n, cost = u.cost } end
        table.sort(rows, function(a, b) return a.cost > b.cost end)
        for i = 1, math.min(10, #rows) do print("  x%-5d %-30s %s", rows[i].n, U.Trunc(U.ItemName(rows[i].id), 30), U.FormatMoney(rows[i].cost)) end
        local bx, px = U.PerHour(acc.buffed.xp, acc.buffed.t, 120), U.PerHour(acc.plain.xp, acc.plain.t, 120)
        local bg, pg = U.PerHour(acc.buffed.gold, acc.buffed.t, 120), U.PerHour(acc.plain.gold, acc.plain.t, 120)
        print("Buffed   %s fighting: %s xp/hr, %s gold/hr", U.FormatDuration(acc.buffed.t), U.Rate(bx), bg and U.ShortMoney(bg) or "--")
        print("Unbuffed %s fighting: %s xp/hr, %s gold/hr", U.FormatDuration(acc.plain.t), U.Rate(px), pg and U.ShortMoney(pg) or "--")
        if bx and px and px > 0 then
            local uplift = (bx - px) / px * 100
            local costPerHour = st.consumables / math.max(st.elapsed, 60) * 3600
            local gphPlain = pg or 0
            print("Uplift %+.0f%% xp/hr. Consumables cost %s/hr%s.", uplift, U.FormatMoney(costPerHour),
                  gphPlain > 0 and string.format(" = %.0f%% of your unbuffed gold/hr", costPerHour / gphPlain * 100) or "")
            print(uplift > 15 and "Verdict: worth it for leveling speed." or uplift > 5 and "Verdict: marginal; buy cheap ones only." or "Verdict: not paying off; skip unless the fight needs it.")
        else
            print("Need ~2 min each of buffed and unbuffed fighting for a verdict.")
        end
        print("Buff patterns: %s  (/fo consumables is read-only; edit patterns in saved vars for now)", table.concat(self.db.settings.buffPatterns, ", "))
    end },
}

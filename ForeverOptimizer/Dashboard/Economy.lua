local ADDON, FO = ...
local U = FO.Util

FO.Dashboard:RegisterTab("Economy", 3, function()
    local st = FO.Session:Stats()
    if not st then return { "no session" } end
    local out = {
        string.format("Loot %s  quests %s  vendor %s", U.ShortMoney(st.lootGold), U.ShortMoney(st.questGold), U.ShortMoney(st.vendorSales)),
        string.format("Repairs %s  buys %s  train %s", U.ShortMoney(st.repairs), U.ShortMoney(st.purchases), U.ShortMoney(st.training)),
        string.format("Bags: AH %s  vendor %s  (%d items)", U.ShortMoney(st.ahEst), U.ShortMoney(st.vendorEst), st.items),
        string.format("Net %s/hr  Eff %s/hr", st.gph and U.ShortMoney(st.gph) or "--", st.egph and U.ShortMoney(st.egph) or "--"),
    }
    local IO = FO:GetModule("Economy.InventoryOptimizer")
    if IO then
        local free, total = IO:FreeSlots()
        out[#out + 1] = string.format("Slots %d/%d free%s", free, total, free <= 3 and " |cffff6060LOW|r" or "")
    end
    local PH = FO:GetModule("Economy.PriceHistory")
    if PH then
        local items = U.Count(PH.db.prices)
        local AS = FO:GetModule("Economy.AuctionHouseScanner")
        local last = AS and AS.db.scans[#AS.db.scans]
        out[#out + 1] = string.format("AH: %d items priced%s", items, last and (", scan " .. U.FormatDuration(time() - last.t) .. " ago") or ", no scan yet")
        local movers = PH:Movers(nil, 2)
        for _, m in ipairs(movers) do out[#out + 1] = string.format("%s%+.0f%%|r %s %s", m.change >= 0 and "|cff60ff60" or "|cffff6060", m.change, U.Trunc(m.name, 16), U.ShortMoney(m.latest)) end
    end
    if st.consumables > 0 then out[#out + 1] = string.format("Consumables %s (%s/hr)", U.ShortMoney(st.consumables), U.ShortMoney(st.consumables / math.max(st.elapsed, 60) * 3600)) end
    return out
end)

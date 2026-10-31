local ADDON, FO = ...
local U = FO.Util
local print = FO:Printer("Economy")

-- ===========================================================================
-- Full scans via ReplicateItems (server-throttled, ~15 min) plus passive
-- capture of anything you browse. Retail-style C_AuctionHouse; if Forever
-- ships the classic list AH this is the file that changes.
-- ===========================================================================
local AS = FO:NewModule("Economy.AuctionHouseScanner", {
    account = "ahscan",
    defaults = { settings = { autoScan = false }, scans = {} },
})

local AH = C_AuctionHouse
local scanStarted

function AS:StartFullScan()
    if not FO.state.frames.auction then print("open the auction house first.") return end
    if not AH or not AH.ReplicateItems then print("C_AuctionHouse.ReplicateItems not available on this client.") return end
    scanStarted = debugprofilestop()
    print("full scan requested...")
    AH.ReplicateItems()
end

local function OnReplicateDone()
    local PH = FO:GetModule("Economy.PriceHistory")
    if not AH.GetNumReplicateItems then return end
    local n = U.Num(AH.GetNumReplicateItems()) or 0
    local acc, missing = {}, 0
    for i = 0, n - 1 do
        local name, _, count, _, _, _, _, _, _, buyout, _, _, _, _, _, _, itemID = AH.GetReplicateItemInfo(i)
        itemID = U.Num(itemID) or U.ItemIDFromLink(AH.GetReplicateItemLink and AH.GetReplicateItemLink(i))
        count, buyout = U.Num(count) or 1, U.Num(buyout) or 0
        if itemID and buyout > 0 then
            local unit = buyout / count
            local a = acc[itemID]
            if not a then a = { name = U.Str(name), min = unit, qty = 0, n = 0 } acc[itemID] = a end
            if unit < a.min then a.min = unit end
            a.qty, a.n = a.qty + count, a.n + 1
        elseif not itemID then missing = missing + 1 end
    end
    local now, items = time(), 0
    for itemID, a in pairs(acc) do PH:Observe(itemID, a.name, math.floor(a.min + 0.5), a.qty, a.n, now) items = items + 1 end
    local ms = scanStarted and (debugprofilestop() - scanStarted) or 0
    U.Push(AS.db.scans, { t = now, items = items, auctions = n, ms = math.floor(ms) }, 100)
    print("scan done: %d auctions, %d items, %d unreadable, %.1fs", n, items, missing, ms / 1000)
    FO:Fire("FO_AH_SCAN", items, n)
end

local function OnCommodityResults(itemID)
    local PH = FO:GetModule("Economy.PriceHistory")
    itemID = U.Num(itemID)
    if not itemID or not AH.GetNumCommoditySearchResults then return end
    local n = U.Num(AH.GetNumCommoditySearchResults(itemID)) or 0
    if n == 0 then return end
    local min, qty = nil, 0
    for i = 1, n do
        local r = AH.GetCommoditySearchResultInfo(itemID, i)
        if r then
            local price, q = U.Num(r.unitPrice), U.Num(r.quantity) or 0
            if price and (not min or price < min) then min = price end
            qty = qty + q
        end
    end
    if min then PH:Observe(itemID, U.ItemName(itemID), min, qty, n) end
end

local function OnItemResults(itemKey)
    local PH = FO:GetModule("Economy.PriceHistory")
    if not itemKey or not AH.GetNumItemSearchResults then return end
    local itemID = U.Num(itemKey.itemID)
    if not itemID then return end
    local n = U.Num(AH.GetNumItemSearchResults(itemKey)) or 0
    if n == 0 then return end
    local min, qty = nil, 0
    for i = 1, n do
        local r = AH.GetItemSearchResultInfo(itemKey, i)
        if r then
            local price, q = U.Num(r.buyoutAmount), U.Num(r.quantity) or 1
            if price and price > 0 and (not min or price < min) then min = price end
            qty = qty + q
        end
    end
    if min then PH:Observe(itemID, U.ItemName(itemID), min, qty, n) end
end

AS.events = {
    AUCTION_HOUSE_SHOW = function(self) if self.db.settings.autoScan then C_Timer.After(1, function() self:StartFullScan() end) end end,
    REPLICATE_ITEM_LIST_UPDATE = function() OnReplicateDone() end,
    COMMODITY_SEARCH_RESULTS_UPDATED = function(self, itemID) OnCommodityResults(itemID) end,
    ITEM_SEARCH_RESULTS_UPDATED = function(self, itemKey) OnItemResults(itemKey) end,
}

AS.commands = {
    scan = { help = "full AH scan (AH must be open)", fn = function(self) self:StartFullScan() end },
    autoscan = { help = "toggle full scan on AH open", fn = function(self)
        self.db.settings.autoScan = not self.db.settings.autoScan
        print("auto-scan on AH open: %s", tostring(self.db.settings.autoScan))
    end },
    ahstats = { help = "scan history", fn = function(self)
        local PH = FO:GetModule("Economy.PriceHistory")
        local items, points = 0, 0
        for _, s in pairs(PH.db.prices) do items = items + 1 points = points + #s end
        local last = self.db.scans[#self.db.scans]
        print("%d items, %d price points, %d scans, %d vendor prices.", items, points, #self.db.scans, U.Count(PH.db.vendor))
        if last then print("last scan %s ago: %d auctions / %d items", U.FormatDuration(time() - last.t), last.auctions, last.items) end
    end },
}

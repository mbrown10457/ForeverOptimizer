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

local scanStarted, classicPending
AS.seenShow = false

local function AH() return C_AuctionHouse end
local function HasRetail() local a = AH() return a and type(a.ReplicateItems) == "function" end
local function HasClassic() return type(QueryAuctionItems) == "function" and type(GetNumAuctionItems) == "function" end

-- The auction window counts as open when AUCTION_HOUSE_SHOW fired, or when either
-- auction frame the client might use is on screen (the event has not been seen on Forever yet).
local function AHOpen()
    if FO.state.frames.auction then return true, "AUCTION_HOUSE_SHOW" end
    for _, name in ipairs({ "AuctionHouseFrame", "AuctionFrame" }) do
        local f = _G[name]
        if type(f) == "table" and f.IsShown and f:IsShown() then return true, name end
    end
    return false
end

function AS:Diag()
    local frames = {}
    for _, name in ipairs({ "AuctionHouseFrame", "AuctionFrame" }) do
        local f = _G[name]
        frames[#frames + 1] = name .. (type(f) ~= "table" and " absent" or (f.IsShown and f:IsShown()) and " shown" or " hidden")
    end
    print("  auction API: retail ReplicateItems %s, classic QueryAuctionItems %s; AUCTION_HOUSE_SHOW %s this session; %s",
        HasRetail() and "present" or "absent", HasClassic() and "present" or "absent", self.seenShow and "fired" or "never fired", table.concat(frames, ", "))
end

-- One accumulator for both scan paths: acc[itemID] = { name, min unit price, qty, n }
local function Finish(acc, n, missing, how)
    local PH = FO:GetModule("Economy.PriceHistory")
    local now, items = time(), 0
    for itemID, a in pairs(acc) do PH:Observe(itemID, a.name, math.floor(a.min + 0.5), a.qty, a.n, now) items = items + 1 end
    local ms = scanStarted and (debugprofilestop() - scanStarted) or 0
    scanStarted = nil
    U.Push(AS.db.scans, { t = now, items = items, auctions = n, ms = math.floor(ms), how = how }, 100)
    print("scan done: %d auctions, %d items, %d unreadable, %.1fs (%s)", n, items, missing, ms / 1000, how)
    FO:Fire("FO_AH_SCAN", items, n)
end

local function Add(acc, name, count, buyout, itemID)
    count, buyout = U.Num(count) or 1, U.Num(buyout) or 0
    if count < 1 then count = 1 end   -- a zero stack would make the unit price infinite
    if not itemID then return false end
    if buyout > 0 then
        local unit = buyout / count
        local a = acc[itemID]
        if not a then a = { name = U.Str(name), min = unit, qty = 0, n = 0 } acc[itemID] = a end
        if unit < a.min then a.min = unit end
        a.qty, a.n = a.qty + count, a.n + 1
    end
    return true
end

function AS:StartFullScan()
    local open, how = AHOpen()
    if not open then
        print("auction window not detected; trying anyway.")
        self:Diag()
    end
    if HasRetail() then
        scanStarted = debugprofilestop()
        print("full scan requested (retail replicate)...")
        local ok, err = pcall(AH().ReplicateItems)
        if not ok then print("ReplicateItems failed: %s", tostring(err)) scanStarted = nil end
    elseif HasClassic() then
        local canQuery, canGetAll = true, true
        if CanSendAuctionQuery then canQuery, canGetAll = CanSendAuctionQuery() end
        if not canGetAll then print("the server's full-scan cooldown is running; try again in a few minutes (classic getAll, ~15 min).") return end
        scanStarted = debugprofilestop()
        classicPending = true
        print("full scan requested (classic getAll)...")
        local ok, err = pcall(QueryAuctionItems, "", nil, nil, 0, nil, nil, true)
        if not ok then print("QueryAuctionItems failed: %s", tostring(err)) classicPending = nil scanStarted = nil end
    else
        print("no auction house scan API on this client.")
        self:Diag()
    end
end

local function OnReplicateDone()
    local a = AH()
    if not (a and a.GetNumReplicateItems and a.GetReplicateItemInfo) then return end
    local n = U.Num(a.GetNumReplicateItems()) or 0
    local acc, missing = {}, 0
    for i = 0, n - 1 do
        local name, _, count, _, _, _, _, _, _, buyout, _, _, _, _, _, _, itemID = a.GetReplicateItemInfo(i)
        itemID = U.Num(itemID) or U.ItemIDFromLink(a.GetReplicateItemLink and a.GetReplicateItemLink(i))
        if not Add(acc, name, count, buyout, itemID) then missing = missing + 1 end
    end
    Finish(acc, n, missing, "replicate")
end

-- Classic list AH: a getAll query answers with one AUCTION_ITEM_LIST_UPDATE carrying every auction
local function OnClassicList()
    if not classicPending then return end
    local n = U.Num(GetNumAuctionItems("list")) or 0
    if n == 0 then return end
    classicPending = nil
    local acc, missing = {}, 0
    for i = 1, n do
        local name, _, count, _, _, _, _, _, _, buyout, _, _, _, _, _, _, itemID = GetAuctionItemInfo("list", i)
        itemID = U.Num(itemID) or U.ItemIDFromLink(GetAuctionItemLink and GetAuctionItemLink("list", i))
        if not Add(acc, name, count, buyout, itemID) then missing = missing + 1 end
    end
    Finish(acc, n, missing, "classic getAll")
end

local function OnCommodityResults(itemID)
    local PH = FO:GetModule("Economy.PriceHistory")
    local AH = C_AuctionHouse
    itemID = U.Num(itemID)
    if not AH or not itemID or not AH.GetNumCommoditySearchResults then return end
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
    local AH = C_AuctionHouse
    if not itemKey or not AH or not AH.GetNumItemSearchResults then return end
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
    AUCTION_HOUSE_SHOW = function(self) self.seenShow = true if self.db.settings.autoScan then C_Timer.After(1, function() self:StartFullScan() end) end end,
    REPLICATE_ITEM_LIST_UPDATE = function() OnReplicateDone() end,
    AUCTION_ITEM_LIST_UPDATE = function() OnClassicList() end,
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
        if last then print("last scan %s ago: %d auctions / %d items (%s)", U.FormatDuration(time() - last.t), last.auctions, last.items, last.how or "replicate") end
        self:Diag()
    end },
}

local ADDON, FO = ...
local U = FO.Util
local print = FO:Printer("Economy")

-- ===========================================================================
-- The market historian. Owns all price data and exposes FO.Prices for Util.
--
-- db.names[itemID]  = "name"
-- db.prices[itemID] = { {t, min, qty, n}, ... }        recent raw observations (newest last)
-- db.daily[itemID]  = { [yyyymmdd] = { lo, hi, sum, n } } compacted history
-- db.vendor[itemID] = { price, t, name }               vendor BUY price per unit
-- db.watch[itemID]  = copper                           alert at or below
-- ===========================================================================
local PH = FO:NewModule("Economy.PriceHistory", {
    account = "prices",
    defaults = { names = {}, prices = {}, daily = {}, vendor = {}, watch = {}, scans = {},
                 settings = { maxPoints = 120, rawDays = 3, maxAgeDays = 7, moverPct = 20 } },
})

local function Day(t) return tonumber(date("%Y%m%d", t)) end

FO.Prices = {
    AH = function(itemID)
        local s = PH.db.prices[itemID]
        if not s or #s == 0 then return nil end
        local pt = s[#s]
        if (time() - (pt.t or 0)) > PH.db.settings.maxAgeDays * 86400 then return nil end
        return pt.min, pt.n or 0
    end,
    VendorBuy = function(itemID)
        local v = PH.db.vendor[itemID]
        return v and v.price or nil
    end,
}

function PH:Observe(itemID, name, minUnit, qty, n, t)
    if not itemID or not minUnit or minUnit <= 0 then return end
    t = t or time()
    if name then self.db.names[itemID] = name end
    local series = self.db.prices[itemID]
    if not series then series = {} self.db.prices[itemID] = series end
    local point = { t = t, min = minUnit, qty = qty or 0, n = n or 0 }
    local lastp = series[#series]
    if lastp and math.abs(lastp.t - point.t) < 60 then series[#series] = point else table.insert(series, point) end
    while #series > self.db.settings.maxPoints do table.remove(series, 1) end
    -- daily compaction
    local d = Day(t)
    local days = self.db.daily[itemID]
    if not days then days = {} self.db.daily[itemID] = days end
    local dd = days[d]
    if not dd then dd = { lo = minUnit, hi = minUnit, sum = 0, n = 0 } days[d] = dd end
    dd.lo, dd.hi = math.min(dd.lo, minUnit), math.max(dd.hi, minUnit)
    dd.sum, dd.n = dd.sum + minUnit, dd.n + 1
    local alert = self.db.watch[itemID]
    if alert and minUnit <= alert then
        print("|cff60ff60WATCH|r %s at %s (alert <= %s)", name or self.db.names[itemID] or itemID, U.FormatMoney(minUnit), U.FormatMoney(alert))
    end
end

function PH:Latest(itemID) local s = self.db.prices[itemID] return s and s[#s] or nil end

-- Average of daily averages over N days, plus lo/hi and day count
function PH:Window(itemID, days)
    local d = self.db.daily[itemID]
    if not d then return nil end
    local cutoff = Day(time() - days * 86400)
    local lo, hi, sum, n, cnt = math.huge, 0, 0, 0, 0
    for day, r in pairs(d) do
        if day >= cutoff then lo = math.min(lo, r.lo) hi = math.max(hi, r.hi) sum = sum + r.sum / r.n n = n + 1 cnt = cnt + r.n end
    end
    if n == 0 then return nil end
    return { lo = lo, hi = hi, avg = sum / n, days = n, samples = cnt }
end

-- Movers: items whose latest price differs from their 7-day average by > pct
function PH:Movers(pct, limit)
    pct = pct or self.db.settings.moverPct
    local rows = {}
    for itemID, s in pairs(self.db.prices) do
        local latest = s[#s]
        local w = self:Window(itemID, 7)
        if latest and w and w.days >= 2 and (latest.n or 0) >= 2 then
            local change = (latest.min - w.avg) / w.avg * 100
            if math.abs(change) >= pct then rows[#rows + 1] = { itemID = itemID, name = self.db.names[itemID] or itemID, latest = latest.min, avg = w.avg, change = change, n = latest.n } end
        end
    end
    table.sort(rows, function(a, b) return math.abs(a.change) > math.abs(b.change) end)
    local out = {}
    for i = 1, math.min(limit or 15, #rows) do out[i] = rows[i] end
    return out
end

-- Flip candidates: (a) AH below vendor sell price, (b) AH far below its 7-day average
function PH:Flips(limit)
    local rows = {}
    for itemID, s in pairs(self.db.prices) do
        local latest = s[#s]
        if latest and (time() - latest.t) < 2 * 86400 then
            local vend = U.VendorSell(itemID)
            if vend > 0 and latest.min < vend then
                rows[#rows + 1] = { itemID = itemID, kind = "vendor", buy = latest.min, sell = vend, margin = vend - latest.min, qty = latest.qty, n = latest.n }
            else
                local w = self:Window(itemID, 7)
                if w and w.days >= 3 and latest.min < w.avg * 0.6 then
                    local net = w.avg * (1 - U.AH_CUT) - latest.min
                    if net > 0 then rows[#rows + 1] = { itemID = itemID, kind = "relist", buy = latest.min, sell = w.avg, margin = net, qty = latest.qty, n = latest.n, days = w.days } end
                end
            end
        end
    end
    table.sort(rows, function(a, b) return a.margin * math.min(a.qty or 1, 20) > b.margin * math.min(b.qty or 1, 20) end)
    local out = {}
    for i = 1, math.min(limit or 15, #rows) do out[i] = rows[i] end
    return out
end

function PH:ResolveItem(arg)
    if not arg or arg == "" then return nil end
    local id = tonumber(arg) or U.ItemIDFromLink(arg)
    if id then return id end
    local needle = arg:lower()
    for itemID, name in pairs(self.db.names) do if name and name:lower() == needle then return itemID end end
    for itemID, name in pairs(self.db.names) do if name and name:lower():find(needle, 1, true) then return itemID end end
    return nil
end

-- Prune daily history older than 60 days (keeps the file small)
function PH:OnEnable()
    local cutoff = Day(time() - 60 * 86400)
    for itemID, days in pairs(self.db.daily) do
        for day in pairs(days) do if day < cutoff then days[day] = nil end end
    end
end

-- Vendor buy prices seen at merchants
local function ScanMerchant()
    if not GetMerchantNumItems then return end
    local n = U.Num(GetMerchantNumItems()) or 0
    local now = time()
    for i = 1, n do
        local name, _, price, stack, _, _, _, extendedCost = GetMerchantItemInfo(i)
        local itemID = U.ItemIDFromLink(GetMerchantItemLink and GetMerchantItemLink(i))
        price, stack = U.Num(price), U.Num(stack) or 1
        if itemID and price and price > 0 and not extendedCost then
            PH.db.vendor[itemID] = { price = price / math.max(stack, 1), t = now, name = U.Str(name) }
            if name then PH.db.names[itemID] = PH.db.names[itemID] or U.Str(name) end
        end
    end
end

PH.events = {
    MERCHANT_SHOW = function() C_Timer.After(0.3, ScanMerchant) end,
    MERCHANT_UPDATE = U.Debounce(1, ScanMerchant),
}

PH.commands = {
    price = { help = "<item> — latest, 7d and 30d stats", fn = function(self, arg)
        local itemID = self:ResolveItem(arg)
        if not itemID then print("no data for '%s'", arg) return end
        local name = self.db.names[itemID] or U.ItemName(itemID)
        local latest = self:Latest(itemID)
        if not latest then print("%s: no AH observations", name) else
            print("%s (%d): %s  (%d auctions, %d qty, %s ago)", name, itemID, U.FormatMoney(latest.min), latest.n, latest.qty, U.FormatDuration(time() - latest.t))
        end
        for _, days in ipairs({ 7, 30 }) do
            local w = self:Window(itemID, days)
            if w then print("  %2dd: lo %s  avg %s  hi %s  (%d days, %d samples)", days, U.FormatMoney(w.lo), U.FormatMoney(w.avg), U.FormatMoney(w.hi), w.days, w.samples) end
        end
        local v = self.db.vendor[itemID]
        if v then print("  vendor sells for %s (%s)", U.FormatMoney(v.price), U.FormatDuration(time() - v.t) .. " ago") end
        print("  vendor buys for %s", U.FormatMoney(U.VendorSell(itemID)))
    end },
    movers = { help = "[pct] — items that moved vs their 7-day average", fn = function(self, arg)
        local rows = self:Movers(tonumber(arg))
        print("Movers (latest vs 7d avg):")
        for _, r in ipairs(rows) do
            print("  %s%+5.0f%%|r  %-28s %s (avg %s, %d auctions)", r.change >= 0 and "|cff60ff60" or "|cffff6060", r.change, U.Trunc(r.name, 28),
                  U.FormatMoney(r.latest), U.FormatMoney(r.avg), r.n)
        end
        if #rows == 0 then print("  nothing yet; needs at least two days of scans.") end
    end },
    watch = { help = "[<item> <price>] — alert when at/below price", fn = function(self, arg)
        local item, price = arg:match("^(.-)%s+(%S+)$")
        if not item then
            print("watching %d items:", U.Count(self.db.watch))
            for itemID, limit in pairs(self.db.watch) do print("  %s (%d) <= %s", self.db.names[itemID] or "?", itemID, U.FormatMoney(limit)) end
            print("usage: /fo watch <item> <price e.g. 12g50s>")
            return
        end
        local itemID = self:ResolveItem(item)
        local copper = U.ParseMoney(price)
        if not itemID then print("unknown item '%s'", item) return end
        if not copper or copper <= 0 then print("bad price '%s'", price) return end
        self.db.watch[itemID] = copper
        print("watching %s <= %s", self.db.names[itemID] or itemID, U.FormatMoney(copper))
    end },
    flips = { help = "auction opportunities: below vendor, or far below 7d average", fn = function(self)
        local rows = self:Flips(15)
        print("Flips (expected net margin per unit; relists assume you sell at the 7d average, minus %d%% cut):", U.AH_CUT * 100)
        for _, r in ipairs(rows) do
            print("  %-7s %-26s buy %s -> %s %s  |cff60ff60+%s|r each, %d listed%s", r.kind, U.Trunc(self.db.names[r.itemID] or U.ItemName(r.itemID), 26),
                  U.FormatMoney(r.buy), r.kind == "vendor" and "vendor" or "avg", U.FormatMoney(r.sell), U.FormatMoney(r.margin), r.qty or 0,
                  r.days and (" (" .. r.days .. "d history)") or "")
        end
        if #rows == 0 then print("  none right now. Needs recent scans; relists need 3+ days of history.") end
    end },
    unwatch = { help = "<item>", fn = function(self, arg)
        local itemID = self:ResolveItem(arg)
        if itemID and self.db.watch[itemID] then self.db.watch[itemID] = nil print("unwatched %d", itemID) else print("not watching '%s'", arg) end
    end },
}

local ADDON, FO = ...
local U = FO.Util
local print = FO:Printer("Economy")

-- ===========================================================================
-- Bags: classify (trash / quest / auction / material / keep / novalue),
-- auto-sell trash at vendors, warn when space runs low.
-- Bank & alts: snapshot bags and bank per character; find items anywhere.
-- ===========================================================================
local IO = FO:NewModule("Economy.InventoryOptimizer", {
    account = "inventory",
    char = "inventory",
    defaults = { settings = { autoSell = true, lowSlots = 3, auctionMin = 5000, auctionRatio = 1.5 }, keep = {} },
    cdefaults = { bags = {}, bank = {}, bagsAt = 0, bankAt = 0 },
})

local ItemClass = Enum and Enum.ItemClass or {}
local CLASS_TRADEGOODS = ItemClass.Tradegoods or 7
local CLASS_QUEST = ItemClass.Questitem or 12
local CLASS_REAGENT = ItemClass.Reagent or 5
local C = C_Container
local NUM_BAGS = NUM_BAG_SLOTS or 4

local function SlotInfo(bag, slot)
    if C and C.GetContainerItemInfo then
        local info = C.GetContainerItemInfo(bag, slot)
        if not info then return nil end
        return U.Num(info.itemID), U.Num(info.stackCount) or 1, U.Num(info.quality), info.hasNoValue == true, info.isBound == true
    end
    local _, count, _, quality, _, _, link, _, noValue, itemID = GetContainerItemInfo(bag, slot)
    return U.Num(itemID) or U.ItemIDFromLink(link), U.Num(count) or 1, U.Num(quality), noValue == true, false
end

local function NumSlots(bag)
    if C and C.GetContainerNumSlots then return U.Num(C.GetContainerNumSlots(bag)) or 0 end
    return U.Num(GetContainerNumSlots(bag)) or 0
end

function IO:FreeSlots()
    local free, total = 0, 0
    for bag = 0, NUM_BAGS do
        free = free + (C and C.GetContainerNumFreeSlots and U.Num(C.GetContainerNumFreeSlots(bag)) or 0)
        total = total + NumSlots(bag)
    end
    return free, total
end

function IO:Classify(itemID, quality, noValue, bound)
    local s = self.db.settings
    if self.db.keep[itemID] then return "keep", U.VendorSell(itemID), "vendor" end
    local classID = U.ItemInstant(itemID)
    if classID == CLASS_QUEST then return "quest", 0, nil end
    local value, src = U.ItemValue(itemID)
    local vend = U.VendorSell(itemID)
    if quality == 0 then return "trash", vend, "vendor" end
    if not bound and src == "ah" and value >= s.auctionMin and value >= vend * s.auctionRatio then return "auction", value, "ah" end
    if classID == CLASS_TRADEGOODS or classID == CLASS_REAGENT then return "material", value, src end
    if noValue and vend == 0 then return "novalue", 0, nil end
    return "keep", value, src
end

function IO:Scan()
    local out, totals, counts = {}, {}, {}
    for bag = 0, NUM_BAGS do
        for slot = 1, NumSlots(bag) do
            local itemID, count, quality, noValue, bound = SlotInfo(bag, slot)
            if itemID then
                local cat, value, src = self:Classify(itemID, quality, noValue, bound)
                out[cat] = out[cat] or {}
                table.insert(out[cat], { itemID = itemID, count = count, value = value, src = src, bag = bag, slot = slot })
                totals[cat] = (totals[cat] or 0) + value * count
                counts[itemID] = (counts[itemID] or 0) + count
            end
        end
    end
    self.cdb.bags, self.cdb.bagsAt = counts, time()
    return out, totals
end

-- Bank: every container id that isn't a regular bag. Enum.BagIndex covers both classic and retail layouts.
local function BankBags()
    local ids, seen = {}, {}
    local function add(id) if id and not seen[id] then seen[id] = true ids[#ids + 1] = id end end
    if Enum and Enum.BagIndex then
        for name, id in pairs(Enum.BagIndex) do
            if type(id) == "number" and (name:find("Bank") or name:find("bank")) then add(id) end
        end
    end
    add(BANK_CONTAINER or -1)
    for i = NUM_BAGS + 1, NUM_BAGS + (NUM_BANKBAGSLOTS or 7) do add(i) end
    return ids
end

function IO:ScanBank()
    local counts, slots = {}, 0
    for _, bag in ipairs(BankBags()) do
        local n = NumSlots(bag)
        for slot = 1, n do
            local itemID, count = SlotInfo(bag, slot)
            if itemID then counts[itemID] = (counts[itemID] or 0) + count slots = slots + 1 end
        end
    end
    self.cdb.bank, self.cdb.bankAt = counts, time()
    print("bank snapshot: %d stacks.", slots)
end

local merchantOpen = false
function IO:SellTrash(manual)
    if not merchantOpen then if manual then print("open a merchant first.") end return end
    local cats = self:Scan()
    local list = cats.trash or {}
    if #list == 0 then if manual then print("no trash to sell.") end return end
    local sold, total = 0, 0
    for _, e in ipairs(list) do
        if sold >= 12 then break end
        if C and C.UseContainerItem then C.UseContainerItem(e.bag, e.slot) else UseContainerItem(e.bag, e.slot) end
        sold, total = sold + 1, total + e.value * e.count
    end
    print("sold %d trash stacks for ~%s%s", sold, U.FormatMoney(total), #list > sold and string.format(" (%d more next visit)", #list - sold) or "")
end

local warned = false
function IO:CheckSpace()
    local free = self:FreeSlots()
    if free <= self.db.settings.lowSlots then
        if not warned then
            warned = true
            local cats, totals = self:Scan()
            FO:Alert("bags", "|cffff6060%d slots left.|r %d trash stacks (%s) can go; %d auction-worthy stacks (%s).", free,
                  #(cats.trash or {}), U.FormatMoney(totals.trash or 0), #(cats.auction or {}), U.FormatMoney(totals.auction or 0))
        end
    else warned = false end
end

function IO:Summary()
    local free, total = self:FreeSlots()
    local cats, totals = self:Scan()
    print("%d/%d slots free.", free, total)
    for _, cat in ipairs({ "trash", "auction", "material", "quest", "novalue", "keep" }) do
        local list = cats[cat]
        if list and #list > 0 then
            local units = 0
            for _, e in ipairs(list) do units = units + e.count end
            print("  %-9s %3d stacks  %4d items  worth %s  (%s per slot)", cat, #list, units, U.FormatMoney(totals[cat] or 0), U.FormatMoney((totals[cat] or 0) / #list))
        end
    end
end

function IO:ListCat(cat)
    local cats = self:Scan()
    local list = cats[cat]
    if not list or #list == 0 then print("nothing in '%s'.", cat) return end
    table.sort(list, function(a, b) return a.value * a.count > b.value * b.count end)
    print("%s (%d):", cat, #list)
    for i = 1, math.min(#list, 25) do
        local e = list[i]
        print("  x%-4d %-30s %s each%s  [%d]", e.count, U.Trunc(U.ItemName(e.itemID), 30), U.FormatMoney(e.value), e.src == "ah" and " (AH)" or "", e.itemID)
    end
end

-- Lowest value per slot: what to drop first when space runs out
function IO:Worst(n)
    local cats = self:Scan()
    local all = {}
    for cat, list in pairs(cats) do
        if cat ~= "quest" then for _, e in ipairs(list) do e.cat = cat all[#all + 1] = e end end
    end
    table.sort(all, function(a, b) return a.value * a.count < b.value * b.count end)
    print("Lowest value per slot (%d of %d stacks):", math.min(n, #all), #all)
    for i = 1, math.min(n, #all) do
        local e = all[i]
        print("  %-9s x%-4d %-28s %s", e.cat, e.count, U.Trunc(U.ItemName(e.itemID), 28), U.FormatMoney(e.value * e.count))
    end
end

-- Alts: find an item across every character's bags and bank
function IO:Find(arg)
    local PH = FO:GetModule("Economy.PriceHistory")
    local itemID = tonumber(arg) or U.ItemIDFromLink(arg) or (PH and PH:ResolveItem(arg))
    local needle = (arg or ""):lower()
    local hits = {}
    for charKey, inv in FO:EachChar("inventory") do
        for place, counts in pairs({ bags = inv.bags or {}, bank = inv.bank or {} }) do
            for id, n in pairs(counts) do
                if id == itemID or (not itemID and U.ItemName(id):lower():find(needle, 1, true)) then
                    hits[#hits + 1] = { char = charKey, place = place, id = id, n = n }
                end
            end
        end
    end
    if #hits == 0 then print("'%s' not found on any character.", arg) return end
    table.sort(hits, function(a, b) return a.n > b.n end)
    for _, h in ipairs(hits) do print("  %-24s %-5s x%-4d %s", h.char, h.place, h.n, U.ItemName(h.id)) end
end

-- Materials across the account, valued
function IO:Mats()
    local acc = {}
    for charKey, inv in FO:EachChar("inventory") do
        for _, counts in pairs({ inv.bags or {}, inv.bank or {} }) do
            for id, n in pairs(counts) do
                local classID = U.ItemInstant(id)
                if classID == CLASS_TRADEGOODS or classID == CLASS_REAGENT then
                    acc[id] = acc[id] or { n = 0, chars = {} }
                    acc[id].n = acc[id].n + n
                    acc[id].chars[charKey] = (acc[id].chars[charKey] or 0) + n
                end
            end
        end
    end
    local rows = {}
    for id, a in pairs(acc) do
        local v = U.ItemValue(id)
        rows[#rows + 1] = { id = id, n = a.n, value = v * a.n, chars = U.Count(a.chars) }
    end
    table.sort(rows, function(a, b) return a.value > b.value end)
    local total = 0
    for _, r in ipairs(rows) do total = total + r.value end
    print("Materials across %d characters, worth %s:", U.Count(FO.root.chars), U.FormatMoney(total))
    for i = 1, math.min(20, #rows) do print("  x%-5d %-30s %s on %d chars", rows[i].n, U.Trunc(U.ItemName(rows[i].id), 30), U.FormatMoney(rows[i].value), rows[i].chars) end
end

IO.events = {
    MERCHANT_SHOW = function(self) merchantOpen = true if self.db.settings.autoSell then C_Timer.After(0.5, function() self:SellTrash(false) end) end end,
    MERCHANT_CLOSED = function() merchantOpen = false end,
    BANKFRAME_OPENED = function(self) C_Timer.After(0.5, function() self:ScanBank() end) end,
    PLAYER_LOGOUT = function(self) self:Scan() end,
}
function IO:OnInit() self.events.BAG_UPDATE_DELAYED = U.Debounce(2, function() self:CheckSpace() end) end

IO.commands = {
    bags = { help = "[trash|auction|material|quest|worst|sell|autosell|keep <item>|min <price>|ratio <n>|low <n>]", fn = function(self, arg)
        local sub, rest = U.SplitCmd(arg)
        if sub == "" then self:Summary()
        elseif sub == "trash" or sub == "auction" or sub == "material" or sub == "quest" or sub == "keep" and rest == "" or sub == "novalue" then self:ListCat(sub)
        elseif sub == "sell" then self:SellTrash(true)
        elseif sub == "worst" then self:Worst(tonumber(rest) or 10)
        elseif sub == "autosell" then self.db.settings.autoSell = not self.db.settings.autoSell print("auto-sell trash: %s", tostring(self.db.settings.autoSell))
        elseif sub == "keep" then
            local id = tonumber(rest) or U.ItemIDFromLink(rest)
            if id then self.db.keep[id] = not self.db.keep[id] or nil print("%s %s", U.ItemName(id), self.db.keep[id] and "will never be sold" or "no longer protected") end
        elseif sub == "min" then local c = U.ParseMoney(rest) if c then self.db.settings.auctionMin = c print("auction minimum %s", U.FormatMoney(c)) end
        elseif sub == "ratio" then local r = tonumber(rest) if r then self.db.settings.auctionRatio = r print("auction ratio %.2f", r) end
        elseif sub == "low" then local n = tonumber(rest) if n then self.db.settings.lowSlots = n print("warn at %d free slots", n) end
        else print("usage: /fo bags [trash|auction|material|quest|novalue|sell|autosell|keep <item>|min <price>|ratio <n>|low <n>]") end
    end },
    find = { help = "<item> — search all characters' bags and bank", fn = function(self, arg) self:Find(arg) end },
    mats = { help = "materials across all characters", fn = function(self) self:Mats() end },
    bank = { help = "rescan bank (bank must be open)", fn = function(self) if FO.state.frames.bank then self:ScanBank() else print("open the bank first.") end end },
}

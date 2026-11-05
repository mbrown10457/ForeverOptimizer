local ADDON, FO = ...
local U = FO.Util
local print = FO:Printer("Economy")

-- ===========================================================================
-- Vendor, disenchant or auction? /fo advise <item> compares the three for one
-- item, /fo advise bags sweeps everything green or better in your bags, and a
-- tooltip line shows the same on hover. Vendor is the item's sell price, the
-- auction figure is the lowest listing from your own scans net of the cut,
-- and the disenchant figure is the expected value of the classic result table
-- (dust / essence / shard by quality and item level; armour favours dust,
-- weapons favour essence) priced from the same scans. Sure money wins unless
-- an alternative beats it by the margin, and disenchanting is only
-- recommended when this character's Enchanting is high enough.
-- ===========================================================================
local IA = FO:NewModule("Economy.ItemAdvisor", {
    account = "advisor",
    defaults = { settings = { tooltip = true, margin = 10, ahMaxAgeDays = 3 } },
})
FO.Advisor = IA

local ItemClass = Enum and Enum.ItemClass or {}
local CLASS_WEAPON = ItemClass.Weapon or 2
local CLASS_ARMOR = ItemClass.Armor or 4
local CLASS_QUEST = ItemClass.Questitem or 12
local SUB_FISHING_POLE = 20
local ENCHANTING_SKILL_LINE = 333

-- Uncommon (green), by item level bracket: { maxIlvl, dust, essence, shard }, each { itemID, lo, hi }.
-- Armour: 75% dust / 20% essence / 5% shard. Weapons: 75% essence / 20% dust / 5% shard.
-- The lowest bracket has no shard and splits 80 / 20.
local GREEN = {
    { 15, { 10940, 1, 2 }, { 10938, 1, 2 }, nil },
    { 20, { 10940, 2, 3 }, { 10939, 1, 2 }, { 10978, 1, 1 } },
    { 25, { 10940, 4, 6 }, { 10998, 1, 2 }, { 10978, 1, 1 } },
    { 30, { 11083, 1, 2 }, { 11082, 1, 2 }, { 11084, 1, 1 } },
    { 35, { 11083, 2, 5 }, { 11134, 1, 2 }, { 11138, 1, 1 } },
    { 40, { 11137, 1, 2 }, { 11135, 1, 2 }, { 11139, 1, 1 } },
    { 45, { 11137, 2, 5 }, { 11174, 1, 2 }, { 11177, 1, 1 } },
    { 50, { 11176, 1, 2 }, { 11175, 1, 2 }, { 11178, 1, 1 } },
    { 55, { 11176, 2, 5 }, { 16202, 1, 2 }, { 14343, 1, 1 } },
    { 60, { 16204, 1, 2 }, { 16203, 1, 2 }, { 14344, 1, 1 } },
    { 65, { 16204, 2, 5 }, { 16203, 2, 3 }, { 14344, 1, 1 } },
}
-- Rare (blue): one shard every time.
local BLUE = { { 25, 10978 }, { 30, 11084 }, { 35, 11138 }, { 40, 11139 }, { 45, 11177 }, { 50, 11178 }, { 55, 14343 }, { 65, 14344 } }
-- Epic (purple): several shards, then Nexus Crystals: { maxIlvl, itemID, lo, hi }.
local PURPLE = { { 45, 11177, 2, 4 }, { 50, 11178, 2, 4 }, { 55, 14343, 2, 4 }, { 60, 20725, 1, 1 }, { 80, 20725, 1, 2 } }
-- Enchanting skill needed to disenchant, by item level.
local SKILL = { { 20, 1 }, { 25, 25 }, { 30, 50 }, { 35, 75 }, { 40, 100 }, { 45, 125 }, { 50, 150 }, { 55, 175 }, { 60, 200 }, { 65, 225 } }
IA.GREEN, IA.BLUE, IA.PURPLE = GREEN, BLUE, PURPLE

local function Bracket(tbl, ilvl)
    for _, row in ipairs(tbl) do if ilvl <= row[1] then return row end end
    return tbl[#tbl]
end

function IA:SkillNeeded(ilvl)
    for _, row in ipairs(SKILL) do if ilvl <= row[1] then return row[2] end end
    return 275
end

-- This character's Enchanting rank, or nil without the profession.
function IA:EnchantSkill()
    local profs = FO.Player and FO.Player.professions
    if type(profs) == "table" then
        for name, p in pairs(profs) do
            if type(p) == "table" and (p.skillLine == ENCHANTING_SKILL_LINE or name == "Enchanting") then return p.rank or 0 end
        end
    end
    local skills = FO.Player and FO.Player.skills
    if type(skills) == "table" then
        for k, s in pairs(skills) do
            if type(s) == "table" and (k == "Enchanting" or s.name == "Enchanting") then return s.rank or 0 end
        end
    end
    return nil
end

-- Possible disenchant results: list of { itemID, lo, hi, p } most likely first, or nil and a reason.
function IA:Outcomes(classID, subclassID, quality, ilvl)
    if classID ~= CLASS_WEAPON and classID ~= CLASS_ARMOR then return nil, "not a weapon or armour" end
    if classID == CLASS_WEAPON and subclassID == SUB_FISHING_POLE then return nil, "fishing poles do not disenchant" end
    if not quality or quality < 2 then return nil, "only green or better disenchants" end
    if quality > 4 then return nil, "legendary and above do not disenchant" end
    ilvl = ilvl or 1
    if quality == 2 then
        local b = Bracket(GREEN, ilvl)
        local dust, ess, shard = b[2], b[3], b[4]
        local pDust, pEss = 0.75, 0.20
        if not shard then pDust, pEss = 0.80, 0.20 end
        if classID == CLASS_WEAPON then pDust, pEss = pEss, pDust end
        local out = {
            { itemID = dust[1], lo = dust[2], hi = dust[3], p = pDust },
            { itemID = ess[1], lo = ess[2], hi = ess[3], p = pEss },
        }
        if shard then out[#out + 1] = { itemID = shard[1], lo = shard[2], hi = shard[3], p = 0.05 } end
        table.sort(out, function(a, c) return a.p > c.p end)
        return out
    elseif quality == 3 then
        local b = Bracket(BLUE, ilvl)
        return { { itemID = b[2], lo = 1, hi = 1, p = 1 } }
    end
    local b = Bracket(PURPLE, ilvl)
    return { { itemID = b[2], lo = b[3], hi = b[4], p = 1 } }
end

-- Full assessment of one item. opts.bound marks it soulbound (no auction).
-- Returns { name, quality, ilvl, vendor, bound, ah = { min, n, qty, age, net, avg } | nil,
--           de = { outcomes, expected, lo, hi, need, skill, can, unpriced } | nil, deReason, best, why, bestValue }
function IA:Assess(itemID, opts)
    opts = opts or {}
    local name, quality, sell, classID, subclassID, _, bindType, link, _, ilvl = U.ItemInfo(itemID)
    if not name then return nil end
    local s = self.db.settings
    local r = { itemID = itemID, name = name, quality = quality or 1, ilvl = ilvl or 1, link = link, vendor = sell or 0, classID = classID }
    r.bound = opts.bound == true or bindType == 1
    r.quest = classID == CLASS_QUEST
    local PH = FO:GetModule("Economy.PriceHistory")
    local latest = PH and PH:Latest(itemID)
    if latest and (time() - (latest.t or 0)) <= (s.ahMaxAgeDays or 3) * 86400 then
        local w = PH:Window(itemID, 7)
        r.ah = { min = latest.min, n = latest.n or 0, qty = latest.qty or 0, age = time() - latest.t, net = math.floor(latest.min * (1 - U.AH_CUT)), avg = w and w.avg }
    end
    local outs, reason = self:Outcomes(classID, subclassID, quality, ilvl)
    if outs then
        local de = { outcomes = {}, expected = 0, lo = math.huge, hi = 0, need = self:SkillNeeded(ilvl or 1), unpriced = 0 }
        for _, o in ipairs(outs) do
            local v, src = U.ItemValue(o.itemID)
            if src ~= "ah" then de.unpriced = de.unpriced + 1 end
            local row = { itemID = o.itemID, name = U.ItemName(o.itemID), lo = o.lo, hi = o.hi, p = o.p, value = v, src = src, min = v * o.lo, max = v * o.hi }
            de.expected = de.expected + o.p * v * (o.lo + o.hi) / 2
            de.lo, de.hi = math.min(de.lo, row.min), math.max(de.hi, row.max)
            de.outcomes[#de.outcomes + 1] = row
        end
        if de.lo == math.huge then de.lo = 0 end
        de.expected = math.floor(de.expected + 0.5)
        de.priced = de.unpriced < #de.outcomes      -- with no scanned mat the figure is vendor copper, not a value
        if not de.priced then de.expected = 0 end
        de.skill = self:EnchantSkill()
        de.can = de.skill ~= nil and de.skill >= de.need
        r.de = de
    else
        r.deReason = reason
    end

    -- the call: sure money (vendor) loses only to a usable alternative that beats it by the margin
    local margin = 1 + (s.margin or 10) / 100
    local best, bestValue, why = "vendor", r.vendor, r.vendor > 0 and "sure money" or "worthless"
    local ahValue = (r.ah and not r.bound) and r.ah.net or 0
    local deValue = r.de and r.de.expected or 0
    if r.de and r.de.can and deValue > 0 and deValue > bestValue * margin then
        best, bestValue, why = "disenchant", deValue, string.format("expected mats %s beat the vendor", U.FormatMoney(deValue))
    end
    if ahValue > bestValue * margin then
        best, bestValue, why = "auction", ahValue, string.format("lowest listing %s with %d up, %s ago", U.FormatMoney(r.ah.min), r.ah.n, U.FormatDuration(r.ah.age))
    end
    if best == "vendor" and r.bound then why = "soulbound" .. (r.ah and ", auction not possible" or "") end
    if best == "vendor" and not r.ah and not r.bound and r.vendor > 0 then why = "no auction data; /fo scan at the AH" end
    if best ~= "disenchant" and r.de and not r.de.can and deValue > bestValue * margin then
        why = why .. string.format("; an enchanter (skill %d) would get about %s in mats", r.de.need, U.FormatMoney(deValue))
    end
    if r.de and not r.de.priced then why = why .. "; disenchant mats unpriced until an AH scan" end
    r.best, r.why, r.bestValue = best, why, bestValue
    return r
end

local QUALITY_NAME = { [0] = "gray", "white", "green", "blue", "purple", "orange" }
local BEST_COLOR = { vendor = "|cffffd100", disenchant = "|cffc080ff", auction = "|cff60ff60" }

function IA:Print(r)
    local color = BEST_COLOR[r.best] or "|cffffffff"
    print("%s (%s, ilvl %d%s): %s%s|r. %s", r.name, QUALITY_NAME[r.quality] or "?", r.ilvl, r.bound and ", soulbound" or "", color, r.best, r.why)
    print("  vendor      %s", U.FormatMoney(r.vendor))
    if r.ah then
        print("  auction     %s net (lowest %s, %d up, %d listed, %s ago%s)%s", U.FormatMoney(r.ah.net), U.FormatMoney(r.ah.min), r.ah.n, r.ah.qty,
              U.FormatDuration(r.ah.age), r.ah.avg and (", 7d avg " .. U.FormatMoney(r.ah.avg)) or "", r.bound and "  [soulbound: cannot list]" or "")
    else
        print("  auction     %s", r.bound and "soulbound, cannot list" or "no scan data (/fo scan with the auction house open)")
    end
    if r.de then
        local de = r.de
        if de.priced then
            print("  disenchant  ~%s expected, range %s to %s; needs Enchanting %d (you: %s)%s", U.FormatMoney(de.expected), U.FormatMoney(de.lo), U.FormatMoney(de.hi),
                  de.need, de.skill and tostring(de.skill) or "none", de.unpriced > 0 and string.format("; %d mat%s priced at vendor only", de.unpriced, de.unpriced > 1 and "s" or "") or "")
        else
            print("  disenchant  mats have no AH price yet (/fo scan); needs Enchanting %d (you: %s)", de.need, de.skill and tostring(de.skill) or "none")
        end
        for _, o in ipairs(de.outcomes) do
            print("    %3.0f%%  %-26s x%s  @ %s%s", o.p * 100, U.Trunc(o.name, 26), o.lo == o.hi and tostring(o.lo) or (o.lo .. "-" .. o.hi),
                  U.FormatMoney(o.value), o.src == "ah" and "" or " (no AH price)")
        end
    elseif r.deReason then
        print("  disenchant  no: %s", r.deReason)
    end
end

-- One-line summary for the tooltip and the bag sweep
function IA:Short(r)
    local parts = { "vendor " .. U.FormatMoney(r.vendor) }
    if r.ah and not r.bound then parts[#parts + 1] = "AH " .. U.FormatMoney(r.ah.net) end
    if r.de then parts[#parts + 1] = "DE " .. (r.de.priced and ("~" .. U.FormatMoney(r.de.expected)) or "?") .. (r.de.can and "" or "*") end
    return table.concat(parts, " | "), (BEST_COLOR[r.best] or "") .. r.best .. "|r"
end

local function BagItem(bag, slot)
    local C = C_Container
    if C and C.GetContainerItemInfo then
        local info = C.GetContainerItemInfo(bag, slot)
        if not info then return nil end
        return U.Num(info.itemID), U.Num(info.stackCount) or 1, U.Num(info.quality), info.isBound == true
    end
    if not GetContainerItemInfo then return nil end
    local _, count, _, quality, _, _, link, _, _, itemID = GetContainerItemInfo(bag, slot)
    return U.Num(itemID) or U.ItemIDFromLink(link), U.Num(count) or 1, U.Num(quality), false
end

local function NumSlots(bag)
    local C = C_Container
    if C and C.GetContainerNumSlots then return U.Num(C.GetContainerNumSlots(bag)) or 0 end
    return GetContainerNumSlots and (U.Num(GetContainerNumSlots(bag)) or 0) or 0
end

-- Every green-or-better item in the bags, assessed and sorted by what the best choice is worth
function IA:Bags(minQuality)
    minQuality = minQuality or 2
    local rows = {}
    for bag = 0, (NUM_BAG_SLOTS or 4) do
        for slot = 1, NumSlots(bag) do
            local itemID, count, quality, bound = BagItem(bag, slot)
            if itemID and (quality or 0) >= minQuality then
                local r = self:Assess(itemID, { bound = bound })
                if r and not r.quest then r.count = count rows[#rows + 1] = r end
            end
        end
    end
    table.sort(rows, function(a, b) return a.bestValue * a.count > b.bestValue * b.count end)
    return rows
end

function IA:PrintBags()
    local rows = self:Bags(2)
    if #rows == 0 then print("advise: nothing green or better in your bags.") return end
    local totals = {}
    for _, r in ipairs(rows) do totals[r.best] = (totals[r.best] or 0) + r.bestValue * r.count end
    print("Bags, green and better (%d): vendor %s, disenchant %s, auction %s", #rows, U.FormatMoney(totals.vendor or 0), U.FormatMoney(totals.disenchant or 0), U.FormatMoney(totals.auction or 0))
    for i = 1, math.min(#rows, 25) do
        local r = rows[i]
        local figures = self:Short(r)
        print("  %s%-11s|r x%-3d %-28s %s", BEST_COLOR[r.best] or "", r.best, r.count, U.Trunc(r.name, 28), figures)
    end
    if #rows > 25 then print("  ... %d more", #rows - 25) end
    local unable = false
    for _, r in ipairs(rows) do if r.de and not r.de.can then unable = true break end end
    if unable then print("  * disenchant value shown for an enchanter; this character cannot disenchant it.") end
    for _, r in ipairs(rows) do if r.de and not r.de.priced then print("  DE ? means the mats have no AH price yet; /fo scan with the auction house open.") break end end
end

local function Hook()
    if not (TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType) then return false end
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip)
        if not IA.db.settings.tooltip then return end
        if tooltip ~= GameTooltip and tooltip ~= ItemRefTooltip then return end
        if not tooltip.GetItem then return end
        local _, link = tooltip:GetItem()
        local itemID = U.ItemIDFromLink(link)
        if not itemID then return end
        local r = IA:Assess(itemID)
        if not r or r.quest or (r.vendor == 0 and not r.ah and not r.de) then return end
        local figures, best = IA:Short(r)
        tooltip:AddLine(string.format("FO: %s  -> %s", figures, best), 0.8, 0.8, 0.8)
    end)
    return true
end

function IA:OnEnable()
    self.hooked = Hook()
end

function IA:Resolve(arg)
    arg = U.Str(arg)
    if not arg then return nil end
    local id = U.ItemIDFromLink(arg) or tonumber(arg)
    if id then return id end
    local PH = FO:GetModule("Economy.PriceHistory")
    id = PH and PH:ResolveItem(arg)
    if id then return id end
    local S = FO.Seed
    if S and S.Find then
        local ids = S.Find(arg, 1)
        if ids and ids[1] then return ids[1] end
    end
    return nil
end

IA.commands = {
    advise = { help = "<item> | bags | tooltip | margin <pct> — vendor, disenchant or auction?", fn = function(self, arg)
        local sub, rest = U.SplitCmd(arg or "")
        if sub == "" or sub == "bags" then self:PrintBags()
        elseif sub == "tooltip" then
            self.db.settings.tooltip = not self.db.settings.tooltip
            print("advise tooltip line: %s", self.db.settings.tooltip and "on" or "off")
        elseif sub == "margin" then
            local n = tonumber(rest)
            if n and n >= 0 and n <= 100 then self.db.settings.margin = n print("an alternative must beat the vendor by %d%% to be recommended.", n) else print("margin <0-100>") end
        else
            local id = self:Resolve(arg)
            local r = id and self:Assess(id)
            if not r then print("advise: unknown item '%s'. Shift-click an item, or give its id or name.", tostring(arg)) return end
            self:Print(r)
        end
    end },
}

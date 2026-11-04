local ADDON, FO = ...
local U = {}
FO.Util = U

-- ===========================================================================
-- Secret-value guards (Midnight / Forever addon restrictions)
-- ===========================================================================
local issecret = _G.issecretvalue

function U.IsSecret(v) return issecret ~= nil and issecret(v) == true end

function U.Num(v)
    if v == nil or U.IsSecret(v) then return nil end
    if type(v) == "number" then return v end
    return tonumber(v)
end

function U.Str(v)
    if v == nil or U.IsSecret(v) then return nil end
    if type(v) == "string" then return v end
    return tostring(v)
end

function U.Bool(v)
    if v == nil or U.IsSecret(v) then return nil end
    return v == true
end

function U.Restricted()
    local R = _G.C_RestrictedActions
    if R and R.IsAddOnRestrictionActive then
        local types = Enum and Enum.AddOnRestrictionType
        if type(types) == "table" then
            for _, v in pairs(types) do
                local ok, res = pcall(R.IsAddOnRestrictionActive, v)
                if ok and res == true then return true end
            end
        else
            local ok, res = pcall(R.IsAddOnRestrictionActive)
            if ok then return res == true end
        end
    end
    return InCombatLockdown()
end

-- ===========================================================================
-- GUIDs. Creature-0-serverID-instanceID-zoneUID-npcID-spawnUID
-- Forever obfuscates serverID / spawnUID; npcID is still readable.
-- ===========================================================================
function U.ParseGUID(guid)
    if type(guid) ~= "string" then return nil end
    local unitType, _, _, _, _, e = strsplit("-", guid)
    if unitType == "Creature" or unitType == "Vehicle" or unitType == "Pet" or unitType == "GameObject" then
        return unitType, tonumber(e)
    end
    return unitType, nil
end

function U.NpcIDFromGUID(guid)
    local t, id = U.ParseGUID(guid)
    if t == "Creature" or t == "Vehicle" then return id end
    return nil
end

function U.ObjectIDFromGUID(guid)
    local t, id = U.ParseGUID(guid)
    if t == "GameObject" then return id end
    return nil
end

-- ===========================================================================
-- Formatting
-- ===========================================================================
function U.FormatMoney(copper)
    copper = U.Num(copper)
    if not copper then return "?" end
    local neg = copper < 0
    copper = math.abs(math.floor(copper + 0.5))
    local g = math.floor(copper / 10000)
    local s = math.floor((copper % 10000) / 100)
    local c = copper % 100
    local out
    if g > 0 then out = string.format("%dg %02ds %02dc", g, s, c)
    elseif s > 0 then out = string.format("%ds %02dc", s, c)
    else out = string.format("%dc", c) end
    return (neg and "-" or "") .. out
end

-- Compact money for HUD: 12.3g / 45s / 8c
function U.ShortMoney(copper)
    copper = U.Num(copper)
    if not copper then return "?" end
    local neg = copper < 0 and "-" or ""
    copper = math.abs(copper)
    if copper >= 10000 then return string.format("%s%.1fg", neg, copper / 10000) end
    if copper >= 100 then return string.format("%s%ds", neg, math.floor(copper / 100)) end
    return string.format("%s%dc", neg, math.floor(copper))
end

function U.FormatDuration(sec)
    sec = U.Num(sec)
    if not sec or sec < 0 or sec ~= sec then return "--:--" end
    if sec > 1e8 then return "forever" end
    sec = math.floor(sec)
    local h = math.floor(sec / 3600)
    local m = math.floor((sec % 3600) / 60)
    local s = sec % 60
    if h > 0 then return string.format("%d:%02d:%02d", h, m, s) end
    return string.format("%02d:%02d", m, s)
end

function U.Round(n, places)
    n = U.Num(n)
    if not n then return nil end
    local mult = 10 ^ (places or 0)
    return math.floor(n * mult + 0.5) / mult
end

function U.PerHour(total, elapsedSec, minSec)
    total, elapsedSec = U.Num(total), U.Num(elapsedSec)
    if not total or not elapsedSec or elapsedSec < (minSec or 30) then return nil end
    return total / elapsedSec * 3600
end

function U.Rate(v, fmt) return v and string.format(fmt or "%.0f", v) or "--" end

-- Blizzard global string -> Lua pattern with captures (%s -> (.-), %d -> (%d+))
function U.GlobalStringToPattern(gs, anchorEnd)
    if type(gs) ~= "string" then return nil end
    local p = gs:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")
    p = p:gsub("%%%%s", "(.-)")
    p = p:gsub("%%%%d", "(%%d+)")
    p = p:gsub("%%%%%d%$s", "(.-)")
    p = p:gsub("%%%%%d%$d", "(%%d+)")
    return "^" .. p .. (anchorEnd and "$" or "")
end

-- "12g50s", "1250", "3g", "40s" -> copper or nil
function U.ParseMoney(s)
    s = U.Str(s)
    if not s then return nil end
    s = s:lower():gsub("%s+", "")
    local plain = tonumber(s)
    if plain then return math.floor(plain) end
    local g, sl, c = s:match("(%d+)g"), s:match("(%d+)s"), s:match("(%d+)c")
    if not g and not sl and not c then return nil end
    return (tonumber(g) or 0) * 10000 + (tonumber(sl) or 0) * 100 + (tonumber(c) or 0)
end

-- ===========================================================================
-- Position / world
-- ===========================================================================
function U.PlayerPosition()
    if not C_Map or not C_Map.GetBestMapForUnit then return nil end
    local mapID = C_Map.GetBestMapForUnit("player")
    if not mapID then return nil end
    local pos = C_Map.GetPlayerMapPosition(mapID, "player")
    if not pos then return mapID, nil, nil end
    local x, y = pos:GetXY()
    x, y = U.Num(x), U.Num(y)
    if not x or not y then return mapID, nil, nil end
    return mapID, U.Round(x, 4), U.Round(y, 4)
end

local mapSizeCache = {}
-- Width/height of a map in yards, for converting normalized coords to distances
function U.MapSize(mapID)
    if not mapID then return nil end
    local c = mapSizeCache[mapID]
    if c then return c[1], c[2] end
    if C_Map.GetMapWorldSize then
        local w, h = C_Map.GetMapWorldSize(mapID)
        w, h = U.Num(w), U.Num(h)
        if w and h and w > 0 then mapSizeCache[mapID] = { w, h } return w, h end
    end
    return nil
end

-- Distance in yards between two normalized points on the same map (nil if unknown map size)
function U.YardsBetween(mapID, x1, y1, x2, y2)
    local w, h = U.MapSize(mapID)
    if not w then return nil end
    local dx, dy = (x1 - x2) * w, (y1 - y2) * h
    return math.sqrt(dx * dx + dy * dy)
end

function U.MapName(mapID)
    local info = mapID and C_Map.GetMapInfo and C_Map.GetMapInfo(mapID)
    return info and U.Str(info.name) or tostring(mapID)
end

function U.ZoneName()
    local z = GetRealZoneText and GetRealZoneText() or GetZoneText()
    local sz = GetSubZoneText and GetSubZoneText() or ""
    return U.Str(z) or "?", U.Str(sz) or ""
end

function U.InInstance()
    local inInst, instType = IsInInstance()
    return inInst == true, U.Str(instType)
end

function U.CharKey()
    local name, realm = UnitFullName("player")
    realm = realm or GetRealmName()
    return (name or "?") .. "-" .. (realm or "?")
end

-- ===========================================================================
-- Items & pricing. Sources: PriceHistory (AH + vendor buy) and item sellPrice.
-- Economy.PriceHistory sets FO.Prices = { AH=fn(itemID)->min,n ; VendorBuy=fn(itemID) }.
-- ===========================================================================
U.AH_CUT = 0.05

function U.ItemIDFromLink(link)
    link = U.Str(link)
    if not link then return nil end
    return tonumber(link:match("item:(%d+)"))
end

function U.ItemInstant(itemID)
    if not itemID then return nil end
    local GII = (C_Item and C_Item.GetItemInfoInstant) or _G.GetItemInfoInstant
    local classID, subclassID, equipLoc, icon
    if GII then
        local _, _, _, eq, ic, c, s = GII(itemID)
        classID, subclassID, equipLoc, icon = U.Num(c), U.Num(s), U.Str(eq), ic
    end
    if classID then return classID, subclassID, equipLoc, icon end
    local S = FO.Seed
    if S and S.Info then
        local _, _, _, c, s, _, _, _, eq = S.Info(itemID)
        if c then return c, s, eq, icon end
    end
    return nil
end

-- name, quality, sellPrice, classID, subclassID, stackMax, bindType, link, equipLoc, iLevel, reqLevel
function U.ItemInfo(itemID)
    if not itemID then return nil end
    local GI = (C_Item and C_Item.GetItemInfo) or _G.GetItemInfo
    local name, link, quality, iLevel, reqLevel, _, _, stackMax, equipLoc, _, sellPrice, classID, subclassID, bindType
    if GI then name, link, quality, iLevel, reqLevel, _, _, stackMax, equipLoc, _, sellPrice, classID, subclassID, bindType = GI(itemID) end
    if not name then
        if C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, itemID) end
        local S = FO.Seed
        if S and S.Info then return S.Info(itemID) end
        return nil
    end
    return U.Str(name), U.Num(quality), U.Num(sellPrice) or 0, U.Num(classID), U.Num(subclassID),
           U.Num(stackMax) or 1, U.Num(bindType), link, U.Str(equipLoc), U.Num(iLevel), U.Num(reqLevel)
end

function U.ItemName(itemID)
    local name = U.ItemInfo(itemID)
    if name then return name end
    if C_Item and C_Item.GetItemNameByID then
        local n = U.Str(C_Item.GetItemNameByID(itemID))
        if n then return n end
    end
    return "item:" .. tostring(itemID)
end

function U.VendorSell(itemID)
    local _, _, sellPrice = U.ItemInfo(itemID)
    return sellPrice or 0
end

function U.AHPrice(itemID)
    local P = FO.Prices
    if P and P.AH then return P.AH(itemID) end
    return nil
end

-- Observed vendor price first; the client seed's list price as a fallback.
function U.VendorBuy(itemID)
    local P = FO.Prices
    local seen = P and P.VendorBuy and P.VendorBuy(itemID)
    if seen then return seen end
    local S = FO.Seed
    if S and S.VendorBuy then return S.VendorBuy(itemID) end
    return nil
end

-- Realistic value per unit: max(AH net of cut, vendor sell). Returns value, "ah"|"vendor"|nil
function U.ItemValue(itemID)
    local ah = U.AHPrice(itemID)
    local vend = U.VendorSell(itemID)
    local ahNet = ah and math.floor(ah * (1 - U.AH_CUT)) or 0
    if ahNet > vend and ahNet > 0 then return ahNet, "ah" end
    if vend > 0 then return vend, "vendor" end
    return 0, nil
end

-- Acquisition cost per unit: min(AH, vendor buy). Returns cost, source
function U.ItemCost(itemID)
    local ah = U.AHPrice(itemID)
    local vb = U.VendorBuy(itemID)
    if ah and vb then if vb <= ah then return vb, "vendor" else return ah, "ah" end end
    if vb then return vb, "vendor" end
    if ah then return ah, "ah" end
    return nil, nil
end

-- ===========================================================================
-- Tables & misc
-- ===========================================================================
function U.Count(t) local n = 0 for _ in pairs(t or {}) do n = n + 1 end return n end

function U.Keys(t) local k = {} for key in pairs(t or {}) do k[#k + 1] = key end return k end

function U.DeepDefaults(dst, defaults)
    if type(defaults) ~= "table" then return dst end
    for k, v in pairs(defaults) do
        if type(v) == "table" then
            if type(dst[k]) ~= "table" then dst[k] = {} end
            U.DeepDefaults(dst[k], v)
        elseif dst[k] == nil then
            dst[k] = v
        end
    end
    return dst
end

function U.Push(list, v, cap)
    table.insert(list, v)
    while cap and #list > cap do table.remove(list, 1) end
end

function U.Median(list)
    if #list == 0 then return nil end
    local s = {}
    for i, v in ipairs(list) do s[i] = v end
    table.sort(s)
    local n = #s
    if n % 2 == 1 then return s[(n + 1) / 2] end
    return (s[n / 2] + s[n / 2 + 1]) / 2
end

function U.Mean(list)
    if #list == 0 then return nil end
    local sum = 0
    for _, v in ipairs(list) do sum = sum + v end
    return sum / #list
end

function U.Debounce(delay, fn)
    local pending = false
    return function(...)
        if pending then return end
        pending = true
        local args = { ... }
        C_Timer.After(delay, function() pending = false; fn(unpack(args)) end)
    end
end

function U.HookGlobal(name, fn)
    if type(_G[name]) == "function" and hooksecurefunc then hooksecurefunc(name, fn) return true end
    return false
end

function U.SplitCmd(msg)
    local cmd, arg = (msg or ""):match("^(%S*)%s*(.-)$")
    return (cmd or ""):lower(), arg or ""
end

function U.Trunc(s, n) s = tostring(s or "") if #s > n then return s:sub(1, n - 1) .. "…" end return s end

function U.Color(hex, s) return "|cff" .. hex .. tostring(s) .. "|r" end
U.GREEN, U.RED, U.GRAY, U.YELLOW = "60ff60", "ff6060", "aaaaaa", "ffd100"
function U.Signed(copper)
    local c = U.Num(copper) or 0
    return U.Color(c >= 0 and U.GREEN or U.RED, (c >= 0 and "+" or "") .. U.FormatMoney(c))
end

-- Player helpful-aura names (empty in restricted contexts)
function U.PlayerBuffNames()
    local names = {}
    if not C_UnitAuras or not C_UnitAuras.GetAuraDataByIndex then return names end
    for i = 1, 40 do
        local a = C_UnitAuras.GetAuraDataByIndex("player", i, "HELPFUL")
        if not a then break end
        local n = U.Str(a.name)
        if n then names[#names + 1] = n end
    end
    return names
end

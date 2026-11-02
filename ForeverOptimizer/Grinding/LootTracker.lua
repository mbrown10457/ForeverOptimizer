local ADDON, FO = ...
local U = FO.Util

-- ===========================================================================
-- Reads the loot window. Dedupes corpses, maps items to the mob they came
-- from, prices them, and tells the session and the mob database.
-- ===========================================================================
local LT = FO:NewModule("Grinding.LootTracker", { account = "loot", defaults = { log = {} } })  -- raw loot events, cap 300

local seen, seenOrder, SEEN_MAX = {}, {}, 600
local function MarkSeen(guid)
    if seen[guid] then return false end
    seen[guid] = true
    table.insert(seenOrder, guid)
    if #seenOrder > SEEN_MAX then seen[table.remove(seenOrder, 1)] = nil end
    return true
end

function LT:OnLootOpened()
    local n = U.Num(GetNumLootItems()) or 0
    local itemType = (Enum and Enum.LootSlotType and Enum.LootSlotType.Item) or 1
    local corpseCounted = {}
    local tGUID = U.Str(UnitGUID("target"))
    local tName = U.Str(UnitName("target"))
    for slot = 1, n do
        local slotType = U.Num(GetLootSlotType(slot))
        local _, name, qty = GetLootSlotInfo(slot)
        name, qty = U.Str(name), U.Num(qty) or 1
        local itemID = U.ItemIDFromLink(GetLootSlotLink(slot))
        local sources = { GetLootSourceInfo(slot) }
        local guid = U.Str(sources[1])
        local unitType, typeID = U.ParseGUID(guid)
        local npcID = (unitType == "Creature" or unitType == "Vehicle") and typeID or nil
        local objectID = unitType == "GameObject" and typeID or nil
        local npcName = (guid and guid == tGUID) and tName or nil

        if guid and not corpseCounted[guid] then
            corpseCounted[guid] = true
            if MarkSeen(guid) then
                FO:Fire("FO_LOOT_SOURCE", guid, npcID, npcName, objectID)
            end
        end
        if slotType == itemType and itemID then
            local value, src = U.ItemValue(itemID)
            U.Push(self.db.log, { t = time(), item = itemID, qty = qty, npc = npcID or objectID, vendor = U.VendorSell(itemID), ah = U.AHPrice(itemID), zone = (U.ZoneName()) }, 300)
            FO.Session:RecordLootItem(itemID, qty, value, src, npcID)
            FO:Fire("FO_LOOT_ITEM", itemID, qty, value, src, npcID, npcName, guid, name, objectID)
        end
    end
end

LT.events = {
    LOOT_OPENED = function(self) self:OnLootOpened() end,
}

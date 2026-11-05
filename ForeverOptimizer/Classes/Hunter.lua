local ADDON, FO = ...
local U = FO.Util
local print = FO:Printer("Classes")

-- ===========================================================================
-- Hunter: ammo supply, pet presence, agility-first weights.
-- ===========================================================================
FO.Classes = FO.Classes or {}
local H = FO:NewModule("Classes.Hunter", {})
H.weights = FO.StatWeights and FO.StatWeights.HUNTER

local ItemClass = Enum and Enum.ItemClass or {}
local CLASS_PROJECTILE = ItemClass.Projectile or 6
local C = C_Container
local ammo, ammoAt, warned = 0, 0, false

local function CountAmmo()
    local n = 0
    for bag = 0, (NUM_BAG_SLOTS or 4) do
        local slots = C and C.GetContainerNumSlots and U.Num(C.GetContainerNumSlots(bag)) or 0
        for slot = 1, slots do
            local info = C.GetContainerItemInfo and C.GetContainerItemInfo(bag, slot)
            local id = info and U.Num(info.itemID)
            if id and U.ItemInstant(id) == CLASS_PROJECTILE then n = n + (U.Num(info.stackCount) or 0) end
        end
    end
    -- ammo slot (classic layout) if present
    local link = GetInventoryItemLink and GetInventoryItemLink("player", 0)
    if link then n = n + (U.Num(GetInventoryItemCount("player", 0)) or 0) end
    return n
end

function H:OnEnable()
    if FO.Player.class ~= "HUNTER" then return end
    FO.Classes.HUNTER = self
    ammo, ammoAt = CountAmmo(), GetTime()
    FO:RegisterEvent("BAG_UPDATE_DELAYED", U.Debounce(2, function()
        ammo = CountAmmo()
        local minAmmo = FO.Alerts and FO.Alerts.db and FO.Alerts.db.settings.ammoMin or 200
        if ammo < minAmmo and not warned then warned = true FO:Alert("ammo", "|cffff6060ammo low:|r %d left.", ammo) elseif ammo >= minAmmo then warned = false end
    end))
end

function H:Lines()
    if FO.Player.class ~= "HUNTER" then return {} end
    local lines = {}
    lines[#lines + 1] = string.format("Ammo %d%s", ammo, ammo < 200 and " |cffff6060LOW|r" or "")
    local hasPet = UnitExists("pet")
    local petLine = hasPet and ("Pet " .. (U.Str(UnitName("pet")) or "?")) or "|cffff6060No pet out|r"
    local PI = C_PetInfo
    local GetHappiness = (PI and PI.GetPetHappiness) or GetPetHappiness
    local GetFoodTypes = (PI and PI.GetPetFoodTypes) or GetPetFoodTypes
    if hasPet and GetHappiness then
        local ok, hap = pcall(GetHappiness)
        hap = ok and U.Num(hap) or nil
        if hap then petLine = petLine .. (({ [1] = " |cffff6060unhappy|r", [2] = " content", [3] = " happy" })[hap] or "") end
    end
    if hasPet and GetFoodTypes then
        local ok, foods = pcall(function() return { GetFoodTypes() } end)
        if ok and type(foods[1]) == "table" then foods = foods[1] end
        if ok and #foods > 0 then petLine = petLine .. " eats " .. table.concat(foods, "/") end
    end
    lines[#lines + 1] = petLine
    local aspect
    for _, b in ipairs(U.PlayerBuffNames()) do if b:find("^Aspect of") then aspect = b end end
    lines[#lines + 1] = aspect or "|cffffd100No aspect|r"
    local AS = FO.AutoShot
    if AS and AS.ready then
        lines[#lines + 1] = string.format("Auto Shot timer %s%s", AS.speed and string.format("%.2f s", AS.speed) or "?",
            AS.shots > 0 and string.format(", %d shots", AS.shots) or "")
    end
    local st = FO.Session:Stats()
    if st and st.deaths > 0 and st.kills > 0 then lines[#lines + 1] = string.format("Deaths per 100 kills: %.1f", st.deaths / st.kills * 100) end
    -- Combat-log extras (optimistic: only when the client exposes the log)
    local CS = FO.CombatStats
    if CS and CS:Available() then
        local c = CS:Stats()
        if c.petShare and c.dmgTotal > 0 then
            lines[#lines + 1] = string.format("Pet damage %.0f%%%s", c.petShare * 100, c.petShare < 0.2 and " |cffffd100low: pet idle or dead?|r" or "")
        end
        local a = c.autos["Auto Shot"]
        if a and a.shots >= 3 and a.clipPct then
            lines[#lines + 1] = string.format("Auto Shot %d, clipped %.0f%% (%s lost)%s", a.shots, a.clipPct * 100, U.FormatDuration(a.clipped),
                a.clipPct > 0.15 and " |cffff6060cast less between shots|r" or "")
        end
    end
    return lines
end

H.commands = {
    hunter = { help = "ammo & pet status", fn = function(self) for _, l in ipairs(self:Lines()) do print("%s", l) end end },
}

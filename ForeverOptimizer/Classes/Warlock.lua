local ADDON, FO = ...
local U = FO.Util
local print = FO:Printer("Classes")

-- ===========================================================================
-- Warlock: soul shard supply (and the bag space they eat), demon presence.
-- ===========================================================================
FO.Classes = FO.Classes or {}
local W = FO:NewModule("Classes.Warlock", {})
W.weights = FO.StatWeights and FO.StatWeights.WARLOCK

local SOUL_SHARD = 6265
local shards = 0

local function CountShards()
    if C_Item and C_Item.GetItemCount then return U.Num(C_Item.GetItemCount(SOUL_SHARD)) or 0 end
    if GetItemCount then return U.Num(GetItemCount(SOUL_SHARD)) or 0 end
    return 0
end

local casts = { ["Life Tap"] = 0, ["Drain Life"] = 0, ["Drain Soul"] = 0 }
local function SpellName(id)
    if C_Spell and C_Spell.GetSpellName then return U.Str(C_Spell.GetSpellName(id)) end
    if GetSpellInfo then return U.Str((GetSpellInfo(id))) end
end

function W:OnEnable()
    if FO.Player.class ~= "WARLOCK" then return end
    FO.Classes.WARLOCK = self
    shards = CountShards()
    FO:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED", function(unit, _, spellID)
        if unit ~= "player" then return end
        local name = SpellName(U.Num(spellID))
        if name and casts[name] then casts[name] = casts[name] + 1 end
    end)
    FO:RegisterEvent("BAG_UPDATE_DELAYED", U.Debounce(2, function()
        local n = CountShards()
        if n ~= shards then
            shards = n
            local minShards = FO.Alerts and FO.Alerts.db and FO.Alerts.db.settings.shardsMin or 3
            if n < minShards then FO:Alert("shards", "|cffff6060%d soul shards.|r Drain Soul the next kill.", n)
            elseif n >= 20 then print("%d soul shards are eating bag space; stop draining.", n) end
        end
    end))
end

function W:Lines()
    if FO.Player.class ~= "WARLOCK" then return {} end
    local lines = {}
    lines[#lines + 1] = string.format("Shards %d%s", shards, shards < 3 and " |cffff6060LOW|r" or shards >= 20 and " |cffffd100many|r" or "")
    lines[#lines + 1] = UnitExists("pet") and ("Demon " .. (U.Str(UnitName("pet")) or "?")) or "|cffff6060No demon out|r"
    local st0 = FO.Session:Stats()
    local kills = st0 and st0.kills or 0
    if kills > 0 and (casts["Life Tap"] + casts["Drain Life"] + casts["Drain Soul"]) > 0 then
        lines[#lines + 1] = string.format("Per kill: Tap %.1f  Drain Life %.1f  Drain Soul %.1f", casts["Life Tap"] / kills, casts["Drain Life"] / kills, casts["Drain Soul"] / kills)
    end
    local st = FO.Session:Stats()
    if st and st.by.rest.t > 0 and st.productive > 0 then
        lines[#lines + 1] = string.format("Drink share %.0f%% (Life Tap + Drain more?)", st.by.rest.t / (st.productive + st.by.rest.t) * 100)
    end
    -- Combat-log extras: DoT efficiency, demon share, mana economy
    local CS = FO.CombatStats
    if CS and CS:Available() then
        local c = CS:Stats()
        for i = 1, math.min(3, #c.dots) do
            local d = c.dots[i]
            lines[#lines + 1] = string.format("%s eff %.0f%%%s%s", U.Trunc(d.name, 14), d.efficiency * 100,
                d.early > 0 and string.format(" (%d early)", d.early) or "", d.truncated > 0 and string.format(" (%d died)", d.truncated) or "")
        end
        if c.petShare and c.dmgTotal > 0 then lines[#lines + 1] = string.format("Demon damage %.0f%%", c.petShare * 100) end
        if c.manaSpent > 0 then
            lines[#lines + 1] = string.format("Mana spent %d, gained %d, %.1f dmg/mana", c.manaSpent, c.manaGained, c.dmgTotal / c.manaSpent)
        end
    end
    return lines
end

W.commands = {
    warlock = { help = "shard & demon status", fn = function(self) for _, l in ipairs(self:Lines()) do print("%s", l) end end },
}

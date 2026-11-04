local ADDON, FO = ...
local U = FO.Util
local print = FO:Printer("Classes")

-- ===========================================================================
-- Shaman: the duo's healer and a melee caster whose damage rests on four
-- things that lapse quietly: the weapon imbue, the shield, the totems and the
-- mana pool. Reads all four from the client, counts shocks, bolts and heals
-- per kill, and warns when the imbue is about to run out or a fight starts
-- without a shield up.
-- ===========================================================================
FO.Classes = FO.Classes or {}
local S = FO:NewModule("Classes.Shaman", {})
S.weights = FO.StatWeights and FO.StatWeights.SHAMAN

local SHIELDS = { ["Lightning Shield"] = true, ["Water Shield"] = true, ["Earth Shield"] = true }
local SHOCKS = { "Earth Shock", "Flame Shock", "Frost Shock" }
local HEALS = { "Healing Wave", "Lesser Healing Wave", "Chain Heal" }
local casts = { ["Lightning Bolt"] = 0, ["Stormstrike"] = 0 }
for _, n in ipairs(SHOCKS) do casts[n] = 0 end
for _, n in ipairs(HEALS) do casts[n] = 0 end
local IMBUE_WARN = 120 * 1000      -- ms left on the weapon imbue before the warning
local imbueWarnedAt = 0

local function SpellName(id)
    if C_Spell and C_Spell.GetSpellName then return U.Str(C_Spell.GetSpellName(id)) end
    if GetSpellInfo then return U.Str((GetSpellInfo(id))) end
end

-- name and charges of the shield buff, or nil
local function Shield()
    if not (C_UnitAuras and C_UnitAuras.GetAuraDataByIndex) then return nil end
    for i = 1, 40 do
        local ok, a = pcall(C_UnitAuras.GetAuraDataByIndex, "player", i, "HELPFUL")
        if not ok or type(a) ~= "table" then break end
        local name = U.Str(a.name)
        if name and SHIELDS[name] then return name, U.Num(a.applications) or 0 end
    end
end

-- milliseconds left on the main-hand and off-hand imbues (nil = none)
local function Imbues()
    local fn = (C_Item and C_Item.GetWeaponEnchantInfo) or GetWeaponEnchantInfo
    if not fn then return nil, nil, false end
    local ok, hasMain, mainExp, _, _, hasOff, offExp = pcall(fn)
    if not ok then return nil, nil, false end
    return hasMain and (U.Num(mainExp) or 0) or nil, hasOff and (U.Num(offExp) or 0) or nil, true
end

-- totems down: { "Searing 0:45", ... } in slot order fire, earth, water, air
local function Totems()
    local out = {}
    if not GetTotemInfo then return out end
    for slot = 1, 4 do
        local ok, have, name, start, dur = pcall(GetTotemInfo, slot)
        name = U.Str(name)
        if ok and have and name and name ~= "" then
            local left = (U.Num(start) or 0) + (U.Num(dur) or 0) - GetTime()
            local short = name:gsub(" Totem.*$", "")
            out[#out + 1] = left > 0 and string.format("%s %s", U.Trunc(short, 20), U.FormatDuration(left)) or U.Trunc(short, 20)
        end
    end
    return out
end

local function CheckImbue()
    local main, _, available = Imbues()
    if not available then return end
    if main and main > 0 and main < IMBUE_WARN and GetTime() - imbueWarnedAt > 300 then
        imbueWarnedAt = GetTime()
        FO:Alert("custom", "weapon imbue runs out in %s: recast it after this pull.", U.FormatDuration(main / 1000))
    end
end

function S:OnEnable()
    if FO.Player.class ~= "SHAMAN" then return end
    FO.Classes.SHAMAN = self
    FO:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED", function(unit, _, spellID)
        if unit ~= "player" then return end
        local name = SpellName(U.Num(spellID))
        if name and casts[name] then casts[name] = casts[name] + 1 end
    end)
    FO:RegisterEvent("PLAYER_REGEN_DISABLED", function()
        local shield = Shield()
        if not shield and (FO.Player.level or 1) >= 8 then FO:Alert("custom", "no shield up: Lightning Shield before the next pull.") end
        local main, _, available = Imbues()
        if available and not main and (FO.Player.level or 1) >= 1 then FO:Alert("custom", "no weapon imbue: Rockbiter Weapon (Windfury from 30).") end
        CheckImbue()
    end)
end

function S:OnTick()
    if FO.Player.class ~= "SHAMAN" then return end
    self.tickN = (self.tickN or 0) + 1
    if self.tickN % 30 == 0 then CheckImbue() end
end

function S:Lines()
    if FO.Player.class ~= "SHAMAN" then return {} end
    local lines = {}
    local shield, charges = Shield()
    lines[#lines + 1] = shield and string.format("%s x%d%s", shield, charges, charges <= 1 and " |cffffd100recast|r" or "") or "|cffff6060No shield up|r"
    local main, off, available = Imbues()
    if available then
        if main then
            lines[#lines + 1] = string.format("Imbue %s left%s%s", U.FormatDuration(main / 1000), main < IMBUE_WARN and " |cffff6060LOW|r" or "",
                off and string.format(", off-hand %s", U.FormatDuration(off / 1000)) or "")
        else
            lines[#lines + 1] = "|cffff6060No weapon imbue|r"
        end
    end
    local totems = Totems()
    lines[#lines + 1] = #totems > 0 and ("Totems " .. table.concat(totems, ", ")) or "No totems down"
    local mana, manaMax = U.Num(UnitPower("player", 0)), U.Num(UnitPowerMax("player", 0))
    if mana and manaMax and manaMax > 0 then lines[#lines + 1] = string.format("Mana %d%%", mana / manaMax * 100) end
    local st = FO.Session:Stats()
    local kills = st and st.kills or 0
    if kills > 0 then
        local shocks, healsN = 0, 0
        for _, n in ipairs(SHOCKS) do shocks = shocks + casts[n] end
        for _, n in ipairs(HEALS) do healsN = healsN + casts[n] end
        if shocks + healsN + casts["Lightning Bolt"] + casts["Stormstrike"] > 0 then
            lines[#lines + 1] = string.format("Per kill: shocks %.1f  bolts %.1f  heals %.1f%s", shocks / kills, casts["Lightning Bolt"] / kills, healsN / kills,
                casts["Stormstrike"] > 0 and string.format("  Stormstrike %.1f", casts["Stormstrike"] / kills) or "")
        end
    end
    if st and st.by.rest.t > 0 and st.productive > 0 then
        local share = st.by.rest.t / (st.productive + st.by.rest.t) * 100
        lines[#lines + 1] = string.format("Drink share %.0f%%%s", share, share > 30 and " |cffff6060high: Water Shield rune, fewer bolts|r" or "")
    end
    -- Combat-log extras: melee share, heal per mana, Flame Shock efficiency, mana economy
    local CS = FO.CombatStats
    if CS and CS:Available() then
        local c = CS:Stats()
        if c.dmgTotal > 0 then
            local melee = 0
            for _, sp in ipairs(c.spells) do if sp.name == "Melee" or sp.name == "Auto Attack" or sp.name == "Stormstrike" or sp.name == "Windfury Attack" then melee = melee + sp.total end end
            lines[#lines + 1] = string.format("Melee %.0f%% of damage%s", melee / c.dmgTotal * 100, c.manaSpent > 0 and string.format(", %.1f dmg/mana", c.dmgTotal / c.manaSpent) or "")
        end
        for i = 1, math.min(2, #c.heals) do
            local h = c.heals[i]
            if h.perMana then lines[#lines + 1] = string.format("%s %.2f heal/mana, %.0f%% overheal", U.Trunc(h.name, 14), h.perMana, h.overPct * 100) end
        end
        for i = 1, math.min(2, #c.dots) do
            local d = c.dots[i]
            lines[#lines + 1] = string.format("%s eff %.0f%%%s", U.Trunc(d.name, 14), d.efficiency * 100, d.early > 0 and string.format(" (%d early)", d.early) or "")
        end
    end
    return lines
end

S.commands = {
    shaman = { help = "shield, weapon imbue, totems & mana status", fn = function(self) for _, l in ipairs(self:Lines()) do print("%s", l) end end },
}

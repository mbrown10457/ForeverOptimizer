local ADDON, FO = ...
local U = FO.Util
local print = FO:Printer("Classes")

-- ===========================================================================
-- Priest: mana downtime is the whole game. Tracks drink share and nudges
-- stat weights toward Spirit when rest time dominates.
-- ===========================================================================
FO.Classes = FO.Classes or {}
local P = FO:NewModule("Classes.Priest", {})
P.weights = FO.StatWeights and FO.StatWeights.PRIEST

local wand, spells = 0, 0
local function SpellName(id)
    if C_Spell and C_Spell.GetSpellName then return U.Str(C_Spell.GetSpellName(id)) end
    if GetSpellInfo then return U.Str((GetSpellInfo(id))) end
end

function P:OnEnable()
    if FO.Player.class ~= "PRIEST" then return end
    FO.Classes.PRIEST = self
    -- Wand vs spell: "Shoot" is the wand auto-attack spell
    FO:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED", function(unit, _, spellID)
        if unit ~= "player" then return end
        local name = SpellName(U.Num(spellID))
        if name == "Shoot" then wand = wand + 1 elseif name then spells = spells + 1 end
    end)
end

function P:Lines()
    if FO.Player.class ~= "PRIEST" then return {} end
    local lines = {}
    local st = FO.Session:Stats()
    if not st then return lines end
    local fight = st.productive
    local rest = st.by.rest.t
    local share = (fight + rest) > 0 and rest / (fight + rest) * 100 or 0
    lines[#lines + 1] = string.format("Drink share %.0f%%%s", share, share > 30 and " |cffff6060high|r" or share > 20 and " |cffffd100meh|r" or "")
    if wand + spells > 0 then lines[#lines + 1] = string.format("Wand %d / spells %d (%.0f%% wand)", wand, spells, wand / (wand + spells) * 100) end
    local mana, manaMax = U.Num(UnitPower("player", 0)), U.Num(UnitPowerMax("player", 0))
    if mana and manaMax and manaMax > 0 then lines[#lines + 1] = string.format("Mana %d%%", mana / manaMax * 100) end
    if share > 30 then lines[#lines + 1] = "Spirit > Int until drink share < 20%; wand more." end
    -- Combat-log extras: healing and damage per mana, wand share by damage
    local CS = FO.CombatStats
    if CS and CS:Available() then
        local c = CS:Stats()
        for i = 1, math.min(2, #c.heals) do
            local h = c.heals[i]
            if h.perMana then lines[#lines + 1] = string.format("%s %.2f heal/mana, %.0f%% overheal", U.Trunc(h.name, 14), h.perMana, h.overPct * 100) end
        end
        local wandDmg = 0
        for _, sp in ipairs(c.spells) do
            if sp.name == "Shoot" then wandDmg = sp.total end
        end
        if c.dmgTotal > 0 then lines[#lines + 1] = string.format("Wand %.0f%% of damage%s", wandDmg / c.dmgTotal * 100, c.manaSpent > 0 and string.format(", %.1f dmg/mana", c.dmgTotal / c.manaSpent) or "") end
        for i = 1, math.min(2, #c.dots) do
            local d = c.dots[i]
            lines[#lines + 1] = string.format("%s eff %.0f%%%s", U.Trunc(d.name, 14), d.efficiency * 100, d.perMana and string.format(", %.1f dmg/mana", d.perMana) or "")
        end
    end
    return lines
end

P.commands = {
    priest = { help = "mana downtime status", fn = function(self) for _, l in ipairs(self:Lines()) do print("%s", l) end end },
}

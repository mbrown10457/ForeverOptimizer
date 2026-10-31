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
    return lines
end

P.commands = {
    priest = { help = "mana downtime status", fn = function(self) for _, l in ipairs(self:Lines()) do print("%s", l) end end },
}

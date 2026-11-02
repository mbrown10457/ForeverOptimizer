local ADDON, FO = ...
local U = FO.Util
local print = FO:Printer("Character")

-- ===========================================================================
-- Rune discovery log. Forever has Season-of-Discovery-style engraved
-- abilities and nobody knows yet how they are handed out. Every "Engrave
-- <slot> - <ability>" spell and every rune ability in the client seed is
-- checked against the spellbook whenever it changes; a new one is announced,
-- flashed, stamped into the session notes and saved with level, zone and
-- position, so the first week tells us where each rune comes from.
-- ===========================================================================
local R = FO:NewModule("Character.Runes", { char = "runes", cdefaults = { learned = {} } })
FO.Runes = R

local function SpellKnown(id)
    if IsPlayerSpell then local ok, r = pcall(IsPlayerSpell, id) if ok and r then return true end end
    if IsSpellKnown then local ok, r = pcall(IsSpellKnown, id) if ok and r then return true end end
    return false
end

local index   -- { engrave = { {id, name} }, abilities = { {id, name} } } for the player's class

local function BuildIndex()
    index = { engrave = {}, abilities = {} }
    local class = FO.Player and FO.Player.class
    if not class then return end
    for id, row in pairs((FO.Seed and FO.Seed.spells) or {}) do
        if row[2] == class then
            if row[3] == "Engraving" then index.engrave[#index.engrave + 1] = { id = id, name = row[1] }
            elseif id >= 400000 then index.abilities[#index.abilities + 1] = { id = id, name = row[1] } end
        end
    end
    table.sort(index.engrave, function(a, b) return a.name < b.name end)
    table.sort(index.abilities, function(a, b) return a.name < b.name end)
end

-- announce = false records what is already known without noise (login, /reload)
function R:Scan(announce)
    if self.disabled or not self.cdb then return 0 end
    if not index then BuildIndex() end
    local new = 0
    local function look(list, kind)
        for _, e in ipairs(list) do
            if not self.cdb.learned[e.id] and SpellKnown(e.id) then
                local zone, sub = U.ZoneName()
                local _, x, y = U.PlayerPosition()
                self.cdb.learned[e.id] = { name = e.name, kind = kind, t = time(), level = FO.Player.level or 0, zone = zone, sub = sub,
                                           x = x, y = y, seenAtLogin = not announce or nil }
                new = new + 1
                if announce then
                    local where = string.format("%s%s%s", zone or "?", (sub and sub ~= "") and (" / " .. sub) or "",
                                                x and string.format(" (%.1f, %.1f)", x * 100, y * 100) or "")
                    FO:Alert("custom", "rune learned: |cffffd100%s|r at %s", e.name, where)
                    if FO.Session and FO.Session.AddNote then FO.Session:AddNote("rune: " .. e.name) end
                end
            end
        end
    end
    look(index.engrave, "engrave")
    look(index.abilities, "ability")
    return new
end

R.events = {
    SPELLS_CHANGED = function(self) self:Scan(true) end,
    LEARNED_SPELL_IN_TAB = function(self) self:Scan(true) end,
}

function R:OnEnable()
    BuildIndex()
    self:Scan(false)
end

function R:Known()
    local out = {}
    for id, e in pairs(self.cdb and self.cdb.learned or {}) do out[#out + 1] = e end
    table.sort(out, function(a, b) return (a.t or 0) < (b.t or 0) end)
    return out
end

R.commands = {
    runes = { help = "runes learned (where and when) and the engravings still missing for your class", fn = function(self)
        if not index then BuildIndex() end
        local known = self:Known()
        print("runes: %d learned, %d engravings in the client for your class", #known, #index.engrave)
        for _, e in ipairs(known) do
            print("  %s  L%d %s%s%s%s", date("%m/%d %H:%M", e.t or 0), e.level or 0, e.zone or "?", (e.sub and e.sub ~= "") and (" / " .. e.sub) or "",
                  e.x and string.format(" (%.1f, %.1f)", e.x * 100, e.y * 100) or "", e.seenAtLogin and "  |cffaaaaaa(already known at login)|r" or "")
            print("      |cffffd100%s|r", e.name)
        end
        local missing = {}
        for _, e in ipairs(index.engrave) do if not (self.cdb and self.cdb.learned[e.id]) then missing[#missing + 1] = (e.name:gsub("^Engrave ", "")) end end
        if #missing > 0 then
            print("  not yet (%d): %s%s", #missing, table.concat(missing, ", ", 1, math.min(#missing, 12)), #missing > 12 and ", ..." or "")
        end
    end },
}

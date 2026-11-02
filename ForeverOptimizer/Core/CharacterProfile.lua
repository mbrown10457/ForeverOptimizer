local ADDON, FO = ...
local U = FO.Util

-- ===========================================================================
-- Who is playing. Kept live in FO.Player and persisted per character so the
-- alt-inventory and analytics modules can reason across characters.
-- ===========================================================================
local P = FO:NewModule("Core.CharacterProfile", {
    char = "profile",
    cdefaults = { professions = {}, equipment = {}, skills = {}, firstSeen = 0, lastSeen = 0 },
})

local EQUIP_SLOTS = 19

local function ReadEquipment()
    local eq = {}
    for slot = 1, EQUIP_SLOTS do
        local link = GetInventoryItemLink and GetInventoryItemLink("player", slot)
        local id = U.ItemIDFromLink(link)
        if id then eq[slot] = id end
    end
    return eq
end

-- Talent build if the client exposes one (retail spec API or classic talent tabs); nil otherwise
local function ReadBuild()
    if GetSpecialization and GetSpecializationInfo then
        local idx = U.Num(GetSpecialization())
        if idx then
            local _, name = GetSpecializationInfo(idx)
            if name then return U.Str(name) end
        end
    end
    if GetNumTalentTabs and GetTalentTabInfo then
        local parts = {}
        for i = 1, GetNumTalentTabs() do
            local name, _, points = GetTalentTabInfo(i)
            if type(name) == "table" then name, points = name.name, name.pointsSpent end
            parts[#parts + 1] = tostring(U.Num(points) or 0)
        end
        if #parts > 0 then return table.concat(parts, "/") end
    end
    return nil
end

-- Skill lines (weapon skills, defense, etc.) where the client still has them
local function ReadSkills()
    local out = {}
    local SK = C_SkillInfo
    if SK and SK.GetNumSkillLines and SK.GetSkillLineInfo then
        local okN, n = pcall(SK.GetNumSkillLines)
        for i = 1, (okN and U.Num(n)) or 0 do
            local ok, info = pcall(SK.GetSkillLineInfo, i)
            if ok and type(info) == "table" and not info.isHeader and U.Str(info.name) then
                out[#out + 1] = { name = U.Str(info.name), rank = U.Num(info.rank) or 0, max = U.Num(info.maxRank) or 0 }
            end
        end
        return out
    end
    if not GetNumSkillLines or not GetSkillLineInfo then return out end
    for i = 1, U.Num(GetNumSkillLines()) or 0 do
        local name, isHeader, _, rank, _, _, maxRank = GetSkillLineInfo(i)
        name = U.Str(name)
        if name and not isHeader then out[name] = { rank = U.Num(rank) or 0, max = U.Num(maxRank) or 0 } end
    end
    return out
end

FO.Player = {}

local function ReadProfessions()
    local out = {}
    if not GetProfessions then return out end
    local idx = { GetProfessions() }
    for _, i in ipairs(idx) do
        if type(i) == "number" then
            local name, _, rank, maxRank, _, _, skillLine = GetProfessionInfo(i)
            name = U.Str(name)
            if name then out[name] = { rank = U.Num(rank) or 0, max = U.Num(maxRank) or 0, skillLine = U.Num(skillLine) } end
        end
    end
    return out
end

function P:Refresh()
    local C = FO.Player
    C.key = FO.charKey
    C.name = U.Str(UnitName("player")) or "?"
    C.realm = U.Str(GetRealmName()) or "?"
    local classLocal, classFile = UnitClass("player")
    C.class = U.Str(classFile) or "UNKNOWN"    -- "HUNTER", "WARLOCK", ...
    C.classLocal = U.Str(classLocal) or C.class
    C.level = U.Num(UnitLevel("player")) or 1
    C.race = select(2, UnitRace("player"))
    C.faction = U.Str(UnitFactionGroup("player")) or "?"
    C.xp = U.Num(UnitXP("player")) or 0
    C.xpMax = U.Num(UnitXPMax("player")) or 1
    C.money = U.Num(GetMoney()) or 0
    C.professions = ReadProfessions()
    C.bind = U.Str(GetBindLocation and GetBindLocation()) or "?"
    C.equipment = ReadEquipment()
    C.build = ReadBuild()
    C.skills = ReadSkills()

    local d = self.cdb
    d.name, d.realm, d.class, d.classLocal, d.level, d.faction = C.name, C.realm, C.class, C.classLocal, C.level, C.faction
    d.money = C.money
    d.professions = C.professions
    d.bind = C.bind
    d.equipment = C.equipment
    d.build = C.build
    d.skills = C.skills
    d.firstSeen = d.firstSeen ~= 0 and d.firstSeen or time()
    d.lastSeen = time()
end

P.events = {
    PLAYER_LEVEL_UP = function(self, level)
        self:Refresh()
        FO:Fire("FO_LEVEL_UP", U.Num(level) or FO.Player.level)
    end,
    SKILL_LINES_CHANGED = function(self) self.cdb.professions = ReadProfessions(); FO.Player.professions = self.cdb.professions end,
    PLAYER_MONEY = function(self) local m = U.Num(GetMoney()) if m then FO.Player.money = m; self.cdb.money = m end end,
    PLAYER_EQUIPMENT_CHANGED = function(self) FO.Player.equipment = ReadEquipment(); self.cdb.equipment = FO.Player.equipment end,
    HEARTHSTONE_BOUND = function(self) FO.Player.bind = U.Str(GetBindLocation and GetBindLocation()) or "?"; self.cdb.bind = FO.Player.bind end,
}

function P:OnInit() self:Refresh() end
function P:OnEnable() self:Refresh() end

P.commands = {
    skills = { help = "skill lines below max (weapon skills etc.)", fn = function(self)
        FO.Player.skills = ReadSkills()
        local any = false
        for name, s in pairs(FO.Player.skills) do
            if s.max > 0 and s.rank < s.max then any = true FO:Print("Core", "  %-24s %d/%d", name, s.rank, s.max) end
        end
        if not any then FO:Print("Core", "no skill lines below max (or the client has no skill line API).") end
    end },
    me = { help = "character profile", fn = function(self)
        self:Refresh()
        local C = FO.Player
        FO:Print("Core", "%s, level %d %s (%s), %s. Hearth: %s", C.name, C.level, C.classLocal, C.faction, U.FormatMoney(C.money), C.bind)
        if C.build then FO:Print("Core", "  build: %s", C.build) end
        for name, pr in pairs(C.professions) do FO:Print("Core", "  %s %d/%d", name, pr.rank, pr.max) end
        FO:Print("Core", "  %d equipped items snapshotted.", U.Count(C.equipment))
        local n = 0
        for _ in FO:EachChar("profile") do n = n + 1 end
        FO:Print("Core", "%d characters known to this account's data.", n)
    end },
}

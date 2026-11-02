local ADDON, FO = ...
local U = FO.Util
local print = FO:Printer("Grinding")
local band = bit.band

-- ===========================================================================
-- Group meter: damage and healing per player for the current fight, the last
-- fight and the session, built from the normalized combat log messages.
-- Pets and guardians are credited to their owner (yours via the adapter's
-- ev.pet flag, party and raid pets via the unit tokens partyNpet / raidNpet).
-- Only group-affiliated sources count, and damage to group members (Life Tap,
-- Hellfire, friendly fire) is ignored. Nothing is synced between players: each
-- copy of the addon sees what its own combat log sees, which for a duo in the
-- open world is everything.
-- ===========================================================================
local M = FO:NewModule("Grinding.Meter", {
    account = "meter",
    defaults = { mode = "dps", rows = 8 },
})
FO.Meter = M

local GROUP = (COMBATLOG_OBJECT_AFFILIATION_MINE or 0x1) + (COMBATLOG_OBJECT_AFFILIATION_PARTY or 0x2) + (COMBATLOG_OBJECT_AFFILIATION_RAID or 0x4)
local TYPE_PLAYER = COMBATLOG_OBJECT_TYPE_PLAYER or 0x400
local TYPE_PET = COMBATLOG_OBJECT_TYPE_PET or 0x1000
local TYPE_GUARDIAN = COMBATLOG_OBJECT_TYPE_GUARDIAN or 0x2000
local GAP = 6          -- seconds without a group damage or heal event closes the fight segment
local SCAN_EVERY = 2   -- seconds between pet-owner rescans triggered by an unknown pet

local function NewSeg() return { rows = {}, dmg = 0, heal = 0, time = 0 } end
M.cur, M.last, M.total = NewSeg(), nil, NewSeg()
M.hidden = 0           -- events whose amount was a secret value
M.fights = 0

local myGUID
local owners = {}      -- pet GUID -> { guid, name } of the owning player
local ownerScanAt = 0
local classCache = {}  -- player GUID -> "|cff......"

local function ScanPets()
    for k in pairs(owners) do owners[k] = nil end
    local function add(unit)
        if not UnitExists(unit) then return end
        local pg = UnitExists(unit .. "pet") and U.Str(UnitGUID(unit .. "pet"))
        if pg then owners[pg] = { guid = U.Str(UnitGUID(unit)), name = U.Str(UnitName(unit)) } end
    end
    add("player")
    if IsInRaid and IsInRaid() then
        for i = 1, (GetNumGroupMembers and GetNumGroupMembers() or 40) do add("raid" .. i) end
    else
        for i = 1, 4 do add("party" .. i) end
    end
    ownerScanAt = GetTime()
end

local function ClassColor(guid)
    local c = classCache[guid]
    if c then return c end
    local cls
    if guid == myGUID then cls = FO.Player.class
    elseif GetPlayerInfoByGUID then local ok, _, eng = pcall(GetPlayerInfoByGUID, guid) if ok then cls = eng end end
    local rc = cls and RAID_CLASS_COLORS and RAID_CLASS_COLORS[cls]
    c = rc and rc.colorStr and ("|c" .. rc.colorStr) or "|cffffffff"
    classCache[guid] = c
    return c
end

-- Who gets the credit for this event: owner GUID, owner name, whether it came from a pet
local function Owner(ev)
    if ev.mine then return ev.srcGUID, ev.srcName, false end
    if ev.pet then return myGUID or "player", FO.Player.name or U.Str(UnitName("player")) or "You", true end
    local f = ev.srcFlags
    if not f or not ev.srcGUID or band(f, GROUP) == 0 then return nil end
    if band(f, TYPE_PLAYER) > 0 then return ev.srcGUID, ev.srcName, false end
    if band(f, TYPE_PET) > 0 or band(f, TYPE_GUARDIAN) > 0 then
        local o = owners[ev.srcGUID]
        if not o and GetTime() - ownerScanAt > SCAN_EVERY then ScanPets() o = owners[ev.srcGUID] end
        if o and o.guid then return o.guid, o.name, true end
        return ev.srcGUID, (ev.srcName or "?") .. " (pet)", true
    end
    return nil
end

local function Row(seg, guid, name)
    local r = seg.rows[guid]
    if not r then
        r = { guid = guid, name = name or "?", dmg = 0, heal = 0, over = 0, pet = 0, spells = {} }
        seg.rows[guid] = r
    elseif name and r.name == "?" then r.name = name end
    return r
end

function M:EndSegment(now)
    local seg = self.cur
    if not seg.start then return end
    seg.time = math.max(1, (seg.last or now) - seg.start)
    seg.ended = true
    self.total.time = self.total.time + seg.time
    self.fights = self.fights + 1
    self.last = seg
    self.cur = NewSeg()
end

local function Add(ev, field)
    local amt = ev.amount
    if amt == nil then M.hidden = M.hidden + 1 return end
    local guid, name, isPet = Owner(ev)
    if not guid then return end
    local now = GetTime()
    if M.cur.last and now - M.cur.last > GAP then M:EndSegment(now) end
    local eff, over = amt, 0
    if field == "heal" then over = ev.over or 0 eff = math.max(0, amt - over) end
    for _, seg in ipairs({ M.cur, M.total }) do
        if not seg.start then seg.start = now end
        seg.last = now
        local r = Row(seg, guid, name)
        r[field] = r[field] + eff
        if field == "dmg" and isPet then r.pet = r.pet + eff end
        if field == "heal" then r.over = r.over + over end
        if guid == myGUID and ev.spellName then r.spells[ev.spellName] = (r.spells[ev.spellName] or 0) + eff end
        seg[field] = seg[field] + eff
    end
end

M.messages = {
    FO_CL_DAMAGE = function(self, ev)
        -- damage to a group member (Life Tap, Hellfire, friendly fire) is not meter damage
        if ev.dstFlags and band(ev.dstFlags, GROUP) > 0 then return end
        Add(ev, "dmg")
    end,
    FO_CL_HEAL = function(self, ev) Add(ev, "heal") end,
}

M.events = {
    UNIT_PET = function(self) ScanPets() end,
    GROUP_ROSTER_UPDATE = function(self) ScanPets() end,
    PLAYER_ENTERING_WORLD = function(self) myGUID = U.Str(UnitGUID("player")) or myGUID ScanPets() end,
}

function M:OnTick(now)
    if self.cur.last and now - self.cur.last > GAP then self:EndSegment(now) end
end

function M:OnEnable()
    myGUID = U.Str(UnitGUID("player"))
    ScanPets()
    if FO.Dashboard and FO.Dashboard.RegisterTab then FO.Dashboard:RegisterTab("Meter", 1.7, function() return self:Lines() end) end
end

function M:Reset()
    self.cur, self.last, self.total = NewSeg(), nil, NewSeg()
    self.hidden, self.fights = 0, 0
end

function M:Available() return FO.CombatLog and FO.CombatLog.available end

-- Active seconds of a segment; the session total adds the live segment on top of the closed ones
function M:Duration(seg)
    if seg == self.total then
        local live = self.cur.start and ((self.cur.last or self.cur.start) - self.cur.start) or 0
        return math.max(1, seg.time + live)
    end
    if seg.ended then return seg.time end
    return math.max(1, (seg.last or 0) - (seg.start or 0))
end

-- Sorted rows for a segment: field is "dmg" or "heal"
function M:Table(seg, field)
    seg = seg or self.cur
    local dur = self:Duration(seg)
    local total = seg[field] or 0
    local rows = {}
    for _, r in pairs(seg.rows) do
        if r[field] > 0 then
            rows[#rows + 1] = { guid = r.guid, name = r.name, value = r[field], rate = r[field] / dur, pct = total > 0 and r[field] / total or 0,
                                pet = r.pet, over = r.over, mine = r.guid == myGUID, spells = r.spells }
        end
    end
    table.sort(rows, function(a, b) return a.value > b.value end)
    return rows, dur, total
end

local function Which(arg)
    arg = (arg or ""):lower()
    if arg:find("session") or arg:find("total") then return M.total, "session" end
    if arg:find("last") then return M.last or M.cur, "last fight" end
    if M.cur.start then return M.cur, "fight" end
    return M.last or M.cur, M.last and "last fight" or "fight"
end

local function Short(n)
    if n >= 100000 then return string.format("%.0fk", n / 1000) end
    if n >= 10000 then return string.format("%.1fk", n / 1000) end
    return string.format("%.0f", n)
end

function M:Lines()
    if not self:Available() then return { "|cffaaaaaacombat log unavailable|r" } end
    local mode = (self.db.mode == "hps") and "heal" or "dmg"
    local seg, label = Which("")
    local rows, dur, total = self:Table(seg, mode)
    local out = { string.format("|cffffd100%s|r %s %s  total %s%s", mode == "dmg" and "DPS" or "HPS", label, U.FormatDuration(dur), Short(total),
                                self.hidden > 0 and string.format("  |cffff6060%d hidden|r", self.hidden) or "") }
    if #rows == 0 then out[#out + 1] = "no group " .. (mode == "dmg" and "damage" or "healing") .. " yet" return out end
    for i = 1, math.min(#rows, self.db.rows or 8) do
        local r = rows[i]
        local extra = ""
        if mode == "dmg" and r.pet > 0 then extra = string.format(" |cffaaaaaapet %.0f%%|r", r.pet / r.value * 100)
        elseif mode == "heal" and r.over > 0 then extra = string.format(" |cffaaaaaaover %.0f%%|r", r.over / (r.value + r.over) * 100) end
        out[#out + 1] = string.format("%d. %s%s|r %s/s  %.0f%%%s", i, ClassColor(r.guid), U.Trunc(r.name, 12), Short(r.rate), r.pct * 100, extra)
    end
    return out
end

local function PrintTable(field, arg)
    if not M:Available() then print("combat log not available on this client; see /fo combatlog.") return end
    local seg, label = Which(arg)
    local rows, dur, total = M:Table(seg, field)
    local word = field == "dmg" and "damage" or "healing"
    print("%s, %s (%s active): %s %s%s", field == "dmg" and "DPS" or "HPS", label, U.FormatDuration(dur), Short(total), word,
          M.hidden > 0 and string.format(", %d amounts hidden by the client", M.hidden) or "")
    if #rows == 0 then print("  no group %s recorded. Party and raid members count once their events reach your combat log.", word) return end
    for i, r in ipairs(rows) do
        local extra = ""
        if field == "dmg" and r.pet > 0 then extra = string.format("  pet %.0f%%", r.pet / r.value * 100) end
        if field == "heal" and r.over > 0 then extra = string.format("  overheal %.0f%%", r.over / (r.value + r.over) * 100) end
        print("  %2d. %s%-14s|r %8s  %7s/s  %5.1f%%%s", i, ClassColor(r.guid), U.Trunc(r.name, 14), Short(r.value), Short(r.rate), r.pct * 100, extra)
        if r.mine and next(r.spells) then
            local sp = {}
            for name, v in pairs(r.spells) do sp[#sp + 1] = { name, v } end
            table.sort(sp, function(a, b) return a[2] > b[2] end)
            local parts = {}
            for j = 1, math.min(5, #sp) do parts[#parts + 1] = string.format("%s %.0f%%", sp[j][1], sp[j][2] / r.value * 100) end
            print("      |cffaaaaaa%s|r", table.concat(parts, ", "))
        end
    end
end

M.commands = {
    dps = { help = "[fight|last|session] — group damage by player, pets credited to owners (combat log)", fn = function(self, arg) PrintTable("dmg", arg) end },
    hps = { help = "[fight|last|session] — group healing by player with overheal (combat log)", fn = function(self, arg) PrintTable("heal", arg) end },
    meter = {
        help = "Meter status | reset | rows <n> | mode dps|hps (HUD tab)",
        fn = function(self, arg)
            local sub, rest = U.SplitCmd(arg or "")
            if sub == "reset" then self:Reset() print("meter reset.") return end
            if sub == "rows" and tonumber(rest) then self.db.rows = math.max(1, math.min(11, tonumber(rest))) print("meter shows %d rows on the HUD", self.db.rows) return end
            if sub == "mode" and (rest == "dps" or rest == "hps") then self.db.mode = rest print("meter HUD tab shows %s", rest:upper()) return end
            local pets = 0
            for _ in pairs(owners) do pets = pets + 1 end
            print("meter: %s | %s | %d fights this session, %s active | %d pets mapped to owners | %d hidden amounts | HUD mode %s, %d rows",
                  self:Available() and "combat log live" or "combat log unavailable", self.cur.start and "in a fight" or "idle",
                  self.fights, U.FormatDuration(self:Duration(self.total)), pets, self.hidden, (self.db.mode or "dps"):upper(), self.db.rows or 8)
        end,
    },
}

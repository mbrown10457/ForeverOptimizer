local ADDON, FO = ...
local U = FO.Util
local print = FO:Printer("Core")

-- ===========================================================================
-- Combat log adapter. Built on the optimistic assumption that the Forever
-- client lets addons register COMBAT_LOG_EVENT_UNFILTERED and read amounts.
-- Registration is attempted in a pcall; if the client refuses it, or hides
-- amounts as secret values, FO.CombatLog.available / amountsHidden say so and
-- every consumer falls back to the chat-line and loot-window paths.
--
-- Each event is normalised into one reused table and fired as:
--   FO_CL_DAMAGE, FO_CL_MISS, FO_CL_HEAL, FO_CL_ENERGIZE, FO_CL_AURA,
--   FO_CL_CAST, FO_CL_DIED, FO_CL_OTHER            (handler(ev))
-- ev = { t, sub, suffix, srcGUID, srcName, srcFlags, dstGUID, dstName, dstFlags,
--        spellID, spellName, school, periodic, amount, over, crit, absorbed,
--        missType, auraType, powerType, mine, pet, toMe, secret }
-- ===========================================================================
local CL = FO:NewModule("Core.CombatLog", {})
FO.CombatLog = CL
CL.registered, CL.available, CL.amountsHidden = false, false, false
CL.count, CL.amountEvents, CL.secretEvents, CL.firstAt, CL.lastAt = 0, 0, 0, nil, nil
CL.kinds = {}

local band = (bit and bit.band) or function(a, b)
    local r, p = 0, 1
    while a > 0 and b > 0 do
        if a % 2 == 1 and b % 2 == 1 then r = r + p end
        a, b, p = math.floor(a / 2), math.floor(b / 2), p * 2
    end
    return r
end
local MINE = COMBATLOG_OBJECT_AFFILIATION_MINE or 0x1
local TYPE_PET = COMBATLOG_OBJECT_TYPE_PET or 0x1000
local TYPE_GUARDIAN = COMBATLOG_OBJECT_TYPE_GUARDIAN or 0x2000

local playerGUID, petGUID
local ev = {}

local function IsMyPet(guid, flags)
    if petGUID and guid == petGUID then return true end
    flags = U.Num(flags)
    if not flags then return false end
    return band(flags, MINE) > 0 and (band(flags, TYPE_PET) > 0 or band(flags, TYPE_GUARDIAN) > 0)
end

-- amount fields: nil when secret; ev.secret flags that something was hidden
local function Amt(v)
    if v == nil then return nil end
    if U.IsSecret(v) then ev.secret = true return nil end
    return U.Num(v)
end

local AMOUNT_KINDS = { DAMAGE = true, HEAL = true, ENERGIZE = true }
local WINDOW = 50                      -- last N amount-bearing events decide whether amounts are hidden
local recent, recentPos, recentFill, recentSecret = {}, 0, 0, 0

function CL:Handle(...)
    local t, sub, _, sGUID, sName, sFlags, _, dGUID, dName, dFlags = ...
    if type(sub) ~= "string" then return end
    for k in pairs(ev) do ev[k] = nil end
    ev.t, ev.sub = U.Num(t), sub
    ev.srcGUID, ev.srcName, ev.srcFlags = U.Str(sGUID), U.Str(sName), U.Num(sFlags)
    ev.dstGUID, ev.dstName, ev.dstFlags = U.Str(dGUID), U.Str(dName), U.Num(dFlags)

    local off, suffix = 12, sub
    if sub:sub(1, 15) == "SPELL_PERIODIC_" then ev.periodic = true suffix = sub:sub(16) off = 15
    elseif sub:sub(1, 15) == "SPELL_BUILDING_" then suffix = sub:sub(16) off = 15
    elseif sub:sub(1, 6) == "SWING_" then suffix = sub:sub(7) ev.spellName = "Melee" off = 12
    elseif sub:sub(1, 6) == "RANGE_" then suffix = sub:sub(7) off = 15
    elseif sub:sub(1, 6) == "SPELL_" then suffix = sub:sub(7) off = 15
    elseif sub:sub(1, 14) == "ENVIRONMENTAL_" then suffix = sub:sub(15) ev.spellName = "Environment" off = 13
    end
    if off == 15 then
        local spellID, spellName, school = select(12, ...)
        ev.spellID, ev.spellName, ev.school = U.Num(spellID), U.Str(spellName), U.Num(school)
    end
    ev.suffix = suffix

    local kind = "OTHER"
    if suffix == "DAMAGE" then
        local amount, over, _, _, _, absorbed, crit = select(off, ...)
        ev.amount, ev.over, ev.absorbed, ev.crit = Amt(amount), Amt(over), Amt(absorbed), crit == true
        kind = "DAMAGE"
    elseif suffix == "MISSED" then
        local missType, _, amountMissed = select(off, ...)
        ev.missType, ev.amount = U.Str(missType), Amt(amountMissed)
        kind = "MISS"
    elseif suffix == "HEAL" then
        local amount, over, absorbed, crit = select(off, ...)
        ev.amount, ev.over, ev.absorbed, ev.crit = Amt(amount), Amt(over), Amt(absorbed), crit == true
        kind = "HEAL"
    elseif suffix == "ENERGIZE" then
        local amount, over, powerType = select(off, ...)
        ev.amount, ev.over, ev.powerType = Amt(amount), Amt(over), U.Num(powerType)
        kind = "ENERGIZE"
    elseif suffix == "DRAIN" or suffix == "LEECH" then
        local amount, powerType = select(off, ...)
        ev.amount, ev.powerType = Amt(amount), U.Num(powerType)
        kind = "ENERGIZE"
    elseif suffix:sub(1, 5) == "AURA_" then
        local auraType, amount = select(off, ...)
        ev.auraType, ev.amount = U.Str(auraType), Amt(amount)
        kind = "AURA"
    elseif suffix:sub(1, 5) == "CAST_" then
        kind = "CAST"
    elseif sub == "UNIT_DIED" or sub == "UNIT_DESTROYED" or sub == "PARTY_KILL" then
        kind = "DIED"
    end

    ev.mine = ev.srcGUID ~= nil and ev.srcGUID == playerGUID
    ev.pet = not ev.mine and IsMyPet(ev.srcGUID, ev.srcFlags)
    ev.toMe = ev.dstGUID ~= nil and ev.dstGUID == playerGUID

    self.count = self.count + 1
    self.lastAt = GetTime()
    if not self.firstAt then self.firstAt = self.lastAt end
    -- amounts are "hidden" when nearly every event that carries an amount came back secret;
    -- casts and deaths carry none, so they must not dilute the ratio
    if AMOUNT_KINDS[kind] then
        self.amountEvents = self.amountEvents + 1
        if ev.secret then self.secretEvents = self.secretEvents + 1 end
        recentPos = recentPos % WINDOW + 1
        if recentFill < WINDOW then recentFill = recentFill + 1 elseif recent[recentPos] then recentSecret = recentSecret - 1 end
        recent[recentPos] = ev.secret == true
        if ev.secret then recentSecret = recentSecret + 1 end
        if recentFill >= 20 then self.amountsHidden = recentSecret >= recentFill * 0.9 end
    end
    self.kinds[kind] = (self.kinds[kind] or 0) + 1
    FO:Fire("FO_CL_" .. kind, ev)
end

function CL:OnEnable()
    playerGUID = U.Str(UnitGUID("player"))
    petGUID = UnitExists("pet") and U.Str(UnitGUID("pet")) or nil
    FO:RegisterEvent("UNIT_PET", function(unit) if unit == "player" then petGUID = UnitExists("pet") and U.Str(UnitGUID("pet")) or nil end end)
    FO:RegisterEvent("PLAYER_ENTERING_WORLD", function() playerGUID = U.Str(UnitGUID("player")) or playerGUID end)

    local f = CreateFrame("Frame")
    -- Forever's client has no CombatLogGetCurrentEventInfo, and registering
    -- COMBAT_LOG_EVENT_UNFILTERED there is a forbidden action (the "blocked from an
    -- action only available to the Blizzard UI" dialog at every login). Check the
    -- API first and never register the event without it.
    if type(CombatLogGetCurrentEventInfo) ~= "function" then
        self.registered, self.reason = false, "CombatLogGetCurrentEventInfo missing"
    else
        local ok, err = pcall(f.RegisterEvent, f, "COMBAT_LOG_EVENT_UNFILTERED")
        self.registered = ok and true or false
        self.reason = ok and nil or tostring(err)
        if ok then
            self.available = true
            -- one fixed closure, no per-event argument packing: the hottest path in the addon
            local function HandleCurrent() return CL:Handle(CombatLogGetCurrentEventInfo()) end
            f:SetScript("OnEvent", function() FO.TryCall("combat log", HandleCurrent) end)
        end
    end
    self.frame = f
    if not self.available then print("combat log not available (%s); class analytics use chat/loot paths.", tostring(self.reason)) end
end

function CL:ClientRestricted()
    if C_CombatLog and C_CombatLog.IsCombatLogRestricted then
        local ok, r = pcall(C_CombatLog.IsCombatLogRestricted)
        if ok then return r == true end
    end
    return nil
end

function CL:Status()
    if not self.available then return "unavailable" end
    local r = self:ClientRestricted()
    if r == true and self.count == 0 then return "registered but the client reports the log restricted here" end
    if self.count == 0 then return "registered, no events yet" end
    if self.amountsHidden then return "events flow but amounts are secret" end
    return "live"
end

CL.commands = {
    combatlog = {
        help = "Combat log availability and event counts",
        fn = function(self)
            print("combat log: %s%s", self:Status(), self.reason and (" (" .. self.reason .. ")") or "")
            local r = self:ClientRestricted()
            if r ~= nil then print("  C_CombatLog.IsCombatLogRestricted(): %s", tostring(r)) end
            if self.count > 0 then
                local span = math.max(1, (self.lastAt or 0) - (self.firstAt or 0))
                print("  %d events (%.1f/s while active), %d of %d amount-bearing events secret", self.count, self.count / span, self.secretEvents, self.amountEvents)
                local parts = {}
                for k, n in pairs(self.kinds) do parts[#parts + 1] = string.format("%s %d", k:lower(), n) end
                table.sort(parts)
                print("  " .. table.concat(parts, ", "))
            end
        end,
    },
}

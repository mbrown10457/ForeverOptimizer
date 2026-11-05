local ADDON, FO = ...
local U = FO.Util
local print = FO:Printer("Core")

-- ===========================================================================
-- Best-effort combat feed for a client without a combat log (Forever). The
-- client still fires UNIT_COMBAT for every hit, heal and miss on the units it
-- tracks (you, your pet, your target, party members, nameplates) with an
-- amount and a school, but no source and no spell. This module turns those
-- into the same FO_CL_* events the meter, the combat stats, the rotation
-- analysis and the class tabs already consume, attributing them:
--   damage on a hostile unit   -> you, or your pet when it is on that unit and
--                                 you cast nothing physical in the last second
--   spell name                 -> your last successful cast of that school
--                                 (a running DoT of that school counts as
--                                 periodic), else Melee
--   damage on you              -> taken, from your current hostile target
--   heals on friendly units    -> you when solo or when you just cast a heal
--   deaths                     -> the XP chat line, matched to the last hostile
--                                 of that name you hit (UNIT_DIED when it has a unit)
-- The same hit arrives once per unit token pointing at the unit (target and
-- nameplate3 are one mob), so identical events in one frame are dropped.
-- Numbers are estimates: in a group, damage on your target by others is yours.
-- Everything runs only when Core.CombatLog could not register the real log.
-- ===========================================================================
local CF = FO:NewModule("Core.CombatFeed", {})
FO.CombatFeed = CF
CF.active, CF.count, CF.dropped, CF.reason = false, 0, 0, nil
CF.readable, CF.secret = { hostile = 0, me = 0, pet = 0, other = 0 }, { hostile = 0, me = 0, pet = 0, other = 0 }   -- amounts by unit kind

local CAST_WINDOW, PHYS_WINDOW, HEAL_WINDOW = 2.5, 1.0, 2.5
local PHYSICAL = 1
local MINE = COMBATLOG_OBJECT_AFFILIATION_MINE or 0x1
local MISSES = { MISS = true, DODGE = true, PARRY = true, BLOCK = true, RESIST = true, ABSORB = true, IMMUNE = true, EVADE = true, DEFLECT = true, REFLECT = true }
local AUTO = { ["Auto Shot"] = true, ["Shoot"] = true }

local playerGUID, petGUID
local lastBySchool = {}      -- school mask -> { name, id, t, dotUntil }
local lastAny                -- newest cast of any school
local lastHeal               -- { name, id, t }
local seenNames = {}         -- hostile name -> guid last hit, for deaths reported by chat
local lastKey, lastKeyAt
local xpPattern

local function Seed(id) local sp = FO.Seed and FO.Seed.spells return sp and sp[id] end

local function SpellName(id)
    local row = Seed(id)
    if row then return row[1] end
    if C_Spell and C_Spell.GetSpellName then local ok, n = pcall(C_Spell.GetSpellName, id) if ok then return U.Str(n) end end
    if GetSpellInfo then local n = GetSpellInfo(id) return U.Str(n) end
end

local function RefreshGUIDs()
    playerGUID = U.Str(UnitGUID("player")) or playerGUID
    petGUID = UnitExists("pet") and U.Str(UnitGUID("pet")) or nil
end

local function NoteCast(spellID)
    spellID = U.Num(spellID)
    if not spellID then return end
    local row = Seed(spellID)
    local name = (row and row[1]) or SpellName(spellID)
    if not name then return end
    local now = GetTime()
    local school = row and U.Num(row[12]) or nil
    local heals = row and ((U.Num(row[14]) or 0) > 0 or (U.Num(row[16]) or 0) > 0)
    local dotTick = row and (U.Num(row[15]) or 0) or 0
    local duration = row and (U.Num(row[11]) or 0) / 1000 or 0
    local c = { name = name, id = spellID, t = now, dotUntil = dotTick > 0 and duration > 0 and (now + duration) or nil }
    if school then lastBySchool[school] = c end
    lastAny = c
    if heals then lastHeal = c end
    return name
end

-- name, spellID, periodic, sub for a hit of the given school on a hostile unit
local function Attribute(school, now)
    if school == PHYSICAL then
        local c = lastBySchool[PHYSICAL]
        if c and now - c.t <= PHYS_WINDOW then return c.name, c.id, false, AUTO[c.name] and "RANGE_DAMAGE" or "SPELL_DAMAGE" end
        return "Melee", nil, false, "SWING_DAMAGE"
    end
    local c = school and lastBySchool[school]
    if c and now - c.t <= CAST_WINDOW then return c.name, c.id, false, "SPELL_DAMAGE" end
    if c and c.dotUntil and now <= c.dotUntil then return c.name, c.id, true, "SPELL_PERIODIC_DAMAGE" end
    if lastAny and now - lastAny.t <= CAST_WINDOW then return lastAny.name, lastAny.id, false, "SPELL_DAMAGE" end
    for _, d in pairs(lastBySchool) do
        if d.dotUntil and now <= d.dotUntil then return d.name, d.id, true, "SPELL_PERIODIC_DAMAGE" end
    end
    return "Unknown", nil, false, "SPELL_DAMAGE"
end

local function PetOn(guid)
    if not petGUID then return false end
    local tg = UnitExists("pettarget") and U.Str(UnitGUID("pettarget"))
    return tg == guid
end

local function HostileTarget()
    if UnitExists("target") and UnitCanAttack("player", "target") then
        return U.Str(UnitGUID("target")), U.Str(UnitName("target"))
    end
    return "Unknown-0", "?"
end

-- descriptor and amount arrive as secret values in combat on Forever; a key built from a
-- secret is itself secret and cannot be compared, so only plain values go into it
local function Dup(guid, action, descriptor, amount, now)
    local key = guid .. "|" .. action .. "|" .. tostring(descriptor) .. "|" .. tostring(amount)
    if key == lastKey and lastKeyAt == now then return true end
    lastKey, lastKeyAt = key, now
    return false
end

local function Emit(fields, kind)
    CF.count = CF.count + 1
    fields.estimated = true
    FO.CombatLog:Feed(fields, kind)
end

local function OnUnitCombat(unit, action, descriptor, amount, school)
    local CL = FO.CombatLog
    if not CL or not CF.active then return end
    unit, action = U.Str(unit), U.Str(action)
    if not unit or not action then return end
    local guid = U.Str(UnitGUID(unit))
    if not guid then return end
    local now = GetTime()
    local secretAmt = U.IsSecret(amount)
    if secretAmt then amount = nil end
    descriptor = U.IsSecret(descriptor) and nil or U.Str(descriptor)
    if Dup(guid, action, descriptor, secretAmt and "?" or amount, now) then CF.dropped = CF.dropped + 1 return end
    if not playerGUID then RefreshGUIDs() end
    school = U.Num(school)
    local crit = descriptor == "CRITICAL"
    local name = U.Str(UnitName(unit))
    local isMe = unit == "player" or guid == playerGUID
    local isPet = petGUID ~= nil and guid == petGUID
    local hostile = not isMe and not isPet and UnitCanAttack("player", unit) == true
    local kindKey = hostile and "hostile" or isMe and "me" or isPet and "pet" or "other"
    if action == "WOUND" or action == "HEAL" then
        local t = secretAmt and CF.secret or CF.readable
        t[kindKey] = t[kindKey] + 1
    end

    if hostile then
        if name then seenNames[name] = guid end
        if action == "WOUND" then
            local spellName, spellID, periodic, sub = Attribute(school, now)
            local pet = spellID == nil and school == PHYSICAL and PetOn(guid)
            Emit({ sub = sub, suffix = "DAMAGE", srcGUID = pet and petGUID or playerGUID, srcName = pet and U.Str(UnitName("pet")) or (FO.Player.name or "You"),
                   srcFlags = MINE, dstGUID = guid, dstName = name, dstFlags = 0,
                   spellID = spellID, spellName = spellName, school = school, periodic = periodic,
                   amount = amount, crit = crit, mine = not pet, pet = pet, toMe = false }, "DAMAGE")
        elseif MISSES[action] then
            local spellName, spellID, _, sub = Attribute(school, now)
            Emit({ sub = sub:gsub("DAMAGE", "MISSED"), suffix = "MISSED", srcGUID = playerGUID, srcFlags = MINE, dstGUID = guid, dstName = name, dstFlags = 0,
                   spellID = spellID, spellName = spellName, missType = action, mine = true, pet = false, toMe = false }, "MISS")
        end
        return
    end

    if action == "WOUND" and isMe then
        local sg, sn = HostileTarget()
        Emit({ sub = "SWING_DAMAGE", suffix = "DAMAGE", srcGUID = sg, srcName = sn, srcFlags = 0,
               dstGUID = playerGUID, dstName = FO.Player.name, dstFlags = MINE, spellName = "Melee", school = school,
               amount = amount, crit = crit, mine = false, pet = false, toMe = true }, "DAMAGE")
    elseif action == "HEAL" and (isMe or isPet or not UnitCanAttack("player", unit)) then
        local recent = lastHeal and now - lastHeal.t <= HEAL_WINDOW
        local solo = not (IsInGroup and IsInGroup())
        if not (recent or solo) then return end
        Emit({ sub = "SPELL_HEAL", suffix = "HEAL", srcGUID = playerGUID, srcName = FO.Player.name, srcFlags = MINE,
               dstGUID = guid, dstName = name, dstFlags = isMe and MINE or 0,
               spellID = recent and lastHeal.id or nil, spellName = recent and lastHeal.name or "Heal", school = school,
               amount = amount, over = 0, crit = crit, mine = true, pet = false, toMe = isMe }, "HEAL")
    end
end

local function OnCast(unit, _, spellID)
    if unit ~= "player" or not CF.active then return end
    local name = NoteCast(spellID)
    if not name then return end
    Emit({ sub = "SPELL_CAST_SUCCESS", suffix = "CAST_SUCCESS", srcGUID = playerGUID, srcName = FO.Player.name, srcFlags = MINE,
           spellID = U.Num(spellID), spellName = name, mine = true, pet = false, toMe = false }, "CAST")
end

local function Died(guid, name)
    if not guid then return end
    Emit({ sub = "UNIT_DIED", suffix = "UNIT_DIED", dstGUID = guid, dstName = name, dstFlags = 0, mine = false, pet = false, toMe = false }, "DIED")
end

local function OnXPLine(msg)
    msg = U.Str(msg)
    if not msg or not CF.active then return end
    if not xpPattern then
        local base = COMBAT_XP_GAIN1 or COMBAT_XP_GAIN or "%s dies, you gain %d experience."
        xpPattern = U.GlobalStringToPattern and U.GlobalStringToPattern(base) or "^(.-) dies, you gain (%d+) experience"
    end
    local name = msg:match(xpPattern)
    if not name then return end
    local guid = seenNames[name]
    if guid then seenNames[name] = nil Died(guid, name) end
end

function CF:OnEnable()
    local CL = FO.CombatLog
    if not CL then self.reason = "no combat log adapter" return end
    if CL.available then self.reason = "real combat log in use" return end
    RefreshGUIDs()
    FO:RegisterEvent("UNIT_COMBAT", OnUnitCombat)
    FO:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED", OnCast)
    FO:RegisterEvent("CHAT_MSG_COMBAT_XP_GAIN", OnXPLine)
    FO:RegisterEvent("UNIT_DIED", function(unit) if type(unit) == "string" and UnitExists(unit) then Died(U.Str(UnitGUID(unit)), U.Str(UnitName(unit))) end end)
    FO:RegisterEvent("UNIT_PET", function(unit) if unit == "player" then RefreshGUIDs() end end)
    FO:RegisterEvent("PLAYER_ENTERING_WORLD", RefreshGUIDs)
    self.active = true
    CL.available, CL.estimated, CL.source, CL.reason = true, true, "UNIT_COMBAT feed", nil
    print("combat log absent; damage, healing and casts are estimated from hits on your units (/fo combatlog).")
end

CF.commands = {
    combatfeed = {
        help = "The UNIT_COMBAT stand-in for the combat log: event counts and the current spell attribution",
        fn = function(self)
            if not self.active then print("combat feed inactive (%s).", self.reason or "?") return end
            print("combat feed: %d events (%d duplicate unit tokens dropped). Attribution: last cast per school within %.1fs, DoTs for their duration, else Melee.", self.count, self.dropped, CAST_WINDOW)
            local r, s = self.readable, self.secret
            print("  amounts readable / secret: on hostiles %d / %d, on you %d / %d, on your pet %d / %d, on others %d / %d", r.hostile, s.hostile, r.me, s.me, r.pet, s.pet, r.other, s.other)
            local now = GetTime()
            local parts = {}
            for school, c in pairs(lastBySchool) do parts[#parts + 1] = string.format("school %d: %s (%.0fs ago%s)", school, c.name, now - c.t, (c.dotUntil and now <= c.dotUntil) and ", DoT running" or "") end
            table.sort(parts)
            for _, p in ipairs(parts) do print("  " .. p) end
            if lastHeal then print("  last heal: %s (%.0fs ago)", lastHeal.name, now - lastHeal.t) end
        end,
    },
}

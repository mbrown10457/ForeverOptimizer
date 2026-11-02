local ADDON, FO = ...
local U = FO.Util
local print = FO:Printer("Grinding")

-- ===========================================================================
-- Combat analytics from the combat log (when Core.CombatLog is available):
--   damage by spell and by source (you vs pet), damage taken, fight lengths,
--   healing with overheal, mana spent per spell (cost read at cast time),
--   mana gained (Life Tap, potions), DoT efficiency (ticks delivered vs lost
--   to early refresh or the target dying), auto-shot / wand clipping.
-- Class modules read CS:Stats() for their lines; MobDatabase gets FO_FIGHT.
-- Everything here is per session; lifetime per-spell totals go to db.lifetime.
-- ===========================================================================
local CS = FO:NewModule("Grinding.CombatStats", { account = "combat", defaults = { lifetime = {} } })
FO.CombatStats = CS

local AUTO_SPELLS = { ["Auto Shot"] = "ranged", ["Shoot"] = "ranged" }
local FIGHT_TIMEOUT = 120

local function Fresh()
    return {
        start = GetTime(),
        dmg = { player = { n = 0, total = 0, crit = 0 }, pet = { n = 0, total = 0, crit = 0 } },
        taken = { n = 0, total = 0 },
        bySpell = {}, heal = {}, mana = {}, energize = {}, dots = {}, autos = {}, misses = {},
        fights = 0, fightTime = 0,
    }
end
CS.s = Fresh()
local active = {}   -- dot instances: dstGUID.."|"..spell -> { ticks, at }
local fights = {}   -- dstGUID -> { start, npcID, name, done, taken, last }

local costCache = {}
local function SpellCost(spellID)
    if not spellID then return nil end
    local c = costCache[spellID]
    if c ~= nil then return c or nil end
    local list
    if C_Spell and C_Spell.GetSpellPowerCost then list = C_Spell.GetSpellPowerCost(spellID)
    elseif GetSpellPowerCost then list = GetSpellPowerCost(spellID) end
    local mana = 0
    for _, p in ipairs(type(list) == "table" and list or {}) do
        if (U.Num(p.type) or 0) == 0 then mana = mana + (U.Num(p.cost) or 0) end
    end
    costCache[spellID] = mana > 0 and mana or false
    return mana > 0 and mana or nil
end

local function RangedSpeed()
    if not UnitRangedDamage then return nil end
    local speed = U.Num((UnitRangedDamage("player")))
    return speed and speed > 0 and speed or nil
end

local function Bucket(t, name, init)
    local b = t[name]
    if not b then b = init t[name] = b end
    return b
end

local function Fight(guid, name, now)
    local f = fights[guid]
    if not f then
        f = { start = now, npcID = U.NpcIDFromGUID(guid), name = name, done = 0, taken = 0, last = now }
        fights[guid] = f
    end
    f.last = now
    return f
end

-- Auto shot / wand timing: one shot per cast-success (or per landed shot when the cast event is missing)
local function Shot(name, now)
    local a = Bucket(CS.s.autos, name, { shots = 0, gapSum = 0, gapN = 0, clipped = 0, speed = nil })
    if a.lastAt and now - a.lastAt < 0.3 then return end       -- same shot reported twice
    a.speed = RangedSpeed() or a.speed
    if a.lastAt and a.speed then
        local gap = now - a.lastAt
        if gap <= a.speed * 2.5 then
            a.gapSum, a.gapN = a.gapSum + gap, a.gapN + 1
            if gap > a.speed * 1.05 then a.clipped = a.clipped + (gap - a.speed) end
        end
    end
    a.shots = a.shots + 1
    a.lastAt = now
end

local function DotBucket(name)
    return Bucket(CS.s.dots, name, { applied = 0, refreshed = 0, completed = 0, ticks = 0, dmg = 0, early = 0, truncated = 0, wasted = 0, maxTicks = 0 })
end

local function EndDotInstance(key, d, inst, byDeath)
    if byDeath then
        if d.maxTicks > inst.ticks then d.truncated = d.truncated + 1 d.wasted = d.wasted + (d.maxTicks - inst.ticks) end
    else
        d.completed = d.completed + 1
        if inst.ticks > d.maxTicks then d.maxTicks = inst.ticks end
    end
    active[key] = nil
end

CS.messages = {
    FO_SESSION_START = function(self) self:Reset() end,
    FO_SESSION_END = function(self) self:Archive() end,

    FO_CL_DAMAGE = function(self, ev)
        local s, now = self.s, GetTime()
        if ev.mine or ev.pet then
            local src = ev.pet and "pet" or "player"
            local amt = ev.amount or 0
            local d = s.dmg[src]
            d.n, d.total = d.n + 1, d.total + amt
            if ev.crit then d.crit = d.crit + 1 end
            local name = ev.spellName or "?"
            local b = Bucket(s.bySpell, name, { src = src, n = 0, total = 0, crit = 0, ticks = 0 })
            b.n, b.total = b.n + 1, b.total + amt
            if ev.crit then b.crit = b.crit + 1 end
            if ev.periodic then
                b.ticks = b.ticks + 1
                local dot = DotBucket(name)
                dot.ticks, dot.dmg = dot.ticks + 1, dot.dmg + amt
                local inst = ev.dstGUID and active[ev.dstGUID .. "|" .. name]
                if inst then inst.ticks = inst.ticks + 1 end
            end
            if ev.mine and AUTO_SPELLS[name] and ev.sub == "RANGE_DAMAGE" then Shot(name, now) end
            if ev.dstGUID then local f = Fight(ev.dstGUID, ev.dstName, now) f.done = f.done + amt end
        elseif ev.toMe and ev.srcGUID then
            local amt = ev.amount or 0
            s.taken.n, s.taken.total = s.taken.n + 1, s.taken.total + amt
            if ev.srcGUID:find("^Creature") or ev.srcGUID:find("^Vehicle") then
                local f = Fight(ev.srcGUID, ev.srcName, now) f.taken = f.taken + amt
            end
        end
    end,

    FO_CL_MISS = function(self, ev)
        if not ev.mine then return end
        local name = ev.spellName or "?"
        local m = Bucket(self.s.misses, name, { n = 0 })
        m.n = m.n + 1
        if AUTO_SPELLS[name] and ev.sub == "RANGE_MISSED" then Shot(name, GetTime()) end
    end,

    FO_CL_HEAL = function(self, ev)
        if not ev.mine then return end
        local h = Bucket(self.s.heal, ev.spellName or "?", { n = 0, total = 0, over = 0, crit = 0 })
        h.n, h.total, h.over = h.n + 1, h.total + (ev.amount or 0), h.over + (ev.over or 0)
        if ev.crit then h.crit = h.crit + 1 end
    end,

    FO_CL_ENERGIZE = function(self, ev)
        if not (ev.mine and ev.toMe) or (ev.powerType or 0) ~= 0 then return end
        local name = ev.spellName or "?"
        self.s.energize[name] = (self.s.energize[name] or 0) + (ev.amount or 0)
    end,

    FO_CL_CAST = function(self, ev)
        if not ev.mine or ev.suffix ~= "CAST_SUCCESS" then return end
        local name = ev.spellName or "?"
        local m = Bucket(self.s.mana, name, { casts = 0, mana = 0 })
        m.casts = m.casts + 1
        m.mana = m.mana + (SpellCost(ev.spellID) or 0)
        if AUTO_SPELLS[name] then Shot(name, GetTime()) end
    end,

    FO_CL_AURA = function(self, ev)
        if not ev.mine or ev.auraType ~= "DEBUFF" or not ev.dstGUID then return end
        local name = ev.spellName or "?"
        local key = ev.dstGUID .. "|" .. name
        if ev.suffix == "AURA_APPLIED" then
            local d = DotBucket(name)
            d.applied = d.applied + 1
            active[key] = { ticks = 0, at = GetTime() }
        elseif ev.suffix == "AURA_REFRESH" then
            local d = DotBucket(name)
            local inst = active[key]
            d.refreshed = d.refreshed + 1
            if inst then
                if d.maxTicks > inst.ticks then d.early = d.early + 1 d.wasted = d.wasted + (d.maxTicks - inst.ticks) end
                inst.ticks, inst.at = 0, GetTime()
            else
                active[key] = { ticks = 0, at = GetTime() }
            end
        elseif ev.suffix == "AURA_REMOVED" then
            local inst = active[key]
            if inst then EndDotInstance(key, DotBucket(name), inst, false) end
        end
    end,

    FO_CL_DIED = function(self, ev)
        local guid = ev.dstGUID
        if not guid then return end
        local now = GetTime()
        local f = fights[guid]
        if f then
            local dur = now - f.start
            fights[guid] = nil
            if dur >= 0 and dur < FIGHT_TIMEOUT then
                self.s.fights, self.s.fightTime = self.s.fights + 1, self.s.fightTime + dur
                FO:Fire("FO_FIGHT", f.npcID, guid, dur, f.done, f.taken, f.name)
            end
        end
        local prefix = guid .. "|"
        for key, inst in pairs(active) do
            if key:sub(1, #prefix) == prefix then
                local name = key:sub(#prefix + 1)
                EndDotInstance(key, DotBucket(name), inst, true)
            end
        end
    end,
}

function CS:OnTick(now)
    for guid, f in pairs(fights) do
        if now - f.last > FIGHT_TIMEOUT then fights[guid] = nil end
    end
end

function CS:Reset()
    self.s = Fresh()
    for k in pairs(active) do active[k] = nil end
    for k in pairs(fights) do fights[k] = nil end
end

-- Fold the session into lifetime per-class, per-spell totals
function CS:Archive()
    local cls = FO.Player and FO.Player.class or "?"
    local life = self.db.lifetime[cls]
    if not life then life = { spells = {}, sessions = 0 } self.db.lifetime[cls] = life end
    life.sessions = life.sessions + 1
    local function fold(name, fields)
        local r = life.spells[name]
        if not r then r = {} life.spells[name] = r end
        for k, v in pairs(fields) do r[k] = (r[k] or 0) + v end
    end
    for name, b in pairs(self.s.bySpell) do fold(name, { hits = b.n, dmg = b.total, crit = b.crit, ticks = b.ticks }) end
    for name, h in pairs(self.s.heal) do fold(name, { heals = h.n, healed = h.total, over = h.over }) end
    for name, m in pairs(self.s.mana) do fold(name, { casts = m.casts, mana = m.mana }) end
    for name, d in pairs(self.s.dots) do fold(name, { applied = d.applied, dotTicks = d.ticks, wasted = d.wasted }) end
end

function CS:Available()
    return FO.CombatLog and FO.CombatLog.available and not FO.CombatLog.amountsHidden
end

function CS:Stats()
    local s = self.s
    local total = s.dmg.player.total + s.dmg.pet.total
    local out = {
        available = self:Available(), elapsed = GetTime() - s.start,
        dmgTotal = total, dmgPlayer = s.dmg.player.total, dmgPet = s.dmg.pet.total,
        petShare = total > 0 and s.dmg.pet.total / total or nil,
        taken = s.taken.total, fights = s.fights, avgFight = s.fights > 0 and s.fightTime / s.fights or nil,
        spells = {}, heals = {}, dots = {}, autos = {}, manaSpent = 0, manaGained = 0, healTotal = 0, overTotal = 0,
    }
    for _, m in pairs(s.mana) do out.manaSpent = out.manaSpent + m.mana end
    for _, e in pairs(s.energize) do out.manaGained = out.manaGained + e end
    for name, b in pairs(s.bySpell) do
        local m = s.mana[name]
        out.spells[#out.spells + 1] = {
            name = name, src = b.src, n = b.n, total = b.total, crit = b.crit, ticks = b.ticks,
            share = total > 0 and b.total / total or 0,
            casts = m and m.casts or nil, mana = m and m.mana or nil,
            perMana = (m and m.mana > 0) and b.total / m.mana or nil,
            misses = s.misses[name] and s.misses[name].n or 0,
        }
    end
    table.sort(out.spells, function(a, b) return a.total > b.total end)
    for name, h in pairs(s.heal) do
        local m = s.mana[name]
        out.healTotal, out.overTotal = out.healTotal + h.total, out.overTotal + h.over
        out.heals[#out.heals + 1] = {
            name = name, n = h.n, total = h.total, over = h.over, crit = h.crit,
            overPct = (h.total + h.over) > 0 and h.over / (h.total + h.over) or 0,
            casts = m and m.casts or nil, mana = m and m.mana or nil,
            perMana = (m and m.mana > 0) and h.total / m.mana or nil,
        }
    end
    table.sort(out.heals, function(a, b) return a.total > b.total end)
    for name, d in pairs(s.dots) do
        if d.ticks > 0 then
            local m = s.mana[name]
            out.dots[#out.dots + 1] = {
                name = name, applied = d.applied, refreshed = d.refreshed, completed = d.completed, ticks = d.ticks, dmg = d.dmg,
                early = d.early, truncated = d.truncated, wasted = d.wasted, maxTicks = d.maxTicks,
                efficiency = (d.ticks + d.wasted) > 0 and d.ticks / (d.ticks + d.wasted) or 1,
                perMana = (m and m.mana > 0) and d.dmg / m.mana or nil,
                perApply = d.applied > 0 and d.dmg / d.applied or nil,
            }
        end
    end
    table.sort(out.dots, function(a, b) return a.dmg > b.dmg end)
    for name, a in pairs(s.autos) do
        local expected = a.speed and a.gapN > 0 and a.gapN * a.speed or nil
        out.autos[name] = {
            name = name, shots = a.shots, speed = a.speed, avgGap = a.gapN > 0 and a.gapSum / a.gapN or nil,
            clipped = a.clipped, clipPct = expected and expected > 0 and a.clipped / expected or nil,
        }
    end
    return out
end

local function Unavailable()
    print("combat log not available on this client (%s); see /fo combatlog.", FO.CombatLog and FO.CombatLog:Status() or "no adapter")
end

CS.commands = {
    combat = {
        help = "Damage by spell and source, mana, fights (combat log)",
        fn = function(self)
            if not self:Available() then Unavailable() return end
            local c = self:Stats()
            print("combat (%s): %d damage%s, %d taken, %d fights%s", U.FormatDuration(c.elapsed), c.dmgTotal,
                c.petShare and string.format(" (pet %.0f%%)", c.petShare * 100) or "", c.taken, c.fights,
                c.avgFight and string.format(" avg %.1fs", c.avgFight) or "")
            if c.manaSpent > 0 or c.manaGained > 0 then print("  mana spent %d, gained %d, %.1f damage per mana", c.manaSpent, c.manaGained, c.manaSpent > 0 and c.dmgTotal / c.manaSpent or 0) end
            for i = 1, math.min(8, #c.spells) do
                local sp = c.spells[i]
                print("  %-20s %5.0f%%  %6d dmg  %4d hits%s%s%s", U.Trunc(sp.name, 20), sp.share * 100, sp.total, sp.n,
                    sp.src == "pet" and " (pet)" or "", sp.perMana and string.format("  %.1f/mana", sp.perMana) or "",
                    sp.n > 0 and sp.crit > 0 and string.format("  %.0f%% crit", sp.crit / sp.n * 100) or "")
            end
        end,
    },
    dots = {
        help = "DoT efficiency: ticks delivered vs lost to refresh/death",
        fn = function(self)
            if not self:Available() then Unavailable() return end
            local c = self:Stats()
            if #c.dots == 0 then print("no periodic damage recorded this session.") return end
            for _, d in ipairs(c.dots) do
                print("%-18s eff %3.0f%%  %d applied, %d ticks (%d/full), %d early refresh, %d died early, %d ticks lost%s",
                    U.Trunc(d.name, 18), d.efficiency * 100, d.applied, d.ticks, d.maxTicks, d.early, d.truncated, d.wasted,
                    d.perMana and string.format(", %.1f dmg/mana", d.perMana) or "")
            end
        end,
    },
    heals = {
        help = "Healing per spell with overheal and mana efficiency",
        fn = function(self)
            if not self:Available() then Unavailable() return end
            local c = self:Stats()
            if #c.heals == 0 then print("no healing recorded this session.") return end
            for _, h in ipairs(c.heals) do
                print("%-18s %6d healed  %3.0f%% overheal  %d casts%s", U.Trunc(h.name, 18), h.total, h.overPct * 100, h.n,
                    h.perMana and string.format("  %.2f heal/mana", h.perMana) or "")
            end
        end,
    },
    autoshot = {
        help = "Auto Shot / wand clipping",
        fn = function(self)
            if not self:Available() then Unavailable() return end
            local c = self:Stats()
            local any = false
            for _, a in pairs(c.autos) do
                any = true
                print("%s: %d shots, avg gap %s vs speed %s, clipped %s (%s)", a.name, a.shots,
                    a.avgGap and string.format("%.2fs", a.avgGap) or "--", a.speed and string.format("%.2fs", a.speed) or "?",
                    U.FormatDuration(a.clipped), a.clipPct and string.format("%.0f%% of shot time lost", a.clipPct * 100) or "n/a")
            end
            if not any then print("no auto shots or wand shots recorded this session.") end
        end,
    },
}

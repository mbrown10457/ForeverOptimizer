local ADDON, FO = ...
local U = FO.Util
local print = FO:Printer("Grinding")

-- ===========================================================================
-- Persistent per-mob intelligence.
-- db.mobs[npcID] = { name, level, type, classification, zone,
--                    kills, xp, looted, deaths, killTime, killN, spots={{mapID,x,y}},
--                    drops = { [itemID] = { name, count } } }
-- db.zones[zoneName] = { [npcID] = kills }
-- Resistances aren't observable without the combat log; we track your deaths
-- and time-to-kill, which is what you feel anyway.
-- ===========================================================================
local MD = FO:NewModule("Grinding.MobDatabase", {
    account = "mobs",
    defaults = { mobs = {}, zones = {}, encounters = {} },   -- encounters: raw per-kill log, newest last (cap 500)
})

-- Encounters since combat started; the post-fight health/mana deficit is attached to them.
local pending = {}
local MAX_ENCOUNTERS = 500

local MAX_SPOTS = 25
local engaged = {}       -- name -> { guid, npcID, firstSeen, level, type, classification }
local lastHostileName
local combatStart
local lastKillAt         -- GetTime of previous kill, for gap-between-kills

function MD:Mob(npcID, name)
    if not npcID then return nil end
    local m = self.db.mobs[npcID]
    if not m then
        m = { name = name, kills = 0, xp = 0, drops = {} }
        self.db.mobs[npcID] = m
    elseif name and (not m.name or m.name == "?") then
        m.name = name
    end
    return m
end

function MD:ByName(name)
    if not name then return nil end
    for id, m in pairs(self.db.mobs) do
        if m.name == name and type(id) == "number" then return m, id end
    end
    return nil
end

-- Merge a name-keyed placeholder (from kill lines before we ever looted one) into the real entry
local function MergePlaceholder(m, name)
    local key = "name:" .. (name or "")
    local ph = MD.db.mobs[key]
    if not ph or ph == m then return end
    m.kills = (m.kills or 0) + (ph.kills or 0)
    m.xp = (m.xp or 0) + (ph.xp or 0)
    m.deaths = (m.deaths or 0) + (ph.deaths or 0)
    m.killTime = (m.killTime or 0) + (ph.killTime or 0)
    m.killN = (m.killN or 0) + (ph.killN or 0)
    for id, d in pairs(ph.drops or {}) do
        m.drops[id] = m.drops[id] or { name = d.name, count = 0 }
        m.drops[id].count = m.drops[id].count + d.count
    end
    MD.db.mobs[key] = nil
end

local function Prune()
    local now = GetTime()
    for name, e in pairs(engaged) do
        if now - e.firstSeen > 600 then engaged[name] = nil end
    end
end

local function NoteUnit(unit)
    if not UnitExists(unit) or not UnitCanAttack("player", unit) or UnitIsPlayer(unit) or UnitIsDead(unit) then return end
    local guid = U.Str(UnitGUID(unit))
    local npcID = U.NpcIDFromGUID(guid)
    local name = U.Str(UnitName(unit))
    if not npcID or not name then return end
    local e = engaged[name]
    if not e or e.guid ~= guid then
        e = { guid = guid, npcID = npcID, firstSeen = GetTime() }
        engaged[name] = e
    end
    e.level = U.Num(UnitLevel(unit)) or e.level
    e.type = U.Str(UnitCreatureType(unit)) or e.type
    e.classification = U.Str(UnitClassification(unit)) or e.classification
    if unit == "target" then lastHostileName = name end
    local m = MD:Mob(npcID, name)
    MergePlaceholder(m, name)
    if e.level and e.level > 0 and (not m.level or e.level > m.level) then m.level = e.level end
    m.type = e.type or m.type
    m.classification = e.classification or m.classification
    m.zone = U.ZoneName()
end

-- XPTracker asks: what npcID/guid is the mob called `name` that just died?
function MD:ResolveEngaged(name)
    local e = engaged[name]
    if e then return e.npcID, e.guid end
    local _, id = self:ByName(name)
    return id, nil
end

MD.lastHostile = function() return lastHostileName end

-- ---------------------------------------------------------------------------
-- Message handlers
-- ---------------------------------------------------------------------------
MD.messages = {
    -- Combat-log fight record (Grinding.CombatStats): precise kill time and damage taken per kill
    FO_FIGHT = function(self, npcID, guid, dur, done, taken, name)
        if not npcID then return end
        local m = self:Mob(npcID, name)
        if dur and dur > 0.5 and dur < 120 then m.clTime = (m.clTime or 0) + dur m.clN = (m.clN or 0) + 1 end
        if taken and taken > 0 then m.taken = (m.taken or 0) + taken m.takenN = (m.takenN or 0) + 1 end
        if done then m.done = (m.done or 0) + done end
    end,
    FO_KILL = function(self, name, xp, npcID, guid, now)
        local e = engaged[name]
        local m
        if npcID then m = self:Mob(npcID, name) MergePlaceholder(m, name)
        else m = self:ByName(name) or self:Mob("name:" .. name, name) end
        m.kills = (m.kills or 0) + 1
        m.xp = (m.xp or 0) + (xp or 0)
        if e then
            -- only time kills that happened in combat; a stale target from minutes ago isn't a fight
            local started = combatStart and math.max(e.firstSeen, combatStart) or nil
            local dur = started and (now - started) or 0
            if dur > 0.5 and dur < 120 then
                m.killTime = (m.killTime or 0) + dur
                m.killN = (m.killN or 0) + 1
            end
            engaged[name] = nil
        end
        if lastKillAt then
            local gap = now - lastKillAt
            if gap > 0 and gap < 180 then
                m.gapTime = (m.gapTime or 0) + gap
                m.gapN = (m.gapN or 0) + 1
            end
        end
        lastKillAt = now
        local mapID, x, y = U.PlayerPosition()
        if mapID and x then
            m.spots = m.spots or {}
            U.Push(m.spots, { mapID, x, y }, MAX_SPOTS)
        end
        local zone = U.ZoneName()
        m.zone = zone
        -- raw observation, separate from the aggregates above
        local enc = { t = time(), npc = npcID or ("name:" .. name), name = name, lvl = (e and e.level) or m.level, plvl = FO.Player.level,
                      zone = zone, xp = xp or 0, mapID = mapID, x = x, y = y }
        if e then
            local started = combatStart and math.max(e.firstSeen, combatStart) or nil
            local dur = started and (now - started) or 0
            if dur > 0.5 and dur < 120 then enc.dur = math.floor(dur * 10) / 10 end
        end
        U.Push(self.db.encounters, enc, MAX_ENCOUNTERS)
        pending[#pending + 1] = { enc = enc, mob = m }
        local z = self.db.zones[zone]
        if not z then z = {} self.db.zones[zone] = z end
        local key = npcID or ("name:" .. name)
        z[key] = (z[key] or 0) + 1
    end,
    FO_LOOT_SOURCE = function(self, guid, npcID, npcName)
        if not npcID then return end
        local m = self:Mob(npcID, npcName)
        m.looted = (m.looted or 0) + 1
    end,
    FO_LOOT_ITEM = function(self, itemID, qty, value, src, npcID, npcName, guid, itemName)
        if not npcID then return end
        local m = self:Mob(npcID, npcName)
        local d = m.drops[itemID]
        if not d then d = { name = itemName, count = 0, n = 0 } m.drops[itemID] = d end
        d.count = d.count + (qty or 1)   -- units
        d.n = (d.n or 0) + 1             -- loots that contained it
    end,
    FO_DEATH = function(self)
        if not lastHostileName then return end
        local e = engaged[lastHostileName]
        local m = e and self:Mob(e.npcID, lastHostileName) or self:ByName(lastHostileName)
        if m then m.deaths = (m.deaths or 0) + 1 end
    end,
}

MD.events = {
    PLAYER_TARGET_CHANGED = function() NoteUnit("target"); Prune() end,
    UPDATE_MOUSEOVER_UNIT = function() NoteUnit("mouseover") end,
    PLAYER_REGEN_DISABLED = function() combatStart = GetTime(); NoteUnit("target") end,
    PLAYER_REGEN_ENABLED = function()
        combatStart = nil
        -- Health/mana are readable again out of combat: how much did that fight cost?
        if #pending > 0 then
            local hp, hpMax = U.Num(UnitHealth("player")), U.Num(UnitHealthMax("player"))
            local hpLoss = (hp and hpMax and hpMax > 0) and (1 - hp / hpMax) or nil
            local manaLoss
            if UnitPowerType and U.Num(UnitPowerType("player")) == 0 then
                local mp, mpMax = U.Num(UnitPower("player", 0)), U.Num(UnitPowerMax("player", 0))
                if mp and mpMax and mpMax > 0 then manaLoss = 1 - mp / mpMax end
            end
            local last = pending[#pending]
            last.enc.hpLoss = hpLoss and math.floor(hpLoss * 100) / 100 or nil
            last.enc.manaLoss = manaLoss and math.floor(manaLoss * 100) / 100 or nil
            last.enc.mobsInFight = #pending
            if hpLoss and #pending == 1 then
                local m = last.mob
                m.hpLoss = (m.hpLoss or 0) + hpLoss
                m.hpN = (m.hpN or 0) + 1
                if manaLoss then m.manaLoss = (m.manaLoss or 0) + manaLoss m.manaN = (m.manaN or 0) + 1 end
            end
        end
        pending = {}
    end,
}

-- ---------------------------------------------------------------------------
-- Derived metrics
-- ---------------------------------------------------------------------------
function MD:Metrics(id, m)
    local kills = m.kills or 0
    local xpk = kills > 0 and (m.xp or 0) / kills or 0
    local ttkChat = (m.killN or 0) > 0 and m.killTime / m.killN or nil
    local ttkCL = (m.clN or 0) >= 3 and m.clTime / m.clN or nil      -- combat-log timing wins once it has a few samples
    local ttk = ttkCL or ttkChat
    local gap = (m.gapN or 0) > 0 and m.gapTime / m.gapN or nil
    local looted = m.looted or 0
    local valuePerLoot, ahPart = 0, 0
    for itemID, d in pairs(m.drops or {}) do
        local v, src = U.ItemValue(itemID)
        local per = looted > 0 and (d.count / looted) * v or 0
        valuePerLoot = valuePerLoot + per
        if src == "ah" then ahPart = ahPart + per end
    end
    return {
        id = id, name = m.name or "?", level = m.level, type = m.type, class = m.classification, zone = m.zone,
        kills = kills, looted = looted, deaths = m.deaths or 0,
        xpk = xpk, ttk = ttk, gap = gap, xpPerSec = (ttk and ttk > 0) and xpk / ttk or nil,
        hpLoss = (m.hpN or 0) > 0 and m.hpLoss / m.hpN or nil, manaLoss = (m.manaN or 0) > 0 and m.manaLoss / m.manaN or nil,
        ttkCL = (m.clN or 0) > 0 and m.clTime / m.clN or nil, clN = m.clN or 0,
        dmgTaken = (m.takenN or 0) > 0 and m.taken / m.takenN or nil, dmgDone = (m.clN or 0) > 0 and (m.done or 0) / m.clN or nil,
        valuePerKill = valuePerLoot, vendorPerKill = valuePerLoot - ahPart, ahPerKill = ahPart,
    }
end

function MD:Rank(sortBy, limit, minKills, zone)
    local rows = {}
    for id, m in pairs(self.db.mobs) do
        if (m.kills or 0) >= (minKills or 1) and (not zone or m.zone == zone) then rows[#rows + 1] = self:Metrics(id, m) end
    end
    table.sort(rows, function(a, b)
        if sortBy == "gold" then return a.valuePerKill > b.valuePerKill end
        if sortBy == "xp" then return (a.xpPerSec or -1) > (b.xpPerSec or -1) end
        if sortBy == "safe" then return a.deaths / math.max(a.kills, 1) < b.deaths / math.max(b.kills, 1) end
        return a.kills > b.kills
    end)
    local out = {}
    for i = 1, math.min(limit or 10, #rows) do out[i] = rows[i] end
    return out
end

-- Kill-weighted averages for the mobs you kill in a zone: xp/kill, vendor/kill, ah/kill, nMobs
function MD:ZonePerKill(zone)
    local z = self.db.zones[zone]
    if not z then return nil end
    local tk, xp, vend, ah, n = 0, 0, 0, 0, 0
    for key, kills in pairs(z) do
        local m = self.db.mobs[key]
        if m and kills > 0 then
            local r = self:Metrics(key, m)
            tk = tk + kills
            xp = xp + r.xpk * kills
            vend = vend + r.vendorPerKill * kills
            ah = ah + r.ahPerKill * kills
            n = n + 1
        end
    end
    if tk == 0 then return nil end
    return xp / tk, vend / tk, ah / tk, n
end

-- Kill-weighted time-to-kill and gap-between-kills for a zone
function MD:ZoneKillTiming(zone)
    local z = self.db.zones[zone]
    if not z then return nil end
    local tN, tSum, gN, gSum = 0, 0, 0, 0
    for key in pairs(z) do
        local m = self.db.mobs[key]
        if m then
            tN, tSum = tN + (m.killN or 0), tSum + (m.killTime or 0)
            gN, gSum = gN + (m.gapN or 0), gSum + (m.gapTime or 0)
        end
    end
    local ttk = tN > 0 and tSum / tN or nil
    local gap = gN > 0 and gSum / gN or nil
    -- gap includes the kill itself; downtime between = gap - ttk
    local between = (ttk and gap and gap > ttk) and (gap - ttk) or nil
    return ttk, between
end

function MD:DropRates(npcID)
    local m = self.db.mobs[npcID]
    if not m then return nil end
    local denom = math.max(m.looted or 0, 1)
    local rows = {}
    for itemID, d in pairs(m.drops) do
        local v, src = U.ItemValue(itemID)
        local n = d.n or d.count
        rows[#rows + 1] = { itemID = itemID, name = d.name, count = d.count, n = n, rate = math.min(n / denom, 1), avgQty = d.count / math.max(n, 1), value = v, src = src }
    end
    table.sort(rows, function(a, b) return a.count * a.value > b.count * b.value end)
    return rows, denom
end

-- ---------------------------------------------------------------------------
-- Commands
-- ---------------------------------------------------------------------------
MD.commands = {
    mobs = { help = "[xp|gold|kills|safe] [here] — ranked mob table", fn = function(self, arg)
        local sortBy, where = U.SplitCmd(arg)
        local zone = where == "here" and (U.ZoneName()) or nil
        sortBy = (sortBy == "gold" or sortBy == "xp" or sortBy == "safe") and sortBy or "kills"
        local rows = self:Rank(sortBy, 12, 3, zone)
        if #rows == 0 then rows = self:Rank(sortBy, 12, 1, zone) end
        print("Mobs by %s%s:", sortBy, zone and (" in " .. zone) or "")
        for _, r in ipairs(rows) do
            print("  %-22s L%-3s k%-4d xp/k %-4.0f ttk %-5s xp/s %-4s %s/k dth %d [%s]",
                U.Trunc(r.name, 22), tostring(r.level or "?"), r.kills, r.xpk,
                r.ttk and string.format("%.0fs", r.ttk) or "--", r.xpPerSec and string.format("%.1f", r.xpPerSec) or "--",
                U.ShortMoney(r.valuePerKill), r.deaths, tostring(r.id))
        end
        if #rows == 0 then print("  nothing recorded yet.") end
    end },
    mob = { help = "<npcID|name> — drop rates and detail", fn = function(self, arg)
        local npc = tonumber(arg)
        local m = npc and self.db.mobs[npc]
        if not m then
            local found, id = self:ByName(arg)
            if found then m, npc = found, id else print("no data for '%s'", tostring(arg)) return end
        end
        local r = self:Metrics(npc, m)
        print("%s (npc %s) L%s %s %s, %s", r.name, tostring(npc), tostring(r.level or "?"), r.type or "", r.class or "", r.zone or "?")
        print("  kills %d looted %d deaths %d | xp/kill %.0f | kill %s, gap %s | value/kill %s (AH %s)",
            r.kills, r.looted, r.deaths, r.xpk, r.ttk and string.format("%.1fs", r.ttk) or "--",
            r.gap and string.format("%.1fs", r.gap) or "--", U.FormatMoney(r.valuePerKill), U.FormatMoney(r.ahPerKill))
        if r.ttkCL then print("  combat log: %.1fs per kill, %d damage dealt and %d taken per fight (%d fights)", r.ttkCL, r.dmgDone or 0, r.dmgTaken or 0, r.clN) end
        if r.hpLoss then print("  after a solo fight: %.0f%% health gone%s (%d samples)", r.hpLoss * 100, r.manaLoss and string.format(", %.0f%% mana", r.manaLoss * 100) or "", m.hpN or 0) end
        local rows = self:DropRates(npc)
        for i = 1, math.min(15, #(rows or {})) do
            local d = rows[i]
            print("  %5.1f%%  x%-4d (avg %.1f) %-26s %s%s", d.rate * 100, d.count, d.avgQty, U.Trunc(d.name or "?", 26), U.FormatMoney(d.value), d.src == "ah" and " (AH)" or "")
        end
        if m.spots and #m.spots > 0 then
            local s = m.spots[#m.spots]
            print("  last kill at %s (%.1f, %.1f); %d spots recorded", U.MapName(s[1]), s[2] * 100, s[3] * 100, #m.spots)
        end
    end },
}

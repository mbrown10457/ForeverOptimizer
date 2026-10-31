local ADDON, FO = ...
local U = FO.Util
local print = FO:Printer("Core")

-- ===========================================================================
-- Turns raw session / mob data into comparisons and estimates.
--   ZoneRows(window)   historical performance per zone near your level
--   ActivityRows()     xp/hr by activity (quest/grind/dungeon) near your level
--   Estimate()         the "unified efficiency" model for where you are now:
--                      kills/hr from kill time + gap, xp/hr, gold/hr net of repairs
--   Recommend()        adaptive leveling suggestion from all of the above
-- ===========================================================================
local A = FO:NewModule("Core.AnalyticsEngine", {
    account = "analytics",
    defaults = { objective = "balanced", weights = { xp = 1, gold = 0.5, safe = 0.5 } },
})
FO.Analytics = A

local PRESETS = {
    xp = { xp = 1, gold = 0, safe = 0 }, gold = { xp = 0, gold = 1, safe = 0 },
    safe = { xp = 0.5, gold = 0, safe = 1 }, balanced = { xp = 1, gold = 0.5, safe = 0.5 },
}

function A:Weights() return self.db.weights end

-- Sample-size confidence for a location row
local function Confidence(wall, kills)
    if wall >= 1800 and kills >= 50 then return "high" end
    if wall >= 600 and kills >= 15 then return "medium" end
    return "low"
end

local function LevelWindow(window)
    local lvl = FO.Player.level or 1
    window = window or 3
    return lvl - window, lvl + window
end

-- Collect archived sessions + the live one that fall in the level window
local function Sessions(window)
    local lo, hi = LevelWindow(window)
    local out = {}
    for _, s in ipairs(FO.Session.db.list) do
        if (s.level or 0) >= lo and (s.level or 0) <= hi then out[#out + 1] = s end
    end
    local live = FO.Session:Live()
    if live then
        out[#out + 1] = {
            live = true, level = live.level, zones = live.zones, time = live.time, xpBy = live.xpBy,
            xp = live.xp, kills = live.kills, gold = live.gold, ahEst = live.ahEst, deaths = live.deaths,
            repairs = live.repairs, deathTime = live.deathTime, elapsed = FO.Session:Elapsed(),
        }
    end
    return out
end

local function ProductiveTime(t) return (t.quest or 0) + (t.grind or 0) + (t.dungeon or 0) end
local function Downtime(t) return (t.travel or 0) + (t.rest or 0) + (t.town or 0) + (t.dead or 0) + (t.idle or 0) end

-- Per-zone rows: { zone, prod, down, xp, kills, gold, ahEst, deaths, xph, gph, egph, downPct, kph }
function A:ZoneRows(window)
    local acc = {}
    for _, s in ipairs(Sessions(window)) do
        for zone, z in pairs(s.zones or {}) do
            local r = acc[zone]
            if not r then r = { zone = zone, prod = 0, down = 0, xp = 0, kills = 0, gold = 0, ahEst = 0, deaths = 0, sessions = 0 } acc[zone] = r end
            r.prod = r.prod + ProductiveTime(z.time)
            r.down = r.down + Downtime(z.time)
            r.xp = r.xp + (z.xp or 0)
            r.kills = r.kills + (z.kills or 0)
            r.gold = r.gold + (z.gold or 0)
            r.ahEst = r.ahEst + (z.ahEst or 0)
            r.deaths = r.deaths + (z.deaths or 0)
            r.sessions = r.sessions + 1
        end
    end
    local rows = {}
    for _, r in pairs(acc) do
        local wall = r.prod + r.down
        if wall >= 120 then
            r.xph = U.PerHour(r.xp, wall, 120)
            r.xphProd = U.PerHour(r.xp, r.prod, 60)
            r.kph = U.PerHour(r.kills, wall, 120)
            r.gph = U.PerHour(r.gold, wall, 120)
            r.egph = U.PerHour(r.gold + r.ahEst, wall, 120)
            r.downPct = wall > 0 and r.down / wall * 100 or 0
            r.deathsPerHour = U.PerHour(r.deaths, wall, 120) or 0
            r.confidence = Confidence(wall, r.kills)
            rows[#rows + 1] = r
        end
    end
    -- objective score: each term normalized to the best row, weighted by the user's objective
    local w = self:Weights()
    local maxX, maxG, maxD = 0, 0, 0
    for _, r in ipairs(rows) do
        maxX = math.max(maxX, r.xph or 0) maxG = math.max(maxG, r.egph or 0) maxD = math.max(maxD, r.deathsPerHour or 0)
    end
    for _, r in ipairs(rows) do
        local sx = maxX > 0 and (r.xph or 0) / maxX or 0
        local sg = maxG > 0 and math.max(r.egph or 0, 0) / maxG or 0
        local ss = maxD > 0 and (1 - (r.deathsPerHour or 0) / maxD) or 1
        r.score = w.xp * sx + w.gold * sg + w.safe * ss
        if r.confidence == "low" then r.score = r.score * 0.8 end -- don't let a 3-minute sample win outright
    end
    table.sort(rows, function(a, b) return (a.score or 0) > (b.score or 0) end)
    return rows
end

-- xp/hr by activity near your level, across sessions
function A:ActivityRows(window)
    local acc = { quest = { t = 0, xp = 0 }, grind = { t = 0, xp = 0 }, dungeon = { t = 0, xp = 0 } }
    for _, s in ipairs(Sessions(window)) do
        for a, r in pairs(acc) do
            r.t = r.t + ((s.time or {})[a] or 0)
            r.xp = r.xp + ((s.xpBy or {})[a] or 0)
        end
    end
    for a, r in pairs(acc) do r.xph = U.PerHour(r.xp, r.t, 300) end
    return acc
end

-- Levels per hour: normalizes xp/hr across levels
function A:LevelsPerHour(xph)
    local xpMax = U.Num(UnitXPMax("player"))
    if not xph or not xpMax or xpMax == 0 then return nil end
    return xph / xpMax
end

-- ---------------------------------------------------------------------------
-- Unified efficiency estimate for the current spot.
-- Inputs: recent kill cadence (XPTracker), per-mob xp & value (MobDatabase),
-- repairs/hr & downtime share (session). Each piece says where it came from.
-- ---------------------------------------------------------------------------
function A:Estimate()
    local XT = FO:GetModule("Grinding.XPTracker")
    local MD = FO:GetModule("Grinding.MobDatabase")
    local st = FO.Session:Stats()
    if not st or not XT or not MD then return nil end
    local E = { notes = {} }

    -- kill cadence: measured from the last N kills if we have them
    local gap, n = XT:InterKillGap()
    local ttk, downBetween = MD:ZoneKillTiming(st.zone)
    if gap and n >= 5 then
        E.secPerKill = gap
        E.cadenceSource = string.format("measured over last %d kills", n)
    elseif ttk then
        E.secPerKill = ttk + (downBetween or 7)
        E.cadenceSource = "kill time + typical gap from mob database"
    else
        E.secPerKill = nil
    end
    E.killsPerHour = E.secPerKill and 3600 / E.secPerKill or nil
    E.ttk, E.gapBetween = ttk, downBetween

    -- per kill economics from mobs killed in this zone
    local xpk, vendk, ahk, mobs = MD:ZonePerKill(st.zone)
    E.xpPerKill, E.vendorPerKill, E.ahPerKill, E.mobsUsed = xpk, vendk, ahk, mobs

    -- expenses
    local hours = math.max(st.elapsed, 600) / 3600
    E.repairsPerHour = st.repairs / hours
    E.consumablesPerHour = st.consumables / hours

    if E.killsPerHour and xpk then
        E.xpPerHour = E.killsPerHour * xpk
        local coinPerKill = st.kills > 0 and st.lootGold / st.kills or 0
        E.coinPerKill = coinPerKill
        E.goldPerHourGross = E.killsPerHour * ((vendk or 0) + (ahk or 0) + coinPerKill)
        E.goldPerHourNet = E.goldPerHourGross - E.repairsPerHour - E.consumablesPerHour
        E.levelsPerHour = self:LevelsPerHour(E.xpPerHour)
    end
    -- productive share: how much of wall time is this cadence actually running
    E.productiveShare = st.elapsed > 0 and st.productive / st.elapsed or 1
    E.xpPerHourWall = E.xpPerHour and E.xpPerHour * E.productiveShare or nil
    return E
end

function A:BestZone(window)
    local rows = self:ZoneRows(window)
    return rows[1], rows
end

-- Adaptive recommendation: returns a list of strings
function A:Recommend()
    local lines = {}
    local st = FO.Session:Stats()
    if not st then return lines end
    local E = self:Estimate()
    local act = self:ActivityRows(3)
    local best, rows = self:BestZone(3)

    if E and E.xpPerHour then
        lines[#lines + 1] = string.format("Here (%s): ~%.0f kills/hr, %.0f xp/kill -> %.0f xp/hr fighting, %.0f xp/hr at your %.0f%% productive share.",
            st.zone, E.killsPerHour, E.xpPerKill, E.xpPerHour, E.xpPerHourWall or 0, E.productiveShare * 100)
        lines[#lines + 1] = string.format("  gold: %s/hr gross (%s vendor + %s AH + %s coin per kill), %s/hr net of repairs & consumables.",
            U.ShortMoney(E.goldPerHourGross), U.ShortMoney(E.vendorPerKill or 0), U.ShortMoney(E.ahPerKill or 0),
            U.ShortMoney(E.coinPerKill or 0), U.ShortMoney(E.goldPerHourNet))
        if E.levelsPerHour then lines[#lines + 1] = string.format("  that is %.2f levels/hr; time to level at this pace %s.", E.levelsPerHour, U.FormatDuration(3600 / E.levelsPerHour * (1 - (U.Num(UnitXP("player")) or 0) / math.max(U.Num(UnitXPMax("player")) or 1, 1)))) end
    else
        lines[#lines + 1] = "Not enough kills here yet for an estimate (need ~5 kills with timing)."
    end

    local bestAct, bestRate
    for a, r in pairs(act) do
        if r.xph and (not bestRate or r.xph > bestRate) then bestAct, bestRate = a, r.xph end
    end
    if bestAct then
        lines[#lines + 1] = string.format("Near L%d your best activity has been %s at %.0f xp/hr (quest %s / grind %s / dungeon %s).",
            FO.Player.level, bestAct, bestRate, U.Rate(act.quest.xph), U.Rate(act.grind.xph), U.Rate(act.dungeon.xph))
    end
    if best and best.zone ~= st.zone and best.xph and st.xph and best.score and best.xph > st.xph * 1.15 then
        lines[#lines + 1] = string.format("%s scored best for your '%s' objective at this level: %.0f xp/hr, %s eff gold/hr, %.0f%% downtime (%s confidence) vs %.0f xp/hr here.",
            best.zone, self.db.objective, best.xph, best.egph and U.ShortMoney(best.egph) or "--", best.downPct, best.confidence, st.xph)
    elseif best and best.zone == st.zone then
        lines[#lines + 1] = string.format("This is already your best recorded zone for this level (%d zones compared).", #rows)
    end
    if st.downtimePct > 35 then
        lines[#lines + 1] = string.format("Downtime is %.0f%% of wall time. /fo downtime to see where it goes.", st.downtimePct)
    end
    return lines
end

A.commands = {
    zones = { help = "[window] — zone comparison near your level, ranked by your objective", fn = function(self, arg)
        local window = math.min(math.max(tonumber(arg) or 3, 0), 10)
        local rows = self:ZoneRows(window)
        print("Zones within %d levels of %d, objective %s (score | xp/hr wall | fighting | k/hr | eff g/hr | down | deaths/hr | conf):",
              window, FO.Player.level, self.db.objective)
        for i = 1, math.min(12, #rows) do
            local r = rows[i]
            print("  %-20s %4.2f | %6s | %6s | %4s | %7s | %3.0f%% | %.1f | %s (%s)", U.Trunc(r.zone, 20), r.score or 0, U.Rate(r.xph), U.Rate(r.xphProd), U.Rate(r.kph),
                  r.egph and U.ShortMoney(r.egph) or "--", r.downPct, r.deathsPerHour or 0, r.confidence, U.FormatDuration(r.prod + r.down))
        end
        if #rows == 0 then print("  no zone data yet.") end
    end },
    objective = { help = "xp | gold | safe | balanced | custom <xp> <gold> <safe>", fn = function(self, arg)
        local sub, rest = U.SplitCmd(arg)
        if PRESETS[sub] then
            self.db.objective = sub
            self.db.weights = { xp = PRESETS[sub].xp, gold = PRESETS[sub].gold, safe = PRESETS[sub].safe }
        elseif sub == "custom" then
            local a, b, c = rest:match("^(%S+)%s+(%S+)%s+(%S+)$")
            a, b, c = tonumber(a), tonumber(b), tonumber(c)
            if not a then print("usage: /fo objective custom <xp> <gold> <safe>") return end
            self.db.objective = "custom"
            self.db.weights = { xp = a, gold = b, safe = c }
        elseif sub ~= "" then print("objectives: xp | gold | safe | balanced | custom <xp> <gold> <safe>") return end
        local w = self.db.weights
        print("objective %s: xp %.2f, gold %.2f, safety %.2f. Used by /fo zones and /fo recommend.", self.db.objective, w.xp, w.gold, w.safe)
    end },
    estimate = { help = "unified efficiency estimate for this spot", fn = function(self)
        local E = self:Estimate()
        if not E then print("no session.") return end
        if not E.secPerKill then print("no kill cadence yet. Kill a few things.") return end
        print("Estimate for %s:", FO.Session:Live().zone)
        print("  cadence %.1fs per kill (%s) -> %.0f kills/hr", E.secPerKill, E.cadenceSource, E.killsPerHour)
        if E.ttk then print("  avg kill %.1fs + gap %.1fs", E.ttk, E.gapBetween or 0) end
        print("  xp/kill %s (from %d mobs) -> %s xp/hr", U.Rate(E.xpPerKill), E.mobsUsed or 0, U.Rate(E.xpPerHour))
        print("  per kill: vendor %s, AH %s, coin %s", U.FormatMoney(E.vendorPerKill or 0), U.FormatMoney(E.ahPerKill or 0), U.FormatMoney(E.coinPerKill or 0))
        print("  gold/hr gross %s, repairs %s/hr, consumables %s/hr -> net %s/hr", U.FormatMoney(E.goldPerHourGross or 0),
              U.FormatMoney(E.repairsPerHour), U.FormatMoney(E.consumablesPerHour), U.FormatMoney(E.goldPerHourNet or 0))
    end },
    recommend = { help = "adaptive leveling recommendation", fn = function(self)
        for _, l in ipairs(self:Recommend()) do print("%s", l) end
    end },
}
